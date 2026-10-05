class_name WeaponWheel
extends Control
## Radial weapon selector (hold TAB): slows time, 8 class slots, mouse direction picks the slot,
## mouse wheel cycles weapons inside the hovered slot, shows ammo.

var hovered := -1
var slot_choice := {}      # slot -> index into owned list
var _mouse := Vector2.ZERO


func open() -> void:
	visible = true
	Engine.time_scale = 0.25
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(get_viewport_rect().size * 0.5)
	Game.ui_open += 1
	Audio.play_ui("ui_click")


func close() -> void:
	visible = false
	Engine.time_scale = 1.0
	Game.ui_open = maxi(Game.ui_open - 1, 0)
	if Game.ui_open == 0:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if hovered >= 0:
		var ids := _slot_ids(hovered)
		if ids.size() > 0:
			var i: int = slot_choice.get(hovered, 0) % ids.size()
			Game.player.weapons.select(ids[i])
			Audio.play_ui("ui_click")


func _slot_ids(slot: int) -> Array:
	var out := []
	for id in Game.player.owned_weapons():
		if WeaponDB.get_def(id).slot == slot:
			out.append(id)
	return out


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and hovered >= 0:
		var ids := _slot_ids(hovered)
		if ids.size() > 1:
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				slot_choice[hovered] = (slot_choice.get(hovered, 0) + 1) % ids.size()
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				slot_choice[hovered] = (slot_choice.get(hovered, 0) - 1 + ids.size()) % ids.size()
			Audio.play_ui("ui_click")


func _process(_d: float) -> void:
	if not visible:
		return
	var c := size * 0.5
	var m := get_local_mouse_position() - c
	if m.length() > 40.0:
		var a := fposmod(atan2(m.x, -m.y), TAU)
		hovered = int(round(a / (TAU / 8.0))) % 8
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r_out := 230.0
	var r_in := 90.0
	draw_circle(c, r_out + 12.0, Color(0.02, 0.03, 0.04, 0.55))
	var font := UITheme.font(true)
	for s in 8:
		var a0 := (s - 0.5) * TAU / 8.0 + 0.02
		var a1 := (s + 0.5) * TAU / 8.0 - 0.02
		var pts := PackedVector2Array()
		for k in 13:
			var a := lerpf(a0, a1, k / 12.0)
			pts.append(c + Vector2(sin(a), -cos(a)) * r_out)
		for k in range(12, -1, -1):
			var a2 := lerpf(a0, a1, k / 12.0)
			pts.append(c + Vector2(sin(a2), -cos(a2)) * r_in)
		var ids := _slot_ids(s)
		var col := Color(0.08, 0.1, 0.12, 0.85)
		if s == hovered:
			col = Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.85)
		elif ids.is_empty():
			col = Color(0.05, 0.05, 0.06, 0.5)
		draw_colored_polygon(pts, col)
		var mid := (a0 + a1) * 0.5
		var lp := c + Vector2(sin(mid), -cos(mid)) * (r_in + r_out) * 0.5
		var tc := Color(0.02, 0.05, 0.06) if s == hovered else UITheme.TEXT
		draw_string(font, lp + Vector2(-70, -14), WeaponDB.SLOT_NAMES[s].to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 140, 13, tc if not ids.is_empty() else UITheme.DIM)
		if not ids.is_empty():
			var i: int = slot_choice.get(s, maxi(ids.find(Game.player.weapons.current), 0)) % ids.size()
			var id: String = ids[i]
			draw_string(font, lp + Vector2(-80, 6), str(WeaponDB.get_def(id).name), HORIZONTAL_ALIGNMENT_CENTER, 160, 16, tc)
			var d := WeaponDB.get_def(id)
			if not d.get("melee", false):
				draw_string(font, lp + Vector2(-60, 26), "%d" % Game.player.weapons.total_ammo(id), HORIZONTAL_ALIGNMENT_CENTER, 120, 14, tc)
			if ids.size() > 1:
				draw_string(font, lp + Vector2(-60, 42), "%d/%d  (wheel)" % [i + 1, ids.size()], HORIZONTAL_ALIGNMENT_CENTER, 120, 11, tc)
	draw_circle(c, r_in - 6.0, Color(0.03, 0.04, 0.05, 0.9))
	var cur := Game.player.weapons.def()
	draw_string(font, c + Vector2(-80, 6), str(cur.name), HORIZONTAL_ALIGNMENT_CENTER, 160, 17, UITheme.ACCENT)
