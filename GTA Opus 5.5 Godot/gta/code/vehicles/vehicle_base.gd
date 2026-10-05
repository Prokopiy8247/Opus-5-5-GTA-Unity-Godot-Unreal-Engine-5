class_name VehicleBase
extends RigidBody3D
## Shared vehicle framework: seats & occupants, raycast wheels, collision damage, fire/explosion,
## lights/siren/horn/radio, engine audio, customization (mods) and repair.

signal destroyed_sig(v: VehicleBase)

var def_id := "sedan"
var def := {}
var display_name := ""
var kind := "car"
var faction := ""
var mods := {}
var health := 1000.0
var max_health := 1000.0
var destroyed := false
var engine_on := false
var controls := {}
var half_extents := Vector3(1, 0.7, 2.3)
var cam_distance := 6.5
var cam_height := 1.6
var vis: VehicleVisuals.Result
var visual_root: Node3D
var seat_nodes: Array[Node3D] = []
var seat_doors: Array = []
var occupants: Array = []
var lights_on := false
var siren_on := false
var parked := false
## Unoccupied vehicles at rest are frozen as static bodies and skip all per-tick work until something
## moves near them, damages them or a character gets in (the big CPU win with ~50 cars around).
var dormant := false
var _rest_t := 0.0
var _wake_check_t := 0.0
var _fx_cache := {}
var ai_driver: Node = null
var traffic_owned := false
var police_unit := false
var owner_is_player := false
var perf := {"engine": 1.0, "brakes": 1.0, "grip": 1.0, "susp": 1.0, "trans": 1.0, "armor": 1.0, "downforce": 0.0, "bp_tires": false}
var dmg_handling := 1.0
var _prev_vel := Vector3.ZERO
var _smoke: GPUParticles3D
var _fire: GPUParticles3D
var _burn_t := 0.0
var _engine_audio: AudioStreamPlayer3D
var _horn_audio: AudioStreamPlayer3D
var _siren_audio: AudioStreamPlayer3D
var _radio_audio: AudioStreamPlayer3D
var _skid_audio: AudioStreamPlayer3D
var _head_spots: Array[SpotLight3D] = []
var _siren_light: OmniLight3D
var _siren_t := 0.0
var _ignore := {}
var _prop_t := 0.0
var _crash_cd := 0.0
var _submerge_t := 0.0
var braking := false
var reversing := false
var rpm := 0.0
var speed_kmh := 0.0
var last_damager: Node = null

# wheels (raycast suspension)
var wheels: Array = []       # [{node, spin, pos, radius, steer, drive, side, comp, contact, hit_pos, normal, spin_angle, grip_mul}]
var susp_rest := 0.35
var susp_k := 0.0
var susp_c := 0.0
var steer_angle := 0.0


static func spawn(id: String, xf: Transform3D, parent: Node = null, vmods := {}) -> VehicleBase:
	var d := VehicleDB.get_def(id)
	var v: VehicleBase
	match d.kind:
		"boat":
			v = Boat.new()
		"heli":
			v = Helicopter.new()
		"plane":
			v = Airplane.new()
		_:
			v = Car.new()
	v.def_id = id
	v.def = d
	v.mods = vmods.duplicate(true)
	v.name = "Veh_" + id
	if parent == null:
		parent = (Engine.get_main_loop() as SceneTree).current_scene.get_node_or_null("Vehicles")
		if parent == null:
			parent = (Engine.get_main_loop() as SceneTree).current_scene
	parent.add_child(v)
	v.global_transform = xf
	v.reset_physics_interpolation()
	return v


func _ready() -> void:
	display_name = def.get("name", def_id)
	kind = def.get("kind", "car")
	faction = def.get("faction", "")
	police_unit = faction == "police"
	mass = float(def.get("mass", 1200.0))
	max_health = 1000.0 * float(def.get("armor", 1.0))
	health = max_health
	collision_layer = C.L_VEHICLE
	collision_mask = C.MASK_VEHICLE
	continuous_cd = true
	contact_monitor = false
	can_sleep = true
	angular_damp = 0.6
	linear_damp = 0.05
	set_meta("surface", C.SURF_METAL)
	_build_visual()
	_build_collision()
	_build_audio()
	_build_lights()
	_apply_perf()
	Game.register_vehicle(self)
	_vehicle_ready()


