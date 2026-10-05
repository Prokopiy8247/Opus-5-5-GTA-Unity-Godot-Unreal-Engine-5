using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

namespace Halcyon.EditorTools
{
    /// <summary>Placement helpers shared by the district/coast/airfield content builders.</summary>
    public static partial class WorldBuilder
    {
        static readonly List<Rect> buildingFootprints = new List<Rect>();
        static Dictionary<string, GameObject> prefabMap;
        static readonly Dictionary<string, Bounds> boundsCache = new Dictionary<string, Bounds>();
        static readonly SortedDictionary<string, int> missing = new SortedDictionary<string, int>();
        static readonly List<Vector3> usedSpots = new List<Vector3>();   // x,z = position, y = radius
        static int parkedCount;

        static void ResetContentState()
        {
            buildingFootprints.Clear(); prefabMap = null; boundsCache.Clear(); missing.Clear();
            usedSpots.Clear(); hillPath.Clear(); blocks.Clear(); parkedCount = 0; terrainRef = null;
        }

        // ------------------------------------------------------------------ random
        static float R(float a, float b) => a + (float)rnd.NextDouble() * (b - a);
        static bool Chance(float p) => rnd.NextDouble() < p;
        static T Pick<T>(IList<T> a) => a[rnd.Next(a.Count)];

        // ------------------------------------------------------------------ prefabs
        static GameObject Prefab(string id)
        {
            if (prefabMap == null)
            {
                prefabMap = new Dictionary<string, GameObject>();
                foreach (var e in Pipeline.Db().entries) if (e.prefab != null) prefabMap[e.id] = e.prefab;
            }
            prefabMap.TryGetValue(id ?? "", out var p);
            return p;
        }

        static void Note(string id) { missing[id] = missing.TryGetValue(id, out var c) ? c + 1 : 1; }

        /// <summary>Local-space bounds of a prefab's render meshes (default 12x6x12 box when the prefab is missing).</summary>
        static Bounds PrefabBounds(string id)
        {
            if (boundsCache.TryGetValue(id, out var b)) return b;
            var p = Prefab(id);
            b = new Bounds(new Vector3(0f, 3f, 0f), new Vector3(12f, 6f, 12f));
            if (p != null)
            {
                bool first = true;
                var inv = p.transform.worldToLocalMatrix;
                foreach (var mf in p.GetComponentsInChildren<MeshFilter>(true))
                {
                    if (mf.sharedMesh == null || U.Role(mf.transform).StartsWith("COL_")) continue;
                    var m = inv * mf.transform.localToWorldMatrix;
                    var mb = mf.sharedMesh.bounds;
                    for (int i = 0; i < 8; i++)
                    {
                        var c = mb.center + Vector3.Scale(mb.extents, new Vector3((i & 1) == 0 ? -1 : 1, (i & 2) == 0 ? -1 : 1, (i & 4) == 0 ? -1 : 1));
                        var w = m.MultiplyPoint3x4(c);
                        if (first) { b = new Bounds(w, Vector3.zero); first = false; } else b.Encapsulate(w);
                    }
                }
            }
            boundsCache[id] = b;
            return b;
        }

        static Vector3 Local(Vector3 pos, float yaw, Vector3 local) => pos + Quaternion.Euler(0f, yaw, 0f) * local;

        static GameObject Place(string id, Vector3 pos, float yaw, Transform parent, float scale = 1f)
        {
            var p = Prefab(id);
            if (p == null) { Note(id); return null; }
            var go = (GameObject)PrefabUtility.InstantiatePrefab(p);
            go.transform.SetParent(parent, true);
            go.transform.SetPositionAndRotation(pos, Quaternion.Euler(0f, yaw, 0f));
            if (Mathf.Abs(scale - 1f) > 0.001f) go.transform.localScale = Vector3.one * scale;
            return go;
        }

        static void ClearStatic(GameObject go)
        {
            foreach (var t in go.GetComponentsInChildren<Transform>(true)) GameObjectUtility.SetStaticEditorFlags(t.gameObject, 0);
        }

        // light movable props (rigidbodies from the start) and breakable fixed props (loosen on vehicle impact)
        static readonly Dictionary<string, float> PropMass = new Dictionary<string, float> {
            { "PRP_Cone", 4f }, { "PRP_Bin", 25f }, { "PRP_BarrelRed", 60f }, { "PRP_Crate", 45f }, { "PRP_Pallet", 20f },
            { "PRP_Umbrella", 12f }, { "PRP_Lounger", 15f }, { "PRP_Bench", 70f }, { "PRP_Mailbox", 40f }, { "PRP_Barrier", 700f },
            { "PRP_PicnicTable", 60f }, { "PRP_Dumpster", 500f }, { "PRP_Planter", 300f } };
        static readonly Dictionary<string, float> Breakable = new Dictionary<string, float> {
            { "PRP_StreetLamp", 9f }, { "PRP_TrafficLight", 10f }, { "PRP_Hydrant", 5f }, { "PRP_Bollard", 12f }, { "PRP_Fence", 7f },
            { "PRP_BusStop", 11f }, { "PRP_PowerPole", 13f }, { "PRP_ATM", 9f }, { "PRP_GasPump", 12f }, { "PRP_Vending", 9f } };

