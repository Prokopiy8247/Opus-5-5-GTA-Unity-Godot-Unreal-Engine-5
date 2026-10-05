class_name VehicleVisuals
## Procedural vehicle models. Builds a node tree with named parts used by gameplay:
## Body(paint) / Trim / Glass / Lights_Head / Lights_Tail / Lights_Reverse / Wheel_* / Rotor / TailRotor / Prop / Seat_* / Door_*.
## Blender GLBs at res://gta/generated/models/vehicles/<id>.glb replace the visible meshes: the procedural
## build still runs for the gameplay metadata (wheel pivots, seats, head-light points, half extents), then
## the Blender body, mod parts (<id>__Mod_<key>_<value>), steering wheel, rotors and props are swapped in
## and their material slots are remapped by name so paint, tint, lights and rims stay customisable.

class Result:
	var root: Node3D
	var paint: StandardMaterial3D
	var paint2: StandardMaterial3D
	var glass: StandardMaterial3D
	var head_mat: StandardMaterial3D
	var tail_mat: StandardMaterial3D
	var rev_mat: StandardMaterial3D
	var bar_red: StandardMaterial3D
	var bar_blue: StandardMaterial3D
	var rim_mat: StandardMaterial3D
	var wheels: Array = []        # [{node, pos, radius, steer, drive, side}]
	var seats: Array = []         # [{pos, door}]
	var head_points: Array = []   # local positions for headlight spots
	var rotor: Node3D
	var tail_rotor: Node3D
	var prop: Node3D
	var steering: Node3D
	var half_extents := Vector3.ONE
	var mod_parts := {}


static func build(id: String, def: Dictionary, mods: Dictionary) -> Result:
	var r := Result.new()
	r.root = Node3D.new()
	r.root.name = "Visual"
	var paint_c: Color = mods.get("paint", def.get("color", Color.WHITE))
	r.paint = Mats.unique(paint_c, 0.28, 0.25)
	r.paint.metallic_specular = 0.7
	_apply_finish(r.paint, mods.get("finish", "gloss"))
	r.paint2 = Mats.unique(mods.get("paint2", paint_c.darkened(0.35)), 0.35, 0.2)
	r.glass = Mats.unique(Color(0.07, 0.09, 0.12, 0.7 + 0.28 * float(mods.get("tint", 0)) / 3.0), 0.05, 0.4)
	r.glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	r.head_mat = Mats.unique(Color(1, 0.97, 0.88), 0.2)
	r.head_mat.emission_enabled = true
	r.head_mat.emission = mods.get("light_color", Color(1, 0.95, 0.85))
	r.head_mat.emission_energy_multiplier = 0.3
	r.tail_mat = Mats.unique(Color(0.6, 0.05, 0.05), 0.3)
	r.tail_mat.emission_enabled = true
	r.tail_mat.emission = Color(1, 0.08, 0.05)
	r.tail_mat.emission_energy_multiplier = 0.4
	r.rev_mat = Mats.unique(Color(0.85, 0.85, 0.85), 0.3)
	r.rev_mat.emission_enabled = true
	r.rev_mat.emission = Color(1, 1, 1)
	r.rev_mat.emission_energy_multiplier = 0.0
	r.bar_red = Mats.unique(Color(0.5, 0.05, 0.05), 0.3)
	r.bar_red.emission_enabled = true
	r.bar_red.emission = Color(1, 0.1, 0.1)
	r.bar_red.emission_energy_multiplier = 0.2
	r.bar_blue = Mats.unique(Color(0.05, 0.1, 0.5), 0.3)
	r.bar_blue.emission_enabled = true
	r.bar_blue.emission = Color(0.15, 0.35, 1.0)
	r.bar_blue.emission_energy_multiplier = 0.2
	r.rim_mat = Mats.unique(mods.get("rim_color", Color(0.75, 0.76, 0.78)), 0.25, 0.85)
	match def.kind:
		"car":
			_car(r, def, mods)
		"bike", "bicycle":
			_bike(r, def, mods)
		"boat":
			_boat(r, def, mods)
		"heli":
			_heli(r, def, mods)
		"plane":
			_plane(r, def, mods)
	var glb := "res://gta/generated/models/vehicles/%s.glb" % id
	if ResourceLoader.exists(glb):
		_apply_glb(r, glb, def, mods)
	return r


static func _apply_finish(m: StandardMaterial3D, finish: String) -> void:
	match finish:
		"matte":
			m.roughness = 0.75
			m.metallic = 0.0
			m.clearcoat_enabled = false
		"metallic":
			m.roughness = 0.22
			m.metallic = 0.75
			m.clearcoat_enabled = true
			m.clearcoat = 0.6
		"chrome":
			m.roughness = 0.05
			m.metallic = 1.0
		_:
			m.roughness = 0.2
			m.metallic = 0.15
			m.clearcoat_enabled = true
			m.clearcoat = 0.8
			m.clearcoat_roughness = 0.1


## Rebuilds gameplay parts from a Blender-authored GLB. Node names in the file are the contract:
## root + Body, Wheel_*, Seat_*, Rotor, TailRotor, Prop, Steering, Mod_<category>_<index>.
static var _scenes := {}
static var _rims: Array = []
static var STEER_AXIS := Vector3(0.0, 0.45, 1.0).normalized()


static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


## Blender rim set (vehicles/wheels.glb): unit wheels (radius 1, width 1) for rim styles 0..3.
static func rim_mesh(style: int) -> Mesh:
	if _rims.is_empty():
		var path := "res://gta/generated/models/vehicles/wheels.glb"
		if not ResourceLoader.exists(path):
			return null
		var inst := _scene(path).instantiate()
		for k in 4:
			var n := inst.find_child("WHEEL_rim%d" % k, true, false) as MeshInstance3D
			_rims.append(n.mesh if n else null)
		inst.free()
	return _rims[clampi(style, 0, 3)]


