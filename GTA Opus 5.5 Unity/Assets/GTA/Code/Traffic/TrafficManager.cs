using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Spawns and recycles civilian traffic and parked vehicles around the player.</summary>
    public class TrafficManager : MonoBehaviour
    {
        public static TrafficManager I;
        public static bool Enabled = true;
        public int maxActive = 26, parkedCount = 90;
        public float spawnRadius = 110f, despawnRadius = 220f, minSpawnDist = 55f;
        readonly List<Vehicle> active = new List<Vehicle>();
        readonly List<Vehicle> parked = new List<Vehicle>();
        float spawnTimer;
        Transform player;

        void Awake() { I = this; }

        public void Begin()
        {
            player = PlayerController.I != null ? PlayerController.I.transform : null;
            SpawnParked();
        }

        static readonly string[] CivilianPool = { "sedan", "compact", "sports", "muscle", "suv", "pickup", "van", "taxi", "truck" };
        static readonly string[] CivilianPoolNight = { "sedan", "compact", "taxi", "suv", "van" };

        void Update()
        {
            if (!Enabled || player == null || GameManager.Paused) return;
            if (PlayerController.I != null && PlayerController.I.actor.IsDead) return;
            spawnTimer -= Time.deltaTime * GameManager.TimeScale;
            // recycle far vehicles
            for (int i = active.Count - 1; i >= 0; i--)
            {
                var v = active[i];
                if (v == null || v.IsDestroyed || v.persistent)
                {
                    if (v != null && v.Driver != null && v.Driver.IsPlayer) continue;
                    active.RemoveAt(i);
                    continue;
                }
                if ((v.transform.position - player.position).sqrMagnitude > despawnRadius * despawnRadius)
                {
                    Despawn(v); active.RemoveAt(i);
                }
            }
            if (spawnTimer > 0f || active.Count >= maxActive) return;
            spawnTimer = Random.Range(0.25f, 0.8f);
            TrySpawn();
        }

        bool TrySpawn()
        {
            var net = RoadNetwork.I;
            if (net == null || net.lanes.Count == 0) return false;
            for (int attempt = 0; attempt < 12; attempt++)
            {
                var lane = net.lanes[Random.Range(0, net.lanes.Count)];
                var p = lane.Point(Random.value);
                float d = Vector3.Distance(p, player.position);
                if (d < minSpawnDist || d > spawnRadius) continue;
                if (!OnScreen(p)) continue;
                if (Physics.CheckBox(p + Vector3.up * 1.2f, new Vector3(1.6f, 1f, 2.6f), Quaternion.LookRotation(lane.Dir), Layers.World | (1 << Layers.Vehicle) | (1 << Layers.NPC), QueryTriggerInteraction.Ignore)) continue;
                var id = GameTime.IsDark ? CivilianPoolNight[Random.Range(0, CivilianPoolNight.Length)] : CivilianPool[Random.Range(0, CivilianPool.Length)];
                if (GameTime.IsDark && id != "taxi" && Random.value < 0.25f) id = "taxi";
                var vdef = VehicleCatalog.Get(id);
                if (vdef == null) continue;
                var v = VehicleFactory.Spawn(vdef, p, Quaternion.LookRotation(lane.Dir));
                if (v == null) continue;
                v.lightsOn = GameTime.IsDark;
                v.input = new VehicleInput { brake = 0.2f, handbrake = 1f };
                // driver
                var drv = NPCFactory.SpawnDriver(v, p + Vector3.up * 1.2f);
                if (drv != null)
                {
                    var ai = v.gameObject.AddComponent<VehicleAI>();
                    ai.Init(v, drv, false);
                    ai.aggression = Random.Range(0.85f, 1.15f);
                    drv.transform.SetParent(v.transform, true);
                    drv.vehicle = v; drv.seat = 0;
                    v.seats[0].occupant = drv;
                    v.engineOn = true;
                }
                active.Add(v);
                return true;
            }
            return false;
        }

        bool OnScreen(Vector3 p)
        {
            var cam = PlayerCamera.I != null ? PlayerCamera.I.cam : Camera.main;
            if (cam == null) return true;
            var vp = cam.WorldToViewportPoint(p + Vector3.up * 1f);
            return vp.z < 0f || vp.x < 0.02f || vp.x > 0.98f || vp.y < 0.02f || vp.y > 0.98f;
        }

        public static void Despawn(Vehicle v)
        {
            if (v == null) return;
            if (v.Driver != null && v.Driver.IsPlayer) return;
            v.persistent = false;
            Pool.Release(v.gameObject);
        }

        void SpawnParked()
        {
            var net = RoadNetwork.I;
            if (net == null) return;
            for (int i = 0; i < parkedCount && net.lanes.Count > 0; i++)
            {
                var lane = net.lanes[Random.Range(0, net.lanes.Count)];
                var p = lane.Point(Random.Range(0.08f, 0.92f));
                var side = Vector3.Cross(Vector3.up, lane.Dir);
                var pos = p + side * (lane.halfWidth + 2.4f);
                // parked cars must be off the driving lane and on flat ground
                float gy = U.GroundHeight(pos + Vector3.up * 2f, pos.y);
                if (Mathf.Abs(gy - pos.y) > 0.6f) continue;
                pos.y = gy;
                var rot = Quaternion.LookRotation(lane.Dir);
                if (Physics.CheckBox(pos + Vector3.up * 1.2f, new Vector3(1.3f, 1f, 2.4f), rot, Layers.World | (1 << Layers.Vehicle) | (1 << Layers.NPC) | (1 << Layers.Player), QueryTriggerInteraction.Ignore)) continue;
                if (PlayerController.I != null && U.FlatDist(pos, PlayerController.I.transform.position) < 9f) continue;   // never on top of the player spawn
                var id = CivilianPool[Random.Range(0, CivilianPool.Length)];
                var def = VehicleCatalog.Get(id);
                if (def == null) continue;
                var v = VehicleFactory.Spawn(def, pos, rot * Quaternion.Euler(0f, Random.Range(-4f, 4f), 0f), true);
                if (v == null) continue;
                v.engineOn = false;
                v.Rb.isKinematic = true;
                parked.Add(v);
            }
        }

        public void ToggleParked(bool on)
        {
            foreach (var p in parked) if (p != null) p.gameObject.SetActive(on);
        }
    }
}
