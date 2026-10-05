using System;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>Reusable static hooks used across systems (single place so behaviour stays explicit, not hidden in stubs).</summary>
    public static class Globals
    {
        public static void TryAction(Action a) { try { a?.Invoke(); } catch (Exception e) { Debug.LogException(e); } }
    }
}

namespace Halcyon
{


    /// <summary>Parachute canopy visual shown while airborne under canopy.</summary>
    public class Parachute : MonoBehaviour
    {
        public static Parachute Instance;
        GameObject canopy;
        Transform root;

        public static void Init()
        {
            var g = new GameObject("[Parachute]");
            Instance = g.AddComponent<Parachute>();
            var mat = new Material(Shader.Find("Universal Render Pipeline/Lit"));
            mat.SetColor("_BaseColor", new Color(0.92f, 0.35f, 0.3f));
            g.GetComponent<Parachute>().canopy = BuildCanopy(mat);
            g.GetComponent<Parachute>().canopy.SetActive(false);
        }

        static GameObject BuildCanopy(Material m)
        {
            var go = new GameObject("canopy");
            var mf = go.AddComponent<MeshFilter>();
            var mr = go.AddComponent<MeshRenderer>();
            mr.sharedMaterial = m;
            var mesh = new Mesh();
            int seg = 20, ring = 3;
            var verts = new List<Vector3>();
            var tris = new List<int>();
            for (int r = 0; r <= ring; r++)
            {
                float rr = r / (float)ring;
                float radius = 2.8f * rr;
                float height = -1.4f * rr * rr;
                for (int s = 0; s <= seg; s++)
                {
                    float a = s / (float)seg * Mathf.PI * 2f;
                    verts.Add(new Vector3(Mathf.Cos(a) * radius, height, Mathf.Sin(a) * radius));
                }
            }
            for (int r = 0; r < ring; r++)
                for (int s = 0; s < seg; s++)
                {
                    int i0 = r * (seg + 1) + s, i1 = i0 + 1, i2 = i0 + seg + 1, i3 = i2 + 1;
                    tris.Add(i0); tris.Add(i2); tris.Add(i1);
                    tris.Add(i1); tris.Add(i2); tris.Add(i3);
                }
            mesh.SetVertices(verts); mesh.SetTriangles(tris, 0); mesh.RecalculateNormals(); mesh.RecalculateBounds();
            mf.sharedMesh = mesh;
            return go;
        }

        public void Show(Transform owner, bool on)
        {
            if (canopy == null) return;
            root = owner;
            canopy.SetActive(on);
        }

        void LateUpdate()
        {
            if (canopy == null || !canopy.activeSelf || root == null) return;
            canopy.transform.position = root.position + Vector3.up * 3.4f;
            canopy.transform.rotation = Quaternion.identity;
        }
    }

    /// <summary>Radio stations: original procedural tracks (drum/bass/chord loops), cycled with , and .</summary>
    public static class RadioSystem
    {
        public static readonly string[] Stations = { "Off", "Harbor FM", "Night Ferry", "Ironside Beats", "Coastline Classics" };
        static int station;
        static AudioSource src;
        static readonly Dictionary<int, AudioClip> cache = new Dictionary<int, AudioClip>();

        public static int Station => station;
        public static string CurrentName => Stations[Mathf.Clamp(station, 0, Stations.Length - 1)];

        public static void OnEnterVehicle(Vehicle v)
        {
            if (src != null) return;
            var g = new GameObject("[Radio]");
            UnityEngine.Object.DontDestroyOnLoad(g);
            src = g.AddComponent<AudioSource>();
            src.spatialBlend = 1f; src.loop = true; src.volume = 0f; src.maxDistance = 22f; src.rolloffMode = AudioRolloffMode.Linear;
            src.transform.SetParent(v.transform, false);
        }

        public static void OnExitVehicle() { }

        public static void Next(int dir)
        {
            station = (station + dir + Stations.Length) % Stations.Length;
            if (src == null) { HUD.Notify("Radio: " + CurrentName, 1.4f); return; }
            if (station == 0) { src.Stop(); HUD.Notify("Radio off", 1.2f); return; }
            if (!cache.TryGetValue(station, out var clip)) { clip = Generate(station); cache[station] = clip; }
            src.clip = clip; src.Play();
            src.volume = 0.5f * AudioFX.Music * AudioFX.Master;
            HUD.Notify("Radio: " + CurrentName, 1.6f);
        }

        static AudioClip Generate(int s)
        {
            const int SR = 22050;
            float[] freqs = s == 1 ? new[] { 110f, 165f, 220f, 277f } : s == 2 ? new[] { 82f, 123f, 164f, 207f } : new[] { 130f, 196f, 260f, 330f };
            float[] scale = s == 1 ? new[] { 0f, 3f, 5f, 7f, 10f } : s == 2 ? new[] { 0f, 2f, 3f, 7f, 8f } : new[] { 0f, 4f, 5f, 7f, 11f };
            float bpm = s == 1 ? 92f : s == 2 ? 76f : 104f;
            float beat = 60f / bpm;
            int bars = 8;
            int len = Mathf.RoundToInt(beat * 4f * bars * SR);
            var data = new float[len];
            var rnd = new System.Random(s * 7919);
            for (int i = 0; i < len; i++)
            {
                float t = (float)i / SR;
                int beatIdx = Mathf.FloorToInt(t / beat);
                float beatT = t - beatIdx * beat;
                // bass
                float bassF = freqs[0];
                if (beatIdx % 4 == 2) bassF = freqs[1];
                float bass = Mathf.Sin(2f * Mathf.PI * bassF * t) * Mathf.Exp(-beatT * 3.5f) * 0.35f;
                // kick
                float kick = Mathf.Sin(2f * Mathf.PI * (60f - beatT * 40f) * beatT) * Mathf.Exp(-beatT * 22f) * 0.5f;
                // hat
                float hatT = (t % (beat * 0.5f));
                float hat = (float)(rnd.NextDouble() * 2 - 1) * Mathf.Exp(-hatT * 90f) * 0.05f;
                // chord pad, changes each bar
                int bar = Mathf.FloorToInt(t / (beat * 4f)) % bars;
                int[] prog = s == 2 ? new[] { 0, 0, 3, 4 } : new[] { 0, 3, 4, 2 };
                int deg = prog[bar % 4];
                float root = freqs[0] * Mathf.Pow(2f, scale[deg] / 12f);
                float pad = 0f;
                pad += Mathf.Sin(2f * Mathf.PI * root * 2f * t) * 0.06f;
                pad += Mathf.Sin(2f * Mathf.PI * root * 2.5f * t) * 0.05f;
                pad += Mathf.Sin(2f * Mathf.PI * root * 3f * t) * 0.04f;
                float lfo = 0.7f + 0.3f * Mathf.Sin(2f * Mathf.PI * 0.12f * t);
                data[i] = (bass + kick + hat + pad * lfo) * 0.8f;
            }
            // fade the loop edges
            int fade = SR / 10;
            for (int i = 0; i < fade; i++) { float k = (float)i / fade; data[i] *= k; data[len - 1 - i] *= k; }
            var clip = AudioClip.Create("Radio" + s, len, 1, SR, false);
            clip.SetData(data, 0);
            return clip;
        }

        public static void Tick(Vector3 listenerPos)
        {
            if (src == null) return;
            var pc = PlayerController.I;
            if (pc == null) return;
            if (pc.actor.InVehicle) src.transform.SetParent(pc.actor.vehicle.transform, false);
            else if (src.transform.parent != null) src.transform.SetParent(null);
        }
    }
}
