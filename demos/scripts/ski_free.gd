extends Node3D
## An endless arcade slope. +Z is downhill (toward the bottom of the screen).
## Snow tiles and scenery are pooled; the two ski ribbons use real deformation.

const Props := preload("res://demos/scripts/demo_props.gd")
const SNOW_QUALITY := preload("res://demos/resources/powder_run/quality.tres")
const SNOW_PROFILE := preload("res://demos/resources/powder_run/snow_profile.tres")
const SlopeGuest := preload("res://demos/scripts/slope_guest.gd")
const TILE_SIZE := 40.0
const COURSE_LENGTH := 144.0
const HALF_WIDTH := 25.0

## Exposed for native A/B profiling; normal gameplay keeps scenery batched.
@export var batch_scenery := true
## Mobile-first lighting; the expensive original is retained only for native A/B tests.
@export var mobile_lighting := true

var skier: Node3D
var visual: Node3D
var skier_shadow: MeshInstance3D
var tracks: DeformerTracks
var camera: Camera3D
var fields: Array[DeformableSurface] = []
var snow_grid: DeformableSurfaceGrid
var obstacles: Array[Node3D] = []
var gates: Array[Node3D] = []
var guests: Array[SlopeGuest] = []
var rng := RandomNumberGenerator.new()
var speed := 0.0
var heading := 0.0
var vertical_speed := 0.0
var crash_time := 0.0
var invincible := 0.0
var score := 0
var combo := 0
var crashes := 0
var paused := false
var message_time := 0.0
var stats: Label
var message: Label
var pause_button: Button
var touch_sticks: TouchSticks
var touch_jump: TouchScreenButton
var _touch_ui: Control
var _hint: Label
var _touch_blockers: Array[Control] = []


func _ready() -> void:
	rng.seed = 78421
	var nav := DemoNav.attach(self)
	for child in nav.get_children():
		if child is Button:
			_touch_blockers.append(child)
	_build_world()
	_build_skier()
	snow_grid.follow_target = skier
	_build_course()
	if batch_scenery:
		_batch_scenery()
	_build_guests()
	_build_hud()
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	_update_camera()
	_flash("FRESH POWDER  /  Find your line", 4.0)


func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("dbeaf2")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c7ddec")
	environment.ambient_light_energy = 0.55 if mobile_lighting else 0.45
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_color = Color("fff0da")
	sun.light_energy = 0.65 if mobile_lighting else 0.75
	sun.shadow_enabled = not mobile_lighting
	sun.directional_shadow_max_distance = 110.0
	add_child(sun)
	var snow := SNOW_PROFILE
	if mobile_lighting:
		snow = SNOW_PROFILE.duplicate() as DeformableSurfaceType
		var snow_material := snow.material.duplicate() as ShaderMaterial
		# Matte powder with enough headroom for the terrain's highlights and berms.
		snow_material.set_shader_parameter("surface_color", Color("e2edf3"))
		snow_material.set_shader_parameter("specular_amount", 0.0)
		snow_material.set_shader_parameter("sparkle_strength", 0.0)
		snow_material.set_shader_parameter("normal_strength", 4.0)
		snow_material.set_shader_parameter("disturbed_darkening", 0.06)
		snow.material = snow_material
	snow_grid = DeformableSurfaceGrid.new()
	snow_grid.name = "SurfaceGrid"
	snow_grid.tile_size = TILE_SIZE
	snow_grid.quality = SNOW_QUALITY
	snow_grid.surface_type = snow
	snow_grid.sun = sun
	snow_grid.follow_x = false
	snow_grid.follow_offset = Vector3(0.0, 0.0, 8.0)
	snow_grid.prefetch_distance = 0.0
	snow_grid.relocations_per_frame = 9
	add_child(snow_grid)
	snow_grid.set_process(false)
	fields = snow_grid.fields
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 37.0
	camera.far = 180.0
	camera.current = true
	add_child(camera)


