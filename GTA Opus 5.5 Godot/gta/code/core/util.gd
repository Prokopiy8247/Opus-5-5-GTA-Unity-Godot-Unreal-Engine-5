class_name U
## Small static helpers used everywhere.

static var _rq: PhysicsRayQueryParameters3D
static var _no_ex: Array[RID] = []
static var _space: PhysicsDirectSpaceState3D


## Raycast with a reused query object (called thousands of times per second by suspension, AI and
## perception, so avoiding per-call allocations matters).
static func ray(from: Vector3, to: Vector3, mask: int, exclude: Array = []) -> Dictionary:
	if _space == null or not is_instance_valid(_space):
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null or tree.root == null or tree.root.get_world_3d() == null:
			return {}
		_space = tree.root.get_world_3d().direct_space_state
	if _rq == null:
		_rq = PhysicsRayQueryParameters3D.new()
		_rq.collide_with_areas = false
	_rq.from = from
	_rq.to = to
	_rq.collision_mask = mask
	if exclude.is_empty():
		_rq.exclude = _no_ex
	else:
		var rids: Array[RID] = []
		for e in exclude:
			if e is CollisionObject3D:
				rids.append(e.get_rid())
			elif e is RID:
				rids.append(e)
		_rq.exclude = rids
	return _space.intersect_ray(_rq)


static func space() -> PhysicsDirectSpaceState3D:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_world_3d().direct_space_state


static func sphere_query(center: Vector3, radius: float, mask: int, max_results := 32, areas := false) -> Array:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, center)
	q.collision_mask = mask
	q.collide_with_areas = areas
	q.collide_with_bodies = not areas
	return space().intersect_shape(q, max_results)


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)


static func dir_of_yaw(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func damp(current: float, target: float, rate: float, dt: float) -> float:
	return lerpf(current, target, 1.0 - exp(-rate * dt))


static func damp_v3(current: Vector3, target: Vector3, rate: float, dt: float) -> Vector3:
	return current.lerp(target, 1.0 - exp(-rate * dt))


static func damp_angle(current: float, target: float, rate: float, dt: float) -> float:
	return lerp_angle(current, target, 1.0 - exp(-rate * dt))


static func find_ancestor_with_method(n: Node, method: String) -> Node:
	while n != null:
		if n.has_method(method):
			return n
		n = n.get_parent()
	return null


static func surface_of(collider: Object) -> String:
	if collider == null:
		return C.SURF_CONCRETE
	if collider is Node and (collider as Node).has_meta("surface"):
		return str((collider as Node).get_meta("surface"))
	if collider is VehicleBase:
		return C.SURF_METAL
	if collider is CharacterBody3D:
		return C.SURF_FLESH
	return C.SURF_CONCRETE


static func money_str(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-$" if v < 0 else "$") + out


static func hash01(x: int) -> float:
	var h := (x * 374761393) & 0x7fffffff
	h = (h ^ (h >> 13)) * 1274126177 & 0x7fffffff
	return float(h % 10000) / 10000.0
