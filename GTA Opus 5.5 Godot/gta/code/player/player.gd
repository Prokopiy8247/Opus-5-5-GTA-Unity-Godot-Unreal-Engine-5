class_name Player
extends Actor
## Third-person player controller: on-foot locomotion, stealth, cover, traversal (vault/mantle/ladder/roll),
## swimming & diving, falling & parachute, combat (aim/fire/melee/takedown), vehicles (enter/jack/exit/drive-by).

const WALK := 1.9
const RUN := 4.6
const SPRINT := 7.2
const CROUCH := 1.7
const JUMP_V := 5.6
const SWIM := 2.3
const SWIM_FAST := 3.8

var state := "foot"          # foot, swim, vehicle, ladder, skydive, parachute, ragdoll, dead, busy
var crouching := false
var sprinting := false
var aiming := false
var aiming_in_vehicle := false
var stamina := 1.0
var breath := 1.0
var scuba := false
var has_parachute := false
var in_cover := false
var cover_normal := Vector3.ZERO
var cover_low := false
var cover_side := 1.0
var _yaw := 0.0
var _air_t := 0.0
var _fall_start_y := 0.0
var _max_fall_speed := 0.0
var _busy_t := 0.0
var _busy_kind := ""
var _enter_target: VehicleBase = null
var _enter_seat := 0
var _fire_hold := 0.0
var _combo := 0
var _step_t := 0.0
var _ladder: Dictionary = {}
var _ladder_y := 0.0
var _chute: Node3D
var _scuba_mesh: Node3D
var _death_t := 0.0
var _vault_from := Vector3.ZERO
var _vault_to := Vector3.ZERO
var _roll_dir := Vector3.ZERO
var _regen_t := 0.0
var _in_water_prev := false
var noise_radius := 0.0
var _blocking := false
var _breath_t := 0.0
var wanted_vehicle: VehicleBase = null


func _ready() -> void:
	_setup_body(0.32, 1.8, C.L_PLAYER)
	team = C.Team.PLAYER
	look_data = HumanoidRig.player_look()
	rig.build(look_data)
	weapons = WeaponUser.new(self, true)
	weapons.give("pistol", 60)
	weapons.give("knife", 0)
	weapons.select("pistol")
	weapons.changed.connect(func(_id): _refresh_weapon_model())
	_refresh_weapon_model()
	max_health = 200.0
	health = 200.0
	_build_parachute()
	Game.player = self


func _build_parachute() -> void:
	_chute = Node3D.new()
	_chute.name = "Parachute"
	var mb := MB.new()
	var cols := [Color(0.95, 0.35, 0.25), Color(0.98, 0.95, 0.9)]
	for i in 7:
		var a0 := -0.9 + i * 0.257
		var a1 := a0 + 0.257
		mb.use("c%d" % (i % 2)).col(Color.WHITE)
		var p0 := Vector3(sin(a0) * 4.2, 6.2 + cos(a0) * 1.2 - 1.2, 0)
		var p1 := Vector3(sin(a1) * 4.2, 6.2 + cos(a1) * 1.2 - 1.2, 0)
		mb.quad(p0 + Vector3(0, 0, -1.4), p1 + Vector3(0, 0, -1.4), p1 + Vector3(0, 0, 1.4), p0 + Vector3(0, 0, 1.4), Vector3.UP)
		mb.quad(p0 + Vector3(0, 0, -1.4), p0 + Vector3(0, 0, 1.4), p1 + Vector3(0, 0, 1.4), p1 + Vector3(0, 0, -1.4), Vector3.DOWN)
	mb.use("l").col(Color.WHITE)
	for s in [-1.0, 1.0]:
		mb.box_xf(Transform3D(Basis(Vector3.FORWARD, s * 0.45), Vector3(s * 1.6, 3.4, 0)), Vector3(0.02, 4.2, 0.02))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit({"c0": Mats.color(cols[0], 0.8), "c1": Mats.color(cols[1], 0.8), "l": Mats.color(Color(0.2, 0.2, 0.2))})
	_chute.add_child(mi)
	_chute.visible = false
	add_child(_chute)
	_scuba_mesh = MeshInstance3D.new()
	var sm := MB.new()
	sm.use("t").col(Color.WHITE)
	sm.cylinder(Vector3(0, -0.2, 0), 0.09, 0.5, 8)
	(_scuba_mesh as MeshInstance3D).mesh = sm.commit({"t": Mats.color(Color(0.95, 0.75, 0.1), 0.4)})
	_scuba_mesh.visible = false


func _physics_process(delta: float) -> void:
	if Game.paused:
		return
	# failsafe: anything that drops the player below the sea floor puts them back on a street
	if global_position.y < -40.0 and state not in ["vehicle", "dead"]:
		if ragdolled:
			_get_up()
		state = "foot"
		_max_fall_speed = 0.0
		velocity = Vector3.ZERO
		global_position = Game.main.find_free_spot(Vector3(global_position.x, C.LAND_Y, global_position.z))
		reset_physics_interpolation()
		Game.notify("Recovered from out-of-world fall", "warn")
	weapons.update(delta)
	_update_water()
	match state:
		"foot":
			_foot(delta)
		"swim":
			_swim(delta)
		"vehicle":
			_in_vehicle(delta)
		"ladder":
			_ladder_climb(delta)
		"skydive", "parachute":
			_sky(delta)
		"busy":
			_busy(delta)
		"ragdoll":
			_update_ragdoll(delta)
			if not ragdolled:
				state = "foot"
		"dead":
			_update_ragdoll(delta)
			_death_t += delta
	if state != "vehicle" and state != "dead":
		_vehicle_contacts(delta)
	_regen(delta)
	if rig and state != "vehicle":
		rig.update_pose(delta)
	elif rig:
		rig.update_pose(delta)
	_update_camera_mode()
	_update_flashlight()


