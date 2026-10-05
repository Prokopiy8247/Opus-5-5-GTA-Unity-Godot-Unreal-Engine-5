using System.Collections;
using System.Collections.Generic;
using System.Text;
using UnityEngine;
using UnityEngine.InputSystem;

namespace Halcyon
{
    /// <summary>
    /// Command-line "-autotest" validation run for the built game. Drives the real gameplay code through simulated input
    /// (GameInput.Sim*), records PASS/FAIL checks with measured values and captures screenshots into QA_Screens/.
    /// It is a QA tool only: it never runs in normal play.
    /// </summary>
    public class AutoTester : MonoBehaviour
    {
        string dir;
        readonly StringBuilder log = new StringBuilder();
        int pass, fail;
        float fpsMin = 9999f, fpsSum; int fpsN; float warm;
        PlayerController pc;
        Camera cam;
        const float RunwayZ = -247f;

        string only;   // "-autotest:plane,boat" runs a subset
        string current = "boot"; int hitches;
        bool Want(string tag) { bool w = string.IsNullOrEmpty(only) || only.Contains(tag); if (w) current = tag; return w; }

        void Log(string s) { log.AppendLine(Time.realtimeSinceStartup.ToString("F1") + "s " + s); Debug.Log("[AutoTest] " + s); }
        void Check(string name, bool ok, string detail)
        {
            if (ok) pass++; else fail++;
            Log((ok ? "PASS " : "FAIL ") + name + " :: " + detail);
        }

        void Update()
        {
            warm += Time.unscaledDeltaTime;
            if (warm > 6f && Time.unscaledDeltaTime > 0.12f && hitches < 25) { hitches++; Log("hitch " + (Time.unscaledDeltaTime * 1000f).ToString("F0") + " ms during " + current); }
            if (warm > 6f && GameManager.Fps > 0f) { fpsMin = Mathf.Min(fpsMin, GameManager.Fps); fpsSum += GameManager.Fps; fpsN++; }
        }

        IEnumerator Shot(string name, Vector3? from = null, Vector3? at = null)
        {
            var pcam = PlayerCamera.I;
            bool manual = from.HasValue && at.HasValue && pcam != null;
            if (manual)
            {
                pcam.enabled = false;
                cam.transform.position = from.Value;
                cam.transform.rotation = Quaternion.LookRotation(at.Value - from.Value);
            }
            yield return null;
            yield return null;
            ScreenCapture.CaptureScreenshot(System.IO.Path.Combine(dir, name + ".png"));
            yield return new WaitForEndOfFrame();
            yield return null;
            if (manual) pcam.enabled = true;
        }

        static float Ground(Vector3 p) => U.GroundHeight(p + Vector3.up * 40f, p.y);

        /// <summary>Flat, unobstructed spot near 'near' (for spawning test vehicles).</summary>
        static Vector3 OpenSpot(Vector3 near, float clearance = 4f)
        {
            for (int i = 0; i < 80; i++)
            {
                float a = i * 2.4f, r = i * 2.2f;
                var p = near + new Vector3(Mathf.Cos(a) * r, 0f, Mathf.Sin(a) * r);
                if (!Physics.Raycast(p + Vector3.up * 60f, Vector3.down, out var h, 120f, Layers.World, QueryTriggerInteraction.Ignore)) continue;
                if (h.normal.y < 0.97f || h.point.y < 0.3f) continue;
                if (Physics.CheckBox(h.point + Vector3.up * 2.2f, new Vector3(clearance, 2f, clearance), Quaternion.identity, Layers.World | (1 << Layers.Vehicle) | (1 << Layers.NPC), QueryTriggerInteraction.Ignore)) continue;
                return h.point;
            }
            return near;
        }

        static Vector3 WaterSpot(Vector3 start)
        {
            var p = start;
            for (int i = 0; i < 80; i++)
            {
                p += Vector3.left * 4f;
                if (Ground(new Vector3(p.x, 5f, p.z)) < -2.5f) return new Vector3(p.x, 0.2f, p.z);
            }
            return new Vector3(start.x - 60f, 0.2f, start.z);
        }

        void Clean()
        {
            GameInput.SimReset();
            WantedSystem.Suppressed = false;
            if (pc != null && pc.actor.InVehicle) { var v = pc.actor.vehicle; v.Vacate(pc.actor); }
        }

        IEnumerator Start()
        {
            foreach (var arg in System.Environment.GetCommandLineArgs()) if (arg.StartsWith("-autotest:")) only = arg.Substring(10);
            dir = System.IO.Path.Combine(Application.dataPath, "..", "QA_Screens");
            System.IO.Directory.CreateDirectory(dir);
            AdminMenu.Invulnerable = false;
            yield return new WaitForSeconds(3f);
            pc = PlayerController.I;
            cam = PlayerCamera.I != null ? PlayerCamera.I.cam : Camera.main;
            if (pc != null) pc.actor.Died += (a, d) => Log("PLAYER DIED during " + current + " at " + a.transform.position.ToString("F0") + ": " + d.type + " " + d.amount.ToString("F0") + " by " + (d.attacker != null ? d.attacker.name : "-"));
            Check("boot.player", pc != null && pc.cc.isGrounded, "spawn " + (pc != null ? pc.transform.position.ToString() : "null"));
            Check("boot.database", GameDatabase.I != null && GameDatabase.I.entries.Count > 100, "prefabs=" + (GameDatabase.I != null ? GameDatabase.I.entries.Count : 0));
            Check("boot.no_missions", FindAnyObjectByType<GameBootstrap>() != null, "free roam start (no mission system exists in code)");
            yield return Shot("00_spawn");
            int blocked = 0, total = 0; var names = new List<string>();
            foreach (var it in Interactable.All) { if (it == null) continue; total++; if (Interactable.Blocked(it.transform.position, it.transform)) { blocked++; names.Add(it.id); } }
            Check("world.interactables_reachable", blocked == 0, (total - blocked) + "/" + total + " interaction points reachable" + (blocked > 0 ? " blocked: " + string.Join(",", names) : ""));

            if (Want("districts")) yield return Districts();
            if (Want("gallery")) yield return VehicleGallery();
            if (Want("walk")) yield return WalkTest();
            if (Want("drive")) yield return DriveTest("sedan", 6f, 25f);
            if (Want("drive")) yield return DriveTest("motorbike", 6f, 25f);
            if (Want("drive")) yield return DriveTest("bicycle", 6f, 10f);
            if (Want("traffic")) yield return TrafficTest();
            if (Want("carjack")) yield return CarjackTest();
            if (Want("peds")) yield return PedestrianTest();
            if (Want("weapons")) yield return WeaponsTest();
            if (Want("cover")) yield return CoverStealthMelee();
            if (Want("driveby")) yield return DriveByTest();
            if (Want("police")) yield return WantedPoliceTest();
            if (Want("heli")) yield return HeliTest();
            if (Want("plane")) yield return PlaneTest();
            if (Want("boat")) yield return BoatTest();
            if (Want("swim")) yield return SwimDiveTest();
            if (Want("parachute")) yield return ParachuteTest();
            if (Want("shops")) yield return ShopsModsSave();
            if (Want("shops")) yield return ShopPurchaseTest();
            if (Want("taxi")) yield return TaxiWildlife();
            if (Want("damage")) yield return VehicleDamageTest();
            if (Want("busted")) yield return BustedAndDeathTest();
            if (Want("ui")) yield return UiScreens();
            if (Want("time")) yield return DayNightWeather();

            Log(string.Format("SUMMARY pass={0} fail={1} fps_avg={2:F0} fps_min={3:F0}", pass, fail, fpsN > 0 ? fpsSum / fpsN : 0f, fpsMin));
            System.IO.File.WriteAllText(System.IO.Path.Combine(dir, "autotest_log.txt"), log.ToString());
            yield return new WaitForSeconds(1f);
            Application.Quit();
        }

