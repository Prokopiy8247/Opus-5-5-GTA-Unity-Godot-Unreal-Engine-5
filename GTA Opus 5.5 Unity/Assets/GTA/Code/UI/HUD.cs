using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace Halcyon
{
    /// <summary>Runtime-built HUD (uGUI): health/armor, ammo, weapon, wanted stars, cash, clock, minimap, notifications, prompts.</summary>
    public class HUD : MonoBehaviour
    {
        public static HUD I;
        Canvas canvas;
        Image healthFill, armorFill, breatheFill, vehHealthFill;
        Text ammoText, weaponText, moneyText, clockText, speedText, notifyText, promptText, skillText;
        Image[] stars = new Image[5];
        Text starText;
        RawImage minimap;
        RectTransform mapRot;
        Image hitMarker, playerArrow, waypointDot;
        RectTransform crosshair, minimapRect;
        Text perfText;
        readonly List<Image> poiDots = new List<Image>();
        float notifyUntil, hitMarkerUntil;
        readonly List<(Image dot, Transform t)> blips = new List<(Image, Transform)>();
        readonly List<Actor> trackedPeds = new List<Actor>();
        float blipTimer, promptTimer;
        static readonly List<(string label, Vector3 pos, Color c)> blipDefs = new List<(string, Vector3, Color)>();

        public static void Init()
        {
            var go = new GameObject("[HUD]");
            I = go.AddComponent<HUD>();
            I.Build();
        }

        public static void RegisterBlip(string label, Vector3 pos, Color c) => blipDefs.Add((label, pos, c));

        Font font;

        void Build()
        {
            font = Font.CreateDynamicFontFromOSFont(new[] { "Segoe UI", "Arial", "Helvetica" }, 16);
            canvas = gameObject.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 100;
            var scaler = gameObject.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920, 1080);
            scaler.matchWidthOrHeight = 0.5f;
            gameObject.AddComponent<GraphicRaycaster>();

            // --- bottom-left status cluster
            var panel = Panel(transform, new Vector2(24f, 24f), new Vector2(430f, 132f), new Vector2(0f, 0f));
            healthFill = Bar(panel, new Vector2(0f, 92f), new Vector2(320f, 20f), new Color(0.9f, 0.25f, 0.3f));
            armorFill = Bar(panel, new Vector2(0f, 66f), new Vector2(260f, 12f), new Color(0.35f, 0.65f, 1f));
            breatheFill = Bar(panel, new Vector2(0f, 50f), new Vector2(180f, 8f), new Color(0.4f, 0.9f, 1f));
            vehHealthFill = Bar(panel, new Vector2(0f, 34f), new Vector2(240f, 10f), new Color(1f, 0.6f, 0.2f));
            skillText = Label(panel, new Vector2(0f, 8f), new Vector2(420f, 22f), "", 15, TextAnchor.LowerLeft, new Color(0.85f, 0.87f, 0.9f));

            // --- money / clock (top-right)
            var topRight = Panel(transform, new Vector2(-24f, -20f), new Vector2(360f, 96f), new Vector2(1f, 1f));
            moneyText = Label(topRight, new Vector2(0f, 62f), new Vector2(340f, 30f), "$0", 26, TextAnchor.UpperRight, new Color(0.55f, 0.95f, 0.65f));
            clockText = Label(topRight, new Vector2(0f, 30f), new Vector2(340f, 26f), "12:00", 20, TextAnchor.UpperRight, Color.white);

            // --- wanted stars
            var wanted = Panel(transform, new Vector2(-24f, -150f), new Vector2(320f, 46f), new Vector2(1f, 1f));
            for (int i = 0; i < 5; i++) stars[i] = Star(wanted, new Vector2(-i * 40f, 0f));
            starText = Label(wanted, new Vector2(-210f, 0f), new Vector2(180f, 30f), "", 16, TextAnchor.MiddleRight, new Color(1f, 0.85f, 0.4f));

            // --- weapon cluster (bottom-right)
            var wpan = Panel(transform, new Vector2(-24f, 24f), new Vector2(430f, 110f), new Vector2(1f, 0f));
            weaponText = Label(wpan, new Vector2(0f, 74f), new Vector2(410f, 32f), "Fists", 24, TextAnchor.LowerRight, Color.white);
            ammoText = Label(wpan, new Vector2(0f, 8f), new Vector2(410f, 56f), "", 42, TextAnchor.LowerRight, new Color(1f, 0.93f, 0.75f));
            speedText = Label(wpan, new Vector2(0f, 44f), new Vector2(410f, 26f), "", 20, TextAnchor.LowerRight, new Color(0.8f, 0.88f, 1f));

            // --- minimap
            var mm = Panel(transform, new Vector2(24f, -20f), new Vector2(300f, 300f), new Vector2(0f, 1f));
            minimap = mm.gameObject.AddComponent<RawImage>();
            minimap.texture = MapTexture.I != null ? MapTexture.I.map : null;
            minimap.color = Color.white;
            mapRot = minimap.rectTransform;
            var mask = mm.gameObject.AddComponent<Mask>();
            mask.showMaskGraphic = true;
            minimapRect = mm;
            // points of interest + waypoint + player arrow live inside the minimap (offsets from its centre)
            foreach (var (label, pos, c) in blipDefs)
            {
                var pd = Panel(mm, Vector2.zero, new Vector2(11f, 11f), new Vector2(0.5f, 0.5f), Color.clear).GetComponent<Image>();
                pd.color = new Color(c.r, c.g, c.b, 0.95f);
                poiDots.Add(pd);
            }
            waypointDot = Panel(mm, Vector2.zero, new Vector2(14f, 14f), new Vector2(0.5f, 0.5f), Color.clear).GetComponent<Image>();
            waypointDot.color = new Color(1f, 0.85f, 0.2f, 1f);
            waypointDot.gameObject.SetActive(false);
            var arrowRT = Panel(mm, Vector2.zero, new Vector2(22f, 22f), new Vector2(0.5f, 0.5f), null);
            playerArrow = arrowRT.gameObject.AddComponent<Image>();
            playerArrow.sprite = PolySprite.Arrow();
            playerArrow.color = Color.white;
            playerArrow.raycastTarget = false;
            arrowRT.gameObject.AddComponent<Outline>().effectColor = new Color(0f, 0f, 0f, 0.9f);

            // --- crosshair (shown while aiming a gun)
            crosshair = Panel(transform, Vector2.zero, new Vector2(40f, 40f), new Vector2(0.5f, 0.5f), null);
            foreach (var (pos, size) in new[] { (new Vector2(0f, 11f), new Vector2(2f, 9f)), (new Vector2(0f, -11f), new Vector2(2f, 9f)), (new Vector2(11f, 0f), new Vector2(9f, 2f)), (new Vector2(-11f, 0f), new Vector2(9f, 2f)), (Vector2.zero, new Vector2(3f, 3f)) })
            {
                var bar = Panel(crosshair, pos, size, new Vector2(0.5f, 0.5f), Color.clear).GetComponent<Image>();
                bar.color = new Color(1f, 1f, 1f, 0.92f);
                bar.gameObject.AddComponent<Outline>().effectColor = new Color(0f, 0f, 0f, 0.7f);
            }
            crosshair.gameObject.SetActive(false);

            // --- FPS / coordinates readout (admin menu toggles)
            perfText = Label(transform, new Vector2(0f, -14f), new Vector2(600f, 24f), "", 15, TextAnchor.MiddleCenter, new Color(0.85f, 0.9f, 1f, 0.9f));
            var prt = perfText.rectTransform; prt.anchorMin = prt.anchorMax = new Vector2(0.5f, 1f); prt.pivot = new Vector2(0.5f, 1f);

            // --- centre overlays
            notifyText = Label(transform, new Vector2(0f, 250f), new Vector2(1200f, 40f), "", 26, TextAnchor.MiddleCenter, new Color(1f, 0.95f, 0.8f));
            promptText = Label(transform, new Vector2(0f, 150f), new Vector2(900f, 40f), "", 22, TextAnchor.MiddleCenter, Color.white);
            hitMarker = Panel(transform, Vector2.zero, new Vector2(26f, 26f), new Vector2(0.5f, 0.5f), new Color(1f, 1f, 1f, 0f)).GetComponent<Image>();

            // --- police blips (children of the minimap, positioned relative to its centre)
            for (int i = 0; i < 14; i++)
            {
                var b = Panel(minimapRect, Vector2.zero, new Vector2(10f, 10f), new Vector2(0.5f, 0.5f), new Color(0.35f, 0.55f, 1f, 0.95f));
                b.gameObject.SetActive(false);
                blips.Add((b.GetComponent<Image>(), null));
            }
        }

        static RectTransform Panel(Transform parent, Vector2 anchored, Vector2 size, Vector2 pivot, Color? bg = null)
        {
            var go = new GameObject("panel", typeof(RectTransform));
            var rt = go.GetComponent<RectTransform>();
            rt.SetParent(parent, false);
            rt.anchorMin = pivot; rt.anchorMax = pivot; rt.pivot = pivot;
            rt.anchoredPosition = anchored; rt.sizeDelta = size;
            if (bg.HasValue)
            {
                var im = go.AddComponent<Image>();
                im.color = new Color(0f, 0f, 0f, 0f);
            }
            return rt;
        }

        Image Bar(RectTransform parent, Vector2 anchored, Vector2 size, Color c)
        {
            var bgRT = Panel(parent, anchored, size, new Vector2(0f, 0f), new Color(0f, 0f, 0f, 0.55f));
            var fill = new GameObject("fill", typeof(RectTransform)).GetComponent<RectTransform>();
            fill.SetParent(bgRT, false);
            fill.anchorMin = Vector2.zero; fill.anchorMax = new Vector2(1f, 1f);
            fill.offsetMin = new Vector2(2f, 2f); fill.offsetMax = new Vector2(-2f, -2f);
            var img = fill.gameObject.AddComponent<Image>();
            img.color = c;
            img.type = Image.Type.Filled; img.fillMethod = Image.FillMethod.Horizontal; img.fillAmount = 1f;
            return img;
        }

        Image Star(RectTransform parent, Vector2 anchored)
        {
            var rt = Panel(parent, anchored, new Vector2(34f, 34f), new Vector2(1f, 0.5f), null);
            var img = rt.gameObject.AddComponent<Image>();
            img.sprite = PolySprite.Star();
            img.color = new Color(1f, 0.85f, 0.3f, 0.15f);
            img.preserveAspect = true;
            return img;
        }

        Text Label(Transform parent, Vector2 anchored, Vector2 size, string txt, int size2, TextAnchor anchor, Color c)
        {
            var go = new GameObject("label", typeof(RectTransform));
            var rt = go.GetComponent<RectTransform>();
            rt.SetParent(parent, false);
            rt.anchorMin = new Vector2(anchor == TextAnchor.UpperRight || anchor == TextAnchor.LowerRight || anchor == TextAnchor.MiddleRight ? 1f : (anchor == TextAnchor.MiddleCenter ? 0.5f : 0f), anchor == TextAnchor.LowerLeft || anchor == TextAnchor.LowerRight ? 0f : (anchor == TextAnchor.MiddleLeft || anchor == TextAnchor.MiddleRight || anchor == TextAnchor.MiddleCenter ? 0.5f : 1f));
            rt.pivot = new Vector2(anchor == TextAnchor.UpperRight || anchor == TextAnchor.LowerRight || anchor == TextAnchor.MiddleRight ? 1f : (anchor == TextAnchor.MiddleCenter ? 0.5f : 0f), 0.5f);
            rt.anchoredPosition = anchored; rt.sizeDelta = size;
            var t = go.AddComponent<Text>();
            t.font = font; t.fontSize = size2; t.text = txt; t.color = c; t.alignment = anchor;
            t.horizontalOverflow = HorizontalWrapMode.Overflow; t.verticalOverflow = VerticalWrapMode.Overflow;
            t.raycastTarget = false;
            var sh = go.AddComponent<Outline>(); sh.effectColor = new Color(0f, 0f, 0f, 0.8f); sh.effectDistance = new Vector2(1.2f, -1.2f);
            return t;
        }

        // ------------------------------------------------------------- runtime API
        public static void Notify(string msg, float dur = 2.2f)
        {
            if (I == null) return;
            I.notifyText.text = msg;
            I.notifyUntil = Time.unscaledTime + dur;
        }

        public static void Prompt(string msg)
        {
            if (I == null) return;
            I.promptText.text = msg;
            I.promptTimer = 0.3f;
        }

        public static void HitMarker(bool kill)
        {
            if (I == null) return;
            I.hitMarker.color = kill ? new Color(1f, 0.3f, 0.3f, 1f) : new Color(1f, 1f, 1f, 0.95f);
            I.hitMarkerUntil = Time.unscaledTime + (kill ? 0.3f : 0.14f);
        }

        public static void OnWantedChanged()
        {
            if (I == null) return;
            for (int i = 0; i < 5; i++) I.stars[i].color = new Color(1f, 0.85f, 0.3f, i < WantedSystem.Level ? 1f : 0.13f);
        }

        public static void ShowVehicleName(string n) { Notify(n, 1.4f); }

        Image fadeImg; float fadeTarget, fadeSpeed = 2f;
        /// <summary>Full-screen black fade (0 = clear, 1 = black) over 'seconds'.</summary>
        public static void Fade(float target, float seconds)
        {
            if (I == null) return;
            if (I.fadeImg == null)
            {
                var rt = Panel(I.transform, Vector2.zero, Vector2.zero, new Vector2(0.5f, 0.5f), Color.clear);
                rt.anchorMin = Vector2.zero; rt.anchorMax = Vector2.one; rt.offsetMin = Vector2.zero; rt.offsetMax = Vector2.zero;
                I.fadeImg = rt.GetComponent<Image>(); I.fadeImg.raycastTarget = false; I.fadeImg.color = new Color(0f, 0f, 0f, 0f);
            }
            I.fadeTarget = target; I.fadeSpeed = 1f / Mathf.Max(seconds, 0.01f);
        }

        public static void RemoveBlip(NPCBrain b) { }

        readonly List<Vehicle> policeTracked = new List<Vehicle>();

        void Update()
        {
            var pc = PlayerController.I;
            if (pc == null) return;
            var a = pc.actor;
            healthFill.fillAmount = a.health / a.maxHealth;
            armorFill.fillAmount = a.maxArmor > 0f ? a.armor / a.maxArmor : 0f;
            breatheFill.fillAmount = pc.breath;
            breatheFill.transform.parent.gameObject.SetActive(pc.breath < 0.999f);

            var ps = PlayerState.I;
            moneyText.text = U.Money(ps.money);
            clockText.text = GameTime.Clock + "  " + Weather.Current;

            var wd = pc.weapons != null ? pc.weapons.Current : null;
            weaponText.text = wd != null ? wd.name + (pc.weapons.CurrentMods.suppressor && wd.canSuppress ? " [supp]" : "") : "-";
            if (wd == null || wd.IsMelee) ammoText.text = "";
            else if (wd.cls == WeaponClass.Thrown) ammoText.text = (pc.weapons.Clip + pc.weapons.Reserve).ToString();
            else ammoText.text = pc.weapons.Clip + " / " + (pc.weapons.infiniteAmmo ? "inf" : pc.weapons.Reserve.ToString());

            if (a.InVehicle && a.vehicle != null)
            {
                speedText.text = Mathf.RoundToInt(a.vehicle.SpeedKmh) + " km/h   " + a.vehicle.def.name;
                vehHealthFill.transform.parent.gameObject.SetActive(true);
                vehHealthFill.fillAmount = a.vehicle.health / a.vehicle.maxHealth;
            }
            else
            {
                speedText.text = pc.Stealth ? "STEALTH" : (pc.state == MoveState.Swim ? (pc.Underwater ? "DIVING" : "SWIMMING") : (pc.state == MoveState.Parachute ? "PARACHUTE" : (pc.state == MoveState.Cover ? "IN COVER" : "")));
                vehHealthFill.transform.parent.gameObject.SetActive(false);
            }

            // skills readout (F7)
            if (GameInput.HeldRaw(UnityEngine.InputSystem.Key.F7))
            {
                var sb = new System.Text.StringBuilder("SKILLS  ");
                for (int i = 0; i < 7; i++) sb.Append(PlayerState.SkillNames[i].Substring(0, Mathf.Min(4, PlayerState.SkillNames[i].Length))).Append(" ").Append(Mathf.RoundToInt(ps.skills[i] * 100f)).Append("%   ");
                skillText.text = sb.ToString();
            }
            else if (skillText.text.Length > 0 && !GameInput.HeldRaw(UnityEngine.InputSystem.Key.F7)) skillText.text = "";

            starText.text = WantedSystem.Level > 0 ? (WantedSystem.Pursuing ? "PURSUING" : (WantedSystem.SearchProgress > 0.05f ? "SEARCHING " + Mathf.RoundToInt(WantedSystem.SearchProgress * 100f) + "%" : "SEARCHING")) : "";

            if (Time.unscaledTime > notifyUntil) notifyText.text = "";
            promptTimer -= Time.unscaledDeltaTime;
            if (promptTimer <= 0f) promptText.text = "";
            hitMarker.color = new Color(hitMarker.color.r, hitMarker.color.g, hitMarker.color.b, Mathf.MoveTowards(hitMarker.color.a, 0f, Time.unscaledDeltaTime * 4f));
            bool gunAim = (pc.IsAiming || pc.DriveByAiming) && wd != null && !wd.IsMelee && !GameInput.UIOpen;
            if (crosshair.gameObject.activeSelf != gunAim) crosshair.gameObject.SetActive(gunAim);
            if (gunAim)
            {
                // project the actual aim point so the reticle sits where bullets go
                var cam = PlayerCamera.I != null ? PlayerCamera.I.cam : null;
                if (cam != null)
                {
                    var sp = cam.WorldToScreenPoint(pc.AimPoint);
                    if (sp.z > 0f) { var cs = canvas.transform as RectTransform; RectTransformUtility.ScreenPointToLocalPointInRectangle(cs, sp, null, out var lp); crosshair.anchoredPosition = lp; }
                }
            }
            if (AdminMenu.ShowFps || AdminMenu.ShowCoords)
            {
                var p = pc.transform.position;
                perfText.text = (AdminMenu.ShowFps ? "FPS " + Mathf.RoundToInt(GameManager.Fps) + "   " : "") + (AdminMenu.ShowCoords ? string.Format("XYZ {0:F0} {1:F0} {2:F0}   {3}", p.x, p.y, p.z, WorldMarkers.ZoneAt(p)) : "");
            }
            else if (perfText.text.Length > 0) perfText.text = "";
            if (fadeImg != null) { var fc = fadeImg.color; fc.a = Mathf.MoveTowards(fc.a, fadeTarget, Time.unscaledDeltaTime * fadeSpeed); fadeImg.color = fc; }
            UpdateMinimap(pc);
        }

        void UpdateMinimap(PlayerController pc)
        {
            if (minimap == null || MapTexture.I == null) return;
            blipTimer -= Time.deltaTime;
            if (blipTimer <= 0f)
            {
                blipTimer = 0.25f;
                policeTracked.Clear();
                foreach (var v in Vehicle.All)
                    if (!v.IsDestroyed && v.def != null && v.def.police && policeTracked.Count < 14) policeTracked.Add(v);
            }
            mapRot.localRotation = Quaternion.Euler(0f, 0f, 0f);
            minimap.uvRect = MapTexture.I.MinimapUv(pc.transform.position, pc.transform.eulerAngles.y);
            for (int i = 0; i < blips.Count; i++)
            {
                var (dot, _) = blips[i];
                if (i < policeTracked.Count && policeTracked[i] != null)
                {
                    dot.gameObject.SetActive(true);
                    var vp = MapTexture.I.WorldToMinimapLocal(policeTracked[i].transform.position, minimap.transform as RectTransform, pc.transform.position, pc.transform.eulerAngles.y);
                    dot.rectTransform.anchoredPosition = Vector2.ClampMagnitude(vp, 142f);
                    dot.color = WantedSystem.Pursuing ? new Color(1f, 0.3f, 0.3f, 1f) : new Color(0.4f, 0.6f, 1f, 0.9f);
                }
                else dot.gameObject.SetActive(false);
            }
            playerArrow.rectTransform.localRotation = Quaternion.Euler(0f, 0f, -(pc.actor.InVehicle && pc.actor.vehicle != null ? pc.actor.vehicle.transform.eulerAngles.y : pc.transform.eulerAngles.y));
            for (int i = 0; i < poiDots.Count && i < blipDefs.Count; i++)
            {
                var lp = MapTexture.I.WorldToMinimapLocal(blipDefs[i].pos, minimapRect, pc.transform.position, 0f);
                poiDots[i].rectTransform.anchoredPosition = Vector2.ClampMagnitude(lp, 142f);
            }
            if (MapScreen.Waypoint.HasValue)
            {
                waypointDot.gameObject.SetActive(true);
                var wl = MapTexture.I.WorldToMinimapLocal(MapScreen.Waypoint.Value, minimapRect, pc.transform.position, 0f);
                waypointDot.rectTransform.anchoredPosition = Vector2.ClampMagnitude(wl, 142f);
                if (U.FlatDist(MapScreen.Waypoint.Value, pc.transform.position) < 12f) { MapScreen.Waypoint = null; Notify("Waypoint reached", 1.4f); }
            }
            else if (waypointDot.gameObject.activeSelf) waypointDot.gameObject.SetActive(false);
            if (pc.actor.InVehicle)
            {
                if (pc.actor.seat == 0 && GarageApi.NearGarage(pc.transform.position)) Prompt("[E] Store this vehicle in the garage");
                return;   // other prompts are on-foot only
            }
            // on-foot prompt
            if (!pc.actor.InVehicle && pc.state == MoveState.Ground)
            {
                var v = Vehicle.Nearest(pc.transform.position, 5.5f);
                if (v != null && !v.IsDestroyed)
                {
                    bool occupied = v.Driver != null && !v.Driver.IsPlayer;
                    Prompt(occupied ? "[F] Pull the driver out" : "[F] Enter vehicle");
                }
            }
            var lad = Ladder.Nearest(pc.transform.position, 1.6f);
            if (lad != null) Prompt("[E] Climb ladder");
            var it = Interactable.Nearest(pc.transform.position);
            if (it != null) Prompt("[E] " + it.Prompt);
        }
    }

    public static class PolySprite
    {
        static Sprite star, arrow;

        /// <summary>Upward-pointing navigation arrow for the minimap player marker.</summary>
        public static Sprite Arrow()
        {
            if (arrow != null) return arrow;
            var tex = new Texture2D(48, 48, TextureFormat.RGBA32, false);
            var cols = new Color[48 * 48];
            for (int y = 0; y < 48; y++)
                for (int x = 0; x < 48; x++)
                {
                    float px = (x - 23.5f) / 23.5f, py = (y - 23.5f) / 23.5f;   // -1..1, +y = tip
                    float half = (py + 0.95f) / 1.9f * 0.0f + (0.95f - py) * 0.42f;  // narrows toward the tip
                    bool inside = py > -0.95f && py < 0.95f && Mathf.Abs(px) < half && !(py < -0.35f && Mathf.Abs(px) < (-0.35f - py) * 0.9f);
                    cols[y * 48 + x] = inside ? Color.white : new Color(1f, 1f, 1f, 0f);
                }
            tex.SetPixels(cols); tex.Apply();
            arrow = Sprite.Create(tex, new Rect(0, 0, 48, 48), new Vector2(0.5f, 0.5f), 48f);
            return arrow;
        }
        public static Sprite Star()
        {
            if (star != null) return star;
            int n = 10;
            var tex = new Texture2D(64, 64, TextureFormat.RGBA32, false);
            var cols = new Color[64 * 64];
            for (int y = 0; y < 64; y++)
                for (int x = 0; x < 64; x++)
                {
                    float px = (x / 63f - 0.5f) * 2f, py = (y / 63f - 0.5f) * 2f;
                    float ang = Mathf.Atan2(py, px);
                    float r = Mathf.Sqrt(px * px + py * py);
                    float rr = 0.52f + 0.48f * Mathf.Cos(5f * ang);
                    cols[y * 64 + x] = r < rr * 0.95f ? Color.white : new Color(1f, 1f, 1f, 0f);
                }
            tex.SetPixels(cols); tex.Apply();
            star = Sprite.Create(tex, new Rect(0, 0, 64, 64), new Vector2(0.5f, 0.5f), 64f);
            return star;
        }
    }
}
