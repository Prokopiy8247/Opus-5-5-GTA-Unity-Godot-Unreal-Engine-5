class_name WantedSystem
extends Node
## 0–5 star wanted system with witnesses, police line-of-sight, pursuit vs. search states,
## last-known position, growing search radius, escape timer and arrests.

signal level_changed(level: int)
signal state_changed(state: String)

# crime -> [stars it guarantees, heat added]
const CRIMES := {
	"brandish": [1, 0.5], "assault": [1, 1.0], "gunfire": [1, 0.6], "carjack": [1, 1.0], "hit_pedestrian": [1, 1.0],
	"vehicular_assault": [2, 1.5], "murder": [2, 2.0], "takedown": [1, 1.5], "attack_police": [2, 2.0],
	"kill_police": [3, 3.0], "steal_police": [2, 2.0], "destroy_police": [3, 3.0], "explosion": [2, 1.5],
	"resist": [1, 1.0],
}
const ESCAPE_TIME := [0.0, 10.0, 16.0, 24.0, 32.0, 42.0]
const SEARCH_RADIUS := [0.0, 60.0, 80.0, 100.0, 120.0, 140.0]

var level := 0
var heat := 0.0
var state := "clean"         # clean, pursuit, search
var last_known := Vector3.ZERO
var last_seen_t := -100.0
var escape_t := 0.0
var search_center := Vector3.ZERO
var search_radius := 0.0
var _arrest_t := 0.0
var _arrest_officer: Node = null
var known_vehicle: VehicleBase = null
var known_outfit := 0
var outfit_id := 0
var _indirect_t := 0.0
var _resist_t := 0.0
var _seen_flag := false


func crime(kind: String, pos: Vector3, victim: Node = null) -> void:
	if not CRIMES.has(kind):
		return
	if Game.player and Game.player.dead:
		return
	var info: Array = CRIMES[kind]
	# police witnesses -> immediate
	var seen_by_police := _police_can_see(pos)
	if seen_by_police or level > 0 and state == "pursuit":
		_apply(kind, info, pos)
		return
	# civilian witnesses (line of sight within 35 m) call it in after a delay
	var any := false
	for n in Game.npcs:
		var npc := n as NPC
		if npc == null or npc.dead or npc == victim or npc.vehicle != null:
			continue
		if npc.kind not in ["civilian", "medic", "shop"]:
			continue
		var d := npc.global_position.distance_to(pos)
		if d > 35.0:
			continue
		var los := U.ray(npc.global_position + Vector3(0, 1.6, 0), pos + Vector3(0, 1.2, 0), C.MASK_SIGHT, [npc]).is_empty()
		if los and npc.witness(kind, pos):
			any = true
			break
	# gunshots / explosions are heard: indirect report after a delay
	if not any and kind in ["gunfire", "explosion"] and level == 0:
		_indirect_t = 9.0
		search_center = pos


func witness_report(kind: String, pos: Vector3, reporter: Node) -> void:
	if not CRIMES.has(kind):
		return
	# A reported crime is real knowledge: the caller may have died in the meantime.
	Game.notify("A witness reported you to the police", "warn")
	if level == 0:
		heat = 0.0
		set_level(1)
		_set_state("search")
		last_known = pos
		search_center = pos
		search_radius = 15.0
		return
	_apply(kind, CRIMES[kind], pos, false)


func _apply(kind: String, info: Array, pos: Vector3, seen := true) -> void:
	var min_lvl: int = info[0]
	heat += float(info[1])
	var new_level := maxi(level, min_lvl)
	# repeated crimes escalate
	var thresholds := [0.0, 0.0, 4.0, 9.0, 16.0, 26.0]
	for l in range(5, 0, -1):
		if heat >= thresholds[l] and l > new_level and l <= level + 1:
			new_level = l
			break
	if new_level != level:
		set_level(new_level)
	if seen:
		_mark_seen(Game.player.global_position)
	else:
		last_known = pos
		if state == "clean":
			_set_state("search")
		search_center = pos