        // ---------------------------------------------------------------------------------------------------------
        IEnumerator Districts()
        {
            int i = 1;
            foreach (var (name, pos) in WorldMarkers.Landmarks)
            {
                var p = pos + new Vector3(0f, 1.5f, 10f);
                p.y = Ground(p) + 0.3f;
                pc.Teleport(p, 30f * i);
                yield return new WaitForSeconds(2.4f);
                Log("district " + name + " pos=" + pc.transform.position + " fps=" + GameManager.Fps.ToString("F0") + " vehicles=" + Vehicle.All.Count + " actors=" + Actor.All.Count);
                yield return Shot((i < 10 ? "0" : "") + i + "_" + name.Replace(" ", "_"));
                i++;
            }
            Check("world.districts", WorldMarkers.Landmarks.Count >= 8, WorldMarkers.Landmarks.Count + " landmarks visited");
        }

        IEnumerator VehicleGallery()
        {
            var basePos = new Vector3(-120f, 2f, RunwayZ);
            pc.Teleport(new Vector3(-120f, Ground(basePos) + 0.3f, RunwayZ - 22f), 0f);
            yield return new WaitForSeconds(1f);
            int ok = 0, total = 0;
            foreach (var def in VehicleCatalog.Available())
            {
                total++;
                bool water = def.kind == VehicleKind.Boat;
                Vector3 p = water ? WaterSpot(WorldMarkers.Docks + new Vector3(0f, 0f, 30f)) : OpenSpot(basePos, 5f) + Vector3.up * 0.6f;
                if (water) pc.Teleport(new Vector3(p.x + 25f, Ground(new Vector3(p.x + 25f, 5f, p.z)) + 0.3f, p.z), 270f);
                var v = VehicleFactory.Spawn(def, p, Quaternion.Euler(0f, 90f, 0f));
                yield return new WaitForSeconds(1.0f);
                if (v != null)
                {
                    ok++;
                    float s = Mathf.Max(1f, v.bounds.size.magnitude / 5.5f);
                    var from = v.transform.TransformPoint(new Vector3(3.6f, 1.9f, 5.2f) * s);
                    yield return Shot("veh_" + def.id, from, v.transform.position + Vector3.up * v.bounds.size.y * 0.45f);
                    Log("vehicle " + def.id + " size=" + v.bounds.size.ToString("F1") + " seats=" + v.seats.Length);
                    Destroy(v.gameObject);
                }
                else Log("vehicle " + def.id + " FAILED to spawn");
                yield return null;
            }
            Check("vehicles.spawn_all", ok == total && total > 0, ok + "/" + total + " vehicle types spawned from Blender prefabs");
        }

        IEnumerator WalkTest()
        {
            var p = OpenSpot(new Vector3(-60f, 2f, RunwayZ), 3f);
            pc.Teleport(p + Vector3.up * 0.2f, 90f);
            yield return new WaitForSeconds(0.5f);
            var a = pc.transform.position;
            GameInput.SimMove = new Vector2(0f, 1f);
            yield return new WaitForSeconds(2f);
            float walk = U.FlatDist(a, pc.transform.position);
            GameInput.SimHold(Key.LeftShift, true);
            a = pc.transform.position;
            yield return new WaitForSeconds(2f);
            float sprint = U.FlatDist(a, pc.transform.position);
            GameInput.SimReset();
            GameInput.SimPress(Key.Space);
            float y0 = pc.transform.position.y, ymax = y0;
            for (float t = 0; t < 0.8f; t += Time.deltaTime) { ymax = Mathf.Max(ymax, pc.transform.position.y); yield return null; }
            Check("player.walk_sprint_jump", walk > 3f && sprint > walk * 1.2f && ymax - y0 > 0.4f, string.Format("walk {0:F1} m/2s, sprint {1:F1} m/2s, jump {2:F2} m", walk, sprint, ymax - y0));
            GameInput.SimPress(Key.V); yield return new WaitForSeconds(0.4f);
            yield return Shot("cam_view2");
            GameInput.SimPress(Key.V); yield return new WaitForSeconds(0.3f);
            GameInput.SimPress(Key.V); yield return new WaitForSeconds(0.3f);
        }

