using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Breakable / movable street furniture (bins, cones, barriers, hydrants): knocked loose by vehicles.</summary>
    public class DynamicProp : MonoBehaviour, IDamageable
    {
        public float mass = 30f, breakImpulse = 4f, health = 60f;
        public bool explosive, hydrant;
        bool loose;
        Rigidbody rb;

        void Awake() { rb = GetComponent<Rigidbody>(); if (rb != null) loose = true; }

        void OnCollisionEnter(Collision c)
        {
            if (loose) return;
            var v = c.collider.GetComponentInParent<Vehicle>();
            if (v == null) return;
            if (c.relativeVelocity.magnitude > breakImpulse) Loosen(c.relativeVelocity * 0.6f);
        }

        void Loosen(Vector3 vel)
        {
            loose = true;
            gameObject.isStatic = false;
            rb = GetComponent<Rigidbody>() ?? gameObject.AddComponent<Rigidbody>();
            rb.mass = mass;
            rb.linearVelocity = vel;
            rb.angularVelocity = Random.insideUnitSphere * 4f;
            gameObject.layer = Layers.Debris;
            AudioFX.PlayAt("hit_metal", transform.position, 0.5f, Random.Range(0.8f, 1.2f));
            if (hydrant) { VFX.Splash(transform.position + Vector3.up * 0.5f, 1.4f); InvokeRepeating(nameof(Spray), 0f, 0.15f); Invoke(nameof(StopSpray), 8f); }
            Destroy(gameObject, 40f);
        }

        void Spray() => VFX.Splash(transform.position + Vector3.up * 0.6f, 0.8f);
        void StopSpray() => CancelInvoke(nameof(Spray));

        public void TakeDamage(DamageInfo d)
        {
            health -= d.amount;
            if (!loose && (d.type == DamageType.Explosion || health <= 0f)) Loosen(d.direction * Mathf.Max(d.force, 3f));
            if (explosive && health <= 0f)
            {
                explosive = false;
                Explosion.Create(transform.position + Vector3.up * 0.5f, 6f, 140f, d.attacker);
                Destroy(gameObject, 0.05f);
            }
            else if (loose && rb != null) rb.AddForceAtPosition(d.direction * Mathf.Max(d.force, 1f) * 2f, d.point, ForceMode.Impulse);
        }
    }
}
