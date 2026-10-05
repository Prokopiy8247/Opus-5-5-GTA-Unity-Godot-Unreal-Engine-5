class_name RangeTarget
extends StaticBody3D
## Pop-up target for the shooting range.

var hit := false
var age := 0.0
var points := 10
var board: Node3D


func _ready() -> void:
	collision_layer = C.L_PROP
	collision_mask = 0
	set_meta("surface", C.SURF_WOOD)
	board = Node3D.new()
	add_child(board)
	var mb := MB.new()
	mb.use("w").col(Color.WHITE)
	mb.box(Vector3(0, 0.9, 0), Vector3(0.7, 1.0, 0.05))
	mb.use("r").col(Color.WHITE)
	mb.cylinder_axis(Vector3(0, 1.0, -0.03), Vector3(0, 0, -1), 0.25, 0.01, 16)
	mb.use("w").col(Color.WHITE)
	mb.cylinder_axis(Vector3(0, 1.0, -0.036), Vector3(0, 0, -1), 0.16, 0.01, 16)
	mb.use("r").col(Color.WHITE)
	mb.cylinder_axis(Vector3(0, 1.0, -0.042), Vector3(0, 0, -1), 0.07, 0.01, 12)
	mb.use("p").col(Color.WHITE)
	mb.box(Vector3(0, 0.2, 0), Vector3(0.08, 0.4, 0.08))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit({"w": Mats.color(Color(0.95, 0.93, 0.85)), "r": Mats.color(Color(0.85, 0.15, 0.12)), "p": Mats.color(Color(0.3, 0.3, 0.32))})
	board.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.7, 1.0, 0.2)
	cs.shape = bs
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	board.rotation.x = -PI * 0.5
	create_tween().tween_property(board, "rotation:x", 0.0, 0.2)


func _process(delta: float) -> void:
	age += delta


func take_damage(_amount: float, source: Node = null, _pos := Vector3.ZERO, _impulse := Vector3.ZERO, _kind := "bullet") -> void:
	if hit or source != Game.player:
		return
	hit = true
	collision_layer = 0
	Audio.play_3d("impact_metal", global_position + Vector3(0, 1, 0), 0.0, 1.4)
	var tw := create_tween()
	tw.tween_property(board, "rotation:x", -PI * 0.5, 0.15)
	tw.tween_callback(queue_free)
