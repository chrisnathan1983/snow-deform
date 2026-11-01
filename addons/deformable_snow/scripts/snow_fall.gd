@icon("res://addons/deformable_snow/icons/snow_fall.svg")
class_name SnowFall
extends CPUParticles3D
## Falling snowflakes: one box emitter above a target, simulated in world space.
## Works on its own (no SnowField needed). SnowField also creates two of these.
##
## Centers on `follow_target`, or on the active camera if that is empty
## (or if `follow_camera` is true).

const SnowUtil = preload("snow_util.gd")

@export var area := Vector2(30.0, 30.0)   # emitter box width / depth (meters)
@export var height := 9.0                 # emitter height above ground_y
@export var ground_y := 0.0
@export var fall_speed := Vector2(1.4, 2.2)
@export var flake_size := 0.1
@export var flake_color := Color(1, 1, 1, 0.9)
@export var follow_target: Node3D
@export var follow_camera := false

var max_amount := 450
var _intensity := 0.5
var _enabled := true
var _wind := Vector2.ZERO


func _ready() -> void:
	top_level = true   # world-space placement, independent of the parent's transform
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = Vector3(area.x * 0.5, 0.3, area.y * 0.5)
	direction = Vector3.DOWN
	spread = 8.0
	initial_velocity_min = fall_speed.x
	initial_velocity_max = fall_speed.y
	scale_amount_min = 0.5
	scale_amount_max = 1.3

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.albedo_texture = SnowUtil.soft_dot()
	mat.albedo_color = flake_color
	var quad := QuadMesh.new()
	quad.size = Vector2(flake_size, flake_size)
	quad.material = mat
	mesh = quad

	lifetime = height / ((fall_speed.x + fall_speed.y) * 0.5) * 1.1
	preprocess = lifetime          # start the scene already snowing
	local_coords = false
	fixed_fps = 30
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Box is centered on the node, flakes fall `height` below it; pad for wind drift.
	visibility_aabb = AABB(Vector3(-area.x * 0.5 - 8.0, -height - 2.0, -area.y * 0.5 - 8.0),
			Vector3(area.x + 16.0, height + 4.0, area.y + 16.0))
	amount = max_amount
	_apply_wind()
	_apply_intensity()


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var t: Node3D = null
	if follow_camera:
		t = cam
	if t == null and is_instance_valid(follow_target):
		t = follow_target
	if t == null:
		t = cam
	var c := global_position
	if t:
		c = t.global_position
	global_position = Vector3(c.x, ground_y + height, c.z)


func set_max_amount(n: int) -> void:
	max_amount = maxi(n, 1)
	_apply_intensity()


## 0..1. Scales the particle count; 0 stops emission.
func set_intensity(v: float) -> void:
	_intensity = clampf(v, 0.0, 1.0)
	_apply_intensity()


func set_enabled(v: bool) -> void:
	_enabled = v
	_apply_intensity()


## Horizontal drift acceleration in m/s^2 (x, z).
func set_wind(w: Vector2) -> void:
	_wind = w
	_apply_wind()


func _apply_intensity() -> void:
	amount = maxi(roundi(max_amount * _intensity), 1)
	emitting = _enabled and _intensity > 0.01


func _apply_wind() -> void:
	gravity = Vector3(_wind.x, 0.0, _wind.y)   # horizontal drift only