        static GameObject Prop(string id, Vector3 pos, float yaw, Transform parent = null)
        {
            var go = Place(id, pos, yaw, parent != null ? parent : propsRoot);
            if (go == null) return null;
            if (PropMass.TryGetValue(id, out var mass))
            {
                ClearStatic(go);
                foreach (var mc in go.GetComponentsInChildren<MeshCollider>(true)) mc.convex = true;
                var rb = go.AddComponent<Rigidbody>();
                rb.mass = mass; rb.linearDamping = 0.05f; rb.angularDamping = 0.3f;
                Layers.SetRecursive(go, Layers.Prop);
                var dp = go.AddComponent<DynamicProp>();
                dp.mass = mass; dp.explosive = id == "PRP_BarrelRed"; dp.health = dp.explosive ? 40f : 120f;
            }
            else if (Breakable.TryGetValue(id, out var impulse))
            {
                ClearStatic(go);
                Layers.SetRecursive(go, Layers.Prop);
                var dp = go.AddComponent<DynamicProp>();
                dp.breakImpulse = impulse; dp.mass = 140f; dp.hydrant = id == "PRP_Hydrant"; dp.explosive = id == "PRP_GasPump";
                dp.health = id == "PRP_GasPump" ? 90f : 400f;
            }
            return go;
        }

        static bool TryProp(string id, Vector3 p, float yaw, float radius)
        {
            if (!Free(p, radius)) return false;
            Claim(p, radius);
            return Prop(id, p, yaw) != null;
        }

        static GameObject Nature(string id, Vector3 p, float yaw, float scale = 1f) => Place(id, p, yaw, natureRoot, scale);

        static void Lamp(Vector3 pos, float yaw)
        {
            var go = Prop("PRP_StreetLamp", pos, yaw);
            if (go == null) return;
            var lg = new GameObject("LampLight");
            lg.transform.SetParent(go.transform, false);
            lg.transform.localPosition = new Vector3(0f, 6.4f, 1.75f);
            var l = lg.AddComponent<Light>();
            l.type = LightType.Point; l.range = 17f; l.intensity = 2.6f; l.color = new Color(1f, 0.82f, 0.58f); l.shadows = LightShadows.None;
            lg.AddComponent<LampLight>();
        }

        static Interactable Interact(string id, Vector3 pos, float radius = 2f)
        {
            var go = new GameObject("INT_" + id);
            go.transform.SetParent(poiRoot, false);
            go.transform.position = pos;
            var it = go.AddComponent<Interactable>();
            it.id = id; it.radius = radius;
            Place("PRP_Marker", pos + Vector3.up * 0.03f, 0f, go.transform);
            return it;
        }

        static void Target(Interactable it, string name, Vector3 world)
        {
            var t = new GameObject(name).transform;
            t.SetParent(it.transform, false);
            t.position = world;
        }

        static void Pickup(string id, string model, Vector3 pos)
        {
            var it = Interact(id, pos, 1.6f);
            var m = Place(model, pos + Vector3.up * 0.6f, 0f, it.transform);
            if (m != null) { ClearStatic(m); var s = m.AddComponent<Spinner>(); s.axis = Vector3.up; s.speed = 90f; foreach (var c in m.GetComponentsInChildren<Collider>()) Object.DestroyImmediate(c); }
        }

        static void Poi(string name, Vector3 p) => data.pois.Add(new WorldData.Mark { name = name, pos = p });
        static void Landmark(string name, Vector3 p) => data.landmarks.Add(new WorldData.Mark { name = name, pos = p });
        static void VSpawn(string id, Vector3 p, float yaw) => data.vehicleSpawns.Add(new WorldData.VSpawn { id = id, pos = p, yaw = yaw });
        static void Parked(string id, Vector3 p, float yaw) { if (parkedCount >= 30) return; parkedCount++; VSpawn(id, p, yaw); }
        static readonly string[] ParkedCars = { "sedan", "compact", "suv", "pickup", "van", "muscle", "taxi" };

