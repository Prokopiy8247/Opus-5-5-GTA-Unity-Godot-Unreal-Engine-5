class_name CityBuilder
extends RefCounted
## Block slabs (sidewalk ring + lot) and procedural buildings for every city block, plus special venues.

const SW := WorldMap.SIDEWALK_W
const Y0 := C.LAND_Y
const YT := C.LAND_Y + WorldMap.CURB_H

const DOWNTOWN := [Color(0.93, 0.88, 0.78), Color(0.85, 0.75, 0.6), Color(0.8, 0.52, 0.4), Color(0.45, 0.5, 0.56),
	Color(0.42, 0.58, 0.6), Color(0.95, 0.94, 0.9), Color(0.32, 0.33, 0.36), Color(0.92, 0.66, 0.56), Color(0.55, 0.62, 0.72)]
const PASTEL := [Color(0.72, 0.88, 0.78), Color(0.98, 0.8, 0.66), Color(0.72, 0.82, 0.95), Color(0.97, 0.9, 0.64),
	Color(0.83, 0.76, 0.9), Color(0.96, 0.95, 0.92), Color(0.95, 0.72, 0.7)]
const ROOFS := [Color(0.72, 0.36, 0.26), Color(0.36, 0.38, 0.43), Color(0.26, 0.5, 0.52), Color(0.55, 0.3, 0.25)]
const INDUSTRIAL := [Color(0.62, 0.64, 0.66), Color(0.46, 0.53, 0.6), Color(0.62, 0.4, 0.3), Color(0.52, 0.58, 0.52), Color(0.86, 0.85, 0.8)]
const AWNINGS := [Color(0.85, 0.25, 0.3), Color(0.15, 0.55, 0.6), Color(0.95, 0.7, 0.2), Color(0.3, 0.35, 0.6), Color(0.2, 0.6, 0.35)]

var w: World
var rng := RandomNumberGenerator.new()
var mb := MB.new()          # merged city mesh (all blocks)
var seed_ctr := 0.0


func build(world: World) -> void:
	w = world
	rng.seed = 424242
	for blk in WorldMap.blocks():
		_block(blk)
	var mats := {
		"bld": w.mats["bld"], "ground": w.mats["ground"], "vc": w.mats["vc"], "gloss": w.mats["vc_gloss"],
		"metal": w.mats["metal"], "glass": w.mats["glass"], "neon_pink": w.mats["neon_pink"],
		"neon_teal": w.mats["neon_teal"], "neon_amber": w.mats["neon_amber"], "neon_red": w.mats["neon_red"],
		"emit_warm": w.mats["emit_warm"], "emit_white": w.mats["emit_white"],
	}
	# split the merged builder by surface into one mesh (Godot handles many surfaces per mesh)
	var mesh := mb.commit(mats)
	w.add_mesh(mesh, "CityBlocks")


func _block(blk: Dictionary) -> void:
	var r: Rect2 = blk.rect
	# slab: sidewalk ring top + lot interior, single collision slab
	RoadBuilder.add_slab_mesh(mb.use("ground"), r, Y0, YT, 0)
	w.add_slab_col(r, Y0, YT)
	var lot := r.grow(-SW)
	match blk.kind:
		"downtown": _downtown(lot)
		"commercial": _commercial(lot)
		"industrial": _industrial(lot)
		"residential": _residential(lot, false)
		"plaza": _plaza(lot)
		"police": _police(lot)
		"gunshop": _gunshop(lot)
		"shops": _shops(lot)
		"dealer": _dealer(lot)
		"gas": _gas(lot)
		"modshop": _modshop(lot)
		"hospital": _hospital(lot)
		"park": _park(lot)
		"safehouse": _safehouse(lot)
		_: _commercial(lot)


# ------------------------------------------------------------------ primitives

func ground(r: Rect2, kind: int, tint := Color.WHITE, y := YT + 0.01) -> void:
	mb.use("ground")
	mb.uv2 = Vector2(kind, 0)
	mb.col(tint)
	var a := r.position
	var b := r.end
	mb.quad_uv(Vector3(a.x, y, a.y), Vector3(b.x, y, a.y), Vector3(b.x, y, b.y), Vector3(a.x, y, b.y),
		Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(a.x, b.y), Vector3.UP)


func bld(r: Rect2, y: float, h: float, style: int, c: Color, v0 := 0.0, collide := true) -> void:
	seed_ctr += 1.0
	mb.use("bld")
	mb.uv2 = Vector2(style, fmod(seed_ctr * 0.6180339, 1.0) * 10.0)
	mb.col(c)
	var ctr := r.get_center()
	mb.prism(Vector3(ctr.x, y, ctr.y), h, r.size * 0.5, r.size * 0.5, 0.0, Vector2.ZERO, true, v0)
	if collide:
		w.add_box_col(Vector3(ctr.x, y + h * 0.5, ctr.y), Vector3(r.size.x, h, r.size.y))


func gable_roof(r: Rect2, y: float, h: float, c: Color, along_x := true, overhang := 0.4) -> void:
	mb.use("vc")
	mb.col(c)
	var ctr := r.get_center()
	var half := r.size * 0.5 + Vector2(overhang, overhang)
	var top := Vector2(half.x, 0.06) if along_x else Vector2(0.06, half.y)
	mb.prism(Vector3(ctr.x, y, ctr.y), h, half, top)
	w.add_box_col(Vector3(ctr.x, y + h * 0.3, ctr.y), Vector3(r.size.x, h * 0.6, r.size.y))


func vbox(center: Vector3, size: Vector3, c: Color, surface := "vc", collide := false, chamfer := 0.0) -> void:
	mb.use(surface)
	mb.col(c)
	mb.box(center, size, chamfer)
	if collide:
		w.add_box_col(center, size)


func awning(x0: float, x1: float, z: float, y: float, depth: float, facing: float, c: Color) -> void:
	# facing: +1 = awning sticks out toward +z, -1 toward -z
	mb.use("vc")
	mb.col(c)
	var length := x1 - x0
	var xf := Transform3D(Basis(Vector3.RIGHT, 0.32 * facing), Vector3((x0 + x1) * 0.5, y, z + facing * depth * 0.5))
	mb.box_xf(xf, Vector3(length, 0.08, depth))


func awning_z(z0: float, z1: float, x: float, y: float, depth: float, facing: float, c: Color) -> void:
	mb.use("vc")
	mb.col(c)
	var xf := Transform3D(Basis(Vector3.FORWARD, -0.32 * facing), Vector3(x + facing * depth * 0.5, y, (z0 + z1) * 0.5))
	mb.box_xf(xf, Vector3(depth, 0.08, z1 - z0))


func neon_sign(center: Vector3, size: Vector3, which := "") -> void:
	if which == "":
		which = ["neon_pink", "neon_teal", "neon_amber"][rng.randi() % 3]
	vbox(center - Vector3(0, 0, 0), size + Vector3(0.1, 0.1, 0.0), Color(0.1, 0.1, 0.12))
	mb.use(which)
	mb.col(Color.WHITE)
	mb.box(center, size * Vector3(0.9, 0.6, 1.6))


