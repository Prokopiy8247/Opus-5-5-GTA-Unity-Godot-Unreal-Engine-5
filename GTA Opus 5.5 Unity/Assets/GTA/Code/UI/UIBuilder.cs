using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace Halcyon
{
    /// <summary>Minimal immediate-mode-ish runtime UI toolkit built on uGUI (no prefabs, no Inspector wiring).</summary>
    public static class UIBuilder
    {
        static Font font;
        public static Font F
        {
            get
            {
                if (font == null) font = Font.CreateDynamicFontFromOSFont(new[] { "Segoe UI", "Arial", "Helvetica" }, 16);
                return font;
            }
        }

        public static RectTransform Panel(Transform parent, Vector2 anchorMin, Vector2 anchorMax, Vector2 offsetMin, Vector2 offsetMax, Color bg)
        {
            var go = new GameObject("panel", typeof(RectTransform));
            var rt = go.GetComponent<RectTransform>();
            rt.SetParent(parent, false);
            rt.anchorMin = anchorMin; rt.anchorMax = anchorMax; rt.offsetMin = offsetMin; rt.offsetMax = offsetMax;
            var img = go.AddComponent<Image>();
            img.color = bg;
            return rt;
        }

        public static RectTransform Column(Transform parent, float x, float y, float w, float h, Vector2 pivot = default)
        {
            var go = new GameObject("col", typeof(RectTransform));
            var rt = go.GetComponent<RectTransform>();
            rt.SetParent(parent, false);
            rt.anchorMin = rt.anchorMax = pivot == default ? new Vector2(0f, 1f) : pivot;
            rt.pivot = rt.anchorMin;
            rt.anchoredPosition = new Vector2(x, -y);
            rt.sizeDelta = new Vector2(w, h);
            var v = go.AddComponent<VerticalLayoutGroup>();
            v.childControlHeight = false; v.childControlWidth = false; v.childForceExpandHeight = false; v.childForceExpandWidth = false;
            v.spacing = 6f; v.padding = new RectOffset(10, 10, 10, 10);
            return rt;
        }

        public static Text Label(Transform parent, string text, int size, Color c, TextAnchor anchor = TextAnchor.MiddleLeft, float width = 400f, float height = 26f)
        {
            var go = new GameObject("label", typeof(RectTransform));
            var rt = go.GetComponent<RectTransform>();
            rt.SetParent(parent, false);
            rt.sizeDelta = new Vector2(width, height);
            var t = go.AddComponent<Text>();
            t.font = F; t.fontSize = size; t.text = text; t.color = c; t.alignment = anchor;
            t.horizontalOverflow = HorizontalWrapMode.Wrap; t.verticalOverflow = VerticalWrapMode.Overflow;
            var le = go.AddComponent<LayoutElement>(); le.minHeight = height; le.preferredWidth = width;
            return t;
        }

        public static Button Btn(Transform parent, string text, Action onClick, float w = 320f, float h = 34f, Color? tint = null)
        {
            var go = new GameObject("btn", typeof(RectTransform));
            var rt = go.GetComponent<RectTransform>();
            rt.SetParent(parent, false);
            rt.sizeDelta = new Vector2(w, h);
            var img = go.AddComponent<Image>();
            img.color = tint ?? new Color(0.13f, 0.16f, 0.2f, 0.96f);
            var b = go.AddComponent<Button>();
            var cb = b.colors;
            cb.normalColor = Color.white; cb.highlightedColor = new Color(1.25f, 1.25f, 1.25f); cb.pressedColor = new Color(0.7f, 0.9f, 1f);
            cb.fadeDuration = 0.05f;
            b.colors = cb;
            b.onClick.AddListener(() => { AudioFX.Play("ui", 0.3f); onClick?.Invoke(); });
            var t = Label(rt, text, 20, Color.white, TextAnchor.MiddleCenter, w - 12f, h);
            t.alignment = TextAnchor.MiddleCenter;
            var le = go.AddComponent<LayoutElement>(); le.minHeight = h; le.preferredWidth = w;
            return b;
        }

        public static Slider Slider(Transform parent, float min, float max, float val, Action<float> onChange, float w = 300f)
        {
            var go = new GameObject("slider", typeof(RectTransform));
            var rt = go.GetComponent<RectTransform>();
            rt.SetParent(parent, false);
            rt.sizeDelta = new Vector2(w, 26f);
            var s = go.AddComponent<Slider>();
            var bg = new GameObject("bg", typeof(RectTransform)).GetComponent<RectTransform>();
            bg.SetParent(rt, false); bg.anchorMin = new Vector2(0f, 0.35f); bg.anchorMax = new Vector2(1f, 0.65f); bg.offsetMin = Vector2.zero; bg.offsetMax = Vector2.zero;
            bg.gameObject.AddComponent<Image>().color = new Color(0.1f, 0.1f, 0.12f, 0.9f);
            var fillArea = new GameObject("fa", typeof(RectTransform)).GetComponent<RectTransform>();
            fillArea.SetParent(rt, false); fillArea.anchorMin = new Vector2(0f, 0.35f); fillArea.anchorMax = new Vector2(1f, 0.65f); fillArea.offsetMin = Vector2.zero; fillArea.offsetMax = Vector2.zero;
            var fill = new GameObject("fill", typeof(RectTransform)).GetComponent<RectTransform>();
            fill.SetParent(fillArea, false); fill.anchorMin = Vector2.zero; fill.anchorMax = Vector2.one; fill.offsetMin = Vector2.zero; fill.offsetMax = Vector2.zero;
            fill.gameObject.AddComponent<Image>().color = new Color(0.25f, 0.6f, 0.7f);
            var handleArea = new GameObject("ha", typeof(RectTransform)).GetComponent<RectTransform>();
            handleArea.SetParent(rt, false); handleArea.anchorMin = Vector2.zero; handleArea.anchorMax = Vector2.one; handleArea.offsetMin = Vector2.zero; handleArea.offsetMax = Vector2.zero;
            var handle = new GameObject("handle", typeof(RectTransform)).GetComponent<RectTransform>();
            handle.SetParent(handleArea, false); handle.sizeDelta = new Vector2(14f, 22f);
            handle.gameObject.AddComponent<Image>().color = new Color(0.85f, 0.9f, 0.95f);
            s.fillRect = fill; s.handleRect = handle; s.targetGraphic = handle.GetComponent<Image>();
            s.minValue = min; s.maxValue = max; s.value = val;
            s.onValueChanged.AddListener(v => onChange?.Invoke(v));
            var le = go.AddComponent<LayoutElement>(); le.minHeight = 26f; le.preferredWidth = w;
            return s;
        }

        public static Canvas Root(string name, int order)
        {
            var go = new GameObject(name);
            var c = go.AddComponent<Canvas>();
            c.renderMode = RenderMode.ScreenSpaceOverlay;
            c.sortingOrder = order;
            var sc = go.AddComponent<CanvasScaler>();
            sc.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            sc.referenceResolution = new Vector2(1920, 1080);
            sc.matchWidthOrHeight = 0.5f;
            go.AddComponent<GraphicRaycaster>();
            return c;
        }
    }

    /// <summary>Tabbed list menu used by the pause screen, shops and the admin menu.</summary>
    public class ListMenu
    {
        public GameObject root;
        public RectTransform content;
        public readonly List<Button> buttons = new List<Button>();
        RectTransform listRT;
        float y;
        public readonly List<(string tab, Action build)> tabs = new List<(string, Action)>();
        public int activeTab;

        public ListMenu(Transform parent, string title, Vector2 size, Vector2 pos, int order = 0)
        {
            var panel = UIBuilder.Panel(parent, new Vector2(0.5f, 0.5f), new Vector2(0.5f, 0.5f), Vector2.zero, Vector2.zero, new Color(0.05f, 0.06f, 0.08f, 0.97f));
            panel.GetComponent<RectTransform>().sizeDelta = size;
            panel.GetComponent<RectTransform>().anchoredPosition = pos;
            root = panel.gameObject;
            var t = UIBuilder.Label(panel, title, 30, new Color(1f, 0.9f, 0.6f), TextAnchor.UpperLeft, size.x - 40f, 40f);
            t.rectTransform.anchoredPosition = new Vector2(20f, -12f);
            var tabsRow = UIBuilder.Column(panel, 12f, 54f, size.x - 24f, 40f);
            tabsRow.GetComponent<VerticalLayoutGroup>().enabled = false;
            tabsRow.gameObject.name = "tabs";
            var scrollGO = new GameObject("scroll", typeof(RectTransform));
            var srt = scrollGO.GetComponent<RectTransform>();
            srt.SetParent(panel, false);
            srt.anchorMin = new Vector2(0f, 0f); srt.anchorMax = new Vector2(1f, 1f);
            srt.offsetMin = new Vector2(8f, 8f); srt.offsetMax = new Vector2(-8f, -100f);
            var sr = scrollGO.AddComponent<ScrollRect>();
            var vp = new GameObject("vp", typeof(RectTransform)).GetComponent<RectTransform>();
            vp.SetParent(srt, false); vp.anchorMin = Vector2.zero; vp.anchorMax = Vector2.one; vp.offsetMin = Vector2.zero; vp.offsetMax = Vector2.zero;
            vp.gameObject.AddComponent<Image>().color = new Color(0f, 0f, 0f, 0.01f);
            vp.gameObject.AddComponent<Mask>().showMaskGraphic = false;
            content = new GameObject("content", typeof(RectTransform)).GetComponent<RectTransform>();
            content.SetParent(vp, false);
            content.anchorMin = new Vector2(0f, 1f); content.anchorMax = new Vector2(1f, 1f); content.pivot = new Vector2(0.5f, 1f);
            content.sizeDelta = new Vector2(0f, 0f);
            var vl = content.gameObject.AddComponent<VerticalLayoutGroup>();
            vl.childControlHeight = false; vl.childControlWidth = false; vl.childForceExpandHeight = false; vl.childForceExpandWidth = false;
            vl.spacing = 4f; vl.padding = new RectOffset(6, 6, 6, 6);
            var fitter = content.gameObject.AddComponent<ContentSizeFitter>();
            fitter.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            sr.content = content; sr.viewport = vp; sr.horizontal = false; sr.vertical = true; sr.scrollSensitivity = 40f;
            sr.movementType = ScrollRect.MovementType.Clamped;
            listRT = tabsRow;
        }

        public void AddTab(string tab, Action build)
        {
            int idx = tabs.Count;
            var b = UIBuilder.Btn(listRT, tab, () => SelectTab(idx), 170f, 32f);
            b.GetComponent<RectTransform>().anchorMin = b.GetComponent<RectTransform>().anchorMax = new Vector2(0f, 1f);
            b.GetComponent<RectTransform>().pivot = new Vector2(0f, 1f);
            b.GetComponent<RectTransform>().anchoredPosition = new Vector2(4f + idx * 176f, -4f);
            tabs.Add((tab, build));
        }

        public void SelectTab(int idx)
        {
            activeTab = idx;
            Clear();
            tabs[idx].build?.Invoke();
        }

        public void Clear()
        {
            // headers, sliders and labels are children of the content rect too, not only the tracked buttons
            for (int i = content.childCount - 1; i >= 0; i--)
            {
                var ch = content.GetChild(i).gameObject;
                ch.SetActive(false);
                UnityEngine.Object.Destroy(ch);
            }
            buttons.Clear();
            y = 0f;
        }

        public void Row(string text, Action onClick, Color? tint = null)
        {
            var b = UIBuilder.Btn(content, text, onClick, 0f, 30f, tint);
            var le = b.GetComponent<LayoutElement>();
            le.preferredWidth = 900f;
            var img = b.GetComponent<Image>();
            b.GetComponent<RectTransform>().sizeDelta = new Vector2(900f, 30f);
            var t = b.GetComponentInChildren<Text>();
            t.alignment = TextAnchor.MiddleLeft;
            t.rectTransform.anchorMin = new Vector2(0f, 0f); t.rectTransform.anchorMax = new Vector2(1f, 1f);
            t.rectTransform.offsetMin = new Vector2(12f, 0f); t.rectTransform.offsetMax = new Vector2(-12f, 0f);
            buttons.Add(b);
            y += 34f;
            var v = content.sizeDelta; v.y = y + 20f; content.sizeDelta = v;
        }

        public void RowButtonGrid(string[] labels, Action<int> onClick, int perRow = 4)
        {
            for (int i = 0; i < labels.Length; i += perRow)
            {
                var row = new GameObject("row", typeof(RectTransform));
                var rt = row.GetComponent<RectTransform>();
                rt.SetParent(content, false);
                rt.sizeDelta = new Vector2(900f, 32f);
                var hl = row.AddComponent<HorizontalLayoutGroup>();
                hl.spacing = 4f; hl.childForceExpandWidth = false; hl.childControlWidth = false; hl.childControlHeight = false; hl.childAlignment = TextAnchor.MiddleLeft;
                var le = row.AddComponent<LayoutElement>(); le.minHeight = 32f; le.preferredWidth = 900f;
                for (int k = 0; k < perRow && i + k < labels.Length; k++)
                {
                    int idx = i + k;
                    var b = UIBuilder.Btn(rt, labels[idx], () => onClick(idx), 220f, 30f);
                    buttons.Add(b);
                }
                y += 34f;
            }
        }

        public void Header(string text)
        {
            var t = UIBuilder.Label(content, text, 22, new Color(0.6f, 0.85f, 0.95f), TextAnchor.MiddleLeft, 900f, 30f);
            buttons.Add(null);
            y += 32f;
        }

        public void SliderRow(string label, float min, float max, float val, Action<float> onChange, Func<string> display)
        {
            var row = new GameObject("srow", typeof(RectTransform));
            var rt = row.GetComponent<RectTransform>();
            rt.SetParent(content, false);
            rt.sizeDelta = new Vector2(900f, 30f);
            var le = row.AddComponent<LayoutElement>(); le.minHeight = 30f; le.preferredWidth = 900f;
            var t = UIBuilder.Label(rt, label, 19, Color.white, TextAnchor.MiddleLeft, 300f, 28f);
            t.rectTransform.anchorMin = new Vector2(0f, 0f); t.rectTransform.anchorMax = new Vector2(0f, 1f); t.rectTransform.pivot = new Vector2(0f, 0.5f);
            t.rectTransform.anchoredPosition = new Vector2(8f, 0f);
            var s = UIBuilder.Slider(rt, min, max, val, onChange, 380f);
            s.GetComponent<RectTransform>().anchorMin = new Vector2(0f, 0.5f); s.GetComponent<RectTransform>().anchorMax = new Vector2(0f, 0.5f);
            s.GetComponent<RectTransform>().pivot = new Vector2(0f, 0.5f);
            s.GetComponent<RectTransform>().anchoredPosition = new Vector2(320f, 0f);
            var disp = UIBuilder.Label(rt, display != null ? display() : val.ToString("F2"), 18, new Color(0.8f, 0.9f, 1f), TextAnchor.MiddleRight, 180f, 28f);
            disp.rectTransform.anchorMin = new Vector2(0f, 0f); disp.rectTransform.anchorMax = new Vector2(0f, 1f); disp.rectTransform.pivot = new Vector2(0f, 0.5f);
            disp.rectTransform.anchoredPosition = new Vector2(710f, 0f);
            if (display != null) s.onValueChanged.AddListener(_ => disp.text = display());
            buttons.Add(null);
            y += 34f;
        }
    }
}