# ------------------------------------------------------------------ input helpers

func _move_input() -> Vector2:
	if Game.ui_open > 0:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _cam_basis() -> Basis:
	return Basis(Vector3.UP, Game.cam.yaw)


func _pressed(a: String) -> bool:
	return Game.ui_open == 0 and Input.is_action_just_pressed(a)


func _held(a: String) -> bool:
	return Game.ui_open == 0 and Input.is_action_pressed(a)


# ------------------------------------------------------------------ on foot

func _foot(delta: float) -> void:
	var inp := _move_input()
	var cb := _cam_basis()
	var wish := (cb * Vector3(inp.x, 0, inp.y))
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()
	var d := weapons.def()
	var melee_w: bool = d.get("melee", false)
	aiming = _held("aim") and not in_cover or (in_cover and _held("aim"))
	if _pressed("crouch"):
		crouching = not crouching
		if crouching:
			Game.notify("Stealth mode", "info")
	sprinting = _held("sprint") and inp.length() > 0.1 and not aiming and stamina > 0.05 and not in_cover
	if sprinting:
		crouching = false
		stamina = maxf(stamina - delta / Game.skills.sprint_duration(), 0.0)
		Game.skills.add("stamina", delta * 0.04)
	var speed := RUN
	if crouching:
		speed = CROUCH
	elif sprinting:
		speed = SPRINT
	elif aiming:
		speed = WALK * 1.3
	if _blocking:
		speed = WALK * 0.6
	# cover handling
	if in_cover:
		_cover_move(delta, inp)
		return
	if _pressed("cover"):
		if _try_enter_cover():
			return
	var target_vel := wish * speed
	var accel := 14.0 if is_on_floor() else 3.0
	velocity.x = move_toward(velocity.x, target_vel.x, accel * delta * speed)
	velocity.z = move_toward(velocity.z, target_vel.z, accel * delta * speed)
	# facing
	if aiming or (_held("fire") and not melee_w and d.get("hold", 0) != 0):
		_yaw = U.damp_angle(_yaw, Game.cam.yaw + PI, 20.0, delta)
	elif wish.length() > 0.1:
		_yaw = U.damp_angle(_yaw, atan2(wish.x, wish.z), 12.0, delta)
	rig.rotation.y = _yaw + PI
	# jump / vault / mantle
	if _pressed("jump") and is_on_floor():
		if aiming and inp.length() > 0.2:
			_start_roll(wish.normalized())
			return
		if _blocking and inp.length() > 0.2:
			_start_roll(wish.normalized())
			return
		if not _try_vault():
			velocity.y = JUMP_V
			_air_t = 0.0
	# gravity & falling
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
		_air_t += delta
		_max_fall_speed = maxf(_max_fall_speed, -velocity.y)
		if _air_t > 0.15 and _fall_start_y < global_position.y:
			_fall_start_y = global_position.y
		if has_parachute and -velocity.y > 14.0 and (_pressed("jump") or _pressed("enter_vehicle")):
			_start_skydive()
			return
		if -velocity.y > 20.0 and _air_t > 1.4 and not has_parachute:
			pass
	else:
		if _max_fall_speed > 0.0:
			_land(_max_fall_speed)
		_max_fall_speed = 0.0
		_air_t = 0.0
		_fall_start_y = global_position.y
	move_and_slide()
	# water
	if in_water and water_depth > 1.1:
		_enter_swim()
		return
	# combat
	_combat(delta, d, melee_w)
	# interactions
	if _pressed("enter_vehicle"):
		_try_enter_vehicle()
	if _pressed("interact"):
		_interact()
	if _pressed("reload"):
		if weapons.start_reload():
			rig.play_action("reload")
	_weapon_switch_input()
	# footsteps / noise
	var hs := Vector2(velocity.x, velocity.z).length()
	_step_t -= delta * hs
	if is_on_floor() and _step_t <= 0.0 and hs > 0.5:
		_step_t = 1.6
		var nr := (3.0 if crouching else (22.0 if sprinting else 12.0)) * Game.skills.noise_mul()
		noise_radius = nr
		Game.emit_event(global_position, nr, "footstep", self)
		Audio.play_3d("footstep", global_position, -14.0 if crouching else -8.0, randf_range(0.85, 1.15), 25.0)
		if crouching:
			Game.skills.add("stealth", 0.08)
	# animation inputs
	rig.speed = hs
	rig.grounded = is_on_floor()
	rig.crouch = move_toward(rig.crouch, 1.0 if crouching else 0.0, delta * 5.0)
	rig.aim = 1.0 if (aiming or (_held("fire") and not melee_w)) else 0.0
	rig.aim_pitch = -Game.cam.pitch
	rig.hold = int(d.get("hold", 0))
	rig.mode = "normal" if is_on_floor() or _air_t < 0.6 else "fall"
	rig.lean = 0.0
	rig.look_yaw = 0.0
	rig.aim_yaw = 0.0


func _land(fall_speed: float) -> void:
	if fall_speed > 11.0:
		var dmg := pow(fall_speed - 10.0, 1.6) * 3.2
		if fall_speed > 23.0:
			dmg = 999.0
		if not Game.invulnerable:
			take_damage(dmg, null, global_position, Vector3(0, -2, 0), "fall")
		if fall_speed > 16.0 and not dead:
			knockdown(Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1)), 1.5)
			state = "ragdoll"
		Game.cam.add_trauma(clampf(fall_speed / 30.0, 0.0, 0.7))
	if fall_speed > 6.0:
		Audio.play_3d("impact_flesh", global_position, -6.0, 0.7, 30.0)


