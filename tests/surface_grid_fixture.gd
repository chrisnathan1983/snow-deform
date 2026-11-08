extends RefCounted
## Use a custom noise source to exercise the shared preset texture path.


static func create(parent: Node) -> DeformableSurfaceGrid:
	var grid := DeformableSurfaceGrid.new()
	grid.surface_type = DemoSettings.SNOW_PROFILE.duplicate() as DeformableSurfaceType
	grid.surface_type.initial_noise = FastNoiseLite.new()
	grid.quality = DeformableSurfaceQuality.low()
	grid.quality.res = 192
	grid.follow_target = Node3D.new()
	grid.add_child(grid.follow_target)
	parent.add_child(grid)
	grid.set_process(false)
	return grid
