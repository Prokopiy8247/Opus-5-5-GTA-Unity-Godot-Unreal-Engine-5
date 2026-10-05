class_name RoadGraph
extends RefCounted
## Directed lane graph for vehicle traffic + traffic-signal timing + A* routing (GPS / police).

const LANE_Y := C.LAND_Y + 0.05
const GREEN := 0
const YELLOW := 1
const RED := 2
const CYCLE := 36.0     # NS green 14, yellow 3, all-red 1, EW green 14, yellow 3, all-red 1

var nodes: Array = []   # {pos: Vector3, arms, hw_a, hw_s, out: [link ids], inc: [link ids], offset}
var links: Array = []   # see _add_link
var time := 0.0
var _last_states := {}


func build() -> void:
	var inters := WorldMap.intersections()
	for i in inters.size():
		var it: Dictionary = inters[i]
		nodes.append({"pos": Vector3(it.pos.x, LANE_Y, it.pos.y), "arms": it.arms, "hw_a": it.hw_a, "hw_s": it.hw_s,
			"out": [], "inc": [], "offset": fmod(float(i) * 7.3, CYCLE)})
	# avenues: connect consecutive intersections along x
	for a in WorldMap.AVENUES:
		var ids := []
		for i in nodes.size():
			if absf(nodes[i].pos.x - a[0]) < 0.5:
				ids.append(i)
		ids.sort_custom(func(p, q): return nodes[p].pos.z < nodes[q].pos.z)
		for k in ids.size() - 1:
			_add_pair(ids[k], ids[k + 1], a[3], a[4])
	for s in WorldMap.STREETS:
		var ids := []
		for i in nodes.size():
			if absf(nodes[i].pos.z - s[0]) < 0.5:
				ids.append(i)
		ids.sort_custom(func(p, q): return nodes[p].pos.x < nodes[q].pos.x)
		for k in ids.size() - 1:
			_add_pair(ids[k], ids[k + 1], s[3], s[4])


func _add_pair(i: int, j: int, lanes: int, name: String) -> void:
	_add_link(i, j, lanes, name)
	_add_link(j, i, lanes, name)


func _boundary(node_idx: int, dir: Vector3) -> float:
	var n: Dictionary = nodes[node_idx]
	return n.hw_s if absf(dir.z) > 0.5 else n.hw_a


func _add_link(i: int, j: int, lanes: int, name: String) -> void:
	var a: Vector3 = nodes[i].pos
	var b: Vector3 = nodes[j].pos
	var dir := (b - a).normalized()
	var right := dir.cross(Vector3.UP).normalized()
	var start := a + dir * (_boundary(i, dir) + 0.5)
	var end := b - dir * (_boundary(j, dir) + 4.5)       # stop line
	var offsets := [1.9] if lanes == 1 else [2.3, 5.6]
	var arm := "n"
	if dir.z > 0.5:
		arm = "n"
	elif dir.z < -0.5:
		arm = "s"
	elif dir.x > 0.5:
		arm = "w"
	else:
		arm = "e"
	var speed := 13.0
	if lanes == 2:
		speed = 19.0 if name == "Coastal Highway" else 16.0
	var id := links.size()
	links.append({"id": id, "from": i, "to": j, "dir": dir, "right": right, "lanes": lanes, "offsets": offsets,
		"start": start, "end": end, "length": start.distance_to(end), "speed": speed, "approach": arm, "name": name})
	nodes[i].out.append(id)
	nodes[j].inc.append(id)


func lane_point(link_id: int, lane: int, s: float) -> Vector3:
	var L: Dictionary = links[link_id]
	return L.start + L.dir * s + L.right * L.offsets[mini(lane, L.offsets.size() - 1)]


func lane_count(link_id: int) -> int:
	return links[link_id].offsets.size()


## Outgoing link choices at the end of a link (no U-turns). Returns [{link, turn}] turn: -1 left, 0 straight, 1 right.
func next_links(link_id: int) -> Array:
	var L: Dictionary = links[link_id]
	var out := []
	for o in nodes[L.to].out:
		var O: Dictionary = links[o]
		if O.to == L.from:
			continue
		var cr: float = L.dir.cross(O.dir).y
		var turn := 0
		if cr > 0.5:
			turn = -1
		elif cr < -0.5:
			turn = 1
		out.append({"link": o, "turn": turn})
	return out


