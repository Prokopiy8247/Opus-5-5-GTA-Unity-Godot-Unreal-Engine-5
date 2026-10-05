using UnityEngine;

namespace Halcyon.EditorTools
{
    /// <summary>Hand-authored special blocks: shops, services, safehouse, towers, plaza and park.</summary>
    public static partial class WorldBuilder
    {
        // walkable roof heights authored in Blender (local Y of the roof slab top)
        public const float TowerARoof = 72.2f, HospitalRoof = 19.2f;

        static void ShopCounter(string id, string model, Vector3 pos, float yaw, string poi = null)
        {
            var b = PrefabBounds(model);
            var p = Local(pos, yaw, new Vector3(0f, 0.02f, b.min.z + 3.4f));
            Interact(id, p, 2.2f);
            if (poi != null) Poi(poi, Local(pos, yaw, new Vector3(0f, 0.2f, b.min.z - 2.5f)));
            InteriorLight(Local(pos, yaw, new Vector3(0f, 2.8f, b.center.z)), 1.6f, 11f);
        }

        static void InteriorLight(Vector3 p, float intensity, float range)
        {
            var go = new GameObject("InteriorLight");
            go.transform.SetParent(poiRoot, false);
            go.transform.position = p;
            var l = go.AddComponent<Light>();
            l.type = LightType.Point; l.intensity = intensity; l.range = range; l.color = new Color(1f, 0.9f, 0.75f); l.shadows = LightShadows.None;
        }

        static void DocksSideBlock(Block b)
        {
            var r = b.rect;
            FitLot(Rect.MinMaxRect(r.xMin, r.yMin, r.xMax, r.yMax), 3, new[] { "BLD_Warehouse_B", "BLD_Warehouse_A" }, 4f);
            Scatter(r, new[] { "PRP_Crate", "PRP_Pallet", "PRP_BarrelRed", "PRP_Dumpster" }, 10, 1.3f);
            Parked(Pick(new[] { "van", "pickup", "truck" }), new Vector3(r.xMin + 6f, PlateTop, r.center.y), 0f);
        }

        static void WeaponShopBlock(Block b)
        {
            var r = b.rect;
            const string id = "BLD_WeaponShop";
            var pos = PlaceFacing(id, Rect.MinMaxRect(r.xMin, r.yMin, r.xMax, r.yMin + 18f), 2, 3f, out _);
            ShopCounter("weaponshop", id, pos, 180f, null);
            var sb = PrefabBounds(id);
            Poi("weaponshop", Local(pos, 180f, new Vector3(0f, 0.2f, sb.min.z + 3.4f)));
            // outdoor shooting range behind the shop (targets are spawned by Activities.StartRange)
            float backZ = pos.z - sb.min.z;
            Interact("range", new Vector3(pos.x, PlateTop, backZ + 3f), 2.2f);
            for (float x = r.xMin + 4f; x <= r.xMax - 4f; x += 4f) Place("PRP_ConcreteWall", new Vector3(x, PlateTop, r.yMax - 2.5f), 0f, propsRoot);
            for (float z = backZ + 2f; z <= r.yMax - 4f; z += 4f)
            {
                Place("PRP_ConcreteWall", new Vector3(r.xMin + 3f, PlateTop, z), 90f, propsRoot);
                Place("PRP_ConcreteWall", new Vector3(r.xMax - 3f, PlateTop, z), 90f, propsRoot);
            }
            buildingFootprints.Add(Rect.MinMaxRect(r.xMin + 2f, backZ, r.xMax - 2f, r.yMax - 1.5f));
        }

        static void TowerBlock(Block b, string id, bool roofAccess)
        {
            var r = b.rect;
            int face = b.iz <= 1 ? 0 : 2;
            var tb = PrefabBounds(id);
            float setback = Mathf.Max(3f, ((face == 0 || face == 2) ? r.height : r.width) * 0.5f - tb.size.z * 0.5f);
            var pos = PlaceFacing(id, r, face, setback, out _);
            float yaw = FaceYaw(face);
            Scatter(r, new[] { "PRP_Planter", "PRP_Bench", "PRP_Bin" }, 8, 1.6f);
            Scatter(r, Palms, 6, 1.8f, natureRoot);
            if (!roofAccess) return;
            var up = Interact("elevator_up", Local(pos, yaw, new Vector3(3f, 0.02f, tb.max.z + 1.4f)), 1.8f);
            Target(up, "Target", Local(pos, yaw, new Vector3(0f, TowerARoof + 0.3f, -3f)));
            var down = Interact("elevator_down", Local(pos, yaw, new Vector3(-4f, TowerARoof + 0.02f, -6f)), 1.8f);
            Target(down, "Target", Local(pos, yaw, new Vector3(3f, 0.3f, tb.max.z + 3f)));
            Pickup("parachute", "PRP_Pickup_Parachute", Local(pos, yaw, new Vector3(5f, TowerARoof + 0.02f, -7f)));
            Poi("helipad_tower", Local(pos, yaw, new Vector3(0f, TowerARoof, 1f)));
        }

