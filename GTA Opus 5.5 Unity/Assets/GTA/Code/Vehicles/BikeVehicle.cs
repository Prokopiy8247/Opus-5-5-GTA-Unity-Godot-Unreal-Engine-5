using UnityEngine;

namespace Halcyon
{
    /// <summary>Two-wheeled vehicle. Upright stabilised physics with countersteer; bicycles are pedalled versions.</summary>
    public class BikeVehicle : Vehicle
    {
        WheelCollider[] wheels = new WheelCollider[2]; // 0 front, 1 rear
        Transform[] vis = new Transform[2];
        float steerAngle, throttleSmooth, brakeSmooth, leanAngle, leanVel;
        Rigidbody riderRb;

        protected override void Awake()
        {
            base.Awake();
            var list = new System.Collections.Generic.List<Transform>();
            foreach (var t in WheelVisuals()) list.Add(t);
            list.Sort((a, b) => transform.InverseTransformPoint(b.position).z.CompareTo(transform.InverseTransformPoint(a.position).z));
            var root = new GameObject("WheelColliders"); root.transform.SetParent(transform, false);
            for (int i = 0; i < 2 && i < list.Count; i++)
            {
                var vt = list[i];
                var lp = transform.InverseTransformPoint(vt.position);
                var wgo = new GameObject("WC_" + U.Role(vt));
                wgo.transform.SetParent(root.transform, false);
                wgo.transform.localPosition = lp;
                var wc = wgo.AddComponent<WheelCollider>();
                var mr = vt.GetComponent<MeshRenderer>();
                float r = mr != null ? Mathf.Max(mr.localBounds.extents.y, mr.localBounds.extents.z) : 0.32f;
                wc.radius = r; wc.mass = 25f;
                wc.suspensionDistance = 0.24f;
                var spring = wc.suspensionSpring; spring.spring = 26000f; spring.damper = 3200f; wc.suspensionSpring = spring;
                var fc = wc.forwardFriction; fc.stiffness = 1.15f; wc.forwardFriction = fc;
                var sc = wc.sidewaysFriction; sc.stiffness = 1.5f; sc.extremumSlip = 0.18f; wc.sidewaysFriction = sc;
                wheels[i] = wc; vis[i] = vt;
            }
            Rb.centerOfMass = new Vector3(0f, -0.45f, 0f);
        }

        protected override void Update()
        {
            base.Update();
            for (int i = 0; i < 2; i++)
            {
                if (wheels[i] == null || vis[i] == null) continue;
                wheels[i].GetWorldPose(out var p, out var q);
                vis[i].SetPositionAndRotation(p, q);
                if (i == 0)
                {
                    var e = vis[i].localEulerAngles;
                    vis[i].localEulerAngles = new Vector3(e.x, wheels[i].steerAngle, e.z);
                }
            }
            // rider lean
            var ang = new Vector3(leanAngle * 0.35f, 0f, -leanAngle);
            transform.rotation = Rb.rotation * Quaternion.Euler(0f, 0f, 0f);
            var rig = Driver != null ? Driver.rig : null;
            if (rig != null && rig.IsRagdoll) { }
        }

