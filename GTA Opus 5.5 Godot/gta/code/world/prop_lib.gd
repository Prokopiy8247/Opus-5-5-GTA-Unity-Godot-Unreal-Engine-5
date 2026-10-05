class_name PropLib
## Mesh library for street furniture / vegetation. A Blender-authored GLB at
## res://gta/generated/models/props/<id>.glb overrides the procedural fallback mesh.

static var _cache := {}
static var _m := {}


static func _mats() -> Dictionary:
	if _m.is_empty():
		_m = {
			"metal": Mats.vc(0.4, 0.7), "vc": Mats.vc(0.8), "gloss": Mats.vc(0.35, 0.0, 0.6),
			"emit": Mats.emissive(Color(1.0, 0.85, 0.6), 4.0), "glass": Mats.glass(Color(0.6, 0.75, 0.8, 0.35)),
			"leaf": Mats.vc(0.9), "bark": Mats.vc(0.95),
		}
	return _m


static func get_mesh(id: String) -> Mesh:
	if _cache.has(id):
		return _cache[id]
	var mesh: Mesh = _from_glb(id)
	if mesh == null:
		mesh = _build(id)
	_cache[id] = mesh
	return mesh


static func _from_glb(id: String) -> Mesh:
	var path := "res://gta/generated/models/props/%s.glb" % id
	if not ResourceLoader.exists(path):
		return null
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var inst := ps.instantiate()
	var found: Mesh = null
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		found = (n as MeshInstance3D).mesh
		break
	inst.free()
	return found


