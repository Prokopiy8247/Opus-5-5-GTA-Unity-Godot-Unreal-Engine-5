class_name HUD
extends CanvasLayer
## Main HUD + overlay manager. Panels (shops, phone, map, wheel, pause, debug) are opened through
## open_panel(), which releases the mouse and pauses gameplay input.

var root: Control
var minimap: Minimap
var health_bar: ProgressBar
var armor_bar: ProgressBar
var stamina_bar: ProgressBar
var breath_bar: ProgressBar
var money_lbl: Label
var time_lbl: Label
var stars: Array[Label] = []
var weapon_lbl: Label
var ammo_lbl: Label
var veh_panel: PanelContainer
var veh_speed: Label
var veh_name: Label
var veh_health: ProgressBar
var prompt_lbl: Label
var notif_box: VBoxContainer
var big_lbl: Label
var big_sub: Label
var big_box: Control
var vignette: ColorRect
var crosshair: Control
var scope: Control
var alt_lbl: Label
var debug_lbl: Label
var escape_bar: ProgressBar
var status_lbl: Label
var panel_host: Control
var current_panel: Control = null
var wheel: WeaponWheel
var waypoint := Vector3.ZERO
var has_waypoint := false
var _dmg_flash := 0.0
var _money_shown := 0
var _hud_visible := true
var _fps_t := 0.0
var _hb_t := 0.0
var menus: Menus


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.theme()
	add_child(root)
	_build_vignette()
	_build_top_right()
	_build_bottom_left()
	_build_bottom_right()
	_build_center()
	panel_host = Control.new()
	panel_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel_host)
	wheel = WeaponWheel.new()
	wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	wheel.visible = false
	root.add_child(wheel)
	menus = Menus.new()
	menus.hud = self
	add_child(menus)
	Game.hud = self
	Game.notified.connect(_on_notify)
	Game.money_changed.connect(func(_v): pass)
	_money_shown = Game.money


func _build_vignette() -> void:
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float amount = 0.0;
uniform vec3 tint = vec3(0.8, 0.05, 0.05);
void fragment() {
	vec2 d = UV - vec2(0.5);
	float v = smoothstep(0.25, 0.75, length(d) * 1.3);
	COLOR = vec4(tint, v * amount);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	vignette.material = m
	root.add_child(vignette)


func _build_top_right() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	box.position = Vector2(-330, 18)
	box.size = Vector2(310, 120)
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	time_lbl = UITheme.label("09:00  ·  Clear", 17, UITheme.DIM)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(time_lbl)
	money_lbl = UITheme.label("$0", 34, Color(0.55, 0.95, 0.6), true)
	money_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(money_lbl)
	var sr := HBoxContainer.new()
	sr.alignment = BoxContainer.ALIGNMENT_END
	sr.add_theme_constant_override("separation", 4)
	box.add_child(sr)
	for i in 5:
		var s := UITheme.label("★", 34, Color(1, 1, 1, 0.18), true)
		sr.add_child(s)
		stars.append(s)
	status_lbl = UITheme.label("", 15, UITheme.ACCENT2, true)
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(status_lbl)
	escape_bar = ProgressBar.new()
	escape_bar.custom_minimum_size = Vector2(200, 6)
	escape_bar.show_percentage = false
	escape_bar.max_value = 1.0
	escape_bar.visible = false
	box.add_child(escape_bar)


func _build_bottom_left() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.position = Vector2(22, -318)
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.panel(Color(0.02, 0.03, 0.04, 0.85), 10, 2.0))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(frame)
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(250, 220)
	minimap.clip_contents = true
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(minimap)
	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 6)
	box.add_child(bars)
	health_bar = _bar(Color(0.35, 0.85, 0.45), Vector2(150, 9))
	armor_bar = _bar(Color(0.35, 0.6, 1.0), Vector2(110, 9))
	bars.add_child(health_bar)
	bars.add_child(armor_bar)
	var bars2 := HBoxContainer.new()
	bars2.add_theme_constant_override("separation", 6)
	box.add_child(bars2)
	stamina_bar = _bar(Color(0.95, 0.8, 0.3), Vector2(150, 5))
	breath_bar = _bar(Color(0.4, 0.85, 1.0), Vector2(110, 5))
	bars2.add_child(stamina_bar)
	bars2.add_child(breath_bar)


