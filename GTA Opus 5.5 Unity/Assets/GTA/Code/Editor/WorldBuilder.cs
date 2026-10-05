using System.Collections.Generic;
using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Halcyon.EditorTools
{
    /// <summary>
    /// Procedural editor-time builder of Port Halcyon (~600 x 600 m island): terrain, road grid, block plates,
    /// water, sky, lighting, post-processing, map paint and runtime world data. Placement of buildings, props,
    /// nature and interaction points lives in WorldContent.cs.
    /// </summary>
    public static partial class WorldBuilder
    {
        public const float CityY = 2f, PlateTop = 2.15f, RoadY = 2.025f, QuayEdge = -236f;
        public static readonly float[] XS = { -200f, -150f, -90f, -30f, 30f, 90f, 150f, 220f, 285f };
        public static readonly float[] ZS = { -170f, -110f, -50f, 10f, 70f, 130f, 190f, 270f };
        public static readonly Vector2 HillCentre = new Vector2(-115f, 190f);
        public static readonly Vector2 PointCentre = new Vector2(-236f, 292f);   // lighthouse promontory
        public const float HillRadius = 70f, HillHeight = 32f;

        class Line { public bool horizontal; public float c, a, b, width; public bool highway; }
        static readonly List<Line> lines = new List<Line>();
        static WorldData data;
        static Transform root, propsRoot, buildRoot, natureRoot, roadRoot, poiRoot;
        static System.Random rnd;
        static readonly Dictionary<string, Material> mats = new Dictionary<string, Material>();
        static Terrain terrainRef;

        [MenuItem("Halcyon/4 Build World Scene")]
        public static void Build()
        {
            rnd = new System.Random(20261003);
            mats.Clear();
            ResetContentState();
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            root = new GameObject("PortHalcyon").transform;
            roadRoot = Child("Ground & Roads");
            buildRoot = Child("Buildings");
            propsRoot = Child("Props");
            natureRoot = Child("Nature");
            poiRoot = Child("Interactions");
            data = new GameObject("WorldData").AddComponent<WorldData>();

            DefineRoads();
            BuildMaterials();
            BuildTerrain();
            BuildWater();
            BuildRoadMeshes();
            BuildPlatesAndContent();
            BuildTrafficLights();
            BuildRoadsideLamps();
            BuildCoast();
            BuildHill();
            BuildAirfield();
            BuildUnderwater();
            BuildActivities();
            BuildLighting();
            PaintMap();

            Directory.CreateDirectory(Path.GetDirectoryName(Pipeline.ScenePath));
            EditorSceneManager.SaveScene(scene, Pipeline.ScenePath);
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(Pipeline.ScenePath, true) };
            // emissive "night" materials are toggled at runtime by GameTime
            var db = Pipeline.Db();
            var night = new List<Material>();
            foreach (var guid in AssetDatabase.FindAssets("t:Material", new[] { Pipeline.Mats }))
            {
                var m = AssetDatabase.LoadAssetAtPath<Material>(AssetDatabase.GUIDToAssetPath(guid));
                if (m == null) continue;
                var n = m.name;
                if (n.Contains("WindowLit") || n.Contains("Neon") || n.Contains("LampGlow") || n.Contains("SignGlow") || n.Contains("Screen")) night.Add(m);
            }
            db.nightMaterials = night.ToArray();
            EditorUtility.SetDirty(db);
            AssetDatabase.SaveAssets();
            var miss = new List<string>();
            foreach (var kv in missing) miss.Add(kv.Key + "x" + kv.Value);
            string report = "buildings=" + buildRoot.childCount + "\nprops=" + propsRoot.childCount + "\nnature=" + natureRoot.childCount +
                "\ninteractions=" + poiRoot.childCount + "\nvehicleSpawns=" + data.vehicleSpawns.Count + "\npedSpots=" + data.pedSpots.Count +
                "\nroads=" + data.roads.Count + "\nlandmarks=" + data.landmarks.Count + "\nmissing(" + miss.Count + ")=" + string.Join(", ", miss) + "\n";
            Debug.Log("[WorldBuilder] scene saved: " + Pipeline.ScenePath + "\n" + report);
            Directory.CreateDirectory("QA");
            File.WriteAllText("QA/world_builder_report.txt", report);
        }

        static Transform Child(string n) { var t = new GameObject(n).transform; t.SetParent(root); return t; }

        // ------------------------------------------------------------------ road graph
        static void AddLine(bool horizontal, float c, float a, float b, float width, bool highway = false)
            => lines.Add(new Line { horizontal = horizontal, c = c, a = a, b = b, width = width, highway = highway });

        static void DefineRoads()
        {
            lines.Clear();
            AddLine(false, -200f, -170f, 270f, 16f, true);            // Coastal Highway (west)
            AddLine(true, -170f, -200f, 285f, 14f, true);             // Airfield ring road (south)
            AddLine(false, 285f, -170f, 270f, 11f);                   // East road
            AddLine(true, 270f, -200f, 285f, 11f);                    // North shore road
            foreach (var z in new[] { -110f, -50f, 10f, 70f }) AddLine(true, z, -200f, 285f, 11f);
            AddLine(false, -150f, -170f, 70f, 11f);
            AddLine(false, -90f, -170f, 70f, 11f);
            foreach (var x in new[] { -30f, 30f, 90f, 150f, 220f }) AddLine(false, x, -170f, 270f, 11f);
            foreach (var z in new[] { 130f, 190f }) AddLine(true, z, -30f, 285f, 11f);

            // split every line at all crossings so lanes meet at junction centres
            foreach (var l in lines)
            {
                var stops = new List<float> { l.a, l.b };
                foreach (var o in lines)
                {
                    if (o.horizontal == l.horizontal) continue;
                    if (o.c > Mathf.Min(l.a, l.b) - 0.1f && o.c < Mathf.Max(l.a, l.b) + 0.1f && l.c >= Mathf.Min(o.a, o.b) - 0.1f && l.c <= Mathf.Max(o.a, o.b) + 0.1f)
                        stops.Add(o.c);
                }
                stops.Sort();
                for (int i = 0; i < stops.Count - 1; i++)
                {
                    if (stops[i + 1] - stops[i] < 2f) continue;
                    var a = l.horizontal ? new Vector3(stops[i], CityY, l.c) : new Vector3(l.c, CityY, stops[i]);
                    var b = l.horizontal ? new Vector3(stops[i + 1], CityY, l.c) : new Vector3(l.c, CityY, stops[i + 1]);
                    data.roads.Add(new WorldData.Seg { a = a, b = b, width = l.width, highway = l.highway });
                }
            }
        }

        public static bool RoadAt(float x, float z, float margin = 0f)
        {
            foreach (var l in lines)
            {
                float along = l.horizontal ? x : z, across = l.horizontal ? z : x;
                if (along >= Mathf.Min(l.a, l.b) - l.width * 0.5f && along <= Mathf.Max(l.a, l.b) + l.width * 0.5f && Mathf.Abs(across - l.c) <= l.width * 0.5f + margin) return true;
            }
            return false;
        }

        static float HalfWidthOn(bool horizontalEdge, float c, float from, float to)
        {
            foreach (var l in lines)
                if (l.horizontal == horizontalEdge && Mathf.Abs(l.c - c) < 0.1f && Mathf.Min(l.a, l.b) <= from + 1f && Mathf.Max(l.a, l.b) >= to - 1f) return l.width * 0.5f;
            return 0f;
        }

        // ------------------------------------------------------------------ materials
        static Material Mat(string name, Color c, float smooth = 0.2f, Texture2D tex = null)
        {
            if (mats.TryGetValue(name, out var m)) return m;
            string path = Pipeline.Mats + "/" + name + ".mat";
            m = AssetDatabase.LoadAssetAtPath<Material>(path);
            bool created = m == null;
            if (created) m = new Material(Shader.Find("Universal Render Pipeline/Lit")) { name = name };
            m.shader = Shader.Find("Universal Render Pipeline/Lit");
            m.SetColor("_BaseColor", c);
            m.SetFloat("_Smoothness", smooth);
            m.SetFloat("_Metallic", 0f);
            if (tex != null) m.SetTexture("_BaseMap", tex);
            m.enableInstancing = true;
            if (created) AssetDatabase.CreateAsset(m, path); else EditorUtility.SetDirty(m);
            mats[name] = m;
            return m;
        }

        static Texture2D NoiseTex(string name, Color a, Color b, float scale, int res = 256, System.Func<int, int, Color, Color> post = null)
        {
            string path = Pipeline.Tex + "/" + name + ".png";
            var t = new Texture2D(res, res, TextureFormat.RGBA32, true);
            for (int y = 0; y < res; y++)
                for (int x = 0; x < res; x++)
                {
                    // tileable noise: sample on a torus
                    float u = x / (float)res * Mathf.PI * 2f, v = y / (float)res * Mathf.PI * 2f;
                    float n = Mathf.PerlinNoise(Mathf.Cos(u) * scale + 11f, Mathf.Sin(u) * scale + Mathf.Cos(v) * scale * 0.7f + 5f) * 0.6f
                            + Mathf.PerlinNoise(Mathf.Sin(v) * scale * 3f + 3f, Mathf.Cos(v) * scale * 3f + Mathf.Sin(u) * scale * 2f + 9f) * 0.4f;
                    var c = Color.Lerp(a, b, n);
                    if (post != null) c = post(x, y, c);
                    t.SetPixel(x, y, c);
                }
            t.Apply();
            File.WriteAllBytes(path, t.EncodeToPNG());
            AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceSynchronousImport);
            var ti = (TextureImporter)AssetImporter.GetAtPath(path);
            ti.wrapMode = TextureWrapMode.Repeat; ti.mipmapEnabled = true; ti.anisoLevel = 8; ti.SaveAndReimport();
            return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
        }

        static void BuildMaterials()
        {
            Directory.CreateDirectory(Pipeline.Tex); Directory.CreateDirectory(Pipeline.Mats);
            var asphaltA = new Color(0.24f, 0.25f, 0.27f); var asphaltB = new Color(0.31f, 0.32f, 0.34f);
            var white = new Color(0.9f, 0.9f, 0.88f); var yellow = new Color(0.93f, 0.76f, 0.2f);
            // two-lane street: double yellow centre, white edge lines
            var road2 = NoiseTex("T_Road2", asphaltA, asphaltB, 1.5f, 256, (x, y, c) =>
            {
                float u = x / 255f;
                if (Mathf.Abs(u - 0.485f) < 0.012f || Mathf.Abs(u - 0.515f) < 0.012f) return yellow;
                if (Mathf.Abs(u - 0.06f) < 0.01f || Mathf.Abs(u - 0.94f) < 0.01f) return white;
                return c;
            });
            // highway: double yellow, dashed lane lines, edge lines
            var road4 = NoiseTex("T_Road4", asphaltA, asphaltB, 1.5f, 256, (x, y, c) =>
            {
                float u = x / 255f, v = y / 255f;
                if (Mathf.Abs(u - 0.49f) < 0.008f || Mathf.Abs(u - 0.51f) < 0.008f) return yellow;
                if ((Mathf.Abs(u - 0.26f) < 0.007f || Mathf.Abs(u - 0.74f) < 0.007f) && (v % 0.5f) < 0.26f) return white;
                if (Mathf.Abs(u - 0.035f) < 0.007f || Mathf.Abs(u - 0.965f) < 0.007f) return white;
                return c;
            });
            var plain = NoiseTex("T_Asphalt", asphaltA, asphaltB, 2f);
            var runway = NoiseTex("T_Runway", new Color(0.21f, 0.22f, 0.23f), new Color(0.28f, 0.29f, 0.3f), 1.5f, 256, (x, y, c) =>
            {
                float u = x / 255f, v = y / 255f;
                if (Mathf.Abs(u - 0.5f) < 0.01f && (v % 0.5f) < 0.3f) return Color.white;
                if (Mathf.Abs(u - 0.04f) < 0.008f || Mathf.Abs(u - 0.96f) < 0.008f) return Color.white;
                return c;
            });
            var sidewalk = NoiseTex("T_Sidewalk", new Color(0.72f, 0.70f, 0.66f), new Color(0.80f, 0.78f, 0.73f), 1f, 256, (x, y, c) => (x % 64 < 2 || y % 64 < 2) ? c * 0.84f : c);
            var grass = NoiseTex("T_Grass", new Color(0.36f, 0.55f, 0.26f), new Color(0.50f, 0.67f, 0.32f), 2.5f);
            var sand = NoiseTex("T_Sand", new Color(0.86f, 0.78f, 0.6f), new Color(0.94f, 0.87f, 0.69f), 3f);
            var rock = NoiseTex("T_Rock", new Color(0.45f, 0.43f, 0.40f), new Color(0.62f, 0.60f, 0.55f), 3.5f);
            var dirt = NoiseTex("T_Dirt", new Color(0.55f, 0.44f, 0.31f), new Color(0.65f, 0.53f, 0.38f), 3f);
            var seabed = NoiseTex("T_Seabed", new Color(0.62f, 0.60f, 0.47f), new Color(0.74f, 0.70f, 0.53f), 3f);
            var planks = NoiseTex("T_Planks", new Color(0.52f, 0.38f, 0.25f), new Color(0.61f, 0.46f, 0.31f), 1.5f, 256, (x, y, c) => (y % 32 < 2) ? c * 0.7f : c);
            Mat("W_Road2", Color.white, 0.25f, road2);
            Mat("W_Road4", Color.white, 0.25f, road4);
            Mat("W_Asphalt", Color.white, 0.22f, plain);
            Mat("W_Runway", Color.white, 0.2f, runway);
            Mat("W_Sidewalk", Color.white, 0.15f, sidewalk);
            Mat("W_Park", Color.white, 0.05f, grass);
            Mat("W_Plaza", new Color(0.95f, 0.88f, 0.78f), 0.2f, sidewalk);
            Mat("W_Industrial", new Color(0.80f, 0.78f, 0.74f), 0.1f, plain);
            Mat("W_Planks", Color.white, 0.1f, planks);
            Mat("W_Crosswalk", new Color(0.93f, 0.93f, 0.91f), 0.2f);
            Mat("W_Quay", new Color(0.66f, 0.64f, 0.60f), 0.1f, sidewalk);
            terrainTex = new[] { sand, grass, rock, dirt, seabed };
        }

        static Texture2D[] terrainTex;

        // ------------------------------------------------------------------ terrain
        static float Smooth(float t) { t = Mathf.Clamp01(t); return t * t * (3f - 2f * t); }

        public static float Height(float x, float z)
        {
            float h = CityY;
            // west coast: docks quay (|z| < 82) or beach
            if (x < -208f)
            {
                if (z > -82f && z < 82f) h = x < QuayEdge ? Mathf.Lerp(-6f, -13f, Mathf.InverseLerp(QuayEdge, -330f, x)) : CityY;
                else
                {
                    float t1 = Mathf.InverseLerp(-212f, -252f, x);
                    h = x > -252f ? Mathf.Lerp(CityY, -2.5f, Smooth(t1)) : Mathf.Lerp(-2.5f, -14f, Mathf.InverseLerp(-252f, -340f, x));
                }
            }
            if (z < -286f) h = Mathf.Min(h, Mathf.Lerp(CityY, -12f, Mathf.InverseLerp(-286f, -340f, z)));   // south coast
            if (z > 284f) h = Mathf.Min(h, Mathf.Lerp(CityY, -12f, Mathf.InverseLerp(284f, 330f, z)));     // north coast
            if (x > 296f) h = Mathf.Min(h, Mathf.Lerp(CityY, -12f, Mathf.InverseLerp(296f, 340f, x)));     // east coast
            // lighthouse promontory
            float dp = Vector2.Distance(new Vector2(x, z), PointCentre);
            if (dp < 32f) h = Mathf.Max(h, Mathf.Lerp(CityY + 3.5f, h, Smooth(Mathf.InverseLerp(13f, 32f, dp))));
            // Crown Hill (flat summit, noisy flanks)
            float d = Vector2.Distance(new Vector2(x, z), HillCentre);
            if (d < HillRadius)
            {
                float k = 1f - d / HillRadius;
                float hill = HillHeight * Smooth(k * 1.25f);
                hill += (Mathf.PerlinNoise(x * 0.045f, z * 0.045f) - 0.5f) * 10f * k * (1f - k);
                h = Mathf.Max(h, CityY + hill);
            }
            if (h < CityY - 0.5f) h += (Mathf.PerlinNoise(x * 0.03f + 10f, z * 0.03f) - 0.5f) * 1.6f;
            return h;
        }

        static void BuildTerrain()
        {
            const int res = 513;
            const float size = 800f, minY = -20f, range = 80f;
            var td = new TerrainData { heightmapResolution = res, size = new Vector3(size, range, size) };
            var heights = new float[res, res];
            for (int iz = 0; iz < res; iz++)
                for (int ix = 0; ix < res; ix++)
                {
                    float x = -size / 2 + ix * size / (res - 1), z = -size / 2 + iz * size / (res - 1);
                    heights[iz, ix] = Mathf.Clamp01((Height(x, z) - minY) / range);
                }
            td.SetHeights(0, 0, heights);
            var layers = new TerrainLayer[terrainTex.Length];
            string[] names = { "TL_Sand", "TL_Grass", "TL_Rock", "TL_Dirt", "TL_Seabed" };
            float[] tiles = { 8f, 9f, 10f, 8f, 10f };
            for (int i = 0; i < layers.Length; i++)
            {
                string p = Pipeline.Gen + "/" + names[i] + ".terrainlayer";
                var tl = AssetDatabase.LoadAssetAtPath<TerrainLayer>(p);
                if (tl == null) { tl = new TerrainLayer(); AssetDatabase.CreateAsset(tl, p); }
                tl.diffuseTexture = terrainTex[i]; tl.tileSize = new Vector2(tiles[i], tiles[i]); tl.smoothness = 0.05f;
                EditorUtility.SetDirty(tl);
                layers[i] = tl;
            }
            td.terrainLayers = layers;
            td.alphamapResolution = 512;
            int ar = td.alphamapResolution;
            var alpha = new float[ar, ar, layers.Length];
            for (int iz = 0; iz < ar; iz++)
                for (int ix = 0; ix < ar; ix++)
                {
                    float x = -size / 2 + ix * size / (ar - 1), z = -size / 2 + iz * size / (ar - 1);
                    float h = Height(x, z);
                    float hx = Height(x + 1.5f, z) - h, hz = Height(x, z + 1.5f) - h;
                    float slope = Mathf.Sqrt(hx * hx + hz * hz) / 1.5f;
                    int layer;
                    bool hill = Vector2.Distance(new Vector2(x, z), HillCentre) < HillRadius + 6f;
                    if (h < -0.6f) layer = 4;
                    else if (h < CityY - 0.05f || (x < -208f && h < CityY + 0.3f)) layer = 0;
                    else if (slope > 0.7f) layer = 2;
                    else if (hill) layer = PathMask(x, z) ? 3 : 1;
                    else if (z < -177f && z > -290f && x > -195f) layer = (Mathf.PerlinNoise(x * 0.05f, z * 0.05f) > 0.72f) ? 3 : 1;
                    else layer = 1;
                    alpha[iz, ix, layer] = 1f;
                }
            td.SetAlphamaps(0, 0, alpha);
            string tdPath = Pipeline.Gen + "/Terrain_PortHalcyon.asset";
            if (AssetDatabase.LoadAssetAtPath<TerrainData>(tdPath) != null) AssetDatabase.DeleteAsset(tdPath);
            AssetDatabase.CreateAsset(td, tdPath);
            var tgo = Terrain.CreateTerrainGameObject(td);
            tgo.name = "Terrain";
            tgo.transform.position = new Vector3(-size / 2, minY, -size / 2);
            var terrain = tgo.GetComponent<Terrain>();
            string tmPath = Pipeline.Mats + "/M_Terrain.mat";
            var tm = AssetDatabase.LoadAssetAtPath<Material>(tmPath);
            var tsh = Shader.Find("Universal Render Pipeline/Terrain/Lit");
            if (tm == null && tsh != null) { tm = new Material(tsh) { name = "M_Terrain" }; AssetDatabase.CreateAsset(tm, tmPath); }
            if (tm != null) terrain.materialTemplate = tm;
            terrain.heightmapPixelError = 3f;
            terrain.basemapDistance = 600f;
            terrain.drawInstanced = true;
            GameObjectUtility.SetStaticEditorFlags(tgo, StaticEditorFlags.BatchingStatic | StaticEditorFlags.OccludeeStatic);
            tgo.transform.SetParent(root);
            terrainRef = terrain;
        }

        static readonly List<Vector2> hillPath = new List<Vector2>();
        static bool PathMask(float x, float z)
        {
            if (hillPath.Count == 0) BuildHillPathPoints();
            var p = new Vector2(x, z);
            for (int i = 0; i < hillPath.Count - 1; i++)
            {
                var a = hillPath[i]; var b = hillPath[i + 1];
                var ab = b - a; float t = Mathf.Clamp01(Vector2.Dot(p - a, ab) / ab.sqrMagnitude);
                if (Vector2.Distance(p, a + ab * t) < 2.6f) return true;
            }
            return false;
        }

        static void BuildHillPathPoints()
        {
            hillPath.Clear();
            // spiral trail from the eastern foot (road x = -30) up to the summit
            for (int i = 0; i <= 48; i++)
            {
                float t = i / 48f;
                float ang = Mathf.Lerp(-0.25f, 5.2f, t);
                float r = Mathf.Lerp(HillRadius + 14f, 6f, t);
                hillPath.Add(HillCentre + new Vector2(Mathf.Cos(ang), Mathf.Sin(ang)) * r);
            }
        }

        // ------------------------------------------------------------------ water
        static void BuildWater()
        {
            var db = Pipeline.Db();
            int n = 160; float size = 2600f;
            var verts = new List<Vector3>(); var tris = new List<int>();
            for (int z = 0; z <= n; z++) for (int x = 0; x <= n; x++) verts.Add(new Vector3(-size / 2 + x * size / n, 0f, -size / 2 + z * size / n));
            for (int z = 0; z < n; z++)
                for (int x = 0; x < n; x++)
                {
                    int i = z * (n + 1) + x;
                    tris.Add(i); tris.Add(i + n + 1); tris.Add(i + 1);
                    tris.Add(i + 1); tris.Add(i + n + 1); tris.Add(i + n + 2);
                }
            var mesh = new Mesh { indexFormat = IndexFormat.UInt32, name = "SeaMesh" };
            mesh.SetVertices(verts); mesh.SetTriangles(tris, 0); mesh.RecalculateNormals(); mesh.RecalculateBounds();
            SaveMesh(mesh);
            var go = new GameObject("Sea");
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = db.waterMaterial;
            mr.shadowCastingMode = ShadowCastingMode.Off;
            go.layer = Layers.Water;
            go.transform.SetParent(root);
        }

        // ------------------------------------------------------------------ meshes
        class MeshAcc
        {
            public readonly List<Vector3> v = new List<Vector3>();
            public readonly List<Vector2> uv = new List<Vector2>();
            public readonly List<int> t = new List<int>();

            public void Quad(Vector3 a, Vector3 b, Vector3 c, Vector3 d, Vector2 ua, Vector2 ub, Vector2 uc, Vector2 ud)
            {
                int i = v.Count;
                v.Add(a); v.Add(b); v.Add(c); v.Add(d);
                uv.Add(ua); uv.Add(ub); uv.Add(uc); uv.Add(ud);
                t.Add(i); t.Add(i + 1); t.Add(i + 2); t.Add(i); t.Add(i + 2); t.Add(i + 3);
            }

            /// <summary>Upward-facing strip from a to b: u across the width, v along the length (vScale per metre).</summary>
            public void Strip(Vector3 a, Vector3 b, float width, float y, float vScale)
            {
                var dir = b - a; dir.y = 0f; float len = dir.magnitude; dir /= Mathf.Max(len, 1e-4f);
                var side = Vector3.Cross(Vector3.up, dir) * width * 0.5f;
                var p0 = new Vector3(a.x, y, a.z); var p1 = new Vector3(b.x, y, b.z);
                Quad(p0 - side, p1 - side, p1 + side, p0 + side, new Vector2(0f, 0f), new Vector2(0f, len * vScale), new Vector2(1f, len * vScale), new Vector2(1f, 0f));
            }

            /// <summary>Upward-facing world-aligned rectangle with world-space UVs.</summary>
            public void FlatRect(Rect r, float y, float uvScale)
            {
                Quad(new Vector3(r.xMin, y, r.yMin), new Vector3(r.xMin, y, r.yMax), new Vector3(r.xMax, y, r.yMax), new Vector3(r.xMax, y, r.yMin),
                     new Vector2(r.xMin, r.yMin) * uvScale, new Vector2(r.xMin, r.yMax) * uvScale, new Vector2(r.xMax, r.yMax) * uvScale, new Vector2(r.xMax, r.yMin) * uvScale);
            }

            public GameObject Flush(string name, Material m, Transform parent, bool collider)
            {
                if (v.Count == 0) return null;
                var mesh = new Mesh { name = name, indexFormat = v.Count > 60000 ? IndexFormat.UInt32 : IndexFormat.UInt16 };
                mesh.SetVertices(v); mesh.SetUVs(0, uv); mesh.SetTriangles(t, 0);
                mesh.RecalculateNormals(); mesh.RecalculateBounds();
                SaveMesh(mesh);
                return MeshObject(name, mesh, m, parent, collider);
            }
        }

        static GameObject MeshObject(string name, Mesh mesh, Material mat, Transform parent, bool collider = false, bool shadows = false)
        {
            var go = new GameObject(name);
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = mat;
            mr.shadowCastingMode = shadows ? ShadowCastingMode.On : ShadowCastingMode.Off;
            if (collider) go.AddComponent<MeshCollider>().sharedMesh = mesh;
            go.transform.SetParent(parent, false);
            GameObjectUtility.SetStaticEditorFlags(go, StaticEditorFlags.BatchingStatic | StaticEditorFlags.OccludeeStatic);
            return go;
        }

        static void SaveMesh(Mesh m)
        {
            string dir = Pipeline.Gen + "/WorldMeshes";
            Directory.CreateDirectory(dir);
            string p = dir + "/" + m.name + ".asset";
            if (AssetDatabase.LoadAssetAtPath<Mesh>(p) != null) AssetDatabase.DeleteAsset(p);
            AssetDatabase.CreateAsset(m, p);
        }

        static Mesh BoxMesh(string name, Vector3 size, float uvScale)
        {
            var m = new Mesh { name = name };
            var h = size * 0.5f;
            Vector3[] c = {
                new Vector3(-h.x, -h.y, -h.z), new Vector3(h.x, -h.y, -h.z), new Vector3(h.x, h.y, -h.z), new Vector3(-h.x, h.y, -h.z),
                new Vector3(-h.x, -h.y, h.z), new Vector3(h.x, -h.y, h.z), new Vector3(h.x, h.y, h.z), new Vector3(-h.x, h.y, h.z) };
            // top, -x, +x, -z, +z (bottom omitted: always buried)
            int[][] faces = { new[] { 3, 7, 6, 2 }, new[] { 4, 7, 3, 0 }, new[] { 1, 2, 6, 5 }, new[] { 0, 3, 2, 1 }, new[] { 5, 6, 7, 4 } };
            var v = new List<Vector3>(); var uv = new List<Vector2>(); var t = new List<int>();
            foreach (var f in faces)
            {
                int b0 = v.Count;
                var n = Vector3.Cross(c[f[1]] - c[f[0]], c[f[2]] - c[f[0]]).normalized;
                for (int k = 0; k < 4; k++)
                {
                    var p = c[f[k]]; v.Add(p);
                    uv.Add((Mathf.Abs(n.y) > 0.5f ? new Vector2(p.x, p.z) : (Mathf.Abs(n.x) > 0.5f ? new Vector2(p.z, p.y) : new Vector2(p.x, p.y))) * uvScale);
                }
                t.Add(b0); t.Add(b0 + 1); t.Add(b0 + 2); t.Add(b0); t.Add(b0 + 2); t.Add(b0 + 3);
            }
            m.SetVertices(v); m.SetUVs(0, uv); m.SetTriangles(t, 0); m.RecalculateNormals(); m.RecalculateBounds();
            return m;
        }

        /// <summary>Solid box object (top at topY) with collider, used for plates, quays and walls.</summary>
        static GameObject Slab(string name, Rect r, float bottomY, float topY, Material m, Transform parent, float uvScale = 0.25f)
        {
            var size = new Vector3(r.width, topY - bottomY, r.height);
            var mesh = BoxMesh(name, size, uvScale);
            SaveMesh(mesh);
            var go = MeshObject(name, mesh, m, parent, false, false);
            go.transform.position = new Vector3(r.center.x, (topY + bottomY) * 0.5f, r.center.y);
            var bc = go.AddComponent<BoxCollider>(); bc.size = size;
            return go;
        }

        // ------------------------------------------------------------------ roads
        public static List<Vector3> junctionNodes = new List<Vector3>();

        static List<Vector3> ArmsAt(Vector3 n, out float maxWidth)
        {
            var arms = new List<Vector3>(); maxWidth = 0f;
            foreach (var s in data.roads)
            {
                if ((s.a - n).sqrMagnitude < 1f) { arms.Add((s.b - s.a).normalized); maxWidth = Mathf.Max(maxWidth, s.width); }
                else if ((s.b - n).sqrMagnitude < 1f) { arms.Add((s.a - s.b).normalized); maxWidth = Mathf.Max(maxWidth, s.width); }
            }
            return arms;
        }

        static void BuildRoadMeshes()
        {
            var acc2 = new MeshAcc(); var acc4 = new MeshAcc(); var accJ = new MeshAcc(); var accZ = new MeshAcc();
            foreach (var s in data.roads)
            {
                var dir = (s.b - s.a).normalized;
                var a = s.a + dir * 6f; var b = s.b - dir * 6f;
                (s.highway ? acc4 : acc2).Strip(a, b, s.width, RoadY, 1f / 12f);
            }
            var nodes = new List<Vector3>();
            foreach (var s in data.roads)
                foreach (var p in new[] { s.a, s.b })
                {
                    bool exists = false;
                    foreach (var n in nodes) if ((n - p).sqrMagnitude < 1f) { exists = true; break; }
                    if (!exists) nodes.Add(p);
                }
            foreach (var n in nodes)
            {
                var arms = ArmsAt(n, out float w);
                float hw = w * 0.5f + 0.6f;
                accJ.FlatRect(Rect.MinMaxRect(n.x - hw, n.z - hw, n.x + hw, n.z + hw), RoadY + 0.004f, 0.1f);
                // zebra crossings on every approach of city junctions
                if (arms.Count < 3 || n.x < -205f || n.z < -175f) continue;
                foreach (var dirS in arms)
                {
                    var right = Vector3.Cross(Vector3.up, dirS);
                    for (int k = -3; k <= 3; k++)
                    {
                        var c = n + dirS * (w * 0.5f + 2.4f) + right * (k * 1.3f);
                        accZ.Strip(c - dirS * 1.5f, c + dirS * 1.5f, 0.6f, RoadY + 0.008f, 0.3f);
                    }
                }
            }
            acc2.Flush("Roads_Street", mats["W_Road2"], roadRoot, false);
            acc4.Flush("Roads_Highway", mats["W_Road4"], roadRoot, false);
            accJ.Flush("Roads_Junctions", mats["W_Asphalt"], roadRoot, false);
            accZ.Flush("Roads_Crosswalks", mats["W_Crosswalk"], roadRoot, false);
            junctionNodes = nodes;
        }

        // ------------------------------------------------------------------ plates (blocks)
        public class Block
        {
            public Rect rect;          // usable plate area (x,z)
            public string district;
            public int ix, iz;
        }

        static readonly List<Block> blocks = new List<Block>();

        static void BuildPlatesAndContent()
        {
            blocks.Clear();
            for (int ix = 0; ix < XS.Length - 1; ix++)
                for (int iz = 0; iz < ZS.Length - 1; iz++)
                {
                    float x0 = XS[ix], x1 = XS[ix + 1], z0 = ZS[iz], z1 = ZS[iz + 1];
                    float cx = (x0 + x1) * 0.5f, cz = (z0 + z1) * 0.5f;
                    if (cx < -30f && cz > 70f) continue; // Crown Hill natural area
                    string district = cz < 70f ? (cx < 150f ? "Downtown" : "Industrial") : "Residential";
                    float l = x0 + Mathf.Max(HalfWidthOn(false, x0, z0, z1), 5.5f);
                    float r = x1 - Mathf.Max(HalfWidthOn(false, x1, z0, z1), 5.5f);
                    float b = z0 + Mathf.Max(HalfWidthOn(true, z0, x0, x1), 5.5f);
                    float t = z1 - Mathf.Max(HalfWidthOn(true, z1, x0, x1), 5.5f);
                    var blk = new Block { rect = Rect.MinMaxRect(l, b, r, t), district = district, ix = ix, iz = iz };
                    blocks.Add(blk);
                    string matName = district == "Industrial" ? "W_Industrial" : district == "Residential" ? "W_Park" : "W_Sidewalk";
                    if (IsPark(blk)) matName = "W_Park";
                    if (IsPlaza(blk)) matName = "W_Plaza";
                    Slab("Plate_" + district + "_" + ix + "_" + iz, blk.rect, CityY - 0.2f, PlateTop, mats[matName], roadRoot);
                }
            foreach (var blk in blocks) FillBlock(blk);
        }

        static bool IsPark(Block b) => b.ix == 4 && b.iz == 4;
        static bool IsPlaza(Block b) => b.ix == 3 && b.iz == 2;

        // ------------------------------------------------------------------ lighting & post
        static void BuildLighting()
        {
            var db = Pipeline.Db();
            var sunGO = new GameObject("Sun");
            var sun = sunGO.AddComponent<Light>();
            sun.type = LightType.Directional; sun.shadows = LightShadows.Soft; sun.intensity = 1.3f; sun.color = new Color(1f, 0.96f, 0.9f);
            sun.shadowStrength = 0.85f;
            sunGO.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
            var moonGO = new GameObject("Moon");
            var moon = moonGO.AddComponent<Light>();
            moon.type = LightType.Directional; moon.shadows = LightShadows.None; moon.intensity = 0.2f; moon.color = new Color(0.6f, 0.7f, 1f);
            RenderSettings.sun = sun;
            RenderSettings.skybox = db.skyMaterial;
            RenderSettings.ambientMode = AmbientMode.Trilight;
            RenderSettings.ambientSkyColor = new Color(0.62f, 0.70f, 0.82f);
            RenderSettings.ambientEquatorColor = new Color(0.58f, 0.60f, 0.58f);
            RenderSettings.ambientGroundColor = new Color(0.32f, 0.30f, 0.27f);
            RenderSettings.fog = true;
            RenderSettings.fogMode = FogMode.ExponentialSquared;
            RenderSettings.fogDensity = 0.0016f;
            RenderSettings.fogColor = new Color(0.66f, 0.74f, 0.83f);

            string pp = "Assets/GTA/Settings_PortHalcyon_Volume.asset";
            if (AssetDatabase.LoadAssetAtPath<VolumeProfile>(pp) != null) AssetDatabase.DeleteAsset(pp);
            var profile = ScriptableObject.CreateInstance<VolumeProfile>();
            AssetDatabase.CreateAsset(profile, pp);
            var tone = profile.Add<Tonemapping>(true); tone.mode.Override(TonemappingMode.ACES); AssetDatabase.AddObjectToAsset(tone, profile);
            var bloom = profile.Add<Bloom>(true); bloom.intensity.Override(0.55f); bloom.threshold.Override(1.05f); bloom.scatter.Override(0.65f); AssetDatabase.AddObjectToAsset(bloom, profile);
            var ca = profile.Add<ColorAdjustments>(true); ca.postExposure.Override(0.3f); ca.contrast.Override(10f); ca.saturation.Override(14f); AssetDatabase.AddObjectToAsset(ca, profile);
            var vig = profile.Add<Vignette>(true); vig.intensity.Override(0.2f); vig.smoothness.Override(0.4f); AssetDatabase.AddObjectToAsset(vig, profile);
            var wb = profile.Add<WhiteBalance>(true); wb.temperature.Override(6f); AssetDatabase.AddObjectToAsset(wb, profile);
            EditorUtility.SetDirty(profile);
            var volGO = new GameObject("GlobalVolume");
            var vol = volGO.AddComponent<Volume>(); vol.isGlobal = true; vol.sharedProfile = profile; vol.priority = 1;

            var camGO = new GameObject("Main Camera");
            camGO.tag = "MainCamera";
            var cam = camGO.AddComponent<Camera>();
            cam.farClipPlane = 1800f; cam.nearClipPlane = 0.1f; cam.fieldOfView = 62f;
            camGO.AddComponent<AudioListener>();
            var acd = camGO.AddComponent<UniversalAdditionalCameraData>();
            acd.renderPostProcessing = true;
            acd.antialiasing = AntialiasingMode.None;
            camGO.transform.position = data.playerSpawn + new Vector3(0f, 3f, 5f);
            camGO.transform.LookAt(data.playerSpawn + Vector3.up * 1.5f);

            var boot = new GameObject("GameBootstrap");
            var gb = boot.AddComponent<GameBootstrap>();
            gb.sun = sun; gb.moon = moon; gb.mainCamera = cam;
        }

        // ------------------------------------------------------------------ map paint
        static void PaintMap()
        {
            void P(Vector3 c, Vector2 s, Color col) => data.mapPaint.Add(new WorldData.Paint { centre = c, size = s, color = col });
            void C(Vector2 c, float r, Color col) => data.mapPaint.Add(new WorldData.Paint { centre = new Vector3(c.x, 0f, c.y), size = new Vector2(r, 0f), color = col, circle = true });
            data.mapGround = new Color(0.30f, 0.56f, 0.68f);     // sea fill
            var sand = new Color(0.93f, 0.86f, 0.66f); var land = new Color(0.62f, 0.76f, 0.50f);
            P(new Vector3(36f, 0f, -1.5f), new Vector2(532f, 585f), sand);
            P(new Vector3(40f, 0f, -1.5f), new Vector2(500f, 560f), land);
            P(new Vector3(-222f, 0f, 0f), new Vector2(28f, 164f), new Color(0.70f, 0.70f, 0.68f));          // quay
            C(PointCentre, 14f, new Color(0.6f, 0.62f, 0.55f));
            C(HillCentre, HillRadius, new Color(0.44f, 0.62f, 0.38f));
            C(HillCentre, HillRadius * 0.45f, new Color(0.38f, 0.55f, 0.33f));
            foreach (var b in blocks)
            {
                var col = b.district == "Industrial" ? new Color(0.78f, 0.74f, 0.68f) : b.district == "Residential" ? new Color(0.80f, 0.88f, 0.72f) : new Color(0.88f, 0.86f, 0.82f);
                if (IsPark(b)) col = new Color(0.52f, 0.74f, 0.44f);
                if (IsPlaza(b)) col = new Color(0.95f, 0.88f, 0.76f);
                P(new Vector3(b.rect.center.x, 0f, b.rect.center.y), new Vector2(b.rect.width, b.rect.height), col);
            }
            P(new Vector3(30f, 0f, -247f), new Vector2(440f, 30f), new Color(0.35f, 0.35f, 0.37f));          // runway
            P(new Vector3(25f, 0f, -217.5f), new Vector2(350f, 29f), new Color(0.5f, 0.5f, 0.52f));           // apron
            foreach (var fp in buildingFootprints) P(new Vector3(fp.center.x, 0f, fp.center.y), fp.size, new Color(0.60f, 0.58f, 0.57f));
            foreach (var r in data.roads)
            {
                var c = (r.a + r.b) * 0.5f;
                bool horiz = Mathf.Abs(r.b.x - r.a.x) > Mathf.Abs(r.b.z - r.a.z);
                float len = (r.b - r.a).magnitude + r.width;
                P(c, horiz ? new Vector2(len, r.width) : new Vector2(r.width, len), r.highway ? new Color(0.98f, 0.82f, 0.42f) : Color.white);
            }
        }
    }
}
