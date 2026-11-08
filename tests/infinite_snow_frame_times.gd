extends SceneTree
## Run headless for CPU regression checks, or without --headless for rendered frames.
## Includes normal scene/actor processing, texture uploads, and frame pacing.
## Writes the samples and environment to .godot/infinite-frame-times.json.


func _initialize() -> void:
	_run.call_deferred()


func _stats(samples: Array[float]) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	return {"median_ms": sorted[sorted.size() / 2],
		"p95_ms": sorted[floori((sorted.size() - 1) * 0.95)],
		"max_ms": sorted.back(), "frames": sorted.size()}


func _run() -> void:
	Engine.max_fps = 120
	var scene = load("res://demos/snow_demo_infinite.tscn").instantiate()
	root.add_child(scene)
	while scene.settings.has_pending_surface_updates():
		await process_frame
	# Warm rendering/actors before measuring; startup is deliberately outside the samples.
	for i in 60:
		await process_frame
	var baseline: Array[float] = []
	var workload: Array[float] = []
	var previous := Time.get_ticks_usec()
	for i in 120:
		await process_frame
		var now := Time.get_ticks_usec()
		baseline.append((now - previous) / 1000.0)
		previous = now
	scene.player.position = Vector3(12.0, 0.0, 4.0)
	scene._run_button = true
	scene.debug_move = Vector2.RIGHT
	var crossed: Dictionary = {}
	for i in 900:
		if i == 180:
			scene.settings.edit_profile("initial_noise_detail", 0.8)
		if i == 300:
			scene.settings.set_quality(0)
		if i == 450:
			scene.debug_move = Vector2.LEFT
		if i == 540:
			scene.settings.set_quality(2)
		await process_frame
		var now := Time.get_ticks_usec()
		workload.append((now - previous) / 1000.0)
		previous = now
		crossed[scene.grid.center_tile] = true
	scene.debug_move = Vector2.ZERO
	var deadline := Time.get_ticks_msec() + 15000
	while scene.settings.has_pending_surface_updates() or scene.grid.has_pending_relocations():
		await process_frame
		if Time.get_ticks_msec() > deadline:
			push_error("Frame benchmark did not drain its settings/recycling queues")
			quit(1)
			return
	var report := {"display_driver": DisplayServer.get_name(), "engine": Engine.get_version_info()["string"],
		"frame_cap": Engine.max_fps, "baseline": _stats(baseline), "movement_and_settings": _stats(workload),
		"distinct_center_tiles": crossed.size(), "samples_ms": workload}
	var file := FileAccess.open("res://.godot/infinite-frame-times.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("Frame benchmark (%s): baseline %s; movement/settings %s; %d center tiles" % [
		report["display_driver"], report["baseline"], report["movement_and_settings"], crossed.size()])
	var failed: bool = crossed.size() < 2 or report["movement_and_settings"]["max_ms"] > maxf(100.0, report["baseline"]["max_ms"] * 5.0)
	if failed:
		push_error("Frame benchmark missed tile crossings or exceeded the stall threshold")
	scene.free()
	quit(1 if failed else 0)
