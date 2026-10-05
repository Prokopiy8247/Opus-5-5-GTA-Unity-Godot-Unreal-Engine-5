using UnityEngine;

namespace Halcyon
{
    public enum CharPose { Normal, Driving, Passenger, Riding, Swimming, Climbing, Parachute, Freefall, Seated }

    /// <summary>
    /// Procedural animation for the Blender-authored rigid-skinned characters.
    /// Rotations are expressed around model-space axes captured from the rest pose, so the result does not depend on how
    /// the FBX importer oriented each bone. Also provides two-bone arm IK (weapons, steering) and an on-demand ragdoll.
    /// </summary>
    public class CharacterRig : MonoBehaviour
    {
        const int H = 0, S = 1, C = 2, N = 3, HD = 4, UAL = 5, LAL = 6, HL = 7, UAR = 8, LAR = 9, HR = 10, ULL = 11, LLL = 12, FL = 13, ULR = 14, LLR = 15, FR = 16;
        static readonly string[] Names = { "Hips", "Spine", "Chest", "Neck", "Head", "UpperArm_L", "LowerArm_L", "Hand_L", "UpperArm_R", "LowerArm_R", "Hand_R", "UpperLeg_L", "LowerLeg_L", "Foot_L", "UpperLeg_R", "LowerLeg_R", "Foot_R" };

        public Transform[] b = new Transform[17];
        Quaternion[] restLocal = new Quaternion[17];
        Vector3[] restLocalPos = new Vector3[17];
        Quaternion[] parentInvRest = new Quaternion[17];
        Vector3 hipsRestModel;
        public bool valid;

        // ---- inputs written by controllers every frame
        [System.NonSerialized] public Vector3 velocity;
        [System.NonSerialized] public bool grounded = true, crouch, aiming, blocking, inCover, coverLow;
        [System.NonSerialized] public CharPose pose = CharPose.Normal;
        [System.NonSerialized] public HoldType hold = HoldType.Unarmed;
        [System.NonSerialized] public Vector3 aimDir = Vector3.forward;
        [System.NonSerialized] public Transform weapon, weaponGrip, weaponForegrip;
        [System.NonSerialized] public Transform steerL, steerR;
        [System.NonSerialized] public float verticalSpeed, swimPitch, panic;
        [System.NonSerialized] public bool lookEnabled;
        [System.NonSerialized] public Vector3 lookTarget;

        float phase, idleT, hitT, hitSide, reloadT, reloadDur;
        float actionT = -1f, actionDur; int actionKind; // 1 punchR 2 punchL 3 heavy 4 swing 5 throw 6 takedown 7 kick
        public bool ActionActive => actionT >= 0f;
        public float ActionProgress => actionT < 0 ? 1f : Mathf.Clamp01(actionT / actionDur);
        public int ActionKind => actionKind;

        public bool IsRagdoll { get; private set; }
        Rigidbody[] rbs; Collider[] rcols; bool ragdollBuilt;
        Vector3[] prevPos = new Vector3[17];
        public Transform Hips => b[H];
        public Transform Head => b[HD];
        public Transform Chest => b[C];
        public Transform HandR => b[HR];
        public Transform HandL => b[HL];

        void Awake() => Init();

        public void Init()
        {
            if (valid) return;
            for (int i = 0; i < 17; i++) b[i] = U.FindDeep(transform, Names[i]);
            for (int i = 0; i < 17; i++) if (b[i] == null) { Debug.LogWarning("[CharacterRig] missing bone " + Names[i] + " on " + name); return; }
            var rootInv = Quaternion.Inverse(transform.rotation);
            for (int i = 0; i < 17; i++)
            {
                restLocal[i] = b[i].localRotation;
                restLocalPos[i] = b[i].localPosition;
                parentInvRest[i] = Quaternion.Inverse(rootInv * b[i].parent.rotation);
            }
            hipsRestModel = transform.InverseTransformPoint(b[H].position);
            valid = true;
        }

        void ResetPose()
        {
            for (int i = 0; i < 17; i++) { b[i].localRotation = restLocal[i]; b[i].localPosition = restLocalPos[i]; }
        }

        /// <summary>Rotate bone i around a model-space axis (axis expressed in the parent's current frame).</summary>
        void R(int i, Vector3 modelAxis, float deg)
        {
            if (deg == 0f) return;
            var t = b[i];
            var axis = t.parent.rotation * (parentInvRest[i] * modelAxis);
            t.rotation = Quaternion.AngleAxis(deg, axis) * t.rotation;
        }

