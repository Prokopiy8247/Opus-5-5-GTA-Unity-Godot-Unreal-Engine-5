class_name Actor
extends CharacterBody3D
## Shared base for the player and NPCs: health/armor, damage, death & ragdoll, knockdown/get-up,
## weapon-in-hand visual, soft vehicle contact (push-out or get run over).

signal died(actor: Actor, killer: Node)

const GRAVITY := 20.0

var health := 100.0
var max_health := 100.0
var armor := 0.0
var team: int = C.Team.CIVILIAN
var rig: HumanoidRig
var weapons: WeaponUser
var dead := false
var ragdolled := false
var ragdoll_node: Node3D
var ragdoll_t := 0.0
var ragdoll_dur := 0.0
var vehicle: VehicleBase = null
var seat := -1
var weapon_model: Node3D
var weapon_model_id := ""
var look_data := {}
var last_attacker: Node = null
var in_water := false
var water_depth := 0.0
var _veh_check_t := 0.0


func _setup_body(radius := 0.32, height := 1.8, layer := C.L_NPC) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "Capsule"
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	cs.shape = cap
	cs.position = Vector3(0, height * 0.5, 0)
	add_child(cs)
	collision_layer = layer
	collision_mask = C.MASK_CHAR_MOVE
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50.0)
	safe_margin = 0.02
	rig = HumanoidRig.new()
	rig.name = "Rig"
	add_child(rig)


func head_y() -> float:
	return 1.5 * float(look_data.get("height", 1.0))


func is_alive() -> bool:
	return not dead


func take_damage(amount: float, source: Node = null, pos := Vector3.ZERO, impulse := Vector3.ZERO, kind := "bullet") -> void:
	if dead:
		if ragdolled and ragdoll_node and rig.ragdoll_bodies.has("chest"):
			(rig.ragdoll_bodies.chest as RigidBody3D).apply_central_impulse(impulse * 4.0)
		return
	last_attacker = source if (source == null or is_instance_valid(source)) else null
	var dmg := amount
	if armor > 0.0 and kind != "fall" and kind != "drown":
		var absorbed := minf(armor, dmg * 0.7)
		armor -= absorbed
		dmg -= absorbed
	health -= dmg
	_on_damaged(dmg, source, pos, impulse, kind)
	if health <= 0.0:
		health = 0.0
		die(source, impulse, kind)
	elif kind in ["explosion", "vehicle", "melee_heavy"] and impulse.length() > 5.0:
		knockdown(impulse, 2.2)
	elif kind == "melee" and impulse.length() > 6.0:
		knockdown(impulse, 1.6)
	elif rig and not ragdolled:
		rig.play_action("hit")


func _on_damaged(_dmg: float, _source: Node, _pos: Vector3, _impulse: Vector3, _kind: String) -> void:
	pass


func die(source: Node, impulse := Vector3.ZERO, kind := "bullet") -> void:
	if dead:
		return
	dead = true
	if vehicle:
		_force_exit_vehicle()
	var imp := impulse * 6.0
	if kind == "headshot":
		imp += Vector3(0, 1, 0)
	go_ragdoll(imp, 9999.0, "head" if kind == "headshot" else "chest")
	died.emit(self, source)
	_on_died(source, kind)


func _on_died(_source: Node, _kind: String) -> void:
	pass


func _ragdoll_container() -> Node:
	var root := get_tree().current_scene
	var c := root.get_node_or_null("Ragdolls")
	if c == null:
		c = Node3D.new()
		c.name = "Ragdolls"
		root.add_child(c)
	return c


func go_ragdoll(impulse: Vector3, duration: float, hit_joint := "chest") -> void:
	if ragdolled or rig == null:
		return
	ragdolled = true
	ragdoll_t = 0.0
	ragdoll_dur = duration
	_drop_weapon_model()
	ragdoll_node = rig.make_ragdoll(_ragdoll_container(), velocity, impulse, hit_joint)
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO


func knockdown(impulse: Vector3, duration: float) -> void:
	if dead or ragdolled or vehicle != null:
		return
	go_ragdoll(impulse * 5.0, duration)


func _update_ragdoll(delta: float) -> void:
	if not ragdolled:
		return
	ragdoll_t += delta
	if is_instance_valid(ragdoll_node):
		global_position = rig.ragdoll_center() - Vector3(0, 0.6, 0)
	if dead:
		if ragdoll_t > 7.0 and ragdoll_t - delta <= 7.0:
			rig.freeze_ragdoll()
		return
	if ragdoll_t >= ragdoll_dur:
		_get_up()


func _get_up() -> void:
	var p := rig.ragdoll_center()
	if is_instance_valid(ragdoll_node):
		ragdoll_node.queue_free()
	ragdoll_node = null
	ragdolled = false
	rig.ragdoll_root = null
	rig.ragdoll_bodies = {}
	rig.visible = true
	rig.build(look_data)
	var hit := U.ray(p + Vector3(0, 1.0, 0), p + Vector3(0, -3.0, 0), C.L_WORLD)
	global_position = (hit.position if not hit.is_empty() else p) + Vector3(0, 0.05, 0)
	_restore_collision()
	weapon_model_id = ""
	_refresh_weapon_model()


