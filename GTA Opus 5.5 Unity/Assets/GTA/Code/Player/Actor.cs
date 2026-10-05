using System;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Shared health/armor/faction/vehicle state for the player, NPCs and police.</summary>
    public class Actor : MonoBehaviour, IDamageable
    {
        public static readonly List<Actor> All = new List<Actor>();

        public Faction faction = Faction.Civilian;
        public float maxHealth = 100f, health = 100f, armor = 0f, maxArmor = 100f;
        public bool invulnerable;
        public float damageScale = 1f;
        public string displayName = "Citizen";

        [NonSerialized] public CharacterRig rig;
        [NonSerialized] public WeaponController weapons;
        [NonSerialized] public CharacterAppearance look;
        [NonSerialized] public Vehicle vehicle;
        [NonSerialized] public int seat = -1;
        [NonSerialized] public float lastDamageTime = -99f, lastAttackTime = -99f;
        [NonSerialized] public GameObject lastAttacker;
        [NonSerialized] public bool knockedDown;
        float knockUntil;

        public event Action<Actor, DamageInfo> Damaged;
        public event Action<Actor, DamageInfo> Died;
        public event Action<bool> RagdollChanged;

        public bool IsDead => health <= 0f;
        public bool IsPlayer => faction == Faction.Player;
        public bool InVehicle => vehicle != null;
        public Vector3 Center => rig != null && rig.IsRagdoll ? rig.Hips.position : transform.position + Vector3.up * 1.0f;
        public Vector3 HeadPos => rig != null && rig.valid ? rig.Head.position + Vector3.up * 0.1f : transform.position + Vector3.up * 1.7f;

        protected virtual void Awake()
        {
            rig = GetComponent<CharacterRig>();
            weapons = GetComponent<WeaponController>();
            look = GetComponent<CharacterAppearance>();
        }

        protected virtual void OnEnable() { if (!All.Contains(this)) All.Add(this); }
        protected virtual void OnDisable() { All.Remove(this); }

        public virtual void TakeDamage(DamageInfo d)
        {
            if (IsDead || invulnerable) return;
            float amt = d.amount * damageScale;
            if (d.headshot) amt *= IsPlayer ? 1.6f : 2.6f;
            if (armor > 0f && d.type != DamageType.Fall && d.type != DamageType.Drown && d.type != DamageType.Fire)
            {
                float absorb = Mathf.Min(armor, amt * 0.75f);
                armor -= absorb; amt -= absorb;
            }
            health -= amt;
            lastDamageTime = Time.time;
            if (d.attacker != null) lastAttacker = d.attacker;
            Damaged?.Invoke(this, d);
            if (rig != null && !rig.IsRagdoll) rig.PlayHit(d.direction);
            if (health <= 0f) { health = 0f; Die(d); return; }
            bool knock = d.heavy || d.type == DamageType.Explosion || (d.type == DamageType.Vehicle && d.force > 6f) || (d.type == DamageType.Melee && d.force > 7f);
            if (knock) Knockdown(d.direction.normalized * Mathf.Max(d.force, 4f) * 8f, d.point, d.type == DamageType.Explosion ? 3.2f : 2.2f);
        }

        public void Heal(float amount) { if (!IsDead) health = Mathf.Min(maxHealth, health + amount); }

        public virtual void Die(DamageInfo d)
        {
            health = 0f;
            if (vehicle != null) vehicle.EjectOccupant(this, true);
            Vector3 imp = d.direction.normalized * Mathf.Clamp(d.force * 10f + d.amount * 0.6f, 15f, 450f);
            if (rig != null) rig.EnableRagdoll(imp, d.point);
            SetCollidersForRagdoll(true);
            RagdollChanged?.Invoke(true);
            Died?.Invoke(this, d);
            WorldEvents.EmitKilled(this);
        }

        public void Knockdown(Vector3 impulse, Vector3 point, float duration)
        {
            if (IsDead || InVehicle || rig == null || !rig.valid) return;
            knockUntil = Time.time + duration;
            if (knockedDown) { rig.ApplyForceToRagdoll(impulse, point); return; }
            knockedDown = true;
            rig.EnableRagdoll(impulse, point);
            SetCollidersForRagdoll(true);
            RagdollChanged?.Invoke(true);
        }

        protected virtual void SetCollidersForRagdoll(bool ragdoll)
        {
            // never re-enable body colliders (incl. the CharacterController) while seated: they would become part of the vehicle
            if (!ragdoll && InVehicle) return;
            foreach (var c in GetComponents<Collider>()) c.enabled = !ragdoll;
        }

        /// <summary>End any knockdown immediately (teleport, entering a vehicle, respawn).</summary>
        public void ClearKnockdown()
        {
            bool was = knockedDown || (rig != null && rig.IsRagdoll);
            if (rig != null && rig.IsRagdoll) rig.DisableRagdoll();
            knockedDown = false;
            SetCollidersForRagdoll(false);
            if (was) RagdollChanged?.Invoke(false);
        }

        protected virtual void Update()
        {
            if (knockedDown && InVehicle) { knockedDown = false; return; }
            if (knockedDown && !IsDead && Time.time > knockUntil && rig.RagdollVelocity.magnitude < 0.8f)
            {
                knockedDown = false;
                rig.DisableRagdoll();
                SetCollidersForRagdoll(false);
                RagdollChanged?.Invoke(false);
            }
        }

        /// <summary>Resurrect in place (respawn / revive).</summary>
        public virtual void Revive(Vector3 pos, Quaternion rot)
        {
            if (rig != null && rig.IsRagdoll) rig.DisableRagdoll();
            knockedDown = false;
            transform.SetPositionAndRotation(pos, rot);
            health = maxHealth;
            SetCollidersForRagdoll(false);
            RagdollChanged?.Invoke(false);
        }

        public static Actor FromCollider(Collider c)
        {
            if (c == null) return null;
            return c.GetComponentInParent<Actor>();
        }
    }
}
