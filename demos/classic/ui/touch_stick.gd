class_name TouchStick
extends Control
## Floating virtual joystick: touch anywhere on the left half of the screen.
## `vector` is x right / y down, which maps directly to world X / Z.

const RADIUS := 80.0
const TOP_DEAD_ZONE := 90.0   # keep the buttons at the top clickable

var vector := Vector2.ZERO
var _id := -1
var _origin := Vector2.ZERO
var _pos := Vector2.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			var left_half: bool = event.position.x < get_viewport_rect().size.x * 0.5
			if _id == -1 and left_half and event.position.y > TOP_DEAD_ZONE:
				_id = event.index
				_origin = event.position
				_pos = event.position
		elif event.index == _id:
			_id = -1
			vector = Vector2.ZERO
		queue_redraw()
	elif event is InputEventScreenDrag and event.index == _id:
		var off: Vector2 = (event.position - _origin).limit_length(RADIUS)
		_pos = _origin + off
		vector = off / RADIUS
		queue_redraw()


func cancel() -> void:
	_id = -1
	vector = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if _id == -1:
		return
	draw_circle(_origin, RADIUS, Color(1, 1, 1, 0.15))
	draw_circle(_pos, 32.0, Color(1, 1, 1, 0.4))
