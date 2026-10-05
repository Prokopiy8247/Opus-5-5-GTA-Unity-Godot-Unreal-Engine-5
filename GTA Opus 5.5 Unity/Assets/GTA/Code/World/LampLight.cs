using UnityEngine;

namespace Halcyon
{
    /// <summary>Registers a street/building point light with the night-time light budget.</summary>
    public class LampLight : MonoBehaviour
    {
        void Start()
        {
            var l = GetComponent<Light>();
            if (l != null) StreetLights.Register(l);
        }
    }
}
