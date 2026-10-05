using UnityEngine;

namespace Halcyon.EditorTools
{
    /// <summary>Coast, docks, beaches, Crown Hill, airfield, seabed, junction signals, roadside lamps and activities.</summary>
    public static partial class WorldBuilder
    {
        static void BuildTrafficLights()
        {
            foreach (var n in junctionNodes)
            {
                if (n.x < -201f || n.z < -171f) continue;
                var arms = ArmsAt(n, out float w);
                if (arms.Count < 3) continue;
                float off = w * 0.5f + 1.1f;
                foreach (var arm in arms)
                {
                    var a = -arm;                                   // travel direction of approaching cars
                    var right = Vector3.Cross(Vector3.up, a);
                    var p = n - a * off + right * off;
                    p.y = GroundAt(p.x, p.z);
                    float yaw = Mathf.Atan2(-a.x, -a.z) * Mathf.Rad2Deg;
                    var go = Prop("PRP_TrafficLight", p, yaw);
                    Claim(p, 1.2f);
                    if (go == null) continue;
                    var tl = go.AddComponent<TrafficLightProp>();
                    tl.junction = n; tl.axisNS = Mathf.Abs(a.z) > Mathf.Abs(a.x);
                }
            }
        }

        /// <summary>Lamps along road edges that are not bordered by city blocks (highway, hill, airfield, shore roads).</summary>
        static void BuildRoadsideLamps()
        {
            foreach (var s in data.roads)
            {
                var dir = (s.b - s.a); float len = dir.magnitude; dir /= len;
                var side = Vector3.Cross(Vector3.up, dir);
                for (float t = 10f; t < len - 10f; t += 30f)
                    for (int k = -1; k <= 1; k += 2)
                    {
                        var p = s.a + dir * t + side * k * (s.width * 0.5f + 1.3f);
                        bool inBlock = false;
                        foreach (var b in blocks) if (b.rect.Contains(new Vector2(p.x, p.z))) { inBlock = true; break; }
                        if (inBlock) continue;
                        float h = GroundAt(p.x, p.z);
                        if (h < CityY - 0.6f || h > CityY + 0.6f || !Free(p, 1f)) continue;
                        p.y = h;
                        var toRoad = -side * k;
                        Lamp(p, Mathf.Atan2(toRoad.x, toRoad.z) * Mathf.Rad2Deg);
                        Claim(p, 1f);
                    }
            }
        }

