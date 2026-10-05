class_name CameraRig
extends Node3D
## Third-person orbit camera with collision (sphere cast), shoulder aim, scope, vehicle chase camera,
## aircraft chase camera, first-person mode, trauma shake and FOV dynamics.

var cam: Camera3D
var yaw := PI
var pitch := -0.18
var target: Node3D
var mode := "foot"          # foot, aim, vehicle, air, boat, death, photo
var view := 0               # 0 near, 1 far, 2 first person
var trauma := 0.0
var scope_fov := 0.0
var _dist := 4.0
var _fov := 72.0
var _shoulder := 0.0
var _height := 1.55
var _idle_mouse := 0.0
var _shape := SphereShape3D.new()
var _noise := FastNoiseLite.new()
var _t := 0.0
var exclude: Array[RID] = []
var look_back := false
var first_person_node: Node3D = null
var free_pos := Vector3.ZERO


func _ready() -> void:
	top_level = true
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = 72.0
	cam.near = 0.08
	cam.far = 2400.0
	add_child(cam)
	cam.current = true
	_shape.radius = 0.22
	_noise.seed = 3
	_noise.frequency = 1.6
	process_priority = 100


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = Game.settings.mouse_sens
		if scope_fov > 0.0 and mode == "aim":
			sens *= scope_fov / 70.0
		elif mode == "aim":
			sens *= 0.7
		yaw -= event.relative.x * sens
		var inv := -1.0 if Game.settings.invert_y else 1.0
		pitch = clampf(pitch - event.relative.y * sens * inv, -1.35, 1.1)
		_idle_mouse = 0.0
	elif event is InputEventJoypadMotion:
		pass


func add_trauma(a: float) -> void:
	trauma = clampf(trauma + a, 0.0, 1.0)


func cycle_view() -> void:
	view = (view + 1) % 3


func is_first_person() -> bool:
	return view == 2 and mode in ["foot", "aim", "vehicle", "boat"]


func aim_forward() -> Vector3:
	return -cam.global_basis.z


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_t += delta
	_idle_mouse += delta
	# gamepad right stick
	var rs := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if rs.length() > 0.15:
		yaw -= rs.x * delta * 2.6
		pitch = clampf(pitch - rs.y * delta * 2.0, -1.35, 1.1)
		_idle_mouse = 0.0
	var tpos: Vector3 = target.get_global_transform_interpolated().origin
	var want_dist := 4.0
	var want_fov: float = Game.settings.fov
	var want_shoulder := 0.0
	var want_height := 1.55
	var base_yaw := yaw
	var base_pitch := pitch
	match mode:
		"foot":
			want_dist = 3.6 if view == 0 else 5.4
			want_shoulder = 0.35
			want_height = 1.55
			var p := Game.player
			if p and p.crouching:
				want_height = 1.05
			if p and p.state == "swim":
				want_height = 0.9
			if p and p.sprinting:
				want_fov += 6.0
			if p and p.in_cover:
				want_shoulder = 0.75 * p.cover_side
				want_dist = 3.0
		"aim":
			want_dist = 2.0
			want_shoulder = 0.62
			want_height = 1.55
			want_fov = 50.0
			if Game.player and Game.player.crouching:
				want_height = 1.1
			if Game.player and Game.player.in_cover:
				want_shoulder = 0.8 * Game.player.cover_side
			if scope_fov > 0.0:
				want_fov = scope_fov
		"vehicle", "boat":
			var v := target as VehicleBase
			var sz := v.cam_distance if v else 6.0
			want_dist = sz * (1.0 if view != 1 else 1.45)
			want_height = (v.cam_height if v else 1.8)
			var spd := v.linear_velocity.length() if v else 0.0
			want_fov += clampf(spd * 0.35, 0.0, 16.0)
			if _idle_mouse > 1.4 and v and spd > 2.0:
				var vy := atan2(v.global_basis.z.x, v.global_basis.z.z)
				var fwd := -v.global_basis.z
				if v.linear_velocity.dot(fwd) < -1.0:
					vy += PI
				yaw = lerp_angle(yaw, vy, 1.0 - exp(-2.2 * delta))
				pitch = lerpf(pitch, -0.2, 1.0 - exp(-2.0 * delta))
			base_yaw = yaw + (PI if look_back else 0.0)
			base_pitch = pitch
			if Game.player and Game.player.aiming_in_vehicle:
				want_dist *= 0.75
				want_fov = 55.0
		"air":
			var a := target as VehicleBase
			want_dist = a.cam_distance if a else 14.0
			want_height = a.cam_height if a else 3.0
			if a:
				var f := -a.global_basis.z
				var vy2 := atan2(-f.x, -f.z)
				if _idle_mouse > 1.2:
					yaw = lerp_angle(yaw, vy2, 1.0 - exp(-3.0 * delta))
					pitch = lerpf(pitch, clampf(asin(clampf(f.y, -1.0, 1.0)) - 0.12, -1.2, 0.8), 1.0 - exp(-2.5 * delta))
				want_fov += clampf(a.linear_velocity.length() * 0.2, 0.0, 14.0)
			base_yaw = yaw + (PI if look_back else 0.0)
			base_pitch = pitch
		"death":
			want_dist = 6.5
			want_height = 1.0
			yaw += delta * 0.25
			base_yaw = yaw
		"photo":
			pass
	_dist = U.damp(_dist, want_dist, 6.0, delta)
	_fov = U.damp(_fov, want_fov, 8.0, delta)
	_shoulder = U.damp(_shoulder, want_shoulder, 8.0, delta)
	_height = U.damp(_height, want_height, 8.0, delta)
	var basis := Basis.from_euler(Vector3(base_pitch, base_yaw, 0.0))
	var pivot := tpos + Vector3(0, _height, 0)
	var final_pos: Vector3
	if is_first_person() and first_person_node and is_instance_valid(first_person_node):
		final_pos = first_person_node.global_position + basis * Vector3(0, 0.05, -0.12)
		_fov = U.damp(_fov, want_fov + 4.0, 8.0, delta)
	else:
		var shoulder_pt := pivot + basis * Vector3(_shoulder, 0, 0)
		var sp := _cast(pivot, shoulder_pt)
		var desired := sp + basis * Vector3(0, 0, _dist)
		final_pos = _cast(sp, desired)
	# shake
	var shake := trauma * trauma
	var rot := Vector3.ZERO
	if shake > 0.0001:
		rot = Vector3(_noise.get_noise_2d(_t * 40.0, 0.0), _noise.get_noise_2d(0.0, _t * 40.0), _noise.get_noise_2d(_t * 40.0, 100.0)) * 0.06 * shake
	trauma = maxf(trauma - delta * 1.2, 0.0)
	if mode == "photo":
		return
	global_transform = Transform3D(basis * Basis.from_euler(rot), final_pos)
	cam.fov = _fov


func _cast(from: Vector3, to: Vector3) -> Vector3:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _shape
	q.transform = Transform3D(Basis.IDENTITY, from)
	q.motion = to - from
	q.collision_mask = C.MASK_CAMERA
	q.exclude = exclude
	var res := get_world_3d().direct_space_state.cast_motion(q)
	var safe: float = res[0] if res.size() > 0 else 1.0
	return from + (to - from) * safe


## World point under the crosshair: the first solid hit along the camera ray, otherwise a far point
## along the same line so projectiles/hitscan weapons keep their direction at range.
func crosshair_point(max_dist := 400.0, ex: Array = []) -> Vector3:
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var hit := U.ray(from + dir * 0.4, from + dir * max_dist, C.MASK_BULLET, ex)
	if hit.is_empty():
		return from + dir * max_dist
	return hit.position