func _bar(c: Color, sz: Vector2) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = sz
	b.show_percentage = false
	b.max_value = 1.0
	var f := StyleBoxFlat.new()
	f.bg_color = c
	f.corner_radius_top_left = 3
	f.corner_radius_top_right = 3
	f.corner_radius_bottom_left = 3
	f.corner_radius_bottom_right = 3
	b.add_theme_stylebox_override("fill", f)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _build_bottom_right() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.position = Vector2(-300, -210)
	box.size = Vector2(280, 190)
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	veh_panel = PanelContainer.new()
	veh_panel.add_theme_stylebox_override("panel", UITheme.panel(UITheme.BG, 8))
	veh_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(veh_panel)
	var vb := VBoxContainer.new()
	veh_panel.add_child(vb)
	veh_name = UITheme.label("", 15, UITheme.DIM)
	veh_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(veh_name)
	veh_speed = UITheme.label("0 km/h", 32, UITheme.TEXT, true)
	veh_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(veh_speed)
	veh_health = _bar(Color(0.95, 0.6, 0.25), Vector2(250, 6))
	vb.add_child(veh_health)
	var wp := PanelContainer.new()
	wp.add_theme_stylebox_override("panel", UITheme.panel(UITheme.BG, 8))
	wp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(wp)
	var wb := VBoxContainer.new()
	wp.add_child(wb)
	weapon_lbl = UITheme.label("P9 Compact", 18, UITheme.ACCENT, true)
	weapon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wb.add_child(weapon_lbl)
	ammo_lbl = UITheme.label("15 / 60", 28, UITheme.TEXT, true)
	ammo_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wb.add_child(ammo_lbl)


func _build_center() -> void:
	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	scope = ScopeOverlay.new()
	scope.set_anchors_preset(Control.PRESET_FULL_RECT)
	scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scope.visible = false
	root.add_child(scope)
	prompt_lbl = UITheme.label("", 20, UITheme.TEXT, true)
	prompt_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_lbl.position = Vector2(-400, -150)
	prompt_lbl.size = Vector2(800, 40)
	prompt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt_lbl)
	notif_box = VBoxContainer.new()
	notif_box.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	notif_box.position = Vector2(22, -160)
	notif_box.custom_minimum_size = Vector2(420, 0)
	notif_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notif_box.add_theme_constant_override("separation", 6)
	root.add_child(notif_box)
	big_box = VBoxContainer.new()
	big_box.set_anchors_preset(Control.PRESET_CENTER)
	big_box.position = Vector2(-500, -90)
	big_box.size = Vector2(1000, 180)
	big_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big_box.visible = false
	root.add_child(big_box)
	big_lbl = UITheme.label("", 92, UITheme.BAD, true)
	big_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_box.add_child(big_lbl)
	big_sub = UITheme.label("", 22, UITheme.TEXT)
	big_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_box.add_child(big_sub)
	alt_lbl = UITheme.label("", 20, UITheme.ACCENT, true)
	alt_lbl.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	alt_lbl.position = Vector2(-260, -20)
	alt_lbl.size = Vector2(240, 60)
	alt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(alt_lbl)
	debug_lbl = UITheme.label("", 15, Color(0.85, 1, 0.85))
	debug_lbl.position = Vector2(20, 14)
	root.add_child(debug_lbl)


# ------------------------------------------------------------------ update

