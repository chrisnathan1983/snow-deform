@icon("res://addons/snowfall/icons/snow_fall.svg")
class_name SnowWeather
extends Node3D
## Shared atmospheric snowfall. Keep one instance for the scene.

@export_range(0.0, 1.0) var snowfall := 0.3 : set = set_snowfall
@export var wind := Vector2(0.3, 0.0) : set = set_wind
@export_range(0.0, 50.0, 0.5) var fall_height := 9.0 : set = set_fall_height
@export_range(1, 10000, 1) var flakes := 900 : set = set_flakes
@export_range(0, 5000, 1) var near_flakes := 120 : set = set_near_flakes
@export var follow_target: Node3D : set = set_follow_target

var _fall: SnowFall
var _fall_near: SnowFall


func _ready() -> void:
	set_flakes(flakes)
	set_near_flakes(near_flakes)
	_fall = SnowFall.new()
	_fall.height = fall_height
	_fall.set_max_amount(flakes)
	_fall.set_intensity(snowfall)
	_fall.set_wind(wind)
	_fall.follow_target = follow_target
	add_child(_fall)

	_ensure_near_emitter()


func _ensure_near_emitter() -> void:
	if near_flakes <= 0:
		if is_instance_valid(_fall_near):
			_fall_near.queue_free()
		_fall_near = null
		return
	if is_instance_valid(_fall_near):
		return

	_fall_near = SnowFall.new()
	_fall_near.area = Vector2(14.0, 14.0)
	_fall_near.height = 7.0
	_fall_near.fall_speed = Vector2(0.9, 1.5)
	_fall_near.flake_size = 0.35
	_fall_near.flake_color = Color(1, 1, 1, 0.4)
	_fall_near.follow_camera = true
	_fall_near.set_max_amount(near_flakes)
	_fall_near.set_intensity(snowfall)
	_fall_near.set_wind(wind)
	add_child(_fall_near)


func _process(_delta: float) -> void:
	if _fall == null:
		return
	if not is_equal_approx(_fall.ground_y, global_position.y):
		_fall.ground_y = global_position.y
	if is_instance_valid(_fall_near) and not is_equal_approx(_fall_near.ground_y, global_position.y):
		_fall_near.ground_y = global_position.y


func apply_quality_settings(settings: Dictionary, intensity: float) -> void:
	var required := ["flakes", "near", "wind_x", "wind_z", "fall_height"]
	for key in required:
		if not settings.has(key):
			push_error("SnowWeather: settings are missing '%s'." % key)
			return
		var type := typeof(settings[key])
		if type != TYPE_INT and type != TYPE_FLOAT:
			push_error("SnowWeather: setting '%s' must be numeric." % key)
			return

	flakes = maxi(roundi(float(settings["flakes"])), 1)
	near_flakes = maxi(roundi(float(settings["near"])), 0)
	wind = Vector2(float(settings["wind_x"]), float(settings["wind_z"]))
	fall_height = maxf(float(settings["fall_height"]), 0.0)
	snowfall = intensity
	if _fall == null:
		return

	_fall.follow_target = follow_target


func set_follow_target(target: Node3D) -> void:
	follow_target = target
	if is_instance_valid(_fall):
		_fall.follow_target = target


func set_snowfall(value: float) -> void:
	var updated := clampf(value, 0.0, 1.0)
	if is_equal_approx(snowfall, updated):
		return
	snowfall = updated
	if is_instance_valid(_fall):
		_fall.set_intensity(snowfall)
	if is_instance_valid(_fall_near):
		_fall_near.set_intensity(snowfall)


func set_wind(value: Vector2) -> void:
	if wind.is_equal_approx(value):
		return
	wind = value
	if is_instance_valid(_fall):
		_fall.set_wind(wind)
	if is_instance_valid(_fall_near):
		_fall_near.set_wind(wind)


func set_fall_height(value: float) -> void:
	var updated := maxf(value, 0.0)
	if is_equal_approx(fall_height, updated):
		return
	fall_height = updated
	if is_instance_valid(_fall):
		_fall.height = fall_height


func set_flakes(value: int) -> void:
	var updated := mini(maxi(value, 1), 250) if SnowFall.is_low_power_mobile() else maxi(value, 1)
	if flakes == updated:
		return
	flakes = updated
	if is_instance_valid(_fall):
		_fall.set_max_amount(flakes)


func set_near_flakes(value: int) -> void:
	var updated := mini(maxi(value, 0), 50) if SnowFall.is_low_power_mobile() else maxi(value, 0)
	if near_flakes == updated:
		return
	near_flakes = updated
	if not is_inside_tree():
		return
	if near_flakes <= 0:
		_ensure_near_emitter()
	elif is_instance_valid(_fall_near):
		_fall_near.set_max_amount(near_flakes)
	else:
		_ensure_near_emitter()
