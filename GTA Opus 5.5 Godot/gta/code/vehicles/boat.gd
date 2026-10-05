class_name Boat
extends VehicleBase
## Buoyant speedboat: multi-point buoyancy, keel drag, prop thrust (only when submerged), rudder, planing.

var buoy := [Vector3(-0.85, 0.15, -2.6), Vector3(0.85, 0.15, -2.6), Vector3(-1.0, 0.1, 0.0), Vector3(1.0, 0.1, 0.0), Vector3(-0.95, 0.15, 2.8), Vector3(0.95, 0.15, 2.8)]
var _spray_t := 0.0


func _vehicle_ready() -> void:
	cam_distance = 9.5
	cam_height = 2.2
	angular_damp = 1.4
	linear_damp = 0.2


static func wave(p: Vector3, t: float) -> float:
	return sin(p.x * 0.11 + t * 1.1) * 0.12 + sin(p.z * 0.07 - t * 0.8) * 0.12


func _vehicle_physics(delta: float) -> void:
	var t := Game.now()
	var fwd := -global_basis.z
	var up := global_basis.y
	var v := linear_velocity
	var submerged_pts := 0
	var storm := 1.0 + (Game.env.wetness if Game.env else 0.0)
	for p in buoy:
		var wp := global_transform * (p as Vector3)
		var depth := C.SEA_LEVEL + wave(wp, t) * storm - wp.y
		if depth > 0.0:
			submerged_pts += 1
			var rel := wp - global_position
			var pv := v + angular_velocity.cross(rel)
			var f := minf(depth, 0.9) * mass * 9.8 * 0.55 - pv.y * mass * 0.35
			apply_force(Vector3.UP * f, rel)
	var in_water := submerged_pts > 0
	var spd_f := v.dot(fwd)
	var throttle: float = controls.get("throttle", 0.0) if engine_on and driver != null else 0.0
	var steer_in: float = controls.get("steer", 0.0)
	braking = throttle < 0.0 and spd_f > 1.0
	reversing = throttle < 0.0 and spd_f <= 1.0
	if in_water:
		# keel: kill lateral motion, light longitudinal drag
		var lat := v.dot(global_basis.x)
		apply_central_force(-global_basis.x * lat * mass * 1.6)
		apply_central_force(-fwd * spd_f * absf(spd_f) * mass * 0.0035)
		var prop_world := global_transform * Vector3(0, 0.05, 3.8)
		if prop_world.y < C.SEA_LEVEL + 0.3:
			var vmax: float = float(def.get("vmax", 34.0)) * perf.engine
			var thrust: float = throttle * float(def.engine) * perf.engine * clampf(1.0 - pow(maxf(spd_f, 0.0) / vmax, 2.0), 0.0, 1.0)
			if throttle < 0.0:
				thrust *= 0.45
			var flat_fwd := Vector3(fwd.x, 0, fwd.z).normalized()
			apply_force(flat_fwd * thrust, prop_world - global_position)
		# rudder
		var yaw_rate := steer_in * clampf(absf(spd_f) / 6.0, 0.25, 1.0) * (1.2 if spd_f >= 0.0 else -1.0)
		apply_torque(Vector3.UP * (yaw_rate - angular_velocity.y) * mass * 3.0)
		# bank into turns + planing bow lift
		apply_torque(fwd * -steer_in * clampf(spd_f / 20.0, 0.0, 1.0) * mass * 1.2)
		apply_torque(global_basis.x * clampf(spd_f / 25.0, 0.0, 1.0) * mass * 1.2)
		# keep upright
		apply_torque(up.cross(Vector3.UP) * mass * 6.0)
		if absf(spd_f) > 8.0:
			_spray_t -= delta
			if _spray_t <= 0.0:
				_spray_t = 0.12
				VFX.burst("splash", global_transform * Vector3(0, 0.0, -2.4), Vector3.UP, 0.35)
	else:
		# beached: heavy friction
		apply_central_force(-v * mass * 2.0)
	if _prop_node():
		_prop_node().rotate_z(throttle * delta * 40.0)
	rpm = lerpf(rpm, clampf(absf(throttle) * 0.9 + 0.1, 0.0, 1.0) if engine_on else 0.0, 1.0 - exp(-5.0 * delta))
	if driver is Player and in_water and absf(spd_f) > 5.0:
		Game.skills.add("driving", delta * 0.01)


func _prop_node() -> Node3D:
	return vis.prop if vis else null


func submerged() -> bool:
	return global_basis.y.y < -0.2 and global_position.y < C.SEA_LEVEL
