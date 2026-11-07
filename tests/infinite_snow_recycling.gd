extends SceneTree
## Run with: godot --headless --path . --script tests/infinite_snow_recycling.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://demos/procedural_playground/snow_demo_infinite.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	var longest_usec := 0
	# Start preparation, then reverse direction before its worker finishes.
	scene.player.position.x = -scene.FIELD_SIZE
	scene._recenter_fields()
	for destination in [Vector2i(1, 0), Vector2i(-2, -1), Vector2i(3, 2)]:
		scene.player.position = Vector3(destination.x * scene.FIELD_SIZE, 0.0,
				destination.y * scene.FIELD_SIZE)
		var frames := 0
		while frames == 0 or not scene._pending_relocations.is_empty():
			var start := Time.get_ticks_usec()
			scene._recenter_fields()
			longest_usec = maxi(longest_usec, Time.get_ticks_usec() - start)
			frames += 1
			await process_frame
			if frames > 10000:
				push_error("Tile recycling failed to finish")
				quit(1)
				return
		for field in scene.snow_fields:
			if field._initial_noise_cache_key != field._initial_noise_key(mini(field._vp.size.x, 512)):
				push_error("Recycled tile has stale noise")
				quit(1)
				return
	print("Longest tile-recycling call: %.2f ms" % (longest_usec / 1000.0))
	if longest_usec > 50000:
		push_error("Tile recycling blocked the main thread for more than 50 ms")
		scene.free()
		quit(1)
		return
	scene.free()
	quit(0)
