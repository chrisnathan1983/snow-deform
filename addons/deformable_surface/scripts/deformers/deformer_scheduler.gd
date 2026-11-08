extends RefCounted
## Tracks active deformers and turns their movement into budgeted stamp requests.

const BERM_REACH := 2.0
const BERM_FORWARD := 0.3
const STAMP_MAX_ASPECT := 8.0

var _surface: Node
var _dirty: Array[Deformer] = []
var _dirty_indices := {}
var _known := {}
var _last := {}
var _puff_distance := {}
var _cursor := 0


func setup(surface: Node) -> void:
	_surface = surface


func register(deformer: Deformer) -> void:
	if not is_instance_valid(deformer):
		return
	var id := deformer.get_instance_id()
	if _dirty_indices.has(id):
		return
	_dirty_indices[id] = _dirty.size()
	_dirty.append(deformer)


func unregister(deformer: Deformer) -> void:
	if is_instance_valid(deformer):
		_remove_dirty(deformer)


func reset() -> void:
	_puff_distance.clear()
	_last.clear()


func clear() -> void:
	_dirty.clear()
	_dirty_indices.clear()
	_known.clear()
	_last.clear()
	_puff_distance.clear()
	_cursor = 0


func forget(deformer: Deformer) -> void:
	var id := deformer.get_instance_id()
	_known.erase(id)
	_last.erase(id)
	_remove_dirty(deformer)
	_puff_distance.erase(id)


func has_history(deformer: Deformer) -> bool:
	return is_instance_valid(deformer) and _last.has(deformer.get_instance_id())


func _remove_dirty(deformer: Deformer) -> void:
	var id := deformer.get_instance_id()
	if not _dirty_indices.has(id):
		return
	var index: int = _dirty_indices[id]
	var last_index := _dirty.size() - 1
	if index != last_index:
		var moved := _dirty[last_index]
		_dirty[index] = moved
		_dirty_indices[moved.get_instance_id()] = index
	_dirty.pop_back()
	_dirty_indices.erase(id)
	if index < _cursor:
		_cursor -= 1
	if _cursor >= _dirty.size():
		_cursor = 0


func process_deformers(res: Vector2, px_per_m: float, priming: bool) -> int:
	var started := Time.get_ticks_usec()
	var list := _dirty.duplicate()
	var n := list.size()
	var stamp_pipeline: RefCounted = _surface._stamp_pipeline
	for k in n:
		var d := list[(k + _cursor) % n] as Deformer
		if d == null or not is_instance_valid(d):
			continue
		var id := d.get_instance_id()
		if not _known.has(id):
			_known[id] = true
			d.tree_exiting.connect(_surface._forget.bind(d), CONNECT_ONE_SHOT)
		if priming:
			continue
		if not d.active or d.strength <= 0.0:
			_last.erase(id)
			_remove_dirty(d)
			continue
		var local: Vector3 = _surface.to_local(d.global_position)
		var reach := d.radius * sqrt(clampf(d.aspect, 1.0, STAMP_MAX_ASPECT)) * (BERM_REACH + BERM_FORWARD)
		if (_surface.render_mesh and local.y > _surface.max_depth) or absf(local.x) > _surface.area_size.x * 0.5 + reach or absf(local.z) > _surface.area_size.y * 0.5 + reach:
			_last.erase(id)
			_remove_dirty(d)
			continue
		var depth_ratio := clampf(1.0 - (local.y / _surface.max_depth), 0.1, 1.0) if _surface.render_mesh else 1.0
		var effective_strength := d.strength * depth_ratio
		var owns_contact: bool = (local.x >= -_surface.area_size.x * 0.5 and local.x < _surface.area_size.x * 0.5
				and local.z >= -_surface.area_size.y * 0.5 and local.z < _surface.area_size.y * 0.5)
		var pos: Vector2 = (Vector2(local.x, local.z) / _surface.area_size + Vector2(0.5, 0.5)) * res
		var r_px := maxf(d.radius, 0.01) * px_per_m
		var heading := d.map_heading()
		var aspect := maxf(d.aspect, 1.0)
		var done := pos
		if _last.has(id):
			var prev: Vector2 = _last[id]
			var dist := prev.distance_to(pos)
			if dist < r_px * 0.15:
				_remove_dirty(d)
				continue
			var move_heading: float = heading if (aspect > 1.05 or d.stamp_texture != null) else (pos - prev).angle()
			if dist > r_px * 20.0:
				var jump = stamp_pipeline.prepare(pos, r_px, heading, aspect, effective_strength, d.mode)
				jump.texture = d.stamp_texture
				jump.flip_x = d.stamp_flip_x
				if not stamp_pipeline.stamp_request(jump):
					continue
			else:
				done = prev
				if aspect <= 1.05 and d.stamp_texture == null:
					var half_len := dist * 0.5
					var capsule = stamp_pipeline.prepare(prev.lerp(pos, 0.5), sqrt(half_len * r_px),
							move_heading, half_len / r_px, effective_strength, d.mode)
					capsule.capsule = true
					if not stamp_pipeline.stamp_request(capsule):
						continue
					done = pos
				else:
					var steps := clampi(ceili(dist / (r_px * 0.5)), 1, 40)
					for s in range(1, steps + 1):
						var sp := prev.lerp(pos, float(s) / steps)
						var step = stamp_pipeline.prepare(sp, r_px, move_heading, aspect, effective_strength, d.mode)
						step.sliding = true
						step.texture = d.stamp_texture
						step.flip_x = d.stamp_flip_x
						if not stamp_pipeline.stamp_request(step):
							break
						done = sp
					if done == prev:
						continue
				if d.puff_distance > 0.0 and owns_contact:
					var stamped_move: Vector2 = done - prev
					var acc: float = _puff_distance.get(id, 0.0) + stamped_move.length() / px_per_m
					if acc >= d.puff_distance:
						acc = 0.0
						_surface._try_puff(d, id, -Vector3(stamped_move.x, 0.0, stamped_move.y))
					_puff_distance[id] = acc
		else:
			var touchdown = stamp_pipeline.prepare(pos, r_px, heading, aspect, effective_strength, d.mode)
			touchdown.texture = d.stamp_texture
			touchdown.flip_x = d.stamp_flip_x
			if not stamp_pipeline.stamp_request(touchdown):
				continue
			if owns_contact:
				_surface._emit_contact(d.global_position, effective_strength, d.mode, d, d.radius, d.puff_on_touchdown)
		_last[id] = done
		if done.distance_to(pos) < 0.001:
			_remove_dirty(d)
	if not _dirty.is_empty():
		_cursor = (_cursor + 1) % _dirty.size()
	return maxi(Time.get_ticks_usec() - started, 0)
