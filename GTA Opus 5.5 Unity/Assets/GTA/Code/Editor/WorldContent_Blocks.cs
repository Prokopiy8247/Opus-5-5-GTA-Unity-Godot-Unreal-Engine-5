using System.Collections.Generic;
using UnityEngine;

namespace Halcyon.EditorTools
{
    /// <summary>City blocks: generic district fills, sidewalks and street furniture.</summary>
    public static partial class WorldBuilder
    {
        static readonly string[] DowntownBig = { "BLD_Office_A", "BLD_Office_B", "BLD_MidRise_A", "BLD_Hotel", "BLD_MixedUse_A" };
        static readonly string[] DowntownSmall = { "BLD_MixedUse_A", "BLD_MixedUse_B", "BLD_ShopStrip", "BLD_Office_B" };
        static readonly string[] HouseIds = { "BLD_House_A", "BLD_House_B", "BLD_House_C" };
        static readonly string[] Sheds = { "BLD_Warehouse_A", "BLD_Warehouse_B", "BLD_Factory" };
        static readonly string[] Palms = { "NAT_Palm_A", "NAT_Palm_B" };
        static readonly string[] Trees = { "NAT_Tree_A", "NAT_Tree_B", "NAT_Palm_A" };

        static void FillBlock(Block b)
        {
            switch (b.ix * 10 + b.iz)
            {
                case 1: case 2: DocksSideBlock(b); break;
                case 13: WeaponShopBlock(b); break;
                case 21: TowerBlock(b, "BLD_Tower_B", false); break;
                case 22: PoliceBlock(b); break;
                case 23: TowerBlock(b, "BLD_Tower_C", false); break;
                case 31: TowerBlock(b, "BLD_Tower_A", true); break;
                case 32: PlazaBlock(b); break;
                case 33: ShopsBlock(b); break;
                case 41: CarLotBlock(b); break;
                case 42: ParkingBlock(b); break;
                case 43: HospitalBlock(b); break;
                case 44: ParkBlock(b); break;
                case 52: ModShopBlock(b); break;
                case 53: GasBlock(b); break;
                case 55: SafehouseBlock(b); break;
                default:
                    if (b.district == "Downtown") DowntownBlock(b);
                    else if (b.district == "Industrial") IndustrialBlock(b);
                    else ResidentialBlock(b);
                    break;
            }
            Sidewalks(b);
        }

        // ------------------------------------------------------------------ generic districts
        static void DowntownBlock(Block b)
        {
            var r = b.rect;
            int pattern = (b.ix * 3 + b.iz * 5) % 3;
            if (pattern == 0)
            {
                FitLot(Rect.MinMaxRect(r.xMin, r.yMin, r.xMax, r.center.y), 2, DowntownBig, 3f);
                FitLot(Rect.MinMaxRect(r.xMin, r.center.y, r.xMax, r.yMax), 0, DowntownBig, 3f);
            }
            else if (pattern == 1)
            {
                for (int q = 0; q < 4; q++)
                {
                    float x0 = q % 2 == 0 ? r.xMin : r.center.x, x1 = q % 2 == 0 ? r.center.x : r.xMax;
                    float z0 = q < 2 ? r.yMin : r.center.y, z1 = q < 2 ? r.center.y : r.yMax;
                    var lot = Rect.MinMaxRect(x0, z0, x1, z1);
                    if (FitLot(lot, q < 2 ? 2 : 0, DowntownSmall, 3f) == null) FitLot(lot, q % 2 == 0 ? 3 : 1, DowntownSmall, 3f);
                }
            }
            else
            {
                FitLot(Rect.MinMaxRect(r.xMin, r.yMin, r.xMax, r.yMax - 15f), 2, DowntownBig, 3f);
                FitLot(Rect.MinMaxRect(r.xMin, r.yMax - 15f, r.xMax, r.yMax), 0, new[] { "BLD_ShopStrip", "BLD_MixedUse_B" }, 1.5f);
            }
            Scatter(Rect.MinMaxRect(r.xMin + 3f, r.yMin + 3f, r.xMax - 3f, r.yMax - 3f), new[] { "PRP_Dumpster", "PRP_Bin", "PRP_Crate", "PRP_Pallet" }, 4, 1.4f);
            Scatter(Rect.MinMaxRect(r.xMin + 2f, r.yMin + 2f, r.xMax - 2f, r.yMax - 2f), new[] { "PRP_Planter", "PRP_Bench" }, 3, 1.5f);
        }

