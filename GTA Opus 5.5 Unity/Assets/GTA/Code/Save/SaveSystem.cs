using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Save/load of the core free-roam state as JSON in persistentDataPath.</summary>
    public static class SaveSystem
    {
        [System.Serializable]
        public class Data
        {
            public int version = 1;
            public float px, py, pz, yaw;
            public float health, armor, breath;
            public int money, wanted;
            public float time01;
            public int weather;
            public string[] weapons;
            public int[] clips, reserves;
            public float[] skills;
            public bool parachute, scuba;
            public string[] garage;
            public string[] garageMods;
            public string outfitJson;
            public float playerX, playerY, playerZ;
        }

        static string Path => System.IO.Path.Combine(Application.persistentDataPath, "halcyon_save.json");

        public static void Save()
        {
            var pc = PlayerController.I;
            if (pc == null) return;
            var ps = PlayerState.I;
            var wc = pc.weapons;
            var d = new Data
            {
                px = pc.transform.position.x, py = pc.transform.position.y, pz = pc.transform.position.z, yaw = pc.transform.eulerAngles.y,
                health = pc.actor.health, armor = pc.actor.armor, breath = pc.breath,
                money = ps.money, wanted = WantedSystem.Level,
                time01 = GameTime.Time01, weather = (int)Weather.Current,
                weapons = wc.owned.ToArray(),
                clips = new int[wc.owned.Count], reserves = new int[wc.owned.Count],
                skills = (float[])ps.skills.Clone(),
                parachute = ps.hasParachute, scuba = ps.hasScuba,
                garage = new string[ps.garage.Count], garageMods = new string[ps.garage.Count],
                outfitJson = ps.outfit != null ? JsonUtility.ToJson(ps.outfit) : "",
            };
            for (int i = 0; i < wc.owned.Count; i++)
            {
                d.clips[i] = wc.clip.TryGetValue(wc.owned[i], out var c) ? c : 0;
                d.reserves[i] = wc.reserve.TryGetValue(wc.owned[i], out var r) ? r : 0;
            }
            for (int i = 0; i < ps.garage.Count; i++) { d.garage[i] = ps.garage[i].id; d.garageMods[i] = ps.garage[i].mods; }
            try
            {
                System.IO.File.WriteAllText(Path, JsonUtility.ToJson(d, true));
                HUD.Notify("Game saved", 1.6f);
            }
            catch (System.Exception e) { Debug.LogWarning("[Save] " + e.Message); HUD.Notify("Save failed", 2f); }
        }

        public static void Load()
        {
            if (!System.IO.File.Exists(Path)) { HUD.Notify("No save file found", 2f); return; }
            try
            {
                var d = JsonUtility.FromJson<Data>(System.IO.File.ReadAllText(Path));
                if (d == null) return;
                var pc = PlayerController.I;
                var ps = PlayerState.I;
                pc.Teleport(new Vector3(d.px, d.py, d.pz), d.yaw);
                pc.actor.health = Mathf.Max(1f, d.health);
                pc.actor.armor = d.armor;
                pc.breath = Mathf.Clamp01(d.breath > 0f ? d.breath : 1f);
                ps.money = d.money;
                ps.hasParachute = d.parachute; ps.hasScuba = d.scuba;
                if (d.skills != null) for (int i = 0; i < Mathf.Min(7, d.skills.Length); i++) ps.skills[i] = d.skills[i];
                var wc = pc.weapons;
                wc.owned.Clear(); wc.clip.Clear(); wc.reserve.Clear();
                wc.owned.Add("fists");
                if (d.weapons != null)
                    for (int i = 0; i < d.weapons.Length; i++)
                    {
                        if (!wc.owned.Contains(d.weapons[i])) wc.owned.Add(d.weapons[i]);
                        wc.clip[d.weapons[i]] = d.clips != null && i < d.clips.Length ? d.clips[i] : 0;
                        wc.reserve[d.weapons[i]] = d.reserves != null && i < d.reserves.Length ? d.reserves[i] : 0;
                    }
                wc.Equip(wc.owned.Count > 1 ? wc.owned[1] : "fists");
                ps.garage.Clear();
                if (d.garage != null)
                    for (int i = 0; i < d.garage.Length; i++)
                        ps.garage.Add(new StoredVehicle { id = d.garage[i], mods = d.garageMods != null && i < d.garageMods.Length ? d.garageMods[i] : "" });
                if (!string.IsNullOrEmpty(d.outfitJson))
                {
                    try { ps.outfit = JsonUtility.FromJson<Outfit>(d.outfitJson); pc.actor.look?.Apply(ps.outfit); } catch { }
                }
                if (GameTime.I != null) GameTime.I.SetTime(d.time01 * 24f);
                Weather.Set((Weather.Kind)Mathf.Clamp(d.weather, 0, 4), true);
                WantedSystem.SetLevelExternal(d.wanted);
                pc.actor.look?.SetGear(ps.hasParachute, ps.hasScuba);
                HUD.Notify("Game loaded", 2f);
            }
            catch (System.Exception e) { Debug.LogWarning("[Load] " + e.Message); HUD.Notify("Load failed", 2f); }
        }
    }

    /// <summary>In-game phone: services, taxi, quick save, map, garage retrieval.</summary>
    public class Phone : MonoBehaviour
    {
        public static Phone I;
        public static bool Open;
        Canvas canvas;
        ListMenu menu;
        public static bool UpgradedTires;

        public static void Init()
        {
            var go = new GameObject("[Phone]");
            I = go.AddComponent<Phone>();
            I.canvas = UIBuilder.Root("[Phone]", 155);
            I.canvas.transform.SetParent(go.transform, false);
            var frame = UIBuilder.Panel(I.canvas.transform, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, Vector2.zero, new Color(0.06f, 0.07f, 0.09f, 0.98f));
            var fw = new Vector2(560f, 700f);
            frame.sizeDelta = fw; frame.anchoredPosition = Vector2.zero;
            var outline = frame.gameObject.AddComponent<UnityEngine.UI.Outline>(); outline.effectColor = new Color(0.3f, 0.75f, 0.85f, 0.5f); outline.effectDistance = new Vector2(3f, 3f);
            I.menu = new ListMenu(frame, "HALCYON PHONE", new Vector2(540f, 660f), Vector2.zero, 2);
            I.menu.AddTab("SERVICES", () => I.BuildServices());
            I.menu.AddTab("TAXI", () => I.BuildTaxi());
            I.menu.AddTab("GARAGE", () => I.BuildGarage());
            I.menu.SelectTab(0);
            go.SetActive(false);
        }

        public static void Toggle()
        {
            if (I == null) return;
            Open = !Open;
            I.gameObject.SetActive(Open);
            GameInput.UIOpen = Open || PauseMenu.IsOpen || AdminMenu.Open || MapScreen.IsOpen || WeaponWheel.Open;
            GameInput.LockCursor(!GameInput.UIOpen);
        }

        void BuildServices()
        {
            menu.Row("Call taxi", () => { TaxiService.Call(); Close(); });
            menu.Row("Quick save", () => { SaveSystem.Save(); });
            menu.Row("Open map", () => { Close(); MapScreen.ShowMap(); });
            menu.Row("Request vehicle repair (free, debug)", () =>
            {
                var v = PlayerController.I.actor.vehicle;
                if (v != null) { v.Repair(); HUD.Notify("Vehicle repaired", 1.6f); }
                else HUD.Notify("Not in a vehicle", 1.4f);
            });
            menu.Row("Landmark list / waypoints", () => { });
            foreach (var (n, p) in WorldMarkers.Landmarks)
            {
                var pos = p;
                menu.Row("  -> waypoint: " + n, () => { MapScreen.Waypoint = pos; HUD.Notify("Waypoint: " + n, 1.6f); Close(); });
            }
            menu.Row("Weather forecast: " + Weather.Current, () => Weather.Set((Weather.Kind)(((int)Weather.Current + 1) % 5), true));
        }

        void BuildTaxi()
        {
            menu.Row("Call a taxi to my position", () => { TaxiService.Call(); Close(); });
            menu.Row("Cancel / release the taxi", () => { if (TaxiService.Current != null) { TaxiService.Current.persistent = false; } HUD.Notify("Taxi released", 1.2f); });
            menu.Header("Ride destinations (get in as a passenger with G; the trip is skipped)");
            foreach (var (n, p) in TaxiService.Destinations())
            {
                var pos = p;
                menu.Row("  -> " + n, () =>
                {
                    TaxiService.SetDestination(pos, n);
                    Close();
                });
            }
        }

        void BuildGarage()
        {
            var ps = PlayerState.I;
            menu.Header("Stored vehicles (" + ps.garage.Count + ")");
            if (ps.garage.Count == 0) menu.Row("No stored vehicles yet - drive into a garage to store one", () => { });
            for (int i = 0; i < ps.garage.Count; i++)
            {
                int idx = i;
                var def = VehicleCatalog.Get(ps.garage[i].id);
                menu.Row("Retrieve " + (def != null ? def.name : ps.garage[i].id), () => { ps.RetrieveVehicle(idx); Close(); });
            }
            menu.Row("Move all stored vehicles to the safehouse garage", () => { ps.SpawnStoredVehicles(); Close(); });
        }

        public static void Close()
        {
            if (I == null) return;
            Open = false;
            I.gameObject.SetActive(false);
            GameInput.UIOpen = PauseMenu.IsOpen || AdminMenu.Open || MapScreen.IsOpen || WeaponWheel.Open;
            GameInput.LockCursor(!GameInput.UIOpen);
        }
    }
}