func _build_skier() -> void:
	skier = Node3D.new()
	skier.name = "Skier"
	add_child(skier)
	visual = Node3D.new()
	skier.add_child(visual)
	var navy := Color("203450")
	var coral := Color("f04f65")
	for side in [-1.0, 1.0]:
		Props.add_mesh(visual, Props.box(Vector3(0.21, 0.09, 2.1)), Color("ffd05a"), Vector3(side * 0.32, 0.05, 0))
		Props.add_mesh(visual, Props.box(Vector3(0.21, 0.09, 0.32)), coral, Vector3(side * 0.32, 0.12, 1.08), Vector3.ONE, Vector3(-24, 0, 0))
		Props.add_mesh(visual, Props.box(Vector3(0.22, 0.25, 0.43)), navy, Vector3(side * 0.32, 0.2, 0))
		Props.add_mesh(visual, Props.capsule(0.14, 0.6), navy, Vector3(side * 0.24, 0.59, -0.07), Vector3.ONE, Vector3(-18, 0, side * 12))
		Props.add_mesh(visual, Props.capsule(0.13, 0.62), coral, Vector3(side * 0.47, 1.05, 0.14), Vector3.ONE, Vector3(25, 0, side * 30))
		Props.add_mesh(visual, Props.cylinder(0.025, 1.2), navy, Vector3(side * 0.65, 0.55, -0.16), Vector3.ONE, Vector3(28, 0, side * -12))
	Props.add_mesh(visual, Props.capsule(0.32, 0.8), coral, Vector3(0, 1.0, 0.02), Vector3(1, 1, 0.8), Vector3(12, 0, 0))
	Props.add_mesh(visual, Props.sphere(0.28), Color("ffe0bd"), Vector3(0, 1.53, 0.16))
	Props.add_mesh(visual, Props.sphere(0.3), Color("21b9c5"), Vector3(0, 1.66, 0.13), Vector3(1, 0.75, 1))
	Props.add_mesh(visual, Props.box(Vector3(0.46, 0.13, 0.12)), navy, Vector3(0, 1.56, 0.4))
	tracks = DeformerTracks.new()
	tracks.preset = DeformerTracks.Preset.CUSTOM
	tracks.wheel_offsets = PackedVector2Array([Vector2(-0.32, -0.3), Vector2(0.32, -0.3)])
	tracks.wheel_width = 0.24
	tracks.strength = 0.85
	tracks.profile = DeformerTracks.Profile.SMOOTH
	skier.add_child(tracks)
	if mobile_lighting:
		skier_shadow = BlobShadow.make(1.8, true)
		skier.add_child(skier_shadow)


func _build_guests() -> void:
	var colors := [Color("9561d9"), Color("28a8bd"), Color("ef913e"), Color("75b94c"), Color("e970ad")]
	for i in 10:
		var guest := SlopeGuest.new()
		guest.name = "SlopeGuest_%02d" % i
		guest.index = i
		guest.kind = SlopeGuest.Kind.SKIER if i < 6 else SlopeGuest.Kind.BOARDER
		if i == 8:
			guest.kind = SlopeGuest.Kind.SLED
		elif i == 9:
			guest.kind = SlopeGuest.Kind.PENGUIN
		guest.tint = colors[i % colors.size()]
		guest.use_blob_shadow = mobile_lighting
		guest.lane = -18.0 + (i % 5) * 9.0
		guest.cruise_speed = 9.0 + (i % 4) * 2.5
		guest.phase = i * 1.7
		guest.position = Vector3(guest.lane, 0, -12.0 + (i * 7) % 35)
		add_child(guest)
		guests.append(guest)


