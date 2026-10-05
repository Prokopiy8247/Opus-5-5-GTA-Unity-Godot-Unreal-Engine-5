class_name WeaponModels
## Weapon models (original generic designs). Grip at origin, barrel toward -Z.
## The Blender GLB at res://gta/generated/models/weapons/<id>.glb (body "<id>__Body", marker "<id>__Muzzle")
## is used when present; its wpn_* material slots are remapped so the tint/finish upgrades still apply.
## Attachments come from weapons/attachments.glb (ATT_<mod>, each centred on its mount anchor).
## The procedural builder below stays as a fallback for missing GLBs.

static var _scenes := {}
static var _att := {}
const _SLOT := {"wpn_metal": "m", "wpn_dark": "d", "wpn_wood": "w", "wpn_poly": "p", "wpn_accent": "a",
	"wpn_olive": "o", "wpn_glass": "g", "wpn_emit": "e"}


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]


static func _att_mesh(key: String) -> Mesh:
	if _att.is_empty():
		_att["_loaded"] = true
		var ps := _scene("res://gta/generated/models/weapons/attachments.glb")
		if ps:
			var inst := ps.instantiate()
			for n in inst.find_children("ATT_*", "MeshInstance3D", true, false):
				_att[String(n.name).substr(4)] = (n as MeshInstance3D).mesh
			inst.free()
	return _att.get(key, null)


static func _remap(mi: MeshInstance3D, mats: Dictionary) -> void:
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		if m and _SLOT.has(m.resource_name):
			mi.set_surface_override_material(i, mats[_SLOT[m.resource_name]])


## Position of a node relative to an ancestor (works before the scene enters the tree).
static func _pos_in(root: Node, n: Node3D) -> Vector3:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf.origin

