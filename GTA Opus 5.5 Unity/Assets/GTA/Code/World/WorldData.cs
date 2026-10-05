using System;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Serialized world layout produced by the editor WorldBuilder (roads, landmarks, map paint, POIs).</summary>
    public class WorldData : MonoBehaviour
    {
        [Serializable] public class Seg { public Vector3 a, b; public float width; public bool highway; }
        [Serializable] public class Mark { public string name; public Vector3 pos; }
        [Serializable] public class Paint { public Vector3 centre; public Vector2 size; public float yaw; public Color color; public bool circle; }
        [Serializable] public class VSpawn { public string id; public Vector3 pos; public float yaw; }
        public List<VSpawn> vehicleSpawns = new List<VSpawn>();

        public List<Seg> roads = new List<Seg>();
        public List<Mark> landmarks = new List<Mark>();
        public List<Mark> pois = new List<Mark>();
        public List<Paint> mapPaint = new List<Paint>();
        public List<Vector3> pedSpots = new List<Vector3>();
        public Vector3 playerSpawn = new Vector3(0f, 2f, 0f);
        public float playerSpawnYaw;
        public Color mapGround = new Color(0.86f, 0.83f, 0.74f), mapWater = new Color(0.33f, 0.62f, 0.72f);

        public Vector3 Poi(string name, Vector3 fallback)
        {
            foreach (var p in pois) if (p.name == name) return p.pos;
            return fallback;
        }

        public void ApplyToRuntime()
        {
            var net = gameObject.GetComponent<RoadNetwork>() ?? gameObject.AddComponent<RoadNetwork>();
            RoadNetwork.I = net;
            var segs = new List<(Vector3, Vector3, float, bool)>();
            foreach (var r in roads) segs.Add((r.a, r.b, r.width * 0.5f, r.highway));
            net.BuildFromSegments(segs);

            WorldMarkers.Landmarks.Clear();
            foreach (var l in landmarks) WorldMarkers.Landmarks.Add((l.name, l.pos));
            WorldMarkers.DistrictCentres.Clear();
            foreach (var l in landmarks) WorldMarkers.DistrictCentres.Add(l.pos);
            WorldMarkers.PoliceStation = Poi("police", new Vector3(-60f, 2f, -30f));
            WorldMarkers.Hospital = Poi("hospital", new Vector3(60f, 2f, 40f));
            WorldMarkers.Safehouse = Poi("safehouse", new Vector3(120f, 2f, 160f));
            WorldMarkers.WeaponShop = Poi("weaponshop", new Vector3(-120f, 2f, 40f));
            WorldMarkers.ClothingShop = Poi("clothing", new Vector3(0f, 2f, 40f));
            WorldMarkers.ModShop = Poi("modshop", new Vector3(130f, 2f, -20f));
            WorldMarkers.GasStation = Poi("gas", new Vector3(130f, 2f, 40f));
            WorldMarkers.Airport = Poi("airport", new Vector3(0f, 2f, -240f));
            WorldMarkers.Docks = Poi("docks", new Vector3(-250f, 2f, 0f));
            WorldMarkers.Downtown = Poi("downtown", new Vector3(-30f, 2f, 0f));
            WorldMarkers.Hilltop = Poi("hilltop", new Vector3(-110f, 30f, 190f));
            WorldMarkers.Beach = Poi("beach", new Vector3(-225f, 1f, 120f));
            WorldMarkers.Industrial = Poi("industrial", new Vector3(200f, 2f, -100f));
            WorldMarkers.Helipads.Clear();
            WorldMarkers.Garages.Clear();
            foreach (var p in pois)
            {
                if (p.name.StartsWith("helipad")) WorldMarkers.Helipads.Add(p.pos);
                if (p.name.StartsWith("garage")) WorldMarkers.Garages.Add(p.pos);
            }
            WorldMarkers.ExtraPedSpots.Clear();
            WorldMarkers.ExtraPedSpots.AddRange(pedSpots);

            // bake the map texture
            var mt = MapTexture.Create(mapGround, mapWater, Color.gray, Color.gray);
            foreach (var p in mapPaint)
            {
                if (p.circle) mt.PaintCircle(p.centre, p.size.x, p.color);
                else mt.PaintRect(p.centre, p.size, p.yaw, p.color);
            }
            mt.Apply();
            foreach (var l in landmarks) HUD.RegisterBlip(l.name, l.pos, Color.white);
        }

        /// <summary>Persistent showcase vehicles (helipads, airfield, marina, police station, dealership).</summary>
        public void SpawnShowcaseVehicles()
        {
            foreach (var s in vehicleSpawns)
            {
                var def = VehicleCatalog.Get(s.id);
                if (def == null) continue;
                var v = VehicleFactory.Spawn(def, s.pos + Vector3.up * 0.3f, Quaternion.Euler(0f, s.yaw, 0f));
                if (v == null) continue;
                v.persistent = true;
                v.engineOn = false;
                if (def.police) v.lightsOn = false;
            }
        }
    }
}