func _build_course() -> void:
	for i in 76:
		var obstacle := Node3D.new()
		var kind := "tree" if i % 4 != 0 else "rock"
		if i % 13 == 0:
			kind = "jump"
		obstacle.set_meta("kind", kind)
		obstacle.set_meta("radius", 1.05 if kind == "tree" else 1.3)
		add_child(obstacle)
		if kind == "tree":
			Props.add_mesh(obstacle, Props.cylinder(0.19, 1.0), Color("795443"), Vector3(0, 0.5, 0))
			for tier in 3:
				var radius := 1.45 - tier * 0.34
				var height := 1.7 + tier * 0.85
				Props.add_mesh(obstacle, Props.cone(radius, 2.0), Color("19756b"), Vector3(0, height, 0))
				Props.add_mesh(obstacle, Props.cone(radius * 0.72, 1.25), Color("e6f2f5"), Vector3(0, height + 0.4, 0))
		elif kind == "rock":
			Props.add_mesh(obstacle, Props.sphere(1.0, 7), Color("76879a"), Vector3(0, 0.35, 0), Vector3(1.2, 0.65, 0.9))
			Props.add_mesh(obstacle, Props.sphere(0.8, 7), Color("e6f2f5"), Vector3(0, 0.7, 0), Vector3(1.1, 0.3, 0.8))
		else:
			Props.add_mesh(obstacle, Props.box(Vector3(2.6, 0.35, 2.0)), Color("90c4d4"), Vector3(0, 0.22, 0), Vector3.ONE, Vector3(-14, 0, 0))
			Props.add_mesh(obstacle, Props.box(Vector3(2.6, 0.05, 0.22)), Color("ffd05a"), Vector3(0, 0.62, 0.8))
		if mobile_lighting:
			obstacle.add_child(BlobShadow.make(3.4 if kind == "tree" else 2.5, true))
		_place_obstacle(obstacle, 15.0 + i * COURSE_LENGTH / 76.0)
		obstacles.append(obstacle)
	for i in 6:
		var gate := Node3D.new()
		add_child(gate)
		var color := Color("f04f65") if i % 2 == 0 else Color("238db6")
		for side in [-1.0, 1.0]:
			Props.add_mesh(gate, Props.cylinder(0.045, 2.1), color, Vector3(side * 3.0, 1.05, 0))
			Props.add_mesh(gate, Props.box(Vector3(0.9, 0.5, 0.04)), color, Vector3(side * 3.45, 1.65, 0))
		_place_gate(gate, 26.0 + i * 24.0)
		gates.append(gate)


func _gate_x(z: float) -> float:
	return sin(z * 0.042) * 12.0


func _place_obstacle(obstacle: Node3D, z: float) -> void:
	var x := rng.randf_range(-HALF_WIDTH, HALF_WIDTH)
	# Keep each gate's approach clear; the remaining slope is free-form skiing.
	var nearest_gate_z := roundf((z - 26.0) / 24.0) * 24.0 + 26.0
	if absf(z - nearest_gate_z) < 5.0 and absf(x - _gate_x(nearest_gate_z)) < 5.0:
		x = clampf(_gate_x(nearest_gate_z) + (8.0 if x >= _gate_x(nearest_gate_z) else -8.0), -HALF_WIDTH, HALF_WIDTH)
	obstacle.position = Vector3(x, 0, z)
	for slot in obstacle.get_meta("draw_slots", []):
		var multimesh: MultiMesh = slot.multimesh
		multimesh.set_instance_transform(slot.index, obstacle.transform * slot.local_transform)


func _batch_scenery() -> void:
	# One draw per repeated mesh part, rather than one per part per tree (plus shadows).
	# Logical obstacle nodes remain independent for AI, collisions, and recycling.
	var groups := {}
	for obstacle in obstacles:
		var part := 0
		for child in obstacle.get_children():
			if not child is MeshInstance3D:
				continue
			var key := "%s_%d" % [obstacle.get_meta("kind"), part]
			if not groups.has(key):
				groups[key] = []
			groups[key].append({"obstacle": obstacle, "mesh": child})
			part += 1
	for key in groups:
		var parts: Array = groups[key]
		var first: MeshInstance3D = parts[0].mesh
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = first.mesh
		multimesh.instance_count = parts.size()
		var renderer := MultiMeshInstance3D.new()
		renderer.name = "Scenery_" + key
		renderer.multimesh = multimesh
		renderer.material_override = first.material_override
		renderer.cast_shadow = first.cast_shadow
		add_child(renderer)
		for i in parts.size():
			var obstacle: Node3D = parts[i].obstacle
			var mesh: MeshInstance3D = parts[i].mesh
			multimesh.set_instance_transform(i, obstacle.transform * mesh.transform)
			var slots: Array = obstacle.get_meta("draw_slots", [])
			slots.append({"multimesh": multimesh, "index": i, "local_transform": mesh.transform})
			obstacle.set_meta("draw_slots", slots)
			mesh.queue_free()


