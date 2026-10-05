using System.Collections;
using UnityEngine;
using UnityEngine.InputSystem;

namespace Halcyon
{
    public enum MoveState { Ground, Air, Swim, Ladder, Cover, Vault, Parachute, Freefall, Vehicle, Scripted, Down }

    /// <summary>Third-person on-foot controller: locomotion, traversal, swimming, cover, stealth, melee, vehicles, parachute.</summary>
    [DefaultExecutionOrder(-10)]
    public class PlayerController : MonoBehaviour
    {
        public static PlayerController I;
        [System.NonSerialized] public Actor actor;
        [System.NonSerialized] public CharacterRig rig;
        [System.NonSerialized] public WeaponController weapons;
        [System.NonSerialized] public CharacterController cc;
        public MoveState state = MoveState.Ground;

        Vector3 planar, vel;
        float vy, airTime, maxFallSpeed, stepT, coverExitT, meleeHoldT, dodgeT, lastGroundY;
        public bool Crouching { get; private set; }
        public bool Stealth => Crouching && state == MoveState.Ground;
        public float stamina = 1f, breath = 1f;
        public bool Underwater { get; private set; }
        public bool IsAiming { get; private set; }
        public bool DriveByAiming { get; private set; }
        public Vector3 AimPoint { get; private set; }
        public float NoiseLevel { get; private set; }
        Vector3 coverNormal, coverPoint; bool coverLow, coverEdgeL, coverEdgeR; float coverPeek;
        Ladder ladder; float ladderT;
        bool busy;
        float parachuteDeployT;
        public float AltitudeAboveGround { get; private set; }
        public bool InWaterSurface => state == MoveState.Swim && !Underwater;

        void Awake()
        {
            I = this;
            actor = GetComponent<Actor>();
            rig = GetComponent<CharacterRig>();
            weapons = GetComponent<WeaponController>();
            cc = GetComponent<CharacterController>();
            actor.RagdollChanged += OnRagdoll;
        }

        void OnRagdoll(bool on)
        {
            // a late get-up callback must not pull the player out of the vehicle state (cc on while parented = stuck vehicle)
            if (actor.InVehicle) return;
            if (on) { state = MoveState.Down; cc.enabled = false; }
            else if (!actor.IsDead) { cc.enabled = true; state = MoveState.Ground; vy = 0f; planar = Vector3.zero; }
        }

        float CamYaw => PlayerCamera.I != null ? PlayerCamera.I.yaw : transform.eulerAngles.y;

        /// <summary>Changing clothes recently helps a little when police search for you.</summary>
        public bool HasChangedAppearanceRecently => PlayerState.I != null && Time.time - PlayerState.I.appearanceChangedAt < 12f;

        void Update()
        {
            if (actor.IsDead || GameManager.Paused) return;
            float dt = Time.deltaTime;
            var ps = PlayerState.I;
            UpdateAimPoint();

            if (GameInput.Down(Key.V)) PlayerCamera.I.CycleView();

            switch (state)
            {
                case MoveState.Ground: case MoveState.Air: GroundUpdate(dt); break;
                case MoveState.Swim: SwimUpdate(dt); break;
                case MoveState.Ladder: LadderUpdate(dt); break;
                case MoveState.Cover: CoverUpdate(dt); break;
                case MoveState.Freefall: case MoveState.Parachute: SkyUpdate(dt); break;
                case MoveState.Vehicle: VehicleUpdate(dt); break;
                case MoveState.Down: rig.velocity = Vector3.zero; break;
            }

            // breath & drowning
            if (Underwater)
            {
                breath -= dt / ps.LungSeconds;
                ps.Train(Skill.Lung, dt * 0.004f);
                if (breath <= 0f) { breath = 0f; actor.TakeDamage(DamageInfo.Make(9f * dt, DamageType.Drown, transform.position, Vector3.down, null)); }
            }
            else breath = Mathf.Min(1f, breath + dt * 0.35f);

            if (state != MoveState.Vehicle && state != MoveState.Down)
            {
                rig.aimDir = (AimPoint - rig.Chest.position).normalized;
                rig.aiming = IsAiming;
            }
        }

        // ------------------------------------------------------------ aiming / weapons
        void UpdateAimPoint()
        {
            var cam = PlayerCamera.I;
            if (cam == null) return;
            var o = cam.AimOrigin; var f = cam.AimForward;
            var hits = Physics.RaycastAll(o, f, 600f, Layers.Shootable, QueryTriggerInteraction.Ignore);
            float best = 600f; Vector3 p = o + f * 600f;
            foreach (var h in hits)
            {
                if (h.collider.transform.IsChildOf(transform)) continue;
                if (actor.InVehicle && h.collider.transform.IsChildOf(actor.vehicle.transform)) continue;
                if (h.distance < best && Vector3.Dot(h.point - transform.position, f) > 0.5f) { best = h.distance; p = h.point; }
            }
            AimPoint = p;
        }