        static readonly Vector3 X = Vector3.right, Y = Vector3.up, Z = Vector3.forward;

        // ------------------------------------------------------------- one-shot actions
        public void PlayAction(int kind, float duration) { actionKind = kind; actionDur = duration; actionT = 0f; }
        public void PlayHit(Vector3 worldDir) { hitT = 0.35f; hitSide = Vector3.Dot(transform.right, worldDir) > 0 ? 1f : -1f; }
        public void PlayReload(float dur) { reloadT = 0f; reloadDur = dur; }

        void LateUpdate()
        {
            if (!valid || IsRagdoll) { CaptureVelocities(); return; }
            float dt = Time.deltaTime;
            idleT += dt;
            ResetPose();

            var lv = transform.InverseTransformDirection(velocity);
            float spd = new Vector2(lv.x, lv.z).magnitude;

            switch (pose)
            {
                case CharPose.Driving: Seated(true, 0f); break;
                case CharPose.Passenger: case CharPose.Seated: Seated(false, 0f); break;
                case CharPose.Riding: Seated(true, 1f); break;
                case CharPose.Swimming: Swim(spd, dt); break;
                case CharPose.Climbing: Climb(velocity.y, dt); break;
                case CharPose.Parachute: Parachute(); break;
                case CharPose.Freefall: Freefall(); break;
                default: Locomotion(lv, spd, dt); break;
            }

            if (pose == CharPose.Normal || pose == CharPose.Driving || pose == CharPose.Riding || pose == CharPose.Passenger)
                UpperBody(dt);

            if (hitT > 0f)
            {
                float k = hitT / 0.35f;
                R(C, X, -14f * k); R(S, Z, 8f * hitSide * k); R(HD, X, -10f * k);
                hitT -= dt;
            }
            if (actionT >= 0f) { actionT += dt; if (actionT >= actionDur) actionT = -1f; }
            CaptureVelocities();
        }

        void HipsOffset(Vector3 modelOffset)
        {
            b[H].position = transform.TransformPoint(hipsRestModel + modelOffset);
        }

        void Locomotion(Vector3 lv, float spd, float dt)
        {
            float runK = Mathf.InverseLerp(2.2f, 5.5f, spd);
            float sprintK = Mathf.InverseLerp(5.6f, 7.6f, spd);
            float moveK = Mathf.Clamp01(spd / 0.9f);
            float hz = Mathf.Lerp(0.9f, 1.4f, runK) + sprintK * 0.25f;
            if (crouch) hz *= 0.85f;
            phase += dt * hz * Mathf.PI * 2f * Mathf.Max(moveK, 0.0001f);
            float s = Mathf.Sin(phase), c = Mathf.Cos(phase);
            float dir = lv.z < -0.25f && Mathf.Abs(lv.z) > Mathf.Abs(lv.x) ? -1f : 1f;

            if (!grounded)
            {
                bool longFall = verticalSpeed < -9f;
                float flail = longFall ? Mathf.Sin(idleT * 14f) * 25f : 0f;
                R(ULL, X, -40f + flail); R(LLL, X, 75f); R(ULR, X, -12f - flail); R(LLR, X, 40f);
                R(UAL, Z, -(longFall ? 110f : 45f) + flail); R(UAR, Z, (longFall ? 110f : 45f) - flail);
                R(LAL, X, -30f); R(LAR, X, -30f);
                R(S, X, 6f);
                return;
            }

            float crouchK = crouch ? 1f : 0f;
            float thighA = Mathf.Lerp(24f, 48f, runK) * moveK * (crouch ? 0.6f : 1f);
            float kneeA = Mathf.Lerp(38f, 100f, runK) * moveK * (crouch ? 0.6f : 1f);
            float armA = Mathf.Lerp(16f, 48f, runK) * moveK;
            float elbowBase = Mathf.Lerp(12f, 82f, runK) + crouchK * 30f;

            float bob = -(0.02f + 0.035f * runK) * moveK * (0.5f + 0.5f * Mathf.Cos(2f * phase));
            float crouchDrop = crouchK * 0.34f;
            HipsOffset(new Vector3(0f, bob - crouchDrop, 0f));
            R(H, Y, 7f * s * moveK * (1f - runK * 0.5f));
            R(H, Z, 3f * s * moveK);

            float thighBase = crouchK * -62f;
            float kneeBase = crouchK * 105f + runK * 12f * moveK;
            float tl = thighBase - thighA * s * dir, tr = thighBase + thighA * s * dir;
            float kl = kneeBase + kneeA * Mathf.Max(0f, c * dir) + 4f * moveK;
            float kr = kneeBase + kneeA * Mathf.Max(0f, -c * dir) + 4f * moveK;
            R(ULL, X, tl); R(LLL, X, kl); R(FL, X, -(tl + kl) * 0.55f);
            R(ULR, X, tr); R(LLR, X, kr); R(FR, X, -(tr + kr) * 0.55f);

            float lean = Mathf.Lerp(3f, 11f, runK) * moveK + sprintK * 7f + crouchK * 24f + panic * 6f;
            R(S, X, lean * 0.6f); R(C, X, lean * 0.4f - (crouchK * 6f));
            R(C, Y, -9f * s * moveK);
            R(C, X, 1.4f * Mathf.Sin(idleT * 1.9f) * (1f - moveK));
            R(HD, X, -lean * 0.6f);

            R(UAL, X, armA * s * dir); R(UAR, X, -armA * s * dir);
            R(UAL, Z, -7f - panic * 30f); R(UAR, Z, 7f + panic * 30f);
            R(LAL, X, -(elbowBase + 18f * Mathf.Max(0f, -s) * moveK + panic * 40f));
            R(LAR, X, -(elbowBase + 18f * Mathf.Max(0f, s) * moveK + panic * 40f));
        }

