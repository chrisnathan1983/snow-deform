class_name DemoCharacter
extends Node3D
## Shared movement and animation for primitive demo characters.
## Movement policy lives in the Behavior child of each character scene.

const GRAVITY := 16.0
const JUMP_SPEED := 6.0

@export var body_radius := 0.3
@export var move_speed := 3.2
@export var bob_amplitude := 0.07
@export var roll_amplitude := 0.05

var move_input := Vector3.ZERO
var running := false
var run_mult := 1.9
var half_extent := 15.2
var obstacles: Array[Vector3] = []
var on_ground := true
var _vy := 0.0
var _speed := 0.0
var _bob := 0.0
var _last_pos := Vector3.ZERO

@onready var _visual: Node3D = $Visual


func _ready() -> void:
	_last_pos = position


func jump() -> void:
	if on_ground:
		_vy = JUMP_SPEED
		on_ground = false


func face_towards(target: Vector3) -> void:
	var d := target - global_position
	d.y = 0.0
	if d.length() > 0.01:
		rotation.y = atan2(-d.x, -d.z)


func set_wander_route(center: Vector3, radius: float) -> void:
	var behavior := get_node("Behavior")
	behavior.set("circle_center", center)
	behavior.set("circle_radius", radius)


func set_follow_target(target: Node3D, distance: float) -> void:
	var behavior := get_node("Behavior")
	behavior.set("follow_target", target)
	behavior.set("follow_distance", distance)


func turn_towards(direction: Vector3, delta: float) -> void:
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-12.0 * delta))


func move_by(direction: Vector3, speed: float, delta: float) -> void:
	position += direction * speed * delta


func collide() -> void:
	position.x = clampf(position.x, -half_extent, half_extent)
	position.z = clampf(position.z, -half_extent, half_extent)
	for obstacle in obstacles:
		var dx := position.x - obstacle.x
		var dz := position.z - obstacle.z
		var min_distance := obstacle.y + body_radius
		var distance_squared := dx * dx + dz * dz
		if distance_squared < min_distance * min_distance and distance_squared > 0.000001:
			var distance := sqrt(distance_squared)
			position.x = obstacle.x + dx / distance * min_distance
			position.z = obstacle.z + dz / distance * min_distance


func _process(delta: float) -> void:
	_animate(delta)


func _animate(delta: float) -> void:
	var moved := Vector2(position.x - _last_pos.x, position.z - _last_pos.z).length()
	_last_pos = position
	var inst := moved / maxf(delta, 0.0001)
	_speed = lerpf(_speed, inst, 1.0 - exp(-10.0 * delta))
	var k := clampf(_speed / 3.0, 0.0, 1.0)
	_bob += _speed * delta * 3.2
	_visual.position.y = absf(sin(_bob)) * bob_amplitude * k
	_visual.rotation.z = sin(_bob) * roll_amplitude * k
