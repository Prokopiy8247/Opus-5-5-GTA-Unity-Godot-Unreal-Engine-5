"""One-off patch (segment 5): more autotest coverage - bicycle, carjack, shop purchase via UI, taxi ride, death respawn, busted."""
import os
ROOT = os.path.join(os.path.dirname(__file__), "..", "Assets", "GTA", "Code")


def edit(rel, pairs):
    p = os.path.join(ROOT, rel)
    s = open(p, encoding="utf-8").read()
    for old, new in pairs:
        assert s.count(old) == 1, (rel, old[:90], s.count(old))
        s = s.replace(old, new)
    open(p, "w", encoding="utf-8").write(s)


edit("Core/AutoTester.cs", [
("""            yield return DriveTest("motorbike", 6f, 25f);
            yield return TrafficTest();""",
 """            yield return DriveTest("motorbike", 6f, 25f);
            yield return DriveTest("bicycle", 6f, 10f);
            yield return TrafficTest();
            yield return CarjackTest();"""),
("""            yield return ShopsModsSave();
            yield return TaxiWildlife();
            yield return VehicleDamageTest();""",
 """            yield return ShopsModsSave();
            yield return ShopPurchaseTest();
            yield return TaxiWildlife();
            yield return VehicleDamageTest();
            yield return BustedAndDeathTest();"""),
("""            Check("drive." + id, dist > minDist && vmax > 20f, string.Format("moved {0:F1} m in {1:F0} s, top {2:F0} km/h", dist, seconds, vmax));""",
 """            Check("drive." + id, dist > minDist && vmax > (id == "bicycle" ? 10f : 20f), string.Format("moved {0:F1} m in {1:F0} s, top {2:F0} km/h", dist, seconds, vmax));"""),
# taxi: actually ride it
("""            Check("world.taxi", taxi != null, "taxi called, distance to player " + d.ToString("F0") + " m");
            if (taxi != null) yield return Shot("taxi", pc.transform.position + new Vector3(-6f, 4f, -6f), taxi.transform.position);""",
 """            if (taxi != null) yield return Shot("taxi", pc.transform.position + new Vector3(-6f, 4f, -6f), taxi.transform.position);
            for (float t = 0; t < 30f && taxi != null && U.FlatDist(taxi.transform.position, pc.transform.position) > 9f; t += 0.5f) yield return new WaitForSeconds(0.5f);
            yield return new WaitForSeconds(1f);
            if (taxi != null)
            {
                // walk up to the passenger side and press G
                pc.Teleport(taxi.transform.position + taxi.transform.right * 2.2f + Vector3.up * 0.3f, taxi.transform.eulerAngles.y);
                yield return new WaitForSeconds(0.3f);
                GameInput.SimPress(Key.G);
                yield return new WaitForSeconds(2.5f);
            }
            bool riding = taxi != null && pc.actor.vehicle == taxi && pc.actor.seat > 0;
            int money0 = PlayerState.I.money;
            if (riding) TaxiService.SetDestination(WorldMarkers.Airport, "Halcyon Airfield");
            yield return new WaitForSeconds(3.5f);
            float toAirport = U.FlatDist(pc.transform.position, WorldMarkers.Airport);
            Check("world.taxi", taxi != null && riding && toAirport < 90f && PlayerState.I.money < money0, "taxi arrived (" + d.ToString("F0") + " m away when checked), rode as passenger=" + riding + ", now " + toAirport.ToString("F0") + " m from the airfield, fare " + (money0 - PlayerState.I.money));
            yield return Shot("taxi_arrived");
            GameInput.SimPress(Key.F);
            yield return new WaitForSeconds(1.5f);"""),
])

