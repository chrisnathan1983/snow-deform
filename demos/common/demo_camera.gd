extends Camera3D

@export var target_path: NodePath = ^"../Player"
@export var follow_offset := Vector3(0.0, 9.0, 7.5)
@export var follow_speed := 6.0

var _target: Node3D


func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		push_error("DemoCamera: target_path must point to a Node3D.")
		set_process(false)
		return
	global_position = _target.global_position + follow_offset


func _process(delta: float) -> void:
	var target_position := _target.global_position + follow_offset
	global_position = global_position.lerp(target_position, 1.0 - exp(-follow_speed * delta))
