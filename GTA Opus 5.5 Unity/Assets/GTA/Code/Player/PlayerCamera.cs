using UnityEngine;

namespace Halcyon
{
    public enum CamView { Near, Far, FirstPerson }

    /// <summary>Third-person orbit / shoulder-aim / vehicle chase / first-person camera with collision and shake.</summary>
    [DefaultExecutionOrder(200)]
    public class PlayerCamera : MonoBehaviour
    {
        public static PlayerCamera I;
        public Camera cam;
        public float yaw, pitch = 10f;
        public CamView view = CamView.Near;
        public float trauma;
        public bool scopeActive;
        public float baseFov = 62f;

        Vector3 pos, vehLook;
        float dist = 4.2f, fov = 62f, lookIdle, vehYawOffset, vehPitchOffset;
        float shoulder = 0.55f;
        Vector3 smoothedPivot;
        public Vector3 AimOrigin => cam.transform.position;
        public Vector3 AimForward => cam.transform.forward;

        void Awake()
        {
            I = this;
            cam = GetComponent<Camera>();
            fov = baseFov;
        }

        public void AddShake(float t) => trauma = Mathf.Clamp01(trauma + t);

        public void SnapBehind(Transform t)
        {
            yaw = t.eulerAngles.y; pitch = 12f;
        }

