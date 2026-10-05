class_name UITheme
## Original HUD/menu theme: dark translucent panels, teal accent, condensed system font.

const ACCENT := Color(0.25, 0.85, 0.8)
const ACCENT2 := Color(1.0, 0.55, 0.3)
const BG := Color(0.05, 0.07, 0.09, 0.78)
const BG2 := Color(0.1, 0.13, 0.16, 0.9)
const TEXT := Color(0.94, 0.96, 0.97)
const DIM := Color(0.6, 0.66, 0.7)
const BAD := Color(0.95, 0.3, 0.28)
const GOOD := Color(0.4, 0.9, 0.5)

static var _font: Font
static var _bold: Font
static var _theme: Theme


static func font(bold := false) -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "Sans-Serif"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_font = f
		var fb := SystemFont.new()
		fb.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "Sans-Serif"])
		fb.font_weight = 700
		_bold = fb
	return _bold if bold else _font


static func panel(col := BG, radius := 8, border := 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	if border > 0.0:
		sb.border_width_left = int(border)
		sb.border_width_right = int(border)
		sb.border_width_top = int(border)
		sb.border_width_bottom = int(border)
		sb.border_color = ACCENT
	return sb


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(0.02, 0.05, 0.06))
	t.set_color("font_pressed_color", "Button", Color(0.02, 0.05, 0.06))
	t.set_color("font_focus_color", "Button", TEXT)
	var bn := panel(Color(0.12, 0.16, 0.19, 0.92), 6)
	bn.content_margin_top = 6
	bn.content_margin_bottom = 6
	var bh := panel(ACCENT, 6)
	bh.content_margin_top = 6
	bh.content_margin_bottom = 6
	var bp := panel(ACCENT.darkened(0.2), 6)
	var bd := panel(Color(0.1, 0.12, 0.14, 0.6), 6)
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("focus", "Button", panel(Color(0, 0, 0, 0), 6, 2.0))
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_stylebox("normal", "LineEdit", panel(Color(0.1, 0.12, 0.15, 0.95), 4))
	var sbg := StyleBoxFlat.new()
	sbg.bg_color = Color(0.15, 0.18, 0.2, 0.9)
	sbg.corner_radius_top_left = 3
	sbg.corner_radius_bottom_left = 3
	sbg.corner_radius_top_right = 3
	sbg.corner_radius_bottom_right = 3
	var sfill := sbg.duplicate() as StyleBoxFlat
	sfill.bg_color = ACCENT
	t.set_stylebox("background", "ProgressBar", sbg)
	t.set_stylebox("fill", "ProgressBar", sfill)
	t.set_stylebox("slider", "HSlider", sbg)
	t.set_stylebox("panel", "TabContainer", panel(BG2, 6))
	t.set_stylebox("tab_selected", "TabContainer", panel(ACCENT.darkened(0.3), 4))
	t.set_stylebox("tab_unselected", "TabContainer", panel(Color(0.1, 0.12, 0.14, 0.9), 4))
	t.set_stylebox("tab_hovered", "TabContainer", panel(ACCENT.darkened(0.5), 4))
	t.set_color("font_selected_color", "TabContainer", TEXT)
	t.set_color("font_unselected_color", "TabContainer", DIM)
	_theme = t
	return t


static func label(text: String, size := 18, col := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if bold:
		l.add_theme_font_override("font", font(true))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


static func button(text: String, cb: Callable, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.pressed.connect(func():
		Audio.play_ui("ui_click")
		cb.call())
	return b