        void Seated(bool drive, float bikeK)
        {
            R(ULL, X, -82f + bikeK * 20f); R(LLL, X, 84f - bikeK * 10f); R(FL, X, -8f);
            R(ULR, X, -82f + bikeK * 20f); R(LLR, X, 84f - bikeK * 10f); R(FR, X, -8f);
            R(ULL, Z, -6f - bikeK * 8f); R(ULR, Z, 6f + bikeK * 8f);
            R(S, X, -4f + bikeK * 26f);
            if (!drive)
            {
                R(UAL, X, -22f); R(UAR, X, -22f); R(LAL, X, -62f); R(LAR, X, -62f);
            }
        }

        void Swim(float spd, float dt)
        {
            phase += dt * (1.2f + spd * 0.5f) * Mathf.PI;
            float s = Mathf.Sin(phase);
            R(H, X, 70f + swimPitch);
            HipsOffset(new Vector3(0f, -0.55f, -0.1f));
            R(HD, X, -55f);
            float stroke = (phase % (Mathf.PI * 2f)) / (Mathf.PI * 2f) * 360f;
            float k = Mathf.Clamp01(spd / 1.5f);
            R(UAL, X, -90f - 70f * Mathf.Sin(phase) * k - 30f); R(UAR, X, -90f + 70f * Mathf.Sin(phase) * k - 30f);
            R(UAL, Z, -25f); R(UAR, Z, 25f);
            R(LAL, X, -25f); R(LAR, X, -25f);
            R(ULL, X, 14f * s); R(ULR, X, -14f * s);
            R(LLL, X, 15f + 10f * Mathf.Max(0, s)); R(LLR, X, 15f + 10f * Mathf.Max(0, -s));
            _ = stroke;
        }

        void Climb(float vy, float dt)
        {
            phase += dt * vy * 3.2f;
            float s = Mathf.Sin(phase);
            R(UAL, X, -150f + 22f * s); R(UAR, X, -150f - 22f * s);
            R(LAL, X, -35f); R(LAR, X, -35f);
            R(ULL, X, -45f - 22f * s); R(LLL, X, 80f);
            R(ULR, X, -45f + 22f * s); R(LLR, X, 80f);
        }

        void Parachute()
        {
            R(UAL, X, -160f); R(UAR, X, -160f); R(UAL, Z, -18f); R(UAR, Z, 18f);
            R(LAL, X, -30f); R(LAR, X, -30f);
            R(ULL, X, -12f); R(ULR, X, -8f); R(LLL, X, 18f); R(LLR, X, 12f);
            R(S, X, -steerLean);
            R(S, Z, steerRoll);
        }
        [System.NonSerialized] public float steerLean, steerRoll;

