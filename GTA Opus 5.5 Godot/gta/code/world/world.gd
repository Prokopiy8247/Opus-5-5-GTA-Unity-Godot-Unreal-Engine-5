class_name World
extends Node3D
## Builds the whole island at load time from WorldMap data (terrain, water, roads, blocks, buildings,
## landmarks, props) and keeps the runtime registries other systems query (POIs, spawn spots, ladders).

signal build_progress(stage: String, frac: float)

var mats := {}
var _col := {}          # key -> StaticBody3D (orphan until finalize)
var poi := {}           # id -> {pos, yaw, name, type}
var parking_spots: Array = []     # [{xform, kind}]
var vehicle_spawns := {}          # name -> Transform3D
var ladders: Array = []           # [{bottom, top, normal}]
var lamp_points: Array = []       # Vector3 positions of lamp heads
var stunt_jumps: Array = []
var range_targets: Array = []
var cover_hint_boxes: Array = []
var ped_graph: PedGraph
var road_graph: RoadGraph
var props: PropManager
var interior_root: Node3D

var terrain_heights := PackedFloat32Array()


func _make_materials() -> void:
	mats["bld"] = Mats.shader_mat("res://gta/shaders/building.gdshader")
	mats["ground"] = Mats.shader_mat("res://gta/shaders/ground.gdshader")
	mats["road"] = Mats.shader_mat("res://gta/shaders/road.gdshader")
	mats["terrain"] = Mats.shader_mat("res://gta/shaders/terrain.gdshader")
	mats["vc"] = Mats.vc(0.82)
	mats["vc_gloss"] = Mats.vc(0.35, 0.0, 0.6)
	mats["metal"] = Mats.vc(0.38, 0.75)
	mats["glass"] = Mats.glass(Color(0.2, 0.28, 0.34, 0.5))
	mats["emit_warm"] = Mats.emissive(Color(1.0, 0.8, 0.5), 3.0)
	mats["emit_white"] = Mats.emissive(Color(0.95, 0.95, 1.0), 3.0)
	mats["neon_pink"] = Mats.emissive(Color(1.0, 0.3, 0.6), 4.0)
	mats["neon_teal"] = Mats.emissive(Color(0.2, 0.95, 0.9), 4.0)
	mats["neon_amber"] = Mats.emissive(Color(1.0, 0.65, 0.15), 4.0)
	mats["neon_red"] = Mats.emissive(Color(1.0, 0.15, 0.12), 4.0)
	mats["water"] = Mats.shader_mat("res://gta/shaders/water.gdshader")
	mats["*"] = mats["vc"]


func build() -> void:
	_make_materials()
	interior_root = Node3D.new()
	interior_root.name = "Interiors"
	add_child(interior_root)
	var stages := [
		["Shaping terrain", _build_terrain],
		["Filling the ocean", _build_water],
		["Paving roads", _build_roads],
		["Raising the city", _build_city],
		["Landmarks & districts", _build_landmarks],
		["Street furniture", _build_props],
		["Pedestrian network", _build_graphs],
		["Physics", _finalize_collision],
	]
	for i in stages.size():
		build_progress.emit(stages[i][0], float(i) / stages.size())
		await get_tree().process_frame
		var t0 := Time.get_ticks_msec()
		stages[i][1].call()
		print("[World] %s: %d ms" % [stages[i][0], Time.get_ticks_msec() - t0])
	build_progress.emit("Ready", 1.0)


# ---------------------------------------------------------------- collision helpers

func _body(surface: String, pos: Vector3, layer := C.L_WORLD) -> StaticBody3D:
	var cell := Vector2i(floori(pos.x / 160.0), floori(pos.z / 160.0))
	var key := "%s_%d_%d_%d" % [surface, cell.x, cell.y, layer]
	if not _col.has(key):
		var b := StaticBody3D.new()
		b.name = "Col_" + key
		b.collision_layer = layer
		b.collision_mask = 0
		b.set_meta("surface", surface)
		_col[key] = b
	return _col[key]


