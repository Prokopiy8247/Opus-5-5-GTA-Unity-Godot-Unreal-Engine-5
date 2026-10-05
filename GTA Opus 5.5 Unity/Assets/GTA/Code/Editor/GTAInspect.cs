using System.Text;
using UnityEditor;
using UnityEngine;

namespace Halcyon.EditorTools
{
    /// <summary>Batch-mode diagnostics: dumps imported Blender models (hierarchy, transforms, materials).</summary>
    public static class GTAInspect
    {
        [MenuItem("Halcyon/Diagnostics/Inspect Models")]
        public static void InspectModels()
        {
            AssetDatabase.Refresh(ImportAssetOptions.ForceSynchronousImport);
            var sb = new StringBuilder();
            foreach (var guid in AssetDatabase.FindAssets("t:Model", new[] { "Assets/GTA/Generated/Models" }))
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                var go = AssetDatabase.LoadAssetAtPath<GameObject>(path);
                if (go == null) continue;
                sb.AppendLine("=== " + path);
                var inst = Object.Instantiate(go);
                foreach (var t in inst.GetComponentsInChildren<Transform>(true))
                    if (t.name.Contains("WHEEL_FL") || t.name.Contains("SEAT_0") || t.name.Contains("MUZZLE") || t.name == "Hand_L" || t.name == "Head" || t.name == "Foot_L" || t.name.EndsWith("__BODY"))
                        sb.AppendLine("  ROOTSPACE " + t.name + " pos=" + inst.transform.InverseTransformPoint(t.position).ToString("F3") + " fwd=" + inst.transform.InverseTransformDirection(t.forward).ToString("F2") + " up=" + inst.transform.InverseTransformDirection(t.up).ToString("F2"));
                foreach (var r in inst.GetComponentsInChildren<Renderer>(true))
                    if (r.name.EndsWith("__BODY") || r.name.EndsWith("__Body")) sb.AppendLine("  WORLDBOUNDS " + r.name + " " + r.bounds);
                Object.DestroyImmediate(inst);
                Dump(go.transform, 0, sb);
                foreach (var o in AssetDatabase.LoadAllAssetsAtPath(path))
                    if (o is Material m)
                        sb.AppendLine("  MAT " + m.name + " shader=" + m.shader.name + " base=" + (m.HasProperty("_BaseColor") ? m.GetColor("_BaseColor").ToString() : "-"));
            }
            System.IO.File.WriteAllText("QA/inspect_models.txt", sb.ToString());
            Debug.Log("[GTAInspect] wrote QA/inspect_models.txt");
        }

        static void Dump(Transform t, int depth, StringBuilder sb)
        {
            if (depth > 4) return;
            var line = new string(' ', depth * 2) + t.name + " lp=" + t.localPosition.ToString("F3") + " le=" + t.localEulerAngles.ToString("F1") + " ls=" + t.localScale.ToString("F2");
            var mf = t.GetComponent<MeshFilter>();
            if (mf && mf.sharedMesh) line += " mesh=" + mf.sharedMesh.name + " b=" + mf.sharedMesh.bounds;
            var smr = t.GetComponent<SkinnedMeshRenderer>();
            if (smr) line += " SKIN bones=" + smr.bones.Length + " root=" + (smr.rootBone ? smr.rootBone.name : "null") + " b=" + smr.sharedMesh.bounds;
            var r = t.GetComponent<Renderer>();
            if (r) { line += " mats=["; foreach (var m in r.sharedMaterials) line += (m ? m.name : "null") + ","; line += "]"; }
            sb.AppendLine(line);
            foreach (Transform c in t) Dump(c, depth + 1, sb);
        }
    }
}