        void Freefall()
        {
            R(H, X, 78f);
            HipsOffset(new Vector3(0f, 0f, 0f));
            R(HD, X, -60f);
            R(UAL, Z, -70f); R(UAR, Z, 70f); R(UAL, X, -25f); R(UAR, X, -25f);
            R(LAL, X, -40f); R(LAR, X, -40f);
            R(ULL, Z, -12f); R(ULR, Z, 12f); R(LLL, X, 35f); R(LLR, X, 35f);
            R(S, Z, steerRoll);
        }

        // ------------------------------------------------------------- upper body / weapons
        void UpperBody(float dt)
        {
            var bodyRot = transform.rotation;
            var flatAim = Vector3.ProjectOnPlane(aimDir, Vector3.up);
            bool hasWeapon = weapon != null && weapon.gameObject.activeInHierarchy;
            bool seated = pose != CharPose.Normal;

            if ((aiming || lookEnabled) && flatAim.sqrMagnitude > 0.001f)
            {
                float yaw = Vector3.SignedAngle(transform.forward, flatAim, Vector3.up);
                yaw = Mathf.Clamp(yaw, seated ? -100f : -75f, seated ? 100f : 75f);
                float pitch = -Mathf.Asin(Mathf.Clamp(aimDir.normalized.y, -0.99f, 0.99f)) * Mathf.Rad2Deg;
                if (!aiming) { yaw *= 0.6f; pitch *= 0.5f; }
                R(S, Y, yaw * 0.3f); R(C, Y, yaw * 0.4f); R(N, Y, yaw * 0.15f); R(HD, Y, yaw * 0.15f);
                R(S, X, pitch * 0.25f); R(C, X, pitch * 0.4f); R(HD, X, pitch * 0.35f);
            }
            else if (lookEnabled == false && pose == CharPose.Normal && panic > 0.5f)
            {
                R(HD, Y, Mathf.Sin(idleT * 3f) * 30f);
            }

            if (blocking)
            {
                R(UAL, X, -75f); R(UAR, X, -75f); R(UAL, Z, 15f); R(UAR, Z, -15f);
                R(LAL, X, -115f); R(LAR, X, -115f);
            }

            // melee/throw actions (procedural keyframes)
            if (actionT >= 0f)
            {
                float p = ActionProgress;
                float strike = p < 0.35f ? p / 0.35f : 1f - (p - 0.35f) / 0.65f;
                switch (actionKind)
                {
                    case 1: R(C, Y, -25f * strike); R(UAR, X, -85f * strike); R(LAR, X, -(70f - 65f * strike)); R(UAL, X, -50f); R(LAL, X, -110f); break;
                    case 2: R(C, Y, 25f * strike); R(UAL, X, -85f * strike); R(LAL, X, -(70f - 65f * strike)); R(UAR, X, -50f); R(LAR, X, -110f); break;
                    case 3: R(C, Y, -40f * strike + 15f * (1 - strike)); R(UAR, X, -110f * strike); R(UAR, Z, 30f * strike); R(LAR, X, -30f); R(S, X, 10f * strike); break;
                    case 4:
                        {
                            float sw = p < 0.4f ? -p / 0.4f : -1f + (p - 0.4f) / 0.6f * 2.2f;
                            sw = Mathf.Clamp(sw, -1f, 1.2f);
                            R(C, Y, 45f * sw); R(UAR, X, -100f); R(UAR, Z, 40f - 50f * sw); R(LAR, X, -40f);
                            R(UAL, X, -70f); R(LAL, X, -60f);
                            break;
                        }
                    case 5: { float th = p < 0.5f ? p / 0.5f : 1f - (p - 0.5f) / 0.5f; R(UAR, X, -150f * th - 30f); R(UAR, Z, 40f * th); R(C, Y, 30f * th - 20f * (1 - th)); break; }
                    case 6: R(UAL, X, -95f); R(UAR, X, -95f); R(LAL, X, -100f); R(LAR, X, -100f); R(S, X, 15f); R(C, Y, -20f * strike); break;
                    case 7: R(ULR, X, -80f * strike); R(LLR, X, 30f * (1 - strike)); R(C, X, -10f * strike); break;
                }
            }

            if (pose == CharPose.Driving || pose == CharPose.Riding)
            {
                if (aiming && hasWeapon && (hold == HoldType.OneHand || hold == HoldType.Throw))
                {
                    PlaceWeapon(bodyRot, dt, true);
                    if (steerL) IK(UAL, LAL, HL, steerL.position, b[UAL].position + bodyRot * new Vector3(-0.3f, -0.4f, 0f));
                    return;
                }
                if (steerL) IK(UAL, LAL, HL, steerL.position, b[UAL].position + bodyRot * new Vector3(-0.35f, -0.4f, -0.1f));
                if (steerR) IK(UAR, LAR, HR, steerR.position, b[UAR].position + bodyRot * new Vector3(0.35f, -0.4f, -0.1f));
                return;
            }
            if (pose == CharPose.Passenger) return;
            if (hasWeapon && actionT < 0f || (hasWeapon && (hold == HoldType.Melee || hold == HoldType.Throw))) PlaceWeapon(bodyRot, dt, aiming);
        }

