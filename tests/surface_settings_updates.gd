extends SceneTree
## Exercises rapid settings edits, simultaneous profile/resolution changes, and recycling.


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://demos/procedural_playground/snow_demo_infinite.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.settings.set_process(false)
	var longest_usec := 0
	for i in 15:
		var start := Time.get_ticks_usec()
		scene.settings.edit_profile("initial_noise_detail", i * 0.04)
		scene.settings.edit_profile("initial_noise_mound_height", i * 0.01)
		scene.settings._edit_technical("res", 192 if i < 14 else 256)
		longest_usec = maxi(longest_usec, Time.get_ticks_usec() - start)
	# A quality change while another result is in flight must keep the latest edits.
	scene.settings._process(0.2)
	scene.settings._edit_technical("res", 192)
	scene.player.position = Vector3(32.0, 0.0, 32.0)
	var frames := 0
	while scene.settings.has_pending_surface_updates() or frames == 0 or not scene._pending_relocations.is_empty():
		var start := Time.get_ticks_usec()
		scene.settings._process(0.016)
		scene._recenter_fields()
		longest_usec = maxi(longest_usec, Time.get_ticks_usec() - start)
		frames += 1
		await process_frame
		if frames > 10000:
			push_error("Settings/recycling queues failed to finish")
			quit(1)
			return
	var failures := 0
	for field in scene.snow_fields:
		if (not is_equal_approx(field.surface_type.initial_noise_detail, 0.56)
				or not is_equal_approx(field.surface_type.initial_noise_mound_height, 0.14)
				or field._vp.size != Vector2i(192, 192)):
			push_error("Settings lost an edit or applied an obsolete worker result")
			failures += 1
		if field._initial_noise_cache_key != field._initial_noise_key(192):
			push_error("Settings/recycling left a stale noise map")
			failures += 1
	# Applying profile and resolution together must consume the prepared texture.
	var field: DeformableSurface = scene.snow_fields[0]
	var profile := field.surface_type.duplicate() as DeformableSurfaceType
	profile.initial_noise_detail = 0.9
	var quality := field.quality.duplicate() as DeformableSurfaceQuality
	quality.res = 256
	while not field.prepare_initial_noise_at(field.global_position, profile, quality):
		await process_frame
	var prepared := field._initial_noise_cache
	field.apply_surface_settings(profile, quality)
	if field._initial_map_texture != prepared:
		push_error("Combined settings regenerated noise synchronously")
		failures += 1
	if longest_usec > 50000:
		push_error("Settings blocked the main thread for more than 50 ms")
		failures += 1
	print("Settings checks: %d failures; longest main-thread update: %.2f ms" % [failures, longest_usec / 1000.0])
	scene.free()
	quit(1 if failures else 0)
