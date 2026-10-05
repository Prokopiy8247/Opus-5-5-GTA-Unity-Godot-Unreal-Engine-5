using System;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Esc menu: resume, settings, controls, skills/status, save/load, quit.</summary>
    public class PauseMenu : MonoBehaviour
    {
        public static PauseMenu I;
        public static bool IsOpen;
        Canvas canvas;
        ListMenu menu;

        public static void Init()
        {
            var go = new GameObject("[PauseMenu]");
            I = go.AddComponent<PauseMenu>();
            I.canvas = UIBuilder.Root("[PauseMenu]", 160);
            I.canvas.transform.SetParent(go.transform, false);
            var bg = UIBuilder.Panel(I.canvas.transform, Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero, new Color(0.02f, 0.03f, 0.05f, 0.93f));
            I.menu = new ListMenu(I.canvas.transform, "HALCYON - PAUSED", new Vector2(1000f, 620f), Vector2.zero, 1);
            I.menu.AddTab("RESUME", () => I.BuildResume());
            I.menu.AddTab("STATUS", () => I.BuildStatus());
            I.menu.AddTab("SETTINGS", () => I.BuildSettings());
            I.menu.AddTab("CONTROLS", () => I.BuildControls());
            I.menu.SelectTab(0);
            go.SetActive(false);
        }

        public static void Open()
        {
            if (I == null) return;
            IsOpen = true; GameInput.UIOpen = true;
            I.gameObject.SetActive(true);
            I.menu.SelectTab(0);
            GameInput.LockCursor(false);
        }

        public static void Close()
        {
            if (I == null) return;
            IsOpen = false; GameInput.UIOpen = false;
            I.gameObject.SetActive(false);
            GameInput.LockCursor(true);
        }

        void BuildResume()
        {
            menu.Row("Resume game", Close);
            menu.Row("Save game  (F5)", () => { SaveSystem.Save(); });
            menu.Row("Load game  (F9)", () => { SaveSystem.Load(); Close(); });
            menu.Row("Respawn at hospital", () => { Close(); PlayerController.I.Teleport(WorldMarkers.Hospital + new Vector3(0f, 1.2f, 0f), 180f); });
            menu.Row("Quit to desktop", () => Application.Quit(), new Color(0.3f, 0.1f, 0.12f, 0.95f));
        }

        void BuildStatus()
        {
            var ps = PlayerState.I;
            menu.Header("Cash: " + U.Money(ps.money) + "     Wanted: " + WantedSystem.Level + "/5");
            menu.Header("Districts explored, distance and stats are saved with the game.");
            for (int i = 0; i < 7; i++)
            {
                int idx = i;
                float v = ps.skills[i];
                menu.SliderRow(PlayerState.SkillNames[i], 0f, 1f, v, val => ps.skills[idx] = val, () => Mathf.RoundToInt(ps.skills[idx] * 100f) + "%   (debug slider)");
            }
            menu.Row("Garage: " + ps.garage.Count + " stored vehicle(s)", () => { });
        }

        void BuildSettings()
        {
            menu.SliderRow("Master volume", 0f, 1f, AudioFX.Master, v => { AudioFX.Master = v; AudioFX.Play("ui", 0.3f); }, () => Mathf.RoundToInt(AudioFX.Master * 100f) + "%");
            menu.SliderRow("Sound effects", 0f, 1f, AudioFX.Sfx, v => AudioFX.Sfx = v, () => Mathf.RoundToInt(AudioFX.Sfx * 100f) + "%");
            menu.SliderRow("Mouse sensitivity", 0.02f, 0.4f, GameInput.MouseSensitivity, v => GameInput.MouseSensitivity = v, () => GameInput.MouseSensitivity.ToString("F2"));
            menu.SliderRow("Time scale", 0.2f, 3f, GameManager.TimeScale, v => GameManager.TimeScale = v, () => GameManager.TimeScale.ToString("F1") + "x");
            menu.SliderRow("Day length (minutes)", 4f, 120f, GameTime.I.dayLength / 60f, v => GameTime.I.dayLength = v * 60f, () => (GameTime.I.dayLength / 60f).ToString("F0"));
            menu.Row("Invert Y axis: " + (GameInput.InvertY ? "ON" : "OFF"), () => { GameInput.InvertY = !GameInput.InvertY; menu.SelectTab(2); });
            menu.Row("Traffic: " + (TrafficManager.Enabled ? "ON" : "OFF"), () => { TrafficManager.Enabled = !TrafficManager.Enabled; menu.SelectTab(2); });
            menu.Row("Pedestrians: " + (PopulationManager.Enabled ? "ON" : "OFF"), () => { PopulationManager.Enabled = !PopulationManager.Enabled; menu.SelectTab(2); });
            menu.Row("Fullscreen: " + (Screen.fullScreen ? "ON" : "OFF"), () => { Screen.fullScreen = !Screen.fullScreen; menu.SelectTab(2); });
        }

        void BuildControls()
        {
            string[,] rows = {
                { "WASD", "Move / drive" }, { "Mouse", "Look / aim" }, { "Left Shift", "Sprint / boost" },
                { "Space", "Jump / handbrake / heli up / plane throttle +" }, { "Left Ctrl", "Dive / heli down / plane throttle -" },
                { "C", "Crouch / stealth" }, { "Left Alt", "Walk" }, { "Q", "Enter/leave cover (heli roll, plane rudder)" },
                { "F", "Enter / exit vehicle, pull driver out" }, { "G", "Enter as passenger (taxi)" },
                { "E", "Interact / ladder / store car at garage" }, { "Left Mouse", "Fire / melee (hold = heavy)" }, { "Right Mouse", "Aim / block / drive-by" },
                { "R", "Reload" }, { "1-8", "Weapon class slots" }, { "Mouse wheel", "Weapon cycle / scope zoom" },
                { "Tab", "Weapon wheel" }, { "M", "Map (click to set waypoint)" }, { "H", "Horn" }, { "N", "Siren (emergency vehicles)" }, { "L", "Lights" },
                { "S (stopped)", "Reverse" }, { "P / Up arrow", "Phone (services, taxi, garage)" },
                { "V", "Camera: near / far / first person" }, { "Esc", "Pause" }, { "F1", "Admin & benchmark menu" },
                { "F5 / F9", "Quick save / quick load" }, { "F7", "Hold: show skills" }, { ", .", "Radio station" },
            };
            for (int i = 0; i < rows.GetLength(0); i++) menu.Row(rows[i, 0].PadRight(18) + rows[i, 1], () => { });
        }
    }

    /// <summary>F1 benchmark/admin menu: instant access to every system for recording.</summary>
    public class AdminMenu : MonoBehaviour
    {
        public static AdminMenu I;
        public static bool Open;
        Canvas canvas;
        ListMenu menu;
        public static bool ShowFps = true, Invulnerable;
        public static bool ShowCoords;

        public static void Init()
        {
            var go = new GameObject("[AdminMenu]");
            I = go.AddComponent<AdminMenu>();
            I.canvas = UIBuilder.Root("[AdminMenu]", 170);
            I.canvas.transform.SetParent(go.transform, false);
            var bg = UIBuilder.Panel(I.canvas.transform, Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero, new Color(0.02f, 0.04f, 0.05f, 0.95f));
            I.menu = new ListMenu(I.canvas.transform, "ADMIN / BENCHMARK MENU", new Vector2(1160f, 660f), Vector2.zero, 1);
            I.menu.AddTab("WORLD", () => I.BuildWorld());
            I.menu.AddTab("VEHICLES", () => I.BuildVehicles());
            I.menu.AddTab("WEAPONS", () => I.BuildWeapons());
            I.menu.AddTab("PLAYER", () => I.BuildPlayer());
            I.menu.AddTab("POLICE", () => I.BuildPolice());
            I.menu.AddTab("SYSTEMS", () => I.BuildSystems());
            I.menu.SelectTab(0);
            go.SetActive(false);
        }

        public static void ToggleVehiclesTab()
        {
            if (I == null) return;
            if (!Open) Toggle();
            I.menu.SelectTab(1);
        }

        public static void Toggle()
        {
            if (I == null) return;
            Open = !Open;
            I.gameObject.SetActive(Open);
            var pauseWanted = PauseMenu.IsOpen;
            GameInput.UIOpen = Open || pauseWanted || MapScreen.IsOpen || WeaponWheel.Open;
            GameInput.LockCursor(!GameInput.UIOpen);
        }

        void BuildWorld()
        {
            menu.Header("Teleport to district");
            foreach (var (name, pos) in WorldMarkers.Landmarks)
            {
                var p = pos;
                menu.Row("-> " + name, () => { Teleport(p + new Vector3(0f, 1.2f, 8f)); Toggle(); });
            }
        }

        void Teleport(Vector3 p)
        {
            var pc = PlayerController.I;
            if (pc == null) return;
            float y = U.GroundHeight(p, p.y);
            pc.Teleport(new Vector3(p.x, y + 0.4f, p.z), UnityEngine.Random.Range(0f, 360f));
            HUD.Notify("Teleported to " + WorldMarkers.ZoneAt(p), 1.6f);
        }

        void BuildVehicles()
        {
            menu.Header("Spawn vehicle (in front of the player)");
            var avail = VehicleCatalog.Available();
            if (avail.Count == 0) { menu.Row("No vehicle prefabs found in GameDatabase", () => { }); return; }
            var names = new List<string>();
            foreach (var v in avail) names.Add(v.name + "  (" + v.id + ")");
            menu.RowButtonGrid(names.ToArray(), i =>
            {
                var def = avail[i];
                var pc = PlayerController.I;
                var fwd = pc.transform.forward;
                var pos = pc.transform.position + fwd * 7f + Vector3.up * 1.2f;
                float y = U.GroundHeight(pos, pos.y);
                var v = VehicleFactory.Spawn(def, new Vector3(pos.x, y + 0.6f, pos.z), Quaternion.LookRotation(fwd));
                if (v != null) { v.persistent = true; v.lightsOn = GameTime.IsDark; v.EngineReset(); HUD.Notify("Spawned " + def.name, 1.4f); }
                Toggle();
            }, 3);
            menu.Row("Spawn inside the nearest empty car", () =>
            {
                var pc = PlayerController.I;
                var def = VehicleCatalog.Get("sedan");
                var fwd = pc.transform.forward;
                var v = VehicleFactory.Spawn(def, pc.transform.position + fwd * 3f + Vector3.up * 0.6f, Quaternion.LookRotation(fwd));
                if (v != null) pc.PutInVehicle(v, 0);
                Toggle();
            });
            menu.Header("Garage / repair / customization");
            menu.Row("Open vehicle customization for the current/nearest vehicle", () =>
            {
                var pc = PlayerController.I;
                var v = pc.actor.vehicle ?? Vehicle.Nearest(pc.transform.position, 10f);
                if (v != null) { Toggle(); ModShop.OpenShop(v); } else HUD.Notify("No vehicle nearby", 1.4f);
            });
            menu.Row("Unlock all vehicle modifications for free: " + (ModShop.UnlockAll ? "ON" : "OFF"), () => { ModShop.UnlockAll = !ModShop.UnlockAll; menu.SelectTab(1); });
            menu.Row("Repair current vehicle", () => { var v = PlayerController.I.actor.vehicle; if (v != null) { v.Repair(); HUD.Notify("Vehicle repaired", 1.4f); } });
            menu.Row("Store current vehicle in the garage", () => PlayerState.I.StoreCurrentVehicle());
            menu.Row("Retrieve stored vehicles (spawn all)", () => PlayerState.I.SpawnStoredVehicles());
        }

        void BuildWeapons()
        {
            menu.Header("Give weapon");
            foreach (var w in WeaponCatalog.All)
            {
                var id = w.id;
                menu.Row("Give " + w.name + (w.cls == WeaponClass.Melee ? "" : "  (+ full ammo)"), () =>
                {
                    var wc = PlayerController.I.weapons;
                    wc.Give(id, w.IsMelee ? 0 : Mathf.Max(w.mag * 3, 90), true);
                    if (!w.IsMelee) { wc.reserve[id] = w.maxAmmo; wc.clip[id] = wc.MagSize(w); }
                    HUD.Notify("Given " + w.name, 1.2f);
                });
            }
            menu.Header("Weapon mods (current weapon)");
            menu.Row("Toggle suppressor", () => { var m = PlayerController.I.weapons.CurrentMods; m.suppressor = !m.suppressor; PlayerController.I.weapons.ApplyMods(); });
            menu.Row("Toggle scope", () => { var m = PlayerController.I.weapons.CurrentMods; m.scope = !m.scope; PlayerController.I.weapons.ApplyMods(); });
            menu.Row("Toggle grip", () => { var m = PlayerController.I.weapons.CurrentMods; m.grip = !m.grip; PlayerController.I.weapons.ApplyMods(); });
            menu.Row("Toggle flashlight", () => { var m = PlayerController.I.weapons.CurrentMods; m.flashlight = !m.flashlight; PlayerController.I.weapons.ApplyMods(); });
            menu.Row("Toggle extended magazine", () => { var m = PlayerController.I.weapons.CurrentMods; m.extMag = !m.extMag; });
            menu.Row("Cycle weapon tint", () => { var m = PlayerController.I.weapons.CurrentMods; m.tint = (m.tint + 1) % WeaponMods.Tints.Length; PlayerController.I.weapons.ApplyMods(); });
            menu.Row("Refill all ammo", () => { PlayerController.I.weapons.RefillAll(); HUD.Notify("Ammo refilled", 1.4f); });
            menu.Row("Give infinite ammo: " + (PlayerController.I.weapons.infiniteAmmo ? "ON" : "OFF"), () => PlayerController.I.weapons.infiniteAmmo = !PlayerController.I.weapons.infiniteAmmo);
        }

        void BuildPlayer()
        {
            menu.Row("Set money to $50,000", () => PlayerState.I.money = 50000);
            menu.Row("Set money to $500,000", () => PlayerState.I.money = 500000);
            menu.Row("Add $10,000", () => PlayerState.I.Earn(10000, "debug"));
            menu.Row("Full health + armor", () => { var a = PlayerController.I.actor; a.health = a.maxHealth; a.armor = a.maxArmor; PlayerController.I.breath = 1f; });
            menu.Row("Toggle invulnerability: " + (Invulnerable ? "ON" : "OFF"), () => { Invulnerable = !Invulnerable; PlayerController.I.actor.invulnerable = Invulnerable; menu.SelectTab(3); });
            menu.Row("Toggle never wanted: " + (WantedSystem.Suppressed ? "ON" : "OFF"), () => { WantedSystem.Suppressed = !WantedSystem.Suppressed; if (WantedSystem.Suppressed) WantedSystem.Clear(); menu.SelectTab(3); });
            menu.Row("Give parachute", () => { PlayerState.I.hasParachute = true; PlayerController.I.actor.look.SetGear(true, PlayerState.I.hasScuba); HUD.Notify("Parachute equipped", 1.4f); });
            menu.Row("Toggle scuba gear: " + (PlayerState.I.hasScuba ? "ON" : "OFF"), () => { PlayerState.I.hasScuba = !PlayerState.I.hasScuba; PlayerController.I.actor.look.SetGear(PlayerState.I.hasParachute, PlayerState.I.hasScuba); menu.SelectTab(3); });
            menu.Row("Refill lung capacity", () => { PlayerController.I.breath = 1f; });
            menu.Row("Max all skills", () => { for (int i = 0; i < 7; i++) PlayerState.I.skills[i] = 1f; HUD.Notify("Skills maxed", 1.4f); });
            menu.Row("Reset all skills", () => { for (int i = 0; i < 7; i++) PlayerState.I.skills[i] = 0f; });
            menu.Header("Clothing / appearance");
            for (int i = 0; i < 8; i++)
            {
                int idx = i;
                menu.Row("Wardrobe preset " + (i + 1), () =>
                {
                    var rnd = new System.Random(idx * 977);
                    var o = CharacterAppearance.Civilian(rnd, idx % 2 == 0);
                    PlayerState.I.outfit = o;
                    PlayerController.I.actor.look.female = idx % 2 == 0;
                    PlayerController.I.actor.look.Apply(o);
                    PlayerState.I.appearanceChangedAt = Time.time;
                    HUD.Notify("Outfit changed", 1.2f);
                });
            }
            menu.Row("Police uniform", () => { var o = CharacterAppearance.Police(new System.Random(3), false); PlayerController.I.actor.look.Apply(o); PlayerState.I.outfit = o; PlayerState.I.appearanceChangedAt = Time.time; });
            menu.Row("Tactical gear", () => { var o = CharacterAppearance.Tactical(new System.Random(5), false); PlayerController.I.actor.look.Apply(o); PlayerState.I.outfit = o; PlayerState.I.appearanceChangedAt = Time.time; });
        }

        void BuildPolice()
        {
            menu.Row("Set wanted level 0 (clear)", () => { WantedSystem.Clear(); });
            for (int i = 1; i <= 5; i++)
            {
                int lvl = i;
                menu.Row("Set wanted level " + lvl, () => { WantedSystem.SetLevelExternal(lvl); });
            }
            menu.Row("Spawn 3 police cars nearby", () =>
            {
                var pc = PlayerController.I;
                for (int i = 0; i < 3; i++)
                {
                    var a = UnityEngine.Random.insideUnitSphere * 45f; a.y = 0f;
                    var p = pc.transform.position + a + Vector3.up * 1.2f;
                    float y = U.GroundHeight(p, p.y);
                    var v = VehicleFactory.Spawn(VehicleCatalog.Get("police"), new Vector3(p.x, y + 0.6f, p.z), Quaternion.LookRotation(pc.transform.position - p));
                    if (v == null) continue;
                    v.lightsOn = true; v.sirenOn = true; v.persistent = true;
                    var drv = NPCFactory.SpawnDriver(v, v.transform.position + Vector3.up);
                    var ai = v.gameObject.AddComponent<VehicleAI>();
                    ai.Init(v, drv, true); ai.pursuing = true;
                }
                HUD.Notify("Police spawned", 1.4f);
            });
            menu.Row("Spawn tactical team on foot", () =>
            {
                var pc = PlayerController.I;
                for (int i = 0; i < 4; i++)
                {
                    var a = UnityEngine.Random.insideUnitSphere * 28f; a.y = 0f;
                    var p = pc.transform.position + a;
                    p.y = U.GroundHeight(p + Vector3.up * 2f, p.y) + 0.05f;
                    var act = NPCFactory.Spawn(NPCFactory.Archetype.Tactical, p, Quaternion.LookRotation(pc.transform.position - p));
                    if (act != null) act.GetComponent<NPCBrain>().Alert(pc.transform.position);
                }
            });
            menu.Row("Spawn police helicopter (attack)", () =>
            {
                var pc = PlayerController.I;
                var v = VehicleFactory.Spawn(VehicleCatalog.Get("policeheli"), pc.transform.position + new Vector3(60f, 70f, 60f), Quaternion.identity);
                if (v == null) return;
                v.gameObject.AddComponent<PoliceHeliAI>().Init(v, 5);
            });
            menu.Row("Escalate: gunfire crime at player position", () => WorldEvents.EmitCrime(CrimeType.Gunfire, PlayerController.I.transform.position, PlayerController.I.gameObject));
        }

        void BuildSystems()
        {
            menu.Header("Time and weather");
            for (int h = 0; h < 24; h += 2)
            {
                int hr = h;
                menu.Row("Set time " + hr.ToString("00") + ":00", () => { GameTime.I.SetTime(hr); HUD.Notify("Time: " + GameTime.Clock, 1.2f); });
            }
            menu.RowButtonGrid(new[] { "Clear", "Cloudy", "Rain", "Fog", "Storm", "Cycle" }, i =>
            {
                if (i == 5) Weather.Set((Weather.Kind)(((int)Weather.Current + 1) % 5), true);
                else Weather.Set((Weather.Kind)i, true);
            }, 6);

            menu.Header("World systems");
            menu.Row("Traffic: " + (TrafficManager.Enabled ? "ON" : "OFF"), () => { TrafficManager.Enabled = !TrafficManager.Enabled; menu.SelectTab(5); });
            menu.Row("Pedestrians: " + (PopulationManager.Enabled ? "ON" : "OFF"), () => { PopulationManager.Enabled = !PopulationManager.Enabled; menu.SelectTab(5); });
            menu.Row("Toggle wildlife: " + (Wildlife.Enabled ? "ON" : "OFF"), () => { Wildlife.Enabled = !Wildlife.Enabled; Wildlife.ApplyEnabled(); menu.SelectTab(5); });
            menu.Row("Toggle vehicle impact deformation: " + (Vehicle.DeformationEnabled ? "ON" : "OFF"), () => { Vehicle.DeformationEnabled = !Vehicle.DeformationEnabled; menu.SelectTab(5); });
            menu.Row("Show FPS: " + (ShowFps ? "ON" : "OFF"), () => { ShowFps = !ShowFps; menu.SelectTab(5); });
            menu.Row("Show coordinates: " + (ShowCoords ? "ON" : "OFF"), () => { ShowCoords = !ShowCoords; menu.SelectTab(5); });
            menu.Row("Clear all debris and bullet holes", () => { VFX.ClearHolesStatic(); });

            menu.Header("Free-roam activities");
            menu.Row("Start shooting range (5 targets)", () => Activities.StartRange());
            menu.Row("Reset stunt jump record", () => Activities.ResetStunts());
            menu.Header("Taxi / transit");
            menu.Row("Call a taxi to the player", () => TaxiService.Call());
            menu.Header("Save");
            menu.Row("Save game", () => SaveSystem.Save());
            menu.Row("Load game", () => SaveSystem.Load());
        }
    }
}
