class_name SnowFieldQualitySettings
extends Resource
## Surface quality settings for one SnowField.

@export_group("Surface")
@export_range(1.0, 256.0, 1.0) var area_size := 40.0
@export_range(0.01, 1.0, 0.01) var max_depth := 0.25
@export_range(0.0, 0.5, 0.01) var berm_strength := 0.15
@export_range(0.0, 0.5, 0.01) var berm_height := 0.08
@export_range(1, 512, 1) var max_stamps_per_frame := 64
@export_range(0.05, 5.0, 0.05) var refill_interval := 0.25
@export_range(0.0, 255.0, 1.0) var refill_levels_per_sec := 16.0
@export_range(0.0, 1.0, 0.05) var recovery_intensity := 0.3
@export_range(0.0, 3.0, 0.1) var sparkle := 1.0
@export_range(1, 64, 1) var puff := 8
@export var puffs_enabled := true
@export_range(0.0, 10.0, 0.05) var puff_min_interval := 0.2
@export_range(128, 2048, 128) var res := 512
@export_range(1, 512, 1) var subdiv := 127
@export var wrapped_diffuse_lighting := true


func to_dictionary() -> Dictionary:
	return {
		"area_size": area_size,
		"max_depth": max_depth,
		"berm_strength": berm_strength,
		"berm_height": berm_height,
		"max_stamps_per_frame": max_stamps_per_frame,
		"refill_interval": refill_interval,
		"refill_levels_per_sec": refill_levels_per_sec,
		"recovery_intensity": recovery_intensity,
		"snowfall": recovery_intensity,
		"sparkle": sparkle,
		"puff": puff,
		"puffs_enabled": puffs_enabled,
		"puff_min_interval": puff_min_interval,
		"res": res,
		"subdiv": subdiv,
		"wrapped_diffuse_lighting": wrapped_diffuse_lighting,
	}
