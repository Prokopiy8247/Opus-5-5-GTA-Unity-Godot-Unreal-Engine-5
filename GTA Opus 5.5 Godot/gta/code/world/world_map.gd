class_name WorldMap
## Static layout data for the island city "Vesper Bay" (~600 x 600 m) and the analytic terrain function.
## Everything (world builder, traffic graph, minimap, spawners) reads from here.

const ROAD_LANE_W := 3.5
const SIDEWALK_W := 3.0
const CURB_H := 0.15

# Avenues run north-south (constant x). [x, z_min, z_max, lanes_per_direction, name]
const AVENUES := [
	[-275.0, -130.0, 150.0, 1, "Westshore Road"],
	[-190.0, -130.0, 150.0, 1, "Foundry Street"],
	[-110.0, -130.0, 150.0, 1, "Rivet Avenue"],
	[-30.0, -130.0, 150.0, 2, "Meridian Boulevard"],
	[50.0, -130.0, 150.0, 1, "Beacon Avenue"],
	[130.0, -60.0, 150.0, 1, "Palm Avenue"],
	[210.0, -60.0, 150.0, 1, "Orchid Avenue"],
	[275.0, -60.0, 150.0, 1, "Eastshore Road"],
]

# Streets run east-west (constant z). [z, x_min, x_max, lanes_per_direction, name]
const STREETS := [
	[-130.0, -275.0, 50.0, 1, "Airfield Road"],
	[-60.0, -275.0, 275.0, 1, "Crown Street"],
	[10.0, -275.0, 275.0, 1, "Harbor Street"],
	[80.0, -275.0, 275.0, 1, "Lantern Street"],
	[150.0, -275.0, 275.0, 2, "Coastal Highway"],
]

const DISTRICTS := [
	{"id": "meridian", "name": "Meridian", "rect": Rect2(-70, -130, 200, 210), "color": Color(0.95, 0.62, 0.42)},
	{"id": "palm", "name": "Palm Terrace", "rect": Rect2(130, -60, 160, 210), "color": Color(0.55, 0.85, 0.55)},
	{"id": "ironside", "name": "Ironside", "rect": Rect2(-295, -130, 225, 210), "color": Color(0.62, 0.66, 0.74)},
	{"id": "lantern", "name": "Lantern Pier", "rect": Rect2(-295, 80, 590, 220), "color": Color(0.35, 0.75, 0.9)},
	{"id": "crown", "name": "Crown Hill", "rect": Rect2(50, -295, 245, 235), "color": Color(0.35, 0.65, 0.35)},
	{"id": "airfield", "name": "Vesper Airfield", "rect": Rect2(-295, -295, 345, 165), "color": Color(0.8, 0.8, 0.7)},
]

# Points of interest: id -> data. "door" is where the interaction trigger sits (world XZ), "face" yaw.
const POIS := {
	"police": {"name": "VBPD Central Precinct", "type": "police", "door": Vector2(10, -6.0), "icon": "P"},
	"hospital": {"name": "St. Vesper Medical", "type": "hospital", "door": Vector2(170, -5.0), "icon": "H"},
	"gunshop": {"name": "Brass & Barrel Arms", "type": "gunshop", "door": Vector2(-95, 22.0), "icon": "W"},
	"range": {"name": "Brass & Barrel Range", "type": "range", "door": Vector2(-60, 66.0), "icon": "R"},
	"modshop": {"name": "Torque Theory Customs", "type": "modshop", "door": Vector2(-150, 4.0), "icon": "C"},
	"clothes": {"name": "Threadline Apparel", "type": "clothes", "door": Vector2(-12, 22.0), "icon": "T"},
	"barber": {"name": "Fade Lab Barbers", "type": "barber", "door": Vector2(30, 22.0), "icon": "B"},
	"safehouse": {"name": "Orchid Lane Safehouse", "type": "safehouse", "door": Vector2(242, 22.0), "icon": "S"},
	"garage": {"name": "Safehouse Garage", "type": "garage", "door": Vector2(258, 22.0), "icon": "G"},
	"gas": {"name": "Sunstop Fuel", "type": "gas", "door": Vector2(90, 128.0), "icon": "F"},
	"dealer": {"name": "Vesper Motors", "type": "dealer", "door": Vector2(90, -48.0), "icon": "V"},
	"airfield": {"name": "Vesper Airfield", "type": "airfield", "door": Vector2(-150, -150.0), "icon": "A"},
	"helipad": {"name": "Airfield Helipad", "type": "helipad", "door": Vector2(-40, -175.0), "icon": "^"},
	"marina": {"name": "Lantern Marina", "type": "marina", "door": Vector2(-100, 178.0), "icon": "M"},
	"viewpoint": {"name": "Crown Hill Lookout", "type": "viewpoint", "door": Vector2(200, -195.0), "icon": "*"},
	"food": {"name": "Gull's Burgers", "type": "food", "door": Vector2(-62, 136.0), "icon": "$"},
	"wreck": {"name": "Shipwreck dive site", "type": "wreck", "icon": "D"},
	"beach": {"name": "Coral Beach", "type": "beach", "icon": "~"},
	"pier": {"name": "Pier End", "type": "pier", "icon": "o"},
}