static func _apply_glb(r: Result, path: String, def: Dictionary, mods: Dictionary) -> void:
	var inst: Node3D = _scene(path).instantiate()
	var old_body := r.root.get_node_or_null("Body")
	if old_body:
		r.root.remove_child(old_body)
		old_body.free()
	r.root.add_child(inst)
	var defaults := {"spoiler": 1 if def.get("spoiler", false) else 0, "hood": 1 if def.get("scoop", false) else 0,
		"roof": 1 if def.get("rack", false) else 0, "livery": 1 if def.get("stripes", false) else 0}
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nm := String(mi.name)
		var role := nm.get_slice("__", 1) if nm.contains("__") else nm
		_remap_materials(mi, r, mods)
		if role.begins_with("Mod_"):
			var kv := role.substr(4).rsplit("_", true, 1)
			if kv.size() == 2:
				mi.visible = int(mods.get(kv[0], defaults.get(kv[0], 0))) == int(kv[1])
				r.mod_parts[role] = mi
		elif role == "Steering":
			r.steering = mi
		elif role in ["Rotor", "TailRotor", "Prop"]:
			var pivot: Node3D = r.rotor if role == "Rotor" else (r.tail_rotor if role == "TailRotor" else r.prop)
			if pivot:
				for c in pivot.get_children():
					pivot.remove_child(c)
					c.free()
				mi.get_parent().remove_child(mi)
				pivot.add_child(mi)
				mi.transform = Transform3D.IDENTITY
	# wheels: Blender rim set at the procedural pivots (the Spin node keeps the gameplay rotation)
	var style := int(mods.get("rims", 2 if def.kind == "bicycle" else (3 if def.kind == "plane" else 0)))
	var rm := rim_mesh(style)
	if rm:
		for w in r.wheels:
			var sp: Node3D = w.get("spin")
			var tire := sp.get_node_or_null("Tire") as MeshInstance3D if sp else null
			if tire:
				tire.mesh = rm
				tire.scale = Vector3(float(w.get("width", 0.24)), float(w.radius), float(w.radius))
				_remap_materials(tire, r, mods)


static func _remap_materials(mi: MeshInstance3D, r: Result, mods: Dictionary) -> void:
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		if m == null:
			continue
		var rep: Material = null
		match m.resource_name.get_slice("__", 0):
			"paint": rep = r.paint
			"paint2": rep = r.paint2
			"glass": rep = r.glass
			"head": rep = r.head_mat
			"tail": rep = r.tail_mat
			"rev": rep = r.rev_mat
			"bar_red": rep = r.bar_red
			"bar_blue": rep = r.bar_blue
			"rim": rep = r.rim_mat
			"plate": rep = Mats.color([Color(0.95, 0.95, 0.9), Color(0.1, 0.12, 0.3), Color(0.95, 0.8, 0.2)][int(mods.get("plate", 0)) % 3], 0.4)
			"stripe": rep = Mats.color(mods.get("stripe_color", Color(0.95, 0.95, 0.95)), 0.3)
		mi.set_surface_override_material(i, rep)


static func _mi(parent: Node3D, mesh: Mesh, name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


static func _wheel_mesh(radius: float, width: float, r: Result, rim_style: int) -> ArrayMesh:
	var mb := MB.new()
	mb.use("tire").col(Color.WHITE)
	mb.cylinder_axis(Vector3.ZERO, Vector3.RIGHT, radius, width, 14)
	mb.use("rim").col(Color.WHITE)
	var rr := radius * 0.62
	mb.cylinder_axis(Vector3(width * 0.5 + 0.005, 0, 0), Vector3.RIGHT, rr, 0.02, 14)
	mb.cylinder_axis(Vector3(-width * 0.5 - 0.005, 0, 0), Vector3.RIGHT, rr, 0.02, 14)
	var spokes: int = [5, 6, 10, 3][rim_style % 4]
	for k in spokes:
		var a := TAU * k / spokes
		var xf := Transform3D(Basis(Vector3.RIGHT, a), Vector3(width * 0.5 + 0.02, 0, 0))
		mb.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(0, rr * 0.5, 0)), Vector3(0.025, rr, 0.05 if rim_style != 2 else 0.025))
	mb.use("hub").col(Color.WHITE)
	mb.cylinder_axis(Vector3(width * 0.5 + 0.03, 0, 0), Vector3.RIGHT, radius * 0.16, 0.04, 8)
	return mb.commit({"tire": Mats.color(Color(0.07, 0.07, 0.08), 0.9), "rim": r.rim_mat, "hub": Mats.color(Color(0.3, 0.3, 0.32), 0.4, 0.8)})


static func _add_wheel(r: Result, pos: Vector3, radius: float, width: float, steer: bool, drive: bool, rim_style: int) -> void:
	var n := Node3D.new()
	n.name = "Wheel_%d" % r.wheels.size()
	n.position = pos
	r.root.add_child(n)
	var spin := Node3D.new()
	spin.name = "Spin"
	n.add_child(spin)
	_mi(spin, _wheel_mesh(radius, width, r, rim_style), "Tire")
	r.wheels.append({"node": n, "spin": spin, "pos": pos, "radius": radius, "width": width, "steer": steer, "drive": drive, "side": signf(pos.x)})


# ------------------------------------------------------------------ cars

