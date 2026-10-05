using System.Collections.Generic;
using UnityEngine;

namespace Halcyon
{
    /// <summary>World time of day, sun/moon, fog, ambient and per-weather presets.</summary>
    public class GameTime : MonoBehaviour
    {
        public static GameTime I;
        [Range(0f, 1f)] public float time01 = 0.34f;   // 0 = midnight
        public float dayLength = 24f * 60f;            // real seconds per in-game day
        public static float Time01 => I != null ? I.time01 : 0.34f;
        public static float Hour => Time01 * 24f;
        public static bool IsDark => Hour < 6.2f || Hour > 19.4f;
        public static string Clock => string.Format("{0:00}:{1:00}", Mathf.FloorToInt(Hour), Mathf.FloorToInt((Hour % 1f) * 60f));
        public Light sun, moon;
        public GameObject sky;
        Transform skyRot;
        bool cityLightsOn, cityLightsDirty = true;

        public static void Init(GameObject skyObj)
        {
            var g = new GameObject("[GameTime]");
            I = g.AddComponent<GameTime>();
            I.sky = skyObj;
            if (skyObj != null) I.skyRot = skyObj.transform;
        }

        void Update()
        {
            if (GameManager.Paused) return;
            time01 = Mathf.Repeat(time01 + Time.deltaTime / dayLength * GameManager.TimeScale, 1f);
            ApplySky(true);
        }

        public void SetTime(float hour)
        {
            time01 = Mathf.Repeat(hour / 24f, 1f);
            ApplySky(true);
        }

        public void ApplySky(bool updateLight)
        {
            float sunAngle = (time01 - 0.25f) * 360f; // 0 at 06:00 sunrise in the east
            float elev = Mathf.Sin((time01 - 0.25f) * Mathf.PI * 2f) * 90f;
            float azimuth = 90f + (time01 - 0.25f) * 360f;
            var sunRot = Quaternion.Euler(elev, azimuth, 0f);
            if (updateLight && sun != null)
            {
                sun.transform.rotation = sunRot;
                float day = Mathf.Clamp01(Mathf.Sin((time01 - 0.2f) * Mathf.PI * 2f) * 2.2f);
                sun.intensity = Mathf.Lerp(0f, 1.35f, day) * Weather.SunMul;
                sun.color = Color.Lerp(new Color(1f, 0.62f, 0.38f), Color.white, Mathf.Clamp01(day * 2.4f));
                sun.shadows = day > 0.05f ? LightShadows.Soft : LightShadows.None;
                sun.enabled = day > 0.02f;
            }
            if (updateLight && moon != null)
            {
                float night = 1f - Mathf.Clamp01(Mathf.Sin((time01 - 0.2f) * Mathf.PI * 2f) * 2.2f);
                moon.transform.rotation = Quaternion.Euler(-elev, azimuth + 180f, 0f);
                moon.intensity = night * 0.22f * Weather.MoonMul;
                moon.enabled = night > 0.05f;
            }
            if (skyRot != null) skyRot.rotation = Quaternion.Euler(0f, azimuth + 90f, 0f);
            float dayK = Mathf.Clamp01(Mathf.Sin((time01 - 0.2f) * Mathf.PI * 2f) * 2.2f);
            float nightK = 1f - dayK;
            RenderSettings.ambientIntensity = Mathf.Lerp(0.35f, 1f, dayK) * Weather.AmbientMul;
            RenderSettings.ambientSkyColor = Color.Lerp(new Color(0.08f, 0.1f, 0.18f), new Color(0.62f, 0.72f, 0.86f), dayK) * Weather.AmbientMul;
            RenderSettings.ambientEquatorColor = Color.Lerp(new Color(0.06f, 0.07f, 0.1f), new Color(0.72f, 0.7f, 0.64f), dayK) * Weather.AmbientMul;
            RenderSettings.ambientGroundColor = Color.Lerp(new Color(0.03f, 0.03f, 0.04f), new Color(0.38f, 0.34f, 0.28f), dayK);
            var skyMat = RenderSettings.skybox;
            if (skyMat != null && skyMat.HasProperty("_SunDir"))
            {
                skyMat.SetVector("_SunDir", -(sunRot * Vector3.forward));
                skyMat.SetFloat("_Night", nightK);
                skyMat.SetFloat("_Cloud", Weather.Current == Weather.Kind.Cloudy ? 0.75f : Weather.Current == Weather.Kind.Clear ? 0.25f : 1f);
                skyMat.SetFloat("_Overcast", Weather.Current == Weather.Kind.Rain || Weather.Current == Weather.Kind.Storm || Weather.Current == Weather.Kind.Fog ? 0.85f * Weather.Blend : (Weather.Current == Weather.Kind.Cloudy ? 0.35f : 0f));
            }
            var db = GameDatabase.I;
            if (db != null && db.waterMaterial != null)
            {
                db.waterMaterial.SetFloat("_Night", nightK);
                db.waterMaterial.SetFloat("_Storm", Weather.Current == Weather.Kind.Storm ? 1f : Weather.Current == Weather.Kind.Rain ? 0.4f : 0f);
            }
            bool lightsOn = Hour > 18.6f || Hour < 6.8f || Weather.Visibility < 0.35f;
            if (lightsOn != cityLightsOn || db != null && db.nightMaterials != null && cityLightsDirty)
            {
                cityLightsOn = lightsOn; cityLightsDirty = false;
                if (db != null && db.nightMaterials != null)
                    foreach (var m in db.nightMaterials)
                        if (m != null) m.SetColor("_EmissionColor", m.GetColor("_BaseColor") * (lightsOn ? 2.2f : 0.05f));
                StreetLights.SetOn(lightsOn);
            }
            RenderSettings.fogColor = Color.Lerp(new Color(0.05f, 0.07f, 0.11f), Weather.FogColor, Mathf.Clamp01(Hour / 7f - 0.15f));
            RenderSettings.fogDensity = Weather.FogDensity * (IsDark ? 1.25f : 1f);
        }
    }