        static void IndustrialBlock(Block b)
        {
            var r = b.rect;
            int k = (b.ix * 7 + b.iz * 3) % 4;
            if (k == 0)
            {
                FitLot(Rect.MinMaxRect(r.xMin, r.center.y - 6f, r.xMax, r.yMax), 0, new[] { "BLD_Factory", "BLD_Warehouse_A" }, 4f);
                ContainerYard(Rect.MinMaxRect(r.xMin + 4f, r.yMin + 4f, r.xMax - 4f, r.center.y - 8f));
            }
            else if (k == 1)
            {
                FitLot(Rect.MinMaxRect(r.xMin, r.yMin, r.center.x, r.yMax), 3, Sheds, 4f);
                FitLot(Rect.MinMaxRect(r.center.x, r.yMin, r.xMax, r.yMax), 1, Sheds, 4f);
                TryProp("PRP_WaterTower", new Vector3(r.center.x, PlateTop, r.center.y), 0f, 4f);
            }
            else if (k == 2)
            {
                FitLot(Rect.MinMaxRect(r.xMin, r.yMin, r.xMax, r.center.y), 2, new[] { "BLD_Warehouse_B", "BLD_Warehouse_A" }, 4f);
                FitLot(Rect.MinMaxRect(r.xMin, r.center.y, r.xMax, r.yMax), 0, new[] { "BLD_Tanks" }, 4f);
            }
            else
            {
                FitLot(Rect.MinMaxRect(r.xMin, r.center.y + 4f, r.xMax, r.yMax), 0, new[] { "BLD_Warehouse_B" }, 4f);
                Ramp(new Vector3(r.center.x - 12f, PlateTop, r.center.y - 8f), 90f);
                Ramp(new Vector3(r.center.x + 12f, PlateTop, r.center.y - 16f), 270f);
                Parked("truck", new Vector3(r.xMax - 6f, PlateTop, r.yMin + 8f), 0f);
            }
            Scatter(Rect.MinMaxRect(r.xMin + 3f, r.yMin + 3f, r.xMax - 3f, r.yMax - 3f), new[] { "PRP_BarrelRed", "PRP_Pallet", "PRP_Crate", "PRP_Dumpster", "PRP_Cone" }, 10, 1.3f);
            FenceRect(r, 1.2f, 12f);
            if (Chance(0.5f)) Parked(Pick(new[] { "van", "pickup", "truck" }), new Vector3(r.xMin + 8f, PlateTop, r.center.y), 90f);
        }

        static void ResidentialBlock(Block b)
        {
            var r = b.rect;
            SidewalkRing(b);
            if ((b.ix + b.iz) % 4 == 3 && b.ix <= 4)
            {
                FitLot(Rect.MinMaxRect(r.xMin, r.yMin, r.xMax, r.center.y), 2, new[] { "BLD_Apartment_A", "BLD_MidRise_A" }, 5f);
                FitLot(Rect.MinMaxRect(r.xMin, r.center.y, r.xMax, r.yMax), 0, new[] { "BLD_Apartment_A", "BLD_MidRise_A" }, 5f);
                Scatter(Rect.MinMaxRect(r.xMin + 4f, r.yMin + 4f, r.xMax - 4f, r.yMax - 4f), Trees, 6, 2.5f, natureRoot);
                return;
            }
            HouseRow(b, 2, null);
            HouseRow(b, 0, null);
        }

