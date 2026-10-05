extends Node3D
## Bootstrap: builds the island, spawns the player and every system, then hands control to free roam.

var world: World
var env: EnvController
var taxi: TaxiService
var emergency: Node
var _loading: CanvasLayer
var _load_bar: ProgressBar
var _load_lbl: Label
var _fade_rect: ColorRect
var _amb_city: AudioStreamPlayer
var _amb_ocean: AudioStreamPlayer
var _amb_wind: AudioStreamPlayer
var _amb_uw: AudioStreamPlayer
var _amb_chatter: AudioStreamPlayer
var ready_done := false


func _ready() -> void:
	Game.main = self
	for n in ["Vehicles", "Actors", "Ragdolls", "Pickups"]:
		var c := Node3D.new()
		c.name = n
		add_child(c)
	_build_loading()
	await get_tree().process_frame
	env = EnvController.new()
	env.name = "Environment"
	add_child(env)
	Game.env = env
	world = World.new()
	world.name = "World"
	add_child(world)
	Game.world = world
	world.build_progress.connect(_on_progress)
	await world.build()
	_on_progress("Mapping streets", 0.95)
	await get_tree().process_frame
	Minimap.bake(world)
	env.lamp_points = world.lamp_points
	_spawn_player()
	_spawn_systems()
	_spawn_initial_content()
	_build_ambience()
	apply_quality()
	_loading.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ready_done = true
	Game.notify("Welcome to Vesper Bay. Free roam — no missions. F1: benchmark menu · ESC: pause & controls", "good")
	if SaveSystem.has_save():
		Game.notify("Press F9 to load your last save", "hint")
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--autotest"):
			var at: Node = load("res://gta/code/debug/autotest.gd").new()
			at.name = "AutoTest"
			add_child(at)
			at.call("start", a)


func _build_loading() -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 50
	add_child(_loading)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.position = Vector2(-300, -80)
	vb.custom_minimum_size = Vector2(600, 160)
	vb.theme = UITheme.theme()
	_loading.add_child(vb)
	vb.add_child(UITheme.label("VESPER BAY", 64, UITheme.ACCENT, true))
	_load_lbl = UITheme.label("Loading…", 20, UITheme.DIM)
	vb.add_child(_load_lbl)
	_load_bar = ProgressBar.new()
	_load_bar.max_value = 1.0
	_load_bar.custom_minimum_size = Vector2(600, 10)
	_load_bar.show_percentage = false
	vb.add_child(_load_bar)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var fl := CanvasLayer.new()
	fl.layer = 40
	add_child(fl)
	fl.add_child(_fade_rect)


func _on_progress(stage: String, frac: float) -> void:
	if is_instance_valid(_load_lbl):
		_load_lbl.text = stage + "…"
		_load_bar.value = frac


func _spawn_player() -> void:
	var p := Player.new()
	p.name = "Player"
	add_child(p)
	p.global_position = WorldMap.respawn_point("safehouse").origin
	p.reset_physics_interpolation()
	var cam := CameraRig.new()
	cam.name = "CameraRig"
	add_child(cam)
	Game.cam = cam
	cam.target = p
	cam.exclude = [p.get_rid()]
	cam.yaw = 0.0
	var hud := HUD.new()
	hud.name = "HUD"
	add_child(hud)


func _spawn_systems() -> void:
	var wanted := WantedSystem.new()
	wanted.name = "Wanted"
	add_child(wanted)
	Game.wanted = wanted
	var peds := PedManager.new()
	peds.name = "PedManager"
	add_child(peds)
	peds.setup(world)
	Game.peds = peds
	var traffic := TrafficManager.new()
	traffic.name = "TrafficManager"
	add_child(traffic)
	traffic.setup(world)
	Game.traffic = traffic
	var police := PoliceDispatch.new()
	police.name = "PoliceDispatch"
	add_child(police)
	police.setup(world)
	Game.police = police
	var wild := WildlifeManager.new()
	wild.name = "Wildlife"
	add_child(wild)
	wild.setup()
	Game.wildlife = wild
	taxi = TaxiService.new()
	taxi.name = "Taxi"
	add_child(taxi)
	var act := Activities.new()
	act.name = "Activities"
	add_child(act)
	emergency = EmergencyServices.new()
	emergency.name = "Emergency"
	add_child(emergency)


