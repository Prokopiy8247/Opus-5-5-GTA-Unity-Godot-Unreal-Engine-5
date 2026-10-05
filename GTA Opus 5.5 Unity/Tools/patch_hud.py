"""One-off source patch (segment 5): HUD crosshair, minimap player arrow/police/POI blips, FPS/coords readout."""
import os
ROOT = os.path.join(os.path.dirname(__file__), "..", "Assets", "GTA", "Code")


def edit(rel, pairs):
    p = os.path.join(ROOT, rel)
    s = open(p, encoding="utf-8").read()
    for old, new in pairs:
        assert s.count(old) == 1, (rel, old[:90], s.count(old))
        s = s.replace(old, new)
    open(p, "w", encoding="utf-8").write(s)


edit("UI/HUD.cs", [
("""        Image hitMarker;
        float notifyUntil, hitMarkerUntil;""",
 """        Image hitMarker, playerArrow, waypointDot;
        RectTransform crosshair, minimapRect;
        Text perfText;
        readonly List<Image> poiDots = new List<Image>();
        float notifyUntil, hitMarkerUntil;"""),
("""            var mask = mm.gameObject.AddComponent<Mask>();
            mask.showMaskGraphic = true;""",
 """            var mask = mm.gameObject.AddComponent<Mask>();
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
            var prt = perfText.rectTransform; prt.anchorMin = prt.anchorMax = new Vector2(0.5f, 1f); prt.pivot = new Vector2(0.5f, 1f);"""),
("""            // --- police blips
            for (int i = 0; i < 14; i++)
            {
                var b = Panel(transform, Vector2.zero, new Vector2(9f, 9f), new Vector2(0.5f, 0.5f), new Color(0.35f, 0.55f, 1f, 0.95f));""",
 """            // --- police blips (children of the minimap, positioned relative to its centre)
            for (int i = 0; i < 14; i++)
            {
                var b = Panel(minimapRect, Vector2.zero, new Vector2(10f, 10f), new Vector2(0.5f, 0.5f), new Color(0.35f, 0.55f, 1f, 0.95f));"""),
("""            hitMarker.color = new Color(hitMarker.color.r, hitMarker.color.g, hitMarker.color.b, Mathf.MoveTowards(hitMarker.color.a, 0f, Time.unscaledDeltaTime * 4f));
            UpdateMinimap(pc);""",
 """            hitMarker.color = new Color(hitMarker.color.r, hitMarker.color.g, hitMarker.color.b, Mathf.MoveTowards(hitMarker.color.a, 0f, Time.unscaledDeltaTime * 4f));
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
            UpdateMinimap(pc);"""),
("""                    dot.rectTransform.anchoredPosition = vp;""",
 """                    dot.rectTransform.anchoredPosition = Vector2.ClampMagnitude(vp, 142f);"""),
("""            // on-foot prompt
            if (!pc.actor.InVehicle && pc.state == MoveState.Ground)""",
 """            playerArrow.rectTransform.localRotation = Quaternion.Euler(0f, 0f, -(pc.actor.InVehicle && pc.actor.vehicle != null ? pc.actor.vehicle.transform.eulerAngles.y : pc.transform.eulerAngles.y));
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
            if (pc.actor.InVehicle) return;   // on-foot prompts only
            // on-foot prompt
            if (!pc.actor.InVehicle && pc.state == MoveState.Ground)"""),
("""    public static class PolySprite
    {
        static Sprite star;""",
 """    public static class PolySprite
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
        }"""),
])
print("patched hud")
