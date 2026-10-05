class_name Landmarks
extends RefCounted
## Non-grid districts: airfield, docks & marina, promenade, Lantern Pier (Ferris wheel), beach,
## lighthouse, Crown Hill lookout & radio mast, shipwreck, stunt ramps.

const YT := C.LAND_Y + WorldMap.CURB_H
const Y0 := C.LAND_Y

var w: World
var mb := MB.new()
var rng := RandomNumberGenerator.new()


func build(world: World) -> void:
	w = world
	rng.seed = 777
	_airfield()
	_docks()
	_promenade_and_pier()
	_beach()
	_hill()
	_wreck()
	_ramps()
	var mats := {"ground": w.mats["ground"], "road": w.mats["road"], "vc": w.mats["vc"], "gloss": w.mats["vc_gloss"],
		"metal": w.mats["metal"], "glass": w.mats["glass"], "bld": w.mats["bld"], "neon_pink": w.mats["neon_pink"],
		"neon_teal": w.mats["neon_teal"], "neon_amber": w.mats["neon_amber"], "neon_red": w.mats["neon_red"],
		"emit_warm": w.mats["emit_warm"], "emit_white": w.mats["emit_white"]}
	w.add_mesh(mb.commit(mats), "Landmarks")


func vbox(center: Vector3, size: Vector3, c: Color, surface := "vc", collide := false, surf := C.SURF_CONCRETE) -> void:
	mb.use(surface).col(c)
	mb.box(center, size)
	if collide:
		w.add_box_col(center, size, 0.0, surf)


func ground(r: Rect2, kind: int, y: float, tint := Color.WHITE) -> void:
	mb.use("ground")
	mb.uv2 = Vector2(kind, 0)
	mb.col(tint)
	var a := r.position
	var b := r.end
	mb.quad_uv(Vector3(a.x, y, a.y), Vector3(b.x, y, a.y), Vector3(b.x, y, b.y), Vector3(a.x, y, b.y),
		Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(a.x, b.y), Vector3.UP)


func bld(r: Rect2, y: float, h: float, style: int, c: Color, collide := true) -> void:
	mb.use("bld")
	mb.uv2 = Vector2(style, rng.randf() * 10.0)
	mb.col(c)
	var ctr := r.get_center()
	mb.prism(Vector3(ctr.x, y, ctr.y), h, r.size * 0.5, r.size * 0.5)
	if collide:
		w.add_box_col(Vector3(ctr.x, y + h * 0.5, ctr.y), Vector3(r.size.x, h, r.size.y))


# ------------------------------------------------------------------ airfield

