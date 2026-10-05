using UnityEditor;
using UnityEngine;

namespace Halcyon.EditorTools
{
    /// <summary>
    /// Import contract for every FBX exported from UnityOpus5.5GTA.blend through Blender MCP.
    /// Blender exports with -Z forward / Y up; "bakeAxisConversion" removes the -90° root rotation so
    /// models face +Z with identity transforms. Object roles are encoded in names as "Asset__ROLE".
    /// </summary>
    public class GTAModelPostprocessor : AssetPostprocessor
    {
        public const string ModelRoot = "Assets/GTA/Generated/Models/";

        void OnPreprocessModel()
        {
            if (!assetPath.StartsWith(ModelRoot)) return;
            var mi = (ModelImporter)assetImporter;
            mi.globalScale = 1f;
            mi.useFileScale = true;
            mi.bakeAxisConversion = true;
            mi.importCameras = false;
            mi.importLights = false;
            mi.importVisibility = false;
            mi.importBlendShapes = false;
            mi.importNormals = ModelImporterNormals.Import;
            mi.importTangents = ModelImporterTangents.CalculateMikk;
            mi.materialImportMode = ModelImporterMaterialImportMode.ImportViaMaterialDescription;
            mi.materialLocation = ModelImporterMaterialLocation.InPrefab;
            mi.meshCompression = ModelImporterMeshCompression.Off;
            // Vehicles need CPU access for the impact-deformation system.
            mi.isReadable = assetPath.Contains("/Vehicles/");
            mi.addCollider = false;
            mi.generateSecondaryUV = false;
            mi.animationType = ModelImporterAnimationType.None;
            mi.importAnimation = false;
            mi.optimizeGameObjects = false;
            mi.preserveHierarchy = false;
            mi.sortHierarchyByName = false;
            mi.weldVertices = false;
        }
    }
}