        void HandleWeapons(float dt, bool allowFire, bool inCover)
        {
            if (weapons == null) return;
            var w = weapons.Current;
            // selection
            for (int i = 0; i < 9; i++) if (GameInput.Down(Key.Digit1 + i)) weapons.SelectSlot(i);
            float sc = GameInput.Scroll;
            if (!IsAiming && Mathf.Abs(sc) > 0.1f && !WeaponWheel.Open) weapons.Cycle(sc > 0 ? -1 : 1);
            if (IsAiming && w != null && w.sniperScope && Mathf.Abs(sc) > 0.1f) weapons.ScopeZoom = Mathf.Clamp(weapons.ScopeZoom - sc * 0.08f, 0.35f, 1f);
            if (GameInput.ReloadDown) weapons.Reload();
            w = weapons.Current;

            bool aimHeld = GameInput.Aim && !WeaponWheel.Open;
            bool melee = w == null || w.IsMelee;
            IsAiming = aimHeld && !melee && allowFire;
            rig.blocking = aimHeld && melee && state == MoveState.Ground;
            if (!allowFire) return;

            if (melee)
            {
                if (GameInput.FireDown) meleeHoldT = 0.0001f;
                if (meleeHoldT > 0f) meleeHoldT += dt;
                bool release = GameInput.FireUp || meleeHoldT > 0.45f;
                if (meleeHoldT > 0f && release)
                {
                    bool heavy = meleeHoldT > 0.3f || planar.magnitude > 5.5f;
                    meleeHoldT = 0f;
                    if (Stealth && TryTakedown()) return;
                    weapons.Melee(heavy, transform.forward);
                    PlayerState.I.Train(Skill.Strength, 0.004f);
                }
                return;
            }

            if (w.cls == WeaponClass.Thrown)
            {
                if (GameInput.FireDown) weapons.Throw(AimPoint);
                return;
            }

            bool fire = w.auto ? GameInput.Fire : GameInput.FireDown;
            if (fire)
            {
                float spreadMul = IsAiming ? 1f : 2.2f;
                if (inCover && !IsAiming) spreadMul = 4.5f; // blind fire
                if (Crouching) spreadMul *= 0.8f;
                spreadMul *= Mathf.Lerp(1.15f, 0.75f, PlayerState.I.Get(Skill.Shooting));
                weapons.Fire(AimPoint, spreadMul, IsAiming || inCover);
            }
        }

        bool TryTakedown()
        {
            foreach (var a in Actor.All)
            {
                if (a == actor || a.IsDead || a.InVehicle || a.faction == Faction.Animal) continue;
                var d = a.transform.position - transform.position;
                if (d.magnitude > 1.7f || Vector3.Dot(transform.forward, d.normalized) < 0.5f) continue;
                if (Vector3.Dot(a.transform.forward, d.normalized) < 0.3f) continue; // must be behind the target
                var ai = a.GetComponent<NPCBrain>();
                if (ai != null && ai.Alerted) continue;
                rig.PlayAction(6, 0.7f);
                a.TakeDamage(new DamageInfo { amount = 999f, type = DamageType.Melee, point = a.Center, direction = d.normalized, attacker = gameObject, force = 2f });
                PlayerState.I.Train(Skill.Stealth, 0.03f);
                HUD.Notify("Stealth takedown");
                if (a.faction == Faction.Police) WorldEvents.EmitCrime(CrimeType.KillCop, transform.position, gameObject);
                else WorldEvents.EmitCrime(CrimeType.Murder, transform.position, gameObject);
                return true;
            }
            return false;
        }

