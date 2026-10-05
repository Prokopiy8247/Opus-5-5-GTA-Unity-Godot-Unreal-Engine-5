class_name NPC
extends Actor
## Pedestrian / police / tactical / gang NPC brain with perception (FOV + LOS + noise events),
## witness reporting, panic & flee, cower, hands-up, fight-back, police pursuit/combat/cover/arrest.

var kind := "civilian"
var brain := "wander"
var personality := "normal"
var alert := 0.0
var fear := 0.0
var threat: Node3D = null
var target_pos := Vector3.ZERO
var cur_node := -1
var next_node := -1
var prev_node := -1
var walk_speed := 1.35
var run_speed := 4.9
var think_t := 0.0
var state_t := 0.0
var call_t := 0.0
var report_t := 0.0            # seconds left before this witness phones the crime in (0 = none)
var report_kind := ""
var crime_pos := Vector3.ZERO
var crime_kind := ""
var home_vehicle: VehicleBase = null
var cover_pos := Vector3.ZERO
var has_cover := false
var strafe_dir := 1.0
var burst_left := 0
var cash := 0
var lod := 0
var _evt_seen := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _yaw := 0.0
var _anim_skip := 0
var sees_player := false
var _los_t := 0.0
var _wait_cross := false
var idle_pose := ""
var manager: Node = null


func setup(k: String, rng: RandomNumberGenerator, appearance := {}) -> void:
	kind = k
	_setup_body(0.3, 1.78, C.L_NPC)
	look_data = appearance if not appearance.is_empty() else HumanoidRig.random_look(rng, k)
	rig.build(look_data)
	weapons = WeaponUser.new(self, false)
	weapons.infinite_ammo = true
	personality = "brave" if rng.randf() < 0.15 else ("coward" if rng.randf() < 0.3 else "normal")
	walk_speed = rng.randf_range(1.15, 1.55)
	cash = rng.randi_range(5, 60)
	match k:
		"police":
			team = C.Team.POLICE
			max_health = 120.0
			weapons.give(["pistol", "pistol", "shotgun", "smg"][rng.randi() % 4], 999)
			personality = "brave"
			run_speed = 5.4
		"swat":
			team = C.Team.POLICE
			max_health = 160.0
			armor = 100.0
			weapons.give(["rifle", "carbine", "smg"][rng.randi() % 3], 999)
			personality = "brave"
			run_speed = 5.6
		"gang":
			team = C.Team.GANG
			max_health = 110.0
			weapons.give(["pistol", "smg", "bat"][rng.randi() % 3], 999)
			personality = "brave"
		"medic":
			team = C.Team.CIVILIAN
		_:
			team = C.Team.CIVILIAN
			if personality == "brave" and rng.randf() < 0.4:
				weapons.give("pistol", 30)
	health = max_health
	if weapons.inv.size() > 1:
		for id in weapons.inv:
			if id != "fists":
				weapons.select(id)
				break
	if kind in ["civilian", "medic"]:
		weapons.select("fists")
	_yaw = rng.randf() * TAU
	Game.register_npc(self)


func _exit_tree() -> void:
	Game.unregister_npc(self)


## Independent witness-report timer (survives panic/flee/cower state changes).
func _tick_report(delta: float) -> void:
	if report_t <= 0.0:
		return
	report_t -= delta
	if report_t > 0.0:
		return
	report_t = 0.0
	if Game.wanted:
		Game.wanted.witness_report(report_kind, crime_pos, self)
	if brain == "phone":
		_set_brain("flee")


func is_alert() -> bool:
	return alert > 0.5 or brain in ["flee", "fight", "chase", "cower", "attack", "search", "handsup", "investigate"]


func is_hostile_to_player() -> bool:
	if kind in ["police", "swat"]:
		return Game.wanted != null and Game.wanted.level > 0
	return brain in ["fight", "attack"]


func head_y() -> float:
	return 1.48 * float(look_data.get("height", 1.0))


