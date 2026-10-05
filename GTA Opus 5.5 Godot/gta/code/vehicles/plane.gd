class_name Airplane
extends VehicleBase
## Arcade airplane: throttle, lift from airspeed & angle of attack, stall, weathervane stability,
## control authority scaled by airspeed, landing gear with brakes/nose-wheel steering.

var throttle_level := 0.0
var stalled := false
var _stall_warn_t := 0.0


func _vehicle_ready() -> void:
	cam_distance = 15.0 if not def.get("jet", false) else 17.0
	cam_height = 3.2
	angular_damp = 1.2
	linear_damp = 0.02
	susp_rest = 0.35


func _vehicle_physics(delta: float) -> void:
	var fwd := -global_basis.z
	var up := global_basis.y
	var right := global_basis.x
	var v := linear_velocity
	var airspeed := v.dot(fwd)
	var stab: float = Game.skills.flight_stability() if driver is Player else 1.0
	var pilot := driver != null and engine_on
	var c_thr_up: float = controls.get("throttle_up", 0.0)
	var c_thr_dn: float = controls.get("throttle_down", 0.0)
	var c_pitch: float = controls.get("pitch", 0.0)      # W = +1 = nose down
	var c_roll: float = -controls.get("steer", 0.0)      # D = roll right
	var c_yaw: float = controls.get("roll", 0.0)         # Q/E rudder
	if pilot:
		throttle_level = clampf(throttle_level + (c_thr_up - c_thr_dn) * delta * 0.6, 0.0, 1.0)
	else:
		throttle_level = move_toward(throttle_level, 0.0, delta * 0.5)
	rpm = lerpf(rpm, 0.2 + throttle_level * 0.8 if engine_on else 0.0, 1.0 - exp(-4.0 * delta))
	if vis and vis.prop:
		vis.prop.rotate_z(delta * (8.0 + rpm * 70.0))
	# gear
	var grounded := 0
	for w in wheels:
		var f := wheel_suspension(w, delta, susp_rest, mass * 30.0 / 3.0, mass * 4.0 / 3.0)
		if f > 0.0:
			grounded += 1
			var ws := global_basis
			if w.steer:
				ws = ws * Basis(Vector3.UP, controls.get("steer", 0.0) * 0.35)
			var rel: Vector3 = (w.hit_pos as Vector3) - global_position
			var pv := v + angular_velocity.cross(rel)
			var lat := pv.dot(ws.x)
			var lon := pv.dot(-ws.z)
			var brake := 1.0 if (throttle_level < 0.05 and controls.get("throttle_down", 0.0) > 0.5) else 0.0
			apply_force(-ws.x * lat * mass * 2.5 / 3.0 - (-ws.z) * signf(lon) * minf(absf(lon) * mass, mass * 6.0 * brake + mass * 0.15) / 3.0, rel)
	# thrust
	var vmax: float = float(def.get("vmax", 70.0))
	var thrust: float = throttle_level * float(def.engine) * clampf(1.0 - pow(maxf(airspeed, 0.0) / vmax, 2.0), 0.0, 1.0)
	apply_central_force(fwd * thrust)
	# aero
	var stall_v: float = float(def.get("stall", 24.0))
	var vdir := v.normalized() if v.length() > 1.0 else fwd
	var aoa := 0.0
	if v.length() > 2.0:
		aoa = asin(clampf(-vdir.dot(up), -1.0, 1.0))
	var cl := clampf(0.35 + aoa * 4.0, -0.6, 1.4)
	stalled = (airspeed < stall_v and grounded == 0) or aoa > 0.42
	if stalled:
		cl *= 0.35
		_stall_warn_t -= delta
		if _stall_warn_t <= 0.0 and driver is Player:
			_stall_warn_t = 3.0
			Game.notify("STALL — push the nose down (W) and add throttle (SHIFT)", "warn")
	var q := airspeed * airspeed
	var lift := cl * q * mass * 9.8 / (stall_v * stall_v * 0.75)
	lift = minf(lift, mass * 9.8 * 3.0)
	var lift_dir := up - up.dot(vdir) * vdir
	apply_central_force(lift_dir.normalized() * lift)
	apply_central_force(-v * v.length() * mass * (0.0009 + aoa * aoa * 0.004))
	# side slip damping (fin)
	apply_central_force(-right * v.dot(right) * mass * 0.6)
	# controls
	var auth := clampf(airspeed / (stall_v * 1.2), 0.0, 1.6)
	var k := mass * (1.4 if not def.get("jet", false) else 2.2) * (0.7 + 0.3 * stab)
	var torque := right * (-c_pitch) * k * auth + (-fwd) * c_roll * k * 1.5 * auth * -1.0 + up * c_yaw * k * 0.5 * auth
	if grounded > 0:
		torque += up * controls.get("steer", 0.0) * mass * 0.8 * clampf(airspeed / 8.0, 0.2, 1.0)
	# weathervane: align nose with velocity
	if v.length() > 8.0:
		var align := fwd.cross(vdir)
		torque += align * mass * 3.0 * auth
	if stalled and grounded == 0:
		torque += right * -mass * 1.5
	torque -= angular_velocity * mass * 1.1
	apply_torque(torque)
	braking = throttle_level < 0.05
	if driver is Player and grounded == 0:
		Game.skills.add("flying", delta * 0.01)


func is_landed() -> bool:
	for w in wheels:
		if w.contact:
			return true
	return false
