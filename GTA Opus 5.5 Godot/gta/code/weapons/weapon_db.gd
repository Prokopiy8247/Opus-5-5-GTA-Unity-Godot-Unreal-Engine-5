class_name WeaponDB
## Data-driven weapon registry (original designs / names). Slots map to the weapon wheel.

const SLOT_NAMES := ["Melee", "Handguns", "SMGs", "Shotguns", "Rifles", "Snipers", "Heavy", "Throwables"]

const W := {
	"fists": {"name": "Fists", "slot": 0, "hold": 0, "melee": true, "damage": 12.0, "rate": 2.8, "range": 1.6, "price": 0, "noise": 6.0},
	"knife": {"name": "Field Knife", "slot": 0, "hold": 3, "melee": true, "damage": 40.0, "rate": 2.2, "range": 1.8, "price": 120, "noise": 4.0},
	"bat": {"name": "Alloy Bat", "slot": 0, "hold": 3, "melee": true, "damage": 32.0, "rate": 1.6, "range": 2.2, "knockdown": true, "price": 90, "noise": 8.0},
	"pistol": {"name": "P9 Compact", "slot": 1, "hold": 1, "damage": 24.0, "rate": 4.5, "mag": 15, "reload": 1.3, "spread": 1.1, "recoil": 2.2,
		"range": 140.0, "sound": "shot_pistol", "noise": 70.0, "price": 450, "ammo_price": 40, "ammo_pack": 45, "drive_by": true,
		"mods": ["suppressor", "extmag", "flashlight", "tint"]},
	"revolver": {"name": "Hammer .44", "slot": 1, "hold": 1, "damage": 58.0, "rate": 1.5, "mag": 6, "reload": 2.2, "spread": 0.7, "recoil": 7.0,
		"range": 160.0, "sound": "shot_heavy", "noise": 95.0, "price": 900, "ammo_price": 60, "ammo_pack": 24, "drive_by": true, "mods": ["tint", "scope"]},
	"smg": {"name": "Viper SMG", "slot": 2, "hold": 1, "damage": 16.0, "rate": 12.0, "mag": 30, "reload": 1.7, "spread": 2.8, "recoil": 1.1, "auto": true,
		"range": 110.0, "sound": "shot_smg", "noise": 70.0, "price": 1500, "ammo_price": 60, "ammo_pack": 90, "drive_by": true,
		"mods": ["suppressor", "extmag", "flashlight", "grip", "tint"]},
	"shotgun": {"name": "Breacher Pump", "slot": 3, "hold": 2, "damage": 15.0, "pellets": 8, "rate": 1.15, "mag": 6, "reload": 2.8, "spread": 5.5, "recoil": 9.0,
		"range": 45.0, "sound": "shot_shotgun", "noise": 100.0, "price": 1200, "ammo_price": 50, "ammo_pack": 24, "mods": ["flashlight", "suppressor", "tint"]},
	"autoshotgun": {"name": "Auto-12 Riot", "slot": 3, "hold": 2, "damage": 12.0, "pellets": 8, "rate": 3.5, "mag": 10, "reload": 2.4, "spread": 6.5, "recoil": 6.0, "auto": true,
		"range": 40.0, "sound": "shot_shotgun", "noise": 100.0, "price": 3200, "ammo_price": 70, "ammo_pack": 30, "mods": ["extmag", "grip", "tint"]},
	"rifle": {"name": "AR-7 Assault", "slot": 4, "hold": 2, "damage": 28.0, "rate": 9.0, "mag": 30, "reload": 2.0, "spread": 1.5, "recoil": 1.7, "auto": true,
		"range": 220.0, "sound": "shot_rifle", "noise": 110.0, "price": 3600, "ammo_price": 80, "ammo_pack": 90,
		"mods": ["suppressor", "extmag", "flashlight", "scope", "grip", "tint"]},
	"carbine": {"name": "K4 Carbine", "slot": 4, "hold": 2, "damage": 25.0, "rate": 11.0, "mag": 30, "reload": 1.8, "spread": 1.9, "recoil": 1.4, "auto": true,
		"range": 200.0, "sound": "shot_rifle", "noise": 105.0, "price": 3000, "ammo_price": 80, "ammo_pack": 90,
		"mods": ["suppressor", "extmag", "flashlight", "scope", "grip", "tint"]},
	"dmr": {"name": "DMR-11 Marksman", "slot": 5, "hold": 2, "damage": 62.0, "rate": 2.6, "mag": 10, "reload": 2.3, "spread": 0.3, "recoil": 4.0, "scope_fov": 28.0,
		"range": 320.0, "sound": "shot_rifle", "noise": 120.0, "price": 4800, "ammo_price": 90, "ammo_pack": 30, "mods": ["suppressor", "extmag", "grip", "tint"]},
	"sniper": {"name": "Longshot .50", "slot": 5, "hold": 2, "damage": 190.0, "rate": 0.8, "mag": 5, "reload": 3.0, "spread": 0.05, "recoil": 10.0, "scope_fov": 11.0,
		"range": 600.0, "sound": "shot_sniper", "noise": 160.0, "price": 7500, "ammo_price": 120, "ammo_pack": 20, "mods": ["suppressor", "extmag", "tint"]},
	"grenade": {"name": "Frag Grenade", "slot": 7, "hold": 1, "throw": true, "damage": 170.0, "radius": 7.5, "rate": 1.0, "mag": 1, "reload": 0.6,
		"projectile": "grenade", "price": 250, "ammo_price": 250, "ammo_pack": 1, "noise": 0.0, "drive_by": true, "range": 30.0},
	"rpg": {"name": "RPL-7 Launcher", "slot": 6, "hold": 4, "damage": 320.0, "radius": 8.0, "rate": 0.5, "mag": 1, "reload": 2.6, "spread": 0.4, "recoil": 12.0,
		"projectile": "rocket", "sound": "shot_launcher", "noise": 130.0, "price": 12000, "ammo_price": 800, "ammo_pack": 2, "range": 300.0},
	"gl": {"name": "GL-6 Launcher", "slot": 6, "hold": 2, "damage": 150.0, "radius": 6.0, "rate": 1.3, "mag": 6, "reload": 3.2, "spread": 0.8, "recoil": 6.0,
		"projectile": "gl_grenade", "sound": "shot_launcher", "noise": 90.0, "price": 9000, "ammo_price": 400, "ammo_pack": 6, "range": 120.0},
}

