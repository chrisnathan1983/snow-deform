extends SceneTree
## The rendered run checks actual warm-up draws and the first live puff.

const Loader := preload("res://demos/shared/demo_loader.gd")
const LAUNCHER := "res://demos/launcher.tscn"
const PLAYGROUND := "res://demos/playground.tscn"
const MATERIALS := "res://demos/materials_demo.tscn"
const POWDER_RUN := "res://demos/ski_free.tscn"
const CUSTOM_TERRAIN := "res://demos/custom_terrain_demo.tscn"

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	change_scene_to_file(LAUNCHER)
	await scene_changed
	var launcher = current_scene
	launcher._launch_demo("res://demos/missing_demo.tscn")
	var loading := root.get_node("DemoLoading")
	_check(current_scene == launcher and loading._label.text == "Loading…",
		"Launcher should show loading feedback before attempting to load")
	launcher._launch_demo(PLAYGROUND)
	_check(root.find_children("DemoLoading*", "", false, false).size() == 1,
		"A second click should not create another loader")
	await loading.tree_exited
	_check(current_scene == launcher and not paused and not launcher._loading,
		"A missing scene should return control to the launcher")
	_check(launcher._status.text.begins_with("Could not load"), "Launcher should show the load error")

	launcher._launch_demo(PLAYGROUND)
	loading = root.get_node("DemoLoading")
	await _check_transition(loading, PLAYGROUND)

	change_scene_to_file(LAUNCHER)
	await scene_changed
	loading = Loader.new()
	loading.use_threads = false
	root.add_child(loading)
	loading.open_demo(MATERIALS)
	await _check_transition(loading, MATERIALS)

	for path in [POWDER_RUN, CUSTOM_TERRAIN]:
		change_scene_to_file(LAUNCHER)
		await scene_changed
		current_scene._launch_demo(path)
		loading = root.get_node("DemoLoading")
		await _check_transition(loading, path)
	print("Demo loading checks: %d failures" % _failures)
	quit(1 if _failures else 0)


func _check_transition(loading: Node, expected_scene: String) -> void:
	await scene_changed
	_check(current_scene.scene_file_path == expected_scene and paused and loading.is_inside_tree(),
		"The loading screen should cover the new scene while gameplay is paused")

	var rendered := DisplayServer.get_name() != "headless"
	var field := DeformableSurface.instances.front() as DeformableSurface
	var warm_image := PackedByteArray()
	var deadline := Time.get_ticks_msec() + 10000
	while is_instance_valid(loading) and Time.get_ticks_msec() < deadline:
		await process_frame
		if not rendered or field.get_stamps_used() != 4 or not warm_image.is_empty():
			continue
		_check(paused and loading._label.text == "Warming up snow…",
			"Warm-up stamps should be drawn behind the loading screen")
		var puffs = field._puffs
		_check(puffs != null and puffs._pool.size() == puffs.pool_size
			and puffs._pool.all(func(p: CPUParticles3D): return p.visible and p.emitting),
			"Every puff emitter should be started")
		await RenderingServer.frame_post_draw
		var image := field._vp.get_texture().get_image()
		if image != null:
			warm_image = image.get_data()

	_check(not is_instance_valid(loading) and not paused, "Loading should finish and resume the scene")
	if not rendered:
		return
	_check(not warm_image.is_empty(), "All four sample stamps should reach the render target")
	_check(field._vp.get_texture().get_image().get_data() != warm_image,
		"Warm-up stamps should be cleared before gameplay resumes")
	var puffs = field._puffs
	if puffs == null:
		_check(false, "The warmed puff pool should be ready for gameplay")
		return
	_check(puffs._pool.all(func(p: CPUParticles3D): return not p.visible and not p.emitting),
		"Warm-up puffs should be hidden and stopped before gameplay resumes")
	var start := field.global_position
	field.stamp_at(start, 0.5, 1.0, null, DeformableSurface.StampMode.CARVE, 0.0, 1.0, true)
	field.stamp_segment(start, start + Vector3.FORWARD, 0.3, 1.0,
		null, DeformableSurface.StampMode.CARVE, 0.0, true)
	field.stamp_segment(start, start + Vector3.RIGHT, 0.3, 1.0, DeformerTracks.get_default_tread())
	var live_stamps_drawn := false
	for frame in 8:
		await process_frame
		if puffs._pool[0].visible and field.get_stamps_used() >= 3:
			live_stamps_drawn = true
			break
	_check(field._puffs == puffs and puffs._pool[0].visible,
		"The first live puff should reuse and show the warmed emitter")
	_check(live_stamps_drawn, "The first live round, capsule, and tread stamps should draw")


func _check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