func _place_gate(gate: Node3D, z: float) -> void:
	gate.position = Vector3(_gate_x(z), 0, z)
	gate.set_meta("passed", false)


func _physics_process(delta: float) -> void:
	if paused:
		return
	var steer := float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	steer = clampf(steer + touch_sticks.move.x, -1.0, 1.0)
	var braking := touch_sticks.move.y < -0.35 or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_UP)
	var tuck := touch_sticks.move.y > 0.35 or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_DOWN)
	invincible = maxf(0, invincible - delta)
	crash_time = maxf(0, crash_time - delta)
	if crash_time > 0:
		speed = move_toward(speed, 0, delta * 22.0)
	else:
		heading = move_toward(heading, steer * 1.12, delta * 2.7)
		var target_speed := (21.0 if tuck else 15.0) * lerpf(1.0, 0.5, absf(heading) / 1.12)
		if braking:
			target_speed = 3.0
		speed = move_toward(speed, target_speed, delta * (14.0 if braking else 4.0))
	var previous := skier.position
	skier.position += Vector3(sin(heading), 0, cos(heading)) * speed * delta
	skier.position.x = clampf(skier.position.x, -HALF_WIDTH, HALF_WIDTH)
	if skier.position.y > 0 or vertical_speed > 0:
		vertical_speed -= delta * 18.0
		skier.position.y = maxf(0, skier.position.y + vertical_speed * delta)
		if skier.position.y == 0:
			vertical_speed = 0
	skier.rotation.y = heading
	if skier_shadow != null:
		skier_shadow.position.y = 0.04 - skier.position.y
	visual.rotation.z = lerpf(visual.rotation.z, -steer * 0.22 if crash_time <= 0 else 1.4, 1.0 - exp(-12.0 * delta))
	visual.visible = invincible <= 0 or int(invincible * 12) % 2 == 0
	tracks.active = skier.position.y < 0.05 and crash_time <= 0
	_check_course(previous)
	snow_grid.update_tiles()
	for guest in guests:
		guest.advance(delta, skier, obstacles, guests)
	_update_camera()
	message_time = maxf(0, message_time - delta)
	message.visible = message_time > 0
	stats.text = "%04d m     %02d km/h     %d pts\nGATES  x%d     WIPEOUTS  %d" % [int(skier.position.z), int(speed * 3.6), score, combo, crashes]


func _check_course(previous: Vector3) -> void:
	for obstacle in obstacles:
		if obstacle.position.z < skier.position.z - 32.0:
			_place_obstacle(obstacle, obstacle.position.z + COURSE_LENGTH)
		var offset := Vector2(skier.position.x - obstacle.position.x, skier.position.z - obstacle.position.z)
		if offset.length() > float(obstacle.get_meta("radius")) + 0.35:
			continue
		var kind: String = obstacle.get_meta("kind")
		if kind == "jump":
			if skier.position.y == 0 and speed > 6.0 and crash_time <= 0:
				_jump(9.0)
				_flash("AIR TIME!", 1.0)
		elif invincible <= 0 and skier.position.y < (3.5 if kind == "tree" else 0.95):
			crash_time = 1.1
			invincible = 2.6
			combo = 0
			crashes += 1
			_flash("WIPEOUT!  /  Back on your skis…", 1.5)
	for gate in gates:
		if not gate.get_meta("passed") and previous.z < gate.position.z and skier.position.z >= gate.position.z:
			gate.set_meta("passed", true)
			var fraction := (gate.position.z - previous.z) / maxf(0.001, skier.position.z - previous.z)
			var crossing_x := lerpf(previous.x, skier.position.x, fraction)
			if absf(crossing_x - gate.position.x) < 2.8 and crash_time <= 0:
				combo += 1
				score += 100 * mini(combo, 5)
				_flash("CLEAN GATE  +%d" % (100 * mini(combo, 5)), 1.4)
			else:
				combo = 0
				_flash("MISSED GATE  /  Catch the next one", 1.4)
		if gate.position.z < skier.position.z - 32.0:
			_place_gate(gate, gate.position.z + COURSE_LENGTH)


