class_name PoliceDispatch
extends Node
## Spawns and directs police response according to the wanted level: patrol cars, tactical vans,
## helicopters (searchlight + marksman), roadblocks, dismounting officers, search patterns.

const CARS := [0, 2, 3, 4, 4, 5]
const SWAT := [0, 0, 0, 0, 1, 2]
const HELIS := [0, 0, 0, 1, 1, 2]

var w: World
var rg: RoadGraph
var units: Array = []          # VehicleBase (cars/vans)
var helis: Array = []          # Helicopter
var roadblocks: Array = []     # [{cars:[], officers:[], t}]
var rng := RandomNumberGenerator.new()
var _t := 0.0
var _rb_t := 20.0
var _los_t := 0.0
var _heli_fire_t := 0.0
var root: Node3D


func setup(world: World) -> void:
	w = world
	rg = world.road_graph
	rng.seed = 911
	root = get_tree().current_scene.get_node("Vehicles")


func _physics_process(delta: float) -> void:
	if Game.paused or Game.player == null or Game.wanted == null:
		return
	var lvl := Game.wanted.level
	_t -= delta
	if _t <= 0.0:
		_t = 1.0
		_cleanup(lvl)
		if lvl > 0:
			_maintain(lvl)
	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = 0.25
		_vehicle_sight()
	_drive_units(delta)
	_heli_ai(delta, lvl)
	if lvl >= 3:
		_rb_t -= delta
		if _rb_t <= 0.0:
			_rb_t = 40.0 if lvl < 5 else 28.0
			_roadblock(lvl)


func _player_pos() -> Vector3:
	var p := Game.player
	return p.vehicle.global_position if p.vehicle else p.global_position


func _cleanup(lvl: int) -> void:
	var pp := _player_pos()
	for i in range(units.size() - 1, -1, -1):
		var v = units[i]
		if v == null or not is_instance_valid(v):
			units.remove_at(i)
			continue
		var d: float = v.global_position.distance_to(pp)
		if v.driver is Player:
			units.remove_at(i)
			continue
		if (lvl == 0 and d > 90.0) or d > 320.0 or (v.destroyed and d > 80.0):
			_remove_unit(v)
			units.remove_at(i)
		elif lvl == 0 and is_instance_valid(v.ai_driver):
			(v.ai_driver as AIDriver).mode = "traffic"
			v.set_siren(false)
	for i in range(helis.size() - 1, -1, -1):
		var h = helis[i]
		if h == null or not is_instance_valid(h):
			helis.remove_at(i)
			continue
		if (lvl < 3 and h.global_position.distance_to(pp) > 120.0) or h.destroyed and h.global_position.distance_to(pp) > 100.0:
			_remove_unit(h)
			helis.remove_at(i)
		elif lvl < 3:
			h.ai_mode = "leave"
	for i in range(roadblocks.size() - 1, -1, -1):
		var rb: Dictionary = roadblocks[i]
		if Game.now() - float(rb.t) > 70.0 or lvl == 0:
			for c in rb.cars:
				if is_instance_valid(c) and not (c as VehicleBase).driver is Player and (c as Node3D).global_position.distance_to(pp) > 60.0:
					_remove_unit(c)
			for o in rb.officers:
				if is_instance_valid(o) and (o as Node3D).global_position.distance_to(pp) > 60.0:
					o.queue_free()
			roadblocks.remove_at(i)


func _remove_unit(v: VehicleBase) -> void:
	for i in v.occupants.size():
		var o := v.seat_occupant(i)
		if o and not (o is Player):
			o.queue_free()
	v.queue_free()


func _maintain(lvl: int) -> void:
	var cars := 0
	var swat := 0
	for v in units:
		if is_instance_valid(v) and not (v as VehicleBase).destroyed:
			if (v as VehicleBase).def_id == "swat":
				swat += 1
			else:
				cars += 1
	if cars < CARS[lvl]:
		_spawn_car("police", lvl)
	elif swat < SWAT[lvl]:
		_spawn_car("swat", lvl)
	var live_helis := 0
	for h in helis:
		if is_instance_valid(h) and not (h as Helicopter).destroyed:
			live_helis += 1
	if live_helis < HELIS[lvl]:
		_spawn_heli()


func _spawn_point(min_d: float, max_d: float) -> Dictionary:
	var pp := Game.wanted.last_known if Game.wanted.state == "search" else _player_pos()
	var cam := Game.cam.cam
	for t in 30:
		var L: Dictionary = rg.links[rng.randi() % rg.links.size()]
		var s := rng.randf_range(3.0, maxf(L.length - 5.0, 3.5))
		var lane := rng.randi() % rg.lane_count(L.id)
		var p := rg.lane_point(L.id, lane, s)
		var d := p.distance_to(pp)
		if d < min_d or d > max_d:
			continue
		var to := p - cam.global_position
		if to.length() < 110.0 and (-cam.global_basis.z).dot(to.normalized()) > 0.4:
			continue
		var clear := true
		for o in Game.vehicles:
			if (o as Node3D).global_position.distance_to(p) < 10.0:
				clear = false
				break
		if clear:
			return {"pos": p, "link": L.id, "lane": lane, "s": s, "dir": L.dir}
	return {}


