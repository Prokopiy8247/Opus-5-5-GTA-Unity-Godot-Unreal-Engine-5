using System;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    public static class Layers
    {
        public const int Default = 0, IgnoreRaycast = 2, Water = 4, UI = 5, Player = 6, Vehicle = 7, NPC = 8, Ragdoll = 9,
            Projectile = 10, Trigger = 11, Prop = 12, Debris = 13;

        public static readonly int World = (1 << Default) | (1 << Prop);
        public static readonly int Shootable = (1 << Default) | (1 << Player) | (1 << Vehicle) | (1 << NPC) | (1 << Ragdoll) | (1 << Prop);
        public static readonly int CameraBlock = (1 << Default);
        public static readonly int Ground = (1 << Default) | (1 << Prop) | (1 << Vehicle);
        public static readonly int Sight = (1 << Default) | (1 << Vehicle) | (1 << Prop);
        public static readonly int Actors = (1 << Player) | (1 << NPC);

        public static void SetupCollisionMatrix()
        {
            Physics.IgnoreLayerCollision(Ragdoll, Player);
            Physics.IgnoreLayerCollision(Ragdoll, NPC);
            Physics.IgnoreLayerCollision(Debris, Player);
            Physics.IgnoreLayerCollision(Debris, NPC);
            Physics.IgnoreLayerCollision(Debris, Ragdoll);
            Physics.IgnoreLayerCollision(NPC, NPC);
            Physics.IgnoreLayerCollision(Trigger, Trigger);
            Physics.IgnoreLayerCollision(Trigger, Ragdoll);
            Physics.IgnoreLayerCollision(Trigger, Debris);
            Physics.IgnoreLayerCollision(Trigger, Prop);
            Physics.IgnoreLayerCollision(Projectile, Trigger);
            Physics.IgnoreLayerCollision(Projectile, Projectile);
        }

        public static void SetRecursive(GameObject g, int layer)
        {
            foreach (var t in g.GetComponentsInChildren<Transform>(true)) t.gameObject.layer = layer;
        }
    }

    public enum DamageType { Bullet, Melee, Explosion, Fall, Vehicle, Fire, Drown, Generic }

    public struct DamageInfo
    {
        public float amount;
        public DamageType type;
        public Vector3 point;
        public Vector3 direction;
        public float force;
        public GameObject attacker;
        public bool headshot;
        public bool heavy;

        public static DamageInfo Make(float amount, DamageType type, Vector3 point, Vector3 dir, GameObject attacker, float force = 0f)
        {
            return new DamageInfo { amount = amount, type = type, point = point, direction = dir, attacker = attacker, force = force };
        }
    }

    public interface IDamageable
    {
        void TakeDamage(DamageInfo d);
    }

    public enum Faction { Player, Civilian, Police, Gang, Animal, Emergency }

    public enum CrimeType { Gunfire, Assault, Murder, AssaultCop, KillCop, CarJack, StealCopCar, Explosion, VehicleHit, DestroyCopCar, Ramming, Robbery }

    /// <summary>Global event bus used by AI perception, the wanted system, audio and VFX.</summary>
    public static class WorldEvents
    {
        public static event Action<Vector3, float, GameObject> Noise;          // position, audible radius, source
        public static event Action<CrimeType, Vector3, GameObject> Crime;      // raw crime; WantedSystem decides who reports it
        public static event Action<Vector3, float> Explosion;                  // position, radius
        public static event Action<Actor> ActorKilled;

        public static void EmitNoise(Vector3 p, float radius, GameObject src) => Noise?.Invoke(p, radius, src);
        public static void EmitCrime(CrimeType c, Vector3 p, GameObject perp) => Crime?.Invoke(c, p, perp);
        public static void EmitExplosion(Vector3 p, float r) => Explosion?.Invoke(p, r);
        public static void EmitKilled(Actor a) => ActorKilled?.Invoke(a);
    }

    public static class U
    {
        /// <summary>Collider.ClosestPoint only supports primitives and convex meshes; fall back to the bounds otherwise.</summary>
        public static Vector3 SafeClosestPoint(Collider c, Vector3 p)
        {
            if (c is MeshCollider mc && !mc.convex) return c.bounds.ClosestPoint(p);
            if (c is TerrainCollider) return c.bounds.ClosestPoint(p);
            return c.ClosestPoint(p);
        }

        public static string Role(Transform t)
        {
            int i = t.name.IndexOf("__", StringComparison.Ordinal);
            return i >= 0 ? t.name.Substring(i + 2) : t.name;
        }

        public static Transform FindRole(Transform root, string role)
        {
            foreach (var t in root.GetComponentsInChildren<Transform>(true))
                if (Role(t) == role) return t;
            return null;
        }

        public static List<Transform> FindRolePrefix(Transform root, string prefix)
        {
            var l = new List<Transform>();
            foreach (var t in root.GetComponentsInChildren<Transform>(true))
                if (Role(t).StartsWith(prefix, StringComparison.Ordinal)) l.Add(t);
            l.Sort((a, b) => string.CompareOrdinal(a.name, b.name));
            return l;
        }

        public static Transform FindDeep(Transform root, string exactName)
        {
            foreach (var t in root.GetComponentsInChildren<Transform>(true))
                if (t.name == exactName) return t;
            return null;
        }

        public static float Damp(float a, float b, float lambda, float dt) => Mathf.Lerp(a, b, 1f - Mathf.Exp(-lambda * dt));
        public static Vector3 Damp(Vector3 a, Vector3 b, float lambda, float dt) => Vector3.Lerp(a, b, 1f - Mathf.Exp(-lambda * dt));
        public static Quaternion Damp(Quaternion a, Quaternion b, float lambda, float dt) => Quaternion.Slerp(a, b, 1f - Mathf.Exp(-lambda * dt));
        public static float DampAngle(float a, float b, float lambda, float dt) => Mathf.LerpAngle(a, b, 1f - Mathf.Exp(-lambda * dt));

        public static Vector3 Flat(Vector3 v) { v.y = 0; return v; }
        public static float FlatDist(Vector3 a, Vector3 b) { a.y = 0; b.y = 0; return Vector3.Distance(a, b); }

        public static T GetOrAdd<T>(GameObject g) where T : Component
        {
            var c = g.GetComponent<T>();
            return c ? c : g.AddComponent<T>();
        }

        static readonly RaycastHit[] _hits = new RaycastHit[16];

        /// <summary>Line of sight that ignores colliders belonging to either end point.</summary>
        public static bool LineOfSight(Vector3 from, Vector3 to, Transform ignoreA, Transform ignoreB, int mask)
        {
            var d = to - from;
            float len = d.magnitude;
            if (len < 0.01f) return true;
            int n = Physics.RaycastNonAlloc(from, d / len, _hits, len, mask, QueryTriggerInteraction.Ignore);
            for (int i = 0; i < n; i++)
            {
                var t = _hits[i].transform;
                if (ignoreA && t.IsChildOf(ignoreA)) continue;
                if (ignoreB && t.IsChildOf(ignoreB)) continue;
                return false;
            }
            return true;
        }

        public static float GroundHeight(Vector3 p, float fallback = 0f)
        {
            if (Physics.Raycast(p + Vector3.up * 50f, Vector3.down, out var h, 200f, Layers.World, QueryTriggerInteraction.Ignore)) return h.point.y;
            return fallback;
        }

        public static Color Hex(string h)
        {
            ColorUtility.TryParseHtmlString(h.StartsWith("#") ? h : "#" + h, out var c);
            return c;
        }

        public static string Money(int v) => "$" + v.ToString("N0");
    }

    /// <summary>Simple GameObject pool keyed by prefab.</summary>
    public static class Pool
    {
        static readonly Dictionary<GameObject, Stack<GameObject>> free = new Dictionary<GameObject, Stack<GameObject>>();
        static readonly Dictionary<GameObject, GameObject> origin = new Dictionary<GameObject, GameObject>();
        static Transform poolRoot;

        public static GameObject Get(GameObject prefab, Vector3 pos, Quaternion rot)
        {
            if (!free.TryGetValue(prefab, out var st)) { st = new Stack<GameObject>(); free[prefab] = st; }
            GameObject g = null;
            while (st.Count > 0 && g == null) g = st.Pop();
            if (g == null)
            {
                g = UnityEngine.Object.Instantiate(prefab, pos, rot);
                origin[g] = prefab;
            }
            else
            {
                g.transform.SetPositionAndRotation(pos, rot);
                g.transform.SetParent(null);
                g.SetActive(true);
            }
            return g;
        }

        public static void Release(GameObject g, float delay = 0f)
        {
            if (g == null) return;
            if (delay > 0f) { PoolTimer.Schedule(g, delay); return; }
            if (!origin.TryGetValue(g, out var prefab)) { UnityEngine.Object.Destroy(g); return; }
            if (poolRoot == null) { poolRoot = new GameObject("[Pool]").transform; }
            g.SetActive(false);
            g.transform.SetParent(poolRoot);
            free[prefab].Push(g);
        }
    }

    public class PoolTimer : MonoBehaviour
    {
        static PoolTimer inst;
        readonly List<(GameObject g, float t)> items = new List<(GameObject, float)>();

        public static void Schedule(GameObject g, float delay)
        {
            if (inst == null) inst = new GameObject("[PoolTimer]").AddComponent<PoolTimer>();
            inst.items.Add((g, Time.time + delay));
        }

        void Update()
        {
            for (int i = items.Count - 1; i >= 0; i--)
            {
                if (Time.time >= items[i].t)
                {
                    var g = items[i].g;
                    items.RemoveAt(i);
                    Pool.Release(g);
                }
            }
        }
    }
}