        protected override void FixedUpdate()
        {
            base.FixedUpdate();
            if (wheels[0] == null) return;
            float dt = Time.fixedDeltaTime;
            bool driver = Driver != null;
            // "kickstand": a riderless, (almost) stationary two-wheeler stays as it is instead of toppling onto people
            var want = !driver && Rb.linearVelocity.sqrMagnitude < 2f ? (RigidbodyConstraints.FreezeRotationX | RigidbodyConstraints.FreezeRotationZ) : RigidbodyConstraints.None;
            if (!Rb.isKinematic && Rb.constraints != want) Rb.constraints = want;
            float torqueMul = mods.TorqueMul * DamageFactor;
            float topSpeed = (def != null ? def.topSpeed : 50f) * mods.TopSpeedMul;
            float grip = (def != null ? def.grip : 1.1f) * mods.GripMul * Weather.GripMul;

            bool bicycle = kind == VehicleKind.Bicycle;
            float throttleTarget = driver && engineOn ? Mathf.Clamp01(input.throttle) * (bicycle ? (input.boost ? 1f : 0.6f) : 1f) : 0f;
            if (driver && Driver.IsPlayer && input.brake > 0.1f && Speed < 0.8f) throttleTarget = -0.3f * input.brake;   // slow reverse for manoeuvring
            throttleSmooth = Mathf.MoveTowards(throttleSmooth, throttleTarget, dt * 2.5f);
            brakeSmooth = Mathf.MoveTowards(brakeSmooth, driver ? (throttleTarget < 0f ? 0f : Mathf.Clamp01(input.brake)) : 1f, dt * 5f);
            steerAngle = Mathf.MoveTowards(steerAngle, (driver ? input.steer : 0f) * 30f, 90f * dt);

            wheels[0].steerAngle = steerAngle;
            float maxSpin = topSpeed / Mathf.Max(wheels[1].radius, 0.05f) * 60f / (2f * Mathf.PI);
            float k = Mathf.Abs(wheels[1].rpm) / Mathf.Max(maxSpin * (throttleSmooth < 0f ? 0.2f : 1f), 1f);
            float t = throttleSmooth * (def != null ? def.torque : 200f) * 2.6f * torqueMul * (k < 0.75f ? 1f : Mathf.Clamp01((1f - k) / 0.25f));
            wheels[1].motorTorque = t;
            wheels[0].brakeTorque = brakeSmooth * (def != null ? def.brake * 0.5f : 1800f) * mods.BrakeMul + (throttleSmooth < 0.1f ? 40f : 0f);
            wheels[1].brakeTorque = brakeSmooth * (def != null ? def.brake * 0.5f : 1800f) * mods.BrakeMul;
            foreach (var w in wheels) { var sc = w.sidewaysFriction; sc.stiffness = Mathf.Lerp(sc.stiffness, 1.5f * grip, dt * 4f); w.sidewaysFriction = sc; }

            // self-righting: torque toward upright, more at speed
            var up = transform.up;
            float spd = Rb.linearVelocity.magnitude;
            float leanK = Mathf.Clamp01(spd / 8f);
            var axis = Vector3.Cross(up, Vector3.up);
            float angle = Vector3.Angle(up, Vector3.up);
            Rb.AddTorque(axis.normalized * (angle * Mathf.Deg2Rad * Rb.mass * (4f + leanK * 22f)) - Rb.angularVelocity * Rb.mass * 0.35f, ForceMode.Force);
            if (angle > 55f && spd < 6f && Time.time - lastPlayerContact > 1f) { Rb.AddForce(Vector3.up * Rb.mass * 3f); }

            // rider visual lean into the turn
            float targetLean = Mathf.Clamp(-steerAngle * 0.32f * Mathf.Clamp01(spd / 12f) - Rb.angularVelocity.y * 4f, -42f, 42f);
            leanAngle = Mathf.SmoothDamp(leanAngle, targetLean, ref leanVel, 0.25f);
            var rider = Driver;
            if (rider != null && rider.rig != null && rider.rig.valid && rider.rig.Chest != null)
            {
                var baseBasis = Rb.rotation;
                var lean = Quaternion.AngleAxis(leanAngle, transform.forward) * Quaternion.AngleAxis(steerAngle * 0.3f, Vector3.up);
                rider.rig.transform.rotation = baseBasis * lean;
                rider.rig.pose = CharPose.Riding;
            }
            if (ControllerSteer()) { }

            SetBrakeLights(brakeSmooth > 0.1f, Speed < -0.6f);
            rb.Stabilize(Rb, dt, spd);
        }

        static class rb { public static void Stabilize(Rigidbody r, float dt, float spd) { } }

        bool ControllerSteer() => false;

        public override void ToggleRoof() { }

        public override void Occupy(Actor a, int seat)
        {
            base.Occupy(a, seat);
            Rb.isKinematic = false;
        }
    }
}
