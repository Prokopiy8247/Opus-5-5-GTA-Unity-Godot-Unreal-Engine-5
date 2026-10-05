class_name PropManager
extends Node3D
## Street furniture & vegetation as chunked MultiMeshes. Breakable props have individual static
## bodies (PhysicsServer3D) registered in a spatial hash; vehicles/explosions/bullets knock them over
## into pooled debris rigid bodies; they respawn later when the player is away.

const CHUNK := 96.0
const BREAK_CELL := 8.0
const MAX_DEBRIS := 28

# category -> {mesh, breakable, shape_size, mass, vis}
var cats := {}
var chunks := {}          # "cat|cx|cz" -> {mmi, xforms:Array, alive:PackedByteArray, bodies:Array}
var cell_hash := {}            # Vector2i -> Array of [chunk_key, idx]
var rid_lookup := {}      # body RID -> [chunk_key, idx]
var debris: Array = []
var broken_queue: Array = []   # [time, chunk_key, idx]
var w: World
var rng := RandomNumberGenerator.new()
var signal_mm: MultiMesh
var signals: Array = []   # [{inter, approach, xform(pole), bulb_idx}]
var _space: RID


func build(world: World) -> void:
	w = world
	rng.seed = 99
	_space = w.get_world_3d().space
	_def("street_lamp", true, Vector3(0.3, 6.0, 0.3), 90.0, 260.0)
	_def("bench", true, Vector3(1.8, 0.9, 0.6), 30.0, 120.0)
	_def("bin", true, Vector3(0.6, 1.0, 0.6), 12.0, 110.0)
	_def("hydrant", true, Vector3(0.4, 0.8, 0.4), 40.0, 110.0)
	_def("bollard", true, Vector3(0.25, 0.9, 0.25), 25.0, 110.0)
	_def("cone", true, Vector3(0.4, 0.7, 0.4), 3.0, 120.0)
	_def("barrier", true, Vector3(2.0, 1.0, 0.5), 25.0, 140.0)
	_def("utility_box", true, Vector3(0.9, 1.3, 0.45), 60.0, 110.0)
	_def("sign_post", true, Vector3(0.2, 2.6, 0.2), 10.0, 120.0)
	_def("bus_stop", false, Vector3(4.2, 2.6, 1.6), 0.0, 180.0)
	_def("traffic_light", false, Vector3(0.3, 6.0, 0.3), 0.0, 260.0)
	_def("palm", false, Vector3(0.5, 7.0, 0.5), 0.0, 420.0)
	_def("tree_round", false, Vector3(0.45, 3.0, 0.45), 0.0, 380.0)
	_def("tree_pine", false, Vector3(0.4, 3.0, 0.4), 0.0, 420.0)
	_def("bush", false, Vector3.ZERO, 0.0, 140.0)
	_def("rock", false, Vector3(1.6, 0.8, 1.2), 0.0, 260.0)
	_def("grass", false, Vector3.ZERO, 0.0, 70.0)
	_def("flowers", false, Vector3.ZERO, 0.0, 80.0)
	_def("kelp", false, Vector3.ZERO, 0.0, 60.0)
	_place_street_furniture()
	_place_vegetation()
	_flush()
	_build_signals()


func _def(id: String, breakable: bool, size: Vector3, mass: float, vis: float) -> void:
	cats[id] = {"mesh": PropLib.get_mesh(id), "breakable": breakable, "size": size, "mass": mass, "vis": vis, "pending": []}


func add(id: String, xf: Transform3D) -> void:
	cats[id].pending.append(xf)


# ------------------------------------------------------------------ placement

