class_name AIDriver
extends Node
## Lane-graph driver: follows lanes and intersection connectors, obeys signals, keeps distance,
## brakes for pedestrians, honks, and supports panic / goto / pursue / roadblock modes.

var v: VehicleBase
var rg: RoadGraph
var mode := "traffic"            # traffic, panic, goto, pursue, park, idle
var points: Array = []           # [{pos, link, lane, stop:bool, node, approach}]
var cur_link := -1
var cur_lane := 0
var speed_limit := 13.0
var dest := Vector3.ZERO
var arrived := false
var arrive_radius := 10.0
var target: Node3D = null        # pursue target
var ignore_lights := false
var cruise_mul := 1.0
var _stuck_t := 0.0
var _honk_t := 0.0
var _reverse_t := 0.0
var _route: Array = []
var _repath_t := 0.0
var _think := 0.0
var _blocked_speed := 999.0
var _ram_t := 0.0
# going around an abandoned / parked / wrecked vehicle that blocks the lane
var _static_block: VehicleBase = null
var _static_wait_t := 0.0
var _pass_obj: VehicleBase = null
var _pass_t := 0.0
var _pass_side := -1.0


func attach(vehicle: VehicleBase, graph: RoadGraph) -> void:
	v = vehicle
	rg = graph
	v.ai_driver = self
	cruise_mul = randf_range(0.85, 1.08)


func start_on_lane(link: int, lane: int, s: float) -> void:
	cur_link = link
	cur_lane = lane
	points.clear()
	var L: Dictionary = rg.links[link]
	points.append({"pos": rg.lane_point(link, lane, minf(s + 6.0, L.length)), "link": link, "lane": lane, "stop": false})
	points.append({"pos": rg.lane_point(link, lane, L.length), "link": link, "lane": lane, "stop": true, "node": L.to, "approach": L.approach})
	speed_limit = L.speed


func _physics_process(delta: float) -> void:
	if v == null or not is_instance_valid(v) or v.destroyed:
		return
	if v.driver == null or v.driver is Player:
		v.set_controls({"throttle": 0.0, "steer": 0.0, "handbrake": 1.0})
		return
	_think -= delta
	if _think <= 0.0:
		_think = 0.12
		_scan_ahead()
	match mode:
		"pursue":
			_pursue(delta)
		"idle", "park":
			v.set_controls({"throttle": 0.0, "steer": 0.0, "handbrake": 1.0})
		_:
			_follow(delta)


# ------------------------------------------------------------------ lane following

func _ensure_points() -> void:
	while points.size() < 4:
		var last: Dictionary = points[points.size() - 1] if points.size() > 0 else {}
		if last.is_empty() or not last.has("link"):
			var nl := rg.nearest_lane(v.global_position, 60.0)
			if nl.is_empty():
				return
			start_on_lane(nl.link, nl.lane, nl.s)
			continue
		var lid: int = last.link
		var opts := rg.next_links(lid)
		if opts.is_empty():
			return
		var choice: Dictionary = opts[randi() % opts.size()]
		if mode == "goto" and not _route.is_empty():
			choice = _route_choice(lid, opts)
		var out_lane := 0
		var nlanes := rg.lane_count(choice.link)
		if choice.turn == 1:
			out_lane = nlanes - 1
		elif choice.turn == -1:
			out_lane = 0
		else:
			out_lane = mini(int(last.lane), nlanes - 1)
		var conn := rg.connector(lid, int(last.lane), choice.link, out_lane, 5)
		for p in conn:
			points.append({"pos": p, "link": choice.link, "lane": out_lane, "stop": false, "turn": choice.turn != 0})
		var L: Dictionary = rg.links[choice.link]
		points.append({"pos": rg.lane_point(choice.link, out_lane, L.length * 0.5), "link": choice.link, "lane": out_lane, "stop": false})
		points.append({"pos": rg.lane_point(choice.link, out_lane, L.length), "link": choice.link, "lane": out_lane, "stop": true, "node": L.to, "approach": L.approach})


