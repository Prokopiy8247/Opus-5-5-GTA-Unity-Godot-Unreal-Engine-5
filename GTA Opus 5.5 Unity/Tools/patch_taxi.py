"""One-off source patch (segment 5): reliable taxi service (arrive, ride as passenger, skip trip with fade, fare)."""
import os
ROOT = os.path.join(os.path.dirname(__file__), "..", "Assets", "GTA", "Code")

p = os.path.join(ROOT, "World", "Wildlife.cs")
s = open(p, encoding="utf-8").read()
i = s.index("    /// <summary>Taxi for hire: call it, it drives to you, you ride as a passenger to a chosen stop.</summary>")
j = s.index("namespace Halcyon", i)
k = s.rindex("}", 0, j)
new_block = r'''    /// <summary>
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
'''
s = s[:i] + new_block + s[k:]
open(p, "w", encoding="utf-8").write(s)

p = os.path.join(ROOT, "Save", "SaveSystem.cs")
s = open(p, encoding="utf-8").read()
old = '''                    var t = TaxiService.Current != null ? TaxiService.Current.GetComponent<TaxiRoutine>() : null;
                    if (t != null) { t.SetDestination(pos); HUD.Notify("Destination: " + n, 2f); }
                    else HUD.Notify("Call a taxi first", 1.6f);
                    Close();'''
new = '''                    TaxiService.SetDestination(pos, n);
                    Close();'''
assert s.count(old) == 1
s = s.replace(old, new)
s = s.replace('menu.Header("Ride destinations (ride as a passenger, then the driver heads there)");',
              'menu.Header("Ride destinations (get in as a passenger with G; the trip is skipped)");')
open(p, "w", encoding="utf-8").write(s)

# HUD: full-screen fade used by the taxi trip skip
p = os.path.join(ROOT, "UI", "HUD.cs")
s = open(p, encoding="utf-8").read()
old = '''        public static void ShowVehicleName(string n) { Notify(n, 1.4f); }'''
new = '''        public static void ShowVehicleName(string n) { Notify(n, 1.4f); }

        Image fadeImg; float fadeTarget, fadeSpeed = 2f;
        /// <summary>Full-screen black fade (0 = clear, 1 = black) over 'seconds'.</summary>
        public static void Fade(float target, float seconds)
        {
            if (I == null) return;
            if (I.fadeImg == null)
            {
                var rt = Panel(I.transform, Vector2.zero, Vector2.zero, new Vector2(0.5f, 0.5f), Color.clear);
                rt.anchorMin = Vector2.zero; rt.anchorMax = Vector2.one; rt.offsetMin = Vector2.zero; rt.offsetMax = Vector2.zero;
                I.fadeImg = rt.GetComponent<Image>(); I.fadeImg.raycastTarget = false; I.fadeImg.color = new Color(0f, 0f, 0f, 0f);
            }
            I.fadeTarget = target; I.fadeSpeed = 1f / Mathf.Max(seconds, 0.01f);
        }'''
assert s.count(old) == 1
s = s.replace(old, new)
old = '''            UpdateMinimap(pc);
        }'''
new = '''            if (fadeImg != null) { var fc = fadeImg.color; fc.a = Mathf.MoveTowards(fc.a, fadeTarget, Time.unscaledDeltaTime * fadeSpeed); fadeImg.color = fc; }
            UpdateMinimap(pc);
        }'''
assert s.count(old) == 1
s = s.replace(old, new)
open(p, "w", encoding="utf-8").write(s)
print("patched taxi")