# ------------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	if Game.paused:
		return
	if ragdolled:
		_update_ragdoll(delta)
		return
	if dead:
		return
	if vehicle != null:
		global_position = vehicle.seat_global(seat).origin
		_anim(delta)
		if vehicle.destroyed:
			_force_exit_vehicle()
			_restore_collision()
		return
	weapons.update(delta)
	_tick_report(delta)
	var p := Game.player
	var dpl := global_position.distance_to(p.global_position) if p else 999.0
	lod = 0 if dpl < 55.0 else (1 if dpl < 110.0 else 2)
	think_t -= delta
	state_t += delta
	if think_t <= 0.0:
		think_t = [0.18, 0.5, 1.2][lod] + randf() * 0.05
		_perceive()
		_think()
	_act(delta)
	if lod < 2:
		_vehicle_contacts(delta)
	_anim_skip += 1
	if lod == 0 or _anim_skip % 3 == 0:
		_anim(delta * (1.0 if lod == 0 else 3.0))


# ------------------------------------------------------------------ perception

func _perceive() -> void:
	var p := Game.player
	if p == null or p.dead:
		sees_player = false
		return
	# events (gunshots, explosions, fights, screams, crashes, horns)
	for e in Game.events:
		if e.time <= _evt_seen:
			continue
		var d := global_position.distance_to(e.pos)
		if d > e.radius:
			continue
		_on_event(e, d)
	if Game.events.size() > 0:
		_evt_seen = Game.events[Game.events.size() - 1].time
	# vision
	var to_p := p.global_position - global_position
	var dist := to_p.length()
	var view := 34.0 * (0.55 if Game.night_factor > 0.5 else 1.0)
	if p.crouching:
		view *= 0.6
	var fwd := -global_basis.z
	var in_fov := fwd.dot(to_p.normalized()) > 0.35 or dist < 4.0
	sees_player = false
	if dist < view and (in_fov or alert > 0.4):
		var hit := U.ray(global_position + Vector3(0, 1.6, 0), p.global_position + Vector3(0, 1.4, 0), C.MASK_SIGHT, [self, p])
		sees_player = hit.is_empty()
	# officers hunting a suspect notice one right next to them even when the eye ray is blocked (car roof, corner)
	if not sees_player and kind in ["police", "swat"] and Game.wanted and Game.wanted.level > 0 and dist < 5.0:
		sees_player = true
	if sees_player:
		alert = minf(alert + (0.25 if not p.crouching else 0.12), 1.0)
		# threatening behaviour visible?
		var armed: bool = p.weapons.current != "fists" and not p.weapons.def().get("melee", false)
		if p.aiming and armed and dist < 25.0:
			var aim_dir := -Game.cam.cam.global_basis.z
			var to_me := (global_position + Vector3(0, 1.2, 0) - Game.cam.cam.global_position).normalized()
			if aim_dir.dot(to_me) > 0.97:
				_on_aimed_at(p, dist)
	else:
		alert = maxf(alert - 0.04, 0.0)
	if kind in ["police", "swat"] and sees_player and Game.wanted:
		Game.wanted.police_sees(self, p.global_position)


func _on_event(e: Dictionary, d: float) -> void:
	# the emitter may have been freed since the event was queued: never assign a freed object to a typed var
	var raw = e.get("source")
	var src: Node = raw if is_instance_valid(raw) else null
	match e.kind:
		"footstep":
			# heard steps: calm NPCs grow wary (sprinting carries ~22 m, walking 12 m, crouch-walking 3 m,
			# all scaled by the stealth skill); alert above 0.4 lets them notice the player outside their FOV
			if src == Game.player and not is_alert() and float(e.radius) > 0.0:
				alert = minf(alert + 0.12 * (1.0 - d / float(e.radius)), 1.0)
			return
		"gunshot", "explosion":
			if kind in ["police", "swat"]:
				if src == Game.player and brain in ["wander", "idle", "patrol"]:
					crime_pos = e.pos
					_set_brain("investigate")
				return
			if kind == "gang":
				if src == Game.player and d < 30.0:
					threat = Game.player
					_set_brain("attack")
				return
			fear = 1.0
			threat = src as Node3D if src != null else null
			crime_pos = e.pos
			if d < 8.0 and randf() < 0.35:
				_set_brain("cower")
			else:
				_set_brain("flee")
			if randf() < 0.3:
				Audio.play_3d("scream", global_position + Vector3(0, 1.6, 0), -4.0, randf_range(0.85, 1.25), 60.0)
		"fight", "crash", "takedown":
			if kind in ["civilian"] and d < 18.0 and brain == "wander":
				fear = 0.6
				threat = src as Node3D
				crime_pos = e.pos
				_set_brain("flee")
		"fire":
			if kind == "civilian" and d < 20.0 and brain == "wander":
				threat = src as Node3D
				crime_pos = e.pos
				_set_brain("flee")
		"horn":
			if d < 6.0 and brain == "wander":
				alert = 0.3


