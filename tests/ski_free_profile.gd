extends SceneTree
## Native Godot only. Fixed simulation steps, uncapped rendering, identical course per case.
## godot --path . --script tests/ski_free_profile.gd

func _initialize() -> void:
	_run.call_deferred()

func _summary(values: Array[float]) -> Dictionary:
	values.sort()
	return {"median": values[values.size() / 2], "p95": values[int(values.size() * 0.95)]}

func _run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var report := {}
	for variant in ["baseline", "shared_mask", "no_tracks", "sled_brushes", "no_shadows", "smooth_only", "batched_only", "optimized", "mobile"]:
		if "--mobile-only" in OS.get_cmdline_user_args() and variant != "mobile":
			continue
		var scene = load("res://demos/ski_free.tscn").instantiate()
		scene.batch_scenery = variant in ["batched_only", "optimized", "mobile"]
		scene.mobile_lighting = variant == "mobile"
		root.add_child(scene)
		scene.set_physics_process(false)
		var all_tracks: Array = [scene.tracks]
		for guest in scene.guests:
			all_tracks.append(guest.tracks)
		var runners: Array[Deformer] = []
		var owners: Array = []
		for track in all_tracks:
			if variant not in ["smooth_only", "optimized", "mobile"]:
				track.profile = DeformerTracks.Profile.TREAD
				var mask := Image.create(8, 8, false, Image.FORMAT_RGBA8)
				mask.fill(Color.WHITE)
				track.tread_texture = ImageTexture.create_from_image(mask)
			if variant == "shared_mask":
				track.tread_texture = scene.tracks.tread_texture
			if variant in ["no_tracks", "sled_brushes"]:
				track.set_process(false)
			if variant == "sled_brushes":
				for offset in track.get_wheel_offsets():
					var runner := Deformer.new()
					runner.aspect = 5.0
					runner.radius = track.wheel_width * 0.5 * sqrt(5.0)
					runner.strength = track.strength
					runner.position = Vector3(offset.x, 0, offset.y)
					runner.rotation.y = PI
					track.get_parent().add_child(runner)
					runners.append(runner)
					owners.append(track)
		if variant == "no_shadows":
			for child in scene.get_children():
				if child is DirectionalLight3D:
					child.shadow_enabled = false
		var frames: Array[float] = []
		var simulation: Array[float] = []
		var surface_cpu: Array[float] = []
		var draws: Array[float] = []
		var stamps: Array[float] = []
		var batches: Array[float] = []
		var last := Time.get_ticks_usec()
		for frame in 360:
			var start := Time.get_ticks_usec()
			scene._physics_process(1.0 / 60.0)
			for i in runners.size():
				runners[i].active = owners[i].active
			var sim_ms := (Time.get_ticks_usec() - start) / 1000.0
			await process_frame
			var now := Time.get_ticks_usec()
			if frame >= 90:
				frames.append((now - last) / 1000.0)
				simulation.append(sim_ms)
				draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				var cpu := 0.0
				var count := 0
					var batch_count := 0
				for field in scene.fields:
					var costs: Dictionary = field.get_frame_costs()
					cpu += costs.deformers_ms + costs.queued_ms
					count += field.get_stamps_used()
					batch_count += field.get_active_stamp_batch_count()
				stamps.append(count)
				batches.append(batch_count)
				surface_cpu.append(cpu)
			last = now
		if variant in ["baseline", "optimized", "mobile"]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/ski-%s.png" % variant)
		report[variant] = {"frame_ms": _summary(frames), "simulation_ms": _summary(simulation),
			"surface_cpu_ms": _summary(surface_cpu), "draw_calls": _summary(draws),
			"stamps": _summary(stamps), "active_stamp_batches": _summary(batches)}
		print(variant, ": ", JSON.stringify(report[variant]))
		scene.free()
		await process_frame
	var output := FileAccess.open("res://.godot/ski-profile.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	quit()
