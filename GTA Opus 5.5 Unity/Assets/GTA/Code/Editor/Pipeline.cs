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
    /// Reproducible editor pipeline (runs in -batchmode): project settings, material library, prefab generation from the
    /// Blender FBX exports, game database, world scene and desktop builds.
    /// </summary>
    public static class Pipeline
    {
        public const string Gen = "Assets/GTA/Generated";
        public const string Models = Gen + "/Models";
        public const string Mats = Gen + "/Materials";
        public const string Tex = Gen + "/Textures";
        public const string Prefabs = "Assets/GTA/Prefabs";
        public const string DbPath = "Assets/GTA/Resources/GameDatabase.asset";
        public const string ScenePath = "Assets/GTA/Scenes/PortHalcyon.unity";

        [MenuItem("Halcyon/1 Setup Project")]
        public static void SetupProject()
        {
            // layers
            var tm = new SerializedObject(AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/TagManager.asset")[0]);
            var layers = tm.FindProperty("layers");
            string[] names = { null, null, null, null, null, null, "Player", "Vehicle", "NPC", "Ragdoll", "Projectile", "Trigger", "Prop", "Debris" };
            for (int i = 6; i < names.Length; i++) layers.GetArrayElementAtIndex(i).stringValue = names[i];
            tm.ApplyModifiedPropertiesWithoutUndo();

            PlayerSettings.productName = "Port Halcyon";
            PlayerSettings.companyName = "Opus55 Benchmark";
            PlayerSettings.defaultScreenWidth = 1920;
            PlayerSettings.defaultScreenHeight = 1080;
            PlayerSettings.fullScreenMode = FullScreenMode.Windowed;
            PlayerSettings.resizableWindow = true;
            PlayerSettings.runInBackground = true;
            PlayerSettings.colorSpace = ColorSpace.Linear;
            Time.fixedDeltaTime = 1f / 60f;

            // URP quality: longer shadows, depth texture for water, HDR, 4 cascades
            foreach (var guid in AssetDatabase.FindAssets("t:UniversalRenderPipelineAsset"))
            {
                var asset = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>(AssetDatabase.GUIDToAssetPath(guid));
                if (asset == null) continue;
                asset.shadowDistance = 140f;
                asset.shadowCascadeCount = 4;
                asset.supportsCameraDepthTexture = true;
                asset.supportsCameraOpaqueTexture = true;
                asset.supportsHDR = true;
                asset.msaaSampleCount = 4;
                var so = new SerializedObject(asset);
                var p = so.FindProperty("m_AdditionalLightsPerObjectLimit"); if (p != null) p.intValue = 8;
                p = so.FindProperty("m_MainLightShadowmapResolution"); if (p != null) p.intValue = 4096;
                p = so.FindProperty("m_SoftShadowsSupported"); if (p != null) p.boolValue = true;
                so.ApplyModifiedPropertiesWithoutUndo();
                EditorUtility.SetDirty(asset);
            }
            QualitySettings.lodBias = 1.6f;
            AssetDatabase.SaveAssets();
            Debug.Log("[Pipeline] project setup done");
        }

        // ------------------------------------------------------------------ materials & textures
        static readonly Dictionary<string, Material> lib = new Dictionary<string, Material>();

        static Shader Lit => Shader.Find("Universal Render Pipeline/Lit");

        public static Material LibraryMaterial(Material src, string name)
        {
            name = name.Replace(" (Instance)", "").Trim();
            if (lib.TryGetValue(name, out var m) && m != null) return m;
            string path = Mats + "/" + name + ".mat";
            m = AssetDatabase.LoadAssetAtPath<Material>(path);
            bool created = false;
            if (m == null) { m = new Material(Lit) { name = name }; created = true; }
            Color baseC = src != null && src.HasProperty("_BaseColor") ? src.GetColor("_BaseColor") : (src != null && src.HasProperty("_Color") ? src.GetColor("_Color") : Color.gray);
            ConfigureLit(m, name, baseC);
            if (created) AssetDatabase.CreateAsset(m, path); else EditorUtility.SetDirty(m);
            lib[name] = m;
            return m;
        }

        static bool Has(string n, params string[] keys) { foreach (var k in keys) if (n.Contains(k)) return true; return false; }

        public static void ConfigureLit(Material m, string name, Color c)
        {
            m.shader = Lit;
            c.a = 1f;
            float smooth = 0.32f, metal = 0f;
            if (Has(name, "Paint")) smooth = 0.72f;
            if (Has(name, "Chrome", "Blade")) { metal = 1f; smooth = 0.9f; }
            if (Has(name, "Rim", "GunMetal", "Badge", "Steel", "Metal", "Emblem")) { metal = 0.75f; smooth = 0.55f; }
            if (Has(name, "Tire", "Grip", "Rubber")) smooth = 0.1f;
            if (Has(name, "Plastic", "Polymer")) smooth = 0.35f;
            if (Has(name, "Water")) smooth = 0.95f;
            m.SetColor("_BaseColor", c);
            m.SetFloat("_Smoothness", smooth);
            m.SetFloat("_Metallic", metal);
            m.SetFloat("_SpecularHighlights", 1f);
            m.enableInstancing = true;
            bool glass = Has(name, "Glass", "Window") && !Has(name, "WindowLit");
            if (glass)
            {
                c.a = 0.62f;
                m.SetColor("_BaseColor", c);
                m.SetFloat("_Smoothness", 0.95f);
                m.SetFloat("_Surface", 1f);
                m.SetFloat("_Blend", 0f);
                m.SetOverrideTag("RenderType", "Transparent");
                m.SetFloat("_SrcBlend", (float)BlendMode.SrcAlpha);
                m.SetFloat("_DstBlend", (float)BlendMode.OneMinusSrcAlpha);
                m.SetFloat("_SrcBlendAlpha", (float)BlendMode.One);
                m.SetFloat("_DstBlendAlpha", (float)BlendMode.OneMinusSrcAlpha);
                m.SetFloat("_ZWrite", 0f);
                m.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
                m.renderQueue = (int)RenderQueue.Transparent;
                if (Has(name, "Window")) { c.a = 1f; m.SetColor("_BaseColor", c); m.SetFloat("_Surface", 0f); m.DisableKeyword("_SURFACE_TYPE_TRANSPARENT"); m.SetFloat("_ZWrite", 1f); m.SetFloat("_SrcBlend", 1f); m.SetFloat("_DstBlend", 0f); m.renderQueue = -1; m.SetOverrideTag("RenderType", "Opaque"); }
            }
            else
            {
                m.SetFloat("_Surface", 0f);
                m.DisableKeyword("_SURFACE_TYPE_TRANSPARENT");
                m.SetFloat("_ZWrite", 1f);
                m.SetFloat("_SrcBlend", 1f); m.SetFloat("_DstBlend", 0f);
                m.renderQueue = -1;
            }
            bool emissive = Has(name, "Light", "Lamp", "Neon", "Glow", "Siren", "TaxiSign", "WindowLit", "Screen", "Signal", "Fire");
            if (emissive)
            {
                m.EnableKeyword("_EMISSION");
                m.globalIlluminationFlags = MaterialGlobalIlluminationFlags.RealtimeEmissive;
                float k = Has(name, "Neon", "Glow", "WindowLit", "Lamp", "Screen") ? 1.4f : 0.2f;
                m.SetColor("_EmissionColor", c * k);
            }
            else
            {
                m.DisableKeyword("_EMISSION");
                m.SetColor("_EmissionColor", Color.black);
            }
        }

        static Texture2D SaveTex(string name, Texture2D t, bool linear = false, bool normal = false)
        {
            string path = Tex + "/" + name + ".png";
            File.WriteAllBytes(path, t.EncodeToPNG());
            AssetDatabase.ImportAsset(path, ImportAssetOptions.ForceSynchronousImport);
            var ti = (TextureImporter)AssetImporter.GetAtPath(path);
            ti.sRGBTexture = !linear;
            ti.alphaIsTransparency = true;
            ti.wrapMode = TextureWrapMode.Repeat;
            ti.mipmapEnabled = true;
            ti.textureCompression = TextureImporterCompression.CompressedHQ;
            if (normal) ti.textureType = TextureImporterType.NormalMap;
            ti.SaveAndReimport();
            return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
        }

        public static Texture2D SoftCircle(int res = 64)
        {
            var t = new Texture2D(res, res, TextureFormat.RGBA32, false);
            for (int y = 0; y < res; y++)
                for (int x = 0; x < res; x++)
                {
                    float d = Vector2.Distance(new Vector2(x, y), new Vector2(res / 2f - 0.5f, res / 2f - 0.5f)) / (res / 2f);
                    float a = Mathf.Clamp01(1f - d); a = a * a * (3f - 2f * a);
                    t.SetPixel(x, y, new Color(1f, 1f, 1f, a));
                }
            t.Apply();
            return t;
        }

        static Texture2D HoleTex()
        {
            int res = 64;
            var t = new Texture2D(res, res, TextureFormat.RGBA32, false);
            var rnd = new System.Random(5);
            for (int y = 0; y < res; y++)
                for (int x = 0; x < res; x++)
                {
                    float d = Vector2.Distance(new Vector2(x, y), new Vector2(31.5f, 31.5f)) / 32f;
                    float core = d < 0.22f ? 1f : 0f;
                    float ring = Mathf.Clamp01(1f - (d - 0.2f) / 0.6f) * 0.55f * (0.7f + 0.3f * (float)rnd.NextDouble());
                    float a = Mathf.Max(core, ring);
                    t.SetPixel(x, y, new Color(0.05f, 0.05f, 0.05f, a));
                }
            t.Apply();
            return t;
        }

        static Material ParticleMat(string name, Texture2D tex, bool additive)
        {
            string path = Mats + "/" + name + ".mat";
            var sh = Shader.Find("Universal Render Pipeline/Particles/Unlit");
            var m = AssetDatabase.LoadAssetAtPath<Material>(path);
            bool created = m == null;
            if (created) m = new Material(sh) { name = name };
            m.shader = sh;
            m.SetTexture("_BaseMap", tex);
            m.SetColor("_BaseColor", Color.white);
            m.SetFloat("_Surface", 1f);
            m.SetFloat("_Blend", additive ? 2f : 0f);
            m.SetFloat("_SrcBlend", (float)BlendMode.SrcAlpha);
            m.SetFloat("_DstBlend", additive ? (float)BlendMode.One : (float)BlendMode.OneMinusSrcAlpha);
            m.SetFloat("_ZWrite", 0f);
            m.SetOverrideTag("RenderType", "Transparent");
            m.EnableKeyword("_SURFACE_TYPE_TRANSPARENT");
            if (additive) m.EnableKeyword("_BLENDMODE_ADD"); else m.DisableKeyword("_BLENDMODE_ADD");
            m.renderQueue = (int)RenderQueue.Transparent;
            if (created) AssetDatabase.CreateAsset(m, path); else EditorUtility.SetDirty(m);
            return m;
        }

        [MenuItem("Halcyon/2 Build Materials")]
        public static void BuildMaterials()
        {
            Directory.CreateDirectory(Mats); Directory.CreateDirectory(Tex);
            var soft = SaveTex("FX_Soft", SoftCircle());
            var hole = SaveTex("FX_Hole", HoleTex());
            var db = Db();
            db.fxAlpha = ParticleMat("FX_Alpha", soft, false);
            db.fxAdd = ParticleMat("FX_Additive", soft, true);
            db.decal = ParticleMat("FX_Decal", hole, false);
            db.line = ParticleMat("FX_Line", soft, true);
            var waterShader = Shader.Find("Halcyon/Water");
            if (waterShader != null)
            {
                var wm = AssetDatabase.LoadAssetAtPath<Material>(Mats + "/M_SeaWater.mat");
                if (wm == null) { wm = new Material(waterShader) { name = "M_SeaWater" }; AssetDatabase.CreateAsset(wm, Mats + "/M_SeaWater.mat"); }
                wm.shader = waterShader;
                db.waterMaterial = wm;
            }
            var skyShader = Shader.Find("Halcyon/Sky");
            if (skyShader != null)
            {
                var sm = AssetDatabase.LoadAssetAtPath<Material>(Mats + "/M_Sky.mat");
                if (sm == null) { sm = new Material(skyShader) { name = "M_Sky" }; AssetDatabase.CreateAsset(sm, Mats + "/M_Sky.mat"); }
                sm.shader = skyShader;
                db.skyMaterial = sm;
            }
            EditorUtility.SetDirty(db);
            AssetDatabase.SaveAssets();
            Debug.Log("[Pipeline] materials done");
        }

        public static GameDatabase Db()
        {
            var db = AssetDatabase.LoadAssetAtPath<GameDatabase>(DbPath);
            if (db == null)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(DbPath));
                db = ScriptableObject.CreateInstance<GameDatabase>();
                AssetDatabase.CreateAsset(db, DbPath);
            }
            return db;
        }

        // ------------------------------------------------------------------ prefabs
        [MenuItem("Halcyon/3 Build Prefabs")]
        public static void BuildPrefabs()
        {
            AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);
            var db = Db();
            db.entries.Clear();
            int n = 0;
            foreach (var guid in AssetDatabase.FindAssets("t:Model", new[] { Models }))
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                if (!path.EndsWith(".fbx")) continue;
                var id = Path.GetFileNameWithoutExtension(path);
                var category = Path.GetFileName(Path.GetDirectoryName(path));
                var prefab = BuildOne(path, id, category);
                if (prefab != null) { db.entries.Add(new GameDatabase.Entry { id = id, prefab = prefab }); n++; }
            }
            EditorUtility.SetDirty(db);
            AssetDatabase.SaveAssets();
            Debug.Log("[Pipeline] prefabs built: " + n);
        }

        static GameObject BuildOne(string fbxPath, string id, string category)
        {
            var model = AssetDatabase.LoadAssetAtPath<GameObject>(fbxPath);
            if (model == null) return null;
            string outDir = Prefabs + "/" + category;
            Directory.CreateDirectory(outDir);
            string outPath = outDir + "/" + id + ".prefab";

            var root = new GameObject(id);
            var inst = (GameObject)PrefabUtility.InstantiatePrefab(model);
            PrefabUtility.UnpackPrefabInstance(inst, PrefabUnpackMode.Completely, InteractionMode.AutomatedAction);
            inst.name = "Model";
            inst.transform.SetParent(root.transform, false);
            inst.transform.localPosition = Vector3.zero;
            // Blender -Y front lands on Unity -Z through the FBX importer; turn it to face +Z.
            inst.transform.localRotation = Quaternion.Euler(0f, 180f, 0f) * inst.transform.localRotation;

            // swap embedded FBX materials for shared library materials (same names as in Blender)
            foreach (var r in inst.GetComponentsInChildren<Renderer>(true))
            {
                var mats = r.sharedMaterials;
                for (int i = 0; i < mats.Length; i++) if (mats[i] != null) mats[i] = LibraryMaterial(mats[i], mats[i].name);
                r.sharedMaterials = mats;
                r.shadowCastingMode = ShadowCastingMode.On;
            }

            bool isStaticWorld = category == "Buildings" || category == "Props" || category == "Nature" || category == "Interiors" || category == "Misc";
            if (isStaticWorld) ConfigureStatic(root, inst, category, id);

            if (category == "Characters")
            {
                root.AddComponent<CharacterRig>();
                root.AddComponent<CharacterAppearance>().female = id.Contains("Female");
                foreach (var smr in inst.GetComponentsInChildren<SkinnedMeshRenderer>(true)) { smr.updateWhenOffscreen = false; smr.skinnedMotionVectors = false; }
            }
            if (category == "Weapons")
            {
                foreach (var r in inst.GetComponentsInChildren<Renderer>(true)) r.shadowCastingMode = ShadowCastingMode.Off;
            }
            if (category == "Vehicles")
            {
                foreach (var t in inst.GetComponentsInChildren<Transform>(true))
                    if (U.Role(t).StartsWith("COL_")) { var mr = t.GetComponent<MeshRenderer>(); if (mr) mr.enabled = false; }
                var lod = root.AddComponent<LODGroup>();
                var rs = new List<Renderer>();
                foreach (var r in inst.GetComponentsInChildren<Renderer>(true)) if (!U.Role(r.transform).StartsWith("COL_")) rs.Add(r);
                lod.SetLODs(new[] { new LOD(0.015f, rs.ToArray()) });
                lod.RecalculateBounds();
            }
            var prefab = PrefabUtility.SaveAsPrefabAsset(root, outPath);
            Object.DestroyImmediate(root);
            return prefab;
        }

        static void ConfigureStatic(GameObject root, GameObject inst, string category, string id)
        {
            var renderers = new List<Renderer>();
            bool hasCol = false;
            foreach (var t in inst.GetComponentsInChildren<Transform>(true))
            {
                var role = U.Role(t);
                if (role.StartsWith("COL_"))
                {
                    hasCol = true;
                    var mf = t.GetComponent<MeshFilter>();
                    var mr = t.GetComponent<MeshRenderer>();
                    if (mf != null && mf.sharedMesh != null)
                    {
                        var b = mf.sharedMesh.bounds;
                        bool boxy = mf.sharedMesh.vertexCount <= 24;
                        if (boxy) { var bc = t.gameObject.AddComponent<BoxCollider>(); bc.center = b.center; bc.size = b.size; }
                        else { var mc = t.gameObject.AddComponent<MeshCollider>(); mc.sharedMesh = mf.sharedMesh; }
                    }
                    if (mr) Object.DestroyImmediate(mr);
                    if (mf) Object.DestroyImmediate(mf);
                    continue;
                }
                var r = t.GetComponent<Renderer>();
                if (r != null) renderers.Add(r);
            }
            if (!hasCol)
            {
                foreach (var r in renderers)
                {
                    var mf = r.GetComponent<MeshFilter>();
                    if (mf == null || mf.sharedMesh == null) continue;
                    var role = U.Role(r.transform);
                    if (role.StartsWith("LEAF") || role.StartsWith("FX_") || role.StartsWith("GLOW")) continue;
                    if (category == "Nature")
                    {
                        var b = mf.sharedMesh.bounds;
                        if (role.StartsWith("TRUNK") || b.size.y > 1.2f && b.size.x < 1.2f) { var cc = r.gameObject.AddComponent<CapsuleCollider>(); cc.center = b.center; cc.height = b.size.y; cc.radius = Mathf.Min(b.size.x, b.size.z) * 0.35f; }
                        else if (id.Contains("Rock")) { var mc = r.gameObject.AddComponent<MeshCollider>(); mc.sharedMesh = mf.sharedMesh; mc.convex = true; }
                        continue;
                    }
                    if (category == "Props")
                    {
                        var b = mf.sharedMesh.bounds;
                        var bc = r.gameObject.AddComponent<BoxCollider>(); bc.center = b.center; bc.size = Vector3.Max(b.size, Vector3.one * 0.05f);
                        continue;
                    }
                    var col = r.gameObject.AddComponent<MeshCollider>();
                    col.sharedMesh = mf.sharedMesh;
                }
            }
            foreach (var t in root.GetComponentsInChildren<Transform>(true))
                GameObjectUtility.SetStaticEditorFlags(t.gameObject, category == "Props" ? (StaticEditorFlags.BatchingStatic | StaticEditorFlags.OccludeeStatic) : (StaticEditorFlags.BatchingStatic | StaticEditorFlags.OccluderStatic | StaticEditorFlags.OccludeeStatic));
            if (renderers.Count > 0)
            {
                var lod = root.AddComponent<LODGroup>();
                float cull = category == "Buildings" ? 0.006f : category == "Nature" ? 0.012f : 0.02f;
                lod.SetLODs(new[] { new LOD(cull, renderers.ToArray()) });
                lod.RecalculateBounds();
            }
        }

        // ------------------------------------------------------------------ build
        [MenuItem("Halcyon/5 Build Windows Player")]
        public static void BuildWindows()
        {
            BuildDesktopPlayer(BuildTarget.StandaloneWindows64, "Builds/PortHalcyon-Windows/PortHalcyon.exe");
        }

        [MenuItem("Halcyon/6 Build macOS Player")]
        public static void BuildMacOS()
        {
            var standalone = UnityEditor.Build.NamedBuildTarget.Standalone;
            int previousArchitecture = PlayerSettings.GetArchitecture(standalone);
            string platformName = BuildPipeline.GetBuildTargetName(BuildTarget.StandaloneOSX);
            string previousPlatformArchitecture = EditorUserBuildSettings.GetPlatformSettings(platformName, "Architecture");
            try
            {
                // Unity architecture values: 0 = x64, 1 = ARM64, 2 = Universal.
                PlayerSettings.SetArchitecture(standalone, 2);
                // Unity's desktop build window stores this per-platform value separately.
                EditorUserBuildSettings.SetPlatformSettings(platformName, "Architecture", "x64arm64");
                Debug.Log("[Pipeline] macOS architecture=" + EditorUserBuildSettings.GetPlatformSettings(platformName, "Architecture"));
                BuildDesktopPlayer(BuildTarget.StandaloneOSX, "Builds/PortHalcyon-macOS/Port Halcyon.app");
            }
            finally
            {
                PlayerSettings.SetArchitecture(standalone, previousArchitecture);
                EditorUserBuildSettings.SetPlatformSettings(platformName, "Architecture", previousPlatformArchitecture);
            }
        }

        [MenuItem("Halcyon/7 Build Windows + macOS Players")]
        public static void BuildDesktopPlayers()
        {
            BuildWindows();
            BuildMacOS();
        }

        static void BuildDesktopPlayer(BuildTarget target, string outputPath)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(outputPath));
            var scenes = new[] { ScenePath };
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
            var opts = new BuildPlayerOptions
            {
                scenes = scenes,
                locationPathName = outputPath,
                target = target,
                options = BuildOptions.None,
            };
            var report = BuildPipeline.BuildPlayer(opts);
            Debug.Log("[Pipeline] " + target + " build result: " + report.summary.result + " path=" + outputPath + " size=" + report.summary.totalSize + " errors=" + report.summary.totalErrors + " time=" + report.summary.totalTime);
            if (report.summary.result != UnityEditor.Build.Reporting.BuildResult.Succeeded)
                throw new UnityEditor.Build.BuildFailedException(target + " build failed with " + report.summary.totalErrors + " error(s).");
        }

        [MenuItem("Halcyon/Run Full Pipeline (no build)")]
        public static void RunAll()
        {
            SetupProject();
            BuildMaterials();
            BuildPrefabs();
            WorldBuilder.Build();
        }

        public static void RunAllAndBuild()
        {
            RunAll();
            BuildWindows();
        }

        public static void PrefabsWorldAndBuild()
        {
            BuildMaterials();
            BuildPrefabs();
            WorldBuilder.Build();
            BuildWindows();
        }
    }
}