        // ------------------------------------------------------------ ground
        void GroundUpdate(float dt)
        {
            var ps = PlayerState.I;
            var input = GameInput.Move;
            bool aimHeld = GameInput.Aim;
            if (GameInput.CrouchDown) Crouching = !Crouching;

            var camRot = Quaternion.Euler(0f, CamYaw, 0f);
            var wish = camRot * new Vector3(input.x, 0f, input.y);
            bool sprint = GameInput.Sprint && input.y > 0.1f && stamina > 0.05f && !IsAiming;
            if (sprint) Crouching = false;
            bool walk = GameInput.Held(Key.LeftAlt);
            float speed = 4.3f;
            if (walk) speed = 1.9f;
            if (sprint) speed = Mathf.Lerp(6.8f, 7.6f, ps.Get(Skill.Stamina));
            if (Crouching) speed = Mathf.Lerp(1.8f, 2.4f, ps.Get(Skill.Stealth));
            if (IsAiming) speed = Crouching ? 1.6f : 2.5f;
            if (rig.ActionActive && weapons.Current != null && weapons.Current.IsMelee) speed *= 0.4f;

            if (sprint) { stamina -= dt * Mathf.Lerp(0.16f, 0.06f, ps.Get(Skill.Stamina)); ps.Train(Skill.Stamina, dt * 0.0025f); }
            else stamina = Mathf.Min(1f, stamina + dt * 0.18f);
            if (Stealth && planar.sqrMagnitude > 0.5f) ps.Train(Skill.Stealth, dt * 0.0015f);

            bool grounded = cc.isGrounded;
            float accel = grounded ? 28f : 6f;
            planar = Vector3.MoveTowards(planar, wish * speed, accel * dt);

            // dodge roll while aiming
            if (dodgeT > 0f) { dodgeT -= dt; }
            if ((IsAiming || rig.blocking) && GameInput.JumpDown && grounded && input.sqrMagnitude > 0.1f && dodgeT <= 0f)
            {
                planar = wish.normalized * 7.5f; dodgeT = 0.45f; rig.PlayAction(7, 0.35f);
            }
            else if (GameInput.JumpDown && grounded && !busy)
            {
                if (!TryVault()) { vy = 6.0f; grounded = false; }
            }

            if (grounded && vy < 0f)
            {
                if (airTime > 0.25f) Land(maxFallSpeed);
                vy = -2f; airTime = 0f; maxFallSpeed = 0f; lastGroundY = transform.position.y;
            }
            else
            {
                vy -= 22f * dt;
                airTime += dt;
                maxFallSpeed = Mathf.Max(maxFallSpeed, -vy);
            }
            state = grounded ? MoveState.Ground : MoveState.Air;

            var motion = planar + Vector3.up * vy;
            cc.Move(motion * dt);

            // facing
            Vector3 face = IsAiming || rig.blocking ? camRot * Vector3.forward : (planar.sqrMagnitude > 0.2f ? planar : transform.forward);
            if (rig.ActionActive && !IsAiming) face = transform.forward;
            face.y = 0f;
            if (face.sqrMagnitude > 0.001f) transform.rotation = Quaternion.RotateTowards(transform.rotation, Quaternion.LookRotation(face), (IsAiming ? 900f : 620f) * dt);

            rig.velocity = cc.velocity;
            rig.grounded = grounded || airTime < 0.12f;
            rig.verticalSpeed = vy;
            rig.crouch = Crouching;
            rig.pose = CharPose.Normal;

            // footsteps / noise
            float hs = new Vector2(cc.velocity.x, cc.velocity.z).magnitude;
            if (grounded && hs > 0.5f)
            {
                stepT += dt * hs / 1.25f;
                if (stepT >= 1f)
                {
                    stepT = 0f;
                    float radius = sprint ? 16f : (walk ? 5f : 9f);
                    if (Crouching) radius = Mathf.Lerp(2.5f, 1.2f, ps.Get(Skill.Stealth));
                    NoiseLevel = radius;
                    WorldEvents.EmitNoise(transform.position, radius, gameObject);
                    AudioFX.PlayAt("step", transform.position, Crouching ? 0.15f : 0.35f, Random.Range(0.9f, 1.1f));
                }
            }
            else NoiseLevel = 0f;

            // altitude & falling into freefall
            AltitudeAboveGround = Physics.Raycast(transform.position + Vector3.up * 0.2f, Vector3.down, out var gh, 400f, Layers.Ground, QueryTriggerInteraction.Ignore) ? gh.distance : 400f;
            if (!grounded && vy < -12f && AltitudeAboveGround > 22f && ps.hasParachute) EnterFreefall();

            // water
            if (transform.position.y < Water.Level - 1.15f && Water.IsWater(transform.position)) EnterSwim();

            HandleWeapons(dt, !busy, false);
            if (!busy)
            {
                if (GameInput.EnterVehicleDown) TryEnterVehicle(false);
                else if (GameInput.Down(Key.G)) TryEnterVehicle(true);
                else if (GameInput.CoverDown) TryEnterCover();
                else if (GameInput.InteractDown) TryInteract();
            }
        }

        void Land(float speed)
        {
            if (speed > 24f) { actor.TakeDamage(DamageInfo.Make(999f, DamageType.Fall, transform.position, Vector3.down, null)); return; }
            if (speed > 11f)
            {
                actor.TakeDamage(DamageInfo.Make((speed - 11f) * 8f, DamageType.Fall, transform.position, Vector3.down, null));
                if (speed > 16f) actor.Knockdown(Vector3.down * 20f + transform.forward * 30f, transform.position + Vector3.up, 1.6f);
                PlayerCamera.I.AddShake(0.4f);
            }
        }

        bool TryVault()
        {
            var fwd = transform.forward;
            var feet = transform.position;
            if (!Physics.Raycast(feet + Vector3.up * 0.45f, fwd, out var low, 1.0f, Layers.World, QueryTriggerInteraction.Ignore)) return false;
            if (Physics.Raycast(feet + Vector3.up * 2.2f, fwd, 1.3f, Layers.World, QueryTriggerInteraction.Ignore)) return false; // too tall
            var topProbe = low.point + fwd * 0.25f + Vector3.up * 2.3f;
            if (!Physics.Raycast(topProbe, Vector3.down, out var top, 2.3f, Layers.World, QueryTriggerInteraction.Ignore)) return false;
            float h = top.point.y - feet.y;
            if (h < 0.35f || h > 2.0f) return false;
            // vault over thin obstacles, mantle onto thick ones
            Vector3 landing;
            var beyond = low.point + fwd * 1.2f + Vector3.up * 2.3f;
            if (Physics.Raycast(beyond, Vector3.down, out var far, 4.5f, Layers.World, QueryTriggerInteraction.Ignore) && far.point.y < top.point.y - 0.3f && h < 1.3f)
                landing = far.point;
            else landing = top.point + fwd * 0.35f;
            StartCoroutine(VaultRoutine(top.point, landing, h));
            return true;
        }

