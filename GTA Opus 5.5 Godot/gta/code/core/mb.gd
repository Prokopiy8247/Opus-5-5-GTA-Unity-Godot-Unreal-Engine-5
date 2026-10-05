class_name MB
extends RefCounted
## Mesh Builder: small procedural modelling kit used for runtime-generated, project-owned geometry
## (roads, terrain dressing, fallback visuals). Flat-shaded, multi-surface, auto-orients faces.
## Convention: polygons are given counter-clockwise as seen from OUTSIDE (math convention);
## the builder emits them clockwise for Godot's front-face winding and stores explicit normals.

var surf := {}
var cur := "default"
var color := Color.WHITE
var xform := Transform3D.IDENTITY
var uv2 := Vector2.ZERO
var smooth := false


func use(key: String) -> MB:
	cur = key
	if not surf.has(key):
		surf[key] = {
			"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(),
			"uv": PackedVector2Array(), "uv2": PackedVector2Array(),
		}
	return self


func col(c: Color) -> MB:
	color = c
	return self


func _s() -> Dictionary:
	if not surf.has(cur):
		use(cur)
	return surf[cur]


func tri(a: Vector3, b: Vector3, c: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, hint := Vector3.ZERO) -> void:
	a = xform * a
	b = xform * b
	c = xform * c
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	if hint != Vector3.ZERO and n.dot(xform.basis * hint) < 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
		n = -n
	n = n.normalized()
	var s := _s()
	# Godot front faces are clockwise -> emit a, c, b
	s.v.append(a); s.v.append(c); s.v.append(b)
	s.n.append(n); s.n.append(n); s.n.append(n)
	s.c.append(color); s.c.append(color); s.c.append(color)
	s.uv.append(ua); s.uv.append(uc); s.uv.append(ub)
	s.uv2.append(uv2); s.uv2.append(uv2); s.uv2.append(uv2)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint := Vector3.ZERO, uv_scale := 1.0) -> void:
	# planar-ish quad a-b-c-d, UV in metres along edges a->b (u) and a->d (v)
	var w := a.distance_to(b) * uv_scale
	var h := a.distance_to(d) * uv_scale
	tri(a, b, c, Vector2(0, h), Vector2(w, h), Vector2(w, 0), hint)
	tri(a, c, d, Vector2(0, h), Vector2(w, 0), Vector2(0, 0), hint)


func quad_uv(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, hint := Vector3.ZERO) -> void:
	tri(a, b, c, ua, ub, uc, hint)
	tri(a, c, d, ua, uc, ud, hint)


func poly(pts: Array, hint := Vector3.ZERO) -> void:
	if pts.size() < 3:
		return
	var center := Vector3.ZERO
	for p in pts:
		center += p
	center /= pts.size()
	for i in range(1, pts.size() - 1):
		var a: Vector3 = pts[0]
		var b: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		tri(a, b, c, Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), hint)


func box(center: Vector3, size: Vector3, chamfer := 0.0) -> void:
	prism(center - Vector3(0, size.y * 0.5, 0), size.y, Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z) * 0.5, chamfer)


func _section(half: Vector2, chamfer: float) -> Array:
	var pts := []
	if chamfer <= 0.0:
		pts = [Vector2(half.x, half.y), Vector2(-half.x, half.y), Vector2(-half.x, -half.y), Vector2(half.x, -half.y)]
	else:
		var cx := minf(chamfer, half.x * 0.49)
		var cz := minf(chamfer, half.y * 0.49)
		pts = [
			Vector2(half.x, half.y - cz), Vector2(half.x - cx, half.y), Vector2(-half.x + cx, half.y), Vector2(-half.x, half.y - cz),
			Vector2(-half.x, -half.y + cz), Vector2(-half.x + cx, -half.y), Vector2(half.x - cx, -half.y), Vector2(half.x, -half.y + cz),
		]
	return pts


## Vertical prism: rectangular (optionally chamfered) section lofted from base to base+height,
## top section can be scaled/shifted (tapered limbs, roofs, hoods).
func prism(base: Vector3, height: float, bot_half: Vector2, top_half: Vector2, chamfer := 0.0, top_shift := Vector2.ZERO, caps := true, v0 := 0.0) -> void:
	var sb := _section(bot_half, chamfer)
	var st := _section(top_half, chamfer * (top_half.x / maxf(bot_half.x, 0.001)))
	var n := sb.size()
	var bot := []
	var top := []
	for i in n:
		bot.append(base + Vector3(sb[i].x, 0, sb[i].y))
		top.append(base + Vector3(st[i].x + top_shift.x, height, st[i].y + top_shift.y))
	var axis_mid := base + Vector3(top_shift.x * 0.5, height * 0.5, top_shift.y * 0.5)
	var u := 0.0
	for i in n:
		var j := (i + 1) % n
		var a: Vector3 = bot[i]
		var b: Vector3 = bot[j]
		var c: Vector3 = top[j]
		var d: Vector3 = top[i]
		var w := a.distance_to(b)
		var mid := (a + b + c + d) * 0.25
		var hint := mid - Vector3(axis_mid.x, mid.y, axis_mid.z)
		if hint.length_squared() < 1e-8:
			hint = mid - axis_mid
		quad_uv(a, b, c, d, Vector2(u, v0), Vector2(u + w, v0), Vector2(u + w, v0 + height), Vector2(u, v0 + height), hint)
		u += w
	if caps:
		poly(top, Vector3.UP)
		poly(bot, Vector3.DOWN)