func rooftop(r: Rect2, y: float) -> void:
	var n := rng.randi_range(1, 4)
	for i in n:
		var sx := rng.randf_range(1.5, 3.5)
		var sz := rng.randf_range(1.5, 3.0)
		var px := rng.randf_range(r.position.x + sx, r.end.x - sx)
		var pz := rng.randf_range(r.position.y + sz, r.end.y - sz)
		if r.size.x < sx * 2.5 or r.size.y < sz * 2.5:
			break
		vbox(Vector3(px, y + 0.6, pz), Vector3(sx, 1.2, sz), Color(0.7, 0.72, 0.74), "metal")
	if rng.randf() < 0.45 and r.size.x > 8:
		var c := r.get_center() + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		mb.use("vc").col(Color(0.55, 0.42, 0.32))
		mb.cylinder(Vector3(c.x, y, c.y), 1.6, 3.2, 10)
		mb.prism(Vector3(c.x, y + 3.2, c.y), 1.0, Vector2(1.7, 1.7), Vector2(0.1, 0.1))
	if rng.randf() < 0.3:
		var c2 := r.get_center()
		vbox(Vector3(c2.x, y + 4.0, c2.y), Vector3(0.15, 8.0, 0.15), Color(0.3, 0.3, 0.32), "metal")
		mb.use("neon_red").col(Color.WHITE)
		mb.box(Vector3(c2.x, y + 8.1, c2.y), Vector3(0.3, 0.3, 0.3))


func split_rect(r: Rect2, along_x: bool, parts: int, gap: float) -> Array:
	var out := []
	var total := r.size.x if along_x else r.size.y
	var each := (total - gap * (parts - 1)) / parts
	for i in parts:
		var off := i * (each + gap)
		if along_x:
			out.append(Rect2(r.position.x + off, r.position.y, each, r.size.y))
		else:
			out.append(Rect2(r.position.x, r.position.y + off, r.size.x, each))
	return out


func parking(r: Rect2, yaw: float, kind := "lot") -> void:
	ground(r, 2)
	# bays every 2.7 m along x (lines drawn by the shader); register spawn transforms
	var bays_x := int(r.size.x / 2.7)
	var rows := int(r.size.y / 5.4)
	for row in rows:
		for b in bays_x:
			if rng.randf() < 0.55:
				continue
			var p := Vector3(r.position.x + 1.35 + b * 2.7, YT + 0.3, r.position.y + 2.7 + row * 5.4)
			w.parking_spots.append({"xform": Transform3D(Basis(Vector3.UP, yaw + (PI if row % 2 == 1 else 0.0)), p), "kind": kind})


func ladder(bottom: Vector3, top_y: float, normal: Vector3) -> void:
	var right := normal.cross(Vector3.UP).normalized()
	var h := top_y - bottom.y
	mb.use("metal").col(Color(0.35, 0.36, 0.38))
	for s in [-0.25, 0.25]:
		mb.box(bottom + right * s + Vector3(0, h * 0.5, 0) + normal * 0.12, Vector3(0.06, h, 0.06).abs())
	var rungs := int(h / 0.35)
	for i in rungs:
		var y := 0.3 + i * 0.35
		var c := bottom + Vector3(0, y, 0) + normal * 0.12
		var xf := Transform3D(Basis(right, Vector3.UP, right.cross(Vector3.UP)), c)
		mb.box_xf(xf, Vector3(0.5, 0.04, 0.04))
	w.ladders.append({"bottom": bottom + normal * 0.55, "top": Vector3(bottom.x, top_y, bottom.z) - normal * 0.6, "normal": normal, "top_y": top_y})


# ------------------------------------------------------------------ generic districts

func _downtown(lot: Rect2) -> void:
	ground(lot, 0)
	var along_x := lot.size.x >= lot.size.y
	var parts := 2 if (lot.size.x if along_x else lot.size.y) < 70 else 3
	for p in split_rect(lot, along_x, parts, 4.0):
		var sub: Array = [p]
		if (p.size.y if along_x else p.size.x) > 44 and rng.randf() < 0.6:
			sub = split_rect(p, not along_x, 2, 4.0)
		for q in sub:
			_tower(q)


func _tower(q: Rect2) -> void:
	var col: Color = DOWNTOWN[rng.randi() % DOWNTOWN.size()]
	var pod_h := rng.randf_range(5.0, 9.0)
	var inner := q.grow(-0.5)
	bld(inner, YT, pod_h, 4, col.darkened(0.08))
	# storefront awnings on the podium (north + south faces)
	if rng.randf() < 0.6:
		awning(inner.position.x + 1, inner.end.x - 1, inner.position.y, YT + 3.4, 1.6, -1, AWNINGS[rng.randi() % AWNINGS.size()])
	if rng.randf() < 0.6:
		awning(inner.position.x + 1, inner.end.x - 1, inner.end.y, YT + 3.4, 1.6, 1, AWNINGS[rng.randi() % AWNINGS.size()])
	if rng.randf() < 0.5:
		neon_sign(Vector3(inner.get_center().x, YT + pod_h - 1.2, inner.end.y + 0.15), Vector3(minf(inner.size.x * 0.4, 8.0), 1.2, 0.2))
	var inset := rng.randf_range(1.5, 4.0)
	var tower := inner.grow(-inset)
	if tower.size.x < 6 or tower.size.y < 6:
		rooftop(inner, YT + pod_h)
		return
	var th := rng.randf_range(18.0, 70.0)
	var style := 1 if rng.randf() < 0.6 else 2
	var tcol: Color = col if style == 2 else DOWNTOWN[rng.randi() % DOWNTOWN.size()]
	bld(tower, YT + pod_h, th, style, tcol, pod_h)
	var top := YT + pod_h + th
	if rng.randf() < 0.45 and tower.size.x > 12 and tower.size.y > 12:
		var crown := tower.grow(-rng.randf_range(2.0, 4.0))
		var ch := rng.randf_range(6.0, 16.0)
		bld(crown, top, ch, style, tcol.lightened(0.05), pod_h + th)
		top += ch
		rooftop(crown, top)
	else:
		rooftop(tower, top)


