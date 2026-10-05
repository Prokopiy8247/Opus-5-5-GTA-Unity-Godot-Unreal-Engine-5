using UnityEngine;

namespace Halcyon
{
    /// <summary>Fixed-wing aircraft: throttle-driven propeller/jet, control surfaces, stall behaviour, landing gear steering.</summary>
    public class PlaneVehicle : Vehicle
    {
        Transform prop, gearRoot;
        Quaternion propRest = Quaternion.identity;
        float throttle, throttleLever, pitchIn, rollIn, yawIn, flap;
        public float ThrottleLever => throttleLever;
        float airspeed, lastGroundDust;
        float propSpin;
        float gearDrop = 1f;

        protected override void Awake()
        {
            base.Awake();
            Rb.linearDamping = 0.02f; Rb.angularDamping = 0.6f;
            Rb.centerOfMass = new Vector3(0f, -0.2f, 0f);
            // the airframe rests on its hull colliders (no wheel colliders): make them slide like rolling gear,
            // rolling resistance / side grip / brakes are applied in FixedUpdate instead
            var rolling = new PhysicsMaterial("PlaneGear") { dynamicFriction = 0.02f, staticFriction = 0.02f, frictionCombine = PhysicsMaterialCombine.Minimum, bounciness = 0f };
            foreach (var c in GetComponentsInChildren<Collider>()) if (!(c is WheelCollider)) c.sharedMaterial = rolling;
            foreach (var t in GetComponentsInChildren<Transform>(true))
            {
                var r = U.Role(t);
                if (r == "PROP") { prop = t; propRest = t.localRotation; }
                else if (r == "GEAR") gearRoot = t;
            }
        }

        protected override void Update()
        {
            base.Update();
            // spin about the model's nose axis, keeping the authored prop orientation
            if (prop != null) { propSpin += (0.4f + throttle * 9f) * Time.deltaTime * 9f; prop.localRotation = propRest * Quaternion.Euler(0f, 0f, propSpin * 57.3f); }
        }

