using UnityEngine;

namespace Halcyon
{
    /// <summary>Garage / personal-vehicle helpers used by the menus, phone and admin tools.</summary>
    public static class GarageApi
    {
        public static void StoreCurrentVehicle(this PlayerState ps)
        {
            var v = PlayerController.I != null ? PlayerController.I.actor.vehicle : null;
            if (v == null || v.def == null) { HUD.Notify("Enter a vehicle first", 1.6f); return; }
            if (ps.garage.Count >= 8) { HUD.Notify("Garage full (8 vehicles)", 1.8f); return; }
            ps.garage.Add(new StoredVehicle { id = v.def.id, mods = v.mods.ToJson() });
            HUD.Notify("Stored " + v.def.name + " (" + ps.garage.Count + "/8). Retrieve it from the phone GARAGE tab", 2.6f);
            AudioFX.Play("cash", 0.4f);
            // the car goes into the garage: the player steps out and the world copy is removed
            v.persistent = true;
            foreach (var s in v.seats) if (s.occupant != null && !s.occupant.IsPlayer) v.EjectOccupant(s.occupant, false);
            PlayerController.I.ForceExitVehicleNow();
            Object.Destroy(v.gameObject, 1.3f);
        }

        /// <summary>Garage door marker within reach of the player (used for the E-to-store prompt).</summary>
        public static bool NearGarage(Vector3 p, float radius = 10f)
        {
            foreach (var g in WorldMarkers.Garages) if (U.FlatDist(g, p) < radius) return true;
            return false;
        }

        public static void RetrieveVehicle(this PlayerState ps, int index)
        {
            if (index < 0 || index >= ps.garage.Count) return;
            var st = ps.garage[index];
            var def = VehicleCatalog.Get(st.id);
            if (def == null) { HUD.Notify("Unknown vehicle", 1.6f); return; }
            var pc = PlayerController.I;
            var fwd = pc.transform.forward;
            var p = pc.transform.position + fwd * 8f + pc.transform.right * 3f;
            float y = U.GroundHeight(p + Vector3.up * 2f, p.y) + 0.6f;
            var v = VehicleFactory.Spawn(def, new Vector3(p.x, y, p.z), Quaternion.LookRotation(fwd));
            if (v == null) { HUD.Notify("Vehicle unavailable", 1.6f); return; }
            v.mods = VehicleMods.FromJson(st.mods);
            v.ApplyMods();
            v.engineOn = true;
            v.persistent = true;
            ps.garage.RemoveAt(index);
            HUD.Notify("Retrieved " + def.name, 1.8f);
        }

        public static void SpawnStoredVehicles(this PlayerState ps)
        {
            if (ps.garage.Count == 0) { HUD.Notify("No stored vehicles", 1.6f); return; }
            int spawned = 0;
            var basePos = WorldMarkers.Garages.Count > 0 ? WorldMarkers.Garages[0] : WorldMarkers.Safehouse;
            foreach (var st in ps.garage.ToArray())
            {
                if (spawned >= 4) break;
                var def = VehicleCatalog.Get(st.id);
                if (def == null) continue;
                var p = basePos + new Vector3(spawned * 4.5f - 4.5f, 1.2f, 6f);
                float y = U.GroundHeight(p, p.y) + 0.5f;
                var v = VehicleFactory.Spawn(def, new Vector3(p.x, y, p.z), Quaternion.identity);
                if (v == null) continue;
                v.mods = VehicleMods.FromJson(st.mods);
                v.ApplyMods();
                v.engineOn = true;
                v.persistent = true;
                ps.garage.Remove(st);   // it now exists in the world again
                spawned++;
            }
            HUD.Notify(spawned + " vehicle(s) delivered to the garage", 2.4f);
        }

        public static void EngineReset(this Vehicle v)
        {
            if (v == null) return;
            v.engineOn = true;
            v.input = new VehicleInput();
        }
    }

    /// <summary>Vehicle customization & repair shop (Bay 7): repair, paint, body parts, performance, wheels.</summary>
    public class ModShop : MonoBehaviour
    {
        public static ModShop I;
        public static bool Open;
        Canvas canvas;
        ListMenu menu;
        Vehicle vehicle;
        public static bool UnlockAll;

