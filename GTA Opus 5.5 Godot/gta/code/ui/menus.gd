class_name Menus
extends Node
## All modal panels: pause, map, phone, shops, garage, customization, wardrobe/barber, rentals, debug.

var hud: HUD


# ------------------------------------------------------------------ helpers

func _frame(title: String, subtitle := "", width := 560, pauses := false) -> Dictionary:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.35)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.panel(UITheme.BG2, 12, 2.0))
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.custom_minimum_size = Vector2(width, 120)
	pc.position = Vector2(-width * 0.5, -330)
	dim.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	var t := UITheme.label(title, 30, UITheme.ACCENT, true)
	vb.add_child(t)
	if subtitle != "":
		var s := UITheme.label(subtitle, 16, UITheme.DIM)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(s)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(width - 30, 460)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 5)
	sc.add_child(list)
	var foot := HBoxContainer.new()
	vb.add_child(foot)
	foot.add_child(UITheme.button("Close  [Esc]", func(): hud.close_panel(), 160))
	var money := UITheme.label("   Cash: " + U.money_str(Game.money), 18, UITheme.GOOD, true)
	foot.add_child(money)
	if pauses:
		dim.set_meta("pauses", true)
		Game.set_paused(true)
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	return {"root": dim, "list": list, "money": money, "vb": vb}


func _row(list: VBoxContainer, text: String, cb: Callable, price := -1, enabled := true) -> Button:
	var label := text if price < 0 else "%s   —   %s" % [text, U.money_str(price) if price > 0 else "FREE"]
	var b := UITheme.button(label, cb)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = not enabled
	list.add_child(b)
	return b


func _header(list: VBoxContainer, text: String) -> void:
	var l := UITheme.label(text, 16, UITheme.ACCENT2, true)
	list.add_child(l)


func _refresh_money(f: Dictionary) -> void:
	(f.money as Label).text = "   Cash: " + U.money_str(Game.money)


func _buy(price: int) -> bool:
	if Game.unlock_all_mods:
		return true
	return Game.spend(price)


# ------------------------------------------------------------------ pause

func open_pause() -> void:
	var f := _frame("PAUSED", "Vesper Bay — free roam sandbox. No missions: go anywhere, do anything.", 640, true)
	var l: VBoxContainer = f.list
	_row(l, "Resume", func(): hud.close_panel())
	_row(l, "Save game", func():
		SaveSystem.save_game()
		hud.close_panel())
	_row(l, "Load last save", func():
		hud.close_panel()
		SaveSystem.load_game())
	_header(l, "CHARACTER SKILLS")
	for k in Skills.NAMES:
		var row := HBoxContainer.new()
		var name := UITheme.label(Skills.LABELS[k], 16)
		name.custom_minimum_size.x = 180
		row.add_child(name)
		var pb := ProgressBar.new()
		pb.custom_minimum_size = Vector2(300, 14)
		pb.max_value = 100.0
		pb.value = Game.skills.v[k]
		pb.show_percentage = false
		row.add_child(pb)
		row.add_child(UITheme.label("  %d%%" % int(Game.skills.v[k]), 15, UITheme.DIM))
		l.add_child(row)
	_header(l, "SETTINGS")
	_slider(l, "Mouse sensitivity", 0.0008, 0.006, Game.settings.mouse_sens, func(v): Game.settings.mouse_sens = v)
	_slider(l, "Field of view", 60.0, 90.0, Game.settings.fov, func(v): Game.settings.fov = v)
	_slider(l, "Master volume (dB)", -30.0, 6.0, Game.settings.master_db, func(v):
		Game.settings.master_db = v
		AudioServer.set_bus_volume_db(0, v))
	_slider(l, "Radio volume (dB)", -30.0, 6.0, Game.settings.music_db, func(v):
		Game.settings.music_db = v
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), v))
	var inv := CheckBox.new()
	inv.text = "Invert mouse Y"
	inv.button_pressed = Game.settings.invert_y
	inv.toggled.connect(func(b): Game.settings.invert_y = b)
	l.add_child(inv)
	_row(l, "Graphics: toggle high quality (SSAO/SSIL/volumetric fog)", func():
		Game.settings.quality = 1 - int(Game.settings.quality)
		Game.main.apply_quality()
		Game.notify("Graphics quality: " + ("High" if Game.settings.quality == 1 else "Performance")))
	_header(l, "CONTROLS")
	var help := UITheme.label(CONTROLS_TEXT, 14, UITheme.DIM)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 560
	l.add_child(help)
	_row(l, "Quit to desktop", func(): get_tree().quit())
	hud.open_panel(f.root)


