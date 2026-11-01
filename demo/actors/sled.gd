extends AnimatableBody3D

@export var orbit_radius := 7.0
@export var orbit_speed := 0.6
@export var height := 0.1
@export_range(0.0, 2.0, 0.05, "or_greater") var wobble_amplitude := 0.3
@export_range(0.0, 8.0, 0.1, "or_greater") var wobble_cycles := 3.0

var _time := 0.0


func _physics_process(delta: float) -> void:
	_time += delta * orbit_speed
	var angle := _time
	var wobble := sin(angle * wobble_cycles) * wobble_amplitude
	var radius := orbit_radius + wobble
	var next_position := Vector3(cos(angle) * radius, height, sin(angle) * radius)

	var radial_speed := cos(angle * wobble_cycles) * wobble_amplitude * wobble_cycles
	var tangent := Vector2(
		-sin(angle) * radius + cos(angle) * radial_speed,
		cos(angle) * radius + sin(angle) * radial_speed
	)
	var heading := atan2(-tangent.x, -tangent.y)
	global_transform = Transform3D(Basis(Vector3.UP, heading), next_position)