        // ------------------------------------------------------------------ coast
        static void BuildCoast()
        {
            Slab("Quay", Rect.MinMaxRect(QuayEdge, -82f, -208.2f, 82f), -7f, PlateTop, mats["W_Quay"], roadRoot);
            for (float z = -78f; z <= 78f; z += 8f)
                if (Mathf.Abs(Mathf.Abs(z) - 45f) > 4f) Prop("PRP_Bollard", new Vector3(QuayEdge + 0.7f, PlateTop, z), 270f);
            for (float z = -66f; z <= 66f; z += 22f) { var lp = new Vector3(QuayEdge + 1.8f, PlateTop, z); Lamp(lp, 90f); Claim(lp, 1f); }
            foreach (var z in new[] { -70f, -20f, 20f, 70f })
                LadderAt(new Vector3(QuayEdge - 0.12f, -1.6f, z), new Vector3(QuayEdge - 0.12f, PlateTop, z), Vector3.left);
            foreach (var pz in new[] { -45f, 45f })
            {
                for (int i = 0; i < 5; i++) Place("PRP_Dock", new Vector3(QuayEdge - 5f - i * 10f, PlateTop, pz), 90f, propsRoot);
                LadderAt(new Vector3(QuayEdge - 50.12f, -1.6f, pz), new Vector3(QuayEdge - 50.12f, PlateTop, pz), Vector3.left);
                Place("PRP_Buoy", new Vector3(QuayEdge - 60f, 0f, pz + 6f), 0f, propsRoot);
                Place("PRP_Buoy", new Vector3(QuayEdge - 60f, 0f, pz - 6f), 0f, propsRoot);
            }
            foreach (var cz in new[] { -16f, 18f }) { Place("PRP_Crane", new Vector3(-222f, PlateTop, cz), 270f, propsRoot); Claim(new Vector3(-222f, 0f, cz), 7f); }
            foreach (var zr in new[] { new Vector2(52f, 80f), new Vector2(-80f, -52f) })
                for (float x = -231.5f; x <= -218f; x += 3.4f)
                {
                    float z = (zr.x + zr.y) * 0.5f;
                    if (Chance(0.2f)) continue;
                    int stack = rnd.Next(1, 4);
                    for (int s = 0; s < stack; s++) Place("PRP_Container", new Vector3(x, PlateTop + 2.6f * s, z), 0f, propsRoot);
                    buildingFootprints.Add(Rect.MinMaxRect(x - 1.3f, z - 6.2f, x + 1.3f, z + 6.2f));
                }
            // boat rental & dive shop kiosks
            var kb = PrefabBounds("BLD_Kiosk");
            var rent = new Vector3(-226f, PlateTop, 36f);
            Building("BLD_Kiosk", rent, 270f);
            var it = Interact("boatrental", Local(rent, 270f, new Vector3(0f, 0.02f, kb.max.z + 1.3f)), 2f);
            Target(it, "Target", new Vector3(QuayEdge - 20f, 0.3f, 39.5f));
            var dive = new Vector3(-226f, PlateTop, -36f);
            Building("BLD_Kiosk", dive, 270f);
            Interact("scuba", Local(dive, 270f, new Vector3(0f, 0.02f, kb.max.z + 1.3f)), 2f);
            VSpawn("speedboat", new Vector3(QuayEdge - 30f, 0.3f, -40.5f), 270f);
            VSpawn("speedboat", new Vector3(QuayEdge - 30f, 0.3f, 49.5f), 270f);
            Parked("truck", new Vector3(-213.5f, PlateTop, -30f), 0f);
            Scatter(Rect.MinMaxRect(-233f, -50f, -212f, 50f), new[] { "PRP_Crate", "PRP_Pallet", "PRP_BarrelRed", "PRP_Crate" }, 14, 1.2f);
            for (float z = -76f; z <= 76f; z += 9f) data.pedSpots.Add(new Vector3(-214f, PlateTop + 0.05f, z));
            Landmark("Saltwater Docks", new Vector3(-222f, PlateTop, 0f));
            Poi("docks", new Vector3(-220f, PlateTop + 0.2f, 4f));

            // beaches north and south of the docks
            foreach (var zr in new[] { new Vector2(88f, 262f), new Vector2(-282f, -88f) })
            {
                for (float z = zr.x; z <= zr.y; z += 14f) { var p = OnGround(-213.6f, z); if (Free(p, 1.5f)) { Nature(Pick(Palms), p, R(0f, 360f), R(0.9f, 1.25f)); Claim(p, 1.5f); } }
                int clusters = Mathf.RoundToInt((zr.y - zr.x) / 22f);
                for (int i = 0; i < clusters; i++)
                {
                    var c = OnGround(R(-236f, -222f), R(zr.x + 4f, zr.y - 4f));
                    if (!Free(c, 3f)) continue;
                    Claim(c, 3f);
                    Prop("PRP_Umbrella", c, R(0f, 360f));
                    Prop("PRP_Lounger", OnGround(c.x + 1.3f, c.z - 0.8f), 270f + R(-15f, 15f));
                    if (Chance(0.6f)) Prop("PRP_Lounger", OnGround(c.x + 1.3f, c.z + 1.0f), 270f + R(-15f, 15f));
                }
                for (int i = 0; i < 10; i++)
                {
                    var rp = OnGround(R(-262f, -246f), R(zr.x, zr.y));
                    Nature(Pick(new[] { "NAT_Rock_A", "NAT_Rock_B" }), rp + Vector3.down * 0.3f, R(0f, 360f), R(0.8f, 1.8f));
                }
                for (float z = zr.x + 5f; z < zr.y; z += 12f) data.pedSpots.Add(OnGround(-224f, z) + Vector3.up * 0.05f);
            }
            foreach (var z in new[] { 130f, 215f, -130f, -225f }) { var p = OnGround(-236f, z); Building("BLD_LifeguardTower", p, 270f); }
            var snack = OnGround(-219f, 176f);
            Building("BLD_Kiosk", snack, 270f);
            Interact("food", Local(snack, 270f, new Vector3(0f, 0.02f, kb.max.z + 1.3f)), 2f);
            VSpawn("bicycle", OnGround(-214.8f, 101f), 0f);
            VSpawn("bicycle", OnGround(-214.8f, -101f), 180f);
            Ramp(OnGround(-226f, 246f), 0f);
            Landmark("North Beach", OnGround(-228f, 170f));
            Poi("beach", OnGround(-224f, 168f) + Vector3.up * 0.2f);
            var lh = OnGround(PointCentre.x, PointCentre.y);
            Building("BLD_Lighthouse", lh, 0f);
            Landmark("Lighthouse Point", lh + new Vector3(8f, 0f, -8f));
            Flock(new Vector3(-226f, 15f, 0f), 6);
            Flock(new Vector3(-234f, 12f, 170f), 5);
            Flock(new Vector3(-230f, 14f, -160f), 4);
            Flock(new Vector3(-236f, 22f, 292f), 4);
        }