func add_box_col(center: Vector3, size: Vector3, yaw := 0.0, surface := C.SURF_CONCRETE, layer := C.L_WORLD) -> void:
	var b := _body(surface, center, layer)
	var sh := BoxShape3D.new()
	sh.size = size
	var o := b.create_shape_owner(b)
	b.shape_owner_add_shape(o, sh)
	b.shape_owner_set_transform(o, Transform3D(Basis(Vector3.UP, yaw), center))


func add_xform_box_col(xf: Transform3D, size: Vector3, surface := C.SURF_CONCRETE) -> void:
	var b := _body(surface, xf.origin)
	var sh := BoxShape3D.new()
	sh.size = size
	var o := b.create_shape_owner(b)
	b.shape_owner_add_shape(o, sh)
	b.shape_owner_set_transform(o, xf)


func add_convex_col(points: PackedVector3Array, surface := C.SURF_CONCRETE) -> void:
	var c := Vector3.ZERO
	for p in points:
		c += p
	c /= points.size()
	var b := _body(surface, c)
	var sh := ConvexPolygonShape3D.new()
	var local := PackedVector3Array()
	for p in points:
		local.append(p - c)
	sh.points = local
	var o := b.create_shape_owner(b)
	b.shape_owner_add_shape(o, sh)
	b.shape_owner_set_transform(o, Transform3D(Basis.IDENTITY, c))


func add_cyl_col(base: Vector3, radius: float, height: float, surface := C.SURF_CONCRETE) -> void:
	var b := _body(surface, base)
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = height
	var o := b.create_shape_owner(b)
	b.shape_owner_add_shape(o, sh)
	b.shape_owner_set_transform(o, Transform3D(Basis.IDENTITY, base + Vector3(0, height * 0.5, 0)))


## Raised slab with ramped curb edges (walkable by capsules, drivable by raycast wheels).
func add_slab_col(rect: Rect2, y0: float, y1: float, ramp := 0.3, surface := C.SURF_CONCRETE) -> void:
	var pts := PackedVector3Array()
	var a := rect.position
	var b := rect.end
	pts.append(Vector3(a.x - ramp, y0, a.y - ramp))
	pts.append(Vector3(b.x + ramp, y0, a.y - ramp))
	pts.append(Vector3(b.x + ramp, y0, b.y + ramp))
	pts.append(Vector3(a.x - ramp, y0, b.y + ramp))
	pts.append(Vector3(a.x, y1, a.y))
	pts.append(Vector3(b.x, y1, a.y))
	pts.append(Vector3(b.x, y1, b.y))
	pts.append(Vector3(a.x, y1, b.y))
	add_convex_col(pts, surface)


func _finalize_collision() -> void:
	var root := Node3D.new()
	root.name = "StaticCollision"
	add_child(root)
	for k in _col:
		root.add_child(_col[k])
	print("[World] static bodies: %d" % _col.size())


func add_mesh(mesh: Mesh, name: String, parent: Node = null, vis_end := 0.0, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = vis_end * 0.1
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent != null else self).add_child(mi)
	return mi


func register_poi(id: String, pos: Vector3, yaw := 0.0) -> void:
	# ids without a WorldMap.POIS entry are interaction/teleport anchors only (no map icon)
	var d: Dictionary = WorldMap.POIS.get(id, {"name": id.capitalize(), "type": id}).duplicate()
	d["pos"] = pos
	d["yaw"] = yaw
	poi[id] = d


# ---------------------------------------------------------------- terrain

