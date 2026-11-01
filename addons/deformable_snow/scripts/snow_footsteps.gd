@icon("res://addons/deformable_snow/icons/snow_footsteps.svg")
class_name SnowFootsteps
extends Node3D
## Add as a child of a character (origin at ground level, facing -Z).
## Needs a SnowField in the scene.
## Two alternating feet stamp footprints as the character moves.

@export var foot_radius := 0.17
@export var foot_aspect := 2.0
@export var spread := 0.15       # left/right offset from center
@export var stride_min := 0.14   # half-stride at a slow walk (meters)
@export var stride_max := 0.38   # half-stride at full speed
@export var speed_for_max := 5.0 # m/s at which stride_max is reached
@export var active := true
@export var puff_on_touchdown := true

var _feet: Array[SnowDeformer] = []
var _phase := 0.0
var _stride := 0.2
var _prev := Vector3.ZERO
var _was_active := true
var _has_updated_feet := false


func _ready() -> void:
	for i in 2:
		var d := SnowDeformer.new()
		d.radius = foot_radius
		d.aspect = foot_aspect
		d.puff_on_touchdown = puff_on_touchdown
		add_child(d)
		_feet.append(d)

	_prev = global_position


func _process(delta: float) -> void:
	var gp := global_position
	if not active:
		_prev = gp
		if _was_active:
			for foot in _feet:
				foot.active = false
		_was_active = false
		return

	var reactivated := not _was_active
	if reactivated:
		_prev = gp
	_was_active = true
	var movement := Vector3(gp.x - _prev.x, 0.0, gp.z - _prev.z)
	var moved := Vector2(movement.x, movement.z).length()
	_prev = gp
	if moved <= 0.0005 and not reactivated and _has_updated_feet:
		return

	if moved > 0.0005:
		var speed := moved / maxf(delta, 0.0001)
		var target := lerpf(stride_min, stride_max, clampf(speed / speed_for_max, 0.0, 1.0))
		_stride = lerpf(_stride, target, 1.0 - exp(-8.0 * delta))
		_phase += moved * PI / (_stride * 2.0)

	for i in 2:
		var ph := _phase + i * PI
		var foot_pos := Vector3((i * 2 - 1) * spread, 0.0, -sin(ph) * _stride)
		
		var c := cos(ph)
		var is_planted := c <= 0.0

		# Primary planted foot
		_feet[i].position = foot_pos
		_feet[i].active = is_planted
	_has_updated_feet = true