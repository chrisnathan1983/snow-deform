class_name DeformableSurfaceGrid
extends Node3D
## Owns a square pool of snow fields. Crossing a tile boundary recycles fields
## outside the new footprint. Prepare noise ahead of travel when possible.
## Set the tile size, radius and initial profiles before adding the grid to the tree.

@export var surface_type: DeformableSurfaceType
@export var quality: DeformableSurfaceQuality
@export var sun: DirectionalLight3D
@export var follow_target: Node3D
@export var priority_camera: Camera3D
@export_range(1.0, 256.0, 1.0) var tile_size := 32.0
@export_range(0, 8) var radius := 1
@export_range(0.0, 32.0, 0.5, "or_greater") var prefetch_distance := 8.0
@export_range(1, 32, 1, "or_greater") var relocations_per_frame := 1
@export var follow_x := true
@export var follow_offset := Vector3.ZERO

## Optional Callable(tile: Vector2i) -> DeformableSurfaceType for initial per-field profiles.
var surface_for_tile: Callable
## Optional Callable() -> bool while settings edits own the fields' noise workers.
var relocation_blocked: Callable
var fields: Array[DeformableSurface] = []
var center_tile := Vector2i.ZERO

var _tiles: Dictionary[Vector2i, DeformableSurface] = {}
var _pending_relocations: Array[Dictionary] = []
var _prefetch_relocations: Array[Dictionary] = []
var _prefetch_center := Vector2i.ZERO
var _prefetch_index := 0
var _last_position := Vector3.ZERO
var _travel_direction := Vector3.ZERO
var _has_sample := false
var _focus := Vector3.ZERO


func _ready() -> void:
	for z in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var tile := Vector2i(x, z)
			var field := DeformableSurface.new()
			field.name = "SnowField_%d_%d" % [x, z]
			field.size = tile_size
			field.quality = quality
			field.surface_type = (surface_for_tile.call(tile) as DeformableSurfaceType
					if surface_for_tile.is_valid() else surface_type)
			field.sun = sun
			field.position = _tile_position(tile)
			add_child(field)
			fields.append(field)
			_tiles[tile] = field


func _process(_delta: float) -> void:
	update_tiles()


func field_at(tile: Vector2i) -> DeformableSurface:
	return _tiles.get(tile)


func tile_at(world_position: Vector3) -> Vector2i:
	return _tile_at_local(to_local(world_position))


func has_pending_relocations() -> bool:
	return not _pending_relocations.is_empty()


func update_tiles() -> void:
	if not is_instance_valid(follow_target):
		return
	_focus = to_local(follow_target.global_position) + follow_offset
	if not follow_x:
		_focus.x = 0.0
	if _has_sample:
		var movement := _focus - _last_position
		movement.y = 0.0
		if movement.length_squared() > 0.000001:
			_travel_direction = movement.normalized()
	_last_position = _focus
	_has_sample = true
	if relocation_blocked.is_valid() and relocation_blocked.call():
		_clear_prefetch()
		return
	var center := _tile_at_local(_focus)
	if center != center_tile:
		_queue_recenter(center)

	if has_pending_relocations():
		for i in relocations_per_frame:
			if not has_pending_relocations() or not _relocate_next():
				break
	elif prefetch_distance > 0.0:
		_prefetch_fields()


func _tile_position(tile: Vector2i) -> Vector3:
	return Vector3(tile.x * tile_size, 0.0, tile.y * tile_size)


func _tile_at_local(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / tile_size + 0.5), floori(point.z / tile_size + 0.5))


func _relocate_next() -> bool:
	var relocation: Dictionary = _pending_relocations.front()
	var field := relocation["field"] as DeformableSurface
	var tile: Vector2i = relocation["tile"]
	var destination := _tile_position(tile)
	if not field.prepare_initial_noise_at(to_global(destination)):
		return false
	_pending_relocations.pop_front()
	_tiles.erase(_tile_at_local(field.position))
	field.position = destination
	field.reset_trails()
	_tiles[tile] = field
	return true


func _prefetch_fields() -> void:
	var center := _tile_at_local(_focus + _travel_direction * prefetch_distance)
	if center == center_tile:
		_clear_prefetch()
		return
	if center != _prefetch_center or _prefetch_relocations.is_empty():
		_prefetch_center = center
		_prefetch_relocations = _plan_relocations(center)
		_prefetch_index = 0
	if _prefetch_index < _prefetch_relocations.size():
		var relocation := _prefetch_relocations[_prefetch_index]
		var field := relocation["field"] as DeformableSurface
		var destination := _tile_position(relocation["tile"])
		if field.prepare_initial_noise_at(to_global(destination)):
			_prefetch_index += 1


func _clear_prefetch() -> void:
	_prefetch_relocations.clear()
	_prefetch_index = 0


func _queue_recenter(center: Vector2i) -> void:
	if center == _prefetch_center and not _prefetch_relocations.is_empty():
		# Keep the field/target pairing that already has work in flight.
		_pending_relocations = _prefetch_relocations.duplicate()
		_pending_relocations.sort_custom(_nearer_relocation)
	else:
		_pending_relocations = _plan_relocations(center)
	_clear_prefetch()
	center_tile = center


func _nearer_relocation(a: Dictionary, b: Dictionary) -> bool:
	return _tile_priority(a["tile"]) < _tile_priority(b["tile"])


func _tile_priority(tile: Vector2i) -> float:
	var local_center := _tile_position(tile)
	var offset := local_center - _focus
	# Distance to the tile footprint keeps the tile under the target first after a teleport.
	var dx := maxf(absf(offset.x) - tile_size * 0.5, 0.0)
	var dz := maxf(absf(offset.z) - tile_size * 0.5, 0.0)
	var distance_sq := dx * dx + dz * dz
	if distance_sq > 0.0 and is_instance_valid(priority_camera):
		if not priority_camera.is_position_in_frustum(to_global(local_center)):
			distance_sq *= 1.25
	return distance_sq


func _plan_relocations(center: Vector2i) -> Array[Dictionary]:
	var available := fields.duplicate()
	var missing: Array[Dictionary] = []
	for z in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var tile := center + Vector2i(x, z)
			if _tiles.has(tile):
				available.erase(_tiles[tile])
			else:
				missing.append({"tile": tile})
	missing.sort_custom(_nearer_relocation)
	for relocation in missing:
		relocation["field"] = available.pop_back()
	return missing