        IEnumerator DriveTest(string id, float seconds, float minDist)
        {
            var def = VehicleCatalog.Get(id);
            var p = new Vector3(-140f, 2f, RunwayZ + (id == "sedan" ? -7f : 7f));   // a showcase plane is parked at x=-170
            p.y = Ground(p) + 0.7f;
            pc.Teleport(p + new Vector3(0f, 0f, -3.2f), 0f);
            var v = VehicleFactory.Spawn(def, p, Quaternion.Euler(0f, 90f, 0f));
            yield return new WaitForSeconds(1.2f);
            if (v == null) { Check("drive." + id, false, "spawn failed"); yield break; }
            GameInput.SimPress(Key.F);
            for (float t = 0; t < 3f && !pc.actor.InVehicle; t += Time.deltaTime) yield return null;
            yield return new WaitForSeconds(0.6f);
            Check("vehicle.enter." + id, pc.actor.InVehicle && pc.actor.vehicle == v, "player seat=" + pc.actor.seat);
            var start = v.transform.position;
            float vmax = 0f;
            GameInput.SimMove = new Vector2(0f, 1f);
            for (float t = 0; t < seconds; t += Time.deltaTime) { vmax = Mathf.Max(vmax, v.SpeedKmh); yield return null; }
            float dist = U.FlatDist(start, v.transform.position);
            var cv = v as CarVehicle;
            Log("drive diag " + id + ": engineOn=" + v.engineOn + " kinematic=" + v.Rb.isKinematic + " mass=" + v.Rb.mass + " driver=" + (v.Driver != null) + " " + (cv != null ? cv.Diag() : ""));
            yield return Shot("drive_" + id);
            Check("drive." + id, dist > minDist && vmax > (id == "bicycle" ? 10f : 20f), string.Format("moved {0:F1} m in {1:F0} s, top {2:F0} km/h", dist, seconds, vmax));
            // steering + brake
            GameInput.SimMove = new Vector2(1f, 1f);
            float yaw0 = v.transform.eulerAngles.y;
            yield return new WaitForSeconds(1.2f);
            float turned = Mathf.Abs(Mathf.DeltaAngle(yaw0, v.transform.eulerAngles.y));
            GameInput.SimMove = new Vector2(0f, -1f);
            yield return new WaitForSeconds(2.5f);
            Check("drive.steer_brake." + id, turned > 8f && v.SpeedKmh < vmax * 0.6f, string.Format("turned {0:F0} deg, speed after brake {1:F0} km/h", turned, v.SpeedKmh));
            GameInput.SimMove = Vector2.zero;
            GameInput.SimHold(Key.Space, true);
            for (float t = 0; t < 6f && v.SpeedKmh > 3f; t += Time.deltaTime) yield return null;
            GameInput.SimHold(Key.Space, false);
            yield return new WaitForSeconds(0.5f);
            GameInput.SimPress(Key.F);
            yield return new WaitForSeconds(1.6f);
            Check("vehicle.exit." + id, !pc.actor.InVehicle && pc.cc.enabled, "on foot at " + pc.transform.position + " state=" + pc.state + " cc=" + pc.cc.enabled);
            GameInput.SimReset();
            Destroy(v.gameObject);
        }

        IEnumerator TrafficTest()
        {
            pc.Teleport(WorldMarkers.Downtown + Vector3.up, 0f);
            yield return new WaitForSeconds(4f);
            // after a teleport the traffic manager adds roughly one car every 0.5 s: let the area fill up first
            for (float w = 0f; w < 20f; w += 1f)
            {
                int ai = 0;
                foreach (var v in Vehicle.All) if (v != null && v.GetComponent<VehicleAI>() != null && v.Driver != null && !v.Driver.IsPlayer) ai++;
                if (ai >= 10) break;
                yield return new WaitForSeconds(1f);
            }
            var cars = new List<Vehicle>(); var p0 = new List<Vector3>();
            foreach (var v in Vehicle.All) if (v != null && v.GetComponent<VehicleAI>() != null && v.Driver != null && !v.Driver.IsPlayer) { cars.Add(v); p0.Add(v.transform.position); }
            yield return new WaitForSeconds(5f);
            int moving = 0;
            for (int i = 0; i < cars.Count; i++) if (cars[i] != null && Vector3.Distance(p0[i], cars[i].transform.position) > 6f) moving++;
            int lights = FindObjectsByType<TrafficLightProp>(FindObjectsSortMode.None).Length;
            Check("traffic.moving", cars.Count >= 8 && moving >= cars.Count / 3, moving + "/" + cars.Count + " AI cars moved >6 m in 5 s; traffic-light props=" + lights);
            yield return Shot("traffic_downtown", pc.transform.position + new Vector3(-14f, 9f, -14f), pc.transform.position + new Vector3(0f, 0f, 10f));
            // over a full signal cycle no civilian car should end up on the pavement or stay stuck
            var watch = new List<Vehicle>(); var w0 = new List<Vector3>();
            foreach (var v in Vehicle.All) if (v != null && !v.IsDestroyed && v.GetComponent<VehicleAI>() != null && v.Driver != null && !v.Driver.IsPlayer && (v.def == null || !v.def.police)) { watch.Add(v); w0.Add(v.transform.position); }
            yield return new WaitForSeconds(28f);
            int offroad = 0, stuck = 0, alive = 0; var net = RoadNetwork.I;
            for (int i = 0; i < watch.Count; i++)
            {
                var v = watch[i];
                if (v == null || v.IsDestroyed || !v.gameObject.activeInHierarchy || v.GetComponent<VehicleAI>() == null) continue;
                alive++;
                if (Vector3.Distance(w0[i], v.transform.position) < 1.5f) { stuck++; Log("traffic: car stayed put at " + v.transform.position.ToString("F0") + " speed " + v.SpeedKmh.ToString("F0") + " km/h"); }
                if (net != null && net.NearestLane(v.transform.position, out int li, out _, out Vector3 lp) && U.FlatDist(lp, v.transform.position) > net.lanes[li].halfWidth + 0.9f)
                { offroad++; Log("traffic: car off the road at " + v.transform.position.ToString("F0") + ", " + U.FlatDist(lp, v.transform.position).ToString("F1") + " m from the nearest lane centre"); }
            }
            Check("traffic.stays_on_road", alive >= 6 && offroad <= 1 && stuck <= 1, alive + " civilian AI cars watched for 28 s: off the road=" + offroad + ", never moved=" + stuck);
        }