func _on_aimed_at(p: Player, dist: float) -> void:
	match kind:
		"civilian", "medic", "shop":
			if personality == "brave" and weapons.has("pistol"):
				weapons.select("pistol")
				threat = p
				_set_brain("attack")
			elif dist < 7.0 and brain != "handsup":
				_set_brain("handsup")
				Game.report_crime("brandish", global_position, self)
			elif brain not in ["flee", "handsup"]:
				threat = p
				_set_brain("flee")
		"gang":
			threat = p
			_set_brain("attack")


## Called by the wanted system when a crime happens in view.
func witness(kind_s: String, pos: Vector3) -> bool:
	if dead or kind not in ["civilian", "medic", "shop"]:
		return false
	# A witness keeps dialling even if gunfire makes them flee first: the report timer is
	# deliberately independent of the brain state, otherwise panic would silently cancel it.
	if report_t > 0.0:
		return false
	crime_kind = kind_s
	crime_pos = pos
	report_kind = kind_s
	report_t = randf_range(3.5, 6.0)
	call_t = report_t
	_set_brain("phone")
	return true


func on_carjacked(by: Player) -> void:
	threat = by
	if personality == "brave" and kind == "civilian":
		get_tree().create_timer(1.6).timeout.connect(func():
			if is_instance_valid(self) and not dead:
				_set_brain("attack"))
	else:
		get_tree().create_timer(1.6).timeout.connect(func():
			if is_instance_valid(self) and not dead:
				_set_brain("flee"))


func _set_brain(b: String) -> void:
	if brain == b:
		return
	brain = b
	state_t = 0.0
	has_cover = false
	if b in ["flee", "cower", "handsup", "phone"] and weapons.current != "fists" and kind == "civilian":
		weapons.select("fists")
		_drop_weapon_model()
	if b in ["attack", "chase", "fight"] and weapons.current != "fists":
		_refresh_weapon_model()


# ------------------------------------------------------------------ decisions

func _think() -> void:
	var p := Game.player
	match brain:
		"wander":
			if kind in ["police", "swat"] and Game.wanted and Game.wanted.level > 0:
				_set_brain("chase")
			elif kind == "gang" and sees_player and p and global_position.distance_to(p.global_position) < 4.0 and p.weapons.current != "fists" and alert > 0.8:
				threat = p
				_set_brain("attack")
		"idle":
			if state_t > randf_range(2.0, 6.0):
				_set_brain("wander")
		"flee":
			if state_t > 12.0 and (threat == null or global_position.distance_to(threat.global_position) > 45.0):
				fear = 0.0
				_set_brain("wander")
				cur_node = -1
		"cower":
			if state_t > 7.0:
				_set_brain("flee")
		"handsup":
			if state_t > 6.0 or (p and global_position.distance_to(p.global_position) > 14.0):
				_set_brain("flee")
		"phone":
			# the actual call is driven by _tick_report(); stay on the phone while dialling
			if report_t <= 0.0:
				_set_brain("flee")
		"investigate":
			if Game.wanted and Game.wanted.level > 0:
				_set_brain("chase")
			elif state_t > 10.0:
				_set_brain("wander")
		"chase":
			if Game.wanted == null or Game.wanted.level == 0:
				_set_brain("wander" if home_vehicle == null else "return")
			elif p and p.vehicle != null and home_vehicle and is_instance_valid(home_vehicle) and global_position.distance_to(p.global_position) > 30.0 and home_vehicle.driver == null:
				_set_brain("return")
			elif _should_shoot():
				_set_brain("attack")
		"attack":
			if kind in ["police", "swat"] and (Game.wanted == null or Game.wanted.level == 0):
				_set_brain("wander")
			elif not _should_shoot() and kind in ["police", "swat"]:
				_set_brain("chase")
			elif threat and is_instance_valid(threat) and threat is Actor and (threat as Actor).dead:
				_set_brain("wander")
		"return":
			if home_vehicle == null or not is_instance_valid(home_vehicle) or home_vehicle.destroyed:
				_set_brain("chase")
			elif Game.wanted and Game.wanted.level == 0 and state_t > 25.0:
				queue_free()


