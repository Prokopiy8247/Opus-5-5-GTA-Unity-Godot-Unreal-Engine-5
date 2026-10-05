using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Rotating landmark parts (Ferris wheel, radar, windsock) — simple continuous rotation.</summary>
    public class Spinner : MonoBehaviour
    {
        public Vector3 axis = Vector3.right;
        public float speed = 6f;
        void Update() { transform.Rotate(axis, speed * Time.deltaTime, Space.Self); }
    }
}
