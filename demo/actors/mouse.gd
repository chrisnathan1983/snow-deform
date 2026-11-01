extends Node3D
## Fast-moving demo mouse. Its SnowDeformer continuously raises and erases snow.

@export var speed := 5.5
@export var bounds := Vector2(10.0, 10.0)
@export var burrow_depth := 0.6
@export var pop_height := 0.0
@export var time_between_pops := Vector2(3.0, 7.0)
@export var pop_duration := Vector2(0.6, 1.2)
@export var burrow_bulge_radius := 0.1
@export var footprint_radius := 0.10
@export var scurry_wobble := 0.35
@export var time_between_pauses := Vector2(4.0, 8.0)
@export var pause_duration := Vector2(0.5, 1.5)

var _target := Vector3.ZERO
var _deformer: SnowDeformer
var _footsteps: SnowFootsteps
var _time_until_pop := 0.0
var _pop_time_left := 0.0
var _time_until_pause := 0.0
var _pause_time_left := 0.0
var _popped_out := false
var _wobble_time := 0.0


func _ready() -> void:
	_deformer = $SnowDeformer
	_footsteps = $SnowFootsteps
	_set_popped_out(false)
	_time_until_pop = randf_range(time_between_pops.x, time_between_pops.y)
	_time_until_pause = randf_range(time_between_pauses.x, time_between_pauses.y)
	_pick_target()


func _process(delta: float) -> void:
	_wobble_time += delta * 18.0
	if _popped_out:
		_pop_time_left -= delta
		if _pop_time_left <= 0.0:
			_popped_out = false
			_set_popped_out(false)
			_time_until_pop = randf_range(time_between_pops.x, time_between_pops.y)
	else:
		_time_until_pop -= delta
		if _time_until_pop <= 0.0:
			_popped_out = true
			_set_popped_out(true)
			_pop_time_left = randf_range(pop_duration.x, pop_duration.y)

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


func _set_popped_out(popped_out: bool) -> void:
	visible = popped_out
	global_position.y = pop_height if popped_out else -burrow_depth
	_deformer.position.y = -global_position.y
	_deformer.active = not popped_out
	_footsteps.active = popped_out
	if popped_out:
		_deformer.stamp_mode = SnowDeformer.StampMode.FOOTPRINT
		_deformer.radius = footprint_radius
		_deformer.puff_distance = 0.0
	else:
		_deformer.stamp_mode = SnowDeformer.StampMode.BULGE_ERASER
		_deformer.radius = burrow_bulge_radius
		_deformer.puff_distance = 0.35


func _pick_target() -> void:
	_target = Vector3(randf_range(-bounds.x, bounds.x), 0.0, randf_range(-bounds.y, bounds.y))
