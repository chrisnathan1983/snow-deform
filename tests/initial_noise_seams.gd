extends SceneTree
## Checks shared noise texture caching and rendered world-space seams.

const NoiseTextures := preload("res://addons/deformable_surface/scripts/initial_noise_textures.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile := DeformableSurfaceType.new()
	profile.initial_noise = FastNoiseLite.new()
	var textures := NoiseTextures.for_profile(profile)
	var cached := NoiseTextures.for_profile(profile)
	for key in ["base", "detail", "mound"]:
		_check(textures[key] == cached[key], "%s noise texture should be shared" % key)
		_check((textures[key] as NoiseTexture2D).seamless, "%s noise texture should tile" % key)

	if DisplayServer.get_name() != "headless":
		await _check_rendered_seam(profile)

	print("Initial noise texture checks: %d failures" % _failures)
	quit(1 if _failures else 0)


func _check_rendered_seam(profile: DeformableSurfaceType) -> void:
	var field := DeformableSurface.new()
	field.size = 32.0
	field.render_mesh = false
	field.surface_type = profile
	var quality := DeformableSurfaceQuality.low()
	quality.res = 192
	field.quality = quality
	root.add_child(field)
	var map_ready := await _wait_for_map(field)
	if not map_ready:
		_check(false, "Initial map should finish generating")
		field.free()
		return
	var center := field.get_deform_image()
	field.position.x += field.size
	field.reset_trails()
	map_ready = await _wait_for_map(field)
	if not map_ready:
		_check(false, "Neighbor map should finish generating")
		field.free()
		return
	var neighbor := field.get_deform_image()
	if center == null or neighbor == null:
		_check(false, "Rendered deformation maps should be readable")
	else:
		for y in center.get_height():
			_check(center.get_pixel(center.get_width() - 1, y).is_equal_approx(
					neighbor.get_pixel(0, y)), "Adjacent map edge should match at row %d" % y)
	field.free()


func _wait_for_map(field: DeformableSurface) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while field.is_priming():
		await process_frame
		if Time.get_ticks_msec() >= deadline:
			return false
	await process_frame
	return true


func _check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
