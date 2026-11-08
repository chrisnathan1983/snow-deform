class_name SnowWeatherSettings
extends Resource
## World-level atmospheric snowfall settings.

enum Quality { LOW, MEDIUM, HIGH }

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
