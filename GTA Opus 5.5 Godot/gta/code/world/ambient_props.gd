class_name FerrisWheel
extends Node3D
## Rotating Ferris wheel landmark on Lantern Pier; gondolas stay upright.

var wheel: Node3D
var gondolas: Array[Node3D] = []
var speed := 0.06


func build(w: World) -> void:
	wheel = Node3D.new()
	wheel.name = "Wheel"
	add_child(wheel)
	var mb := MB.new()
	var R := 14.0
	var segs := 24
	for side in [-1.6, 1.6]:
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var p0 := Vector3(side, cos(a0) * R, sin(a0) * R)
			var p1 := Vector3(side, cos(a1) * R, sin(a1) * R)
			var mid := (p0 + p1) * 0.5
			var length := p0.distance_to(p1)
			var dir := (p1 - p0).normalized()
			var up := mid.normalized()
			var b := Basis(Vector3.RIGHT, up, dir).orthonormalized()
			mb.use("metal").col(Color(0.95, 0.95, 0.98))
			mb.box_xf(Transform3D(Basis(Vector3.RIGHT, atan2(dir.z, dir.y)), mid), Vector3(0.35, length + 0.1, 0.35))
		for i in 12:
			var a := TAU * i / 12.0
			var tip := Vector3(side, cos(a) * R, sin(a) * R)
			mb.use("metal").col(Color(0.85, 0.85, 0.9))
			mb.box_xf(Transform3D(Basis(Vector3.RIGHT, a), tip * 0.5), Vector3(0.18, R, 0.18))
	mb.use("metal").col(Color(0.7, 0.7, 0.75))
	mb.cylinder_axis(Vector3.ZERO, Vector3.RIGHT, 1.0, 4.4, 10)
	# lights on the rim
	for i in segs:
		var a := TAU * (i + 0.5) / segs
		mb.use("neon_pink" if i % 2 == 0 else "neon_teal").col(Color.WHITE)
		mb.box(Vector3(0, cos(a) * (R + 0.3), sin(a) * (R + 0.3)), Vector3(3.6, 0.25, 0.25))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit({"metal": w.mats["metal"], "neon_pink": w.mats["neon_pink"], "neon_teal": w.mats["neon_teal"]})
	wheel.add_child(mi)
	# gondolas
	var gm := MB.new()
	gm.use("vc").col(Color(0.95, 0.4, 0.35))
	gm.box(Vector3(0, -1.4, 0), Vector3(2.2, 1.8, 1.8), 0.25)
	gm.use("glass").col(Color.WHITE)
	gm.box(Vector3(0, -1.0, 0), Vector3(2.25, 0.7, 1.85))
	gm.use("vc").col(Color(0.9, 0.9, 0.9))
	gm.box(Vector3(0, -0.2, 0), Vector3(0.12, 0.8, 0.12))
	var gmesh := gm.commit({"vc": w.mats["vc_gloss"], "glass": w.mats["glass"]})
	for i in 12:
		var a := TAU * i / 12.0
		var pivot := Node3D.new()
		pivot.position = Vector3(0, cos(a) * R, sin(a) * R)
		wheel.add_child(pivot)
		var g := MeshInstance3D.new()
		g.mesh = gmesh
		pivot.add_child(g)
		gondolas.append(pivot)


func _process(delta: float) -> void:
	if wheel == null:
		return
	wheel.rotate_x(speed * delta)
	for g in gondolas:
		g.global_basis = Basis.IDENTITY