func _vehicle_ready() -> void:
	pass


func _exit_tree() -> void:
	Game.unregister_vehicle(self)


func _build_visual() -> void:
	if visual_root:
		visual_root.queue_free()
	vis = VehicleVisuals.build(def_id, def, mods)
	visual_root = vis.root
	add_child(visual_root)
	half_extents = vis.half_extents
	# seats
	for n in seat_nodes:
		if is_instance_valid(n) and n.get_child_count() == 0:
			n.queue_free()
	var old_occ := occupants.duplicate()
	if seat_nodes.size() != vis.seats.size():
		seat_nodes.clear()
		seat_doors.clear()
		occupants.clear()
		for i in vis.seats.size():
			var sn := Node3D.new()
			sn.name = "Seat_%d" % i
			sn.position = vis.seats[i].pos
			add_child(sn)
			seat_nodes.append(sn)
			seat_doors.append(vis.seats[i].door)
			occupants.append(old_occ[i] if i < old_occ.size() else null)
	wheels.clear()
	for w in vis.wheels:
		var wd: Dictionary = w.duplicate()
		wd["comp"] = 0.0
		wd["contact"] = false
		wd["hit_pos"] = Vector3.ZERO
		wd["normal"] = Vector3.UP
		wd["spin_angle"] = 0.0
		wd["grip_mul"] = 1.0
		wd["load"] = 0.0
		wheels.append(wd)


func _build_collision() -> void:
	for c in get_children():
		if c is CollisionShape3D:
			c.queue_free()
	var he := half_extents
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	match kind:
		"car":
			var b: Array = def.body
			var clr: float = b[4]
			var belt: float = b[2]
			var roof: float = b[3]
			bs.size = Vector3(he.x * 2.0, belt - clr - 0.05, he.z * 2.0 - 0.1)
			cs.position = Vector3(0, (belt + clr) * 0.5 + 0.03, 0)
			var cs2 := CollisionShape3D.new()
			var bs2 := BoxShape3D.new()
			bs2.size = Vector3(he.x * 1.6, roof - belt, he.z * 1.1)
			cs2.shape = bs2
			cs2.position = Vector3(0, (roof + belt) * 0.5, 0.1)
			add_child(cs2)
		"bike", "bicycle":
			bs.size = Vector3(0.35, 0.6, he.z * 2.0 - 0.3)
			cs.position = Vector3(0, float(def.wheel_r) + 0.3, 0)
		"boat":
			bs.size = Vector3(2.2, 0.9, 7.2)
			cs.position = Vector3(0, 0.55, -0.1)
		"heli":
			bs.size = Vector3(1.6, 1.6, 4.2)
			cs.position = Vector3(0, 1.1, -0.1)
			var tail := CollisionShape3D.new()
			var tb := BoxShape3D.new()
			tb.size = Vector3(0.4, 0.5, 4.0)
			tail.shape = tb
			tail.position = Vector3(0, 1.45, 4.4)
			add_child(tail)
		"plane":
			bs.size = Vector3(1.3, 1.3, he.z * 1.8)
			cs.position = Vector3(0, 1.25, 0.2)
			var wing := CollisionShape3D.new()
			var wb := BoxShape3D.new()
			wb.size = Vector3(he.x * 2.0, 0.2, 1.8)
			wing.shape = wb
			wing.position = Vector3(0, 1.85 if not def.get("jet", false) else 0.9, -0.3 if not def.get("jet", false) else 1.0)
			add_child(wing)
	cs.shape = bs
	add_child(cs)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = _com()


func _com() -> Vector3:
	match kind:
		"car":
			return Vector3(0, float(def.body[4]) + 0.25, 0.05)
		"bike", "bicycle":
			return Vector3(0, 0.5, 0.0)
		"boat":
			return Vector3(0, 0.25, 0.3)
		"heli":
			return Vector3(0, 1.0, 0.2)
		"plane":
			return Vector3(0, 1.1, -0.2)
	return Vector3.ZERO