func _place_street_furniture() -> void:
	var inters := WorldMap.intersections()
	var y := C.LAND_Y + WorldMap.CURB_H
	# lamps + furniture along each road side
	for rd in WorldMap.roads():
		var a: Vector2 = rd.a
		var b: Vector2 = rd.b
		var hw: float = rd.hw
		var dir := (b - a).normalized()
		var length := a.distance_to(b)
		var right := Vector2(-dir.y, dir.x)
		for side: float in [-1.0, 1.0]:
			var off: float = hw + 0.55
			var t := 14.0 + (6.0 if side > 0 else 0.0)
			while t < length - 10.0:
				var p := a + dir * t + right * side * off
				if not _near_intersection(p, inters, 9.0) and not _blocked(p):
					var face := -right * side   # lamp arm toward road
					var yaw := atan2(face.x, face.y)
					add("street_lamp", Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.y)))
					w.lamp_points.append(Vector3(p.x, y + 6.55, p.y) + Vector3(face.x, 0, face.y) * 1.75)
					var k := rng.randf()
					var q := a + dir * (t + 8.0) + right * side * (hw + 0.6)
					if not _near_intersection(q, inters, 9.0) and not _blocked(q):
						var qy := atan2(-face.x, -face.y)
						if k < 0.25:
							add("bench", Transform3D(Basis(Vector3.UP, qy), Vector3(q.x, y, q.y) - Vector3(face.x, 0, face.y) * 0.9))
						elif k < 0.45:
							add("bin", Transform3D(Basis.IDENTITY, Vector3(q.x, y, q.y)))
						elif k < 0.52:
							add("utility_box", Transform3D(Basis(Vector3.UP, qy), Vector3(q.x, y, q.y) - Vector3(face.x, 0, face.y) * 1.6))
						elif k < 0.6:
							add("sign_post", Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, y, q.y)))
				t += 24.0
	# hydrants near intersections, bus stops on Harbor St and Lantern St
	for it in inters:
		var p: Vector2 = it.pos
		if rng.randf() < 0.6:
			var c := p + Vector2(it.hw_a + 1.4, it.hw_s + 4.0)
			if not _blocked(c):
				add("hydrant", Transform3D(Basis.IDENTITY, Vector3(c.x, y, c.y)))
	for bx in [-150.0, -70.0, 10.0, 90.0, 170.0, 245.0]:
		var bp := Vector2(bx + 20.0, 10.0 + 3.8 + 1.4)
		add("bus_stop", Transform3D(Basis(Vector3.UP, PI), Vector3(bp.x, y, bp.y)))
		w.add_box_col(Vector3(bp.x, y + 1.3, bp.y - 0.62), Vector3(4.0, 2.6, 0.12))
		var bp2 := Vector2(bx - 20.0, 80.0 - 3.8 - 1.4)
		add("bus_stop", Transform3D(Basis.IDENTITY, Vector3(bp2.x, y, bp2.y)))
		w.add_box_col(Vector3(bp2.x, y + 1.3, bp2.y + 0.62), Vector3(4.0, 2.6, 0.12))
	# plaza / promenade bollards
	for k in 16:
		add("bollard", Transform3D(Basis.IDENTITY, Vector3(-100.0 + k * 10.0, y, 161.6)))
	# construction zone with cones & barriers on Crown Street (west)
	for k in 10:
		add("cone", Transform3D(Basis.IDENTITY, Vector3(-160.0 + k * 2.2, C.LAND_Y + 0.02, -62.5)))
	for k in 3:
		add("barrier", Transform3D(Basis.IDENTITY, Vector3(-158.0 + k * 7.0, C.LAND_Y + 0.02, -64.0)))
	# promenade lamps & palms
	for k in 18:
		var x := -105.0 + k * 10.0
		if absf(x + 62.0) < 5.0 or absf(x + 32.0) < 8.0:
			continue
		add("street_lamp", Transform3D(Basis(Vector3.UP, PI), Vector3(x, y, 194.0)))
		w.lamp_points.append(Vector3(x, y + 6.55, 192.25))
		add("palm", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x + 5.0, y, 164.0)))
		if k % 3 == 0:
			add("bench", Transform3D(Basis(Vector3.UP, PI), Vector3(x + 2.5, y, 193.0)))


func _near_intersection(p: Vector2, inters: Array, r: float) -> bool:
	for it in inters:
		var q: Vector2 = it.pos
		if absf(p.x - q.x) < it.hw_a + r and absf(p.y - q.y) < it.hw_s + r:
			return true
	return false