        static void HouseRow(Block b, int face, string[] forced)
        {
            var r = b.rect;
            float rowDepth = Mathf.Min(r.height * 0.5f, 28f);
            var row = face == 2 ? Rect.MinMaxRect(r.xMin, r.yMin, r.xMax, r.yMin + rowDepth) : Rect.MinMaxRect(r.xMin, r.yMax - rowDepth, r.xMax, r.yMax);
            int n = Mathf.Max(1, Mathf.FloorToInt(r.width / 16f));
            float w = r.width / n;
            var outDir = SideDir(face);
            float yaw = FaceYaw(face);
            for (int i = 0; i < n; i++)
            {
                var lot = Rect.MinMaxRect(row.xMin + i * w, row.yMin, row.xMin + (i + 1) * w, row.yMax);
                string id = forced != null && i < forced.Length && forced[i] != null ? forced[i] : HouseIds[(b.ix * 5 + b.iz * 3 + i + face) % HouseIds.Length];
                if (Prefab(id) == null) { Note(id); continue; }
                var hb = PrefabBounds(id);
                if (hb.size.x > w - 1f) continue;
                // the house hugs one side of the lot; the free strip on the other side is the driveway
                float lateral = -(w - hb.size.x) * 0.5f + 0.6f;
                PlaceFacing(id, lot, face, 5.5f, out _, lateral);
                var lotC = new Vector3(lot.center.x, PlateTop, lot.center.y);
                var front = lotC + outDir * (rowDepth * 0.5f);
                var right = Vector3.Cross(Vector3.up, outDir);
                float freeW = w * 0.5f - (lateral + hb.size.x * 0.5f);
                float driveLat = lateral + hb.size.x * 0.5f + freeW * 0.5f;
                if (freeW > 3.2f && Chance(0.35f)) Parked(Pick(ParkedCars), front - outDir * 6.5f + right * driveLat, yaw);
                TryProp("PRP_Mailbox", front - outDir * 3.0f + right * (driveLat + freeW * 0.35f), yaw, 0.5f);
                var tp = front - outDir * 3.0f + right * (lateral - hb.size.x * 0.25f);
                if (Free(tp, 1.2f)) { Nature(Pick(Trees), tp, R(0f, 360f), R(0.8f, 1.05f)); Claim(tp, 1.4f); }
                var bp = front - outDir * (5.5f + hb.size.z + 2.5f) + right * lateral;
                if (Free(bp, 1f)) { Nature("NAT_Bush", bp, R(0f, 360f), R(0.8f, 1.2f)); Claim(bp, 1.2f); }
            }
            // back fence along the middle of the block
            float zBack = face == 2 ? row.yMax : row.yMin;
            for (float x = r.xMin + 3f; x < r.xMax - 3f; x += 4f) Prop("PRP_Fence", new Vector3(x + 2f, PlateTop, zBack), 90f);
        }

        /// <summary>Concrete sidewalk ring and driveways over the grass plate of residential blocks.</summary>
        static void SidewalkRing(Block b)
        {
            var r = b.rect; const float w = 2.6f; float y = PlateTop + 0.006f;
            var acc = new MeshAcc();
            acc.FlatRect(Rect.MinMaxRect(r.xMin, r.yMin, r.xMax, r.yMin + w), y, 0.25f);
            acc.FlatRect(Rect.MinMaxRect(r.xMin, r.yMax - w, r.xMax, r.yMax), y, 0.25f);
            acc.FlatRect(Rect.MinMaxRect(r.xMin, r.yMin + w, r.xMin + w, r.yMax - w), y, 0.25f);
            acc.FlatRect(Rect.MinMaxRect(r.xMax - w, r.yMin + w, r.xMax, r.yMax - w), y, 0.25f);
            acc.Flush("Sidewalk_" + b.ix + "_" + b.iz, mats["W_Sidewalk"], roadRoot, false);
        }

        // ------------------------------------------------------------------ fillers
        static void Scatter(Rect r, IList<string> ids, int count, float radius, Transform parent = null)
        {
            for (int i = 0, tries = 0; i < count && tries < count * 8; tries++)
            {
                var p = new Vector3(R(r.xMin, r.xMax), 0f, R(r.yMin, r.yMax));
                p.y = GroundAt(p.x, p.z);
                if (!Free(p, radius)) continue;
                Claim(p, radius);
                var id = Pick(ids);
                if (parent == natureRoot) Nature(id, p, R(0f, 360f), R(0.85f, 1.15f));
                else Prop(id, p, R(0f, 360f));
                i++;
            }
        }

        static void ContainerYard(Rect r)
        {
            for (float x = r.xMin + 2f; x < r.xMax - 2f; x += 3.4f)
                for (float z = r.yMin + 6.5f; z < r.yMax - 6f; z += 13.5f)
                {
                    var p = new Vector3(x, PlateTop, z);
                    if (!Free(p, 1.4f) || Chance(0.25f)) continue;
                    int stack = rnd.Next(1, 4);
                    for (int s = 0; s < stack; s++) Place("PRP_Container", p + Vector3.up * (2.6f * s), Chance(0.5f) ? 0f : 180f, propsRoot);
                    buildingFootprints.Add(Rect.MinMaxRect(x - 1.3f, z - 6.2f, x + 1.3f, z + 6.2f));
                }
        }

        static void FenceRect(Rect r, float inset, float gap)
        {
            var rr = Rect.MinMaxRect(r.xMin + inset, r.yMin + inset, r.xMax - inset, r.yMax - inset);
            for (int side = 0; side < 4; side++)
            {
                bool ns = side == 0 || side == 2;
                float len = ns ? rr.width : rr.height;
                for (float t = 2f; t < len - 1f; t += 4f)
                {
                    if (Mathf.Abs(t - len * 0.5f) < gap * 0.5f) continue;
                    Vector3 p = side == 0 ? new Vector3(rr.xMin + t, PlateTop, rr.yMax) : side == 2 ? new Vector3(rr.xMin + t, PlateTop, rr.yMin)
                              : side == 1 ? new Vector3(rr.xMax, PlateTop, rr.yMin + t) : new Vector3(rr.xMin, PlateTop, rr.yMin + t);
                    if (!Free(p, 0.3f)) continue;
                    Prop("PRP_Fence", p, ns ? 90f : 0f);
                }
            }
        }