        static void PoliceBlock(Block b)
        {
            var r = b.rect;
            const string id = "BLD_PoliceStation";
            var pos = PlaceFacing(id, Rect.MinMaxRect(r.xMin + 16f, r.yMin, r.xMax, r.yMax), 1, 3f, out _);
            var pb = PrefabBounds(id);
            Poi("police", Local(pos, 90f, new Vector3(0f, 0.2f, pb.min.z - 2.6f)));
            InteriorLight(Local(pos, 90f, new Vector3(0f, 3f, 0f)), 1.2f, 14f);
            var pad = new Vector3(r.xMin + 8f, PlateTop + 0.02f, r.yMin + 9f);
            Place("PRP_Helipad", pad, 0f, propsRoot);
            Claim(pad, 7f);
            VSpawn("policeheli", pad, 90f);
            Poi("helipad_police", pad);
            VSpawn("police", new Vector3(r.xMin + 8f, PlateTop, r.center.y + 3f), 0f);
            VSpawn("police", new Vector3(r.xMin + 8f, PlateTop, r.center.y + 11f), 0f);
            VSpawn("swat", new Vector3(r.xMin + 8f, PlateTop, r.yMax - 7f), 0f);
            Pickup("armor", "PRP_Pickup_Armor", new Vector3(r.xMin + 3f, PlateTop, r.center.y - 4f));
            for (float z = r.yMin + 2f; z < r.yMax - 2f; z += 4f) Prop("PRP_Fence", new Vector3(r.xMin + 0.8f, PlateTop, z + 2f), 0f);
        }

        static void PlazaBlock(Block b)
        {
            var r = b.rect;
            var c = new Vector3(r.center.x, PlateTop, r.center.y);
            if (Place("PRP_Fountain", c, 0f, propsRoot) != null) buildingFootprints.Add(new Rect(c.x - 4.5f, c.z - 4.5f, 9f, 9f));
            Claim(c, 5f);
            for (int i = 0; i < 8; i++)
            {
                float a = i * Mathf.PI / 4f;
                var dir = new Vector3(Mathf.Cos(a), 0f, Mathf.Sin(a));
                var p = c + dir * 16f;
                Nature(Pick(Palms), p, R(0f, 360f), R(0.95f, 1.2f)); Claim(p, 1.5f);
                var bp = c + Quaternion.Euler(0f, 22.5f, 0f) * dir * 9.5f;
                float yaw = Mathf.Atan2(-bp.x + c.x, -bp.z + c.z) * Mathf.Rad2Deg;
                TryProp("PRP_Bench", bp, yaw, 1f);
            }
            foreach (var q in new[] { new Vector2(-1, -1), new Vector2(1, -1), new Vector2(-1, 1), new Vector2(1, 1) })
                TryProp("PRP_Planter", c + new Vector3(q.x * (r.width * 0.5f - 6f), 0f, q.y * (r.height * 0.5f - 6f)), 0f, 1.5f);
            Interact("taxi", new Vector3(r.xMax - 4f, PlateTop, r.yMax - 4f), 2.2f);
            TryProp("PRP_ATM", new Vector3(r.xMin + 3f, PlateTop, r.yMax - 3f), 0f, 0.8f);
            Interact("atm", new Vector3(r.xMin + 3f, PlateTop, r.yMax - 4.2f), 1.6f);
            for (float x = r.xMin + 6f; x < r.xMax - 4f; x += 8f)
                for (float z = r.yMin + 6f; z < r.yMax - 4f; z += 8f) data.pedSpots.Add(new Vector3(x, PlateTop + 0.05f, z));
            Landmark("Halcyon Plaza", c);
            Poi("downtown", c + new Vector3(0f, 0.2f, -10f));
        }

