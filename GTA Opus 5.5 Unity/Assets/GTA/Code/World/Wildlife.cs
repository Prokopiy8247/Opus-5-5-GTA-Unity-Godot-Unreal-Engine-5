using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Region-based wildlife with simple ecosystem behaviour (grazing, wandering, fleeing, predators).</summary>
    public class Wildlife : MonoBehaviour
    {
        public static Wildlife I;
        public static bool Enabled = true;
        readonly List<AnimalActor> animals = new List<AnimalActor>();
        float timer;

        public static void Init() { var g = new GameObject("[Wildlife]"); I = g.AddComponent<Wildlife>(); }

        public static void ApplyEnabled()
        {
            if (I == null) return;
            foreach (var a in I.animals) if (a != null) a.gameObject.SetActive(Enabled);
        }

        struct SpawnRule { public string model; public Vector3 centre; public float radius; public int count; public bool predator; public bool aquatic; }

        static readonly SpawnRule[] Rules =
        {
            new SpawnRule{ model="ANI_Deer",   centre=new Vector3(-90f, 0f, 210f), radius=90f, count=6, predator=false },
            new SpawnRule{ model="ANI_Deer",   centre=new Vector3(210f, 0f, 200f), radius=70f, count=3 },
            new SpawnRule{ model="ANI_Coyote", centre=new Vector3(-60f, 0f, 170f), radius=80f, count=4, predator=true },
            new SpawnRule{ model="ANI_Boar",   centre=new Vector3(30f, 0f, 150f),  radius=60f, count=3 },
            new SpawnRule{ model="ANI_Rabbit", centre=new Vector3(-130f, 0f, 160f), radius=70f, count=7 },
            new SpawnRule{ model="ANI_Cat",    centre=new Vector3(20f, 0f, 20f),   radius=60f, count=4 },
            new SpawnRule{ model="ANI_Dog",    centre=new Vector3(150f, 0f, 180f), radius=50f, count=3 },
            new SpawnRule{ model="ANI_Shark",  centre=new Vector3(-380f, -3f, 40f), radius=90f, count=3, predator=true, aquatic=true },
            new SpawnRule{ model="ANI_Fish",   centre=new Vector3(-285f, -3f, 0f), radius=60f, count=10, aquatic=true },
        };

        void Update()
        {
            if (!Enabled) return;
            var pc = PlayerController.I;
            if (pc == null) return;
            timer -= Time.deltaTime;
            if (timer > 0f) return;
            timer = 3f;
            // despawn far animals
            for (int i = animals.Count - 1; i >= 0; i--)
            {
                var a = animals[i];
                if (a == null) { animals.RemoveAt(i); continue; }
                if (Vector3.Distance(a.transform.position, pc.transform.position) > 260f) { Destroy(a.gameObject); animals.RemoveAt(i); }
            }
            foreach (var r in Rules)
            {
                int have = 0;
                foreach (var a in animals) if (a != null && a.model == r.model && Vector3.Distance(a.transform.position, r.centre) < r.radius * 1.6f) have++;
                if (have >= r.count) continue;
                if (Vector3.Distance(pc.transform.position, r.centre) > 220f) continue;
                for (int k = 0; k < 3; k++)
                {
                    var ang = Random.value * Mathf.PI * 2f;
                    var rr = Mathf.Sqrt(Random.value) * r.radius;
                    var p = r.centre + new Vector3(Mathf.Cos(ang) * rr, 0f, Mathf.Sin(ang) * rr);
                    float gh = r.aquatic ? Water.Level - 3.5f : U.GroundHeight(p + Vector3.up * 4f, 0f);
                    p.y = gh + (r.aquatic ? 0f : 0.05f);
                    if (!r.aquatic && (p.x < -300f || p.x > 300f || p.z < -300f || p.z > 300f)) continue;
                    if (Vector3.Distance(p, pc.transform.position) < 45f) continue;
                    var a = AnimalFactory.Spawn(r.model, p, r.predator, r.aquatic);
                    if (a != null) { animals.Add(a); break; }
                }
            }
        }

        public static int Count => I != null ? I.animals.Count : 0;
    }

    public class AnimalActor : MonoBehaviour
    {
        public string model;
        public bool predator, aquatic;
        public float health = 60f;
        Actor actor; CharacterController cc;
        float vy, wanderTimer, speed, panicTimer;
        Vector3 target;
        Transform modelRoot;
        float hover;

        public void Setup(Actor a, CharacterController controller) { actor = a; cc = controller; }

        void Start()
        {
            speed = predator ? 7.5f : 3.2f;
            PickTarget();
        }

        void PickTarget()
        {
            if (aquatic) { float a = Random.value * Mathf.PI * 2f, r = Random.Range(10f, 60f); target = transform.position + new Vector3(Mathf.Cos(a) * r, Random.Range(-2f, 2f), Mathf.Sin(a) * r); }
            else target = transform.position + new Vector3(Random.Range(-35f, 35f), 0f, Random.Range(-35f, 35f));
            wanderTimer = Random.Range(6f, 16f);
        }

        bool deathPosed;

        void Update()
        {
            if (actor != null && actor.IsDead)
            {
                if (!deathPosed)
                {
                    // fall over on the side and stop all procedural motion (gait / wings)
                    deathPosed = true;
                    foreach (var g in GetComponentsInChildren<AnimalGait>()) g.enabled = false;
                    foreach (var f in GetComponentsInChildren<Flapper>()) f.enabled = false;
                    if (cc != null) cc.enabled = false;
                    transform.rotation = Quaternion.Euler(0f, transform.eulerAngles.y, aquatic ? 180f : 88f);
                    if (!aquatic) transform.position = new Vector3(transform.position.x, U.GroundHeight(transform.position + Vector3.up, transform.position.y) + 0.15f, transform.position.z);
                }
                return;
            }
            float dt = Time.deltaTime;
            wanderTimer -= dt;
            panicTimer -= dt;
            var pc = PlayerController.I;
            float spd = speed;
            if (pc != null)
            {
                float d = Vector3.Distance(pc.transform.position, transform.position);
                if (d < 14f && !aquatic)
                {
                    // flee or, for predators, attack when the player is slow / close
                    if (predator && d < 6f && Random.value < 0.4f && panicTimer <= 0f)
                    {
                        target = pc.transform.position;
                        if (d < 2.2f && panicTimer <= 0f)
                        {
                            panicTimer = 2.2f;
                            pc.actor.TakeDamage(DamageInfo.Make(9f, DamageType.Melee, pc.actor.Center, (pc.actor.Center - transform.position).normalized, gameObject, 3f));
                            AudioFX.PlayAt("hit", transform.position, 0.6f);
                        }
                    }
                    else
                    {
                        target = transform.position + (transform.position - pc.transform.position).normalized * 20f;
                        wanderTimer = 3f; spd = speed * 1.7f;
                    }
                }
            }
            if (wanderTimer <= 0f) PickTarget();
            var to = target - transform.position; to.y = 0f;
            if (to.sqrMagnitude < 1.5f) PickTarget();
            var dir = to.normalized;
            if (aquatic)
            {
                float depth = Water.Level - 2.5f - transform.position.y;
                vy = Mathf.Clamp(depth * 0.4f + Mathf.Sin(Time.time * 0.7f) * 0.4f, -1.6f, 1.6f);
                transform.position += (dir * spd + Vector3.up * vy) * dt;
                transform.rotation = Quaternion.RotateTowards(transform.rotation, Quaternion.LookRotation(dir), 90f * dt);
                return;
            }
            if (cc != null && cc.enabled)
            {
                if (cc.isGrounded) vy = -1.5f; else vy -= 20f * dt;
                cc.Move((dir * spd + Vector3.up * vy) * dt);
            }
            else transform.position += dir * spd * dt;
            transform.rotation = Quaternion.RotateTowards(transform.rotation, Quaternion.LookRotation(dir), 180f * dt);
        }
    }

    public static class AnimalFactory
    {
        static readonly Dictionary<string, GameObject> models = new Dictionary<string, GameObject>();

        public static AnimalActor Spawn(string model, Vector3 pos, bool predator, bool aquatic)
        {
            var prefab = GameDatabase.I != null ? GameDatabase.I.Get(model) : null;
            if (prefab == null) return null;
            var go = Object.Instantiate(prefab, pos, Quaternion.Euler(0f, Random.Range(0f, 360f), 0f));
            go.name = model + "_wild";
            Layers.SetRecursive(go, Layers.NPC);
            var cc = go.AddComponent<CharacterController>();
            var b = ComputeBounds(go);
            cc.height = Mathf.Max(b.size.y, 0.4f); cc.radius = Mathf.Max(Mathf.Max(b.size.x, b.size.z) * 0.35f, 0.2f);
            cc.center = new Vector3(0f, cc.height * 0.5f, 0f); cc.stepOffset = 0.3f;
            if (aquatic) cc.enabled = false;
            var actor = go.AddComponent<Actor>();
            actor.faction = Faction.Animal;
            actor.displayName = predator ? "Predator" : "Animal";
            actor.maxHealth = actor.health = predator ? 90f : 45f;
            go.AddComponent<AnimalGait>();
            var aa = go.AddComponent<AnimalActor>();
            aa.model = model; aa.predator = predator; aa.aquatic = aquatic;
            aa.Setup(actor, cc);
            return aa;
        }

        static Bounds ComputeBounds(GameObject go)
        {
            bool first = true; Bounds b = new Bounds(Vector3.zero, Vector3.one);
            foreach (var r in go.GetComponentsInChildren<Renderer>())
            {
                if (first) { b = r.bounds; first = false; } else b.Encapsulate(r.bounds);
            }
            if (first) b = new Bounds(Vector3.zero, new Vector3(1f, 1f, 1.5f));
            b.center -= go.transform.position;
            return b;
        }
    }

    /// <summary>
    /// Taxi for hire: call it from the phone/admin menu, it pulls up next to you, ride as a passenger (G), pick a stop
    /// from the phone or a map waypoint (or SPACE for the nearest district) and the trip is skipped with a fade.
    /// </summary>
    public static class TaxiService
    {
        public static Vehicle Current;
        public static bool Riding => Current != null && PlayerController.I != null && PlayerController.I.actor.vehicle == Current && PlayerController.I.actor.seat > 0;
        static float cooldown;

        public static void Call()
        {
            if (Current != null && !Current.IsDestroyed && cooldown > Time.time) { HUD.Notify("Taxi already on the way", 1.4f); return; }
            var pc = PlayerController.I;
            var net = RoadNetwork.I;
            if (pc == null || net == null) return;
            if (!net.NearestLane(pc.transform.position, out int idx, out float t, out Vector3 pt)) { HUD.Notify("No road nearby", 1.6f); return; }
            var lane = net.lanes[idx];
            var p = pt - lane.Dir * 32f;
            p.y = U.GroundHeight(p + Vector3.up * 3f, p.y) + 0.5f;
            var v = VehicleFactory.Spawn(VehicleCatalog.Get("taxi"), p, Quaternion.LookRotation(lane.Dir));
            if (v == null) { HUD.Notify("Taxi unavailable", 2f); return; }
            v.persistent = true; v.engineOn = true; v.lightsOn = GameTime.IsDark;
            var drv = NPCFactory.SpawnDriver(v, v.transform.position + Vector3.up);
            var ai = v.gameObject.AddComponent<VehicleAI>();
            ai.Init(v, drv, false);
            v.gameObject.AddComponent<TaxiRoutine>().Init(v, pc);
            Current = v;
            cooldown = Time.time + 20f;
            HUD.Notify("Taxi dispatched - it will pull up next to you", 3f);
        }

        public static List<(string, Vector3)> Destinations()
        {
            var list = new List<(string, Vector3)>();
            foreach (var (n, p) in WorldMarkers.Landmarks) list.Add((n, p));
            return list;
        }

        public static void SetDestination(Vector3 pos, string name)
        {
            var t = Current != null ? Current.GetComponent<TaxiRoutine>() : null;
            if (t == null) { HUD.Notify("Call a taxi first", 1.6f); return; }
            t.SetDestination(pos, name);
        }
    }

    public class TaxiRoutine : MonoBehaviour
    {
        enum S { Approach, Waiting, Riding, Travelling, Arrived, Leaving }
        Vehicle v; PlayerController pc;
        S state = S.Approach;
        Vector3 destination; string destName; bool hasDestination;
        float timer = 28f;
        public bool HasArrived => state == S.Arrived;

        public void Init(Vehicle vehicle, PlayerController player) { v = vehicle; pc = player; }

        public void SetDestination(Vector3 pos, string name)
        {
            destination = pos; destName = name; hasDestination = true;
            HUD.Notify("Taxi: heading to " + name + (state == S.Riding ? "" : " - get in as a passenger (G)"), 2.5f);
        }

        void Park()
        {
            var ai = GetComponent<VehicleAI>(); if (ai != null) ai.enabled = false;
            v.input = new VehicleInput { brake = 1f, handbrake = 1f };
            if (v.Rb != null) { v.Rb.linearVelocity = Vector3.zero; v.Rb.angularVelocity = Vector3.zero; }
        }

        void Update()
        {
            if (v == null || v.IsDestroyed || pc == null) { Destroy(this); return; }
            if (v.Driver == null || v.Driver.IsPlayer) { if (TaxiService.Current == v) TaxiService.Current = null; Destroy(this); return; }   // driver killed or taxi stolen
            float d = U.FlatDist(v.transform.position, pc.transform.position);
            bool playerInside = pc.actor.vehicle == v;
            switch (state)
            {
                case S.Approach:
                    timer -= Time.deltaTime;
                    if (d < 9f) { Park(); state = S.Waiting; timer = 40f; HUD.Notify("Taxi is here - press G to ride as a passenger", 4f); }
                    else if (timer <= 0f || d > 140f)
                    {
                        // the lane did not bring it to the player: pull up at the kerb next to them
                        var net = RoadNetwork.I;
                        if (net != null && net.NearestLane(pc.transform.position, out int li, out float lt, out Vector3 lp))
                        {
                            lp.y = U.GroundHeight(lp + Vector3.up * 3f, lp.y) + 0.5f;
                            v.Rb.position = lp; v.transform.SetPositionAndRotation(lp, Quaternion.LookRotation(net.lanes[li].Dir));
                        }
                        Park(); state = S.Waiting; timer = 40f;
                        HUD.Notify("Taxi is here - press G to ride as a passenger", 4f);
                    }
                    break;
                case S.Waiting:
                    timer -= Time.deltaTime;
                    v.input = new VehicleInput { brake = 1f, handbrake = 1f };
                    if (playerInside && pc.actor.seat > 0)
                    {
                        state = S.Riding;
                        HUD.Notify("Taxi: pick a stop on the phone, set a map waypoint (M), or SPACE for the nearest district", 5f);
                    }
                    else if (timer <= 0f) Leave();
                    break;
                case S.Riding:
                    if (!playerInside) { Leave(); break; }
                    v.input = new VehicleInput { brake = 1f, handbrake = 1f };
                    if (!hasDestination && MapScreen.Waypoint.HasValue) { destination = MapScreen.Waypoint.Value; destName = "your waypoint"; hasDestination = true; }
                    if (!hasDestination && GameInput.Down(UnityEngine.InputSystem.Key.Space)) { destination = WorldMarkers.NearestDistrict(pc.transform.position + v.transform.forward * 150f); destName = WorldMarkers.ZoneAt(destination); hasDestination = true; }
                    if (hasDestination) { state = S.Travelling; StartCoroutine(Trip()); }
                    break;
                case S.Arrived:
                    timer -= Time.deltaTime;
                    v.input = new VehicleInput { brake = 1f, handbrake = 1f };
                    if (!playerInside || timer <= 0f) Leave();
                    break;
            }
        }

        System.Collections.IEnumerator Trip()
        {
            var start = v.transform.position;
            HUD.Fade(1f, 0.6f);
            yield return new WaitForSeconds(0.7f);
            var net = RoadNetwork.I;
            Vector3 p = destination; Quaternion r = v.transform.rotation;
            if (net != null && net.NearestLane(destination, out int li, out float lt, out Vector3 lp)) { p = lp; r = Quaternion.LookRotation(net.lanes[li].Dir); }
            p.y = U.GroundHeight(p + Vector3.up * 4f, p.y) + 0.5f;
            v.Rb.linearVelocity = Vector3.zero; v.Rb.angularVelocity = Vector3.zero;
            v.Rb.position = p; v.Rb.rotation = r; v.transform.SetPositionAndRotation(p, r);
            float dist = Vector3.Distance(start, p);
            int fare = Mathf.Max(15, Mathf.RoundToInt(dist * 0.12f));
            if (GameTime.I != null) GameTime.I.SetTime((GameTime.Hour + dist / 900f) % 24f);
            yield return new WaitForSeconds(0.4f);
            HUD.Fade(0f, 0.6f);
            var ps = PlayerState.I;
            if (ps != null) { fare = Mathf.Min(fare, ps.money); ps.money -= fare; }
            HUD.Notify("Arrived at " + destName + " - fare " + U.Money(fare) + ". Press G or F to get out", 4f);
            state = S.Arrived; timer = 25f;
        }

        void Leave()
        {
            state = S.Leaving;
            v.persistent = false;
            var ai = GetComponent<VehicleAI>(); if (ai != null) ai.enabled = true;
            if (TaxiService.Current == v) TaxiService.Current = null;
            Destroy(this);
        }
    }
}