func _commercial(lot: Rect2) -> void:
	ground(lot, 0)
	# row of shops along the north and south edges, parking/court in the middle
	var depth := minf(14.0, lot.size.y * 0.35)
	for side in [0, 1]:
		var z0 := lot.position.y if side == 0 else lot.end.y - depth
		var x := lot.position.x
		while x < lot.end.x - 8:
			var wdt := minf(rng.randf_range(9.0, 18.0), lot.end.x - x)
			var r := Rect2(x, z0, wdt - 0.4, depth)
			var floors := rng.randi_range(2, 4)
			var h := 4.2 + (floors - 1) * 3.4
			var col: Color = DOWNTOWN[rng.randi() % DOWNTOWN.size()].lightened(0.05)
			bld(r, YT, h, 4, col)
			var face_z := r.position.y if side == 0 else r.end.y
			var facing := -1.0 if side == 0 else 1.0
			if rng.randf() < 0.75:
				awning(r.position.x + 0.8, r.end.x - 0.8, face_z, YT + 3.3, 1.5, facing, AWNINGS[rng.randi() % AWNINGS.size()])
			if rng.randf() < 0.55:
				neon_sign(Vector3(r.get_center().x, YT + 4.6, face_z + facing * 0.15), Vector3(minf(wdt * 0.5, 6.0), 0.9, 0.2))
			rooftop(r, YT + h)
			x += wdt
	var mid := Rect2(lot.position.x + 2, lot.position.y + depth + 2, lot.size.x - 4, lot.size.y - depth * 2 - 4)
	if mid.size.y > 8:
		parking(mid, 0.0, "street")


func _industrial(lot: Rect2) -> void:
	ground(lot, 6)
	var halves := split_rect(lot, lot.size.x > lot.size.y, 2, 8.0)
	for i in halves.size():
		var r: Rect2 = halves[i]
		if rng.randf() < 0.75:
			_warehouse(r.grow(-2.0))
		else:
			_yard(r.grow(-1.0))


func _warehouse(r: Rect2) -> void:
	var col: Color = INDUSTRIAL[rng.randi() % INDUSTRIAL.size()]
	var h := rng.randf_range(8.0, 13.0)
	var along_x := r.size.x > r.size.y
	bld(r, YT, h, 3, col)
	# roof
	if rng.randf() < 0.5:
		gable_roof(r, YT + h, rng.randf_range(2.0, 3.5), col.darkened(0.25), along_x, 0.3)
	else:
		# sawtooth
		var n := maxi(int((r.size.x if not along_x else r.size.y) / 8.0), 2)
		for k in n:
			var sub := split_rect(r, not along_x, n, 0.0)[k] as Rect2
			mb.use("vc").col(col.darkened(0.2))
			var c := sub.get_center()
			var half := sub.size * 0.5
			var shift := Vector2(half.x * 0.9, 0) if not along_x else Vector2(0, half.y * 0.9)
			mb.prism(Vector3(c.x, YT + h, c.y), 2.5, half, Vector2(0.05, half.y) if not along_x else Vector2(half.x, 0.05), 0.0, shift)
	# roll-up doors on the long sides
	var doors := maxi(int((r.size.x if along_x else r.size.y) / 12.0), 1)
	for k in doors:
		var t := (k + 0.5) / doors
		if along_x:
			var x := lerpf(r.position.x, r.end.x, t)
			vbox(Vector3(x, YT + 2.3, r.end.y + 0.06), Vector3(4.2, 4.6, 0.12), Color(0.36, 0.38, 0.4), "metal")
			vbox(Vector3(x, YT + 4.9, r.end.y + 0.5), Vector3(5.0, 0.15, 1.0), Color(0.75, 0.6, 0.2))
		else:
			var z := lerpf(r.position.y, r.end.y, t)
			vbox(Vector3(r.end.x + 0.06, YT + 2.3, z), Vector3(0.12, 4.6, 4.2), Color(0.36, 0.38, 0.4), "metal")
	if rng.randf() < 0.5:
		ladder(Vector3(r.position.x + 3.0, YT, r.position.y - 0.0), YT + h, Vector3(0, 0, -1))
	if rng.randf() < 0.35:
		mb.use("vc").col(Color(0.55, 0.5, 0.48))
		var c := Vector2(r.end.x - 3, r.position.y + 3)
		mb.cylinder(Vector3(c.x, YT + h, c.y), 0.9, 8.0, 10)
		w.add_cyl_col(Vector3(c.x, YT + h, c.y), 0.9, 8.0)


func _yard(r: Rect2) -> void:
	ground(r, 6, Color(0.95, 0.95, 0.95))
	# container stacks
	var cols := [Color(0.8, 0.3, 0.2), Color(0.2, 0.45, 0.7), Color(0.85, 0.65, 0.2), Color(0.3, 0.6, 0.4), Color(0.6, 0.62, 0.65)]
	var x := r.position.x + 4
	while x < r.end.x - 4:
		var stack := rng.randi_range(1, 3)
		var z := r.position.y + rng.randf_range(3, maxf(r.size.y - 8, 3.5))
		for s in stack:
			var c: Color = cols[rng.randi() % cols.size()]
			var ctr := Vector3(x, YT + 1.3 + s * 2.6, z + 3.0)
			vbox(ctr, Vector3(2.44, 2.59, 6.06), c, "vc", true)
			# corrugation ribs
			vbox(ctr + Vector3(1.25, 0, 0), Vector3(0.06, 2.4, 5.8), c.darkened(0.2))
		x += rng.randf_range(4.0, 7.0)
	# fence
	_fence(r, Color(0.55, 0.58, 0.6))
	# tanks
	if rng.randf() < 0.5:
		var c2 := Vector2(r.end.x - 6, r.end.y - 6)
		mb.use("metal").col(Color(0.8, 0.8, 0.78))
		mb.cylinder(Vector3(c2.x, YT, c2.y), 3.5, 7.0, 14)
		w.add_cyl_col(Vector3(c2.x, YT, c2.y), 3.5, 7.0, C.SURF_METAL)
	w.stunt_jumps.append({"pos": Vector3(r.get_center().x, YT, r.get_center().y), "yaw": 0.0, "auto": true, "rect": r})