func _should_shoot() -> bool:
	var p := Game.player
	if p == null or p.dead:
		return false
	if kind in ["police", "swat"]:
		var lvl: int = Game.wanted.level if Game.wanted else 0
		if lvl == 0:
			return false
		var armed: bool = p.weapons.current != "fists" and not p.weapons.def().get("melee", false)
		var dist := global_position.distance_to(p.global_position)
		if lvl >= 2 or armed or p.vehicle != null:
			return dist < 45.0 and sees_player
		return false
	return threat != null


# ------------------------------------------------------------------ actions

func _act(delta: float) -> void:
	var p := Game.player
	var move := Vector3.ZERO
	var speed := 0.0
	var face_target := Vector3.ZERO
	idle_pose = ""
	match brain:
		"wander":
			move = _wander_dir()
			speed = walk_speed if not _wait_cross else 0.0
		"idle", "phone":
			speed = 0.0
			if brain == "phone":
				idle_pose = "phone"
				if crime_pos != Vector3.ZERO:
					face_target = crime_pos
		"flee":
			move = _flee_dir()
			speed = run_speed * (1.1 if personality == "coward" else 1.0)
		"cower":
			idle_pose = "cower"
		"handsup":
			idle_pose = "handsup"
			if p:
				face_target = p.global_position
		"investigate":
			var to := crime_pos - global_position
			to.y = 0
			if to.length() > 3.0:
				move = to.normalized()
				speed = walk_speed * 1.6
		"chase", "return":
			var tgt := Vector3.ZERO
			if brain == "return" and home_vehicle and is_instance_valid(home_vehicle):
				tgt = home_vehicle.door_position(0)
				if global_position.distance_to(tgt) < 2.0:
					_enter_home_vehicle()
					return
			elif p:
				tgt = p.global_position if sees_player or not Game.wanted else Game.wanted.last_known
			var to2 := tgt - global_position
			to2.y = 0
			var arrest_range := 1.6
			if to2.length() > arrest_range:
				move = to2.normalized()
				speed = run_speed
			if p and brain == "chase":
				face_target = p.global_position
				if global_position.distance_to(p.global_position) < 2.4 and Game.wanted:
					Game.wanted.arrest_attempt(self)
				# hold weapon ready
				if weapons.current != "fists":
					_refresh_weapon_model()
		"attack":
			_attack(delta)
			return
	_steer_move(move, speed, delta, face_target)


func _attack(delta: float) -> void:
	var t: Node3D = threat if threat and is_instance_valid(threat) else Game.player
	if t == null:
		_set_brain("wander")
		return
	var tp := t.global_position
	if t is Player and (t as Player).vehicle:
		tp = (t as Player).vehicle.global_position
	var to := tp - global_position
	to.y = 0
	var dist := to.length()
	var d := weapons.def()
	var melee_w: bool = d.get("melee", false)
	var move := Vector3.ZERO
	var speed := 0.0
	if melee_w:
		if dist > 1.4:
			move = to.normalized()
			speed = run_speed
		else:
			weapons.melee(global_position + Vector3(0, 1.1, 0), to.normalized(), randf() < 0.3)
			rig.play_action("punch" if randf() < 0.5 else "punch2")
	else:
		# keep distance, use cover, strafe
		var ideal := 12.0 if kind != "swat" else 16.0
		if not has_cover and state_t > 0.5 and randf() < 0.05:
			_find_cover(tp)
		if has_cover:
			var tc := cover_pos - global_position
			tc.y = 0
			if tc.length() > 0.6:
				move = tc.normalized()
				speed = run_speed
		else:
			if dist > ideal + 6.0:
				move = to.normalized()
				speed = run_speed
			elif dist < ideal - 5.0:
				move = -to.normalized()
				speed = walk_speed * 1.5
			else:
				if fmod(state_t, 3.0) < delta:
					strafe_dir = -strafe_dir
				move = to.normalized().cross(Vector3.UP) * strafe_dir
				speed = walk_speed * 1.3
		if weapons.can_fire() and sees_player_or_target(t) and dist < float(d.get("range", 60.0)):
			if burst_left <= 0:
				burst_left = randi_range(2, 5) if d.get("auto", false) else randi_range(1, 2)
				weapons.cooldown = randf_range(0.4, 1.1)
			else:
				var aim := tp + Vector3(0, 1.1, 0)
				var acc := clampf(dist / 12.0, 1.0, 3.5) * (2.5 if kind == "civilian" else 1.6)
				if t is Player and (t as Player).sprinting:
					acc *= 1.5
				var mx := muzzle_xform()
				if weapons.fire(mx.origin, aim, acc, [self]):
					VFX.muzzle_flash(mx, 0.9)
					burst_left -= 1
		if weapons.mag() == 0:
			weapons.start_reload()
	_steer_move(move, speed, delta, tp)