func _spawn_initial_content() -> void:
	# personal car outside the safehouse
	var xf: Transform3D = world.vehicle_spawns.get("safehouse_garage", Transform3D(Basis.IDENTITY, Vector3(256, 1.5, 12)))
	var car := VehicleBase.spawn("muscle", xf, null, {"paint": Color(0.15, 0.55, 0.6), "livery": 1, "stripe_color": Color(0.95, 0.95, 0.95)})
	car.owner_is_player = true
	# a motorbike & bicycle nearby
	VehicleBase.spawn("bike", Transform3D(Basis(Vector3.UP, PI * 0.5), xf.origin + Vector3(-6, 0, -2)), null, {}).owner_is_player = true
	VehicleBase.spawn("bicycle", Transform3D(Basis(Vector3.UP, PI * 0.5), xf.origin + Vector3(-9, 0, -2)), null, {}).owner_is_player = true
	# aircraft & boats parked at their bases
	for key in ["plane_0", "heli_pad"]:
		if world.vehicle_spawns.has(key):
			VehicleBase.spawn("plane" if key == "plane_0" else "heli", world.vehicle_spawns[key])
	if world.vehicle_spawns.has("plane_1"):
		VehicleBase.spawn("jet", world.vehicle_spawns["plane_1"])
	for key2 in ["boat_0_0", "boat_1_1", "beach_boat"]:
		if world.vehicle_spawns.has(key2):
			VehicleBase.spawn("boat", world.vehicle_spawns[key2])
	if world.vehicle_spawns.has("police_heli"):
		var ph := VehicleBase.spawn("police_heli", world.vehicle_spawns["police_heli"])
		ph.police_unit = true
	if world.vehicle_spawns.has("ambulance"):
		VehicleBase.spawn("ambulance", world.vehicle_spawns["ambulance"])
	if world.vehicle_spawns.has("modshop_out"):
		VehicleBase.spawn("sports", world.vehicle_spawns["modshop_out"], null, {"paint": Color(0.95, 0.75, 0.1)})
	# pickups
	if world.poi.has("viewpoint"):
		spawn_pickup("parachute", world.poi.viewpoint.pos + Vector3(2, 0.3, 2), 1, 1e9)
	if world.poi.has("viewpoint_spire"):
		spawn_pickup("parachute", world.poi.viewpoint_spire.pos + Vector3(2, 0.3, 0), 1, 1e9)
	spawn_pickup("parachute", Vector3(-150, 1.3, -148), 1, 1e9)
	spawn_pickup("weapon:bat", Vector3(-232, 1.4, -20), 1, 1e9)
	spawn_pickup("weapon:smg", Vector3(-140, 1.4, 169), 60, 1e9)
	spawn_pickup("armor", Vector3(14, 1.4, 4), 1, 1e9)
	spawn_pickup("health", Vector3(176, 1.4, 4), 1, 1e9)
	spawn_pickup("weapon:shotgun", Vector3(150, -15.0, 268), 24, 1e9)
	spawn_pickup("cash", WorldMap.WRECK_POS + Vector3(2, 1.5, 0), 2500, 1e9)


func _build_ambience() -> void:
	_amb_city = _amb("city_loop", -14.0)
	_amb_ocean = _amb("ocean_loop", -40.0)
	_amb_wind = _amb("wind_loop", -40.0)
	_amb_uw = _amb("underwater_loop", -60.0)
	_amb_chatter = _amb("chatter", -60.0)


func _amb(name: String, db: float) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.stream = Audio.get_stream(name)
	a.volume_db = db
	a.bus = "Ambient"
	add_child(a)
	a.play()
	return a