        /// <summary>Seagulls circling on spinning pivots (each bird on its own pivot and radius).</summary>
        static void Flock(Vector3 centre, int count)
        {
            if (Prefab("ANI_Seagull") == null) { Note("ANI_Seagull"); return; }
            for (int i = 0; i < count; i++)
            {
                var pivot = new GameObject("GullPivot");
                pivot.transform.SetParent(natureRoot, false);
                pivot.transform.position = centre + Vector3.up * R(-3f, 5f);
                pivot.transform.rotation = Quaternion.Euler(0f, R(0f, 360f), 0f);
                var sp = pivot.AddComponent<Spinner>(); sp.axis = Vector3.up; sp.speed = R(16f, 30f);
                var gull = Place("ANI_Seagull", pivot.transform.position, 0f, pivot.transform);
                if (gull == null) continue;
                ClearStatic(gull);
                gull.transform.localPosition = new Vector3(R(7f, 20f), 0f, 0f);
                gull.transform.localRotation = Quaternion.Euler(0f, 180f, R(-14f, -6f));
                gull.AddComponent<Flapper>();
            }
        }

        // ------------------------------------------------------------------ Crown Hill
        static void BuildHill()
        {
            var summit = OnGround(HillCentre.x, HillCentre.y);
            Building("BLD_Observatory", summit - Vector3.up * 0.15f, 135f);
            for (int i = -1; i <= 1; i++)
            {
                var bp = OnGround(HillCentre.x + 9.5f + i * 2.4f, HillCentre.y - 9.5f + i * 2.4f);
                TryProp("PRP_Bench", bp, 135f, 1f);
            }
            TryProp("PRP_Telescope", OnGround(HillCentre.x + 11.5f, HillCentre.y - 5f), 135f, 0.8f);
            Pickup("parachute", "PRP_Pickup_Parachute", OnGround(HillCentre.x - 9f, HillCentre.y + 6f));
            Pickup("health", "PRP_Pickup_Health", OnGround(HillCentre.x + 6f, HillCentre.y + 10f));
            Place("PRP_RadioMast", OnGround(-150f, 222f), 0f, propsRoot);
            Claim(OnGround(-150f, 222f), 4f);
            var villas = new[] { new Vector3(-172f, 0f, 96f), new Vector3(-60f, 0f, 96f), new Vector3(-54f, 0f, 246f), new Vector3(-176f, 0f, 248f) };
            for (int i = 0; i < villas.Length; i++)
            {
                float yaw = villas[i].z < 150f ? 180f : 0f;
                var vp = OnGround(villas[i].x, villas[i].z);
                Building("BLD_Villa", vp, yaw);
                var front = Local(vp, yaw, new Vector3(-12f, 0f, PrefabBounds("BLD_Villa").max.z + 3f));
                if (i % 2 == 0) Parked(i == 0 ? "sports" : "suv", OnGround(front.x, front.z), yaw);
                Lamp(Local(vp, yaw, new Vector3(9f, 0f, PrefabBounds("BLD_Villa").max.z + 6f)), yaw);
            }
            for (int i = 0, tries = 0; i < 85 && tries < 600; tries++)
            {
                float a = R(0f, Mathf.PI * 2f), d = Mathf.Sqrt(R(0.05f, 1f)) * (HillRadius - 4f);
                if (d < 17f) continue;
                var p = OnGround(HillCentre.x + Mathf.Cos(a) * d, HillCentre.y + Mathf.Sin(a) * d);
                if (PathMask(p.x, p.z) || !Free(p, 2.2f)) continue;
                Claim(p, 2.2f);
                Nature(Chance(0.8f) ? "NAT_Pine" : Pick(Trees), p - Vector3.up * 0.2f, R(0f, 360f), R(0.8f, 1.3f));
                i++;
            }
            for (int i = 0; i < 30; i++)
            {
                float a = R(0f, Mathf.PI * 2f), d = R(18f, HillRadius);
                var p = OnGround(HillCentre.x + Mathf.Cos(a) * d, HillCentre.y + Mathf.Sin(a) * d);
                if (!Free(p, 1.5f)) continue;
                Nature(Pick(new[] { "NAT_Rock_A", "NAT_Rock_B", "NAT_Rock_C" }), p - Vector3.up * 0.4f, R(0f, 360f), R(0.7f, 1.6f));
            }
            var flats = Rect.MinMaxRect(-197f, 76f, -36f, 264f);
            for (int i = 0, tries = 0; i < 70 && tries < 700; tries++)
            {
                var p = OnGround(R(flats.xMin, flats.xMax), R(flats.yMin, flats.yMax));
                if (Vector2.Distance(new Vector2(p.x, p.z), HillCentre) < HillRadius + 2f || !Free(p, 1.6f)) continue;
                Claim(p, 1.6f);
                string id = Chance(0.45f) ? Pick(Trees) : Pick(new[] { "NAT_Bush", "NAT_Flowers", "NAT_Grass", "NAT_Grass" });
                Nature(id, p, R(0f, 360f), R(0.8f, 1.2f));
                i++;
            }
            for (int i = 0; i < 40; i++)
            {
                float a = R(0f, Mathf.PI * 2f), d = R(12f, HillRadius);
                var p = OnGround(HillCentre.x + Mathf.Cos(a) * d, HillCentre.y + Mathf.Sin(a) * d);
                if (Free(p, 0.8f)) Nature(Pick(new[] { "NAT_Grass", "NAT_Flowers", "NAT_Bush" }), p, R(0f, 360f), R(0.8f, 1.3f));
            }
            foreach (var hp in hillPath) data.pedSpots.Add(OnGround(hp.x, hp.y) + Vector3.up * 0.1f);
            Landmark("Crown Hill", summit + new Vector3(9f, 0f, -9f));
            Poi("hilltop", summit + new Vector3(10f, 0.4f, -10f));
        }

