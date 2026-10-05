class_name Car
extends VehicleBase
## Raycast-suspension wheeled vehicle (cars, trucks, motorcycles, bicycles).

var _skid_t := 0.0
var _gear := 1
var _upside_t := 0.0
var _air_t := 0.0
var _stunt_air := 0.0
var _stunt_start := Vector3.ZERO
var two_wheel := false


func _vehicle_ready() -> void:
	two_wheel = kind in ["bike", "bicycle"]
	susp_rest = 0.32 if not two_wheel else 0.22
	var m := mass
	susp_k = m * (24.0 if not two_wheel else 30.0) / maxf(wheels.size(), 1) * perf.susp
	susp_c = m * (3.2 if not two_wheel else 3.0) / maxf(wheels.size(), 1)
	cam_distance = clampf(half_extents.z * 2.0 + 2.2, 4.5, 12.0)
	cam_height = clampf(half_extents.y * 2.0 + 0.6, 1.4, 3.6)
	if two_wheel:
		cam_distance = 4.2
		cam_height = 1.5
		angular_damp = 2.0


func _vehicle_physics(delta: float) -> void:
	var fwd := -global_basis.z
	var up := global_basis.y
	var right := global_basis.x
	var v := linear_velocity
	var spd_f := v.dot(fwd)
	var throttle: float = controls.get("throttle", 0.0) if engine_on else 0.0
	var steer_in: float = controls.get("steer", 0.0)
	var hb: float = controls.get("handbrake", 0.0)
	var has_driver := driver != null
	if not has_driver and ai_driver == null:
		throttle = 0.0
		hb = 1.0 if v.length() < 3.0 else 0.3
	# steering (less lock at speed)
	var max_steer: float = float(def.get("steer", 0.55)) * lerpf(1.0, 0.3, clampf(absf(spd_f) / 45.0, 0.0, 1.0))
	steer_angle = move_toward(steer_angle, steer_in * max_steer, delta * 2.6)
	if vis and vis.steering:
		vis.steering.basis = Basis(VehicleVisuals.STEER_AXIS, steer_angle * 2.2)
	var grip_base: float = float(def.get("grip", 1.0)) * perf.grip * dmg_handling
	if Game.env:
		grip_base *= Game.env.grip_factor()
	if driver is Player:
		grip_base *= Game.skills.grip_bonus()
	var vmax: float = float(def.get("vmax", 50.0)) * (1.0 + (perf.engine - 1.0) * 0.6) * perf.trans
	var engine: float = float(def.get("engine", 6000.0)) * perf.engine
	if controls.get("boost", 0.0) > 0.5 and kind == "bicycle":
		engine *= 1.6
		if driver is Player:
			Game.skills.add("stamina", delta * 0.02)
	braking = false
	reversing = false
	var drive_force := 0.0
	var brake_force := 0.0
	if throttle > 0.05:
		if spd_f < -1.0:
			brake_force = throttle
			braking = true
		else:
			drive_force = throttle * engine * clampf(1.0 - pow(maxf(spd_f, 0.0) / vmax, 2.0), 0.0, 1.0)
	elif throttle < -0.05:
		if spd_f > 1.0:
			brake_force = -throttle
			braking = true
		else:
			drive_force = throttle * engine * 0.55 * clampf(1.0 - pow(maxf(-spd_f, 0.0) / (vmax * 0.35), 2.0), 0.0, 1.0)
			reversing = true
	var n_drive := 0
	for w in wheels:
		if w.drive:
			n_drive += 1
	n_drive = maxi(n_drive, 1)
	var grounded := 0
	var skid := 0.0
	var mw := mass / maxf(wheels.size(), 1)
	for w in wheels:
		var load := wheel_suspension(w, delta, susp_rest, susp_k, susp_c)
		var wnode: Node3D = w.node
		if w.steer:
			wnode.rotation.y = steer_angle
		if not w.contact:
			_spin_wheel(w, spd_f, delta, hb > 0.5 and not w.steer)
			continue
		grounded += 1
		var ws := global_basis
		if w.steer:
			ws = ws * Basis(Vector3.UP, steer_angle)
		var wf := -ws.z
		var wr := ws.x
		var cp: Vector3 = w.hit_pos
		var rel := cp - global_position
		var pv := v + angular_velocity.cross(rel)
		var v_long := pv.dot(wf)
		var v_lat := pv.dot(wr)
		var f_long := 0.0
		if w.drive:
			f_long += drive_force / n_drive
		f_long += -signf(v_long) * minf(absf(v_long) * mw * 6.0, brake_force * mass * 9.0 * perf.brakes / wheels.size())
		f_long += -v_long * mw * 0.08
		var rear: bool = not w.steer
		var g: float = grip_base * float(w.grip_mul)
		if rear and hb > 0.5:
			g *= 0.32
			f_long += -signf(v_long) * minf(absf(v_long) * mw * 2.0, mass * 5.0 / wheels.size())
		var f_lat := -v_lat * mw * 9.0 * g
		var mu := g * 1.15 * maxf(load, mw * 4.0)
		var total := Vector2(f_long, f_lat)
		if total.length() > mu:
			total = total.normalized() * mu
			skid += absf(v_lat) + (3.0 if absf(f_long) > mu * 0.9 and drive_force > 0.0 else 0.0)
		elif absf(v_lat) > 4.0:
			skid += absf(v_lat) * 0.5
		var force := wf * total.x + wr * total.y
		force -= force.dot(up) * up
		apply_force(force, rel)
		_spin_wheel(w, v_long, delta, rear and hb > 0.5)
	# aero
	var drag := 0.0028 * mass * 0.06
	apply_central_force(-v * v.length() * drag)
	apply_central_force(-up * v.length_squared() * perf.downforce * 0.6)
	# two-wheel balance
	if two_wheel and has_driver:
		var lean := -steer_angle * clampf(absf(spd_f) / 12.0, 0.0, 1.0) * 1.2
		var target_up := Vector3.UP.rotated(fwd, lean)
		var err := up.cross(target_up)
		var k_up := mass * 60.0
		apply_torque(err * k_up - angular_velocity.project(fwd) * mass * 8.0)
		# yaw assist for responsive steering
		var yaw_rate := steer_angle * spd_f * 0.55
		var cur_yaw := angular_velocity.dot(up)
		apply_torque(up * (yaw_rate - cur_yaw) * mass * 1.2)
	elif two_wheel and not has_driver and v.length() < 1.0 and up.y > 0.7:
		# parked: kick-stand
		var err2 := up.cross(Vector3.UP.rotated(fwd, 0.12))
		apply_torque(err2 * mass * 40.0 - angular_velocity * mass * 4.0)
	# airborne control + stunt tracking
	if grounded == 0:
		_air_t += delta
		if has_driver and _air_t > 0.3:
			var p: float = controls.get("throttle", 0.0)
			var r: float = controls.get("steer", 0.0)
			apply_torque((right * -p * 0.6 + fwd * r * 0.5) * mass * 2.0)
		if _air_t > 0.6 and _stunt_air == 0.0:
			_stunt_air = 0.001
			_stunt_start = global_position
	else:
		if _stunt_air > 0.0 and _air_t > 1.0 and driver is Player:
			var dist := U.flat_dist(_stunt_start, global_position)
			if Game.activities and Game.activities.has_method("on_vehicle_jump"):
				Game.activities.on_vehicle_jump(self, _air_t, dist, up.y > 0.7)
		_stunt_air = 0.0
		_air_t = 0.0
	# rpm / gears for audio
	var sp := absf(spd_f)
	var gear_top := vmax / 5.0
	_gear = clampi(int(sp / gear_top) + 1, 1, 5)
	var in_gear := fmod(sp, gear_top) / gear_top
	rpm = lerpf(rpm, clampf(0.15 + in_gear * 0.75 + absf(throttle) * 0.1, 0.0, 1.0) if engine_on else 0.0, 1.0 - exp(-8.0 * delta))
	# skid fx
	if skid > 6.0 and grounded > 0 and v.length() > 4.0:
		_skid_t -= delta
		if _skid_t <= 0.0:
			_skid_t = 0.06
			var w0: Dictionary = wheels[wheels.size() - 1]
			VFX.tire_smoke(w0.hit_pos)
		if _skid_audio and not _skid_audio.playing:
			_skid_audio.play()
	elif _skid_audio and _skid_audio.playing:
		_skid_audio.stop()
	# upside-down recovery hint
	if up.y < 0.25 and v.length() < 2.0:
		_upside_t += delta
		if _upside_t > 2.5 and driver is Player:
			_upside_t = -6.0
			Game.notify("Vehicle flipped — press F to bail out (or use the debug menu to repair)", "hint")
	else:
		_upside_t = 0.0


func _spin_wheel(w: Dictionary, v_long: float, delta: float, locked: bool) -> void:
	if locked:
		return
	w.spin_angle = fmod(float(w.spin_angle) - v_long / float(w.radius) * delta, TAU)
	var sp: Node3D = w.get("spin")
	if sp:
		sp.rotation.x = w.spin_angle
