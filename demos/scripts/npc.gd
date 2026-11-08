class_name SnowNPC
extends CharacterBody3D
## Wanders between random points. Footprints come from its Feet child.

const BallPush = preload("ball_push.gd")

@export var speed := 2.5
@export var bounds := Vector2(11, 11) :
	set(value):
		bounds = value
		if is_node_ready():
			_pick()
@export var body_color := Color(0.2, 0.5, 0.9)

var _target := Vector3.ZERO
var _wait := 0.0
var _stuck := 0.0   # seconds spent NOT making progress (not total travel time)


func _ready() -> void:
	var body := get_node("Body") as MeshInstance3D
	var material := body.get_surface_override_material(0).duplicate() as StandardMaterial3D
	material.albedo_color = body_color
	body.set_surface_override_material(0, material)
	_pick()


func _pick() -> void:
	_target = Vector3(randf_range(-bounds.x, bounds.x), 0.0, randf_range(-bounds.y, bounds.y))
	_stuck = 0.0


func _physics_process(delta: float) -> void:
	if _wait > 0.0:
		_wait -= delta
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var to := _target - global_position
	to.y = 0.0
	if to.length() < 0.4:   # arrived
		_wait = randf_range(0.5, 2.5)
		_pick()
		return

	var dir := to.normalized()
	var before := global_position
	velocity = dir * speed
	var motion_velocity := velocity
	move_and_slide()
	BallPush.apply_contact_impulses(self, motion_velocity)
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 8.0 * delta)

	# Blocked (e.g. by a tree) = moved far less than we should have.
	if global_position.distance_to(before) < speed * delta * 0.2:
		_stuck += delta
		if _stuck > 1.0:
			_pick()
	else:
		_stuck = 0.0
