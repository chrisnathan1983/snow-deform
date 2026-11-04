class_name DemoTheme
extends RefCounted
## One look for every demo: HUD, settings panel and the launcher button.

const FONT_SIZE := 18
const PANEL_COLOR := Color(0.06, 0.10, 0.18, 0.84)
const ACCENT_COLOR := Color(0.7, 0.82, 1.0)
const OUTLINE_COLOR := Color(0, 0, 0, 0.85)

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


## Light text with a dark outline so labels stay legible over snow and dark ground alike.
static func style_floating_label(label: Label) -> void:
	label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", 4)


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	var panel := StyleBoxFlat.new()
	panel.bg_color = PANEL_COLOR
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(10)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_font_size("font_size", "TabContainer", 16)
	return t
