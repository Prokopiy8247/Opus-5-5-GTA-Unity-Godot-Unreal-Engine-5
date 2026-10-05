using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Traffic signal head driven by the shared junction phase (emission via MaterialPropertyBlock).</summary>
    public class TrafficLightProp : MonoBehaviour
    {
        public Vector3 junction;
        public bool axisNS;
        Renderer red, amber, green;
        MaterialPropertyBlock mpb;
        int lastState = -1;
        static readonly int EmissionId = Shader.PropertyToID("_EmissionColor");

        void Start()
        {
            mpb = new MaterialPropertyBlock();
            foreach (var r in GetComponentsInChildren<Renderer>())
            {
                var role = U.Role(r.transform);
                if (role == "SIG_R") red = r; else if (role == "SIG_Y") amber = r; else if (role == "SIG_G") green = r;
            }
        }

        void Update()
        {
            if (Time.frameCount % 6 != 0) return;
            float phase = RoadNetwork.SignalPhase + (axisNS ? 0.5f : 0f);
            int st = RoadNetwork.SignalState(junction, phase);
            if (st == lastState) return;
            lastState = st;
            Set(red, st == 2, new Color(1f, 0.15f, 0.1f));
            Set(amber, st == 1, new Color(1f, 0.65f, 0.1f));
            Set(green, st == 0, new Color(0.2f, 1f, 0.45f));
        }

        void Set(Renderer r, bool on, Color c)
        {
            if (r == null) return;
            r.GetPropertyBlock(mpb);
            mpb.SetColor(EmissionId, on ? c * 4f : c * 0.05f);
            r.SetPropertyBlock(mpb);
        }
    }
}
