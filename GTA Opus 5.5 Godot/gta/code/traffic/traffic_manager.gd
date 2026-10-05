class_name TrafficManager
extends Node
## Spawns/despawns civilian traffic around the player on the lane graph, plus parked cars.

var rg: RoadGraph
var w: World
var cars: Array = []
var parked: Array = []
var rng := RandomNumberGenerator.new()
var _t := 0.0
var _pt := 0.0
var density := 1.0
var root: Node3D
var _warm_until := 4.0


func setup(world: World) -> void:
	w = world
	rg = world.road_graph
	rng.seed = 2024
	root = get_tree().current_scene.get_node("Vehicles")


func _physics_process(delta: float) -> void:
	if Game.paused or Game.player == null:
		return
	rg.update(delta, w.props)
	_t -= delta
	if _t <= 0.0:
		_t = 0.5
		_manage_traffic()
	_pt -= delta
	if _pt <= 0.0:
		_pt = 1.5
		_manage_parked()


func target_count() -> int:
	if not Game.traffic_enabled:
		return 0
	var n := 22.0 * density
	if Game.night_factor > 0.6:
		n *= 0.6
	return int(n)


func _player_pos() -> Vector3:
	var p := Game.player
	return p.vehicle.global_position if p.vehicle else p.global_position


func _manage_traffic() -> void:
	var pp := _player_pos()
	var cam := Game.cam.cam if Game.cam else null
	# despawn
	for i in range(cars.size() - 1, -1, -1):
		var v = cars[i]
		if v == null or not is_instance_valid(v):
			cars.remove_at(i)
			continue
		var d: float = v.global_position.distance_to(pp)
		var owned_by_player: bool = (v.driver is Player) or bool(v.owner_is_player)
		if owned_by_player:
			cars.remove_at(i)
			continue
		if d > 210.0 or (d > 140.0 and not _visible(cam, v.global_position)) or (v.destroyed and d > 70.0) or not Game.traffic_enabled and d > 40.0:
			_despawn(v)
			cars.remove_at(i)
	# spawn: candidate links are pre-filtered by distance so the city fills quickly; during the first
	# seconds (behind the loading fade) cars may appear in view to populate the streets at once.
	var want := target_count()
	if cars.size() >= want:
		return
	var near: Array = []
	for L in rg.links:
		var mid: Vector3 = (L.start + L.end) * 0.5
		var dm := mid.distance_to(pp)
		if dm > 40.0 and dm < 175.0:
			near.append(L)
	if near.is_empty():
		return
	var warmup := Game.now() < _warm_until
	var tries := 0
	while cars.size() < want and tries < (24 if warmup else 6):
		tries += 1
		_try_spawn(pp, cam, near[rng.randi() % near.size()], warmup)


func _visible(cam: Camera3D, p: Vector3) -> bool:
	if cam == null:
		return false
	var to := p - cam.global_position
	return (-cam.global_basis.z).dot(to.normalized()) > 0.45 and to.length() < 160.0


func _try_spawn(pp: Vector3, cam: Camera3D, L: Dictionary, warmup := false) -> void:
	var s := rng.randf_range(4.0, maxf(L.length - 8.0, 4.5))
	var lane := rng.randi() % rg.lane_count(L.id)
	var p := rg.lane_point(L.id, lane, s)
	var d := p.distance_to(pp)
	if d < (25.0 if warmup else 55.0) or d > 170.0:
		return
	if not warmup and d < 120.0 and _visible(cam, p):
		return
	for o in Game.vehicles:
		if (o as Node3D).global_position.distance_to(p) < 14.0:
			return
	var id: String = VehicleDB.TRAFFIC_POOL[rng.randi() % VehicleDB.TRAFFIC_POOL.size()]
	var basis := Basis.looking_at(L.dir, Vector3.UP)
	var m := {"paint": VehicleDB.PAINTS[rng.randi() % VehicleDB.PAINTS.size()]} if id not in ["taxi"] else {}
	var v := VehicleBase.spawn(id, Transform3D(basis, p + Vector3(0, 0.25, 0)), root, m)
	v.traffic_owned = true
	v.linear_velocity = L.dir * 8.0
	var drv := Game.peds.make_npc("civilian", p)
	v.enter(drv, 0)
	drv.brain = "drive"
	drv.collision_layer = 0
	drv.collision_mask = 0
	var ai := AIDriver.new()
	v.add_child(ai)
	ai.attach(v, rg)
	ai.start_on_lane(L.id, lane, s)
	cars.append(v)


func _despawn(v: VehicleBase) -> void:
	for i in v.occupants.size():
		var o := v.seat_occupant(i)
		if o and not (o is Player):
			o.queue_free()
	v.queue_free()


func _manage_parked() -> void:
	var pp := _player_pos()
	for i in range(parked.size() - 1, -1, -1):
		var v = parked[i]
		if v == null or not is_instance_valid(v):
			parked.remove_at(i)
			continue
		if v.owner_is_player or v.driver != null:
			parked.remove_at(i)
			continue
		if v.global_position.distance_to(pp) > 170.0:
			v.queue_free()
			parked.remove_at(i)
	if not Game.traffic_enabled:
		return
	for spot in w.parking_spots:
		if parked.size() >= 26:
			break
		var xf: Transform3D = spot.xform
		var d := xf.origin.distance_to(pp)
		if d > 120.0 or d < 30.0:
			continue
		if spot.get("used", false):
			if is_instance_valid(spot.get("veh")):
				continue
			if spot.get("cool", 0.0) > Game.now():
				continue
		var busy := false
		for o in Game.vehicles:
			if (o as Node3D).global_position.distance_to(xf.origin) < 4.0:
				busy = true
				break
		if busy:
			continue
		var kind: String = spot.get("kind", "lot")
		var id: String
		if kind == "police":
			id = "police"
		else:
			id = VehicleDB.PARKED_POOL[rng.randi() % VehicleDB.PARKED_POOL.size()]
		var m := {"paint": VehicleDB.PAINTS[rng.randi() % VehicleDB.PAINTS.size()]} if kind != "police" else {}
		var v := VehicleBase.spawn(id, xf, root, m)
		v.parked = true
		v.engine_on = false
		v.sleeping = true
		parked.append(v)
		spot["used"] = true
		spot["veh"] = v
		spot["cool"] = Game.now() + 60.0


func clear_all() -> void:
	for v in cars:
		if is_instance_valid(v):
			_despawn(v)
	cars.clear()
