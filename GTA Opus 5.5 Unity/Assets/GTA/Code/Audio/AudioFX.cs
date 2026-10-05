using System;
using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>
    /// Fully procedural, project-owned audio. Every clip is synthesized at startup (no recorded or third-party audio).
    /// </summary>
    public class AudioFX : MonoBehaviour
    {
        public const int SR = 22050;
        static AudioFX inst;
        static readonly Dictionary<string, AudioClip> clips = new Dictionary<string, AudioClip>();
        AudioSource[] pool; int poolIdx; AudioSource ui;
        public static float Sfx = 1f, Music = 0.7f, Master = 1f;
        static System.Random rng = new System.Random(1234);

        public static void Init()
        {
            if (inst != null) return;
            inst = new GameObject("[Audio]").AddComponent<AudioFX>();
            DontDestroyOnLoad(inst.gameObject);
            inst.pool = new AudioSource[40];
            for (int i = 0; i < inst.pool.Length; i++)
            {
                var g = new GameObject("src" + i); g.transform.SetParent(inst.transform);
                var s = g.AddComponent<AudioSource>(); s.playOnAwake = false; s.spatialBlend = 1f; s.rolloffMode = AudioRolloffMode.Linear; s.dopplerLevel = 0.3f;
                inst.pool[i] = s;
            }
            inst.ui = inst.gameObject.AddComponent<AudioSource>(); inst.ui.spatialBlend = 0f; inst.ui.playOnAwake = false;
            Generate();
        }

        public static AudioClip Clip(string n) { Init(); clips.TryGetValue(n, out var c); return c; }

        public static void Play(string n, float vol, float pitch = 1f)
        {
            var c = Clip(n); if (c == null) return;
            inst.ui.pitch = pitch; inst.ui.PlayOneShot(c, vol * Sfx * Master);
        }

        public static void PlayAt(string n, Vector3 p, float vol, float pitch = 1f, float maxDist = 120f)
        {
            var c = Clip(n); if (c == null) return;
            var cam = PlayerCamera.I != null ? PlayerCamera.I.transform.position : p;
            if ((cam - p).sqrMagnitude > maxDist * maxDist * 1.1f) return;
            var s = inst.pool[inst.poolIdx]; inst.poolIdx = (inst.poolIdx + 1) % inst.pool.Length;
            s.transform.position = p; s.clip = c; s.volume = vol * Sfx * Master; s.pitch = pitch; s.maxDistance = maxDist; s.minDistance = Mathf.Max(1.5f, maxDist * 0.04f);
            s.loop = false; s.Play();
        }

        public static AudioSource Attach(GameObject g, string n, float vol, bool loop, float maxDist = 90f)
        {
            var s = g.AddComponent<AudioSource>();
            s.clip = Clip(n); s.loop = loop; s.volume = vol * Sfx * Master; s.spatialBlend = 1f; s.rolloffMode = AudioRolloffMode.Linear;
            s.maxDistance = maxDist; s.minDistance = 3f; s.dopplerLevel = 0.4f; s.playOnAwake = false;
            if (loop && s.clip != null) { s.time = UnityEngine.Random.Range(0f, s.clip.length * 0.9f); s.Play(); }
            return s;
        }

        // ------------------------------------------------------------------ synthesis
        static float N() => (float)(rng.NextDouble() * 2.0 - 1.0);
        static float[] B(float sec) => new float[Mathf.CeilToInt(sec * SR)];
        static float A(float fc) => 1f - Mathf.Exp(-2f * Mathf.PI * fc / SR);

        static void Store(string n, float[] d, bool loop = false, float gain = 0.9f)
        {
            float peak = 0f; foreach (var v in d) peak = Mathf.Max(peak, Mathf.Abs(v));
            if (peak > 0f) for (int i = 0; i < d.Length; i++) d[i] *= gain / peak;
            if (loop)
            {
                int xf = Mathf.Min(d.Length / 10, SR / 10);
                for (int i = 0; i < xf; i++) { float k = (float)i / xf; d[i] = d[i] * k + d[d.Length - xf + i] * (1 - k); }
                Array.Resize(ref d, d.Length - xf);
            }
            else
            {
                int fade = Mathf.Min(200, d.Length / 4);
                for (int i = 0; i < fade; i++) d[d.Length - 1 - i] *= (float)i / fade;
            }
            var c = AudioClip.Create(n, d.Length, 1, SR, false);
            c.SetData(d, 0);
            clips[n] = c;
        }

        static float[] Gunshot(float len, float decay, float fc0, float fc1, float thumpHz, float thump, float crack, float echo = 0f)
        {
            var d = B(len); float y = 0f, y2 = 0f;
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR;
                float env = Mathf.Exp(-t * decay);
                float fc = Mathf.Lerp(fc0, fc1, Mathf.Clamp01(t * 6f));
                y += A(fc) * (N() - y); y2 += A(fc * 0.6f) * (y - y2);
                float s = y2 * env * 1.6f;
                if (t < 0.004f) s += N() * crack;
                s += Mathf.Sin(2f * Mathf.PI * thumpHz * t) * Mathf.Exp(-t * 24f) * thump;
                d[i] = s;
            }
            if (echo > 0f)
            {
                int delay = (int)(0.23f * SR);
                for (int i = d.Length - 1; i >= delay; i--) d[i] += d[i - delay] * echo;
            }
            return d;
        }

        static float[] Tone(float len, float decay, params float[] freqs)
        {
            var d = B(len);
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR, s = 0f;
                for (int k = 0; k < freqs.Length; k++) s += Mathf.Sin(2f * Mathf.PI * freqs[k] * t) / (k + 1);
                d[i] = s * Mathf.Exp(-t * decay) * Mathf.Clamp01(t * 400f);
            }
            return d;
        }

        static float[] Noise(float len, float fc, float decay, float attack = 0.002f)
        {
            var d = B(len); float y = 0f;
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR;
                y += A(fc) * (N() - y);
                d[i] = y * Mathf.Exp(-t * decay) * Mathf.Clamp01(t / attack);
            }
            return d;
        }

        static float[] Mix(float[] a, float[] b, float gb, int offset = 0)
        {
            var d = new float[Mathf.Max(a.Length, b.Length + offset)];
            for (int i = 0; i < a.Length; i++) d[i] += a[i];
            for (int i = 0; i < b.Length; i++) d[i + offset] += b[i] * gb;
            return d;
        }

        static void Generate()
        {
            Store("shot_pistol", Gunshot(0.42f, 20f, 4200f, 900f, 120f, 0.5f, 0.9f));
            Store("shot_heavy", Gunshot(0.7f, 12f, 3000f, 700f, 85f, 0.9f, 1f, 0.2f));
            Store("shot_smg", Gunshot(0.25f, 30f, 4800f, 1200f, 140f, 0.35f, 0.7f));
            Store("shot_rifle", Gunshot(0.55f, 15f, 3800f, 900f, 95f, 0.6f, 1.1f, 0.15f));
            Store("shot_shotgun", Gunshot(0.8f, 9f, 2400f, 600f, 70f, 1f, 1f, 0.2f));
            Store("shot_sniper", Gunshot(1.3f, 6f, 3200f, 700f, 75f, 0.9f, 1.2f, 0.35f));
            Store("shot_sup", Noise(0.14f, 2600f, 45f), false, 0.55f);
            Store("launch", Mix(Noise(0.9f, 1600f, 4f, 0.05f), Tone(0.4f, 12f, 70f), 0.8f));
            // explosion: brown noise rumble + crack
            {
                var d = B(2.6f); float y = 0f, br = 0f;
                for (int i = 0; i < d.Length; i++)
                {
                    float t = (float)i / SR;
                    br = Mathf.Clamp(br + N() * 0.08f, -1f, 1f) * 0.999f;
                    y += A(Mathf.Lerp(2500f, 300f, Mathf.Clamp01(t * 2f))) * (N() * 0.6f + br - y);
                    d[i] = y * Mathf.Exp(-t * 2.1f) * 1.5f + Mathf.Sin(2f * Mathf.PI * 42f * t) * Mathf.Exp(-t * 2.8f) * 0.8f + (t < 0.01f ? N() : 0f);
                }
                Store("explosion", d);
            }
            Store("reload", Mix(Tone(0.12f, 50f, 2200f, 3400f), Tone(0.12f, 45f, 1600f, 2600f), 1f, (int)(0.3f * SR)));
            Store("dry", Tone(0.05f, 90f, 3000f, 4800f), false, 0.5f);
            Store("step", Noise(0.09f, 700f, 55f), false, 0.6f);
            Store("punch", Mix(Noise(0.16f, 500f, 30f), Tone(0.16f, 35f, 95f), 0.8f));
            Store("hit", Mix(Noise(0.2f, 900f, 25f), Tone(0.2f, 30f, 140f), 0.6f));
            Store("hit_metal", Mix(Tone(0.4f, 11f, 1230f, 2750f, 4110f), Noise(0.03f, 6000f, 100f), 0.5f));
            {
                var d = B(0.28f); float y = 0f;
                for (int i = 0; i < d.Length; i++) { float t = (float)i / SR; y += A(Mathf.Lerp(400f, 1700f, t / 0.28f)) * (N() - y); d[i] = y * Mathf.Sin(Mathf.PI * t / 0.28f); }
                Store("swing", d, false, 0.5f);
            }
            {
                var d = Noise(0.9f, 2600f, 3.5f, 0.03f);
                for (int k = 0; k < 14; k++)
                {
                    int s0 = rng.Next(d.Length / 6, d.Length - 2000); float f = 600f + (float)rng.NextDouble() * 1400f;
                    for (int i = 0; i < 1500 && s0 + i < d.Length; i++) { float t = (float)i / SR; d[s0 + i] += Mathf.Sin(2f * Mathf.PI * (f + t * 4000f) * t) * Mathf.Exp(-t * 60f) * 0.4f; }
                }
                Store("splash", d);
            }
            {
                var d = Noise(0.7f, 1800f, 4f, 0.02f);
                for (int i = 0; i < d.Length; i++) d[i] *= 0.5f + 0.5f * Mathf.Sin(2f * Mathf.PI * 26f * i / SR);
                Store("chute", d);
            }
            Store("cash", Mix(Tone(0.35f, 9f, 1320f, 2640f), Tone(0.3f, 9f, 1760f, 3520f), 1f, (int)(0.08f * SR)));
            Store("ui", Tone(0.07f, 60f, 880f, 1760f), false, 0.5f);
            Store("beep", Tone(0.16f, 8f, 1046f), false, 0.5f);
            {
                var d = B(0.7f);
                for (int k = 0; k < 26; k++)
                {
                    int s0 = rng.Next(0, d.Length / 2); float f = 2800f + (float)rng.NextDouble() * 4500f;
                    for (int i = 0; i < 3000 && s0 + i < d.Length; i++) { float t = (float)i / SR; d[s0 + i] += Mathf.Sin(2f * Mathf.PI * f * t) * Mathf.Exp(-t * 35f) * 0.4f; }
                }
                Store("glass", Mix(d, Noise(0.08f, 7000f, 60f), 0.7f));
            }
            {
                var d = B(0.45f);
                double ph = 0;
                for (int i = 0; i < d.Length; i++) { float t = (float)i / SR; float f = Mathf.Lerp(2600f, 1100f, t / 0.45f); ph += f / SR; d[i] = (float)Math.Sin(2 * Math.PI * ph) * Mathf.Exp(-t * 7f); }
                Store("ricochet", Mix(d, Noise(0.05f, 5000f, 80f), 0.6f), false, 0.6f);
            }
            Store("crash", Mix(Mix(Noise(0.9f, 1300f, 6f), Tone(0.6f, 9f, 380f, 910f, 1470f), 0.5f), Tone(0.3f, 18f, 60f), 0.7f));
            // horn loop: two detuned squares, integer cycles in 0.5 s
            {
                var d = B(0.5f + 0.05f); float y = 0f;
                for (int i = 0; i < d.Length; i++) { float t = (float)i / SR; float s = Mathf.Sign(Mathf.Sin(2f * Mathf.PI * 416f * t)) + Mathf.Sign(Mathf.Sin(2f * Mathf.PI * 524f * t)); y += A(2600f) * (s - y); d[i] = y; }
                Store("horn", d, true, 0.6f);
                var d2 = B(0.5f + 0.05f); y = 0f;
                for (int i = 0; i < d2.Length; i++) { float t = (float)i / SR; float s = Mathf.Sign(Mathf.Sin(2f * Mathf.PI * 312f * t)) + 0.6f * Mathf.Sign(Mathf.Sin(2f * Mathf.PI * 394f * t)); y += A(1800f) * (s - y); d2[i] = y; }
                Store("horn_truck", d2, true, 0.7f);
            }
            // siren wail (4 s period)
            {
                var d = B(4.4f); double ph = 0; float y = 0f;
                for (int i = 0; i < d.Length; i++) { float t = (float)i / SR; float f = 680f + 520f * (0.5f - 0.5f * Mathf.Cos(2f * Mathf.PI * t / 4f)); ph += f / SR; float s = (float)Math.Sin(2 * Math.PI * ph); s = Mathf.Clamp(s * 2.2f, -1f, 1f); y += A(3000f) * (s - y); d[i] = y; }
                Store("siren", d, true, 0.6f);
                var d2 = B(0.5f + 0.05f); ph = 0;
                for (int i = 0; i < d2.Length; i++) { float t = (float)i / SR; float f = 700f + 650f * ((t * 4f) % 1f); ph += f / SR; d2[i] = Mathf.Clamp((float)Math.Sin(2 * Math.PI * ph) * 2f, -1f, 1f); }
                Store("siren_yelp", d2, true, 0.55f);
            }
            // engines: loops with integer cycles per second
            Store("engine", EngineLoop(40f, 12, 0.35f), true, 0.7f);
            Store("engine_heavy", EngineLoop(28f, 14, 0.5f), true, 0.75f);
            Store("engine_bike", EngineLoop(55f, 10, 0.55f), true, 0.65f);
            {
                var d = B(1.1f); float y = 0f;
                for (int i = 0; i < d.Length; i++)
                {
                    float t = (float)i / SR; float blade = (t * 14f) % 1f;
                    y += A(400f) * (N() - y);
                    d[i] = y * Mathf.Exp(-blade * 9f) * 2f + Mathf.Sin(2f * Mathf.PI * 1400f * t) * 0.07f + Mathf.Sin(2f * Mathf.PI * 28f * t) * 0.25f * Mathf.Exp(-blade * 5f);
                }
                Store("rotor", d, true, 0.75f);
            }
            {
                var d = B(1.1f); float y = 0f;
                for (int i = 0; i < d.Length; i++) { float t = (float)i / SR; float saw = 2f * ((t * 85f) % 1f) - 1f; y += A(900f) * (saw - y); d[i] = y * (0.7f + 0.3f * Mathf.Sin(2f * Mathf.PI * 28f * t)); }
                Store("prop", d, true, 0.6f);
            }
            {
                var d = B(2.2f); float y = 0f, lp = 0f;
                for (int i = 0; i < d.Length; i++) { float t = (float)i / SR; lp += A(5000f) * (N() - lp); y += A(300f) * (lp - y); d[i] = (lp - y) * 0.8f + Mathf.Sin(2f * Mathf.PI * 2200f * t) * 0.05f + y * 0.6f; }
                Store("jet", d, true, 0.7f);
            }
            {
                var d = B(1.1f); float y = 0f, y2 = 0f;
                for (int i = 0; i < d.Length; i++) { float t = (float)i / SR; y += A(1400f) * (N() - y); y2 += A(700f) * (y - y2); d[i] = (y - y2) * (0.8f + 0.2f * Mathf.Sin(t * 70f)); }
                Store("skid", d, true, 0.5f);
            }
            {
                var d = B(3.3f); float y = 0f;
                for (int i = 0; i < d.Length; i++) { y += A(5500f) * (N() - y); d[i] = y * 0.6f; }
                for (int k = 0; k < 160; k++) { int s0 = rng.Next(0, d.Length - 400); for (int i = 0; i < 300; i++) d[s0 + i] += N() * Mathf.Exp(-i / 40f) * 0.5f; }
                Store("rain", d, true, 0.5f);
            }
            {
                var d = B(8.8f); float y = 0f, br = 0f;
                for (int i = 0; i < d.Length; i++) { float t = (float)i / SR; br = Mathf.Clamp(br + N() * 0.05f, -1f, 1f) * 0.998f; y += A(600f) * (br + N() * 0.2f - y); d[i] = y * (0.45f + 0.55f * Mathf.Pow(0.5f + 0.5f * Mathf.Sin(2f * Mathf.PI * t / 4.4f), 2f)); }
                Store("ocean", d, true, 0.6f);
            }
            {
                var d = B(6.6f); float y = 0f, y2 = 0f;
                for (int i = 0; i < d.Length; i++) { float t = (float)i / SR; y += A(900f) * (N() - y); y2 += A(250f) * (y - y2); d[i] = (y - y2) * (0.5f + 0.5f * Mathf.Sin(2f * Mathf.PI * t / 3.3f)); }
                Store("wind", d, true, 0.5f);
            }
            {
                var d = B(11f); float y = 0f, br = 0f;
                for (int i = 0; i < d.Length; i++) { br = Mathf.Clamp(br + N() * 0.03f, -1f, 1f) * 0.999f; y += A(260f) * (br - y); d[i] = y * 0.8f; }
                for (int k = 0; k < 5; k++) { int s0 = rng.Next(SR, d.Length - SR); float f = 350f + (float)rng.NextDouble() * 200f; for (int i = 0; i < SR / 4; i++) { float t = (float)i / SR; d[s0 + i] += Mathf.Sign(Mathf.Sin(2f * Mathf.PI * f * t)) * 0.05f * Mathf.Sin(Mathf.PI * t * 4f); } }
                for (int k = 0; k < 40; k++) { int s0 = rng.Next(0, d.Length - SR / 5); float f = 300f + (float)rng.NextDouble() * 900f; float yy = 0; for (int i = 0; i < SR / 6; i++) { float t = (float)i / SR; yy += A(f) * (N() - yy); d[s0 + i] += yy * 0.08f * Mathf.Sin(Mathf.PI * t * 6f) * (0.5f + 0.5f * Mathf.Sin(t * 60f)); } }
                Store("city", d, true, 0.6f);
            }
            {
                var d = B(2.2f); float y = 0f;
                for (int i = 0; i < d.Length; i++) { y += A(700f) * (N() - y); d[i] = y * 0.7f; }
                for (int k = 0; k < 70; k++) { int s0 = rng.Next(0, d.Length - 300); for (int i = 0; i < 250; i++) d[s0 + i] += N() * Mathf.Exp(-i / 25f); }
                Store("fire", d, true, 0.6f);
                Store("rocket", Noise(1.1f, 1800f, 0f, 0.001f), true, 0.6f);
            }
            {
                var d = EngineLoop(30f, 8, 0.25f); float y = 0f;
                for (int i = 0; i < d.Length; i++) { y += A(1200f) * (N() - y); d[i] = d[i] * 0.7f + y * 0.4f; }
                Store("boat", d, true, 0.7f);
            }
            Store("stinger_dead", Chord(1.8f, new[] { 196f, 233f, 293f }, 1.4f));
            Store("stinger_busted", Chord(1.5f, new[] { 261f, 311f, 392f, 466f }, 2f));
            Store("stinger_good", Chord(0.9f, new[] { 523f, 659f, 784f }, 3f));
            {
                var d = B(1.2f);
                for (int i = 0; i < d.Length; i++) { float t = (float)i / SR; bool on = (t % 0.4f) < 0.25f; d[i] = on ? (Mathf.Sin(2f * Mathf.PI * 950f * t) + Mathf.Sin(2f * Mathf.PI * 1150f * t)) * 0.5f * (Mathf.Sin(2f * Mathf.PI * 20f * t) > 0 ? 1f : 0.3f) : 0f; }
                Store("phone", d, false, 0.5f);
            }
            {
                var d = B(1.05f);
                for (int i = 0; i < d.Length; i++) { float t = (float)i / SR; d[i] = Mathf.Sign(Mathf.Sin(2f * Mathf.PI * (t % 0.5f < 0.25f ? 880f : 660f) * t)) * 0.5f; }
                Store("alarm", d, true, 0.45f);
            }
        }

        static float[] EngineLoop(float f0, int harmonics, float rough)
        {
            var d = B(1.05f);
            float y = 0f;
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR, s = 0f;
                for (int k = 1; k <= harmonics; k++) s += Mathf.Sin(2f * Mathf.PI * f0 * k * t + k * 0.7f) / Mathf.Pow(k, 0.85f) * (k % 2 == 0 ? 0.8f : 1f);
                float firing = Mathf.Pow(0.5f + 0.5f * Mathf.Sin(2f * Mathf.PI * f0 * 0.5f * t), 4f);
                y += A(1800f) * (N() - y);
                d[i] = s * (0.7f + 0.3f * firing) + y * rough * firing;
            }
            return d;
        }

        static float[] Chord(float len, float[] freqs, float decay)
        {
            var d = B(len);
            for (int i = 0; i < d.Length; i++)
            {
                float t = (float)i / SR, s = 0f;
                foreach (var f in freqs) s += Mathf.Sin(2f * Mathf.PI * f * t) + 0.3f * Mathf.Sin(4f * Mathf.PI * f * t);
                d[i] = s * Mathf.Exp(-t * decay) * Mathf.Clamp01(t * 60f);
            }
            return d;
        }
    }
}