        protected override void FixedUpdate()
        {
            base.FixedUpdate();
            float dt = Time.fixedDeltaTime;
            if (IsDestroyed) return;
            bool driver = Driver != null;
            bool jet = def != null && def.id == "jet";

            // SPACE / CTRL move a persistent throttle lever (W/S stay free for pitch)
            if (driver) throttleLever = Mathf.Clamp01(throttleLever + input.lift * dt * 0.6f); else throttleLever = 0f;
            float thrTarget = driver && engineOn ? throttleLever : 0f;
            if (driver && input.boost) thrTarget = Mathf.Min(1f, thrTarget + 0.25f);
            throttle = Mathf.MoveTowards(throttle, Mathf.Clamp01(thrTarget), dt * 0.5f);
            pitchIn = Mathf.MoveTowards(pitchIn, driver ? input.pitch : 0f, dt * 2.2f);   // stick convention: S = pull up, W = push down
            rollIn = Mathf.MoveTowards(rollIn, driver ? -input.roll : 0f, dt * 2.2f);
            yawIn = Mathf.MoveTowards(yawIn, driver ? input.yaw : 0f, dt * 2f);

            airspeed = Vector3.Dot(Rb.linearVelocity, transform.forward);
            float maxSpeed = (def != null ? def.topSpeed : 70f) * mods.TopSpeedMul;
            // thrust as an acceleration; quadratic drag tuned so full throttle levels off at the catalogue top speed
            float thrustAcc = jet ? 13f : 8.5f;
            Rb.AddForce(transform.forward * throttle * thrustAcc * DamageFactor * Rb.mass, ForceMode.Force);
            float cd = thrustAcc / Mathf.Max(maxSpeed * maxSpeed, 1f);
            var vel = Rb.linearVelocity;
            Rb.AddForce(-vel * (vel.magnitude * cd + 0.02f) * Rb.mass, ForceMode.Force);

            // lift: needs forward speed (stall below ~ 40% of max speed)
            float speedK = Mathf.Clamp01(Mathf.Abs(airspeed) / (maxSpeed * 0.55f));
            float liftK = speedK * speedK * (0.75f + flap * 0.5f);
            float lift = Rb.mass * 9.81f * liftK * (1f + Mathf.Clamp(airspeed / 20f, 0f, 1f) * 0.5f);
            Rb.AddForce(transform.up * lift, ForceMode.Force);
            // stall: mushy nose drop when too slow in the air
            // height above ground measured from the lowest point of the airframe (own colliders are on the Vehicle layer, excluded)
            float gd = Physics.Raycast(transform.position, Vector3.down, out var gh, 120f, Layers.World | (1 << Layers.Water), QueryTriggerInteraction.Ignore) ? gh.distance : 120f;
            bool airborne = gd > -bounds.min.y + 1.2f;
            if (airborne && speedK < 0.45f)
            {
                Rb.AddTorque(transform.right * -Rb.mass * 2.2f * (0.45f - speedK) * 3f, ForceMode.Force);
                if (driver && Driver.IsPlayer) HUD.Notify("STALL - add throttle", 1.2f);
            }

            // control surfaces: authority grows with airspeed, minimal on the ground
            float auth = airborne ? Mathf.Clamp01(speedK * 1.15f) : Mathf.Clamp01(Mathf.Abs(airspeed) / 12f) * 0.25f;
            Rb.AddTorque(transform.right * pitchIn * auth * Rb.mass * (jet ? 0.55f : 0.42f) * 10f, ForceMode.Force);
            Rb.AddTorque(transform.forward * rollIn * auth * Rb.mass * (jet ? 0.7f : 0.55f) * 10f, ForceMode.Force);
            Rb.AddTorque(transform.up * yawIn * auth * Rb.mass * 0.12f * 10f, ForceMode.Force);

            // yaw-to-turn assist (banked turns)
            float bank = Vector3.SignedAngle(Vector3.up, transform.up, transform.forward);
            if (airborne) Rb.AddTorque(transform.up * Mathf.Clamp(-bank * Mathf.Deg2Rad, -0.6f, 0.6f) * auth * Rb.mass * 1.6f, ForceMode.Force);

            // attitude damping
            Rb.AddTorque(-Rb.angularVelocity * (Rb.mass * (airborne ? 0.9f : 2.4f)), ForceMode.Force);

            // ground steering with the nose wheel; wheel brakes when the lever is closed and CTRL is held
            if (!airborne)
            {
                // tyre side grip + rolling resistance; parked/unmanned aircraft keep their brakes on
                Rb.AddForce(-transform.right * Vector3.Dot(Rb.linearVelocity, transform.right) * Rb.mass * 4f, ForceMode.Force);
                Rb.AddForce(-transform.forward * airspeed * Rb.mass * 0.03f, ForceMode.Force);
                if (!driver || (throttleLever < 0.02f && Mathf.Abs(airspeed) < 2f)) Rb.AddForce(-Rb.linearVelocity * Rb.mass * 1.5f, ForceMode.Force);
                if (driver && throttleLever < 0.02f && input.lift < -0.1f) Rb.AddForce(-Rb.linearVelocity * Rb.mass * 0.9f, ForceMode.Force);
                Rb.AddTorque(Vector3.up * (driver ? input.steer : 0f) * Rb.mass * 0.5f, ForceMode.Force);
                if (Mathf.Abs(airspeed) > 1f)
                {
                    lastGroundDust += dt;
                    if (lastGroundDust > 0.15f) { lastGroundDust = 0f; if (Mathf.Abs(airspeed) > 12f) VFX.Dust(transform.position + Vector3.down * gd, 0.6f, new Color(0.8f, 0.78f, 0.72f, 0.35f)); }
                }
            }

            Speed = airspeed;
            if (Driver != null && Driver.rig != null) Driver.rig.pose = CharPose.Driving;
            if (gearRoot != null) gearRoot.localScale = new Vector3(1f, Mathf.Lerp(gearRoot.localScale.y, gearDrop, dt * 3f), 1f);
        }

        protected override void OnCollisionEnter(Collision c)
        {
            float dv = c.impulse.magnitude / Mathf.Max(Rb.mass, 1f);
            if (dv > 3f) { ApplyDamage((dv - 3f) * 90f, null); PlayerCamera.I?.AddShake(0.7f); }
            base.OnCollisionEnter(c);
        }

        protected override void OnDestroyedVehicle() { throttle = 0f; }

        public void SetFlaps(float f) => flap = Mathf.Clamp01(f);
        public override void ToggleRoof() { }
    }
}
