using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Rockets, launcher grenades and thrown grenades.</summary>
    public class Projectile : MonoBehaviour
    {
        WeaponDef def; GameObject owner; Rigidbody rb;
        float life, fuse = 3f; bool impact, done;
        ParticleSystem trail;

        public static void Spawn(WeaponDef w, Vector3 pos, Quaternion rot, GameObject owner, Rigidbody inherit)
        {
            bool rocket = w.id == "rpg";
            var g = MakeBody(rocket ? "WPN_RocketLauncher" : "WPN_Grenade", rocket ? "ROCKET" : null, pos, rot, rocket ? 0.09f : 0.06f);
            var p = g.AddComponent<Projectile>();
            p.def = w; p.owner = owner; p.impact = true;
            p.rb = g.GetComponent<Rigidbody>();
            p.rb.useGravity = !rocket;
            p.rb.linearVelocity = rot * Vector3.forward * w.projSpeed + (rocket ? Vector3.zero : Vector3.up * 1.5f) + (inherit != null ? inherit.linearVelocity : Vector3.zero);
            p.IgnoreOwner();
            p.trail = VFX.Trail(g.transform, rocket);
            if (rocket) AudioFX.Attach(g, "rocket", 0.6f, true);
        }

        public static void SpawnGrenade(Vector3 pos, Vector3 vel, GameObject owner, WeaponDef w)
        {
            var g = MakeBody("WPN_Grenade", null, pos, Random.rotation, 0.06f);
            var p = g.AddComponent<Projectile>();
            p.def = w; p.owner = owner; p.impact = false; p.fuse = 3f;
            p.rb = g.GetComponent<Rigidbody>();
            p.rb.linearVelocity = vel; p.rb.angularVelocity = Random.insideUnitSphere * 10f;
            var pm = new PhysicsMaterial { bounciness = 0.35f, dynamicFriction = 0.6f, staticFriction = 0.6f, bounceCombine = PhysicsMaterialCombine.Maximum };
            g.GetComponent<Collider>().sharedMaterial = pm;
            p.IgnoreOwner();
        }

        static GameObject MakeBody(string prefabId, string role, Vector3 pos, Quaternion rot, float radius)
        {
            GameObject g;
            var prefab = GameDatabase.I != null ? GameDatabase.I.Get(prefabId) : null;
            Transform part = prefab != null && role != null ? U.FindRole(prefab.transform, role) : null;
            if (part != null) { g = new GameObject("Projectile"); var vis = Instantiate(part.gameObject, g.transform); vis.transform.localPosition = Vector3.zero; vis.transform.localRotation = Quaternion.Inverse(prefab.transform.rotation) * part.rotation; }
            else if (prefab != null) { g = new GameObject("Projectile"); var vis = Instantiate(prefab, g.transform); vis.transform.localPosition = Vector3.zero; foreach (var c in vis.GetComponentsInChildren<Collider>()) Destroy(c); }
            else { g = GameObject.CreatePrimitive(PrimitiveType.Sphere); g.transform.localScale = Vector3.one * radius * 2f; Destroy(g.GetComponent<Collider>()); }
            g.transform.SetPositionAndRotation(pos, rot);
            g.layer = Layers.Projectile;
            var sc = g.AddComponent<SphereCollider>(); sc.radius = radius;
            var rb = g.AddComponent<Rigidbody>(); rb.mass = 1.5f; rb.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic; rb.interpolation = RigidbodyInterpolation.Interpolate;
            return g;
        }

        void IgnoreOwner()
        {
            var mine = GetComponent<Collider>();
            if (owner == null) return;
            foreach (var c in owner.GetComponentsInChildren<Collider>()) Physics.IgnoreCollision(mine, c);
            var a = owner.GetComponent<Actor>();
            if (a != null && a.InVehicle) foreach (var c in a.vehicle.GetComponentsInChildren<Collider>()) Physics.IgnoreCollision(mine, c);
        }

        void Update()
        {
            life += Time.deltaTime;
            if (rb != null && !rb.useGravity && rb.linearVelocity.sqrMagnitude > 1f) transform.rotation = Quaternion.LookRotation(rb.linearVelocity);
            if ((!impact && life > fuse) || life > 10f) Explode();
            if (transform.position.y < Water.Level - 0.5f && Water.IsWater(transform.position)) { if (!impact) { VFX.Splash(transform.position, 0.6f); } Explode(); }
        }

        void OnCollisionEnter(Collision c)
        {
            if (impact && life > 0.03f) Explode();
            else if (c.relativeVelocity.magnitude > 2f) AudioFX.PlayAt("hit_metal", transform.position, 0.25f, 1.6f);
        }

        void Explode()
        {
            if (done) return;
            done = true;
            if (trail != null) { trail.transform.SetParent(null); trail.Stop(); Destroy(trail.gameObject, 3f); }
            Explosion.Create(transform.position, def.blast, def.damage, owner);
            Destroy(gameObject);
        }
    }

    public static class Explosion
    {
        static readonly Collider[] buf = new Collider[256];

        public static void Create(Vector3 pos, float radius, float damage, GameObject attacker, bool fromVehicle = false)
        {
            VFX.Explosion(pos, radius);
            AudioFX.PlayAt("explosion", pos, 1f, Random.Range(0.85f, 1.05f), 400f);
            WorldEvents.EmitExplosion(pos, radius);
            WorldEvents.EmitNoise(pos, 170f, attacker);
            if (attacker != null && attacker.GetComponent<PlayerController>() != null) WorldEvents.EmitCrime(CrimeType.Explosion, pos, attacker);
            if (PlayerCamera.I != null)
            {
                float d = Vector3.Distance(PlayerCamera.I.transform.position, pos);
                PlayerCamera.I.AddShake(Mathf.Clamp01(1.2f - d / (radius * 6f)));
            }
            int n = Physics.OverlapSphereNonAlloc(pos, radius, buf, ~(1 << Layers.Trigger), QueryTriggerInteraction.Ignore);
            var seen = new HashSet<Object>();
            for (int i = 0; i < n; i++)
            {
                var c = buf[i];
                float dist = Vector3.Distance(pos, U.SafeClosestPoint(c, pos));
                float k = Mathf.Clamp01(1f - dist / radius);
                var a = c.GetComponentInParent<Actor>();
                if (a != null)
                {
                    if (seen.Contains(a)) continue; seen.Add(a);
                    if (!U.LineOfSight(pos + Vector3.up * 0.3f, a.Center, null, a.transform, Layers.World)) k *= 0.35f;
                    var dir = (a.Center - pos).normalized + Vector3.up * 0.6f;
                    a.TakeDamage(new DamageInfo { amount = damage * k * k + 10f * k, type = DamageType.Explosion, point = a.Center, direction = dir, attacker = attacker, force = 14f * k, heavy = k > 0.2f });
                    if (a.rig != null && a.rig.IsRagdoll) a.rig.ApplyForceToRagdoll(dir * 120f * k, pos);
                    continue;
                }
                var v = c.GetComponentInParent<Vehicle>();
                if (v != null)
                {
                    if (seen.Contains(v)) continue; seen.Add(v);
                    v.ExplosionHit(pos, damage * k * (fromVehicle ? 0.8f : 1.6f), radius, attacker);
                    continue;
                }
                var dm = c.GetComponentInParent<IDamageable>();
                if (dm != null && !seen.Contains((Object)dm)) { seen.Add((Object)dm); dm.TakeDamage(DamageInfo.Make(damage * k, DamageType.Explosion, c.transform.position, (c.transform.position - pos).normalized, attacker, 10f * k)); }
                var rb = c.attachedRigidbody;
                if (rb != null && !rb.isKinematic && !seen.Contains(rb)) { seen.Add(rb); rb.AddExplosionForce(Mathf.Min(damage * 8f, 2500f) * Mathf.Clamp(rb.mass / 40f, 0.2f, 4f), pos, radius * 1.4f, 1.2f, ForceMode.Impulse); }
            }
        }
    }
}