const CONTROLS_TEXT := """ON FOOT: WASD move · Mouse look · SHIFT sprint · SPACE jump/vault (aim+SPACE = roll) · CTRL/C stealth crouch · Q cover · RMB aim · LMB fire / melee (hold = heavy, crouch behind = takedown) · RMB with melee = block · R reload · 1-8 / wheel / hold TAB weapon wheel · E interact / ladder · F enter / steal vehicle · V camera · M map · ↑ or P phone · F1 benchmark menu · F5 quick-save · F9 quick-load · F2 hide HUD
VEHICLES: W/S throttle & brake/reverse · A/D steer · SPACE handbrake · H horn · L lights · G siren · , . radio · X look back · RMB+LMB drive-by · F exit (bail at speed)
HELICOPTER: SPACE up · CTRL down · W/S pitch · A/D yaw · Q/E roll · PLANE: SHIFT/CTRL throttle · W/S pitch · A/D roll · Q/E rudder
SWIM: SPACE surface · CTRL dive · PARACHUTE: SPACE open · A/D steer · S/SHIFT flare"""


func _slider(l: VBoxContainer, text: String, mn: float, mx: float, val: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	var lab := UITheme.label(text, 16)
	lab.custom_minimum_size.x = 220
	row.add_child(lab)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = (mx - mn) / 100.0
	s.value = val
	s.custom_minimum_size = Vector2(300, 20)
	s.value_changed.connect(cb)
	row.add_child(s)
	l.add_child(row)


# ------------------------------------------------------------------ map

func open_map() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.set_meta("is_map", true)
	var m := Minimap.new()
	m.big = true
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.big_center = Vector2(Game.player.global_position.x, Game.player.global_position.z)
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(m)
	var t := UITheme.label("VESPER BAY", 34, UITheme.ACCENT, true)
	t.position = Vector2(30, 20)
	root.add_child(t)
	hud.open_panel(root)


# ------------------------------------------------------------------ phone

func open_phone() -> void:
	Audio.play_ui("phone")
	var f := _frame("📱 VESPA PHONE", "Contacts & apps", 420)
	var l: VBoxContainer = f.list
	_header(l, "CONTACTS")
	_row(l, "Gold Line Taxi — request a cab", func():
		hud.close_panel()
		Game.main.taxi.call_taxi())
	_row(l, "Torque Theory Mechanic — deliver a garage vehicle", func():
		hud.close_panel()
		_open_garage(true))
	_row(l, "Medic One — heal on the spot ($400)", func():
		if _buy(400):
			Game.player.health = Game.player.max_health
			Game.notify("Paramedic patched you up", "good")
		hud.close_panel())
	_header(l, "APPS")
	_row(l, "Map & GPS waypoint", func():
		hud.close_panel()
		open_map())
	_row(l, "Camera — snap a photo (saved to user://photos)", func():
		hud.close_panel()
		Game.main.take_photo())
	_row(l, "Quick save", func():
		SaveSystem.save_game()
		hud.close_panel())
	_row(l, "Radio: next station", func():
		Game.radio_station = (Game.radio_station + 1) % Audio.STATIONS.size()
		if Game.player.vehicle:
			Game.player.vehicle.set_radio(Game.radio_station)
		else:
			Game.notify("Radio set to " + Audio.STATIONS[Game.radio_station] + " (plays in vehicles)")
		hud.close_panel())
	hud.open_panel(f.root)


# ------------------------------------------------------------------ POI dispatch

static func poi_prompt(p: Dictionary) -> String:
	match str(p.get("type", p.get("id", ""))):
		"gunshop": return "[E] Brass & Barrel — weapons, ammo, armour, workbench"
		"range": return "[E] Shooting range challenge"
		"clothes": return "[E] Threadline Apparel — clothes"
		"barber": return "[E] Fade Lab — hair & beard"
		"safehouse": return "[E] Safehouse — save game"
		"bed": return "[E] Sleep (save & skip 6 h)"
		"wardrobe": return "[E] Wardrobe"
		"garage": return "[E] Garage — retrieve a stored vehicle"
		"modshop": return "Drive a vehicle in and press [E] to customize"
		"dealer": return "[E] Vesper Motors — buy a vehicle"
		"gas", "food": return "[E] Grab a snack (+health)"
		"hospital": return "[E] Treatment & body armour"
		"airfield": return "[E] Rent an aircraft"
		"helipad": return "[E] Rent a helicopter"
		"marina": return "[E] Rent a boat"
		"viewpoint": return "[E] Take a parachute"
		"police": return "[E] Turn yourself in (clears wanted level, fine)"
	return ""


func open_poi(p: Dictionary) -> void:
	var t: String = str(p.get("type", p.get("id", "")))
	match t:
		"gunshop": _gunshop()
		"range":
			if Game.activities:
				Game.activities.start_range()
		"clothes", "wardrobe": _clothes(t == "wardrobe")
		"barber": _barber()
		"safehouse":
			SaveSystem.save_game()
		"bed": _bed()
		"garage": _open_garage(false)
		"dealer": _dealer()
		"gas", "food":
			if _buy(25):
				Game.player.health = minf(Game.player.health + 60.0, Game.player.max_health)
				Game.notify("Snack eaten (+health)", "good")
		"hospital": _hospital()
		"airfield": _rental(["plane", "jet"], "plane_0", "AIRFIELD RENTALS")
		"helipad": _rental(["heli"], "heli_pad", "HELIPAD RENTALS")
		"marina": _rental(["boat"], "boat_0_0", "MARINA RENTALS")
		"viewpoint":
			Game.player.give_parachute()
		"police":
			if Game.wanted.level > 0:
				Game.player.arrest()
			else:
				Game.notify("Nothing to confess today.")


# ------------------------------------------------------------------ shops

func _gunshop() -> void:
	var f := _frame("BRASS & BARREL ARMS", "Original firearms, ammunition, armour and a gunsmith workbench.", 640)
	var l: VBoxContainer = f.list
	var p := Game.player
	_header(l, "ARMOUR")
	_row(l, "Body armour (full)", func():
		if _buy(500):
			p.armor = 100.0
			_refresh_money(f), 500)
	for slot in range(0, 8):
		var ids := WeaponDB.ids_in_slot(slot)
		if ids.is_empty():
			continue
		_header(l, WeaponDB.SLOT_NAMES[slot].to_upper())
		for id in ids:
			if id == "fists":
				continue
			var d := WeaponDB.get_def(id)
			if not p.weapons.has(id):
				_row(l, "Buy " + str(d.name), func():
					if _buy(int(d.price)):
						p.weapons.give(id)
						p.weapons.select(id)
						Game.notify(str(d.name) + " purchased", "good")
						hud.close_panel()
						_gunshop(), int(d.price))
			elif not d.get("melee", false):
				_row(l, "%s ammo (+%d)" % [d.name, int(d.get("ammo_pack", 30))], func():
					if _buy(int(d.get("ammo_price", 50))):
						p.weapons.add_ammo(id, int(d.get("ammo_pack", 30)))
						_refresh_money(f), int(d.get("ammo_price", 50)))
				for mod in d.get("mods", []):
					var mi: Dictionary = WeaponDB.MODS[mod]
					var owned: bool = p.weapons.inv[id].mods.get(mod, false)
					if mod == "tint":
						_row(l, "   Workbench: %s finish (cycle)" % d.name, func():
							if _buy(int(mi.price)):
								var cur: int = int(p.weapons.inv[id].mods.get("tint_idx", 0))
								p.weapons.inv[id].mods["tint_idx"] = (cur + 1) % WeaponDB.TINTS.size()
								p.weapon_model_id = ""
								p._refresh_weapon_model()
								_refresh_money(f), int(mi.price))
					elif not owned:
						_row(l, "   Workbench: add %s to %s" % [mi.name, d.name], func():
							if _buy(int(mi.price)):
								p.weapons.inv[id].mods[mod] = true
								if mod == "extmag":
									p.weapons.inv[id].mag = int(WeaponDB.stat(id, "mag", p.weapons.inv[id].mods))
								p.weapon_model_id = ""
								p._refresh_weapon_model()
								Game.notify(mi.name + " fitted", "good")
								hud.close_panel()
								_gunshop(), int(mi.price))
	hud.open_panel(f.root)


func _clothes(free: bool) -> void:
	var f := _frame("THREADLINE APPAREL" if not free else "WARDROBE", "Cosmetic only. Changing outfits while police are searching makes you harder to recognise.", 600)
	var l: VBoxContainer = f.list
	var p := Game.player
	var price := 0 if free else 1
	var apply := func(key: String, val, cost: int):
		if _buy(cost * price):
			p.look_data[key] = val
			p.rig.build(p.look_data)
			p.weapon_model_id = ""
			p._refresh_weapon_model()
			if Game.wanted:
				Game.wanted.outfit_id += 1
			_refresh_money(f)
	_header(l, "TOPS")
	for s in [["T-shirt", 0], ["Bomber jacket", 1], ["Hoodie", 2], ["Suit jacket", 3], ["Work shirt", 4]]:
		_row(l, s[0], func(): apply.call("top_style", s[1], 120), 120 * price)
	_header(l, "TOP COLOUR")
	for c in HumanoidRig.CLOTH:
		var b := _row(l, "■ Colour", func(): apply.call("top", c, 60), 60 * price)
		b.add_theme_color_override("font_color", c)
	_header(l, "PANTS")
	for c2 in HumanoidRig.PANTS:
		var b2 := _row(l, "■ Pants", func(): apply.call("pants", c2, 80), 80 * price)
		b2.add_theme_color_override("font_color", c2)
	_header(l, "SHOES")
	for c3 in [Color(0.1, 0.1, 0.1), Color(0.95, 0.95, 0.95), Color(0.45, 0.3, 0.2), Color(0.8, 0.2, 0.2), Color(0.2, 0.5, 0.9)]:
		var b3 := _row(l, "■ Sneakers", func(): apply.call("shoes", c3, 70), 70 * price)
		b3.add_theme_color_override("font_color", c3)
	_header(l, "HATS & GLASSES")
	for h in [["No hat", 0], ["Cap", 1], ["Beanie", 2]]:
		_row(l, h[0], func(): apply.call("hat", h[1], 40), 40 * price)
	for g in [["No glasses", 0], ["Sunglasses", 1], ["Clear specs", 2]]:
		_row(l, g[0], func(): apply.call("glasses", g[1], 50), 50 * price)
	hud.open_panel(f.root)


func _barber() -> void:
	var f := _frame("FADE LAB BARBERS", "Hair, colour and facial hair.", 520)
	var l: VBoxContainer = f.list
	var p := Game.player
	var apply := func(key: String, val):
		if _buy(45):
			p.look_data[key] = val
			p.rig.build(p.look_data)
			p.weapon_model_id = ""
			p._refresh_weapon_model()
			if Game.wanted:
				Game.wanted.outfit_id += 1
			_refresh_money(f)
	_header(l, "STYLE")
	for s in [["Buzz / bald", 0], ["Short crop", 1], ["Long", 2], ["Bun", 3], ["Shoulder length", 4], ["Mohawk", 5]]:
		_row(l, s[0], func(): apply.call("hair_style", s[1]), 45)
	_header(l, "COLOUR")
	for c in HumanoidRig.HAIR_COLS:
		var b := _row(l, "■ Hair colour", func(): apply.call("hair", c), 45)
		b.add_theme_color_override("font_color", c)
	_header(l, "FACIAL HAIR")
	for bd in [["Clean shaven", 0], ["Stubble", 1], ["Full beard", 2]]:
		_row(l, bd[0], func(): apply.call("beard", bd[1]), 45)
	hud.open_panel(f.root)


func _bed() -> void:
	var f := _frame("SAFEHOUSE BED", "Sleep to save and pass time.", 420)
	var l: VBoxContainer = f.list
	_row(l, "Sleep 6 hours & save", func():
		Game.env.set_hour(Game.env.hour + 6.0)
		Game.player.health = Game.player.max_health
		SaveSystem.save_game()
		hud.close_panel())
	_row(l, "Sleep until morning (07:00) & save", func():
		Game.env.set_hour(7.0)
		Game.player.health = Game.player.max_health
		SaveSystem.save_game()
		hud.close_panel())
	_row(l, "Sleep until night (22:00) & save", func():
		Game.env.set_hour(22.0)
		SaveSystem.save_game()
		hud.close_panel())
	hud.open_panel(f.root)


func _hospital() -> void:
	var f := _frame("ST. VESPER MEDICAL", "", 440)
	var l: VBoxContainer = f.list
	_row(l, "Full treatment", func():
		if _buy(200):
			Game.player.health = Game.player.max_health
			_refresh_money(f), 200)
	_row(l, "Body armour", func():
		if _buy(500):
			Game.player.armor = 100.0
			_refresh_money(f), 500)
	hud.open_panel(f.root)


func _rental(ids: Array, spawn_key: String, title: String) -> void:
	var f := _frame(title, "Vehicles appear on the apron / pad / pier nearby.", 480)
	var l: VBoxContainer = f.list
	for id in ids:
		var d := VehicleDB.get_def(id)
		var price := int(d.price / 40)
		_row(l, "Rent " + str(d.name), func():
			if _buy(price):
				var xf: Transform3D = Game.world.vehicle_spawns.get(spawn_key, Transform3D(Basis.IDENTITY, Game.player.global_position + Vector3(6, 2, 0)))
				var v := VehicleBase.spawn(id, xf)
				v.owner_is_player = true
				Game.notify(str(d.name) + " is ready", "good")
				hud.close_panel(), price)
	hud.open_panel(f.root)


func _dealer() -> void:
	var f := _frame("VESPER MOTORS", "Buy a vehicle — it's delivered to the lot outside and can be stored in your safehouse garage.", 600)
	var l: VBoxContainer = f.list
	for id in VehicleDB.SPAWN_MENU:
		var d := VehicleDB.get_def(id)
		if int(d.price) <= 0:
			continue
		_row(l, "%s  (%s)" % [d.name, d.cls], func():
			if _buy(int(d.price)):
				var key := "dealer_%d" % (randi() % 8)
				var xf: Transform3D = Game.world.vehicle_spawns.get(key, Transform3D(Basis.IDENTITY, Game.player.global_position + Vector3(6, 1, 0)))
				var v := VehicleBase.spawn(id, xf)
				v.owner_is_player = true
				Game.notify(str(d.name) + " delivered to the lot", "good")
				hud.close_panel(), int(d.price))
	hud.open_panel(f.root)


func _open_garage(deliver: bool) -> void:
	var f := _frame("PERSONAL GARAGE", "Stored vehicles keep their customization and persist in saves (%d/%d)." % [Game.garage.slots.size(), GarageStorage.SLOTS], 520)
	var l: VBoxContainer = f.list
	if Game.garage.slots.is_empty():
		l.add_child(UITheme.label("No vehicles stored. Drive one to the safehouse garage door and press E.", 16, UITheme.DIM))
	for i in Game.garage.slots.size():
		var s: Dictionary = Game.garage.slots[i]
		var d := VehicleDB.get_def(s.id)
		_row(l, ("Deliver " if deliver else "Take out ") + str(d.name), func():
			var slot := Game.garage.take(i)
			var xf: Transform3D
			if deliver:
				var nl := Game.world.road_graph.nearest_lane(Game.player.global_position, 80.0)
				var pos: Vector3 = nl.point if not nl.is_empty() else Game.player.global_position + Vector3(4, 1, 0)
				xf = Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.6, 0))
			else:
				xf = Game.world.vehicle_spawns.get("safehouse_garage", Transform3D(Basis.IDENTITY, Game.player.global_position + Vector3(4, 1, 0)))
			var v := VehicleBase.spawn(slot.id, xf, null, slot.mods)
			v.owner_is_player = true
			Game.notify(str(d.name) + (" delivered nearby" if deliver else " is outside"), "good")
			hud.close_panel())
	hud.open_panel(f.root)


