class_name WeaponUser
extends RefCounted
## Inventory + firing logic shared by the player and armed NPCs.

signal fired(id: String)
signal reloaded(id: String)
signal changed(id: String)

var owner: Node3D
var inv := {}            # id -> {mag:int, reserve:int, mods:Dictionary}
var current := "fists"
var cooldown := 0.0
var reload_t := 0.0
var heat := 0.0          # sustained-fire spread growth
var is_player := false
var infinite_ammo := false


func _init(o: Node3D, player := false) -> void:
	owner = o
	is_player = player
	inv["fists"] = {"mag": 0, "reserve": 0, "mods": {}}


func def() -> Dictionary:
	return WeaponDB.get_def(current)


func mods() -> Dictionary:
	return inv.get(current, {}).get("mods", {})


func has(id: String) -> bool:
	return inv.has(id)


func give(id: String, ammo := -1) -> void:
	var d := WeaponDB.get_def(id)
	if not inv.has(id):
		inv[id] = {"mag": 0, "reserve": 0, "mods": {}}
		var mag := int(WeaponDB.stat(id, "mag", {}))
		inv[id].mag = mag
	add_ammo(id, ammo if ammo >= 0 else int(d.get("ammo_pack", 0)) * 2)


func add_ammo(id: String, amount: int) -> void:
	if not inv.has(id):
		return
	var d := WeaponDB.get_def(id)
	if d.get("melee", false):
		return
	inv[id].reserve = mini(inv[id].reserve + amount, 999)


func refill_all() -> void:
	for id in inv:
		var d := WeaponDB.get_def(id)
		if d.get("melee", false):
			continue
		inv[id].mag = int(WeaponDB.stat(id, "mag", inv[id].mods))
		inv[id].reserve = 999 if not d.get("throw", false) else 25


func select(id: String) -> void:
	if not inv.has(id) or id == current:
		return
	current = id
	reload_t = 0.0
	cooldown = 0.25
	heat = 0.0
	changed.emit(id)


func mag() -> int:
	return inv.get(current, {}).get("mag", 0)


func reserve() -> int:
	return inv.get(current, {}).get("reserve", 0)


func total_ammo(id: String) -> int:
	if not inv.has(id):
		return 0
	return inv[id].mag + inv[id].reserve


func is_reloading() -> bool:
	return reload_t > 0.0


func update(dt: float) -> void:
	cooldown = maxf(cooldown - dt, 0.0)
	heat = maxf(heat - dt * 2.5, 0.0)
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			_finish_reload()


func start_reload() -> bool:
	var d := def()
	if d.get("melee", false) or reload_t > 0.0:
		return false
	var e: Dictionary = inv[current]
	var cap := int(WeaponDB.stat(current, "mag", e.mods))
	if e.mag >= cap or (e.reserve <= 0 and not infinite_ammo):
		return false
	var mul := Game.skills.reload_mul() if is_player else 1.0
	reload_t = float(d.get("reload", 1.5)) * mul
	Audio.play_3d("reload", owner.global_position, -6.0, 1.0, 40.0)
	return true


func _finish_reload() -> void:
	var e: Dictionary = inv[current]
	var cap := int(WeaponDB.stat(current, "mag", e.mods))
	var need: int = cap - e.mag
	var take := need if infinite_ammo else mini(need, e.reserve)
	e.mag += take
	if not infinite_ammo:
		e.reserve -= take
	reloaded.emit(current)


func can_fire() -> bool:
	return cooldown <= 0.0 and reload_t <= 0.0


## Fires toward target point. Returns true if a shot was made.
func fire(origin: Vector3, target: Vector3, accuracy_mul := 1.0, exclude: Array = []) -> bool:
	var d := def()
	if not can_fire():
		return false
	if d.get("melee", false):
		return false
	var e: Dictionary = inv[current]
	if e.mag <= 0:
		if not start_reload():
			cooldown = 0.3
			Audio.play_3d("empty", origin, -8.0)
		return false
	e.mag -= 1
	if is_player and Game.invulnerable and infinite_ammo:
		e.mag += 1
	var m: Dictionary = e.mods
	cooldown = 1.0 / float(d.get("rate", 2.0))
	var spread_deg := WeaponDB.stat(current, "spread", m) * accuracy_mul + heat * 1.2
	heat = minf(heat + WeaponDB.stat(current, "recoil", m) * 0.25, 6.0)
	var dir := (target - origin).normalized()
	var dmg := WeaponDB.stat(current, "damage", m)
	var range_m := float(d.get("range", 100.0))
	var proj: String = d.get("projectile", "")
	if proj != "":
		Projectile.launch(proj, origin, dir, owner, dmg, float(d.get("radius", 6.0)))
	else:
		var pellets := int(d.get("pellets", 1))
		for i in pellets:
			var sd := _spread(dir, spread_deg)
			hitscan(origin, sd, range_m, dmg, exclude, i == 0 or pellets <= 1 or i % 3 == 0)
	# presentation
	var suppressed: bool = m.get("suppressor", false)
	var snd: String = "shot_suppressed" if suppressed else d.get("sound", "shot_pistol")
	if proj != "grenade":
		Audio.play_3d(snd, origin, 0.0 if not suppressed else -6.0, randf_range(0.94, 1.06), 260.0 if not suppressed else 60.0)
	var noise := WeaponDB.stat(current, "noise", m)
	if noise > 0.0:
		Game.emit_event(origin, noise, "gunshot", owner)
		if is_player:
			Game.report_crime("gunfire", origin)
	if is_player and Game.skills:
		Game.skills.add("shooting", 0.05)
	fired.emit(current)
	return true


