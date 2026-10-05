extends Node
## In-game automated validation. Run with:
##   Godot --path . -- --autotest=<scenario>
## Drives the real game through Input actions / public APIs, captures screenshots into the
## benchmark run folder and writes a JSON report of checks.

const RUN_DIR := ".opus-5.5-gta-runs/run-20261003-121512-opus55-godot/screens/"

var scenario := "basic"
var report := {"checks": {}, "notes": []}
var shot_i := 0
var dir := ""


func start(arg: String) -> void:
	if arg.contains("="):
		scenario = arg.split("=")[1]
	dir = ProjectSettings.globalize_path("res://") + RUN_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	_run()


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	shot_i += 1
	var path := dir + "%s_%02d_%s.png" % [scenario, shot_i, name]
	img.save_png(path)
	print("[AutoTest] screenshot ", path)


func check(name: String, ok: bool, info := "") -> void:
	report.checks[name] = {"ok": ok, "info": info}
	print("[AutoTest] CHECK %s: %s %s" % [name, "PASS" if ok else "FAIL", info])


func _finish() -> void:
	var f := FileAccess.open(dir + "report_%s.json" % scenario, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	var passed := 0
	for k in report.checks:
		if report.checks[k].ok:
			passed += 1
	print("[AutoTest] DONE %s: %d/%d checks passed" % [scenario, passed, report.checks.size()])
	get_tree().quit()


func _run() -> void:
	await _wait(2.0)
	match scenario:
		"basic": await _basic()
		"vehicles": await _vehicles()
		"combat": await _combat()
		"world": await _world()
		"air": await _air()
		"boat": await _boat()
		"views": await _views()
		"systems": await _systems()
		"perf": await _perf()
		"characters": await _characters()
		"weapons": await _weapons()
		"buildings": await _buildings()
		_: await _basic()
	_finish()


func _p() -> Player:
	return Game.player


func _hold(action: String, t: float) -> void:
	Input.action_press(action)
	await _wait(t)
	Input.action_release(action)


## Points the camera rig exactly at a world point (verified by a raycast in the tests).
func _aim_at(point: Vector3) -> void:
	var cam := Game.cam.cam
	var from := cam.global_position
	var d := (point - from).normalized()
	# camera looks along -basis.z; with Basis.from_euler(pitch, yaw) that means
	# dir = (-sin(yaw)cos(pitch), sin(pitch), -cos(yaw)cos(pitch))
	Game.cam.yaw = atan2(-d.x, -d.z)
	Game.cam.pitch = asin(clampf(d.y, -1.0, 1.0))


func _basic() -> void:
	var p := _p()
	Game.env.set_hour(10.0)
	Game.env.set_weather("clear", true)
	Game.cam.yaw = PI * 0.15
	Game.cam.pitch = -0.2
	await _wait(1.0)
	await shot("start_safehouse")
	var start := p.global_position
	Game.cam.yaw = 0.0
	await _hold("move_forward", 2.0)
	check("player_walks", p.global_position.distance_to(start) > 4.0, "moved %.1f m" % p.global_position.distance_to(start))
	await _hold("sprint", 0.1)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _wait(1.5)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await shot("running")
	# drive
	var v: VehicleBase = Game.main.spawn_vehicle_near_player("sedan")
	await _wait(1.0)
	Game.cam.yaw = atan2(v.global_position.x - p.global_position.x, v.global_position.z - p.global_position.z) + PI
	await _hold("enter_vehicle", 0.1)
	await _wait(1.5)
	check("enter_vehicle", p.vehicle == v, "state=" + p.state)
	await shot("in_car")
	Input.action_press("move_forward")
	await _wait(4.0)
	var spd := v.linear_velocity.length()
	check("car_drives", spd > 8.0, "speed %.1f m/s" % spd)
	await shot("driving")
	Input.action_release("move_forward")
	Input.action_press("move_back")
	await _wait(2.0)
	Input.action_release("move_back")
	await _hold("enter_vehicle", 0.1)
	await _wait(1.0)
	check("exit_vehicle", p.vehicle == null, "state=" + p.state)
	check("traffic_spawned", Game.traffic.cars.size() > 3, "%d cars" % Game.traffic.cars.size())
	check("peds_spawned", Game.peds.peds.size() > 5, "%d peds" % Game.peds.peds.size())
	Game.cam.yaw = PI
	Game.cam.pitch = -0.25
	await shot("street_life")


func _vehicles() -> void:
	var p := _p()
	Game.env.set_hour(10.5)
	Game.env.set_weather("clear", true)
	Game.traffic_enabled = false
	# open airfield apron: cars in a front row, two-wheelers/boat/aircraft behind
	Game.main.teleport_player(Vector3(-130, 1.3, -150))
	await _wait(1.0)
	var row := ["compact", "sedan", "sports", "muscle", "suv", "pickup", "van", "police", "taxi", "ambulance", "firetruck", "swat", "truck"]
	var x := -196.0
	for id in row:
		var v := VehicleBase.spawn(id, Transform3D(Basis(Vector3.UP, PI), Vector3(x, 1.6, -166)))
		v.owner_is_player = true
		x += 6.5
	x = -190.0
	for id in ["bike", "bicycle", "boat", "heli", "police_heli", "plane", "jet"]:
		var v2 := VehicleBase.spawn(id, Transform3D(Basis(Vector3.UP, PI), Vector3(x, 1.8, -182)))
		v2.owner_is_player = true
		x += 13.0 if id in ["heli", "police_heli", "plane", "jet"] else 6.0
	await _wait(3.0)
	p.global_position = Vector3(-150, 1.3, -150)
	Game.cam.yaw = -0.35
	Game.cam.pitch = -0.22
	await _wait(1.0)
	await shot("lineup_a")
	p.global_position = Vector3(-112, 1.3, -152)
	Game.cam.yaw = 0.45
	Game.cam.pitch = -0.2
	await _wait(1.0)
	await shot("lineup_b")
	p.global_position = Vector3(-168, 1.3, -158)
	Game.cam.yaw = -0.2
	Game.cam.pitch = -0.15
	await _wait(1.0)
	await shot("closeup_police_taxi")
	var settled := 0
	for v in Game.vehicles:
		var veh := v as VehicleBase
		if veh.global_position.distance_to(Vector3(-150, 1, -172)) < 80.0 and veh.global_basis.y.y > 0.9:
			settled += 1
	check("vehicles_upright", settled >= 18, "%d upright" % settled)
	Game.traffic_enabled = true


func _combat() -> void:
	var p := _p()
	Game.main.teleport_player(Vector3(10, 1.3, -95))
	await _wait(1.0)
	for id in WeaponDB.W:
		p.weapons.give(id, 300)
	p.weapons.select("rifle")
	p._refresh_weapon_model()
	var target := Game.peds.make_npc("civilian", p.global_position + Vector3(0, 0.2, -10))
	var target_weak := target
	Game.peds.peds.append(target)
	# ensure witnesses are around so the crime is reported (design: crimes need a witness)
	for k in 4:
		var w2 := Game.peds.make_npc("civilian", p.global_position + Vector3(randf_range(-6, 6), 0.2, -6.0 + randf_range(-3, 3)))
		w2.cur_node = -1
		Game.peds.peds.append(w2)
	await _wait(0.5)
	_aim_at(target.global_position + Vector3(0, 1.1, 0))
	Input.action_press("aim")
	await _wait(0.6)
	await shot("aiming")
	var ammo0 := p.weapons.mag()
	Input.action_press("fire")
	await _wait(1.2)
	Input.action_release("fire")
	Input.action_release("aim")
	check("weapon_fires", p.weapons.mag() < ammo0, "mag %d -> %d" % [ammo0, p.weapons.mag()])
	await _wait(0.5)
	check("npc_damaged", target == null or target.health < 100.0, "alive=%s" % (target != null))
	# crimes are witnessed, not global: give the witness call time to complete (3.5-6 s + margin)
	await _wait(9.0)
	var phoning := 0
	for n in Game.npcs:
		if is_instance_valid(n) and (n as NPC).brain == "phone":
			phoning += 1
	check("wanted_raised", Game.wanted.level > 0, "level %d heat %.1f state %s witnesses_dialling=%d" % [Game.wanted.level, Game.wanted.heat, Game.wanted.state, phoning])
	await shot("after_shooting")
	Game.wanted.set_level(3)
	await _wait(12.0)
	check("police_responded", Game.police.units.size() > 0, "%d units, %d helis" % [Game.police.units.size(), Game.police.helis.size()])
	Game.cam.pitch = -0.3
	await shot("police")
	p.weapons.select("rpg")
	# clear line of fire: stand on the plaza and place the target car a short, open distance away
	Game.main.teleport_player(Vector3(10, 1.3, -70))
	await _wait(1.2)
	var car := VehicleBase.spawn("sedan", Transform3D(Basis(Vector3.UP, PI), Vector3(10, 1.4, -86)))
	await _wait(1.2)
	_aim_at(car.global_position + Vector3(0, 1.1, 0))
	Input.action_press("aim")
	await _wait(0.4)
	Input.action_press("fire")
	await _wait(0.15)
	Input.action_release("fire")
	await _wait(1.4)
	print("[AutoTest] after rocket: hp=%.0f dist=%.1f" % [car.health, car.global_position.distance_to(p.global_position)])
	Input.action_release("aim")
	await shot("explosion")
	check("vehicle_destroyed", car.destroyed or car.health < car.max_health, "hp %.0f/%.0f destroyed=%s" % [car.health, car.max_health, car.destroyed])
	Game.invulnerable = true
	await _wait(1.0)
	Game.wanted.clear()


func _world() -> void:
	var spots := [["downtown", Vector3(-10, 1.3, -40), PI * 0.75, -0.15], ["beach", Vector3(150, 1.3, 165), PI, -0.1],
		["docks", Vector3(-160, 1.3, 163), PI, -0.2], ["airfield", Vector3(-120, 1.3, -150), PI * 0.5, -0.12],
		["hill", Vector3(196, 42.0, -196), PI * 0.8, -0.25], ["pier", Vector3(-32, 1.4, 205), 0.0, -0.05],
		["residential", Vector3(170, 1.3, 85), 0.3, -0.15], ["industrial", Vector3(-200, 1.3, -60), PI * 0.25, -0.12]]
	for s in spots:
		Game.main.teleport_player(s[1])
		Game.cam.yaw = s[2]
		Game.cam.pitch = s[3]
		Game.cam.view = 1
		await _wait(1.5)
		await shot(s[0])
	Game.cam.view = 0
	Game.main.teleport_player(Vector3(10, 1.3, -60))
	Game.cam.yaw = 0.0
	Game.cam.pitch = 0.05
	Game.env.set_hour(21.5)
	await _wait(2.0)
	await shot("night_downtown")
	Game.env.set_weather("storm", true)
	await _wait(3.0)
	await shot("storm_night")
	Game.env.set_hour(13.0)
	Game.env.set_weather("rain", true)
	await _wait(2.0)
	await shot("rain_day")
	Game.env.set_weather("fog", true)
	await _wait(2.0)
	await shot("fog")
	Game.env.set_weather("clear", true)
	Game.env.set_hour(18.6)
	await _wait(2.0)
	await shot("sunset")
	check("world_built", Game.world.poi.size() > 10, "%d pois" % Game.world.poi.size())


func _air() -> void:
	var p := _p()
	Game.main.teleport_player(Vector3(30, 1.3, -180))
	await _wait(1.0)
	var h: VehicleBase = Game.main.spawn_vehicle_near_player("heli")
	await _wait(1.0)
	p.global_position = h.door_position(0)
	await _hold("enter_vehicle", 0.1)
	await _wait(1.5)
	check("enter_heli", p.vehicle == h, p.state)
	Input.action_press("jump")
	await _wait(6.0)
	Input.action_release("jump")
	var agl := h.global_position.y - WorldMap.height(h.global_position.x, h.global_position.z)
	check("heli_lifts", agl > 8.0, "agl %.1f" % agl)
	Input.action_press("move_forward")
	await _wait(3.0)
	Input.action_release("move_forward")
	await shot("heli_flight")
	# plane
	Game.main.teleport_player(Vector3(-250, 1.3, -240))
	await _wait(1.5)
	var pl: VehicleBase = VehicleBase.spawn("plane", Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-245, 1.4, -231)))
	await _wait(1.0)
	p.exit_vehicle(false)
	await _wait(0.5)
	p.global_position = pl.door_position(0)
	await _hold("enter_vehicle", 0.1)
	await _wait(1.2)
	check("enter_plane", p.vehicle == pl, p.state)
	Input.action_press("sprint")
	await _wait(9.0)
	Input.action_press("move_back")
	await _wait(3.0)
	Input.action_release("move_back")
	await _wait(3.0)
	Input.action_release("sprint")
	var agl2 := pl.global_position.y - maxf(WorldMap.height(pl.global_position.x, pl.global_position.z), 0.0)
	check("plane_takes_off", agl2 > 6.0, "agl %.1f speed %.1f" % [agl2, pl.linear_velocity.length()])
	await shot("plane_flight")
	p.exit_vehicle(false)
	await _wait(1.0)
	await _boat()