func _build_audio() -> void:
	var a: String = def.get("audio", "")
	if a != "":
		_engine_audio = Audio.make_loop(self, a, -4.0, 140.0)
	_horn_audio = Audio.make_loop(self, "horn", 0.0, 120.0)
	_skid_audio = Audio.make_loop(self, "skid", -8.0, 70.0)
	if def.get("lightbar", false) or faction == "police":
		_siren_audio = Audio.make_loop(self, "siren", 2.0, 260.0)


func _build_lights() -> void:
	for s in _head_spots:
		s.queue_free()
	_head_spots.clear()
	for p in vis.head_points:
		var sp := SpotLight3D.new()
		sp.position = p
		sp.rotation = Vector3(-0.08, 0, 0)
		sp.spot_range = 36.0
		sp.spot_angle = 32.0
		sp.light_color = mods.get("light_color", Color(1.0, 0.95, 0.85))
		sp.light_energy = 0.0
		sp.shadow_enabled = false
		sp.visible = false
		add_child(sp)
		_head_spots.append(sp)
	if def.get("lightbar", false) or faction == "police":
		_siren_light = OmniLight3D.new()
		_siren_light.position = Vector3(0, half_extents.y * 2.0 + 0.6, 0)
		_siren_light.omni_range = 16.0
		_siren_light.light_energy = 0.0
		_siren_light.shadow_enabled = false
		add_child(_siren_light)


# ------------------------------------------------------------------ occupants

func seat_global(i: int) -> Transform3D:
	if i < 0 or i >= seat_nodes.size():
		return global_transform
	return seat_nodes[i].global_transform


func door_position(i: int) -> Vector3:
	if i < 0 or i >= seat_doors.size():
		return global_position + global_basis * Vector3(-2, 0, 0)
	return global_transform * (seat_doors[i] as Vector3)


func seat_occupant(i: int) -> Actor:
	if i < 0 or i >= occupants.size():
		return null
	var o = occupants[i]
	if o == null or not is_instance_valid(o):
		return null
	return o


var driver: Actor:
	get:
		return seat_occupant(0)


func best_seat_for(pos: Vector3, prefer_driver: bool) -> int:
	if seat_nodes.is_empty():
		return -1
	if prefer_driver:
		return 0
	var best := -1
	var bd := INF
	for i in seat_nodes.size():
		if seat_occupant(i) != null:
			continue
		var d := door_position(i).distance_to(pos)
		if d < bd:
			bd = d
			best = i
	return best


func free_seat(exclude_driver := true) -> int:
	for i in seat_nodes.size():
		if exclude_driver and i == 0:
			continue
		if seat_occupant(i) == null:
			return i
	return -1


func enter(a: Actor, i: int) -> void:
	if i < 0 or i >= seat_nodes.size():
		return
	wake()
	occupants[i] = a
	a.vehicle = self
	a.seat = i
	_ignore[a] = true
	if a.rig:
		var r := a.rig
		r.get_parent().remove_child(r)
		seat_nodes[i].add_child(r)
		r.transform = Transform3D.IDENTITY
		r.rotation.y = 0.0
		r.mode = "ride" if kind in ["bike", "bicycle"] else ("drive" if i == 0 else "sit")
		r.reset_physics_interpolation()
	if i == 0:
		engine_on = true
		sleeping = false
		freeze = false
		parked = false
		if a is Player:
			owner_is_player = true
			if is_instance_valid(ai_driver):
				ai_driver.queue_free()
				ai_driver = null
	if _engine_audio and not _engine_audio.playing:
		_engine_audio.play()


func remove_occupant(a: Actor) -> void:
	for i in occupants.size():
		if occupants[i] == a:
			occupants[i] = null
	_ignore.erase(a)
	if a.rig and a.rig.get_parent() != a:
		var r := a.rig
		r.get_parent().remove_child(r)
		a.add_child(r)
		r.transform = Transform3D.IDENTITY
		r.reset_physics_interpolation()
		r.mode = "normal"
	a.vehicle = null
	a.seat = -1
	if driver == null:
		controls = {}
		if a is Player:
			get_tree().create_timer(1.0).timeout.connect(func():
				if is_instance_valid(self) and driver == null:
					_ignore.erase(a))