static func build(id: String, mods := {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Weapon_" + id
	var tint_i: int = int(mods.get("tint_idx", 0))
	var body_col: Color = WeaponDB.TINTS[tint_i % WeaponDB.TINTS.size()]
	var metal := Mats.color(body_col, 0.4, 0.55)
	var dark := Mats.color(Color(0.08, 0.08, 0.09), 0.5, 0.3)
	var wood := Mats.color(Color(0.42, 0.26, 0.14), 0.7)
	var poly := Mats.color(Color(0.13, 0.13, 0.14), 0.75)
	var accent := Mats.color(Color(0.9, 0.55, 0.15), 0.5)
	var mats := {"m": metal, "d": dark, "w": wood, "p": poly, "a": accent, "o": Mats.color(Color(0.35, 0.4, 0.3), 0.7),
		"g": Mats.glass(Color(0.3, 0.6, 0.8, 0.6)), "e": Mats.emissive(Color(1, 0.95, 0.8), 3.0)}
	var muzzle_z := -0.3
	var muzzle_y := 0.05
	var glb := "res://gta/generated/models/weapons/%s.glb" % id
	var mb := MB.new()
	var ps := _scene(glb)
	if ps:
		var inst: Node3D = ps.instantiate()
		inst.name = "Body"
		root.add_child(inst)
		for n in inst.find_children("*", "MeshInstance3D", true, false):
			_remap(n as MeshInstance3D, mats)
		var mk := inst.find_child("*Muzzle", true, false) as Node3D
		if mk:
			var mp := _pos_in(inst, mk)
			muzzle_z = mp.z
			muzzle_y = mp.y
	else:
		match id:
			"fists":
				pass
			"knife":
				mb.use("p").col(Color.WHITE)
				mb.box(Vector3(0, 0.0, 0.0), Vector3(0.03, 0.035, 0.12), 0.008)
				mb.use("m").col(Color.WHITE)
				mb.box(Vector3(0, 0.0, -0.065), Vector3(0.05, 0.05, 0.012))
				mb.prism(Vector3(0, 0, -0.07), 0.0, Vector2.ZERO, Vector2.ZERO)
				mb.box(Vector3(0, 0.005, -0.15), Vector3(0.006, 0.035, 0.16))
			"bat":
				mb.use("a").col(Color.WHITE)
				mb.cylinder_axis(Vector3(0, 0, -0.35), Vector3(0, 0, -1), 0.022, 0.85, 8, true, 0.042)
				mb.use("p").col(Color.WHITE)
				mb.cylinder_axis(Vector3(0, 0, 0.05), Vector3(0, 0, -1), 0.02, 0.18, 8)
			"pistol":
				mb.use("m").col(Color.WHITE)
				mb.box(Vector3(0, 0.06, -0.06), Vector3(0.034, 0.04, 0.2), 0.006)
				mb.use("p").col(Color.WHITE)
				mb.box_xf(Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(0, -0.01, 0.01)), Vector3(0.032, 0.11, 0.045), 0.006)
				mb.box(Vector3(0, 0.025, -0.05), Vector3(0.008, 0.02, 0.04))
				muzzle_z = -0.17
				muzzle_y = 0.065
			"revolver":
				mb.use("m").col(Color.WHITE)
				mb.box(Vector3(0, 0.06, -0.03), Vector3(0.03, 0.045, 0.09), 0.005)
				mb.cylinder_axis(Vector3(0, 0.055, -0.04), Vector3(0, 0, -1), 0.024, 0.045, 8)
				mb.cylinder_axis(Vector3(0, 0.07, -0.15), Vector3(0, 0, -1), 0.011, 0.16, 6)
				mb.use("w").col(Color.WHITE)
				mb.box_xf(Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, -0.01, 0.02)), Vector3(0.03, 0.1, 0.04), 0.01)
				muzzle_z = -0.23
				muzzle_y = 0.07
			"smg":
				mb.use("m").col(Color.WHITE)
				mb.box(Vector3(0, 0.06, -0.08), Vector3(0.045, 0.07, 0.28), 0.008)
				mb.use("d").col(Color.WHITE)
				mb.cylinder_axis(Vector3(0, 0.07, -0.26), Vector3(0, 0, -1), 0.012, 0.08, 6)
				mb.box(Vector3(0, -0.04, -0.12), Vector3(0.03, 0.14, 0.035))
				mb.use("p").col(Color.WHITE)
				mb.box_xf(Transform3D(Basis(Vector3.RIGHT, 0.2), Vector3(0, -0.01, 0.0)), Vector3(0.032, 0.1, 0.04), 0.006)
				mb.box(Vector3(0, 0.06, 0.12), Vector3(0.02, 0.03, 0.14))
				muzzle_z = -0.3
				muzzle_y = 0.07
			"shotgun", "autoshotgun":
				var auto := id == "autoshotgun"
				mb.use("m").col(Color.WHITE)
				mb.box(Vector3(0, 0.06, -0.05), Vector3(0.05, 0.075, 0.24 if auto else 0.18), 0.01)
				mb.use("d").col(Color.WHITE)
				mb.cylinder_axis(Vector3(0, 0.08, -0.42), Vector3(0, 0, -1), 0.018, 0.6, 8)
				mb.cylinder_axis(Vector3(0, 0.045, -0.36), Vector3(0, 0, -1), 0.015, 0.45, 8)
				mb.use("w" if not auto else "p").col(Color.WHITE)
				mb.box(Vector3(0, 0.045, -0.36), Vector3(0.045, 0.045, 0.16), 0.01)
				mb.box_xf(Transform3D(Basis(Vector3.RIGHT, -0.12), Vector3(0, 0.03, 0.2)), Vector3(0.045, 0.08, 0.3), 0.012)
				mb.box_xf(Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, -0.015, 0.02)), Vector3(0.035, 0.09, 0.045), 0.008)
				if auto:
					mb.use("p").col(Color.WHITE)
					mb.cylinder_axis(Vector3(0, -0.03, -0.1), Vector3(1, 0, 0), 0.07, 0.06, 10)
				muzzle_z = -0.72
				muzzle_y = 0.08
			"rifle", "carbine", "dmr":
				var len_k := 1.0 if id == "rifle" else (0.85 if id == "carbine" else 1.2)
				mb.use("m").col(Color.WHITE)
				mb.box(Vector3(0, 0.07, -0.08), Vector3(0.05, 0.08, 0.3), 0.01)
				mb.use("p").col(Color.WHITE)
				mb.box(Vector3(0, 0.075, -0.32 * len_k), Vector3(0.055, 0.06, 0.24 * len_k), 0.012)
				mb.use("d").col(Color.WHITE)
				mb.cylinder_axis(Vector3(0, 0.075, -0.5 * len_k), Vector3(0, 0, -1), 0.012, 0.3 * len_k, 6)
				mb.box(Vector3(0, 0.115, -0.1), Vector3(0.03, 0.012, 0.32))
				mb.use("p").col(Color.WHITE)
				mb.box_xf(Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0, -0.02, -0.14)), Vector3(0.03, 0.15, 0.06), 0.008)
				mb.box_xf(Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, -0.01, 0.0)), Vector3(0.035, 0.09, 0.04), 0.008)
				mb.box(Vector3(0, 0.05, 0.2), Vector3(0.045, 0.08, 0.26), 0.012)
				if id == "dmr":
					mb.use("w").col(Color.WHITE)
					mb.box(Vector3(0, 0.05, 0.2), Vector3(0.05, 0.085, 0.27), 0.012)
				muzzle_z = -0.65 * len_k
				muzzle_y = 0.075
			"sniper":
				mb.use("m").col(Color.WHITE)
				mb.box(Vector3(0, 0.07, -0.05), Vector3(0.055, 0.08, 0.36), 0.01)
				mb.use("d").col(Color.WHITE)
				mb.cylinder_axis(Vector3(0, 0.075, -0.6), Vector3(0, 0, -1), 0.02, 0.62, 8, true, 0.016)
				mb.box(Vector3(0, 0.075, -0.93), Vector3(0.05, 0.03, 0.06))
				mb.use("p").col(Color.WHITE)
				mb.box(Vector3(0, 0.05, 0.24), Vector3(0.05, 0.1, 0.3), 0.015)
				mb.box(Vector3(0, -0.06, -0.02), Vector3(0.03, 0.1, 0.06))
				mb.box_xf(Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, -0.01, 0.06)), Vector3(0.035, 0.09, 0.04), 0.008)
				for s in [-1.0, 1.0]:
					mb.box_xf(Transform3D(Basis(Vector3.FORWARD, s * 0.35), Vector3(s * 0.04, -0.05, -0.62)), Vector3(0.012, 0.18, 0.012))
				muzzle_z = -0.97
				muzzle_y = 0.075
			"rpg":
				mb.use("p").col(Color(0.35, 0.4, 0.3))
				mb.cylinder_axis(Vector3(0, 0.12, -0.15), Vector3(0, 0, -1), 0.055, 1.1, 10)
				mb.use("a").col(Color.WHITE)
				mb.cylinder_axis(Vector3(0, 0.12, -0.78), Vector3(0, 0, -1), 0.05, 0.16, 8, true, 0.0)
				mb.use("p").col(Color.WHITE)
				mb.box(Vector3(0, 0.02, 0.0), Vector3(0.03, 0.12, 0.04))
				mb.box(Vector3(0, 0.02, -0.25), Vector3(0.03, 0.12, 0.04))
				mb.box(Vector3(-0.07, 0.16, -0.1), Vector3(0.04, 0.05, 0.12))
				muzzle_z = -0.85
				muzzle_y = 0.12
			"gl":
				mb.use("m").col(Color.WHITE)
				mb.cylinder_axis(Vector3(0, 0.07, -0.12), Vector3(0, 0, -1), 0.065, 0.14, 10)
				mb.use("d").col(Color.WHITE)
				mb.cylinder_axis(Vector3(0, 0.08, -0.36), Vector3(0, 0, -1), 0.03, 0.36, 8)
				mb.use("p").col(Color.WHITE)
				mb.box(Vector3(0, 0.05, 0.15), Vector3(0.04, 0.07, 0.22), 0.01)
				mb.box_xf(Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, -0.01, 0.02)), Vector3(0.035, 0.09, 0.04), 0.008)
				muzzle_z = -0.55
				muzzle_y = 0.08
			"grenade":
				mb.use("p").col(Color(0.3, 0.38, 0.25))
				mb.sphere(Vector3(0, 0.0, -0.02), 0.04, 8, 5, Vector3(1, 1.2, 1))
				mb.use("m").col(Color.WHITE)
				mb.box(Vector3(0, 0.05, -0.02), Vector3(0.02, 0.025, 0.02))
				muzzle_z = -0.02
	if not mb.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "Body"
		mi.mesh = mb.commit(mats)
		root.add_child(mi)
	_add_mods(root, id, mods, muzzle_z, muzzle_y, mats)
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	var extra := 0.22 if mods.get("suppressor", false) else 0.0
	muzzle.position = Vector3(0, muzzle_y, muzzle_z - extra)
	root.add_child(muzzle)
	return root


