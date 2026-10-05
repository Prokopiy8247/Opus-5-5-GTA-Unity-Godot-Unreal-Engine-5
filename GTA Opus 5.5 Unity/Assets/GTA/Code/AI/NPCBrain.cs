using System;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    public enum NPCState { Idle, Walk, Flee, Panic, Combat, Cover, Dead, Chat, Sit, FleeVehicle }

    /// <summary>Pedestrian / driver / officer brains: navigation on the sidewalk graph, perception, reactions, combat.</summary>
    public class NPCBrain : MonoBehaviour
    {
        public NPCState state = NPCState.Walk;
        public Faction faction = Faction.Civilian;
        public bool armed, officer, tactical;
        Actor actor; CharacterController cc; CharacterRig rig; WeaponController weapons;
        public Vehicle vehicle;
        float vy, thinkTimer, stateTimer, shootTimer, panicRadius;
        Vector3 wanderTarget, lastKnownPlayerPos, coverPoint;
        public bool Alerted { get; private set; }
        public Actor target;
        float perceptionTimer;
        public float aggression = 0.3f, bravery = 0.5f;
        public static readonly List<NPCBrain> All = new List<NPCBrain>();
        public int simTier = 0; // 0 near, 1 medium, 2 far
        float simTimer;
        float speakCooldown;
        public Vector3 homePosition;
        public bool isDriverCiv;
        public string displayName = "Citizen";
        static readonly Collider[] percBuf = new Collider[48];

        void Awake()
        {
            actor = GetComponent<Actor>();
            cc = GetComponent<CharacterController>();
            rig = GetComponent<CharacterRig>();
            weapons = GetComponent<WeaponController>();
        }

        void OnEnable() { All.Add(this); WorldEvents.Noise += OnNoise; WorldEvents.Explosion += OnExplosion; }
        void OnDisable() { All.Remove(this); WorldEvents.Noise -= OnNoise; WorldEvents.Explosion -= OnExplosion; }

        /// <summary>Hearing: gunfire/explosions scare civilians and alert police; player footsteps help officers find a hidden suspect.</summary>
        void OnNoise(Vector3 p, float radius, GameObject src)
        {
            if (actor == null || actor.IsDead || src == gameObject) return;
            float d2 = (transform.position - p).sqrMagnitude;
            if (d2 > radius * radius) return;
            if (radius >= 30f) { OnGunfireHeard(p, radius); return; }
            var pc = PlayerController.I;
            if (officer && pc != null && src == pc.gameObject && WantedSystem.Level > 0)
            {
                lastKnownPlayerPos = p;
                var look = U.Flat(p - transform.position);
                if (vehicle == null && state != NPCState.Combat && look.sqrMagnitude > 0.01f) { Alerted = true; transform.rotation = Quaternion.LookRotation(look.normalized); }
            }
        }

        void OnExplosion(Vector3 p, float r) { OnGunfireHeard(p, Mathf.Max(r * 8f, 60f)); }

        void Start()
        {
            homePosition = transform.position;
            actor.Died += OnDied;
            if (armed && weapons != null && weapons.owned.Count <= 1)
                weapons.Give(faction == Faction.Police ? (tactical ? "rifle" : "pistol") : PickCivilianWeapon(), 120, true);
        }

        string PickCivilianWeapon()
        {
            float r = UnityEngine.Random.value;
            if (r < 0.5f) return "pistol";
            if (r < 0.8f) return "bat";
            return "knife";
        }

        void OnDied(Actor a, DamageInfo d)
        {
            state = NPCState.Dead; Alerted = false;
            HUD.RemoveBlip(this);
        }

        void Update()
        {
            if (actor.IsDead || GameManager.Paused) return;
            var pc = PlayerController.I;
            float distToPlayer = pc != null ? Vector3.Distance(transform.position, pc.transform.position) : 999f;
            simTier = distToPlayer < 45f ? 0 : distToPlayer < 110f ? 1 : 2;
            simTimer += Time.deltaTime;
            float dt = Time.deltaTime;
            if (simTier == 2 && simTimer < 0.35f) { return; }
            if (simTier == 1 && simTimer < 0.12f) { return; }
            simTimer = 0f;

            perceptionTimer -= dt;
            if (perceptionTimer <= 0f) { perceptionTimer = simTier == 0 ? 0.25f : 0.6f; Perceive(); }

            if (vehicle != null && actor.vehicle != vehicle)
            {
                // pulled out / ejected / vehicle cleaned up: resume walking AI
                vehicle = null;
                if (cc != null) cc.enabled = true;
            }
            if (vehicle != null) return;   // inside a vehicle the driving AI is in charge

            switch (state)
            {
                case NPCState.Walk: Walk(); break;
                case NPCState.Idle: Idle(); break;
                case NPCState.Flee: Flee(); break;
                case NPCState.Panic: Panic(); break;
                case NPCState.Combat: Combat(); break;
                case NPCState.Cover: Cover(); break;
                case NPCState.Chat: Chat(); break;
            }
            // weapon hold state
            if (rig != null) { rig.aiming = state == NPCState.Combat && armed; rig.pose = rig.pose == CharPose.Swimming ? CharPose.Swimming : CharPose.Normal; }
            if (speakCooldown > 0f) speakCooldown -= dt;
        }

        // ------------------------------------------------------------------ perception
        void Perceive()
        {
            var pc = PlayerController.I;
            if (pc == null) return;
            float d = Vector3.Distance(transform.position, pc.transform.position);
            bool seePlayer = false;
            // stealth (crouched, slow) shrinks how far and how wide NPCs notice the player
            float sightRange = pc.Stealth ? 22f : 60f;
            if (d < sightRange)
            {
                float fov = (officer ? 120f : 100f) * (pc.Stealth ? 0.7f : 1f);
                var to = pc.transform.position - transform.position;
                float ang = Vector3.Angle(transform.forward, to);
                if (ang < fov * 0.5f || d < 7f)
                {
                    var from = actor.HeadPos;
                    var toH = pc.actor.Center;
                    if (U.LineOfSight(from, toH, transform, pc.transform, Layers.Sight)) seePlayer = true;
                }
            }
            // the player is dangerous if recently violent nearby
            bool playerViolent = WantedSystem.Level > 0 && d < 45f;
            if (seePlayer && playerViolent && !officer)
            {
                if (UnityEngine.Random.value < 0.5f) SetState(NPCState.Flee);
                else SetState(NPCState.Panic);
                if (speakCooldown <= 0f) { speakCooldown = 3f; AudioFX.PlayAt("beep", transform.position, 0.2f, UnityEngine.Random.Range(0.7f, 1.4f), 25f); }
                return;
            }
            if (seePlayer && WantedSystem.Level > 0 && officer)
            {
                WantedSystem.Spotted(pc.transform.position);
                lastKnownPlayerPos = pc.transform.position;
                if (!Alerted) { Alerted = true; if (vehicle == null) SetState(NPCState.Combat); }
            }
            if (actor.lastAttacker != null && Time.time - actor.lastDamageTime < 6f && actor.lastAttacker == pc.gameObject)
            {
                if (officer || UnityEngine.Random.value < bravery) SetState(NPCState.Combat);
                else SetState(NPCState.Flee);
            }
        }

        // ------------------------------------------------------------------ movement helpers
        void MoveTo(Vector3 target, float speed, bool run)
        {
            var d = target - transform.position; d.y = 0f;
            if (rig != null) rig.velocity = d.normalized * speed;
            if (cc != null && cc.enabled)
            {
                if (cc.isGrounded) vy = -1.5f; else vy -= 20f * dt_();
                var motion = d.normalized * speed + Vector3.up * vy;
                if (d.magnitude > 0.6f) cc.Move(motion * dt_());
                else cc.Move(Vector3.up * vy * dt_());
                if (cc.isGrounded && vy < 0f) vy = -1.5f;
            }
            if (d.sqrMagnitude > 0.04f)
            {
                var look = Quaternion.LookRotation(d.normalized);
                transform.rotation = Quaternion.RotateTowards(transform.rotation, look, (run ? 600f : 320f) * dt_());
            }
        }

        float dt_() => Mathf.Min(Time.deltaTime, 0.1f) * (simTier == 2 ? 3f : simTier == 1 ? 1.8f : 1f);

        void SetState(NPCState s)
        {
            if (state == s) return;
            state = s; stateTimer = 0f;
            if (s == NPCState.Flee || s == NPCState.Panic)
            {
                if (vehicle != null) { /* drives away */ }
                else if (rig != null) rig.panic = 1f;
            }
            if (s == NPCState.Combat && rig != null) rig.panic = 0f;
        }

        // ------------------------------------------------------------------ states
        void Idle()
        {
            stateTimer -= Time.deltaTime;
            if (rig != null) { rig.velocity = Vector3.zero; }
            if (cc != null && cc.enabled && cc.isGrounded) cc.Move(Vector3.up * -1.5f * dt_());
            if (stateTimer <= 0f) SetState(NPCState.Walk);
        }

        void Walk()
        {
            if (wanderTarget == Vector3.zero || Vector3.Distance(transform.position, wanderTarget) < 1.6f || stateTimer > 30f)
            {
                stateTimer = 0f;
                if (UnityEngine.Random.value < 0.22f) { stateTimer = UnityEngine.Random.Range(2f, 6f); SetState(NPCState.Idle); return; }
                wanderTarget = PickSidewalkTarget();
            }
            stateTimer += Time.deltaTime;
            MoveTo(wanderTarget, UnityEngine.Random.value < 0.75f ? 1.35f : 1.7f, false);
            // cross the road at junctions
            var net = RoadNetwork.I;
            if (net != null && net.InJunction(transform.position, out _) && UnityEngine.Random.value < 0.02f)
                wanderTarget = transform.position + transform.forward * 10f;
        }

        Vector3 PickSidewalkTarget()
        {
            var net = RoadNetwork.I;
            if (net != null && net.lanes.Count > 0)
            {
                var lane = net.lanes[UnityEngine.Random.Range(0, net.lanes.Count)];
                var p = lane.Point(UnityEngine.Random.value);
                var side = Vector3.Cross(Vector3.up, lane.Dir);
                var pt = p + side * (lane.halfWidth + 2.6f);
                pt.y = transform.position.y;
                if (Vector3.Distance(pt, transform.position) < 70f) return pt;
            }
            var a = UnityEngine.Random.insideUnitCircle * 25f;
            return transform.position + new Vector3(a.x, 0f, a.y);
        }

        void Flee()
        {
            var threat = PlayerController.I != null && (WantedSystem.Level > 0 || actor.lastAttacker != null) ? PlayerController.I.transform : null;
            Vector3 dir;
            if (threat != null && Vector3.Distance(transform.position, threat.position) < 30f)
            {
                lastKnownPlayerPos = threat.position;
                dir = (transform.position - threat.position).normalized;
                if (Physics.Raycast(transform.position + Vector3.up, dir, 2.2f, Layers.World, QueryTriggerInteraction.Ignore))
                {
                    var r = new Vector3(-dir.z, 0f, dir.x);
                    dir = (UnityEngine.Random.value < 0.5f ? r : -r);
                }
            }
            else dir = transform.forward;
            var target = transform.position + dir * 8f;
            MoveTo(target, 4.6f, true);
            if (rig != null) rig.panic = 1f;
            stateTimer += Time.deltaTime;
            if (stateTimer > 8f) { SetState(NPCState.Walk); wanderTarget = PickSidewalkTarget(); }
            // fleeing to a car: steal the nearest parked car (only if really panicked)
            if (stateTimer > 3f && pedestrianStealChance > 0f && UnityEngine.Random.value < 0.0006f * pedestrianStealChance)
            {
                var v = Vehicle.Nearest(transform.position, 14f);
                if (v != null && v.Driver == null && v.kind == VehicleKind.Car) EnterVehicle(v);
            }
        }
        public float pedestrianStealChance = 0f;

        void Panic()
        {
            stateTimer += Time.deltaTime;
            if (rig != null) { rig.panic = 1f; rig.velocity = Vector3.zero; }
            if (rig != null) rig.PlayAction(UnityEngine.Random.value < 0.5f ? 1 : 2, 0.5f);
            if (UnityEngine.Random.value < 0.01f) transform.rotation = Quaternion.LookRotation(U.Flat(lastKnownPlayerPos - transform.position).normalized);
            if (stateTimer > 6f) SetState(NPCState.Flee);
            if (officer && stateTimer > 1f) SetState(NPCState.Combat);
        }

        void Combat()
        {
            var pc = PlayerController.I;
            target = actor.lastAttacker != null ? Actor.FromCollider(actor.lastAttacker.GetComponent<Collider>()) : null;
            if (target == null && pc != null) target = pc.actor;
            if (target == null) { SetState(NPCState.Walk); return; }
            var to = target.transform.position - transform.position; to.y = 0f;
            float d = to.magnitude;
            transform.rotation = Quaternion.RotateTowards(transform.rotation, Quaternion.LookRotation(to.normalized), 480f * Time.deltaTime);

            // low-level wanted + suspect not holding a gun: officers close in to make an arrest instead of shooting
            if (officer && target.IsPlayer && pc != null && WantedSystem.Level <= 2 && !target.InVehicle && !pc.IsAiming
                && (pc.weapons == null || pc.weapons.Current == null || pc.weapons.Current.IsMelee) && Time.time - actor.lastDamageTime > 4f)
            {
                if (d > 1.15f) MoveTo(target.transform.position, 4.4f, true);
                else if (rig != null) rig.velocity = Vector3.zero;
                if (rig != null) rig.aiming = d < 12f;
                return;
            }

            if (weapons != null && armed)
            {
                float ideal = tactical ? 12f : officer ? 8f : 6f;
                if (d > ideal * 1.35f) MoveTo(target.transform.position, officer ? 4.6f : 3.4f, true);
                else if (d < ideal * 0.55f) MoveTo(transform.position - to.normalized * 3f, 3.2f, false);
                else { if (rig != null) rig.velocity = Vector3.zero; if (cc != null && cc.isGrounded) cc.Move(Vector3.up * -1.5f * dt_()); }
                shootTimer -= Time.deltaTime;
                if (d < (tactical ? 45f : 30f) && shootTimer <= 0f && U.LineOfSight(actor.HeadPos, target.Center + Vector3.up * 0.2f, transform, target.transform, Layers.Sight))
                {
                    shootTimer = UnityEngine.Random.Range(0.25f, 0.7f) / Mathf.Max(aggression, 0.4f);
                    weapons.accuracyMul = tactical ? 0.85f : officer ? 1.15f : 1.8f;
                    weapons.Fire(target.Center + UnityEngine.Random.insideUnitSphere * 0.25f, 1.4f, true);
                    if (UnityEngine.Random.value < 0.2f) weapons.Reload();
                }
            }
            else
            {
                if (d > 1.9f) MoveTo(target.transform.position, 4.2f, true);
                else if (weapons != null) { weapons.Melee(false, to.normalized); }
            }
        }

        void Cover()
        {
            SetState(NPCState.Combat);
        }

        void Chat()
        {
            stateTimer -= Time.deltaTime;
            if (rig != null) rig.velocity = Vector3.zero;
            if (stateTimer <= 0f) SetState(NPCState.Walk);
        }

        public void OnGunfireHeard(Vector3 p, float radius)
        {
            if (actor.IsDead) return;
            float d = Vector3.Distance(transform.position, p);
            if (d > radius) return;
            if (officer && Alerted == false) { Alerted = true; lastKnownPlayerPos = p; }
            if (!officer && state != NPCState.Flee)
            {
                if (UnityEngine.Random.value < 0.7f) SetState(UnityEngine.Random.value < 0.5f ? NPCState.Flee : NPCState.Panic);
            }
            else if (officer && state == NPCState.Walk && d < radius * 0.6f) SetState(NPCState.Combat);
        }

        public void OnCarjacked(Actor by)
        {
            if (officer || (by != null && UnityEngine.Random.value < bravery * 0.6f)) { actor.lastAttacker = by != null ? by.gameObject : null; actor.lastDamageTime = Time.time; SetState(NPCState.Combat); }
            else SetState(NPCState.Flee);
        }

        public void OnHitByVehicle(Vehicle v)
        {
            var d = v.Driver;
            if (d != null && d.IsPlayer) { SetState(NPCState.Flee); }
            else SetState(NPCState.Panic);
        }

        /// <summary>Command the NPC to run to a position (used by police group AI and scripted reactions).</summary>
        public void GoTo(Vector3 p) { wanderTarget = p; if (state != NPCState.Combat && state != NPCState.Flee) SetState(NPCState.Walk); }

        public void Alert(Vector3 pos)
        {
            Alerted = true; lastKnownPlayerPos = pos;
            if (officer) SetState(NPCState.Combat);
            else SetState(NPCState.Flee);
        }

        public void EnterVehicle(Vehicle v, int seat = 0)
        {
            if (v == null) return;
            if (cc != null) cc.enabled = false;
            v.Occupy(actor, seat);
            vehicle = v;
            if (rig != null) rig.pose = seat == 0 ? CharPose.Driving : CharPose.Passenger;
        }

        public void ExitVehicle()
        {
            if (vehicle == null) return;
            var v = vehicle;
            var p = v.ExitPosition(actor.seat);
            v.Vacate(actor);
            transform.position = p;
            if (cc != null) cc.enabled = true;
            vehicle = null;
            SetState(UnityEngine.Random.value < 0.4f ? NPCState.Flee : NPCState.Combat);
        }

        public void ForceExitForCombat()
        {
            if (vehicle != null && (officer || UnityEngine.Random.value < bravery)) ExitVehicle();
        }
    }
}
