class_name Activities
extends Node
## Optional free-roam activities (no missions): shooting range challenge and stunt jumps.

var range_active := false
var range_t := 0.0
var range_score := 0
var range_shots := 0
var range_hits := 0
var targets: Array = []
var _spawn_t := 0.0
var _shots_at_start := 0
var best_range := 0
var jumps_done := {}
var best_jump := 0.0


func _ready() -> void:
	Game.activities = self


# ------------------------------------------------------------------ shooting range

func start_range() -> void:
	if range_active:
		return
	var p := Game.player
	if p.weapons.current == "fists" or p.weapons.def().get("melee", false):
		if not p.weapons.has("pistol"):
			p.weapons.give("pistol", 60)
		p.weapons.select("pistol")
	range_active = true
	range_t = 45.0
	range_score = 0
	range_hits = 0
	range_shots = 0
	_spawn_t = 0.5
	if not p.weapons.fired.is_connected(_on_fired):
		p.weapons.fired.connect(_on_fired)
	Game.notify("SHOOTING RANGE: hit the pop-up targets — 45 seconds!", "good")


func _on_fired(_id: String) -> void:
	if range_active:
		range_shots += 1


func _process(delta: float) -> void:
	if not range_active:
		return
	range_t -= delta
	_spawn_t -= delta
	if _spawn_t <= 0.0:
		_spawn_t = randf_range(0.7, 1.4)
		_spawn_target()
	for i in range(targets.size() - 1, -1, -1):
		var t = targets[i]
		if t == null or not is_instance_valid(t):
			targets.remove_at(i)
			continue
		if t.hit:
			range_hits += 1
			range_score += t.points
			targets.remove_at(i)
		elif t.age > 3.2:
			t.queue_free()
			targets.remove_at(i)
	if Game.hud:
		Game.hud.prompt_lbl.text = "RANGE  %ds   SCORE %d   HITS %d   ACC %d%%" % [int(range_t), range_score, range_hits, int(100.0 * range_hits / maxf(range_shots, 1))]
	if range_t <= 0.0 or Game.player.global_position.distance_to(Game.world.poi.range.pos) > 40.0:
		_end_range()


func _spawn_target() -> void:
	var pts: Array = Game.world.range_targets
	if pts.is_empty():
		return
	var p: Vector3 = pts[randi() % pts.size()]
	var t := RangeTarget.new()
	get_tree().current_scene.add_child(t)
	t.global_position = p
	t.points = 10 + int(p.distance_to(Game.world.poi.range.pos) * 0.8)
	targets.append(t)


func _end_range() -> void:
	range_active = false
	for t in targets:
		if is_instance_valid(t):
			t.queue_free()
	targets.clear()
	var acc := 100.0 * range_hits / maxf(range_shots, 1)
	var reward := range_score * 3 + int(acc) * 5
	Game.add_money(reward)
	Game.skills.add("shooting", 2.0 + range_hits * 0.4)
	best_range = maxi(best_range, range_score)
	Game.notify("Range complete: score %d, accuracy %d%% — reward %s (best %d)" % [range_score, int(acc), U.money_str(reward), best_range], "good")


# ------------------------------------------------------------------ stunt jumps

func on_vehicle_jump(v: VehicleBase, air: float, dist: float, clean: bool) -> void:
	if air < 1.1 or dist < 12.0:
		return
	var near_ramp := ""
	for j in Game.world.stunt_jumps:
		if j.get("auto", false):
			continue
		if U.flat_dist(j.pos, v.global_position) < dist + 25.0:
			near_ramp = j.name
	var label := near_ramp if near_ramp != "" else "Stunt jump"
	var reward := int(dist * 4.0 + air * 60.0) * (2 if clean else 1)
	if near_ramp != "" and not jumps_done.has(near_ramp):
		jumps_done[near_ramp] = true
		reward += 500
		label += " (first completion!)"
	best_jump = maxf(best_jump, dist)
	Game.add_money(reward)
	Game.skills.add("driving", 1.0)
	Game.notify("%s — %.0f m, %.1f s airtime%s  +%s" % [label, dist, air, ", clean landing" if clean else ", rough landing", U.money_str(reward)], "good")