static func _build(id: String) -> Mesh:
	var mb := MB.new()
	var dark := Color(0.22, 0.24, 0.27)
	match id:
		"street_lamp":
			mb.use("metal").col(dark)
			mb.cylinder(Vector3.ZERO, 0.11, 0.5, 8)
			mb.cylinder(Vector3(0, 0.5, 0), 0.08, 6.3, 8, true, 0.06)
			mb.box(Vector3(0, 6.75, 0.9), Vector3(0.12, 0.12, 1.9))
			mb.box(Vector3(0, 6.7, 1.75), Vector3(0.42, 0.22, 0.75), 0.05)
			mb.use("emit").col(Color.WHITE)
			mb.box(Vector3(0, 6.58, 1.75), Vector3(0.36, 0.04, 0.66))
		"traffic_light":
			mb.use("metal").col(Color(0.18, 0.19, 0.2))
			mb.cylinder(Vector3.ZERO, 0.14, 6.0, 8)
			mb.box(Vector3(0, 5.8, 2.4), Vector3(0.14, 0.14, 4.8))
			mb.box(Vector3(0, 5.2, 4.3), Vector3(0.45, 1.3, 0.38), 0.05)
			mb.box(Vector3(0.3, 1.25, 0.0), Vector3(0.28, 0.6, 0.25), 0.04)
		"signal_bulb":
			mb.use("vc").col(Color.WHITE)
			mb.sphere(Vector3.ZERO, 0.16, 8, 5)
		"bench":
			mb.use("vc").col(Color(0.55, 0.36, 0.22))
			for k in 3:
				mb.box(Vector3(0, 0.45, -0.2 + k * 0.17), Vector3(1.8, 0.05, 0.14))
			mb.box(Vector3(0, 0.75, 0.25), Vector3(1.8, 0.35, 0.05))
			mb.use("metal").col(dark)
			for sx in [-0.75, 0.75]:
				mb.box(Vector3(sx, 0.22, 0.0), Vector3(0.06, 0.45, 0.55))
				mb.box(Vector3(sx, 0.6, 0.25), Vector3(0.05, 0.5, 0.05))
		"bin":
			mb.use("gloss").col(Color(0.15, 0.45, 0.35))
			mb.cylinder(Vector3.ZERO, 0.3, 0.95, 10)
			mb.use("metal").col(dark)
			mb.cylinder(Vector3(0, 0.95, 0), 0.33, 0.08, 10)
		"hydrant":
			mb.use("gloss").col(Color(0.85, 0.15, 0.12))
			mb.cylinder(Vector3.ZERO, 0.17, 0.6, 8)
			mb.sphere(Vector3(0, 0.62, 0), 0.17, 8, 4)
			mb.cylinder_axis(Vector3(0, 0.42, 0), Vector3.RIGHT, 0.07, 0.5, 6)
			mb.cylinder(Vector3(0, 0.0, 0), 0.22, 0.08, 8)
		"bollard":
			mb.use("metal").col(Color(0.3, 0.31, 0.33))
			mb.cylinder(Vector3.ZERO, 0.12, 0.9, 8)
			mb.use("vc").col(Color(0.95, 0.75, 0.15))
			mb.cylinder(Vector3(0, 0.7, 0), 0.125, 0.1, 8)
		"cone":
			mb.use("gloss").col(Color(1.0, 0.45, 0.08))
			mb.box(Vector3(0, 0.02, 0), Vector3(0.42, 0.04, 0.42))
			mb.cylinder(Vector3(0, 0.04, 0), 0.17, 0.66, 8, true, 0.03)
			mb.use("vc").col(Color(0.95, 0.95, 0.95))
			mb.cylinder(Vector3(0, 0.38, 0), 0.105, 0.12, 8, false, 0.085)
		"barrier":
			mb.use("gloss").col(Color(0.95, 0.95, 0.95))
			mb.box(Vector3(0, 0.75, 0), Vector3(2.0, 0.3, 0.08))
			mb.use("gloss").col(Color(0.9, 0.2, 0.15))
			for k in 4:
				mb.box(Vector3(-0.75 + k * 0.5, 0.75, 0.045), Vector3(0.22, 0.28, 0.01))
			mb.use("metal").col(dark)
			for sx in [-0.85, 0.85]:
				mb.box(Vector3(sx, 0.4, 0), Vector3(0.06, 0.8, 0.5))
		"utility_box":
			mb.use("vc").col(Color(0.55, 0.6, 0.55))
			mb.box(Vector3(0, 0.65, 0), Vector3(0.9, 1.3, 0.45), 0.04)
		"bus_stop":
			mb.use("metal").col(dark)
			for sx in [-1.9, 1.9]:
				mb.box(Vector3(sx, 1.25, 0.6), Vector3(0.08, 2.5, 0.08))
			mb.box(Vector3(0, 2.55, 0.0), Vector3(4.2, 0.1, 1.6))
			mb.use("glass").col(Color.WHITE)
			mb.box(Vector3(0, 1.3, 0.62), Vector3(3.8, 2.2, 0.04))
			mb.use("vc").col(Color(0.15, 0.55, 0.6))
			mb.box(Vector3(2.0, 1.4, 0.0), Vector3(0.05, 1.6, 1.0))
			mb.use("vc").col(Color(0.55, 0.36, 0.22))
			mb.box(Vector3(0, 0.45, 0.35), Vector3(3.0, 0.06, 0.4))
		"sign_post":
			mb.use("metal").col(Color(0.6, 0.62, 0.65))
			mb.cylinder(Vector3.ZERO, 0.04, 2.6, 6)
			mb.use("gloss").col(Color(0.12, 0.45, 0.3))
			mb.box(Vector3(0, 2.5, 0), Vector3(1.2, 0.3, 0.03))
		"palm":
			mb.use("bark").col(Color(0.55, 0.42, 0.3))
			var hgt := 7.5
			for k in 6:
				var t0 := float(k) / 6.0
				var bend := Vector3(sin(t0 * 1.2) * 0.9, 0, 0)
				mb.cylinder(Vector3(0, t0 * hgt, 0) + bend, 0.24 - t0 * 0.08, hgt / 6.0 + 0.05, 7, false, 0.22 - t0 * 0.08)
			var top := Vector3(sin(1.2) * 0.9, hgt, 0)
			mb.use("leaf").col(Color(0.25, 0.55, 0.22))
			for k in 8:
				var a := TAU * k / 8.0
				var d := Vector3(cos(a), 0, sin(a))
				var tip := top + d * 3.4 + Vector3(0, -1.2, 0)
				var side := d.cross(Vector3.UP) * 0.55
				var mid := top + d * 1.7 + Vector3(0, 0.35, 0)
				mb.tri(top, mid + side, mid - side, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP)
				mb.tri(mid + side, tip, mid - side, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP)
				mb.tri(top, mid - side, mid + side, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.DOWN)
				mb.tri(mid - side, tip, mid + side, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.DOWN)
			mb.use("bark").col(Color(0.45, 0.32, 0.18))
			mb.sphere(top + Vector3(0, -0.2, 0), 0.4, 6, 4)
		"tree_round":
			mb.use("bark").col(Color(0.42, 0.3, 0.2))
			mb.cylinder(Vector3.ZERO, 0.22, 2.6, 7, false, 0.16)
			mb.use("leaf").col(Color(0.32, 0.58, 0.28))
			mb.sphere(Vector3(0, 3.6, 0), 1.9, 8, 5, Vector3(1.0, 0.9, 1.0))
			mb.col(Color(0.38, 0.64, 0.3))
			mb.sphere(Vector3(0.9, 3.0, 0.4), 1.2, 7, 4)
			mb.col(Color(0.28, 0.52, 0.25))
			mb.sphere(Vector3(-0.8, 3.2, -0.5), 1.25, 7, 4)
		"tree_pine":
			mb.use("bark").col(Color(0.38, 0.27, 0.18))
			mb.cylinder(Vector3.ZERO, 0.2, 2.0, 6, false, 0.15)
			mb.use("leaf").col(Color(0.2, 0.42, 0.25))
			mb.cylinder(Vector3(0, 1.4, 0), 1.9, 2.6, 8, true, 0.2)
			mb.col(Color(0.22, 0.46, 0.27))
			mb.cylinder(Vector3(0, 3.0, 0), 1.5, 2.4, 8, true, 0.15)
			mb.col(Color(0.25, 0.5, 0.3))
			mb.cylinder(Vector3(0, 4.5, 0), 1.0, 2.4, 8, true, 0.05)
		"bush":
			mb.use("leaf").col(Color(0.3, 0.52, 0.26))
			mb.sphere(Vector3(0, 0.5, 0), 0.8, 7, 4, Vector3(1.2, 0.8, 1.0))
			mb.col(Color(0.36, 0.58, 0.3))
			mb.sphere(Vector3(0.5, 0.45, 0.3), 0.55, 6, 4)
		"rock":
			mb.use("vc").col(Color(0.52, 0.5, 0.47))
			mb.sphere(Vector3(0, 0.3, 0), 1.0, 6, 4, Vector3(1.3, 0.7, 1.0))
		"grass":
			mb.use("leaf").col(Color(0.36, 0.58, 0.26))
			for k in 5:
				var a := TAU * k / 5.0 + 0.3
				var d := Vector3(cos(a), 0, sin(a)) * 0.18
				var s := d.cross(Vector3.UP).normalized() * 0.05
				mb.tri(d - s, d + s, d * 2.0 + Vector3(0, 0.55, 0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, d + Vector3.UP * 0.2)
				mb.tri(d + s, d - s, d * 2.0 + Vector3(0, 0.55, 0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, -d + Vector3.UP * 0.2)
		"flowers":
			mb.use("leaf").col(Color(0.3, 0.55, 0.25))
			mb.sphere(Vector3(0, 0.15, 0), 0.3, 6, 3, Vector3(1.4, 0.6, 1.4))
			for k in 6:
				var a := TAU * k / 6.0
				mb.use("vc").col(Color.from_hsv(fmod(k * 0.17, 1.0), 0.7, 1.0))
				mb.box(Vector3(cos(a) * 0.25, 0.3, sin(a) * 0.25), Vector3(0.1, 0.06, 0.1))
		"kelp":
			mb.use("leaf").col(Color(0.2, 0.42, 0.22))
			for k in 4:
				var a := TAU * k / 4.0
				var d := Vector3(cos(a), 0, sin(a)) * 0.2
				mb.quad(d, d + Vector3(0.15, 0, 0), d + Vector3(0.25, 3.5, 0), d + Vector3(0.1, 3.5, 0), Vector3(0, 0, 1))
				mb.quad(d + Vector3(0.15, 0, 0), d, d + Vector3(0.1, 3.5, 0), d + Vector3(0.25, 3.5, 0), Vector3(0, 0, -1))
		_:
			mb.use("vc").col(Color.MAGENTA)
			mb.box(Vector3(0, 0.5, 0), Vector3.ONE)
	return mb.commit(_mats())