static func _car(r: Result, def: Dictionary, mods: Dictionary) -> void:
	var b: Array = def.body
	var L: float = b[0]
	var W: float = b[1]
	var belt: float = b[2]
	var roof: float = b[3]
	var clr: float = b[4]
	var hood: float = b[5]
	var deck: float = b[6]
	var ws_slope: float = b[7]
	var rear_slope: float = b[8]
	var nose_drop: float = b[9]
	var style: String = def.get("style", "sedan")
	var hw := W * 0.5
	var zf := -L * 0.5
	var zr := L * 0.5
	var wr: float = def.wheel_r
	var mb := MB.new()
	# ---- lower body loft (front -> rear). sections: chamfered rectangles
	var stations := []
	var z_ws := zf + hood
	var z_cab_end := zr - deck
	var bottom := clr + 0.05
	stations.append([zf, bottom + 0.12, belt - nose_drop - 0.12, hw - 0.12])
	stations.append([zf + 0.12, bottom, belt - nose_drop, hw - 0.04])
	stations.append([zf + hood * 0.5, bottom, belt - nose_drop * 0.4, hw])
	stations.append([z_ws, bottom, belt, hw])
	stations.append([z_cab_end, bottom, belt, hw])
	if style in ["sedan", "fastback"]:
		stations.append([zr - 0.12, bottom, belt - 0.03, hw - 0.04])
		stations.append([zr, bottom + 0.12, belt - 0.15, hw - 0.12])
	else:
		stations.append([zr - 0.08, bottom, belt, hw - 0.03])
		stations.append([zr, bottom + 0.1, belt - 0.08, hw - 0.1])
	var secs := []
	for st in stations:
		secs.append(_section(st[0], st[1], st[2], st[3], 0.1))
	mb.use("paint").col(Color.WHITE)
	mb.loft(secs, true, true)
	# wheel arch shadows (dark boxes)
	mb.use("trim").col(Color.WHITE)
	var wb: float = def.wheelbase
	var tr: float = def.track
	for zz in [-wb * 0.5, wb * 0.5]:
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(sx * (hw - 0.02), wr + clr * 0.2, zz), Vector3(0.05, wr * 1.5, wr * 2.3))
	# lower trim, bumpers
	var bump: int = int(mods.get("bumper", 0))
	mb.box(Vector3(0, bottom + 0.12, zf - 0.02), Vector3(W - 0.1, 0.22 + bump * 0.05, 0.12 + bump * 0.06))
	mb.box(Vector3(0, bottom + 0.12, zr + 0.02), Vector3(W - 0.1, 0.22, 0.12))
	if bump >= 2:
		mb.box(Vector3(0, bottom + 0.02, zf - 0.12), Vector3(W - 0.3, 0.06, 0.25))   # splitter
	if int(mods.get("skirts", 0)) > 0:
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(sx * (hw + 0.02), bottom + 0.06, 0), Vector3(0.08, 0.12, wb - wr * 1.6))
	# grille
	var grille: int = int(mods.get("grille", 0))
	mb.box(Vector3(0, (bottom + belt - nose_drop) * 0.5 + 0.05, zf - 0.005), Vector3(W * (0.45 + grille * 0.1), 0.18 + grille * 0.04, 0.03))
	# ---- cabin / greenhouse
	var cab := []
	match style:
		"hatch":
			cab = [[z_ws, 0.0], [z_ws + ws_slope, 1.0], [zr - 0.35, 1.0], [zr - 0.1, 0.25]]
		"sedan":
			cab = [[z_ws, 0.0], [z_ws + ws_slope, 1.0], [z_cab_end - rear_slope, 1.0], [z_cab_end, 0.0]]
		"fastback":
			cab = [[z_ws, 0.0], [z_ws + ws_slope, 1.0], [z_ws + ws_slope + 0.7, 1.0], [z_cab_end, 0.0]]
		"wagon":
			cab = [[z_ws, 0.0], [z_ws + ws_slope, 1.0], [zr - 0.25, 1.0], [zr - 0.1, 0.7]]
		"pickup":
			cab = [[z_ws, 0.0], [z_ws + ws_slope, 1.0], [z_ws + ws_slope + 1.0, 1.0], [z_ws + ws_slope + 1.15, 0.0]]
		"van", "box", "truck", "armored":
			cab = [[z_ws, 0.0], [z_ws + ws_slope, 1.0], [zr - 0.1, 1.0], [zr - 0.05, 1.0]]
	var rhw := hw - 0.16
	var csecs := []
	for c in cab:
		var z: float = c[0]
		var k: float = c[1]
		var top := belt + (roof - belt) * k
		csecs.append(_cabin_section(z, belt - 0.02, top, hw - 0.08, rhw))
	var is_boxy := style in ["van", "box", "truck", "armored"]
	if is_boxy:
		# boxy rear body painted, only front glass
		mb.use("paint").col(Color.WHITE)
		var box_start := z_ws + ws_slope + (0.9 if style in ["box", "truck"] else 0.0)
		if style in ["box", "truck"]:
			# separate cab + cargo box
			mb.use("glass").col(Color.WHITE)
			mb.loft([csecs[0], csecs[1], _cabin_section(box_start - 0.05, belt - 0.02, roof - 0.15, hw - 0.08, rhw), _cabin_section(box_start, belt - 0.02, belt + 0.05, hw - 0.08, rhw)], true, true)
			mb.use("paint2" if style == "truck" else "paint").col(Color.WHITE)
			mb.box(Vector3(0, (belt + roof + 0.25) * 0.5 + 0.05, (box_start + zr) * 0.5 + 0.05), Vector3(W + 0.06, roof + 0.25 - belt + 0.1, zr - box_start + 0.1))
		else:
			mb.use("glass").col(Color.WHITE)
			mb.loft([csecs[0], csecs[1], _cabin_section(z_ws + ws_slope + 0.6, belt - 0.02, roof, hw - 0.08, rhw)], true, false)
			mb.use("paint").col(Color.WHITE)
			mb.prism(Vector3(0, belt - 0.02, (z_ws + ws_slope + 0.6 + zr) * 0.5), roof - belt + 0.02, Vector2(hw - 0.04, (zr - z_ws - ws_slope - 0.6) * 0.5), Vector2(rhw + 0.04, (zr - z_ws - ws_slope - 0.6) * 0.5), 0.06)
			# side windows on van/armored
			mb.use("glass").col(Color.WHITE)
			for sx in [-1.0, 1.0]:
				mb.box(Vector3(sx * (hw - 0.03), (belt + roof) * 0.5 + 0.08, z_ws + ws_slope + 0.9), Vector3(0.02, (roof - belt) * 0.5, 0.9))
	else:
		mb.use("glass").col(Color.WHITE)
		mb.loft(csecs, true, true)
		# roof panel (paint) + pillars
		mb.use("paint").col(Color.WHITE)
		var rz0: float = cab[1][0]
		var rz1: float = cab[2][0]
		mb.box(Vector3(0, roof + 0.015, (rz0 + rz1) * 0.5), Vector3(rhw * 2.0 + 0.04, 0.05, rz1 - rz0 + 0.04))
		for c2 in [cab[0], cab[cab.size() - 1]]:
			var zc: float = c2[0]
			for sx in [-1.0, 1.0]:
				var top_z: float = rz0 if zc < 0 else rz1
				var p0 := Vector3(sx * (hw - 0.1), belt, zc)
				var p1 := Vector3(sx * (rhw - 0.02), roof, top_z)
				var mid := (p0 + p1) * 0.5
				var dirv := (p1 - p0).normalized()
				var bs := Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK)
				var up := dirv
				var side := Vector3.RIGHT
				var fwd := side.cross(up).normalized()
				bs = Basis(side, up, fwd).orthonormalized()
				mb.box_xf(Transform3D(bs, mid), Vector3(0.07, p0.distance_to(p1), 0.09))
		# B pillar
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(sx * (hw - 0.12), (belt + roof) * 0.5, (rz0 + rz1) * 0.5 + 0.1), Vector3(0.06, roof - belt, 0.08))
	if style == "pickup":
		# bed walls
		var bz0 := z_ws + ws_slope + 1.15
		mb.use("paint").col(Color.WHITE)
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(sx * (hw - 0.06), belt + 0.2, (bz0 + zr) * 0.5), Vector3(0.1, 0.42, zr - bz0))
		mb.box(Vector3(0, belt + 0.2, zr - 0.05), Vector3(W - 0.1, 0.42, 0.1))
		mb.use("trim").col(Color.WHITE)
		mb.box(Vector3(0, belt + 0.01, (bz0 + zr) * 0.5), Vector3(W - 0.25, 0.02, zr - bz0 - 0.1))
	# ---- lights
	var ly := belt - nose_drop - 0.14
	for sx in [-1.0, 1.0]:
		mb.use("head").col(Color.WHITE)
		mb.box(Vector3(sx * (hw - 0.26), ly, zf + 0.04), Vector3(0.36, 0.12, 0.06))
		r.head_points.append(Vector3(sx * (hw - 0.26), ly, zf - 0.05))
		mb.use("tail").col(Color.WHITE)
		mb.box(Vector3(sx * (hw - 0.24), belt - 0.16, zr - 0.02), Vector3(0.34, 0.13, 0.06))
		mb.use("rev").col(Color.WHITE)
		mb.box(Vector3(sx * (hw - 0.5), belt - 0.16, zr - 0.02), Vector3(0.12, 0.08, 0.065))
	# ---- extras
	if def.get("lightbar", false):
		var by := roof + 0.06
		var bz: float = (cab[1][0] + cab[2][0]) * 0.5 if not is_boxy else z_ws + ws_slope + 0.3
		mb.use("trim").col(Color.WHITE)
		mb.box(Vector3(0, by, bz), Vector3(W * 0.62, 0.06, 0.28))
		mb.use("bar_red").col(Color.WHITE)
		mb.box(Vector3(-W * 0.17, by + 0.07, bz), Vector3(W * 0.28, 0.1, 0.24))
		mb.use("bar_blue").col(Color.WHITE)
		mb.box(Vector3(W * 0.17, by + 0.07, bz), Vector3(W * 0.28, 0.1, 0.24))
		mb.use("trim").col(Color.WHITE)
		mb.box(Vector3(0, bottom + 0.2, zf - 0.12), Vector3(W * 0.6, 0.3, 0.08))   # push bar
	if def.get("taxisign", false):
		mb.use("head").col(Color.WHITE)
		mb.box(Vector3(0, roof + 0.12, (cab[1][0] + cab[2][0]) * 0.5), Vector3(0.6, 0.18, 0.22))
	var livery: String = def.get("livery", "")
	if livery == "police":
		mb.use("livery").col(Color.WHITE)
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(sx * (hw + 0.005), (bottom + belt) * 0.5 + 0.05, (z_ws + z_cab_end) * 0.5), Vector3(0.01, belt - bottom - 0.12, z_cab_end - z_ws + 0.4))
	elif livery == "medic":
		mb.use("stripe_red").col(Color.WHITE)
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(sx * (hw + 0.035), belt + 0.25, 0.3), Vector3(0.01, 0.22, L * 0.7))
	elif livery == "checker":
		mb.use("trim").col(Color.WHITE)
		for sx in [-1.0, 1.0]:
			for k in 10:
				mb.box(Vector3(sx * (hw + 0.005), belt - 0.08, z_ws + k * 0.3), Vector3(0.01, 0.1, 0.15))
	if def.get("stripes", false) or int(mods.get("livery", 0)) > 0:
		mb.use("stripe").col(Color.WHITE)
		mb.box(Vector3(-0.22, belt + 0.002, (zf + z_ws) * 0.5), Vector3(0.18, 0.01, hood))
		mb.box(Vector3(0.22, belt + 0.002, (zf + z_ws) * 0.5), Vector3(0.18, 0.01, hood))
		if not is_boxy:
			mb.box(Vector3(-0.22, roof + 0.045, (cab[1][0] + cab[2][0]) * 0.5), Vector3(0.18, 0.01, cab[2][0] - cab[1][0]))
			mb.box(Vector3(0.22, roof + 0.045, (cab[1][0] + cab[2][0]) * 0.5), Vector3(0.18, 0.01, cab[2][0] - cab[1][0]))
	var hood_mod: int = int(mods.get("hood", 1 if def.get("scoop", false) else 0))
	if hood_mod > 0:
		mb.use("paint" if hood_mod == 1 else "trim").col(Color.WHITE)
		mb.prism(Vector3(0, belt - nose_drop * 0.3, (zf + z_ws) * 0.5 + 0.1), 0.12, Vector2(0.32, 0.5), Vector2(0.22, 0.35), 0.03)
	var spoiler: int = int(mods.get("spoiler", 1 if def.get("spoiler", false) else 0))
	if spoiler > 0 and not is_boxy and style != "pickup":
		mb.use("paint" if spoiler == 1 else "trim").col(Color.WHITE)
		var sh := 0.12 + spoiler * 0.12
		var sz := zr - 0.22
		mb.box(Vector3(0, belt + sh + 0.02, sz), Vector3(W * 0.88, 0.05, 0.32))
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(sx * W * 0.3, belt + sh * 0.5, sz), Vector3(0.05, sh, 0.12))
	var exhaust: int = int(mods.get("exhaust", 0))
	mb.use("chrome").col(Color.WHITE)
	var pipes: int = [1, 2, 4][exhaust % 3]
	for k in pipes:
		var x: float = -hw + 0.35 + k * 0.14 if pipes < 4 else (-hw + 0.35 + (k % 2) * 0.14) * (1.0 if k < 2 else -1.0)
		mb.cylinder_axis(Vector3(x, bottom + 0.08, zr + 0.05), Vector3(0, 0, 1), 0.04 + exhaust * 0.01, 0.2, 8)
	if def.get("rack", false) or int(mods.get("roof", 0)) == 1:
		mb.use("trim").col(Color.WHITE)
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(sx * (rhw - 0.05), roof + 0.1, (cab[1][0] + cab[2][0]) * 0.5), Vector3(0.05, 0.05, cab[2][0] - cab[1][0]))
	if def.get("ladder", false):
		mb.use("chrome").col(Color.WHITE)
		for sx in [-0.4, 0.4]:
			mb.box(Vector3(sx, roof + 0.4, 0.8), Vector3(0.08, 0.08, L * 0.7))
		for k in 14:
			mb.box(Vector3(0, roof + 0.4, -1.5 + k * 0.4), Vector3(0.8, 0.05, 0.05))
	if style == "armored":
		mb.use("trim").col(Color.WHITE)
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(sx * (hw + 0.03), belt + 0.1, 0.0), Vector3(0.06, 0.12, L * 0.85))
	var plate: int = int(mods.get("plate", 0))
	mb.use("plate%d" % (plate % 3)).col(Color.WHITE)
	mb.box(Vector3(0, bottom + 0.24, zr + 0.06), Vector3(0.52, 0.12, 0.02))
	var mats := {"paint": r.paint, "paint2": r.paint2, "glass": r.glass, "trim": Mats.color(Color(0.08, 0.08, 0.09), 0.6),
		"head": r.head_mat, "tail": r.tail_mat, "rev": r.rev_mat, "bar_red": r.bar_red, "bar_blue": r.bar_blue,
		"livery": Mats.color(Color(0.95, 0.95, 0.95), 0.3), "stripe_red": Mats.color(Color(0.9, 0.15, 0.12), 0.4),
		"stripe": Mats.color(mods.get("stripe_color", Color(0.95, 0.95, 0.95)), 0.3), "chrome": Mats.color(Color(0.8, 0.8, 0.82), 0.1, 1.0),
		"plate0": Mats.color(Color(0.95, 0.95, 0.9), 0.4), "plate1": Mats.color(Color(0.1, 0.12, 0.3), 0.4), "plate2": Mats.color(Color(0.95, 0.8, 0.2), 0.4)}
	var body := _mi(r.root, mb.commit(mats), "Body")
	body.position.y = 0.0
	# wheels
	var rim_style: int = int(mods.get("rims", 0))
	var wwidth := 0.24 if L < 5.5 else 0.32
	for zz in [-wb * 0.5, wb * 0.5]:
		for sx in [-1.0, 1.0]:
			_add_wheel(r, Vector3(sx * tr * 0.5, wr, zz), wr, wwidth, zz < 0.0, zz > 0.0 or def.get("awd", false), rim_style)
	# seats (driver on the left)
	var seat_y := belt - 0.55
	var sz0 := z_ws + ws_slope + 0.45
	r.seats.append({"pos": Vector3(-hw * 0.42, seat_y, sz0), "door": Vector3(-hw - 0.75, 0.0, sz0 - 0.2)})
	if int(def.seats) >= 2:
		r.seats.append({"pos": Vector3(hw * 0.42, seat_y, sz0), "door": Vector3(hw + 0.75, 0.0, sz0 - 0.2)})
	if int(def.seats) >= 4:
		r.seats.append({"pos": Vector3(-hw * 0.42, seat_y, sz0 + 0.95), "door": Vector3(-hw - 0.75, 0.0, sz0 + 0.8)})
		r.seats.append({"pos": Vector3(hw * 0.42, seat_y, sz0 + 0.95), "door": Vector3(hw + 0.75, 0.0, sz0 + 0.8)})
	r.half_extents = Vector3(hw, (roof - clr) * 0.5, L * 0.5)


