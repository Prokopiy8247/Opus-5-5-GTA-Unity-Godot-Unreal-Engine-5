using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>
    /// Procedural particle effects. One-shot effects reuse one world-space ParticleSystem per effect type and Emit()
    /// particles directly (no GameObject churn); lights, tracers and bullet holes are pooled.
    /// </summary>
    public class VFX : MonoBehaviour
    {
        static VFX inst;
        readonly Dictionary<string, ParticleSystem> sys = new Dictionary<string, ParticleSystem>();
        readonly List<Light> lights = new List<Light>();
        readonly List<float> lightEnd = new List<float>();
        readonly List<float> lightStart = new List<float>();
        readonly List<float> lightPeak = new List<float>();
        readonly Queue<LineRenderer> tracers = new Queue<LineRenderer>();
        readonly List<(LineRenderer lr, float t)> liveTracers = new List<(LineRenderer, float)>();
        readonly Transform[] holes = new Transform[90];
        int holeIdx;
        Mesh quad;

        static VFX I
        {
            get
            {
                if (inst == null) inst = new GameObject("[VFX]").AddComponent<VFX>();
                return inst;
            }
        }

        static Material Alpha => GameDatabase.I != null ? GameDatabase.I.fxAlpha : null;
        static Material Add => GameDatabase.I != null ? GameDatabase.I.fxAdd : null;

        ParticleSystem Sys(string key)
        {
            if (sys.TryGetValue(key, out var ps) && ps != null) return ps;
            switch (key)
            {
                case "muzzle": ps = Make(key, Add, 0.06f, 0.4f, new Color(1f, 0.82f, 0.45f), 0f, 0.4f, 200); break;
                case "spark": ps = Make(key, Add, 0.35f, 0.06f, new Color(1f, 0.75f, 0.3f), 1.2f, 0.2f, 600, true); break;
                case "dust": ps = Make(key, Alpha, 0.7f, 0.3f, new Color(0.72f, 0.69f, 0.64f, 0.8f), -0.03f, 2.6f, 600); break;
                case "glass": ps = Make(key, Alpha, 0.8f, 0.07f, new Color(0.75f, 0.9f, 1f, 0.9f), 1.5f, 0.6f, 400); break;
                case "chip": ps = Make(key, Alpha, 0.7f, 0.07f, new Color(0.5f, 0.35f, 0.2f, 1f), 1.4f, 0.6f, 300); break;
                case "flesh": ps = Make(key, Alpha, 0.45f, 0.16f, new Color(0.7f, 0.08f, 0.1f, 0.85f), 0.6f, 2f, 400); break;
                case "splash": ps = Make(key, Alpha, 0.9f, 0.25f, new Color(0.92f, 0.97f, 1f, 0.85f), 1.3f, 1.8f, 600); break;
                case "fireball": ps = Make(key, Add, 0.55f, 1.5f, new Color(1f, 0.55f, 0.18f), -0.15f, 2.4f, 400); break;
                case "smoke": ps = Make(key, Alpha, 2.8f, 1.2f, new Color(0.2f, 0.2f, 0.21f, 0.75f), -0.06f, 3.2f, 800); break;
                case "debris": ps = Make(key, Alpha, 1.6f, 0.15f, new Color(0.15f, 0.14f, 0.13f, 1f), 2f, 0.7f, 400); break;
                case "skid": ps = Make(key, Alpha, 1.6f, 0.6f, new Color(0.85f, 0.85f, 0.85f, 0.45f), -0.02f, 3.5f, 800); break;
                case "heal": ps = Make(key, Add, 0.8f, 0.18f, new Color(0.4f, 1f, 0.6f), -0.4f, 0.4f, 200); break;
                default: ps = Make(key, Alpha, 1f, 0.3f, Color.white, 0f, 1f, 200); break;
            }
            sys[key] = ps;
            return ps;
        }

        ParticleSystem Make(string name, Material mat, float life, float size, Color c, float gravity, float sizeEnd, int max, bool stretch = false)
        {
            var go = new GameObject("FX_" + name);
            go.transform.SetParent(transform, false);
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = ps.main;
            main.loop = false; main.playOnAwake = false; main.duration = 1f;
            main.startLifetime = life; main.startSize = size; main.startColor = c; main.gravityModifier = gravity;
            main.simulationSpace = ParticleSystemSimulationSpace.World; main.maxParticles = max;
            var em = ps.emission; em.enabled = false;
            var sh = ps.shape; sh.enabled = false;
            var col = ps.colorOverLifetime; col.enabled = true;
            var g = new Gradient();
            g.SetKeys(new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.white, 1f) }, new[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(0.8f, 0.4f), new GradientAlphaKey(0f, 1f) });
            col.color = g;
            var sol = ps.sizeOverLifetime; sol.enabled = true;
            sol.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0f, 1f, 1f, sizeEnd));
            var rot = ps.rotationOverLifetime; rot.enabled = !stretch; rot.z = new ParticleSystem.MinMaxCurve(-1.5f, 1.5f);
            var r = go.GetComponent<ParticleSystemRenderer>();
            r.sharedMaterial = mat;
            r.renderMode = stretch ? ParticleSystemRenderMode.Stretch : ParticleSystemRenderMode.Billboard;
            if (stretch) { r.velocityScale = 0.04f; r.lengthScale = 1f; }
            r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.receiveShadows = false;
            ps.Play();
            return ps;
        }

        static void Emit(string key, Vector3 pos, Vector3 baseVel, float randVel, int count, float sizeMul = 1f, float lifeMul = 1f, Color? color = null)
        {
            var ps = I.Sys(key);
            var main = ps.main;
            var ep = new ParticleSystem.EmitParams();
            for (int i = 0; i < count; i++)
            {
                ep.position = pos + Random.insideUnitSphere * 0.05f * sizeMul;
                ep.velocity = baseVel + Random.insideUnitSphere * randVel;
                ep.startSize = main.startSize.constant * sizeMul * Random.Range(0.7f, 1.3f);
                ep.startLifetime = main.startLifetime.constant * lifeMul * Random.Range(0.7f, 1.3f);
                ep.rotation = Random.Range(0f, 360f);
                if (color.HasValue) ep.startColor = color.Value; else ep.ResetStartColor();
                ps.Emit(ep, 1);
            }
        }

        public static void MuzzleFlash(Vector3 p, Vector3 dir, float scale)
        {
            Emit("muzzle", p + dir * 0.06f, dir * 2f, 0.4f, 3, scale);
            if (scale > 0.5f) Flash(p, new Color(1f, 0.8f, 0.5f), 4f * scale, 6f, 0.05f);
        }

        public static void Impact(Vector3 p, Vector3 n, Surface s)
        {
            switch (s)
            {
                case Surface.Metal: Emit("spark", p, n * 4f, 3.5f, 8); Emit("dust", p, n * 0.5f, 0.3f, 1, 0.5f); break;
                case Surface.Glass: Emit("glass", p, n * 1.5f, 2.2f, 10); AudioFX.PlayAt("glass", p, 0.5f, Random.Range(0.9f, 1.2f)); break;
                case Surface.Wood: Emit("chip", p, n * 2f, 2f, 6); Emit("dust", p, n * 0.6f, 0.3f, 2, 0.6f, 1f, new Color(0.6f, 0.5f, 0.38f, 0.7f)); break;
                case Surface.Flesh: Emit("flesh", p, n * 0.8f, 0.7f, 5); break;
                case Surface.Dirt: Emit("dust", p, n * 1.2f, 0.6f, 4, 0.9f, 1f, new Color(0.62f, 0.55f, 0.42f, 0.8f)); break;
                case Surface.Water: Splash(p, 0.3f); break;
                default: Emit("dust", p, n * 1.0f, 0.5f, 4, 0.8f); Emit("spark", p, n * 2f, 2f, 2, 0.6f); break;
            }
            if (s != Surface.Flesh && Random.value < 0.4f) AudioFX.PlayAt(s == Surface.Metal ? "hit_metal" : "ricochet", p, 0.35f, Random.Range(0.85f, 1.3f));
        }

        public static void Splash(Vector3 p, float size)
        {
            Emit("splash", p, Vector3.up * (3f + size * 3f), 1.6f + size, Mathf.RoundToInt(10 + size * 18), 0.6f + size);
        }

        public static void Sparks(Vector3 p, Vector3 dir, int n) => Emit("spark", p, dir * 3f, 3f, n);
        public static void Smoke(Vector3 p, float size) => Emit("smoke", p, Vector3.up * 1.2f, 0.5f, 1, size);
        public static void SkidSmoke(Vector3 p) => Emit("skid", p, Vector3.up * 0.4f, 0.6f, 1);
        public static void Heal(Vector3 p) => Emit("heal", p, Vector3.up * 1.2f, 0.8f, 14);
        public static void Dust(Vector3 p, float size, Color c) => Emit("dust", p, Vector3.up * 0.6f, 1.2f * size, 2, size, 1f, c);

        public static void Explosion(Vector3 p, float radius)
        {
            float k = radius / 7f;
            Emit("fireball", p, Vector3.up * 1.5f, 5f * k, 26, k);
            Emit("smoke", p + Vector3.up * 0.5f, Vector3.up * 2.5f, 2.5f * k, 18, k * 1.3f, 1.4f);
            Emit("spark", p, Vector3.up * 4f, 11f * k, 40, 1.5f);
            Emit("debris", p, Vector3.up * 6f, 8f * k, 24, 1f);
            Flash(p + Vector3.up, new Color(1f, 0.62f, 0.3f), 60f * k, radius * 4f, 0.45f);
            if (p.y < Water.Level + 1.5f && Water.IsWater(p)) Splash(p, 2.5f);
        }

        public static void Flash(Vector3 p, Color c, float intensity, float range, float duration)
        {
            var i = I;
            Light l = null; int idx = -1;
            for (int k = 0; k < i.lights.Count; k++) if (!i.lights[k].enabled) { l = i.lights[k]; idx = k; break; }
            if (l == null)
            {
                if (i.lights.Count >= 12) { idx = 0; l = i.lights[0]; }
                else
                {
                    l = new GameObject("FlashLight").AddComponent<Light>(); l.transform.SetParent(i.transform); l.type = LightType.Point; l.shadows = LightShadows.None;
                    i.lights.Add(l); i.lightEnd.Add(0); i.lightStart.Add(0); i.lightPeak.Add(0); idx = i.lights.Count - 1;
                }
            }
            l.transform.position = p; l.color = c; l.range = range; l.intensity = intensity; l.enabled = true;
            i.lightStart[idx] = Time.time; i.lightEnd[idx] = Time.time + duration; i.lightPeak[idx] = intensity;
        }

        public static void Tracer(Vector3 a, Vector3 b)
        {
            var i = I;
            if (GameDatabase.I == null || GameDatabase.I.line == null) return;
            LineRenderer lr = i.tracers.Count > 0 ? i.tracers.Dequeue() : null;
            if (lr == null)
            {
                lr = new GameObject("Tracer").AddComponent<LineRenderer>();
                lr.transform.SetParent(i.transform);
                lr.sharedMaterial = GameDatabase.I.line; lr.positionCount = 2; lr.widthMultiplier = 0.025f;
                lr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off; lr.receiveShadows = false;
                lr.startColor = new Color(1f, 0.9f, 0.6f, 0.9f); lr.endColor = new Color(1f, 0.9f, 0.6f, 0.0f);
            }
            var start = Vector3.Lerp(a, b, 0.15f);
            lr.SetPosition(0, start); lr.SetPosition(1, b); lr.enabled = true;
            i.liveTracers.Add((lr, Time.time + 0.05f));
        }

        public static void BulletHole(Vector3 p, Vector3 n, Transform parent)
        {
            var i = I;
            if (GameDatabase.I == null || GameDatabase.I.decal == null) return;
            if (i.quad == null) i.quad = BuildQuad();
            var t = i.holes[i.holeIdx];
            if (t == null)
            {
                var g = new GameObject("Hole");
                g.AddComponent<MeshFilter>().sharedMesh = i.quad;
                var mr = g.AddComponent<MeshRenderer>(); mr.sharedMaterial = GameDatabase.I.decal; mr.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                t = g.transform; i.holes[i.holeIdx] = t;
            }
            t.SetParent(null);
            t.position = p + n * 0.012f;
            t.rotation = Quaternion.LookRotation(-n) * Quaternion.Euler(0, 0, Random.Range(0f, 360f));
            t.localScale = Vector3.one * Random.Range(0.08f, 0.13f);
            if (parent != null && parent.lossyScale == Vector3.one) t.SetParent(parent, true);
            i.holeIdx = (i.holeIdx + 1) % i.holes.Length;
        }

        /// <summary>Removes all bullet-hole decals (admin menu / performance relief).</summary>
        public static void ClearHolesStatic()
        {
            for (int i = 0; i < I.holes.Length; i++)
            {
                if (I.holes[i] != null) { UnityEngine.Object.Destroy(I.holes[i].gameObject); I.holes[i] = null; }
            }
            I.holeIdx = 0;
        }

        static Mesh BuildQuad()
        {
            var m = new Mesh();
            m.vertices = new[] { new Vector3(-0.5f, -0.5f, 0), new Vector3(0.5f, -0.5f, 0), new Vector3(0.5f, 0.5f, 0), new Vector3(-0.5f, 0.5f, 0) };
            m.uv = new[] { new Vector2(0, 0), new Vector2(1, 0), new Vector2(1, 1), new Vector2(0, 1) };
            m.triangles = new[] { 0, 2, 1, 0, 3, 2 };
            m.RecalculateNormals(); m.RecalculateBounds();
            return m;
        }

        void Update()
        {
            for (int k = 0; k < lights.Count; k++)
            {
                if (!lights[k].enabled) continue;
                float t = Mathf.InverseLerp(lightStart[k], lightEnd[k], Time.time);
                if (t >= 1f) lights[k].enabled = false;
                else lights[k].intensity = lightPeak[k] * (1f - t) * (1f - t);
            }
            for (int k = liveTracers.Count - 1; k >= 0; k--)
            {
                if (Time.time > liveTracers[k].t) { liveTracers[k].lr.enabled = false; tracers.Enqueue(liveTracers[k].lr); liveTracers.RemoveAt(k); }
            }
        }

        // ------------------------------------------------------------- persistent emitters
        public static ParticleSystem Loop(string kind, Transform parent, Vector3 localPos)
        {
            var go = new GameObject("FX_Loop_" + kind);
            go.transform.SetParent(parent, false);
            go.transform.localPosition = localPos;
            var ps = go.AddComponent<ParticleSystem>();
            ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
            var main = ps.main; main.loop = true; main.playOnAwake = true; main.simulationSpace = ParticleSystemSimulationSpace.World;
            var em = ps.emission; var sh = ps.shape; sh.shapeType = ParticleSystemShapeType.Sphere; sh.radius = 0.25f;
            var col = ps.colorOverLifetime; col.enabled = true;
            var g = new Gradient(); var sol = ps.sizeOverLifetime; sol.enabled = true;
            var r = go.GetComponent<ParticleSystemRenderer>(); r.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
            r.sharedMaterial = Alpha;   // never leave a renderer without a material (renders magenta in players)
            switch (kind)
            {
                case "rain":
                    main.startLifetime = 1.1f; main.startColor = new Color(0.78f, 0.84f, 0.95f, 0.45f); main.gravityModifier = 0.6f;
                    em.rateOverTime = 2600f; r.sharedMaterial = Alpha;
                    g.SetKeys(new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.white, 1f) }, new[] { new GradientAlphaKey(0.55f, 0f), new GradientAlphaKey(0.4f, 1f) });
                    sol.enabled = false;
                    break;
                case "fire":
                    main.startLifetime = 0.7f; main.startSize = 0.9f; main.startSpeed = 1.5f; main.startColor = new Color(1f, 0.55f, 0.15f); main.gravityModifier = -0.3f; main.maxParticles = 120;
                    em.rateOverTime = 40f; r.sharedMaterial = Add; sh.radius = 0.4f;
                    g.SetKeys(new[] { new GradientColorKey(new Color(1f, 0.9f, 0.5f), 0f), new GradientColorKey(new Color(1f, 0.3f, 0.05f), 1f) }, new[] { new GradientAlphaKey(1f, 0f), new GradientAlphaKey(0f, 1f) });
                    sol.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0, 1f, 1, 0.2f));
                    var l = new GameObject("FireLight").AddComponent<Light>(); l.transform.SetParent(go.transform, false); l.type = LightType.Point; l.color = new Color(1f, 0.55f, 0.2f); l.range = 9f; l.intensity = 6f; l.shadows = LightShadows.None;
                    go.AddComponent<Flicker>().target = l;
                    break;
                case "smoke":
                    main.startLifetime = 3f; main.startSize = 0.8f; main.startSpeed = 1.2f; main.startColor = new Color(0.25f, 0.25f, 0.26f, 0.6f); main.gravityModifier = -0.05f; main.maxParticles = 160;
                    em.rateOverTime = 12f; r.sharedMaterial = Alpha;
                    g.SetKeys(new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.white, 1f) }, new[] { new GradientAlphaKey(0.8f, 0f), new GradientAlphaKey(0f, 1f) });
                    sol.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0, 1f, 1, 3.5f));
                    break;
                case "trail":
                    main.startLifetime = 1.2f; main.startSize = 0.35f; main.startSpeed = 0.2f; main.startColor = new Color(0.85f, 0.85f, 0.85f, 0.6f); main.maxParticles = 300;
                    em.rateOverTime = 0f; em.rateOverDistance = 8f; r.sharedMaterial = Alpha; sh.radius = 0.05f;
                    g.SetKeys(new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.white, 1f) }, new[] { new GradientAlphaKey(0.7f, 0f), new GradientAlphaKey(0f, 1f) });
                    sol.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0, 1f, 1, 3f));
                    break;
                case "rotordust":
                    main.startLifetime = 1.4f; main.startSize = 1.6f; main.startSpeed = 7f; main.startColor = new Color(0.75f, 0.7f, 0.6f, 0.4f); main.maxParticles = 200;
                    em.rateOverTime = 0f; r.sharedMaterial = Alpha; sh.shapeType = ParticleSystemShapeType.Circle; sh.radius = 3f; sh.rotation = new Vector3(90, 0, 0);
                    g.SetKeys(new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.white, 1f) }, new[] { new GradientAlphaKey(0.6f, 0f), new GradientAlphaKey(0f, 1f) });
                    sol.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0, 1f, 1, 3f));
                    break;
                case "wake":
                    main.startLifetime = 1.5f; main.startSize = 0.8f; main.startSpeed = 1.5f; main.startColor = new Color(0.95f, 0.98f, 1f, 0.7f); main.gravityModifier = 0.4f; main.maxParticles = 250;
                    em.rateOverTime = 0f; r.sharedMaterial = Alpha; sh.radius = 0.4f;
                    g.SetKeys(new[] { new GradientColorKey(Color.white, 0f), new GradientColorKey(Color.white, 1f) }, new[] { new GradientAlphaKey(0.8f, 0f), new GradientAlphaKey(0f, 1f) });
                    sol.size = new ParticleSystem.MinMaxCurve(1f, AnimationCurve.Linear(0, 1f, 1, 2.5f));
                    break;
            }
            col.color = g;
            ps.Play();
            return ps;
        }

        public static ParticleSystem Trail(Transform t, bool rocket)
        {
            var ps = Loop("trail", t, Vector3.zero);
            if (rocket)
            {
                var l = new GameObject("RocketLight").AddComponent<Light>(); l.transform.SetParent(t, false); l.type = LightType.Point; l.color = new Color(1f, 0.6f, 0.3f); l.range = 6f; l.intensity = 5f; l.shadows = LightShadows.None;
            }
            return ps;
        }
    }

    public class Flicker : MonoBehaviour
    {
        public Light target;
        float baseI;
        void Start() { if (target) baseI = target.intensity; }
        void Update() { if (target) target.intensity = baseI * (0.75f + Mathf.PerlinNoise(Time.time * 9f, transform.position.x) * 0.5f); }
    }
}