        IEnumerator PedestrianTest()
        {
            pc.Teleport(WorldMarkers.Downtown + new Vector3(4f, 1f, 4f), 0f);
            yield return new WaitForSeconds(9f);
            int near = 0, walking = 0;
            foreach (var b in NPCBrain.All) if (b != null && b.vehicle == null && Vector3.Distance(b.transform.position, pc.transform.position) < 60f) { near++; if (b.state == NPCState.Walk || b.state == NPCState.Idle || b.state == NPCState.Chat || b.state == NPCState.Sit) walking++; }
            pc.weapons.Give("pistol", 120, true);
            yield return new WaitForSeconds(0.3f);
            for (int i = 0; i < 4; i++) { pc.weapons.Fire(pc.transform.position + Vector3.up * 30f + pc.transform.forward * 5f, 1f, true); yield return new WaitForSeconds(0.25f); }
            yield return new WaitForSeconds(2.5f);
            int fleeing = 0, nearAfter = 0;
            foreach (var b in NPCBrain.All) if (b != null && b.vehicle == null && Vector3.Distance(b.transform.position, pc.transform.position) < 60f) { nearAfter++; if (b.state == NPCState.Flee || b.state == NPCState.Panic || b.state == NPCState.Cover || b.state == NPCState.Combat) fleeing++; }
            Check("peds.population", near >= 6, near + " pedestrians within 60 m (" + walking + " ambient)");
            Check("peds.react_gunfire", fleeing >= Mathf.Max(2, nearAfter / 3), fleeing + "/" + nearAfter + " reacted (flee/panic/cover/combat) to gunfire; wanted=" + WantedSystem.Level);
            yield return Shot("peds_panic");
            WantedSystem.Clear();
        }

        IEnumerator WeaponsTest()
        {
            WantedSystem.Clear(); WantedSystem.Suppressed = true;
            var spot = OpenSpot(new Vector3(-30f, 2f, RunwayZ), 4f);
            float yaw = ClearYaw(spot, 90f);
            pc.Teleport(spot + Vector3.up * 0.2f, yaw);
            Log("weapons test at " + spot.ToString("F0") + " yaw " + yaw.ToString("F0"));
            yield return new WaitForSeconds(0.6f);
            int okGuns = 0, guns = 0;
            foreach (var w in WeaponCatalog.All)
            {
                pc.weapons.Give(w.id, 200, true);
                yield return new WaitForSeconds(1.7f);
                if (w.IsGun)
                {
                    guns++;
                    int c0 = pc.weapons.Clip;
                    bool fired = pc.weapons.Fire(pc.transform.position + pc.transform.forward * 30f + Vector3.up, 1f, true);
                    yield return new WaitForSeconds(0.35f);
                    if (fired && (pc.weapons.Clip < c0 || pc.weapons.infiniteAmmo)) okGuns++;
                    else Log("weapon " + w.id + " fire=" + fired + " clip " + c0 + "->" + pc.weapons.Clip);
                }
            }
            Check("weapons.fire_all", okGuns == guns && guns >= 10, okGuns + "/" + guns + " ranged weapons fired and consumed ammo; catalog=" + WeaponCatalog.All.Count);
            // reload
            pc.weapons.Give("rifle", 200, true);
            yield return new WaitForSeconds(0.3f);
            for (int i = 0; i < 6; i++) { pc.weapons.Fire(pc.transform.position + pc.transform.forward * 30f, 1f, true); yield return new WaitForSeconds(0.12f); }
            int before = pc.weapons.Clip;
            GameInput.SimPress(Key.R);
            yield return new WaitForSeconds(3f);
            Check("weapons.reload", pc.weapons.Clip > before, "clip " + before + " -> " + pc.weapons.Clip);
            // explosive vs parked car
            var cp = pc.transform.position + pc.transform.forward * 14f; cp.y = Ground(cp) + 0.8f;
            var car = VehicleFactory.Spawn(VehicleCatalog.Get("compact"), cp, Quaternion.identity);
            yield return new WaitForSeconds(1f);
            float h0 = car != null && !car.IsDestroyed ? car.health : 0f;
            pc.weapons.Give("rpg", 4, true);
            yield return new WaitForSeconds(1.7f);
            if (pc.weapons.Clip == 0) { pc.weapons.Reload(); yield return new WaitForSeconds(3.5f); }
            bool rocket = car != null && pc.weapons.Fire(car.transform.position + Vector3.up * 0.6f, 0.2f, true);
            Log("rpg fired=" + rocket + " carDist=" + (car != null ? Vector3.Distance(car.transform.position, pc.transform.position).ToString("F1") : "-"));
            yield return new WaitForSeconds(0.25f);
            yield return Shot("explosion", pc.transform.position - pc.transform.forward * 4f + Vector3.up * 3f, pc.transform.position + pc.transform.forward * 14f);
            yield return new WaitForSeconds(1.2f);
            Check("weapons.explosive_vs_vehicle", h0 > 0f && (car == null || car.IsDestroyed || car.health < h0 * 0.7f), "car health " + h0.ToString("F0") + " -> " + (car != null ? car.health.ToString("F0") : "gone") + " destroyed=" + (car == null || car.IsDestroyed));
            yield return Shot("weapons");
            if (car != null) Destroy(car.gameObject);
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
        }

