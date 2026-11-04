@tool
class_name DeformableSurfaceSettings
extends Resource
## Technical quality settings for one DeformableSurface: map resolution, mesh density,
## stamp and puff budgets, and refill cadence. What the surface is made of (depth, berms,
## recovery, look) lives in DeformableSurfaceMaterialProfile. `sparkle` is only a quality
## scale on top of the material's own `sparkle_strength`.

@export_group("Surface")
@export_range(1.0, 256.0, 1.0) var area_size := 40.0
@export_range(128, 2048, 128) var res := 512
@export_range(1, 512, 1) var subdiv := 127

@export_group("Budgets")
@export_range(1, 512, 1) var max_stamps_per_frame := 64
@export_range(0.05, 5.0, 0.05) var refill_interval := 0.25
@export_range(1, 64, 1) var puff := 8
@export_range(0.0, 10.0, 0.05) var puff_min_interval := 0.2

@export_group("Effects")
## Quality scale for the material's sparkle.
@export_range(0.0, 3.0, 0.1) var sparkle := 1.0


func to_dictionary() -> Dictionary:
	return {
		"area_size": area_size,
		"res": res,
		"subdiv": subdiv,
		"max_stamps_per_frame": max_stamps_per_frame,
		"refill_interval": refill_interval,
		"puff": puff,
		"puff_min_interval": puff_min_interval,
		"sparkle": sparkle,
	}