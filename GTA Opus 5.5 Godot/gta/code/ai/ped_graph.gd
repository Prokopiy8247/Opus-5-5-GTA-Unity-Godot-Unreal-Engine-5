class_name PedGraph
extends RefCounted
## Sidewalk navigation graph: intersection corners + sidewalk nodes + signal-controlled crosswalks,
## promenade and beach paths. Pedestrians wander on it; flee/combat logic steers freely.

const Y := C.LAND_Y + WorldMap.CURB_H
var pos: Array = []          # Vector3
var adj: Array = []          # Array of Array[{to, cross_node, arm}]  (cross_node = -1 for plain sidewalk)
var _corner := {}            # "i|NE" -> node id


func add_node(p: Vector3) -> int:
	pos.append(p)
	adj.append([])
	return pos.size() - 1


func connect_nodes(a: int, b: int, cross_node := -1, arm := "") -> void:
	adj[a].append({"to": b, "cross": cross_node, "arm": arm})
	adj[b].append({"to": a, "cross": cross_node, "arm": arm})


func build(w: World) -> void:
	var inters := WorldMap.intersections()
	for i in inters.size():
		var it: Dictionary = inters[i]
		var p: Vector2 = it.pos
		var ox: float = it.hw_a + 1.5
		var oz: float = it.hw_s + 1.5
		_corner["%d|NE" % i] = add_node(Vector3(p.x + ox, Y, p.y - oz))
		_corner["%d|NW" % i] = add_node(Vector3(p.x - ox, Y, p.y - oz))
		_corner["%d|SE" % i] = add_node(Vector3(p.x + ox, Y, p.y + oz))
		_corner["%d|SW" % i] = add_node(Vector3(p.x - ox, Y, p.y + oz))
		var arms: Dictionary = it.arms
		# crossings (or plain links where the arm is missing)
		_link_corner(i, "NW", "NE", i if arms.n else -1, "n")
		_link_corner(i, "SW", "SE", i if arms.s else -1, "s")
		_link_corner(i, "NE", "SE", i if arms.e else -1, "e")
		_link_corner(i, "NW", "SW", i if arms.w else -1, "w")
	# sidewalks along segments
	var rg := RoadGraph.new()
	rg.build()
	var done := {}
	for L in rg.links:
		var a: int = L.from
		var b: int = L.to
		var key := "%d-%d" % [mini(a, b), maxi(a, b)]
		if done.has(key):
			continue
		done[key] = true
		var lo := a if (L.dir.x + L.dir.z) > 0 else b
		var hi := b if lo == a else a
		if absf(L.dir.z) > 0.5:
			# avenue: west side NW..., lo is north node
			_chain(_corner["%d|SW" % lo], _corner["%d|NW" % hi])
			_chain(_corner["%d|SE" % lo], _corner["%d|NE" % hi])
		else:
			_chain(_corner["%d|NE" % lo], _corner["%d|NW" % hi])
			_chain(_corner["%d|SE" % lo], _corner["%d|SW" % hi])
	# promenade path linked to coastal highway south corners
	var prom := []
	for k in 12:
		prom.append(add_node(Vector3(-104.0 + k * 14.5, Y, 178.0)))
	for k in prom.size() - 1:
		connect_nodes(prom[k], prom[k + 1])
	for x in [-110.0, -30.0, 50.0]:
		var c := nearest(Vector3(x + 9.0, Y, 159.0))
		var pn := nearest_in(Vector3(x, Y, 178.0), prom)
		connect_nodes(c, pn)
	# Lantern pier walk
	var pier_a := add_node(Vector3(-32, Y + 0.05, 205))
	var pier_b := add_node(Vector3(-32, Y + 0.05, 250))
	var pier_c := add_node(Vector3(-45, Y + 0.05, 268))
	var pier_d := add_node(Vector3(-18, Y + 0.05, 268))
	connect_nodes(nearest_in(Vector3(-32, Y, 178), prom), pier_a)
	connect_nodes(pier_a, pier_b)
	connect_nodes(pier_b, pier_c)
	connect_nodes(pier_b, pier_d)
	connect_nodes(pier_c, pier_d)
	# beach strolls
	var prev := -1
	for k in 10:
		var x := 80.0 + k * 20.0
		var z := 172.0
		var n := add_node(Vector3(x, WorldMap.height(x, z) + 0.05, z))
		if prev >= 0:
			connect_nodes(prev, n)
		else:
			connect_nodes(nearest(Vector3(x, Y, 159.0)), n)
		prev = n
	connect_nodes(prev, nearest(Vector3(260, Y, 159.0)))


func _link_corner(i: int, ca: String, cb: String, cross_node: int, arm: String) -> void:
	var a: int = _corner["%d|%s" % [i, ca]]
	var b: int = _corner["%d|%s" % [i, cb]]
	if cross_node >= 0:
		connect_nodes(a, b, cross_node, arm)
	else:
		_chain(a, b)


## Sidewalk run with intermediate nodes every ~16 m.
func _chain(a: int, b: int) -> void:
	var pa: Vector3 = pos[a]
	var pb: Vector3 = pos[b]
	var n := int(pa.distance_to(pb) / 16.0)
	var prev := a
	for k in range(1, n):
		var mid := add_node(pa.lerp(pb, float(k) / n))
		connect_nodes(prev, mid)
		prev = mid
	connect_nodes(prev, b)


func nearest(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for i in pos.size():
		var d: float = (pos[i] as Vector3).distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func nearest_in(p: Vector3, ids: Array) -> int:
	var best: int = ids[0]
	var bd := INF
	for i in ids:
		var d: float = (pos[i] as Vector3).distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func random_node_near(p: Vector3, rmin: float, rmax: float, rng: RandomNumberGenerator) -> int:
	for t in 24:
		var i := rng.randi() % pos.size()
		var d := U.flat_dist(pos[i], p)
		if d >= rmin and d <= rmax:
			return i
	return -1