func _fence(r: Rect2, c: Color, h := 2.0, gate_side := 3) -> void:
	var post := 3.0
	var edges := [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
		[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]
	for ei in edges.size():
		var a: Vector2 = edges[ei][0]
		var b: Vector2 = edges[ei][1]
		var len := a.distance_to(b)
		var n := int(len / post)
		for k in n + 1:
			var p := a.lerp(b, float(k) / maxf(n, 1))
			vbox(Vector3(p.x, YT + h * 0.5, p.y), Vector3(0.08, h, 0.08), c, "metal")
		if ei == gate_side:
			continue
		var mid := (a + b) * 0.5
		var dir := (b - a).normalized()
		var size := Vector3(absf(dir.x) * len + 0.05, h * 0.9, absf(dir.y) * len + 0.05)
		mb.use("glass").col(Color.WHITE)
		mb.box(Vector3(mid.x, YT + h * 0.5, mid.y), Vector3(maxf(size.x, 0.03), size.y, maxf(size.z, 0.03)))
		w.add_box_col(Vector3(mid.x, YT + h * 0.5, mid.y), Vector3(maxf(size.x, 0.1), h, maxf(size.z, 0.1)), 0.0, C.SURF_METAL)


func _residential(lot: Rect2, skip_center: bool) -> void:
	ground(lot, 1)
	# houses facing north and south streets with back yards in between
	var depth := lot.size.y * 0.5
	for side in [0, 1]:
		var x := lot.position.x + 1.0
		while x < lot.end.x - 12:
			var wdt := minf(rng.randf_range(14.0, 18.0), lot.end.x - x)
			if wdt < 12:
				break
			var plot := Rect2(x, lot.position.y if side == 0 else lot.position.y + depth, wdt, depth)
			if rng.randf() < 0.18 and depth > 22:
				_apartment(plot.grow(-2.0))
			else:
				_house(plot, side == 0)
			x += wdt


func _house(plot: Rect2, faces_north: bool) -> void:
	var hw := minf(plot.size.x - 4.0, rng.randf_range(8.0, 11.0))
	var hd := rng.randf_range(7.5, 9.5)
	var front_gap := rng.randf_range(4.0, 6.0)
	var cx := plot.position.x + 2.0 + hw * 0.5 + rng.randf_range(0, maxf(plot.size.x - 4.0 - hw, 0.0)) * 0.3
	var z0 := (plot.position.y + front_gap) if faces_north else (plot.end.y - front_gap - hd)
	var r := Rect2(cx - hw * 0.5, z0, hw, hd)
	var floors := 1 if rng.randf() < 0.55 else 2
	var h := floors * 3.0
	var col: Color = PASTEL[rng.randi() % PASTEL.size()]
	var roof_h := rng.randf_range(2.0, 3.0)
	var roof_c: Color = ROOFS[rng.randi() % ROOFS.size()]
	var roof_x := rng.randf() < 0.5
	var dz := r.position.y if faces_north else r.end.y
	var f := -1.0 if faces_north else 1.0
	var model := "buildings/house_%df" % floors
	if ModelLib.has(model):
		# Blender house (10 x 8.5 m reference footprint, front at -Z) fitted to the lot, tinted per house
		seed_ctr += 1.0
		var ctr := r.get_center()
		var basis := Basis(Vector3.UP, 0.0 if faces_north else PI) * Basis.from_scale(Vector3(hw / 10.0, 1.0, hd / 8.5))
		ModelLib.bake(mb, model, Transform3D(basis, Vector3(cx, YT, ctr.y)), {"wall": col, "roof": roof_c, "door": col.darkened(0.45)})
		var rh := 2.4 if floors == 1 else 2.7
		w.add_box_col(Vector3(cx, YT + h * 0.5, ctr.y), Vector3(hw, h, hd))
		w.add_box_col(Vector3(cx, YT + h + rh * 0.3, ctr.y), Vector3(hw, rh * 0.6, hd))
		w.add_box_col(Vector3(cx, YT + 0.15, dz + f * 1.0 * hd / 8.5), Vector3(3.6 * hw / 10.0, 0.3, 2.0 * hd / 8.5))
	else:
		bld(r, YT, h, 5, col)
		gable_roof(r, YT + h, roof_h, roof_c, roof_x)
		# door + porch
		vbox(Vector3(cx, YT + 1.05, dz + f * 0.05), Vector3(1.0, 2.1, 0.1), col.darkened(0.45))
		vbox(Vector3(cx, YT + 0.08, dz + f * 1.0), Vector3(2.4, 0.16, 2.0), Color(0.7, 0.68, 0.64))
	# driveway + parked car spot
	var dx := r.end.x + 1.8
	if dx + 1.5 < plot.end.x:
		var drive := Rect2(dx - 1.5, (plot.position.y) if faces_north else (z0 + 1.0), 3.0, front_gap + hd - 1.0) if faces_north else Rect2(dx - 1.5, z0 + 1.0, 3.0, plot.end.y - z0 - 1.0)
		ground(drive, 6, Color(0.9, 0.9, 0.9), YT + 0.02)
		if rng.randf() < 0.5:
			var pz := drive.get_center().y
			w.parking_spots.append({"xform": Transform3D(Basis(Vector3.UP, 0.0 if faces_north else PI), Vector3(dx, YT + 0.3, pz)), "kind": "driveway"})
	# low front fence
	var fz := plot.position.y + 0.3 if faces_north else plot.end.y - 0.3
	vbox(Vector3(plot.position.x + plot.size.x * 0.3, YT + 0.45, fz), Vector3(plot.size.x * 0.5, 0.9, 0.08), Color(0.95, 0.95, 0.92), "vc", true)


func _apartment(r: Rect2) -> void:
	var floors := rng.randi_range(4, 6)
	var h := 3.6 + (floors - 1) * 3.2
	var col: Color = PASTEL[rng.randi() % PASTEL.size()].darkened(0.05)
	bld(r, YT, h, 2, col)
	# balconies
	for f in range(1, floors):
		vbox(Vector3(r.get_center().x, YT + 3.6 + (f - 1) * 3.2, r.position.y - 0.6), Vector3(r.size.x * 0.8, 0.15, 1.2), Color(0.9, 0.9, 0.88))
	rooftop(r, YT + h)
	ladder(Vector3(r.end.x - 1.0, YT, r.end.y), YT + h, Vector3(0, 0, 1))


# ------------------------------------------------------------------ special venues

func _plaza(lot: Rect2) -> void:
	ground(lot, 5)
	var c := lot.get_center()
	# Meridian Spire — landmark tower on the north edge
	var spire := Rect2(c.x - 10, lot.position.y + 2, 20, 18)
	bld(spire, YT, 12.0, 4, Color(0.92, 0.9, 0.86))
	bld(spire.grow(-2.0), YT + 12.0, 70.0, 1, Color(0.4, 0.55, 0.62), 12.0)
	bld(spire.grow(-4.0), YT + 82.0, 22.0, 1, Color(0.45, 0.6, 0.66), 82.0)
	vbox(Vector3(c.x, YT + 104.0 + 9.0, spire.get_center().y), Vector3(0.6, 18.0, 0.6), Color(0.85, 0.85, 0.88), "metal")
	mb.use("neon_red").col(Color.WHITE)
	mb.box(Vector3(c.x, YT + 122.3, spire.get_center().y), Vector3(0.7, 0.7, 0.7))
	w.register_poi("viewpoint_spire", Vector3(c.x, YT + 104.5, spire.get_center().y), 0.0)
	# side towers
	_tower(Rect2(lot.position.x + 1, lot.position.y + 1, 18, 22))
	_tower(Rect2(lot.end.x - 19, lot.position.y + 1, 18, 22))
	# fountain
	var fc := Vector3(c.x, YT, c.y + 14)
	mb.use("vc").col(Color(0.82, 0.8, 0.76))
	mb.cylinder(fc, 6.0, 0.7, 20)
	w.add_cyl_col(fc, 6.0, 0.7)
	mb.use("glass").col(Color.WHITE)
	mb.cylinder(fc + Vector3(0, 0.55, 0), 5.5, 0.05, 20)
	mb.use("vc").col(Color(0.85, 0.83, 0.8))
	mb.cylinder(fc, 0.8, 3.0, 10)
	mb.cylinder(fc + Vector3(0, 3.0, 0), 2.0, 0.3, 14)
	w.register_poi("fountain", fc, 0.0)
	# planters (low cover)
	for k in 6:
		var a := TAU * k / 6.0
		var p := fc + Vector3(cos(a) * 11.0, 0.45, sin(a) * 11.0)
		vbox(p, Vector3(3.0, 0.9, 1.0), Color(0.55, 0.5, 0.45), "vc", true)
		vbox(p + Vector3(0, 0.5, 0), Vector3(2.8, 0.2, 0.8), Color(0.3, 0.55, 0.25))


func _police(lot: Rect2) -> void:
	ground(lot, 6)
	var b := Rect2(lot.position.x + 22, lot.position.y + 14, 40, 36)
	var c := b.get_center()
	bld(b, YT, 14.0, 2, Color(0.82, 0.84, 0.88))
	bld(Rect2(b.position.x + 12, b.end.y - 0.1, 16, 4), YT, 4.5, 4, Color(0.22, 0.32, 0.55))  # entrance lobby
	vbox(Vector3(c.x, YT + 5.2, b.end.y + 4.2), Vector3(16, 0.4, 1.0), Color(0.2, 0.3, 0.55))
	mb.use("neon_teal").col(Color.WHITE)
	mb.box(Vector3(c.x, YT + 6.2, b.end.y + 4.15), Vector3(8.0, 1.0, 0.25))
	# blue & red stripe lights
	mb.use("neon_red").col(Color.WHITE)
	mb.box(Vector3(c.x - 6, YT + 14.2, b.end.y + 0.1), Vector3(2.0, 0.3, 0.2))
	vbox(Vector3(c.x + 6, YT + 14.2, b.end.y + 0.1), Vector3(2.0, 0.3, 0.2), Color(0.2, 0.3, 1.0), "neon_teal")
	# rooftop helipad
	_helipad(Vector3(c.x, YT + 14.02, c.y), 8.0)
	w.vehicle_spawns["police_heli"] = Transform3D(Basis.IDENTITY, Vector3(c.x, YT + 14.6, c.y))
	ladder(Vector3(b.position.x + 4, YT, b.end.y), YT + 14.0, Vector3(0, 0, 1))
	# parking lot with patrol cars
	var lotr := Rect2(lot.position.x + 1, lot.position.y + 4, 18, lot.size.y - 8)
	ground(lotr, 2)
	for k in 5:
		w.parking_spots.append({"xform": Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(lotr.get_center().x, YT + 0.3, lotr.position.y + 4 + k * 5.4)), "kind": "police"})
	w.register_poi("police", Vector3(c.x, YT, b.end.y + 5.5), 0.0)


