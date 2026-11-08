extends CanvasLayer
## Keeps the loading screen alive across the scene change.

signal failed(message: String)

var use_threads := not OS.has_feature("nothreads")
var _label: Label


func _ready() -> void:
	name = "DemoLoading"
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS

	var background := ColorRect.new()
	background.color = Color("dbeaf2")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	_label = Label.new()
	_label.text = "Loading…"
	_label.theme = DemoTheme.get_theme()
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Color("203450"))
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(_label)


func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()


func open_demo(path: String) -> void:
	# Give the loading screen a draw before resource loading or scene construction.
	await _draw_frame()
	var scene := await _load_demo(path)
	if scene == null:
		_fail("Could not load demo '%s'." % path)
		return

	var tree := get_tree()
	var was_paused := tree.paused
	tree.paused = true
	var error := tree.change_scene_to_packed(scene)
	if error != OK:
		tree.paused = was_paused
		_fail("Could not open demo '%s': %s" % [path, error_string(error)])
		return
	await tree.scene_changed

	if DisplayServer.get_name() != "headless":
		_label.text = "Warming up snow…"
		await _draw_frame()
		await _warm_effects(tree.current_scene)

	tree.paused = was_paused
	queue_free()


func _load_demo(path: String) -> PackedScene:
	if not ResourceLoader.exists(path, "PackedScene"):
		return null
	if not use_threads or ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
		return load(path) as PackedScene
	var status := ResourceLoader.load_threaded_get_status(path)
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
		status = ResourceLoader.load_threaded_get_status(path)
	# Collect completed and failed requests so the loader can retry the same path.
	if status in [ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED]:
		return ResourceLoader.load_threaded_get(path) as PackedScene
	return null


func _warm_effects(demo: Node) -> void:
	var camera := get_viewport().get_camera_3d()
	var puff_position := Vector3.ZERO
	if camera != null:
		# Draw particles inside the frustum even for tiles beyond the camera.
		puff_position = camera.global_position - camera.global_basis.z * 5.0
	var tread := DeformerTracks.get_default_tread()
	var fields: Array[DeformableSurface] = []
	for field in DeformableSurface.instances:
		if demo.is_ancestor_of(field):
			fields.append(field)
			field.warm_up_effects(tread, puff_position)
	# Give CPU particles time to emit and draw while the scene is paused.
	await _draw_frame()
	await _draw_frame()
	for field in fields:
		field.finish_effects_warmup()
	await _draw_frame()


func _draw_frame() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _fail(message: String) -> void:
	failed.emit(message)
	queue_free()