func _blocked(p: Vector2) -> bool:
	# avoid driveways / venues where props would block access
	for id in ["modshop", "garage", "gas", "police", "hospital", "safehouse"]:
		if w.poi.has(id):
			var q: Vector3 = w.poi[id].pos
			if Vector2(q.x, q.z).distance_to(p) < 9.0:
				return true
	return false


func _place_vegetation() -> void:
	# palms along the coastal highway (north side) and beach
	for k in 40:
		var x := -270.0 + k * 14.0
		add("palm", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x + rng.randf_range(-2, 2), C.LAND_Y + WorldMap.CURB_H, 150.0 + 7.5 + 1.6)))
	for k in 30:
		var x := rng.randf_range(70, 285)
		var z := rng.randf_range(162, 178)
		var h := WorldMap.height(x, z)
		if h > 0.5:
			add("palm", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, h, z)))
	# Crown Hill forest
	var placed := 0
	var tries := 0
	while placed < 420 and tries < 4000:
		tries += 1
		var x := rng.randf_range(55, 292)
		var z := rng.randf_range(-292, -66)
		var h := WorldMap.height(x, z)
		if h < 1.2 or WorldMap.coast_sdf(x, z) > -6.0:
			continue
		if _near_hill_road(Vector2(x, z), 6.5):
			continue
		if Vector2(x, z).distance_to(Vector2(196, -204)) < 14 or Vector2(x, z).distance_to(Vector2(232, -214)) < 6:
			continue
		var r := rng.randf()
		var s := rng.randf_range(0.8, 1.4)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, h - 0.1, z))
		if r < 0.55:
			add("tree_pine", xf)
		elif r < 0.8:
			add("tree_round", xf)
		elif r < 0.92:
			add("bush", xf)
		else:
			add("rock", xf)
		placed += 1
	for k in 900:
		var x := rng.randf_range(55, 292)
		var z := rng.randf_range(-292, -66)
		var h := WorldMap.height(x, z)
		if h < 1.2 or WorldMap.coast_sdf(x, z) > -4.0 or _near_hill_road(Vector2(x, z), 4.5):
			continue
		add("grass" if k % 5 != 0 else "flowers", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x, h - 0.05, z)))
	# park + residential + plaza trees
	for blk in WorldMap.blocks():
		var r: Rect2 = blk.rect.grow(-WorldMap.SIDEWALK_W)
		var y := C.LAND_Y + WorldMap.CURB_H
		match blk.kind:
			"park":
				for k in 26:
					var p := Vector2(rng.randf_range(r.position.x + 3, r.end.x - 3), rng.randf_range(r.position.y + 3, r.end.y - 3))
					var c := r.get_center()
					if absf(p.x - c.x) < 3.5 or absf(p.y - c.y) < 3.5:
						continue
					if p.distance_to(c + Vector2(18, 12)) < 8.5 or p.distance_to(c + Vector2(-18, -12)) < 5.5:
						continue
					add("tree_round", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p.x, y, p.y)))
				for k in 160:
					var p2 := Vector2(rng.randf_range(r.position.x + 1, r.end.x - 1), rng.randf_range(r.position.y + 1, r.end.y - 1))
					add("grass" if k % 4 != 0 else "flowers", Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(p2.x, y, p2.y)))
				for k in 8:
					var a := TAU * k / 8.0
					var c2 := r.get_center()
					add("bench", Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(c2.x + cos(a) * 9.0, y, c2.y + sin(a) * 9.0)))
			"residential", "safehouse":
				# trees in back yards
				for k in 12:
					var p3 := Vector2(rng.randf_range(r.position.x + 3, r.end.x - 3), r.get_center().y + rng.randf_range(-4, 4))
					add("tree_round", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 1.15), Vector3(p3.x, y, p3.y)))
				for k in 10:
					var p4 := Vector2(rng.randf_range(r.position.x + 1, r.end.x - 1), r.get_center().y + rng.randf_range(-6, 6))
					add("bush", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 0.8), Vector3(p4.x, y, p4.y)))
			"plaza":
				for k in 8:
					var px := r.position.x + 6 + k * (r.size.x - 12) / 7.0
					add("tree_round", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 1.3), Vector3(px, y, r.end.y - 4)))
					add("bench", Transform3D(Basis.IDENTITY, Vector3(px + 3.0, y, r.end.y - 6)))
				for k in 6:
					add("tree_round", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 1.25), Vector3(r.position.x + 6 + k * (r.size.x - 12) / 5.0, y, r.position.y + 30)))
	# coast strips: rocks and bushes
	for k in 120:
		var a := rng.randf() * TAU
		var x := clampf(cos(a) * 320.0, -289, 289)
		var z := clampf(sin(a) * 320.0 - 48, -293, 197)
		var h := WorldMap.height(x, z)
		if h > 0.4 and h < 3.0 and WorldMap.beach_weight(x, z) < 0.3:
			add("rock" if k % 2 == 0 else "bush", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.8)), Vector3(x, h - 0.2, z)))
	# underwater kelp around the wreck and reef
	for k in 60:
		var x := WorldMap.WRECK_POS.x + rng.randf_range(-35, 35)
		var z := WorldMap.WRECK_POS.z + rng.randf_range(-35, 35)
		var h := WorldMap.height(x, z)
		if h < -3.0:
			add("kelp", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.6)), Vector3(x, h, z)))


