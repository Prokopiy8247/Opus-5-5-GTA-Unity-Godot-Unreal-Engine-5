class_name Animal
extends CharacterBody3D
## Lightweight wildlife actor: land (graze/wander/flee/charge), air (gull flight) and water (fish/shark).

var species := "deer"
var habitat := "land"         # land, air, water
var state := "wander"
var target := Vector3.ZERO
var home := Vector3.ZERO
var health := 40.0
var dead := false
var speed_walk := 1.6
var speed_run := 8.0
var _t := 0.0
var _think := 0.0
var _phase := 0.0
var parts := {}
var body: Node3D
var _dead_t := 0.0
var _bite_t := 0.0
var aggressive := false


func setup(sp: String, pos: Vector3, rng: RandomNumberGenerator) -> void:
	species = sp
	home = pos
	collision_layer = C.L_NPC
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	body = Node3D.new()
	add_child(body)
	match sp:
		"deer":
			bs.size = Vector3(0.5, 1.2, 1.4)
			_build_quad(Color(0.62, 0.42, 0.26), 1.0, true, false)
			health = 60.0
			speed_run = 10.0
		"rabbit":
			bs.size = Vector3(0.25, 0.3, 0.4)
			_build_quad(Color(0.75, 0.68, 0.6), 0.28, false, false)
			health = 10.0
			speed_run = 7.0
			speed_walk = 0.8
		"boar":
			bs.size = Vector3(0.5, 0.8, 1.2)
			_build_quad(Color(0.3, 0.24, 0.2), 0.6, false, true)
			health = 90.0
			aggressive = true
			speed_run = 8.5
		"coyote":
			bs.size = Vector3(0.35, 0.7, 1.0)
			_build_quad(Color(0.6, 0.5, 0.36), 0.6, false, false)
			health = 50.0
			aggressive = true
			speed_run = 9.5
		"dog":
			bs.size = Vector3(0.3, 0.6, 0.8)
			_build_quad([Color(0.85, 0.75, 0.55), Color(0.2, 0.18, 0.16), Color(0.95, 0.95, 0.92)][rng.randi() % 3], 0.5, false, false)
			health = 40.0
			speed_run = 8.0
		"gull":
			habitat = "air"
			bs.size = Vector3(0.6, 0.3, 0.5)
			_build_gull()
			health = 5.0
		"fish":
			habitat = "water"
			bs.size = Vector3(0.2, 0.25, 0.5)
			_build_fish(Color.from_hsv(rng.randf(), 0.6, 0.9), 0.5)
			health = 5.0
		"shark":
			habitat = "water"
			bs.size = Vector3(0.8, 0.9, 3.0)
			_build_fish(Color(0.42, 0.48, 0.55), 3.2, true)
			health = 220.0
			aggressive = true
	cs.shape = bs
	cs.position = Vector3(0, bs.size.y * 0.5, 0)
	add_child(cs)
	global_position = pos
	_phase = rng.randf() * TAU
	target = pos


