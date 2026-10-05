using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Wing flapping for birds circling on a Spinner pivot.</summary>
    public class Flapper : MonoBehaviour
    {
        public float amplitude = 38f, speed = 9f;
        Transform l, r; Quaternion rl, rr; float seed;
        void Start()
        {
            l = U.FindRole(transform, "WING_L"); r = U.FindRole(transform, "WING_R");
            if (l) rl = l.localRotation; if (r) rr = r.localRotation;
            seed = Random.value * 10f;
        }
        void Update()
        {
            float glide = Mathf.PerlinNoise(seed, Time.time * 0.3f) > 0.55f ? 0.15f : 1f;
            float a = Mathf.Sin((Time.time + seed) * speed) * amplitude * glide;
            if (l) l.localRotation = rl * Quaternion.Euler(0f, 0f, a);
            if (r) r.localRotation = rr * Quaternion.Euler(0f, 0f, -a);
        }
    }
}