func _combat(delta: float, d: Dictionary, melee_w: bool) -> void:
	_blocking = melee_w and _held("aim") and not _held("fire")
	if Game.ui_open > 0:
		return
	if melee_w:
		if _held("fire"):
			_fire_hold += delta
		if Input.is_action_just_released("fire") and Game.ui_open == 0:
			var heavy := _fire_hold > 0.35
			_fire_hold = 0.0
			_melee(heavy)
		return
	_fire_hold = 0.0
	if d.get("throw", false):
		if _pressed("fire") and weapons.can_fire():
			var target := Game.cam.crosshair_point(60.0, [self])
			var origin := global_position + Vector3(0, 1.6, 0) + (-Game.cam.cam.global_basis.z) * 0.6
			rig.play_action("throw")
			if weapons.fire(origin, target + Vector3(0, 2.5, 0), 0.5, [self]):
				Audio.play_3d("swing", origin, -4.0)
		return
	var auto: bool = d.get("auto", false)
	var want := _held("fire") if auto else _pressed("fire")
	if want:
		var mx := muzzle_xform()
		var target2 := Game.cam.crosshair_point(float(d.get("range", 200.0)), [self])
		var acc := 1.0 if aiming else 2.2
		if crouching:
			acc *= 0.75
		if in_cover and not aiming:
			acc *= 3.0
		if sprinting:
			acc *= 1.8
		var landed := weapons.fire(mx.origin, target2, acc, [self])
		if landed:
			var sh := (weapons.def().get("recoil", 1.0) as float) * Game.skills.recoil_mul()
			Game.cam.pitch += deg_to_rad(sh * 0.35)
			Game.cam.yaw += deg_to_rad(randf_range(-sh, sh) * 0.12)
			Game.cam.add_trauma(minf(sh * 0.025, 0.2))
			VFX.muzzle_flash(mx, 1.4 if d.get("hold", 1) == 2 else 1.0)
	if weapons.mag() == 0 and not weapons.is_reloading() and weapons.reserve() > 0 and _held("fire"):
		if weapons.start_reload():
			rig.play_action("reload")


func _melee(heavy: bool) -> void:
	var fwd := -rig.global_basis.z
	# stealth takedown from behind
	if crouching:
		var victim := _takedown_target(fwd)
		if victim:
			rig.play_action("takedown")
			weapons.melee(global_position + Vector3(0, 1.1, 0), fwd, true, true)
			Game.emit_event(global_position, 4.0, "takedown", self)
			Game.skills.add("stealth", 1.5)
			return
	if aiming or heavy:
		pass
	var anim := "heavy" if heavy else ("punch" if _combo % 2 == 0 else "punch2")
	if weapons.current != "fists":
		anim = "swing"
	if not heavy and weapons.current == "fists" and _combo % 3 == 2:
		anim = "kick"
	_combo += 1
	rig.play_action(anim)
	weapons.melee(global_position + Vector3(0, 1.1, 0), fwd, heavy)


func _takedown_target(fwd: Vector3) -> Actor:
	for n in Game.npcs:
		var a := n as NPC
		if a == null or a.dead:
			continue
		var to := a.global_position - global_position
		if to.length() > 1.9:
			continue
		var npc_fwd := -a.global_basis.z
		if npc_fwd.dot(to.normalized()) > 0.3 and fwd.dot(to.normalized()) > 0.4 and not a.is_alert():
			return a
	return null


func _weapon_switch_input() -> void:
	if Game.ui_open > 0:
		return
	var owned := owned_weapons()
	if owned.size() <= 1:
		return
	var idx := owned.find(weapons.current)
	if Input.is_action_just_pressed("weapon_next"):
		weapons.select(owned[(idx + 1) % owned.size()])
	elif Input.is_action_just_pressed("weapon_prev"):
		weapons.select(owned[(idx - 1 + owned.size()) % owned.size()])
	for s in 8:
		if Input.is_action_just_pressed("slot_%d" % (s + 1)):
			var ids := []
			for id in owned:
				if WeaponDB.get_def(id).slot == s:
					ids.append(id)
			if ids.size() > 0:
				var cur := ids.find(weapons.current)
				weapons.select(ids[(cur + 1) % ids.size()])


func owned_weapons() -> Array:
	var out := []
	for id in WeaponDB.W:
		if weapons.has(id):
			out.append(id)
	return out


# ------------------------------------------------------------------ traversal

func _try_vault() -> bool:
	var fwd := U.dir_of_yaw(_yaw + PI)
	var base := global_position
	var knee := U.ray(base + Vector3(0, 0.5, 0), base + Vector3(0, 0.5, 0) + fwd * 1.1, C.L_WORLD | C.L_PROP | C.L_VEHICLE, [self])
	if knee.is_empty():
		return false
	# find top of obstacle
	var probe: Vector3 = knee.position + fwd * 0.35 + Vector3(0, 2.4, 0)
	var top := U.ray(probe, probe - Vector3(0, 2.4, 0), C.L_WORLD | C.L_PROP | C.L_VEHICLE, [self])
	if top.is_empty():
		return false
	var h: float = top.position.y - base.y
	if h < 0.35 or h > 2.1:
		return false
	# room on top?
	var clear := U.ray(top.position + Vector3(0, 0.3, 0), top.position + Vector3(0, 1.7, 0), C.L_WORLD, [self])
	if not clear.is_empty():
		return false
	_vault_from = global_position
	if h < 1.15:
		# vault over: land beyond if possible
		var beyond: Vector3 = knee.position + fwd * 1.3
		var ground := U.ray(beyond + Vector3(0, 1.5, 0), beyond - Vector3(0, 3.0, 0), C.L_WORLD | C.L_PROP, [self])
		_vault_to = ground.position if not ground.is_empty() and ground.position.y < top.position.y - 0.2 else top.position
	else:
		_vault_to = top.position + fwd * 0.3
	_begin_busy("vault", 0.5)
	rig.play_action("vault")
	return true


