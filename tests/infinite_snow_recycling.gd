extends SceneTree
## Run with: godot --headless --path . --script tests/infinite_snow_recycling.gd


const Fixture := preload("res://tests/surface_grid_fixture.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var grid := Fixture.create(root)
	var longest_usec := 0
	# Start preparation, then reverse direction before its worker finishes.
	grid.follow_target.position.x = -grid.tile_size
	grid.update_tiles()
	for destination in [Vector2i(1, 0), Vector2i(-2, -1), Vector2i(3, 2)]:
		grid.follow_target.position = Vector3(destination.x * grid.tile_size, 0.0,
				destination.y * grid.tile_size)
		var frames := 0
		while frames == 0 or grid.has_pending_relocations():
			var start := Time.get_ticks_usec()
			grid.update_tiles()
			longest_usec = maxi(longest_usec, Time.get_ticks_usec() - start)
			frames += 1
			await process_frame
			if frames > 10000:
				push_error("Tile recycling failed to finish")
				quit(1)
				return
		for field in grid.fields:
			if field._initial_noise_cache_key != field._initial_noise_key(mini(field._vp.size.x, 512)):
				push_error("Recycled tile has stale noise")
				quit(1)
				return
	print("Longest tile-recycling call: %.2f ms" % (longest_usec / 1000.0))
	if longest_usec > 50000:
		push_error("Tile recycling blocked the main thread for more than 50 ms")
		grid.free()
		quit(1)
		return
	grid.free()
	quit(0)
