extends SceneTree
## Geometry checks for the toroidal map window prototype.

const WindowScript := preload("res://addons/deformable_surface/scripts/toroidal_map_window.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var window = WindowScript.new()
	var initial := window.configure(Vector2i(8, 8), Vector2(8.0, 8.0), Vector2.ZERO)
	_check(_rect_area(initial) == 64, "Configure should expose the complete map")
	_check(window.history_extent() == Vector2(8.0, 8.0), "History extent should match world size")
	var world_point := Vector2.ZERO
	var uv_before: Vector2 = window.world_to_uv(world_point)

	var exposed := window.scroll_to(Vector2(1.0, 0.0))
	_check(_rect_area(exposed) == 8, "One X texel should expose one column")
	_check(_covers(exposed, Rect2i(0, 0, 1, 8)), "Positive X scroll should wrap the new column")
	_check(window.world_to_uv(world_point).is_equal_approx(uv_before),
			"A retained world point should keep the same physical texel")
	var stamp_centers := window.wrapped_stamp_centers(Vector2(0.0, 0.0), Vector2(0.5, 0.5))
	_check(stamp_centers.size() == 1, "Interior stamps should have one center")
	stamp_centers = window.wrapped_stamp_centers(Vector2(-3.9, 0.0), Vector2(0.5, 0.5))
	_check(stamp_centers.size() == 2, "An edge-crossing stamp should wrap to the opposite edge")
	stamp_centers = window.wrapped_stamp_centers(Vector2(-3.9, -3.9), Vector2(0.5, 0.5))
	_check(stamp_centers.size() == 4, "A corner-crossing stamp should cover all four corners")

	exposed = window.scroll_to(Vector2(2.0, 1.0))
	_check(_rect_area(exposed) == 15, "Diagonal scroll should expose a non-overlapping L")
	_check(_rects_in_bounds(exposed, Vector2i(8, 8)), "Wrapped rectangles must stay in texture bounds")
	var uv_after_diagonal: Vector2 = window.world_to_uv(world_point)
	_check(uv_after_diagonal.is_equal_approx(uv_before),
			"Diagonal scroll should preserve retained world coordinates")

	exposed = window.scroll_to(Vector2(2.1, 1.0))
	_check(exposed.is_empty(), "Sub-texel focus movement should not scroll the map")

	exposed = window.scroll_to(Vector2(1.0, 0.0))
	_check(_rect_area(exposed) == 15, "Reverse diagonal scroll should expose the same area")
	_check(window.world_to_uv(world_point).is_equal_approx(uv_before),
			"Reverse scroll should preserve retained world coordinates")

	exposed = window.scroll_to(Vector2(10.0, 0.0))
	_check(_rect_area(exposed) == 64, "A teleport beyond the window should reset the full map")
	_check(_covers(exposed, Rect2i(0, 0, 8, 8)), "Teleport reset should return the full texture")

	print("Toroidal map window checks: %d failures" % _failures)
	quit(1 if _failures else 0)


func _rect_area(rects: Array[Rect2i]) -> int:
	var area := 0
	for rect in rects:
		area += rect.size.x * rect.size.y
	return area


func _covers(rects: Array[Rect2i], expected: Rect2i) -> bool:
	return rects.size() == 1 and rects[0] == expected


func _rects_in_bounds(rects: Array[Rect2i], extent: Vector2i) -> bool:
	for rect in rects:
		if rect.position.x < 0 or rect.position.y < 0 \
				or rect.end.x > extent.x or rect.end.y > extent.y:
			return false
	return true


func _check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1