func _near_hill_road(p: Vector2, r: float) -> bool:
	var pts: Array = WorldMap.HILL_ROAD
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if (a + ab * t).distance_to(p) < r:
			return true
	return false


# ------------------------------------------------------------------ instancing

func _flush() -> void:
	for id in cats:
		var cat: Dictionary = cats[id]
		var groups := {}
		for xf in cat.pending:
			var key := "%s|%d|%d" % [id, floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK)]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(xf)
		for key in groups:
			var list: Array = groups[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = cat.mesh
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = key.replace("|", "_")
			mmi.multimesh = mm
			mmi.visibility_range_end = cat.vis
			mmi.visibility_range_end_margin = cat.vis * 0.1
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			if id in ["grass", "flowers", "kelp", "cone", "bollard", "hydrant", "sign_post"]:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			var ch := {"id": id, "mmi": mmi, "xforms": list, "alive": PackedByteArray(), "bodies": []}
			ch.alive.resize(list.size())
			ch.alive.fill(1)
			chunks[key] = ch
			var size: Vector3 = cat.size
			if size == Vector3.ZERO:
				continue
			for i in list.size():
				var xf: Transform3D = list[i]
				if cat.breakable:
					var body := _make_body(xf, size, C.L_PROP)
					ch.bodies.append(body)
					rid_lookup[body] = [key, i]
					var cell := Vector2i(floori(xf.origin.x / BREAK_CELL), floori(xf.origin.z / BREAK_CELL))
					if not cell_hash.has(cell):
						cell_hash[cell] = []
					cell_hash[cell].append([key, i])
				else:
					ch.bodies.append(RID())
					var s := xf.basis.get_scale()
					if id in ["palm", "tree_round", "tree_pine"]:
						w.add_cyl_col(xf.origin, size.x * 0.5 * s.x, size.y * s.y, C.SURF_WOOD)
					elif id == "traffic_light":
						w.add_cyl_col(xf.origin, 0.16, 6.0, C.SURF_METAL)
					elif id == "rock":
						w.add_box_col(xf.origin + Vector3(0, 0.3 * s.y, 0), size * s, 0.0, C.SURF_CONCRETE)
		cat.pending = []


func _make_body(xf: Transform3D, size: Vector3, layer: int) -> RID:
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, size * 0.5)
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis.IDENTITY, Vector3(0, size.y * 0.5, 0)))
	PhysicsServer3D.body_set_collision_layer(body, layer)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(xf.basis.orthonormalized(), xf.origin))
	PhysicsServer3D.body_set_space(body, _space)
	PhysicsServer3D.body_attach_object_instance_id(body, get_instance_id())
	return body


# ------------------------------------------------------------------ traffic signal heads

