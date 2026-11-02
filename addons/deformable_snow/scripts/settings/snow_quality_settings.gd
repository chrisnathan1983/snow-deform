@tool
class_name SnowQualitySettings
extends Resource
## Legacy combined surface and weather profile. Prefer SnowFieldQualitySettings
## and SnowWeatherSettings for new projects.

@export_group("Surface")
## Width and length of the square snow field, in meters.
@export_range(1.0, 256.0, 1.0) var area_size := 40.0
## Maximum depth of a fully pressed footprint, in meters.
@export_range(0.01, 1.0, 0.01) var max_depth := 0.25
## Amount of raised snow formed around a footprint. Set to 0 to disable berms.
@export_range(0.0, 0.5, 0.01) var berm_strength := 0.15
## Height of a fully formed raised berm, in meters.
@export_range(0.0, 0.5, 0.01) var berm_height := 0.08
## Maximum number of footprint stamps processed each frame.
@export_range(1, 512, 1) var max_stamps_per_frame := 64
## Time between trail-healing updates, in seconds.
@export_range(0.05, 5.0, 0.05) var refill_interval := 0.25
## Trail-healing speed parameter at 100% snowfall.
@export_range(0.0, 255.0, 1.0) var refill_levels_per_sec := 16.0
## Legacy shared atmospheric intensity and trail-healing strength.
@export_range(0.0, 1.0, 0.05) var snowfall := 0.3
## Brightness of the snow's sparkle effect. Set to 0 to disable it.
@export_range(0.0, 3.0, 0.1) var sparkle := 1.0

@export_group("Particles")
## Maximum main flake count at 100% snowfall.
@export_range(1, 10000, 1) var flakes := 900
## Maximum extra near-camera flake count at 100% snowfall. Set to 0 to disable.
@export_range(0, 5000, 1) var near := 120
## Number of particles emitted in each deformer puff.
@export_range(1, 64, 1) var puff := 8
## Horizontal flake drift along the world X axis.
@export_range(-10.0, 10.0, 0.1) var wind_x := 0.3
## Horizontal flake drift along the world Z axis.
@export_range(-10.0, 10.0, 0.1) var wind_z := 0.0
## Height of the main falling-snow emitter above the field, in meters.
@export_range(0.0, 50.0, 0.5) var fall_height := 9.0
## Object followed by the main falling-snow emitter.
@export_enum("Camera:0", "Player:1", "Sled:2") var follow_target_mode := 0
## Whether moving deformers emit snow puffs.
@export var puffs_enabled := true
## Minimum time between puffs from one deformer, in seconds.
@export_range(0.0, 10.0, 0.05) var puff_min_interval := 0.2

@export_group("Graphics")
## Resolution of the snow deformation map.
@export_range(128, 2048, 128) var res := 512
## Number of snow mesh subdivisions per side.
@export_range(1, 512, 1) var subdiv := 127
## Softens dark footprint bevels with cool-tinted wrapped lighting.
@export var wrapped_diffuse_lighting := true


func to_dictionary() -> Dictionary:
	return {
		"res": res,
		"subdiv": subdiv,
		"sparkle": sparkle,
		"flakes": flakes,
		"near": near,
		"puff": puff,
		"area_size": area_size,
		"max_depth": max_depth,
		"berm_strength": berm_strength,
		"berm_height": berm_height,
		"max_stamps_per_frame": max_stamps_per_frame,
		"snowfall": snowfall,
		"refill_levels_per_sec": refill_levels_per_sec,
		"refill_interval": refill_interval,
		"wind_x": wind_x,
		"wind_z": wind_z,
		"fall_height": fall_height,
		"follow_target_mode": follow_target_mode,
		"puffs_enabled": puffs_enabled,
		"puff_min_interval": puff_min_interval,
		"wrapped_diffuse_lighting": wrapped_diffuse_lighting,
	}
