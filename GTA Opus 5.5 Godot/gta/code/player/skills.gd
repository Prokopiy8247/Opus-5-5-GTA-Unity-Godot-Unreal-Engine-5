class_name Skills
extends RefCounted
## Use-based character stats (0..100). Each improves by doing the activity.

const NAMES := ["stamina", "shooting", "strength", "stealth", "driving", "flying", "lung"]
const LABELS := {"stamina": "Stamina", "shooting": "Shooting", "strength": "Strength", "stealth": "Stealth",
	"driving": "Driving", "flying": "Flying", "lung": "Lung Capacity"}

var v := {"stamina": 20.0, "shooting": 15.0, "strength": 20.0, "stealth": 10.0, "driving": 20.0, "flying": 10.0, "lung": 15.0}
var _pending := {}


func add(name: String, amount: float) -> void:
	var before := int(v[name] / 10.0)
	v[name] = clampf(v[name] + amount, 0.0, 100.0)
	if int(v[name] / 10.0) > before:
		Game.notify("%s skill increased (%d%%)" % [LABELS[name], int(v[name])], "skill")


func f(name: String) -> float:
	return v[name] / 100.0


func set_all(value: float) -> void:
	for k in v:
		v[k] = value


# Derived modifiers (kept modest so low skill still feels fine)
func sprint_duration() -> float:
	return 6.0 + 14.0 * f("stamina")


func recoil_mul() -> float:
	return 1.0 - 0.3 * f("shooting")


func reload_mul() -> float:
	return 1.0 - 0.25 * f("shooting")


func melee_mul() -> float:
	return 1.0 + 0.6 * f("strength")


func damage_resist() -> float:
	return 1.0 - 0.2 * f("strength")


func noise_mul() -> float:
	return 1.0 - 0.4 * f("stealth")


func grip_bonus() -> float:
	return 1.0 + 0.12 * f("driving")


func flight_stability() -> float:
	return 0.5 + 0.5 * f("flying")


func breath_time() -> float:
	return 20.0 + 40.0 * f("lung")


func to_dict() -> Dictionary:
	return v.duplicate()


func from_dict(d: Dictionary) -> void:
	for k in d:
		if v.has(k):
			v[k] = float(d[k])