        // ------------------------------------------------------------------ airfield
        static void BuildAirfield()
        {
            float y = CityY;
            var accR = new MeshAcc();
            accR.Strip(new Vector3(-190f, 0f, -247f), new Vector3(250f, 0f, -247f), 30f, y + 0.035f, 1f / 30f);
            accR.Flush("Runway", mats["W_Runway"], roadRoot, false);
            var accA = new MeshAcc();
            accA.FlatRect(Rect.MinMaxRect(-155f, -232f, 205f, -203f), y + 0.03f, 0.1f);
            accA.FlatRect(Rect.MinMaxRect(-155.5f, -203f, -144.5f, -177f), y + 0.03f, 0.1f);
            accA.FlatRect(Rect.MinMaxRect(144.5f, -203f, 155.5f, -177f), y + 0.03f, 0.1f);
            accA.Flush("Apron", mats["W_Asphalt"], roadRoot, false);
            var term = new Vector3(-90f, y, -190f);
            Building("BLD_Terminal", term, 180f);
            Building("BLD_ControlTower", new Vector3(-30f, y, -191f), 180f);
            Building("BLD_Hangar", new Vector3(55f, y, -190f), 180f);
            Building("BLD_Hangar", new Vector3(105f, y, -190f), 180f);
            Building("BLD_Tanks", new Vector3(186f, y, -190f), 0f);
            var tb = PrefabBounds("BLD_Terminal");
            Poi("airport", Local(term, 180f, new Vector3(0f, 0.2f, tb.max.z + 3f)));
            InteriorLight(term + Vector3.up * 4f, 1.4f, 16f);
            var pad = new Vector3(-128f, y + 0.035f, -217f);
            Place("PRP_Helipad", pad, 0f, propsRoot);
            VSpawn("heli", pad, 90f);
            Poi("helipad_airfield", pad);
            VSpawn("plane", new Vector3(55f, y + 0.1f, -214f), 180f);
            VSpawn("jet", new Vector3(105f, y + 0.1f, -217f), 180f);
            VSpawn("plane", new Vector3(-170f, y + 0.1f, -247f), 90f);
            Pickup("parachute", "PRP_Pickup_Parachute", new Vector3(55f, y + 0.05f, -184f));
            Pickup("armor", "PRP_Pickup_Armor", new Vector3(105f, y + 0.05f, -184f));
            Place("PRP_Windsock", new Vector3(235f, y, -270f), 0f, propsRoot);
            for (float x = -190f; x <= 250f; x += 20f)
            {
                Place("PRP_RunwayLight", new Vector3(x, y + 0.035f, -262.4f), 0f, propsRoot);
                Place("PRP_RunwayLight", new Vector3(x, y + 0.035f, -231.6f), 0f, propsRoot);
            }
            Ramp(new Vector3(-60f, y, -276f), 90f);
            Ramp(new Vector3(120f, y, -276f), 270f);
            for (float x = -140f; x <= 190f; x += 30f) data.pedSpots.Add(new Vector3(x, y + 0.1f, -205f));
            Landmark("Halcyon Airfield", new Vector3(0f, y, -214f));
        }