func _spawn_car(id: String, lvl: int) -> void:
	var sp := _spawn_point(80.0, 170.0)
	if sp.is_empty():
		return
	var v := VehicleBase.spawn(id, Transform3D(Basis.looking_at(sp.dir, Vector3.UP), sp.pos + Vector3(0, 0.3, 0)), root)
	v.police_unit = true
	v.linear_velocity = sp.dir * 12.0
	var n_off := 2 if (lvl >= 2 or id == "swat") else 1
	if id == "swat":
		n_off = 4
	for i in mini(n_off, v.seat_nodes.size()):
		var o := Game.peds.make_npc("swat" if id == "swat" else "police", sp.pos)
		v.enter(o, i)
		o.brain = "drive" if i == 0 else "passenger"
		o.collision_layer = 0
		o.collision_mask = 0
		o.home_vehicle = v
	var ai := AIDriver.new()
	v.add_child(ai)
	ai.attach(v, rg)
	ai.mode = "pursue"
	ai.target = Game.player
	ai.ignore_lights = true
	v.set_siren(true)
	units.append(v)


func reattach_driver(v: VehicleBase, _o: NPC) -> void:
	if not is_instance_valid(v.ai_driver):
		var ai := AIDriver.new()
		v.add_child(ai)
		ai.attach(v, rg)
	var a := v.ai_driver as AIDriver
	a.mode = "pursue"
	a.target = Game.player
	a.ignore_lights = true
	v.set_siren(true)
	if not units.has(v):
		units.append(v)


func _spawn_heli() -> void:
	var pp := _player_pos()
	var a := rng.randf() * TAU
	var pos := pp + Vector3(cos(a) * 170.0, 55.0, sin(a) * 170.0)
	var h := VehicleBase.spawn("police_heli", Transform3D(Basis.looking_at((pp - pos) * Vector3(1, 0, 1), Vector3.UP), pos), root) as Helicopter
	var pilot := Game.peds.make_npc("police", pos)
	h.enter(pilot, 0)
	pilot.brain = "drive"
	pilot.collision_layer = 0
	pilot.collision_mask = 0
	var gunner := Game.peds.make_npc("swat", pos)
	h.enter(gunner, 1)
	gunner.brain = "passenger"
	gunner.collision_layer = 0
	gunner.collision_mask = 0
	h.rotor = 1.0
	h.engine_on = true
	h.ai_mode = "orbit"
	h.linear_velocity = (pp - pos).normalized() * 20.0
	helis.append(h)
	Game.notify("Police helicopter inbound", "warn")


# ------------------------------------------------------------------ unit behaviour

func _drive_units(_delta: float) -> void:
	var p := Game.player
	var pp := _player_pos()
	var search := Game.wanted.state == "search"
	for v in units:
		var veh := v as VehicleBase
		if not is_instance_valid(veh) or veh.destroyed:
			continue
		var ai := veh.ai_driver as AIDriver
		if ai == null:
			continue
		if Game.wanted.level == 0:
			continue
		if search:
			# drive toward search area points
			if ai.mode == "pursue":
				ai.set_destination(Game.wanted.search_center + Vector3(rng.randf_range(-40, 40), 0, rng.randf_range(-40, 40)))
				ai.ignore_lights = true
			elif ai.mode == "goto" and ai.arrived:
				ai.set_destination(Game.wanted.search_center + Vector3(rng.randf_range(-60, 60), 0, rng.randf_range(-60, 60)))
		else:
			if ai.mode != "pursue":
				ai.mode = "pursue"
				ai.target = p
		# dismount when close to an on-foot player
		var d := veh.global_position.distance_to(pp)
		if p.vehicle == null and d < 22.0 and veh.linear_velocity.length() < 6.0 and not search:
			for i in veh.occupants.size():
				var o := veh.seat_occupant(i)
				if o is NPC:
					var npc := o as NPC
					veh.eject(npc, false)
					npc.brain = "chase"
					npc.home_vehicle = veh
					npc._refresh_weapon_model()
			ai.mode = "idle"


func _vehicle_sight() -> void:
	if Game.wanted.level == 0:
		return
	var p := Game.player
	var target := p.global_position + Vector3(0, 1.2, 0)
	for v in units:
		var veh := v as VehicleBase
		if not is_instance_valid(veh) or veh.driver == null or veh.destroyed:
			continue
		var from := veh.global_position + Vector3(0, 1.4, 0)
		if from.distance_to(target) > 75.0:
			continue
		var ex := [veh, p]
		if p.vehicle:
			ex.append(p.vehicle)
		if U.ray(from, target, C.MASK_SIGHT, ex).is_empty():
			Game.wanted.police_sees(veh, p.global_position)
	for h in helis:
		var heli := h as Helicopter
		if not is_instance_valid(heli) or heli.destroyed or heli.driver == null:
			continue
		var from2 := heli.global_position + Vector3(0, -0.5, 0)
		var rng_m := 140.0 if Game.night_factor < 0.5 else 90.0
		if from2.distance_to(target) > rng_m:
			continue
		var ex2 := [heli, p]
		if p.vehicle:
			ex2.append(p.vehicle)
		if U.ray(from2, target, C.MASK_SIGHT, ex2).is_empty():
			Game.wanted.police_sees(heli, p.global_position)


