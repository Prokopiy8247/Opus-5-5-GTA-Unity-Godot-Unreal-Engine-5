class_name WildlifeManager
extends Node
## Region-based wildlife spawning with per-species caps near the player.

const REGIONS := [
	{"sp": "deer", "center": Vector3(200, 0, -180), "radius": 80.0, "max": 6},
	{"sp": "rabbit", "center": Vector3(160, 0, -130), "radius": 70.0, "max": 5},
	{"sp": "rabbit", "center": Vector3(170, 0, 45), "radius": 25.0, "max": 3},
	{"sp": "boar", "center": Vector3(240, 0, -240), "radius": 45.0, "max": 2},
	{"sp": "coyote", "center": Vector3(150, 0, -240), "radius": 60.0, "max": 2, "night": true},
	{"sp": "dog", "center": Vector3(230, 0, 40), "radius": 50.0, "max": 3},
	{"sp": "gull", "center": Vector3(-40, 0, 200), "radius": 60.0, "max": 6},
	{"sp": "gull", "center": Vector3(180, 0, 190), "radius": 60.0, "max": 4},
	{"sp": "gull", "center": Vector3(-190, 0, 200), "radius": 50.0, "max": 4},
	{"sp": "fish", "center": Vector3(150, 0, 268), "radius": 25.0, "max": 14},
	{"sp": "fish", "center": Vector3(-100, 0, 240), "radius": 30.0, "max": 8},
	{"sp": "shark", "center": Vector3(60, 0, 285), "radius": 40.0, "max": 1},
]

var animals: Array = []
var rng := RandomNumberGenerator.new()
var _t := 0.0
var root: Node3D


func setup() -> void:
	rng.seed = 31
	root = get_tree().current_scene.get_node("Actors")


func _physics_process(delta: float) -> void:
	if Game.player == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0
	var pp := Game.player.global_position
	for i in range(animals.size() - 1, -1, -1):
		var a = animals[i]
		if not is_instance_valid(a):
			animals.remove_at(i)
			continue
		if (a as Node3D).global_position.distance_to(pp) > 190.0 or not Game.wildlife_enabled:
			a.queue_free()
			animals.remove_at(i)
	if not Game.wildlife_enabled:
		return
	for ri in REGIONS.size():
		var r: Dictionary = REGIONS[ri]
		var c: Vector3 = r.center
		if c.distance_to(Vector3(pp.x, 0, pp.z)) > 170.0:
			continue
		if r.get("night", false) and Game.night_factor < 0.5:
			continue
		var count := 0
		for a in animals:
			if is_instance_valid(a) and (a as Animal).get_meta("region", -1) == ri:
				count += 1
		if count >= int(r.max):
			continue
		_spawn(r, ri)


func _spawn(r: Dictionary, ri: int) -> void:
	var c: Vector3 = r.center
	var rad: float = r.radius
	var pos := c + Vector3(rng.randf_range(-rad, rad), 0, rng.randf_range(-rad, rad))
	var sp: String = r.sp
	var gh := WorldMap.height(pos.x, pos.z)
	match sp:
		"gull":
			pos.y = 16.0
		"fish", "shark":
			if gh > -3.0:
				return
			pos.y = clampf(gh + 1.5, gh + 0.5, C.SEA_LEVEL - 1.0)
		_:
			if gh < 0.5:
				return
			pos.y = gh
	if Game.player.global_position.distance_to(pos) < 25.0 and sp not in ["fish", "gull"]:
		return
	var a := Animal.new()
	root.add_child(a)
	a.setup(sp, pos, rng)
	a.set_meta("region", ri)
	animals.append(a)


func clear_all() -> void:
	for a in animals:
		if is_instance_valid(a):
			a.queue_free()
	animals.clear()
