extends Node
## Global game state & service locator (autoload "Game").

signal notified(text: String, kind: String)
signal money_changed(value: int)
signal player_died
signal player_busted

var main: Node
var world: World
var player: Player
var cam: CameraRig
var hud: Node
var env: EnvController
var wanted: WantedSystem
var traffic: TrafficManager
var peds: PedManager
var police: PoliceDispatch
var wildlife: WildlifeManager
var activities: Node
var skills: Skills
var garage: GarageStorage

var money := 2500
var night_factor := 0.0
var invulnerable := false
var traffic_enabled := true
var peds_enabled := true
var wildlife_enabled := true
var show_fps := false
var show_coords := false
var paused := false
var unlock_all_mods := false
var ui_open := 0          # >0 while a menu needs the mouse
var vehicles: Array = []  # VehicleBase
var npcs: Array = []      # NPC
var settings := {"mouse_sens": 0.0025, "invert_y": false, "master_db": 0.0, "music_db": -6.0, "fov": 72.0, "quality": 1}
var radio_station := 0

# event bus for perception: [{pos, radius, kind, time, source}]
var events: Array = []
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputSetup.setup()
	skills = Skills.new()
	garage = GarageStorage.new()


func _process(delta: float) -> void:
	_t += delta
	if events.size() > 0:
		var keep: Array = []
		for e in events:
			if _t - e.time >= 4.0:
				continue
			if e.source != null and not is_instance_valid(e.source):
				e.source = null
			keep.append(e)
		events = keep


func now() -> float:
	return _t


func notify(text: String, kind := "info") -> void:
	notified.emit(text, kind)
	print("[Notify] ", text)


func add_money(v: int) -> void:
	money = maxi(money + v, 0)
	money_changed.emit(money)


func spend(v: int) -> bool:
	if money < v:
		notify("Not enough cash (" + U.money_str(v) + ")", "warn")
		Audio.play_ui("deny")
		return false
	add_money(-v)
	Audio.play_ui("buy")
	return true


## Noise / threat events nearby actors react to (gunshots, explosions, screams, crashes).
func emit_event(pos: Vector3, radius: float, kind: String, source: Node = null) -> void:
	if source != null and not is_instance_valid(source):
		source = null
	events.append({"pos": pos, "radius": radius, "kind": kind, "time": _t, "source": source})
	if events.size() > 64:
		events.pop_front()


## Crime reporting entry point (wanted system decides about witnesses / police sight).
func report_crime(kind: String, pos: Vector3, victim: Node = null) -> void:
	if wanted:
		wanted.crime(kind, pos, victim)


## Area damage + impulse + props + chain reactions.
func explosion(pos: Vector3, radius: float, damage: float, source: Node = null) -> void:
	VFX.explosion(pos, radius / 6.0)
	Audio.play_3d("explosion", pos, 6.0, randf_range(0.85, 1.05))
	emit_event(pos, 140.0, "explosion", source)
	if cam:
		var d := cam.global_position.distance_to(pos)
		cam.add_trauma(clampf(1.2 - d / 60.0, 0.0, 1.0))
	if world and world.props:
		world.props.explode_area(pos, radius * 0.9)
	var hits := U.sphere_query(pos, radius, C.L_PLAYER | C.L_NPC | C.L_VEHICLE | C.L_PROP | C.L_RAGDOLL, 64)
	var seen := {}
	for h in hits:
		var o: Object = h.collider
		if o == null or seen.has(o):
			continue
		seen[o] = true
		var n := o as Node3D
		if n == null:
			continue
		var d2 := n.global_position.distance_to(pos)
		var f := clampf(1.0 - d2 / radius, 0.0, 1.0)
		var dir := (n.global_position - pos + Vector3(0, 0.8, 0)).normalized()
		if n.has_method("take_damage"):
			n.take_damage(damage * f, source, n.global_position, dir * 18.0 * f, "explosion")
		elif n is RigidBody3D:
			if n is VehicleBase:
				(n as VehicleBase).wake()
			(n as RigidBody3D).apply_central_impulse(dir * 60.0 * f * (n as RigidBody3D).mass * 0.1)
	if source == player:
		report_crime("explosion", pos)


func register_vehicle(v: Node) -> void:
	if not vehicles.has(v):
		vehicles.append(v)


func unregister_vehicle(v: Node) -> void:
	vehicles.erase(v)


func register_npc(n: Node) -> void:
	if not npcs.has(n):
		npcs.append(n)


func unregister_npc(n: Node) -> void:
	npcs.erase(n)


func poi_near(pos: Vector3, radius := 2.6) -> Dictionary:
	if world == null:
		return {}
	var best := {}
	var bd := radius
	for id in world.poi:
		var p: Dictionary = world.poi[id]
		var d := U.flat_dist(p.pos, pos)
		if d < bd and absf((p.pos as Vector3).y - pos.y) < 3.0:
			bd = d
			best = p.duplicate()
			best["id"] = id
	return best


func set_paused(v: bool) -> void:
	paused = v
	get_tree().paused = v