func cylinder(base: Vector3, radius: float, height: float, segs := 10, caps := true, radius_top := -1.0) -> void:
	if radius_top < 0.0:
		radius_top = radius
	var bot := []
	var top := []
	for i in segs:
		var a := TAU * float(i) / segs
		var d := Vector3(cos(a), 0, sin(a))
		bot.append(base + d * radius)
		top.append(base + d * radius_top + Vector3(0, height, 0))
	for i in segs:
		var j := (i + 1) % segs
		var mid: Vector3 = (bot[i] + bot[j] + top[i] + top[j]) * 0.25
		var hint := mid - Vector3(base.x, mid.y, base.z)
		var u0 := float(i) / segs * TAU * radius
		var u1 := float(i + 1) / segs * TAU * radius
		quad_uv(bot[i], bot[j], top[j], top[i], Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, height), Vector2(u0, height), hint)
	if caps:
		if radius_top > 0.001:
			poly(top, Vector3.UP)
		poly(bot, Vector3.DOWN)


## Cylinder along an arbitrary axis (wheels, barrels, pipes).
func cylinder_axis(center: Vector3, axis: Vector3, radius: float, length: float, segs := 10, caps := true, radius_end := -1.0) -> void:
	var old := xform
	var y := axis.normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	var b := Basis(x, y, z)
	xform = old * Transform3D(b, center - y * length * 0.5)
	cylinder(Vector3.ZERO, radius, length, segs, caps, radius_end)
	xform = old


func sphere(center: Vector3, radius: float, segs := 8, rings := 5, squash := Vector3.ONE) -> void:
	var rows := []
	for r in rings + 1:
		var phi := PI * float(r) / rings
		var row := []
		for s in segs:
			var th := TAU * float(s) / segs
			var p := Vector3(sin(phi) * cos(th), cos(phi), sin(phi) * sin(th)) * radius
			row.append(center + p * squash)
		rows.append(row)
	for r in rings:
		for s in segs:
			var t := (s + 1) % segs
			var a: Vector3 = rows[r][s]
			var b: Vector3 = rows[r][t]
			var c: Vector3 = rows[r + 1][t]
			var d: Vector3 = rows[r + 1][s]
			var mid := (a + b + c + d) * 0.25
			if r == 0:
				tri(a, c, d, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, mid - center)
			elif r == rings - 1:
				tri(a, b, c, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, mid - center)
			else:
				quad(a, b, c, d, mid - center)


## Loft through ring sections (each PackedVector3Array / Array with equal point count).
func loft(sections: Array, cap_start := true, cap_end := true, closed := true) -> void:
	if sections.size() < 2:
		return
	var n: int = sections[0].size()
	var centers := []
	for sec in sections:
		var c := Vector3.ZERO
		for p in sec:
			c += p
		centers.append(c / n)
	for k in sections.size() - 1:
		var A = sections[k]
		var B = sections[k + 1]
		var cm: Vector3 = (centers[k] + centers[k + 1]) * 0.5
		var last := n if closed else n - 1
		for i in last:
			var j := (i + 1) % n
			var a: Vector3 = A[i]
			var b: Vector3 = A[j]
			var c: Vector3 = B[j]
			var d: Vector3 = B[i]
			var mid := (a + b + c + d) * 0.25
			quad(a, b, c, d, mid - cm)
	if cap_start:
		var axis: Vector3 = centers[0] - centers[1]
		poly(Array(sections[0]), axis)
	if cap_end:
		var axis2: Vector3 = centers[centers.size() - 1] - centers[centers.size() - 2]
		poly(Array(sections[sections.size() - 1]), axis2)


## Oriented box via transform (rotated parts: awnings, signs, ramps).
func box_xf(xf: Transform3D, size: Vector3, chamfer := 0.0) -> void:
	var old := xform
	xform = old * xf
	box(Vector3.ZERO, size, chamfer)
	xform = old


## Appends ready-made triangles (Godot winding, e.g. a baked Blender model part) transformed by t.
func append_tris(key: String, v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, c: Color, t: Transform3D) -> void:
	use(key)
	var s := _s()
	var tt := xform * t
	s.v.append_array(tt * v)
	s.n.append_array(Transform3D(tt.basis.inverse().transposed(), Vector3.ZERO) * n)
	var cs := PackedColorArray()
	cs.resize(v.size())
	cs.fill(c)
	s.c.append_array(cs)
	if uv.size() == v.size():
		s.uv.append_array(uv)
	else:
		var u := PackedVector2Array()
		u.resize(v.size())
		s.uv.append_array(u)
	var u2 := PackedVector2Array()
	u2.resize(v.size())
	u2.fill(uv2)
	s.uv2.append_array(u2)


func is_empty() -> bool:
	for k in surf:
		if surf[k].v.size() > 0:
			return false
	return true


func commit(mats := {}, mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	for key in surf:
		var s: Dictionary = surf[key]
		if s.v.size() == 0:
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = s.v
		arr[Mesh.ARRAY_NORMAL] = s.n
		arr[Mesh.ARRAY_COLOR] = s.c
		arr[Mesh.ARRAY_TEX_UV] = s.uv
		arr[Mesh.ARRAY_TEX_UV2] = s.uv2
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var idx := mesh.get_surface_count() - 1
		mesh.surface_set_name(idx, key)
		if mats.has(key):
			mesh.surface_set_material(idx, mats[key])
		elif mats.has("*"):
			mesh.surface_set_material(idx, mats["*"])
	return mesh


## Convenience: build a MeshInstance3D from the builder.
func instance(mats := {}, name := "Mesh") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = commit(mats)
	return mi
