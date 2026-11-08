extends Node3D
## Demonstrates a shared weather manager over a recycled grid of DeformableSurfaces.

const DemoCharacter := preload("res://demos/scripts/demo_character.gd")

const TILE_SIZE := 40.0
const QUALITY_PRESETS: Array[DeformableSurfaceQuality] = [
	preload("res://demos/resources/infinite_snow/low.tres"),
	preload("res://demos/resources/infinite_snow/medium.tres"),
	preload("res://demos/resources/infinite_snow/high.tres"),
]
const WEATHER := preload("res://demos/resources/infinite_snow/weather.tres")

var _player: DemoCharacter
var _camera: DemoCamera
var _sun: DirectionalLight3D
var _distant_ground: MeshInstance3D
var _weather: SnowWorldManager
var _grid: DeformableSurfaceGrid
var _dragging := false
var _hud: DemoHud
var _settings: DemoSettings
var _hud_t := 0.0
var _sticks: TouchSticks
var _shell: DemoShell
var _run_button := false


func _ready() -> void:
	_shell = DemoShell.attach(self, true)
	_build_world()
	_build_hud()
	_camera.update_view()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.22, 0.36, 0.58)
	sky_material.sky_horizon_color = Color(0.78, 0.86, 0.96)
	sky_material.ground_horizon_color = Color(0.78, 0.86, 0.96)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.8, 0.96)
	environment.ambient_light_energy = 0.7
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.78, 0.86, 0.96)
	environment.fog_density = 0.006
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	_sun.light_color = Color(1.0, 0.94, 0.84)
	_sun.light_energy = 0.9
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 90.0
	add_child(_sun)

	_distant_ground = MeshInstance3D.new()
	_distant_ground.name = "DistantSnow"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(1200.0, 1200.0)
	_distant_ground.mesh = ground_mesh
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.82, 0.88, 0.96)
	ground_material.roughness = 1.0
	_distant_ground.material_override = ground_material
	_distant_ground.position.y = -0.12
	_distant_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_distant_ground)

	_player = (load("res://demos/characters/explorer.tscn") as PackedScene).instantiate() as DemoCharacter
	_player.name = "Player"
	_player.kind = "explorer"
	_player.role = DemoCharacter.Role.PLAYER
	_player.move_speed = 5.0
	_player.half_extent = 1000000.0
	_player.position = Vector3(0.0, 0.0, 4.0)
	add_child(_player)

	_camera = DemoCamera.new()
	_camera.auto_update = false
	_camera.follow_target = _player
	_camera.focus_offset = Vector3(0.0, 1.2, 0.0)
	_camera.follow_speed = 10.0
	_camera.distance = 9.0
	_camera.pitch_limits = Vector2(0.08, 1.25)
	_camera.distance_limits = Vector2(4.0, 22.0)
	_camera.name = "Camera3D"
	_camera.current = true
	_camera.fov = 65.0
	_camera.far = 250.0
	add_child(_camera)

	_weather = SnowWorldManager.new()
	_weather.name = "SnowWorldManager"
	_weather.weather_settings = WEATHER
	add_child(_weather)
	_weather.follow_target = _player

	_create_field_grid()


func _create_field_grid() -> void:
	_grid = DeformableSurfaceGrid.new()
	_grid.name = "SurfaceGrid"
	_grid.tile_size = TILE_SIZE
	_grid.quality = QUALITY_PRESETS[1]
	_grid.sun = _sun
	_grid.follow_target = _player
	_grid.prefetch_distance = 0.0
	_grid.relocations_per_frame = 9
	_grid.surface_for_tile = _surface_for_tile
	add_child(_grid)


func _surface_for_tile(tile: Vector2i) -> DeformableSurfaceType:
	var recovery_levels := [0.0, 0.18, 0.4]
	var profile := DemoSettings.SNOW_PROFILE.duplicate() as DeformableSurfaceType
	profile.recovery_intensity = recovery_levels[posmod(tile.x + tile.y, recovery_levels.size())]
	profile.initial_noise_enabled = false
	return profile


func _build_hud() -> void:
	_hud = _shell.hud
	_hud.set_title("Infinite Snow")
	_settings = _shell.bind_surfaces(_grid.fields)
	_grid.relocation_blocked = _settings.has_pending_surface_updates
	_settings.quality_presets = QUALITY_PRESETS
	_settings.add_surface_tab()
	_settings.add_weather_tab(_weather)
	_settings.add_graphics_tab(_sun)
	_sticks = _shell.sticks
	_hud.changed.connect(_on_hud_changed)
	_hud.set_hint("WASD / arrows move | Shift run | Space jump | right-drag look | wheel zoom | R reset | M menu", 12.0)
	_update_hud()


func _process(delta: float) -> void:
	var move := Vector2(
		_key_axis(KEY_D, KEY_RIGHT, KEY_A, KEY_LEFT),
		_key_axis(KEY_S, KEY_DOWN, KEY_W, KEY_UP)
	)
	if _sticks:
		move += _sticks.move
		_camera.apply_stick(_sticks.look, delta)
	move = move.limit_length(1.0)
	_player.move_input = Basis(Vector3.UP, _camera.yaw) * Vector3(move.x, 0.0, move.y)
	_player.running = Input.is_key_pressed(KEY_SHIFT) or _run_button

	_distant_ground.global_position.x = _player.global_position.x
	_distant_ground.global_position.z = _player.global_position.z
	_camera.update_view(delta)
	_hud_t -= delta
	if _hud_t <= 0.0:
		_hud_t = 0.4
		_update_hud()


func _on_hud_changed(key: String, value: Variant) -> void:
	match key:
		"jump": _player.jump()
		"run": _run_button = bool(value)


func _key_axis(positive_a: Key, positive_b: Key, negative_a: Key, negative_b: Key) -> float:
	var positive := 1.0 if Input.is_key_pressed(positive_a) or Input.is_key_pressed(positive_b) else 0.0
	var negative := 1.0 if Input.is_key_pressed(negative_a) or Input.is_key_pressed(negative_b) else 0.0
	return positive - negative


func _update_hud() -> void:
	if not is_instance_valid(_hud):
		return
	var tile := _grid.tile_at(_player.global_position)
	_hud.set_info("%d FPS  |  %d fields  |  tile (%d, %d)" % [
		Engine.get_frames_per_second(), _grid.fields.size(), tile.x, tile.y])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_SPACE:
				_player.jump()
			elif key.keycode == KEY_R:
				for field in _grid.fields:
					field.reset_trails()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_camera.zoom(-0.8)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_camera.zoom(0.8)
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = button.pressed and button.position.x >= get_viewport().get_visible_rect().size.x * 0.5
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_camera.drag(motion.relative)