func _restore_collision() -> void:
	collision_layer = C.L_NPC
	collision_mask = C.MASK_CHAR_MOVE


func cleanup_ragdoll() -> void:
	if is_instance_valid(ragdoll_node):
		ragdoll_node.queue_free()
	ragdoll_node = null


# ------------------------------------------------------------------ weapon visual

func _refresh_weapon_model() -> void:
	if weapons == null or rig == null or rig.hand_socket == null:
		return
	var id := weapons.current
	if id == weapon_model_id and is_instance_valid(weapon_model):
		return
	_drop_weapon_model()
	weapon_model_id = id
	if id == "fists":
		return
	weapon_model = WeaponModels.build(id, weapons.mods())
	rig.hand_socket.add_child(weapon_model)
	_fit_aim_ik()


## Measures the held model (weapon space) so the rig's aim IK puts the stock in the shoulder and the
## support hand on the fore-end of this particular gun.
func _fit_aim_ik() -> void:
	var d := weapons.def()
	var bb := AABB()
	var first := true
	var inv := weapon_model.global_transform.affine_inverse()
	for n in weapon_model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	rig.ik_aim = not first and not d.get("melee", false) and not d.get("throw", false)
	if first:
		return
	rig.wpn_long = bb.size.z > 0.4
	rig.wpn_butt = Vector3(0, 0.05, bb.end.z)
	match int(d.get("hold", 0)):
		4:
			rig.wpn_fore = Vector3(0, 0.0, -0.25)
		2:
			rig.wpn_fore = Vector3(0, 0.0, maxf(bb.position.z * 0.33, -0.25))
		_:
			rig.wpn_fore = Vector3(0, -0.03, -0.15) if rig.wpn_long else Vector3(0, -0.045, 0.02)


func _drop_weapon_model() -> void:
	if is_instance_valid(weapon_model):
		weapon_model.queue_free()
	weapon_model = null
	weapon_model_id = ""
	if rig:
		rig.ik_aim = false


func muzzle_xform() -> Transform3D:
	if is_instance_valid(weapon_model):
		var m := weapon_model.get_node_or_null("Muzzle") as Node3D
		if m:
			return m.global_transform
	return Transform3D(global_basis, global_position + Vector3(0, 1.4, 0) - global_basis.z * 0.5)


# ------------------------------------------------------------------ environment interaction

func _update_water() -> void:
	var gy := WorldMap.height(global_position.x, global_position.z)
	water_depth = C.SEA_LEVEL - global_position.y
	in_water = gy < C.SEA_LEVEL - 0.6 and water_depth > 0.95


## Soft contact with vehicles: push out when slow, get run over when fast.
func _vehicle_contacts(delta: float) -> void:
	_veh_check_t -= delta
	if _veh_check_t > 0.0 or ragdolled or dead or vehicle != null:
		return
	_veh_check_t = 0.033
	for v in Game.vehicles:
		var veh := v as VehicleBase
		if veh == null or not is_instance_valid(veh) or veh.is_ignoring(self):
			continue
		var d := veh.global_position - global_position
		if absf(d.x) > 8.0 or absf(d.z) > 8.0 or absf(d.y) > 4.0:
			continue
		var lp := veh.global_transform.affine_inverse() * (global_position + Vector3(0, 0.9, 0))
		var he := veh.half_extents + Vector3(0.3, 0.0, 0.3)
		if absf(lp.x) > he.x or absf(lp.z) > he.z or lp.y < -he.y - 0.9 or lp.y > he.y + 0.6:
			continue
		# only the vehicle's own motion runs people over: someone running into a parked car (or walking up to
		# a plane's door under the wing) is pushed out, not knocked down
		var vv := veh.linear_velocity
		var spd := vv.length()
		if spd > 4.5 and vv.dot(-d) > 0.0:
			var dmg := (spd - 3.5) * 7.0
			var imp := veh.linear_velocity * 1.05 + Vector3(0, 2.5 + spd * 0.15, 0)
			take_damage(dmg, veh.driver, global_position + Vector3(0, 1, 0), imp, "vehicle")
			if not ragdolled and not dead:
				knockdown(imp, 2.5)
			veh.linear_velocity *= 0.93
			veh.on_hit_pedestrian(self, spd)
			Audio.play_3d("impact_flesh", global_position, 2.0, 0.8, 60.0)
		else:
			# push out along the shallowest axis (vehicle local space)
			var px := he.x - absf(lp.x)
			var pz := he.z - absf(lp.z)
			var push_local := Vector3(signf(lp.x) * px, 0, 0) if px < pz else Vector3(0, 0, signf(lp.z) * pz)
			var push := veh.global_basis * push_local
			push.y = 0.0
			global_position += push


func _force_exit_vehicle() -> void:
	if vehicle and is_instance_valid(vehicle):
		vehicle.remove_occupant(self)
	vehicle = null
	seat = -1
	if rig:
		rig.mode = "normal"