func _mk(mb: MB, mats: Dictionary, name: String, parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	parent.add_child(n)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(mats)
	n.add_child(mi)
	parts[name] = n
	return n


func _build_quad(col: Color, s: float, antlers: bool, tusks: bool) -> void:
	var mats := {"c": Mats.color(col, 0.9), "d": Mats.color(col.darkened(0.45), 0.9), "w": Mats.color(Color(0.95, 0.92, 0.85), 0.6)}
	var mb := MB.new()
	mb.use("c").col(Color.WHITE)
	mb.prism(Vector3(0, -0.22 * s, 0), 0.44 * s, Vector2(0.22, 0.55) * s, Vector2(0.2, 0.5) * s, 0.08 * s)
	mb.use("d").col(Color.WHITE)
	mb.box(Vector3(0, 0.08 * s, 0.55 * s), Vector3(0.08, 0.2, 0.08) * s)
	_mk(mb, mats, "torso", body, Vector3(0, 0.75 * s, 0))
	mb = MB.new()
	mb.use("c").col(Color.WHITE)
	mb.prism(Vector3(0, 0, 0), 0.4 * s, Vector2(0.1, 0.12) * s, Vector2(0.09, 0.1) * s, 0.03 * s, Vector2(0, -0.12 * s))
	mb.box(Vector3(0, 0.42 * s, -0.24 * s), Vector3(0.18, 0.18, 0.34) * s, 0.04 * s)
	mb.use("d").col(Color.WHITE)
	mb.box(Vector3(0, 0.38 * s, -0.42 * s), Vector3(0.1, 0.08, 0.06) * s)
	for sx in [-1.0, 1.0]:
		mb.box(Vector3(sx * 0.09 * s, 0.55 * s, -0.18 * s), Vector3(0.05, 0.14, 0.03) * s)
	if antlers:
		mb.use("w").col(Color.WHITE)
		for sx in [-1.0, 1.0]:
			mb.box_xf(Transform3D(Basis(Vector3.FORWARD, sx * 0.4), Vector3(sx * 0.12 * s, 0.68 * s, -0.18 * s)), Vector3(0.03, 0.35, 0.03) * s)
			mb.box(Vector3(sx * 0.2 * s, 0.78 * s, -0.2 * s), Vector3(0.12, 0.03, 0.03) * s)
	if tusks:
		mb.use("w").col(Color.WHITE)
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(sx * 0.07 * s, 0.32 * s, -0.42 * s), Vector3(0.02, 0.06, 0.02) * s)
	_mk(mb, mats, "head", body, Vector3(0, 0.85 * s, -0.5 * s))
	var i := 0
	for p in [Vector3(-0.14, 0.62, -0.4), Vector3(0.14, 0.62, -0.4), Vector3(-0.14, 0.62, 0.4), Vector3(0.14, 0.62, 0.4)]:
		mb = MB.new()
		mb.use("d").col(Color.WHITE)
		mb.prism(Vector3(0, -0.62 * s, 0), 0.62 * s, Vector2(0.035, 0.035) * s, Vector2(0.05, 0.06) * s, 0.01)
		_mk(mb, mats, "leg%d" % i, body, p * s)
		i += 1