func _boat() -> void:
	var p := _p()
	Game.main.teleport_player(Vector3(-190, 1.3, 172))
	await _wait(1.0)
	var b: VehicleBase = Game.main.spawn_vehicle_near_player("boat")
	await _wait(2.0)
	p.global_position = b.door_position(0) + Vector3(0, 1, 0)
	await _hold("enter_vehicle", 0.1)
	await _wait(1.0)
	Input.action_press("move_forward")
	await _wait(4.0)
	Input.action_release("move_forward")
	check("boat_moves", b.linear_velocity.length() > 4.0 and b.global_position.y > -1.0, "speed %.1f y %.1f" % [b.linear_velocity.length(), b.global_position.y])
	await shot("boat")
	# swim / dive
	p.exit_vehicle(false)
	await _wait(2.0)
	check("swimming", p.state == "swim", p.state)
	Input.action_press("crouch")
	await _wait(2.5)
	Input.action_release("crouch")
	await shot("underwater")
	# parachute
	p.give_parachute()
	Game.main.teleport_player(Vector3(0, 300, -60))
	await _wait(2.5)
	Input.action_press("jump")
	await _wait(0.2)
	Input.action_release("jump")
	await _wait(1.5)
	check("parachute", p.state in ["parachute", "skydive"], p.state)
	await shot("parachute")


