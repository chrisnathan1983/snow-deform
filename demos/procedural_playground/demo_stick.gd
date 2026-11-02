extends Control
## Floating virtual joystick, drawn in screen pixels. Driven by snow_demo.gd.

var active := false
var origin := Vector2.ZERO
var knob := Vector2.ZERO
var radius := 80.0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func begin(pos: Vector2, r: float) -> void:
    active = true
    origin = pos
    knob = Vector2.ZERO
    radius = r
    queue_redraw()


func drag_to(pos: Vector2) -> void:
    knob = (pos - origin).limit_length(radius)
    queue_redraw()


func end() -> void:
    active = false
    knob = Vector2.ZERO
    queue_redraw()


func value() -> Vector2:
    if not active:
        return Vector2.ZERO
    var v := knob / radius
    return Vector2.ZERO if v.length() < 0.12 else v


func _draw() -> void:
    if not active:
        return
    # Dark outline + light fill so it stays visible on bright snow.
    draw_circle(origin, radius, Color(0.08, 0.14, 0.3, 0.22))
    draw_arc(origin, radius, 0.0, TAU, 48, Color(0.08, 0.14, 0.3, 0.85), 4.0)
    draw_circle(origin + knob, radius * 0.42, Color(0.08, 0.14, 0.3, 0.9))
    draw_circle(origin + knob, radius * 0.36, Color(0.9, 0.95, 1.0, 0.95))