func _airfield() -> void:
	var y := Y0 + 0.03
	# runway (east-west) using road shader runway mode
	var rw_a := Vector3(-262, y, -231)
	var rw_b := Vector3(68, y, -231)
	var hw := 15.0
	mb.use("road")
	mb.uv2 = Vector2(9, rw_a.distance_to(rw_b))
	mb.col(Color(hw / 20.0, 0, 0))
	var right := Vector3(0, 0, 1)
	var length := rw_a.distance_to(rw_b)
	mb.quad_uv(rw_a - right * hw, rw_a + right * hw, rw_b + right * hw, rw_b - right * hw,
		Vector2(-hw, 0), Vector2(hw, 0), Vector2(hw, length), Vector2(-hw, length), Vector3.UP)
	# taxiway + connectors
	mb.uv2 = Vector2(0, 0)
	mb.col(Color(0, 0, 0))
	var taxi := Rect2(-245, -214, 300, 12)
	_road_rect(taxi, y)
	_road_rect(Rect2(-245, -216, 12, 4), y)
	_road_rect(Rect2(43, -216, 12, 4), y)
	vbox(Vector3(taxi.get_center().x, y + 0.005, taxi.get_center().y), Vector3(taxi.size.x, 0.01, 0.25), Color(0.95, 0.75, 0.15))
	# apron
	ground(Rect2(-250, -202, 290, 26), 6, y + 0.01, Color(0.95, 0.95, 0.95))
	ground(Rect2(-250, -176, 290, 39), 6, y, Color(0.9, 0.9, 0.9))
	# hangars (curved roof via stepped prisms), doors facing north toward the apron
	for i in 3:
		var hx := -225.0 + i * 52.0
		var r := Rect2(hx - 20, -172, 40, 30)
		_hangar(r)
		w.vehicle_spawns["plane_%d" % i] = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(hx, Y0 + 1.4, -190))
	# terminal + control tower
	bld(Rect2(-60, -170, 40, 20), Y0, 7.0, 1, Color(0.9, 0.92, 0.95))
	var tower_c := Vector3(-8, Y0, -160)
	mb.use("vc").col(Color(0.92, 0.92, 0.9))
	mb.cylinder(tower_c, 2.6, 22.0, 12)
	w.add_cyl_col(tower_c, 2.6, 22.0)
	mb.use("glass").col(Color.WHITE)
	mb.cylinder(tower_c + Vector3(0, 22, 0), 4.5, 3.6, 12, true, 4.8)
	mb.use("vc").col(Color(0.3, 0.32, 0.36))
	mb.cylinder(tower_c + Vector3(0, 25.6, 0), 5.0, 0.6, 12)
	mb.use("neon_red").col(Color.WHITE)
	mb.box(tower_c + Vector3(0, 27.2, 0), Vector3(0.4, 0.4, 0.4))
	vbox(tower_c + Vector3(0, 26.5, 0), Vector3(0.12, 2.0, 0.12), Color(0.3, 0.3, 0.3), "metal")
	# helipad
	var hp := Vector3(30, y + 0.02, -190)
	mb.use("ground")
	mb.uv2 = Vector2(9, 0)
	mb.col(Color.WHITE)
	var rr := 9.0
	mb.quad_uv(hp + Vector3(-rr, 0, -rr), hp + Vector3(rr, 0, -rr), hp + Vector3(rr, 0, rr), hp + Vector3(-rr, 0, rr),
		Vector2(-rr, -rr), Vector2(rr, -rr), Vector2(rr, rr), Vector2(-rr, rr), Vector3.UP)
	w.vehicle_spawns["heli_pad"] = Transform3D(Basis.IDENTITY, hp + Vector3(0, 0.6, 0))
	w.register_poi("helipad", hp, 0.0)
	w.register_poi("airfield", Vector3(-150, Y0, -150), 0.0)
	# runway approach lights
	for k in 12:
		var x := -262.0 + k * 30.0
		for side in [-1.0, 1.0]:
			mb.use("emit_white").col(Color.WHITE)
			mb.box(Vector3(x, y + 0.15, -231 + side * 15.5), Vector3(0.3, 0.3, 0.3))
	# windsock
	vbox(Vector3(-100, Y0 + 3.0, -222), Vector3(0.12, 6.0, 0.12), Color(0.8, 0.8, 0.8), "metal")
	mb.use("vc").col(Color(1.0, 0.45, 0.1))
	mb.cylinder_axis(Vector3(-98.6, Y0 + 5.8, -222), Vector3.RIGHT, 0.45, 2.6, 8, false, 0.2)
	# perimeter fence along the north coast
	for k in 32:
		var x := -270.0 + k * 10.0
		vbox(Vector3(x, Y0 + 1.0, -262), Vector3(0.1, 2.0, 0.1), Color(0.5, 0.52, 0.55), "metal")
	mb.use("glass").col(Color.WHITE)
	mb.box(Vector3(-115, Y0 + 1.0, -262), Vector3(310, 1.8, 0.03))
	w.add_box_col(Vector3(-115, Y0 + 1.0, -262), Vector3(310, 2.0, 0.2), 0.0, C.SURF_METAL)


func _road_rect(r: Rect2, y: float) -> void:
	mb.use("road")
	mb.uv2 = Vector2(0, 0)
	mb.col(Color(0, 0, 0))
	var a := r.position
	var b := r.end
	mb.quad_uv(Vector3(a.x, y, a.y), Vector3(b.x, y, a.y), Vector3(b.x, y, b.y), Vector3(a.x, y, b.y),
		Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP)