func sees_player_or_target(t: Node3D) -> bool:
	if t == Game.player:
		return sees_player
	var hit := U.ray(global_position + Vector3(0, 1.6, 0), t.global_position + Vector3(0, 1.2, 0), C.MASK_SIGHT, [self, t])
	return hit.is_empty()


func _find_cover(threat_pos: Vector3) -> void:
	for i in 8:
		var a := randf() * TAU
		var cand := global_position + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 9.0)
		var hit := U.ray(cand + Vector3(0, 1.0, 0), threat_pos + Vector3(0, 1.0, 0), C.MASK_SIGHT, [self])
		if not hit.is_empty() and (hit.position as Vector3).distance_to(cand) < 2.0:
			var ground := U.ray(cand + Vector3(0, 2, 0), cand - Vector3(0, 3, 0), C.L_WORLD)
			if not ground.is_empty():
				cover_pos = ground.position
				has_cover = true
				return


func _enter_home_vehicle() -> void:
	if home_vehicle == null or not is_instance_valid(home_vehicle):
		return
	var s := 0 if home_vehicle.driver == null else home_vehicle.free_seat()
	if s < 0:
		_set_brain("chase")
		return
	home_vehicle.enter(self, s)
	collision_layer = 0
	collision_mask = 0
	_drop_weapon_model()
	if s == 0 and Game.police and home_vehicle.police_unit:
		Game.police.reattach_driver(home_vehicle, self)
	brain = "drive"


func _steer_move(dir: Vector3, speed: float, delta: float, face_target: Vector3) -> void:
	if dir.length() > 0.01 and speed > 0.0:
		dir = dir.normalized()
		# simple obstacle avoidance
		if lod == 0:
			var ahead := U.ray(global_position + Vector3(0, 0.6, 0), global_position + Vector3(0, 0.6, 0) + dir * 1.3, C.L_WORLD | C.L_PROP | C.L_VEHICLE, [self])
			if not ahead.is_empty():
				var side := dir.cross(Vector3.UP)
				var l := U.ray(global_position + Vector3(0, 0.6, 0), global_position + Vector3(0, 0.6, 0) + (dir + side).normalized() * 1.5, C.L_WORLD | C.L_PROP | C.L_VEHICLE, [self])
				dir = (dir + side * (1.5 if l.is_empty() else -1.5)).normalized()
		velocity.x = move_toward(velocity.x, dir.x * speed, delta * 14.0)
		velocity.z = move_toward(velocity.z, dir.z * speed, delta * 14.0)
	else:
		velocity.x = move_toward(velocity.x, 0.0, delta * 12.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 12.0)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -1.0
	move_and_slide()
	var hv := Vector3(velocity.x, 0, velocity.z)
	if face_target != Vector3.ZERO:
		var tf := face_target - global_position
		_yaw = U.damp_angle(_yaw, atan2(tf.x, tf.z), 10.0, delta)
	elif hv.length() > 0.2:
		_yaw = U.damp_angle(_yaw, atan2(hv.x, hv.z), 8.0, delta)
	rotation.y = _yaw + PI
	# stuck detection
	if speed > 0.5 and hv.length() < 0.2:
		_stuck_t += delta
		if _stuck_t > 2.0:
			_stuck_t = 0.0
			cur_node = -1
			velocity += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 2.0
	else:
		_stuck_t = 0.0
	if global_position.y < -30.0:
		queue_free()


