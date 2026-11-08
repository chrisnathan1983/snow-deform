extends SceneTree
## godot --headless --path . --script tests/ski_free_gameplay.gd
## Run with rendering to verify MultiMesh transforms. Add -- --capture to save a preview.

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://demos/ski_free.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	await process_frame
	await _check_touch_controls(scene)
	_check(scene.fields.size() == 9, "Snow grid should have nine fields")
	_check(scene.obstacles.size() == 76, "Course should have 76 pooled obstacles")
	_check(scene.guests.size() == 10, "Course should have ten slope guests")
	_check(scene.tracks.profile == DeformerTracks.Profile.SMOOTH, "The skier should carve smooth grooves")
	var guest_counts := [0, 0, 0, 0]
	for rider in scene.guests:
		guest_counts[rider.kind] += 1
		_check(not rider.scene_file_path.is_empty(), "Slope guests should use authored scenes")
		_check(rider.tracks.profile == DeformerTracks.Profile.SMOOTH,
			"Every slope guest should carve continuous grooves")
	_check(guest_counts == [6, 2, 1, 1], "Course should spawn each slope guest kind")
	var pooled_obstacle: Node3D = scene.obstacles[0]
	var next_z: float = pooled_obstacle.position.z + scene.COURSE_LENGTH
	scene._place_obstacle(pooled_obstacle, next_z)
	_check(is_equal_approx(pooled_obstacle.position.z, next_z), "Logical obstacle should recycle")
	var slots: Array = pooled_obstacle.get_meta("draw_slots", [])
	_check(not slots.is_empty(), "Pooled obstacle should have scenery batch slots")
	if DisplayServer.get_name() != "headless":
		for slot in slots:
			var drawn: Transform3D = slot.multimesh.get_instance_transform(slot.index)
			_check(drawn.is_equal_approx(pooled_obstacle.transform * slot.local_transform),
				"Recycled scenery instances must follow logical obstacles")
	var guest = scene.guests[0]
	var old_position: Vector3 = guest.position
	guest.advance(0.1, scene.skier, scene.obstacles, scene.guests)
	_check(guest.position.z > old_position.z, "Traffic must ski downhill")
	guest.position.z = scene.skier.position.z - 100
	guest.tracks._process(0.016)
	guest.advance(0.016, scene.skier, scene.obstacles, scene.guests)
	_check(guest.position.z > scene.skier.position.z + 50, "Stragglers recycle ahead")
	_check(guest.tracks._last[0] == null, "Recycling must not draw a teleport ribbon")
	guest.position.z = scene.skier.position.z + 100
	guest.advance(0.016, scene.skier, scene.obstacles, scene.guests)
	_check(guest.position.z < scene.skier.position.z - 37, "Fast guests recycle behind")
	guest.position = Vector3(0, 1.0, 0)
	guest.lift = 3.0
	var empty_scenery: Array[Node3D] = []
	guest.advance(0.016, scene.skier, empty_scenery, [])
	_check(not guest.tracks.active, "Airborne guests must not carve")
	for i in 120:
		guest.advance(0.016, scene.skier, empty_scenery, [])
	_check(guest.position.y == 0 and guest.tracks.active, "Tracks resume on landing")
	var gate: Node3D = scene.gates[0]
	scene.skier.position = gate.position + Vector3(0, 0, 0.1)
	scene._check_course(gate.position - Vector3(0, 0, 0.1))
	_check(scene.score == 100 and scene.combo == 1, "Gate crossing must score once")
	scene._check_course(gate.position - Vector3(0, 0, 0.1))
	_check(scene.score == 100, "Gate cannot score twice")
	scene._jump()
	_check(scene.vertical_speed > 0 and not scene.tracks.active, "Jump should lift the skier and stop stamping")
	scene.skier.position = Vector3(0, 0, 600)
	scene.snow_grid.update_tiles()
	var tile_positions := {}
	for field in scene.fields:
		_check(absf(field.position.z - 600.0) <= 40.0, "Snow fields should follow the skier")
		tile_positions[field.position] = true
	_check(tile_positions.size() == 9, "Recycling must preserve unique tiles")
	var obstacle: Node3D = scene.obstacles[1]
	scene.skier.position = obstacle.position
	scene.invincible = 0
	scene._check_course(scene.skier.position)
	_check(scene.crashes == 1 and scene.crash_time > 0, "Hitting an obstacle should cause a wipeout")
	scene._check_course(scene.skier.position)
	_check(scene.crashes == 1, "Recovery immunity must prevent repeated collisions")
	scene._toggle_pause()
	var guest_stopped: Vector3 = guest.position
	var stopped: Vector3 = scene.skier.position
	scene._physics_process(0.5)
	_check(scene.skier.position == stopped and not scene.tracks.active, "Pause should freeze the skier and tracks")
	_check(guest.position == guest_stopped and not guest.tracks.active, "Pause freezes traffic and stamping")
	scene.free()
	await _check_launcher_layout()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		scene = load("res://demos/ski_free.tscn").instantiate()
		root.add_child(scene)
		scene.set_physics_process(false)
		for i in 210:
			scene.heading = sin(i * 0.035) * 0.65
			scene._physics_process(1.0 / 60.0)
			await process_frame
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png("res://.godot/ski_free_preview.png")
		_check(result == OK, "Rendered preview should save")
		scene.free()
	print("Powder Run gameplay checks: %d failures" % _failures)
	quit(1 if _failures else 0)


