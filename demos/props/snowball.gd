class_name DemoSnowball
extends Node3D

const GRAVITY := 16.0
const Props := preload("res://demos/props/demo_props.gd")

@export var radius := 0.28
@export var velocity := Vector3.ZERO

var _landed := false
var _elapsed := 0.0


func _ready() -> void:
	$Visual.scale = Vector3.ONE * radius
	$Visual/Sphere.material_override = Props.mat(Color(0.97, 0.98, 1.0))


func _process(delta: float) -> void:
	if not _landed:
		velocity.y -= GRAVITY * delta
		position += velocity * delta
		if velocity.y < 0.0 and position.y - radius <= 0.0:
			position.y = radius
			_landed = true
			_stamp_impact()
	else:
		_elapsed += delta
		if _elapsed > 0.25:
			scale = Vector3.ONE * maxf(0.0, 1.0 - (_elapsed - 0.25) / 0.2)
		if _elapsed > 0.6:
			queue_free()


func _stamp_impact() -> void:
	var position_on_surface := Vector3(global_position.x, 0.0, global_position.z)
	for surface in DeformableSurface.instances:
		surface.stamp_at(position_on_surface, 0.62, 1.0, null,
				DeformableSurface.StampMode.CARVE, 0.0, 1.0, true)