func _start_roll(dir: Vector3) -> void:
	_roll_dir = dir
	_begin_busy("roll", 0.55)
	rig.play_action("roll")


func _begin_busy(kind: String, t: float) -> void:
	state = "busy"
	_busy_kind = kind
	_busy_t = t
	velocity = Vector3.ZERO


func _busy(delta: float) -> void:
	_busy_t -= delta
	match _busy_kind:
		"vault":
			var k := 1.0 - clampf(_busy_t / 0.5, 0.0, 1.0)
			var p := _vault_from.lerp(_vault_to, k)
			p.y += sin(k * PI) * 0.6 + (_vault_to.y - _vault_from.y) * 0.0
			global_position = p
		"roll":
			velocity = _roll_dir * 6.0
			velocity.y -= GRAVITY * delta
			move_and_slide()
		"enter":
			if _enter_target == null or not is_instance_valid(_enter_target):
				state = "foot"
				return
			var door := _enter_target.door_position(_enter_seat)
			var to := door - global_position
			to.y = 0
			if to.length() > 0.15:
				velocity = to.normalized() * minf(to.length() / maxf(_busy_t, 0.05), 6.0)
				move_and_slide()
				_yaw = U.damp_angle(_yaw, atan2(to.x, to.z), 15.0, delta)
				rig.rotation.y = _yaw + PI
			rig.speed = 3.0
	if _busy_t <= 0.0:
		if _busy_kind == "enter":
			_finish_enter()
		else:
			state = "foot"
			if _busy_kind == "vault":
				global_position = _vault_to + Vector3(0, 0.05, 0)
			velocity = Vector3.ZERO


# ------------------------------------------------------------------ cover

func _try_enter_cover() -> bool:
	var fwd := -Game.cam.cam.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var best := {}
	for ang in [0.0, -0.5, 0.5, -1.0, 1.0]:
		var dir := fwd.rotated(Vector3.UP, ang)
		var hit := U.ray(global_position + Vector3(0, 0.6, 0), global_position + Vector3(0, 0.6, 0) + dir * 2.4, C.L_WORLD | C.L_VEHICLE | C.L_PROP, [self])
		if not hit.is_empty() and absf(hit.normal.y) < 0.4:
			best = hit
			break
	if best.is_empty():
		return false
	cover_normal = Vector3(best.normal.x, 0, best.normal.z).normalized()
	var high := U.ray(global_position + Vector3(0, 1.55, 0), global_position + Vector3(0, 1.55, 0) - cover_normal * 2.6, C.L_WORLD | C.L_VEHICLE | C.L_PROP, [self])
	cover_low = high.is_empty()
	var target_pos: Vector3 = best.position + cover_normal * 0.42
	target_pos.y = global_position.y
	global_position = target_pos
	in_cover = true
	crouching = cover_low
	cover_side = 1.0
	velocity = Vector3.ZERO
	Audio.play_3d("footstep", global_position, -4.0, 0.7)
	return true


func _cover_move(delta: float, inp: Vector2) -> void:
	var tangent := cover_normal.cross(Vector3.UP).normalized()   # moving +tangent = to the right when facing the wall
	var cam_right := _cam_basis() * Vector3.RIGHT
	var sign_t := signf(tangent.dot(cam_right))
	if sign_t == 0.0:
		sign_t = 1.0
	var move := inp.x * sign_t
	if _pressed("cover") or inp.y > 0.6 or _held("sprint"):
		in_cover = false
		crouching = false
		return
	if absf(inp.x) > 0.1:
		cover_side = signf(inp.x)
	var step := tangent * move * 2.2 * delta
	var probe := global_position + step - cover_normal * 0.1
	var still := U.ray(probe + Vector3(0, 0.6, 0), probe + Vector3(0, 0.6, 0) - cover_normal * 1.0, C.L_WORLD | C.L_VEHICLE | C.L_PROP, [self])
	if not still.is_empty():
		var n := Vector3(still.normal.x, 0, still.normal.z).normalized()
		if n.length() > 0.5:
			cover_normal = cover_normal.lerp(n, 0.2).normalized()
		global_position += step
	velocity = Vector3.ZERO
	velocity.y -= GRAVITY * delta
	move_and_slide()
	var face := atan2(cover_normal.x, cover_normal.z)
	aiming = _held("aim")
	if aiming:
		face = Game.cam.yaw + PI
		crouching = false if cover_low else crouching
	else:
		crouching = cover_low
	_yaw = U.damp_angle(_yaw, face, 14.0, delta)
	rig.rotation.y = _yaw + PI
	rig.speed = absf(move) * 2.0
	rig.crouch = move_toward(rig.crouch, 1.0 if crouching else 0.0, delta * 6.0)
	rig.aim = 1.0 if aiming or _held("fire") else 0.0
	rig.aim_pitch = -Game.cam.pitch
	rig.hold = int(weapons.def().get("hold", 0))
	rig.mode = "normal"
	rig.lean = cover_side * (0.6 if aiming and not cover_low else 0.0)
	var d := weapons.def()
	_combat(delta, d, d.get("melee", false))
	if _pressed("reload") and weapons.start_reload():
		rig.play_action("reload")
	_weapon_switch_input()


