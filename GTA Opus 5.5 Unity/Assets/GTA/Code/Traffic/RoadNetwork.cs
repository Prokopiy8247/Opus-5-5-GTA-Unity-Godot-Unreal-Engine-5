using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Lane-graph road network built procedurally by the world builder. Provides lane positions, directions and junctions.</summary>
    public class RoadNetwork : MonoBehaviour
    {
        public static RoadNetwork I;
        public class Lane
        {
            public Vector3 a, b;              // centre-line start/end (y = ground)
            public float halfWidth = 3.4f;
            public int dir;                   // +1 drives a->b, -1 drives b->a
            public List<int> next = new List<int>();
            public List<int> cross = new List<int>();  // perpendicular lanes (junction)
            public bool isHighway;
            public Vector3 Point(float t) => Vector3.Lerp(a, b, t);
            public Vector3 Dir => ((b - a).normalized) * dir;
            public float Length => Vector3.Distance(a, b);
        }

        public readonly List<Lane> lanes = new List<Lane>();
        public readonly List<Vector3> intersections = new List<Vector3>();
        readonly List<Bounds> junctionBounds = new List<Bounds>();

        void Awake() { I = this; }

        public void BuildFromSegments(List<(Vector3 a, Vector3 b, float halfWidth, bool highway)> segs)
        {
            lanes.Clear(); intersections.Clear(); junctionBounds.Clear();
            var raw = new List<Lane>();
            foreach (var s in segs)
            {
                for (int d = 0; d < 2; d++)
                {
                    var dir = new Vector3(s.b.x - s.a.x, 0f, s.b.z - s.a.z).normalized;
                    var off = Vector3.Cross(Vector3.up, dir) * (s.halfWidth * 0.44f);
                    if (d == 0) raw.Add(new Lane { a = s.a + off, b = s.b + off, dir = 1, halfWidth = s.halfWidth * 0.5f, isHighway = s.highway });
                    else raw.Add(new Lane { a = s.b - off, b = s.a - off, dir = 1, halfWidth = s.halfWidth * 0.5f, isHighway = s.highway });
                }
            }
            // link lanes that end near another lane's start (junction connections)
            for (int i = 0; i < raw.Count; i++)
            {
                for (int j = 0; j < raw.Count; j++)
                {
                    if (i == j) continue;
                    if (Vector3.Distance(raw[i].b, raw[j].a) < 14f)
                    {
                        raw[i].next.Add(j);
                        var cross = Vector3.Cross(raw[i].Dir, raw[j].Dir).y;
                        if (Mathf.Abs(cross) > 0.35f) raw[j].isHighway = raw[j].isHighway;
                    }
                }
                if (raw[i].next.Count == 0)
                {
                    // dead end: connect to the nearest lane start so traffic can loop
                    int best = -1; float bd = 60f;
                    for (int j = 0; j < raw.Count; j++)
                    {
                        if (i == j) continue;
                        float d = Vector3.Distance(raw[i].b, raw[j].a);
                        if (d < bd) { bd = d; best = j; }
                    }
                    if (best >= 0) raw[i].next.Add(best);
                }
            }
            lanes.AddRange(raw);
            // junctions = lane endpoints where 3+ lanes meet
            foreach (var l in lanes) l.cross.Clear();
            for (int i = 0; i < lanes.Count; i++)
            {
                var end = lanes[i].b;
                var list = new List<int>();
                for (int j = 0; j < lanes.Count; j++)
                {
                    if (i == j) continue;
                    if (Vector3.Distance(lanes[j].a, end) < 12f || Vector3.Distance(lanes[j].b, end) < 12f) list.Add(j);
                }
                if (list.Count >= 4)
                {
                    lanes[i].cross = list;
                    bool exists = false;
                    foreach (var p in intersections) if (Vector3.Distance(p, end) < 6f) { exists = true; break; }
                    if (!exists) { intersections.Add(end); junctionBounds.Add(new Bounds(end, new Vector3(26f, 20f, 26f))); }
                }
            }
        }

        public bool InJunction(Vector3 p, out Vector3 centre)
        {
            foreach (var b in junctionBounds)
            {
                if (b.Contains(new Vector3(p.x, b.center.y, p.z))) { centre = b.center; return true; }
            }
            centre = Vector3.zero; return false;
        }

        /// <summary>Nearest point on any lane (used by traffic spawn and driving AI fallback).</summary>
        public bool NearestLane(Vector3 p, out int laneIdx, out float t, out Vector3 point)
        {
            laneIdx = -1; t = 0f; point = p;
            float best = float.MaxValue;
            for (int i = 0; i < lanes.Count; i++)
            {
                var l = lanes[i];
                var ap = p - l.a; var ab = l.b - l.a;
                float tt = Mathf.Clamp01(Vector3.Dot(ap, ab) / Mathf.Max(ab.sqrMagnitude, 0.001f));
                var q = l.a + ab * tt;
                float d = (q - p).sqrMagnitude;
                if (d < best) { best = d; laneIdx = i; t = tt; point = q; }
            }
            return laneIdx >= 0;
        }

        /// <summary>Traffic-light state at a junction (0 green, 1 amber, 2 red) based on phase.</summary>
        public static int SignalState(Vector3 junction, float phase)
        {
            float k = Mathf.Repeat(phase + Mathf.Abs(junction.x * 0.03f + junction.z * 0.017f), 1f);
            if (k < 0.42f) return 0;
            if (k < 0.5f) return 1;
            return 2;
        }

        public static float SignalPhase => Mathf.Repeat(Time.time / 26f, 1f);

        /// <summary>Pedestrian sidewalk graph = lane endpoints inset toward the curb.</summary>
        public void GetSidewalkPoints(List<Vector3> outPts, float step = 12f)
        {
            foreach (var l in lanes)
            {
                float len = l.Length;
                int n = Mathf.Max(2, Mathf.RoundToInt(len / step));
                for (int i = 0; i <= n; i++)
                {
                    var p = l.Point((float)i / n);
                    outPts.Add(p);
                }
            }
        }
    }
}