static func _section(z: float, y0: float, y1: float, hw: float, ch: float) -> PackedVector3Array:
	var p := PackedVector3Array()
	var c := minf(ch, (y1 - y0) * 0.45)
	p.append(Vector3(hw, y0 + c, z))
	p.append(Vector3(hw - c, y0, z))
	p.append(Vector3(-hw + c, y0, z))
	p.append(Vector3(-hw, y0 + c, z))
	p.append(Vector3(-hw, y1 - c, z))
	p.append(Vector3(-hw + c * 1.5, y1, z))
	p.append(Vector3(hw - c * 1.5, y1, z))
	p.append(Vector3(hw, y1 - c, z))
	return p


static func _cabin_section(z: float, y0: float, y1: float, hw0: float, hw1: float) -> PackedVector3Array:
	var p := PackedVector3Array()
	var h := maxf(y1 - y0, 0.01)
	var k := clampf(h / 0.6, 0.0, 1.0)
	var top_w := lerpf(hw0, hw1, k)
	p.append(Vector3(hw0, y0, z))
	p.append(Vector3(-hw0, y0, z))
	p.append(Vector3(-top_w, y0 + h, z))
	p.append(Vector3(top_w, y0 + h, z))
	return p


# ------------------------------------------------------------------ two-wheelers

