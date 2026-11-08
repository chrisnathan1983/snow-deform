extends RefCounted
## Owns queued stamps, stamp request packing, and submission to a surface map.

const BERM_REACH := 2.0
const BERM_FORWARD := 0.3
const STAMP_MIN_RADIUS_PX := 0.5
const STAMP_MAX_ASPECT := 8.0

class PendingStamp:
	extends RefCounted
	var local := Vector3.ZERO
	var radius := 0.0
	var strength := 0.0
	var shape: Texture2D
	var mode := 0
	var heading := 0.0
	var aspect := 1.0
	var puff := false
	var silent := false
	var track := false
	var phase := 0.0
	var capsule := false


class StampRequest:
	extends RefCounted
	var pos := Vector2.ZERO
	var radius_px := 0.0
	var heading := 0.0
	var aspect := 1.0
	var strength := 1.0
	var sliding := false
	var texture: Texture2D
	var flip_x := false
	var mode := 0
	var track := false
	var phase := 0.0
	var capsule := false


var _surface: Node
var _map: DeformationMap
var _pending: Array[PendingStamp] = []
var _pool: Array[PendingStamp] = []
var _scratch := StampRequest.new()


func setup(surface: Node, map: DeformationMap) -> void:
	_surface = surface
	_map = map


func get_used_count() -> int:
	return _map.stamp_renderer.stamps_used if _map != null else 0


func get_batch_count() -> int:
	return _map.stamp_renderer.get_batch_count() if _map != null else 0


func get_active_batch_count() -> int:
	return _map.stamp_renderer.get_active_batch_count() if _map != null else 0


func get_pending_count() -> int:
	return _pending.size()


func get_pending_info(index: int) -> Dictionary:
	if index < 0 or index >= _pending.size():
		return {}
	var stamp := _pending[index]
	return {"capsule": stamp.capsule, "shape": stamp.shape,
			"aspect": stamp.aspect, "track": stamp.track}


func reset_counts() -> void:
	_map.stamp_renderer.reset_counts()


func submit() -> void:
	_map.stamp_renderer.submit()


func prepare(pos: Vector2, radius_px: float, heading: float, aspect: float,
		strength: float, mode := 0) -> StampRequest:
	_scratch.pos = pos
	_scratch.radius_px = radius_px
	_scratch.heading = heading
	_scratch.aspect = aspect
	_scratch.strength = strength
	_scratch.sliding = false
	_scratch.texture = null
	_scratch.flip_x = false
	_scratch.mode = mode
	_scratch.track = false
	_scratch.phase = 0.0
	_scratch.capsule = false
	return _scratch


func queue(local: Vector3, radius: float, strength: float, shape: Texture2D,
		mode: int, heading: float, aspect: float, puff: bool, silent: bool,
		track: bool, phase: float, capsule: bool) -> void:
	var stamp: PendingStamp
	if _pool.is_empty():
		stamp = PendingStamp.new()
	else:
		stamp = _pool.pop_back()
	stamp.local = local
	stamp.radius = radius
	stamp.strength = strength
	stamp.shape = shape
	stamp.mode = mode
	stamp.heading = heading
	stamp.aspect = aspect
	stamp.puff = puff
	stamp.silent = silent
	stamp.track = track
	stamp.phase = phase
	stamp.capsule = capsule
	_pending.append(stamp)


func clear_pending() -> void:
	for stamp in _pending:
		stamp.shape = null
		_pool.append(stamp)
	_pending.clear()


func flush(res: Vector2, px_per_m: float, priming: bool) -> void:
	var input_count := _pending.size()
	var write_index := 0
	for read_index in input_count:
		var stamp := _pending[read_index]
		var local: Vector3 = stamp.local
		var pos: Vector2 = (Vector2(local.x, local.z) / _surface.area_size + Vector2(0.5, 0.5)) * res
		var request := prepare(pos, stamp.radius * px_per_m, stamp.heading,
				stamp.aspect, stamp.strength, stamp.mode)
		request.texture = stamp.shape
		request.track = stamp.track
		request.phase = stamp.phase
		request.capsule = stamp.capsule
		if priming or not stamp_request(request):
			_pending[write_index] = stamp
			write_index += 1
			continue
		if not stamp.silent:
			_surface._emit_contact(_surface.to_global(Vector3(local.x, 0.0, local.z)),
					stamp.strength, stamp.mode, null, stamp.radius, stamp.puff)
		stamp.shape = null
		_pool.append(stamp)
	# Contact callbacks may enqueue new stamps; preserve that tail after compaction.
	var appended_count := _pending.size() - input_count
	for i in appended_count:
		_pending[write_index + i] = _pending[input_count + i]
	_pending.resize(write_index + appended_count)


func stamp_request(request: StampRequest) -> bool:
	if get_used_count() >= _surface.max_stamps_per_frame:
		return false
	var stamp_radius_px := maxf(request.radius_px, STAMP_MIN_RADIUS_PX)
	var stamp_aspect := clampf(request.aspect, 0.001, STAMP_MAX_ASPECT)
	var len_r := stamp_radius_px * sqrt(stamp_aspect)
	var wid_r := stamp_radius_px / sqrt(stamp_aspect)
	var berm_strength: float = _surface._values().berm_strength
	var berm_radius := Vector2(len_r, wid_r) * BERM_REACH if berm_strength > 0.0 else Vector2.ZERO
	var berm_offset_x := len_r * BERM_FORWARD * clampf(stamp_aspect - 1.0, 0.0, 1.0) \
		if berm_strength > 0.0 else 0.0
	var outer_half_extent := Vector2(
		maxf(len_r, absf(berm_offset_x) + berm_radius.x),
		maxf(wid_r, berm_radius.y))
	if request.capsule:
		outer_half_extent = Vector2(len_r + maxf(berm_radius.y, wid_r),
				maxf(berm_radius.y, wid_r))
	var custom_data := Color(
		stamp_aspect / STAMP_MAX_ASPECT,
		3.0 if request.capsule else (2.0 if request.track else (1.0 if request.sliding else 0.0)),
		wrapf(request.heading, -PI, PI) / TAU + 0.5,
		(2.0 if request.flip_x else 1.0) if request.texture != null else 0.0)
	return _map.stamp_renderer.stamp(
		request.texture,
		Transform2D(request.heading, outer_half_extent, 0.0, request.pos),
		Color(request.strength, stamp_radius_px / float(_map.viewport.size.x),
				float(request.mode) * 0.25, fposmod(request.phase, 1.0)),
		custom_data,
		4.0 * outer_half_extent.x * outer_half_extent.y)
