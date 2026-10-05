class_name Pickup
extends Node3D
## Collectable: cash, weapon:<id>, armor, health, parachute. Spins, auto-collects on contact.

var kind := "cash"
var amount := 0
var _t := 0.0
var mesh: Node3D
var life := 90.0


func setup(k: String, a: int) -> void:
	kind = k
	amount = a
	mesh = Node3D.new()
	add_child(mesh)
	var mb := MB.new()
	var col := Color(0.4, 0.95, 0.5)
	if k == "cash":
		mb.use("m").col(Color.WHITE)
		mb.box(Vector3(0, 0.0, 0), Vector3(0.32, 0.1, 0.18), 0.02)
		mb.use("b").col(Color.WHITE)
		mb.box(Vector3(0, 0.0, 0), Vector3(0.1, 0.105, 0.185))
	elif k.begins_with("weapon:"):
		var w := WeaponModels.build(k.substr(7), {})
		w.scale = Vector3.ONE * 1.6
		mesh.add_child(w)
		col = Color(1.0, 0.75, 0.3)
	elif k == "armor":
		mb.use("m").col(Color.WHITE)
		mb.prism(Vector3(0, -0.2, 0), 0.4, Vector2(0.18, 0.08), Vector2(0.2, 0.07), 0.03)
		col = Color(0.4, 0.6, 1.0)
	elif k == "health":
		mb.use("r").col(Color.WHITE)
		mb.box(Vector3.ZERO, Vector3(0.3, 0.1, 0.1))
		mb.box(Vector3.ZERO, Vector3(0.1, 0.3, 0.1))
		col = Color(1, 0.3, 0.3)
	elif k == "parachute":
		mb.use("m").col(Color.WHITE)
		mb.box(Vector3.ZERO, Vector3(0.35, 0.45, 0.2), 0.05)
		col = Color(1, 0.5, 0.2)
	if not mb.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = mb.commit({"m": Mats.color(Color(0.3, 0.75, 0.4) if k == "cash" else (Color(0.25, 0.35, 0.6) if k == "armor" else Color(0.9, 0.5, 0.15)), 0.5), "b": Mats.color(Color(0.95, 0.9, 0.7)), "r": Mats.emissive(Color(1, 0.25, 0.25), 2.0)})
		mesh.add_child(mi)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 0.8
	l.omni_range = 2.5
	add_child(l)


func _process(delta: float) -> void:
	_t += delta
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	mesh.rotation.y += delta * 2.0
	mesh.position.y = 0.35 + sin(_t * 3.0) * 0.08
	var p := Game.player
	if p and not p.dead and p.vehicle == null and p.global_position.distance_to(global_position) < 1.4:
		_collect(p)


func _collect(p: Player) -> void:
	match kind:
		"cash":
			Game.add_money(amount)
			Game.notify("+" + U.money_str(amount), "good")
		"armor":
			p.armor = 100.0
			Game.notify("Body armour", "good")
		"health":
			p.health = minf(p.health + 80.0, p.max_health)
		"parachute":
			p.give_parachute()
		_:
			if kind.begins_with("weapon:"):
				var id := kind.substr(7)
				var had := p.weapons.has(id)
				p.weapons.give(id, amount)
				Game.notify(("+ammo: " if had else "Picked up ") + str(WeaponDB.get_def(id).name), "good")
	Audio.play_ui("pickup")
	queue_free()
