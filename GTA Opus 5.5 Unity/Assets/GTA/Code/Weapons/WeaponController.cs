using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    [Serializable]
    public class WeaponMods
    {
        public bool suppressor, scope, grip, extMag, flashlight;
        public int tint;
        public static readonly string[] Tints = { "#32363b", "#c9a227", "#556b2f", "#8b5a2b", "#e5e5e5", "#c1121f", "#1d3557" };
    }

    /// <summary>Weapon inventory + firing/melee/throw logic shared by the player and AI shooters.</summary>
    public class WeaponController : MonoBehaviour
    {
        public Actor owner;
        CharacterRig rig;
        public bool isPlayer, infiniteAmmo;
        public float accuracyMul = 1f, damageMul = 1f;

        public readonly List<string> owned = new List<string> { "fists" };
        public readonly Dictionary<string, int> clip = new Dictionary<string, int>();
        public readonly Dictionary<string, int> reserve = new Dictionary<string, int>();
        public readonly Dictionary<string, WeaponMods> mods = new Dictionary<string, WeaponMods>();

        public string currentId = "fists";
        public WeaponDef Current => WeaponCatalog.Get(currentId);
        public WeaponMods CurrentMods => GetMods(currentId);
        public float ScopeZoom = 1f;
        public bool Reloading => Time.time < reloadUntil;
        public float LastShotTime { get; private set; } = -99f;

        GameObject model; Transform muzzle, foregrip;
        readonly List<GameObject> attachments = new List<GameObject>();
        Light flashLight;
        float nextFire, reloadUntil, bloom;
        int combo;
        bool holstered, visible = true;
        static readonly RaycastHit[] hitBuf = new RaycastHit[24];

        public static readonly WeaponClass[] SlotClasses = { WeaponClass.Melee, WeaponClass.Pistol, WeaponClass.SMG, WeaponClass.Shotgun, WeaponClass.Rifle, WeaponClass.Sniper, WeaponClass.Heavy, WeaponClass.Thrown };

        void Awake()
        {
            owner = GetComponent<Actor>();
            rig = GetComponent<CharacterRig>();
        }

        public WeaponMods GetMods(string id)
        {
            if (!mods.TryGetValue(id, out var m)) { m = new WeaponMods(); mods[id] = m; }
            return m;
        }

        public int MagSize(WeaponDef w) => Mathf.RoundToInt(w.mag * (GetMods(w.id).extMag && w.canExtMag ? 1.6f : 1f));
        public int Clip => clip.TryGetValue(currentId, out var c) ? c : 0;
        public int Reserve => reserve.TryGetValue(currentId, out var r) ? r : 0;

        public void Give(string id, int ammo, bool equip = false)
        {
            var w = WeaponCatalog.Get(id);
            if (w == null) return;
            if (!owned.Contains(id)) { owned.Add(id); clip[id] = w.IsMelee ? 0 : Mathf.Min(MagSize(w), Mathf.Max(ammo, 0)); ammo -= clip[id]; }
            if (!w.IsMelee)
            {
                reserve.TryGetValue(id, out var r);
                reserve[id] = Mathf.Clamp(r + Mathf.Max(ammo, 0), 0, Mathf.Max(w.maxAmmo, 1));
            }
            if (equip) Equip(id);
        }

        public void RefillAll()
        {
            foreach (var id in owned)
            {
                var w = WeaponCatalog.Get(id);
                if (w == null || w.IsMelee) continue;
                clip[id] = MagSize(w); reserve[id] = w.maxAmmo;
            }
        }

        public void Equip(string id)
        {
            if (!owned.Contains(id)) return;
            currentId = id;
            reloadUntil = 0f; bloom = 0f; ScopeZoom = 1f;
            BuildModel();
        }

        public void SelectSlot(int slot)
        {
            if (slot < 0 || slot >= SlotClasses.Length) return;
            var cls = SlotClasses[slot];
            var list = owned.FindAll(id => WeaponCatalog.Get(id).cls == cls);
            if (list.Count == 0) return;
            int i = list.IndexOf(currentId);
            Equip(list[(i + 1) % list.Count]);
            AudioFX.Play("ui", 0.2f);
        }

        public void Cycle(int dir)
        {
            if (owned.Count == 0) return;
            int i = owned.IndexOf(currentId);
            i = (i + dir + owned.Count) % owned.Count;
            Equip(owned[i]);
        }

        public void Holster(bool h) { holstered = h; ApplyVisibility(); }
        public void SetVisible(bool v) { visible = v; ApplyVisibility(); }
        void ApplyVisibility() { if (model) model.SetActive(!holstered && visible); }

        void BuildModel()
        {
            if (model) Destroy(model);
            attachments.Clear(); muzzle = null; foregrip = null; flashLight = null;
            var w = Current;
            if (w == null || string.IsNullOrEmpty(w.model) || GameDatabase.I == null) { rig.weapon = null; rig.hold = w != null ? w.hold : HoldType.Unarmed; return; }
            var prefab = GameDatabase.I.Get(w.model);
            if (prefab == null) { rig.weapon = null; rig.hold = w.hold; return; }
            model = Instantiate(prefab);
            model.name = w.model + "_held";
            foreach (var c in model.GetComponentsInChildren<Collider>()) Destroy(c);
            foreach (var r in model.GetComponentsInChildren<Rigidbody>()) Destroy(r);
            Layers.SetRecursive(model, isPlayer ? Layers.Player : Layers.NPC);
            muzzle = U.FindRole(model.transform, "MUZZLE");
            foregrip = U.FindRole(model.transform, "FOREGRIP");
            rig.weapon = model.transform; rig.weaponGrip = null; rig.weaponForegrip = w.hold == HoldType.TwoHand || w.hold == HoldType.Shoulder ? foregrip : null;
            rig.hold = w.hold;
            ApplyMods();
            ApplyVisibility();
        }

        public void ApplyMods()
        {
            if (!model) return;
            foreach (var a in attachments) if (a) Destroy(a);
            attachments.Clear();
            var w = Current; var m = CurrentMods;
            var kit = GameDatabase.I != null ? GameDatabase.I.Get("WPN_Attachments") : null;
            void Attach(string role, string socket)
            {
                if (kit == null) return;
                var src = U.FindRole(kit.transform, role);
                var s = U.FindRole(model.transform, socket);
                if (src == null || s == null) return;
                var g = Instantiate(src.gameObject, s);
                // sockets and attachment meshes share the Blender export frame, so identity local pose aligns them
                g.transform.localPosition = Vector3.zero; g.transform.localRotation = Quaternion.identity; g.transform.localScale = Vector3.one;
                Layers.SetRecursive(g, model.layer);
                attachments.Add(g);
            }
            if (m.suppressor && w.canSuppress) Attach("ATT_Suppressor", "MUZZLE");
            if (m.scope && w.canScope) Attach("ATT_Scope", "ATT_SCOPE");
            if (m.grip && w.canGrip) Attach("ATT_Grip", "ATT_GRIP");
            if (m.flashlight && w.canLight)
            {
                Attach("ATT_Flashlight", "ATT_LIGHT");
                var s = U.FindRole(model.transform, "ATT_LIGHT") ?? muzzle;
                if (s != null)
                {
                    var lg = new GameObject("Flashlight"); lg.transform.SetParent(model.transform, false);
                    lg.transform.position = s.position; lg.transform.rotation = model.transform.rotation;
                    flashLight = lg.AddComponent<Light>(); flashLight.type = LightType.Spot; flashLight.range = 28f; flashLight.spotAngle = 38f; flashLight.intensity = 18f; flashLight.color = new Color(1f, 0.96f, 0.88f);
                    flashLight.shadows = LightShadows.None;
                }
            }
            var tint = U.Hex(WeaponMods.Tints[Mathf.Clamp(m.tint, 0, WeaponMods.Tints.Length - 1)]);
            foreach (var r in model.GetComponentsInChildren<Renderer>())
            {
                var mats = r.materials;
                foreach (var mt in mats) if (mt.name.StartsWith("M_GunMetal") || mt.name.StartsWith("M_GunPolymer")) mt.SetColor("_BaseColor", mt.name.StartsWith("M_GunMetal") ? tint : Color.Lerp(tint, Color.black, 0.35f));
                r.materials = mats;
            }
        }

        void Update()
        {
            bloom = Mathf.MoveTowards(bloom, 0f, Time.deltaTime * 6f);
            if (flashLight) flashLight.enabled = rig != null && rig.aiming && model.activeInHierarchy;
        }

        // ------------------------------------------------------------------ guns
        public bool Fire(Vector3 aimPoint, float spreadMul, bool aimed)
        {
            var w = Current;
            if (w == null || w.IsMelee || holstered) return false;
            if (w.cls == WeaponClass.Thrown) { Throw(aimPoint); return true; }
            if (Time.time < nextFire || Reloading) return false;
            if (Clip <= 0)
            {
                if (Reserve > 0 || infiniteAmmo) Reload(); else { AudioFX.PlayAt("dry", transform.position, 0.4f); nextFire = Time.time + 0.3f; }
                return false;
            }
            var m = CurrentMods;
            nextFire = Time.time + 1f / w.fireRate;
            clip[currentId] = Clip - 1;
            LastShotTime = Time.time;
            owner.lastAttackTime = Time.time;
            Vector3 origin = muzzle != null && model.activeInHierarchy ? muzzle.position : owner.HeadPos + transform.forward * 0.3f;
            // never shoot through a wall the muzzle is poking into
            var chest = owner.rig != null && owner.rig.valid ? owner.rig.Chest.position : owner.HeadPos;
            if (Physics.Linecast(chest, origin, out var block, Layers.World, QueryTriggerInteraction.Ignore)) origin = block.point - (origin - chest).normalized * 0.05f;
            Vector3 baseDir = (aimPoint - origin).normalized;
            float spread = (aimed ? w.aimSpread : w.hipSpread) * spreadMul * accuracyMul + bloom;
            if (m.grip && w.canGrip) spread *= 0.8f;
            if (m.scope && w.canScope && aimed) spread *= 0.7f;
            float dmg = w.damage * damageMul * (m.suppressor && w.canSuppress ? 0.93f : 1f);

            if (w.projectile)
            {
                var rot = Quaternion.LookRotation(Spread(baseDir, spread));
                Projectile.Spawn(w, origin + baseDir * 0.4f, rot, gameObject, owner.InVehicle ? owner.vehicle.Rb : null);
            }
            else
            {
                for (int p = 0; p < w.pellets; p++) Hitscan(origin, Spread(baseDir, spread), w.range, dmg, w);
            }

            float recoil = w.recoil * (m.grip && w.canGrip ? 0.7f : 1f);
            bloom = Mathf.Min(bloom + recoil * 0.22f, 6f);
            bool sup = m.suppressor && w.canSuppress;
            VFX.MuzzleFlash(origin, baseDir, sup ? 0.35f : (w.cls == WeaponClass.Shotgun || w.cls == WeaponClass.Sniper ? 1.6f : 1f));
            AudioFX.PlayAt(sup ? "shot_sup" : ShotSound(w), origin, sup ? 0.5f : 1f, UnityEngine.Random.Range(0.94f, 1.06f));
            WorldEvents.EmitNoise(origin, sup ? 12f : w.noise, gameObject);
            if (isPlayer)
            {
                var ps = PlayerState.I;
                float k = Mathf.Lerp(1f, 0.6f, ps != null ? ps.Get(Skill.Shooting) : 0f);
                var cam = PlayerCamera.I;
                if (cam) { cam.pitch -= recoil * k * UnityEngine.Random.Range(0.6f, 1f); cam.yaw += recoil * k * UnityEngine.Random.Range(-0.35f, 0.35f); cam.AddShake(Mathf.Min(0.08f + recoil * 0.02f, 0.3f)); }
                if (!sup || UnityEngine.Random.value < 0.15f) WorldEvents.EmitCrime(CrimeType.Gunfire, origin, gameObject);
            }
            if (Clip == 0 && (Reserve > 0 || infiniteAmmo)) StartCoroutine(AutoReload());
            return true;
        }

        IEnumerator AutoReload() { yield return new WaitForSeconds(0.2f); Reload(); }

        static string ShotSound(WeaponDef w)
        {
            switch (w.cls)
            {
                case WeaponClass.Pistol: return w.id == "revolver" ? "shot_heavy" : "shot_pistol";
                case WeaponClass.SMG: return "shot_smg";
                case WeaponClass.Shotgun: return "shot_shotgun";
                case WeaponClass.Sniper: return "shot_sniper";
                case WeaponClass.Heavy: return "launch";
                default: return "shot_rifle";
            }
        }

        static Vector3 Spread(Vector3 dir, float deg)
        {
            if (deg <= 0f) return dir;
            var c = UnityEngine.Random.insideUnitCircle * deg;
            var rot = Quaternion.LookRotation(dir);
            return rot * Quaternion.Euler(c.y, c.x, 0f) * Vector3.forward;
        }

        void Hitscan(Vector3 origin, Vector3 dir, float range, float damage, WeaponDef w)
        {
            int n = Physics.RaycastNonAlloc(origin, dir, hitBuf, range, Layers.Shootable, QueryTriggerInteraction.Ignore);
            Array.Sort(hitBuf, 0, n, HitComparer.I);
            Vector3 end = origin + dir * range;
            int penetrations = 0;
            for (int i = 0; i < n; i++)
            {
                var h = hitBuf[i];
                var t = h.collider.transform;
                if (t.IsChildOf(transform)) continue;
                if (owner.InVehicle && t.IsChildOf(owner.vehicle.transform)) continue;
                end = h.point;
                float falloff = Mathf.Lerp(1f, 0.55f, h.distance / range);
                bool stop = ApplyHit(h, dir, damage * falloff * (penetrations > 0 ? 0.5f : 1f), w);
                if (stop || penetrations >= 1) break;
                penetrations++;
            }
            VFX.Tracer(origin, end);
            if (end.y < Water.Level && origin.y > Water.Level) VFX.Splash(origin + dir * ((Water.Level - origin.y) / Mathf.Min(dir.y, -0.001f)), 0.25f);
            WorldEvents.EmitNoise(end, 6f, gameObject);
        }

        /// <summary>Returns true if the bullet stops here.</summary>
        bool ApplyHit(RaycastHit h, Vector3 dir, float damage, WeaponDef w)
        {
            var actor = h.collider.GetComponentInParent<Actor>();
            if (actor != null)
            {
                if (actor == owner) return false;
                bool head = actor.rig != null && actor.rig.valid && (h.point.y > actor.rig.Head.position.y - 0.02f || h.collider.transform == actor.rig.Head);
                var d = new DamageInfo { amount = damage, type = DamageType.Bullet, point = h.point, direction = dir, attacker = gameObject, force = w.knock * (w.cls == WeaponClass.Shotgun ? 3f : 1.5f), headshot = head };
                bool wasAlive = !actor.IsDead;
                actor.TakeDamage(d);
                if (actor.IsDead && actor.rig != null) actor.rig.ApplyForceToRagdoll(dir * (w.knock * 25f), h.point);
                VFX.Impact(h.point, h.normal, Surface.Flesh);
                if (isPlayer && wasAlive)
                {
                    HUD.HitMarker(actor.IsDead);
                    PlayerState.I?.Train(Skill.Shooting, 0.003f);
                    if (actor.faction == Faction.Police) WorldEvents.EmitCrime(actor.IsDead ? CrimeType.KillCop : CrimeType.AssaultCop, h.point, gameObject);
                    else if (actor.faction != Faction.Animal) WorldEvents.EmitCrime(actor.IsDead ? CrimeType.Murder : CrimeType.Assault, h.point, gameObject);
                }
                return true;
            }
            var veh = h.collider.GetComponentInParent<Vehicle>();
            if (veh != null)
            {
                veh.BulletHit(h.point, dir, damage, gameObject);
                VFX.Impact(h.point, h.normal, Surface.Metal);
                return h.collider.name.Contains("Glass") ? false : UnityEngine.Random.value < 0.75f;
            }
            var dmg = h.collider.GetComponentInParent<IDamageable>();
            dmg?.TakeDamage(new DamageInfo { amount = damage, type = DamageType.Bullet, point = h.point, direction = dir, attacker = gameObject, force = w.knock });
            if (h.rigidbody != null && !h.rigidbody.isKinematic) h.rigidbody.AddForceAtPosition(dir * w.knock * 4f, h.point, ForceMode.Impulse);
            var surf = Surfaces.Of(h.collider);
            VFX.Impact(h.point, h.normal, surf);
            if (surf == Surface.Glass) return false;
            if (h.collider.gameObject.isStatic || h.rigidbody == null) VFX.BulletHole(h.point, h.normal, h.collider.transform);
            return true;
        }

        class HitComparer : IComparer<RaycastHit>
        {
            public static readonly HitComparer I = new HitComparer();
            public int Compare(RaycastHit a, RaycastHit b) => a.distance.CompareTo(b.distance);
        }

        public void Reload()
        {
            var w = Current;
            if (w == null || w.IsMelee || w.cls == WeaponClass.Thrown || Reloading) return;
            int need = MagSize(w) - Clip;
            if (need <= 0) return;
            if (!infiniteAmmo && Reserve <= 0) return;
            float t = w.reload * (isPlayer ? Mathf.Lerp(1f, 0.75f, PlayerState.I != null ? PlayerState.I.Get(Skill.Shooting) : 0f) : 1.15f);
            reloadUntil = Time.time + t;
            rig?.PlayReload(t);
            AudioFX.PlayAt("reload", transform.position, 0.5f);
            StartCoroutine(FinishReload(currentId, t));
        }

        IEnumerator FinishReload(string id, float t)
        {
            yield return new WaitForSeconds(t);
            if (id != currentId) yield break;
            var w = WeaponCatalog.Get(id);
            int need = MagSize(w) - Clip;
            int take = infiniteAmmo ? need : Mathf.Min(need, Reserve);
            clip[id] = Clip + take;
            if (!infiniteAmmo) reserve[id] = Reserve - take;
        }

        // ------------------------------------------------------------------ melee
        public void Melee(bool heavy, Vector3 dir)
        {
            var w = Current ?? WeaponCatalog.Get("fists");
            if (Time.time < nextFire) return;
            nextFire = Time.time + (1f / w.fireRate) * (heavy ? 1.6f : 1f);
            int kind = w.hold == HoldType.Unarmed ? (heavy ? 3 : (combo++ % 2 == 0 ? 1 : 2)) : 4;
            float dur = heavy ? 0.62f : (w.hold == HoldType.Unarmed ? 0.36f : 0.5f);
            rig?.PlayAction(kind, dur);
            owner.lastAttackTime = Time.time;
            AudioFX.PlayAt("swing", transform.position, 0.4f, UnityEngine.Random.Range(0.9f, 1.15f));
            StartCoroutine(MeleeStrike(w, heavy, dur * 0.36f));
        }

        IEnumerator MeleeStrike(WeaponDef w, bool heavy, float delay)
        {
            yield return new WaitForSeconds(delay);
            if (owner.IsDead || (rig != null && rig.IsRagdoll)) yield break;
            var center = transform.position + Vector3.up * 1.1f + transform.forward * (w.meleeRange * 0.55f);
            var cols = Physics.OverlapSphere(center, w.meleeRange * 0.5f + 0.25f, Layers.Actors | (1 << Layers.Ragdoll) | (1 << Layers.Vehicle) | (1 << Layers.Prop), QueryTriggerInteraction.Ignore);
            var done = new HashSet<object>();
            float strength = isPlayer && PlayerState.I != null ? Mathf.Lerp(1f, 1.5f, PlayerState.I.Get(Skill.Strength)) : 1f;
            foreach (var c in cols)
            {
                var a = c.GetComponentInParent<Actor>();
                if (a != null)
                {
                    if (a == owner || done.Contains(a) || a.IsDead && !a.rig.IsRagdoll) continue;
                    done.Add(a);
                    var d = U.Flat(a.transform.position - transform.position).normalized + Vector3.up * 0.25f;
                    bool blocked = a.rig != null && a.rig.blocking && Vector3.Dot(a.transform.forward, -d) > 0.3f;
                    float dmg = w.damage * (heavy ? 1.8f : 1f) * strength * damageMul * (blocked ? 0.3f : 1f);
                    float force = blocked ? 0f : (heavy ? 9f : 3f) * w.knock * strength;
                    bool fromBehind = Vector3.Dot(a.transform.forward, d) > 0.5f;
                    if (fromBehind) dmg *= 1.4f;
                    a.TakeDamage(new DamageInfo { amount = dmg, type = DamageType.Melee, point = a.Center, direction = d, attacker = gameObject, force = force, heavy = heavy && !blocked && w.knock >= 1f });
                    AudioFX.PlayAt(w.hold == HoldType.Unarmed ? "punch" : "hit", a.Center, 0.7f, UnityEngine.Random.Range(0.85f, 1.1f));
                    VFX.Impact(a.Center, -d, Surface.Flesh);
                    if (isPlayer)
                    {
                        PlayerCamera.I?.AddShake(heavy ? 0.25f : 0.1f);
                        WorldEvents.EmitCrime(a.faction == Faction.Police ? (a.IsDead ? CrimeType.KillCop : CrimeType.AssaultCop) : (a.IsDead ? CrimeType.Murder : CrimeType.Assault), a.Center, gameObject);
                    }
                    WorldEvents.EmitNoise(transform.position, 14f, gameObject);
                    continue;
                }
                var v = c.GetComponentInParent<Vehicle>();
                if (v != null && !done.Contains(v)) { done.Add(v); v.BulletHit(U.SafeClosestPoint(c, center), transform.forward, w.damage * 0.3f, gameObject); AudioFX.PlayAt("hit_metal", center, 0.5f); continue; }
                var dm = c.GetComponentInParent<IDamageable>();
                if (dm != null && !done.Contains(dm)) { done.Add(dm); dm.TakeDamage(DamageInfo.Make(w.damage, DamageType.Melee, center, transform.forward, gameObject, 4f)); }
            }
        }

        // ------------------------------------------------------------------ throwables
        public void Throw(Vector3 target)
        {
            var w = Current;
            if (w == null || w.cls != WeaponClass.Thrown || Time.time < nextFire) return;
            if (Clip <= 0 && Reserve <= 0 && !infiniteAmmo) return;
            nextFire = Time.time + 1.1f;
            rig?.PlayAction(5, 0.55f);
            StartCoroutine(ThrowRelease(w, target));
        }

        IEnumerator ThrowRelease(WeaponDef w, Vector3 target)
        {
            yield return new WaitForSeconds(0.28f);
            if (owner.IsDead) yield break;
            if (!infiniteAmmo)
            {
                if (Clip > 0) clip[currentId] = Clip - 1; else reserve[currentId] = Reserve - 1;
                if (Clip <= 0 && Reserve > 0) { clip[currentId] = 1; reserve[currentId] = Reserve - 1; }
            }
            var from = (owner.rig != null && owner.rig.valid ? owner.rig.HandR.position : owner.HeadPos) + transform.forward * 0.3f;
            var to = target - from;
            float dist = Mathf.Clamp(U.Flat(to).magnitude, 4f, 40f);
            var flatDir = U.Flat(to).normalized;
            float speed = Mathf.Lerp(10f, w.projSpeed + 4f, dist / 40f);
            var vel = flatDir * speed + Vector3.up * (4f + dist * 0.12f);
            if (owner.InVehicle && owner.vehicle.Rb != null) vel += owner.vehicle.Rb.linearVelocity;
            Projectile.SpawnGrenade(from, vel, gameObject, w);
            if (Clip <= 0 && Reserve <= 0 && !infiniteAmmo) { owned.Remove(currentId); Equip("fists"); }
        }
    }

    public enum Surface { Concrete, Metal, Glass, Wood, Flesh, Dirt, Water }

    public static class Surfaces
    {
        /// <summary>Surface classification from collider naming conventions (Blender material/object names) and layers.</summary>
        public static Surface Of(Collider c)
        {
            if (c == null) return Surface.Concrete;
            if (c.gameObject.layer == Layers.Vehicle) return Surface.Metal;
            var n = c.name;
            if (n.Contains("Glass") || n.Contains("Window")) return Surface.Glass;
            if (n.Contains("Metal") || n.Contains("Steel") || n.Contains("Container") || n.Contains("Hangar") || n.Contains("Lamp") || n.Contains("Sign") || n.Contains("Pole") || n.Contains("Rail")) return Surface.Metal;
            if (n.Contains("Wood") || n.Contains("Pier") || n.Contains("Crate") || n.Contains("Pallet") || n.Contains("Bench") || n.Contains("Fence")) return Surface.Wood;
            if (c is TerrainCollider || n.Contains("Sand") || n.Contains("Grass")) return Surface.Dirt;
            return Surface.Concrete;
        }
    }
}