        public static void Init()
        {
            var go = new GameObject("[ModShop]");
            I = go.AddComponent<ModShop>();
            I.canvas = UIBuilder.Root("[ModShopCanvas]", 158);
            I.canvas.transform.SetParent(go.transform, false);
            UIBuilder.Panel(I.canvas.transform, Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero, new Color(0.03f, 0.05f, 0.06f, 0.6f));
            I.menu = new ListMenu(I.canvas.transform, "BAY 7 - SERVICE & CUSTOM", new Vector2(1000f, 600f), new Vector2(380f, 0f), 1);
            I.menu.AddTab("REPAIR", () => I.BuildRepair());
            I.menu.AddTab("PAINT", () => I.BuildPaint());
            I.menu.AddTab("BODY", () => I.BuildBody());
            I.menu.AddTab("PERFORMANCE", () => I.BuildPerf());
            I.menu.AddTab("WHEELS", () => I.BuildWheels());
            go.SetActive(false);
        }

        public static void OpenShop(Vehicle v)
        {
            if (I == null || v == null || v.def == null) return;
            I.vehicle = v;
            Open = true;
            I.gameObject.SetActive(true);
            GameInput.UIOpen = true;
            GameInput.LockCursor(false);
            I.menu.SelectTab(0);
        }

        public static void Close()
        {
            if (I == null) return;
            Open = false;
            GameInput.UIOpen = false;
            GameInput.LockCursor(true);
            I.gameObject.SetActive(false);
        }

        bool Pay(int price) => UnlockAll || PlayerState.I.Spend(price);

        static readonly string[] Paints = { "#d64a3b", "#264653", "#e5e5e5", "#3d405b", "#6d6875", "#1d3557", "#b5838d", "#e9c46a", "#2a9d8f", "#f4a261", "#8ecae6", "#ffb703", "#06d6a0", "#7209b7", "#f1faee", "#111111" };
        static readonly string[] PaintNames = { "Coral Red", "Deep Teal", "Pearl", "Slate", "Mauve", "Navy", "Rose", "Sand", "Lagoon", "Apricot", "Sky", "Amber", "Mint", "Violet", "Snow", "Onyx" };
        static readonly string[] Finishes = { "Gloss", "Matte", "Metallic", "Chrome" };
        static readonly string[] Wheels = { "Stock", "Sport", "Offroad", "Chrome" };
        static readonly string[] LightTints = { "Stock", "Xenon", "Amber" };
        static readonly string[] Horns = { "Standard", "Truck", "Sport" };

        void BuildRepair()
        {
            var m = vehicle.mods;
            menu.Header(vehicle.def.name + "   condition " + Mathf.RoundToInt(vehicle.health / vehicle.maxHealth * 100f) + "%   cash " + U.Money(PlayerState.I.money));
            menu.Row("Full repair (body, engine, lights, glass) - $350", () => { if (Pay(350)) { vehicle.Repair(); HUD.Notify("Repaired", 1.4f); menu.SelectTab(0); } });
            menu.Row("Headlight tint: " + LightTints[m.lightsTint] + "  - $150", () => { if (Pay(150)) { m.lightsTint = (m.lightsTint + 1) % 3; vehicle.ApplyMods(); menu.SelectTab(0); } });
            menu.Row("Horn: " + Horns[m.horn] + "  - $100", () => { if (Pay(100)) { m.horn = (m.horn + 1) % 3; menu.SelectTab(0); } });
            menu.Row("Store this vehicle in my garage", () => { PlayerState.I.StoreCurrentVehicle(); });
            menu.Row("Unlock everything for free (benchmark): " + (UnlockAll ? "ON" : "OFF"), () => { UnlockAll = !UnlockAll; menu.SelectTab(0); });
            menu.Row("Leave the bay", Close);
        }

        void BuildPaint()
        {
            var m = vehicle.mods;
            menu.Header("Primary colour ($200)");
            menu.RowButtonGrid(PaintNames, i => { if (Pay(200)) { m.paint = Paints[i]; vehicle.ApplyMods(); } }, 8);
            menu.Header("Secondary colour ($150)");
            menu.RowButtonGrid(PaintNames, i => { if (Pay(150)) { m.paint2 = Paints[i]; vehicle.ApplyMods(); } }, 8);
            menu.Header("Finish ($300)  current: " + Finishes[m.finish]);
            menu.RowButtonGrid(Finishes, i => { if (Pay(300)) { m.finish = i; vehicle.ApplyMods(); menu.SelectTab(1); } }, 4);
            menu.Header("Window tint ($250)");
            menu.RowButtonGrid(new[] { "Clear", "Light", "Dark", "Limo" }, i => { if (Pay(250)) { m.tint = i; vehicle.ApplyMods(); } }, 4);
        }

