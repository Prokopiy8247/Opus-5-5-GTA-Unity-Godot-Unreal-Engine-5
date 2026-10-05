class_name Minimap
extends Control
## Rotating radar (HUD) or full-screen map (big=true): roads, water, districts, POIs, police with
## vision cones during search, wanted search area, waypoint and GPS route.

static var map_tex: ImageTexture
static var map_img: Image
const MAP_HALF := 320.0
const PX := 1.0      # pixels per metre in the baked map

var big := false
var zoom := 1.6      # screen px per metre (radar)
var big_zoom := 1.0
var big_center := Vector2.ZERO
var _route_t := 0.0
var route: Array = []
var _dragging := false


static func bake(w: World) -> void:
	var n := int(MAP_HALF * 2.0 * PX)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var water := Color(0.12, 0.28, 0.4)
	var deep := Color(0.08, 0.2, 0.32)
	var land := Color(0.24, 0.27, 0.25)
	var sand := Color(0.55, 0.5, 0.38)
	var grass := Color(0.22, 0.33, 0.22)
	for y in range(0, n, 2):
		for x in range(0, n, 2):
			var wx := x / PX - MAP_HALF
			var wz := y / PX - MAP_HALF
			var h := WorldMap.height(wx, wz)
			var c: Color
			if h < -0.05:
				c = water.lerp(deep, clampf(-h / 20.0, 0.0, 1.0))
			elif WorldMap.beach_weight(wx, wz) > 0.4 and h < 1.05 and WorldMap.coast_sdf(wx, wz) > -45.0:
				c = sand
			elif h > 2.0:
				c = grass.lerp(Color(0.3, 0.42, 0.28), clampf(h / 40.0, 0.0, 1.0))
			else:
				c = land
			img.fill_rect(Rect2i(x, y, 2, 2), c)
	# blocks
	for b in WorldMap.blocks():
		var r: Rect2 = b.rect
		var col := Color(0.33, 0.35, 0.37)
		match b.kind:
			"park": col = Color(0.25, 0.42, 0.25)
			"residential", "safehouse": col = Color(0.36, 0.34, 0.3)
			"industrial", "modshop": col = Color(0.3, 0.31, 0.34)
			"plaza": col = Color(0.42, 0.38, 0.33)
		img.fill_rect(_to_px(r), col)
	for r2 in WorldMap.edge_strips():
		img.fill_rect(_to_px(r2), Color(0.36, 0.37, 0.38))
	# airfield
	img.fill_rect(_to_px(Rect2(-262, -246, 330, 30)), Color(0.15, 0.15, 0.16))
	img.fill_rect(_to_px(Rect2(-245, -214, 300, 12)), Color(0.18, 0.18, 0.19))
	# roads
	for rd in WorldMap.roads():
		var a: Vector2 = rd.a
		var b2: Vector2 = rd.b
		var hw: float = rd.hw
		var rr := Rect2(Vector2(minf(a.x, b2.x) - hw, minf(a.y, b2.y) - hw), Vector2(absf(b2.x - a.x) + hw * 2.0, absf(b2.y - a.y) + hw * 2.0))
		img.fill_rect(_to_px(rr), Color(0.62, 0.64, 0.66) if rd.lanes == 1 else Color(0.85, 0.75, 0.45))
	var pts := RoadBuilder.smooth_path(WorldMap.HILL_ROAD, 1.0)
	for p in pts:
		img.fill_rect(_to_px(Rect2(p - Vector2(3.5, 3.5), Vector2(7, 7))), Color(0.62, 0.64, 0.66))
	# piers
	img.fill_rect(_to_px(Rect2(-38, 196, 12, 64)), Color(0.5, 0.4, 0.3))
	img.fill_rect(_to_px(Rect2(-58, 256, 52, 44)), Color(0.5, 0.4, 0.3))
	map_img = img
	map_tex = ImageTexture.create_from_image(img)


static func _to_px(r: Rect2) -> Rect2i:
	return Rect2i(int((r.position.x + MAP_HALF) * PX), int((r.position.y + MAP_HALF) * PX), int(r.size.x * PX), int(r.size.y * PX))