static func _att_part(root: Node3D, key: String, pos: Vector3, mats: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Att_" + key
	mi.mesh = _att_mesh(key)
	mi.position = pos
	root.add_child(mi)
	_remap(mi, mats)


static func _add_mods(root: Node3D, id: String, mods: Dictionary, mz: float, my: float, mats: Dictionary) -> void:
	var scoped_glb: bool = mods.get("scope", false) or id in ["sniper", "dmr"]
	if _att_mesh("suppressor") != null:
		if mods.get("suppressor", false):
			_att_part(root, "suppressor", Vector3(0, my, mz - 0.11), mats)
		if scoped_glb:
			_att_part(root, "scope_big" if id == "sniper" else "scope", Vector3(0, my, -0.04), mats)
		if mods.get("grip", false):
			_att_part(root, "grip", Vector3(0, my - 0.07, mz * 0.6), mats)
		if mods.get("extmag", false):
			_att_part(root, "extmag", Vector3(0, -0.09, -0.12), mats)
		if mods.get("flashlight", false):
			_att_part(root, "flashlight", Vector3(0, my - 0.04, mz * 0.55), mats)
			_add_flash_light(root, mz, my)
		return
	var mb := MB.new()
	if mods.get("suppressor", false):
		mb.use("d").col(Color.WHITE)
		mb.cylinder_axis(Vector3(0, my, mz - 0.11), Vector3(0, 0, -1), 0.022, 0.22, 8)
	var scoped: bool = mods.get("scope", false) or id in ["sniper", "dmr"]
	if scoped:
		mb.use("d").col(Color.WHITE)
		var big := id == "sniper"
		mb.cylinder_axis(Vector3(0, my + 0.07, -0.08), Vector3(0, 0, -1), 0.026 if not big else 0.032, 0.24 if not big else 0.3, 8)
		mb.box(Vector3(0, my + 0.035, -0.08), Vector3(0.02, 0.04, 0.03))
		mb.use("g").col(Color.WHITE)
		mb.cylinder_axis(Vector3(0, my + 0.07, -0.205), Vector3(0, 0, -1), 0.024, 0.01, 8)
	if mods.get("grip", false):
		mb.use("p").col(Color.WHITE)
		mb.box(Vector3(0, my - 0.07, mz * 0.6), Vector3(0.025, 0.08, 0.03))
	if mods.get("extmag", false):
		mb.use("p").col(Color.WHITE)
		mb.box(Vector3(0, -0.09, -0.12), Vector3(0.028, 0.1, 0.04))
	if not mb.is_empty():
		var mi := MeshInstance3D.new()
		mi.name = "Mods"
		mi.mesh = mb.commit(mats)
		root.add_child(mi)
	if mods.get("flashlight", false):
		var fl := MB.new()
		fl.use("d").col(Color.WHITE)
		fl.cylinder_axis(Vector3(0.0, my - 0.04, mz * 0.55), Vector3(0, 0, -1), 0.018, 0.08, 8)
		fl.use("e").col(Color.WHITE)
		fl.cylinder_axis(Vector3(0.0, my - 0.04, mz * 0.55 - 0.041), Vector3(0, 0, -1), 0.016, 0.004, 8)
		var fmi := MeshInstance3D.new()
		fmi.mesh = fl.commit(mats)
		root.add_child(fmi)
		_add_flash_light(root, mz, my)


static func _add_flash_light(root: Node3D, mz: float, my: float) -> void:
	var spot := SpotLight3D.new()
	spot.name = "Flashlight"
	spot.position = Vector3(0, my - 0.04, mz * 0.55 - 0.05)
	spot.spot_range = 38.0
	spot.spot_angle = 22.0
	spot.light_energy = 0.0
	spot.light_color = Color(1.0, 0.97, 0.9)
	spot.shadow_enabled = true
	root.add_child(spot)
