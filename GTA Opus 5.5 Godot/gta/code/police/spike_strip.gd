class_name SpikeStrip
extends Node3D
## Police spike strip (5-star roadblocks): punctures the tyres of vehicles driving over it.

var length := 8.0
var _t := 0.0


func setup(pos: Vector3, right: Vector3, l: float) -> void:
	length = l
	global_position = Vector3(pos.x, C.LAND_Y + 0.04, pos.z)
	global_basis = Basis(right, Vector3.UP, right.cross(Vector3.UP)).orthonormalized()
	var mb := MB.new()
	mb.use("m").col(Color.WHITE)
	mb.box(Vector3.ZERO, Vector3(length, 0.05, 0.35))
	for k in int(length / 0.25):
		mb.prism(Vector3(-length * 0.5 + k * 0.25, 0.02, 0), 0.08, Vector2(0.04, 0.04), Vector2(0.005, 0.005))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit({"m": Mats.color(Color(0.25, 0.25, 0.27), 0.4, 0.8)})
	add_child(mi)


func _physics_process(delta: float) -> void:
	_t += delta
	if _t > 90.0:
		queue_free()
		return
	var inv := global_transform.affine_inverse()
	for v in Game.vehicles:
		var veh := v as VehicleBase
		if veh == null or veh.police_unit or veh.perf.bp_tires:
			continue
		for w in veh.wheels:
			var wp := veh.global_transform * (w.pos as Vector3)
			var lp := inv * wp
			if absf(lp.x) < length * 0.5 and absf(lp.z) < 0.6 and lp.y < 1.0 and float(w.grip_mul) > 0.5:
				w.grip_mul = 0.3
				Audio.play_3d("impact_metal", wp, 0.0, 0.6)
				if veh.driver is Player:
					Game.notify("Tyres shredded by a spike strip!", "warn")
