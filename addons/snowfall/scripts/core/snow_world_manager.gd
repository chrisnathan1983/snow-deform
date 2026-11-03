@icon("res://addons/deformable_snow/icons/snow_fall.svg")
class_name SnowWorldManager
extends Node3D
## Shared atmospheric snowfall for a world. SnowFields keep their own surfaces.

const SnowQualitySettingsScript = preload("../settings/snow_quality_settings.gd")
const SnowWeatherSettingsScript = preload("../settings/snow_weather_settings.gd")

@export_range(0.0, 1.0, 0.01) var snowfall_intensity := 0.3 : set = set_snowfall_intensity
@export var wind := Vector2(0.3, 0.0) : set = set_wind
@export var follow_target: Node3D : set = set_follow_target
@export var follow_camera := false : set = set_follow_camera
@export_range(0.0, 50.0, 0.5) var fall_height := 9.0 : set = set_fall_height
@export var emitter_area := Vector2(30.0, 30.0) : set = set_emitter_area
@export_range(1, 10000, 1) var flake_count := 900 : set = set_flake_count
@export_range(0, 5000, 1) var near_flake_count := 120 : set = set_near_flake_count
@export var weather_enabled := true : set = set_weather_enabled
## Optional world-only settings resource. When empty, the individual properties are used.
@export var weather_settings: SnowWeatherSettingsScript : set = set_weather_settings
var weather_quality: int = SnowWeatherSettingsScript.Quality.MEDIUM

var _main_snow_fall: SnowFall
var _near_camera_snow_fall: SnowFall
var _weather_root: Node3D
var _effects_root: Node3D
var _last_ground_y := 0.0
var _registered_fields: Array[Node3D] = []


func _ready() -> void:
	if weather_settings != null:
		_apply_weather_settings(weather_settings)
	_weather_root = Node3D.new()
	_weather_root.name = "Weather"
	add_child(_weather_root)
	_effects_root = Node3D.new()
	_effects_root.name = "Effects"
	add_child(_effects_root)
	_main_snow_fall = _create_main_emitter()
	_near_camera_snow_fall = _create_near_emitter()
	_last_ground_y = global_position.y


func _process(_delta: float) -> void:
	var ground_y := global_position.y
	if is_equal_approx(_last_ground_y, ground_y):
		return
	_last_ground_y = ground_y
	if is_instance_valid(_main_snow_fall):
		_main_snow_fall.ground_y = ground_y
	if is_instance_valid(_near_camera_snow_fall):
		_near_camera_snow_fall.ground_y = ground_y


func _exit_tree() -> void:
	for field in _registered_fields.duplicate():
		if is_instance_valid(field) and field.has_method("set_world_manager"):
			field.call("set_world_manager", null)
	_registered_fields.clear()


func register_field(field: Node3D) -> void:
	if not is_instance_valid(field):
		return
	if not _registered_fields.has(field):
		_registered_fields.append(field)


func unregister_field(field: Node3D) -> void:
	if is_instance_valid(field):
		_registered_fields.erase(field)


func _create_main_emitter() -> SnowFall:
	var emitter := SnowFall.new()
	emitter.name = "MainSnowFall"
	emitter.area = emitter_area
	emitter.height = fall_height
	emitter.ground_y = global_position.y
	emitter.follow_target = follow_target
	emitter.follow_camera = follow_camera
	emitter.set_max_amount(flake_count)
	emitter.set_intensity(snowfall_intensity)
	emitter.set_wind(wind)
	emitter.set_enabled(weather_enabled)
	_weather_root.add_child(emitter)
	return emitter


func _create_near_emitter() -> SnowFall:
	var emitter := SnowFall.new()
	emitter.name = "NearCameraSnowFall"
	emitter.area = Vector2(14.0, 14.0)
	emitter.height = 7.0
	emitter.ground_y = global_position.y
	emitter.fall_speed = Vector2(0.9, 1.5)
	emitter.flake_size = 0.35
	emitter.flake_color = Color(1.0, 1.0, 1.0, 0.4)
	emitter.follow_camera = true
	emitter.set_max_amount(maxi(near_flake_count, 1))
	emitter.set_intensity(snowfall_intensity if near_flake_count > 0 else 0.0)
	emitter.set_wind(wind)
	emitter.set_enabled(weather_enabled)
	_weather_root.add_child(emitter)
	return emitter


