class_name SnowWeatherSettings
extends Resource
## World-level atmospheric snowfall settings.

enum Quality { LOW, MEDIUM, HIGH, CUSTOM }

@export_group("Weather")
@export_range(1, 10000, 1) var flake_count := 900
@export_range(0, 5000, 1) var near_flake_count := 120
@export var wind := Vector2(0.3, 0.0)
@export_range(0.0, 50.0, 0.5) var fall_height := 9.0
@export var emitter_area := Vector2(30.0, 30.0)
@export_range(0.0, 1.0, 0.05) var snowfall_intensity := 0.3
@export var follow_target_path: NodePath
@export var follow_camera := false
@export var quality: Quality = Quality.MEDIUM


func to_dictionary() -> Dictionary:
	return {
		"flakes": flake_count,
		"near": near_flake_count,
		"wind_x": wind.x,
		"wind_z": wind.y,
		"fall_height": fall_height,
		"emitter_area": emitter_area,
		"snowfall": snowfall_intensity,
		"follow_target_path": follow_target_path,
		"follow_camera": follow_camera,
		"quality": quality,
	}
