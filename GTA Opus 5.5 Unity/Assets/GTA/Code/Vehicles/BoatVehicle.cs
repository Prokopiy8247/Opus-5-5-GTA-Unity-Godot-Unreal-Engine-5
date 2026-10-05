using UnityEngine;

namespace Halcyon
{
    /// <summary>Buoyant watercraft: probe-based buoyancy, planing hull, thrust by throttle, steering by rudder.</summary>
    public class BoatVehicle : Vehicle
    {
        float throttleSmooth, steerSmooth, rudder;
        readonly Vector3[] probes = new Vector3[5];
        float lastWakeTime;

        protected override void Awake()
        {
            base.Awake();
            Rb.linearDamping = 0.35f; Rb.angularDamping = 0.8f;
            Rb.centerOfMass = new Vector3(0f, -0.5f, 0.1f);
            var b = bounds;
            probes[0] = new Vector3(b.min.x * 0.85f, b.min.y, b.max.z * 0.9f);
            probes[1] = new Vector3(b.max.x * 0.85f, b.min.y, b.max.z * 0.9f);
            probes[2] = new Vector3(b.min.x * 0.9f, b.min.y, b.min.z * 0.9f);
            probes[3] = new Vector3(b.max.x * 0.9f, b.min.y, b.min.z * 0.9f);
            probes[4] = new Vector3(0f, b.min.y, b.min.z * 0.5f);
        }

        protected override void FixedUpdate()
        {
            base.FixedUpdate();
            float dt = Time.fixedDeltaTime;
            if (IsDestroyed) return;
            bool driver = Driver != null;
            throttleSmooth = Mathf.MoveTowards(throttleSmooth, driver && engineOn ? Mathf.Clamp01(input.throttle) : 0f, dt * 1.6f);
            rudder = Mathf.MoveTowards(rudder, (driver ? Mathf.Clamp(input.steer, -1f, 1f) : 0f), dt * 2.4f);
            bool reversing = input.brake > 0.1f && driver;

            float torque = (def != null ? def.torque : 26000f) * mods.TorqueMul * DamageFactor;
            float speedAlong = Vector3.Dot(Rb.linearVelocity, transform.forward);
            float topSpeed = (def != null ? def.topSpeed : 28f) * mods.TopSpeedMul;
            float thrust = 0f;
            if (throttleSmooth > 0.01f) thrust = throttleSmooth * torque * Mathf.Clamp01(1f - Mathf.Abs(speedAlong) / topSpeed);
            else if (reversing) thrust = -torque * 0.35f * Mathf.Clamp01(1f - Mathf.Abs(speedAlong) / (topSpeed * 0.4f));
            Rb.AddForceAtPosition(transform.forward * thrust, Rb.worldCenterOfMass + transform.forward * 2f, ForceMode.Force);

            // rudder authority scales with speed
            float auth = Mathf.Clamp01(Mathf.Abs(speedAlong) / 6f) * 1.2f;
            float yawTorque = -rudder * auth * Rb.mass * 2.2f;
            Rb.AddTorque(Vector3.up * yawTorque, ForceMode.Force);
            // roll damping
            Rb.AddTorque(-Vector3.Project(Rb.angularVelocity, transform.forward) * Rb.mass * 1.1f, ForceMode.Force);

            // buoyancy
            int inWater = 0;
            foreach (var p in probes)
            {
                var wp = transform.TransformPoint(p);
                float depth = Water.Level - wp.y;
                if (depth <= 0f) continue;
                inWater++;
                float k = Mathf.Clamp01(depth);
                Rb.AddForceAtPosition(Vector3.up * (Rb.mass * 9.81f / probes.Length) * (1f + k * 2.6f), wp, ForceMode.Force);
                // anisotropic water drag shared between the probes: the hull glides forward, resists sideslip and heave
                var lv = transform.InverseTransformDirection(Rb.GetPointVelocity(wp));
                lv.x *= 1.0f; lv.y *= 0.8f; lv.z *= 0.05f;
                Rb.AddForceAtPosition(-transform.TransformDirection(lv) * (Rb.mass * 1.6f / probes.Length), wp, ForceMode.Force);
            }
            if (inWater == 0)
            {
                Rb.AddForce(Physics.gravity * 0.35f, ForceMode.Acceleration);
            }
            else
            {
                // planing lift
                float planing = Mathf.Clamp01(Mathf.Abs(speedAlong) / 12f);
                Rb.AddForce(Vector3.up * Rb.mass * 9.81f * planing * 0.35f, ForceMode.Force);
            }

            // wake
            if (inWater > 0 && Mathf.Abs(speedAlong) > 2.5f)
            {
                lastWakeTime += dt;
                if (lastWakeTime > 0.08f)
                {
                    lastWakeTime = 0f;
                    VFX.Splash(transform.position - transform.forward * (bounds.extents.z * 0.8f) + Vector3.up * (Water.Level - transform.position.y), 0.5f);
                }
            }
            SetBrakeLights(false, Speed < -0.5f);
            Submerged = false;
        }

        public override void ToggleRoof() { }
    }
}
