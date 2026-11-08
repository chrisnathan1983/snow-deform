extends SceneTree

var _contacts := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fields: Array[DeformableSurface] = []
	for tile in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
		var field := DeformableSurface.new()
		field.size = 32.0
		field.position = Vector3(tile.x * 32.0, 0.0, tile.y * 32.0)
		var profile := DeformableSurfaceType.new()
		profile.initial_noise_enabled = false
		profile.recovery_intensity = 0.0
		profile.puffs_enabled = false
		field.surface_type = profile
		var quality := DeformableSurfaceQuality.new()
		quality.res = 128
		quality.subdiv = 1
		field.quality = quality
		root.add_child(field)
		field.set_process(false)
		field.contact.connect(func(_p, _d, _t, _s, _r, _puff): _contacts += 1)
		fields.append(field)
	await _finish_priming(fields)
	var deformer := Deformer.new()
	deformer.puff_on_touchdown = false
	root.add_child(deformer)
	var failures := 0
	for aspect in [1.0, 8.0]:
		deformer.aspect = aspect
		deformer.rotation.y = PI / 4.0
		# Both a near-corner footprint and one centered exactly on the corner
		# must stamp all four tiles and emit a single contact.
		for location in [Vector3(15.9, 0.0, 15.9), Vector3(16.0, 0.0, 16.0)]:
			deformer.position = location
			_contacts = 0
			for field in fields:
				field.reset_trails()
			await _finish_priming(fields)
			for field in fields:
				field._process(0.016)
				if field.get_stamps_used() == 0:
					push_error("Overlapping brush did not stamp a neighbor")
					failures += 1
			if _contacts != 1:
				push_error("Shared footprint emitted %d contacts instead of one" % _contacts)
				failures += 1
			for field in fields:
				field.reset_trails()
				if field.has_deformer_history(deformer):
					push_error("Reset retained old movement history")
					failures += 1
			await _finish_priming(fields)
	# A moving trail must keep affecting both sides throughout a border crossing.
	deformer.aspect = 1.0
	for x in [15.7, 15.9, 16.1, 16.3]:
		deformer.position = Vector3(x, 0.0, 0.0)
		for i in 2:
			var field := fields[i]
			field._mark_deformer_dirty(deformer)
			field._process(0.016)
			if field.get_stamps_used() == 0:
				push_error("Moving trail skipped a tile at the border")
				failures += 1
	deformer.position = Vector3(100.0, 0.0, 100.0)
	for field in fields:
		field._process(0.016)
		if field.get_stamps_used() != 0:
			push_error("Non-overlapping brush stamped a tile")
			failures += 1
	deformer.free()
	for field in fields:
		field.free()
	print("Deformer tile edge/corner checks: %d failures" % failures)
	quit(1 if failures else 0)


func _finish_priming(fields: Array[DeformableSurface]) -> void:
	for field in fields:
		field.set_process(true)
	while true:
		var waiting := false
		for field in fields:
			waiting = waiting or field.is_priming()
		if not waiting:
			break
		await process_frame
	for field in fields:
		field.set_process(false)