func _check_touch_controls(scene: Node) -> void:
	var sticks: TouchSticks = scene.touch_sticks
	var origin := Vector2(160, 380)
	_send_touch(0, origin, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = origin + Vector2(60, -50)
	root.push_input(drag, true)
	_check(sticks.move.x > 0.5 and sticks.move.y < -0.35, "Shared joystick must steer and tuck")
	_check(sticks.look == Vector2.ZERO, "The ski camera must remain fixed")

	var jump_point: Vector2 = scene.touch_jump.global_position
	_send_touch(1, jump_point, true)
	_check(scene.vertical_speed > 0, "A second finger must jump while steering")
	_send_touch(1, jump_point, false)
	_check(sticks.move.x > 0.5, "Releasing Jump must not release the steering finger")
	drag.position = origin + Vector2(-45, 60)
	root.push_input(drag, true)
	_check(sticks.move.x < -0.5 and sticks.move.y > 0.35, "Pulling back must brake while steering")
	_send_touch(0, drag.position, false)
	_check(sticks.move == Vector2.ZERO, "Lifting the steering finger must release the stick")

	_send_touch(0, origin, true)
	root.push_input(drag, true)
	scene._toggle_pause()
	_check(sticks.move == Vector2.ZERO, "Pausing must clear held touch input")
	_send_touch(0, drag.position, false)
	scene._toggle_pause()
	scene.skier.position.y = 0
	scene.vertical_speed = 0

	var old_size := root.size
	var old_scale := root.content_scale_size
	root.content_scale_size = Vector2i(720, 720)
	for window_size in [Vector2i(390, 844), Vector2i(844, 390)]:
		root.size = window_size
		await process_frame
		await process_frame
		scene._update_layout()
		var visible_size := root.get_visible_rect().size
		var portrait := visible_size.x < visible_size.y
		_check(portrait == (window_size.x < window_size.y), "Viewport must follow device orientation")
		_check(scene.camera.keep_aspect == (Camera3D.KEEP_WIDTH if portrait else Camera3D.KEEP_HEIGHT),
			"Camera framing should follow orientation")
		var jump_rect: Rect2 = scene.touch_jump.get_parent().get_global_rect()
		_check(Rect2(Vector2.ZERO, visible_size).encloses(jump_rect), "Jump must stay on screen after rotation")
	root.content_scale_size = old_scale
	root.size = old_size
	await process_frame


func _send_touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)


func _check_launcher_layout() -> void:
	var launcher = load("res://demos/launcher.tscn").instantiate()
	root.add_child(launcher)
	var old_size := root.size
	var old_scale := root.content_scale_size
	root.content_scale_size = Vector2i(720, 720)
	for window_size in [Vector2i(390, 844), Vector2i(844, 390)]:
		root.size = window_size
		await process_frame
		await process_frame
		await process_frame
		var viewport_width := root.get_visible_rect().size.x
		var panel: PanelContainer = launcher._panel
		_check(panel.get_global_rect().position.x >= 0, "Launcher must stay inside the left edge")
		_check(panel.get_global_rect().end.x <= viewport_width, "Launcher must fit horizontally in both orientations")
		_check(panel.get_minimum_size().x <= panel.size.x, "Launcher text must not force horizontal overflow")
	root.content_scale_size = old_scale
	root.size = old_size
	launcher.free()



func _check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