static func _bike(r: Result, def: Dictionary, mods: Dictionary) -> void:
	var mb := MB.new()
	var wr: float = def.wheel_r
	var wb: float = def.wheelbase
	var bicycle: bool = def.kind == "bicycle"
	if bicycle:
		mb.use("paint").col(Color.WHITE)
		var bb := Vector3(0, wr + 0.05, 0.05)
		var seat := Vector3(0, wr + 0.62, 0.2)
		var head := Vector3(0, wr + 0.62, -wb * 0.5 + 0.18)
		for pair in [[bb, seat], [bb, head], [seat, head], [bb, Vector3(0, wr, wb * 0.5)], [seat, Vector3(0, wr, wb * 0.5)], [head, Vector3(0, wr, -wb * 0.5)]]:
			var a: Vector3 = pair[0]
			var b: Vector3 = pair[1]
			var dirv := (b - a).normalized()
			var side := Vector3.RIGHT
			var fwd := side.cross(dirv).normalized()
			mb.box_xf(Transform3D(Basis(side, dirv, fwd).orthonormalized(), (a + b) * 0.5), Vector3(0.04, a.distance_to(b), 0.04))
		mb.use("trim").col(Color.WHITE)
		mb.box(seat + Vector3(0, 0.05, 0.02), Vector3(0.12, 0.05, 0.24))
		mb.box(head + Vector3(0, 0.15, 0.05), Vector3(0.6, 0.03, 0.03))
		r.half_extents = Vector3(0.3, 0.6, wb * 0.5 + wr)
		r.seats.append({"pos": Vector3(0, wr + 0.12, 0.3), "door": Vector3(-0.8, 0, 0)})
	else:
		mb.use("paint").col(Color.WHITE)
		# tank + fairing + tail
		mb.prism(Vector3(0, wr + 0.32, -0.15), 0.26, Vector2(0.16, 0.32), Vector2(0.12, 0.22), 0.06)
		mb.prism(Vector3(0, wr + 0.18, -0.62), 0.5, Vector2(0.18, 0.12), Vector2(0.12, 0.08), 0.05, Vector2(0, -0.12))
		mb.prism(Vector3(0, wr + 0.42, 0.42), 0.14, Vector2(0.12, 0.3), Vector2(0.06, 0.25), 0.04, Vector2(0, 0.12))
		mb.use("trim").col(Color.WHITE)
		mb.box(Vector3(0, wr + 0.12, 0.0), Vector3(0.26, 0.3, 0.7), 0.05)        # engine block
		mb.box(Vector3(0, wr + 0.5, 0.2), Vector3(0.24, 0.07, 0.5), 0.03)        # seat
		mb.box_xf(Transform3D(Basis(Vector3.RIGHT, 0.45), Vector3(0, wr + 0.35, -wb * 0.5 + 0.1)), Vector3(0.12, 0.7, 0.06))   # forks
		mb.box(Vector3(0, wr + 0.7, -0.55), Vector3(0.62, 0.04, 0.04))           # bars
		mb.use("glass").col(Color.WHITE)
		mb.box_xf(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0, wr + 0.78, -0.75)), Vector3(0.3, 0.2, 0.02))
		mb.use("head").col(Color.WHITE)
		mb.box(Vector3(0, wr + 0.5, -0.88), Vector3(0.16, 0.1, 0.05))
		r.head_points.append(Vector3(0, wr + 0.5, -0.92))
		mb.use("tail").col(Color.WHITE)
		mb.box(Vector3(0, wr + 0.5, 0.68), Vector3(0.12, 0.06, 0.04))
		mb.use("chrome").col(Color.WHITE)
		mb.cylinder_axis(Vector3(0.16, wr + 0.05, 0.45), Vector3(0, -0.2, 1).normalized(), 0.05, 0.55, 8)
		r.half_extents = Vector3(0.35, 0.65, wb * 0.5 + wr)
		r.seats.append({"pos": Vector3(0, wr + 0.08, 0.15), "door": Vector3(-0.9, 0, 0)})
	var mats := {"paint": r.paint, "trim": Mats.color(Color(0.1, 0.1, 0.11), 0.6), "glass": r.glass, "head": r.head_mat, "tail": r.tail_mat,
		"chrome": Mats.color(Color(0.8, 0.8, 0.82), 0.1, 1.0)}
	_mi(r.root, mb.commit(mats), "Body")
	var w := 0.08 if bicycle else 0.16
	_add_wheel(r, Vector3(0, wr, -wb * 0.5), wr, w, true, false, int(mods.get("rims", 2 if bicycle else 0)))
	_add_wheel(r, Vector3(0, wr, wb * 0.5), wr, w, false, true, int(mods.get("rims", 2 if bicycle else 0)))


