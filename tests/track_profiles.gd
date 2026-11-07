extends SceneTree
## Native regression coverage for smooth/tread batching, boundaries, lift and teleports.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fields: Array[DeformableSurface] = []
	for x in [0.0, 16.0]:
		var field := DeformableSurface.new()
		field.size = 16
		field.position.x = x
		var quality := DeformableSurfaceQuality.new()
		quality.res = 256
		quality.subdiv = 1
		field.quality = quality
		var snow := DeformableSurfaceType.new()
		snow.initial_noise_enabled = false
		snow.recovery_intensity = 0
		field.surface_type = snow
		root.add_child(field)
		field.set_process(false)
		fields.append(field)
	var track := DeformerTracks.new()
	track.preset = DeformerTracks.Preset.CUSTOM
	track.wheel_offsets = PackedVector2Array([Vector2.ZERO])
	track.profile = DeformerTracks.Profile.SMOOTH
	track.wheel_width = 0.05
	root.add_child(track)
	track.set_process(false)
	track.position = Vector3(8, 0, 0)
	track._process(0.016)
	track.position.z = 1.0
	track._process(0.016)
	var failures := 0
	for field in fields:
		if field._pending_stamps.is_empty():
			push_error("Smooth track must overlap both sides of tile boundary")
			failures += 1
		for stamp in field._pending_stamps:
			if not stamp.capsule or stamp.shape != null or stamp.aspect > 8.0:
				push_error("Smooth tracks must be untextured capsules within shader aspect limit")
				failures += 1
		field._prime_frames = 0
		field._process(0.016)
		if field._stamp_batches.size() != 1:
			push_error("Smooth tracks should reuse the default stamp batch")
			failures += 1
		field.reset_trails()
	track.position.y = 4
	track.position.z += 1
	track._process(0.016)
	track.position = Vector3(8, 0, 3)
	track._process(0.016)
	track.position.z += 20
	track._process(0.016)
	for field in fields:
		if not field._pending_stamps.is_empty():
			push_error("Lift/landing/teleport must break track history")
			failures += 1
	track.profile = DeformerTracks.Profile.TREAD
	track.position.z += 0.2
	track._process(0.016)
	# Move back inside the tile and start a fresh tread strip.
	track.position = Vector3.ZERO
	track.reset_path()
	track._process(0.016)
	track.position.z = 0.2
	track._process(0.016)
	if fields[0]._pending_stamps.is_empty() or fields[0]._pending_stamps.back().shape == null:
		push_error("Default tread mode must retain its texture")
		failures += 1
	track.free()
	for field in fields:
		field.free()
	print("Track profiles: %d failures" % failures)
	quit(1 if failures else 0)