func _spread(dir: Vector3, deg: float) -> Vector3:
	if deg <= 0.001:
		return dir
	var r := deg_to_rad(deg) * sqrt(randf())
	var a := randf() * TAU
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var x := dir.cross(up).normalized()
	var y := x.cross(dir).normalized()
	return (dir + (x * cos(a) + y * sin(a)) * tan(r)).normalized()


func hitscan(from: Vector3, dir: Vector3, range_m: float, dmg: float, exclude: Array, tracer := true) -> Dictionary:
	var to := from + dir * range_m
	var hit := U.ray(from, to, C.MASK_BULLET, exclude)
	var end := to
	if not hit.is_empty():
		end = hit.position
	# water surface crossing
	if from.y > C.SEA_LEVEL and end.y < C.SEA_LEVEL:
		var t := (from.y - C.SEA_LEVEL) / maxf(from.y - end.y, 0.001)
		var wp := from.lerp(end, t)
		VFX.burst("splash", wp, Vector3.UP, 0.25)
		if wp.distance_to(end) > 2.5:
			if tracer:
				VFX.tracer(from + dir * 1.0, wp)
			return {}
	if tracer:
		VFX.tracer(from + dir * 1.2, end)
	if hit.is_empty():
		return {}
	var col: Object = hit.collider
	var surface := U.surface_of(col)
	if col is PropManager:
		(col as PropManager).break_at_rid(hit.rid, dir * 6.0 + Vector3(0, 2, 0), hit.position)
	var target := U.find_ancestor_with_method(col as Node, "take_damage") if col is Node else null
	var kind := "bullet"
	if target != null:
		var d2 := dmg
		if target is Actor:
			var a := target as Actor
			if hit.position.y > a.global_position.y + a.head_y():
				d2 *= 2.6
				kind = "headshot"
			surface = C.SURF_FLESH
		target.take_damage(d2, owner, hit.position, dir * 4.0, kind)
		if target is VehicleBase:
			surface = (target as VehicleBase).surface_at(hit.position)
	elif col is RigidBody3D:
		if col is VehicleBase:
			(col as VehicleBase).wake()
		(col as RigidBody3D).apply_impulse(dir * dmg * 0.15, hit.position - (col as RigidBody3D).global_position)
	VFX.impact(hit.position, hit.normal, surface)
	return hit


## Melee strike in front of the attacker. Returns number of things hit.
func melee(origin: Vector3, forward: Vector3, heavy := false, takedown := false) -> int:
	var d := def()
	if cooldown > 0.0:
		return 0
	cooldown = 1.0 / float(d.get("rate", 2.0)) * (1.6 if heavy else 1.0)
	var reach: float = float(d.get("range", 1.6))
	var center := origin + forward * reach * 0.6
	var hits := U.sphere_query(center, reach * 0.75, C.L_NPC | C.L_PLAYER | C.L_VEHICLE | C.L_RAGDOLL, 8)
	var n := 0
	var dmg: float = float(d.get("damage", 10.0)) * (1.9 if heavy else 1.0)
	if is_player:
		dmg *= Game.skills.melee_mul()
	Audio.play_3d("swing", origin, -8.0, randf_range(0.9, 1.15), 30.0)
	for h in hits:
		var c: Object = h.collider
		if c == owner:
			continue
		var t := U.find_ancestor_with_method(c as Node, "take_damage") if c is Node else null
		if t == null or t == owner:
			if c is RigidBody3D:
				if c is VehicleBase:
					(c as VehicleBase).wake()
				(c as RigidBody3D).apply_central_impulse(forward * 40.0)
			continue
		var push := forward * (7.0 if heavy or d.get("knockdown", false) else 2.5) + Vector3(0, 1.5, 0)
		var kind := "takedown" if takedown else ("melee_heavy" if heavy else "melee")
		t.take_damage(999.0 if takedown else dmg, owner, (t as Node3D).global_position + Vector3(0, 1.2, 0), push, kind)
		Audio.play_3d("punch", (t as Node3D).global_position, -2.0, randf_range(0.85, 1.1), 40.0)
		if c is Actor:
			VFX.burst("blood", (t as Node3D).global_position + Vector3(0, 1.3, 0), -forward, 0.6)
		n += 1
		if is_player:
			Game.skills.add("strength", 0.25)
	Game.emit_event(origin, 14.0, "fight", owner)
	if n > 0 and is_player:
		Game.report_crime("assault", origin)
	return n
