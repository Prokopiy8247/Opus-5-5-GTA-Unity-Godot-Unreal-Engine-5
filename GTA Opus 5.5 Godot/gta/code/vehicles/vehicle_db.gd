class_name VehicleDB
## Vehicle definitions: dimensions, body style parameters (distinct silhouettes), handling, seats, price.
## body: [length, width, belt_h, roof_h, clearance, hood_len, deck_len, ws_slope, rear_slope, nose_drop]

const V := {
	"compact": {"name": "Pico Hatch", "kind": "car", "cls": "Compact", "mass": 950.0, "engine": 5200.0, "vmax": 42.0, "grip": 1.15, "steer": 0.62,
		"body": [3.7, 1.72, 0.95, 1.52, 0.2, 0.75, 0.25, 0.75, 0.35, 0.12], "wheel_r": 0.31, "wheelbase": 2.4, "track": 1.48, "style": "hatch",
		"seats": 2, "price": 9000, "color": Color(0.95, 0.75, 0.2), "audio": "engine_car", "pitch": 1.25},
	"sedan": {"name": "Meridian Sedan", "kind": "car", "cls": "Sedan", "mass": 1350.0, "engine": 6800.0, "vmax": 50.0, "grip": 1.1, "steer": 0.58,
		"body": [4.7, 1.84, 0.95, 1.46, 0.2, 1.15, 0.85, 0.65, 0.55, 0.1], "wheel_r": 0.34, "wheelbase": 2.85, "track": 1.58, "style": "sedan",
		"seats": 4, "price": 16000, "color": Color(0.2, 0.42, 0.7), "audio": "engine_car", "pitch": 1.0},
	"sports": {"name": "Vortex GT", "kind": "car", "cls": "Sports", "mass": 1250.0, "engine": 11500.0, "vmax": 72.0, "grip": 1.45, "steer": 0.55,
		"body": [4.5, 1.98, 0.78, 1.18, 0.14, 1.45, 0.7, 0.45, 0.35, 0.16], "wheel_r": 0.35, "wheelbase": 2.7, "track": 1.7, "style": "fastback",
		"seats": 2, "price": 95000, "color": Color(0.9, 0.15, 0.15), "audio": "engine_car", "pitch": 1.35, "spoiler": true},
	"muscle": {"name": "Brawler SS", "kind": "car", "cls": "Muscle", "mass": 1550.0, "engine": 10500.0, "vmax": 62.0, "grip": 1.05, "steer": 0.55,
		"body": [4.95, 1.95, 0.92, 1.36, 0.18, 1.9, 0.75, 0.55, 0.42, 0.04], "wheel_r": 0.36, "wheelbase": 2.95, "track": 1.66, "style": "fastback",
		"seats": 2, "price": 42000, "color": Color(0.15, 0.15, 0.17), "audio": "engine_truck", "pitch": 1.1, "stripes": true, "scoop": true},
	"suv": {"name": "Trailhound SUV", "kind": "car", "cls": "SUV", "mass": 2100.0, "engine": 9000.0, "vmax": 48.0, "grip": 1.05, "steer": 0.55,
		"body": [4.85, 1.98, 1.25, 1.95, 0.32, 1.05, 0.35, 0.75, 0.15, 0.06], "wheel_r": 0.42, "wheelbase": 2.9, "track": 1.7, "style": "wagon",
		"seats": 4, "price": 38000, "color": Color(0.32, 0.4, 0.32), "audio": "engine_truck", "pitch": 1.0, "rack": true},
	"pickup": {"name": "Haulbuck Pickup", "kind": "car", "cls": "Pickup", "mass": 2000.0, "engine": 8800.0, "vmax": 46.0, "grip": 1.0, "steer": 0.55,
		"body": [5.3, 1.98, 1.2, 1.9, 0.34, 1.2, 0.0, 0.8, 0.1, 0.05], "wheel_r": 0.42, "wheelbase": 3.2, "track": 1.72, "style": "pickup",
		"seats": 2, "price": 28000, "color": Color(0.75, 0.3, 0.15), "audio": "engine_truck", "pitch": 0.95},
	"van": {"name": "Courier Van", "kind": "car", "cls": "Van", "mass": 2300.0, "engine": 7500.0, "vmax": 40.0, "grip": 0.95, "steer": 0.55,
		"body": [5.1, 2.0, 1.2, 2.45, 0.24, 0.65, 0.0, 0.95, 0.0, 0.08], "wheel_r": 0.36, "wheelbase": 3.2, "track": 1.72, "style": "van",
		"seats": 2, "price": 24000, "color": Color(0.95, 0.95, 0.93), "audio": "engine_truck", "pitch": 0.9},
	"police": {"name": "VBPD Interceptor", "kind": "car", "cls": "Emergency", "mass": 1500.0, "engine": 10000.0, "vmax": 62.0, "grip": 1.25, "steer": 0.58,
		"body": [4.9, 1.9, 0.95, 1.46, 0.2, 1.25, 0.85, 0.6, 0.5, 0.1], "wheel_r": 0.35, "wheelbase": 2.95, "track": 1.62, "style": "sedan",
		"seats": 4, "price": 0, "color": Color(0.1, 0.12, 0.16), "audio": "engine_car", "pitch": 1.05, "faction": "police", "lightbar": true, "livery": "police", "armor": 1.3},
	"taxi": {"name": "Gold Line Taxi", "kind": "car", "cls": "Sedan", "mass": 1400.0, "engine": 6800.0, "vmax": 48.0, "grip": 1.1, "steer": 0.58,
		"body": [4.8, 1.86, 0.95, 1.48, 0.2, 1.15, 0.85, 0.65, 0.55, 0.1], "wheel_r": 0.34, "wheelbase": 2.9, "track": 1.6, "style": "sedan",
		"seats": 4, "price": 0, "color": Color(0.98, 0.78, 0.1), "audio": "engine_car", "pitch": 1.0, "faction": "taxi", "taxisign": true, "livery": "checker"},
	"ambulance": {"name": "Medic One", "kind": "car", "cls": "Emergency", "mass": 3000.0, "engine": 9000.0, "vmax": 44.0, "grip": 0.95, "steer": 0.52,
		"body": [5.9, 2.15, 1.25, 2.75, 0.3, 0.9, 0.0, 0.85, 0.0, 0.06], "wheel_r": 0.4, "wheelbase": 3.6, "track": 1.8, "style": "box",
		"seats": 2, "price": 0, "color": Color(0.96, 0.96, 0.95), "audio": "engine_truck", "pitch": 0.9, "faction": "ambulance", "lightbar": true, "livery": "medic"},
	"firetruck": {"name": "Ladder 7", "kind": "car", "cls": "Emergency", "mass": 7000.0, "engine": 19000.0, "vmax": 36.0, "grip": 0.9, "steer": 0.45,
		"body": [8.4, 2.45, 1.5, 2.9, 0.38, 1.6, 0.0, 0.9, 0.0, 0.04], "wheel_r": 0.5, "wheelbase": 5.2, "track": 2.0, "style": "truck",
		"seats": 2, "price": 0, "color": Color(0.85, 0.12, 0.1), "audio": "engine_truck", "pitch": 0.7, "faction": "fire", "lightbar": true, "ladder": true},
	"swat": {"name": "Bulwark Tactical", "kind": "car", "cls": "Emergency", "mass": 5200.0, "engine": 17000.0, "vmax": 42.0, "grip": 1.0, "steer": 0.5,
		"body": [5.8, 2.3, 1.5, 2.6, 0.42, 1.1, 0.0, 0.7, 0.0, 0.04], "wheel_r": 0.5, "wheelbase": 3.5, "track": 1.9, "style": "armored",
		"seats": 4, "price": 0, "color": Color(0.12, 0.13, 0.15), "audio": "engine_truck", "pitch": 0.75, "faction": "police", "lightbar": true, "armor": 3.0},
	"truck": {"name": "Hauler Box Truck", "kind": "car", "cls": "Truck", "mass": 6500.0, "engine": 16000.0, "vmax": 34.0, "grip": 0.9, "steer": 0.45,
		"body": [7.6, 2.4, 1.45, 3.3, 0.4, 1.5, 0.0, 0.9, 0.0, 0.04], "wheel_r": 0.5, "wheelbase": 4.6, "track": 1.95, "style": "truck",
		"seats": 2, "price": 32000, "color": Color(0.9, 0.9, 0.88), "audio": "engine_truck", "pitch": 0.65},
	"bike": {"name": "Razorback 600", "kind": "bike", "cls": "Motorcycle", "mass": 230.0, "engine": 3600.0, "vmax": 64.0, "grip": 1.3, "steer": 0.45,
		"wheel_r": 0.32, "wheelbase": 1.45, "seats": 1, "price": 14000, "color": Color(0.1, 0.55, 0.9), "audio": "engine_bike", "pitch": 1.4},
	"bicycle": {"name": "Pedalfast BMX", "kind": "bicycle", "cls": "Bicycle", "mass": 90.0, "engine": 900.0, "vmax": 13.0, "grip": 1.2, "steer": 0.5,
		"wheel_r": 0.33, "wheelbase": 1.05, "seats": 1, "price": 600, "color": Color(0.2, 0.8, 0.4), "audio": "", "pitch": 1.0},
	"boat": {"name": "Wavecutter 24", "kind": "boat", "cls": "Boat", "mass": 1300.0, "engine": 19000.0, "vmax": 34.0, "grip": 1.0, "steer": 0.6,
		"seats": 2, "price": 45000, "color": Color(0.95, 0.95, 0.97), "audio": "engine_boat", "pitch": 1.0},
	"heli": {"name": "Skylark H2", "kind": "heli", "cls": "Helicopter", "mass": 1400.0, "engine": 0.0, "vmax": 55.0, "seats": 2, "price": 220000,
		"color": Color(0.95, 0.55, 0.15), "audio": "heli_loop", "pitch": 1.0},
	"police_heli": {"name": "VBPD Sentinel", "kind": "heli", "cls": "Helicopter", "mass": 1500.0, "engine": 0.0, "vmax": 60.0, "seats": 2, "price": 0,
		"color": Color(0.12, 0.15, 0.22), "audio": "heli_loop", "pitch": 0.95, "faction": "police", "searchlight": true},
	"plane": {"name": "Gull Trainer", "kind": "plane", "cls": "Airplane", "mass": 1000.0, "engine": 9000.0, "vmax": 70.0, "seats": 2, "price": 160000,
		"color": Color(0.95, 0.95, 0.95), "audio": "engine_plane", "pitch": 1.0, "stall": 24.0},
	"jet": {"name": "Stiletto Jet", "kind": "plane", "cls": "Airplane", "mass": 2600.0, "engine": 52000.0, "vmax": 150.0, "seats": 1, "price": 900000,
		"color": Color(0.55, 0.6, 0.66), "audio": "engine_plane", "pitch": 1.8, "stall": 42.0, "jet": true},
}