## Pull an occupant out (carjacking / bailing).
func eject(a: Actor, violent := false) -> void:
	var i := a.seat
	var door := door_position(i if i >= 0 else 0)
	remove_occupant(a)
	a.global_position = door + Vector3(0, 0.1, 0)
	a.reset_physics_interpolation()
	a._restore_collision()
	if violent and a.has_method("knockdown"):
		a.knockdown((door - global_position).normalized() * 2.0 + Vector3(0, 1.5, 0), 1.4)


func is_ignoring(a: Node) -> bool:
	return _ignore.has(a) or (a == Game.player and Game.player and Game.player.vehicle == self)


func eject_all() -> void:
	for i in occupants.size():
		var o := seat_occupant(i)
		if o:
			if o is Player:
				(o as Player).exit_vehicle(true)
			else:
				eject(o, true)


func set_controls(c: Dictionary) -> void:
	controls = c


func on_hit_pedestrian(a: Actor, spd: float) -> void:
	take_damage(spd * 2.0, a, a.global_position, Vector3.ZERO, "impact")
	if driver is Player:
		Game.report_crime("hit_pedestrian" if spd < 14.0 else "vehicular_assault", global_position, a)


# ------------------------------------------------------------------ physics

func _physics_process(delta: float) -> void:
	if destroyed:
		_destroyed_tick(delta)
		return
	if dormant:
		_wake_check_t -= delta
		if _wake_check_t <= 0.0:
			_wake_check_t = 0.15
			if _traffic_nearby():
				wake()
		return
	_crash_cd = maxf(_crash_cd - delta, 0.0)
	var v := linear_velocity
	speed_kmh = v.length() * 3.6
	# collision damage from sudden velocity change not explained by our own forces
	var dv := (v - _prev_vel).length()
	if dv > 7.0 and _crash_cd <= 0.0 and not freeze:
		var dmg: float = (dv - 6.0) * (dv - 6.0) * 2.4 / float(perf.armor)
		take_damage(dmg, last_damager, global_position, Vector3.ZERO, "crash")
		_crash_cd = 0.25
		Audio.play_3d("crash", global_position, clampf(dv - 8.0, -6.0, 6.0), randf_range(0.8, 1.1), 120.0)
		VFX.burst("sparks", global_position + Vector3(0, 0.6, 0), Vector3.UP, 0.8)
		if driver:
			if driver is Player:
				Game.cam.add_trauma(clampf(dv / 25.0, 0.1, 0.8))
				if dv > 14.0:
					Game.emit_event(global_position, 40.0, "crash", self)
			if kind in ["bike", "bicycle"] and dv > 9.0:
				var d := driver
				eject(d, false)
				if d is Player:
					(d as Player).state = "foot"
				d.knockdown(_prev_vel * 0.8 + Vector3(0, 3, 0), 2.0)
				if d is Player:
					(d as Player).state = "ragdoll"
	_prev_vel = v
	# break street props
	if v.length() > 2.0 and Game.world and Game.world.props:
		_prop_t -= delta
		if _prop_t <= 0.0:
			_prop_t = 0.05
			var n := Game.world.props.check_vehicle(self, half_extents, v)
			if n > 0:
				linear_velocity *= 0.92
				take_damage(15.0 * n, null, global_position, Vector3.ZERO, "crash")
				if driver is Player:
					Game.cam.add_trauma(0.15)
	_vehicle_physics(delta)
	_update_effects(delta)
	# go dormant once empty and settled on the ground
	if driver == null and ai_driver == null and occupant_count() == 0 and _fire == null and kind in ["car", "bike", "bicycle"] \
			and linear_velocity.length_squared() < 0.04 and angular_velocity.length_squared() < 0.04:
		_rest_t += delta
		if _rest_t > 1.2:
			go_dormant()
	else:
		_rest_t = 0.0


func occupant_count() -> int:
	var n := 0
	for o in occupants:
		if o != null:
			n += 1
	return n


func go_dormant() -> void:
	if dormant or destroyed:
		return
	dormant = true
	_rest_t = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	for s in _head_spots:
		s.visible = false
	if _engine_audio and _engine_audio.playing:
		_engine_audio.stop()


func wake() -> void:
	if not dormant:
		return
	dormant = false
	_rest_t = 0.0
	freeze = false
	sleeping = false
	_prev_vel = Vector3.ZERO
	_crash_cd = 0.3


