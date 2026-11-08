class_name DemoCamera
extends Camera3D

enum Mode { FOLLOW, ORBIT }

const YAW_RATE := 2.4
const PITCH_RATE := 1.5

@export var target_path: NodePath
@export var follow_offset := Vector3(0.0, 9.0, 7.5)
@export var follow_speed := 6.0

var mode := Mode.FOLLOW
var follow_target: Node3D
var focus_offset := Vector3.ZERO
var focus_speed := 0.0
var minimum_height := -INF
var auto_update := true
var sticks: TouchSticks
var yaw := 0.0
var pitch := 0.42
var distance := 7.5
var pitch_limits := Vector2(0.3, 1.45)
var distance_limits := Vector2(3.0, 30.0)

var _focus := Vector3.ZERO
var _placed := false


func _ready() -> void:
	if not target_path.is_empty():
		follow_target = get_node_or_null(target_path) as Node3D
		if follow_target == null:
			push_error("DemoCamera: target_path must point to a Node3D.")
			set_process(false)
			return
		pitch = atan2(follow_offset.y, Vector2(follow_offset.x, follow_offset.z).length())
		distance = follow_offset.length()
		update_view()
	set_process(auto_update)


func _process(delta: float) -> void:
	if sticks:
		apply_stick(sticks.look, delta)
	update_view(delta)


func apply_stick(look: Vector2, delta: float) -> void:
	yaw -= look.x * YAW_RATE * delta
	pitch = clampf(pitch + look.y * PITCH_RATE * delta, pitch_limits.x, pitch_limits.y)


func drag(relative: Vector2, yaw_sensitivity := 0.006) -> void:
	yaw -= relative.x * yaw_sensitivity
	pitch = clampf(pitch + relative.y * 0.005, pitch_limits.x, pitch_limits.y)


func zoom(amount: float) -> void:
	distance = clampf(distance + amount, distance_limits.x, distance_limits.y)


func update_view(delta := 0.0) -> void:
	var target := focus_offset
	if is_instance_valid(follow_target):
		target += follow_target.global_position
	if mode == Mode.ORBIT and focus_speed > 0.0 and delta > 0.0:
		_focus = _focus.lerp(target, 1.0 - exp(-focus_speed * delta))
	else:
		_focus = target
	var offset := Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, yaw) * distance
	var destination := _focus + offset
	destination.y = maxf(destination.y, minimum_height)
	if mode == Mode.FOLLOW and _placed and delta > 0.0:
		global_position = global_position.lerp(destination, 1.0 - exp(-follow_speed * delta))
	else:
		global_position = destination
	_placed = true
	look_at(_focus, Vector3.UP)
