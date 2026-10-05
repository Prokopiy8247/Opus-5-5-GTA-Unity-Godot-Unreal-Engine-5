class_name Crosshair
extends Control
## Dynamic crosshair: gap follows weapon spread/heat, turns red over hostile targets, hit marker.

var _hit_t := 0.0


func _ready() -> void:
	if Game.player:
		Game.player.weapons.fired.connect(func(_id): _check_hit())


func _check_hit() -> void:
	_hit_t = 0.0


func _process(delta: float) -> void:
	_hit_t += delta
	queue_redraw()


func _draw() -> void:
	var p := Game.player
	if p == null:
		return
	var c := size * 0.5
	var d := p.weapons.def()
	var spread := WeaponDB.stat(p.weapons.current, "spread", p.weapons.mods()) + p.weapons.heat * 1.2
	if not p.aiming:
		spread *= 2.2
	var gap := 6.0 + spread * 6.0
	var col := Color(1, 1, 1, 0.9)
	# target under crosshair
	var cam := Game.cam.cam
	var hit := U.ray(cam.global_position, cam.global_position - cam.global_basis.z * 120.0, C.MASK_BULLET, [p, p.vehicle] if p.vehicle else [p])
	if not hit.is_empty():
		var t := U.find_ancestor_with_method(hit.collider as Node, "take_damage") if hit.collider is Node else null
		if t is NPC and not (t as NPC).dead:
			col = Color(1.0, 0.3, 0.25, 0.95) if (t as NPC).kind in ["police", "swat", "gang"] else Color(1.0, 0.8, 0.3, 0.95)
	if d.get("melee", false):
		draw_circle(c, 3.0, col)
		return
	var l := 9.0
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + dir * gap, c + dir * (gap + l), Color(0, 0, 0, 0.6), 4.0)
		draw_line(c + dir * gap, c + dir * (gap + l), col, 2.0)
	draw_circle(c, 1.5, col)
	if _hit_t < 0.12:
		for dir2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + dir2.normalized() * 6.0, c + dir2.normalized() * 13.0, Color(1, 1, 1, 0.9), 2.0)