# ------------------------------------------------------------------ ladders

func _try_ladder() -> bool:
	if Game.world == null:
		return false
	for l in Game.world.ladders:
		var b: Vector3 = l.bottom
		if U.flat_dist(b, global_position) < 1.4 and absf(global_position.y - b.y) < 1.5:
			_ladder = l
			state = "ladder"
			_ladder_y = global_position.y
			global_position = Vector3(b.x, global_position.y, b.z)
			_yaw = atan2(-l.normal.x, -l.normal.z)
			rig.rotation.y = _yaw + PI
			return true
		var t: Vector3 = l.top
		if U.flat_dist(t, global_position) < 1.4 and absf(global_position.y - l.top_y) < 1.5:
			_ladder = l
			state = "ladder"
			_ladder_y = float(l.top_y) - 1.6
			global_position = Vector3(b.x, _ladder_y, b.z)
			_yaw = atan2(-l.normal.x, -l.normal.z)
			rig.rotation.y = _yaw + PI
			return true
	return false


func _ladder_climb(delta: float) -> void:
	var inp := _move_input()
	var v := -inp.y * 2.2
	_ladder_y += v * delta
	var bottom: Vector3 = _ladder.bottom
	global_position = Vector3(bottom.x, _ladder_y, bottom.z)
	velocity = Vector3.ZERO
	rig.mode = "ladder"
	rig.speed = absf(v)
	if _ladder_y >= float(_ladder.top_y) - 1.0:
		global_position = _ladder.top + Vector3(0, 0.1, 0)
		state = "foot"
		rig.mode = "normal"
	elif _ladder_y <= bottom.y - 0.05 and v < 0.0:
		state = "foot"
		rig.mode = "normal"
	elif _pressed("jump"):
		state = "foot"
		rig.mode = "normal"
		velocity = _ladder.normal * 3.0 + Vector3(0, 2.0, 0)


# ------------------------------------------------------------------ swimming

func _enter_swim() -> void:
	state = "swim"
	in_cover = false
	crouching = false
	if _max_fall_speed > 8.0:
		VFX.splash(global_position, 1.5)
	_max_fall_speed = 0.0
	_drop_weapon_model()


func _swim(delta: float) -> void:
	var inp := _move_input()
	var cb := Basis.from_euler(Vector3(Game.cam.pitch if _held("crouch") or global_position.y < -0.8 else 0.0, Game.cam.yaw, 0))
	var wish := cb * Vector3(inp.x, 0, inp.y)
	var fast := _held("sprint") and stamina > 0.05
	var spd := SWIM_FAST if fast else SWIM
	if fast:
		stamina = maxf(stamina - delta * 0.08, 0.0)
		Game.skills.add("stamina", delta * 0.03)
	var surface_y := C.SEA_LEVEL - 1.25
	var target := wish * spd
	if _held("crouch"):
		target.y = -2.0
	elif _held("jump"):
		target.y = 2.2
	elif global_position.y > surface_y - 0.4 and global_position.y < surface_y + 0.4:
		target.y = (surface_y - global_position.y) * 3.0
	elif global_position.y < surface_y:
		target.y = maxf(target.y, 0.35)   # gentle buoyancy
	velocity = velocity.lerp(target, 1.0 - exp(-3.0 * delta))
	if global_position.y > surface_y + 0.05 and velocity.y > 0:
		velocity.y = minf(velocity.y, (surface_y + 0.05 - global_position.y) * 5.0)
	move_and_slide()
	var flat := Vector3(velocity.x, 0, velocity.z)
	if flat.length() > 0.3:
		_yaw = U.damp_angle(_yaw, atan2(flat.x, flat.z), 6.0, delta)
	rig.rotation.y = _yaw + PI
	var head_under := global_position.y + 1.55 < C.SEA_LEVEL - 0.1
	rig.mode = "dive" if head_under else "swim"
	rig.speed = velocity.length()
	# breath
	if head_under and not Game.invulnerable:
		var bt := Game.skills.breath_time() * (8.0 if scuba else 1.0)
		breath = maxf(breath - delta / bt, 0.0)
		_breath_t += delta
		if _breath_t > 2.0:
			Game.skills.add("lung", 0.12)
			_breath_t = 0.0
		if breath <= 0.0:
			take_damage(12.0 * delta, null, global_position, Vector3.ZERO, "drown")
	else:
		breath = minf(breath + delta * 0.35, 1.0)
	Audio.set_underwater(Game.cam.cam.global_position.y < C.SEA_LEVEL)
	# leave water
	var gy := WorldMap.height(global_position.x, global_position.z)
	var ground_hit := U.ray(global_position + Vector3(0, 1.0, 0), global_position - Vector3(0, 0.6, 0), C.L_WORLD, [self])
	if (gy > C.SEA_LEVEL - 1.0 and global_position.y > gy - 0.3) or (not ground_hit.is_empty() and water_depth < 1.0):
		state = "foot"
		rig.mode = "normal"
		Audio.set_underwater(false)
		_refresh_weapon_model()
	if _pressed("enter_vehicle"):
		_try_enter_vehicle()


# ------------------------------------------------------------------ sky

func _start_skydive() -> void:
	state = "skydive"
	_drop_weapon_model()
	Game.notify("Press SPACE / F to open the parachute", "hint")


