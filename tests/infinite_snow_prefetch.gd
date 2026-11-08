extends SceneTree


const Fixture := preload("res://tests/surface_grid_fixture.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var grid := Fixture.create(root)
	var shell := DemoShell.attach(root)
	var settings := shell.bind_surfaces(grid.fields)
	grid.relocation_blocked = settings.has_pending_surface_updates
	grid.follow_target.position = Vector3.ZERO
	grid.update_tiles()
	var positions: Array[Vector3] = []
	var textures: Array[Texture2D] = []
	for field in grid.fields:
		positions.append(field.position)
		textures.append(field._initial_map_texture)
	grid.follow_target.position.x = 9.0
	grid.update_tiles()
	var failures := 0
	if grid._prefetch_relocations.size() != 3 or grid.center_tile != Vector2i.ZERO:
		push_error("Approaching a boundary did not prefetch the next row")
		failures += 1
	var deadline := Time.get_ticks_msec() + 10000
	while grid._prefetch_index < grid._prefetch_relocations.size():
		grid.update_tiles()
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("Prefetch did not complete")
			quit(1)
			return
	for i in grid.fields.size():
		var field: DeformableSurface = grid.fields[i]
		if field.position != positions[i] or field._initial_map_texture != textures[i]:
			push_error("Prefetch changed an active tile")
			failures += 1
		field.reset_trails()
		if field._initial_map_texture != textures[i]:
			push_error("Reset during prefetch regenerated the active texture")
			failures += 1
	# Settings invalidate the forecast; preparation must restart with the new profile.
	settings.edit_profile("initial_noise_detail", 0.85)
	grid.update_tiles()
	if not grid._prefetch_relocations.is_empty():
		push_error("Settings retained an obsolete prefetch plan")
		failures += 1
	deadline = Time.get_ticks_msec() + 10000
	while settings.has_pending_surface_updates():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("Settings during prefetch did not finish")
			quit(1)
			return
	grid.update_tiles()
	while grid._prefetch_index < grid._prefetch_relocations.size():
		grid.update_tiles()
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("Prefetch after settings did not finish")
			quit(1)
			return
	grid.follow_target.position.x = 16.1
	var crossing_frames := 0
	while crossing_frames == 0 or grid.has_pending_relocations():
		grid.update_tiles()
		crossing_frames += 1
		await process_frame
		if crossing_frames > 3:
			push_error("Prepared tiles were not reused immediately at the boundary")
			failures += 1
			break
	for field in grid.fields:
		if (not is_equal_approx(field.surface_type.initial_noise_detail, 0.85)
				or field._initial_noise_cache_key != field._initial_noise_key(mini(field._vp.size.x, 512))):
			push_error("Prepared crossing reused noise from before the settings change")
			failures += 1
	# For a teleport, terrain under the player must be generated ahead of distant corners.
	grid.follow_target.position = Vector3(128.0, 0.0, 128.0)
	grid.update_tiles()
	if grid._pending_relocations[0]["tile"] != Vector2i(4, 4):
		push_error("Relocation did not prioritize the tile under the player")
		failures += 1
	var previous_priority := -1.0
	for relocation in grid._pending_relocations:
		var priority: float = grid._tile_priority(relocation["tile"])
		if priority < previous_priority:
			push_error("Relocation queue is not ordered by proximity/visibility")
			failures += 1
		previous_priority = priority
	# Reverse before that work finishes: obsolete jobs must not change active maps.
	grid.update_tiles()
	grid.follow_target.position = Vector3.ZERO
	deadline = Time.get_ticks_msec() + 10000
	while grid.center_tile != Vector2i.ZERO or grid.has_pending_relocations():
		grid.update_tiles()
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("Reversing an in-flight relocation did not finish")
			quit(1)
			return
	for field in grid.fields:
		if field._initial_noise_cache_key != field._initial_noise_key(mini(field._vp.size.x, 512)):
			push_error("Reversal left a stale active texture")
			failures += 1
	print("Prefetch/priority checks: %d failures; prepared boundary crossing: %d frames" % [failures, crossing_frames])
	shell.free()
	grid.free()
	quit(1 if failures else 0)
