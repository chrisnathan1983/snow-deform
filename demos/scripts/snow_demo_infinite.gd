extends "res://demos/scripts/snow_demo.gd"
## Procedural playground variant with a recycled, fence-free DeformableSurface grid.

const TILE_RADIUS := 1
const PREFETCH_DISTANCE := 8.0
const TILE_QUALITY_PRESETS: Array[DeformableSurfaceQuality] = [
	preload("res://demos/resources/snow_lab_infinite/low.tres"),
	preload("res://demos/resources/snow_lab_infinite/medium.tres"),
	preload("res://demos/resources/snow_lab_infinite/high.tres"),
]

var _tiles: Dictionary = {}
var _center_tile := Vector2i.ZERO
var _pending_relocations: Array[Dictionary] = []
var _prefetch_relocations: Array[Dictionary] = []
var _prefetch_center := Vector2i.ZERO
var _prefetch_index := 0
var _last_player_position := Vector3.ZERO
var _travel_direction := Vector3.ZERO
var _has_player_sample := false


func _build_snow() -> void:
	_quality_presets = TILE_QUALITY_PRESETS
	var profile := _snow_profile()
	for z in range(-TILE_RADIUS, TILE_RADIUS + 1):
		for x in range(-TILE_RADIUS, TILE_RADIUS + 1):
			var tile := Vector2i(x, z)
			var field := DeformableSurface.new()
			field.name = "SnowField_%d_%d" % [x, z]
			field.sun = sun
			field.size = FIELD_SIZE
			field.surface_type = profile
			field.quality = _quality_presets[_quality]
			field.position = Vector3(x * FIELD_SIZE, 0.0, z * FIELD_SIZE)
			add_child(field)
			snow_fields.append(field)
			_tiles[tile] = field
			if tile == Vector2i.ZERO:
				snow = field


func _actor_half_extent() -> float:
	return 1000000.0


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
	var player_position := to_local(player.global_position)
	if _has_player_sample:
		var movement := player_position - _last_player_position
		movement.y = 0.0
		if movement.length_squared() > 0.000001:
			_travel_direction = movement.normalized()
	_last_player_position = player_position
	_has_player_sample = true
	# Settings and relocation share each field's noise worker/cache. Finish a settings
	# batch before requesting another destination so the two queues cannot compete.
	if settings != null and settings.has_pending_surface_updates():
		_prefetch_relocations.clear()
		_prefetch_index = 0
		return
	var center := Vector2i(
		floori(player_position.x / FIELD_SIZE + 0.5),
		floori(player_position.z / FIELD_SIZE + 0.5)
	)
	if center != _center_tile:
		_queue_recenter(center)

	if not _pending_relocations.is_empty():
		var relocation: Dictionary = _pending_relocations.front()
		var field := relocation["field"] as DeformableSurface
		var tile: Vector2i = relocation["tile"]
		var destination := Vector3(tile.x * FIELD_SIZE, 0.0, tile.y * FIELD_SIZE)
		if not field.prepare_initial_noise_at(to_global(destination)):
			return
		_pending_relocations.pop_front()
		var old_tile := Vector2i(
			roundi(field.position.x / FIELD_SIZE),
			roundi(field.position.z / FIELD_SIZE)
		)
		_tiles.erase(old_tile)
		field.position = destination
		field.reset_trails()
		_tiles[tile] = field
		return

	_prefetch_fields(player_position)


func _prefetch_fields(player_position: Vector3) -> void:
	var ahead := player_position + _travel_direction * PREFETCH_DISTANCE
	var center := Vector2i(floori(ahead.x / FIELD_SIZE + 0.5), floori(ahead.z / FIELD_SIZE + 0.5))
	if center == _center_tile:
		_prefetch_relocations.clear()
		_prefetch_index = 0
		return
	if center != _prefetch_center or _prefetch_relocations.is_empty():
		_prefetch_center = center
		_prefetch_relocations = _plan_relocations(center)
		_prefetch_index = 0
	if _prefetch_index < _prefetch_relocations.size():
		var relocation := _prefetch_relocations[_prefetch_index]
		var field := relocation["field"] as DeformableSurface
		var tile: Vector2i = relocation["tile"]
		var destination := Vector3(tile.x * FIELD_SIZE, 0.0, tile.y * FIELD_SIZE)
		if field.prepare_initial_noise_at(to_global(destination)):
			_prefetch_index += 1


func _queue_recenter(center: Vector2i) -> void:
	if center == _prefetch_center and not _prefetch_relocations.is_empty():
		# Keep the field/target pairing that already has work in flight.
		_pending_relocations = _prefetch_relocations.duplicate()
		_pending_relocations.sort_custom(_nearer_relocation)
	else:
		_pending_relocations = _plan_relocations(center)
	_prefetch_relocations.clear()
	_prefetch_index = 0
	_center_tile = center


func _nearer_relocation(a: Dictionary, b: Dictionary) -> bool:
	return _tile_priority(a["tile"]) < _tile_priority(b["tile"])


func _tile_priority(tile: Vector2i) -> float:
	var local_center := Vector3(tile.x * FIELD_SIZE, 0.0, tile.y * FIELD_SIZE)
	var world_center := to_global(local_center)
	var offset := world_center - player.global_position
	# Distance to the tile's footprint keeps the tile under the player first after a teleport.
	var dx := maxf(absf(offset.x) - FIELD_SIZE * 0.5, 0.0)
	var dz := maxf(absf(offset.z) - FIELD_SIZE * 0.5, 0.0)
	var distance_sq := dx * dx + dz * dz
	if distance_sq > 0.0 and camera != null and not camera.is_position_in_frustum(world_center):
		distance_sq *= 1.25
	return distance_sq


func _plan_relocations(center: Vector2i) -> Array[Dictionary]:
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

	var missing: Array[Dictionary] = []
	for tile in wanted:
		if next_tiles.has(tile):
			continue
		missing.append({"tile": tile})
	missing.sort_custom(_nearer_relocation)
	for relocation in missing:
		var field := available.pop_back() as DeformableSurface
		relocation["field"] = field
	return missing