func store_vehicle(v: VehicleBase) -> void:
	if v.kind in ["heli", "plane", "boat"]:
		Game.notify("Aircraft and boats can't be stored here", "warn")
		return
	if Game.garage.store(v):
		Game.player.exit_vehicle(false)
		v.queue_free()


# ------------------------------------------------------------------ vehicle customization

func open_modshop(v: VehicleBase) -> void:
	var f := _frame("TORQUE THEORY CUSTOMS", "%s — health %d%%. Cosmetic parts rebuild the model; performance parts change handling." % [v.display_name, int(v.health / v.max_health * 100.0)], 660)
	var l: VBoxContainer = f.list
	var repair_cost := int((1.0 - v.health / v.max_health) * 1500.0)
	_row(l, "REPAIR (body, glass, lights, tyres, handling)", func():
		if _buy(repair_cost):
			v.repair()
			hud.close_panel()
			open_modshop(v), repair_cost)
	for cat in VehicleMods.CATEGORIES:
		if v.kind in ["boat", "heli", "plane"] and cat.id not in ["paint", "paint2", "finish", "engine", "armor"]:
			continue
		_header(l, str(cat.name).to_upper())
		var row := HFlowContainer.new()
		l.add_child(row)
		if cat.get("type", "") == "color":
			for c in VehicleDB.PAINTS:
				var b := UITheme.button("■■", func():
					if _buy(int(cat.price)):
						var m := v.mods.duplicate(true)
						m[cat.key] = c
						v.apply_mods(m)
						_refresh_money(f))
				b.add_theme_color_override("font_color", c)
				b.add_theme_font_size_override("font_size", 22)
				row.add_child(b)
		else:
			var opts: Array = cat.options
			for i in opts.size():
				var o: Array = opts[i]
				var cur = v.mods.get(cat.key, null)
				var is_cur: bool = cur == o[1] or (cur == null and i == 0)
				var price := VehicleMods.price_for(cat, i)
				var b2 := UITheme.button(("✔ " if is_cur else "") + "%s  %s" % [o[0], U.money_str(price)], func():
					if _buy(price):
						var m2 := v.mods.duplicate(true)
						m2[cat.key] = o[1]
						v.apply_mods(m2)
						Game.notify("%s: %s" % [cat.name, o[0]], "good")
						hud.close_panel()
						open_modshop(v))
				row.add_child(b2)
	hud.open_panel(f.root)