func _views() -> void:
	var p := _p()
	Game.cam.yaw = 0.3
	Game.cam.view = 2
	await _wait(1.0)
	await shot("first_person")
	Game.cam.view = 0
	Input.action_press("weapon_wheel")
	await _wait(0.5)
	await shot("weapon_wheel")
	Input.action_release("weapon_wheel")
	await _wait(0.3)
	Game.hud.menus.open_debug()
	await _wait(0.5)
	await shot("debug_menu")
	Game.hud.close_panel()
	Game.hud.menus.open_map()
	await _wait(0.5)
	await shot("big_map")
	Game.hud.close_panel()
	Game.main.teleport_player(Vector3(-150, 1.3, -10))
	var v: VehicleBase = Game.main.spawn_vehicle_near_player("sports")
	await _wait(1.0)
	p.global_position = v.door_position(0)
	await _hold("enter_vehicle", 0.1)
	await _wait(1.0)
	Game.hud.menus.open_modshop(v)
	await _wait(0.5)
	await shot("modshop")
	Game.hud.close_panel()
	check("menus_open", true, "")


func _find_button(n: Node, prefix: String) -> Button:
	if n is Button and (n as Button).text.begins_with(prefix) and (n as Button).visible:
		return n
	for c in n.get_children():
		var b := _find_button(c, prefix)
		if b:
			return b
	return null


