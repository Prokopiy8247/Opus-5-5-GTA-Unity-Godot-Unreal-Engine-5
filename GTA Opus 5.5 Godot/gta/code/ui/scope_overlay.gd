class_name ScopeOverlay
extends Control
## Sniper / marksman scope overlay (circular lens with mil-dots).

func _process(_d: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.42
	var black := Color(0, 0, 0, 0.97)
	# mask outside the lens
	draw_rect(Rect2(0, 0, c.x - r, size.y), black)
	draw_rect(Rect2(c.x + r, 0, size.x - c.x - r, size.y), black)
	var pts := PackedVector2Array()
	for k in 65:
		var a := PI + PI * k / 64.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	pts.append(Vector2(c.x + r, 0))
	pts.append(Vector2(c.x - r, 0))
	draw_colored_polygon(pts, black)
	var pts2 := PackedVector2Array()
	for k in 65:
		var a2 := PI * k / 64.0
		pts2.append(c + Vector2(cos(a2), sin(a2)) * r)
	pts2.append(Vector2(c.x - r, size.y))
	pts2.append(Vector2(c.x + r, size.y))
	draw_colored_polygon(pts2, black)
	draw_arc(c, r, 0, TAU, 96, Color(0, 0, 0), 6.0)
	var lc := Color(0.05, 0.05, 0.05, 0.9)
	draw_line(c - Vector2(r, 0), c - Vector2(14, 0), lc, 2.0)
	draw_line(c + Vector2(14, 0), c + Vector2(r, 0), lc, 2.0)
	draw_line(c - Vector2(0, r), c - Vector2(0, 14), lc, 2.0)
	draw_line(c + Vector2(0, 14), c + Vector2(0, r), lc, 2.0)
	for k in range(1, 6):
		draw_circle(c + Vector2(0, k * r * 0.12), 2.5, lc)
		draw_circle(c + Vector2(k * r * 0.12, 0), 2.5, lc)
		draw_circle(c - Vector2(k * r * 0.12, 0), 2.5, lc)
	draw_circle(c, 1.5, Color(1, 0.2, 0.2))