const RUNWAY := Rect2(-262, -246, 330, 30)   # x, z, w, h  (runs east-west)
const TAXIWAY := Rect2(-240, -205, 300, 14)
const APRON := Rect2(-205, -192, 150, 40)
const HARBOR_BASIN_CENTER := Vector2(-185, 245)
const HARBOR_BASIN_HALF := Vector2(62, 72)

# Hill road (terrain following) from Palm Ave north end to the lookout.
const HILL_ROAD := [
	Vector2(130, -66), Vector2(124, -100), Vector2(132, -135), Vector2(158, -160), Vector2(190, -160),
	Vector2(226, -170), Vector2(240, -200), Vector2(226, -228), Vector2(196, -232), Vector2(178, -212), Vector2(188, -196),
]

const WRECK_POS := Vector3(150, -16, 268)

static var _noise: FastNoiseLite


static func _sdf_round_rect(p: Vector2, center: Vector2, half: Vector2, r: float) -> float:
	var q := (p - center).abs() - half + Vector2(r, r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


## Signed distance to coastline: negative on land.
static func coast_sdf(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var d := _sdf_round_rect(p, Vector2(0, -48), Vector2(292, 248), 45.0)
	var basin := _sdf_round_rect(p, HARBOR_BASIN_CENTER, HARBOR_BASIN_HALF, 10.0)
	return maxf(d, -basin)


static func hill(x: float, z: float) -> float:
	var dx := x - 205.0
	var dz := z + 196.0
	var h := 40.0 * exp(-(dx * dx) / (2.0 * 66.0 * 66.0) - (dz * dz) / (2.0 * 60.0 * 60.0))
	h *= smoothstep(-62.0, -105.0, z) * smoothstep(70.0, 118.0, x)
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 7
		_noise.frequency = 0.02
	h += _noise.get_noise_2d(x, z) * 3.0 * smoothstep(-70.0, -120.0, z) * smoothstep(80.0, 130.0, x)
	return h


static func beach_weight(x: float, z: float) -> float:
	return smoothstep(40.0, 95.0, x) * smoothstep(110.0, 165.0, z)


## Ground height (terrain only – not including sidewalks, buildings, piers).
static func height(x: float, z: float) -> float:
	var d := coast_sdf(x, z)
	# default rocky/quay coast
	var h_rock: float
	if d < -6.0:
		h_rock = C.LAND_Y
	elif d < 4.0:
		h_rock = lerpf(C.LAND_Y, -5.0, smoothstep(-6.0, 4.0, d))
	else:
		h_rock = -5.0 - 21.0 * smoothstep(4.0, 160.0, d)
	# docks: vertical quay walls along the south-west
	var quay_w := (1.0 - smoothstep(-40.0, -10.0, x)) * smoothstep(120.0, 160.0, z)
	var h_quay: float = C.LAND_Y if d < 0.0 else (-7.0 - 19.0 * smoothstep(2.0, 160.0, d))
	# sandy beach on the south-east
	var h_beach: float
	if d < -38.0:
		h_beach = C.LAND_Y
	elif d < 12.0:
		h_beach = lerpf(C.LAND_Y, -1.6, (d + 38.0) / 50.0)
	else:
		h_beach = -1.6 - 22.0 * smoothstep(12.0, 170.0, d)
	var bw := beach_weight(x, z)
	var h := lerpf(h_rock, h_quay, quay_w)
	h = lerpf(h, h_beach, bw)
	h += hill(x, z) * (1.0 - smoothstep(-30.0, 2.0, d))
	# shipwreck trench
	var wd := Vector2(x - WRECK_POS.x, z - WRECK_POS.z).length()
	h = minf(h, lerpf(-18.0, h, smoothstep(10.0, 30.0, wd))) if d > 20.0 else h
	return h


static func is_water(x: float, z: float) -> bool:
	return height(x, z) < C.SEA_LEVEL - 0.05


static func district_at(x: float, z: float) -> Dictionary:
	for d in DISTRICTS:
		if (d.rect as Rect2).has_point(Vector2(x, z)):
			return d
	return {"id": "sea", "name": "Vesper Bay Waters", "color": Color(0.2, 0.5, 0.8)}


static func road_half_width(lanes: int) -> float:
	return (lanes * 2 * ROAD_LANE_W + (1.0 if lanes > 1 else 0.6)) * 0.5


## All straight road segments as dictionaries (used by builder, minimap and lane graph).
static func roads() -> Array:
	var out := []
	for a in AVENUES:
		out.append({"axis": "z", "x": a[0], "a": Vector2(a[0], a[1]), "b": Vector2(a[0], a[2]), "lanes": a[3], "name": a[4], "hw": road_half_width(a[3])})
	for s in STREETS:
		out.append({"axis": "x", "z": s[0], "a": Vector2(s[1], s[0]), "b": Vector2(s[2], s[0]), "lanes": s[3], "name": s[4], "hw": road_half_width(s[3])})
	return out


static func avenue_hw_at(x: float) -> float:
	for a in AVENUES:
		if absf(a[0] - x) < 0.5:
			return road_half_width(a[3])
	return 4.0


static func street_hw_at(z: float) -> float:
	for s in STREETS:
		if absf(s[0] - z) < 0.5:
			return road_half_width(s[3])
	return 4.0


static func avenue_exists(x: float, z: float) -> bool:
	for a in AVENUES:
		if absf(a[0] - x) < 0.5 and z >= a[1] - 0.5 and z <= a[2] + 0.5:
			return true
	return false


static func street_exists(z: float, x: float) -> bool:
	for s in STREETS:
		if absf(s[0] - z) < 0.5 and x >= s[1] - 0.5 and x <= s[2] + 0.5:
			return true
	return false


## City blocks between adjacent avenues/streets. Returns inner rects (inside sidewalks' outer edge).
static func blocks() -> Array:
	var xs := []
	for a in AVENUES:
		xs.append(a[0])
	var zs := []
	for s in STREETS:
		zs.append(s[0])
	var out := []
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var x0: float = xs[i]
			var x1: float = xs[i + 1]
			var z0: float = zs[j]
			var z1: float = zs[j + 1]
			var cx := (x0 + x1) * 0.5
			var cz := (z0 + z1) * 0.5
			# a block needs bounding roads on at least its south and two sides
			if not (avenue_exists(x0, cz) and avenue_exists(x1, cz) and street_exists(z1, cx)):
				continue
			var has_north := street_exists(z0, cx)
			var r := Rect2()
			r.position = Vector2(x0 + avenue_hw_at(x0), (z0 + street_hw_at(z0)) if has_north else z0)
			r.end = Vector2(x1 - avenue_hw_at(x1), z1 - street_hw_at(z1))
			out.append({"rect": r, "i": i, "j": j, "kind": _block_kind(i, j), "center": Vector2(cx, cz)})
	return out


static func _block_kind(i: int, j: int) -> String:
	# i: avenue index (0..6), j: street index (0..3)
	var key := "%d,%d" % [i, j]
	var special := {
		"3,0": "plaza", "3,1": "police", "2,2": "gunshop", "3,2": "shops", "4,1": "dealer",
		"4,3": "gas", "1,1": "modshop", "5,1": "hospital", "5,2": "park", "6,2": "safehouse",
	}
	if special.has(key):
		return special[key]
	if i <= 1:
		return "industrial"
	if i <= 4:
		return "downtown" if j <= 2 else "commercial"
	return "residential"


## Spawn transforms in front of the relevant doors (origin = feet). Basis only encodes facing.
static func respawn_point(kind: String) -> Transform3D:
	var w: World = Game.world
	var id := "safehouse"
	match kind:
		"hospital": id = "hospital"
		"police": id = "police"
	if w and w.poi.has(id):
		var p: Vector3 = w.poi[id].pos
		var off := Vector3(0, 0.25, -1.0) if id == "safehouse" else Vector3(0, 0.25, 1.5)
		return Transform3D(Basis(Vector3.UP, 0.0 if id == "safehouse" else PI), p + off)
	return Transform3D(Basis.IDENTITY, Vector3(240, C.LAND_Y + 0.4, 17.0))


const TELEPORTS := [
	["Safehouse (Palm Terrace)", Vector3(242, 1.3, 27)],
	["Meridian Plaza (Downtown)", Vector3(10, 1.3, -95)],
	["Police Precinct", Vector3(10, 1.3, 0)],
	["Ironside Industrial / Customs", Vector3(-150, 1.3, 8)],
	["Brass & Barrel Arms", Vector3(-95, 1.3, 18)],
	["Lantern Pier & Marina", Vector3(-20, 1.3, 172)],
	["Coral Beach", Vector3(200, 1.3, 175)],
	["Crown Hill Lookout", Vector3(198, 42.0, -198)],
	["Vesper Airfield", Vector3(-150, 1.3, -160)],
	["Hospital", Vector3(170, 1.3, 0)],
	["Shipwreck dive site (boat)", Vector3(140, 1.0, 250)],
]


## Intersections where an avenue meets a street. arms: which directions roads leave the junction.
static func intersections() -> Array:
	var out := []
	for a in AVENUES:
		for s in STREETS:
			var x: float = a[0]
			var z: float = s[0]
			if z < a[1] - 0.5 or z > a[2] + 0.5:
				continue
			if x < s[1] - 0.5 or x > s[2] + 0.5:
				continue
			var arms := {
				"n": z > a[1] + 0.5,
				"s": z < a[2] - 0.5,
				"w": x > s[1] + 0.5,
				"e": x < s[2] - 0.5,
			}
			out.append({"pos": Vector2(x, z), "hw_a": road_half_width(a[3]), "hw_s": road_half_width(s[3]),
				"lanes_a": a[3], "lanes_s": s[3], "arms": arms})
	return out


## Sidewalk strips along road sides that have no city block next to them (outer edges of the grid).
static func edge_strips() -> Array:
	var sw := SIDEWALK_W
	var xa0: float = AVENUES[0][0]
	var hw0 := road_half_width(AVENUES[0][3])
	var xa4: float = AVENUES[4][0]
	var hw4 := road_half_width(AVENUES[4][3])
	var xa7: float = AVENUES[7][0]
	var hw7 := road_half_width(AVENUES[7][3])
	var z1: float = STREETS[0][0]
	var h1 := road_half_width(STREETS[0][3])
	var z2: float = STREETS[1][0]
	var h2 := road_half_width(STREETS[1][3])
	var z5: float = STREETS[4][0]
	var h5 := road_half_width(STREETS[4][3])
	var r := []
	r.append(Rect2(Vector2(xa0 - hw0 - sw, z1 - h1 - sw), Vector2(xa4 + hw4 + sw - (xa0 - hw0 - sw), sw)))   # north of Airfield Rd
	r.append(Rect2(Vector2(xa0 - hw0 - sw, z1 - h1), Vector2(sw, (z5 + h5) - (z1 - h1))))                  # west of Westshore
	r.append(Rect2(Vector2(xa0 - hw0 - sw, z5 + h5), Vector2((xa7 + hw7 + sw) - (xa0 - hw0 - sw), sw)))    # south of Coastal Hwy
	r.append(Rect2(Vector2(xa7 + hw7, z2 - h2), Vector2(sw, (z5 + h5) - (z2 - h2))))                       # east of Eastshore
	r.append(Rect2(Vector2(xa4 + hw4, z2 - h2 - sw), Vector2((xa7 + hw7 + sw) - (xa4 + hw4), sw)))         # north of Crown St (east)
	r.append(Rect2(Vector2(xa4 + hw4, z1 - h1), Vector2(sw, (z2 - h2 - sw) - (z1 - h1))))                  # east of Beacon (north part)
	return r
