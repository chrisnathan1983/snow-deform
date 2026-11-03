extends Node3D
## Demonstrates a shared weather manager over a recycled grid of DeformableSurfaces.

const DemoCharacter := preload("res://demos/procedural_playground/demo_character.gd")

const TILE_SIZE := 40.0
const TILE_RADIUS := 1
const FIELD_COUNT := (TILE_RADIUS * 2 + 1) * (TILE_RADIUS * 2 + 1)

var _player: DemoCharacter
var _camera: Camera3D
var _sun: DirectionalLight3D
var _distant_ground: MeshInstance3D
var _weather: SnowWorldManager
var _fields: Array[DeformableSurface] = []
var _tiles: Dictionary = {}
var _center_tile := Vector2i.ZERO
var _yaw := 0.0
var _pitch := 0.42
var _camera_distance := 9.0
var _dragging := false
var _hud_label: Label


func _ready() -> void:
	_build_world()
	_build_hud()
	_update_camera(0.0)
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

	_player = DemoCharacter.new()
	_player.name = "Player"
	_player.kind = "explorer"
	_player.role = DemoCharacter.Role.PLAYER
	_player.move_speed = 5.0
	_player.half_extent = 1000000.0
	_player.position = Vector3(0.0, 0.0, 4.0)
	add_child(_player)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.current = true
	_camera.fov = 65.0
	_camera.far = 250.0
	add_child(_camera)

	_weather = SnowWorldManager.new()
	_weather.name = "SnowWorldManager"
	_weather.follow_target = _player
	_weather.fall_height = 12.0
	_weather.emitter_area = Vector2(48.0, 48.0)
	_weather.flake_count = 900
	_weather.near_flake_count = 100
	_weather.snowfall_intensity = 0.45
	_weather.wind = Vector2(0.3, 0.1)
	add_child(_weather)

	_create_field_grid()


func _create_field_grid() -> void:
	var recovery_levels := [0.0, 0.18, 0.4]
	for z in range(-TILE_RADIUS, TILE_RADIUS + 1):
		for x in range(-TILE_RADIUS, TILE_RADIUS + 1):
			var field := DeformableSurface.new()
			field.name = "SnowField_%02d" % _fields.size()
			field.sun = _sun
			field.initial_noise_enabled = false
			field.quality = DeformableSurface.Quality.MEDIUM

			var profile := DeformableSurfaceSettings.new()
			profile.area_size = TILE_SIZE
			profile.res = 256
			profile.subdiv = 64
			profile.recovery_intensity = recovery_levels[posmod(x + z, recovery_levels.size())]
			profile.refill_levels_per_sec = 16.0
			profile.puff = 8
			profile.max_stamps_per_frame = 64
			field.medium_surface_quality = profile

			var tile := Vector2i(x, z)
			field.position = Vector3(tile.x * TILE_SIZE, 0.0, tile.y * TILE_SIZE)
			add_child(field)
			_fields.append(field)
			_tiles[tile] = field


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_hud_label = Label.new()
	_hud_label.position = Vector2(18.0, 16.0)
	_hud_label.add_theme_font_size_override("font_size", 17)
	_hud_label.add_theme_color_override("font_color", Color(0.08, 0.12, 0.2))
	_hud_label.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 1.0, 0.8))
	_hud_label.add_theme_constant_override("shadow_offset_x", 1)
	_hud_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_hud_label)
	_update_hud()


func _process(delta: float) -> void:
	var move := Vector2(
		_key_axis(KEY_D, KEY_RIGHT, KEY_A, KEY_LEFT),
		_key_axis(KEY_S, KEY_DOWN, KEY_W, KEY_UP)
	).limit_length(1.0)
	_player.move_input = Basis(Vector3.UP, _yaw) * Vector3(move.x, 0.0, move.y)
	_player.running = Input.is_key_pressed(KEY_SHIFT)

	_distant_ground.global_position.x = _player.global_position.x
	_distant_ground.global_position.z = _player.global_position.z
	_recenter_fields()
	_update_camera(delta)
	_update_hud()


func _key_axis(positive_a: Key, positive_b: Key, negative_a: Key, negative_b: Key) -> float:
	var positive := 1.0 if Input.is_key_pressed(positive_a) or Input.is_key_pressed(positive_b) else 0.0
	var negative := 1.0 if Input.is_key_pressed(negative_a) or Input.is_key_pressed(negative_b) else 0.0
	return positive - negative


func _recenter_fields() -> void:
	var center := Vector2i(
		floori(_player.global_position.x / TILE_SIZE + 0.5),
		floori(_player.global_position.z / TILE_SIZE + 0.5)
	)
	if center == _center_tile:
		return

	var wanted: Array[Vector2i] = []
	for z in range(-TILE_RADIUS, TILE_RADIUS + 1):
		for x in range(-TILE_RADIUS, TILE_RADIUS + 1):
			wanted.append(center + Vector2i(x, z))

	var next_tiles: Dictionary = {}
	var available := _fields.duplicate()
	for tile in wanted:
		if _tiles.has(tile):
			var field: DeformableSurface = _tiles[tile]
			next_tiles[tile] = field
			available.erase(field)

	for tile in wanted:
		if next_tiles.has(tile):
			continue
		var field := available.pop_back() as DeformableSurface
		field.position = Vector3(tile.x * TILE_SIZE, 0.0, tile.y * TILE_SIZE)
		field.reset_trails()
		next_tiles[tile] = field

	_tiles = next_tiles
	_center_tile = center


func _update_camera(delta: float) -> void:
	var focus := _player.global_position + Vector3(0.0, 1.2, 0.0)
	var offset := Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, -_pitch) * Vector3(0.0, 0.0, _camera_distance)
	var destination := focus + offset
	if delta <= 0.0:
		_camera.global_position = destination
	else:
		_camera.global_position = _camera.global_position.lerp(destination, 1.0 - exp(-10.0 * delta))
	_camera.look_at(focus, Vector3.UP)


func _update_hud() -> void:
	if not is_instance_valid(_hud_label):
		return
	var tile := Vector2i(
		floori(_player.global_position.x / TILE_SIZE + 0.5),
		floori(_player.global_position.z / TILE_SIZE + 0.5)
	)
	_hud_label.text = (
		"INFINITE SNOW  |  %d independent fields  |  1 shared weather manager\n"
		+ "WASD / arrows move   Shift run   Space jump   Right-drag look   Wheel zoom   R reset\n"
		+ "Recycled tile center: (%d, %d)   |   Surface recovery varies per field"
	) % [FIELD_COUNT, tile.x, tile.y]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_SPACE:
				_player.jump()
			elif key.keycode == KEY_R:
				for field in _fields:
					field.reset_trails()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_camera_distance = maxf(_camera_distance - 0.8, 4.0)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_camera_distance = minf(_camera_distance + 0.8, 22.0)
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = button.pressed
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * 0.006
		_pitch = clampf(_pitch + motion.relative.y * 0.005, 0.08, 1.25)
