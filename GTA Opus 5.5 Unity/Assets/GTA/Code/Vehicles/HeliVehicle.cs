using UnityEngine;

namespace Halcyon
{
    /// <summary>Helicopter: collective lift, cyclic pitch/roll, yaw pedals, rotor wash and crash damage.</summary>
    public class HeliVehicle : Vehicle
    {
        Transform mainRotor, tailRotor;
        float rotorSpeed, collective, cyclicPitch, cyclicRoll, pedal, lastDust;
        float tiltPitch, tiltRoll;
        float maxHealthRef;

        Quaternion modelBase = Quaternion.identity;

        protected override void Awake()
        {
            base.Awake();
            Rb.linearDamping = 0.12f; Rb.angularDamping = 1.2f;
            Rb.centerOfMass = new Vector3(0f, -0.6f, 0f);
            modelBase = model != null ? model.localRotation : Quaternion.identity;
            foreach (var t in GetComponentsInChildren<Transform>(true))
            {
                var r = U.Role(t);
                if (r == "ROTOR_MAIN") mainRotor = t;
                else if (r == "ROTOR_TAIL") tailRotor = t;
            }
            if (mainRotor == null) foreach (var t in GetComponentsInChildren<Transform>(true)) if (t.name.ToLower().Contains("rotor_main")) mainRotor = t;
            VFX.Loop("rotordust", transform, new Vector3(0f, -1.4f, 0f)).Stop();
        }

        protected override void Update()
        {
            base.Update();
            if (mainRotor != null) mainRotor.localRotation *= Quaternion.Euler(0f, rotorSpeed * 720f * Time.deltaTime, 0f);
            if (tailRotor != null) tailRotor.localRotation *= Quaternion.Euler(rotorSpeed * 1500f * Time.deltaTime, 0f, 0f);

            float groundDist = Physics.Raycast(transform.position, Vector3.down, out var gh, 60f, Layers.Ground, QueryTriggerInteraction.Ignore) ? gh.distance : 60f;
            if (rotorSpeed > 0.5f && groundDist < 9f && Time.time - lastDust > 0.12f)
            {
                lastDust = Time.time;
                VFX.Dust(transform.position + Vector3.down * groundDist, 1.6f * (1f - groundDist / 9f), new Color(0.78f, 0.72f, 0.6f, 0.35f));
            }
        }

        protected override void FixedUpdate()
        {
            base.FixedUpdate();
            float dt = Time.fixedDeltaTime;
            if (IsDestroyed) return;
            bool driver = Driver != null;

            float target = engineOn ? (0.55f + collective * 0.45f) : 0f;
            rotorSpeed = Mathf.MoveTowards(rotorSpeed, target, dt * (engineOn ? 0.7f : 0.8f));

            float colInput = driver ? input.lift + Mathf.Clamp01(input.throttle) * 0.9f - Mathf.Clamp01(input.brake) * 0.9f : -0.15f;
            collective = Mathf.MoveTowards(collective, Mathf.Clamp(colInput, -1f, 1f), dt * 1.4f);
            cyclicPitch = Mathf.MoveTowards(cyclicPitch, driver ? input.pitch : 0f, dt * 2.5f);
            cyclicRoll = Mathf.MoveTowards(cyclicRoll, driver ? input.roll : 0f, dt * 2.5f);
            pedal = Mathf.MoveTowards(pedal, driver ? input.yaw : 0f, dt * 3f);

            float authority = rotorSpeed * rotorSpeed;
            float lift = (Rb.mass * 9.81f) * (0.55f + collective * 1.5f) * authority * DamageFactor * Mathf.Max(authority, 0.001f);
            Rb.AddForce(Vector3.up * lift, ForceMode.Force);
            // gentle stabilisation
            Rb.AddForce(-Rb.linearVelocity * (Rb.mass * (0.12f + (1f - authority) * 0.5f)), ForceMode.Force);
            // ground effect
            float gd = Physics.Raycast(transform.position, Vector3.down, out var gh2, 12f, Layers.Ground, QueryTriggerInteraction.Ignore) ? gh2.distance : 12f;
            if (gd < 6f && gd > 0.4f) Rb.AddForce(Vector3.up * Rb.mass * 9.81f * (1f - gd / 6f) * 0.28f, ForceMode.Force);

            // attitude: tilt toward the cyclic input (arcade)
            float desiredPitch = cyclicPitch * 22f * authority;
            float desiredRoll = -cyclicRoll * 24f * authority;
            tiltPitch = Mathf.MoveTowards(tiltPitch, desiredPitch, dt * 55f);
            tiltRoll = Mathf.MoveTowards(tiltRoll, desiredRoll, dt * 55f);
            var targetRot = Quaternion.Euler(tiltPitch, transform.eulerAngles.y, tiltRoll);
            Rb.MoveRotation(Quaternion.Slerp(Rb.rotation, targetRot, dt * 6f));
            Rb.AddTorque(Vector3.up * pedal * authority * Rb.mass * 0.85f, ForceMode.Force);
            Rb.AddTorque(-Vector3.Project(Rb.angularVelocity, Vector3.up) * Rb.mass * 1.1f * authority, ForceMode.Force);

            // forward translation from tilt
            var fwd = Vector3.ProjectOnPlane(-transform.up, Vector3.up).normalized;
            float fwdSpeed = Vector3.Dot(Rb.linearVelocity, fwd);
            float top = (def != null ? def.topSpeed : 55f) * mods.TopSpeedMul;
            if (gd > 1.2f) Rb.AddForce(fwd * Mathf.Clamp01(1f - fwdSpeed / top) * Rb.mass * 7f * authority, ForceMode.Force);

            // visual tilt of the body
            if (model != null && model != transform)
            {
                var baseRot = Quaternion.Inverse(transform.rotation) * Rb.rotation;
                // tilt on top of the imported model orientation (the prefab turns the FBX 180 deg, keep it)
                model.localRotation = Quaternion.Slerp(model.localRotation, Quaternion.Euler(cyclicPitch * 8f, 0f, -cyclicRoll * 10f) * modelBase, dt * 5f);
            }

            Speed = fwdSpeed;
            if (Driver != null && Driver.rig != null)
            {
                Driver.rig.pose = CharPose.Driving;
                if (steerL != null) { steerL.position = transform.position + transform.right * -0.22f + transform.up * 0.35f + transform.forward * 0.4f; steerR.position = transform.position + transform.right * 0.22f + transform.up * 0.35f + transform.forward * 0.4f; }
            }
        }

        protected override void OnCollisionEnter(Collision c)
        {
            float dv = c.impulse.magnitude / Mathf.Max(Rb.mass, 1f);
            if (dv > 4f)
            {
                ApplyDamage((dv - 4f) * 70f, null);
                PlayerCamera.I?.AddShake(0.6f);
                AudioFX.PlayAt("crash", c.GetContact(0).point, 0.9f);
                rotorSpeed *= 0.7f;
            }
            base.OnCollisionEnter(c);
        }

        protected override void OnDestroyedVehicle() { rotorSpeed = 0f; }
        public override void ToggleRoof() { }
    }
}