func _build_signals() -> void:
	var inters := WorldMap.intersections()
	var y := C.LAND_Y + WorldMap.CURB_H
	var poles := []
	for ii in inters.size():
		var it: Dictionary = inters[ii]
		var p: Vector2 = it.pos
		var ha: float = it.hw_a + 0.9
		var hs: float = it.hw_s + 0.9
		# approach -> (corner offset, facing dir)
		var defs := {
			"s": [Vector2(ha, hs), Vector3(0, 0, 1)],
			"n": [Vector2(-ha, -hs), Vector3(0, 0, -1)],
			"e": [Vector2(ha, -hs), Vector3(1, 0, 0)],
			"w": [Vector2(-ha, hs), Vector3(-1, 0, 0)],
		}
		for ap in defs:
			if not it.arms[ap]:
				continue
			var c: Vector2 = p + defs[ap][0]
			var f: Vector3 = defs[ap][1]
			var yaw := atan2(-f.z, f.x)
			var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, y, c.y))
			add("traffic_light", xf)
			poles.append({"inter": ii, "approach": ap, "xform": xf})
	_flush()
	signal_mm = MultiMesh.new()
	signal_mm.transform_format = MultiMesh.TRANSFORM_3D
	signal_mm.use_colors = true
	var bulb_mesh := PropLib.get_mesh("signal_bulb")
	var bulb_mat := ShaderMaterial.new()
	bulb_mat.shader = Mats.shader("res://gta/shaders/bulb.gdshader")
	signal_mm.mesh = bulb_mesh
	signal_mm.instance_count = poles.size()
	for i in poles.size():
		poles[i]["bulb"] = i
		signal_mm.set_instance_transform(i, poles[i].xform * Transform3D(Basis.IDENTITY, Vector3(0.26, 4.8, 4.3)))
		signal_mm.set_instance_color(i, Color(0.2, 1.0, 0.4))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "SignalBulbs"
	mmi.multimesh = signal_mm
	mmi.material_override = bulb_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 220.0
	add_child(mmi)
	signals = poles


## state: 0 green, 1 yellow, 2 red
func set_signal(idx: int, state: int) -> void:
	var s: Dictionary = signals[idx]
	var ys := [4.8, 5.2, 5.6]
	var cols := [Color(0.25, 1.0, 0.45), Color(1.0, 0.75, 0.1), Color(1.0, 0.12, 0.1)]
	signal_mm.set_instance_transform(idx, s.xform * Transform3D(Basis.IDENTITY, Vector3(0.26, ys[state], 4.3)))
	signal_mm.set_instance_color(idx, cols[state])


# ------------------------------------------------------------------ breaking

func _process(_delta: float) -> void:
	if broken_queue.is_empty() or Game.player == null:
		return
	var now := Time.get_ticks_msec() * 0.001
	var ppos: Vector3 = Game.player.global_position
	for i in range(broken_queue.size() - 1, -1, -1):
		var e: Array = broken_queue[i]
		if now - e[0] < 90.0:
			continue
		var ch: Dictionary = chunks[e[1]]
		var xf: Transform3D = ch.xforms[e[2]]
		if xf.origin.distance_to(ppos) > 70.0:
			_restore(e[1], e[2])
			broken_queue.remove_at(i)


func _restore(key: String, idx: int) -> void:
	var ch: Dictionary = chunks[key]
	ch.alive[idx] = 1
	var xf: Transform3D = ch.xforms[idx]
	(ch.mmi as MultiMeshInstance3D).multimesh.set_instance_transform(idx, xf)
	var body := _make_body(xf, cats[ch.id].size, C.L_PROP)
	ch.bodies[idx] = body
	rid_lookup[body] = [key, idx]