func _update_camera() -> void:
	var focus := Vector3(skier.position.x * 0.35, 0, skier.position.z + 8.0)
	camera.position = focus + Vector3(0, 36, 27)
	camera.look_at(focus)


func _jump(impulse := 7.0) -> void:
	if not paused and skier.position.y == 0 and crash_time <= 0:
		vertical_speed = impulse
		tracks.active = false
		tracks.reset_path()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: _jump()
			KEY_P: _toggle_pause()
			KEY_R: get_tree().reload_current_scene()


func _toggle_pause() -> void:
	paused = not paused
	_cancel_touch_input()
	touch_sticks.set_process_input(not paused)
	for guest in guests:
		guest.set_paused(paused)
	tracks.active = not paused and skier.position.y < 0.05 and crash_time <= 0
	pause_button.text = "Resume (P)" if paused else "Pause (P)"
	if paused:
		message.text = "PAUSED  /  Take a breath"
		message.visible = true
	else:
		_flash("FIND YOUR LINE", 1.0)


func _flash(text: String, duration: float) -> void:
	message.text = text
	message_time = duration
	message.visible = true


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var title := _label("POWDER RUN\nSLOPE FRIENDS / 10", 27)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	stats = _label("", 22)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(stats)
	message = _label("", 20)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	message.offset_top = 104
	message.offset_left = 24
	message.offset_right = -24
	layer.add_child(message)
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 180
	bottom.offset_right = -24
	bottom.offset_top = -64
	bottom.offset_bottom = -18
	layer.add_child(bottom)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(buttons)
	pause_button = _button("Pause (P)", _toggle_pause)
	buttons.add_child(pause_button)
	var restart := _button("New run (R)", func(): get_tree().reload_current_scene())
	buttons.add_child(restart)
	_touch_blockers.append_array([pause_button, restart])
	_hint = _label("A/D or ←/→ steer   W/↓ tuck   S/↑ brake   SPACE jump", 15)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom.add_child(_hint)

	touch_sticks = TouchSticks.new()
	touch_sticks.look_enabled = false
	touch_sticks.is_blocked = _over_touch_ui
	layer.add_child(touch_sticks)
	_touch_ui = Control.new()
	_touch_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_touch_ui.visible = OS.has_feature("web") or OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
	layer.add_child(_touch_ui)
	var instruction := _label("Drag left side to steer\nForward: brake / Back: tuck", 18)
	instruction.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	instruction.offset_left = 24
	instruction.offset_top = -200
	_touch_ui.add_child(instruction)
	var jump_area := Control.new()
	jump_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jump_area.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	jump_area.offset_left = -140
	jump_area.offset_right = -24
	jump_area.offset_top = -200
	jump_area.offset_bottom = -104
	_touch_ui.add_child(jump_area)
	_touch_blockers.append(jump_area)
	var jump_visual := _button("JUMP", func(): pass)
	jump_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jump_visual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	jump_area.add_child(jump_visual)
	# Native touch input lets a second finger jump while the joystick is held.
	touch_jump = TouchScreenButton.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(116, 96)
	touch_jump.shape = shape
	touch_jump.position = shape.size * 0.5
	touch_jump.pressed.connect(func():
		jump_visual.set_pressed_no_signal(true)
		_jump())
	touch_jump.released.connect(func(): jump_visual.set_pressed_no_signal(false))
	jump_area.add_child(touch_jump)


func _over_touch_ui(point: Vector2) -> bool:
	for control in _touch_blockers:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(point):
			return true
	return false


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_touch_ui.show()
		_hint.hide()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT] and is_instance_valid(touch_jump):
		_cancel_touch_input()


func _cancel_touch_input() -> void:
	touch_sticks.cancel()
	# Hiding also releases a native touch button whose finger was interrupted.
	touch_jump.hide()
	touch_jump.visible = not paused


func _update_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	camera.keep_aspect = Camera3D.KEEP_WIDTH if viewport_size.x < viewport_size.y else Camera3D.KEEP_HEIGHT
	_cancel_touch_input()
	_hint.visible = not _touch_ui.visible


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("203450"))
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(112, 36)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button