        IEnumerator VaultRoutine(Vector3 top, Vector3 landing, float h)
        {
            busy = true; state = MoveState.Vault; cc.enabled = false;
            Vector3 p0 = transform.position;
            float dur = 0.35f + h * 0.22f;
            rig.PlayAction(6, dur);
            for (float t = 0f; t < 1f; t += Time.deltaTime / dur)
            {
                float k = Mathf.SmoothStep(0f, 1f, t);
                var a = Vector3.Lerp(p0, top + Vector3.up * 0.1f, Mathf.Clamp01(k * 1.6f));
                var p = Vector3.Lerp(a, landing, Mathf.Clamp01(k * 1.6f - 0.6f));
                transform.position = p;
                rig.velocity = transform.forward * 3f;
                yield return null;
            }
            transform.position = landing + Vector3.up * 0.05f;
            cc.enabled = true; busy = false; state = MoveState.Ground; vy = 0f; airTime = 0f;
            planar = transform.forward * 2.5f;
        }

        // ------------------------------------------------------------ swimming / diving
        void EnterSwim()
        {
            state = MoveState.Swim; Crouching = false; vy = 0f;
            AudioFX.PlayAt("splash", transform.position, 0.7f);
            VFX.Splash(new Vector3(transform.position.x, Water.Level, transform.position.z), 1f);
            weapons?.Holster(true);
        }

        void SwimUpdate(float dt)
        {
            var ps = PlayerState.I;
            var input = GameInput.Move;
            var camRot = Quaternion.Euler(0f, CamYaw, 0f);
            float surfaceY = Water.Level - 1.32f;
            bool diveDown = GameInput.Held(Key.LeftCtrl) || GameInput.Held(Key.C);
            bool up = GameInput.JumpHeld;
            bool sprint = GameInput.Sprint && stamina > 0.05f;
            float speed = sprint ? Mathf.Lerp(3.0f, 3.8f, ps.Get(Skill.Stamina)) : 2.1f;
            if (ps.hasScuba && Underwater) speed *= 1.25f;
            var pitchRot = Quaternion.Euler(Underwater ? Mathf.Clamp(PlayerCamera.I.pitch, -60f, 60f) : 0f, CamYaw, 0f);
            var wish = (Underwater ? pitchRot : camRot) * new Vector3(input.x, 0f, input.y) * speed;
            if (diveDown) wish += Vector3.down * 2.2f;
            if (up) wish += Vector3.up * 2.4f;
            if (sprint && input.sqrMagnitude > 0.1f) { stamina -= dt * 0.1f; ps.Train(Skill.Stamina, dt * 0.002f); }
            else stamina = Mathf.Min(1f, stamina + dt * 0.12f);

            vel = Vector3.MoveTowards(vel, wish, 6f * dt);
            var p = transform.position;
            if (!Underwater && !diveDown && p.y >= surfaceY - 0.15f) { vel.y = Mathf.Min(vel.y, 0f); p.y = Mathf.Lerp(p.y, surfaceY, dt * 5f); transform.position = p; }
            if (Underwater && p.y > surfaceY && !diveDown) vel.y = Mathf.Min(vel.y, 0.5f);
            cc.Move(vel * dt);
            p = transform.position;
            if (p.y > surfaceY + 0.02f && !cc.isGrounded) { p.y = surfaceY; transform.position = p; }
            Underwater = transform.position.y < surfaceY - 0.6f;

            var face = Vector3.ProjectOnPlane(vel, Vector3.up);
            if (face.sqrMagnitude > 0.05f) transform.rotation = Quaternion.RotateTowards(transform.rotation, Quaternion.LookRotation(face), 360f * dt);
            rig.pose = CharPose.Swimming;
            rig.velocity = vel;
            rig.swimPitch = Underwater ? Mathf.Clamp(-Mathf.Atan2(vel.y, Mathf.Max(face.magnitude, 0.1f)) * Mathf.Rad2Deg, -60f, 60f) : 0f;
            IsAiming = false;

            // leave the water when the sea floor is close (shallows / beach)
            if (!Underwater && Physics.Raycast(transform.position + Vector3.up, Vector3.down, out var g, 2.3f, Layers.World, QueryTriggerInteraction.Ignore) && g.point.y > Water.Level - 1.25f)
            {
                state = MoveState.Ground; Underwater = false; vy = 0f; planar = vel; vel = Vector3.zero;
                weapons?.Holster(false);
            }
            if (GameInput.InteractDown) TryInteract();
            if (GameInput.EnterVehicleDown) TryEnterVehicle(false);
        }

        // ------------------------------------------------------------ ladders
        public void AttachLadder(Ladder l)
        {
            ladder = l; state = MoveState.Ladder; cc.enabled = false;
            ladderT = l.Project(transform.position);
            weapons?.Holster(true);
        }