func _route_choice(lid: int, opts: Array) -> Dictionary:
	var at: int = rg.links[lid].to
	var nxt := rg.next_hop(at, dest)
	for o in opts:
		if rg.links[o.link].to == nxt:
			return o
	return opts[0]


func _follow(delta: float) -> void:
	_ensure_points()
	if points.is_empty():
		v.set_controls({"throttle": 0.0, "steer": 0.0, "handbrake": 1.0})
		return
	var pos := v.global_position
	var fwd := -v.global_basis.z
	# pop reached points
	while points.size() > 1:
		var p0: Vector3 = points[0].pos
		var to0 := p0 - pos
		to0.y = 0
		if to0.length() < 3.5 or to0.normalized().dot(fwd) < -0.2 and to0.length() < 9.0:
			var popped: Dictionary = points.pop_front()
			if popped.has("link"):
				cur_link = popped.link
				cur_lane = popped.lane
				speed_limit = rg.links[cur_link].speed
		else:
			break
	var spd := v.linear_velocity.dot(fwd)
	var look := 5.0 + absf(spd) * 0.55
	var tgt := _lookahead(pos, look)
	var passing := _update_pass(delta, pos, fwd, spd)
	if passing:
		tgt += v.global_basis.x * (_pass_side * 3.4)
	var desired := speed_limit * cruise_mul
	if mode == "panic":
		desired = speed_limit * 1.6
	elif mode == "goto":
		desired = speed_limit * 1.05
		if dest.distance_to(pos) < 30.0:
			desired = minf(desired, 6.0)
		if dest.distance_to(pos) < arrive_radius:
			arrived = true
			v.set_controls({"throttle": 0.0, "steer": 0.0, "handbrake": 1.0})
			return
	# curvature slow-down
	for i in mini(points.size(), 4):
		if points[i].get("turn", false):
			var d := (points[i].pos as Vector3).distance_to(pos)
			desired = minf(desired, lerpf(6.5, desired, clampf((d - 6.0) / 25.0, 0.0, 1.0)))
			break
	# signals
	if not ignore_lights and mode != "panic":
		for i in mini(points.size(), 3):
			var pt: Dictionary = points[i]
			if pt.stop:
				var st := rg.signal_state(pt.node, pt.approach)
				var d2 := (pt.pos as Vector3).distance_to(pos)
				if st != RoadGraph.GREEN:
					var stop_d := d2 - 2.0
					if st == RoadGraph.YELLOW and stop_d < spd * spd / 10.0 - 2.0:
						break
					desired = minf(desired, sqrt(maxf(stop_d, 0.0) * 6.0))
				break
	desired = minf(desired, _blocked_speed)
	if passing:
		desired = minf(desired, 7.0)
	_drive_to(tgt, desired, delta)
	_stuck_logic(delta, spd, desired)


## Lane-blocking vehicles without a driver (abandoned, parked badly, wrecked) are passed on whichever
## neighbouring lane is clear once the car has waited behind one for 2 s; drivers waiting at signals or
## in queues have drivers and are never overtaken.
func _update_pass(delta: float, pos: Vector3, fwd: Vector3, spd: float) -> bool:
	if _pass_t > 0.0:
		_pass_t -= delta
		if _pass_obj == null or not is_instance_valid(_pass_obj):
			_pass_t = 0.0
			return false
		if (_pass_obj.global_position - pos).dot(fwd) < -(v.half_extents.z + _pass_obj.half_extents.z + 1.5):
			_pass_t = 0.0
			return false
		return true
	if _static_block != null and is_instance_valid(_static_block) and absf(spd) < 1.0 and mode != "pursue":
		_static_wait_t += delta
		if _static_wait_t > 2.0:
			_static_wait_t = 0.0
			_pass_obj = _static_block
			_pass_t = 9.0
			_pass_side = -1.0 if _side_free(pos, -1.0) or not _side_free(pos, 1.0) else 1.0
			return true
	else:
		_static_wait_t = 0.0
	return false