    /// <summary>Street/building point lights: on at night, culled to the nearest few for Forward+ performance.</summary>
    public class StreetLights : MonoBehaviour
    {
        static StreetLights inst;
        readonly List<Light> lights = new List<Light>();
        bool on;
        float timer;
        public static void Register(Light l) { if (inst == null) inst = new GameObject("[StreetLights]").AddComponent<StreetLights>(); inst.lights.Add(l); l.enabled = false; }
        public static void SetOn(bool v) { if (inst != null) { inst.on = v; inst.timer = 0f; } }
        void Update()
        {
            timer -= Time.deltaTime;
            if (timer > 0f) return;
            timer = 0.5f;
            var cam = PlayerCamera.I != null ? PlayerCamera.I.transform.position : Vector3.zero;
            int budget = 56;
            foreach (var l in lights)
            {
                if (l == null) continue;
                bool want = on && budget > 0 && (l.transform.position - cam).sqrMagnitude < 150f * 150f;
                if (want) budget--;
                if (l.enabled != want) l.enabled = want;
            }
        }
    }

    /// <summary>Weather states with visual and handling effects.</summary>
    public class Weather : MonoBehaviour
    {
        public enum Kind { Clear, Cloudy, Rain, Fog, Storm }
        public static Kind Current = Kind.Clear;
        public static float Blend = 1f;
        public static float SunMul = 1f, MoonMul = 1f, AmbientMul = 1f, FogDensity = 0.0016f, GripMul = 1f;
        public static Color FogColor = new Color(0.62f, 0.70f, 0.80f);
        public static float Visibility => Mathf.Clamp01(0.0016f / Mathf.Max(FogDensity, 0.0001f));
        static Weather inst;
        ParticleSystem rain, stormRain;
        AudioSource rainSrc, windSrc;
        float nextChange = 90f, targetBlend = 1f;
        static readonly Dictionary<Kind, float[]> Presets = new Dictionary<Kind, float[]>
        {
            { Kind.Clear,  new[] { 1f, 1f, 1f, 0.0014f } },
            { Kind.Cloudy, new[] { 0.65f, 0.8f, 0.85f, 0.0022f } },
            { Kind.Rain,   new[] { 0.4f, 0.6f, 0.7f, 0.0032f } },
            { Kind.Fog,    new[] { 0.35f, 0.5f, 0.6f, 0.0095f } },
            { Kind.Storm,  new[] { 0.22f, 0.4f, 0.55f, 0.0042f } },
        };

