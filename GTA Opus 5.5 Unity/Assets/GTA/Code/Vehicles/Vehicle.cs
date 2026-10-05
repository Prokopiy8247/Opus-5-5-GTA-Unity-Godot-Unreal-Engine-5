using System;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    public struct VehicleInput
    {
        public float throttle, brake, steer, handbrake, pitch, roll, yaw, lift;
        public bool horn, boost;
    }

    [Serializable]
    public class Seat
    {
        public Transform anchor, door;
        [NonSerialized] public Actor occupant;
    }

    /// <summary>Shared vehicle framework: seats, occupancy, damage, lights, siren, horn, audio, mods. Physics lives in subclasses.</summary>
    [RequireComponent(typeof(Rigidbody))]
    public abstract class Vehicle : MonoBehaviour, IDamageable
    {
        public static readonly List<Vehicle> All = new List<Vehicle>();
        /// <summary>Impact deformation can be turned off from the admin menu (vertex edits cost CPU).</summary>
        public static bool DeformationEnabled = true;

        public string defId = "sedan";
        [NonSerialized] public VehicleDef def;
        public VehicleKind kind;
        public Seat[] seats;
        [NonSerialized] public VehicleInput input;
        [NonSerialized] public Rigidbody Rb;
        public float health = 1000f, maxHealth = 1000f;
        public bool IsDestroyed { get; protected set; }
        [NonSerialized] public bool engineOn, lightsOn, sirenOn, roofDown, playerOwned, isTraffic, persistent;
        [NonSerialized] public VehicleMods mods = new VehicleMods();
        [NonSerialized] public GameObject lastAttacker;
        [NonSerialized] public float lastPlayerContact = -99f;
        public bool Submerged { get; protected set; }
        public float Speed { get; protected set; }
        public float SpeedKmh => Mathf.Abs(Speed) * 3.6f;
        public Actor Driver => seats != null && seats.Length > 0 ? seats[0].occupant : null;
        public virtual float CameraDistance => Mathf.Max(5.2f, bounds.size.z * 1.35f);
        public virtual float CameraHeight => Mathf.Max(1.4f, bounds.size.y * 0.9f);
        public Bounds bounds;

        protected Transform model, steerWheel;
        protected Quaternion steerRest; protected Vector3 steerAxisLocal;
        [NonSerialized] public Transform steerL, steerR;
        protected readonly Dictionary<string, Material> mats = new Dictionary<string, Material>();
        protected Light headSpot, sirenLight;
        protected Renderer sirenR, sirenB;
        protected AudioSource engineSrc, sirenSrc, hornSrc, skidSrc;
        protected ParticleSystem smokeFx, fireFx;
        protected float burnTimer = -1f, sirenPhase, destroyedAt;
        protected Vector3 lastVel, lastAngVel;
        protected int headlightDamage;
        readonly List<MeshFilter> deformables = new List<MeshFilter>();
        readonly Dictionary<string, GameObject> modParts = new Dictionary<string, GameObject>();
        protected bool brakeLightsOn, reverseOn;

        protected virtual void Awake()
        {
            Rb = GetComponent<Rigidbody>();
            def = VehicleCatalog.Get(defId);
            if (def != null) { kind = def.kind; maxHealth = def.health; health = maxHealth; Rb.mass = def.mass; }
            Rb.interpolation = RigidbodyInterpolation.Interpolate;
            Rb.collisionDetectionMode = CollisionDetectionMode.ContinuousSpeculative;
            model = transform.childCount > 0 ? transform.GetChild(0) : transform;
            bounds = ComputeBounds();
            BuildSeats();
            BuildMaterials();
            foreach (var t in GetComponentsInChildren<Transform>(true))
            {
                var role = U.Role(t);
                if (role.StartsWith("MOD_")) { modParts[role] = t.gameObject; t.gameObject.SetActive(false); }
            }
            steerWheel = U.FindRole(transform, "STEER");
            if (steerWheel != null) SetupSteerTargets();
            var r = U.FindRole(transform, "SIREN_R"); if (r) sirenR = r.GetComponent<Renderer>();
            var bb = U.FindRole(transform, "SIREN_B"); if (bb) sirenB = bb.GetComponent<Renderer>();
            foreach (var t in GetComponentsInChildren<MeshFilter>())
                if (U.Role(t.transform) == "BODY" && t.sharedMesh != null && t.sharedMesh.isReadable) deformables.Add(t);
            SetupAudio();
            if (def != null && def.paints.Length > 0) mods.paint = def.paints[UnityEngine.Random.Range(0, def.paints.Length)];
            ApplyMods();
        }

        protected virtual void OnEnable() { All.Add(this); }
        protected virtual void OnDisable() { All.Remove(this); }

        Bounds ComputeBounds()
        {
            var rot = transform.rotation; transform.rotation = Quaternion.identity;
            var p = transform.position;
            Bounds b = new Bounds(Vector3.zero, Vector3.one);
            bool first = true;
            foreach (var r in GetComponentsInChildren<Renderer>())
            {
                if (r is ParticleSystemRenderer) continue;
                var rb = r.bounds; rb.center -= p;
                if (first) { b = rb; first = false; } else b.Encapsulate(rb);
            }
            transform.rotation = rot;
            return b;
        }

        void BuildSeats()
        {
            var anchors = U.FindRolePrefix(transform, "SEAT_");
            seats = new Seat[anchors.Count];
            for (int i = 0; i < anchors.Count; i++)
            {
                seats[i] = new Seat { anchor = anchors[i], door = U.FindRole(transform, "DOOR_" + U.Role(anchors[i]).Substring(5)) };
                if (seats[i].door == null) seats[i].door = anchors[i];
            }
            if (seats.Length == 0)
            {
                var a = new GameObject("Veh__SEAT_0").transform; a.SetParent(transform, false); a.localPosition = new Vector3(0, 0.6f, 0);
                seats = new[] { new Seat { anchor = a, door = a } };
            }
        }

        void BuildMaterials()
        {
            foreach (var r in GetComponentsInChildren<Renderer>(true))
            {
                if (r is ParticleSystemRenderer) continue;
                var sm = r.sharedMaterials;
                bool changed = false;
                for (int i = 0; i < sm.Length; i++)
                {
                    if (sm[i] == null) continue;
                    var n = sm[i].name.Replace(" (Instance)", "");
                    if (n == "M_Paint" || n == "M_Paint2" || n == "M_Glass" || n == "M_HeadLight" || n == "M_TailLight" || n == "M_ReverseLight" || n == "M_Rim" || n == "M_SirenRed" || n == "M_SirenBlue" || n == "M_TaxiSign")
                    {
                        if (!mats.TryGetValue(n, out var m)) { m = new Material(sm[i]) { name = n + "_veh" }; mats[n] = m; }
                        sm[i] = m; changed = true;
                    }
                }
                if (changed) r.sharedMaterials = sm;
            }
        }

        void SetupSteerTargets()
        {
            steerRest = steerWheel.localRotation;
            var mf = steerWheel.GetComponent<MeshFilter>();
            var ext = mf != null && mf.sharedMesh != null ? mf.sharedMesh.bounds.extents : Vector3.one;
            steerAxisLocal = ext.x < ext.y && ext.x < ext.z ? Vector3.right : (ext.y < ext.z ? Vector3.up : Vector3.forward);
            float rad = Mathf.Max(ext.x, Mathf.Max(ext.y, ext.z)) * 0.92f;
            bool bike = kind == VehicleKind.Bike || kind == VehicleKind.Bicycle;
            steerL = new GameObject("SteerL").transform; steerL.SetParent(steerWheel, false);
            steerR = new GameObject("SteerR").transform; steerR.SetParent(steerWheel, false);
            steerL.position = steerWheel.position - transform.right * rad + (bike ? Vector3.zero : transform.up * 0.04f);
            steerR.position = steerWheel.position + transform.right * rad + (bike ? Vector3.zero : transform.up * 0.04f);
        }

        void SetupAudio()
        {
            string eng = kind == VehicleKind.Heli ? "rotor" : kind == VehicleKind.Plane ? (def != null && def.id == "jet" ? "jet" : "prop") : kind == VehicleKind.Boat ? "boat" : kind == VehicleKind.Bike ? "engine_bike" : (def != null && def.heavy ? "engine_heavy" : "engine");
            if (kind != VehicleKind.Bicycle)
            {
                engineSrc = AudioFX.Attach(gameObject, eng, 0.0f, true, kind == VehicleKind.Heli || kind == VehicleKind.Plane ? 260f : 70f);
                engineSrc.Stop();
            }
            if (def != null && def.siren) { sirenSrc = AudioFX.Attach(gameObject, "siren", 0.8f, true, 160f); sirenSrc.Stop(); }
            hornSrc = AudioFX.Attach(gameObject, def != null && def.heavy ? "horn_truck" : "horn", 0.8f, true, 90f); hornSrc.Stop();
            if (kind == VehicleKind.Car || kind == VehicleKind.Bike) { skidSrc = AudioFX.Attach(gameObject, "skid", 0f, true, 60f); }
        }

        // ------------------------------------------------------------------ occupancy
        public static Vehicle Nearest(Vector3 p, float radius)
        {
            Vehicle best = null; float bd = radius;
            foreach (var v in All)
            {
                if (v.IsDestroyed) continue;
                var cp = v.ClosestPoint(p);
                float d = Vector3.Distance(cp, p);
                if (d < bd) { bd = d; best = v; }
            }
            return best;
        }

        public Vector3 ClosestPoint(Vector3 p)
        {
            var local = transform.InverseTransformPoint(p);
            var c = bounds.ClosestPoint(local);
            return transform.TransformPoint(c);
        }

        public int FreePassengerSeat()
        {
            for (int i = 1; i < seats.Length; i++) if (seats[i].occupant == null) return i;
            return -1;
        }

        public Vector3 SeatRootPosition(int i, CharacterRig rig)
        {
            float hh = rig != null && rig.valid ? rig.transform.InverseTransformPoint(rig.Hips.position).y : 0.95f;
            if (rig != null && rig.valid && rig.pose != CharPose.Normal) hh = 0.95f * (rig.transform.localScale.y);
            return seats[i].anchor.position - transform.up * hh;
        }

        public virtual void Occupy(Actor a, int i)
        {
            if (a.vehicle != null && a.vehicle != this) a.vehicle.Vacate(a);
            a.ClearKnockdown();   // a stale knockdown would later re-enable the occupant's colliders inside the vehicle
            seats[i].occupant = a;
            a.vehicle = this; a.seat = i;
            foreach (var c in a.GetComponents<Collider>()) c.enabled = false;
            var cc = a.GetComponent<CharacterController>(); if (cc) cc.enabled = false;
            a.transform.SetParent(transform, true);
            a.transform.position = SeatRootPosition(i, a.rig);
            a.transform.rotation = transform.rotation;
            if (a.rig != null)
            {
                bool bike = kind == VehicleKind.Bike || kind == VehicleKind.Bicycle;
                a.rig.pose = i == 0 ? (bike ? CharPose.Riding : CharPose.Driving) : CharPose.Passenger;
                a.rig.steerL = i == 0 ? steerL : null; a.rig.steerR = i == 0 ? steerR : null;
                a.rig.velocity = Vector3.zero;
                if (kind == VehicleKind.Bike || kind == VehicleKind.Heli || kind == VehicleKind.Plane || kind == VehicleKind.Boat || roofDown || kind == VehicleKind.Bicycle) { }
            }
            if (i == 0)
            {
                engineOn = true;   // bicycles: "engine" = pedalling allowed
                if (engineSrc && !engineSrc.isPlaying && kind != VehicleKind.Bicycle) engineSrc.Play();
                Wake();
                // a stolen traffic / police car must stop being steered by its AI
                if (a.IsPlayer) { var ai = GetComponent<VehicleAI>(); if (ai != null) Destroy(ai); isTraffic = false; }
            }
            if (a.IsPlayer) { playerOwned = playerOwned || false; persistent = true; RadioSystem.OnEnterVehicle(this); }
        }

        public virtual void Vacate(Actor a)
        {
            for (int i = 0; i < seats.Length; i++) if (seats[i].occupant == a) seats[i].occupant = null;
            if (a.vehicle == this) { a.vehicle = null; a.seat = -1; }
            a.transform.SetParent(null, true);
            a.transform.rotation = Quaternion.LookRotation(U.Flat(transform.forward).sqrMagnitude > 0.01f ? U.Flat(transform.forward) : Vector3.forward);
            if (a.rig != null) { a.rig.pose = CharPose.Normal; a.rig.steerL = null; a.rig.steerR = null; a.rig.aiming = false; }
            foreach (var c in a.GetComponents<Collider>()) if (!(c is CharacterController)) c.enabled = true;
            if (Driver == null) { input = new VehicleInput { brake = 0.3f, handbrake = 1f }; }
            if (a.IsPlayer) RadioSystem.OnExitVehicle();
        }

        public Vector3 ExitPosition(int seat)
        {
            var door = seats[seat].door != null ? seats[seat].door.position : transform.position + transform.right * 1.5f;
            if (kind == VehicleKind.Bike || kind == VehicleKind.Bicycle)
            {
                // two-wheelers: step off to the left (or right) instead of the seat anchor on top of the frame
                door = transform.position - transform.right * 0.95f;
                if (Physics.CheckCapsule(door + Vector3.up * 0.4f, door + Vector3.up * 1.6f, 0.3f, Layers.World, QueryTriggerInteraction.Ignore)) door = transform.position + transform.right * 0.95f;
                door.y = U.GroundHeight(door + Vector3.up * 1.5f, transform.position.y) + 0.05f;
                return door;
            }
            if (kind == VehicleKind.Heli || kind == VehicleKind.Plane || kind == VehicleKind.Boat)
            {
                if (Physics.Raycast(door + Vector3.up * 2f, Vector3.down, out var h, 6f, Layers.World, QueryTriggerInteraction.Ignore)) return h.point + Vector3.up * 0.05f;
                return door + Vector3.up * 0.2f;
            }
            if (Physics.CheckCapsule(door + Vector3.up * 0.4f, door + Vector3.up * 1.6f, 0.3f, Layers.World | (1 << Layers.Vehicle), QueryTriggerInteraction.Ignore))
            {
                var other = transform.position - (door - transform.position);
                if (!Physics.CheckCapsule(other + Vector3.up * 0.4f, other + Vector3.up * 1.6f, 0.3f, Layers.World, QueryTriggerInteraction.Ignore)) door = other;
                else door = transform.position + Vector3.up * (bounds.size.y + 0.2f);
            }
            float gy = U.GroundHeight(door + Vector3.up * 1.5f, door.y);
            return new Vector3(door.x, Mathf.Max(gy, door.y - 1f) + 0.05f, door.z);
        }

        public void EjectOccupant(Actor a, bool dead)
        {
            int s = a.seat;
            var p = s >= 0 ? ExitPosition(s) : transform.position + Vector3.up * 2f;
            Vacate(a);
            a.transform.position = p;
            if (!dead && a.GetComponent<CharacterController>() is CharacterController cc) cc.enabled = true;
        }

        /// <summary>The occupant is pulled out by the carjacker.</summary>
        public void Carjacked(Actor occ, Actor by)
        {
            int s = occ.seat;
            var door = s >= 0 && seats[s].door != null ? seats[s].door.position : transform.position;
            Vacate(occ);
            occ.transform.position = door + (door - transform.position).normalized * 0.4f;
            var away = (door - transform.position); away.y = 0f;
            occ.Knockdown(away.normalized * 40f + Vector3.up * 10f, occ.Center, 1.6f);
            var brain = occ.GetComponent<NPCBrain>();
            brain?.OnCarjacked(by);
        }

        public void ClearAllOccupants()
        {
            foreach (var s in seats) if (s.occupant != null) { var a = s.occupant; EjectOccupant(a, false); }
        }

        // ------------------------------------------------------------------ update
        protected virtual void FixedUpdate()
        {
            Speed = Vector3.Dot(Rb.linearVelocity, transform.forward);
            lastVel = Rb.linearVelocity; lastAngVel = Rb.angularVelocity;
            if (IsDestroyed) return;
            Submerged = transform.position.y + bounds.center.y < Water.Level - 0.4f && Water.IsWater(transform.position) && kind != VehicleKind.Boat;
            if (Submerged && kind != VehicleKind.Boat)
            {
                engineOn = false;
                Rb.linearDamping = 2.5f; Rb.angularDamping = 2.5f;
                Rb.AddForce(Vector3.up * Rb.mass * 6f);
            }
            if (Driver == null && kind == VehicleKind.Car) input = new VehicleInput { brake = 0.2f, handbrake = 1f };
        }

        float wakeCheck;

        protected virtual void Update()
        {
            float dt = Time.deltaTime;
            // parked (kinematic) cars near the player turn dynamic so they can be rammed and pushed
            wakeCheck -= dt;
            if (wakeCheck <= 0f)
            {
                wakeCheck = 0.4f + UnityEngine.Random.value * 0.2f;
                if (Rb != null && Rb.isKinematic && !IsDestroyed && !persistent && PlayerController.I != null
                    && (PlayerController.I.transform.position - transform.position).sqrMagnitude < 45f * 45f) Wake();
            }
            UpdateLights(dt);
            UpdateAudio(dt);
            UpdateSteeringWheel(dt);
            if (burnTimer >= 0f && !IsDestroyed)
            {
                burnTimer -= dt;
                health -= dt * 15f;
                if (burnTimer <= 0f) Explode();
            }
            if (hornSrc != null)
            {
                bool h = input.horn && !IsDestroyed && Driver != null;
                if (h && !hornSrc.isPlaying) { hornSrc.pitch = mods.horn == 1 ? 0.68f : mods.horn == 2 ? 1.38f : 1f; hornSrc.Play(); WorldEvents.EmitNoise(transform.position, 25f, gameObject); }
                if (!h && hornSrc.isPlaying) hornSrc.Stop();
            }
        }

        void UpdateSteeringWheel(float dt)
        {
            if (steerWheel == null) return;
            if (kind == VehicleKind.Bike || kind == VehicleKind.Bicycle)
                steerWheel.localRotation = steerRest * Quaternion.AngleAxis(input.steer * 25f, steerWheel.InverseTransformDirection(transform.up));
            else
                steerWheel.localRotation = steerRest * Quaternion.AngleAxis(-input.steer * 110f, steerAxisLocal);
        }

        protected virtual void UpdateLights(float dt)
        {
            bool night = GameTime.IsDark || Weather.Visibility < 0.6f;
            bool head = !IsDestroyed && (engineOn || Driver != null) && (lightsOn || (night && (Driver != null)));
            if (Driver != null && Driver.IsPlayer) head = !IsDestroyed && (lightsOn != night);
            if (headlightDamage >= 2) head = false;
            SetEmission("M_HeadLight", head ? 3.5f : 0.15f, mods.LightsColor);
            SetEmission("M_TailLight", head || brakeLightsOn ? (brakeLightsOn ? 4f : 1.4f) : 0.1f, null);
            SetEmission("M_ReverseLight", reverseOn ? 2.5f : 0f, null);
            if (mats.ContainsKey("M_TaxiSign")) SetEmission("M_TaxiSign", night ? 2.5f : 0.6f, null);
            bool wantSpot = head && LightBudget.Allow(this);
            if (wantSpot && headSpot == null) CreateHeadSpot();
            if (headSpot != null) headSpot.enabled = wantSpot;

            if (sirenOn && !IsDestroyed)
            {
                sirenPhase += dt * 3.2f;
                bool red = (sirenPhase % 1f) < 0.5f;
                SetEmission("M_SirenRed", red ? 6f : 0.2f, null);
                SetEmission("M_SirenBlue", red ? 0.2f : 6f, null);
                if (sirenLight == null) CreateSirenLight();
                sirenLight.enabled = LightBudget.AllowSiren(this);
                sirenLight.color = red ? new Color(1f, 0.15f, 0.15f) : new Color(0.2f, 0.35f, 1f);
                if (sirenSrc && !sirenSrc.isPlaying) sirenSrc.Play();
            }
            else
            {
                SetEmission("M_SirenRed", 0.3f, null); SetEmission("M_SirenBlue", 0.3f, null);
                if (sirenLight) sirenLight.enabled = false;
                if (sirenSrc && sirenSrc.isPlaying) sirenSrc.Stop();
            }
        }

        void CreateHeadSpot()
        {
            var a = U.FindRole(transform, "FX_HEAD_L");
            var g = new GameObject("HeadSpot"); g.transform.SetParent(transform, false);
            g.transform.position = a != null ? (a.position + (U.FindRole(transform, "FX_HEAD_R") ?? a).position) * 0.5f : transform.position + transform.forward * bounds.extents.z + Vector3.up * 0.7f;
            g.transform.rotation = transform.rotation * Quaternion.Euler(6f, 0f, 0f);
            headSpot = g.AddComponent<Light>(); headSpot.type = LightType.Spot; headSpot.range = 42f; headSpot.spotAngle = 70f; headSpot.innerSpotAngle = 35f; headSpot.intensity = 22f;
            headSpot.color = mods.LightsColor ?? new Color(1f, 0.95f, 0.85f); headSpot.shadows = LightShadows.None;
        }

        void CreateSirenLight()
        {
            var g = new GameObject("SirenLight"); g.transform.SetParent(transform, false);
            g.transform.localPosition = new Vector3(0f, bounds.max.y + 0.4f, bounds.center.z);
            sirenLight = g.AddComponent<Light>(); sirenLight.type = LightType.Point; sirenLight.range = 16f; sirenLight.intensity = 9f; sirenLight.shadows = LightShadows.None;
        }

        protected void SetEmission(string mat, float intensity, Color? overrideColor)
        {
            if (!mats.TryGetValue(mat, out var m)) return;
            var c = overrideColor ?? m.GetColor("_BaseColor");
            m.SetColor("_EmissionColor", c * intensity);
        }

        protected virtual void UpdateAudio(float dt)
        {
            if (engineSrc == null) return;
            if (!engineOn || IsDestroyed) { if (engineSrc.isPlaying) engineSrc.volume = Mathf.MoveTowards(engineSrc.volume, 0f, dt); if (engineSrc.volume <= 0.01f) engineSrc.Stop(); return; }
            if (!engineSrc.isPlaying) engineSrc.Play();
            float top = def != null ? def.topSpeed : 40f;
            float sp = Mathf.Abs(Speed) / top;
            float gears = 5f;
            float g = Mathf.Min(sp * gears, gears - 0.001f);
            float rpm = 0.25f + 0.75f * (g - Mathf.Floor(g)) * (0.6f + 0.4f * Mathf.Floor(g) / gears);
            if (sp < 0.02f) rpm = 0.2f + input.throttle * 0.5f;
            engineSrc.pitch = Mathf.Lerp(engineSrc.pitch, 0.6f + rpm * 1.5f + input.throttle * 0.15f, dt * 8f);
            engineSrc.volume = Mathf.Lerp(engineSrc.volume, (0.35f + 0.45f * Mathf.Max(input.throttle, sp)) * AudioFX.Sfx * AudioFX.Master, dt * 5f);
        }

        // ------------------------------------------------------------------ damage
        public float DamageFactor => Mathf.Lerp(0.55f, 1f, health / Mathf.Max(maxHealth, 1f));

        public void TakeDamage(DamageInfo d)
        {
            if (IsDestroyed) return;
            if (d.type == DamageType.Bullet) { BulletHit(d.point, d.direction, d.amount, d.attacker); return; }
            ApplyDamage(d.amount, d.attacker);
        }

        protected void ApplyDamage(float amount, GameObject attacker)
        {
            if (IsDestroyed) return;
            if (Driver != null && Driver.IsPlayer && Driver.invulnerable) amount *= 0.2f;
            amount *= mods.ArmorMul * (def != null && def.armored ? 0.35f : 1f);
            health -= amount;
            if (attacker != null) lastAttacker = attacker;
            float f = health / maxHealth;
            if (f < 0.4f && smokeFx == null) smokeFx = VFX.Loop("smoke", transform, new Vector3(0f, bounds.max.y * 0.7f, bounds.max.z * 0.6f));
            if (f < 0.15f && fireFx == null && kind != VehicleKind.Bicycle) { fireFx = VFX.Loop("fire", transform, new Vector3(0f, bounds.max.y * 0.6f, bounds.max.z * 0.55f)); burnTimer = 7f; AudioFX.Attach(fireFx.gameObject, "fire", 0.7f, true, 40f); }
            if (health <= 0f) Explode();
        }

        /// <summary>Parked cars are spawned kinematic for performance; they become real rigid bodies when touched.</summary>
        public void Wake()
        {
            if (Rb == null || IsDestroyed) return;
            if (Rb.isKinematic) { Rb.isKinematic = false; Rb.constraints = RigidbodyConstraints.None; }
            Rb.useGravity = true;
            Rb.WakeUp();
        }

        public void BulletHit(Vector3 point, Vector3 dir, float dmg, GameObject attacker)
        {
            if (IsDestroyed) return;
            Wake();
            lastAttacker = attacker;
            ApplyDamage(dmg * 0.9f, attacker);
            var local = transform.InverseTransformPoint(point);
            OnBulletLocal(local);
            if (local.y > bounds.center.y + bounds.extents.y * 0.3f && UnityEngine.Random.value < 0.4f) { AudioFX.PlayAt("glass", point, 0.4f, UnityEngine.Random.Range(0.9f, 1.3f)); VFX.Impact(point, -dir, Surface.Glass); }
            var drv = Driver;
            if (drv != null && !drv.IsPlayer && kind != VehicleKind.Heli && UnityEngine.Random.value < 0.18f && (point - drv.Center).magnitude < 0.9f)
                drv.TakeDamage(new DamageInfo { amount = dmg * 0.8f, type = DamageType.Bullet, point = point, direction = dir, attacker = attacker });
            if (attacker != null && attacker.GetComponent<PlayerController>() != null && def != null && def.police) WorldEvents.EmitCrime(CrimeType.AssaultCop, point, attacker);
        }

        protected virtual void OnBulletLocal(Vector3 local) { }

        public void ExplosionHit(Vector3 pos, float dmg, float radius, GameObject attacker)
        {
            Wake();
            if (!IsDestroyed) ApplyDamage(dmg * 1.6f, attacker);
            Rb.AddExplosionForce(Mathf.Clamp(dmg * 18f, 2000f, 30000f) * Mathf.Clamp(Rb.mass / 1400f, 0.5f, 3f), pos, radius * 1.6f, 1.5f, ForceMode.Impulse);
            Deform(transform.InverseTransformPoint(pos), (transform.position - pos).normalized, Mathf.Min(dmg * 0.002f, 0.25f));
        }

        public void Explode()
        {
            if (IsDestroyed) return;
            IsDestroyed = true; destroyedAt = Time.time;
            health = 0f; engineOn = false; sirenOn = false;
            foreach (var s in seats)
                if (s.occupant != null)
                {
                    var a = s.occupant; EjectOccupant(a, true);
                    a.TakeDamage(new DamageInfo { amount = 999f, type = DamageType.Explosion, point = transform.position, direction = Vector3.up, attacker = lastAttacker, force = 10f });
                }
            Explosion.Create(transform.position + Vector3.up * 0.6f, 7.5f, 180f, lastAttacker, true);
            Rb.AddForce(Vector3.up * Rb.mass * 6f + UnityEngine.Random.insideUnitSphere * Rb.mass * 2f, ForceMode.Impulse);
            Rb.AddTorque(UnityEngine.Random.insideUnitSphere * Rb.mass * 2f, ForceMode.Impulse);
            foreach (var m in mats.Values) { m.SetColor("_BaseColor", new Color(0.09f, 0.085f, 0.08f)); m.SetColor("_EmissionColor", Color.black); }
            if (fireFx == null) fireFx = VFX.Loop("fire", transform, new Vector3(0f, bounds.max.y * 0.5f, 0f));
            if (smokeFx == null) smokeFx = VFX.Loop("smoke", transform, new Vector3(0f, bounds.max.y, 0f));
            if (engineSrc) engineSrc.Stop();
            if (sirenSrc) sirenSrc.Stop();
            if (headSpot) headSpot.enabled = false;
            if (sirenLight) sirenLight.enabled = false;
            OnDestroyedVehicle();
            if (def != null && def.police && lastAttacker != null && lastAttacker.GetComponent<PlayerController>() != null) WorldEvents.EmitCrime(CrimeType.DestroyCopCar, transform.position, lastAttacker);
            Invoke(nameof(Extinguish), 25f);
        }

        void Extinguish() { if (fireFx) { fireFx.Stop(); Destroy(fireFx.gameObject, 3f); } }
        protected virtual void OnDestroyedVehicle() { }

        public virtual void Repair()
        {
            health = maxHealth; burnTimer = -1f; headlightDamage = 0;
            if (smokeFx) { Destroy(smokeFx.gameObject); smokeFx = null; }
            if (fireFx) { Destroy(fireFx.gameObject); fireFx = null; }
            foreach (var mf in deformables)
            {
                var src = mf.GetComponent<DeformState>();
                if (src != null) { mf.sharedMesh = src.original; Destroy(src); }
            }
            if (IsDestroyed) { IsDestroyed = false; }
            Rb.linearDamping = 0.02f; Rb.angularDamping = 0.05f;
            ApplyMods();
        }

        protected virtual void OnCollisionEnter(Collision c)
        {
            if (IsDestroyed) return;
            var other = c.collider;
            var actor = other.GetComponentInParent<Actor>();
            Vector3 rel = c.relativeVelocity;
            if (actor != null && !actor.InVehicle)
            {
                float sp = Vector3.Dot(lastVel, (actor.transform.position - transform.position).normalized);
                if (sp > 2.5f)
                {
                    Rb.linearVelocity = lastVel * 0.93f; Rb.angularVelocity = lastAngVel;
                    actor.TakeDamage(new DamageInfo { amount = sp * sp * 0.9f, type = DamageType.Vehicle, point = actor.Center, direction = (lastVel.normalized + Vector3.up * 0.35f), attacker = Driver != null ? Driver.gameObject : null, force = sp * 1.2f, heavy = true });
                    AudioFX.PlayAt("hit", actor.Center, 0.8f);
                    if (Driver != null && Driver.IsPlayer)
                        WorldEvents.EmitCrime(actor.faction == Faction.Police ? CrimeType.AssaultCop : CrimeType.VehicleHit, actor.transform.position, Driver.gameObject);
                    var brain = actor.GetComponent<NPCBrain>(); brain?.OnHitByVehicle(this);
                }
                return;
            }
            float dv = c.impulse.magnitude / Mathf.Max(Rb.mass, 1f);
            if (dv < 2.5f) { if (rel.magnitude > 3f) VFX.Sparks(c.GetContact(0).point, Vector3.up, 2); return; }
            var cp = c.GetContact(0);
            float dmg = (dv - 2.5f) * (kind == VehicleKind.Heli || kind == VehicleKind.Plane ? 95f : 45f);
            ApplyDamage(dmg, other.GetComponentInParent<Vehicle>()?.Driver?.gameObject);
            AudioFX.PlayAt("crash", cp.point, Mathf.Clamp01(dv / 12f), UnityEngine.Random.Range(0.85f, 1.1f));
            VFX.Sparks(cp.point, cp.normal, Mathf.Clamp((int)(dv * 3), 4, 30));
            Deform(transform.InverseTransformPoint(cp.point), transform.InverseTransformDirection(-cp.normal), Mathf.Min(dv * 0.018f, 0.2f));
            var lp = transform.InverseTransformPoint(cp.point);
            if (lp.z > bounds.max.z * 0.7f && dv > 7f) headlightDamage++;
            var otherV = other.GetComponentInParent<Vehicle>();
            if (otherV != null && Driver != null && Driver.IsPlayer)
            {
                otherV.lastPlayerContact = Time.time;
                if (otherV.def != null && otherV.def.police && dv > 4f) WorldEvents.EmitCrime(CrimeType.Ramming, cp.point, Driver.gameObject);
                otherV.GetComponent<VehicleAI>()?.OnRammed(this);
            }
            if (Driver != null && !Driver.IsPlayer) GetComponent<VehicleAI>()?.OnCrash(dv);
            if (Driver != null && Driver.IsPlayer) PlayerCamera.I?.AddShake(Mathf.Clamp01(dv / 15f));
            OnCrash(dv, cp);
        }

        protected virtual void OnCrash(float dv, ContactPoint cp) { }

        void Deform(Vector3 localPoint, Vector3 localDir, float amount)
        {
            if (!DeformationEnabled || amount < 0.01f) return;
            foreach (var mf in deformables)
            {
                var st = mf.GetComponent<DeformState>();
                if (st == null) { st = mf.gameObject.AddComponent<DeformState>(); st.original = mf.sharedMesh; mf.sharedMesh = Instantiate(mf.sharedMesh); st.verts = mf.sharedMesh.vertices; }
                var mesh = mf.sharedMesh;
                var lp = mf.transform.InverseTransformPoint(transform.TransformPoint(localPoint));
                var ld = mf.transform.InverseTransformDirection(transform.TransformDirection(localDir)).normalized;
                var v = st.verts;
                float r = 0.7f;
                for (int i = 0; i < v.Length; i++)
                {
                    float d = Vector3.Distance(v[i], lp);
                    if (d < r) v[i] += ld * amount * (1f - d / r) * (0.7f + 0.3f * Mathf.PerlinNoise(v[i].x * 7f, v[i].z * 7f));
                }
                mesh.vertices = v; mesh.RecalculateNormals(); mesh.RecalculateBounds();
            }
        }

        // ------------------------------------------------------------------ lights / siren / mods
        public void ToggleLights() { lightsOn = !lightsOn; AudioFX.Play("ui", 0.3f); }
        public void ToggleSiren() { sirenOn = !sirenOn; }
        public void SetBrakeLights(bool brake, bool reverse) { brakeLightsOn = brake; reverseOn = reverse; }
        public virtual void ToggleRoof() { }

        public void ApplyMods()
        {
            var m = mods;
            if (mats.TryGetValue("M_Paint", out var p))
            {
                p.SetColor("_BaseColor", U.Hex(m.paint));
                m.ApplyFinish(p);
            }
            if (mats.TryGetValue("M_Paint2", out var p2)) { p2.SetColor("_BaseColor", U.Hex(m.paint2)); m.ApplyFinish(p2); }
            if (mats.TryGetValue("M_Rim", out var rim)) rim.SetColor("_BaseColor", U.Hex(m.wheelColor));
            if (mats.TryGetValue("M_Glass", out var gl)) { var c = gl.GetColor("_BaseColor"); var tints = new[] { 0.55f, 0.72f, 0.86f, 0.95f }; c = Color.Lerp(new Color(0.13f, 0.2f, 0.25f), Color.black, m.tint * 0.3f); c.a = tints[Mathf.Clamp(m.tint, 0, 3)]; gl.SetColor("_BaseColor", c); }
            SetPart("MOD_Spoiler_1", m.spoiler == 1); SetPart("MOD_Spoiler_2", m.spoiler == 2);
            SetPart("MOD_Hood_1", m.hood); SetPart("MOD_Skirt_1", m.skirts); SetPart("MOD_BumperF_1", m.bumper);
            SetPart("MOD_Exhaust_1", m.exhaust); SetPart("MOD_Grille_1", m.grille); SetPart("MOD_Roof_1", m.roof);
            SetPart("MOD_Livery_1", m.livery);
            WheelKit.Apply(this, m.wheelType);
            if (headSpot) headSpot.color = m.LightsColor ?? new Color(1f, 0.95f, 0.85f);
            OnModsApplied();
        }

        protected virtual void OnModsApplied() { }

        void SetPart(string role, bool on) { if (modParts.TryGetValue(role, out var g)) g.SetActive(on); }
        public bool HasPart(string role) => modParts.ContainsKey(role);

        public IEnumerable<Transform> WheelVisuals()
        {
            foreach (var t in GetComponentsInChildren<Transform>(true)) if (U.Role(t).StartsWith("WHEEL_")) yield return t;
        }

        public virtual void ResetAfterDestroyedIfFar() { }
    }

    public class DeformState : MonoBehaviour { public Mesh original; public Vector3[] verts; }

    /// <summary>Limits the number of real-time vehicle spot/siren lights to the nearest vehicles.</summary>
    public static class LightBudget
    {
        static int frame = -1; static readonly HashSet<Vehicle> allowed = new HashSet<Vehicle>(); static readonly HashSet<Vehicle> sirens = new HashSet<Vehicle>();
        static readonly List<Vehicle> tmp = new List<Vehicle>();

        static void Refresh()
        {
            if (Time.frameCount / 15 == frame) return;
            frame = Time.frameCount / 15;
            allowed.Clear(); sirens.Clear();
            var cam = PlayerCamera.I != null ? PlayerCamera.I.transform.position : Vector3.zero;
            tmp.Clear(); tmp.AddRange(Vehicle.All);
            tmp.Sort((a, b) => (a.transform.position - cam).sqrMagnitude.CompareTo((b.transform.position - cam).sqrMagnitude));
            int n = 0, s = 0;
            foreach (var v in tmp)
            {
                if (n < 8) { allowed.Add(v); n++; }
                if (v.sirenOn && s < 4) { sirens.Add(v); s++; }
            }
        }

        public static bool Allow(Vehicle v) { Refresh(); return allowed.Contains(v); }
        public static bool AllowSiren(Vehicle v) { Refresh(); return sirens.Contains(v); }
    }
}