func _helipad(center: Vector3, radius: float) -> void:
	mb.use("ground")
	mb.uv2 = Vector2(9, 0)
	mb.col(Color.WHITE)
	var r := radius
	var p := [Vector3(center.x - r, center.y, center.z - r), Vector3(center.x + r, center.y, center.z - r), Vector3(center.x + r, center.y, center.z + r), Vector3(center.x - r, center.y, center.z + r)]
	mb.quad_uv(p[0], p[1], p[2], p[3], Vector2(-r, -r), Vector2(r, -r), Vector2(r, r), Vector2(-r, r), Vector3.UP)


func _gunshop(lot: Rect2) -> void:
	ground(lot, 0)
	var shop := Rect2(lot.position.x + 2, lot.position.y + 1, 20, 14)
	bld(shop, YT, 7.5, 4, Color(0.3, 0.32, 0.3))
	neon_sign(Vector3(shop.get_center().x, YT + 5.8, shop.position.y - 0.15), Vector3(10, 1.4, 0.2), "neon_amber")
	awning(shop.position.x + 1, shop.end.x - 1, shop.position.y, YT + 3.3, 1.4, -1, Color(0.25, 0.25, 0.25))
	w.register_poi("gunshop", Vector3(shop.get_center().x, YT, shop.position.y - 1.6), PI)
	# outdoor shooting range (walled, roofed firing line)
	var rg := Rect2(lot.position.x + 26, lot.position.y + 24, 38, lot.size.y - 26)
	ground(rg, 7)
	var hw := 0.25
	bld(Rect2(rg.position.x - hw, rg.position.y, hw * 2, rg.size.y), YT, 3.0, 0, Color(0.6, 0.58, 0.55))
	bld(Rect2(rg.end.x - hw, rg.position.y, hw * 2, rg.size.y), YT, 3.0, 0, Color(0.6, 0.58, 0.55))
	bld(Rect2(rg.position.x, rg.end.y - 0.5, rg.size.x, 1.0), YT, 5.0, 0, Color(0.5, 0.45, 0.4))  # berm/backstop
	# firing line booth roof
	vbox(Vector3(rg.get_center().x, YT + 3.0, rg.position.y + 2.0), Vector3(rg.size.x, 0.2, 4.0), Color(0.35, 0.36, 0.38), "metal")
	for k in 6:
		var x := rg.position.x + 3.0 + k * (rg.size.x - 6.0) / 5.0
		vbox(Vector3(x, YT + 0.55, rg.position.y + 3.5), Vector3(0.1, 1.1, 2.4), Color(0.4, 0.4, 0.42), "vc", true)
		for d in [14.0, 24.0, 32.0]:
			if rg.position.y + 3.5 + d < rg.end.y - 1.5:
				w.range_targets.append(Vector3(x + rng.randf_range(-1.5, 1.5), YT, rg.position.y + 3.5 + d))
	w.register_poi("range", Vector3(rg.get_center().x, YT, rg.position.y + 1.0), 0.0)
	# rest of the block: commercial units
	var rest := Rect2(lot.position.x + 26, lot.position.y + 1, lot.size.x - 27, 18)
	_commercial_row(rest, true)
	_tower(Rect2(lot.position.x + 2, lot.position.y + 20, 20, lot.size.y - 22))


func _commercial_row(r: Rect2, faces_north: bool) -> void:
	var x := r.position.x
	while x < r.end.x - 6:
		var wdt := minf(rng.randf_range(9.0, 14.0), r.end.x - x)
		var q := Rect2(x, r.position.y, wdt - 0.4, r.size.y)
		var h := 4.2 + rng.randi_range(0, 2) * 3.4
		bld(q, YT, h, 4, DOWNTOWN[rng.randi() % DOWNTOWN.size()])
		var fz := q.position.y if faces_north else q.end.y
		awning(q.position.x + 0.8, q.end.x - 0.8, fz, YT + 3.3, 1.4, -1.0 if faces_north else 1.0, AWNINGS[rng.randi() % AWNINGS.size()])
		rooftop(q, YT + h)
		x += wdt


