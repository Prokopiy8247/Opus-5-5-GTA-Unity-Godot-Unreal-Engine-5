using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>
    /// Instantiates vehicles from the Blender-generated prefabs: builds colliders from the COL_* helper meshes,
    /// attaches the right physics component for the vehicle class and wires seats/doors.
    /// </summary>
    public static class VehicleFactory
    {
        static readonly Dictionary<string, GameObject> cache = new Dictionary<string, GameObject>();

        public static Vehicle Spawn(VehicleDef def, Vector3 pos, Quaternion rot, bool kinematic = false)
        {
            if (def == null) return null;
            var prefab = GameDatabase.I != null ? GameDatabase.I.Get(def.model) : null;
            if (prefab == null) return null;
            var go = Object.Instantiate(prefab, pos, rot);
            // keep the instance inactive while components are added so Vehicle.Awake runs with the right defId/kind
            go.SetActive(false);
            go.name = def.model;
            foreach (var t in go.GetComponentsInChildren<Transform>(true))
            {
                var role = U.Role(t);
                if (role.StartsWith("WHEEL_")) t.gameObject.layer = Layers.Vehicle;
            }
            SetLayerRecursive(go, Layers.Vehicle);
            foreach (var r in go.GetComponentsInChildren<Renderer>()) r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.On;
            var rb = go.GetComponent<Rigidbody>();
            if (rb == null) rb = go.AddComponent<Rigidbody>();
            rb.isKinematic = kinematic;
            if (kinematic) rb.useGravity = false;

            // colliders from COL_* helpers; fall back to hulls derived from the visual meshes
            var cols = new List<GameObject>();
            foreach (var t in go.GetComponentsInChildren<Transform>(true))
            {
                var role = U.Role(t);
                if (role.StartsWith("COL_")) cols.Add(t.gameObject);
                else if (t.GetComponent<Collider>() != null && !role.StartsWith("COL_")) Object.Destroy(t.GetComponent<Collider>());
            }
            if (cols.Count > 0)
            {
                foreach (var c in cols)
                {
                    var mf = c.GetComponent<MeshFilter>();
                    if (mf == null || mf.sharedMesh == null) { Object.Destroy(c); continue; }
                    var mc = c.AddComponent<MeshCollider>();
                    mc.sharedMesh = mf.sharedMesh;
                    mc.convex = true;
                    float maxDim = Mathf.Max(mf.sharedMesh.bounds.size.x, Mathf.Max(mf.sharedMesh.bounds.size.y, mf.sharedMesh.bounds.size.z));
                    mc.convex = maxDim < 40f;
                    var mr = c.GetComponent<MeshRenderer>();
                    if (mr) mr.enabled = false;
                    c.transform.SetParent(go.transform, true);
                }
            }
            else BuildFallbackColliders(go, def);

            Vehicle v;
            switch (def.kind)
            {
                case VehicleKind.Bike: case VehicleKind.Bicycle: v = go.AddComponent<BikeVehicle>(); break;
                case VehicleKind.Boat: v = go.AddComponent<BoatVehicle>(); break;
                case VehicleKind.Heli: v = go.AddComponent<HeliVehicle>(); break;
                case VehicleKind.Plane: v = go.AddComponent<PlaneVehicle>(); break;
                default: v = go.AddComponent<CarVehicle>(); break;
            }
            v.defId = def.id;
            v.kind = def.kind;
            v.persistent = kinematic;
            LayerMaskSetup(go);
            go.SetActive(true);
            return v;
        }

        static void LayerMaskSetup(GameObject go)
        {
            var mc = go.GetComponent<Collider>() ?? go.GetComponentInChildren<Collider>();
            if (mc == null) return;
            // wheels must not collide with the body
            var wheelCols = new List<Collider>();
            foreach (var c in go.GetComponentsInChildren<Collider>()) if (U.Role(c.transform).StartsWith("WHEEL_")) wheelCols.Add(c);
            foreach (var c in wheelCols) c.isTrigger = false;
        }

        static void BuildFallbackColliders(GameObject go, VehicleDef def)
        {
            Bounds b = new Bounds(go.transform.position, Vector3.zero);
            bool first = true;
            foreach (var r in go.GetComponentsInChildren<Renderer>())
            {
                if (first) { b = r.bounds; first = false; } else b.Encapsulate(r.bounds);
            }
            if (first) b = new Bounds(go.transform.position + Vector3.up, new Vector3(2f, 1.4f, 4.4f));
            var local = go.transform.InverseTransformPoint(b.center);
            var size = go.transform.InverseTransformVector(b.size);
            bool air = def.kind == VehicleKind.Heli || def.kind == VehicleKind.Plane || def.kind == VehicleKind.Boat;
            if (air)
            {
                var box = go.AddComponent<BoxCollider>();
                box.center = local;
                box.size = new Vector3(size.x, Mathf.Max(size.y * 0.9f, 0.8f), size.z);
            }
            else
            {
                var body = new GameObject("AUTO_COL_Body"); body.transform.SetParent(go.transform, false);
                var bc = body.AddComponent<BoxCollider>();
                float ride = 0.3f;
                bc.size = new Vector3(size.x * 0.95f, Mathf.Max(size.y - ride, 0.6f), size.z * 0.98f);
                bc.center = new Vector3(local.x, ride + bc.size.y * 0.5f, local.z);
                var cabin = new GameObject("AUTO_COL_Cabin"); cabin.transform.SetParent(go.transform, false);
                var cc = cabin.AddComponent<BoxCollider>();
                cc.size = new Vector3(size.x * 0.72f, Mathf.Min(size.y * 0.45f, 0.9f), size.z * 0.5f);
                cc.center = new Vector3(local.x, ride + 0.4f + cc.size.y * 0.5f, local.z);
            }
        }

        static void SetLayerRecursive(GameObject go, int layer)
        {
            foreach (var t in go.GetComponentsInChildren<Transform>(true)) t.gameObject.layer = layer;
        }

        /// <summary>Vehicle pickups scattered by the world builder (garages, shops, airport).</summary>
        public static Vehicle SpawnById(string id, Vector3 pos, float yaw = 0f)
        {
            var d = VehicleCatalog.Get(id);
            return Spawn(d, pos + Vector3.up * 0.4f, Quaternion.Euler(0f, yaw, 0f));
        }
    }
}