        static void Ramp(Vector3 p, float yaw)
        {
            if (Place("PRP_Ramp", p, yaw, propsRoot) != null) Claim(p, 4f);
        }

        // ------------------------------------------------------------------ sidewalks & street furniture
        static bool BusRoute(Block b, int side)
        {
            var r = b.rect;
            float c = side == 0 ? r.yMax + 5.5f : side == 2 ? r.yMin - 5.5f : side == 1 ? r.xMax + 5.5f : r.xMin - 5.5f;
            bool ns = side == 0 || side == 2;
            return ns ? (Mathf.Abs(c - 10f) < 1f || Mathf.Abs(c + 50f) < 1f || Mathf.Abs(c - 130f) < 1f) : (Mathf.Abs(c - 30f) < 1f || Mathf.Abs(c + 30f) < 1f || Mathf.Abs(c - 150f) < 1f);
        }

        static void Sidewalks(Block b)
        {
            var r = b.rect;
            bool dt = b.district == "Downtown", ind = b.district == "Industrial";
            for (int side = 0; side < 4; side++)
            {
                var outDir = SideDir(side);
                var along = new Vector3(outDir.z, 0f, -outDir.x);
                bool ns = side == 0 || side == 2;
                float len = ns ? r.width : r.height;
                float half = (ns ? r.height : r.width) * 0.5f;
                var mid = new Vector3(r.center.x, PlateTop, r.center.y) + outDir * half;
                float yawOut = Mathf.Atan2(outDir.x, outDir.z) * Mathf.Rad2Deg;
                int nl = Mathf.Max(2, Mathf.RoundToInt(len / 24f) + 1);
                for (int i = 0; i < nl; i++)
                {
                    float t = Mathf.Lerp(-len * 0.5f + 6f, len * 0.5f - 6f, i / (float)(nl - 1));
                    var p = mid + along * t - outDir * 0.75f;
                    if (Free(p, 0.4f)) { Lamp(p, yawOut); Claim(p, 1f); }
                    if (i < nl - 1 && !ind)
                    {
                        float t2 = Mathf.Lerp(-len * 0.5f + 6f, len * 0.5f - 6f, (i + 0.5f) / (nl - 1));
                        var q = mid + along * t2 - outDir * 1.25f;
                        if (Free(q, 1.0f)) { Nature(dt ? Pick(Palms) : Pick(Trees), q, R(0f, 360f), R(0.85f, 1.15f)); Claim(q, 1.5f); }
                    }
                }
                if (Chance(0.55f)) TryProp("PRP_Hydrant", mid + along * (len * 0.5f - 9f) - outDir * 0.8f, yawOut, 0.6f);
                if (dt && Chance(0.5f))
                {
                    var p = mid + along * R(-len * 0.3f, len * 0.3f) - outDir * 2.1f;
                    if (TryProp("PRP_Bench", p, yawOut, 1.2f)) TryProp("PRP_Bin", p + along * 1.7f, yawOut, 0.5f);
                }
                if (dt && Chance(0.25f)) TryProp("PRP_Mailbox", mid + along * R(-len * 0.35f, len * 0.35f) - outDir * 0.9f, yawOut, 0.6f);
                if (dt && Chance(0.2f)) TryProp("PRP_Vending", mid + along * R(-len * 0.35f, len * 0.35f) - outDir * 2.4f, yawOut, 0.8f);
                if (!ind && BusRoute(b, side) && Chance(0.6f)) TryProp("PRP_BusStop", mid + along * R(-5f, 5f) - outDir * 1.9f, yawOut, 2.6f);
                if (ind && Chance(0.5f)) TryProp("PRP_PowerPole", mid + along * R(-len * 0.4f, len * 0.4f) - outDir * 0.6f, yawOut, 0.5f);
                for (float t = -len * 0.5f + 3f; t <= len * 0.5f - 3f; t += 12f)
                {
                    var sp = mid + along * t - outDir * 1.9f;
                    if (Free(sp, 0.2f)) data.pedSpots.Add(sp + Vector3.up * 0.05f);
                }
            }
        }
    }
}
