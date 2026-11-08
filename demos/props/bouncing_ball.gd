class_name BouncingBall
extends Node3D

const GRAVITY := 16.0
const Props := preload("res://demos/props/demo_props.gd")

@export var radius := 0.35
@export var bounce_speed := 7.5
@export var half := 13.5
@export var color := Color(0.9, 0.2, 0.2)
@export var velocity := Vector3.ZERO


func _ready() -> void:
	$Visual.scale = Vector3.ONE * radius
	$Visual/Sphere.material_override = Props.mat(color)


func _process(delta: float) -> void:
	velocity.y -= GRAVITY * delta
	position += velocity * delta
	if position.y - radius <= 0.0:
		position.y = radius
		velocity.y = bounce_speed
		_stamp_impact()
	if absf(position.x) > half:
		position.x = clampf(position.x, -half, half)
		velocity.x = -velocity.x
	if absf(position.z) > half:
		position.z = clampf(position.z, -half, half)
		velocity.z = -velocity.z


func _stamp_impact() -> void:
	var position_on_surface := Vector3(global_position.x, 0.0, global_position.z)
	for surface in DeformableSurface.instances:
		surface.stamp_at(position_on_surface, radius * 1.2, 0.85)