func _wander_dir() -> Vector3:
	var g: PedGraph = Game.world.ped_graph if Game.world else null
	if g == null:
		return Vector3.ZERO
	if cur_node < 0:
		cur_node = g.nearest(global_position)
		next_node = cur_node
	var tgt: Vector3 = g.pos[next_node]
	var to := tgt - global_position
	to.y = 0
	_wait_cross = false
	if to.length() < 0.8:
		prev_node = cur_node
		cur_node = next_node
		var opts: Array = g.adj[cur_node]
		if opts.is_empty():
			return Vector3.ZERO
		var choice: Dictionary = opts[randi() % opts.size()]
		if opts.size() > 1 and choice.to == prev_node:
			choice = opts[randi() % opts.size()]
		next_node = choice.to
		if randf() < 0.05:
			_set_brain("idle")
		# crosswalk wait
		if choice.cross >= 0 and Game.world.road_graph and not Game.world.road_graph.ped_can_cross(choice.cross, choice.arm):
			_wait_cross = true
			next_node = cur_node
		return Vector3.ZERO
	return to.normalized()


func _flee_dir() -> Vector3:
	var from := crime_pos
	if threat and is_instance_valid(threat):
		from = threat.global_position
	var away := global_position - from
	away.y = 0
	if away.length() < 0.1:
		away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	var g: PedGraph = Game.world.ped_graph if Game.world else null
	if g == null or lod > 0:
		return away.normalized()
	if cur_node < 0 or next_node < 0:
		cur_node = g.nearest(global_position)
		next_node = cur_node
	var tgt: Vector3 = g.pos[next_node]
	var to := tgt - global_position
	to.y = 0
	if to.length() < 1.0 or to.normalized().dot(away.normalized()) < -0.2:
		cur_node = next_node
		var best := cur_node
		var bd := -INF
		for o in g.adj[cur_node]:
			var p2: Vector3 = g.pos[o.to]
			var sc := (p2 - from).length() - (p2 - global_position).length() * 0.3
			if sc > bd:
				bd = sc
				best = o.to
		next_node = best
		tgt = g.pos[next_node]
		to = tgt - global_position
		to.y = 0
	return (to.normalized() * 0.7 + away.normalized() * 0.3).normalized()


func _anim(delta: float) -> void:
	if rig == null:
		return
	var hs := Vector2(velocity.x, velocity.z).length()
	rig.speed = hs
	rig.grounded = true
	rig.crouch = 0.0
	if vehicle != null:
		rig.update_pose(delta)
		return
	rig.aim = 1.0 if brain == "attack" and weapons.current != "fists" else 0.0
	rig.hold = int(weapons.def().get("hold", 0))
	rig.aim_pitch = 0.0
	if idle_pose != "":
		rig.mode = idle_pose
	else:
		rig.mode = "normal"
	rig.update_pose(delta)


# ------------------------------------------------------------------ damage

func _on_damaged(dmg: float, source: Node, _pos: Vector3, _impulse: Vector3, kind_s: String) -> void:
	alert = 1.0
	if source == Game.player:
		var crime := "assault"
		if kind in ["police", "swat"]:
			crime = "attack_police"
		Game.report_crime(crime, global_position, self)
		threat = Game.player
		if kind in ["police", "swat", "gang"]:
			_set_brain("attack")
		elif personality == "brave" and kind_s in ["melee", "melee_heavy"]:
			_set_brain("attack")
		elif brain not in ["flee"]:
			_set_brain("flee")
		if randf() < 0.5:
			Audio.play_3d("scream", global_position + Vector3(0, 1.6, 0), -2.0, randf_range(0.9, 1.3), 50.0)


func _on_died(source: Node, kind_s: String) -> void:
	if source == Game.player or (source is VehicleBase and (source as VehicleBase).driver == Game.player):
		var crime := "murder"
		if kind in ["police", "swat"]:
			crime = "kill_police"
		if kind_s == "takedown":
			crime = "takedown"
		Game.report_crime(crime, global_position, self)
	Game.emit_event(global_position, 20.0, "fight", self)
	if cash > 0 and randf() < 0.75 and Game.main and Game.main.has_method("spawn_pickup"):
		Game.main.spawn_pickup("cash", global_position + Vector3(0, 0.4, 0), cash)
	if kind in ["police", "swat"] and randf() < 0.6 and Game.main and Game.main.has_method("spawn_pickup"):
		Game.main.spawn_pickup("weapon:" + weapons.current, global_position + Vector3(0.6, 0.4, 0), 30)
	if manager and manager.has_method("on_npc_died"):
		manager.on_npc_died(self)
	if Game.has_method("on_npc_died"):
		Game.on_npc_died(self)
