extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://demos/snow_demo_infinite.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.player.set_process(false)
	while scene.settings.has_pending_surface_updates():
		await process_frame
	scene.player.position = Vector3.ZERO
	scene._recenter_fields()
	var positions: Array[Vector3] = []
	var textures: Array[Texture2D] = []
	for field in scene.snow_fields:
		positions.append(field.position)
		textures.append(field._initial_map_texture)
	scene.player.position.x = 9.0
	scene._recenter_fields()
	var failures := 0
	if scene._prefetch_relocations.size() != 3 or scene._center_tile != Vector2i.ZERO:
		push_error("Approaching a boundary did not prefetch the next row")
		failures += 1
	var deadline := Time.get_ticks_msec() + 10000
	while scene._prefetch_index < scene._prefetch_relocations.size():
		scene._recenter_fields()
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("Prefetch did not complete")
			quit(1)
			return
	for i in scene.snow_fields.size():
		var field: DeformableSurface = scene.snow_fields[i]
		if field.position != positions[i] or field._initial_map_texture != textures[i]:
			push_error("Prefetch changed an active tile")
			failures += 1
		field.reset_trails()
		if field._initial_map_texture != textures[i]:
			push_error("Reset during prefetch regenerated the active texture")
			failures += 1
	# Settings invalidate the forecast; preparation must restart with the new profile.
	scene.settings.edit_profile("initial_noise_detail", 0.85)
	scene._recenter_fields()
	if not scene._prefetch_relocations.is_empty():
		push_error("Settings retained an obsolete prefetch plan")
		failures += 1
	deadline = Time.get_ticks_msec() + 10000
	while scene.settings.has_pending_surface_updates():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("Settings during prefetch did not finish")
			quit(1)
			return
	scene._recenter_fields()
	while scene._prefetch_index < scene._prefetch_relocations.size():
		scene._recenter_fields()
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("Prefetch after settings did not finish")
			quit(1)
			return
	scene.player.position.x = 16.1
	var crossing_frames := 0
	while crossing_frames == 0 or not scene._pending_relocations.is_empty():
		scene._recenter_fields()
		crossing_frames += 1
		await process_frame
		if crossing_frames > 3:
			push_error("Prepared tiles were not reused immediately at the boundary")
			failures += 1
			break
	for field in scene.snow_fields:
		if (not is_equal_approx(field.surface_type.initial_noise_detail, 0.85)
				or field._initial_noise_cache_key != field._initial_noise_key(mini(field._vp.size.x, 512))):
			push_error("Prepared crossing reused noise from before the settings change")
			failures += 1
	# For a teleport, terrain under the player must be generated ahead of distant corners.
	scene.player.position = Vector3(128.0, 0.0, 128.0)
	scene._queue_recenter(Vector2i(4, 4))
	if scene._pending_relocations[0]["tile"] != Vector2i(4, 4):
		push_error("Relocation did not prioritize the tile under the player")
		failures += 1
	var previous_priority := -1.0
	for relocation in scene._pending_relocations:
		var priority: float = scene._tile_priority(relocation["tile"])
		if priority < previous_priority:
			push_error("Relocation queue is not ordered by proximity/visibility")
			failures += 1
		previous_priority = priority
	# Reverse before that work finishes: obsolete jobs must not change active maps.
	scene._recenter_fields()
	scene.player.position = Vector3.ZERO
	deadline = Time.get_ticks_msec() + 10000
	while scene._center_tile != Vector2i.ZERO or not scene._pending_relocations.is_empty():
		scene._recenter_fields()
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("Reversing an in-flight relocation did not finish")
			quit(1)
			return
	for field in scene.snow_fields:
		if field._initial_noise_cache_key != field._initial_noise_key(mini(field._vp.size.x, 512)):
			push_error("Reversal left a stale active texture")
			failures += 1
	print("Prefetch/priority checks: %d failures; prepared boundary crossing: %d frames" % [failures, crossing_frames])
	scene.free()
	quit(1 if failures else 0)