func _hangar(r: Rect2) -> void:
	var c := r.get_center()
	var col := Color(0.78, 0.8, 0.82)
	var h := 7.0
	# back + side walls, open front (north side, -z) with a big door frame
	bld(Rect2(r.position.x, r.end.y - 0.4, r.size.x, 0.4), Y0, h, 3, col)
	bld(Rect2(r.position.x, r.position.y, 0.4, r.size.y), Y0, h, 3, col)
	bld(Rect2(r.end.x - 0.4, r.position.y, 0.4, r.size.y), Y0, h, 3, col)
	bld(Rect2(r.position.x, r.position.y, r.size.x, 0.4), Y0 + 6.0, h - 6.0, 0, col)
	# arched roof built from segments
	var segs := 8
	for i in segs:
		var a0 := PI * float(i) / segs
		var a1 := PI * float(i + 1) / segs
		var x0 := c.x - cos(a0) * r.size.x * 0.5
		var x1 := c.x - cos(a1) * r.size.x * 0.5
		var y0 := Y0 + h + sin(a0) * 5.0
		var y1 := Y0 + h + sin(a1) * 5.0
		mb.use("metal").col(Color(0.62, 0.64, 0.68))
		mb.quad(Vector3(x0, y0, r.position.y), Vector3(x1, y1, r.position.y), Vector3(x1, y1, r.end.y), Vector3(x0, y0, r.end.y), Vector3(-cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0))
		mb.quad(Vector3(x0, y0, r.position.y), Vector3(x0, y0, r.end.y), Vector3(x1, y1, r.end.y), Vector3(x1, y1, r.position.y), Vector3(cos((a0 + a1) * 0.5), -sin((a0 + a1) * 0.5), 0))
	# gable ends of the arch
	for zz in [r.position.y, r.end.y]:
		var pts := [Vector3(r.position.x, Y0 + h, zz)]
		for i in segs + 1:
			var a := PI * float(i) / segs
			pts.append(Vector3(c.x - cos(a) * r.size.x * 0.5, Y0 + h + sin(a) * 5.0, zz))
		mb.use("metal").col(col.darkened(0.1))
		mb.poly(pts, Vector3(0, 0, -1 if zz == r.position.y else 1))
		mb.poly(pts, Vector3(0, 0, 1 if zz == r.position.y else -1))
	w.add_box_col(Vector3(c.x, Y0 + h + 2.5, c.y), Vector3(r.size.x, 5.0, r.size.y))
	ground(r.grow(-0.4), 6, Y0 + 0.04, Color(0.8, 0.8, 0.82))
	var light := OmniLight3D.new()
	light.position = Vector3(c.x, Y0 + 6.0, c.y)
	light.omni_range = 18.0
	light.light_energy = 0.8
	light.light_color = Color(0.9, 0.95, 1.0)
	w.interior_root.add_child(light)


# ------------------------------------------------------------------ docks

func _docks() -> void:
	# quay slabs around the harbour basin
	var quays := [Rect2(-270, 160.5, 23, 24), Rect2(-247, 160.5, 124, 12.5), Rect2(-123, 160.5, 13, 36)]
	for q in quays:
		RoadBuilder.add_slab_mesh(mb.use("ground"), q, Y0, YT, 6)
		w.add_slab_col(q, Y0 - 0.5, YT, 0.05)
	# quay edge bollards + bumper
	for k in 20:
		var x := -244.0 + k * 6.0
		vbox(Vector3(x, YT + 0.35, 172.4), Vector3(0.4, 0.7, 0.4), Color(0.25, 0.25, 0.28), "metal", true, C.SURF_METAL)
	vbox(Vector3(-185, YT - 0.6, 173.1), Vector3(124, 1.2, 0.3), Color(0.2, 0.2, 0.2))
	# gantry cranes
	for cx in [-226.0, -146.0]:
		_crane(Vector3(cx, YT, 166.0))
	# container stacks on the west quay
	var cols := [Color(0.8, 0.3, 0.2), Color(0.2, 0.45, 0.7), Color(0.85, 0.65, 0.2), Color(0.3, 0.6, 0.4)]
	for i in 3:
		for s in rng.randi_range(1, 3):
			var c: Color = cols[rng.randi() % cols.size()]
			vbox(Vector3(-262 + i * 3.0, YT + 1.3 + s * 2.6, 172), Vector3(2.44, 2.59, 6.06), c, "vc", true, C.SURF_METAL)
	# marina piers (wood) into the basin
	for i in 3:
		var px := -220.0 + i * 30.0
		var pier := Rect2(px - 1.5, 173, 3.0, 42)
		ground(pier, 4, Y0 + 0.1)
		w.add_box_col(Vector3(px, Y0 - 0.1, 194), Vector3(3.0, 0.4, 42))
		for k in 8:
			mb.use("vc").col(Color(0.4, 0.3, 0.2))
			mb.cylinder(Vector3(px - 1.6, -3.0, 176 + k * 5.5), 0.18, 4.4, 6)
			mb.cylinder(Vector3(px + 1.6, -3.0, 176 + k * 5.5), 0.18, 4.4, 6)
		for k in 3:
			w.vehicle_spawns["boat_%d_%d" % [i, k]] = Transform3D(Basis(Vector3.UP, PI), Vector3(px + 6.0, 0.4, 182 + k * 11.0))
	w.register_poi("marina", Vector3(-190, YT, 168), 0.0)
	# harbour warehouse
	bld(Rect2(-123, 165, 12, 28), YT, 8.0, 3, Color(0.55, 0.42, 0.35))