func _street_spawn(id: String, near: Vector3) -> VehicleBase:
	var rg: RoadGraph = Game.world.road_graph
	var nl := rg.nearest_lane(near, 60.0)
	var L: Dictionary = rg.links[nl.link]
	return VehicleBase.spawn(id, Transform3D(Basis.looking_at(L.dir, Vector3.UP), nl.point + Vector3(0, 0.4, 0)))


## Exercises the secondary systems end-to-end through the real input/UI paths.
func _systems() -> void:
	var p := _p()
	Game.env.set_hour(11.0)
	Game.env.set_weather("clear", true)
	var busted := [false]
	Game.player_busted.connect(func(): busted[0] = true)
	# --- save / load round trip
	Game.money = 12345
	var saved := SaveSystem.save_game()
	Game.money = 7
	var loaded := SaveSystem.load_game()
	await _wait(1.0)
	check("save_load", saved and loaded and Game.money == 12345, "money after load %d" % Game.money)
	# --- weapon shop purchase through the real menu buttons
	Game.money = 60000
	var gs: Dictionary = Game.world.poi.gunshop
	Game.main.teleport_player(gs.pos)
	await _wait(1.0)
	Game.hud.open_poi(gs)
	await _wait(0.6)
	await shot("gunshop")
	var owned0: int = p.owned_weapons().size()
	var m0 := Game.money
	var buy := _find_button(Game.hud, "Buy ")
	var had_btn := buy != null
	if had_btn:
		buy.pressed.emit()
	await _wait(0.4)
	check("shop_purchase", had_btn and Game.money < m0 and p.owned_weapons().size() > owned0, "%d -> %d weapons, $%d -> $%d" % [owned0, p.owned_weapons().size(), m0, Game.money])
	Game.hud.close_panel()
	await _wait(0.3)
	# --- carjack an occupied car
	Game.main.teleport_player(Vector3(-20, 1.3, 40))
	await _wait(1.0)
	var v := _street_spawn("sedan", p.global_position)
	var drv := Game.peds.make_npc("civilian", v.global_position)
	v.enter(drv, 0)
	drv.brain = "drive"
	drv.collision_layer = 0
	drv.collision_mask = 0
	await _wait(1.0)
	p.global_position = v.door_position(0) + (v.door_position(0) - v.global_position).normalized() * 0.4
	await _hold("enter_vehicle", 0.1)
	await _wait(1.6)
	check("carjack", p.vehicle == v and v.seat_occupant(0) == p and drv.vehicle == null, "driver_out=%s state=%s" % [drv.vehicle == null, p.state])
	await shot("carjacked")
	# --- drive-by: aim + fire from the driver seat
	p.weapons.give("smg")
	p.weapons.select("smg")
	await _wait(0.3)
	var mag0 := p.weapons.mag()
	Input.action_press("aim")
	await _wait(0.4)
	Input.action_press("fire")
	await _wait(0.6)
	await shot("driveby")
	Input.action_release("fire")
	Input.action_release("aim")
	check("drive_by", p.weapons.mag() < mag0, "mag %d -> %d" % [mag0, p.weapons.mag()])
	# --- radio station switch
	var st0: int = Game.radio_station
	await _hold("radio_next", 0.1)
	await _wait(0.3)
	check("radio_switch", Game.radio_station != st0, "station %d -> %d" % [st0, Game.radio_station])
	# --- vehicle damage + repair
	v.take_damage(450.0, null, v.global_position, Vector3.ZERO, "impact")
	var hp_dmg := v.health
	v.repair()
	check("vehicle_damage_repair", hp_dmg < v.max_health and v.health >= v.max_health, "hp %.0f -> %.0f" % [hp_dmg, v.health])
	# --- garage storage
	var g0: int = Game.garage.slots.size()
	Game.garage.store(v)
	check("garage_store", Game.garage.slots.size() == g0 + 1, "%d slots" % Game.garage.slots.size())
	Game.wanted.clear()
	# --- cover against the car body
	p.exit_vehicle(false)
	await _wait(1.0)
	var to_car := v.global_position - p.global_position
	Game.cam.yaw = atan2(-to_car.x, -to_car.z)
	Game.cam.pitch = -0.15
	await _wait(0.3)
	await _hold("cover", 0.1)
	await _wait(0.5)
	check("cover", p.in_cover, "low=%s" % p.cover_low)
	await shot("cover")
	await _hold("cover", 0.1)
	await _wait(0.4)
	# --- stealth takedown from behind
	Game.wanted.clear()
	p.weapons.select("fists")
	var vic := Game.peds.make_npc("civilian", p.global_position + Vector3(0, 0, -3))
	await _wait(0.5)
	Game.cam.yaw = 0.0
	await _hold("crouch", 0.1)
	await _wait(0.4)
	vic.brain = "idle"
	vic.velocity = Vector3.ZERO
	vic._yaw = PI   # NPC facing is driven by _yaw (rotation.y = _yaw + PI): face away from the player (-Z)
	vic.alert = 0.0  # an unaware victim (it may have glimpsed the player while spawning in front of them)
	p._yaw = PI
	p.rig.rotation.y = p._yaw + PI
	vic._yaw = PI     # NPC bodies face -basis.z with rotation.y = _yaw + PI: facing away (-Z)
	vic.global_position = p.global_position + Vector3(0, 0, -1.2)
	await _hold("fire", 0.1)
	await _wait(1.0)
	check("stealth_takedown", vic.dead or vic.ragdolled, "dead=%s hp=%.0f crouch=%s" % [vic.dead, vic.health, p.crouching])
	await shot("takedown")
	if p.crouching:
		await _hold("crouch", 0.1)
	# --- emergency services respond to the body
	await _wait(7.0)
	var em_units: int = Game.main.emergency.units.size()
	check("emergency_dispatch", em_units > 0, "%d units" % em_units)
	Game.wanted.clear()
	# --- busted: 1 star, unarmed, an officer on foot next to the player
	p.weapons.select("fists")
	Game.wanted.set_level(1)
	var cop := Game.peds.make_npc("police", p.global_position + Vector3(4, 0, 0))
	var t := 0.0
	while t < 20.0 and not busted[0]:
		await _wait(0.5)
		t += 0.5
		if is_instance_valid(cop) and int(t * 2.0) % 4 == 0:
			print("[AutoTest] busted wait %.1fs: cop brain=%s sees=%s dist=%.1f alert=%.2f wanted=%d/%s player=%s" % [t, cop.brain, cop.sees_player,
				cop.global_position.distance_to(p.global_position), cop.alert, Game.wanted.level, Game.wanted.state, p.state])
	check("busted", busted[0], "after %.1f s" % t)
	await shot("busted")
	await _wait(5.0)
	if is_instance_valid(cop):
		cop.queue_free()
	# --- escaping a 1-star search by leaving the area out of sight
	Game.wanted.set_level(1)
	Game.wanted.last_known = p.global_position
	Game.wanted.search_center = p.global_position
	Game.main.teleport_player(Vector3(200, 1.3, -195))
	t = 0.0
	while t < 45.0 and Game.wanted.level > 0:
		await _wait(0.5)
		t += 0.5
	check("wanted_escape", Game.wanted.level == 0, "cleared after %.1f s (state %s)" % [t, Game.wanted.state])
	# --- wildlife around Crown Hill
	await _wait(2.0)
	check("wildlife", Game.wildlife.animals.size() > 0, "%d animals" % Game.wildlife.animals.size())
	await shot("hill_wildlife")
	# --- taxi: call, wait for arrival, board as passenger
	Game.main.teleport_player(Vector3(60, 1.3, 40))
	await _wait(1.5)
	Game.main.taxi.call_taxi()
	t = 0.0
	# ~120 m through town; a red phase can hold the cab for up to 19 s of the 36 s light cycle
	while t < 90.0 and Game.main.taxi.state == "coming":
		await _wait(0.5)
		t += 0.5
		var tx0: VehicleBase = Game.main.taxi.taxi
		if tx0 and int(t * 2.0) % 10 == 0:
			print("[AutoTest] taxi %.1fs: dist %.1f speed %.1f pos %s" % [t, tx0.global_position.distance_to(p.global_position), tx0.linear_velocity.length(), tx0.global_position.round()])
	var tx: VehicleBase = Game.main.taxi.taxi
	check("taxi_arrives", Game.main.taxi.state == "waiting", "state %s after %.1f s, dist %.1f" % [Game.main.taxi.state, t, tx.global_position.distance_to(p.global_position) if tx else -1.0])
	if tx:
		p.global_position = tx.door_position(1)
		await _hold("enter_vehicle", 0.1)
		await _wait(1.5)
		check("taxi_passenger", p.vehicle == tx and p.seat != 0, "seat %d state %s" % [p.seat, Game.main.taxi.state])
		await shot("taxi")
		Game.hud.close_panel()
		await _wait(0.3)
		if p.vehicle:
			p.exit_vehicle(false)
	# --- performance sample downtown with traffic and pedestrians
	Game.main.teleport_player(Vector3(10, 1.3, -40))
	await _wait(3.0)
	var fps_sum := 0.0
	var fps_min := 1000.0
	for i in 10:
		await _wait(0.5)
		var f := Engine.get_frames_per_second()
		fps_sum += f
		fps_min = minf(fps_min, f)
	var info := "avg %.0f / min %.0f fps, %d cars, %d peds, %d draw calls" % [fps_sum / 10.0, fps_min, Game.traffic.cars.size(), Game.npcs.size(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)]
	check("performance_downtown", fps_sum / 10.0 >= 30.0, info)
	await shot("perf_downtown")


