extends SceneTree
## godot --headless --path . --script tests/ski_free_gameplay.gd
## Add -- --capture to save a rendered gameplay preview (without --headless).


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://demos/ski_free.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	await process_frame
	assert(scene.fields.size() == 9)
	assert(scene.obstacles.size() == 76)
	assert(scene.guests.size() == 10)
	var guest = scene.guests[0]
	var old_position: Vector3 = guest.position
	guest.advance(0.1, scene.skier, scene.obstacles, scene.guests)
	assert(guest.position.z > old_position.z, "Traffic must ski downhill")
	guest.position.z = scene.skier.position.z - 100
	guest.tracks._process(0.016)
	guest.advance(0.016, scene.skier, scene.obstacles, scene.guests)
	assert(guest.position.z > scene.skier.position.z + 50, "Stragglers recycle ahead")
	assert(guest.tracks._last[0] == null, "Recycling must not draw a teleport ribbon")
	guest.position.z = scene.skier.position.z + 100
	guest.advance(0.016, scene.skier, scene.obstacles, scene.guests)
	assert(guest.position.z < scene.skier.position.z - 37, "Fast guests recycle behind")
	guest.position = Vector3(0, 1.0, 0)
	guest.lift = 3.0
	var empty_scenery: Array[Node3D] = []
	guest.advance(0.016, scene.skier, empty_scenery, [])
	assert(not guest.tracks.active, "Airborne guests must not carve")
	for i in 120:
		guest.advance(0.016, scene.skier, empty_scenery, [])
	assert(guest.position.y == 0 and guest.tracks.active, "Tracks resume on landing")
	var gate: Node3D = scene.gates[0]
	scene.skier.position = gate.position + Vector3(0, 0, 0.1)
	scene._check_course(gate.position - Vector3(0, 0, 0.1))
	assert(scene.score == 100 and scene.combo == 1, "Gate crossing must score once")
	scene._check_course(gate.position - Vector3(0, 0, 0.1))
	assert(scene.score == 100, "Gate cannot score twice")
	scene._jump()
	assert(scene.vertical_speed > 0 and not scene.tracks.active)
	scene.skier.position = Vector3(0, 0, 600)
	scene._recycle_snow()
	var tile_positions := {}
	for field in scene.fields:
		assert(absf(field.position.z - 600.0) <= 40.0)
		tile_positions[field.position] = true
	assert(tile_positions.size() == 9, "Recycling must preserve unique tiles")
	var obstacle: Node3D = scene.obstacles[1]
	scene.skier.position = obstacle.position
	scene.invincible = 0
	scene._check_course(scene.skier.position)
	assert(scene.crashes == 1 and scene.crash_time > 0)
	scene._check_course(scene.skier.position)
	assert(scene.crashes == 1, "Recovery immunity must prevent repeated collisions")
	scene._toggle_pause()
	var guest_stopped: Vector3 = guest.position
	var stopped: Vector3 = scene.skier.position
	scene._physics_process(0.5)
	assert(scene.skier.position == stopped and not scene.tracks.active)
	assert(guest.position == guest_stopped and not guest.tracks.active, "Pause freezes traffic and stamping")
	scene.free()
	print("PASS: ski gates, jump, tile recycling, crash immunity, pause, NPC motion/recycling/airborne tracks")
	if "--capture" in OS.get_cmdline_user_args():
		scene = load("res://demos/ski_free.tscn").instantiate()
		root.add_child(scene)
		scene.set_physics_process(false)
		for i in 210:
			scene.heading = sin(i * 0.035) * 0.65
			scene._physics_process(1.0 / 60.0)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://ski_free_preview.png")
		scene.free()
	quit(0)