const SPAWN_MENU := ["compact", "sedan", "sports", "muscle", "suv", "pickup", "van", "police", "taxi", "ambulance", "firetruck", "swat", "truck",
	"bike", "bicycle", "boat", "heli", "police_heli", "plane", "jet"]

const TRAFFIC_POOL := ["compact", "compact", "sedan", "sedan", "sedan", "suv", "suv", "pickup", "van", "taxi", "muscle", "sports", "truck"]
const PARKED_POOL := ["compact", "sedan", "sedan", "suv", "pickup", "muscle", "sports", "van"]

const PAINTS := [Color(0.9, 0.15, 0.15), Color(0.95, 0.5, 0.1), Color(0.95, 0.8, 0.15), Color(0.25, 0.65, 0.3), Color(0.15, 0.5, 0.75),
	Color(0.2, 0.25, 0.6), Color(0.55, 0.25, 0.65), Color(0.95, 0.95, 0.95), Color(0.12, 0.12, 0.14), Color(0.55, 0.57, 0.6),
	Color(0.3, 0.75, 0.75), Color(0.95, 0.55, 0.65), Color(0.45, 0.3, 0.2), Color(0.7, 0.8, 0.2)]


static func get_def(id: String) -> Dictionary:
	return V.get(id, V["sedan"])