func _crane(base: Vector3) -> void:
	if ModelLib.bake(mb, "buildings/gantry_crane", Transform3D(Basis.IDENTITY, base)):
		for dx in [-5.0, 5.0]:
			for dz in [-3.0, 3.0]:
				w.add_box_col(base + Vector3(dx, 9.0, dz), Vector3(0.8, 18.0, 0.8), 0.0, C.SURF_METAL)
		w.add_box_col(base + Vector3(0, 18.5, 8.0), Vector3(5.2, 1.6, 34.0), 0.0, C.SURF_METAL)
		w.add_box_col(base + Vector3(0, 20.5, -5.0), Vector3(6.0, 2.2, 5.0), 0.0, C.SURF_METAL)
		return
	var col := Color(0.92, 0.55, 0.12)
	for dx in [-5.0, 5.0]:
		for dz in [-3.0, 3.0]:
			vbox(base + Vector3(dx, 9.0, dz), Vector3(0.7, 18.0, 0.7), col, "gloss", true, C.SURF_METAL)
	vbox(base + Vector3(0, 18.5, 8.0), Vector3(12.0, 1.4, 34.0), col, "gloss", true, C.SURF_METAL)
	vbox(base + Vector3(0, 20.2, -2.0), Vector3(6.0, 2.0, 5.0), Color(0.9, 0.9, 0.88), "vc")
	vbox(base + Vector3(0, 14.0, 20.0), Vector3(3.0, 0.6, 3.0), Color(0.3, 0.3, 0.32), "metal")
	mb.use("neon_red").col(Color.WHITE)
	mb.box(base + Vector3(0, 21.5, 24.0), Vector3(0.4, 0.4, 0.4))


# ------------------------------------------------------------------ promenade & Lantern Pier

