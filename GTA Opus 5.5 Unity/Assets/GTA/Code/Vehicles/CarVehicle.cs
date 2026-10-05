using UnityEngine;

namespace Halcyon
{
    /// <summary>WheelCollider-driven road car / pickup / van / truck.</summary>
    public class CarVehicle : Vehicle
    {
        WheelCollider[] wheels;
        Transform[] wheelVis;
        float[] wheelRadius;
        float steerAngle, throttleSmooth, brakeSmooth, handbrakeSmooth, rpm, skidTime;
        bool drifting;
        float airborneTime;

        protected override void Awake()
        {
            base.Awake();
            BuildWheels();
        }

        void BuildWheels()
        {
            var wcRoot = new GameObject("WheelColliders"); wcRoot.transform.SetParent(transform, false);
            var vis = new System.Collections.Generic.List<Transform>();
            foreach (var t in WheelVisuals()) vis.Add(t);
            wheels = new WheelCollider[vis.Count];
            wheelVis = new Transform[vis.Count];
            wheelRadius = new float[vis.Count];
            for (int i = 0; i < vis.Count; i++)
            {
                var vt = vis[i];
                var lp = transform.InverseTransformPoint(vt.position);
                var wgo = new GameObject("WC_" + U.Role(vt));
                wgo.transform.SetParent(wcRoot.transform, false);
                wgo.transform.localPosition = new Vector3(lp.x, lp.y, lp.z);
                var wc = wgo.AddComponent<WheelCollider>();
                var mr = vt.GetComponent<MeshRenderer>();
                float r = mr != null ? Mathf.Max(mr.localBounds.extents.y, mr.localBounds.extents.z) : 0.34f;
                float w = mr != null ? mr.localBounds.extents.x * 2f : 0.24f;
                bool front = lp.z > 0f;
                wc.radius = r;
                wc.mass = def != null ? Mathf.Max(20f, def.mass * 0.035f) : 40f;
                wc.suspensionDistance = Mathf.Clamp(r * 0.6f, 0.16f, 0.42f);
                var spring = wc.suspensionSpring;
                spring.spring = def != null ? Mathf.Clamp(def.mass * 22f, 26000f, 90000f) : 42000f;
                spring.damper = Mathf.Clamp(spring.spring * 0.22f, 1800f, 9000f);
                wc.suspensionSpring = spring;
                var fc = wc.forwardFriction; fc.stiffness = 1.05f; fc.extremumSlip = 0.32f; fc.extremumValue = 1f; fc.asymptoteSlip = 0.7f; fc.asymptoteValue = 0.62f; wc.forwardFriction = fc;
                var sc = wc.sidewaysFriction; sc.stiffness = 1.25f; sc.extremumSlip = 0.22f; sc.extremumValue = 0.9f; sc.asymptoteSlip = 0.6f; sc.asymptoteValue = 0.5f; wc.sidewaysFriction = sc;
                wheels[i] = wc; wheelVis[i] = vt; wheelRadius[i] = r;
            }
        }

        void Start()
        {
            if (Rb != null && def != null) Rb.centerOfMass = new Vector3(0f, def.comY, 0f);
        }

        protected override void Update()
        {
            base.Update();
            if (wheels == null) return;
            for (int i = 0; i < wheels.Length; i++)
            {
                if (wheels[i] == null || wheelVis[i] == null) continue;
                wheels[i].GetWorldPose(out var p, out var q);
                wheelVis[i].SetPositionAndRotation(p, q);
                if (U.Role(wheelVis[i]).StartsWith("WHEEL_F"))
                {
                    var steer = wheels[i].steerAngle;
                    var e = wheelVis[i].localEulerAngles;
                    wheelVis[i].localEulerAngles = new Vector3(e.x, steer, e.z);
                }
            }
        }