        void BuildBody()
        {
            var m = vehicle.mods;
            menu.Header("Body parts - Blender-authored modular variants");
            menu.Row("Spoiler: " + (m.spoiler == 0 ? "none" : m.spoiler == 1 ? "lip" : "wing") + " (cycle) - $600", () => { if (Pay(600)) { m.spoiler = (m.spoiler + 1) % 3; vehicle.ApplyMods(); menu.SelectTab(2); } });
            BodyRow("Hood scoop", "MOD_Hood_1", () => m.hood, v => m.hood = v, 500);
            BodyRow("Side skirts", "MOD_Skirt_1", () => m.skirts, v => m.skirts = v, 450);
            BodyRow("Sport front bumper", "MOD_BumperF_1", () => m.bumper, v => m.bumper = v, 700);
            BodyRow("Twin exhaust", "MOD_Exhaust_1", () => m.exhaust, v => m.exhaust = v, 400);
            BodyRow("Chrome grille", "MOD_Grille_1", () => m.grille, v => m.grille = v, 300);
            BodyRow("Roof rack", "MOD_Roof_1", () => m.roof, v => m.roof = v, 350);
            BodyRow("Racing stripe livery", "MOD_Livery_1", () => m.livery, v => m.livery = v, 500);
        }

        void BodyRow(string label, string part, System.Func<bool> get, System.Action<bool> set, int price)
        {
            bool has = vehicle.HasPart(part);
            menu.Row(label + ": " + (has ? (get() ? "FITTED" : "stock") : "n/a for this model") + (has ? "  - $" + price : ""), () =>
            {
                if (!has) return;
                if (get()) { set(false); vehicle.ApplyMods(); menu.SelectTab(2); return; }
                if (Pay(price)) { set(true); vehicle.ApplyMods(); menu.SelectTab(2); }
            });
        }

        void BuildPerf()
        {
            var m = vehicle.mods;
            menu.Header("Performance - every level changes the handling model");
            PerfRow("Engine tune", m.engine, 1200, () => m.engine++, "torque x" + m.TorqueMul.ToString("F2"));
            PerfRow("Turbo", m.turbo, 1600, () => m.turbo++, "top speed x" + m.TopSpeedMul.ToString("F2"));
            PerfRow("Brakes", m.brakes, 900, () => m.brakes++, "brake x" + m.BrakeMul.ToString("F2"));
            PerfRow("Suspension", m.suspension, 1000, () => m.suspension++, "grip x" + m.GripMul.ToString("F2"));
            PerfRow("Transmission", m.transmission, 1400, () => m.transmission++, "steer x" + m.SteerMul.ToString("F2"));
            PerfRow("Armour plating", m.armor, 2000, () => m.armor++, "damage x" + m.ArmorMul.ToString("F2"));
            PerfRow("Performance tires", m.tires, 800, () => m.tires++, "");
            menu.Row("Reset all upgrades to stock", () => { m.engine = m.turbo = m.brakes = m.suspension = m.transmission = m.armor = m.tires = 0; vehicle.ApplyMods(); menu.SelectTab(3); });
        }

        void PerfRow(string label, int level, int price, System.Action inc, string effect)
        {
            menu.Row(label + "  level " + level + "/3   " + effect + (level < 3 ? "   next: $" + (price * (level + 1)) : "   MAX"), () =>
            {
                if (level >= 3) return;
                if (Pay(price * (level + 1))) { inc(); vehicle.ApplyMods(); AudioFX.Play("cash", 0.4f); menu.SelectTab(3); }
            });
        }

        void BuildWheels()
        {
            var m = vehicle.mods;
            menu.Header("Wheels ($400)  current: " + Wheels[m.wheelType]);
            menu.RowButtonGrid(Wheels, i => { if (Pay(400)) { m.wheelType = i; vehicle.ApplyMods(); menu.SelectTab(4); } }, 4);
            menu.Header("Rim colour ($150)");
            menu.RowButtonGrid(new[] { "Silver", "Black", "Gold", "White", "Copper", "Chrome" }, i =>
            {
                if (!Pay(150)) return;
                m.wheelColor = new[] { "#b9c0c7", "#22252a", "#e9c46a", "#f1faee", "#b87333", "#e8ecef" }[i];
                vehicle.ApplyMods();
            }, 6);
        }
    }
}
