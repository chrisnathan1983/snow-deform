extends "res://demos/procedural_playground/snow_demo.gd"
## Procedural playground variant with a recycled, fence-free DeformableSurface grid.

const TILE_RADIUS := 1

var _tiles: Dictionary = {}
var _center_tile := Vector2i.ZERO
var _pending_relocations: Array[Dictionary] = []


func _make_quality_presets() -> Array[DeformableSurfaceQuality]:
	return [_make_profile(192, 48, 4, 0.3, 64), _make_profile(256, 64, 8, 1.0, 96),
			_make_profile(320, 80, 12, 1.5, 128)]


func _build_snow() -> void:
	_quality_presets = _make_quality_presets()
	_quality = DeformableSurfaceQuality.platform_tier()
	for z in range(-TILE_RADIUS, TILE_RADIUS + 1):
		for x in range(-TILE_RADIUS, TILE_RADIUS + 1):
			var tile := Vector2i(x, z)
			var field := DeformableSurface.new()
			field.name = "SnowField_%d_%d" % [x, z]
			field.sun = sun
			field.size = FIELD_SIZE
			field.surface_type = _make_surface_type()
			field.quality = _quality_presets[_quality]
			field.position = Vector3(x * FIELD_SIZE, 0.0, z * FIELD_SIZE)
			add_child(field)
			snow_fields.append(field)
			_tiles[tile] = field
			if tile == Vector2i.ZERO:
				snow = field


func _build_actors() -> void:
	#super._build_actors()
	player = _make_character("explorer", DemoCharacter.Role.PLAYER)
	player.position = Vector3(0, 0, 4.0)
	player.obstacles = _obstacles
	add_child(player)

	# weather follows the player
	weather = SnowWorldManager.new()
	weather.name = "SnowWorldManager"
	weather.weather_settings = _make_weather_profile(_quality)
	add_child(weather)
	weather.follow_target = player
	sled = (load("res://demos/common/props/sled.tscn") as PackedScene).instantiate() as DemoSled
	add_child(sled)

	# torso centre on the snow surface; yaw = rotation around Y, head points along -Z
	var x := 5.0
	var z := 5.0
	var yaw := 0.0
	_snowangel = Snowangel.make(self, Vector3(x, 0.0, z), yaw)
	_snowangel.cycles = 10
	#await _snowangel.finished    # limbs have finished sweeping; the node then frees itself

	_yeti = _make_character("yeti", DemoCharacter.Role.WANDERER)
	_yeti.circle_center = Vector3(-2.0, 0, -10.5)
	_yeti.circle_radius = 3.2
	add_child(_yeti)

	# var prev: Node3D = player
	# for i in 3:
	#     var pg := _make_character("penguin", DemoCharacter.Role.FOLLOWER)
	#     pg.follow_target = prev
	#     pg.follow_distance = 1.1 + 0.1 * float(i)
	#     pg.obstacles = _obstacles
	#     pg.position = Vector3(0.4 * float(i + 1) - 1.0, 0, 5.8 + 0.9 * float(i))
	#     add_child(pg)
	#     _penguins.append(pg)
	#     prev = pg

	var cols := [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.95), Color(0.95, 0.6, 0.1),
			Color(0.2, 0.75, 0.4), Color(0.8, 0.3, 0.85), Color(0.95, 0.85, 0.2)]
	for i in 6:
		var b := (load("res://demos/common/props/ball.tscn") as PackedScene).instantiate() as DemoBall
		b.kind = DemoBall.Kind.BOUNCER
		b.radius = _rng.randf_range(0.3, 0.45)
		b.color = cols[i]
		b.half = HALF - 1.5
		b.bounce_speed = _rng.randf_range(6.5, 9.0)
		var ang := _rng.randf() * TAU
		b.velocity = Vector3(cos(ang), 0, sin(ang)) * _rng.randf_range(1.5, 4.0)
		b.position = Vector3(_rng.randf_range(-10, 10), b.radius + _rng.randf() * 2.0, _rng.randf_range(-10, 10))
		add_child(b)
		_balls.append(b)
	player.half_extent = 1000000.0


func _has_fence() -> bool:
	return false


func _constrain_target(target: Vector3, _margin: float) -> Vector3:
	return target


func _process(delta: float) -> void:
	super._process(delta)
	_ground.global_position.x = player.global_position.x
	_ground.global_position.z = player.global_position.z
	_recenter_fields()


func _recenter_fields() -> void:
	var center := Vector2i(
		floori(player.global_position.x / FIELD_SIZE + 0.5),
		floori(player.global_position.z / FIELD_SIZE + 0.5)
	)
	if center != _center_tile:
		_queue_recenter(center)

	if not _pending_relocations.is_empty():
		var relocation: Dictionary = _pending_relocations.pop_front()
		var field := relocation["field"] as DeformableSurface
		var tile: Vector2i = relocation["tile"]
		var old_tile := Vector2i(
			roundi(field.position.x / FIELD_SIZE),
			roundi(field.position.z / FIELD_SIZE)
		)
		_tiles.erase(old_tile)
		field.position = Vector3(tile.x * FIELD_SIZE, 0.0, tile.y * FIELD_SIZE)
		field.reset_trails()
		_tiles[tile] = field


func _queue_recenter(center: Vector2i) -> void:
	var wanted: Array[Vector2i] = []
	for z in range(-TILE_RADIUS, TILE_RADIUS + 1):
		for x in range(-TILE_RADIUS, TILE_RADIUS + 1):
			wanted.append(center + Vector2i(x, z))

	_tiles.clear()
	for field in snow_fields:
		var tile := Vector2i(
			roundi(field.position.x / FIELD_SIZE),
			roundi(field.position.z / FIELD_SIZE)
		)
		_tiles[tile] = field

	var next_tiles: Dictionary = {}
	var available := snow_fields.duplicate()
	for tile in wanted:
		if _tiles.has(tile):
			var field: DeformableSurface = _tiles[tile]
			next_tiles[tile] = field
			available.erase(field)

	_pending_relocations.clear()
	for tile in wanted:
		if next_tiles.has(tile):
			continue
		var field := available.pop_back() as DeformableSurface
		_pending_relocations.append({"field": field, "tile": tile})

	_center_tile = center