        void LadderUpdate(float dt)
        {
            float v = GameInput.Move.y * (GameInput.Sprint ? 2.6f : 1.6f);
            ladderT += v * dt / ladder.Length;
            var pos = ladder.PointAt(Mathf.Clamp01(ladderT));
            transform.SetPositionAndRotation(pos, Quaternion.LookRotation(-ladder.Normal));
            rig.pose = CharPose.Climbing; rig.velocity = Vector3.up * v;
            if (ladderT >= 1f) { ExitLadder(ladder.TopExit); return; }
            if (ladderT <= 0f || GameInput.JumpDown || GameInput.InteractDown) { ExitLadder(ladderT <= 0f ? ladder.BottomExit : transform.position - ladder.Normal * -0.6f); }
        }

        void ExitLadder(Vector3 p)
        {
            transform.position = p; cc.enabled = true; state = MoveState.Ground; ladder = null; vy = 0f;
            weapons?.Holster(false);
        }

        // ------------------------------------------------------------ cover
        void TryEnterCover()
        {
            var dir = Quaternion.Euler(0f, CamYaw, 0f) * Vector3.forward;
            Vector3 origin = transform.position + Vector3.up * 0.6f;
            if (!Physics.Raycast(origin, dir, out var hit, 2.2f, Layers.World | (1 << Layers.Vehicle), QueryTriggerInteraction.Ignore))
                if (!Physics.Raycast(origin, transform.forward, out hit, 2.2f, Layers.World | (1 << Layers.Vehicle), QueryTriggerInteraction.Ignore)) return;
            if (Mathf.Abs(hit.normal.y) > 0.4f) return;
            coverNormal = U.Flat(hit.normal).normalized;
            coverPoint = hit.point;
            coverLow = !Physics.Raycast(transform.position + Vector3.up * 1.45f, -coverNormal, 2.4f, Layers.World | (1 << Layers.Vehicle), QueryTriggerInteraction.Ignore);
            StartCoroutine(MoveIntoCover(hit.point + coverNormal * 0.42f));
        }

        IEnumerator MoveIntoCover(Vector3 target)
        {
            busy = true;
            target.y = transform.position.y;
            for (float t = 0f; t < 0.3f; t += Time.deltaTime)
            {
                var d = target - transform.position; d.y = 0f;
                cc.Move(Vector3.ClampMagnitude(d, 8f * Time.deltaTime) + Vector3.down * 2f * Time.deltaTime);
                rig.velocity = d / 0.3f;
                yield return null;
            }
            busy = false;
            state = MoveState.Cover; Crouching = coverLow; coverExitT = 0f;
        }

        void CoverUpdate(float dt)
        {
            var input = GameInput.Move;
            var tangent = Vector3.Cross(Vector3.up, coverNormal); // character's right when facing the wall
            var camRight = Quaternion.Euler(0f, CamYaw, 0f) * Vector3.right;
            float side = Vector3.Dot(camRight, tangent) >= 0f ? input.x : -input.x;
            bool aimHeld = GameInput.Aim;

            // probe wall continuity to the sides
            coverEdgeR = !Physics.Raycast(transform.position + Vector3.up * 0.6f + tangent * 0.45f, -coverNormal, 1.0f, Layers.World | (1 << Layers.Vehicle), QueryTriggerInteraction.Ignore);
            coverEdgeL = !Physics.Raycast(transform.position + Vector3.up * 0.6f - tangent * 0.45f, -coverNormal, 1.0f, Layers.World | (1 << Layers.Vehicle), QueryTriggerInteraction.Ignore);
            if ((side > 0 && coverEdgeR) || (side < 0 && coverEdgeL)) side = 0f;

            Vector3 move = tangent * side * (Crouching ? 1.6f : 2.2f);
            // stick to the wall
            if (Physics.Raycast(transform.position + Vector3.up * 0.6f, -coverNormal, out var wall, 1.4f, Layers.World | (1 << Layers.Vehicle), QueryTriggerInteraction.Ignore))
            {
                coverNormal = Vector3.Lerp(coverNormal, U.Flat(wall.normal).normalized, dt * 8f).normalized;
                move += -coverNormal * (wall.distance - 0.42f) * 6f;
            }
            else { ExitCover(); return; }

            // peeking when aiming: rise above low cover, lean out at edges
            float peekTarget = 0f;
            if (aimHeld) peekTarget = coverLow ? 0f : (coverEdgeR ? 0.65f : (coverEdgeL ? -0.65f : 0f));
            coverPeek = Mathf.MoveTowards(coverPeek, peekTarget, dt * 4f);
            move += tangent * (coverPeek - 0f) * 0f;
            cc.Move((move + Vector3.down * 3f) * dt);
            Crouching = coverLow && !aimHeld;

            var face = aimHeld ? Quaternion.Euler(0f, CamYaw, 0f) * Vector3.forward : -coverNormal;
            face.y = 0f;
            transform.rotation = Quaternion.RotateTowards(transform.rotation, Quaternion.LookRotation(face), 720f * dt);
            if (aimHeld && Mathf.Abs(coverPeek) > 0.05f)
            {
                var off = tangent * coverPeek * dt * 0f;
                cc.Move(off);
            }
            rig.pose = CharPose.Normal; rig.crouch = Crouching; rig.velocity = move; rig.grounded = true;
            rig.inCover = true;

            HandleWeapons(dt, true, true);
            if (aimHeld && Mathf.Abs(coverPeek) > 0.3f) rig.aimDir = (AimPoint - (rig.Chest.position + tangent * coverPeek)).normalized;

            // corner swap: jump at an edge moves around the corner
            if (GameInput.JumpDown && (coverEdgeL || coverEdgeR)) { TryCornerSwap(coverEdgeR ? tangent : -tangent); return; }
            if (GameInput.CoverDown || GameInput.Sprint) { ExitCover(); return; }
            if (Vector3.Dot(Quaternion.Euler(0f, CamYaw, 0f) * new Vector3(input.x, 0f, input.y), coverNormal) > 0.6f) { coverExitT += dt; if (coverExitT > 0.25f) ExitCover(); }
            else coverExitT = 0f;
        }

