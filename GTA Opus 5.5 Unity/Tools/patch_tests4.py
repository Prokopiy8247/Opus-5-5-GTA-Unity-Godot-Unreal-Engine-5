"""One-off patch (segment 5, after run6): 'never wanted' switch, death logging and robust weapon/damage tests."""
import os
ROOT = os.path.join(os.path.dirname(__file__), "..", "Assets", "GTA", "Code")


def edit(rel, pairs):
    p = os.path.join(ROOT, rel)
    s = open(p, encoding="utf-8").read()
    for old, new in pairs:
        assert s.count(old) == 1, (rel, old[:90], s.count(old))
        s = s.replace(old, new)
    open(p, "w", encoding="utf-8").write(s)


edit("Police/WantedSystem.cs", [
("""        public static void Report(Vector3 pos, float severity, GameObject perp, bool byPolice)
        {
            if (I == null) return;""",
 """        /// <summary>Admin "never wanted" switch (also used by the autotest while it shoots at test targets).</summary>
        public static bool Suppressed;

        public static void Report(Vector3 pos, float severity, GameObject perp, bool byPolice)
        {
            if (I == null || Suppressed) return;"""),
])

edit("UI/Menus.cs", [
("""            menu.Row("Toggle invulnerability: " + (Invulnerable ? "ON" : "OFF"), () => { Invulnerable = !Invulnerable; PlayerController.I.actor.invulnerable = Invulnerable; menu.SelectTab(3); });""",
 """            menu.Row("Toggle invulnerability: " + (Invulnerable ? "ON" : "OFF"), () => { Invulnerable = !Invulnerable; PlayerController.I.actor.invulnerable = Invulnerable; menu.SelectTab(3); });
            menu.Row("Toggle never wanted: " + (WantedSystem.Suppressed ? "ON" : "OFF"), () => { WantedSystem.Suppressed = !WantedSystem.Suppressed; if (WantedSystem.Suppressed) WantedSystem.Clear(); menu.SelectTab(3); });"""),
])

edit("Core/AutoTester.cs", [
# log every player death with the running test
("""            pc = PlayerController.I;
            cam = PlayerCamera.I != null ? PlayerCamera.I.cam : Camera.main;""",
 """            pc = PlayerController.I;
            cam = PlayerCamera.I != null ? PlayerCamera.I.cam : Camera.main;
            if (pc != null) pc.actor.Died += (a, d) => Log("PLAYER DIED during " + current + " at " + a.transform.position.ToString("F0") + ": " + d.type + " " + d.amount.ToString("F0") + " by " + (d.attacker != null ? d.attacker.name : "-"));"""),
("""        void Clean()
        {
            GameInput.SimReset();""",
 """        void Clean()
        {
            GameInput.SimReset();
            WantedSystem.Suppressed = false;"""),
# weapons: no police while emptying every gun at the airfield; fire along a clear line; the target car must be intact first
("""            pc.Teleport(OpenSpot(new Vector3(-30f, 2f, RunwayZ), 2f) + Vector3.up * 0.2f, 90f);
            yield return new WaitForSeconds(0.6f);
            int okGuns = 0, guns = 0;""",
 """            WantedSystem.Clear(); WantedSystem.Suppressed = true;
            var spot = OpenSpot(new Vector3(-30f, 2f, RunwayZ), 4f);
            float yaw = ClearYaw(spot, 90f);
            pc.Teleport(spot + Vector3.up * 0.2f, yaw);
            Log("weapons test at " + spot.ToString("F0") + " yaw " + yaw.ToString("F0"));
            yield return new WaitForSeconds(0.6f);
            int okGuns = 0, guns = 0;"""),
("""            var car = VehicleFactory.Spawn(VehicleCatalog.Get("compact"), pc.transform.position + pc.transform.forward * 14f + Vector3.up, Quaternion.identity);
            yield return new WaitForSeconds(1f);
            float h0 = car != null ? car.health : 0f;""",
 """            var cp = pc.transform.position + pc.transform.forward * 14f; cp.y = Ground(cp) + 0.8f;
            var car = VehicleFactory.Spawn(VehicleCatalog.Get("compact"), cp, Quaternion.identity);
            yield return new WaitForSeconds(1f);
            float h0 = car != null && !car.IsDestroyed ? car.health : 0f;"""),
("""            Check("weapons.explosive_vs_vehicle", car == null || car.IsDestroyed || car.health < h0 * 0.7f, "car health " """,
 """            Check("weapons.explosive_vs_vehicle", h0 > 0f && (car == null || car.IsDestroyed || car.health < h0 * 0.7f), "car health " """),
("""            if (car != null) Destroy(car.gameObject);
            pc.weapons.Give("pistol", 120, true);
            WantedSystem.Clear();
        }""",
 """            if (car != null) Destroy(car.gameObject);
            pc.weapons.Give("pistol", 120, true);
            WantedSystem.Suppressed = false; WantedSystem.Clear();
        }

        /// <summary>A firing direction with 36 m of free space (no wall, vehicle or person) from the given spot.</summary>
        static float ClearYaw(Vector3 p, float preferred)
        {
            for (int k = 0; k < 8; k++)
            {
                float yaw = preferred + k * 45f;
                var dir = Quaternion.Euler(0f, yaw, 0f) * Vector3.forward;
                if (!Physics.SphereCast(p + Vector3.up * 1.4f, 0.6f, dir, out _, 36f, Layers.World | (1 << Layers.Vehicle) | (1 << Layers.NPC), QueryTriggerInteraction.Ignore)) return yaw;
            }
            return preferred;
        }"""),
# vehicle damage: the subject is the vehicle, keep the police out of the line of fire
("""            var p = new Vector3(20f, 2f, RunwayZ); p.y = Ground(p) + 0.7f;
            pc.Teleport(p + new Vector3(0f, 0f, -16f), 0f);""",
 """            var p = new Vector3(20f, 2f, RunwayZ); p.y = Ground(p) + 0.7f;
            WantedSystem.Clear(); WantedSystem.Suppressed = true;
            pc.Teleport(p + new Vector3(0f, 0f, -16f), 0f);"""),
("""            Check("vehicle.damage_explosion", v == null || v.IsDestroyed, "health after gunfire " + hp.ToString("F0") + "; destroyed=" + (v == null || v.IsDestroyed));
            WantedSystem.Clear();""",
 """            Check("vehicle.damage_explosion", v == null || v.IsDestroyed, "health after gunfire " + hp.ToString("F0") + "; destroyed=" + (v == null || v.IsDestroyed));
            WantedSystem.Suppressed = false; WantedSystem.Clear();"""),
])
print("patched tests4")
# follow-up (applied by hand after run7): the crime handler queues reports itself, so "never wanted" also gates
# WantedSystem.OnCrime (early return) and drops queued reports while Suppressed is on.
