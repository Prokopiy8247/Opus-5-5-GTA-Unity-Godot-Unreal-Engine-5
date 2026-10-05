using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Bakes a top-down map texture of the world at runtime and converts world positions to minimap UVs.</summary>
    public class MapTexture : MonoBehaviour
    {
        public static MapTexture I;
        public Texture2D map;
        public const float WorldSize = 640f;     // painted area (world spans -320..320)
        public const int Res = 1024;
        public Vector2 centre = Vector2.zero;

        void Awake() { I = this; }

        public static MapTexture Create(Color ground, Color water, Color road, Color building)
        {
            var inst = new GameObject("[MapTexture]").AddComponent<MapTexture>();
            I = inst;
            inst.map = new Texture2D(Res, Res, TextureFormat.RGBA32, true);
            inst.map.wrapMode = TextureWrapMode.Clamp;
            inst.map.filterMode = FilterMode.Bilinear;
            var px = new Color[Res * Res];
            for (int i = 0; i < px.Length; i++) px[i] = ground;
            inst.map.SetPixels(px);
            return inst;
        }

        public Vector2 WorldToUV(Vector3 p)
        {
            float u = (p.x - centre.x) / WorldSize + 0.5f;
            float v = (p.z - centre.y) / WorldSize + 0.5f;
            return new Vector2(u, v);
        }

        Vector2 WorldToPx(Vector3 p)
        {
            var uv = WorldToUV(p);
            return new Vector2(uv.x * Res, uv.y * Res);
        }

        public void PaintRect(Vector3 centreW, Vector2 size, float yaw, Color c, int border = 0, Color? borderColor = null)
        {
            var p = WorldToPx(centreW);
            float w = size.x / WorldSize * Res, h = size.y / WorldSize * Res;
            int x0 = Mathf.RoundToInt(p.x - w * 0.5f), x1 = Mathf.RoundToInt(p.x + w * 0.5f);
            int y0 = Mathf.RoundToInt(p.y - h * 0.5f), y1 = Mathf.RoundToInt(p.y + h * 0.5f);
            bool rotated = Mathf.Abs(Mathf.Sin(yaw * Mathf.Deg2Rad)) > 0.3f;
            if (rotated) { var t = w; w = h; h = t; var t2 = x0; x0 = Mathf.RoundToInt(p.x - w * 0.5f); x1 = Mathf.RoundToInt(p.x + w * 0.5f); y0 = Mathf.RoundToInt(p.y - h * 0.5f); y1 = Mathf.RoundToInt(p.y + h * 0.5f); }
            for (int y = y0; y <= y1; y++)
            {
                if (y < 0 || y >= Res) continue;
                for (int x = x0; x <= x1; x++)
                {
                    if (x < 0 || x >= Res) continue;
                    bool edge = border > 0 && (x - x0 < border || x1 - x < border || y - y0 < border || y1 - y < border);
                    map.SetPixel(x, y, edge && borderColor.HasValue ? borderColor.Value : c);
                }
            }
        }

        public void PaintCircle(Vector3 centreW, float radiusM, Color c)
        {
            var p = WorldToPx(centreW);
            float r = radiusM / WorldSize * Res;
            int x0 = Mathf.FloorToInt(p.x - r), x1 = Mathf.CeilToInt(p.x + r);
            int y0 = Mathf.FloorToInt(p.y - r), y1 = Mathf.CeilToInt(p.y + r);
            for (int y = y0; y <= y1; y++)
            {
                if (y < 0 || y >= Res) continue;
                for (int x = x0; x <= x1; x++)
                {
                    if (x < 0 || x >= Res) continue;
                    float d = Vector2.Distance(new Vector2(x, y), p);
                    if (d <= r) map.SetPixel(x, y, c);
                }
            }
        }

        public void Apply() { map.Apply(true); }

        /// <summary>UV rect for a rotated minimap view centred on the player.</summary>
        public Rect MinimapUv(Vector3 playerPos, float yaw)
        {
            float view = 0.19f;  // fraction of the map shown
            var uv = WorldToUV(playerPos);
            return new Rect(uv.x - view * 0.5f, uv.y - view * 0.5f, view, view);
        }

        /// <summary>Converts a world position into minimap-local UI coordinates (map is north-up, minimap is north-up too).</summary>
        public Vector2 WorldToMinimapLocal(Vector3 world, RectTransform mapRect, Vector3 playerPos, float yaw)
        {
            var uv = WorldToUV(world);
            var puv = WorldToUV(playerPos);
            float view = 0.19f;
            var rect = mapRect.rect;
            float dx = (uv.x - puv.x) / view * rect.width;
            float dy = (uv.y - puv.y) / view * rect.height;
            return new Vector2(dx, dy);
        }

        /// <summary>Full-screen map: returns the anchored position of a world point on the given rect.</summary>
        public Vector2 WorldToFullMap(Vector3 world, RectTransform mapRect)
        {
            var uv = WorldToUV(world);
            var r = mapRect.rect;
            return new Vector2((uv.x - 0.5f) * r.width, (uv.y - 0.5f) * r.height);
        }

        public Vector2 FullMapToWorldNormalized(Vector2 local, RectTransform mapRect)
        {
            var r = mapRect.rect;
            return new Vector2(local.x / r.width + 0.5f, local.y / r.height + 0.5f);
        }

        /// <summary>Raycast a world position from a map click using the ground height.</summary>
        public Vector3 MapPointToWorld(Vector2 normalized)
        {
            float x = (normalized.x - 0.5f) * WorldSize + centre.x;
            float z = (normalized.y - 0.5f) * WorldSize + centre.y;
            float y = U.GroundHeight(new Vector3(x, 50f, z), 0f);
            return new Vector3(x, y, z);
        }
    }

    /// <summary>Named world anchors filled in by the world builder (used by the taxi, phone, respawn and blips).</summary>
    public static class WorldMarkers
    {
        public static Vector3 PoliceStation, Hospital, Safehouse, WeaponShop, ClothingShop, ModShop, GasStation, Airport, Docks, Downtown, Hilltop, Beach, Industrial;
        public static readonly List<Vector3> DistrictCentres = new List<Vector3>();
        public static readonly List<Vector3> Helipads = new List<Vector3>();
        public static readonly List<Vector3> Garages = new List<Vector3>();
        public static readonly List<Vector3> ExtraPedSpots = new List<Vector3>();
        public static readonly List<(string name, Vector3 pos)> Landmarks = new List<(string, Vector3)>();

        public static string ZoneAt(Vector3 p)
        {
            float best = float.MaxValue; string name = "Halcyon";
            foreach (var (n, pos) in Landmarks)
            {
                float d = Vector3.Distance(p, pos);
                if (d < best) { best = d; name = n; }
            }
            if (p.x < -206f && p.z > -84f && p.z < 84f) return "Saltwater Docks";
            if (p.x < -206f) return p.z > 0f ? "North Beach" : "South Beach";
            if (p.z < -176f) return "Halcyon Airfield";
            if (p.x > 150f && p.z < 70f) return "Ironside Yards";
            if (p.z > 70f && p.x < -30f) return "Crown Hill";
            if (p.z > 70f) return "Palm Row";
            return "Downtown";
        }

        public static Vector3 NearestDistrict(Vector3 p)
        {
            float best = float.MaxValue; Vector3 v = p;
            foreach (var d in DistrictCentres) { float dd = Vector3.Distance(p, d); if (dd < best) { best = dd; v = d; } }
            return v;
        }
    }
}