# ------------------------------------------------------------------ benchmark / debug menu

func open_debug() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.set_meta("is_debug", true)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.panel(UITheme.BG2, 10, 2.0))
	pc.position = Vector2(30, 30)
	pc.custom_minimum_size = Vector2(760, 0)
	root.add_child(pc)
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	vb.add_child(UITheme.label("BENCHMARK / ADMIN MENU  [F1]", 24, UITheme.ACCENT, true))
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(740, 560)
	vb.add_child(tabs)
	var p := Game.player
	# teleport
	var t1 := _tab(tabs, "Teleport")
	for tp in WorldMap.TELEPORTS:
		_grid_btn(t1, tp[0], func(): Game.main.teleport_player(tp[1]))
	_grid_btn(t1, "To waypoint", func():
		if hud.has_waypoint:
			Game.main.teleport_player(hud.waypoint + Vector3(0, 2, 0)))
	# vehicles
	var t2 := _tab(tabs, "Vehicles")
	for id in VehicleDB.SPAWN_MENU:
		_grid_btn(t2, "Spawn " + str(VehicleDB.get_def(id).name), func(): Game.main.spawn_vehicle_near_player(id))
	_grid_btn(t2, "Repair current vehicle", func():
		if p.vehicle:
			p.vehicle.repair())
	_grid_btn(t2, "Open customization (current)", func():
		if p.vehicle:
			hud.close_panel()
			open_modshop(p.vehicle))
	_grid_btn(t2, "Unlock all mods (free)", func():
		Game.unlock_all_mods = not Game.unlock_all_mods
		Game.notify("All mods free: " + str(Game.unlock_all_mods)))
	_grid_btn(t2, "Explode current vehicle", func():
		if p.vehicle:
			p.vehicle.explode())
	_grid_btn(t2, "Call taxi", func():
		hud.close_panel()
		Game.main.taxi.call_taxi())
	# weapons
	var t3 := _tab(tabs, "Weapons")
	_grid_btn(t3, "Give ALL weapons + ammo", func():
		for id in WeaponDB.W:
			p.weapons.give(id, 500)
		p.weapons.refill_all()
		Game.notify("All weapons granted", "good"))
	_grid_btn(t3, "Refill ammo", func(): p.weapons.refill_all())
	_grid_btn(t3, "Give all weapon mods", func():
		for id in p.weapons.inv:
			for m in WeaponDB.get_def(id).get("mods", []):
				p.weapons.inv[id].mods[m] = true
		p.weapon_model_id = ""
		p._refresh_weapon_model())
	for id2 in WeaponDB.W:
		if id2 == "fists":
			continue
		_grid_btn(t3, "Give " + str(WeaponDB.get_def(id2).name), func():
			p.weapons.give(id2, 200)
			p.weapons.select(id2))
	# player
	var t4 := _tab(tabs, "Player")
	_grid_btn(t4, "+$10,000", func(): Game.add_money(10000))
	_grid_btn(t4, "Set money $1,000,000", func(): Game.add_money(1000000 - Game.money))
	_grid_btn(t4, "Full health", func(): p.health = p.max_health)
	_grid_btn(t4, "Full armour", func(): p.armor = 100.0)
	_grid_btn(t4, "Set health 25%", func(): p.health = p.max_health * 0.25)
	_grid_btn(t4, "Toggle invulnerability", func():
		Game.invulnerable = not Game.invulnerable
		p.weapons.infinite_ammo = Game.invulnerable
		Game.notify("Invulnerable: " + str(Game.invulnerable)))
	_grid_btn(t4, "Give parachute", func(): p.give_parachute())
	_grid_btn(t4, "Refill lungs", func(): p.breath = 1.0)
	_grid_btn(t4, "Toggle scuba gear", func():
		p.set_scuba(not p.scuba)
		Game.notify("Scuba: " + str(p.scuba)))
	_grid_btn(t4, "Max all skills", func(): Game.skills.set_all(100.0))
	_grid_btn(t4, "Reset all skills", func(): Game.skills.set_all(0.0))
	_grid_btn(t4, "Skydive from 400 m", func():
		p.give_parachute()
		Game.main.teleport_player(p.global_position + Vector3(0, 400, 0)))
	# wanted
	var t5 := _tab(tabs, "Wanted & Police")
	for i in 6:
		_grid_btn(t5, "Wanted level %d" % i, func(): Game.wanted.set_level(i) if i > 0 else Game.wanted.clear())
	_grid_btn(t5, "Clear wanted", func(): Game.wanted.clear())
	_grid_btn(t5, "Spawn police car", func(): Game.police._spawn_car("police", maxi(Game.wanted.level, 1)))
	_grid_btn(t5, "Spawn police helicopter", func(): Game.police._spawn_heli())
	_grid_btn(t5, "Spawn foot officers", func():
		for k in 2:
			var o := Game.peds.make_npc("police", p.global_position + Vector3(randf_range(-12, 12), 1, randf_range(-12, 12)))
			Game.peds.peds.append(o))
	_grid_btn(t5, "Spawn hostile gang", func():
		for k in 3:
			var g := Game.peds.make_npc("gang", p.global_position + Vector3(randf_range(-14, 14), 1, randf_range(-14, 14)))
			g.threat = p
			g._set_brain("attack")
			Game.peds.peds.append(g))
	# world
	var t6 := _tab(tabs, "World")
	for h in [6.0, 9.0, 12.0, 17.5, 19.5, 21.0, 0.0, 3.0]:
		_grid_btn(t6, "Time %02d:%02d" % [int(h), int(fmod(h, 1.0) * 60)], func(): Game.env.set_hour(h))
	_grid_btn(t6, "Toggle time flow", func(): Game.env.time_running = not Game.env.time_running)
	for wname in EnvController.WEATHERS:
		_grid_btn(t6, "Weather: " + str(wname).capitalize(), func():
			Game.env.auto_weather = false
			Game.env.set_weather(wname))
	_grid_btn(t6, "Auto weather on", func(): Game.env.auto_weather = true)
	# toggles / info
	var t7 := _tab(tabs, "Toggles & Info")
	_grid_btn(t7, "Toggle traffic", func():
		Game.traffic_enabled = not Game.traffic_enabled
		Game.notify("Traffic: " + str(Game.traffic_enabled)))
	_grid_btn(t7, "Toggle pedestrians", func():
		Game.peds_enabled = not Game.peds_enabled
		Game.notify("Pedestrians: " + str(Game.peds_enabled)))
	_grid_btn(t7, "Toggle wildlife", func():
		Game.wildlife_enabled = not Game.wildlife_enabled
		Game.notify("Wildlife: " + str(Game.wildlife_enabled)))
	_grid_btn(t7, "Show FPS", func(): Game.show_fps = not Game.show_fps)
	_grid_btn(t7, "Show coordinates / sector", func(): Game.show_coords = not Game.show_coords)
	_grid_btn(t7, "Start shooting range", func():
		Game.main.teleport_player(Game.world.poi.range.pos + Vector3(0, 1, 0))
		hud.close_panel()
		Game.activities.start_range())
	_grid_btn(t7, "Save now", func(): SaveSystem.save_game())
	_grid_btn(t7, "Load save", func():
		hud.close_panel()
		SaveSystem.load_game())
	hud.open_panel(root)


func _tab(tabs: TabContainer, name: String) -> GridContainer:
	var sc := ScrollContainer.new()
	sc.name = name
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	sc.add_child(g)
	return g


func _grid_btn(g: GridContainer, text: String, cb: Callable) -> void:
	var b := UITheme.button(text, cb, 236)
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 14)
	g.add_child(b)
