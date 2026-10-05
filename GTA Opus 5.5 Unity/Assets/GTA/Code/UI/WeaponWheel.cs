using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace Halcyon
{
    /// <summary>Radial weapon selector (Tab): class-organised, slows time while open, mouse or keyboard driven.</summary>
    public class WeaponWheel : MonoBehaviour
    {
        public static WeaponWheel I;
        public static bool Open { get; private set; }
        Canvas canvas;
        readonly List<Slot> slots = new List<Slot>();
        Text title, ammoLabel;
        int hover = -1;
        class Slot { public int classIndex; public string weaponId; public Image img; public Image ring; public Text label; }

        public static void Init()
        {
            var go = new GameObject("[WeaponWheel]");
            I = go.AddComponent<WeaponWheel>();
            I.Build();
            go.SetActive(false);
        }

        void Build()
        {
            canvas = gameObject.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 150;
            var scaler = gameObject.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920, 1080);
            var font = Font.CreateDynamicFontFromOSFont(new[] { "Segoe UI", "Arial" }, 16);
            var bg = new GameObject("dim", typeof(RectTransform)).GetComponent<RectTransform>();
            bg.SetParent(transform, false);
            bg.anchorMin = Vector2.zero; bg.anchorMax = Vector2.one; bg.offsetMin = Vector2.zero; bg.offsetMax = Vector2.zero;
            var bgi = bg.gameObject.AddComponent<Image>(); bgi.color = new Color(0f, 0f, 0f, 0.55f);
            for (int c = 0; c < WeaponController.SlotClasses.Length; c++)
            {
                int idx = c;
                var rt = MakeRT(transform, new Vector2(0f, 0f), new Vector2(190f, 120f));
                rt.anchorMin = rt.anchorMax = new Vector2(0.5f, 0.5f);
                float ang = -(c / (float)WeaponController.SlotClasses.Length) * Mathf.PI * 2f - Mathf.PI * 0.5f;
                rt.anchoredPosition = new Vector2(Mathf.Cos(ang), Mathf.Sin(ang)) * 230f;
                var panel = rt.gameObject.AddComponent<Image>(); panel.color = new Color(0.1f, 0.12f, 0.16f, 0.85f);
                var lbl = MakeText(rt, Vector2.zero, new Vector2(180f, 100f), WhichName(WeaponController.SlotClasses[c]), 22, font);
                var sub = MakeText(rt, new Vector2(0f, -34f), new Vector2(180f, 30f), "empty", 18, font);
                sub.color = new Color(0.7f, 0.75f, 0.8f);
                var s = new Slot { classIndex = c, img = panel, label = sub };
                slots.Add(s);
            }
            title = MakeText(transform, new Vector2(0f, -240f), new Vector2(600f, 40f), "", 30, font);
            title.alignment = TextAnchor.MiddleCenter;
            ammoLabel = MakeText(transform, new Vector2(0f, -280f), new Vector2(600f, 30f), "", 22, font);
            ammoLabel.alignment = TextAnchor.MiddleCenter;
        }

        static string WhichName(WeaponClass c)
        {
            switch (c)
            {
                case WeaponClass.Melee: return "MELEE";
                case WeaponClass.Pistol: return "PISTOL";
                case WeaponClass.SMG: return "SMG";
                case WeaponClass.Shotgun: return "SHOTGUN";
                case WeaponClass.Rifle: return "RIFLE";
                case WeaponClass.Sniper: return "SNIPER";
                case WeaponClass.Heavy: return "HEAVY";
                default: return "THROWN";
            }
        }

        static RectTransform MakeRT(Transform parent, Vector2 pos, Vector2 size)
        {
            var go = new GameObject("rt", typeof(RectTransform));
            var rt = go.GetComponent<RectTransform>();
            rt.SetParent(parent, false);
            rt.anchorMin = rt.anchorMax = new Vector2(0.5f, 0.5f);
            rt.pivot = new Vector2(0.5f, 0.5f);
            rt.anchoredPosition = pos; rt.sizeDelta = size;
            return rt;
        }

        static Text MakeText(Transform parent, Vector2 pos, Vector2 size, string txt, int sz, Font f)
        {
            var rt = MakeRT(parent, pos, size);
            var t = rt.gameObject.AddComponent<Text>();
            t.font = f; t.fontSize = sz; t.text = txt; t.color = Color.white; t.alignment = TextAnchor.MiddleCenter;
            t.horizontalOverflow = HorizontalWrapMode.Overflow;
            var sh = rt.gameObject.AddComponent<Outline>(); sh.effectColor = new Color(0, 0, 0, 0.9f); sh.effectDistance = new Vector2(1f, -1f);
            return t;
        }

        public static void Toggle() { if (Open) Close(); else OpenWheel(); }

        public static void OpenWheel()
        {
            if (I == null || PlayerController.I == null) return;
            Open = true;
            GameInput.UIOpen = true;
            I.gameObject.SetActive(true);
            I.Refresh();
        }

        public static void Close()
        {
            if (I == null || !Open) return;
            if (I.hover >= 0 && I.hover < I.slots.Count) PlayerController.I.weapons.Equip(I.slots[I.hover].weaponId);
            Open = false;
            GameInput.UIOpen = false;
            I.gameObject.SetActive(false);
        }

        void Refresh()
        {
            var wc = PlayerController.I.weapons;
            for (int i = 0; i < slots.Count; i++)
            {
                var s = slots[i];
                var cls = WeaponController.SlotClasses[s.classIndex];
                string found = null;
                foreach (var id in wc.owned)
                {
                    var d = WeaponCatalog.Get(id);
                    if (d != null && d.cls == cls) { found = id; break; }
                }
                s.weaponId = found;
                var def = found != null ? WeaponCatalog.Get(found) : null;
                s.label.text = def != null ? def.name : "empty";
                s.label.color = def != null ? (def.id == wc.currentId ? new Color(1f, 0.85f, 0.4f) : Color.white) : new Color(0.5f, 0.5f, 0.55f);
                s.img.color = def != null ? new Color(0.12f, 0.2f, 0.26f, 0.9f) : new Color(0.08f, 0.09f, 0.11f, 0.6f);
            }
            hover = Mathf.Clamp((int)wc.Current.cls, 0, slots.Count - 1);
            Highlight();
        }

        void Highlight()
        {
            for (int i = 0; i < slots.Count; i++)
                slots[i].img.color = i == hover ? new Color(0.16f, 0.4f, 0.5f, 0.95f) : (slots[i].weaponId != null ? new Color(0.12f, 0.2f, 0.26f, 0.9f) : new Color(0.08f, 0.09f, 0.11f, 0.6f));
            var wc = PlayerController.I.weapons;
            title.text = slots[hover].weaponId != null ? WeaponCatalog.Get(slots[hover].weaponId).name : "empty slot";
            ammoLabel.text = slots[hover].weaponId != null && WeaponCatalog.Get(slots[hover].weaponId).IsGun
                ? "clip " + wc.clip[slots[hover].weaponId] + " / reserve " + wc.reserve[slots[hover].weaponId] : "";
        }

        void Update()
        {
            float scroll = GameInput.Scroll;
            if (Mathf.Abs(scroll) > 0.1f) { hover = (hover + (scroll > 0 ? 1 : -1) + slots.Count) % slots.Count; Highlight(); }
            for (int i = 0; i < 8; i++) if (GameInput.DownRaw(UnityEngine.InputSystem.Key.Digit1 + i)) { hover = i; Highlight(); }
            // mouse aim selects the segment under the cursor
            var mp = new Vector2(GameInput.MousePosition.x, GameInput.MousePosition.y);
            var c = new Vector2(Screen.width * 0.5f, Screen.height * 0.5f);
            var d = (mp - c) / (Screen.height * 0.5f);
            if (d.magnitude > 0.18f)
            {
                float ang = Mathf.Atan2(d.y, d.x) * Mathf.Rad2Deg;
                float k = Mathf.Repeat(-(ang + 90f), 360f) / 360f;
                int idx = Mathf.RoundToInt(k * slots.Count) % slots.Count;
                if (idx != hover) { hover = idx; Highlight(); }
            }
            if (GameInput.MouseLeftDownRaw) Close();
        }
    }

    /// <summary>Full-screen map with waypoint setting and district labels.</summary>
    public class MapScreen : MonoBehaviour
    {
        public static MapScreen I;
        public static bool IsOpen;
        Canvas canvas;
        RectTransform mapRect;
        Image playerArrow, waypoint;
        readonly List<(Image dot, Vector3 pos)> markers = new List<(Image, Vector3)>();
        public static Vector3? Waypoint;
        Text hint;

        public static void Init()
        {
            var go = new GameObject("[MapScreen]");
            I = go.AddComponent<MapScreen>();
            I.Build();
            go.SetActive(false);
        }

        void Build()
        {
            canvas = gameObject.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 140;
            var scaler = gameObject.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920, 1080);
            var font = Font.CreateDynamicFontFromOSFont(new[] { "Segoe UI", "Arial" }, 16);
            var bg = MakeRT(transform, Vector2.zero, new Vector2(1920, 1080));
            var bgi = bg.gameObject.AddComponent<Image>(); bgi.color = new Color(0.02f, 0.03f, 0.05f, 0.94f);
            mapRect = MakeRT(transform, Vector2.zero, new Vector2(860f, 860f));
            var img = mapRect.gameObject.AddComponent<RawImage>();
            img.texture = MapTexture.I != null ? MapTexture.I.map : null;
            playerArrow = Marker(new Vector2(18f, 18f), new Color(1f, 0.9f, 0.3f));
            waypoint = Marker(new Vector2(22f, 22f), new Color(0.4f, 1f, 0.6f));
            waypoint.gameObject.SetActive(false);
            foreach (var (name, pos) in WorldMarkers.Landmarks)
            {
                var m = Marker(new Vector2(12f, 12f), new Color(0.8f, 0.85f, 0.9f, 0.85f));
                var lbl = MakeText(m.transform, new Vector2(0f, -16f), new Vector2(200f, 24f), name, 16, font);
                lbl.alignment = TextAnchor.UpperCenter;
                markers.Add((m, pos));
                m.gameObject.SetActive(true);
            }
            foreach (var d in WorldMarkers.DistrictCentres)
            {
                var m = Marker(new Vector2(9f, 9f), new Color(0.5f, 0.7f, 0.9f, 0.7f));
                markers.Add((m, d));
                m.gameObject.SetActive(true);
            }
            hint = MakeText(transform, new Vector2(0f, -470f), new Vector2(1400f, 60f), "Left click: set waypoint   ·   Right click: clear   ·   M or Esc: close", 22, font);
        }

        Image Marker(Vector2 size, Color c)
        {
            var rt = MakeRT(mapRect, Vector2.zero, size);
            var img = rt.gameObject.AddComponent<Image>();
            img.sprite = PolySprite.Star();
            img.color = c;
            return img;
        }

        static RectTransform MakeRT(Transform p, Vector2 pos, Vector2 size)
        {
            var go = new GameObject("rt", typeof(RectTransform));
            var rt = go.GetComponent<RectTransform>();
            rt.SetParent(p, false);
            rt.anchorMin = rt.anchorMax = new Vector2(0.5f, 0.5f); rt.pivot = new Vector2(0.5f, 0.5f);
            rt.anchoredPosition = pos; rt.sizeDelta = size;
            return rt;
        }

        static Text MakeText(Transform p, Vector2 pos, Vector2 size, string t, int sz, Font f)
        {
            var rt = MakeRT(p, pos, size);
            var tx = rt.gameObject.AddComponent<Text>();
            tx.font = f; tx.fontSize = sz; tx.text = t; tx.color = Color.white; tx.alignment = TextAnchor.MiddleCenter;
            tx.horizontalOverflow = HorizontalWrapMode.Overflow;
            var sh = rt.gameObject.AddComponent<Outline>(); sh.effectColor = new Color(0, 0, 0, 0.9f); sh.effectDistance = new Vector2(1f, -1f);
            return tx;
        }

        public static void Toggle() { if (IsOpen) Close(); else ShowMap(); }

        public static void ShowMap()
        {
            if (I == null) return;
            IsOpen = true; GameInput.UIOpen = true;
            I.gameObject.SetActive(true);
        }

        public static void Close()
        {
            if (I == null) return;
            IsOpen = false; GameInput.UIOpen = false;
            I.gameObject.SetActive(false);
        }

        void Update()
        {
            var pc = PlayerController.I;
            if (pc == null) return;
            var p = pc.transform.position;
            playerArrow.rectTransform.anchoredPosition = MapTexture.I.WorldToFullMap(p, mapRect);
            playerArrow.rectTransform.localRotation = Quaternion.Euler(0f, 0f, -pc.transform.eulerAngles.y);
            foreach (var (dot, pos) in markers) dot.rectTransform.anchoredPosition = MapTexture.I.WorldToFullMap(pos, mapRect);
            if (Waypoint.HasValue)
            {
                waypoint.gameObject.SetActive(true);
                waypoint.rectTransform.anchoredPosition = MapTexture.I.WorldToFullMap(Waypoint.Value, mapRect);
            }
            else waypoint.gameObject.SetActive(false);

            if (GameInput.MouseLeftDownRaw)
            {
                var mp = GameInput.MousePosition;
                if (RectTransformUtility.RectangleContainsScreenPoint(mapRect, mp, null))
                {
                    RectTransformUtility.ScreenPointToLocalPointInRectangle(mapRect, mp, null, out var local);
                    var norm = MapTexture.I.FullMapToWorldNormalized(local, mapRect);
                    Waypoint = MapTexture.I.MapPointToWorld(norm);
                    HUD.Notify("Waypoint set", 1.4f);
                }
            }
            if (GameInput.MouseRightDownRaw) Waypoint = null;
            if (GameInput.DownRaw(UnityEngine.InputSystem.Key.M)) Close();
        }
    }
}