# ------------------------------------------------------------------ boat

static func _boat(r: Result, _def: Dictionary, _mods: Dictionary) -> void:
	var mb := MB.new()
	mb.use("paint").col(Color.WHITE)
	# hull: loft from stern (+z) to bow (-z) with V bottom
	var secs := []
	var st := [[3.6, 1.15, 0.2, 0.9], [2.0, 1.2, -0.05, 0.95], [0.0, 1.15, -0.25, 1.0], [-2.0, 0.95, -0.15, 1.05], [-3.4, 0.45, 0.25, 1.1], [-4.0, 0.06, 0.75, 1.15]]
	for s in st:
		var z: float = s[0]
		var hw: float = s[1]
		var keel: float = s[2]
		var top: float = s[3]
		var p := PackedVector3Array()
		p.append(Vector3(hw, top, z))
		p.append(Vector3(hw * 0.85, keel + 0.35, z))
		p.append(Vector3(0, keel, z))
		p.append(Vector3(-hw * 0.85, keel + 0.35, z))
		p.append(Vector3(-hw, top, z))
		secs.append(p)
	mb.loft(secs, true, true)
	mb.use("paint2").col(Color.WHITE)
	mb.box(Vector3(0, 0.3, -0.2), Vector3(2.3, 0.08, 7.0))                     # stripe
	mb.use("trim").col(Color.WHITE)
	mb.box(Vector3(0, 0.98, 0.6), Vector3(2.0, 0.06, 4.6))                      # deck
	mb.box(Vector3(0, 1.25, 0.9), Vector3(1.6, 0.5, 1.0), 0.08)                 # seats
	mb.box(Vector3(0.55, 1.35, -0.4), Vector3(0.5, 0.75, 0.4), 0.05)           # console
	mb.use("glass").col(Color.WHITE)
	mb.box_xf(Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(0, 1.55, -0.85)), Vector3(1.9, 0.5, 0.03))
	mb.use("trim").col(Color.WHITE)
	mb.box(Vector3(0, 0.9, 3.75), Vector3(0.45, 0.9, 0.45), 0.06)               # outboard
	mb.use("head").col(Color.WHITE)
	mb.box(Vector3(0, 1.0, -3.8), Vector3(0.12, 0.08, 0.05))
	r.head_points.append(Vector3(0, 1.0, -3.9))
	var mats := {"paint": r.paint, "paint2": r.paint2, "trim": Mats.color(Color(0.2, 0.22, 0.25), 0.6), "glass": r.glass, "head": r.head_mat}
	_mi(r.root, mb.commit(mats), "Body")
	r.seats.append({"pos": Vector3(0.55, 0.85, 0.2), "door": Vector3(-1.9, 0.6, 0.6)})
	r.seats.append({"pos": Vector3(-0.55, 0.85, 0.6), "door": Vector3(-1.9, 0.6, 0.9)})
	r.half_extents = Vector3(1.2, 0.8, 3.9)
	var prop := Node3D.new()
	prop.name = "Prop"
	prop.position = Vector3(0, 0.15, 3.9)
	r.root.add_child(prop)
	r.prop = prop


