extends Node
## Supports circular roaming and random point-to-point wandering.

@export var circle_center := Vector3.ZERO
@export var circle_radius := 3.0
@export var phase := 0.0
@export var random_waypoints := false
@export var bounds := Vector2(11.0, 11.0)
@export var wait_range := Vector2(0.5, 2.5)

var _target := Vector3.ZERO
var _wait := 0.0
@onready var character: DemoCharacter = get_parent() as DemoCharacter


func _ready() -> void:
	if random_waypoints:
		_pick_target()


func _process(delta: float) -> void:
	if random_waypoints:
		_process_random(delta)
		return
	phase += character.move_speed / maxf(circle_radius, 0.001) * delta
	var target := circle_center + Vector3(cos(phase) * circle_radius, 0.0,
			sin(phase) * circle_radius)
	var direction := target - character.position
	if delta > 0.0 and direction.length() > 0.0001:
		character.turn_towards(direction, delta)
	character.position = target
	character.collide()


func _process_random(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		return
	var direction := _target - character.position
	direction.y = 0.0
	if direction.length() < 0.4:
		_wait = randf_range(wait_range.x, wait_range.y)
		_pick_target()
		return
	direction = direction.normalized()
	character.turn_towards(direction, delta)
	character.move_by(direction, character.move_speed, delta)
	character.collide()


func _pick_target() -> void:
	_target = Vector3(randf_range(-bounds.x, bounds.x), 0.0,
			randf_range(-bounds.y, bounds.y))


func set_bounds(value: Vector2) -> void:
	bounds = value
	if random_waypoints:
		_pick_target()