        IEnumerator CoverStealthMelee()
        {
            // cover against a building wall downtown
            var p = WorldMarkers.Downtown + new Vector3(0f, 1f, 0f);
            Vector3 wallHit = Vector3.zero; bool found = false;
            for (int i = 0; i < 36 && !found; i++)
            {
                var dirv = Quaternion.Euler(0f, i * 10f, 0f) * Vector3.forward;
                if (Physics.Raycast(p + Vector3.up, dirv, out var h, 45f, Layers.World, QueryTriggerInteraction.Ignore) && Mathf.Abs(h.normal.y) < 0.2f && h.collider.bounds.size.y > 3f)
                { wallHit = h.point + h.normal * 0.9f; wallHit.y = Ground(wallHit) + 0.1f; pc.Teleport(wallHit, Quaternion.LookRotation(-h.normal).eulerAngles.y); found = true; }
            }
            yield return new WaitForSeconds(0.6f);
            GameInput.SimPress(Key.Q);
            yield return new WaitForSeconds(0.8f);
            bool cover = pc.state == MoveState.Cover;
            yield return Shot("cover", pc.transform.position + pc.transform.right * 3f + Vector3.up * 2f - pc.transform.forward * 3f, pc.transform.position + Vector3.up);
            Check("player.cover", cover, "state=" + pc.state + " wallFound=" + found);
            GameInput.SimPress(Key.Q);
            yield return new WaitForSeconds(0.6f);
            GameInput.SimPress(Key.C);
            yield return new WaitForSeconds(0.5f);
            Check("player.stealth_crouch", pc.Stealth, "crouching=" + pc.Crouching + " noise=" + pc.NoiseLevel.ToString("F2"));
            GameInput.SimPress(Key.C);
            yield return new WaitForSeconds(0.3f);
            // melee on a spawned civilian
            pc.weapons.Give("bat", 0, true);
            var npc = NPCFactory.Spawn(NPCFactory.Archetype.Civilian, pc.transform.position + pc.transform.forward * 1.3f, Quaternion.LookRotation(-pc.transform.forward));
            yield return new WaitForSeconds(0.4f);
            float h0 = npc != null ? npc.health : 0f;
            for (int i = 0; i < 3 && npc != null; i++)
            {
                // step up behind the target (it may walk away), then swing where the camera looks
                var np = npc.transform.position - npc.transform.forward * 1.1f;
                pc.Teleport(new Vector3(np.x, Ground(np) + 0.05f, np.z), npc.transform.eulerAngles.y);
                yield return null;
                var toN = U.Flat(npc.transform.position - pc.transform.position).normalized;
                if (PlayerCamera.I != null) PlayerCamera.I.yaw = Quaternion.LookRotation(toN).eulerAngles.y;
                pc.transform.rotation = Quaternion.LookRotation(toN);
                GameInput.SimFirePress();
                yield return new WaitForSeconds(0.8f);
                Log("melee swing " + i + ": npc dist=" + Vector3.Distance(npc.transform.position, pc.transform.position).ToString("F1") + " hp=" + npc.health.ToString("F0") + " weapon=" + pc.weapons.currentId + " state=" + pc.state);
            }
            Check("combat.melee", npc != null && npc.health < h0, "npc health " + h0.ToString("F0") + " -> " + (npc != null ? npc.health.ToString("F0") : "-"));
            Log("wanted after melee=" + WantedSystem.Level);
            WantedSystem.Clear();
            pc.weapons.Give("smg", 200, true);
        }

        IEnumerator DriveByTest()
        {
            var p = new Vector3(-100f, 2f, RunwayZ); p.y = Ground(p) + 0.7f;
            var v = VehicleFactory.Spawn(VehicleCatalog.Get("sedan"), p, Quaternion.Euler(0f, 90f, 0f));
            yield return new WaitForSeconds(1f);
            pc.PutInVehicle(v, 0);
            pc.weapons.Give("smg", 200, true);
            yield return new WaitForSeconds(0.5f);
            int c0 = pc.weapons.Clip;
            GameInput.SimAim = true; GameInput.SimFire = true; GameInput.SimMove = new Vector2(0f, 0.6f);
            yield return new WaitForSeconds(1.2f);
            yield return Shot("driveby");
            GameInput.SimReset();
            int used = c0 - pc.weapons.Clip;
            Check("vehicle.driveby", used > 2, "SMG rounds fired while driving: " + used + " (aim=" + pc.DriveByAiming + ")");
            pc.ForceExitVehicleNow();
            yield return new WaitForSeconds(1.2f);
            if (v != null) Destroy(v.gameObject);
            WantedSystem.Clear();
        }

        IEnumerator WantedPoliceTest()
        {
            WantedSystem.Clear();
            pc.Teleport(WorldMarkers.Downtown + new Vector3(-6f, 1f, 6f), 90f);
            yield return new WaitForSeconds(2f);
            // real crime: shoot a pedestrian in front of witnesses
            int witnesses = 0;
            foreach (var a in Actor.All) if (a != null && !a.IsPlayer && !a.IsDead && a.faction != Faction.Animal && Vector3.Distance(a.transform.position, pc.transform.position) < 40f) witnesses++;
            var victim = NPCFactory.Spawn(NPCFactory.Archetype.Civilian, pc.transform.position + pc.transform.forward * 5f, Quaternion.LookRotation(-pc.transform.forward));
            if (PlayerCamera.I != null) PlayerCamera.I.yaw = pc.transform.eulerAngles.y;
            Log("wanted test: people within 40 m = " + witnesses);
            pc.weapons.Give("pistol", 120, true);
            yield return new WaitForSeconds(0.3f);
            for (int i = 0; i < 10 && victim != null && !victim.IsDead; i++) { pc.weapons.Fire(victim.Center, 0.05f, true); yield return new WaitForSeconds(0.35f); }
            yield return new WaitForSeconds(3f);
            int lvlCrime = WantedSystem.Level;
            Check("wanted.crime_raises_level", lvlCrime >= 1, "after shooting a civilian: stars=" + lvlCrime + " victimDead=" + (victim != null && victim.IsDead));
            WantedSystem.SetLevelExternal(3);
            int maxCars = 0, maxCops = 0; bool heli = false, roadblockOrTactical = false;
            for (float t = 0; t < 26f; t += 1f)
            {
                int cars = 0, cops = 0;
                foreach (var v in Vehicle.All) if (v != null && v.def != null && v.def.police && !v.IsDestroyed) { if (v.kind == VehicleKind.Heli) heli = true; else cars++; if (v.def.id == "swat") roadblockOrTactical = true; }
                foreach (var a in Actor.All) if (a != null && !a.IsDead && a.faction == Faction.Police) cops++;
                maxCars = Mathf.Max(maxCars, cars); maxCops = Mathf.Max(maxCops, cops);
                if (t == 14f) yield return Shot("police_response");
                yield return new WaitForSeconds(1f);
            }
            Check("police.dispatch", maxCars >= 2 && maxCops >= 2, "max police cars=" + maxCars + " officers=" + maxCops + " heli=" + heli + " at 3 stars (" + WantedSystem.Level + " now)");
            Check("police.helicopter", heli, "police helicopter spawned at 3+ stars");
            Log("police: pursuing=" + WantedSystem.Pursuing + " search=" + WantedSystem.SearchProgress.ToString("F2") + " lastKnown=" + WantedSystem.LastKnownPos);
            yield return Shot("police_close", pc.transform.position + new Vector3(10f, 14f, -10f), pc.transform.position);
            // escape: break line of sight far away and hide until the search times out
            WantedSystem.SetLevelExternal(1);
            var hide = new Vector3(-150f, 2f, 270f); hide.y = Ground(hide) + 0.3f;
            pc.Teleport(hide, 0f);
            GameInput.SimPress(Key.C);
            float t0 = Time.time;
            while (WantedSystem.Level > 0 && Time.time - t0 < 75f) yield return new WaitForSeconds(1f);
            Check("wanted.escape_by_search_timeout", WantedSystem.Level == 0, "1 star lost after hiding out of sight for " + (Time.time - t0).ToString("F0") + " s");
            GameInput.SimPress(Key.C);
            WantedSystem.Clear();
            yield return new WaitForSeconds(1f);
        }