        void LateUpdate()
        {
            var pc = PlayerController.I;
            if (pc == null) return;
            float dt = Time.unscaledDeltaTime;
            var look = GameInput.Look;
            var actor = pc.actor;
            bool fp = view == CamView.FirstPerson;
            float targetFov = baseFov;
            Vector3 desired; Quaternion rot;
            pc.rig.SetHeadVisible(!(fp && !actor.IsDead));

            if (actor.InVehicle && !actor.IsDead)
            {
                var v = actor.vehicle;
                bool air = v.kind == VehicleKind.Heli || v.kind == VehicleKind.Plane;
                float size = v.CameraDistance;
                bool driveAim = pc.DriveByAiming;
                if (look.sqrMagnitude > 0.01f) lookIdle = 0f; else lookIdle += dt;
                vehYawOffset += look.x; vehPitchOffset = Mathf.Clamp(vehPitchOffset - look.y, -30f, 50f);
                if (lookIdle > 1.4f && !driveAim)
                {
                    vehYawOffset = Mathf.LerpAngle(vehYawOffset, 0f, dt * 2.5f);
                    vehPitchOffset = Mathf.Lerp(vehPitchOffset, 0f, dt * 2f);
                }
                var vf = v.transform.forward;
                if (air && v.kind == VehicleKind.Plane) vf = v.transform.forward;
                float baseYaw = Mathf.Atan2(vf.x, vf.z) * Mathf.Rad2Deg;
                if (v.Speed < -2f && !air) baseYaw += 180f * Mathf.Clamp01((-v.Speed - 2f) / 4f);
                yaw = Mathf.LerpAngle(yaw, baseYaw + vehYawOffset, driveAim ? 1f : dt * (air ? 3.5f : 5f));
                float vehPitch = air && v.kind == VehicleKind.Plane ? -v.transform.eulerAngles.x : 0f;
                if (vehPitch < -180f) vehPitch += 360f;
                pitch = Mathf.Lerp(pitch, (air ? 10f : 9f) + vehPitchOffset + vehPitch * 0.5f, dt * 4f);
                rot = Quaternion.Euler(pitch, yaw, 0f);
                if (fp)
                {
                    desired = pc.rig.Head.position + v.transform.forward * 0.12f + Vector3.up * 0.05f;
                    rot = Quaternion.Euler(Mathf.Clamp(vehPitchOffset, -40f, 40f) + vehPitch, Mathf.Atan2(vf.x, vf.z) * Mathf.Rad2Deg + vehYawOffset, 0f);
                    targetFov = 72f;
                }
                else
                {
                    float d = size * (view == CamView.Far ? 1.45f : 1f);
                    if (driveAim) d *= 0.75f;
                    var pivot = v.transform.position + Vector3.up * (v.CameraHeight);
                    smoothedPivot = Vector3.Lerp(smoothedPivot == Vector3.zero ? pivot : smoothedPivot, pivot, 1f - Mathf.Exp(-18f * dt));
                    desired = smoothedPivot - rot * Vector3.forward * d + (driveAim ? rot * Vector3.right * 0.8f : Vector3.zero);
                    desired = Collide(smoothedPivot, desired, 0.3f);
                    float spdK = Mathf.Clamp01(Mathf.Abs(v.Speed) / 45f);
                    targetFov = baseFov + spdK * (air ? 6f : 12f);
                    if (driveAim) targetFov = 55f;
                }
            }
            else
            {
                vehYawOffset = 0f; vehPitchOffset = 0f; smoothedPivot = Vector3.zero;
                yaw += look.x;
                pitch = Mathf.Clamp(pitch - look.y, -70f, 80f);
                rot = Quaternion.Euler(pitch, yaw, 0f);
                bool aiming = pc.IsAiming;
                var wd = pc.weapons != null ? pc.weapons.Current : null;
                var hips = actor.rig.IsRagdoll ? actor.rig.Hips.position : pc.transform.position;
                float h = pc.Crouching ? 1.15f : 1.6f;
                if (pc.state == MoveState.Swim) h = 1.3f;
                if (pc.state == MoveState.Parachute || pc.state == MoveState.Freefall) h = 1.0f;
                var pivot = actor.rig.IsRagdoll ? hips + Vector3.up * 0.5f : hips + Vector3.up * h;
                if (fp && !actor.rig.IsRagdoll)
                {
                    desired = actor.rig.Head.position + rot * new Vector3(0f, 0.06f, 0.14f);
                    targetFov = aiming && wd != null ? Mathf.Min(wd.aimFov + 8f, 60f) : 72f;
                    if (aiming && wd != null && wd.scope) targetFov = wd.aimFov;
                    if (aiming && wd != null && wd.sniperScope) targetFov = wd.aimFov * pc.weapons.ScopeZoom;
                }
                else
                {
                    float targetDist = view == CamView.Far ? 6.2f : 4.0f;
                    if (pc.state == MoveState.Parachute) targetDist = 7.5f;
                    if (pc.state == MoveState.Freefall) targetDist = 6f;
                    float sh = 0f;
                    if (aiming)
                    {
                        targetDist = 1.7f; sh = shoulder;
                        targetFov = wd != null ? wd.aimFov : 52f;
                        if (wd != null && wd.sniperScope) { targetDist = 0.2f; sh = 0.1f; targetFov = wd.aimFov * pc.weapons.ScopeZoom; }
                        else if (wd != null && wd.scope) { targetDist = 0.9f; }
                    }
                    else if (pc.state == MoveState.Cover) { targetDist = 3.0f; sh = 0.35f; }
                    dist = Mathf.Lerp(dist, targetDist, 1f - Mathf.Exp(-14f * dt));
                    var offset = rot * new Vector3(sh, 0f, -dist);
                    desired = Collide(pivot, pivot + offset, 0.22f);
                }
            }

            scopeActive = !actor.InVehicle && pc.IsAiming && pc.weapons != null && pc.weapons.Current != null && pc.weapons.Current.sniperScope;
            fov = Mathf.Lerp(fov, targetFov, 1f - Mathf.Exp(-12f * dt));
            cam.fieldOfView = fov;

            // trauma-based shake
            trauma = Mathf.Max(0f, trauma - dt * 1.4f);
            float sk = trauma * trauma;
            float t = Time.unscaledTime * 25f;
            var shakeRot = Quaternion.Euler((Mathf.PerlinNoise(t, 0f) - 0.5f) * 8f * sk, (Mathf.PerlinNoise(0f, t) - 0.5f) * 8f * sk, (Mathf.PerlinNoise(t, t) - 0.5f) * 6f * sk);
            transform.SetPositionAndRotation(desired, rot * shakeRot);
            cam.nearClipPlane = fp ? 0.03f : 0.1f;
        }

        Vector3 Collide(Vector3 pivot, Vector3 desired, float radius)
        {
            var d = desired - pivot;
            float len = d.magnitude;
            if (len < 0.01f) return desired;
            if (Physics.SphereCast(pivot, radius, d / len, out var hit, len, Layers.CameraBlock, QueryTriggerInteraction.Ignore))
                return pivot + d / len * Mathf.Max(hit.distance - 0.05f, 0.25f);
            return desired;
        }

        public void CycleView()
        {
            view = view == CamView.Near ? CamView.Far : (view == CamView.Far ? CamView.FirstPerson : CamView.Near);
        }
    }
}
