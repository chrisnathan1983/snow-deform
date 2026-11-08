extends SceneTree
## Checks the launcher and live arena/grid switches, including queued HUD edits.

const PLAYGROUND := "res://demos/playground.tscn"

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1


func _run() -> void:
	change_scene_to_file("res://demos/launcher.tscn")
	await scene_changed
	var launcher = current_scene
	var paths: Array[String] = []
	for demo in launcher.DEMOS:
		var path: String = demo["scene"]
		paths.append(path)
		_check(load(path) is PackedScene, "Launcher scene should load: %s" % path)
	paths.sort()
	_check(paths == [
		"res://demos/custom_terrain_demo.tscn",
		"res://demos/materials_demo.tscn",
		PLAYGROUND,
		"res://demos/ski_free.tscn",
	], "Launcher should list the four current demos")
	var playground_button: Button
	for node in launcher._panel.find_children("*", "Button", true, false):
		if node.text == "Playground":
			playground_button = node
			break
	if playground_button == null:
		push_error("Launcher is missing the Playground button")
		quit(1)
		return
	playground_button.pressed.emit()
	await scene_changed
	var loading := root.get_node_or_null("DemoLoading")
	if loading != null:
		await loading.tree_exited
	var scene = current_scene
	_check(scene.scene_file_path == PLAYGROUND, "Launcher should open Playground")
	if scene.scene_file_path != PLAYGROUND:
		quit(1)
		return

	var toggle: CheckButton = scene.ui._controls["infinite"]["control"]
	var area: HSlider = scene.ui._controls["surface.area_size"]["control"]
	var people: Node3D = scene.get_node("Actors/People")
	var mouse: Node3D = scene.get_node("Actors/Mouse")
	var ball: RigidBody3D = scene.get_node("Actors/SoccerBall")
	var ball_deformer: Deformer = ball.get_node("Deformer")
	var player_id: int = scene.player.get_instance_id()
	var weather_id: int = scene.weather.get_instance_id()
	_check(not toggle.button_pressed and area.editable, "Playground starts in the fenced arena")
	_check(scene.snow_fields.size() == 1 and scene.get_node_or_null("Fence") != null,
		"Finite mode should create a single field and a fence")
	_check(people.get_child_count() == 4 and mouse.visible and ball.visible,
		"Classic actors should appear in Playground")
	for i in 8:
		await physics_frame
	_check(ball.position.y > 0.25 and ball.position.y < 0.45, "Soccer ball should rest on the floor")
	var ball_start_x := ball.position.x
	scene.player.position = Vector3(ball_start_x - 0.6, 0.0, ball.position.z)
	for i in 4:
		await physics_frame
	_check(ball.position.x > ball_start_x, "Explorer should be able to push the soccer ball")
	area.value = 48.0
	_check(scene.snow.size == 48.0 and is_equal_approx(scene.player.half_extent, 23.2),
		"Area slider should resize the snow and player bounds")
	_check(is_equal_approx(scene._walls[0].position.x, 24.25), "Area slider should move the wall")
	scene.ui._controls["people"]["control"].button_pressed = false
	scene.ui._controls["mouse"]["control"].button_pressed = false
	scene.ui._controls["soccer_ball"]["control"].button_pressed = false
	_check(not people.visible and not mouse.can_process() and not ball.can_process() and not ball_deformer.active,
		"Actor toggles should hide and disable Classic actors")

	scene.settings.set_quality(0)
	scene.ui.changed.emit("surface.preset", 1)
	scene.settings.edit_profile("max_depth", 0.27)
	var finite: WeakRef = weakref(scene.snow)
	toggle.button_pressed = true
	_check(scene.infinite and not area.editable, "Infinite toggle should disable the area slider")
	_check(finite.get_ref() == null and scene.snow_fields.size() == 9,
		"Infinite mode should replace the finite field with nine tiles")
	_check(DeformableSurface.instances.size() == 9, "Only the live grid fields should be registered")
	_check(scene.get_node_or_null("Fence") == null and scene._walls[0].disabled,
		"Infinite mode should remove the fence and disable its collision")
	for field in scene.snow_fields:
		_check(field.size == 32.0 and field.quality.res == 192, "Infinite mode should use its tile size and low preset")
		_check(field.surface_type.type_name == &"sand" and is_equal_approx(field.max_depth, 0.27),
			"Mode switches should preserve pending material and profile edits")
	_check(not scene.settings.has_pending_surface_updates(), "Field replacement should clear the old edit queue")
	_check(not people.visible and not mouse.visible and not ball.visible, "Actor toggles should persist")
	_check(scene.player.get_instance_id() == player_id and scene.weather.get_instance_id() == weather_id,
		"Mode switches should retain the explorer and weather")
	scene.ui.changed.emit("surface.area_size", 60.0)
	_check(scene.snow.size == 32.0, "Area slider events must not resize grid tiles")

	scene.player.position = Vector3(96.0, 0.0, -32.0)
	var deadline := Time.get_ticks_msec() + 10000
	while scene.grid.field_at(Vector2i(3, -1)) == null and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(scene.grid.center_tile == Vector2i(3, -1) and scene.grid.field_at(Vector2i(3, -1)) != null,
		"Infinite grid should follow travel outside the arena")
	scene.settings._edit_technical("res", 320)
	toggle.button_pressed = false
	_check(not scene.infinite and scene.grid == null and DeformableSurface.instances.size() == 1,
		"Returning to the arena should unregister every grid tile")
	_check(area.editable and area.value == 48.0 and scene.snow.size == 48.0,
		"Returning to the arena should restore its saved size")
	_check(scene.snow.quality.res == 320 and scene.settings.quality_index == 3,
		"Returning to the arena should retain the custom quality edit")
	_check(not scene._walls[0].disabled and is_equal_approx(scene.player.position.x, 23.2),
		"Returning to the arena should restore collision and move the player inside")
	_check(scene.settings.fields == scene.snow_fields and not scene.settings.has_pending_surface_updates(),
		"Settings should bind to the replacement arena field")

	for key in ["people", "mouse", "soccer_ball"]:
		scene.ui._controls[key]["control"].button_pressed = true
	_check(people.visible and mouse.can_process() and ball.can_process(), "Classic actors should re-enable")
	print("Playground mode checks: %d failures" % _failures)
	quit(1 if _failures else 0)