func _process(delta: float) -> void:
	if not ready_done or Game.player == null:
		return
	var p := Game.player
	var pos := Game.cam.cam.global_position if Game.cam else p.global_position
	var coast := clampf(1.0 - absf(WorldMap.coast_sdf(pos.x, pos.z)) / 60.0, 0.0, 1.0)
	var alt := clampf((pos.y - 20.0) / 60.0, 0.0, 1.0)
	var under := pos.y < C.SEA_LEVEL
	var district: String = WorldMap.district_at(pos.x, pos.z).id
	var city := 1.0 if district in ["meridian", "palm", "ironside"] else 0.4
	_amb_city.volume_db = lerpf(_amb_city.volume_db, -60.0 if under else linear_to_db(city * (1.0 - alt) * 0.5 + 0.02), delta * 2.0)
	_amb_ocean.volume_db = lerpf(_amb_ocean.volume_db, -60.0 if under else linear_to_db(coast * 0.6 + 0.01), delta * 2.0)
	_amb_wind.volume_db = lerpf(_amb_wind.volume_db, linear_to_db(alt * 0.6 + (env.wetness * 0.2 if env else 0.0) + 0.01), delta * 2.0)
	_amb_uw.volume_db = lerpf(_amb_uw.volume_db, -8.0 if under else -60.0, delta * 4.0)
	var crowd := 0
	for n in Game.npcs:
		if is_instance_valid(n) and (n as Node3D).global_position.distance_to(pos) < 18.0:
			crowd += 1
	_amb_chatter.volume_db = lerpf(_amb_chatter.volume_db, linear_to_db(clampf(crowd / 8.0, 0.001, 0.5)) - 12.0, delta * 2.0)
	if p.state != "swim":
		Audio.set_underwater(under)


# ------------------------------------------------------------------ helpers

func teleport_player(pos: Vector3) -> void:
	var p := Game.player
	if p.vehicle:
		var v := p.vehicle
		v.global_position = pos + Vector3(0, 1.5, 0)
		v.linear_velocity = Vector3.ZERO
		v.angular_velocity = Vector3.ZERO
		v.reset_physics_interpolation()
		return
	if p.ragdolled and not p.dead:
		p._get_up()
		p.state = "foot"
	if Game.traffic:
		Game.traffic._warm_until = Game.now() + 2.0
	if pos.y < 200.0:
		pos = find_free_spot(pos)
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p._max_fall_speed = 0.0
	p._air_t = 0.0
	p.reset_physics_interpolation()
	if p.state not in ["foot", "skydive", "parachute"]:
		p.state = "foot"
		p.rig.mode = "normal"
	Game.notify("Teleported")


## Ground point near `pos` where a standing character does not overlap buildings/props. Rays that
## start inside a collider do not report it, so a capsule overlap test guards against teleporting
## into a building and falling through the terrain.
func find_free_spot(pos: Vector3) -> Vector3:
	for r in [0.0, 2.5, 5.0, 8.0, 12.0, 18.0, 26.0]:
		var n := 1 if r == 0.0 else 10
		for k in n:
			var a := TAU * k / n
			var q := pos + Vector3(cos(a) * r, 0, sin(a) * r)
			var hit := U.ray(q + Vector3(0, 3, 0), q - Vector3(0, 8, 0), C.L_WORLD)
			var g: Vector3 = hit.position if not hit.is_empty() else Vector3(q.x, maxf(WorldMap.height(q.x, q.z), C.SEA_LEVEL), q.z)
			if _capsule_free(g + Vector3(0, 0.1, 0)):
				return g + Vector3(0, 0.1, 0)
	var nl := world.road_graph.nearest_lane(pos, 200.0) if world and world.road_graph else {}
	return (nl.point + Vector3(0, 0.3, 0)) if not nl.is_empty() else pos


func _capsule_free(feet: Vector3) -> bool:
	var sh := CapsuleShape3D.new()
	sh.radius = 0.36
	sh.height = 1.7
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0, 0.95, 0))
	q.collision_mask = C.L_WORLD | C.L_PROP | C.L_VEHICLE
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


static func _open_water(q: Vector3, clearance: float) -> bool:
	if WorldMap.height(q.x, q.z) > -2.5:
		return false
	for k in 8:
		var a := TAU * k / 8.0
		if WorldMap.height(q.x + cos(a) * clearance, q.z + sin(a) * clearance) > -1.5:
			return false
	return true