func _shops(lot: Rect2) -> void:
	ground(lot, 0)
	var clothes := Rect2(lot.position.x + 2, lot.position.y + 1, 18, 14)
	bld(clothes, YT, 8.0, 4, Color(0.95, 0.93, 0.9))
	neon_sign(Vector3(clothes.get_center().x, YT + 5.6, clothes.position.y - 0.15), Vector3(9, 1.2, 0.2), "neon_pink")
	awning(clothes.position.x + 1, clothes.end.x - 1, clothes.position.y, YT + 3.3, 1.5, -1, Color(0.85, 0.3, 0.45))
	w.register_poi("clothes", Vector3(clothes.get_center().x, YT, clothes.position.y - 1.6), PI)
	var barber := Rect2(lot.position.x + 44, lot.position.y + 1, 14, 12)
	bld(barber, YT, 7.0, 4, Color(0.2, 0.42, 0.5))
	neon_sign(Vector3(barber.get_center().x, YT + 5.2, barber.position.y - 0.15), Vector3(7, 1.0, 0.2), "neon_teal")
	# barber pole
	mb.use("vc").col(Color(0.9, 0.2, 0.2))
	mb.cylinder(Vector3(barber.position.x + 1.0, YT + 1.0, barber.position.y - 0.4), 0.15, 1.6, 8)
	w.register_poi("barber", Vector3(barber.get_center().x, YT, barber.position.y - 1.6), PI)
	_commercial_row(Rect2(lot.position.x + 21, lot.position.y + 1, 22, 13), true)
	_commercial_row(Rect2(lot.position.x + 59, lot.position.y + 1, lot.size.x - 60, 13), true)
	_tower(Rect2(lot.position.x + 2, lot.position.y + 22, 30, lot.size.y - 24))
	parking(Rect2(lot.position.x + 36, lot.position.y + 24, lot.size.x - 38, lot.size.y - 26), 0.0, "street")


func _dealer(lot: Rect2) -> void:
	ground(lot, 0)
	var show := Rect2(lot.position.x + 4, lot.position.y + 1, 30, 18)
	bld(show, YT, 0.6, 0, Color(0.9, 0.9, 0.9))
	# glass showroom: frame + glass walls (no collision inside → simple solid box collision)
	mb.use("glass").col(Color.WHITE)
	mb.box(Vector3(show.get_center().x, YT + 3.6, show.get_center().y), Vector3(show.size.x, 6.0, show.size.y))
	vbox(Vector3(show.get_center().x, YT + 6.8, show.get_center().y), Vector3(show.size.x + 1.0, 0.5, show.size.y + 1.0), Color(0.95, 0.95, 0.95))
	w.add_box_col(Vector3(show.get_center().x, YT + 3.5, show.get_center().y), Vector3(show.size.x, 7.0, show.size.y))
	neon_sign(Vector3(show.get_center().x, YT + 7.6, show.position.y - 0.4), Vector3(12, 1.2, 0.2), "neon_teal")
	w.register_poi("dealer", Vector3(show.get_center().x, YT, show.position.y - 1.6), PI)
	var lotr := Rect2(lot.position.x + 2, lot.position.y + 22, lot.size.x - 4, lot.size.y - 24)
	ground(lotr, 2)
	var i := 0
	for row in 3:
		for b in int(lotr.size.x / 4.0):
			var p := Vector3(lotr.position.x + 2.0 + b * 4.0, YT + 0.3, lotr.position.y + 4.0 + row * 9.0)
			if p.z > lotr.end.y - 3:
				continue
			w.vehicle_spawns["dealer_%d" % i] = Transform3D(Basis(Vector3.UP, PI), p)
			i += 1


func _gas(lot: Rect2) -> void:
	ground(lot, 2, Color(1.05, 1.05, 1.05))
	var c := Vector2(lot.get_center().x - 4, lot.get_center().y + 8)
	# canopy, pillars, pump islands: Blender model when present (colliders stay simple boxes)
	var glb := ModelLib.bake(mb, "buildings/gas_station", Transform3D(Basis.IDENTITY, Vector3(c.x, YT, c.y)))
	if glb:
		w.add_box_col(Vector3(c.x, YT + 5.3, c.y), Vector3(28, 0.8, 16))
	else:
		vbox(Vector3(c.x, YT + 5.3, c.y), Vector3(28, 0.8, 16), Color(0.95, 0.95, 0.95), "vc", true)
		vbox(Vector3(c.x, YT + 5.3, c.y - 8.05), Vector3(28, 0.6, 0.1), Color(0.95, 0.45, 0.15), "neon_amber")
		mb.use("emit_white").col(Color.WHITE)
		mb.box(Vector3(c.x, YT + 4.85, c.y), Vector3(24, 0.05, 12))
	for px in [-9.0, 0.0, 9.0]:
		for pz in [-4.0, 4.0]:
			if glb:
				w.add_box_col(Vector3(c.x + px, YT + 2.5, c.y + pz), Vector3(0.45, 5.0, 0.45))
			else:
				vbox(Vector3(c.x + px, YT + 2.5, c.y + pz), Vector3(0.4, 5.0, 0.4), Color(0.9, 0.9, 0.9), "vc", true)
	for px in [-9.0, 0.0, 9.0]:
		for pz in [-1.5, 1.5]:
			if glb:
				w.add_box_col(Vector3(c.x + px + 3.0, YT + 1.1, c.y + pz), Vector3(0.9, 2.2, 0.66))
			else:
				vbox(Vector3(c.x + px + 3.0, YT + 0.8, c.y + pz), Vector3(0.9, 1.6, 0.6), Color(0.85, 0.3, 0.2), "gloss", true)
			w.cover_hint_boxes.append(Vector3(c.x + px + 3.0, YT, c.y + pz))
	var shop := Rect2(lot.end.x - 22, lot.position.y + 3, 18, 12)
	bld(shop, YT, 4.5, 4, Color(0.95, 0.9, 0.8))
	neon_sign(Vector3(shop.get_center().x, YT + 3.9, shop.end.y + 0.15), Vector3(8, 0.9, 0.2), "neon_amber")
	w.register_poi("gas", Vector3(c.x, YT, c.y), 0.0)
	# price pylon
	vbox(Vector3(lot.position.x + 3, YT + 4, lot.end.y - 3), Vector3(1.2, 8, 0.5), Color(0.2, 0.2, 0.22))
	mb.use("neon_amber").col(Color.WHITE)
	mb.box(Vector3(lot.position.x + 3, YT + 7, lot.end.y - 2.7), Vector3(1.0, 1.6, 0.1))