        void PlaceWeapon(Quaternion bodyRot, float dt, bool aimingNow)
        {
            var aimRot = Quaternion.LookRotation(aimDir.sqrMagnitude > 0.01f ? aimDir : transform.forward, Vector3.up);
            Vector3 shoulderR = b[UAR].position, chestP = b[C].position;
            Vector3 gripPos; Quaternion gripRot;
            float reloadK = 0f;
            if (reloadDur > 0f && reloadT < reloadDur)
            {
                reloadT += dt; float p = reloadT / reloadDur; reloadK = Mathf.Sin(Mathf.Clamp01(p) * Mathf.PI);
            }
            switch (hold)
            {
                case HoldType.TwoHand:
                    if (aimingNow) { gripPos = shoulderR + aimRot * new Vector3(-0.04f, -0.07f, 0.2f); gripRot = aimRot; }
                    else { gripPos = chestP + bodyRot * new Vector3(0.12f, -0.16f, 0.26f); gripRot = bodyRot * Quaternion.Euler(28f, -18f, 0f); }
                    break;
                case HoldType.Shoulder:
                    if (aimingNow) { gripPos = shoulderR + aimRot * new Vector3(-0.02f, -0.12f, 0.22f); gripRot = aimRot; }
                    else { gripPos = chestP + bodyRot * new Vector3(0.14f, -0.2f, 0.22f); gripRot = bodyRot * Quaternion.Euler(20f, -10f, 0f); }
                    break;
                case HoldType.OneHand:
                    if (aimingNow) { gripPos = shoulderR + aimRot * new Vector3(-0.14f, -0.04f, 0.46f); gripRot = aimRot; }
                    else
                    {
                        var arm = (b[HR].position - b[LAR].position).normalized;
                        gripPos = b[HR].position + arm * 0.04f;
                        gripRot = Quaternion.LookRotation(Vector3.Slerp(transform.forward, Vector3.down, 0.45f), -arm);
                        weapon.SetPositionAndRotation(gripPos, gripRot);
                        return;
                    }
                    break;
                default: // melee / throw: weapon follows the right hand
                    {
                        var arm = (b[HR].position - b[LAR].position).normalized;
                        gripPos = b[HR].position + arm * 0.03f;
                        var fwd = Vector3.Slerp(transform.forward, -arm, hold == HoldType.Melee ? 0.25f : 0.6f);
                        gripRot = Quaternion.LookRotation(Vector3.Cross(Vector3.Cross(arm, fwd), arm).sqrMagnitude > 0.001f ? Vector3.Cross(Vector3.Cross(arm, fwd), arm) : fwd, -arm);
                        if (hold == HoldType.Melee) gripRot = Quaternion.LookRotation(-arm, transform.forward);
                        weapon.SetPositionAndRotation(gripPos, gripRot);
                        return;
                    }
            }
            if (reloadK > 0f) { gripRot = gripRot * Quaternion.Euler(18f * reloadK, 0f, 35f * reloadK); gripPos += Vector3.down * 0.08f * reloadK; }
            weapon.SetPositionAndRotation(gripPos, gripRot);
            IK(UAR, LAR, HR, weaponGrip ? weaponGrip.position : gripPos, b[UAR].position + bodyRot * new Vector3(0.45f, -0.45f, -0.05f));
            Vector3 lt = weaponForegrip ? weaponForegrip.position : gripPos + gripRot * new Vector3(-0.03f, -0.02f, 0.02f);
            if (reloadK > 0f) lt = Vector3.Lerp(lt, gripPos + gripRot * new Vector3(0f, -0.12f, 0.02f), reloadK);
            IK(UAL, LAL, HL, lt, b[UAL].position + bodyRot * new Vector3(-0.25f, -0.6f, 0.15f));
        }