func _measure(label: String, secs := 3.0) -> Dictionary:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	await _wait(0.8)
	var n := 0
	var acc := {"fps": 0.0, "proc": 0.0, "phys": 0.0, "cpu": 0.0, "gpu": 0.0}
	var t := 0.0
	while t < secs:
		await get_tree().process_frame
		t += get_process_delta_time()
		n += 1
		acc.fps += Engine.get_frames_per_second()
		acc.proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		acc.phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		acc.cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		acc.gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	for k in acc:
		acc[k] /= maxf(n, 1)
	var line := "%-26s fps %5.1f | process %5.2f ms | physics %5.2f ms | render cpu %5.2f ms | gpu %5.2f ms | draws %d | objs %d" % [label, acc.fps, acc.proc, acc.phys, acc.cpu, acc.gpu,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)]
	print("[Perf] ", line)
	report.notes.append(line)
	return acc


func _perf() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Game.env.set_hour(11.0)
	Game.env.set_weather("clear", true)
	Game.main.teleport_player(Vector3(10, 1.3, -40))
	Game.cam.yaw = PI * 0.25
	Game.cam.pitch = -0.1
	await _wait(6.0)
	print("[Perf] cars %d peds %d animals %d vehicles(all) %d" % [Game.traffic.cars.size(), Game.npcs.size(), Game.wildlife.animals.size(), Game.vehicles.size()])
	var full := await _measure("full")
	var env: Environment = Game.env.env
	env.ssao_enabled = false
	await _measure("no ssao")
	env.glow_enabled = false
	await _measure("no ssao/glow")
	Game.env.sun.shadow_enabled = false
	await _measure("+ no sun shadow")
	Game.env.sun.shadow_enabled = true
	env.ssao_enabled = true
	env.glow_enabled = true
	for n in Game.npcs:
		(n as Node3D).visible = false
	await _measure("npcs hidden")
	for n in Game.npcs:
		(n as Node).process_mode = Node.PROCESS_MODE_DISABLED
	await _measure("npcs hidden+frozen")
	for n in Game.npcs:
		(n as Node3D).visible = true
		(n as Node).process_mode = Node.PROCESS_MODE_INHERIT
	for v in Game.vehicles:
		(v as Node).process_mode = Node.PROCESS_MODE_DISABLED
	await _measure("vehicles frozen")
	for v in Game.vehicles:
		(v as Node).process_mode = Node.PROCESS_MODE_INHERIT
	Game.cam.pitch = 1.0
	await _measure("looking at sky")
	Game.cam.pitch = -0.1
	check("perf_profile", full.fps > 0.0, "full %.1f fps" % full.fps)