func _sky(delta: float) -> void:
	var inp := _move_input()
	var cb := _cam_basis()
	if state == "skydive":
		var wish := cb * Vector3(inp.x, 0, inp.y) * 9.0
		velocity.x = move_toward(velocity.x, wish.x, delta * 12.0)
		velocity.z = move_toward(velocity.z, wish.z, delta * 12.0)
		velocity.y = maxf(velocity.y - GRAVITY * delta, -45.0)
		rig.mode = "skydive"
		if _pressed("jump") or _pressed("enter_vehicle") or _pressed("fire"):
			state = "parachute"
			_chute.visible = true
			_chute.scale = Vector3(0.2, 0.2, 0.2)
			Audio.play_3d("swing", global_position, 4.0, 0.5)
			Game.notify("Steer: A/D  ·  W dive  ·  S / SHIFT flare", "hint")
	else:
		_chute.scale = _chute.scale.lerp(Vector3.ONE, 1.0 - exp(-6.0 * delta))
		var turn := -inp.x * 1.3
		_yaw += turn * delta
		var fwd := U.dir_of_yaw(_yaw + PI)
		var flare := _held("sprint") or inp.y > 0.5
		var glide := 9.0 + (-inp.y) * 4.0
		var sink := -5.0 + (2.8 if flare else 0.0) - maxf(-inp.y, 0.0) * 3.0
		velocity.x = move_toward(velocity.x, fwd.x * glide, delta * 6.0)
		velocity.z = move_toward(velocity.z, fwd.z * glide, delta * 6.0)
		velocity.y = move_toward(velocity.y, sink, delta * 12.0)
		rig.mode = "parachute"
		rig.steer = inp.x
		_chute.rotation = Vector3(0, 0, -inp.x * 0.3)
	if state == "skydive" and velocity.length() > 1.0:
		_yaw = U.damp_angle(_yaw, Game.cam.yaw + PI, 2.0, delta)
	rig.rotation.y = _yaw + PI
	move_and_slide()
	Game.cam.add_trauma(0.01)
	if is_on_floor() or in_water:
		var vs := -velocity.y
		_chute.visible = false
		has_parachute = false
		state = "foot"
		rig.mode = "normal"
		_refresh_weapon_model()
		if in_water:
			_enter_swim()
		elif vs > 7.5:
			take_damage(vs * 4.0, null, global_position, Vector3.ZERO, "fall")
			if not dead:
				knockdown(velocity * 0.3, 1.2)
				state = "ragdoll"
		_max_fall_speed = 0.0


# ------------------------------------------------------------------ vehicles

func nearest_vehicle(radius := 4.5) -> VehicleBase:
	var best: VehicleBase = null
	var bd := radius
	for v in Game.vehicles:
		var veh := v as VehicleBase
		if veh == null or veh.destroyed:
			continue
		var d := veh.global_position.distance_to(global_position) - maxf(veh.half_extents.x, veh.half_extents.z) * 0.5
		if d < bd:
			bd = d
			best = veh
	return best


func _try_enter_vehicle() -> void:
	var v := nearest_vehicle()
	if v == null:
		return
	var s := v.best_seat_for(global_position, true)
	var taxi_svc: TaxiService = Game.main.taxi if Game.main else null
	if taxi_svc and taxi_svc.taxi == v and taxi_svc.state in ["waiting", "coming"]:
		s = taxi_svc.passenger_seat()
	if s < 0:
		return
	_enter_target = v
	_enter_seat = s
	in_cover = false
	crouching = false
	aiming = false
	var occ := v.seat_occupant(s)
	if occ != null and occ != self:
		rig.play_action("jack")
		_begin_busy("enter", 0.9)
	else:
		rig.play_action("enter")
		_begin_busy("enter", 0.45 if v.kind in ["bike", "bicycle"] else 0.6)


func _finish_enter() -> void:
	var v := _enter_target
	_enter_target = null
	if v == null or not is_instance_valid(v) or v.destroyed:
		state = "foot"
		return
	var occ := v.seat_occupant(_enter_seat)
	if occ != null and occ != self:
		# carjack
		v.eject(occ, true)
		if occ is NPC:
			(occ as NPC).on_carjacked(self)
		Game.report_crime("carjack" if v.faction != "police" else "steal_police", v.global_position, occ)
		Audio.play_3d("punch", v.global_position, 0.0)
	elif v.faction == "police":
		Game.report_crime("steal_police", v.global_position)
	v.enter(self, _enter_seat)
	vehicle = v
	seat = _enter_seat
	state = "vehicle"
	_max_fall_speed = 0.0
	_air_t = 0.0
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	_drop_weapon_model()
	Game.cam.exclude = [v.get_rid(), get_rid()]
	wanted_vehicle = v
	if seat == 0 and not v.engine_on:
		v.engine_on = true
	Audio.play_3d("impact_metal", v.global_position, -10.0, 0.6)


func exit_vehicle(bail := false) -> void:
	var v := vehicle
	if v == null:
		return
	var spd := v.linear_velocity.length()
	var door := v.door_position(seat)
	v.remove_occupant(self)
	vehicle = null
	seat = -1
	state = "foot"
	_restore_collision()
	collision_layer = C.L_PLAYER
	var hit := U.ray(door + Vector3(0, 1.5, 0), door - Vector3(0, 3.0, 0), C.L_WORLD, [self, v])
	global_position = (hit.position if not hit.is_empty() else door) + Vector3(0, 0.05, 0)
	if v.kind == "boat" and WorldMap.is_water(global_position.x, global_position.z):
		global_position = door
	reset_physics_interpolation()
	velocity = v.linear_velocity * (0.8 if bail else 0.0)
	rig.mode = "normal"
	Game.cam.exclude = [get_rid()]
	_refresh_weapon_model()
	if v.kind in ["heli", "plane"] and global_position.y > WorldMap.height(global_position.x, global_position.z) + 25.0:
		if not has_parachute:
			Game.notify("No parachute! Find one at the Crown Hill lookout or the airfield.", "warn")
		_air_t = 0.5
	elif bail and spd > 9.0:
		knockdown(v.linear_velocity * 0.4 + Vector3(0, 2, 0), 1.6)
		state = "ragdoll"
		take_damage(spd * 1.2, null, global_position, Vector3.ZERO, "fall")