func _side_free(pos: Vector3, side: float) -> bool:
	var fwd := -v.global_basis.z
	var right := v.global_basis.x
	for o in Game.vehicles:
		var ov := o as VehicleBase
		if ov == null or ov == v or not is_instance_valid(ov) or ov == _static_block:
			continue
		var rel := ov.global_position - pos
		if absf(rel.x) > 30.0 or absf(rel.z) > 30.0:
			continue
		var lat := rel.dot(right) * side
		var along := rel.dot(fwd)
		if lat > 1.5 and lat < 5.5 and along > -6.0 and along < 22.0:
			return false
	return true


func _lookahead(pos: Vector3, dist: float) -> Vector3:
	var acc := 0.0
	var prev := pos
	for p in points:
		var q: Vector3 = p.pos
		var seg := prev.distance_to(q)
		if acc + seg >= dist:
			return prev.lerp(q, (dist - acc) / maxf(seg, 0.001))
		acc += seg
		prev = q
	return prev


func _drive_to(tgt: Vector3, desired: float, _delta: float) -> void:
	var fwd := -v.global_basis.z
	var to := tgt - v.global_position
	to.y = 0
	var f2 := Vector3(fwd.x, 0, fwd.z).normalized()
	var ang := f2.signed_angle_to(to.normalized(), Vector3.UP)
	var spd := v.linear_velocity.dot(fwd)
	var steer := clampf(ang * 2.4, -1.0, 1.0)
	var throttle := 0.0
	if _reverse_t > 0.0:
		throttle = -0.7
		steer = -steer
	else:
		var err := desired - spd
		throttle = clampf(err * 0.35, -1.0, 1.0)
		if desired < 0.5 and spd < 0.6:
			throttle = 0.0
	v.set_controls({"throttle": throttle, "steer": steer, "handbrake": 1.0 if desired < 0.3 and absf(spd) < 0.5 else 0.0})


func _stuck_logic(delta: float, spd: float, desired: float) -> void:
	if _reverse_t > 0.0:
		_reverse_t -= delta
		return
	if desired > 2.0 and absf(spd) < 0.6:
		_stuck_t += delta
		if _stuck_t > 2.5 and _honk_t <= 0.0:
			v.horn(true)
			_honk_t = 0.6
		if _stuck_t > 7.0:
			_stuck_t = 0.0
			_reverse_t = 1.6
	else:
		_stuck_t = maxf(_stuck_t - delta, 0.0)
	if _honk_t > 0.0:
		_honk_t -= delta
		if _honk_t <= 0.0:
			v.horn(false)