func _process(delta: float) -> void:
	var p := Game.player
	if p == null:
		return
	root.visible = _hud_visible
	if Input.is_action_just_pressed("photo") and Game.main:
		Game.main.take_photo()
	if Input.is_action_just_pressed("toggle_hud"):
		_hud_visible = not _hud_visible
	# money ticker
	if _money_shown != Game.money:
		var step := maxi(1, absi(Game.money - _money_shown) / 12)
		_money_shown = _money_shown + clampi(Game.money - _money_shown, -step, step)
	money_lbl.text = U.money_str(_money_shown)
	# time / weather
	if Game.env:
		var h := int(Game.env.hour)
		var m := int(fmod(Game.env.hour, 1.0) * 60.0)
		time_lbl.text = "%02d:%02d  ·  %s  ·  %s" % [h, m, Game.env.weather.capitalize(), WorldMap.district_at(p.global_position.x, p.global_position.z).name]
	# wanted
	var lvl := Game.wanted.level if Game.wanted else 0
	var searching := Game.wanted and Game.wanted.state == "search" and lvl > 0
	var blink := int(Time.get_ticks_msec() / 300) % 2 == 0
	for i in 5:
		var on := i < lvl
		var c := Color(1.0, 0.85, 0.3) if on else Color(1, 1, 1, 0.15)
		if on and searching:
			c = Color(1.0, 0.85, 0.3, 1.0 if blink else 0.35)
		stars[i].add_theme_color_override("font_color", c)
	status_lbl.text = ("SEARCHING — stay out of sight" if searching else ("PURSUIT" if lvl > 0 else ""))
	escape_bar.visible = searching
	if searching:
		escape_bar.value = Game.wanted.escape_progress()
	# vitals
	health_bar.value = p.health / p.max_health
	armor_bar.value = p.armor / 100.0
	stamina_bar.value = p.stamina
	breath_bar.value = p.breath
	breath_bar.visible = p.state == "swim" or p.breath < 1.0
	stamina_bar.visible = p.stamina < 0.99 or p.sprinting
	# low health heartbeat + vignette
	_dmg_flash = maxf(_dmg_flash - delta * 1.5, 0.0)
	var low := clampf(1.0 - p.health / (p.max_health * 0.35), 0.0, 1.0) if not p.dead else 0.0
	(vignette.material as ShaderMaterial).set_shader_parameter("amount", clampf(_dmg_flash + low * (0.5 + 0.2 * sin(Time.get_ticks_msec() * 0.006)), 0.0, 0.9))
	if low > 0.3:
		_hb_t -= delta
		if _hb_t <= 0.0:
			_hb_t = 0.9
			Audio.play_2d("heartbeat", -6.0 + low * 6.0)
	# weapon
	var d := p.weapons.def()
	weapon_lbl.text = str(d.name)
	if d.get("melee", false):
		ammo_lbl.text = "—"
	elif d.get("throw", false):
		ammo_lbl.text = "x%d" % p.weapons.total_ammo(p.weapons.current)
	else:
		ammo_lbl.text = ("%d / %d" % [p.weapons.mag(), p.weapons.reserve()]) + ("  ⟳" if p.weapons.is_reloading() else "")
	# vehicle
	var v := p.vehicle
	veh_panel.visible = v != null
	if v:
		veh_name.text = v.display_name + ("  ·  Radio: " + Audio.STATIONS[Game.radio_station] if v._radio_audio and v._radio_audio.playing else "")
		veh_speed.text = "%d km/h" % int(v.speed_kmh)
		veh_health.value = v.health / v.max_health
	# prompts
	prompt_lbl.text = _prompt_text(p)
	# scope / crosshair
	scope.visible = Game.cam and Game.cam.scope_fov > 0.0 and Game.cam.mode == "aim"
	crosshair.visible = not scope.visible and ((p.aiming and p.state == "foot") or p.aiming_in_vehicle or (p.in_cover and p.aiming))
	# altimeter
	alt_lbl.text = ""
	if p.state in ["skydive", "parachute"] or (v and v.kind in ["heli", "plane"]):
		var src: Node3D = v if v else p
		var agl := src.global_position.y - maxf(WorldMap.height(src.global_position.x, src.global_position.z), C.SEA_LEVEL)
		alt_lbl.text = "ALT %d m" % int(agl)
		if v and v.kind == "plane":
			alt_lbl.text += "\nTHR %d%%" % int((v as Airplane).throttle_level * 100.0)
			if (v as Airplane).stalled:
				alt_lbl.text += "\nSTALL"
	# debug
	_fps_t -= delta
	if _fps_t <= 0.0:
		_fps_t = 0.25
		var s := ""
		if Game.show_fps:
			s += "FPS %d  ·  draw calls %d  ·  objs %d\n" % [Engine.get_frames_per_second(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)]
		if Game.show_coords:
			var gp := p.global_position
			s += "XYZ %.1f %.1f %.1f  ·  sector %d,%d  ·  %s\nvehicles %d  npcs %d" % [gp.x, gp.y, gp.z, floori(gp.x / 100.0), floori(gp.z / 100.0), WorldMap.district_at(gp.x, gp.z).name, Game.vehicles.size(), Game.npcs.size()]
		debug_lbl.text = s
	_handle_global_input()