# new test coroutines appended before the last two closing braces
p = os.path.join(ROOT, "Core", "AutoTester.cs")
s = open(p, encoding="utf-8").read()
end = s.rstrip()
assert end.endswith("}")
cut = end.rstrip()[:-1].rstrip()          # drop namespace brace
assert cut.endswith("}")
cut = cut[:-1].rstrip()                   # drop class brace
extra = r'''

        IEnumerator CarjackTest()
        {
            pc.Teleport(WorldMarkers.Downtown + new Vector3(0f, 1f, -6f), 0f);
            yield return new WaitForSeconds(3f);
            Vehicle target = null; float best = 120f;
            foreach (var v in Vehicle.All)
            {
                if (v == null || v.IsDestroyed || v.kind != VehicleKind.Car || v.Driver == null || v.Driver.IsPlayer || v.GetComponent<VehicleAI>() == null || (v.def != null && v.def.police)) continue;
                float d = Vector3.Distance(v.transform.position, pc.transform.position);
                if (d < best) { best = d; target = v; }
            }
            if (target == null) { Check("vehicle.carjack", false, "no NPC-driven car nearby"); yield break; }
            var ai = target.GetComponent<VehicleAI>(); ai.enabled = false;                 // the car waits, like at a red light
            target.input = new VehicleInput { brake = 1f, handbrake = 1f };
            yield return new WaitForSeconds(1.5f);
            var victim = target.Driver;
            var door = target.seats[0].door != null ? target.seats[0].door.position : target.transform.position;
            var stand = door + (door - target.transform.position).normalized * 1.3f; stand.y = Ground(stand) + 0.05f;
            pc.Teleport(stand, Quaternion.LookRotation(U.Flat(target.transform.position - stand).normalized).eulerAngles.y);
            yield return new WaitForSeconds(0.3f);
            GameInput.SimPress(Key.F);
            for (float t = 0; t < 4f && pc.actor.vehicle != target; t += Time.deltaTime) yield return null;
            yield return new WaitForSeconds(0.5f);
            yield return Shot("carjack", target.transform.position + target.transform.right * 6f + Vector3.up * 3f, target.transform.position);
            Check("vehicle.carjack", pc.actor.vehicle == target && pc.actor.seat == 0 && victim != null && victim.vehicle != target,
                "player took the driver seat=" + (pc.actor.vehicle == target) + ", previous driver out=" + (victim != null && victim.vehicle != target) + ", wanted=" + WantedSystem.Level);
            GameInput.SimMove = new Vector2(0f, 1f);
            yield return new WaitForSeconds(1.5f);
            GameInput.SimMove = Vector2.zero;
            Check("vehicle.stolen_car_obeys_player", target.GetComponent<VehicleAI>() == null && target.SpeedKmh > 5f, "AI removed=" + (target.GetComponent<VehicleAI>() == null) + ", speed " + target.SpeedKmh.ToString("F0") + " km/h under player input");
            GameInput.SimHold(Key.Space, true);
            yield return new WaitForSeconds(2f);
            GameInput.SimHold(Key.Space, false);
            GameInput.SimPress(Key.F);
            yield return new WaitForSeconds(1.5f);
            WantedSystem.Clear();
        }

        IEnumerator ShopPurchaseTest()
        {
            var ps = PlayerState.I; var a = pc.actor;
            a.armor = 0f; int m0 = ps.money;
            ShopUI.Show("weapons");
            yield return new WaitForSecondsRealtime(0.4f);
            bool clicked = false;
            foreach (var b in ShopUI.I.GetComponentsInChildren<UnityEngine.UI.Button>(true))
            {
                var t = b.GetComponentInChildren<UnityEngine.UI.Text>(true);
                if (t != null && t.text.Trim() == "ARMOUR") { b.onClick.Invoke(); break; }
            }
            yield return new WaitForSecondsRealtime(0.3f);
            foreach (var b in ShopUI.I.GetComponentsInChildren<UnityEngine.UI.Button>(true))
            {
                var t = b.GetComponentInChildren<UnityEngine.UI.Text>(true);
                if (t != null && t.text.StartsWith("Heavy body armour")) { b.onClick.Invoke(); clicked = true; break; }
            }
            yield return new WaitForSecondsRealtime(0.3f);
            yield return Shot("ui_shop_armour");
            ShopUI.Close();
            Check("shops.purchase_ui", clicked && ps.money == m0 - 900 && a.armor >= a.maxArmor - 0.1f, "clicked the shop row: money " + m0 + " -> " + ps.money + ", armour " + a.armor.ToString("F0") + "/" + a.maxArmor.ToString("F0"));
        }

        IEnumerator BustedAndDeathTest()
        {
            // busted: 1 star, an officer walks up to a calm suspect
            var spot = OpenSpot(new Vector3(-40f, 2f, -190f), 3f);
            pc.Teleport(spot + Vector3.up * 0.2f, 0f);
            pc.weapons.Give("fists", 0, true);
            yield return new WaitForSeconds(0.5f);
            WantedSystem.SetLevelExternal(1);
            var cop = NPCFactory.Spawn(NPCFactory.Archetype.Police, pc.transform.position + pc.transform.forward * 1.2f, Quaternion.LookRotation(-pc.transform.forward));
            float t0 = Time.time; bool busted = false;
            while (Time.time - t0 < 8f) { if (WantedSystem.Busted) busted = true; if (busted && !WantedSystem.Busted) break; yield return null; }
            yield return new WaitForSeconds(0.5f);
            float toStation = U.FlatDist(pc.transform.position, WorldMarkers.PoliceStation);
            Check("police.busted", busted && WantedSystem.Level == 0 && toStation < 40f, "busted=" + busted + ", released " + toStation.ToString("F0") + " m from the police station, stars=" + WantedSystem.Level);
            yield return Shot("busted_release");
            if (cop != null) Destroy(cop.gameObject);
            // death: respawn at the hospital
            pc.actor.TakeDamage(DamageInfo.Make(5000f, DamageType.Fall, pc.transform.position, Vector3.down, null));
            yield return new WaitForSeconds(6f);
            float toHospital = U.FlatDist(pc.transform.position, WorldMarkers.Hospital);
            Check("player.death_respawn", !pc.actor.IsDead && toHospital < 40f && pc.actor.health > 0f, "respawned " + toHospital.ToString("F0") + " m from the hospital with hp " + pc.actor.health.ToString("F0"));
            yield return Shot("hospital_respawn");
        }
'''
s = cut + extra + "    }\n}\n"
open(p, "w", encoding="utf-8").write(s)
print("patched tests3")