func _heli_ai(delta: float, lvl: int) -> void:
	var p := Game.player
	var pp := Game.wanted.last_known if Game.wanted.state == "search" else _player_pos()
	_heli_fire_t -= delta
	for h in helis:
		var heli := h as Helicopter
		if not is_instance_valid(heli) or heli.destroyed or heli.driver == null:
			continue
		var t := Game.now() * 0.25 + float(heli.get_instance_id() % 7)
		var orbit := pp + Vector3(cos(t) * 38.0, 0, sin(t) * 38.0)
		var ground := maxf(WorldMap.height(orbit.x, orbit.z), C.SEA_LEVEL)
		orbit.y = ground + 42.0
		if heli.ai_mode == "leave":
			orbit = heli.global_position + Vector3(0, 20, 0) + (heli.global_position - pp).normalized() * 50.0
		var to := orbit - heli.global_position
		var local := heli.global_basis.inverse() * Vector3(to.x, 0, to.z)
		var c := {}
		c["up"] = clampf(to.y * 0.15, -1.0, 1.0)
		c["pitch"] = clampf(-local.z * 0.03, -1.0, 1.0)
		c["roll"] = clampf(local.x * 0.03, -1.0, 1.0)
		var face := pp - heli.global_position
		var fl := heli.global_basis.inverse() * Vector3(face.x, 0, face.z)
		c["yaw"] = clampf(atan2(-fl.x, -fl.z) * 1.5, -1.0, 1.0)
		heli.set_controls(c)
		# marksman
		if lvl >= 4 and _heli_fire_t <= 0.0 and Game.wanted.state == "pursuit":
			var from := heli.global_position + heli.global_basis * Vector3(1.0, 0.6, -0.8)
			var tgt := p.global_position + Vector3(0, 1.0, 0)
			if from.distance_to(tgt) < 110.0 and U.ray(from, tgt, C.MASK_SIGHT, [heli]).is_empty():
				var dir := (tgt - from).normalized()
				var sd := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.06
				var hit := U.ray(from, from + (dir + sd).normalized() * 140.0, C.MASK_BULLET, [heli])
				VFX.tracer(from, hit.position if not hit.is_empty() else from + dir * 140.0)
				Audio.play_3d("shot_rifle", from, -2.0)
				if not hit.is_empty():
					var tnode := U.find_ancestor_with_method(hit.collider as Node, "take_damage") if hit.collider is Node else null
					if tnode:
						tnode.take_damage(14.0, heli, hit.position, dir * 3.0, "bullet")
					VFX.impact(hit.position, hit.normal, U.surface_of(hit.collider))
			_heli_fire_t = 0.35


# ------------------------------------------------------------------ roadblocks

func _roadblock(lvl: int) -> void:
	var p := Game.player
	if p.vehicle == null:
		return
	var v := p.vehicle
	var fwd := v.linear_velocity
	if fwd.length() < 6.0:
		return
	fwd = fwd.normalized()
	var best := {}
	var bs := -INF
	for L in rg.links:
		var mid: Vector3 = (L.start + L.end) * 0.5
		var rel: Vector3 = mid - v.global_position
		var d := rel.length()
		if d < 70.0 or d > 150.0:
			continue
		var score := rel.normalized().dot(fwd) * 100.0 - absf(d - 100.0)
		var to_cam := mid - Game.cam.cam.global_position
		if score > bs and to_cam.length() > 60.0:
			bs = score
			best = L
	if best.is_empty() or bs < 40.0:
		return
	var mid2: Vector3 = (best.start + best.end) * 0.5
	var dir: Vector3 = best.dir
	var right := dir.cross(Vector3.UP).normalized()
	var rb := {"cars": [], "officers": [], "t": Game.now()}
	var hw := 4.0 if best.lanes == 1 else 7.0
	for k: float in [-1.0, 1.0]:
		var pos := mid2 + right * k * hw * 0.5 + Vector3(0, 0.3, 0)
		var basis := Basis.looking_at(right * k, Vector3.UP)
		var car := VehicleBase.spawn("police" if lvl < 4 else "swat", Transform3D(basis, pos), root)
		car.police_unit = true
		car.set_siren(true)
		car.sleeping = true
		rb.cars.append(car)
		var o := Game.peds.make_npc("police" if lvl < 4 else "swat", pos - dir * 3.0 + right * k * 1.5)
		o.brain = "attack" if lvl >= 2 else "chase"
		o.home_vehicle = car
		rb.officers.append(o)
	if lvl >= 4:
		_spike_strip(mid2 - dir * 8.0, right, hw)
	roadblocks.append(rb)
	Game.notify("Roadblock ahead!", "warn")


func _spike_strip(pos: Vector3, right: Vector3, hw: float) -> void:
	var strip := SpikeStrip.new()
	get_tree().current_scene.add_child(strip)
	strip.setup(pos, right, hw * 2.0)