        void TryCornerSwap(Vector3 dir)
        {
            var probe = transform.position + Vector3.up * 0.6f + dir * 1.0f - coverNormal * 0.9f;
            if (Physics.Raycast(probe, -dir, out var side, 1.2f, Layers.World | (1 << Layers.Vehicle), QueryTriggerInteraction.Ignore) && Mathf.Abs(side.normal.y) < 0.4f)
            {
                coverNormal = U.Flat(side.normal).normalized;
                var target = side.point + coverNormal * 0.42f; target.y = transform.position.y;
                StartCoroutine(MoveIntoCover(target));
            }
        }

        void ExitCover() { state = MoveState.Ground; rig.inCover = false; Crouching = false; coverPeek = 0f; }

        // ------------------------------------------------------------ freefall & parachute
        void EnterFreefall()
        {
            state = MoveState.Freefall; Crouching = false; vel = planar + Vector3.up * vy;
            weapons?.Holster(true);
            HUD.Notify("Press SPACE to open the parachute");
        }

        void SkyUpdate(float dt)
        {
            var input = GameInput.Move;
            AltitudeAboveGround = Physics.Raycast(transform.position + Vector3.up * 0.2f, Vector3.down, out var gh, 1000f, Layers.Ground, QueryTriggerInteraction.Ignore) ? gh.distance : 1000f;
            float yaw = transform.eulerAngles.y + input.x * (state == MoveState.Parachute ? 55f : 90f) * dt;
            var fwd = Quaternion.Euler(0f, yaw, 0f) * Vector3.forward;
            if (state == MoveState.Freefall)
            {
                float forwardSpeed = 8f + input.y * 14f;
                vel = Vector3.Lerp(vel, fwd * Mathf.Max(forwardSpeed, 2f) + Vector3.down * (input.y > 0 ? 58f : 45f), dt * 0.8f);
                rig.pose = CharPose.Freefall; rig.steerRoll = -input.x * 25f;
                if (GameInput.JumpDown || GameInput.EnterVehicleDown || AltitudeAboveGround < 18f) DeployParachute();
            }
            else
            {
                parachuteDeployT += dt;
                float flare = GameInput.Held(Key.S) ? 1f : 0f;
                float dive = GameInput.Held(Key.W) ? 1f : 0f;
                float sink = Mathf.Lerp(4.6f, 9f, dive) * Mathf.Lerp(1f, 0.45f, flare);
                float fspd = Mathf.Lerp(9f, 15f, dive) * Mathf.Lerp(1f, 0.35f, flare);
                vel = Vector3.Lerp(vel, fwd * fspd + Vector3.down * sink, dt * (parachuteDeployT < 1f ? 3f : 1.6f));
                rig.pose = CharPose.Parachute; rig.steerRoll = -input.x * 12f; rig.steerLean = flare * 15f;
                Parachute.Instance?.Show(transform, true);
            }
            transform.rotation = Quaternion.Euler(0f, yaw, 0f);
            cc.Move(vel * dt);
            rig.velocity = vel;
            if (cc.isGrounded || (Water.IsWater(transform.position) && transform.position.y < Water.Level - 0.5f))
            {
                float impact = -vel.y;
                bool wasChute = state == MoveState.Parachute;
                Parachute.Instance?.Show(transform, false);
                state = MoveState.Ground; vy = vel.y; planar = U.Flat(vel) * 0.4f; airTime = 0f;
                weapons?.Holster(false);
                if (wasChute && impact > 7.5f) { actor.TakeDamage(DamageInfo.Make((impact - 7.5f) * 6f, DamageType.Fall, transform.position, Vector3.down, null)); actor.Knockdown(fwd * 30f, transform.position + Vector3.up, 1.2f); }
                else if (!wasChute) Land(impact);
                else HUD.Notify("Nice landing");
            }
        }

        void DeployParachute()
        {
            if (!PlayerState.I.hasParachute) return;
            state = MoveState.Parachute; parachuteDeployT = 0f;
            PlayerState.I.hasParachute = false;
            actor.look?.SetGear(false, PlayerState.I.hasScuba);
            AudioFX.PlayAt("chute", transform.position, 0.8f);
            Parachute.Instance?.Show(transform, true);
        }

        // ------------------------------------------------------------ vehicles
        void TryEnterVehicle(bool passenger)
        {
            var v = Vehicle.Nearest(transform.position, 5.5f);
            if (v == null || v.IsDestroyed) return;
            int seat = passenger ? v.FreePassengerSeat() : 0;
            if (seat < 0) return;
            StartCoroutine(EnterRoutine(v, seat));
        }