        IEnumerator HeliTest()
        {
            var p = OpenSpot(new Vector3(60f, 2f, RunwayZ + 40f), 7f) + Vector3.up * 0.8f;
            var v = VehicleFactory.Spawn(VehicleCatalog.Get("heli"), p, Quaternion.Euler(0f, 90f, 0f));
            yield return new WaitForSeconds(1.2f);
            if (v == null) { Check("air.heli", false, "spawn failed"); yield break; }
            pc.PutInVehicle(v, 0);
            yield return new WaitForSeconds(0.5f);
            float y0 = v.transform.position.y;
            GameInput.SimHold(Key.Space, true);
            yield return new WaitForSeconds(6f);
            GameInput.SimHold(Key.Space, false);
            float climb = v.transform.position.y - y0;
            GameInput.SimMove = new Vector2(0f, 1f);
            var h0 = v.transform.position;
            yield return new WaitForSeconds(3f);
            GameInput.SimMove = Vector2.zero;
            yield return Shot("heli_flight", v.transform.position - v.transform.forward * 16f + Vector3.up * 5f, v.transform.position);
            float fwd = U.FlatDist(h0, v.transform.position);
            Check("air.heli", climb > 8f && fwd > 8f, string.Format("climbed {0:F1} m in 6 s, flew {1:F1} m forward in 3 s", climb, fwd));
            pc.ForceExitVehicleNow();
            yield return new WaitForSeconds(0.4f);
            pc.Teleport(OpenSpot(new Vector3(0f, 2f, RunwayZ + 30f), 2f) + Vector3.up * 0.2f, 0f);
            Destroy(v.gameObject);
            GameInput.SimReset();
        }

        IEnumerator PlaneTest()
        {
            var p = new Vector3(-125f, 2f, RunwayZ); p.y = Ground(p) + 1.2f;
            var v = VehicleFactory.Spawn(VehicleCatalog.Get("plane"), p, Quaternion.Euler(0f, 90f, 0f));
            yield return new WaitForSeconds(1.2f);
            if (v == null) { Check("air.plane", false, "spawn failed"); yield break; }
            pc.PutInVehicle(v, 0);
            yield return new WaitForSeconds(0.5f);
            var vb = v.bounds; var cols = v.GetComponentsInChildren<Collider>(); var cb = cols.Length > 0 ? cols[0].bounds : new Bounds();
            foreach (var c in cols) if (!(c is WheelCollider) && c.enabled && !c.isTrigger && c.attachedRigidbody == v.Rb) cb.Encapsulate(c.bounds);
            float gy = Ground(v.transform.position + Vector3.up * 3f);
            Log("plane geometry: pivotY=" + v.transform.position.y.ToString("F2") + " boundsMinY(local)=" + vb.min.y.ToString("F2") + " collidersMinY(world)=" + cb.min.y.ToString("F2") + " groundY=" + gy.ToString("F2") + " colliders=" + cols.Length);
            Log("plane boarded: state=" + pc.state + " inVehicle=" + pc.actor.InVehicle + " seat=" + pc.actor.seat + " parent=" + (pc.transform.parent != null ? pc.transform.parent.name : "none"));
            float y0 = v.transform.position.y, vmax = 0f, ymax = y0;
            GameInput.SimHold(Key.Space, true);
            for (float t = 0; t < 9f; t += Time.deltaTime) { vmax = Mathf.Max(vmax, v.SpeedKmh); yield return null; }
            var pv = v as PlaneVehicle;
            Log("plane diag: destroyed=" + v.IsDestroyed + " hp=" + v.health.ToString("F0") + " engine=" + v.engineOn + " driver=" + (v.Driver != null) + " kinematic=" + v.Rb.isKinematic
                + " vel=" + v.Rb.linearVelocity.ToString("F1") + " lever=" + (pv != null ? pv.ThrottleLever.ToString("F2") : "-") + " lift=" + v.input.lift.ToString("F1") + " pos=" + v.transform.position.ToString("F1") + " state=" + pc.state);
            GameInput.SimMove = new Vector2(0f, -0.8f);           // pull up
            for (float t = 0; t < 4f; t += Time.deltaTime) { vmax = Mathf.Max(vmax, v.SpeedKmh); ymax = Mathf.Max(ymax, v.transform.position.y); yield return null; }
            GameInput.SimMove = Vector2.zero;
            for (float t = 0; t < 3f; t += Time.deltaTime) { ymax = Mathf.Max(ymax, v.transform.position.y); yield return null; }
            yield return Shot("plane_flight", v.transform.position - v.transform.forward * 18f + Vector3.up * 4f, v.transform.position);
            Check("air.plane", vmax > 90f && ymax - y0 > 10f, string.Format("top {0:F0} km/h, climbed {1:F1} m", vmax, ymax - y0));
            GameInput.SimReset();
            pc.Teleport(OpenSpot(new Vector3(0f, 2f, RunwayZ + 30f), 2f) + Vector3.up * 0.2f, 0f);
            Destroy(v.gameObject);
        }

        IEnumerator BoatTest()
        {
            var p = WaterSpot(WorldMarkers.Docks + new Vector3(0f, 0f, -40f));
            var v = VehicleFactory.Spawn(VehicleCatalog.Get("speedboat"), p + Vector3.up * 0.3f, Quaternion.Euler(0f, 270f, 0f));
            yield return new WaitForSeconds(1.5f);
            if (v == null) { Check("water.boat", false, "spawn failed"); yield break; }
            pc.PutInVehicle(v, 0);
            yield return new WaitForSeconds(0.5f);
            var a = v.transform.position;
            GameInput.SimMove = new Vector2(0f, 1f);
            yield return new WaitForSeconds(5f);
            GameInput.SimMove = Vector2.zero;
            float d = U.FlatDist(a, v.transform.position);
            bool afloat = Mathf.Abs(v.transform.position.y - Water.Level) < 1.6f;
            yield return Shot("boat", v.transform.position - v.transform.forward * 12f + Vector3.up * 4f, v.transform.position);
            Check("water.boat", d > 25f && afloat, string.Format("moved {0:F1} m in 5 s, hull y={1:F2}", d, v.transform.position.y));
            pc.ForceExitVehicleNow();
            yield return new WaitForSeconds(1f);
            Destroy(v.gameObject);
            GameInput.SimReset();
        }

