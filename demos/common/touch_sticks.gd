class_name TouchSticks
extends Control
## Shared touch controls for the demos. A touch starting on the left half drags a floating
## joystick that moves the character (`move`); one on the right half drags a floating joystick
## that turns the camera (`look`). A quick touch with no drag emits `tapped`.
## Both are x right / y down, with a small dead zone. Give it a CanvasLayer of its own.

signal tapped(position: Vector2)

const RADIUS := 80.0
const KNOB_RADIUS := 32.0
const DEAD_ZONE := 0.12
const TAP_TIME_MS := 350
const TAP_SLOP := 14.0

var move := Vector2.ZERO
var look := Vector2.ZERO
## Optional Callable(position: Vector2) -> bool; true means the point belongs to other UI.
var is_blocked: Callable
var stick_scale := 1.0

var _slots := {
	"move": {"id": -1, "origin": Vector2.ZERO, "pos": Vector2.ZERO, "moved": false, "t": 0},
	"look": {"id": -1, "origin": Vector2.ZERO, "pos": Vector2.ZERO, "moved": false, "t": 0},
}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_begin(t.index, t.position)
		else:
			_end(t.index, t.position)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_drag(d.index, d.position)


func cancel() -> void:
	for slot in _slots.values():
		slot["id"] = -1
	move = Vector2.ZERO
	look = Vector2.ZERO
	queue_redraw()


func _begin(index: int, pos: Vector2) -> void:
	if is_blocked.is_valid() and is_blocked.call(pos):
		return
	var key := "move" if pos.x < get_viewport_rect().size.x * 0.5 else "look"
	var slot: Dictionary = _slots[key]
	if slot["id"] != -1:
		return
	slot["id"] = index
	slot["origin"] = pos
	slot["pos"] = pos
	slot["moved"] = false
	slot["t"] = Time.get_ticks_msec()
	queue_redraw()


func _drag(index: int, pos: Vector2) -> void:
	for key in _slots:
		var slot: Dictionary = _slots[key]
		if slot["id"] != index:
			continue
		var radius := RADIUS * stick_scale
		var off: Vector2 = (pos - slot["origin"]).limit_length(radius)
		slot["pos"] = slot["origin"] + off
		if pos.distance_to(slot["origin"]) > TAP_SLOP * stick_scale:
			slot["moved"] = true
		var v := off / radius
		v = Vector2.ZERO if v.length() < DEAD_ZONE else v
		if key == "move":
			move = v
		else:
			look = v
		queue_redraw()


func _end(index: int, pos: Vector2) -> void:
	for key in _slots:
		var slot: Dictionary = _slots[key]
		if slot["id"] != index:
			continue
		slot["id"] = -1
		if key == "move":
			move = Vector2.ZERO
		else:
			look = Vector2.ZERO
		if not slot["moved"] and Time.get_ticks_msec() - int(slot["t"]) < TAP_TIME_MS:
			tapped.emit(pos)
		queue_redraw()


func _draw() -> void:
	for slot in _slots.values():
		if slot["id"] == -1:
			continue
		draw_circle(slot["origin"], RADIUS * stick_scale, Color(1, 1, 1, 0.15))
		draw_circle(slot["pos"], KNOB_RADIUS * stick_scale, Color(1, 1, 1, 0.4))