## A moving vehicle or a character running at it should find a dynamic body, not a frozen one.
func _traffic_nearby() -> bool:
	var me := global_position
	for o in Game.vehicles:
		var ov := o as VehicleBase
		if ov == null or ov == self or ov.dormant or not is_instance_valid(ov):
			continue
		var r := 7.0 + ov.linear_velocity.length() * 0.35
		if ov.linear_velocity.length_squared() > 1.0 and ov.global_position.distance_squared_to(me) < r * r:
			return true
	return false


func _vehicle_physics(_delta: float) -> void:
	pass


## Raycast suspension for one wheel (spring preloaded so the design ride height is the rest state).
## Returns the normal force.
func wheel_suspension(w: Dictionary, delta: float, rest: float, k: float, c: float) -> float:
	var n: Node3D = w.node
	var r: float = w.radius
	var mount := global_transform * ((w.pos as Vector3) + Vector3(0, rest, 0))
	var down := -global_basis.y
	var pre_load := mass * 9.8 / (maxf(wheels.size(), 1) * k)
	var max_len := rest + pre_load
	var hit := U.ray(mount, mount + down * (max_len + r + 0.05), C.L_WORLD | C.L_VEHICLE | C.L_PROP, [self])
	var cur_len := max_len
	if not hit.is_empty():
		cur_len = mount.distance_to(hit.position) - r
	if hit.is_empty() or cur_len >= max_len:
		w.contact = false
		w.comp = 0.0
		w.load = 0.0
		n.position.y = float(w.pos.y) + rest - max_len
		return 0.0
	var comp := max_len - cur_len
	var comp_v := (comp - float(w.comp)) / delta
	w.comp = comp
	w.contact = true
	w.hit_pos = hit.position
	w.normal = hit.normal
	var force: float = maxf(k * comp + c * comp_v, 0.0)
	if cur_len < 0.0:
		force += -cur_len * k * 6.0
	apply_force(global_basis.y * force, (hit.position as Vector3) - global_position)
	n.position.y = float(w.pos.y) + rest - maxf(cur_len, -0.05)
	w.load = force
	return force


func _update_effects(delta: float) -> void:
	# health-based smoke / fire
	var hf := health / max_health
	if hf < 0.35 and _smoke == null:
		_smoke = VFX.attach_emitter(self, "smoke", Vector3(0, half_extents.y + 0.6, -half_extents.z * 0.6))
	if hf < 0.15 and _fire == null:
		_fire = VFX.attach_emitter(self, "fire", Vector3(0, half_extents.y + 0.4, -half_extents.z * 0.55))
		Game.emit_event(global_position, 30.0, "fire", self)
	if _fire:
		_burn_t += delta
		health -= delta * 25.0
		if health <= 0.0 or _burn_t > 9.0:
			explode()
			return
	dmg_handling = clampf(0.55 + hf * 0.45, 0.55, 1.0)
	# lights
	var night: bool = Game.night_factor > 0.3 or (Game.env and Game.env.weather in ["rain", "storm", "fog"])
	var lit := (lights_on or (night and driver != null and not (driver is Player))) and engine_on
	if driver is Player and night and not lights_on:
		lit = false
	var spots_on := lit and (driver != null) and global_position.distance_to(Game.cam.global_position if Game.cam else global_position) < 140.0
	if _fx_cache.get("spots", null) != spots_on:
		_fx_cache["spots"] = spots_on
		for s in _head_spots:
			s.visible = spots_on
			s.light_energy = 3.2 if spots_on else 0.0
	if vis:
		_set_emit("head", vis.head_mat, 3.5 if lit else 0.25)
		_set_emit("tail", vis.tail_mat, 4.0 if braking else (1.6 if lit else 0.35))
		_set_emit("rev", vis.rev_mat, 3.0 if reversing else 0.0)
	# siren
	if siren_on:
		_siren_t += delta
		var ph := fmod(_siren_t * 3.0, 1.0)
		var red := ph < 0.5
		vis.bar_red.emission_energy_multiplier = 6.0 if red else 0.3
		vis.bar_blue.emission_energy_multiplier = 0.3 if red else 6.0
		if _siren_light:
			_siren_light.light_color = Color(1, 0.15, 0.1) if red else Color(0.2, 0.35, 1.0)
			_siren_light.light_energy = 3.0
	elif vis and vis.bar_red:
		_set_emit("bar_r", vis.bar_red, 0.2)
		_set_emit("bar_b", vis.bar_blue, 0.2)
		if _siren_light and _siren_light.light_energy != 0.0:
			_siren_light.light_energy = 0.0
	# engine audio
	if _engine_audio:
		if engine_on and not _engine_audio.playing:
			_engine_audio.play()
		elif not engine_on and _engine_audio.playing:
			_engine_audio.stop()
		if _engine_audio.playing:
			_engine_audio.pitch_scale = float(def.get("pitch", 1.0)) * (0.55 + rpm * 1.1)
			_engine_audio.volume_db = -10.0 + rpm * 8.0
	# radio volume follows player in vehicle
	if _radio_audio and driver == null:
		_radio_audio.stop()


