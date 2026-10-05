"""One-off source patch (segment 5): garage store/retrieve without duplicates, E-to-store prompt, stealth sight range."""
import os
ROOT = os.path.join(os.path.dirname(__file__), "..", "Assets", "GTA", "Code")


def edit(rel, pairs):
    p = os.path.join(ROOT, rel)
    s = open(p, encoding="utf-8").read()
    for old, new in pairs:
        assert s.count(old) == 1, (rel, old[:90], s.count(old))
        s = s.replace(old, new)
    open(p, "w", encoding="utf-8").write(s)


edit("Vehicles/VehicleApi.cs", [
("""            ps.garage.Add(new StoredVehicle { id = v.def.id, mods = v.mods.ToJson() });
            HUD.Notify("Stored " + v.def.name, 1.8f);
            AudioFX.Play("cash", 0.4f);
        }""",
 """            ps.garage.Add(new StoredVehicle { id = v.def.id, mods = v.mods.ToJson() });
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
        }"""),
("""                v.engineOn = true;
                v.persistent = true;
                spawned++;
            }
            HUD.Notify(spawned + " vehicle(s) delivered to the garage", 2.4f);""",
 """                v.engineOn = true;
                v.persistent = true;
                ps.garage.Remove(st);   // it now exists in the world again
                spawned++;
            }
            HUD.Notify(spawned + " vehicle(s) delivered to the garage", 2.4f);"""),
])

edit("Player/PlayerController.cs", [
("""                if (GameInput.Down(Key.Period)) RadioSystem.Next(1);""",
 """                if (GameInput.InteractDown && GarageApi.NearGarage(v.transform.position) && v.kind != VehicleKind.Heli && v.kind != VehicleKind.Plane && v.kind != VehicleKind.Boat) { PlayerState.I.StoreCurrentVehicle(); return; }
                if (GameInput.Down(Key.Period)) RadioSystem.Next(1);"""),
])

edit("UI/HUD.cs", [
("""            if (pc.actor.InVehicle) return;   // on-foot prompts only""",
 """            if (pc.actor.InVehicle)
            {
                if (pc.actor.seat == 0 && GarageApi.NearGarage(pc.transform.position)) Prompt("[E] Store this vehicle in the garage");
                return;   // other prompts are on-foot only
            }"""),
])

edit("AI/NPCBrain.cs", [
("""            bool seePlayer = false;
            if (d < 60f)
            {
                float fov = officer ? 120f : 100f;""",
 """            bool seePlayer = false;
            // stealth (crouched, slow) shrinks how far and how wide NPCs notice the player
            float sightRange = pc.Stealth ? 22f : 60f;
            if (d < sightRange)
            {
                float fov = (officer ? 120f : 100f) * (pc.Stealth ? 0.7f : 1f);"""),
])
print("patched garage/stealth")