        IEnumerator EnterRoutine(Vehicle v, int seatIdx)
        {
            busy = true; state = MoveState.Scripted; IsAiming = false;
            var seat = v.seats[seatIdx];
            float t = 0f;
            bool bike = v.kind == VehicleKind.Bike || v.kind == VehicleKind.Bicycle;
            var door = seat.door != null ? seat.door.position : v.transform.position;
            while (t < 1.4f && U.FlatDist(transform.position, door) > 0.45f && !bike)
            {
                var d = door - transform.position; d.y = 0f;
                cc.Move(d.normalized * 4.5f * Time.deltaTime + Vector3.down * 3f * Time.deltaTime);
                if (d.sqrMagnitude > 0.01f) transform.rotation = Quaternion.LookRotation(d);
                rig.velocity = d.normalized * 4.5f; rig.pose = CharPose.Normal; rig.grounded = true;
                t += Time.deltaTime; door = seat.door.position;
                yield return null;
            }
            var occ = seat.occupant;
            if (occ != null && occ != actor)
            {
                transform.rotation = Quaternion.LookRotation(U.Flat(v.transform.position - transform.position));
                rig.PlayAction(6, 0.6f);
                yield return new WaitForSeconds(0.3f);
                v.Carjacked(occ, actor);
                WorldEvents.EmitCrime(v.def != null && v.def.police ? CrimeType.StealCopCar : CrimeType.CarJack, transform.position, gameObject);
                yield return new WaitForSeconds(0.25f);
            }
            else if (v.def != null && v.def.police && seatIdx == 0)
                WorldEvents.EmitCrime(CrimeType.StealCopCar, transform.position, gameObject);

            cc.enabled = false;
            Vector3 p0 = transform.position; Quaternion r0 = transform.rotation;
            float dur = bike ? 0.35f : 0.5f;
            for (float k = 0f; k < 1f; k += Time.deltaTime / dur)
            {
                var target = v.SeatRootPosition(seatIdx, rig);
                transform.SetPositionAndRotation(Vector3.Lerp(p0, target, Mathf.SmoothStep(0, 1, k)), Quaternion.Slerp(r0, v.transform.rotation, k));
                rig.pose = k > 0.5f ? (seatIdx == 0 ? (bike ? CharPose.Riding : CharPose.Driving) : CharPose.Passenger) : CharPose.Normal;
                yield return null;
            }
            v.Occupy(actor, seatIdx);
            busy = false;
            state = MoveState.Vehicle;
            PlayerCamera.I.SnapBehind(v.transform);
            if (v.def != null) HUD.ShowVehicleName(v.def.name);
            if (seatIdx == 0 && (v.kind == VehicleKind.Heli || v.kind == VehicleKind.Plane))
                HUD.Notify(v.kind == VehicleKind.Heli ? "Heli: SPACE up, CTRL down, W/S pitch, A/D yaw, Q/E roll" : "Plane: SPACE/CTRL throttle, S pull up / W nose down, A/D roll, Q/E rudder");
        }

        void VehicleUpdate(float dt)
        {
            var v = actor.vehicle;
            if (v == null) { state = MoveState.Ground; cc.enabled = true; return; }
            bool driver = actor.seat == 0;
            var wd = weapons != null ? weapons.Current : null;
            DriveByAiming = GameInput.Aim && wd != null && (wd.driveBy || wd.cls == WeaponClass.Thrown) && v.kind != VehicleKind.Plane;
            IsAiming = DriveByAiming;
            if (driver)
            {
                var vi = new VehicleInput();
                var m = GameInput.Move;
                vi.throttle = Mathf.Max(0f, m.y); vi.brake = Mathf.Max(0f, -m.y); vi.steer = m.x;
                vi.handbrake = GameInput.Held(Key.Space) ? 1f : 0f;
                if (v.kind == VehicleKind.Heli || v.kind == VehicleKind.Plane)
                {
                    vi.pitch = m.y; vi.yaw = v.kind == VehicleKind.Heli ? m.x : (GameInput.Held(Key.E) ? 1f : 0f) - (GameInput.Held(Key.Q) ? 1f : 0f);
                    vi.roll = v.kind == VehicleKind.Heli ? (GameInput.Held(Key.E) ? 1f : 0f) - (GameInput.Held(Key.Q) ? 1f : 0f) : m.x;
                    vi.lift = (GameInput.Held(Key.Space) ? 1f : 0f) - (GameInput.Held(Key.LeftCtrl) ? 1f : 0f);
                    vi.handbrake = 0f;
                }
                vi.horn = GameInput.Held(Key.H);
                vi.boost = GameInput.Held(Key.LeftShift);
                v.input = vi;
                if (GameInput.Down(Key.L)) v.ToggleLights();
                if (GameInput.Down(Key.N) && v.def != null && v.def.siren) v.ToggleSiren();   // H = horn, N = siren
                if (GameInput.Down(Key.R) && !DriveByAiming && v.def != null && v.def.convertible) v.ToggleRoof();
                if (GameInput.InteractDown && GarageApi.NearGarage(v.transform.position) && v.kind != VehicleKind.Heli && v.kind != VehicleKind.Plane && v.kind != VehicleKind.Boat) { PlayerState.I.StoreCurrentVehicle(); return; }
                if (GameInput.Down(Key.Period)) RadioSystem.Next(1);
                if (GameInput.Down(Key.Comma)) RadioSystem.Next(-1);
                var ps = PlayerState.I;
                if (Mathf.Abs(v.Speed) > 18f) ps.Train(v.kind == VehicleKind.Heli || v.kind == VehicleKind.Plane ? Skill.Flying : Skill.Driving, dt * 0.0016f);
                if (v.kind == VehicleKind.Bicycle && Mathf.Abs(v.Speed) > 4f) ps.Train(Skill.Stamina, dt * 0.002f);
            }
            rig.aiming = DriveByAiming;
            if (DriveByAiming) rig.aimDir = (AimPoint - rig.Chest.position).normalized;
            if (weapons != null) weapons.SetVisible(DriveByAiming);
            if (DriveByAiming)
            {
                if (wd.cls == WeaponClass.Thrown) { if (GameInput.FireDown) weapons.Throw(AimPoint); }
                else if (wd.auto ? GameInput.Fire : GameInput.FireDown) weapons.Fire(AimPoint, 1.9f * Mathf.Lerp(1.15f, 0.75f, PlayerState.I.Get(Skill.Shooting)), true);
                if (GameInput.ReloadDown) weapons.Reload();
            }
            for (int i = 0; i < 9; i++) if (GameInput.Down(Key.Digit1 + i)) weapons.SelectSlot(i);
            if (GameInput.EnterVehicleDown && !busy) StartCoroutine(ExitRoutine());
            if (v.Submerged && v.kind != VehicleKind.Boat) StartCoroutine(ExitRoutine());
        }

