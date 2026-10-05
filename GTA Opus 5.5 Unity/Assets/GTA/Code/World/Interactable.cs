using System;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Attachable objects (garage, shop, safehouse, pickups, ladders).</summary>
    public class Interactable : MonoBehaviour
    {
        public string id = "interact";
        public string Prompt = "Interact";
        public float radius = 1.8f;
        public Action<PlayerController> action;
        public bool oneShot;
        static readonly List<Interactable> all = new List<Interactable>();

        void OnEnable() { all.Add(this); }
        void OnDisable() { all.Remove(this); }

        public void Interact(PlayerController pc)
        {
            action?.Invoke(pc);
            if (oneShot) enabled = false;
        }

        public static IReadOnlyList<Interactable> All => all;

        /// <summary>
        /// Interaction points authored inside a building footprint (solid COL_Main boxes) are moved to the nearest
        /// free spot outside at the same ground level so the player can actually reach them.
        /// </summary>
        public bool EnsureReachable()
        {
            var p = transform.position;
            if (!Blocked(p, transform)) return true;
            for (float r = 1f; r <= 10f; r += 0.75f)
                for (int k = 0; k < 20; k++)
                {
                    float a = k * Mathf.PI * 2f / 20f;
                    var q = p + new Vector3(Mathf.Cos(a) * r, 0f, Mathf.Sin(a) * r);
                    q.y = U.GroundHeight(q + Vector3.up * 2.5f, p.y);
                    if (Mathf.Abs(q.y - p.y) > 1.2f || Blocked(q, transform)) continue;
                    transform.position = q + Vector3.up * 0.02f;
                    return true;
                }
            return false;
        }

        static readonly Collider[] probe = new Collider[16];

        /// <summary>True when a standing player capsule at p would intersect world geometry (own marker/props ignored).</summary>
        public static bool Blocked(Vector3 p, Transform self)
        {
            int n = Physics.OverlapCapsuleNonAlloc(p + Vector3.up * 0.45f, p + Vector3.up * 1.6f, 0.3f, probe, Layers.World, QueryTriggerInteraction.Ignore);
            for (int i = 0; i < n; i++) if (self == null || !probe[i].transform.IsChildOf(self)) return true;
            return false;
        }

        public static Interactable Nearest(Vector3 p)
        {
            Interactable best = null; float bd = float.MaxValue;
            foreach (var i in all)
            {
                if (i == null || !i.isActiveAndEnabled) continue;
                float d = Vector3.Distance(i.transform.position, p);
                if (d < i.radius && d < bd) { bd = d; best = i; }
            }
            return best;
        }
    }
}