func set_snowfall_intensity(value: float) -> void:
	var updated := clampf(value, 0.0, 1.0)
	if is_equal_approx(snowfall_intensity, updated):
		return
	snowfall_intensity = updated
	if is_instance_valid(_main_snow_fall):
		_main_snow_fall.set_intensity(updated)
	if is_instance_valid(_near_camera_snow_fall):
		_near_camera_snow_fall.set_intensity(updated if near_flake_count > 0 else 0.0)


func set_wind(value: Vector2) -> void:
	if wind.is_equal_approx(value):
		return
	wind = value
	if is_instance_valid(_main_snow_fall):
		_main_snow_fall.set_wind(value)
	if is_instance_valid(_near_camera_snow_fall):
		_near_camera_snow_fall.set_wind(value)


func set_weather_enabled(enabled: bool) -> void:
	if weather_enabled == enabled:
		return
	weather_enabled = enabled
	if is_instance_valid(_main_snow_fall):
		_main_snow_fall.set_enabled(enabled)
	if is_instance_valid(_near_camera_snow_fall):
		_near_camera_snow_fall.set_enabled(enabled)


func set_follow_target(target: Node3D) -> void:
	if follow_target == target:
		return
	follow_target = target
	if is_instance_valid(_main_snow_fall):
		_main_snow_fall.follow_target = target


func set_follow_camera(enabled: bool) -> void:
	if follow_camera == enabled:
		return
	follow_camera = enabled
	if is_instance_valid(_main_snow_fall):
		_main_snow_fall.follow_camera = enabled


func set_fall_height(value: float) -> void:
	var updated := clampf(value, 0.0, 50.0)
	if is_equal_approx(fall_height, updated):
		return
	fall_height = updated
	if is_instance_valid(_main_snow_fall):
		_main_snow_fall.height = updated


func set_emitter_area(value: Vector2) -> void:
	var updated := value.max(Vector2.ONE)
	if emitter_area.is_equal_approx(updated):
		return
	emitter_area = updated
	if is_instance_valid(_main_snow_fall):
		_main_snow_fall.area = updated


func set_flake_count(value: int) -> void:
	var updated := maxi(value, 1)
	if flake_count == updated:
		return
	flake_count = updated
	if is_instance_valid(_main_snow_fall):
		_main_snow_fall.set_max_amount(updated)


func set_near_flake_count(value: int) -> void:
	var updated := maxi(value, 0)
	if near_flake_count == updated:
		return
	near_flake_count = updated
	if not is_instance_valid(_near_camera_snow_fall):
		return
	_near_camera_snow_fall.set_max_amount(maxi(updated, 1))
	_near_camera_snow_fall.set_intensity(snowfall_intensity if updated > 0 else 0.0)


func set_weather_preset(preset: Resource) -> void:
	if not is_instance_valid(preset):
		push_error("SnowWorldManager: weather preset must be a SnowWeatherSettings or legacy SnowQualitySettings resource.")
		return
	if preset is SnowWeatherSettingsScript:
		set_weather_settings(preset as SnowWeatherSettingsScript)
		return
	if not (preset is SnowQualitySettingsScript):
		push_error("SnowWorldManager: weather preset must be a SnowWeatherSettings or legacy SnowQualitySettings resource.")
		return
	var legacy_settings := preset as SnowQualitySettingsScript
	set_snowfall_intensity(legacy_settings.snowfall)
	set_wind(Vector2(legacy_settings.wind_x, legacy_settings.wind_z))
	set_fall_height(legacy_settings.fall_height)
	set_flake_count(legacy_settings.flakes)
	set_near_flake_count(legacy_settings.near)


func set_weather_settings(settings: SnowWeatherSettingsScript) -> void:
	if weather_settings == settings:
		return
	if settings == null:
		weather_settings = null
		return
	weather_settings = settings
	if is_inside_tree():
		_apply_weather_settings(settings)


func _apply_weather_settings(settings: SnowWeatherSettingsScript) -> void:
	var target: Node3D
	if not settings.follow_target_path.is_empty():
		target = get_node_or_null(settings.follow_target_path) as Node3D
		if target == null:
			push_error(
				"SnowWorldManager: weather target path '%s' does not resolve to a Node3D."
				% settings.follow_target_path
			)
			return
	set_snowfall_intensity(settings.snowfall_intensity)
	set_wind(settings.wind)
	set_fall_height(settings.fall_height)
	set_emitter_area(settings.emitter_area)
	set_flake_count(settings.flake_count)
	set_near_flake_count(settings.near_flake_count)
	set_follow_target(target)
	set_follow_camera(settings.follow_camera)
	weather_quality = settings.quality
