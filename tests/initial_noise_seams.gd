extends SceneTree
## Run with: godot --headless --path . --script tests/initial_noise_seams.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var field := DeformableSurface.new()
	field.size = 32.0
	field.render_mesh = false
	var quality := DeformableSurfaceQuality.new()
	quality.res = 64
	field.quality = quality
	root.add_child(field)
	var failures := 0
	for resolution in [64, 192, 256, 320]:
		field._vp.size = Vector2i(resolution, resolution)
		for tile in [Vector2i.ZERO, Vector2i(-3, -2), Vector2i(5, 7)]:
			field.position = Vector3(tile.x * field.size, 0.0, tile.y * field.size)
			var center := field._make_initial_noise_image()
			for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
				field.position = Vector3((tile.x + direction.x) * field.size, 0.0,
						(tile.y + direction.y) * field.size)
				var neighbor := field._make_initial_noise_image()
				for i in resolution:
					var a := center.get_pixel(resolution - 1, i) if direction.x else center.get_pixel(i, resolution - 1)
					var b := neighbor.get_pixel(0, i) if direction.x else neighbor.get_pixel(i, 0)
					if not a.is_equal_approx(b):
						push_error("Height/normal seam at resolution %d, tile %s, direction %s, pixel %d" % [resolution, tile, direction, i])
						failures += 1
	var original := field._get_initial_noise_texture()
	if field._get_initial_noise_texture() != original:
		push_error("Unchanged noise texture was not cached")
		failures += 1
	field.position.x += field.size
	field.reset_trails()
	var relocated := field._initial_map_texture
	if relocated == original:
		push_error("Relocation reused the old noise texture")
		failures += 1
	field.position.x -= field.size
	field.reset_trails()
	if field._initial_map_texture.get_image().get_data() != original.get_image().get_data():
		push_error("Returning to the same position changed the noise")
		failures += 1
	var destination := field.position + Vector3(field.size, 0.0, -field.size)
	while not field.prepare_initial_noise_at(destination):
		await process_frame
	field.position = destination
	field.reset_trails()
	if field._initial_map_texture.get_image().get_data() != field._make_initial_noise_image().get_data():
		push_error("Background noise differs from synchronous noise")
		failures += 1
	# A changed destination must discard the obsolete result before relocating.
	field.prepare_initial_noise_at(destination + Vector3(field.size, 0.0, 0.0))
	destination -= Vector3(field.size, 0.0, field.size)
	while not field.prepare_initial_noise_at(destination):
		await process_frame
	field.position = destination
	field.reset_trails()
	if field._initial_map_texture.get_image().get_data() != field._make_initial_noise_image().get_data():
		push_error("Changed destination reused an obsolete background result")
		failures += 1
	field.free()
	print("Initial noise seam and relocation checks: %d failures" % failures)
	quit(1 if failures else 0)
