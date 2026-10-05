using System;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Climbable ladder.</summary>
    public class Ladder : MonoBehaviour
    {
        public float Length = 6f;
        public Vector3 Bottom, Top;
        public Vector3 Normal = Vector3.forward;
        static readonly List<Ladder> all = new List<Ladder>();

        void OnEnable() { all.Add(this); }
        void OnDisable() { all.Remove(this); }

        public float Project(Vector3 p)
        {
            var d = Top - Bottom;
            return Mathf.Clamp01(Vector3.Dot(p - Bottom, d) / Mathf.Max(d.sqrMagnitude, 0.001f));
        }

        // Normal is the wall's outward surface normal (from the wall toward the climber)
        public Vector3 PointAt(float t) => Vector3.Lerp(Bottom, Top, t) + Normal * 0.45f;
        public Vector3 TopExit => Top - Normal * 1.1f + Vector3.up * 0.1f;
        public Vector3 BottomExit => Bottom + Normal * 1.0f;

        public static Ladder Nearest(Vector3 p, float radius)
        {
            Ladder best = null; float bd = radius;
            foreach (var l in all)
            {
                if (l == null) continue;
                float d = Vector3.Distance(l.PointAt(l.Project(p)), p);
                if (d < bd) { bd = d; best = l; }
            }
            return best;
        }
    }
}