func _modshop(lot: Rect2) -> void:
	ground(lot, 6)
	# hollow garage hall with a wide drive-in opening on the south side
	var hall := Rect2(lot.position.x + 16, lot.position.y + 20, 40, 34)
	var h := 9.0
	var t := 0.4
	var col := Color(0.2, 0.22, 0.26)
	bld(Rect2(hall.position.x, hall.position.y, hall.size.x, t), YT, h, 3, col)
	bld(Rect2(hall.position.x, hall.position.y, t, hall.size.y), YT, h, 3, col)
	bld(Rect2(hall.end.x - t, hall.position.y, t, hall.size.y), YT, h, 3, col)
	var door_w := 14.0
	var dx0 := hall.get_center().x - door_w * 0.5
	var dx1 := hall.get_center().x + door_w * 0.5
	bld(Rect2(hall.position.x, hall.end.y - t, dx0 - hall.position.x, t), YT, h, 3, col)
	bld(Rect2(dx1, hall.end.y - t, hall.end.x - dx1, t), YT, h, 3, col)
	bld(Rect2(dx0, hall.end.y - t, door_w, t), YT + 5.5, h - 5.5, 0, col)
	vbox(Vector3(hall.get_center().x, YT + h + 0.15, hall.get_center().y), Vector3(hall.size.x, 0.3, hall.size.y), Color(0.3, 0.32, 0.35), "metal", true)
	# interior: floor, lifts, tool walls, lights
	ground(hall.grow(-t), 6, Color(0.75, 0.75, 0.78), YT + 0.02)
	for k in 2:
		var lx := hall.position.x + 8 + k * 24
		vbox(Vector3(lx, YT + 1.2, hall.get_center().y - 4), Vector3(0.3, 2.4, 0.3), Color(0.9, 0.7, 0.1), "gloss", true)
		vbox(Vector3(lx + 3.4, YT + 1.2, hall.get_center().y - 4), Vector3(0.3, 2.4, 0.3), Color(0.9, 0.7, 0.1), "gloss", true)
	vbox(Vector3(hall.get_center().x, YT + 2.0, hall.position.y + 0.9), Vector3(20, 2.4, 1.0), Color(0.75, 0.15, 0.15), "gloss", true)
	mb.use("emit_white").col(Color.WHITE)
	for k in 3:
		mb.box(Vector3(hall.position.x + 8 + k * 12, YT + h - 0.3, hall.get_center().y), Vector3(1.0, 0.1, 10))
	neon_sign(Vector3(hall.get_center().x, YT + 7.2, hall.end.y + 0.2), Vector3(12, 1.6, 0.2), "neon_pink")
	w.register_poi("modshop", Vector3(hall.get_center().x, YT, hall.get_center().y + 4.0), 0.0)
	w.vehicle_spawns["modshop_out"] = Transform3D(Basis.IDENTITY, Vector3(hall.get_center().x, YT + 0.4, hall.end.y + 6.0))
	# side buildings
	_warehouse(Rect2(lot.position.x + 1, lot.position.y + 1, 13, lot.size.y * 0.5))
	parking(Rect2(lot.position.x + 16, lot.position.y + 2, 40, 14), 0.0, "street")


func _hospital(lot: Rect2) -> void:
	ground(lot, 0)
	var b := Rect2(lot.position.x + 14, lot.position.y + 8, 46, 36)
	bld(b, YT, 18.0, 2, Color(0.95, 0.96, 0.97))
	bld(Rect2(b.position.x + 15, b.end.y - 0.1, 16, 6), YT, 4.5, 4, Color(0.8, 0.88, 0.92))
	vbox(Vector3(b.get_center().x, YT + 5.0, b.end.y + 7.0), Vector3(18, 0.35, 3.0), Color(0.95, 0.95, 0.95))
	for sx in [-1.0, 1.0]:
		vbox(Vector3(b.get_center().x + sx * 8.0, YT + 2.4, b.end.y + 8.0), Vector3(0.3, 4.8, 0.3), Color(0.9, 0.9, 0.9), "vc", true)
	# red cross signs
	for face in [b.end.y + 0.15, b.position.y - 0.15]:
		mb.use("neon_red").col(Color.WHITE)
		mb.box(Vector3(b.get_center().x, YT + 15.0, face), Vector3(3.6, 1.0, 0.2))
		mb.box(Vector3(b.get_center().x, YT + 15.0, face), Vector3(1.0, 3.6, 0.2))
	_helipad(Vector3(b.get_center().x, YT + 18.02, b.get_center().y), 8.0)
	w.vehicle_spawns["hospital_heli"] = Transform3D(Basis.IDENTITY, Vector3(b.get_center().x, YT + 18.6, b.get_center().y))
	w.vehicle_spawns["ambulance"] = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(b.end.x + 5, YT + 0.4, b.end.y + 4))
	w.register_poi("hospital", Vector3(b.get_center().x, YT, b.end.y + 9.0), 0.0)
	parking(Rect2(lot.position.x + 1, lot.position.y + 2, 11, lot.size.y - 4), 0.0, "street")


func _park(lot: Rect2) -> void:
	ground(lot, 1)
	var c := lot.get_center()
	# cross paths
	ground(Rect2(lot.position.x, c.y - 1.5, lot.size.x, 3.0), 5, Color(1, 1, 1), YT + 0.02)
	ground(Rect2(c.x - 1.5, lot.position.y, 3.0, lot.size.y), 5, Color(1, 1, 1), YT + 0.02)
	# pond
	mb.use("vc").col(Color(0.62, 0.6, 0.55))
	mb.cylinder(Vector3(c.x + 18, YT, c.y + 12), 7.0, 0.35, 18)
	mb.use("glass").col(Color.WHITE)
	mb.cylinder(Vector3(c.x + 18, YT + 0.3, c.y + 12), 6.6, 0.02, 18)
	# gazebo
	var g := Vector3(c.x - 18, YT, c.y - 12)
	for k in 6:
		var a := TAU * k / 6.0
		vbox(g + Vector3(cos(a) * 3.0, 1.5, sin(a) * 3.0), Vector3(0.2, 3.0, 0.2), Color(0.95, 0.95, 0.92), "vc", true)
	mb.use("vc").col(Color(0.75, 0.38, 0.28))
	mb.cylinder(g + Vector3(0, 3.0, 0), 3.8, 1.6, 6, true, 0.1)
	vbox(g + Vector3(0, 0.12, 0), Vector3(6.4, 0.24, 6.4), Color(0.75, 0.72, 0.66), "vc", true)
	w.register_poi("park", Vector3(c.x, YT, c.y), 0.0)


