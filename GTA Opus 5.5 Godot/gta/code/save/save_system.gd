class_name SaveSystem
## JSON save/load (user://vesperbay_save.json). Dynamic world objects are intentionally not persisted.

const PATH := "user://vesperbay_save.json"


static func _c2a(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]


static func _ser(v: Variant) -> Variant:
	if v is Color:
		return {"__c": _c2a(v)}
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _ser(v[k])
		return d
	if v is Array:
		var a := []
		for x in v:
			a.append(_ser(x))
		return a
	return v


static func _des(v: Variant) -> Variant:
	if v is Dictionary:
		if v.has("__c"):
			var a: Array = v["__c"]
			return Color(a[0], a[1], a[2], a[3])
		var d := {}
		for k in v:
			d[k] = _des(v[k])
		return d
	if v is Array:
		var out := []
		for x in v:
			out.append(_des(x))
		return out
	return v


static func save_game() -> bool:
	var p := Game.player
	if p == null or p.dead:
		Game.notify("Can't save right now", "warn")
		return false
	var pos := p.global_position
	if p.vehicle:
		pos = p.vehicle.global_position + Vector3(0, 2, 0)
	var inv := {}
	for id in p.weapons.inv:
		inv[id] = {"mag": p.weapons.inv[id].mag, "reserve": p.weapons.inv[id].reserve, "mods": p.weapons.inv[id].mods}
	var data := {
		"version": 1,
		"time_saved": Time.get_datetime_string_from_system(),
		"player": {"pos": [pos.x, pos.y, pos.z], "health": p.health, "armor": p.armor, "look": p.look_data,
			"weapons": inv, "current": p.weapons.current, "parachute": p.has_parachute, "scuba": p.scuba},
		"money": Game.money,
		"hour": Game.env.hour if Game.env else 9.0,
		"weather": Game.env.weather if Game.env else "clear",
		"settings": Game.settings,
		"skills": Game.skills.to_dict(),
		"garage": Game.garage.to_array(),
		"radio": Game.radio_station,
		"last_vehicle": ({"id": p.wanted_vehicle.def_id, "mods": p.wanted_vehicle.mods} if p.wanted_vehicle and is_instance_valid(p.wanted_vehicle) and p.wanted_vehicle.owner_is_player and not p.wanted_vehicle.destroyed else {}),
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		Game.notify("Save failed: " + error_string(FileAccess.get_open_error()), "warn")
		return false
	f.store_string(JSON.stringify(_ser(data), "\t"))
	f.close()
	Game.notify("Game saved", "good")
	return true


static func has_save() -> bool:
	return FileAccess.file_exists(PATH)


static func load_game() -> bool:
	if not has_save():
		Game.notify("No save found", "warn")
		return false
	var txt := FileAccess.get_file_as_string(PATH)
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		Game.notify("Save file corrupted", "warn")
		return false
	var d: Dictionary = _des(parsed)
	var p := Game.player
	if p.vehicle:
		p.exit_vehicle(false)
	if p.dead:
		p.respawn("hospital")
	var pd: Dictionary = d.get("player", {})
	var pos: Array = pd.get("pos", [242, 1.3, 27])
	Game.main.teleport_player(Vector3(pos[0], pos[1], pos[2]))
	p.health = float(pd.get("health", p.max_health))
	p.armor = float(pd.get("armor", 0.0))
	if pd.has("look"):
		p.look_data = pd.look
		p.rig.build(p.look_data)
	p.weapons.inv.clear()
	p.weapons.inv["fists"] = {"mag": 0, "reserve": 0, "mods": {}}
	for id in pd.get("weapons", {}):
		var e: Dictionary = pd.weapons[id]
		p.weapons.inv[id] = {"mag": int(e.get("mag", 0)), "reserve": int(e.get("reserve", 0)), "mods": e.get("mods", {})}
	p.weapons.current = "fists"
	p.weapons.select(str(pd.get("current", "fists")))
	p.weapon_model_id = ""
	p._refresh_weapon_model()
	p.has_parachute = bool(pd.get("parachute", false))
	p.set_scuba(bool(pd.get("scuba", false)))
	Game.money = int(d.get("money", Game.money))
	Game.money_changed.emit(Game.money)
	if Game.env:
		Game.env.set_hour(float(d.get("hour", 9.0)))
		Game.env.set_weather(str(d.get("weather", "clear")), true)
	var st: Dictionary = d.get("settings", {})
	for k in st:
		Game.settings[k] = st[k]
	Game.skills.from_dict(d.get("skills", {}))
	Game.garage.from_array(d.get("garage", []))
	Game.radio_station = int(d.get("radio", 0))
	var lv: Dictionary = d.get("last_vehicle", {})
	if not lv.is_empty():
		var v := VehicleBase.spawn(str(lv.id), Transform3D(Basis.IDENTITY, Vector3(pos[0] + 4.0, pos[1] + 1.0, pos[2])), null, lv.get("mods", {}))
		v.owner_is_player = true
		p.wanted_vehicle = v
	if Game.wanted:
		Game.wanted.clear()
	Game.notify("Save loaded (" + str(d.get("time_saved", "")) + ")", "good")
	return true