namespace Halcyon
{
    /// <summary>Procedural gait for the Blender animals: swings LEG_* parts, wags TAIL, bobs HEAD, waves FIN/WING parts.</summary>
    public class AnimalGait : MonoBehaviour
    {
        readonly List<(Transform t, Quaternion rest, float phase, int kind)> parts = new List<(Transform, Quaternion, float, int)>();
        Vector3 lastPos;
        float cycle, speed;

        void Start()
        {
            foreach (var t in GetComponentsInChildren<Transform>(true))
            {
                var role = U.Role(t);
                if (role.StartsWith("LEG_"))
                {
                    // diagonal pairs move together (FL+BR, FR+BL)
                    float ph = (role == "LEG_FL" || role == "LEG_BR") ? 0f : Mathf.PI;
                    parts.Add((t, t.localRotation, ph, 0));
                }
                else if (role.StartsWith("TAIL")) parts.Add((t, t.localRotation, 0f, 1));
                else if (role.StartsWith("HEAD")) parts.Add((t, t.localRotation, 0f, 2));
                else if (role.StartsWith("FIN") || role.StartsWith("WING")) parts.Add((t, t.localRotation, role.EndsWith("R") ? Mathf.PI : 0f, 3));
            }
            lastPos = transform.position;
        }

        void Update()
        {
            float dt = Mathf.Max(Time.deltaTime, 1e-4f);
            float v = U.FlatDist(transform.position, lastPos) / dt;
            lastPos = transform.position;
            speed = Mathf.Lerp(speed, v, 1f - Mathf.Exp(-8f * dt));
            cycle += dt * (2.5f + speed * 2.2f);
            float amp = Mathf.Clamp01(speed / 4f);
            foreach (var (t, rest, ph, kind) in parts)
            {
                if (t == null) continue;
                Quaternion q;
                switch (kind)
                {
                    case 0: q = Quaternion.Euler(Mathf.Sin(cycle * 2f + ph) * 32f * amp, 0f, 0f); break;
                    case 1: q = Quaternion.Euler(0f, Mathf.Sin(cycle * 1.3f) * (12f + 18f * amp), 0f); break;
                    case 2: q = Quaternion.Euler(Mathf.Sin(cycle * 2f) * 4f * amp + (amp < 0.1f ? Mathf.Sin(Time.time * 0.6f) * 10f + 12f : 0f), 0f, 0f); break;
                    default: q = Quaternion.Euler(0f, 0f, Mathf.Sin(cycle * 3f + ph) * 25f); break;
                }
                t.localRotation = rest * q;
            }
        }
    }

}
