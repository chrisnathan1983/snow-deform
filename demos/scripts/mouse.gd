extends Node3D
## Fast-moving demo mouse that scurries across the snow and leaves footprints.

@export var speed := 5.5
@export var bounds := Vector2(10.0, 10.0)
@export var footprint_radius := 0.025
@export var scurry_wobble := 0.35
@export var time_between_pauses := Vector2(4.0, 8.0)
@export var pause_duration := Vector2(0.5, 1.5)

var _target := Vector3.ZERO
var _footsteps: DeformerFootsteps
var _time_until_pause := 0.0
var _pause_time_left := 0.0
var _wobble_time := 0.0


func _ready() -> void:
	global_position.y = 0.0
	_footsteps = $DeformerFootsteps
	_footsteps.active = true
	_time_until_pause = randf_range(time_between_pauses.x, time_between_pauses.y)
	_pick_target()


func _process(delta: float) -> void:
	_wobble_time += delta * 18.0
	if _pause_time_left > 0.0:
		_pause_time_left -= delta
		return
	_time_until_pause -= delta
	if _time_until_pause <= 0.0:
		_pause_time_left = randf_range(pause_duration.x, pause_duration.y)
		_time_until_pause = randf_range(time_between_pauses.x, time_between_pauses.y)
		return

	var direction := _target - global_position
	direction.y = 0.0
	if direction.length() < 0.35:
		_pick_target()
		return

	direction = direction.normalized()
	var perp := Vector3(-direction.z, 0.0, direction.x)
	var move_dir := (direction + perp * sin(_wobble_time) * scurry_wobble).normalized()

	global_position += move_dir * speed * delta
	rotation.y = lerp_angle(rotation.y, atan2(-move_dir.x, -move_dir.z), 12.0 * delta)


func _pick_target() -> void:
	_target = Vector3(randf_range(-bounds.x, bounds.x), 0.0, randf_range(-bounds.y, bounds.y))