## Called by fast vehicles each physics tick: breaks props inside the vehicle footprint.
func check_vehicle(v: Node3D, half_extents: Vector3, vel: Vector3) -> int:
	var hits := 0
	var pos := v.global_position
	var r := maxf(half_extents.x, half_extents.z) + 1.0
	var c0 := Vector2i(floori((pos.x - r) / BREAK_CELL), floori((pos.z - r) / BREAK_CELL))
	var c1 := Vector2i(floori((pos.x + r) / BREAK_CELL), floori((pos.z + r) / BREAK_CELL))
	var inv := v.global_transform.affine_inverse()
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cell := Vector2i(cx, cz)
			if not cell_hash.has(cell):
				continue
			for e in cell_hash[cell]:
				var ch: Dictionary = chunks[e[0]]
				if ch.alive[e[1]] == 0:
					continue
				var xf: Transform3D = ch.xforms[e[1]]
				var lp := inv * (xf.origin + Vector3(0, 0.5, 0))
				if absf(lp.x) < half_extents.x + 0.35 and absf(lp.z) < half_extents.z + 0.35 and lp.y < half_extents.y + 1.5 and lp.y > -half_extents.y - 2.0:
					break_prop(e[0], e[1], vel * 1.1 + Vector3(0, 3.0, 0), xf.origin)
					hits += 1
	return hits


func break_at_rid(rid: RID, impulse_vel: Vector3, at: Vector3) -> void:
	if rid_lookup.has(rid):
		var e: Array = rid_lookup[rid]
		break_prop(e[0], e[1], impulse_vel, at)


func explode_area(center: Vector3, radius: float) -> void:
	var c0 := Vector2i(floori((center.x - radius) / BREAK_CELL), floori((center.z - radius) / BREAK_CELL))
	var c1 := Vector2i(floori((center.x + radius) / BREAK_CELL), floori((center.z + radius) / BREAK_CELL))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cell := Vector2i(cx, cz)
			if not cell_hash.has(cell):
				continue
			for e in cell_hash[cell]:
				var ch: Dictionary = chunks[e[0]]
				if ch.alive[e[1]] == 0:
					continue
				var xf: Transform3D = ch.xforms[e[1]]
				var d := xf.origin.distance_to(center)
				if d < radius:
					var dir := (xf.origin - center).normalized()
					break_prop(e[0], e[1], dir * (radius - d) * 4.0 + Vector3(0, 6, 0), xf.origin)


func break_prop(key: String, idx: int, vel: Vector3, at: Vector3) -> void:
	var ch: Dictionary = chunks[key]
	if ch.alive[idx] == 0:
		return
	ch.alive[idx] = 0
	var xf: Transform3D = ch.xforms[idx]
	var hidden := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.0001), xf.origin + Vector3(0, -50, 0))
	(ch.mmi as MultiMeshInstance3D).multimesh.set_instance_transform(idx, hidden)
	var body: RID = ch.bodies[idx]
	if body.is_valid():
		rid_lookup.erase(body)
		PhysicsServer3D.free_rid(body)
		ch.bodies[idx] = RID()
	broken_queue.append([Time.get_ticks_msec() * 0.001, key, idx])
	var cat: Dictionary = cats[ch.id]
	_spawn_debris(cat, xf, vel)
	if ch.id == "hydrant":
		VFX.water_jet(xf.origin + Vector3(0, 0.5, 0))
	Audio.play_3d("impact_metal" if ch.id in ["street_lamp", "sign_post", "bollard", "hydrant", "utility_box"] else "impact_wood", xf.origin, 0.0, randf_range(0.8, 1.1))


func _spawn_debris(cat: Dictionary, xf: Transform3D, vel: Vector3) -> void:
	if debris.size() >= MAX_DEBRIS:
		var old: RigidBody3D = debris.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var rb := RigidBody3D.new()
	rb.collision_layer = C.L_PROP
	rb.collision_mask = C.L_WORLD | C.L_VEHICLE | C.L_PROP
	rb.mass = maxf(cat.mass, 2.0)
	rb.set_meta("surface", C.SURF_METAL)
	var size: Vector3 = cat.size
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, size.y * 0.5, 0)
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = cat.mesh
	rb.add_child(mi)
	add_child(rb)
	rb.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3(0, 0.05, 0))
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
	debris.append(rb)
	var t := get_tree().create_timer(40.0)
	t.timeout.connect(func():
		if is_instance_valid(rb):
			debris.erase(rb)
			rb.queue_free())


func _exit_tree() -> void:
	for key in chunks:
		for b in chunks[key].bodies:
			if (b as RID).is_valid():
				PhysicsServer3D.free_rid(b)
	chunks.clear()