        public static void Init()
        {
            var g = new GameObject("[Weather]");
            inst = g.AddComponent<Weather>();
            inst.rain = VFX.Loop("rain", g.transform, Vector3.zero);
            var main = inst.rain.main; main.startSpeed = 26f; main.startSize = 0.06f; main.maxParticles = 4000;
            var sh = inst.rain.shape; sh.shapeType = ParticleSystemShapeType.Box; sh.scale = new Vector3(70f, 1f, 70f); sh.rotation = new Vector3(90f, 0f, 0f);
            var r = inst.rain.GetComponent<ParticleSystemRenderer>(); r.renderMode = ParticleSystemRenderMode.Stretch; r.velocityScale = 0.03f;
            inst.rain.Stop();
            inst.rainSrc = AudioFX.Attach(g, "rain", 0f, true, 400f);
            inst.windSrc = AudioFX.Attach(g, "wind", 0.25f, true, 400f);
            Apply(Kind.Clear, 1f);
        }

        void Update()
        {
            var cam = PlayerCamera.I != null ? PlayerCamera.I.transform : transform;
            rain.transform.position = cam.position + Vector3.up * 26f;
            Blend = Mathf.MoveTowards(Blend, targetBlend, Time.deltaTime * 0.4f);
            Apply(Current, Blend);
            if (GameManager.Paused) return;
            nextChange -= Time.deltaTime * GameManager.TimeScale;
            if (nextChange <= 0f)
            {
                nextChange = Random.Range(150f, 420f);
                Set(RandomWeather());
            }
        }

        static Kind RandomWeather()
        {
            float r = Random.value;
            if (r < 0.42f) return Kind.Clear;
            if (r < 0.68f) return Kind.Cloudy;
            if (r < 0.86f) return Kind.Rain;
            if (r < 0.94f) return Kind.Fog;
            return Kind.Storm;
        }

        public static void Set(Kind k, bool instant = false)
        {
            Current = k;
            inst.targetBlend = 1f;
            if (instant) { Blend = 1f; }
            Apply(k, instant ? 1f : Blend);
            HUD.Notify("Weather: " + k, 1.6f);
            if (k == Kind.Storm) { GameManager.I.StartCoroutine(ThunderRoutine()); }
        }

        static System.Collections.IEnumerator ThunderRoutine()
        {
            while (Current == Kind.Storm)
            {
                yield return new WaitForSeconds(Random.Range(4f, 14f));
                if (Current != Kind.Storm) break;
                if (PlayerCamera.I != null) PlayerCamera.I.AddShake(0.35f);
                VFX.Flash(PlayerCamera.I != null ? PlayerCamera.I.transform.position + PlayerCamera.I.transform.forward * 30f + Vector3.up * 20f : Vector3.up * 20f, new Color(0.85f, 0.9f, 1f), 90f, 200f, 0.35f);
            }
        }