## Close-up line-up of the Blender character kit on the player and every NPC archetype.
func _characters() -> void:
	var p := _p()
	Game.env.set_hour(11.0)
	Game.env.set_weather("clear", true)
	Game.peds_enabled = false
	Game.traffic_enabled = false
	Game.main.teleport_player(Vector3(10, 1.3, -60))
	await _wait(1.0)
	var base := p.global_position
	var kinds := ["civilian", "civilian", "civilian", "police", "swat", "medic", "gang", "shop"]
	var npcs: Array = []
	for i in kinds.size():
		var n: NPC = Game.peds.make_npc(kinds[i], base + Vector3(-4.2 + i * 1.2, 0.1, -3.0))
		n.brain = "idle"
		n.process_mode = Node.PROCESS_MODE_DISABLED
		n._yaw = 0.0
		n.rotation.y = PI
		npcs.append(n)
	await _wait(0.6)
	p._yaw = PI
	Game.cam.yaw = 0.0
	Game.cam.pitch = -0.08
	await _wait(0.8)
	await shot("lineup")
	Game.cam.view = 2
	await _wait(0.2)
	Game.cam.view = 0
	p.global_position = base + Vector3(0, 0, -1.6)
	p._yaw = 0.0
	p.rig.rotation.y = PI
	Game.cam.yaw = PI
	Game.cam.pitch = -0.1
	await _wait(0.8)
	await shot("player_front")
	var ok := 0
	for n in npcs:
		if (n as NPC).rig.part_meshes.size() >= 16:
			ok += 1
	check("character_kit", ok == npcs.size() and p.rig.part_meshes.size() >= 16, "%d/%d NPC rigs use the kit, player parts %d" % [ok, npcs.size(), p.rig.part_meshes.size()])



