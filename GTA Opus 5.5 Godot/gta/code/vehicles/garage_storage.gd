class_name GarageStorage
extends RefCounted
## Persistent personal vehicles (safehouse garage). Each slot: {id, mods: Dictionary}.

const SLOTS := 4
var slots: Array = []


func store(v: VehicleBase) -> bool:
	if slots.size() >= SLOTS:
		Game.notify("Garage full (%d/%d)" % [slots.size(), SLOTS], "warn")
		return false
	slots.append({"id": v.def_id, "mods": v.mods.duplicate(true)})
	Game.notify("%s stored in garage (%d/%d)" % [v.display_name, slots.size(), SLOTS], "good")
	return true


func take(i: int) -> Dictionary:
	if i < 0 or i >= slots.size():
		return {}
	return slots.pop_at(i)


func to_array() -> Array:
	return slots.duplicate(true)


func from_array(a: Array) -> void:
	slots = a.duplicate(true)
