class_name PedManager
extends Node
## Keeps a living pedestrian population around the player (sidewalk graph), with district flavour,
## day/night density, patrols, gang presence at night, body cleanup and LOD-friendly caps.

var w: World
var peds: Array = []
var bodies: Array = []
var rng := RandomNumberGenerator.new()
var root: Node3D
var _t := 0.0
var density := 1.0


func setup(world: World) -> void:
	w = world
	rng.seed = 77
	root = get_tree().current_scene.get_node("Actors")


func make_npc(kind: String, pos: Vector3, appearance := {}) -> NPC:
	var n := NPC.new()
	n.name = "NPC_" + kind
	root.add_child(n)
	n.setup(kind, rng, appearance)
	n.manager = self
	n.global_position = pos
	n.reset_physics_interpolation()
	return n


func target_count() -> int:
	if not Game.peds_enabled:
		return 0
	var n := 30.0 * density
	if Game.night_factor > 0.6:
		n *= 0.55
	if Game.env and Game.env.weather in ["rain", "storm"]:
		n *= 0.6
	return int(n)


func _physics_process(delta: float) -> void:
	if Game.paused or Game.player == null or w == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.4
	var pp := Game.player.global_position
	for i in range(peds.size() - 1, -1, -1):
		var n = peds[i]
		if n == null or not is_instance_valid(n):
			peds.remove_at(i)
			continue
		if n.dead:
			peds.remove_at(i)
			bodies.append([n, Game.now()])
			continue
		if n.vehicle != null:
			peds.remove_at(i)
			continue
		var d: float = n.global_position.distance_to(pp)
		if d > 125.0 or (not Game.peds_enabled and d > 30.0):
			n.queue_free()
			peds.remove_at(i)
	# bodies cleanup
	for i in range(bodies.size() - 1, -1, -1):
		var b: Array = bodies[i]
		var n2 = b[0]
		if n2 == null or not is_instance_valid(n2):
			bodies.remove_at(i)
			continue
		var age: float = Game.now() - float(b[1])
		var dd: float = (n2 as Node3D).global_position.distance_to(pp)
		if age > 60.0 or dd > 140.0 or bodies.size() > 14:
			(n2 as NPC).cleanup_ragdoll()
			n2.queue_free()
			bodies.remove_at(i)
	var want := target_count()
	var tries := 0
	while peds.size() < want and tries < 3:
		tries += 1
		_spawn_one(pp)


func _spawn_one(pp: Vector3) -> void:
	var g := w.ped_graph
	var i := g.random_node_near(pp, 35.0, 95.0, rng)
	if i < 0:
		return
	var pos: Vector3 = g.pos[i]
	var cam := Game.cam.cam if Game.cam else null
	if cam and pos.distance_to(pp) < 60.0:
		var to := pos - cam.global_position
		if (-cam.global_basis.z).dot(to.normalized()) > 0.5:
			return
	var dist: Dictionary = WorldMap.district_at(pos.x, pos.z)
	var kind := "civilian"
	var r := rng.randf()
	if dist.id == "ironside" and Game.night_factor > 0.5 and r < 0.25:
		kind = "gang"
	elif dist.id == "meridian" and r < 0.06:
		kind = "police"
	var n := make_npc(kind, pos + Vector3(rng.randf_range(-0.8, 0.8), 0.05, rng.randf_range(-0.8, 0.8)))
	n.cur_node = i
	n.next_node = i
	peds.append(n)


func on_npc_died(_n: NPC) -> void:
	pass


func clear_all() -> void:
	for n in peds:
		if is_instance_valid(n):
			n.queue_free()
	peds.clear()
