@icon("res://addons/snowfall/icons/snow_fall.svg")
class_name SnowFall
extends CPUParticles3D
## Falling snowflakes: one box emitter above a target, simulated in world space.
## Works on its own; a manager can group emitters for a world.
##
## Centers on `follow_target`, or on the active camera if that is empty
## (or if `follow_camera` is true).

@export var area := Vector2(30.0, 30.0) : set = set_area  # emitter box width / depth (meters)
@export var height := 9.0 : set = set_height             # emitter height above ground_y
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
static var _dot_cache: GradientTexture2D


func _ready() -> void:
	top_level = true   # world-space placement, independent of the parent's transform
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_update_emitter_bounds()
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
	mat.albedo_texture = _soft_dot()
	mat.albedo_color = flake_color
	var quad := QuadMesh.new()
	quad.size = Vector2(flake_size, flake_size)
	quad.material = mat
	mesh = quad

	_update_lifetime()
	preprocess = lifetime          # start the scene already snowing
	local_coords = false
	fixed_fps = 20 if is_low_power_mobile() else 30
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_wind()
	_apply_intensity()
	preprocess = 0.0


func _process(_delta: float) -> void:
	var t: Node3D = null
	if not follow_camera and is_instance_valid(follow_target):
		t = follow_target
	else:
		t = get_viewport().get_camera_3d()
	var c := global_position
	if t:
		c = t.global_position
	var target_position := Vector3(c.x, ground_y + height, c.z)
	if not global_position.is_equal_approx(target_position):
		global_position = target_position


func set_max_amount(n: int) -> void:
	var updated := maxi(n, 1)
	if max_amount == updated:
		return
	max_amount = updated
	_apply_intensity()


func set_area(value: Vector2) -> void:
	if area.is_equal_approx(value):
		return
	area = value
	if is_inside_tree():
		_update_emitter_bounds()


func set_height(value: float) -> void:
	if is_equal_approx(height, value):
		return
	height = value
	if is_inside_tree():
		_update_lifetime()
		_update_emitter_bounds()


## 0..1. Scales the particle count; 0 stops emission.
func set_intensity(v: float) -> void:
	var updated := clampf(v, 0.0, 1.0)
	if is_equal_approx(_intensity, updated):
		return
	_intensity = updated
	_apply_intensity()


func set_enabled(v: bool) -> void:
	if _enabled == v:
		return
	_enabled = v
	_apply_intensity()


## Horizontal drift acceleration in m/s^2 (x, z).
func set_wind(w: Vector2) -> void:
	if _wind.is_equal_approx(w):
		return
	_wind = w
	_apply_wind()


func _apply_intensity() -> void:
	var target_amount := maxi(roundi(max_amount * _intensity), 1)
	if amount != target_amount:
		amount = target_amount
	var should_emit := _enabled and _intensity > 0.0
	if emitting != should_emit:
		emitting = should_emit


func _apply_wind() -> void:
	var target_gravity := Vector3(_wind.x, 0.0, _wind.y)
	if not gravity.is_equal_approx(target_gravity):
		gravity = target_gravity   # horizontal drift only


func _update_lifetime() -> void:
	lifetime = height / ((fall_speed.x + fall_speed.y) * 0.5) * 1.1


func _update_emitter_bounds() -> void:
	emission_box_extents = Vector3(area.x * 0.5, 0.3, area.y * 0.5)
	# Box is centered on the node, flakes fall `height` below it; pad for wind drift.
	visibility_aabb = AABB(Vector3(-area.x * 0.5 - 8.0, -height - 2.0, -area.y * 0.5 - 8.0),
			Vector3(area.x + 16.0, height + 4.0, area.y + 16.0))


static func _soft_dot(size := 32) -> GradientTexture2D:
	if size == 32 and _dot_cache != null:
		return _dot_cache

	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.5, Color(1, 1, 1, 0.6))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	if size == 32:
		_dot_cache = t
	return t


static func is_low_power_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