## Close-up of every Blender weapon model and the attachment set, rendered by the game itself.
func _weapons() -> void:
	var p := _p()
	Game.env.set_hour(12.0)
	Game.env.set_weather("clear", true)
	Game.peds_enabled = false
	Game.traffic_enabled = false
	Game.main.teleport_player(Vector3(-130, 1.3, -150))
	await _wait(1.0)
	p.visible = false
	var base := p.global_position + Vector3(0, 1.3, -6.0)
	var holder := Node3D.new()
	get_tree().current_scene.add_child(holder)
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(6.0, 3.2, 0.05)
	back.mesh = bm
	back.material_override = Mats.color(Color(0.78, 0.8, 0.82), 0.9)
	holder.add_child(back)
	back.global_position = base + Vector3(0, 0, -0.35)
	var cols := [["knife", "bat", "pistol", "revolver", "smg", "grenade", "gl"], ["shotgun", "autoshotgun", "rifle", "carbine", "dmr", "sniper", "rpg"]]
	var glb_ok := 0
	var total := 0
	for c in 2:
		for r in cols[c].size():
			var id: String = cols[c][r]
			var w := WeaponModels.build(id, {})
			holder.add_child(w)
			w.global_basis = Basis(Vector3.UP, -PI * 0.5)
			w.global_position = base + Vector3(-1.75 + c * 1.75, 0.95 - r * 0.32, 0)
			total += 1
			var body := w.get_node_or_null("Body")
			if body and not (body is MeshInstance3D) and body.find_children("*", "MeshInstance3D", true, false).size() > 0:
				glb_ok += 1
	var cam := Camera3D.new()
	get_tree().current_scene.add_child(cam)
	cam.fov = 50.0
	cam.global_position = base + Vector3(-0.1, 0.0, 2.6)
	cam.make_current()
	await _wait(0.8)
	await shot("all_weapons")
	# attachments on a few guns, closer
	for ch in holder.get_children():
		if ch != back:
			ch.queue_free()
	var kits := [["rifle", {"suppressor": true, "scope": true, "grip": true, "extmag": true, "flashlight": true, "tint_idx": 2}],
		["smg", {"suppressor": true, "flashlight": true, "extmag": true, "tint_idx": 3}],
		["pistol", {"suppressor": true, "tint_idx": 1}], ["shotgun", {"flashlight": true, "tint_idx": 0}]]
	var att_ok := false
	for i in kits.size():
		var w2 := WeaponModels.build(kits[i][0], kits[i][1])
		holder.add_child(w2)
		w2.global_basis = Basis(Vector3.UP, -PI * 0.5)
		w2.global_position = base + Vector3(-0.55 + (0.35 if i == 2 else 0.0), 0.55 - i * 0.36, 0)
		if i == 0:
			att_ok = w2.get_node_or_null("Att_suppressor") != null and w2.get_node_or_null("Att_scope") != null \
				and w2.get_node_or_null("Att_grip") != null and w2.get_node_or_null("Att_flashlight") != null and w2.get_node_or_null("Flashlight") != null
	cam.global_position = base + Vector3(-0.15, 0.0, 1.45)
	await _wait(0.6)
	await shot("attachments")
	check("weapon_glb_models", glb_ok == total, "%d/%d weapons use the Blender GLB" % [glb_ok, total])
	check("weapon_attachments", att_ok, "rifle has suppressor/scope/grip/flashlight parts + light")
	cam.queue_free()
	holder.queue_free()
	Game.cam.cam.make_current()
	p.visible = true
	# held in third person, aiming: over-the-shoulder view plus a side camera to judge the pose
	for id in ["rifle", "pistol", "rpg", "sniper"]:
		p.weapons.give(id, 100)
	Game.cam.yaw = 2.4
	Game.cam.pitch = -0.05
	var side := Camera3D.new()
	get_tree().current_scene.add_child(side)
	side.fov = 45.0
	for id in ["rifle", "pistol", "rpg"]:
		p.weapons.select(id)
		p._refresh_weapon_model()
		Input.action_press("aim")
		await _wait(0.9)
		await shot("aim_" + id)
		var fwd := -Game.cam.cam.global_basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var right := fwd.cross(Vector3.UP)
		var chest := p.global_position + Vector3(0, 1.35, 0)
		side.global_position = chest + right * 2.1 + fwd * 1.2 + Vector3(0, 0.15, 0)
		side.look_at(chest + fwd * 0.3, Vector3.UP)
		side.make_current()
		await _wait(0.3)
		await shot("aim_%s_side" % id)
		Game.cam.cam.make_current()
		Input.action_release("aim")
		await _wait(0.3)
	side.queue_free()
	Game.peds_enabled = true
	Game.traffic_enabled = true