func _promenade_and_pier() -> void:
	var prom := Rect2(-110, 160.5, 175, 36)
	RoadBuilder.add_slab_mesh(mb.use("ground"), prom, Y0, YT, 5)
	w.add_slab_col(prom, Y0 - 0.5, YT, 0.05)
	# sea railing
	for k in 35:
		var x := -108.0 + k * 5.0
		vbox(Vector3(x, YT + 0.55, 196.2), Vector3(0.08, 1.1, 0.08), Color(0.9, 0.9, 0.9), "metal")
	vbox(Vector3(-22.5, YT + 1.05, 196.2), Vector3(175, 0.08, 0.08), Color(0.9, 0.9, 0.9), "metal", false)
	w.add_box_col(Vector3(-22.5, YT + 0.6, 196.3), Vector3(175, 1.2, 0.15), 0.0, C.SURF_METAL)
	# food stand
	var fs := Vector3(-62, YT, 172)
	vbox(fs + Vector3(0, 1.3, 0), Vector3(5, 2.6, 3.2), Color(0.95, 0.85, 0.3), "vc", true)
	mb.use("vc").col(Color(0.9, 0.25, 0.25))
	mb.box_xf(Transform3D(Basis(Vector3.RIGHT, -0.25), fs + Vector3(0, 2.7, -2.0)), Vector3(5.6, 0.1, 1.8))
	mb.use("neon_amber").col(Color.WHITE)
	mb.box(fs + Vector3(0, 3.1, -1.65), Vector3(3.5, 0.6, 0.1))
	w.register_poi("food", fs + Vector3(0, 0, -2.8), PI)
	# --- Lantern Pier: deck on piles, Ferris wheel at the end
	var deck_y := YT + 0.05
	var pier := Rect2(-38, 196, 12, 64)
	var plat := Rect2(-58, 256, 52, 44)
	for r in [pier, plat]:
		ground(r, 4, deck_y)
		w.add_box_col(Vector3(r.get_center().x, deck_y - 0.25, r.get_center().y), Vector3(r.size.x, 0.5, r.size.y))
		vbox(Vector3(r.get_center().x, deck_y - 0.4, r.get_center().y), Vector3(r.size.x, 0.3, r.size.y), Color(0.38, 0.28, 0.2))
	for k in 12:
		var z := 200.0 + k * 8.0
		for x in [-37.5, -26.5]:
			mb.use("vc").col(Color(0.35, 0.27, 0.2))
			mb.cylinder(Vector3(x, -8.0, z), 0.3, 9.0, 6)
	# railings
	for z in range(198, 258, 4):
		for x in [-37.8, -26.2]:
			vbox(Vector3(x, deck_y + 0.5, z), Vector3(0.08, 1.0, 0.08), Color(0.95, 0.95, 0.95), "metal")
	w.add_box_col(Vector3(-37.9, deck_y + 0.5, 227), Vector3(0.15, 1.0, 60), 0.0, C.SURF_METAL)
	w.add_box_col(Vector3(-26.1, deck_y + 0.5, 227), Vector3(0.15, 1.0, 60), 0.0, C.SURF_METAL)
	# entrance arch with neon
	vbox(Vector3(-38.5, deck_y + 3.0, 197), Vector3(0.6, 6.0, 0.6), Color(0.15, 0.2, 0.3), "vc", true)
	vbox(Vector3(-25.5, deck_y + 3.0, 197), Vector3(0.6, 6.0, 0.6), Color(0.15, 0.2, 0.3), "vc", true)
	vbox(Vector3(-32, deck_y + 6.2, 197), Vector3(14, 1.2, 0.5), Color(0.15, 0.2, 0.3))
	mb.use("neon_pink").col(Color.WHITE)
	mb.box(Vector3(-32, deck_y + 6.2, 196.7), Vector3(11, 0.7, 0.1))
	# stalls
	for k in 4:
		var sx := -52.0 + k * 9.0
		var sc := Color.from_hsv(k * 0.22, 0.55, 0.95)
		vbox(Vector3(sx, deck_y + 1.2, 262), Vector3(4.0, 2.4, 3.0), sc, "vc", true)
		mb.use("vc").col(Color(0.95, 0.95, 0.95))
		mb.prism(Vector3(sx, deck_y + 2.4, 262), 1.2, Vector2(2.3, 1.8), Vector2(0.1, 0.1))
	# Ferris wheel (animated)
	var fw := FerrisWheel.new()
	fw.name = "FerrisWheel"
	fw.position = Vector3(-32, deck_y + 17.0, 288)
	w.add_child(fw)
	fw.build(w)
	vbox(Vector3(-32, deck_y + 8.5, 288 - 3.5), Vector3(1.0, 17.0, 1.0), Color(0.85, 0.85, 0.9), "metal", true, C.SURF_METAL)
	vbox(Vector3(-32, deck_y + 8.5, 288 + 3.5), Vector3(1.0, 17.0, 1.0), Color(0.85, 0.85, 0.9), "metal", true, C.SURF_METAL)
	w.register_poi("pier", Vector3(-32, deck_y, 280), 0.0)


# ------------------------------------------------------------------ beach