        public IEnumerator ExitRoutine()
        {
            var v = actor.vehicle;
            if (v == null) yield break;
            busy = true;
            int seatIdx = actor.seat;
            float speed = v.Rb != null ? v.Rb.linearVelocity.magnitude : 0f;
            var velocityAtExit = v.Rb != null ? v.Rb.linearVelocity : Vector3.zero;
            bool air = v.kind == VehicleKind.Heli || v.kind == VehicleKind.Plane;
            var exitPos = v.ExitPosition(seatIdx);
            v.Vacate(actor);
            if (weapons) weapons.SetVisible(true);
            if (!air && speed > 7f)
            {
                // bail out of a moving vehicle
                transform.position = exitPos + Vector3.up * 0.3f;
                cc.enabled = true; state = MoveState.Ground; busy = false;
                actor.Knockdown(velocityAtExit * 2.5f + v.transform.right * 40f, transform.position + Vector3.up, 1.8f);
                actor.TakeDamage(DamageInfo.Make(Mathf.Min(speed * 0.8f, 30f), DamageType.Fall, transform.position, Vector3.down, null));
                yield break;
            }
            Vector3 p0 = transform.position;
            float dur = air ? 0.15f : 0.4f;
            for (float k = 0f; k < 1f; k += Time.deltaTime / dur)
            {
                transform.position = Vector3.Lerp(p0, exitPos, Mathf.SmoothStep(0, 1, k));
                transform.rotation = Quaternion.LookRotation(U.Flat(v.transform.forward));
                rig.pose = CharPose.Normal;
                yield return null;
            }
            transform.position = exitPos;
            cc.enabled = true; busy = false;
            state = MoveState.Ground; vy = 0f; planar = air ? U.Flat(velocityAtExit) : Vector3.zero;
            if (air) { vy = velocityAtExit.y; airTime = 0.3f; }
            DriveByAiming = false; IsAiming = false;
        }

        // ------------------------------------------------------------ interaction
        void TryInteract()
        {
            var l = Ladder.Nearest(transform.position, 1.6f);
            if (l != null) { AttachLadder(l); return; }
            var it = Interactable.Nearest(transform.position);
            if (it != null) it.Interact(this);
        }

        public void Teleport(Vector3 p, float yaw)
        {
            StopAllCoroutines(); busy = false;
            if (actor.InVehicle) actor.vehicle.Vacate(actor);
            actor.ClearKnockdown();
            cc.enabled = false;
            transform.SetPositionAndRotation(p, Quaternion.Euler(0f, yaw, 0f));
            cc.enabled = true;
            state = MoveState.Ground; vy = 0f; planar = Vector3.zero; Underwater = false;
            Parachute.Instance?.Show(transform, false);
            if (PlayerCamera.I) { PlayerCamera.I.yaw = yaw; PlayerCamera.I.pitch = 10f; }
            weapons?.Holster(false);
        }

        public void PutInVehicle(Vehicle v, int seat)
        {
            StopAllCoroutines(); busy = false;
            if (actor.InVehicle) actor.vehicle.Vacate(actor);
            cc.enabled = false;
            v.Occupy(actor, seat);
            state = MoveState.Vehicle;
            PlayerCamera.I.SnapBehind(v.transform);
        }

        public void ForceExitVehicleNow()
        {
            if (actor.InVehicle) StartCoroutine(ExitRoutine());
        }
    }
}