        static void LadderAt(Vector3 bottom, Vector3 top, Vector3 outward)
        {
            var go = new GameObject("Ladder");
            go.transform.SetParent(propsRoot, false);
            go.transform.position = bottom;
            var l = go.AddComponent<Ladder>();
            l.Bottom = bottom; l.Top = top; l.Normal = outward.normalized; l.Length = Vector3.Distance(bottom, top);
            float yaw = Mathf.Atan2(outward.x, outward.z) * Mathf.Rad2Deg;
            float h = top.y - bottom.y;
            for (float y = 0f; y < h - 0.2f; y += 4f)
            {
                var m = Place("PRP_Ladder", bottom + Vector3.up * y, yaw, go.transform);
                if (m != null && h - y < 4f) m.transform.localScale = new Vector3(1f, (h - y) / 4f, 1f);
            }
        }

        // ------------------------------------------------------------------ space bookkeeping
        static bool Free(Vector3 p, float r)
        {
            var p2 = new Vector2(p.x, p.z);
            foreach (var f in buildingFootprints)
                if (p2.x > f.xMin - r && p2.x < f.xMax + r && p2.y > f.yMin - r && p2.y < f.yMax + r) return false;
            foreach (var u in usedSpots)
            {
                float rr = r + u.y;
                if ((new Vector2(u.x, u.z) - p2).sqrMagnitude < rr * rr) return false;
            }
            return true;
        }

        static void Claim(Vector3 p, float r) => usedSpots.Add(new Vector3(p.x, r, p.z));

        static float GroundAt(float x, float z)
        {
            var p = new Vector2(x, z);
            foreach (var b in blocks) if (b.rect.Contains(p)) return PlateTop;
            if (x >= QuayEdge && x <= -208.2f && z > -82f && z < 82f) return PlateTop;
            if (terrainRef != null) return terrainRef.SampleHeight(new Vector3(x, 0f, z)) + terrainRef.transform.position.y;
            return Height(x, z);
        }

        static Vector3 OnGround(float x, float z) => new Vector3(x, GroundAt(x, z), z);

        static void AddFootprint(Vector3 pos, float yaw, Bounds b)
        {
            var rot = Quaternion.Euler(0f, yaw, 0f);
            float minX = float.MaxValue, maxX = float.MinValue, minZ = float.MaxValue, maxZ = float.MinValue;
            for (int i = 0; i < 4; i++)
            {
                var w = pos + rot * new Vector3((i & 1) == 0 ? b.min.x : b.max.x, 0f, (i & 2) == 0 ? b.min.z : b.max.z);
                minX = Mathf.Min(minX, w.x); maxX = Mathf.Max(maxX, w.x); minZ = Mathf.Min(minZ, w.z); maxZ = Mathf.Max(maxZ, w.z);
            }
            buildingFootprints.Add(Rect.MinMaxRect(minX, minZ, maxX, maxZ));
        }

        /// <summary>Places a building by its pivot; returns the instance (null if the prefab is missing, footprint still reserved).</summary>
        static GameObject Building(string id, Vector3 pos, float yaw)
        {
            var go = Place(id, pos, yaw, buildRoot);
            AddFootprint(pos, yaw, PrefabBounds(id));
            return go;
        }

        /// <summary>Places a building inside a lot with its front facing the street on side `face` (0 N, 1 E, 2 S, 3 W).</summary>
        static Vector3 PlaceFacing(string id, Rect lot, int face, float setback, out GameObject go, float lateral = 0f)
        {
            var b = PrefabBounds(id);
            float yaw = face * 90f;
            var rot = Quaternion.Euler(0f, yaw, 0f);
            Vector3 fwd = rot * Vector3.forward, right = rot * Vector3.right;
            bool ns = face == 0 || face == 2;
            float depth = ns ? lot.height : lot.width;
            var lotC = new Vector3(lot.center.x, PlateTop, lot.center.y);
            var edge = lotC + fwd * depth * 0.5f;
            var pos = edge - fwd * (setback + b.max.z) - right * (b.center.x - lateral);
            pos.y = PlateTop;
            go = Building(id, pos, yaw);
            return pos;
        }

        static GameObject FitLot(Rect lot, int face, IList<string> candidates, float setback)
        {
            bool ns = face == 0 || face == 2;
            float along = ns ? lot.width : lot.height, depth = ns ? lot.height : lot.width;
            var order = new List<string>(candidates);
            for (int i = order.Count - 1; i > 0; i--) { int j = rnd.Next(i + 1); var t = order[i]; order[i] = order[j]; order[j] = t; }
            foreach (var id in order)
            {
                if (Prefab(id) == null) { Note(id); continue; }
                var b = PrefabBounds(id);
                if (b.size.x > along - 1f || b.size.z > depth - setback - 0.5f) continue;
                PlaceFacing(id, lot, face, setback, out var go);
                return go;
            }
            return null;
        }

        static float FaceYaw(int face) => face * 90f;
        static Vector3 SideDir(int side) => side == 0 ? Vector3.forward : side == 1 ? Vector3.right : side == 2 ? Vector3.back : Vector3.left;
    }
}