        IEnumerator SwimDiveTest()
        {
            var p = WaterSpot(WorldMarkers.Docks + new Vector3(0f, 0f, 60f));
            pc.Teleport(p + Vector3.up * 0.5f, 270f);
            yield return new WaitForSeconds(1.5f);
            bool swim = pc.state == MoveState.Swim;
            GameInput.SimMove = new Vector2(0f, 1f);
            var a = pc.transform.position;
            yield return new WaitForSeconds(2f);
            float sd = U.FlatDist(a, pc.transform.position);
            GameInput.SimHold(Key.LeftCtrl, true);
            yield return new WaitForSeconds(2.5f);
            bool under = pc.Underwater; float breath = pc.breath;
            yield return Shot("dive");
            GameInput.SimReset();
            Check("water.swim", swim && sd > 1.5f, "state=" + (swim ? "Swim" : pc.state.ToString()) + " swam " + sd.ToString("F1") + " m/2s");
            Check("water.dive", under && breath < 1f, "underwater=" + under + " breath=" + breath.ToString("F2"));
            yield return new WaitForSeconds(2.5f);
        }

        IEnumerator ParachuteTest()
        {
            PlayerState.I.hasParachute = true;
            var p = new Vector3(30f, 0f, -205f); p.y = Ground(p) + 160f;   // open airfield apron
            pc.Teleport(p, 0f);
            yield return new WaitForSeconds(1.5f);
            bool freefall = pc.state == MoveState.Freefall;
            GameInput.SimPress(Key.Space);
            yield return new WaitForSeconds(2.5f);
            float y1 = pc.transform.position.y;
            yield return new WaitForSeconds(1f);
            float rate = y1 - pc.transform.position.y;
            yield return Shot("parachute", pc.transform.position + new Vector3(6f, 2f, -8f), pc.transform.position + Vector3.up * 2f);
            Check("player.parachute", freefall && pc.state == MoveState.Parachute && rate < 9f, "freefall=" + freefall + " state=" + pc.state + " sink " + rate.ToString("F1") + " m/s");
            for (float t = 0; t < 40f && pc.state != MoveState.Ground; t += 0.5f) yield return new WaitForSeconds(0.5f);
            Check("player.parachute_landing", pc.state == MoveState.Ground && !pc.actor.IsDead, "landed state=" + pc.state + " hp=" + pc.actor.health.ToString("F0"));
        }

        IEnumerator ShopsModsSave()
        {
            var ps = PlayerState.I;
            ps.money = 50000;
            ShopUI.Show("weapons");
            yield return new WaitForSeconds(0.6f);
            yield return Shot("ui_weaponshop");
            ShopUI.Close();
            ShopUI.Show("clothing");
            yield return new WaitForSeconds(0.6f);
            yield return Shot("ui_clothing");
            ShopUI.Close();
            var p = new Vector3(-60f, 2f, RunwayZ); p.y = Ground(p) + 0.7f;
            var v = VehicleFactory.Spawn(VehicleCatalog.Get("sports"), p, Quaternion.Euler(0f, 90f, 0f));
            yield return new WaitForSeconds(1f);
            pc.PutInVehicle(v, 0);
            ModShop.OpenShop(v);
            yield return new WaitForSeconds(0.6f);
            yield return Shot("ui_modshop");
            ModShop.Close();
            float tq0 = v.mods.TorqueMul;
            v.mods.engine = 3; v.mods.turbo = 1; v.mods.spoiler = 2; v.mods.paint = "#2a9d8f"; v.mods.wheelType = 3; v.ApplyMods();
            v.health *= 0.4f; v.Repair();
            yield return new WaitForSeconds(0.4f);
            Check("vehicle.mods_repair", v.mods.TorqueMul > tq0 && v.health >= v.maxHealth * 0.99f, "torque x" + v.mods.TorqueMul.ToString("F2") + " health " + v.health.ToString("F0") + "/" + v.maxHealth.ToString("F0"));
            yield return Shot("modded_car", v.transform.TransformPoint(new Vector3(3.5f, 1.6f, 5f)), v.transform.position + Vector3.up * 0.6f);
            pc.ForceExitVehicleNow();
            yield return new WaitForSeconds(1.2f);
            // save / load round trip
            int m0 = ps.money;
            SaveSystem.Save();
            ps.money = 7;
            SaveSystem.Load();
            yield return new WaitForSeconds(0.5f);
            Check("save.load_roundtrip", ps.money == m0, "money " + m0 + " -> 7 -> " + ps.money + " after Load()");
            if (v != null) Destroy(v.gameObject);
        }

        IEnumerator TaxiWildlife()
        {
            pc.Teleport(WorldMarkers.Downtown + new Vector3(8f, 1f, -8f), 0f);
            yield return new WaitForSeconds(1f);
            TaxiService.Call();
            float t0 = Time.time;
            while (TaxiService.Current == null && Time.time - t0 < 5f) yield return null;
            yield return new WaitForSeconds(6f);
            var taxi = TaxiService.Current;
            float d = taxi != null ? Vector3.Distance(taxi.transform.position, pc.transform.position) : -1f;
            if (taxi != null) yield return Shot("taxi", pc.transform.position + new Vector3(-6f, 4f, -6f), taxi.transform.position);
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
            yield return new WaitForSeconds(1.5f);
            pc.Teleport(WorldMarkers.Hilltop + Vector3.up * 2f, 0f);
            yield return new WaitForSeconds(5f);
            int animals = 0; var kinds = new HashSet<string>();
            foreach (var an in FindObjectsByType<AnimalActor>(FindObjectsSortMode.None)) { animals++; kinds.Add(an.model); }
            Check("world.wildlife", animals >= 3, animals + " animals active (" + string.Join(",", kinds) + ")");
            yield return Shot("wildlife_hill");
        }

