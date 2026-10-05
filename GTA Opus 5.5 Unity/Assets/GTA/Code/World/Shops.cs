using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Shop menus: weapon store, ammo, armour/health, clothing, barber, food. Original names and UI.</summary>
    public class ShopUI : MonoBehaviour
    {
        public static ShopUI I;
        public static bool Open;
        Canvas canvas;
        ListMenu menu;
        string kind;

        public static void Init()
        {
            var go = new GameObject("[ShopUI]");
            I = go.AddComponent<ShopUI>();
            I.canvas = UIBuilder.Root("[ShopCanvas]", 157);
            I.canvas.transform.SetParent(go.transform, false);
            UIBuilder.Panel(I.canvas.transform, Vector2.zero, Vector2.one, Vector2.zero, Vector2.zero, new Color(0.02f, 0.03f, 0.05f, 0.75f));
            go.SetActive(false);
        }

        public static void Show(string shopKind)
        {
            if (I == null) return;
            I.kind = shopKind;
            if (I.menu != null) Destroy(I.menu.root);
            string title = shopKind == "weapons" ? "BRASS ANCHOR ARMS" : shopKind == "clothing" ? "THREADLINE OUTFITTERS" : shopKind == "barber" ? "SHARP COAST BARBERS" : shopKind == "food" ? "SALT SHACK DINER" : shopKind == "wardrobe" ? "SAFEHOUSE WARDROBE" : "SHOP";
            I.menu = new ListMenu(I.canvas.transform, title + "      cash " + U.Money(PlayerState.I.money), new Vector2(1060f, 640f), Vector2.zero, 1);
            switch (shopKind)
            {
                case "weapons":
                    I.menu.AddTab("HANDGUNS", () => I.BuildGuns(WeaponClass.Pistol, WeaponClass.SMG));
                    I.menu.AddTab("LONG GUNS", () => I.BuildGuns(WeaponClass.Shotgun, WeaponClass.Rifle, WeaponClass.Sniper));
                    I.menu.AddTab("HEAVY", () => I.BuildGuns(WeaponClass.Heavy, WeaponClass.Thrown, WeaponClass.Melee));
                    I.menu.AddTab("MODS", () => I.BuildMods());
                    I.menu.AddTab("ARMOUR", () => I.BuildArmour());
                    break;
                case "clothing": case "wardrobe":
                    I.menu.AddTab("TOPS", () => I.BuildClothes(0));
                    I.menu.AddTab("BOTTOMS", () => I.BuildClothes(1));
                    I.menu.AddTab("SHOES", () => I.BuildClothes(2));
                    I.menu.AddTab("HATS & EXTRAS", () => I.BuildClothes(3));
                    break;
                case "barber":
                    I.menu.AddTab("HAIR", () => I.BuildBarber());
                    break;
                case "food":
                    I.menu.AddTab("MENU", () => I.BuildFood());
                    break;
            }
            I.menu.SelectTab(0);
            Open = true;
            I.gameObject.SetActive(true);
            GameInput.UIOpen = true;
            GameInput.LockCursor(false);
        }

        public static void Close()
        {
            if (I == null) return;
            Open = false;
            I.gameObject.SetActive(false);
            GameInput.UIOpen = false;
            GameInput.LockCursor(true);
        }


        void BuildGuns(params WeaponClass[] classes)
        {
            var wc = PlayerController.I.weapons;
            foreach (var w in WeaponCatalog.All)
            {
                if (System.Array.IndexOf(classes, w.cls) < 0 || w.id == "fists") continue;
                bool owned = wc.owned.Contains(w.id);
                var wd = w;
                string stats = wd.IsMelee ? "dmg " + wd.damage : "dmg " + wd.damage + (wd.pellets > 1 ? "x" + wd.pellets : "") + "  rof " + wd.fireRate.ToString("F1") + "/s  mag " + wd.mag;
                menu.Row((owned ? "[OWNED] " : "") + wd.name + "   " + stats + "   " + (owned ? (wd.IsMelee ? "" : "ammo " + U.Money(wd.ammoPrice)) : U.Money(wd.price)), () =>
                {
                    if (!wc.owned.Contains(wd.id))
                    {
                        if (PlayerState.I.Spend(wd.price)) { wc.Give(wd.id, wd.IsMelee ? 0 : wd.mag * 3, true); HUD.Notify("Bought " + wd.name, 1.6f); }
                    }
                    else if (!wd.IsMelee)
                    {
                        if (wc.reserve.TryGetValue(wd.id, out var r) && r >= wd.maxAmmo) { HUD.Notify("Ammo full", 1.2f); return; }
                        if (PlayerState.I.Spend(wd.ammoPrice)) { wc.Give(wd.id, wd.mag * 2); HUD.Notify("+" + wd.mag * 2 + " rounds", 1.2f); }
                    }
                    menu.SelectTab(menu.activeTab);
                });
            }
        }

        void BuildMods()
        {
            var wc = PlayerController.I.weapons;
            var w = wc.Current;
            if (w == null || !w.IsGun) { menu.Row("Equip a firearm to see compatible modifications", () => { }); return; }
            var m = wc.CurrentMods;
            menu.Header("Modifications for " + w.name);
            ModRow("Suppressor (quiet: detection radius 70 m -> 12 m, -7% damage)", w.canSuppress, m.suppressor, 900, () => m.suppressor = !m.suppressor);
            ModRow("Optic / scope (tighter aim, zoom)", w.canScope, m.scope, 750, () => m.scope = !m.scope);
            ModRow("Grip (-30% recoil, -20% spread)", w.canGrip, m.grip, 500, () => m.grip = !m.grip);
            ModRow("Extended magazine (+60% capacity)", w.canExtMag, m.extMag, 650, () => m.extMag = !m.extMag);
            ModRow("Flashlight (lights the way while aiming)", w.canLight, m.flashlight, 300, () => m.flashlight = !m.flashlight);
            menu.Header("Finish / tint ($200)");
            menu.RowButtonGrid(new[] { "Gunmetal", "Gold", "Olive", "Bronze", "Arctic", "Crimson", "Navy" }, i =>
            {
                if (PlayerState.I.Spend(200)) { m.tint = i; wc.ApplyMods(); }
            }, 7);
        }

        void ModRow(string label, bool compatible, bool has, int price, System.Action toggle)
        {
            var wc = PlayerController.I.weapons;
            if (!compatible) { menu.Row(label + "   - not compatible", () => { }); return; }
            menu.Row(label + "   " + (has ? "[FITTED - click to remove]" : U.Money(price)), () =>
            {
                if (has || PlayerState.I.Spend(price)) { toggle(); wc.ApplyMods(); HUD.Notify("Weapon modified", 1.2f); }
                menu.SelectTab(menu.activeTab);
            });
        }

        void BuildArmour()
        {
            var a = PlayerController.I.actor;
            menu.Row("Light body armour (+50) - $400", () => { if (PlayerState.I.Spend(400)) a.armor = Mathf.Min(a.maxArmor, a.armor + 50f); });
            menu.Row("Heavy body armour (full) - $900", () => { if (PlayerState.I.Spend(900)) a.armor = a.maxArmor; });
            menu.Row("First aid kit (full health) - $250", () => { if (PlayerState.I.Spend(250)) { a.health = a.maxHealth; VFX.Heal(a.Center); } });
            menu.Row("Parachute - $500", () => { if (PlayerState.I.Spend(500)) { PlayerState.I.hasParachute = true; a.look.SetGear(true, PlayerState.I.hasScuba); } });
            menu.Row("Scuba rebreather (10 min underwater) - $1,500", () => { if (PlayerState.I.Spend(1500)) { PlayerState.I.hasScuba = true; a.look.SetGear(PlayerState.I.hasParachute, true); } });
        }

        static readonly string[] Colors = { "#2a9d8f", "#e76f51", "#f4a261", "#e9c46a", "#264653", "#f1faee", "#8ecae6", "#ff006e", "#6a4c93", "#ef476f", "#118ab2", "#3a5a40", "#111111", "#7f5539", "#b7b7a4", "#1d3557" };
        static readonly string[] ColorNames = { "Lagoon", "Coral", "Apricot", "Sand", "Teal", "Cream", "Sky", "Neon Pink", "Grape", "Watermelon", "Ocean", "Forest", "Black", "Leather", "Stone", "Navy" };

        void BuildClothes(int part)
        {
            var o = PlayerState.I.outfit ?? CharacterAppearance.PlayerDefault();
            bool free = kind == "wardrobe";
            int price = free ? 0 : (part == 3 ? 120 : 180);
            System.Action apply = () =>
            {
                PlayerState.I.outfit = o;
                PlayerController.I.actor.look.Apply(o);
                PlayerState.I.appearanceChangedAt = Time.time;
            };
            if (part == 0)
            {
                menu.Header("Shirts & jackets  " + (free ? "(owned)" : U.Money(price)));
                menu.RowButtonGrid(ColorNames, i => { if (free || PlayerState.I.Spend(price)) { o.top = U.Hex(Colors[i]); apply(); } }, 8);
                menu.Row("Sleeves: " + (o.longSleeves ? "long (jacket)" : "short (tee)"), () => { o.longSleeves = !o.longSleeves; apply(); menu.SelectTab(0); });
            }
            else if (part == 1)
            {
                menu.Header("Pants & shorts");
                menu.RowButtonGrid(ColorNames, i => { if (free || PlayerState.I.Spend(price)) { o.bottom = U.Hex(Colors[i]); apply(); } }, 8);
                menu.Row("Length: " + (o.shorts ? "shorts" : "full length"), () => { o.shorts = !o.shorts; apply(); menu.SelectTab(1); });
            }
            else if (part == 2)
            {
                menu.Header("Shoes");
                menu.RowButtonGrid(ColorNames, i => { if (free || PlayerState.I.Spend(price)) { o.shoes = U.Hex(Colors[i]); apply(); } }, 8);
            }
            else
            {
                menu.Header("Hats");
                menu.RowButtonGrid(new[] { "None", "Cap", "Beanie" }, i => { if (free || PlayerState.I.Spend(price)) { o.hat = i - 1; apply(); } }, 3);
                menu.Header("Hat colour");
                menu.RowButtonGrid(ColorNames, i => { if (free || PlayerState.I.Spend(60)) { o.acc = U.Hex(Colors[i]); apply(); } }, 8);
                menu.Row("Sunglasses: " + (o.glasses ? "ON" : "OFF"), () => { if (free || PlayerState.I.Spend(90)) { o.glasses = !o.glasses; apply(); menu.SelectTab(3); } });
            }
        }

        void BuildBarber()
        {
            var o = PlayerState.I.outfit ?? CharacterAppearance.PlayerDefault();
            System.Action apply = () => { PlayerState.I.outfit = o; PlayerController.I.actor.look.Apply(o); PlayerState.I.appearanceChangedAt = Time.time; };
            menu.Header("Haircut ($80)");
            menu.RowButtonGrid(new[] { "Short", "Long", "Bun", "Buzz", "Curly", "Shaved" }, i => { if (PlayerState.I.Spend(80)) { o.hair = i == 5 ? -1 : i; apply(); } }, 6);
            menu.Header("Hair colour ($60)");
            menu.RowButtonGrid(new[] { "Black", "Dark brown", "Brown", "Auburn", "Blonde", "Grey", "Copper" }, i => { if (PlayerState.I.Spend(60)) { o.hairColor = U.Hex(CharacterAppearance.HairTones[i]); apply(); } }, 7);
            menu.Row("Beard: " + (o.beard ? "ON" : "OFF") + " ($40)", () => { if (PlayerState.I.Spend(40)) { o.beard = !o.beard; apply(); menu.SelectTab(0); } });
        }

        void BuildFood()
        {
            var a = PlayerController.I.actor;
            menu.Row("Fish taco (+25 health) - $12", () => { if (PlayerState.I.Spend(12)) { a.Heal(25f); VFX.Heal(a.Center); } });
            menu.Row("Harbour platter (+60 health) - $28", () => { if (PlayerState.I.Spend(28)) { a.Heal(60f); VFX.Heal(a.Center); } });
            menu.Row("Energy drink (stamina refill) - $6", () => { if (PlayerState.I.Spend(6)) PlayerController.I.stamina = 1f; });
        }
    }

    /// <summary>Binds world interaction points placed by the world builder (identified by Interactable.id) to behaviour.</summary>
    public static class WorldInteractions
    {
        public static void BindAll()
        {
            Physics.SyncTransforms();
            int moved = 0, stuck = 0;
            foreach (var it in Object.FindObjectsByType<Interactable>(FindObjectsSortMode.None))
            {
                var before = it.transform.position;
                if (!it.EnsureReachable()) stuck++;
                else if ((it.transform.position - before).sqrMagnitude > 0.01f) moved++;
                Bind(it);
            }
            if (moved > 0 || stuck > 0) Debug.Log("[World] interaction points moved out of geometry: " + moved + ", still blocked: " + stuck);
        }

        public static void Bind(Interactable it)
        {
            switch (it.id)
            {
                case "weaponshop": it.Prompt = "Brass Anchor Arms - buy weapons, ammo, mods"; it.action = pc => ShopUI.Show("weapons"); break;
                case "clothing": it.Prompt = "Threadline Outfitters - clothes"; it.action = pc => ShopUI.Show("clothing"); break;
                case "barber": it.Prompt = "Sharp Coast Barbers"; it.action = pc => ShopUI.Show("barber"); break;
                case "food": it.Prompt = "Salt Shack Diner - eat"; it.action = pc => ShopUI.Show("food"); break;
                case "wardrobe": it.Prompt = "Wardrobe"; it.action = pc => ShopUI.Show("wardrobe"); break;
                case "bed": it.Prompt = "Sleep until morning & save"; it.action = pc => { GameTime.I.SetTime(GameTime.Hour < 7f ? 8f : (GameTime.Hour + 8f) % 24f); pc.actor.health = pc.actor.maxHealth; SaveSystem.Save(); HUD.Notify("You slept. Game saved.", 2.4f); }; break;
                case "garage": it.Prompt = "Garage - store/retrieve vehicles"; it.action = pc => { if (pc.actor.InVehicle) PlayerState.I.StoreCurrentVehicle(); else Phone.Toggle(); }; break;
                case "modshop": it.Prompt = "Bay 7 - drive in for repair & custom"; it.action = pc => { var v = pc.actor.vehicle ?? Vehicle.Nearest(pc.transform.position, 8f); if (v != null) ModShop.OpenShop(v); else HUD.Notify("Bring a vehicle into the bay", 2f); }; break;
                case "parachute": it.Prompt = "Take parachute"; it.action = pc => { PlayerState.I.hasParachute = true; pc.actor.look.SetGear(true, PlayerState.I.hasScuba); HUD.Notify("Parachute equipped - jump!", 2f); }; break;
                case "scuba": it.Prompt = "Rent scuba gear ($200)"; it.action = pc => { if (PlayerState.I.Spend(200)) { PlayerState.I.hasScuba = true; pc.actor.look.SetGear(PlayerState.I.hasParachute, true); HUD.Notify("Scuba gear on - dive near the wreck", 2.4f); } }; break;
                case "armor": it.Prompt = "Body armour pickup"; it.oneShot = false; it.action = pc => { pc.actor.armor = pc.actor.maxArmor; HUD.Notify("Armour +100", 1.4f); AudioFX.Play("cash", 0.3f); it.gameObject.SetActive(false); }; break;
                case "health": it.Prompt = "Health pickup"; it.action = pc => { pc.actor.health = pc.actor.maxHealth; VFX.Heal(pc.actor.Center); it.gameObject.SetActive(false); }; break;
                case "cash": it.Prompt = "Pick up cash"; it.action = pc => { PlayerState.I.Earn(Random.Range(80, 400), "cash"); it.gameObject.SetActive(false); }; break;
                case "elevator_up": it.Prompt = "Elevator to the roof"; it.action = pc => { var t = it.transform.Find("Target"); if (t != null) pc.Teleport(t.position, pc.transform.eulerAngles.y); }; break;
                case "elevator_down": it.Prompt = "Elevator to street level"; it.action = pc => { var t = it.transform.Find("Target"); if (t != null) pc.Teleport(t.position, pc.transform.eulerAngles.y); }; break;
                case "range": it.Prompt = "Shooting range ($50)"; it.action = pc => { if (PlayerState.I.Spend(50)) Activities.StartRange(); }; break;
                case "boatrental": it.Prompt = "Rent a speedboat ($150)"; it.action = pc => { if (PlayerState.I.Spend(150)) { var tgt = it.transform.Find("Target"); var p = tgt != null ? tgt.position : pc.transform.position + Vector3.left * 12f; var v = VehicleFactory.Spawn(VehicleCatalog.Get("speedboat"), p, Quaternion.Euler(0f, 270f, 0f)); if (v != null) v.persistent = true; } }; break;
                case "vehiclelot": it.Prompt = "Coastline Motors - vehicle lot (spawn any car)"; it.action = pc => AdminMenu.ToggleVehiclesTab(); break;
                case "atm": it.Prompt = "ATM - withdraw $500"; it.action = pc => PlayerState.I.Earn(500, "ATM"); break;
                case "robbery": it.Prompt = "Hold up the register"; it.action = pc => { PlayerState.I.Earn(Random.Range(300, 900), "register cash"); WorldEvents.EmitCrime(CrimeType.Robbery, pc.transform.position, pc.gameObject); AudioFX.PlayAt("alarm", it.transform.position, 0.6f); }; break;
                case "race": it.Prompt = "Start street race"; it.action = pc => { var cps = new List<Transform>(); foreach (Transform c in it.transform) if (c.name.StartsWith("CP")) cps.Add(c); Activities.StartStreetRace(cps); }; break;
                case "taxi": it.Prompt = "Taxi stand - call a cab"; it.action = pc => TaxiService.Call(); break;
                default: it.Prompt = it.id; break;
            }
        }
    }
}