## Material parameter writes dirty the material every time, so only write on change.
func _set_emit(key: String, m: StandardMaterial3D, e: float) -> void:
	if m == null or _fx_cache.get(key, -1.0) == e:
		return
	_fx_cache[key] = e
	m.emission_energy_multiplier = e


func horn(on: bool) -> void:
	if _horn_audio == null:
		return
	if on and not _horn_audio.playing:
		_horn_audio.pitch_scale = [1.0, 0.6, 1.5][int(mods.get("horn", 0)) % 3]
		_horn_audio.play()
		Game.emit_event(global_position, 25.0, "horn", self)
	elif not on:
		_horn_audio.stop()


func toggle_lights() -> void:
	lights_on = not lights_on


func toggle_siren() -> void:
	if _siren_audio == null:
		return
	set_siren(not siren_on)


func set_siren(on: bool) -> void:
	siren_on = on
	if _siren_audio:
		if on and not _siren_audio.playing:
			_siren_audio.play()
		elif not on:
			_siren_audio.stop()


func set_radio(station: int) -> void:
	if _radio_audio == null:
		_radio_audio = AudioStreamPlayer3D.new()
		_radio_audio.bus = "Music"
		_radio_audio.unit_size = 4.0
		_radio_audio.max_distance = 30.0
		add_child(_radio_audio)
	if station >= 3:
		_radio_audio.stop()
		Game.notify("Radio off")
		return
	var s := Audio.get_stream("radio_%d" % station)
	if s == null:
		Game.notify("Radio warming up…")
		return
	_radio_audio.stream = s
	_radio_audio.volume_db = Game.settings.music_db
	_radio_audio.play()
	Game.notify("♪ " + Audio.STATIONS[station])


# ------------------------------------------------------------------ damage

func take_damage(amount: float, source: Node = null, pos := Vector3.ZERO, impulse := Vector3.ZERO, kind_s := "bullet") -> void:
	if destroyed:
		return
	wake()
	if source:
		last_damager = source
	var a: float = amount / float(perf.armor)
	if kind_s == "explosion":
		a = amount * 4.0 / perf.armor
		apply_central_impulse(impulse * mass * 0.35 + Vector3(0, mass * 2.0, 0))
	elif kind_s in ["bullet", "headshot"]:
		a = amount * 0.9 / perf.armor
		# tires / glass
		if randf() < 0.18 and not perf.bp_tires and kind in ["car", "bike"]:
			_puncture_near(pos)
	health -= a
	if source == Game.player and police_unit and kind_s in ["bullet", "explosion", "headshot"]:
		Game.report_crime("attack_police", global_position)
	if health <= 0.0:
		health = 0.0
		if _fire == null:
			_fire = VFX.attach_emitter(self, "fire", Vector3(0, half_extents.y + 0.4, -half_extents.z * 0.55))
		if kind_s == "explosion" or health < -200.0:
			explode()


func _puncture_near(pos: Vector3) -> void:
	var best := -1
	var bd := 1.2
	for i in wheels.size():
		var wp := global_transform * (wheels[i].pos as Vector3)
		var d := wp.distance_to(pos)
		if d < bd:
			bd = d
			best = i
	if best >= 0 and wheels[best].grip_mul > 0.5:
		wheels[best].grip_mul = 0.35
		Audio.play_3d("impact_metal", pos, 0.0, 0.5)
		if driver is Player:
			Game.notify("Tire blown!", "warn")


