class_name VehicleMods
## Data-driven vehicle customization catalogue (Torque Theory Customs). Each option writes `key = value`
## into VehicleBase.mods; visuals rebuild and performance (VehicleBase._apply_perf) updates.

const CATEGORIES := [
	{"id": "paint", "name": "Primary Paint", "key": "paint", "price": 400, "type": "color"},
	{"id": "paint2", "name": "Secondary Paint", "key": "paint2", "price": 250, "type": "color"},
	{"id": "finish", "name": "Paint Finish", "key": "finish", "price": 600, "options": [["Gloss", "gloss"], ["Matte", "matte"], ["Metallic", "metallic"], ["Chrome", "chrome"]]},
	{"id": "rims", "name": "Wheels / Rims", "key": "rims", "price": 700, "options": [["Stock 5-spoke", 0], ["Mesh 6", 1], ["Turbine 10", 2], ["Tri-blade", 3]]},
	{"id": "rim_color", "name": "Wheel Colour", "key": "rim_color", "price": 300, "type": "color"},
	{"id": "tint", "name": "Window Tint", "key": "tint", "price": 200, "options": [["None", 0], ["Light", 1], ["Dark", 2], ["Limo", 3]]},
	{"id": "bumper", "name": "Front Bumper", "key": "bumper", "price": 500, "options": [["Stock", 0], ["Sport", 1], ["Splitter", 2]]},
	{"id": "hood", "name": "Hood", "key": "hood", "price": 650, "options": [["Stock", 0], ["Scoop", 1], ["Carbon Vent", 2]]},
	{"id": "roof", "name": "Roof", "key": "roof", "price": 350, "options": [["Stock", 0], ["Roof Rails", 1]]},
	{"id": "grille", "name": "Grille", "key": "grille", "price": 300, "options": [["Stock", 0], ["Wide", 1], ["Aggressive", 2]]},
	{"id": "exhaust", "name": "Exhaust", "key": "exhaust", "price": 450, "options": [["Single", 0], ["Twin", 1], ["Quad", 2]]},
	{"id": "skirts", "name": "Side Skirts", "key": "skirts", "price": 400, "options": [["None", 0], ["Sport Skirts", 1]]},
	{"id": "spoiler", "name": "Spoiler (adds downforce)", "key": "spoiler", "price": 900, "options": [["None", 0], ["Lip Wing", 1], ["GT Wing", 2]]},
	{"id": "light_color", "name": "Headlight Colour", "key": "light_color", "price": 250, "options": [["Halogen", Color(1, 0.95, 0.85)], ["Xenon Blue", Color(0.75, 0.85, 1.0)], ["Amber", Color(1, 0.75, 0.35)], ["Neon Teal", Color(0.4, 1, 0.9)]]},
	{"id": "horn", "name": "Horn", "key": "horn", "price": 150, "options": [["Stock", 0], ["Truck", 1], ["Melody", 2]]},
	{"id": "plate", "name": "Licence Plate", "key": "plate", "price": 100, "options": [["White", 0], ["Navy", 1], ["Gold", 2]]},
	{"id": "livery", "name": "Livery / Stripes", "key": "livery", "price": 800, "options": [["None", 0], ["Twin Racing Stripes", 1]]},
	{"id": "stripe_color", "name": "Stripe Colour", "key": "stripe_color", "price": 200, "type": "color"},
	{"id": "engine", "name": "Engine Tuning", "key": "engine", "price": 2500, "perf": true, "options": [["Stock", 0], ["Stage 1 (+10%)", 1], ["Stage 2 (+20%)", 2], ["Stage 3 (+30%)", 3]]},
	{"id": "brakes", "name": "Brakes", "key": "brakes", "price": 1200, "perf": true, "options": [["Stock", 0], ["Street (+15%)", 1], ["Sport (+30%)", 2], ["Race (+45%)", 3]]},
	{"id": "suspension", "name": "Suspension", "key": "suspension", "price": 1000, "perf": true, "options": [["Stock", 0], ["Lowered (+10% grip)", 1], ["Sport (+20%)", 2]]},
	{"id": "transmission", "name": "Transmission", "key": "transmission", "price": 1500, "perf": true, "options": [["Stock", 0], ["Street", 1], ["Sport", 2], ["Race", 3]]},
	{"id": "turbo", "name": "Turbo", "key": "turbo", "price": 4000, "perf": true, "options": [["None", false], ["Turbo Tuning", true]]},
	{"id": "armor", "name": "Armour Plating", "key": "armor", "price": 3000, "perf": true, "options": [["None", 0], ["20%", 1], ["40%", 2], ["60%", 3], ["80%", 4]]},
	{"id": "bp_tires", "name": "Bullet-resistant Tyres", "key": "bp_tires", "price": 2500, "perf": true, "options": [["Standard", false], ["Run-flat / Bulletproof", true]]},
]


static func price_for(cat: Dictionary, idx: int) -> int:
	var base: int = cat.price
	if cat.get("perf", false):
		return base * maxi(idx, 1)
	return base


static func apply_grip(v: VehicleBase) -> void:
	v.perf.grip = 1.0 + 0.1 * float(v.mods.get("suspension", 0))