        protected override void FixedUpdate()
        {
            base.FixedUpdate();
            if (wheels == null || wheels.Length == 0 || IsDestroyed) { return; }
            float dt = Time.fixedDeltaTime;
            bool driver = Driver != null;
            float torqueMul = mods.TorqueMul * (1f + (Driver != null ? PlayerState.I.Get(Skill.Driving) * 0.1f : 0f)) * DamageFactor;
            float topSpeed = (def != null ? def.topSpeed : 45f) * mods.TopSpeedMul * (1f - (1f - DamageFactor) * 0.25f);
            float grip = (def != null ? def.grip : 1f) * mods.GripMul * Weather.GripMul * (1f - (1f - DamageFactor) * 0.2f);

            bool playerDriving = driver && Driver.IsPlayer;
            // AI drivers back up with negative throttle (stuck recovery); the player uses the brake key instead (below)
            float targetThrottle = driver ? (playerDriving ? Mathf.Clamp01(input.throttle) : Mathf.Clamp(input.throttle, -1f, 1f)) * (input.boost ? 1.25f : 1f) : (engineOn ? 0.12f : 0f);
            float targetBrake = driver ? Mathf.Clamp01(input.brake) : (engineOn ? 0f : 1f);
            // player reverse gear: holding brake at (near) standstill engages reverse; throttle while rolling back brakes
            if (playerDriving && input.brake > 0.1f && Speed < 1.2f) { targetThrottle = -0.55f * input.brake; targetBrake = 0f; }
            if (playerDriving && input.throttle > 0.1f && Speed < -0.8f) { targetThrottle = 0f; targetBrake = input.throttle; }
            if (!driver && def != null && def.police && engineOn) targetThrottle = 0f;
            if (Submerged) { targetThrottle = 0f; targetBrake = 1f; }
            throttleSmooth = Mathf.MoveTowards(throttleSmooth, targetThrottle, dt * 3f);
            brakeSmooth = Mathf.MoveTowards(brakeSmooth, targetBrake, dt * 5f);
            handbrakeSmooth = Mathf.MoveTowards(handbrakeSmooth, driver ? input.handbrake : (engineOn ? 0f : 1f), dt * 6f);

            float steerTarget = driver ? Mathf.Clamp(input.steer, -1f, 1f) : 0f;
            float speedSteer = Mathf.Lerp(1f, 0.4f, Mathf.Clamp01(Mathf.Abs(Speed) / 22f));
            float steerRate = Mathf.Abs(steerTarget) < 0.05f ? 5f : 3.2f;
            steerAngle = Mathf.MoveTowards(steerAngle, steerTarget * (def != null ? def.steer : 34f) * speedSteer * mods.SteerMul, steerRate * (def != null ? def.steer : 34f) * dt);

            // wheel layout: +z forward. def.torque is engine torque; GearMul folds in the final drive ratio.
            const float GearMul = 4.2f;
            int driven = 0;
            for (int i = 0; i < wheels.Length; i++)
            {
                bool f = wheels[i].transform.localPosition.z > 0f;
                if (def == null || def.drive == 2 || (def.drive == 0 ? f : !f)) driven++;
            }
            for (int i = 0; i < wheels.Length; i++)
            {
                var lp = wheels[i].transform.localPosition;
                bool front = lp.z > 0f;
                if (front) wheels[i].steerAngle = steerAngle;
                bool motor = def != null && def.drive == 2 ? true : (def != null && def.drive == 0 ? front : !front);
                float spin = wheels[i].rpm;
                float maxSpin = topSpeed / Mathf.Max(wheels[i].radius, 0.05f) * 60f / (2f * Mathf.PI);
                // flat torque up to 75 % of the governed wheel speed, then fade to zero at top speed
                float k = Mathf.Abs(spin) / Mathf.Max(maxSpin * (throttleSmooth < 0f ? 0.3f : 1f), 1f);
                float curve = k < 0.75f ? 1f : Mathf.Clamp01((1f - k) / 0.25f);
                float t = 0f;
                if (engineOn && motor) t = throttleSmooth * (def != null ? def.torque : 400f) * GearMul / Mathf.Max(driven, 1) * torqueMul * curve;
                if (Speed < -0.5f && throttleSmooth > 0.1f) t *= 0.4f;
                wheels[i].motorTorque = t;
                wheels[i].brakeTorque = (brakeSmooth * (def != null ? def.brake : 3600f) * mods.BrakeMul) + handbrakeSmooth * (motor ? 0f : 1f) * (def != null ? def.brake : 3600f) * 0.7f;
                // handbrake locks the rear
                if (handbrakeSmooth > 0.1f && !front) wheels[i].brakeTorque = (def != null ? def.brake : 3600f) * 0.85f;
                var sc = wheels[i].sidewaysFriction;
                float wantStiff = 1.25f * grip * (handbrakeSmooth > 0.2f && !front ? 0.45f : 1f) * (drifting && !front ? 0.7f : 1f);
                sc.stiffness = Mathf.Lerp(sc.stiffness, wantStiff, dt * 6f);
                wheels[i].sidewaysFriction = sc;
                var fc = wheels[i].forwardFriction;
                fc.stiffness = Mathf.Lerp(fc.stiffness, 1.05f * grip, dt * 6f);
                wheels[i].forwardFriction = fc;
            }

            // downforce & anti-roll
            float down = mods.DownforceMul * 6f * Mathf.Clamp01(Mathf.Abs(Speed) / topSpeed);
            Rb.AddForce(-transform.up * down * Rb.mass * Mathf.Clamp01(Mathf.Abs(Speed) / 8f));
            float roll = Mathf.Clamp(Vector3.Dot(Rb.angularVelocity, transform.forward) * 60f, -1.2f, 1.2f);
            Rb.AddTorque(-transform.forward * roll * Rb.mass * 0.12f);

            // engine rpm estimate for audio + burnout detection
            float avgSpin = 0f; int n = 0;
            foreach (var w in wheels) if (w != null) { avgSpin += Mathf.Abs(w.rpm); n++; }
            avgSpin = n > 0 ? avgSpin / n : 0f;
            rpm = Mathf.Clamp01(Mathf.Abs(Speed) / Mathf.Max(topSpeed, 1f));

            bool handDrift = handbrakeSmooth > 0.3f && Mathf.Abs(Speed) > 6f;
            drifting = handDrift || (avgSpin > Mathf.Abs(Speed) / 0.34f * 60f / (2f * Mathf.PI) * 1.5f && throttleSmooth > 0.6f);
            if ((drifting || handDrift) && Rb.linearVelocity.magnitude > 3f)
            {
                skidTime += dt;
                if (skidTime > 0.08f)
                {
                    skidTime = 0f;
                    for (int i = 0; i < wheels.Length; i++)
                        if (wheels[i].GetGroundHit(out var gh) && !U.Role(wheelVis[i]).StartsWith("WHEEL_F"))
                            VFX.SkidSmoke(gh.point + Vector3.up * 0.1f);
                    if (skidSrc != null && !skidSrc.isPlaying) skidSrc.Play();
                    if (skidSrc != null) skidSrc.volume = Mathf.Clamp01(Rb.linearVelocity.magnitude / 20f) * 0.5f * AudioFX.Sfx * AudioFX.Master;
                }
            }
            else if (skidSrc != null && skidSrc.isPlaying) skidSrc.volume = Mathf.MoveTowards(skidSrc.volume, 0f, dt * 2f);

            SetBrakeLights(brakeSmooth > 0.1f || handbrakeSmooth > 0.4f, Speed < -0.6f);
            airborneTime = wheels[0] != null && !wheels[0].isGrounded ? airborneTime + dt : 0f;
            if (airborneTime > 0.12f) Rb.AddForce(Physics.gravity * Rb.mass * -0.25f);
        }

        /// <summary>Wheel state summary for the autotest log.</summary>
        public string Diag()
        {
            if (wheels == null) return "no wheels";
            var sb = new System.Text.StringBuilder("wheels=" + wheels.Length);
            foreach (var w in wheels)
                if (w != null) sb.Append(" [").Append(U.Role(w.transform)).Append(" g=").Append(w.isGrounded ? 1 : 0).Append(" mt=").Append(w.motorTorque.ToString("F0"))
                    .Append(" bt=").Append(w.brakeTorque.ToString("F0")).Append(" rpm=").Append(w.rpm.ToString("F0")).Append(" r=").Append(w.radius.ToString("F2")).Append("]");
            sb.Append(" throttle=").Append(throttleSmooth.ToString("F2"));
            return sb.ToString();
        }

        protected override void OnCrash(float dv, ContactPoint cp)
        {
            if (dv > 5f) throttleSmooth = 0f;
        }

        public override void ToggleRoof()
        {
            if (def == null || !def.convertible) return;
            roofDown = !roofDown;
            var roof = U.FindRole(transform, "MOD_Roof_1");
            if (roof) roof.gameObject.SetActive(!roofDown);
            AudioFX.Play("ui", 0.4f);
        }
    }
}