func surface_at(pos: Vector3) -> String:
	var lp := global_transform.affine_inverse() * pos
	if kind == "car" and lp.y > float(def.body[2]) + 0.05:
		VFX.burst("glass", pos, Vector3.UP, 0.4)
		return C.SURF_GLASS
	return C.SURF_METAL


func explode() -> void:
	if destroyed:
		return
	destroyed = true
	health = 0.0
	engine_on = false
	set_siren(false)
	horn(false)
	var src := last_damager
	for i in occupants.size():
		var o := seat_occupant(i)
		if o:
			if o is Player:
				(o as Player).exit_vehicle(true)
				o.take_damage(150.0, src, global_position, Vector3(0, 8, 0), "explosion")
			else:
				eject(o, false)
				o.take_damage(999.0, src, global_position, Vector3(0, 8, 0), "explosion")
	Game.explosion(global_position + Vector3(0, 0.8, 0), 8.0, 120.0, src)
	apply_central_impulse(Vector3(randf_range(-2, 2), 9.0, randf_range(-2, 2)) * mass)
	apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * mass * 3.0)
	if src == Game.player and police_unit:
		Game.report_crime("destroy_police", global_position)
	# charred look
	if vis:
		vis.paint.albedo_color = Color(0.08, 0.075, 0.07)
		vis.paint.metallic = 0.0
		vis.paint.roughness = 0.95
		vis.paint.clearcoat_enabled = false
		vis.glass.albedo_color = Color(0.05, 0.05, 0.05, 0.9)
		vis.head_mat.emission_energy_multiplier = 0.0
		vis.tail_mat.emission_energy_multiplier = 0.0
	for s in _head_spots:
		s.visible = false
	if _engine_audio:
		_engine_audio.stop()
	if _smoke == null:
		_smoke = VFX.attach_emitter(self, "smoke", Vector3(0, half_extents.y + 0.5, 0))
	destroyed_sig.emit(self)
	if Game.has_method("on_vehicle_destroyed"):
		Game.on_vehicle_destroyed(self)
	get_tree().create_timer(18.0).timeout.connect(func():
		if is_instance_valid(_fire):
			_fire.emitting = false)


func _destroyed_tick(_delta: float) -> void:
	if wheels.size() > 0 and kind in ["car"]:
		for w in wheels:
			wheel_suspension(w, _delta, susp_rest * 0.6, mass * 18.0, mass * 2.0)


func submerged() -> bool:
	return global_position.y + half_extents.y < C.SEA_LEVEL - 0.3 and WorldMap.is_water(global_position.x, global_position.z)


func repair() -> void:
	health = max_health
	destroyed = false
	dmg_handling = 1.0
	_burn_t = 0.0
	if is_instance_valid(_fire):
		_fire.queue_free()
	if is_instance_valid(_smoke):
		_smoke.queue_free()
	_fire = null
	_smoke = null
	for w in wheels:
		w.grip_mul = 1.0
	_build_visual()
	_build_lights()


## Rebuild visuals + performance after customization.
func apply_mods(m: Dictionary) -> void:
	mods = m.duplicate(true)
	_build_visual()
	_build_lights()
	_apply_perf()


func _apply_perf() -> void:
	perf.engine = 1.0 + 0.1 * float(mods.get("engine", 0)) + (0.12 if mods.get("turbo", false) else 0.0)
	perf.brakes = 1.0 + 0.15 * float(mods.get("brakes", 0))
	perf.grip = 1.0 + 0.1 * float(mods.get("suspension", 0))
	perf.susp = 1.0 + 0.1 * float(mods.get("suspension", 0))
	perf.trans = 1.0 + 0.08 * float(mods.get("transmission", 0))
	perf.armor = float(def.get("armor", 1.0)) * (1.0 + 0.25 * float(mods.get("armor", 0)))
	perf.bp_tires = mods.get("bp_tires", false)
	perf.downforce = 0.0 + 0.6 * float(mods.get("spoiler", 1 if def.get("spoiler", false) else 0))
	max_health = 1000.0 * perf.armor
	health = minf(health, max_health)