        static void ShopsBlock(Block b)
        {
            var r = b.rect;
            var south = Rect.MinMaxRect(r.xMin, r.yMin, r.xMax, r.yMin + 20f);
            float w = south.width;
            var lotA = Rect.MinMaxRect(south.xMin, south.yMin, south.xMin + w * 0.38f, south.yMax);
            var lotB = Rect.MinMaxRect(lotA.xMax, south.yMin, lotA.xMax + w * 0.24f, south.yMax);
            var lotC = Rect.MinMaxRect(lotB.xMax, south.yMin, south.xMax, south.yMax);
            var pA = PlaceFacing("BLD_ClothingShop", lotA, 2, 3f, out _);
            ShopCounter("clothing", "BLD_ClothingShop", pA, 180f, "clothing");
            var pB = PlaceFacing("BLD_Barber", lotB, 2, 3f, out _);
            ShopCounter("barber", "BLD_Barber", pB, 180f, "barber");
            var pC = PlaceFacing("BLD_Diner", lotC, 2, 3f, out _);
            ShopCounter("food", "BLD_Diner", pC, 180f, "diner");
            FitLot(Rect.MinMaxRect(r.xMin, r.yMin + 22f, r.xMax, r.yMax), 0, new[] { "BLD_MixedUse_A", "BLD_Office_B", "BLD_MidRise_A" }, 3f);
        }

        static void CarLotBlock(Block b)
        {
            var r = b.rect;
            const string id = "BLD_Showroom";
            var pos = PlaceFacing(id, Rect.MinMaxRect(r.xMin, r.yMax - 26f, r.xMin + 30f, r.yMax), 0, 3f, out _);
            var sb = PrefabBounds(id);
            Interact("vehiclelot", Local(pos, 0f, new Vector3(0f, 0.02f, sb.min.z - 1.5f)), 2.4f);
            Poi("vehiclelot", Local(pos, 0f, new Vector3(0f, 0.2f, sb.min.z - 2.5f)));
            string[] show = { "sports", "muscle", "suv", "compact", "motorbike", "pickup" };
            for (int i = 0; i < show.Length; i++)
            {
                var p = new Vector3(r.xMin + 6f + i * 7.6f, PlateTop, r.yMin + 8f);
                VSpawn(show[i], p, 0f);
                Prop("PRP_Flag", p + new Vector3(3.6f, 0f, -4.5f), 0f);
            }
            Claim(new Vector3(r.center.x, PlateTop, r.yMin + 8f), 9f);
            buildingFootprints.Add(Rect.MinMaxRect(r.xMin + 2f, r.yMin + 3f, r.xMax - 2f, r.yMin + 13f));
        }

        static void ParkingBlock(Block b)
        {
            var r = b.rect;
            const string id = "BLD_ParkingGarage";
            var pb = PrefabBounds(id);
            float setback = Mathf.Max(2f, r.height * 0.5f - pb.size.z * 0.5f);
            var pos = PlaceFacing(id, r, 2, setback, out _);
            Vector3[] spots = { new Vector3(-6f, 3.25f, 2f), new Vector3(2f, 3.25f, 2f), new Vector3(4f, 6.45f, -4f), new Vector3(-4f, 6.45f, -4f), new Vector3(-8f, 9.65f, 0f), new Vector3(6f, 9.65f, 6f) };
            float[] yaws = { 0f, 0f, 180f, 180f, 90f, 270f };
            for (int i = 0; i < spots.Length; i++) VSpawn(ParkedCars[i % ParkedCars.Length], Local(pos, 180f, spots[i]), 180f + yaws[i]);
            Ramp(Local(pos, 180f, new Vector3(-6f, 9.6f, -12f)), 0f);
            Landmark("Skyline Parking", Local(pos, 180f, new Vector3(0f, 0f, pb.min.z - 2f)));
        }