func _prompt_text(p: Player) -> String:
	if current_panel != null or p.dead:
		return ""
	if p.state == "vehicle" and p.vehicle:
		var poi := Game.poi_near(p.vehicle.global_position, 7.0)
		if poi.get("type", "") == "modshop":
			return "[E] Customize & repair at Torque Theory"
		if poi.get("type", "") == "garage":
			return "[E] Store this vehicle in your garage"
		return ""
	if p.state == "skydive":
		return "[SPACE] Open parachute"
	if p.state != "foot":
		return ""
	var v := p.nearest_vehicle(4.0)
	if v and not v.destroyed:
		var occ := v.seat_occupant(0)
		if occ and occ != p:
			return "[F] Steal " + v.display_name
		return "[F] Enter " + v.display_name
	var poi2 := Game.poi_near(p.global_position, 3.0)
	if not poi2.is_empty():
		return Menus.poi_prompt(poi2)
	if Game.world:
		for l in Game.world.ladders:
			if U.flat_dist(l.bottom, p.global_position) < 1.4 or (U.flat_dist(l.top, p.global_position) < 1.4 and absf(p.global_position.y - float(l.top_y)) < 1.5):
				return "[E] Climb ladder"
	if Game.main and Game.main.has_method("pickup_prompt"):
		return Game.main.pickup_prompt(p.global_position)
	return ""


func _handle_global_input() -> void:
	if Input.is_action_just_pressed("pause"):
		if current_panel:
			close_panel()
		else:
			menus.open_pause()
	elif Input.is_action_just_pressed("map") and (current_panel == null or current_panel.has_meta("is_map")):
		if current_panel:
			close_panel()
		else:
			menus.open_map()
	elif Input.is_action_just_pressed("phone") and current_panel == null:
		menus.open_phone()
	elif Input.is_action_just_pressed("debug_menu"):
		if current_panel and current_panel.has_meta("is_debug"):
			close_panel()
		elif current_panel == null:
			menus.open_debug()
	elif Input.is_action_just_pressed("quick_save") and current_panel == null:
		SaveSystem.save_game()
	elif Input.is_action_just_pressed("quick_load") and current_panel == null:
		SaveSystem.load_game()
	if Input.is_action_just_pressed("interact") and current_panel == null and Game.player and Game.player.state == "vehicle":
		var v := Game.player.vehicle
		var poi := Game.poi_near(v.global_position, 7.0)
		if poi.get("type", "") == "modshop":
			menus.open_modshop(v)
		elif poi.get("type", "") == "garage" and Game.player.seat == 0:
			menus.store_vehicle(v)
	# weapon wheel (hold Tab)
	if current_panel == null and Game.player and not Game.player.dead:
		if Input.is_action_just_pressed("weapon_wheel"):
			wheel.open()
		elif Input.is_action_just_released("weapon_wheel") and wheel.visible:
			wheel.close()


# ------------------------------------------------------------------ panels

func open_panel(c: Control) -> void:
	if current_panel:
		close_panel()
	current_panel = c
	panel_host.add_child(c)
	Game.ui_open += 1
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_panel() -> void:
	if current_panel == null:
		return
	if current_panel.has_meta("pauses"):
		Game.set_paused(false)
	current_panel.queue_free()
	current_panel = null
	Game.ui_open = maxi(Game.ui_open - 1, 0)
	if Game.ui_open == 0:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Audio.play_ui("ui_back")


func open_poi(p: Dictionary) -> void:
	menus.open_poi(p)


func set_waypoint(p: Vector3) -> void:
	waypoint = p
	has_waypoint = true
	Game.notify("Waypoint set (GPS route on the radar)")


func clear_waypoint() -> void:
	has_waypoint = false


# ------------------------------------------------------------------ feedback

func _on_notify(text: String, kind: String) -> void:
	var pc := PanelContainer.new()
	var col := UITheme.ACCENT
	match kind:
		"warn": col = UITheme.ACCENT2
		"good": col = UITheme.GOOD
		"skill": col = Color(0.75, 0.6, 1.0)
		"hint": col = Color(0.85, 0.85, 0.85)
	var sb := UITheme.panel(UITheme.BG, 6)
	sb.border_width_left = 4
	sb.border_color = col
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UITheme.label(text, 17)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 380
	pc.add_child(l)
	notif_box.add_child(pc)
	if notif_box.get_child_count() > 5:
		notif_box.get_child(0).queue_free()
	if kind != "hint":
		Audio.play_ui("notify")
	var tw := pc.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(pc, "modulate:a", 0.0, 0.6)
	tw.tween_callback(pc.queue_free)


func flash_damage(amount: float) -> void:
	_dmg_flash = clampf(_dmg_flash + amount / 40.0, 0.0, 0.8)


func show_big_message(t: String, sub: String, col: Color) -> void:
	big_lbl.text = t
	big_sub.text = sub
	big_lbl.add_theme_color_override("font_color", col)
	big_box.visible = true
	big_box.modulate.a = 0.0
	create_tween().tween_property(big_box, "modulate:a", 1.0, 0.6)


func hide_big_message() -> void:
	big_box.visible = false
