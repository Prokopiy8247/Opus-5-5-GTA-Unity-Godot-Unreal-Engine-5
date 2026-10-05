class_name RoadBuilder
extends RefCounted
## Generates asphalt segments, intersections, outer sidewalk strips and the terrain-following hill road.

const ROAD_Y := C.LAND_Y + 0.02
const WALK_Y := C.LAND_Y + WorldMap.CURB_H

var w: World
var road := MB.new()
var walk := MB.new()


func build(world: World) -> void:
	w = world
	road.use("road")
	walk.use("ground")
	var inters := WorldMap.intersections()
	# --- avenue segments (north -> south, +z)
	for a in WorldMap.AVENUES:
		var x: float = a[0]
		var hw := WorldMap.road_half_width(a[3])
		var zs := []
		for it in inters:
			if absf(it.pos.x - x) < 0.5:
				zs.append(it.pos.y)
		zs.sort()
		for k in zs.size() - 1:
			var z0: float = zs[k] + WorldMap.street_hw_at(zs[k])
			var z1: float = zs[k + 1] - WorldMap.street_hw_at(zs[k + 1])
			_segment(Vector3(x, ROAD_Y, z0), Vector3(x, ROAD_Y, z1), hw, a[3])
	# --- street segments (west -> east, +x)
	for s in WorldMap.STREETS:
		var z: float = s[0]
		var hw := WorldMap.road_half_width(s[3])
		var xs := []
		for it in inters:
			if absf(it.pos.y - z) < 0.5:
				xs.append(it.pos.x)
		xs.sort()
		for k in xs.size() - 1:
			var x0: float = xs[k] + WorldMap.avenue_hw_at(xs[k])
			var x1: float = xs[k + 1] - WorldMap.avenue_hw_at(xs[k + 1])
			_segment(Vector3(x0, ROAD_Y, z), Vector3(x1, ROAD_Y, z), hw, s[3])
	# --- intersection squares
	for it in inters:
		var p: Vector2 = it.pos
		var ha: float = it.hw_a
		var hs: float = it.hw_s
		road.uv2 = Vector2(0, 0)
		road.col(Color(0.0, 0, 0))
		road.quad_uv(Vector3(p.x - ha, ROAD_Y, p.y + hs), Vector3(p.x + ha, ROAD_Y, p.y + hs), Vector3(p.x + ha, ROAD_Y, p.y - hs), Vector3(p.x - ha, ROAD_Y, p.y - hs),
			Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector3.UP)
	# --- outer sidewalk strips
	for r in WorldMap.edge_strips():
		_walk_slab(r)
	# --- hill road
	_hill_road()
	var road_mesh := road.commit({"road": w.mats["road"]})
	var mi := w.add_mesh(road_mesh, "Roads")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var walk_mesh := walk.commit({"ground": w.mats["ground"]})
	w.add_mesh(walk_mesh, "OuterSidewalks")


func _segment(a: Vector3, b: Vector3, hw: float, lanes: int) -> void:
	var fwd := (b - a)
	var length := fwd.length()
	if length < 0.5:
		return
	fwd /= length
	var right := fwd.cross(Vector3.UP).normalized()
	road.uv2 = Vector2(lanes, length)
	road.col(Color(hw / 20.0, 0, 0))
	var la := a - right * hw
	var ra := a + right * hw
	var lb := b - right * hw
	var rb := b + right * hw
	road.quad_uv(la, ra, rb, lb, Vector2(-hw, 0), Vector2(hw, 0), Vector2(hw, length), Vector2(-hw, length), Vector3.UP)


## Sidewalk slab with curb faces, ground shader kind 0.
func _walk_slab(r: Rect2, kind := 0) -> void:
	add_slab_mesh(walk, r, C.LAND_Y, WALK_Y, kind)
	w.add_slab_col(r, C.LAND_Y, WALK_Y)


static func add_slab_mesh(mb: MB, r: Rect2, y0: float, y1: float, kind := 0, tint := Color.WHITE) -> void:
	var a := r.position
	var b := r.end
	mb.uv2 = Vector2(kind, 0)
	mb.col(tint)
	var p0 := Vector3(a.x, y1, a.y)
	var p1 := Vector3(b.x, y1, a.y)
	var p2 := Vector3(b.x, y1, b.y)
	var p3 := Vector3(a.x, y1, b.y)
	mb.quad_uv(p0, p1, p2, p3, Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(a.x, b.y), Vector3.UP)
	# curb faces (plain concrete)
	mb.uv2 = Vector2(8, 0)
	var q0 := Vector3(a.x, y0, a.y)
	var q1 := Vector3(b.x, y0, a.y)
	var q2 := Vector3(b.x, y0, b.y)
	var q3 := Vector3(a.x, y0, b.y)
	mb.quad_uv(q0, q1, p1, p0, Vector2(a.x, y0), Vector2(b.x, y0), Vector2(b.x, y1), Vector2(a.x, y1), Vector3.FORWARD)
	mb.quad_uv(q1, q2, p2, p1, Vector2(a.y, y0), Vector2(b.y, y0), Vector2(b.y, y1), Vector2(a.y, y1), Vector3.RIGHT)
	mb.quad_uv(q2, q3, p3, p2, Vector2(b.x, y0), Vector2(a.x, y0), Vector2(a.x, y1), Vector2(b.x, y1), Vector3.BACK)
	mb.quad_uv(q3, q0, p0, p3, Vector2(b.y, y0), Vector2(a.y, y0), Vector2(a.y, y1), Vector2(b.y, y1), Vector3.LEFT)


static func smooth_path(pts: Array, step := 2.0) -> Array:
	# Catmull-Rom resample of a 2D polyline
	var out := []
	for i in pts.size() - 1:
		var p0: Vector2 = pts[maxi(i - 1, 0)]
		var p1: Vector2 = pts[i]
		var p2: Vector2 = pts[i + 1]
		var p3: Vector2 = pts[mini(i + 2, pts.size() - 1)]
		var seg := p1.distance_to(p2)
		var n := maxi(int(seg / step), 1)
		for k in n:
			var t := float(k) / n
			var t2 := t * t
			var t3 := t2 * t
			var q := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
			out.append(q)
	out.append(pts[pts.size() - 1])
	return out


func _hill_road() -> void:
	var pts := smooth_path(WorldMap.HILL_ROAD, 2.0)
	var hw := 3.8
	var dist := 0.0
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_d := 0.0
	road.uv2 = Vector2(1, -1)
	road.col(Color(hw / 20.0, 0, 0))
	for i in pts.size():
		var p: Vector2 = pts[i]
		var nxt: Vector2 = pts[mini(i + 1, pts.size() - 1)]
		var prv: Vector2 = pts[maxi(i - 1, 0)]
		var f := (nxt - prv).normalized()
		var right := Vector2(-f.y, f.x)
		var lp := p - right * hw
		var rp := p + right * hw
		var l := Vector3(lp.x, WorldMap.height(lp.x, lp.y) + 0.12, lp.y)
		var r := Vector3(rp.x, WorldMap.height(rp.x, rp.y) + 0.12, rp.y)
		if i > 0:
			dist += p.distance_to(pts[i - 1])
			road.quad_uv(prev_l, prev_r, r, l, Vector2(hw, prev_d), Vector2(-hw, prev_d), Vector2(-hw, dist), Vector2(hw, dist), Vector3.UP)
		prev_l = l
		prev_r = r
		prev_d = dist