const MODS := {
	"suppressor": {"name": "Suppressor", "price": 900},
	"extmag": {"name": "Extended Magazine", "price": 600},
	"flashlight": {"name": "Flashlight", "price": 350},
	"scope": {"name": "Optic / Scope", "price": 750},
	"grip": {"name": "Stabilising Grip", "price": 500},
	"tint": {"name": "Finish: Desert / Teal / Gold", "price": 400},
}

const TINTS := [Color(0.16, 0.17, 0.19), Color(0.72, 0.62, 0.45), Color(0.2, 0.55, 0.55), Color(0.85, 0.68, 0.25)]


static func get_def(id: String) -> Dictionary:
	return W.get(id, W["fists"])


static func ids_in_slot(slot: int) -> Array:
	var out := []
	for k in W:
		if W[k].slot == slot:
			out.append(k)
	return out


## Effective stats after mods.
static func stat(id: String, key: String, mods: Dictionary) -> float:
	var d := get_def(id)
	var v: float = float(d.get(key, 0.0))
	match key:
		"mag":
			if mods.get("extmag", false):
				v = ceilf(v * 1.6)
		"spread":
			if mods.get("grip", false):
				v *= 0.7
			if mods.get("suppressor", false):
				v *= 1.08
		"recoil":
			if mods.get("grip", false):
				v *= 0.65
		"noise":
			if mods.get("suppressor", false):
				v *= 0.18
		"damage":
			if mods.get("suppressor", false):
				v *= 0.92
		"scope_fov":
			if mods.get("scope", false) and v <= 0.0:
				v = 35.0
	return v
