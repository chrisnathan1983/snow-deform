class_name DemoCamera
extends Camera3D

@export var target_path: NodePath = ^"../Player"
@export var follow_offset := Vector3(0.0, 9.0, 7.5)
@export var follow_speed := 6.0

const YAW_RATE := 2.4
const PITCH_RATE := 1.5

## Optional touch controls; their right-hand joystick orbits the camera.
var sticks: TouchSticks
var yaw := 0.0
var _pitch := 0.0
var _distance := 1.0
var _target: Node3D


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		push_error("DemoCamera: target_path must point to a Node3D.")
		set_process(false)
		return
	_pitch = atan2(follow_offset.y, Vector2(follow_offset.x, follow_offset.z).length())
	_distance = follow_offset.length()
	global_position = _target.global_position + _orbit_offset()


func _process(delta: float) -> void:
	if sticks:
		yaw -= sticks.look.x * YAW_RATE * delta
		_pitch = clampf(_pitch + sticks.look.y * PITCH_RATE * delta, 0.3, 1.45)
	var target_position := _target.global_position + _orbit_offset()
	global_position = global_position.lerp(target_position, 1.0 - exp(-follow_speed * delta))
	if sticks and (sticks.look != Vector2.ZERO or yaw != 0.0):
		look_at(_target.global_position, Vector3.UP)


func _orbit_offset() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3(0.0, sin(_pitch), cos(_pitch)) * _distance
