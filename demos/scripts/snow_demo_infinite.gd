extends "res://demos/scripts/snow_demo.gd"
## Procedural playground variant with a recycled, fence-free DeformableSurface grid.

const TILE_QUALITY_PRESETS: Array[DeformableSurfaceQuality] = [
	preload("res://demos/resources/snow_lab_infinite/low.tres"),
	preload("res://demos/resources/snow_lab_infinite/medium.tres"),
	preload("res://demos/resources/snow_lab_infinite/high.tres"),
]

var grid: DeformableSurfaceGrid


func _ready() -> void:
	super._ready()
	grid.follow_target = player
	grid.relocation_blocked = settings.has_pending_surface_updates


func _build_snow() -> void:
	_quality_presets = TILE_QUALITY_PRESETS
	grid = DeformableSurfaceGrid.new()
	grid.name = "SurfaceGrid"
	grid.tile_size = FIELD_SIZE
	grid.surface_type = _snow_profile()
	grid.quality = _quality_presets[_quality]
	grid.sun = sun
	grid.priority_camera = camera
	add_child(grid)
	snow_fields = grid.fields
	snow = grid.field_at(Vector2i.ZERO)


func _actor_half_extent() -> float:
	return 1000000.0


func _has_fence() -> bool:
	return false


func _constrain_target(target: Vector3, _margin: float) -> Vector3:
	return target


func _process(delta: float) -> void:
	super._process(delta)
	_ground.global_position.x = player.global_position.x
	_ground.global_position.z = player.global_position.z