func _beach() -> void:
	# lifeguard tower
	var lg := Vector3(170, WorldMap.height(170, 182), 182)
	if ModelLib.bake(mb, "buildings/lifeguard_tower", Transform3D(Basis.IDENTITY, lg)):
		w.add_box_col(lg + Vector3(0, 3.2, 0), Vector3(3.2, 0.2, 3.2), 0.0, C.SURF_WOOD)
		w.add_box_col(lg + Vector3(0, 4.3, 0.15), Vector3(2.6, 2.0, 2.3))
	else:
		for dx in [-1.0, 1.0]:
			for dz in [-1.0, 1.0]:
				vbox(lg + Vector3(dx, 1.5, dz), Vector3(0.18, 3.0, 0.18), Color(0.95, 0.95, 0.95), "vc")
		vbox(lg + Vector3(0, 3.2, 0), Vector3(3.0, 0.2, 3.0), Color(0.95, 0.95, 0.95), "vc", true)
		vbox(lg + Vector3(0, 4.3, 0), Vector3(2.6, 2.0, 2.6), Color(0.95, 0.3, 0.3), "vc", true)
		mb.use("vc").col(Color(0.95, 0.95, 0.95))
		mb.prism(lg + Vector3(0, 5.3, 0), 0.9, Vector2(1.8, 1.8), Vector2(0.1, 0.1))
	w.ladders.append({"bottom": lg + Vector3(0, 0, -1.9), "top": lg + Vector3(0, 3.3, -0.6), "normal": Vector3(0, 0, -1), "top_y": lg.y + 3.3})
	# umbrellas + towels
	for k in 14:
		var x := rng.randf_range(80, 280)
		var z := rng.randf_range(170, 190)
		var y := WorldMap.height(x, z)
		if y < 0.3:
			continue
		var c := Color.from_hsv(rng.randf(), 0.6, 0.95)
		vbox(Vector3(x, y + 1.2, z), Vector3(0.06, 2.4, 0.06), Color(0.9, 0.9, 0.9), "vc")
		mb.use("vc").col(c)
		mb.cylinder(Vector3(x, y + 2.2, z), 1.5, 0.5, 8, true, 0.05)
		vbox(Vector3(x + 1.0, y + 0.03, z + 1.2), Vector3(0.8, 0.04, 1.8), c.lightened(0.3))
	# volleyball net
	var vn := Vector3(230, WorldMap.height(230, 178), 178)
	vbox(vn + Vector3(-4, 1.2, 0), Vector3(0.1, 2.4, 0.1), Color(0.9, 0.9, 0.9), "vc")
	vbox(vn + Vector3(4, 1.2, 0), Vector3(0.1, 2.4, 0.1), Color(0.9, 0.9, 0.9), "vc")
	mb.use("glass").col(Color.WHITE)
	mb.box(vn + Vector3(0, 2.0, 0), Vector3(8, 0.9, 0.02))
	# beach bar
	var bb := Vector3(110, YT, 166)
	if ModelLib.bake(mb, "buildings/beach_bar", Transform3D(Basis.IDENTITY, bb)):
		w.add_box_col(bb + Vector3(0, 1.2, 0.3), Vector3(8, 2.4, 3.4), 0.0, C.SURF_WOOD)
	else:
		vbox(bb + Vector3(0, 1.2, 0), Vector3(8, 2.4, 4), Color(0.75, 0.55, 0.35), "vc", true, C.SURF_WOOD)
		mb.use("vc").col(Color(0.85, 0.75, 0.45))
		mb.prism(bb + Vector3(0, 2.4, 0), 1.6, Vector2(5, 3), Vector2(0.2, 0.2))
	# lighthouse at the east end
	var lh := Vector3(272, WorldMap.height(272, 190) - 0.2, 190)
	var lh_glb := ModelLib.bake(mb, "buildings/lighthouse", Transform3D(Basis.IDENTITY, lh))
	if not lh_glb:
		for i in 6:
			mb.use("vc").col(Color(0.95, 0.95, 0.95) if i % 2 == 0 else Color(0.85, 0.2, 0.2))
			mb.cylinder(lh + Vector3(0, i * 3.5, 0), 3.0 - i * 0.25, 3.5, 14, false, 3.0 - (i + 1) * 0.25)
		mb.use("glass").col(Color.WHITE)
		mb.cylinder(lh + Vector3(0, 21, 0), 1.6, 2.2, 10)
		mb.use("vc").col(Color(0.2, 0.2, 0.22))
		mb.cylinder(lh + Vector3(0, 23.2, 0), 1.9, 1.2, 10, true, 0.2)
	w.add_cyl_col(lh, 2.6, 22.0 if lh_glb else 21.0)
	var beacon := LighthouseBeacon.new()
	beacon.position = lh + Vector3(0, 23.2 if lh_glb else 22.1, 0)
	w.add_child(beacon)
	w.register_poi("beach", Vector3(200, YT, 170), 0.0)
	w.vehicle_spawns["beach_boat"] = Transform3D(Basis(Vector3.UP, PI), Vector3(200, 0.4, 222))


