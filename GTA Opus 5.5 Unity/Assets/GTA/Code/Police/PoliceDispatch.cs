using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Spawns and commands the police response for the current wanted level: cruisers, officers on foot, roadblocks, helicopter.</summary>
    public class PoliceDispatch : MonoBehaviour
    {
        public static PoliceDispatch I;
        [System.NonSerialized] public bool active;
        public const float MaxDist = 320f;
        int maxCars = 0, maxFoot = 0;
        float spawnTimer, blockTimer, heliTimer;
        readonly List<(Vehicle v, VehicleAI ai)> units = new List<(Vehicle, VehicleAI)>();
        readonly Dictionary<Vehicle, float> shootTimer = new Dictionary<Vehicle, float>();
        Vehicle heli;
        public static bool HeliSeesPlayer;
        public static bool AnyPursuing => I != null && I.units.Count > 0;

        void Awake() { I = this; }

        void Update()
        {
            var pc = PlayerController.I;
            if (pc == null) return;
            int lvl = WantedSystem.Level;
            active = lvl > 0;
            switch (lvl)
            {
                case 0: maxCars = 0; maxFoot = 0; break;
                case 1: maxCars = 2; maxFoot = 2; break;
                case 2: maxCars = 4; maxFoot = 4; break;
                case 3: maxCars = 6; maxFoot = 6; break;
                case 4: maxCars = 8; maxFoot = 8; break;
                default: maxCars = 11; maxFoot = 10; break;
            }
            Cleanup();
            if (!active) { heliTimer = 0f; return; }

            float dt = Time.deltaTime * GameManager.TimeScale;
            spawnTimer -= dt;
            if (spawnTimer <= 0f && units.Count < maxCars)
            {
                spawnTimer = Mathf.Lerp(2.4f, 0.8f, lvl / 5f);
                SpawnUnit(lvl);
            }
            // helicopter at 3+
            if (lvl >= 3)
            {
                heliTimer += dt;
                if (heli == null && heliTimer > 8f) { SpawnHeli(lvl); heliTimer = 0f; }
            }
            else if (heli != null) { RemoveHeli(); }
            // roadblocks at 3+
            if (lvl >= 3)
            {
                blockTimer -= dt;
                if (blockTimer <= 0f) { blockTimer = 22f; SpawnRoadblock(lvl); }
            }
            // foot officers exit when the player is on foot and close
            foreach (var (v, ai) in units)
            {
                if (v == null || ai == null) continue;
                if (v.IsDestroyed) continue;
                var drv = v.Driver;
                bool playerOnFoot = !pc.actor.InVehicle;
                float d = Vector3.Distance(v.transform.position, pc.transform.position);
                if (drv != null && !drv.IsPlayer && playerOnFoot && d < 13f && v.Speed < 9f && Random.value < 0.02f)
                {
                    var brain = drv.GetComponent<NPCBrain>();
                    if (brain == null) continue;
                    var vv = v;
                    string plate = vv.name;
                    brain.ExitVehicle();
                    // one officer stays in the car
                    if (Random.value < 0.6f) NPCFactory.AddPassenger(vv, NPCFactory.Archetype.Police);
                }
                if (v.Speed > 0.5f && !v.sirenOn && Random.value < 0.01f) v.ToggleSiren();
                ai.pursuing = true;
                // passengers lean out and shoot at a suspect they can see (3+ stars)
                if (lvl >= 3 && d < 32f && v.seats.Length > 1)
                {
                    shootTimer.TryGetValue(v, out float st);
                    st -= Time.deltaTime;
                    if (st <= 0f)
                    {
                        st = Random.Range(0.35f, 0.9f);
                        for (int s = 1; s < v.seats.Length; s++)
                        {
                            var occ = v.seats[s].occupant;
                            if (occ == null || occ.IsDead || occ.weapons == null) continue;
                            if (!U.LineOfSight(occ.HeadPos, pc.actor.Center, v.transform, pc.transform, Layers.Sight)) continue;
                            occ.weapons.accuracyMul = 2.6f;
                            occ.weapons.Fire(pc.actor.Center + Random.insideUnitSphere * 0.6f, 1.8f, true);
                            break;
                        }
                    }
                    shootTimer[v] = st;
                }
            }
            if (heli != null && heli.IsDestroyed) { heli = null; HeliSeesPlayer = false; }
        }

        void Cleanup()
        {
            for (int i = units.Count - 1; i >= 0; i--)
            {
                var (v, ai) = units[i];
                var pc = PlayerController.I;
                float dist = (pc != null && v != null) ? Vector3.Distance(v.transform.position, pc.transform.position) : 0f;
                // driverless units (officers out on foot, roadblocks) stay while they are close to the action
                bool abandoned = v != null && v.Driver == null && v.Speed < 0.2f && !v.persistent && dist > 70f;
                if (v == null || v.IsDestroyed || dist > MaxDist || abandoned || WantedSystem.Level == 0)
                {
                    if (v != null)
                    {
                        v.ClearAllOccupants();
                        Pool.Release(v.gameObject);
                    }
                    units.RemoveAt(i);
                }
            }
        }

        void SpawnUnit(int lvl)
        {
            var pc = PlayerController.I;
            var net = RoadNetwork.I;
            if (net == null || pc == null) return;
            Vector3 pos = Vector3.zero; bool found = false;
            for (int k = 0; k < 24; k++)
            {
                var lane = net.lanes[Random.Range(0, net.lanes.Count)];
                var p = lane.Point(Random.value);
                float d = Vector3.Distance(p, pc.transform.position);
                if (d < (lvl >= 4 ? 45f : 60f) || d > 220f) continue;
                var cam = PlayerCamera.I != null ? PlayerCamera.I.cam : null;
                if (cam != null && d < 90f)
                {
                    var vp = cam.WorldToViewportPoint(p + Vector3.up);
                    if (vp.z > 0 && vp.x > -0.1f && vp.x < 1.1f && vp.y > -0.1f && vp.y < 1.1f) continue; // never spawn in view
                }
                if (Physics.CheckBox(p + Vector3.up * 1.3f, new Vector3(1.5f, 1.2f, 2.8f), Quaternion.LookRotation(lane.Dir), Layers.World | (1 << Layers.Vehicle) | (1 << Layers.NPC), QueryTriggerInteraction.Ignore)) continue;
                pos = p; found = true; break;
            }
            if (!found) return;
            string id = lvl >= 4 && Random.value < 0.5f ? "swat" : "police";
            var def = VehicleCatalog.Get(id);
            var v = VehicleFactory.Spawn(def, pos, Quaternion.identity);
            if (v == null) return;
            var lane2Idx = 0; float t; Vector3 pt;
            RoadNetwork.I.NearestLane(pos, out lane2Idx, out t, out pt);
            var fwd = lane2Idx >= 0 ? RoadNetwork.I.lanes[lane2Idx].Dir : Vector3.forward;
            v.transform.rotation = Quaternion.LookRotation(fwd);
            v.lightsOn = GameTime.IsDark;
            v.sirenOn = true;
            v.engineOn = true;
            var drv = NPCFactory.SpawnDriver(v, pos + Vector3.up * 1.2f);
            var ai = v.gameObject.AddComponent<VehicleAI>();
            ai.Init(v, drv, true);
            ai.pursuing = true;
            ai.aggression = Mathf.Lerp(1.1f, 1.7f, lvl / 5f);
            if (lvl >= 3 && drv != null) NPCFactory.AddPassenger(v, lvl >= 4 ? NPCFactory.Archetype.Tactical : NPCFactory.Archetype.Police);
            units.Add((v, ai));
            if (units.Count > 0 && Random.value < 0.1f) HUD.Notify("Police responding", 1.4f);
        }

        void SpawnHeli(int lvl)
        {
            var pc = PlayerController.I;
            var def = VehicleCatalog.Get("policeheli");
            var spawn = pc.transform.position + new Vector3(Random.Range(-140f, 140f), 60f, Random.Range(-140f, 140f));
            var v = VehicleFactory.Spawn(def, spawn, Quaternion.identity);
            if (v == null) return;
            heli = v;
            var ai = v.gameObject.AddComponent<PoliceHeliAI>();
            ai.Init(v, lvl);
            HUD.Notify("Police helicopter inbound", 2.2f);
        }

        void RemoveHeli()
        {
            if (heli != null) { heli.ClearAllOccupants(); Pool.Release(heli.gameObject); heli = null; HeliSeesPlayer = false; }
        }

        void SpawnRoadblock(int lvl)
        {
            var pc = PlayerController.I;
            var net = RoadNetwork.I;
            if (pc == null || net == null) return;
            // find a lane ahead of the player's travel direction or near last known position
            Vector3 anchor = WantedSystem.Pursuing ? pc.transform.position : WantedSystem.LastKnownPos;
            var vel = pc.actor.InVehicle && pc.actor.vehicle.Rb != null ? pc.actor.vehicle.Rb.linearVelocity : Vector3.zero;
            Vector3 ahead = anchor + vel.normalized * 120f;
            if (vel.sqrMagnitude < 4f) ahead = anchor + Random.insideUnitSphere * 80f;
            int idx; float t; Vector3 pt;
            if (!net.NearestLane(ahead, out idx, out t, out pt)) return;
            if (Vector3.Distance(pt, pc.transform.position) < 60f) return;
            var lane = net.lanes[idx];
            var dir = lane.Dir;
            var right = Vector3.Cross(Vector3.up, dir);
            int cars = lvl >= 4 ? 3 : 2;
            for (int i = 0; i < cars; i++)
            {
                float off = (i - (cars - 1) * 0.5f) * 3.4f;
                var p = pt + right * off;
                p.y = U.GroundHeight(p + Vector3.up * 2f, p.y) + 0.2f;
                var v = VehicleFactory.Spawn(VehicleCatalog.Get("police"), p, Quaternion.LookRotation(right * (i % 2 == 0 ? 1f : -1f)));
                if (v == null) continue;
                v.input = new VehicleInput { brake = 0.5f, handbrake = 1f };
                v.lightsOn = true; v.sirenOn = true; v.persistent = true;
                v.Rb.constraints = RigidbodyConstraints.FreezePositionX | RigidbodyConstraints.FreezePositionZ;
                var drv = NPCFactory.SpawnDriver(v, p + Vector3.up * 1.2f);
                if (i == 0 && drv != null)
                {
                    // one officer stands behind the block
                    drv.GetComponent<NPCBrain>().ExitVehicle();
                    var bp = pt - dir * 4f + right * 1.2f;
                    drv.transform.position = new Vector3(bp.x, U.GroundHeight(bp + Vector3.up * 2f, bp.y) + 0.05f, bp.z);
                    drv.GetComponent<NPCBrain>().Alert(anchor);
                }
                units.Add((v, v.gameObject.AddComponent<VehicleAI>()));
                units[units.Count - 1].ai.Init(v, drv, true);
            }
            HUD.Notify("Roadblock ahead", 1.6f);
        }
    }

    /// <summary>Police helicopter: orbits the player, keeps eyes on, and disgorges a marksman at high wanted levels.</summary>
    public class PoliceHeliAI : MonoBehaviour
    {
        Vehicle v; int level; float gunTimer, spawnTimer;
        Transform player;
        readonly List<Actor> crew = new List<Actor>();
        Vector3 orbitOffset;

        public void Init(Vehicle veh, int lvl)
        {
            v = veh; level = lvl;
            player = PlayerController.I != null ? PlayerController.I.transform : null;
            v.engineOn = true; v.lightsOn = true; v.sirenOn = true; v.persistent = true;
            orbitOffset = new Vector3(Random.Range(-30f, 30f), 0f, Random.Range(-30f, 30f));
            // pilot in seat 0 (helicopters ignore input without a driver), marksmen in the back
            var pilot = NPCFactory.Spawn(NPCFactory.Archetype.Police, v.transform.position + Vector3.up * 2f, v.transform.rotation);
            if (pilot != null) pilot.GetComponent<NPCBrain>().EnterVehicle(v, 0);
            if (lvl >= 3)
            {
                for (int i = 0; i < 2 && i + 1 < v.seats.Length; i++)
                {
                    var a = NPCFactory.Spawn(i == 0 ? NPCFactory.Archetype.Tactical : NPCFactory.Archetype.Police, v.transform.position + Vector3.up * 2f, v.transform.rotation);
                    if (a == null) continue;
                    a.GetComponent<NPCBrain>().EnterVehicle(v, i + 1);
                    crew.Add(a);
                }
            }
        }

        void Update()
        {
            if (player == null || v == null || v.IsDestroyed) { Destroy(gameObject); return; }
            float dt = Time.deltaTime;
            var want = player.position + orbitOffset + Vector3.up * 42f;
            var to = want - transform.position;
            var dir = to.normalized;
            v.input = new VehicleInput
            {
                lift = Mathf.Clamp(dir.y * 2.2f, -1f, 1f),
                pitch = Mathf.Clamp(Vector3.Dot(U.Flat(dir).normalized, transform.forward), -1f, 1f),
                roll = Mathf.Clamp(Vector3.Dot(U.Flat(dir).normalized, transform.right), -1f, 1f),
                yaw = Mathf.Clamp(Vector3.Cross(U.Flat(dir).normalized, transform.forward).y * -2f, -1f, 1f),
            };
            v.engineOn = true;

            bool seen = U.LineOfSight(transform.position, player.position + Vector3.up, transform, player, Layers.Sight);
            PoliceDispatch.HeliSeesPlayer = seen && Vector3.Distance(transform.position, player.position) < 130f;
            if (PoliceDispatch.HeliSeesPlayer) WantedSystem.Spotted(player.position);

            // shoot at the player at 4+ when seen and close
            if (level >= 4 && seen && crew.Count > 0)
            {
                gunTimer -= dt;
                if (gunTimer <= 0f && Vector3.Distance(transform.position, player.position) < 90f)
                {
                    gunTimer = Random.Range(0.5f, 1.3f);
                    foreach (var c in crew)
                    {
                        if (c == null || c.IsDead || c.vehicle != v) continue;
                        var wc = c.weapons;
                        if (wc == null) continue;
                        wc.accuracyMul = 2.4f;
                        wc.Fire(player.position + Vector3.up * Random.Range(0f, 1.2f), 1.6f, true);
                        break;
                    }
                }
            }
            if (Vector3.Distance(transform.position, player.position) > 300f) { v.ClearAllOccupants(); Pool.Release(v.gameObject); Destroy(gameObject); }
        }
    }
}