        static void HospitalBlock(Block b)
        {
            var r = b.rect;
            const string id = "BLD_Hospital";
            var pos = PlaceFacing(id, r, 2, 12f, out _);
            var hb = PrefabBounds(id);
            Poi("hospital", Local(pos, 180f, new Vector3(0f, 0.2f, hb.min.z - 3f)));
            InteriorLight(Local(pos, 180f, new Vector3(0f, 3f, hb.max.z - 4f)), 1.4f, 14f);
            var up = Interact("elevator_up", Local(pos, 180f, new Vector3(4f, 0.02f, hb.max.z + 1.4f)), 1.8f);
            Target(up, "Target", Local(pos, 180f, new Vector3(-5f, HospitalRoof + 0.3f, -6f)));
            var down = Interact("elevator_down", Local(pos, 180f, new Vector3(-8f, HospitalRoof + 0.02f, -6f)), 1.8f);
            Target(down, "Target", Local(pos, 180f, new Vector3(4f, 0.3f, hb.max.z + 3f)));
            Poi("helipad_hospital", Local(pos, 180f, new Vector3(0f, HospitalRoof, 2f)));
            VSpawn("ambulance", new Vector3(r.xMax - 8f, PlateTop, r.yMin + 6f), 90f);
            Pickup("health", "PRP_Pickup_Health", new Vector3(r.xMin + 5f, PlateTop, r.yMin + 5f));
            Landmark("Halcyon General", Local(pos, 180f, new Vector3(0f, 0f, hb.max.z + 4f)));
        }

        static void ParkBlock(Block b)
        {
            var r = b.rect;
            var c = new Vector3(r.center.x, PlateTop, r.center.y);
            var acc = new MeshAcc();
            float y = PlateTop + 0.006f;
            acc.FlatRect(Rect.MinMaxRect(r.xMin, c.z - 1.6f, r.xMax, c.z + 1.6f), y, 0.25f);
            acc.FlatRect(Rect.MinMaxRect(c.x - 1.6f, r.yMin, c.x + 1.6f, c.z - 1.6f), y, 0.25f);
            acc.FlatRect(Rect.MinMaxRect(c.x - 1.6f, c.z + 1.6f, c.x + 1.6f, r.yMax), y, 0.25f);
            acc.Flush("ParkPaths", mats["W_Sidewalk"], roadRoot, false);
            Claim(c, 4f);
            for (float t = -r.width * 0.5f + 4f; t < r.width * 0.5f - 3f; t += 4f) { Claim(c + new Vector3(t, 0f, 0f), 1.9f); Claim(c + new Vector3(0f, 0f, t), 1.9f); }
            TryProp("PRP_Planter", c, 0f, 2f);
            for (int i = 0; i < 4; i++)
            {
                var d = SideDir(i);
                var p = c + d * 10f + Vector3.Cross(Vector3.up, d) * 2.6f;
                TryProp("PRP_Bench", p, Mathf.Atan2(-Vector3.Cross(Vector3.up, d).x, -Vector3.Cross(Vector3.up, d).z) * Mathf.Rad2Deg, 1f);
                Lamp(c + d * 18f + Vector3.Cross(Vector3.up, d) * 2.2f, Mathf.Atan2(-Vector3.Cross(Vector3.up, d).x, -Vector3.Cross(Vector3.up, d).z) * Mathf.Rad2Deg);
            }
            Scatter(r, new[] { "NAT_Tree_A", "NAT_Tree_B", "NAT_Tree_A", "NAT_Palm_B" }, 18, 2.4f, natureRoot);
            Scatter(r, new[] { "NAT_Bush", "NAT_Flowers", "NAT_Flowers" }, 16, 1f, natureRoot);
            Scatter(r, new[] { "PRP_PicnicTable" }, 4, 2f);
            for (float x = r.xMin + 4f; x < r.xMax - 2f; x += 7f) data.pedSpots.Add(new Vector3(x, PlateTop + 0.05f, c.z));
            for (float z = r.yMin + 4f; z < r.yMax - 2f; z += 7f) data.pedSpots.Add(new Vector3(c.x, PlateTop + 0.05f, z));
            Landmark("Palm Row Park", c);
        }