func spawn_vehicle_near_player(id: String) -> VehicleBase:
	var p := Game.player
	var d := VehicleDB.get_def(id)
	var fwd := U.dir_of_yaw(Game.cam.yaw)
	var base := p.global_position + fwd * (6.0 if d.kind in ["car", "bike", "bicycle"] else 14.0)
	var spawn_basis := Basis(Vector3.UP, Game.cam.yaw)
	if d.kind in ["car", "bike", "bicycle"] and world.road_graph:
		# prefer the nearest road lane so vehicles never appear inside buildings
		var nl := world.road_graph.nearest_lane(p.global_position, 45.0)
		if not nl.is_empty():
			base = nl.point
			spawn_basis = Basis.looking_at(world.road_graph.links[nl.link].dir, Vector3.UP)
	if d.kind == "boat":
		# nearest open water with clearance all round, then point the bow at the most open direction
		var best := Vector3.ZERO
		var bd := INF
		for k in 60:
			var a := TAU * k / 60.0
			for r in [12.0, 20.0, 30.0, 45.0, 70.0, 110.0]:
				var q := p.global_position + Vector3(cos(a) * r, 0, sin(a) * r)
				if r < bd and _open_water(q, 7.0):
					bd = r
					best = q
		if bd == INF:
			Game.notify("No water nearby — teleporting you to the marina with the boat", "hint")
			best = Vector3(-190, 0, 200)
			teleport_player(Vector3(-190, 1.5, 172))
		base = Vector3(best.x, 0.4, best.z)
		var best_dir := Vector3.FORWARD
		var best_run := -1.0
		for k in 24:
			var dir := Vector3(sin(TAU * k / 24.0), 0, cos(TAU * k / 24.0))
			var run := 0.0
			while run < 80.0 and WorldMap.height(base.x + dir.x * (run + 4.0), base.z + dir.z * (run + 4.0)) < -2.0:
				run += 4.0
			if run > best_run:
				best_run = run
				best_dir = dir
		spawn_basis = Basis.looking_at(best_dir, Vector3.UP)
	else:
		var hit := U.ray(base + Vector3(0, 20, 0), base - Vector3(0, 30, 0), C.L_WORLD)
		if not hit.is_empty():
			base = hit.position + Vector3(0, 0.6, 0)
		if d.kind == "plane":
			Game.notify("Tip: SHIFT for throttle, W/S pitch — the airfield runway is best for take-off", "hint")
	if d.kind in ["heli", "plane"]:
		# open space check: push away from buildings by probing upward
		for k in 8:
			var up_hit := U.ray(base + Vector3(0, 0.5, 0), base + Vector3(0, 12, 0), C.L_WORLD)
			if up_hit.is_empty():
				break
			base += fwd * 6.0
	var v := VehicleBase.spawn(id, Transform3D(spawn_basis, base))
	v.owner_is_player = true
	Game.notify(str(d.name) + " spawned")
	return v


func spawn_pickup(kind: String, pos: Vector3, amount: int, life := 90.0) -> void:
	var pk := Pickup.new()
	get_node("Pickups").add_child(pk)
	pk.global_position = pos
	pk.setup(kind, amount)
	pk.life = life


func pickup_prompt(_pos: Vector3) -> String:
	return ""


func fade(mid: Callable) -> void:
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, 0.5)
	tw.tween_callback(mid)
	tw.tween_interval(0.4)
	tw.tween_property(_fade_rect, "color:a", 0.0, 0.6)


func take_photo() -> void:
	var hud: HUD = Game.hud
	# the HUD re-applies _hud_visible every frame, so hide it through that flag for the capture
	var was: bool = hud._hud_visible
	hud._hud_visible = false
	hud.root.visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://photos")
	var path := "user://photos/vesperbay_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	img.save_png(path)
	hud._hud_visible = was
	hud.root.visible = was
	Audio.play_ui("pickup")
	Game.notify("Photo saved: " + ProjectSettings.globalize_path(path), "good")


func apply_quality() -> void:
	var hi: bool = int(Game.settings.quality) == 1
	var e := env.env
	e.ssao_enabled = true
	e.ssil_enabled = hi
	e.volumetric_fog_enabled = hi and false
	e.sdfgi_enabled = false
	env.sun.directional_shadow_max_distance = 220.0 if hi else 140.0
	get_viewport().msaa_3d = Viewport.MSAA_2X if hi else Viewport.MSAA_DISABLED
	get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