## Detect vehicles / pedestrians ahead and set a speed cap.
func _scan_ahead() -> void:
	_blocked_speed = 999.0
	_static_block = null
	var static_gap := 12.0
	var pos := v.global_position
	var fwd := -v.global_basis.z
	var right := v.global_basis.x
	var my_len := v.half_extents.z
	for o in Game.vehicles:
		var ov := o as VehicleBase
		if ov == v or ov == null or not is_instance_valid(ov):
			continue
		var rel := ov.global_position - pos
		if absf(rel.x) > 40.0 or absf(rel.z) > 40.0:
			continue
		var along := rel.dot(fwd)
		var lat := rel.dot(right)
		if along > 0.0 and along < 30.0 and absf(lat) < 2.3 + absf(along) * 0.02:
			if mode == "pursue" and ov == _target_vehicle():
				continue
			if _pass_t > 0.0 and ov == _pass_obj:
				continue
			var gap := along - my_len - ov.half_extents.z
			var ov_spd := maxf(ov.linear_velocity.dot(fwd), 0.0)
			if (ov.driver == null or ov.destroyed) and ov.linear_velocity.length_squared() < 0.25 and gap < static_gap:
				static_gap = gap
				_static_block = ov
			_blocked_speed = minf(_blocked_speed, maxf(ov_spd + (gap - 4.0) * 0.7, 0.0))
	# pedestrians & player on foot
	if mode != "panic":
		for n in Game.npcs:
			var a := n as Actor
			if a == null or a.vehicle != null or a.dead:
				continue
			var rel2 := a.global_position - pos
			if absf(rel2.x) > 20.0 or absf(rel2.z) > 20.0:
				continue
			var along2 := rel2.dot(fwd)
			if along2 > 0.0 and along2 < 14.0 and absf(rel2.dot(right)) < 1.8:
				_blocked_speed = minf(_blocked_speed, maxf((along2 - my_len - 2.5) * 0.8, 0.0))
		var p := Game.player
		if p and p.vehicle == null and not p.dead and mode != "pursue":
			var rel3 := p.global_position - pos
			var along3 := rel3.dot(fwd)
			if along3 > 0.0 and along3 < 14.0 and absf(rel3.dot(right)) < 1.8:
				_blocked_speed = minf(_blocked_speed, maxf((along3 - my_len - 2.5) * 0.8, 0.0))


# ------------------------------------------------------------------ goto / pursue

func set_destination(p: Vector3) -> void:
	mode = "goto"
	dest = p
	arrived = false
	_route = rg.route(v.global_position, p)
	points.clear()
	var nl := rg.nearest_lane(v.global_position, 60.0)
	if not nl.is_empty():
		start_on_lane(nl.link, nl.lane, nl.s)


func _target_vehicle() -> VehicleBase:
	if target is Player and (target as Player).vehicle:
		return (target as Player).vehicle
	return target as VehicleBase


func _pursue(delta: float) -> void:
	var t_pos: Vector3
	var tv := _target_vehicle()
	if target == null or not is_instance_valid(target):
		mode = "traffic"
		return
	t_pos = tv.global_position if tv else target.global_position
	var pos := v.global_position
	var dist := pos.distance_to(t_pos)
	var spd := v.linear_velocity.dot(-v.global_basis.z)
	var los := dist < 70.0 and U.ray(pos + Vector3(0, 1.2, 0), t_pos + Vector3(0, 1.0, 0), C.L_WORLD, [v]).is_empty()
	if los or dist < 25.0:
		var aim := t_pos
		if tv:
			# PIT / ram: aim at the rear quarter, lead the target
			var lead := tv.linear_velocity * clampf(dist / 30.0, 0.0, 1.2)
			var side := tv.global_basis.x * (1.2 if fmod(Time.get_ticks_msec() * 0.0002, 2.0) > 1.0 else -1.2)
			aim = t_pos + lead + (side + tv.global_basis.z * 1.6 if dist < 12.0 else Vector3.ZERO)
		var desired := 40.0 if dist > 15.0 else (tv.linear_velocity.length() + 4.0 if tv else 4.0)
		if not tv and dist < 14.0:
			desired = 0.0
		_drive_to(aim, desired, delta)
		_stuck_logic(delta, spd, desired)
		points.clear()
		_route.clear()
	else:
		# route along roads toward the target / last known position
		_repath_t -= delta
		if _repath_t <= 0.0 or points.size() < 2:
			_repath_t = 3.0
			_route = rg.route(pos, t_pos)
			points.clear()
			for i in range(1, _route.size()):
				points.append({"pos": _route[i], "stop": false})
		while points.size() > 1 and (points[0].pos as Vector3).distance_to(pos) < 8.0:
			points.pop_front()
		if points.is_empty():
			return
		var tgt := _lookahead(pos, 8.0 + absf(spd) * 0.5)
		_drive_to(tgt, minf(32.0, _blocked_speed + 10.0), delta)
		_stuck_logic(delta, spd, 20.0)
