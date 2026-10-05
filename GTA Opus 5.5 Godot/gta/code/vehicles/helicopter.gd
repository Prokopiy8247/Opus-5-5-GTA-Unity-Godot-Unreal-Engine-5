class_name Helicopter
extends VehicleBase
## Arcade-realistic helicopter: rotor spin-up, collective with altitude hold, cyclic pitch/roll,
## yaw (tail rotor), auto-levelling scaled by Flying skill, skids, rotor wash, rotor strike damage.

var rotor := 0.0
var skids: Array = []
var _dust_t := 0.0
var searchlight: SpotLight3D
var ai_target_pos := Vector3.ZERO
var ai_mode := ""            # "", "orbit" (police support)


func _vehicle_ready() -> void:
	cam_distance = 13.0
	cam_height = 3.0
	angular_damp = 2.5
	linear_damp = 0.3
	for p in [Vector3(-0.85, 0.12, -1.2), Vector3(0.85, 0.12, -1.2), Vector3(-0.85, 0.12, 1.2), Vector3(0.85, 0.12, 1.2)]:
		var n := Node3D.new()
		add_child(n)
		n.position = p
		skids.append({"node": n, "pos": p, "radius": 0.12, "comp": 0.0, "contact": false, "hit_pos": Vector3.ZERO, "normal": Vector3.UP, "load": 0.0})
	if def.get("searchlight", false):
		searchlight = SpotLight3D.new()
		searchlight.position = Vector3(0, 0.2, -1.6)
		searchlight.spot_range = 90.0
		searchlight.spot_angle = 14.0
		searchlight.light_energy = 0.0
		searchlight.light_color = Color(0.95, 0.97, 1.0)
		add_child(searchlight)


func _vehicle_physics(delta: float) -> void:
	var has_pilot := driver != null
	rotor = move_toward(rotor, 1.0 if (engine_on and has_pilot) else 0.0, delta * (0.35 if has_pilot else 0.15))
	if vis and vis.rotor:
		vis.rotor.rotate_y(rotor * delta * 38.0)
	if vis and vis.tail_rotor:
		vis.tail_rotor.rotate_x(rotor * delta * 60.0)
	rpm = rotor
	var up := global_basis.y
	var fwd := -global_basis.z
	var right := global_basis.x
	var v := linear_velocity
	var stab: float = Game.skills.flight_stability() if driver is Player else 1.0
	var c_up: float = controls.get("up", 0.0)
	var c_pitch: float = controls.get("pitch", 0.0)
	var c_roll: float = controls.get("roll", 0.0)
	var c_yaw: float = controls.get("yaw", 0.0)
	# skids
	var on_ground := 0
	for s in skids:
		var f := wheel_suspension(s, delta, 0.25, mass * 40.0 / 4.0, mass * 6.0 / 4.0)
		if f > 0.0:
			on_ground += 1
			var rel: Vector3 = (s.hit_pos as Vector3) - global_position
			var pv := v + angular_velocity.cross(rel)
			var lateral := pv - pv.project(up)
			apply_force(-lateral * mass * 0.9 / 4.0, rel)
	if rotor > 0.05:
		# collective: altitude hold with input
		var target_vy := c_up * 9.0
		var g := 9.8
		var tilt := maxf(up.y, 0.35)
		var lift := (mass * g + (target_vy - v.y) * mass * 2.2) / tilt
		lift = clampf(lift, 0.0, mass * g * 2.6) * rotor
		if rotor < 0.85:
			lift *= rotor * 0.9
		apply_central_force(up * lift)
		# attitude
		var cur_pitch := asin(clampf(fwd.y, -1.0, 1.0))
		var cur_roll := asin(clampf(-right.y, -1.0, 1.0))
		var t_pitch := -c_pitch * 0.42
		var t_roll := c_roll * 0.5 + c_yaw * 0.15 * clampf(v.length() / 20.0, 0.0, 1.0)
		var k := mass * 7.0 * (0.6 + 0.4 * stab)
		var dmp := mass * 2.2
		var torque := right * (t_pitch - cur_pitch) * k + (-fwd) * (t_roll - cur_roll) * k * -1.0
		torque -= (angular_velocity - angular_velocity.project(up)) * dmp
		# yaw
		var yaw_rate := c_yaw * 1.4
		torque += up * (yaw_rate - angular_velocity.dot(up)) * mass * 2.0
		apply_torque(torque * rotor)
		# turbulence for low skill
		if driver is Player and stab < 0.9 and v.length() > 10.0:
			apply_torque(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * mass * (1.0 - stab) * 1.5)
		# drag
		var hv := Vector3(v.x, 0, v.z)
		apply_central_force(-hv * hv.length() * mass * 0.0028)
		# speed cap
		var vmax: float = float(def.get("vmax", 55.0))
		if hv.length() > vmax:
			apply_central_force(-hv.normalized() * (hv.length() - vmax) * mass * 2.0)
		# rotor wash dust
		var agl := global_position.y - maxf(WorldMap.height(global_position.x, global_position.z), C.SEA_LEVEL)
		if agl < 14.0 and rotor > 0.6:
			_dust_t -= delta
			if _dust_t <= 0.0:
				_dust_t = 0.25
				var gp := Vector3(global_position.x, maxf(WorldMap.height(global_position.x, global_position.z), C.SEA_LEVEL) + 0.2, global_position.z)
				if gp.y <= C.SEA_LEVEL + 0.3:
					VFX.burst("splash", gp, Vector3.UP, 1.0)
				else:
					VFX.dust_cloud(gp, 1.5)
		# rotor strike: hitting walls with the rotor spinning
		if on_ground == 0 and v.length() < 0.5 and _prev_vel.length() > 12.0:
			take_damage(250.0, null, global_position, Vector3.ZERO, "crash")
	# searchlight at night
	if searchlight:
		searchlight.light_energy = 8.0 * Game.night_factor if rotor > 0.5 else 0.0
		if ai_mode == "orbit" and Game.player:
			searchlight.look_at(Game.player.global_position, Vector3.UP)


func is_landed() -> bool:
	for s in skids:
		if s.contact:
			return true
	return false