        // ------------------------------------------------------------------ seabed
        static void BuildUnderwater()
        {
            var wp = OnGround(-300f, -20f);
            Place("MSC_Wreck", wp + Vector3.up * 0.3f, 32f, propsRoot);
            Pickup("cash", "PRP_Pickup_Cash", OnGround(-290f, -11f) + Vector3.up * 0.3f);
            Poi("wreck", wp);
            for (int i = 0, tries = 0; i < 90 && tries < 900; tries++)
            {
                float x = R(-345f, -240f), z = R(-140f, 140f);
                float h = GroundAt(x, z);
                if (h > -2.8f) continue;
                if (Vector2.Distance(new Vector2(x, z), new Vector2(-300f, -20f)) < 12f) continue;
                string id = Chance(0.55f) ? "NAT_Seaweed" : Chance(0.6f) ? Pick(new[] { "NAT_Coral_A", "NAT_Coral_B" }) : "NAT_Rock_B";
                Nature(id, new Vector3(x, h - 0.1f, z), R(0f, 360f), R(0.8f, 1.5f));
                i++;
            }
        }

        // ------------------------------------------------------------------ activities
        static void BuildActivities()
        {
            var start = Interact("race", new Vector3(-140f, CityY + 0.05f, -210f), 3f);
            Vector2[] cps = { new Vector2(-150f, -170f), new Vector2(-150f, -50f), new Vector2(-30f, -50f), new Vector2(-30f, 70f), new Vector2(90f, 70f),
                              new Vector2(90f, -110f), new Vector2(220f, -110f), new Vector2(220f, -170f), new Vector2(30f, -170f), new Vector2(-150f, -196f) };
            for (int i = 0; i < cps.Length; i++) Target(start, "CP" + (i + 1).ToString("00"), new Vector3(cps[i].x, CityY + 0.5f, cps[i].y));
            Poi("industrial", new Vector3(218f, PlateTop + 0.2f, -60f));
            Landmark("Ironside Yards", new Vector3(218f, PlateTop, -60f));
            if (data.playerSpawn == new Vector3(0f, 2f, 0f)) data.playerSpawn = new Vector3(0f, PlateTop + 0.2f, -20f);
        }
    }
}