func _process(delta: float) -> void:
	_route_t -= delta
	if _route_t <= 0.0:
		_route_t = 1.0
		_update_route()
	queue_redraw()


func _update_route() -> void:
	route.clear()
	if Game.hud == null or Game.player == null or not Game.hud.has_waypoint:
		return
	var w := Game.world
	if w == null or w.road_graph == null:
		return
	var pp := Game.player.global_position
	route = w.road_graph.route(pp, Game.hud.waypoint)


func _w2s(p: Vector3, center: Vector2, origin: Vector3, rot: float, scale: float) -> Vector2:
	var d := Vector2(p.x - origin.x, p.z - origin.z) * scale
	return center + d.rotated(rot)


func _draw() -> void:
	if map_tex == null or Game.player == null:
		return
	var p := Game.player
	var ppos: Vector3 = p.vehicle.global_position if p.vehicle else p.global_position
	var sz := size
	var center := sz * 0.5
	var rot := 0.0
	var scale := zoom
	var origin := ppos
	if big:
		scale = big_zoom * minf(sz.x, sz.y) / 640.0
		origin = Vector3(big_center.x, 0, big_center.y)
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.06, 0.12, 0.18, 0.96))
	else:
		rot = Game.cam.yaw if Game.cam else 0.0
		var veh := p.vehicle
		if veh and veh.linear_velocity.length() > 8.0:
			scale = zoom * lerpf(1.0, 0.55, clampf(veh.linear_velocity.length() / 50.0, 0.0, 1.0))
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.18, 0.26, 0.9))
	# map texture
	var tl := Vector2(-MAP_HALF - origin.x, -MAP_HALF - origin.z) * scale
	draw_set_transform(center, rot, Vector2.ONE)
	draw_texture_rect(map_tex, Rect2(tl, Vector2(MAP_HALF * 2.0, MAP_HALF * 2.0) * scale), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font := UITheme.font(true)
	# wanted search area + police
	if Game.wanted and Game.wanted.level > 0:
		var sc := _w2s(Game.wanted.search_center, center, origin, rot, scale)
		if Game.wanted.state == "search":
			var pulse := 0.25 + 0.1 * sin(Time.get_ticks_msec() * 0.008)
			draw_circle(sc, Game.wanted.search_radius * scale, Color(1, 0.2, 0.2, pulse * 0.5))
		for n in Game.npcs:
			var npc := n as NPC
			if npc == null or npc.dead or npc.kind not in ["police", "swat"] or npc.vehicle != null:
				continue
			var s := _w2s(npc.global_position, center, origin, rot, scale)
			_draw_cone(s, npc, rot, scale)
			draw_circle(s, 4.0, Color(0.3, 0.5, 1.0))
		if Game.police:
			for u in Game.police.units + Game.police.helis:
				if is_instance_valid(u):
					var s2 := _w2s((u as Node3D).global_position, center, origin, rot, scale)
					var blink := int(Time.get_ticks_msec() / 250) % 2 == 0
					draw_circle(s2, 5.5, Color(1, 0.2, 0.2) if blink else Color(0.25, 0.45, 1.0))
	# GPS route
	if route.size() > 1:
		var prev := _w2s(route[0], center, origin, rot, scale)
		for i in range(1, route.size()):
			var s3 := _w2s(route[i], center, origin, rot, scale)
			draw_line(prev, s3, Color(0.95, 0.75, 0.2, 0.9), 4.0 if not big else 3.0, true)
			prev = s3
	# POIs
	if Game.world:
		var label_rects: Array[Rect2] = []
		for id in Game.world.poi:
			var poi: Dictionary = Game.world.poi[id]
			if not poi.has("icon"):
				continue
			var s4 := _w2s(poi.pos, center, origin, rot, scale)
			if not big and s4.distance_to(center) > minf(sz.x, sz.y) * 0.5 - 8.0:
				continue
			draw_circle(s4, 9.0, Color(0.05, 0.07, 0.09, 0.85))
			draw_arc(s4, 9.0, 0, TAU, 20, UITheme.ACCENT, 1.5, true)
			draw_string(font, s4 + Vector2(-5, 5), str(poi.icon), HORIZONTAL_ALIGNMENT_CENTER, 10, 12, UITheme.TEXT)
			if big:
				# skip labels that would overlap an earlier one (icons are always drawn)
				var tw := font.get_string_size(str(poi.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
				var lr := Rect2(s4 + Vector2(11, -8), Vector2(tw + 4, 16))
				var free := true
				for r in label_rects:
					if r.intersects(lr):
						free = false
						break
				if free:
					label_rects.append(lr)
					draw_string(font, s4 + Vector2(12, 5), str(poi.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UITheme.TEXT)
	# district labels on big map
	if big:
		for d in WorldMap.DISTRICTS:
			var r: Rect2 = d.rect
			var cpos := _w2s(Vector3(r.get_center().x, 0, r.get_center().y), center, origin, rot, scale)
			draw_string(font, cpos - Vector2(60, 0), str(d.name).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 120, 16, Color(1, 1, 1, 0.55))
	# waypoint
	if Game.hud and Game.hud.has_waypoint:
		var ws := _w2s(Game.hud.waypoint, center, origin, rot, scale)
		if not big:
			var lim := minf(sz.x, sz.y) * 0.5 - 10.0
			if ws.distance_to(center) > lim:
				ws = center + (ws - center).normalized() * lim
		draw_circle(ws, 7.0, Color(0.95, 0.75, 0.2))
		draw_circle(ws, 3.0, Color(0.1, 0.1, 0.1))
	# player arrow
	var heading := 0.0
	if p.vehicle:
		var f := -p.vehicle.global_basis.z
		heading = atan2(f.x, -f.z)
	else:
		var f2 := U.dir_of_yaw(p._yaw + PI)
		heading = atan2(f2.x, -f2.z)
	var ps := _w2s(ppos, center, origin, rot, scale)
	var a := heading + rot
	var tip := ps + Vector2(sin(a), -cos(a)) * 9.0
	var l := ps + Vector2(sin(a + 2.5), -cos(a + 2.5)) * 7.0
	var r2 := ps + Vector2(sin(a - 2.5), -cos(a - 2.5)) * 7.0
	draw_colored_polygon(PackedVector2Array([tip, l, ps, r2]), Color(1, 1, 1))
	draw_polyline(PackedVector2Array([tip, l, ps, r2, tip]), Color(0, 0, 0, 0.6), 1.0)
	if not big:
		# north marker
		var nrot := Vector2(0, -1).rotated(rot) * (minf(sz.x, sz.y) * 0.5 - 12.0)
		draw_string(font, center + nrot - Vector2(5, -5), "N", HORIZONTAL_ALIGNMENT_CENTER, 12, 14, UITheme.ACCENT)
	else:
		draw_string(font, Vector2(20, sz.y - 20), "Left-click: set waypoint · Right-click: clear · Wheel: zoom · Drag: pan · M/Esc: close", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UITheme.DIM)


func _draw_cone(s: Vector2, npc: NPC, rot: float, scale: float) -> void:
	var f := -npc.global_basis.z
	var a := atan2(f.x, -f.z) + rot
	var r := 34.0 * scale
	var pts := PackedVector2Array([s])
	for k in 7:
		var aa := a - 0.6 + 1.2 * k / 6.0
		pts.append(s + Vector2(sin(aa), -cos(aa)) * r)
	draw_colored_polygon(pts, Color(1.0, 0.3, 0.3, 0.18) if not npc.sees_player else Color(1.0, 0.1, 0.1, 0.35))


func _gui_input(event: InputEvent) -> void:
	if not big:
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var scale := big_zoom * minf(size.x, size.y) / 640.0
		var wpos := big_center + (mb.position - size * 0.5) / scale
		if mb.button_index == MOUSE_BUTTON_LEFT:
			Game.hud.set_waypoint(Vector3(wpos.x, 1.0, wpos.y))
			_route_t = 0.0
			Audio.play_ui("ui_click")
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			Game.hud.clear_waypoint()
			route.clear()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			big_zoom = minf(big_zoom * 1.15, 6.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			big_zoom = maxf(big_zoom / 1.15, 0.6)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = true
	if event is InputEventMouseMotion and (Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and event.relative.length() > 2.0):
		var scale2 := big_zoom * minf(size.x, size.y) / 640.0
		big_center -= event.relative / scale2