# ------------------------------------------------------------------ Crown Hill

func _hill() -> void:
	var top := Vector3(196, 0, -204)
	top.y = WorldMap.height(top.x, top.z)
	# lookout deck
	var deck := Rect2(top.x - 7, top.z - 7, 14, 14)
	vbox(Vector3(top.x, top.y + 0.6, top.z), Vector3(14, 0.4, 14), Color(0.55, 0.4, 0.28), "vc", true, C.SURF_WOOD)
	for k in 8:
		var a := TAU * k / 8.0
		vbox(Vector3(top.x + cos(a) * 7, top.y + 0.2, top.z + sin(a) * 7), Vector3(0.3, 1.6, 0.3), Color(0.4, 0.3, 0.2))
	for side in 4:
		var n := Vector3([0, 1, 0, -1][side], 0, [1, 0, -1, 0][side])
		var c := Vector3(top.x, top.y + 1.35, top.z) + n * 6.9
		var size := Vector3(14 if n.x == 0 else 0.1, 1.0, 14 if n.z == 0 else 0.1)
		if side == 2:
			continue  # open side (road arrival)
		vbox(c, size, Color(0.45, 0.33, 0.22), "vc", true, C.SURF_WOOD)
	# binoculars
	vbox(Vector3(top.x + 4, top.y + 1.4, top.z + 4), Vector3(0.15, 1.2, 0.15), Color(0.3, 0.3, 0.3), "metal")
	vbox(Vector3(top.x + 4, top.y + 2.0, top.z + 4), Vector3(0.5, 0.3, 0.6), Color(0.2, 0.4, 0.6), "gloss")
	w.register_poi("viewpoint", Vector3(top.x, top.y + 0.8, top.z), 0.0)
	# radio mast (lattice approximation)
	var mast := Vector3(232, 0, -214)
	mast.y = WorldMap.height(mast.x, mast.z)
	if ModelLib.bake(mb, "buildings/radio_mast", Transform3D(Basis.IDENTITY, mast)):
		w.add_box_col(Vector3(mast.x, mast.y + 25, mast.z), Vector3(4.0, 50, 4.0), 0.0, C.SURF_METAL)
		w.add_box_col(mast + Vector3(6.0, 1.3, 0), Vector3(4.0, 2.6, 3.0))
		# concrete pad under the equipment hut where the hillside falls away
		var hy := WorldMap.height(mast.x + 6.0, mast.z)
		if hy < mast.y - 0.05:
			vbox(Vector3(mast.x + 6.0, (hy + mast.y) * 0.5 - 0.3, mast.z), Vector3(4.6, mast.y - hy + 0.6, 3.6), Color(0.6, 0.6, 0.58), "vc", true)
		return
	for i in 10:
		var y := mast.y + i * 5.0
		var s := 2.4 - i * 0.2
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				vbox(Vector3(mast.x + cx * s, y + 2.5, mast.z + cz * s), Vector3(0.18, 5.0, 0.18), Color(0.85, 0.2, 0.15) if i % 2 == 0 else Color(0.95, 0.95, 0.95), "metal")
		vbox(Vector3(mast.x, y + 5.0, mast.z), Vector3(s * 2.0, 0.12, s * 2.0), Color(0.6, 0.6, 0.6), "metal")
	w.add_box_col(Vector3(mast.x, mast.y + 25, mast.z), Vector3(4.0, 50, 4.0), 0.0, C.SURF_METAL)
	mb.use("neon_red").col(Color.WHITE)
	mb.box(Vector3(mast.x, mast.y + 51, mast.z), Vector3(0.6, 0.6, 0.6))


# ------------------------------------------------------------------ shipwreck