        static void ModShopBlock(Block b)
        {
            var r = b.rect;
            const string id = "BLD_ModGarage";
            var pos = PlaceFacing(id, Rect.MinMaxRect(r.xMin, r.yMin, r.xMin + 26f, r.yMin + 26f), 2, 4f, out _);
            var mb = PrefabBounds(id);
            var bay = Local(pos, 180f, new Vector3(0f, 0.02f, mb.center.z));
            Interact("modshop", bay, 6.5f);
            Poi("modshop", Local(pos, 180f, new Vector3(0f, 0.2f, mb.min.z - 3f)));
            InteriorLight(bay + Vector3.up * 4f, 1.6f, 14f);
            FitLot(Rect.MinMaxRect(r.xMin, r.yMin + 28f, r.xMax, r.yMax), 0, DowntownSmall, 3f);
            Scatter(Rect.MinMaxRect(r.xMin + 28f, r.yMin + 3f, r.xMax - 3f, r.yMin + 26f), new[] { "PRP_Crate", "PRP_BarrelRed", "PRP_Pallet", "PRP_Cone" }, 6, 1.2f);
            Parked("muscle", new Vector3(r.xMax - 7f, PlateTop, r.yMin + 10f), 90f);
        }

        static void GasBlock(Block b)
        {
            var r = b.rect;
            const string id = "BLD_GasStation";
            var pos = PlaceFacing(id, Rect.MinMaxRect(r.xMin, r.yMin, r.xMin + 32f, r.yMin + 30f), 2, 5f, out _);
            float yaw = 180f;
            foreach (var x in new[] { -4.5f, 4.5f })
            {
                var pp = Local(pos, yaw, new Vector3(x, 0f, 6f));
                Prop("PRP_GasPump", pp, yaw + 90f);
            }
            Interact("robbery", Local(pos, yaw, new Vector3(0f, 0.02f, -3f)), 1.8f);
            var atm = Local(pos, yaw, new Vector3(5f, 0f, -3.4f));
            Prop("PRP_ATM", atm, yaw);
            Interact("atm", Local(pos, yaw, new Vector3(5f, 0.02f, -2.4f)), 1.4f);
            Poi("gas", Local(pos, yaw, new Vector3(0f, 0.2f, 14f)));
            InteriorLight(Local(pos, yaw, new Vector3(0f, 4.5f, 6f)), 2f, 16f);
            FitLot(Rect.MinMaxRect(r.xMin, r.yMin + 32f, r.xMax, r.yMax), 0, DowntownSmall, 3f);
            FitLot(Rect.MinMaxRect(r.xMin + 33f, r.yMin, r.xMax, r.yMin + 31f), 1, new[] { "BLD_MixedUse_B", "BLD_ShopStrip" }, 3f);
        }

        static void SafehouseBlock(Block b)
        {
            var r = b.rect;
            SidewalkRing(b);
            HouseRow(b, 0, null);
            const string id = "BLD_Safehouse";
            var sb = PrefabBounds(id);
            var pos = new Vector3(r.xMin + 4f + sb.size.x * 0.5f + 6f, PlateTop, r.yMin + 6f + sb.max.z);
            Building(id, pos, 180f);
            float yaw = 180f;
            Interact("bed", Local(pos, yaw, new Vector3(-3.8f, 0.02f, -1.6f)), 1.6f);
            Interact("wardrobe", Local(pos, yaw, new Vector3(4.2f, 0.02f, -3.0f)), 1.5f);
            InteriorLight(Local(pos, yaw, new Vector3(0f, 2.6f, 0f)), 1.3f, 9f);
            var drive = Local(pos, yaw, new Vector3(-(sb.size.x * 0.5f + 3.2f), 0f, 1.5f));
            VSpawn("sedan", drive, 180f);
            VSpawn("motorbike", drive + new Vector3(0f, 0f, 6f), 180f);
            Interact("garage", drive + new Vector3(2.4f, 0.02f, 3f), 2f);
            Poi("garage_safehouse", drive);
            // prefabs face local +Z (door side); with the 180 deg placement the door looks onto the street at the block's south edge
            Poi("safehouse", Local(pos, yaw, new Vector3(0f, 0.2f, sb.max.z + 2.0f)));
            data.playerSpawn = Local(pos, yaw, new Vector3(1.5f, 0.15f, sb.max.z + 3.2f));
            data.playerSpawnYaw = 180f + 25f;
            Claim(data.playerSpawn, 2f);
            var east = Rect.MinMaxRect(drive.x + 4f, r.yMin, r.xMax, r.yMin + 26f);
            FitLot(east, 2, HouseIds, 5.5f);
            Nature("NAT_Palm_A", Local(pos, yaw, new Vector3(sb.size.x * 0.5f + 1.2f, 0f, sb.max.z + 2.5f)), 30f);
            Landmark("Palm Row", Local(pos, yaw, new Vector3(0f, 0f, sb.min.z - 6f)));
        }
    }
}