func _build_gull() -> void:
	var mats := {"w": Mats.color(Color(0.96, 0.96, 0.96), 0.8), "g": Mats.color(Color(0.55, 0.58, 0.62), 0.8), "y": Mats.color(Color(0.95, 0.75, 0.2), 0.6)}
	var mb := MB.new()
	mb.use("w").col(Color.WHITE)
	mb.sphere(Vector3.ZERO, 0.14, 8, 5, Vector3(0.8, 0.8, 1.8))
	mb.sphere(Vector3(0, 0.08, -0.22), 0.08, 6, 4)
	mb.use("y").col(Color.WHITE)
	mb.box(Vector3(0, 0.07, -0.33), Vector3(0.03, 0.03, 0.08))
	_mk(mb, mats, "torso", body, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		mb = MB.new()
		mb.use("g").col(Color.WHITE)
		mb.quad(Vector3(0, 0, -0.1), Vector3(sx * 0.5, 0, -0.02), Vector3(sx * 0.5, 0, 0.08), Vector3(0, 0, 0.12), Vector3.UP)
		mb.quad(Vector3(0, 0, -0.1), Vector3(0, 0, 0.12), Vector3(sx * 0.5, 0, 0.08), Vector3(sx * 0.5, 0, -0.02), Vector3.DOWN)
		_mk(mb, mats, "wing_l" if sx < 0 else "wing_r", body, Vector3(sx * 0.08, 0.05, 0))


func _build_fish(col: Color, s: float, shark := false) -> void:
	var mats := {"c": Mats.color(col, 0.4, 0.2), "d": Mats.color(col.darkened(0.3), 0.5), "w": Mats.color(Color(0.92, 0.92, 0.9), 0.5)}
	var mb := MB.new()
	mb.use("c").col(Color.WHITE)
	mb.sphere(Vector3.ZERO, 0.12 * s, 8, 5, Vector3(0.6, 0.8, 2.2))
	if shark:
		mb.use("d").col(Color.WHITE)
		mb.prism(Vector3(0, 0.08 * s, 0.0), 0.12 * s, Vector2(0.02, 0.1) * s, Vector2(0.01, 0.02) * s, 0.0, Vector2(0, 0.06 * s))
		mb.use("w").col(Color.WHITE)
		mb.box(Vector3(0, -0.06 * s, -0.12 * s), Vector3(0.1, 0.03, 0.12) * s)
	_mk(mb, mats, "torso", body, Vector3.ZERO)
	mb = MB.new()
	mb.use("d").col(Color.WHITE)
	mb.quad(Vector3(0, 0, 0), Vector3(0, 0.1 * s, 0.14 * s), Vector3(0, 0, 0.1 * s), Vector3(0, -0.1 * s, 0.14 * s), Vector3.RIGHT)
	mb.quad(Vector3(0, 0, 0), Vector3(0, -0.1 * s, 0.14 * s), Vector3(0, 0, 0.1 * s), Vector3(0, 0.1 * s, 0.14 * s), Vector3.LEFT)
	_mk(mb, mats, "tail", body, Vector3(0, 0, 0.24 * s))


func take_damage(amount: float, source: Node = null, _pos := Vector3.ZERO, _impulse := Vector3.ZERO, _kind := "bullet") -> void:
	if dead:
		return
	health -= amount
	if health <= 0.0:
		dead = true
		collision_layer = 0
		body.rotation.z = PI * 0.5
		if habitat == "air":
			state = "fall"
		if habitat == "water":
			body.rotation.z = PI
		VFX.burst("blood", global_position + Vector3(0, 0.5, 0), Vector3.UP, 0.6)
	else:
		state = "flee"
		if aggressive and source == Game.player:
			state = "charge"
		_t = 0.0


func _physics_process(delta: float) -> void:
	if Game.paused:
		return
	_t += delta
	_phase += delta
	if dead:
		_dead_t += delta
		if habitat == "air" and global_position.y > WorldMap.height(global_position.x, global_position.z) + 0.2:
			global_position.y -= delta * 9.0
		elif habitat == "water":
			global_position.y = move_toward(global_position.y, C.SEA_LEVEL - 0.1, delta)
		if _dead_t > 40.0:
			queue_free()
		return
	match habitat:
		"land":
			_land(delta)
		"air":
			_air(delta)
		"water":
			_water(delta)


func _player_threat() -> float:
	var p := Game.player
	if p == null or p.dead:
		return 999.0
	return global_position.distance_to(p.global_position)


func _land(delta: float) -> void:
	_think -= delta
	var p := Game.player
	if _think <= 0.0:
		_think = 0.3
		var d := _player_threat()
		for e in Game.events:
			if e.kind in ["gunshot", "explosion"] and global_position.distance_to(e.pos) < e.radius * 0.8:
				state = "flee"
				_t = 0.0
		if species == "coyote" and Game.night_factor > 0.5 and d < 18.0 and p.vehicle == null:
			state = "charge"
		elif species == "boar" and d < 5.0 and p.vehicle == null and state != "flee":
			state = "charge"
		elif species == "dog" and d < 8.0 and state == "wander":
			state = "bark"
			_t = 0.0
		elif state in ["wander", "graze"] and d < (6.0 if Game.player.crouching else 16.0) and species not in ["dog"]:
			state = "flee"
			_t = 0.0
		if state == "flee" and _t > 8.0:
			state = "wander"
		if state == "charge" and (d > 40.0 or p.vehicle != null):
			state = "wander"
		if state == "bark" and _t > 4.0:
			state = "wander"
		if state in ["wander", "graze"] and global_position.distance_to(target) < 1.0:
			if randf() < 0.5:
				state = "graze"
				_t = 0.0
			target = home + Vector3(randf_range(-25, 25), 0, randf_range(-25, 25))
		if state == "graze" and _t > randf_range(3.0, 7.0):
			state = "wander"
	var dir := Vector3.ZERO
	var spd := 0.0
	match state:
		"wander":
			dir = target - global_position
			spd = speed_walk
		"flee":
			dir = global_position - p.global_position
			spd = speed_run
		"charge":
			dir = p.global_position - global_position
			spd = speed_run
			_bite_t -= delta
			if dir.length() < 1.3 and _bite_t <= 0.0:
				_bite_t = 1.0
				p.take_damage(12.0, self, p.global_position, dir.normalized() * 3.0, "melee")
				Audio.play_3d("bark" if species != "boar" else "punch", global_position, 0.0, 0.7)
		"bark":
			dir = p.global_position - global_position
			spd = 0.0
			if fmod(_t, 0.9) < delta:
				Audio.play_3d("bark", global_position + Vector3(0, 0.5, 0), -2.0, randf_range(0.9, 1.2), 40.0)
	dir.y = 0
	if dir.length() > 0.1:
		var yaw := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, yaw + PI, 1.0 - exp(-6.0 * delta))
	var mv := dir.normalized() * spd * delta if dir.length() > 0.1 else Vector3.ZERO
	var np := global_position + mv
	var gh := WorldMap.height(np.x, np.z)
	if gh < 0.3:
		state = "wander"
		target = home
		return
	np.y = gh
	if gh > C.LAND_Y + 0.5 or absf(np.x) > 280 or absf(np.z) > 280:
		pass
	global_position = np
	# leg animation
	var sw := sin(_phase * spd * 2.2) * clampf(spd / 3.0, 0.0, 0.8)
	for i in 4:
		var leg: Node3D = parts.get("leg%d" % i)
		if leg:
			leg.rotation.x = sw * (1.0 if i % 3 == 0 else -1.0)
	var head: Node3D = parts.get("head")
	if head:
		head.rotation.x = 0.7 if state == "graze" else 0.0