# ------------------------------------------------------------------ helicopter

static func _heli(r: Result, def: Dictionary, _mods: Dictionary) -> void:
	var mb := MB.new()
	mb.use("paint").col(Color.WHITE)
	var secs := []
	for s in [[-2.2, 0.15, 0.85, 1.2], [-1.6, 0.65, 0.55, 1.95], [0.0, 0.75, 0.45, 2.15], [1.4, 0.6, 0.55, 1.9], [2.2, 0.25, 1.0, 1.45]]:
		secs.append(_section(s[0], s[2], s[3], s[1], 0.18))
	mb.loft(secs, true, true)
	# tail boom
	mb.cylinder_axis(Vector3(0, 1.45, 4.4), Vector3(0, 0, 1), 0.22, 4.4, 8, true, 0.12)
	mb.box(Vector3(0, 2.0, 6.5), Vector3(0.08, 1.2, 0.6))
	mb.box(Vector3(0, 1.45, 6.2), Vector3(1.3, 0.06, 0.4))
	mb.use("glass").col(Color.WHITE)
	mb.loft([_section(-2.3, 0.95, 1.25, 0.5, 0.1), _section(-1.6, 0.85, 1.95, 0.62, 0.15), _section(-0.6, 0.95, 2.05, 0.7, 0.15)], true, true)
	mb.use("trim").col(Color.WHITE)
	for sx in [-0.85, 0.85]:
		mb.box(Vector3(sx, 0.08, 0.0), Vector3(0.08, 0.08, 3.4))
		mb.box(Vector3(sx * 0.9, 0.4, -0.8), Vector3(0.06, 0.65, 0.06))
		mb.box(Vector3(sx * 0.9, 0.4, 0.8), Vector3(0.06, 0.65, 0.06))
	mb.box(Vector3(0, 2.2, 0.2), Vector3(0.9, 0.35, 1.5), 0.1)                  # engine cowling
	mb.cylinder(Vector3(0, 2.3, 0.0), 0.12, 0.45, 8)                            # mast
	if def.get("faction", "") == "police":
		mb.use("livery").col(Color.WHITE)
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(sx * 0.76, 1.0, 0.6), Vector3(0.01, 0.3, 2.2))
		mb.use("bar_red").col(Color.WHITE)
		mb.box(Vector3(-0.3, 2.42, 0.6), Vector3(0.2, 0.1, 0.2))
		mb.use("bar_blue").col(Color.WHITE)
		mb.box(Vector3(0.3, 2.42, 0.6), Vector3(0.2, 0.1, 0.2))
	mb.use("head").col(Color.WHITE)
	mb.box(Vector3(0, 0.3, -2.1), Vector3(0.2, 0.12, 0.1))
	r.head_points.append(Vector3(0, 0.25, -2.2))
	var mats := {"paint": r.paint, "glass": r.glass, "trim": Mats.color(Color(0.15, 0.16, 0.18), 0.6), "head": r.head_mat,
		"livery": Mats.color(Color(0.95, 0.95, 0.95), 0.3), "bar_red": r.bar_red, "bar_blue": r.bar_blue}
	_mi(r.root, mb.commit(mats), "Body")
	var rotor := Node3D.new()
	rotor.name = "Rotor"
	rotor.position = Vector3(0, 2.78, 0.0)
	r.root.add_child(rotor)
	var rm := MB.new()
	rm.use("trim").col(Color.WHITE)
	for k in 4:
		var a := TAU * k / 4.0
		rm.box_xf(Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * 2.6, 0, -sin(a) * 2.6)), Vector3(5.2, 0.04, 0.26))
	rm.cylinder(Vector3(0, -0.08, 0), 0.22, 0.16, 8)
	_mi(rotor, rm.commit({"trim": Mats.color(Color(0.12, 0.12, 0.13), 0.5)}), "Blades")
	var tr := Node3D.new()
	tr.name = "TailRotor"
	tr.position = Vector3(0.18, 2.0, 6.55)
	r.root.add_child(tr)
	var tm := MB.new()
	tm.use("trim").col(Color.WHITE)
	tm.box(Vector3.ZERO, Vector3(0.04, 1.3, 0.14))
	tm.box(Vector3.ZERO, Vector3(0.04, 0.14, 1.3))
	_mi(tr, tm.commit({"trim": Mats.color(Color(0.12, 0.12, 0.13), 0.5)}), "Blades")
	r.rotor = rotor
	r.tail_rotor = tr
	r.seats.append({"pos": Vector3(-0.38, 0.75, -0.9), "door": Vector3(-1.8, 0.0, -0.9)})
	r.seats.append({"pos": Vector3(0.38, 0.75, -0.9), "door": Vector3(1.8, 0.0, -0.9)})
	r.half_extents = Vector3(0.95, 1.2, 3.4)