## Bezier connector through an intersection.
func connector(link_in: int, lane_in: int, link_out: int, lane_out: int, steps := 6) -> Array:
	var a := lane_point(link_in, lane_in, links[link_in].length)
	var b := lane_point(link_out, lane_out, 0.0)
	var din: Vector3 = links[link_in].dir
	var dout: Vector3 = links[link_out].dir
	var ctrl: Vector3
	if absf(din.dot(dout)) > 0.9:
		ctrl = (a + b) * 0.5
	else:
		# intersection of the two lane lines
		var t := 0.0
		if absf(din.x) > 0.5:
			t = (b.x - a.x) / din.x
		else:
			t = (b.z - a.z) / din.z
		ctrl = a + din * t
	var pts := []
	for k in range(1, steps + 1):
		var u := float(k) / steps
		pts.append(a.lerp(ctrl, u).lerp(ctrl.lerp(b, u), u))
	return pts


func signal_state(node_idx: int, approach: String) -> int:
	var n: Dictionary = nodes[node_idx]
	var t := fmod(time + n.offset, CYCLE)
	var ns := approach == "n" or approach == "s"
	# arms count: T-junction minor approaches still use the cycle
	if ns:
		if t < 14.0:
			return GREEN
		if t < 17.0:
			return YELLOW
		return RED
	else:
		if t >= 18.0 and t < 32.0:
			return GREEN
		if t >= 32.0 and t < 35.0:
			return YELLOW
		return RED


func update(dt: float, props: PropManager) -> void:
	time += dt
	if props == null:
		return
	for i in props.signals.size():
		var s: Dictionary = props.signals[i]
		var st := signal_state(s.inter, s.approach)
		if _last_states.get(i, -1) != st:
			_last_states[i] = st
			props.set_signal(i, st)


## Pedestrians may cross an arm when cars on that arm's axis have red.
func ped_can_cross(node_idx: int, arm: String) -> bool:
	return signal_state(node_idx, arm) == RED


func nearest_lane(pos: Vector3, max_dist := 40.0) -> Dictionary:
	var best := {}
	var bd := max_dist
	for L in links:
		var rel: Vector3 = pos - L.start
		var s := clampf(rel.dot(L.dir), 0.0, L.length)
		for k in L.offsets.size():
			var p := lane_point(L.id, k, s)
			var d := Vector2(p.x - pos.x, p.z - pos.z).length()
			if d < bd:
				bd = d
				best = {"link": L.id, "lane": k, "s": s, "dist": d, "point": p}
	return best


func nearest_node(pos: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in nodes.size():
		var d: float = U.flat_dist(nodes[i].pos, pos)
		if d < bd:
			bd = d
			best = i
	return best


## A* over intersections; returns world points (start → intersections → goal).
func route(from: Vector3, to: Vector3) -> Array:
	var s := nearest_node(from)
	var g := nearest_node(to)
	if s < 0 or g < 0:
		return []
	var open := {s: true}
	var came := {}
	var gs := {s: 0.0}
	var fs := {s: U.flat_dist(nodes[s].pos, nodes[g].pos)}
	while not open.is_empty():
		var cur := -1
		var cf := INF
		for k in open:
			if fs.get(k, INF) < cf:
				cf = fs[k]
				cur = k
		if cur == g:
			break
		open.erase(cur)
		for lid in nodes[cur].out:
			var nb: int = links[lid].to
			var ng: float = gs[cur] + links[lid].length + 8.0
			if ng < gs.get(nb, INF):
				came[nb] = cur
				gs[nb] = ng
				fs[nb] = ng + U.flat_dist(nodes[nb].pos, nodes[g].pos)
				open[nb] = true
	var path := [to]
	var c := g
	while c != s and came.has(c):
		path.push_front(nodes[c].pos)
		c = came[c]
	path.push_front(nodes[s].pos)
	path.push_front(from)
	return path


func link_between(i: int, j: int) -> int:
	for lid in nodes[i].out:
		if links[lid].to == j:
			return lid
	return -1


## Next intersection index on the shortest path from node a toward goal position.
func next_hop(a: int, goal: Vector3) -> int:
	var path := route(nodes[a].pos, goal)
	if path.size() >= 3:
		var p: Vector3 = path[2]
		return nearest_node(p)
	return -1