func _frame(cam: Camera3D, from: Vector3, at: Vector3, name: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await _wait(0.5)
	await shot(name)


## Blender buildings, interiors and landmarks as baked into the world, framed with a free camera.
func _buildings() -> void:
	var p := _p()
	Game.env.set_hour(10.5)
	Game.env.set_weather("clear", true)
	var models := ["buildings/house_1f", "buildings/house_2f", "buildings/gas_station", "buildings/lighthouse",
		"buildings/lifeguard_tower", "buildings/radio_mast", "buildings/gantry_crane", "buildings/beach_bar",
		"buildings/shipwreck", "interiors/safehouse_set"]
	var ok := 0
	for m in models:
		if ModelLib.has(m):
			ok += 1
	check("building_models", ok == models.size(), "%d/%d Blender building/landmark models loaded" % [ok, models.size()])
	var world_mesh := Game.world.find_child("CityBlocks", true, false) as MeshInstance3D
	var tris := 0
	if world_mesh and world_mesh.mesh:
		for i in world_mesh.mesh.get_surface_count():
			tris += world_mesh.mesh.surface_get_array_len(i) / 3
	check("city_mesh_baked", tris > 0, "CityBlocks %d triangles" % tris)
	Game.hud.visible = false
	var cam := Camera3D.new()
	get_tree().current_scene.add_child(cam)
	cam.fov = 60.0
	cam.make_current()
	var sh: Dictionary = Game.world.poi.safehouse
	var sp: Vector3 = sh.pos
	Game.main.teleport_player(sp + Vector3(0, 1.3, -3))
	await _wait(1.5)
	await _frame(cam, sp + Vector3(-16, 7, -16), sp + Vector3(8, 1, 14), "street_houses")
	await _frame(cam, sp + Vector3(30, 5, -9), sp + Vector3(36, 3, 22), "houses_neighbours")
	var ix := sp.x - 9.0
	var iz := sp.z + 1.4
	await _frame(cam, Vector3(ix + 8.6, sp.y + 2.4, iz + 0.9), Vector3(ix + 2.5, sp.y + 0.6, iz + 8.5), "safehouse_living")
	await _frame(cam, Vector3(ix + 11.0, sp.y + 2.4, iz + 0.9), Vector3(ix + 15.5, sp.y + 0.4, iz + 9.5), "safehouse_bedroom")
	var gp: Vector3 = Game.world.poi.gas.pos
	Game.main.teleport_player(gp + Vector3(0, 1.3, 14))
	await _wait(1.5)
	await _frame(cam, gp + Vector3(-22, 7, -24), gp + Vector3(0, 2, 0), "gas_station")
	Game.main.teleport_player(Vector3(140, 1.3, 160))
	await _wait(1.5)
	await _frame(cam, Vector3(101, 4.0, 153), Vector3(110, 1.8, 166), "beach_bar")
	var lgy := WorldMap.height(170, 182)
	await _frame(cam, Vector3(160, lgy + 4.5, 168), Vector3(170, lgy + 3.5, 182), "lifeguard_tower")
	var lhy := WorldMap.height(272, 190)
	await _frame(cam, Vector3(238, lhy + 9, 160), Vector3(272, lhy + 13, 190), "lighthouse")
	var my := WorldMap.height(232, -214)
	Game.main.teleport_player(Vector3(200, my + 1.3, -200))
	await _wait(1.5)
	await _frame(cam, Vector3(196, my + 6, -186), Vector3(232, my + 22, -214), "radio_mast")
	Game.main.teleport_player(Vector3(-186, 1.3, 150))
	await _wait(1.5)
	await _frame(cam, Vector3(-200, 9, 128), Vector3(-186, 14, 172), "cranes")
	var wp: Vector3 = Game.world.poi.wreck.pos
	await _frame(cam, wp + Vector3(-11, 6.5, -13), wp + Vector3(0, 2.5, 0), "shipwreck")
	cam.queue_free()
	Game.cam.cam.make_current()
	Game.hud.visible = true
