using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>AI driving for civilian and police vehicles: lane following, junction handling, gap keeping, avoidance.</summary>
    public class VehicleAI : MonoBehaviour
    {
        Vehicle v;
        public bool police, pursuing, reverse;
        int lane; float t; float stuckTime, reverseTime, avoidOffset, avoidVel, laneChangeCooldown;
        int stuckCount;
        Vector3 targetPos, targetDir;
        public Actor driver;
        Transform playerT;
        const float LookAhead = 12f;
        public float skillHighway = 1f;
        public Vector3 chasePos;
        public bool hasChasePos;
        public float aggression = 1f;
        float hornCooldown;
        static readonly Collider[] buf = new Collider[24];

        public void Init(Vehicle vehicle, Actor drv, bool isPolice)
        {
            v = vehicle; driver = drv; police = isPolice;
            var net = RoadNetwork.I;
            if (net != null && net.NearestLane(transform.position, out lane, out t, out _)) { }
            nextLane = -1; stuckTime = 0f; reverseTime = 0f; stuckCount = 0;
            playerT = PlayerController.I != null ? PlayerController.I.transform : null;
        }

        float searchT; Vector3 searchOffset;
        int nextLane = -1;
        static readonly System.Collections.Generic.List<int> turnCands = new System.Collections.Generic.List<int>();

        /// <summary>Next lane at the end of this one: mostly straight on, sometimes a left/right turn, never a U-turn.</summary>
        static int PickNext(RoadNetwork net, int laneIdx)
        {
            var cur = net.lanes[laneIdx];
            if (cur.next.Count == 0) return -1;
            int pick = cur.next[0], straight = -1; turnCands.Clear();
            for (int i = 0; i < cur.next.Count; i++)
            {
                float dot = Vector3.Dot(cur.Dir, net.lanes[cur.next[i]].Dir);
                if (dot > 0.7f) straight = cur.next[i];
                else if (dot > -0.5f) turnCands.Add(cur.next[i]);
            }
            if (straight >= 0 && (turnCands.Count == 0 || Random.value < 0.6f)) pick = straight;
            else if (turnCands.Count > 0) pick = turnCands[Random.Range(0, turnCands.Count)];
            return pick;
        }

        /// <summary>Where the path leaves lane l for lane nl. turn &lt; 0 = right turn, &gt; 0 = left turn, ~0 = straight on.</summary>
        static Vector3 Corner(RoadNetwork.Lane l, RoadNetwork.Lane nl, out float turn)
        {
            turn = 0f;
            if (nl == null) return l.b;
            Vector3 d1 = l.Dir, d2 = nl.Dir;
            turn = d1.x * d2.z - d1.z * d2.x;
            if (Mathf.Abs(turn) < 0.35f) return l.b;
            Vector3 w = nl.a - l.a;
            float s = (w.x * d2.z - w.z * d2.x) / turn;   // intersection of the two centre lines
            var c = l.a + d1 * s; c.y = l.b.y;
            return c;
        }

        void Update()
        {
            if (v == null || v.IsDestroyed) { enabled = false; return; }
            if (v.Driver == null && !police) { enabled = false; return; }
            var net = RoadNetwork.I;
            if (net == null) return;

            float dt = Time.deltaTime;
            if (lane < 0 || lane >= net.lanes.Count) { net.NearestLane(transform.position, out lane, out t, out _); }
            if (lane < 0) return;

            var l = net.lanes[lane];
            if (nextLane < 0 || nextLane >= net.lanes.Count || !l.next.Contains(nextLane)) nextLane = PickNext(net, lane);
            var nl = nextLane >= 0 ? net.lanes[nextLane] : null;
            Vector3 pos = transform.position;
            // the path turns at the crossing point of the two lane centre lines (not at the junction centre),
            // so right turns hug the near corner without cutting across the pavement
            Vector3 corner = Corner(l, nl, out float turn);
            float toCorner = Vector3.Dot(corner - pos, l.Dir);
            // switch once past the corner along this lane, or once further along the next lane than short of the corner
            // (a car rounding the corner never quite reaches the corner point itself)
            if (nl != null && (toCorner < 0.5f || Vector3.Dot(pos - corner, nl.Dir) > Mathf.Max(0.5f, toCorner)))
            {
                lane = nextLane; l = nl;
                nextLane = PickNext(net, lane); nl = nextLane >= 0 ? net.lanes[nextLane] : null;
                corner = Corner(l, nl, out turn);
                toCorner = Vector3.Dot(corner - pos, l.Dir);
                laneChangeCooldown = 0f;
            }
            float sAlong = Mathf.Max(0f, Vector3.Dot(pos - l.a, l.Dir));
            t = Mathf.Clamp01(sAlong / Mathf.Max(l.Length, 0.01f));

            float speed = Mathf.Abs(v.Speed);
            float look = Mathf.Clamp(3f + speed * 0.6f, 6f, LookAhead);
            Vector3 aimPoint;
            if (nl == null || look <= toCorner) aimPoint = l.a + l.Dir * (sAlong + look);
            else if (Mathf.Abs(turn) >= 0.35f) aimPoint = corner + nl.Dir * (look - Mathf.Max(toCorner, 0f));
            else aimPoint = nl.a + nl.Dir * (look - Mathf.Max(toCorner, 0f));   // straight on
            Vector3 laneDir = l.Dir;

            // ---- junction / traffic light
            float wantSpeed = (l.isHighway ? 22f : 14f) * (police && pursuing ? 1.35f : 1f) * aggression;
            // slow down for a turn: ~20 km/h for a right turn, ~25 km/h for a left turn at the corner
            if (nl != null && Mathf.Abs(turn) >= 0.35f && !(police && pursuing))
                wantSpeed = Mathf.Min(wantSpeed, (turn < 0f ? 5.5f : 7f) + Mathf.Max(0f, toCorner - 6f) * 0.55f);
            if (net.InJunction(l.b, out var jc))
            {
                // north-south approaches run half a cycle out of phase with east-west ones (same rule as TrafficLightProp)
                bool ns = Mathf.Abs(l.Dir.z) > Mathf.Abs(l.Dir.x);
                int st = RoadNetwork.SignalState(jc, RoadNetwork.SignalPhase + (ns ? 0.5f : 0f));
                float distToJ = U.FlatDist(transform.position, jc);
                const float stopLine = 12.5f;
                if (police && pursuing) { }
                else if (st == 2 && distToJ > stopLine - 1.5f && distToJ < stopLine + 26f)
                    wantSpeed = Mathf.Min(wantSpeed, Mathf.Max(0f, (distToJ - stopLine) * 0.9f));
                else if (st == 1 && distToJ > stopLine + 4f && distToJ < stopLine + 20f)
                    wantSpeed = Mathf.Min(wantSpeed, 5f);
            }

            // ---- gap keeping + avoidance (forward and diagonal fans)
            bool blocked = false; float blockDist = 99f; Vector3 avoidDir = Vector3.zero; Vehicle blocker = null;
            int n = Physics.OverlapSphereNonAlloc(transform.position + v.transform.forward * 6f, 7f, buf, ~(1 << Layers.Trigger), QueryTriggerInteraction.Ignore);
            for (int i = 0; i < n; i++)
            {
                var c = buf[i];
                var other = c.GetComponentInParent<Vehicle>();
                if (other == null)
                {
                    // people standing or walking in the lane ahead: slow down / stop and honk at the player
                    var who = c.GetComponentInParent<Actor>();
                    if (who == null || who.IsDead || who.vehicle != null || (police && pursuing && who.IsPlayer)) continue;
                    var tp = who.transform.position - transform.position;
                    if (Vector3.Dot(v.transform.forward, tp.normalized) < 0.6f || Mathf.Abs(Vector3.Dot(v.transform.right, tp)) > 1.9f) continue;
                    float dp = tp.magnitude;
                    wantSpeed = Mathf.Min(wantSpeed, Mathf.Max(0f, (dp - 4.5f) * 1.6f));
                    if (who.IsPlayer && hornCooldown <= 0f && dp < 10f) { hornCooldown = 3f; v.input.horn = true; Invoke(nameof(HornOff), 0.5f); }
                    continue;
                }
                if (other == v) continue;
                var to = other.transform.position - transform.position;
                float fwdDot = Vector3.Dot(v.transform.forward, to.normalized);
                if (fwdDot < 0.45f) continue;
                float lat = Vector3.Dot(v.transform.right, to);
                if (Mathf.Abs(lat) > 2.6f) continue;   // other lane / parked off-road
                float d = to.magnitude;
                // a wreck or an abandoned car standing in the lane: slow down and drive around it (left if it is dead ahead)
                if (other.IsDestroyed || (other.Driver == null && other.Rb != null && other.Rb.linearVelocity.sqrMagnitude < 1f))
                {
                    if (d < 12f) { wantSpeed = Mathf.Min(wantSpeed, 4f); avoidDir -= v.transform.right * (Mathf.Abs(lat) > 0.7f ? Mathf.Sign(lat) : 1f) * (12f - d); }
                    continue;
                }
                if (d < blockDist) { blockDist = d; blocked = true; blocker = other; }
                // swerve away from a car that only partly blocks the lane; one dead ahead is simply followed
                if (d < 9f && Mathf.Abs(lat) > 0.7f) avoidDir -= v.transform.right * Mathf.Sign(lat) * (9f - d);
            }
            if (blocked)
            {
                float followGap = police && pursuing ? 5f : 8f;
                if (blockDist < followGap) wantSpeed = Mathf.Min(wantSpeed, Mathf.Max(0f, (blockDist - 3f) * 2.4f));
                // honk at a player who blocks the road
                if (blocker != null && blocker.Driver != null && blocker.Driver.IsPlayer && Mathf.Abs(v.Speed) < 0.6f && hornCooldown <= 0f)
                { hornCooldown = 3f; v.input.horn = true; Invoke(nameof(HornOff), 0.4f); }
            }
            hornCooldown -= dt;

            // ---- steering toward the aim point
            Vector3 toAim = aimPoint - transform.position; toAim.y = 0f;
            float desiredYaw = Mathf.Atan2(toAim.x, toAim.z) * Mathf.Rad2Deg;
            float yawErr = Mathf.DeltaAngle(transform.eulerAngles.y, desiredYaw);
            float steer = Mathf.Clamp(yawErr / 26f, -1f, 1f);

            // obstacle avoidance offset blends into the steering, but never pushes the car over the kerb
            if (avoidDir.sqrMagnitude > 0.01f && reverseTime <= 0f)
            {
                float want = Mathf.Clamp(Vector3.Dot(avoidDir.normalized, v.transform.right), -1f, 1f);
                float laneLat = Vector3.Dot(transform.position - l.a, Vector3.Cross(Vector3.up, laneDir));   // + = right of the lane centre
                if ((want > 0f && laneLat > 1.2f) || (want < 0f && laneLat < -3.6f)) want = 0f;
                avoidOffset = Mathf.MoveTowards(avoidOffset, want, dt * 1.5f);
            }
            else avoidOffset = Mathf.MoveTowards(avoidOffset, 0f, dt * 1.2f);
            steer = Mathf.Clamp(steer + avoidOffset * 0.6f, -1f, 1f);

            // ---- police pursuit overrides
            if (police && pursuing && playerT != null)
            {
                // direct chase only while the suspect is seen; otherwise search around the last known position
                if (!WantedSystem.Pursuing)
                {
                    searchT -= dt;
                    if (searchT <= 0f) { searchT = Random.Range(5f, 9f); searchOffset = Random.insideUnitSphere * Mathf.Lerp(18f, 45f, Random.value); searchOffset.y = 0f; }
                }
                Vector3 chase = WantedSystem.Pursuing ? (hasChasePos ? chasePos : playerT.position) : WantedSystem.LastKnownPos + searchOffset;
                var toP = chase - transform.position; toP.y = 0f;
                float dP = toP.magnitude;
                float desired = Mathf.Atan2(toP.x, toP.z) * Mathf.Rad2Deg;
                float err = Mathf.DeltaAngle(transform.eulerAngles.y, desired);
                steer = Mathf.Clamp(err / 22f, -1f, 1f);
                wantSpeed = dP > 25f ? 30f : dP > 12f ? 20f : 12f;
                if (!WantedSystem.Pursuing) wantSpeed = dP > 30f ? 20f : 8f;   // search patrol
                // ram from behind rather than head-on
                if (dP < 6f) wantSpeed = 16f;
            }

            // ---- stuck recovery: wanted to move but did not (another car, wall, tree, post) -> back up with counter-steer
            float along = Vector3.Dot(v.Rb.linearVelocity, v.transform.forward);
            float spd = Mathf.Abs(v.Speed);
            if (reverseTime > 0f) reverseTime -= dt;
            else if (wantSpeed > 3f && spd < 0.6f)
            {
                stuckTime += dt;
                if (stuckTime > 2.2f) { stuckTime = 0f; reverseTime = 1.5f; stuckCount++; }
            }
            else if (spd > 2f) { stuckTime = 0f; if (along > 3f) stuckCount = 0; }
            if (reverseTime > 0f) steer = -steer;   // reversing: opposite lock swings the nose toward the target
            // hopelessly stuck where the player cannot see it happen: recycle the car
            if (stuckCount >= 4 && !police && !v.persistent && playerT != null && (transform.position - playerT.position).sqrMagnitude > 40f * 40f)
            { TrafficManager.Despawn(v); return; }

            // ---- write the vehicle input
            var inp = v.input;
            if (reverseTime > 0f) { inp.throttle = -0.7f; inp.brake = 0f; }
            else if (along < wantSpeed - 1f) { inp.throttle = Mathf.Clamp01((wantSpeed - along) / 8f); inp.brake = 0f; }
            else { inp.throttle = 0f; inp.brake = Mathf.Clamp01((along - wantSpeed) / 6f) * 0.7f; }
            inp.steer = steer;
            inp.handbrake = 0f;
            inp.horn = v.input.horn;
            v.input = inp;
            reverse = reverseTime > 0f;

            // lights for night driving
            if (GameTime.IsDark && !v.lightsOn && Random.value < 0.002f) v.ToggleLights();
            if (!GameTime.IsDark && v.lightsOn && Random.value < 0.001f) v.ToggleLights();

            // despawn if very far away and unoccupied by the player
            if (!police && !v.persistent && playerT != null && (transform.position - playerT.position).sqrMagnitude > 260f * 260f)
                TrafficManager.Despawn(v);
        }

        void HornOff() { var i = v.input; i.horn = false; v.input = i; }

        public void OnCrash(float dv)
        {
            stuckTime += 1.2f;
            if (dv > 8f) { Invoke(nameof(StopNow), 0.2f); }
        }

        void StopNow() { var i = v.input; i.throttle = 0f; i.brake = 1f; v.input = i; }

        public void OnRammed(Vehicle by)
        {
            var a = by.Driver;
            if (a != null && a.IsPlayer) { aggression = Mathf.Min(aggression + 0.25f, 2.2f); stuckTime = 0f; }
        }

        /// <summary>Police tactic: match the target laterally for a PIT / box-in attempt.</summary>
        public void PITAssist(Vector3 playerPos, Vector3 playerVel)
        {
            chasePos = playerPos + playerVel * 0.35f;
            hasChasePos = true;
        }
    }
}