# ------------------------------------------------------------------ airplanes

static func _plane(r: Result, def: Dictionary, _mods: Dictionary) -> void:
	var jet: bool = def.get("jet", false)
	var mb := MB.new()
	mb.use("paint").col(Color.WHITE)
	var secs := []
	if jet:
		for s in [[-5.2, 0.05, 1.1, 1.2], [-3.8, 0.42, 0.7, 1.65], [-1.0, 0.65, 0.55, 1.95], [2.5, 0.6, 0.6, 1.85], [4.6, 0.45, 0.8, 1.6]]:
			secs.append(_section(s[0], s[2], s[3], s[1], 0.15))
	else:
		for s in [[-3.0, 0.42, 0.75, 1.55], [-2.2, 0.55, 0.55, 1.8], [0.0, 0.6, 0.5, 1.9], [2.6, 0.32, 0.95, 1.65], [4.4, 0.12, 1.3, 1.55]]:
			secs.append(_section(s[0], s[2], s[3], s[1], 0.15))
	mb.loft(secs, true, true)
	# wings
	var wing_z := -0.3 if not jet else 0.5
	var span := 5.4 if not jet else 3.6
	var wy := 1.85 if not jet else 0.9
	for sx in [-1.0, 1.0]:
		var root_p := Vector3(sx * 0.5, wy, wing_z)
		var tip := Vector3(sx * span, wy + (0.15 if not jet else -0.05), wing_z + (0.25 if not jet else 1.6))
		mb.quad(root_p + Vector3(0, 0, -0.8 if not jet else -1.8), tip + Vector3(0, 0, -0.5 if not jet else -0.3), tip + Vector3(0, 0, 0.5 if not jet else 0.5), root_p + Vector3(0, 0, 0.8 if not jet else 1.4), Vector3.UP)
		mb.quad(root_p + Vector3(0, -0.06, -0.8 if not jet else -1.8), root_p + Vector3(0, -0.06, 0.8 if not jet else 1.4), tip + Vector3(0, -0.06, 0.5 if not jet else 0.5), tip + Vector3(0, -0.06, -0.5 if not jet else -0.3), Vector3.DOWN)
	# tail
	var tz := 4.2 if not jet else 4.3
	mb.box(Vector3(0, 2.0 if not jet else 2.0, tz), Vector3(0.08, 1.2 if not jet else 1.6, 0.9))
	mb.box(Vector3(0, 1.55 if not jet else 1.2, tz + 0.1), Vector3(2.6 if not jet else 3.0, 0.06, 0.7))
	mb.use("paint2").col(Color.WHITE)
	mb.box(Vector3(0, 1.0, 0.0), Vector3(1.15, 0.12, 6.0 if not jet else 8.0))
	mb.use("glass").col(Color.WHITE)
	if jet:
		mb.loft([_section(-3.6, 1.55, 1.7, 0.3, 0.08), _section(-2.6, 1.6, 2.25, 0.45, 0.15), _section(-1.2, 1.65, 2.2, 0.45, 0.15), _section(-0.4, 1.6, 1.9, 0.3, 0.1)], true, true)
	else:
		mb.loft([_section(-2.25, 1.55, 1.7, 0.45, 0.08), _section(-1.6, 1.55, 2.25, 0.55, 0.15), _section(-0.2, 1.6, 2.25, 0.55, 0.15), _section(0.6, 1.6, 1.75, 0.45, 0.1)], true, true)
	mb.use("trim").col(Color.WHITE)
	# landing gear
	var gear := [Vector3(0, 0.0, -2.2 if not jet else -3.4), Vector3(-1.1, 0.0, 0.5 if not jet else 1.0), Vector3(1.1, 0.0, 0.5 if not jet else 1.0)]
	for g in gear:
		mb.box(g + Vector3(0, 0.55, 0), Vector3(0.08, 0.7, 0.08))
	if jet:
		mb.cylinder_axis(Vector3(0, 1.15, 4.9), Vector3(0, 0, 1), 0.38, 0.5, 10)
		mb.use("head").col(Color.WHITE)
		mb.cylinder_axis(Vector3(0, 1.15, 5.12), Vector3(0, 0, 1), 0.3, 0.02, 10)
	else:
		mb.use("head").col(Color.WHITE)
		for sx in [-1.0, 1.0]:
			mb.box(Vector3(sx * 2.4, 1.9, -0.75), Vector3(0.2, 0.08, 0.06))
	r.head_points.append(Vector3(0, 1.0, -3.2 if not jet else -5.3))
	var mats := {"paint": r.paint, "paint2": r.paint2, "glass": r.glass, "trim": Mats.color(Color(0.12, 0.12, 0.13), 0.6), "head": r.head_mat}
	_mi(r.root, mb.commit(mats), "Body")
	for g in gear:
		_add_wheel(r, g + Vector3(0, 0.2, 0), 0.22, 0.12, g.z < -1.0, false, 3)
	if not jet:
		var prop := Node3D.new()
		prop.name = "Prop"
		prop.position = Vector3(0, 1.15, -3.15)
		r.root.add_child(prop)
		var pm := MB.new()
		pm.use("trim").col(Color.WHITE)
		pm.box(Vector3.ZERO, Vector3(2.0, 0.16, 0.05))
		pm.cylinder_axis(Vector3(0, 0, -0.1), Vector3(0, 0, -1), 0.14, 0.25, 8, true, 0.02)
		_mi(prop, pm.commit({"trim": Mats.color(Color(0.15, 0.15, 0.16), 0.4)}), "Blades")
		r.prop = prop
	r.seats.append({"pos": Vector3(0, 0.95, -1.2 if not jet else -2.4), "door": Vector3(-1.6, 0.0, -1.0)})
	if int(def.seats) > 1:
		r.seats.append({"pos": Vector3(0, 0.95, -0.2), "door": Vector3(1.6, 0.0, -0.2)})
	r.half_extents = Vector3(span * 0.9, 1.1, 4.6 if not jet else 5.3)