func _air(delta: float) -> void:
	var t := _phase * 0.4
	var r := 18.0 + sin(_phase * 0.1) * 6.0
	var goal := home + Vector3(cos(t) * r, 14.0 + sin(t * 1.7) * 4.0, sin(t) * r)
	if _player_threat() < 6.0:
		goal += Vector3(0, 10, 0)
	var to := goal - global_position
	global_position += to.limit_length(9.0 * delta)
	if to.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z) + PI, 1.0 - exp(-3.0 * delta))
	var flap := sin(_phase * 9.0) * 0.6
	if parts.has("wing_l"):
		parts.wing_l.rotation.z = flap
		parts.wing_r.rotation.z = -flap
	if randf() < 0.002:
		Audio.play_3d("gull", global_position, -6.0, randf_range(0.9, 1.2), 70.0)


func _water(delta: float) -> void:
	var p := Game.player
	var spd := 1.4
	var goal := target
	if species == "shark":
		spd = 3.0
		var t := _phase * 0.15
		goal = home + Vector3(cos(t) * 22.0, 0, sin(t) * 22.0)
		goal.y = minf(WorldMap.height(goal.x, goal.z) + 3.0, C.SEA_LEVEL - 2.5)
		if p and p.state == "swim" and p.global_position.distance_to(global_position) < 20.0:
			goal = p.global_position + Vector3(0, 0.5, 0)
			spd = 6.5
			_bite_t -= delta
			if global_position.distance_to(p.global_position + Vector3(0, 0.8, 0)) < 2.2 and _bite_t <= 0.0:
				_bite_t = 1.4
				p.take_damage(28.0, self, p.global_position, Vector3.ZERO, "melee")
				VFX.burst("blood", p.global_position + Vector3(0, 0.6, 0), Vector3.UP, 1.2)
	else:
		if global_position.distance_to(target) < 1.5:
			target = home + Vector3(randf_range(-8, 8), randf_range(-2, 2), randf_range(-8, 8))
			target.y = clampf(target.y, WorldMap.height(target.x, target.z) + 0.6, C.SEA_LEVEL - 0.8)
		if p and p.global_position.distance_to(global_position) < 4.0:
			goal = global_position + (global_position - p.global_position).normalized() * 5.0
			spd = 4.0
	var to := goal - global_position
	global_position += to.limit_length(spd * delta)
	global_position.y = minf(global_position.y, C.SEA_LEVEL - 0.4)
	if to.length() > 0.05:
		look_at(global_position - to.normalized(), Vector3.UP)
	if parts.has("tail"):
		parts.tail.rotation.y = sin(_phase * 8.0) * 0.5