        /// <summary>Analytic two-bone IK (shoulder-elbow-hand) toward a target with an elbow hint.</summary>
        void IK(int ia, int ib, int ic, Vector3 target, Vector3 hint)
        {
            Transform a = b[ia], m = b[ib], e = b[ic];
            Vector3 ap = a.position, mp = m.position, ep = e.position;
            float la = (mp - ap).magnitude, lb = (ep - mp).magnitude;
            Vector3 toT = target - ap;
            float lt = Mathf.Clamp(toT.magnitude, 0.02f, (la + lb) * 0.999f);
            // current & desired elbow interior angles
            float cur = Vector3.Angle(ap - mp, ep - mp);
            float cosD = Mathf.Clamp((la * la + lb * lb - lt * lt) / (2f * la * lb), -1f, 1f);
            float desired = Mathf.Acos(cosD) * Mathf.Rad2Deg;
            Vector3 axis = Vector3.Cross(mp - ap, ep - mp);
            if (axis.sqrMagnitude < 1e-6f) axis = Vector3.Cross(mp - ap, hint - ap);
            if (axis.sqrMagnitude < 1e-6f) axis = transform.right;
            axis.Normalize();
            m.rotation = Quaternion.AngleAxis(cur - desired, axis) * m.rotation;
            // aim chain at target
            ep = e.position;
            a.rotation = Quaternion.FromToRotation(ep - ap, toT) * a.rotation;
            // twist around target axis so the elbow points toward the hint
            mp = m.position;
            var n = toT.normalized;
            var curE = Vector3.ProjectOnPlane(mp - ap, n);
            var wantE = Vector3.ProjectOnPlane(hint - ap, n);
            if (curE.sqrMagnitude > 1e-6f && wantE.sqrMagnitude > 1e-6f)
                a.rotation = Quaternion.AngleAxis(Vector3.SignedAngle(curE, wantE, n), n) * a.rotation;
        }

        public void SetHeadVisible(bool v) { if (valid) b[HD].localScale = v ? Vector3.one : Vector3.one * 0.001f; }

        // ------------------------------------------------------------- ragdoll
        void CaptureVelocities()
        {
            if (!valid) return;
            for (int i = 0; i < 17; i++) prevPos[i] = b[i].position;
        }

        void BuildRagdoll()
        {
            ragdollBuilt = true;
            int[] bodies = { H, S, C, HD, UAL, LAL, UAR, LAR, ULL, LLL, ULR, LLR };
            int[] parents = { -1, H, S, C, C, UAL, C, UAR, H, ULL, H, ULR };
            int[] childOf = { S, C, N, -1, LAL, HL, LAR, HR, LLL, FL, LLR, FR };
            float[] mass = { 12f, 9f, 13f, 5f, 2.5f, 2f, 2.5f, 2f, 7f, 4.5f, 7f, 4.5f };
            float[] rad = { 0.15f, 0.13f, 0.15f, 0.12f, 0.055f, 0.05f, 0.055f, 0.05f, 0.08f, 0.06f, 0.08f, 0.06f };
            rbs = new Rigidbody[bodies.Length]; rcols = new Collider[bodies.Length];
            var map = new int[17]; for (int i = 0; i < 17; i++) map[i] = -1;
            for (int k = 0; k < bodies.Length; k++)
            {
                var t = b[bodies[k]];
                var rb = t.gameObject.AddComponent<Rigidbody>();
                rb.mass = mass[k]; rb.isKinematic = true; rb.interpolation = RigidbodyInterpolation.Interpolate;
                rb.collisionDetectionMode = CollisionDetectionMode.ContinuousSpeculative;
                rb.linearDamping = 0.05f; rb.angularDamping = 0.6f;
                t.gameObject.layer = Layers.Ragdoll;
                Collider col;
                if (bodies[k] == HD)
                {
                    var sc = t.gameObject.AddComponent<SphereCollider>(); sc.radius = rad[k];
                    sc.center = t.InverseTransformPoint(t.position + transform.up * 0.13f); col = sc;
                }
                else if (bodies[k] == H)
                {
                    var sc = t.gameObject.AddComponent<SphereCollider>(); sc.radius = rad[k];
                    sc.center = t.InverseTransformPoint((t.position + b[S].position) * 0.5f); col = sc;
                }
                else
                {
                    var end = childOf[k] >= 0 ? b[childOf[k]].position : t.position + transform.up * 0.2f;
                    if (childOf[k] == HL || childOf[k] == HR || childOf[k] == FL || childOf[k] == FR) end += (end - t.position).normalized * 0.08f;
                    var local = t.InverseTransformPoint(end);
                    var cc = t.gameObject.AddComponent<CapsuleCollider>();
                    int ax = 0; var al = new Vector3(Mathf.Abs(local.x), Mathf.Abs(local.y), Mathf.Abs(local.z));
                    if (al.y > al.x && al.y >= al.z) ax = 1; else if (al.z > al.x && al.z > al.y) ax = 2;
                    cc.direction = ax; cc.center = local * 0.5f; cc.radius = rad[k]; cc.height = local.magnitude + rad[k];
                    col = cc;
                }
                col.enabled = false;
                rbs[k] = rb; rcols[k] = col; map[bodies[k]] = k;
            }
            for (int k = 1; k < bodies.Length; k++)
            {
                var j = b[bodies[k]].gameObject.AddComponent<CharacterJoint>();
                j.connectedBody = rbs[map[parents[k]]];
                j.enableProjection = true;
                var lo = new SoftJointLimit(); lo.limit = -35f; j.lowTwistLimit = lo;
                var hi = new SoftJointLimit(); hi.limit = 35f; j.highTwistLimit = hi;
                var s1 = new SoftJointLimit(); s1.limit = bodies[k] == LLL || bodies[k] == LLR || bodies[k] == LAL || bodies[k] == LAR ? 70f : 45f; j.swing1Limit = s1;
                var s2 = new SoftJointLimit(); s2.limit = 30f; j.swing2Limit = s2;
            }
        }