func _wreck() -> void:
	var p := WorldMap.WRECK_POS
	var hull := Color(0.35, 0.3, 0.27)
	var xf := Transform3D(Basis(Vector3.UP, 0.6) * Basis(Vector3.FORWARD, 0.35), p)
	if ModelLib.bake(mb, "buildings/shipwreck", xf):
		w.add_xform_box_col(xf, Vector3(8, 1.0, 30))
		w.add_xform_box_col(xf * Transform3D(Basis.IDENTITY, Vector3(-3.6, 2.2, 0)), Vector3(0.5, 4.4, 30))
		w.add_xform_box_col(xf * Transform3D(Basis.IDENTITY, Vector3(3.6, 2.2, 0)), Vector3(0.5, 4.4, 30))
		w.add_xform_box_col(xf * Transform3D(Basis.IDENTITY, Vector3(0, 6.0, 8)), Vector3(5.0, 3.0, 6.0))
		for k in 6:
			var cp2 := p + Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-14, 14))
			cp2.y = WorldMap.height(cp2.x, cp2.z) + 0.5
			vbox(cp2, Vector3(1.0, 1.0, 1.0), Color(0.5, 0.38, 0.22))
		w.register_poi("wreck", p + Vector3(0, 3, 0), 0.0)
		return
	mb.use("vc").col(hull)
	mb.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)), Vector3(8.0, 0.4, 30.0))
	mb.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(-3.8, 2.2, 0)), Vector3(0.4, 4.4, 30.0))
	mb.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(3.8, 1.6, -4)), Vector3(0.4, 3.2, 22.0))
	mb.box_xf(xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.0, 8)), Vector3(5.0, 3.0, 6.0))
	mb.box_xf(xf * Transform3D(Basis(Vector3.RIGHT, 0.5), Vector3(0, 6.0, -3)), Vector3(0.5, 12.0, 0.5))
	w.add_xform_box_col(xf, Vector3(8, 1.0, 30))
	w.add_xform_box_col(xf * Transform3D(Basis.IDENTITY, Vector3(-3.8, 2.2, 0)), Vector3(0.5, 4.4, 30))
	for k in 6:
		var cp := p + Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-14, 14))
		cp.y = WorldMap.height(cp.x, cp.z) + 0.5
		vbox(cp, Vector3(1.0, 1.0, 1.0), Color(0.5, 0.38, 0.22))
	w.register_poi("wreck", p + Vector3(0, 3, 0), 0.0)


# ------------------------------------------------------------------ stunt ramps

func _ramps() -> void:
	var ramps := [
		{"pos": Vector3(-232, YT, 30.0), "yaw": PI * 0.5, "name": "Ironside Yard Leap"},
		{"pos": Vector3(-140, YT, 167.0), "yaw": PI, "name": "Harbour Hop"},
		{"pos": Vector3(150, WorldMap.height(150, 192) + 0.05, 192.0), "yaw": PI, "name": "Coral Beach Launch"},
		{"pos": Vector3(70, Y0 + 0.02, -150.0), "yaw": -PI * 0.5, "name": "Airfield Kicker"},
	]
	for r in ramps:
		var base: Vector3 = r.pos
		var yaw: float = r.yaw
		var b := Basis(Vector3.UP, yaw)
		var fwd := b * Vector3(0, 0, -1)
		var right := b * Vector3(1, 0, 0)
		var L := 9.0
		var H := 2.4
		var hw := 2.6
		var p0 := base - right * hw
		var p1 := base + right * hw
		var p2 := base + right * hw + fwd * L + Vector3(0, H, 0)
		var p3 := base - right * hw + fwd * L + Vector3(0, H, 0)
		var p4 := base + right * hw + fwd * L
		var p5 := base - right * hw + fwd * L
		mb.use("metal").col(Color(0.95, 0.75, 0.2))
		mb.quad(p0, p1, p2, p3, Vector3.UP - fwd)
		mb.quad(p5, p4, p2, p3, fwd)
		mb.tri(p1, p4, p2, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, right)
		mb.tri(p0, p3, p5, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, -right)
		var pts := PackedVector3Array([p0, p1, p2, p3, p4, p5])
		w.add_convex_col(pts, C.SURF_METAL)
		w.stunt_jumps.append({"pos": base + fwd * L + Vector3(0, H, 0), "yaw": yaw, "name": r.name, "auto": false})