func _in_vehicle(delta: float) -> void:
	var v := vehicle
	if v == null or not is_instance_valid(v):
		state = "foot"
		_restore_collision()
		return
	global_position = v.seat_global(seat).origin
	if v.destroyed or (v.kind != "boat" and v.submerged()):
		exit_vehicle(true)
		return
	if seat == 0:
		v.set_controls(_vehicle_controls())
		if v.kind in ["heli", "plane"]:
			Game.skills.add("flying", delta * 0.02)
		elif v.linear_velocity.length() > 15.0:
			Game.skills.add("driving", delta * 0.02)
	if _pressed("enter_vehicle"):
		exit_vehicle(v.linear_velocity.length() > 8.0 and v.kind not in ["heli", "plane", "boat"])
		return
	if _pressed("horn"):
		v.horn(true)
	if Input.is_action_just_released("horn"):
		v.horn(false)
	if _pressed("headlights"):
		v.toggle_lights()
	if _pressed("siren"):
		v.toggle_siren()
	if _pressed("radio_next"):
		Game.radio_station = (Game.radio_station + 1) % Audio.STATIONS.size()
		v.set_radio(Game.radio_station)
	if _pressed("radio_prev"):
		Game.radio_station = (Game.radio_station - 1 + Audio.STATIONS.size()) % Audio.STATIONS.size()
		v.set_radio(Game.radio_station)
	Game.cam.look_back = _held("look_back")
	# drive-by
	var d := weapons.def()
	aiming_in_vehicle = _held("aim") and d.get("drive_by", false) and v.kind not in ["plane"]
	rig.aim = 1.0 if aiming_in_vehicle else 0.0
	rig.hold = 1
	rig.aim_pitch = -Game.cam.pitch
	if aiming_in_vehicle:
		if weapon_model_id != weapons.current:
			_refresh_weapon_model()
		var cam_f := -Game.cam.cam.global_basis.z
		var local_f := v.global_basis.inverse() * cam_f
		var ang := atan2(-local_f.x, -local_f.z)
		rig.rotation.y = ang * 0.6
		rig.aim_yaw = ang * 0.4
		if (_held("fire") if d.get("auto", false) else _pressed("fire")):
			var mx := muzzle_xform()
			var target := Game.cam.crosshair_point(150.0, [self, v])
			if d.get("throw", false):
				weapons.fire(mx.origin, target + Vector3(0, 2.0, 0), 1.0, [self, v])
			elif weapons.fire(mx.origin, target, 2.0, [self, v]):
				VFX.muzzle_flash(mx, 1.0)
				Game.cam.add_trauma(0.06)
		if _pressed("reload"):
			weapons.start_reload()
	else:
		if is_instance_valid(weapon_model):
			_drop_weapon_model()
		rig.rotation.y = 0.0
		rig.aim_yaw = 0.0
	_weapon_switch_input_vehicle()


func _weapon_switch_input_vehicle() -> void:
	if not (Input.is_action_just_pressed("weapon_next") or Input.is_action_just_pressed("weapon_prev")):
		return
	var ids := []
	for id in owned_weapons():
		if WeaponDB.get_def(id).get("drive_by", false):
			ids.append(id)
	if ids.is_empty():
		return
	var i := ids.find(weapons.current)
	weapons.select(ids[(i + 1) % ids.size()])
	_drop_weapon_model()


func _vehicle_controls() -> Dictionary:
	var c := {}
	if Game.ui_open > 0:
		return {"throttle": 0.0, "steer": 0.0, "brake": 1.0, "handbrake": 0.0, "up": 0.0, "yaw": 0.0, "roll": 0.0, "pitch": 0.0}
	c["throttle"] = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	c["steer"] = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	c["handbrake"] = 1.0 if Input.is_action_pressed("jump") else 0.0
	c["up"] = (1.0 if Input.is_action_pressed("jump") else 0.0) - (1.0 if Input.is_action_pressed("crouch") else 0.0)
	c["boost"] = 1.0 if Input.is_action_pressed("sprint") else 0.0
	c["roll"] = (1.0 if Input.is_action_pressed("roll_right") else 0.0) - (1.0 if Input.is_action_pressed("roll_left") else 0.0)
	c["pitch"] = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	c["yaw"] = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	c["throttle_up"] = 1.0 if Input.is_action_pressed("sprint") else 0.0
	c["throttle_down"] = 1.0 if Input.is_action_pressed("crouch") else 0.0
	return c


# ------------------------------------------------------------------ interaction

func _interact() -> void:
	if _try_ladder():
		return
	var p := Game.poi_near(global_position, 3.0)
	if p.is_empty():
		return
	if Game.hud and Game.hud.has_method("open_poi"):
		Game.hud.open_poi(p)


# ------------------------------------------------------------------ damage / death

