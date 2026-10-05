class_name TaxiService
extends Node
## Phone-requested taxi: drives to the player, player boards as passenger (F), picks a destination
## (map waypoint or a landmark), rides there with the AI driver or skips the trip for a fare.

var taxi: VehicleBase = null
var driver: NPC = null
var state := "none"          # none, coming, waiting, riding
var dest := Vector3.ZERO
var _min_d := INF
var _t := 0.0
var _start_pos := Vector3.ZERO


func call_taxi() -> void:
	if state != "none" and is_instance_valid(taxi):
		Game.notify("A taxi is already on its way", "info")
		return
	var rg: RoadGraph = Game.world.road_graph
	var pp := Game.player.global_position
	var best := {}
	for t in 40:
		var L: Dictionary = rg.links[randi() % rg.links.size()]
		var p := rg.lane_point(L.id, 0, L.length * 0.3)
		var d := p.distance_to(pp)
		if d > 60.0 and d < 140.0:
			best = {"link": L.id, "pos": p, "dir": L.dir}
			break
	if best.is_empty():
		var nl := rg.nearest_lane(pp + Vector3(40, 0, 0), 120.0)
		if nl.is_empty():
			Game.notify("No taxis available", "warn")
			return
		best = {"link": nl.link, "pos": nl.point, "dir": rg.links[nl.link].dir}
	taxi = VehicleBase.spawn("taxi", Transform3D(Basis.looking_at(best.dir, Vector3.UP), best.pos + Vector3(0, 0.4, 0)))
	driver = Game.peds.make_npc("civilian", best.pos)
	taxi.enter(driver, 0)
	driver.brain = "drive"
	driver.collision_layer = 0
	driver.collision_mask = 0
	var ai := AIDriver.new()
	taxi.add_child(ai)
	ai.attach(taxi, rg)
	var target := rg.nearest_lane(pp, 60.0)
	ai.set_destination(target.point if not target.is_empty() else pp)
	ai.arrive_radius = 9.0
	state = "coming"
	_min_d = INF
	Game.notify("Gold Line Taxi dispatched — it's on the radar", "good")
	Audio.play_ui("phone")


func _physics_process(delta: float) -> void:
	if state == "none":
		return
	if not is_instance_valid(taxi) or taxi.destroyed or not is_instance_valid(driver) or driver.dead or taxi.driver != driver:
		state = "none"
		return
	var p := Game.player
	var ai := taxi.ai_driver as AIDriver
	match state:
		"coming":
			# pull over at the destination, next to the player, or as soon as the cab is close and the lane
			# route starts leading it away again (one-way approach loops around a block otherwise)
			var d := taxi.global_position.distance_to(p.global_position)
			_min_d = minf(_min_d, d)
			if ai.arrived or d < 12.0 or (d < 40.0 and d > _min_d + 4.0):
				state = "waiting"
				ai.mode = "idle"
				taxi.horn(true)
				get_tree().create_timer(0.5).timeout.connect(func(): if is_instance_valid(taxi): taxi.horn(false))
				Game.notify("Your taxi is here — press F near it to get in", "hint")
		"waiting":
			if p.vehicle == taxi:
				state = "choose"
				_choose_destination()
		"choose":
			if p.vehicle != taxi:
				state = "waiting"
		"riding":
			_t += delta
			if p.vehicle != taxi:
				state = "none"
				ai.mode = "traffic"
				return
			if ai.arrived or taxi.global_position.distance_to(dest) < 14.0:
				_arrive()


## Player tried to enter the taxi: put them in a passenger seat instead of the driver's.
func passenger_seat() -> int:
	if not is_instance_valid(taxi):
		return -1
	return taxi.free_seat(true)


func _choose_destination() -> void:
	var hud: HUD = Game.hud
	var f := hud.menus._frame("GOLD LINE TAXI", "Where to? Fare is $3 per 10 m. Skip the trip for a flat $50 extra.", 520)
	var l: VBoxContainer = f.list
	if hud.has_waypoint:
		hud.menus._row(l, "Drive to my waypoint", func(): _go(hud.waypoint, false))
		hud.menus._row(l, "Skip trip to waypoint", func(): _go(hud.waypoint, true))
	for tp in WorldMap.TELEPORTS:
		if str(tp[0]).contains("boat"):
			continue
		hud.menus._row(l, "→ " + str(tp[0]), func(): _go(tp[1], false))
		hud.menus._row(l, "   (skip trip)", func(): _go(tp[1], true))
	hud.open_panel(f.root)


func _go(p: Vector3, skip: bool) -> void:
	Game.hud.close_panel()
	var rg: RoadGraph = Game.world.road_graph
	var nl := rg.nearest_lane(p, 80.0)
	dest = nl.point if not nl.is_empty() else p
	_start_pos = taxi.global_position
	if skip:
		var fare := int(_start_pos.distance_to(dest) * 0.3) + 50
		Game.add_money(-mini(fare, Game.money))
		var ai := taxi.ai_driver as AIDriver
		Game.main.fade(func():
			var L: Dictionary = rg.links[nl.link] if not nl.is_empty() else {}
			var basis := Basis.looking_at(L.dir, Vector3.UP) if not L.is_empty() else Basis.IDENTITY
			taxi.global_transform = Transform3D(basis, dest + Vector3(0, 0.5, 0))
			taxi.linear_velocity = Vector3.ZERO
			taxi.reset_physics_interpolation()
			ai.mode = "idle"
			_arrive())
		return
	var ai2 := taxi.ai_driver as AIDriver
	ai2.set_destination(dest)
	ai2.arrive_radius = 12.0
	state = "riding"
	_t = 0.0
	Game.notify("Sit back and enjoy the ride (F to bail out)", "hint")


func _arrive() -> void:
	var fare := int(_start_pos.distance_to(dest) * 0.3)
	Game.add_money(-mini(fare, Game.money))
	Game.notify("Arrived. Fare: " + U.money_str(fare), "good")
	if Game.player.vehicle == taxi:
		Game.player.exit_vehicle(false)
	var ai := taxi.ai_driver as AIDriver
	ai.mode = "traffic"
	state = "none"
