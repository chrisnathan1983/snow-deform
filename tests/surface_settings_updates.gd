extends SceneTree
## Exercises rapid settings edits, simultaneous profile/resolution changes, and recycling.


const Fixture := preload("res://tests/surface_grid_fixture.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var grid := Fixture.create(root)
	var shell := DemoShell.attach(root)
	var settings := shell.bind_surfaces(grid.fields)
	settings.set_process(false)
	var longest_usec := 0
	for i in 15:
		var start := Time.get_ticks_usec()
		settings.edit_profile("initial_noise_detail", i * 0.04)
		settings.edit_profile("initial_noise_mound_height", i * 0.01)
		settings._edit_technical("res", 192 if i < 14 else 256)
		longest_usec = maxi(longest_usec, Time.get_ticks_usec() - start)
	# The latest queued settings apply together after the debounce.
	settings._process(0.2)
	settings._edit_technical("res", 192)
	grid.follow_target.position = Vector3(grid.tile_size, 0.0, grid.tile_size)
	var frames := 0
	while settings.has_pending_surface_updates() or frames == 0 or grid.has_pending_relocations():
		var start := Time.get_ticks_usec()
		settings._process(0.016)
		grid.update_tiles()
		longest_usec = maxi(longest_usec, Time.get_ticks_usec() - start)
		frames += 1
		await process_frame
		if frames > 10000:
			push_error("Settings/recycling queues failed to finish")
			quit(1)
			return
	var failures := 0
	for field in grid.fields:
		if (not is_equal_approx(field.surface_type.initial_noise_detail, 0.56)
				or not is_equal_approx(field.surface_type.initial_noise_mound_height, 0.14)
				or field.get_deform_resolution() != Vector2i(192, 192)):
			push_error("Settings lost an edit or applied an obsolete update")
			failures += 1
	# Applying profile and resolution together should clear the map once.
	var field: DeformableSurface = grid.fields[0]
	var profile := field.surface_type.duplicate() as DeformableSurfaceType
	profile.initial_noise_detail = 0.9
	var quality := field.quality.duplicate() as DeformableSurfaceQuality
	quality.res = 256
	field.apply_surface_settings(profile, quality)
	if field.quality.res != 256 or not field.is_priming():
		push_error("Combined settings did not apply and clear the map")
		failures += 1
	if longest_usec > 50000:
		push_error("Settings blocked the main thread for more than 50 ms")
		failures += 1
	print("Settings checks: %d failures; longest main-thread update: %.2f ms" % [failures, longest_usec / 1000.0])
	shell.free()
	grid.free()
	quit(1 if failures else 0)