func _on_damaged(dmg: float, source: Node, _pos: Vector3, _impulse: Vector3, kind: String) -> void:
	_regen_t = 0.0   # health regeneration waits 6 s after the last hit
	if Game.invulnerable:
		health = max_health
		return
	Game.cam.add_trauma(clampf(dmg / 60.0, 0.05, 0.5))
	if Game.hud and Game.hud.has_method("flash_damage"):
		Game.hud.flash_damage(dmg)
	if source is NPC and (source as NPC).team == C.Team.POLICE:
		pass


## Every ragdoll entry (vehicle hits, explosions, falls, melee) must also switch the state machine,
## otherwise the collision-less capsule would keep running the on-foot logic.
func go_ragdoll(impulse: Vector3, duration: float, hit_joint := "chest") -> void:
	if vehicle != null:
		return
	super.go_ragdoll(impulse, duration, hit_joint)
	if ragdolled and not dead:
		state = "ragdoll"
		in_cover = false


func take_damage(amount: float, source: Node = null, pos := Vector3.ZERO, impulse := Vector3.ZERO, kind := "bullet") -> void:
	if Game.invulnerable:
		return
	amount *= Game.skills.damage_resist()
	if vehicle != null and kind in ["bullet", "headshot"]:
		amount *= 0.45
	super.take_damage(amount, source, pos, impulse, kind)
	if ragdolled and not dead and state != "ragdoll":
		state = "ragdoll"


func _on_died(_source: Node, kind: String) -> void:
	state = "dead"
	_death_t = 0.0
	in_cover = false
	Game.cam.mode = "death"
	Game.player_died.emit()
	if Game.hud and Game.hud.has_method("show_big_message"):
		Game.hud.show_big_message("FLATLINED", "St. Vesper Medical will patch you up", Color(0.9, 0.25, 0.25))
	get_tree().create_timer(4.5).timeout.connect(func(): respawn("hospital"))


func arrest() -> void:
	if dead or state == "dead":
		return
	state = "dead"
	velocity = Vector3.ZERO
	rig.mode = "handsup"
	Game.player_busted.emit()
	if Game.hud and Game.hud.has_method("show_big_message"):
		Game.hud.show_big_message("ARRESTED", "Bail and confiscation applied", Color(0.35, 0.55, 1.0))
	var fine := mini(Game.money, 500 + Game.money / 10)
	Game.add_money(-fine)
	for id in weapons.inv:
		weapons.inv[id].reserve = int(weapons.inv[id].reserve * 0.5)
	get_tree().create_timer(4.0).timeout.connect(func(): respawn("police"))


func respawn(where: String) -> void:
	cleanup_ragdoll()
	dead = false
	ragdolled = false
	rig.ragdoll_root = null
	rig.ragdoll_bodies = {}
	rig.visible = true
	rig.build(look_data)
	health = max_health
	armor = 0.0
	breath = 1.0
	stamina = 1.0
	_chute.visible = false
	if vehicle:
		_force_exit_vehicle()
	state = "foot"
	_restore_collision()
	collision_layer = C.L_PLAYER
	var xf := WorldMap.respawn_point(where)
	global_position = xf.origin
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	_yaw = xf.basis.get_euler().y + PI
	Game.cam.mode = "foot"
	Game.cam.yaw = PI
	if Game.wanted:
		Game.wanted.clear()
	weapon_model_id = ""
	_refresh_weapon_model()
	if Game.hud and Game.hud.has_method("hide_big_message"):
		Game.hud.hide_big_message()
	if where == "hospital" and Game.money > 0:
		var bill := mini(Game.money, 300)
		Game.add_money(-bill)
		Game.notify("Hospital bill: " + U.money_str(bill), "warn")


func _restore_collision() -> void:
	collision_layer = C.L_PLAYER
	collision_mask = C.MASK_CHAR_MOVE


func _regen(delta: float) -> void:
	if not sprinting and state != "swim":
		stamina = minf(stamina + delta * 0.18, 1.0)
	if state != "swim" and breath < 1.0:
		breath = minf(breath + delta * 0.5, 1.0)
	if dead:
		return
	_regen_t += delta
	if health < max_health * 0.5 and _regen_t > 6.0:
		health = minf(health + delta * 2.0, max_health * 0.5)


func _update_camera_mode() -> void:
	if Game.cam == null or state == "dead":
		return
	if state == "vehicle" and vehicle:
		Game.cam.target = vehicle
		Game.cam.mode = "air" if vehicle.kind in ["heli", "plane"] else ("boat" if vehicle.kind == "boat" else "vehicle")
		Game.cam.first_person_node = rig.j.get("head")
		Game.cam.scope_fov = 0.0
	else:
		Game.cam.target = self
		var d := weapons.def()
		var scope := WeaponDB.stat(weapons.current, "scope_fov", weapons.mods())
		Game.cam.mode = "aim" if aiming and state == "foot" else "foot"
		Game.cam.scope_fov = scope if (aiming and scope > 0.0) else 0.0
		Game.cam.first_person_node = rig.j.get("head")
		if d.is_empty():
			pass
	rig.set_head_visible(not Game.cam.is_first_person())


func _update_flashlight() -> void:
	if not is_instance_valid(weapon_model):
		return
	var fl := weapon_model.get_node_or_null("Flashlight") as SpotLight3D
	if fl:
		fl.light_energy = 3.0 if (aiming or aiming_in_vehicle) else 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_toggle") and Game.ui_open == 0:
		Game.cam.cycle_view()


func set_scuba(v: bool) -> void:
	scuba = v
	if v and _scuba_mesh.get_parent() == null and rig.back_socket:
		rig.back_socket.add_child(_scuba_mesh)
	_scuba_mesh.visible = v


func give_parachute() -> void:
	has_parachute = true
	Game.notify("Parachute equipped", "good")