func _police_can_see(pos: Vector3) -> bool:
	for n in Game.npcs:
		var npc := n as NPC
		if npc == null or npc.dead or npc.kind not in ["police", "swat"]:
			continue
		var from := npc.global_position + Vector3(0, 1.6, 0)
		if from.distance_to(pos) > 55.0:
			continue
		if U.ray(from, pos + Vector3(0, 1.0, 0), C.MASK_SIGHT, [npc, Game.player]).is_empty():
			return true
	if Game.police:
		for u in Game.police.units:
			var v := u as VehicleBase
			if v and is_instance_valid(v) and v.driver and v.global_position.distance_to(pos) < 60.0:
				if U.ray(v.global_position + Vector3(0, 1.5, 0), pos + Vector3(0, 1.0, 0), C.MASK_SIGHT, [v, Game.player]).is_empty():
					return true
	return false


func set_level(l: int) -> void:
	l = clampi(l, 0, 5)
	if l == level:
		return
	var up := l > level
	level = l
	if l == 0:
		heat = 0.0
		_set_state("clean")
	else:
		heat = maxf(heat, [0.0, 0.0, 4.0, 9.0, 16.0, 26.0][l])
		if state == "clean":
			_set_state("pursuit")
			_mark_seen(Game.player.global_position)
	if up:
		Audio.play_ui("wanted_up")
	print("[Wanted] level %d (heat %.1f, state %s)" % [level, heat, state])
	level_changed.emit(level)


func clear() -> void:
	print("[Wanted] CLEARED (was level %d, escape %.1f/%0.1f s)" % [level, escape_t, ESCAPE_TIME[maxi(level, 1)]])
	heat = 0.0
	set_level(0)
	escape_t = 0.0
	_indirect_t = 0.0


func _set_state(s: String) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)


func _mark_seen(ppos: Vector3) -> void:
	last_known = ppos
	last_seen_t = Game.now()
	search_center = ppos
	escape_t = 0.0
	var p := Game.player
	known_vehicle = p.vehicle if p else null
	known_outfit = outfit_id
	if level > 0:
		_set_state("pursuit")


## Called by police perception (on-foot officers, police drivers, helicopters).
func police_sees(_unit: Node, ppos: Vector3) -> void:
	if level == 0:
		return
	# disguise: changed vehicle/outfit while searching makes identification harder at range
	if state == "search":
		var p := Game.player
		var changed := (p.vehicle != known_vehicle) or (outfit_id != known_outfit)
		if changed and _unit is Node3D and (_unit as Node3D).global_position.distance_to(ppos) > 22.0 and randf() < 0.6:
			return
	_seen_flag = true
	_mark_seen(ppos)


func arrest_attempt(officer: Node) -> void:
	var p := Game.player
	if p == null or p.dead or level == 0 or level >= 4:
		return
	if p.vehicle != null:
		return
	var armed: bool = p.weapons.current != "fists" and not p.weapons.def().get("melee", false)
	if (armed and p.aiming) or p.sprinting:
		return
	if Vector2(p.velocity.x, p.velocity.z).length() > 2.5:
		return
	_arrest_officer = officer
	_arrest_t += 0.2
	if _arrest_t > 1.6:
		_arrest_t = 0.0
		p.arrest()
		clear()


func _process(delta: float) -> void:
	if Game.paused:
		return
	if _indirect_t > 0.0:
		_indirect_t -= delta
		if _indirect_t <= 0.0 and level == 0:
			Game.notify("Shots reported — police are investigating the area", "warn")
			set_level(1)
			_set_state("search")
			last_known = search_center
	if level == 0:
		_arrest_t = maxf(_arrest_t - delta, 0.0)
		return
	_arrest_t = maxf(_arrest_t - delta * 0.5, 0.0)
	var seen_recent := Game.now() - last_seen_t < 1.6
	if seen_recent:
		_set_state("pursuit")
		escape_t = 0.0
		search_radius = 25.0
		# sustained resistance at high stars
		_resist_t += delta
		if level >= 3 and _resist_t > 75.0 and level < 5:
			_resist_t = 0.0
			heat += 4.0
			set_level(level + 1)
	else:
		_set_state("search")
		escape_t += delta
		search_radius = minf(search_radius + delta * 3.0, SEARCH_RADIUS[level])
		# leaving the search zone accelerates the escape, but at least a third of the timer must
		# still elapse so a wanted level never evaporates in a couple of seconds.
		var p := Game.player
		if p and p.global_position.distance_to(search_center) > search_radius:
			escape_t += delta * 0.4
		if escape_t >= ESCAPE_TIME[level]:
			Game.notify("You lost the police", "good")
			clear()


func escape_progress() -> float:
	if level == 0:
		return 0.0
	return clampf(escape_t / ESCAPE_TIME[level], 0.0, 1.0)
