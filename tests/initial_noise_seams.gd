extends SceneTree
## Headless checks image seams and cache keys. A rendered run also checks texture bytes.

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var field := DeformableSurface.new()
	field.size = 32.0
	field.render_mesh = false
	var profile := DeformableSurfaceType.new()
	profile.initial_noise = FastNoiseLite.new()
	field.surface_type = profile
	var quality := DeformableSurfaceQuality.low()
	quality.res = 192
	field.quality = quality
	root.add_child(field)
	field.set_process(false)

	_check_seams(field)
	field._vp.size = Vector2i(quality.res, quality.res)
	field.position = Vector3.ZERO
	field.reset_trails()
	var original := field._initial_map_texture
	var original_key := field._initial_noise_key(quality.res)
	_check(original != null and field._get_initial_noise_texture() == original,
		"Unchanged noise texture should be cached")
	var original_bytes := field._make_initial_noise_image().get_data()

	field.position.x += field.size
	field.reset_trails()
	_check(field._initial_noise_cache_key != original_key, "Relocation should change the cache key")
	_check_active_noise(field, quality.res, "Relocation should generate noise at the destination")

	field.position = Vector3.ZERO
	field.reset_trails()
	_check(field._initial_noise_cache_key == original_key, "Returning should restore the original cache key")
	_check_texture_bytes(field, original_bytes, "Returning should restore the original noise")

	var destination := Vector3(field.size, 0.0, -field.size)
	await _prepare_and_relocate(field, destination, quality.res)

	# Request one destination, then change it before applying the result.
	field.prepare_initial_noise_at(destination + Vector3(field.size, 0.0, 0.0))
	await _prepare_and_relocate(field, destination - Vector3(field.size, 0.0, field.size), quality.res)

	field.free()
	print("Initial noise seam and relocation checks: %d failures" % _failures)
	quit(1 if _failures else 0)


func _check_seams(field: DeformableSurface) -> void:
	for resolution in [64, 192, 256, 320]:
		field._vp.size = Vector2i(resolution, resolution)
		for tile in [Vector2i.ZERO, Vector2i(-3, -2), Vector2i(5, 7)]:
			var origin := Vector3(tile.x * field.size, 0.0, tile.y * field.size)
			field.position = origin
			var center := field._make_initial_noise_image()
			for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
				field.position = origin + Vector3(direction.x * field.size, 0.0, direction.y * field.size)
				var neighbor := field._make_initial_noise_image()
				for i in resolution:
					var a := center.get_pixel(resolution - 1, i) if direction.x else center.get_pixel(i, resolution - 1)
					var b := neighbor.get_pixel(0, i) if direction.x else neighbor.get_pixel(i, 0)
					_check(a.is_equal_approx(b), "Height/normal seam at %d, tile %s, direction %s, pixel %d"
						% [resolution, tile, direction, i])


func _prepare_and_relocate(field: DeformableSurface, destination: Vector3, resolution: int) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while not field.prepare_initial_noise_at(destination):
		if Time.get_ticks_msec() >= deadline:
			_check(false, "Noise preparation should finish for %s" % destination)
			return
		await process_frame
	var prepared := field._prepared_noise_texture
	field.position = destination
	field.reset_trails()
	_check(prepared != null and field._initial_map_texture == prepared,
		"Relocation should consume the prepared texture for %s" % destination)
	_check_active_noise(field, resolution, "Background noise should match synchronous noise")


func _check_active_noise(field: DeformableSurface, resolution: int, description: String) -> void:
	_check(field._initial_noise_cache_key == field._initial_noise_key(resolution), description)
	_check_texture_bytes(field, field._make_initial_noise_image().get_data(), description)


func _check_texture_bytes(field: DeformableSurface, expected: PackedByteArray, description: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var texture := field._initial_map_texture
	var image := texture.get_image() if texture != null else null
	_check(image != null and image.get_data() == expected, description)


func _check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