func _build_terrain() -> void:
	var n := C.TERRAIN_RES + 1
	var half := C.TERRAIN_HALF
	var step := (half * 2.0) / C.TERRAIN_RES
	terrain_heights.resize(n * n)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	norms.resize(n * n)
	cols.resize(n * n)
	uvs.resize(n * n)
	for zi in n:
		for xi in n:
			var x := -half + xi * step
			var z := -half + zi * step
			var h := WorldMap.height(x, z)
			terrain_heights[zi * n + xi] = h
	for zi in n:
		for xi in n:
			var i := zi * n + xi
			var x := -half + xi * step
			var z := -half + zi * step
			var h := terrain_heights[i]
			var hl := terrain_heights[zi * n + maxi(xi - 1, 0)]
			var hr := terrain_heights[zi * n + mini(xi + 1, n - 1)]
			var hd := terrain_heights[maxi(zi - 1, 0) * n + xi]
			var hu := terrain_heights[mini(zi + 1, n - 1) * n + xi]
			verts[i] = Vector3(x, h, z)
			norms[i] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			uvs[i] = Vector2(x, z)
			cols[i] = _terrain_color(x, z, h)
	var idx := PackedInt32Array()
	idx.resize(C.TERRAIN_RES * C.TERRAIN_RES * 6)
	var k := 0
	for zi in C.TERRAIN_RES:
		for xi in C.TERRAIN_RES:
			var a := zi * n + xi
			var b := a + 1
			var c := a + n
			var d := c + 1
			# clockwise front faces (viewed from above)
			idx[k] = a; idx[k + 1] = b; idx[k + 2] = c
			idx[k + 3] = b; idx[k + 4] = d; idx[k + 5] = c
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, mats["terrain"])
	var mi := add_mesh(mesh, "Terrain")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# heightfield collision
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = C.L_WORLD
	body.collision_mask = 0
	body.set_meta("surface", C.SURF_DIRT)
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = terrain_heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(step, 1.0, step)
	body.add_child(cs)
	add_child(body)
	# far sea floor
	var far := MB.new()
	far.use("vc").col(Color(0.55, 0.5, 0.4))
	far.quad(Vector3(-3000, -26.5, 3000), Vector3(3000, -26.5, 3000), Vector3(3000, -26.5, -3000), Vector3(-3000, -26.5, -3000), Vector3.UP)
	add_mesh(far.commit({"vc": mats["vc"]}), "FarSeaFloor", null, 0.0, false)


func _terrain_color(x: float, z: float, h: float) -> Color:
	var d := WorldMap.coast_sdf(x, z)
	var grass := Color(0.42, 0.6, 0.3)
	var dry := Color(0.62, 0.62, 0.38)
	var sand := Color(0.92, 0.82, 0.6)
	var rock := Color(0.5, 0.48, 0.45)
	var floor_c := Color(0.75, 0.68, 0.5)
	var c := grass
	if h < 0.2:
		c = floor_c.lerp(Color(0.35, 0.42, 0.42), clampf(-h / 22.0, 0.0, 1.0))
	elif WorldMap.beach_weight(x, z) > 0.4 and d > -45.0:
		c = sand
	elif d > -9.0:
		c = rock.lerp(sand, 0.3)
	elif h > 3.0:
		c = grass.lerp(Color(0.3, 0.5, 0.26), clampf((h - 3.0) / 30.0, 0.0, 1.0)).lerp(dry, clampf(sin(x * 0.05) * cos(z * 0.04) * 0.5, 0.0, 0.4))
	elif z < -136.0 and x < 52.0:
		c = dry
	return c


func ground_height(x: float, z: float) -> float:
	return WorldMap.height(x, z)


# ---------------------------------------------------------------- water

func _build_water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	var mi := MeshInstance3D.new()
	mi.name = "Ocean"
	mi.mesh = pm
	mi.material_override = mats["water"]
	mi.position = Vector3(0, C.SEA_LEVEL, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------------------------------------------------------------- delegated stages

func _build_roads() -> void:
	RoadBuilder.new().build(self)


func _build_city() -> void:
	CityBuilder.new().build(self)


func _build_landmarks() -> void:
	Landmarks.new().build(self)


func _build_props() -> void:
	props = PropManager.new()
	props.name = "Props"
	add_child(props)
	props.build(self)


func _build_graphs() -> void:
	road_graph = RoadGraph.new()
	road_graph.build()
	ped_graph = PedGraph.new()
	ped_graph.build(self)