        IEnumerator VehicleDamageTest()
        {
            var p = new Vector3(20f, 2f, RunwayZ); p.y = Ground(p) + 0.7f;
            WantedSystem.Clear(); WantedSystem.Suppressed = true;
            pc.Teleport(p + new Vector3(0f, 0f, -16f), 0f);
            var v = VehicleFactory.Spawn(VehicleCatalog.Get("van"), p, Quaternion.Euler(0f, 90f, 0f));
            yield return new WaitForSeconds(1f);
            pc.weapons.Give("rifle", 300, true);
            for (int i = 0; i < 40 && v != null && !v.IsDestroyed; i++) { pc.weapons.Fire(v.transform.position + Vector3.up * 0.8f, 0.3f, true); yield return new WaitForSeconds(0.11f); }
            float hp = v != null ? v.health : 0f;
            yield return Shot("vehicle_damaged", pc.transform.position + new Vector3(-6f, 3f, -2f), v != null ? v.transform.position : p);
            bool smoking = v != null && v.health < v.maxHealth * 0.4f;
            pc.weapons.Give("rpg", 4, true);
            yield return new WaitForSeconds(1.7f);
            if (pc.weapons.Clip == 0) { pc.weapons.Reload(); yield return new WaitForSeconds(3.5f); }
            if (v != null && !v.IsDestroyed) { bool f = pc.weapons.Fire(v.transform.position + Vector3.up * 0.8f, 0.1f, true); Log("rocket at van fired=" + f + ", health before=" + v.health.ToString("F0")); }
            for (float t = 0; t < 14f && v != null && !v.IsDestroyed; t += 0.5f) yield return new WaitForSeconds(0.5f);
            Log("vehicle damage: smoking/low health after gunfire=" + smoking);
            yield return new WaitForSeconds(1f);
            yield return Shot("vehicle_destroyed", pc.transform.position + new Vector3(-6f, 3f, -2f), v != null ? v.transform.position : p);
            Check("vehicle.damage_explosion", v == null || v.IsDestroyed, "health after gunfire " + hp.ToString("F0") + "; destroyed=" + (v == null || v.IsDestroyed));
            WantedSystem.Suppressed = false; WantedSystem.Clear();
        }

        IEnumerator UiScreens()
        {
            AdminMenu.Toggle(); yield return new WaitForSecondsRealtime(0.5f);
            Check("ui.admin_menu", AdminMenu.Open, "F1 admin/benchmark menu opened");
            yield return Shot("ui_admin");
            AdminMenu.Toggle(); yield return new WaitForSecondsRealtime(0.3f);
            MapScreen.ShowMap(); yield return new WaitForSecondsRealtime(0.5f);
            Check("ui.map", MapScreen.IsOpen, "full map opened");
            yield return Shot("ui_map");
            MapScreen.Close(); yield return new WaitForSecondsRealtime(0.3f);
            WeaponWheel.OpenWheel(); yield return new WaitForSecondsRealtime(0.4f);
            Check("ui.weapon_wheel", WeaponWheel.Open, "weapon wheel opened");
            yield return Shot("ui_weaponwheel");
            WeaponWheel.Close(); yield return new WaitForSecondsRealtime(0.3f);
            Phone.Toggle(); yield return new WaitForSecondsRealtime(0.5f);
            Check("ui.phone", Phone.Open, "phone opened");
            yield return Shot("ui_phone");
            Phone.Close(); yield return new WaitForSecondsRealtime(0.3f);
            PauseMenu.Open(); yield return new WaitForSecondsRealtime(0.5f);
            Check("ui.pause", PauseMenu.IsOpen, "pause menu opened");
            yield return Shot("ui_pause");
            PauseMenu.Close(); yield return new WaitForSecondsRealtime(0.5f);
        }

        IEnumerator DayNightWeather()
        {
            pc.Teleport(WorldMarkers.Downtown + new Vector3(0f, 1f, -12f), 0f);
            yield return new WaitForSeconds(1.5f);
            GameTime.I.SetTime(18.6f); Weather.Set(Weather.Kind.Clear, true);
            yield return new WaitForSeconds(1.5f);
            yield return Shot("time_sunset");
            GameTime.I.SetTime(23f); Weather.Set(Weather.Kind.Rain, true);
            yield return new WaitForSeconds(2f);
            yield return Shot("time_night_rain");
            Weather.Set(Weather.Kind.Fog, true); GameTime.I.SetTime(7f);
            yield return new WaitForSeconds(1.5f);
            yield return Shot("weather_fog_morning");
            Check("world.time_weather", GameTime.Hour > 6.5f && Weather.Current == Weather.Kind.Fog, "hour=" + GameTime.Clock + " weather=" + Weather.Current);
            Weather.Set(Weather.Kind.Clear, true); GameTime.I.SetTime(12f);
        }

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
            if (target.SpeedKmh < 5f)
            {
                var cv = target as CarVehicle;
                Log("stolen car diag: " + (cv != null ? cv.Diag() : "-") + " kinematic=" + target.Rb.isKinematic + " constraints=" + target.Rb.constraints + " engine=" + target.engineOn
                    + " driver=" + (target.Driver != null ? target.Driver.name : "none") + " pcState=" + pc.state + " thr=" + target.input.throttle.ToString("F2") + " vel=" + target.Rb.linearVelocity.ToString("F2") + " hp=" + target.health.ToString("F0"));
                var sb = new System.Text.StringBuilder("stolen car contacts:");
                foreach (var h in Physics.OverlapSphere(target.transform.position + target.transform.forward * 1.5f, 3.4f, ~0, QueryTriggerInteraction.Ignore))
                    if (h.attachedRigidbody != target.Rb)
                        sb.Append(' ').Append(h.name).Append("(L").Append(h.gameObject.layer).Append(h.attachedRigidbody == null ? ",static" : (h.attachedRigidbody.isKinematic ? ",kin" : ",dyn")).Append(h is CharacterController ? ",CC" : "").Append(h.transform.IsChildOf(target.transform) ? ",child" : "").Append(')');
                foreach (var h in target.GetComponentsInChildren<Collider>()) if (h.enabled && h.attachedRigidbody == target.Rb && h.GetComponentInParent<Actor>() != null) sb.Append(" ACTOR-COLLIDER-IN-CAR:").Append(h.name);
                Log(sb.ToString());
            }
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
    }
}
