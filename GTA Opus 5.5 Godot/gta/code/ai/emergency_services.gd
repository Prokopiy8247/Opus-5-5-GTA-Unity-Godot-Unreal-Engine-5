class_name EmergencyServices
extends Node
## Atmospheric responders: ambulances attend bodies, fire trucks attend wrecks/fires. They use sirens,
## drive the lane graph, dismount, "treat" / "extinguish" and leave. Never interferes with wanted level.

var calls: Array = []        # [{type, pos, t}]
var units: Array = []        # [{veh, crew:[], type, pos, state, t}]
var _t := 0.0
var _handled := {}


func _physics_process(delta: float) -> void:
	if Game.player == null or Game.world == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 3.0
		_scan()
		_dispatch()
	_update_units(delta)


func _scan() -> void:
	var pp := Game.player.global_position
	if Game.peds:
		for b in Game.peds.bodies:
			var n = b[0]
			if is_instance_valid(n) and not _handled.has(n) and (n as Node3D).global_position.distance_to(pp) < 110.0:
				_handled[n] = true
				calls.append({"type": "medic", "pos": (n as NPC).rig.ragdoll_center(), "t": Game.now()})
	for v in Game.vehicles:
		var veh := v as VehicleBase
		if veh and veh.destroyed and not _handled.has(veh) and veh.global_position.distance_to(pp) < 110.0:
			_handled[veh] = true
			calls.append({"type": "fire", "pos": veh.global_position, "t": Game.now()})


func _dispatch() -> void:
	if calls.is_empty() or units.size() >= 2:
		return
	if Game.wanted and Game.wanted.level >= 3:
		return
	var c: Dictionary = calls.pop_front()
	if Game.now() - float(c.t) > 60.0:
		return
	var rg: RoadGraph = Game.world.road_graph
	var spawn := {}
	for k in 40:
		var L: Dictionary = rg.links[randi() % rg.links.size()]
		var p := rg.lane_point(L.id, 0, L.length * 0.5)
		var d := p.distance_to(c.pos)
		if d > 90.0 and d < 170.0 and p.distance_to(Game.player.global_position) > 70.0:
			spawn = {"pos": p, "dir": L.dir}
			break
	if spawn.is_empty():
		return
	var id := "ambulance" if c.type == "medic" else "firetruck"
	var veh := VehicleBase.spawn(id, Transform3D(Basis.looking_at(spawn.dir, Vector3.UP), spawn.pos + Vector3(0, 0.4, 0)))
	var crew := []
	for i in mini(2, veh.seat_nodes.size()):
		var n := Game.peds.make_npc("medic", spawn.pos)
		if c.type == "fire":
			n.look_data.top = Color(0.75, 0.55, 0.1)
			n.look_data.pants = Color(0.2, 0.2, 0.22)
			n.look_data.hat = 4
			n.look_data.hat_color = Color(0.85, 0.75, 0.1)
			n.rig.build(n.look_data)
		veh.enter(n, i)
		n.brain = "drive" if i == 0 else "passenger"
		n.collision_layer = 0
		n.collision_mask = 0
		crew.append(n)
	var ai := AIDriver.new()
	veh.add_child(ai)
	ai.attach(veh, rg)
	ai.ignore_lights = true
	ai.set_destination(c.pos)
	ai.ignore_lights = true
	ai.arrive_radius = 16.0
	veh.set_siren(true)
	units.append({"veh": veh, "crew": crew, "type": c.type, "pos": c.pos, "state": "driving", "t": 0.0})


func _update_units(delta: float) -> void:
	for i in range(units.size() - 1, -1, -1):
		var u: Dictionary = units[i]
		var veh = u.veh
		if veh == null or not is_instance_valid(veh) or veh.destroyed:
			units.remove_at(i)
			continue
		u.t += delta
		var ai := veh.ai_driver as AIDriver
		match u.state:
			"driving":
				if ai.arrived or veh.global_position.distance_to(u.pos) < 18.0 or u.t > 60.0:
					u.state = "working"
					u.t = 0.0
					ai.mode = "idle"
					for n in u.crew:
						if is_instance_valid(n) and n.vehicle == veh:
							veh.eject(n, false)
							n.brain = "investigate"
							n.crime_pos = u.pos
			"working":
				for n in u.crew:
					if is_instance_valid(n) and not n.dead and n.global_position.distance_to(u.pos) < 4.0:
						n.idle_pose = "cower" if u.type == "medic" else ""
						if u.type == "fire" and fmod(u.t, 2.0) < delta:
							VFX.burst("water_jet", n.global_position + Vector3(0, 1.2, 0), (u.pos - n.global_position).normalized() + Vector3(0, 0.6, 0), 0.6)
				if u.t > 12.0:
					u.state = "leaving"
					u.t = 0.0
					for n in u.crew:
						if is_instance_valid(n) and not n.dead and n.vehicle == null:
							n.home_vehicle = veh
							n.brain = "return"
			"leaving":
				var all_in := true
				for n in u.crew:
					if is_instance_valid(n) and not n.dead and n.vehicle != veh:
						all_in = false
						if n.global_position.distance_to(veh.door_position(0)) < 3.0:
							var s: int = veh.free_seat(false)
							if s >= 0:
								veh.enter(n, s)
								n.collision_layer = 0
								n.collision_mask = 0
								n.brain = "drive" if s == 0 else "passenger"
				if all_in or u.t > 20.0:
					ai.mode = "traffic"
					veh.set_siren(false)
					u.state = "gone"
			"gone":
				if veh.global_position.distance_to(Game.player.global_position) > 160.0 or u.t > 90.0:
					for n in u.crew:
						if is_instance_valid(n):
							n.queue_free()
					veh.queue_free()
					units.remove_at(i)