func _safehouse(lot: Rect2) -> void:
	ground(lot, 1)
	# player's house: enterable (walls only), garage next to it, both facing the north street
	var house := Rect2(lot.position.x + 14, lot.position.y + 4, 18, 12)
	var hy := YT
	var h := 3.4
	var t := 0.25
	var col := Color(0.98, 0.86, 0.7)
	var door_c := house.get_center().x
	var dw := 1.6
	# walls (style 5 house facade), front wall with door gap
	bld(Rect2(house.position.x, house.position.y, door_c - dw * 0.5 - house.position.x, t), hy, h, 5, col)
	bld(Rect2(door_c + dw * 0.5, house.position.y, house.end.x - door_c - dw * 0.5, t), hy, h, 5, col)
	bld(Rect2(door_c - dw * 0.5, house.position.y, dw, t), hy + 2.3, h - 2.3, 0, col)
	bld(Rect2(house.position.x, house.end.y - t, house.size.x, t), hy, h, 5, col)
	bld(Rect2(house.position.x, house.position.y, t, house.size.y), hy, h, 5, col)
	bld(Rect2(house.end.x - t, house.position.y, t, house.size.y), hy, h, 5, col)
	# interior partition with doorway
	bld(Rect2(house.position.x + 10, house.position.y + t, t, 6.5), hy, h, 0, Color(0.92, 0.9, 0.86))
	# roof
	gable_roof(house, hy + h, 2.6, Color(0.3, 0.5, 0.55), true)
	# floor (wood) and ceiling
	ground(house.grow(-t), 4, Color(1, 1, 1), YT + 0.03)
	vbox(Vector3(house.get_center().x, hy + h - 0.05, house.get_center().y), Vector3(house.size.x - 0.5, 0.1, house.size.y - 0.5), Color(0.96, 0.95, 0.92))
	# furniture
	var ix := house.position.x
	var iz := house.position.y
	if ModelLib.has("interiors/safehouse_set"):
		# Blender furniture set: [part, x, z, yaw, collider size (0 = none)]
		var set := [["bed", 14.5, 8.5, 0.0, Vector3(2.2, 0.75, 3.0)], ["wardrobe", 17.15, 3.0, PI * 0.5, Vector3(0.7, 2.2, 2.0)],
			["sofa", 4.0, 9.9, 0.0, Vector3(4.0, 0.8, 1.2)], ["tv", 4.0, 3.0, PI, Vector3(2.6, 0.5, 0.5)],
			["table", 4.0, 6.0, 0.0, Vector3(1.6, 0.45, 0.9)], ["rug", 4.0, 6.2, 0.0, Vector3.ZERO],
			["kitchen", 0.56, 3.5, -PI * 0.5, Vector3(0.7, 0.95, 3.0)], ["lamp", 7.0, 10.8, 0.0, Vector3.ZERO],
			["plant", 7.4, 0.8, 0.0, Vector3.ZERO], ["plant", 11.0, 11.2, 0.0, Vector3.ZERO],
			["shelf", 10.27, 3.0, -PI * 0.5, Vector3(0.38, 2.0, 1.6)]]
		for it in set:
			var pos := Vector3(ix + it[1], YT + (0.03 if it[0] == "rug" else 0.0), iz + it[2])
			ModelLib.bake(mb, "interiors/safehouse_set", Transform3D(Basis(Vector3.UP, it[3]), pos), {}, it[0])
			var cs: Vector3 = it[4]
			if cs != Vector3.ZERO:
				var off := Vector3(0.18, 0, 0) if it[0] == "shelf" else Vector3.ZERO
				w.add_box_col(pos + off + Vector3(0, cs.y * 0.5, 0), cs)   # sizes are world-aligned
		w.add_box_col(Vector3(ix + 0.6, YT + 0.95, iz + 5.45), Vector3(0.75, 1.9, 0.85))   # fridge
	else:
		vbox(Vector3(ix + 14.5, YT + 0.3, iz + 8.5), Vector3(2.2, 0.6, 3.0), Color(0.3, 0.35, 0.55), "vc", true)        # bed
		vbox(Vector3(ix + 14.5, YT + 0.65, iz + 9.6), Vector3(2.2, 0.25, 0.8), Color(0.95, 0.95, 0.95))                # pillow
		vbox(Vector3(ix + 17.2, YT + 1.1, iz + 3.0), Vector3(0.7, 2.2, 2.0), Color(0.5, 0.33, 0.2), "vc", true)        # wardrobe
		vbox(Vector3(ix + 4.0, YT + 0.4, iz + 9.5), Vector3(4.0, 0.8, 1.2), Color(0.75, 0.3, 0.25), "vc", true)        # sofa
		vbox(Vector3(ix + 4.0, YT + 0.8, iz + 10.3), Vector3(4.0, 0.8, 0.4), Color(0.7, 0.28, 0.23))
		vbox(Vector3(ix + 4.0, YT + 0.9, iz + 3.0), Vector3(2.4, 1.4, 0.15), Color(0.05, 0.05, 0.08))                  # tv
		mb.use("neon_teal").col(Color.WHITE)
		mb.box(Vector3(ix + 4.0, YT + 0.9, iz + 3.1), Vector3(2.2, 1.2, 0.02))
		vbox(Vector3(ix + 4.0, YT + 0.4, iz + 6.0), Vector3(1.6, 0.05, 0.9), Color(0.55, 0.4, 0.25), "vc", true)       # table
	w.register_poi("safehouse", Vector3(door_c, YT, house.position.y - 1.4), PI)
	w.register_poi("bed", Vector3(ix + 14.5, YT, iz + 6.5), 0.0)
	w.register_poi("wardrobe", Vector3(ix + 16.2, YT, iz + 3.0), 0.0)
	var light := OmniLight3D.new()
	light.name = "SafehouseLight"
	light.position = Vector3(house.get_center().x, YT + 3.0, house.get_center().y)
	light.light_color = Color(1.0, 0.85, 0.65)
	light.omni_range = 11.0
	light.light_energy = 1.4
	light.shadow_enabled = false
	w.interior_root.add_child(light)
	# garage
	var gar := Rect2(house.end.x + 1.0, house.position.y, 8, 12)
	bld(Rect2(gar.position.x, gar.position.y + 1.2, gar.size.x, gar.size.y - 1.2), hy, 3.6, 0, col.darkened(0.05))
	vbox(Vector3(gar.get_center().x, YT + 1.6, gar.position.y + 1.15), Vector3(6.4, 3.0, 0.1), Color(0.85, 0.85, 0.85), "metal")
	w.register_poi("garage", Vector3(gar.get_center().x, YT, gar.position.y - 2.5), PI)
	w.vehicle_spawns["safehouse_garage"] = Transform3D(Basis(Vector3.UP, PI), Vector3(gar.get_center().x, YT + 0.4, gar.position.y - 5.5))
	ground(Rect2(gar.position.x + 0.5, lot.position.y - 0.1, 7, gar.position.y - lot.position.y + 0.2), 6, Color(0.9, 0.9, 0.9), YT + 0.02)
	# neighbours
	_house(Rect2(lot.position.x + 34 + 10, lot.position.y, 16, lot.size.y * 0.5), true)
	_house(Rect2(lot.position.x, lot.position.y + lot.size.y * 0.5, 16, lot.size.y * 0.5), false)
	_house(Rect2(lot.position.x + 18, lot.position.y + lot.size.y * 0.5, 16, lot.size.y * 0.5), false)
	_house(Rect2(lot.position.x + 36, lot.position.y + lot.size.y * 0.5, 16, lot.size.y * 0.5), false)