        public void EnableRagdoll(Vector3 impulse, Vector3 point)
        {
            if (!valid || IsRagdoll) return;
            if (!ragdollBuilt) BuildRagdoll();
            IsRagdoll = true;
            float dt = Mathf.Max(Time.deltaTime, 0.01f);
            for (int k = 0; k < rbs.Length; k++)
            {
                var rb = rbs[k];
                rb.isKinematic = false; rcols[k].enabled = true;
                int bi = System.Array.IndexOf(b, rb.transform);
                var v = bi >= 0 ? (rb.position - prevPos[bi]) / dt : velocity;
                if (v.sqrMagnitude > 900f) v = velocity;
                rb.linearVelocity = v;
            }
            if (impulse.sqrMagnitude > 0f)
            {
                Rigidbody best = rbs[0]; float bd = float.MaxValue;
                foreach (var rb in rbs) { float d = (rb.worldCenterOfMass - point).sqrMagnitude; if (d < bd) { bd = d; best = rb; } }
                best.AddForceAtPosition(impulse * 0.6f, point, ForceMode.Impulse);
                rbs[0].AddForce(impulse * 0.4f, ForceMode.Impulse);
            }
            if (weapon) weapon.gameObject.SetActive(false);
        }

        public Vector3 RagdollVelocity => IsRagdoll && rbs != null ? rbs[0].linearVelocity : Vector3.zero;

        /// <summary>Stand back up: move the root to where the hips landed and restore the animated pose.</summary>
        public void DisableRagdoll()
        {
            if (!IsRagdoll) return;
            var hp = b[H].position;
            var fwd = Vector3.ProjectOnPlane(b[H].up, Vector3.up);
            if (fwd.sqrMagnitude < 0.01f) fwd = transform.forward;
            float gy = U.GroundHeight(hp + Vector3.up, hp.y - 0.9f);
            foreach (var rb in rbs) { rb.isKinematic = true; }
            foreach (var c in rcols) c.enabled = false;
            transform.SetPositionAndRotation(new Vector3(hp.x, gy, hp.z), Quaternion.LookRotation(fwd.normalized, Vector3.up));
            IsRagdoll = false;
            ResetPose();
        }

        public void ApplyForceToRagdoll(Vector3 force, Vector3 point)
        {
            if (!IsRagdoll) return;
            foreach (var rb in rbs) rb.AddExplosionForce(force.magnitude, point - force.normalized, 3f, 0.3f, ForceMode.Impulse);
        }
    }
}