        public static void Apply(Kind k, float blend)
        {
            var p = Presets[k];
            SunMul = Mathf.Lerp(1f, p[0], blend);
            MoonMul = Mathf.Lerp(1f, p[1], blend);
            AmbientMul = Mathf.Lerp(1f, p[2], blend);
            FogDensity = Mathf.Lerp(0.0014f, p[3], blend);
            GripMul = k == Kind.Rain ? Mathf.Lerp(1f, 0.85f, blend) : k == Kind.Storm ? Mathf.Lerp(1f, 0.78f, blend) : 1f;
            FogColor = k == Kind.Rain ? new Color(0.5f, 0.55f, 0.6f) : k == Kind.Storm ? new Color(0.3f, 0.33f, 0.38f) : k == Kind.Fog ? new Color(0.72f, 0.75f, 0.78f) : new Color(0.66f, 0.74f, 0.83f);
            if (inst == null) return;
            bool wet = (k == Kind.Rain || k == Kind.Storm) && blend > 0.5f;
            if (inst.rain != null)
            {
                var em = inst.rain.emission; em.rateOverTime = wet ? (k == Kind.Storm ? 3200f : 1800f) : 0f;
                if (wet && !inst.rain.isPlaying) inst.rain.Play();
                if (!wet && inst.rain.isPlaying) inst.rain.Stop(true, ParticleSystemStopBehavior.StopEmitting);
            }
            if (inst.rainSrc != null) inst.rainSrc.volume = wet ? (k == Kind.Storm ? 0.5f : 0.32f) * AudioFX.Sfx * AudioFX.Master : 0f;
            if (inst.windSrc != null) inst.windSrc.volume = (k == Kind.Storm ? 0.6f : k == Kind.Rain ? 0.3f : 0.16f) * AudioFX.Sfx * AudioFX.Master;
            if (GameTime.I != null) GameTime.I.ApplySky(true);
        }
    }

    /// <summary>Sea level plane and water queries.</summary>
    public static class Water
    {
        public const float Level = 0f;
        /// <summary>The island is surrounded by sea and nothing on land is below sea level, so anything below it is water.</summary>
        public static bool IsWater(Vector3 p) => p.y < Level + 0.05f;
    }

    /// <summary>Global manager: pause, time scale, frame stats and the boot sequence.</summary>
    public class GameManager : MonoBehaviour
    {
        public static GameManager I;
        public static bool Paused;
        public static float TimeScale = 1f;
        public static float Fps;
        float fpsAcc; int fpsFrames;

        void Awake()
        {
            I = this;
            DontDestroyOnLoad(gameObject);
        }

        void Update()
        {
            fpsAcc += Time.unscaledDeltaTime; fpsFrames++;
            if (fpsAcc >= 0.5f) { Fps = fpsFrames / fpsAcc; fpsAcc = 0; fpsFrames = 0; }
            if (GameInput.DownRaw(UnityEngine.InputSystem.Key.Escape))
            {
                if (ShopUI.Open) ShopUI.Close();
                else if (ModShop.Open) ModShop.Close();
                else if (Phone.Open) Phone.Close();
                else if (MapScreen.IsOpen) MapScreen.Close();
                else if (AdminMenu.Open) AdminMenu.Toggle();
                else if (WeaponWheel.Open) WeaponWheel.Close();
                else if (PauseMenu.IsOpen) PauseMenu.Close();
                else PauseMenu.Open();
            }
            if (GameInput.DownRaw(UnityEngine.InputSystem.Key.F1)) AdminMenu.Toggle();
            if (GameInput.DownRaw(UnityEngine.InputSystem.Key.Tab))
            {
                if (WeaponWheel.Open) WeaponWheel.Close(); else if (!PauseMenu.IsOpen && !AdminMenu.Open && !ShopUI.Open && !ModShop.Open && !Phone.Open && !MapScreen.IsOpen) WeaponWheel.OpenWheel();
            }
            Paused = PauseMenu.IsOpen || AdminMenu.Open;
            Time.timeScale = Paused || WeaponWheel.Open ? Mathf.Lerp(Time.timeScale, WeaponWheel.Open ? 0.22f : 0f, Time.unscaledDeltaTime * 14f) : Mathf.Lerp(Time.timeScale, TimeScale, Time.unscaledDeltaTime * 10f);
            AudioListener.pause = Paused;
            if (GameInput.DownRaw(UnityEngine.InputSystem.Key.F5)) SaveSystem.Save();
            if (GameInput.DownRaw(UnityEngine.InputSystem.Key.F9)) SaveSystem.Load();
        }
    }
}
