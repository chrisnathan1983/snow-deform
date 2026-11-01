@icon("res://addons/deformable_snow/icons/snow_footsteps.svg")
class_name SnowFootsteps
extends Node3D
## Add as a child of a character (origin at ground level, facing -Z).
## Needs a SnowField in the scene.
## Two alternating feet with shallow drags restricted to touchdown and liftoff transitions.

@export var foot_radius := 0.17
@export var foot_aspect := 2.0
@export var spread := 0.15       # left/right offset from center
@export var stride_min := 0.14   # half-stride at a slow walk (meters)
@export var stride_max := 0.38   # half-stride at full speed
@export var speed_for_max := 5.0 # m/s at which stride_max is reached
@export var active := true
@export var puff_on_touchdown := true

# Drag settings
@export var enable_drags := false
@export var drag_radius_scale := 0.65  # Narrower radius for lighter drag marks
@export var drag_window := 0.95        # How close to the transition boundary (0.0 to 1.0) the drag occurs

var _feet: Array[SnowDeformer] = []
var _drags: Array[SnowDeformer] = []
var _phase := 0.0
var _stride := 0.2
var _prev := Vector3.ZERO


func _ready() -> void:
	for i in 2:
		var d := SnowDeformer.new()
		d.radius = foot_radius
		d.aspect = foot_aspect
		d.puff_on_touchdown = puff_on_touchdown
		add_child(d)
		_feet.append(d)
	
	if enable_drags:
		for i in 2:
			var drag := SnowDeformer.new()
			drag.radius = foot_radius * drag_radius_scale
			drag.aspect = foot_aspect
			drag.puff_on_touchdown = false
			add_child(drag)
			_drags.append(drag)

	_prev = global_position


func _process(delta: float) -> void:
	var gp := global_position
	if not active:
		_prev = gp
		for foot in _feet:
			foot.active = false
		for drag in _drags:
			drag.active = false
		return

	var movement := Vector3(gp.x - _prev.x, 0.0, gp.z - _prev.z)
	var moved := Vector2(movement.x, movement.z).length()
	var forward_movement := movement.dot(-global_basis.z)
	_prev = gp

	if moved > 0.0005:
		var speed := moved / maxf(delta, 0.0001)
		var target := lerpf(stride_min, stride_max, clampf(speed / speed_for_max, 0.0, 1.0))
		_stride = lerpf(_stride, target, 1.0 - exp(-8.0 * delta))
		_phase += forward_movement * PI / (_stride * 2.0)

	for i in 2:
		var ph := _phase + i * PI
		var foot_pos := Vector3((i * 2 - 1) * spread, 0.0, -sin(ph) * _stride)
		
		var c := cos(ph)
		var is_planted := c <= 0.0

		# Primary planted foot
		_feet[i].position = foot_pos
		_feet[i].active = is_planted

		# Drag only activates in a narrow window right around the transition point (c near 0.0)
		if enable_drags:
			_drags[i].position = foot_pos
			var transition_intensity := 1.0 - (absf(c) / drag_window)
			_drags[i].active = (transition_intensity > 0.0) and (moved > 0.01)