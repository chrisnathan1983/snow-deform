class_name BrushDeformer
extends Deformer
## A mouse brush over a flat field or a height function with no collider.

var camera: Camera3D
var height_at: Callable
var is_blocked: Callable
var painting := false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		painting = not is_blocked.is_valid() or not is_blocked.call(event.position)


func _input(event: InputEvent) -> void:
	# GUI controls can consume the release after a stroke starts over the field.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		painting = false


func paint_at_pointer() -> void:
	var hit := ground_point(get_viewport().get_mouse_position()) if painting else Vector3.INF
	active = hit != Vector3.INF
	if active:
		global_position = hit


func ground_point(mouse: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var hit: Vector3
	if height_at.is_valid():
		hit = _terrain_hit(origin, direction)
	else:
		var point: Variant = Plane(Vector3.UP, field.global_position.y).intersects_ray(origin, direction)
		if point == null:
			return Vector3.INF
		hit = point
	if hit == Vector3.INF:
		return hit
	var offset := hit - field.global_position
	if absf(offset.x) > field.area_size.x * 0.5 or absf(offset.z) > field.area_size.y * 0.5:
		return Vector3.INF
	return hit


func _terrain_hit(origin: Vector3, direction: Vector3) -> Vector3:
	var previous := 0.0
	var travelled := 0.0
	while travelled < 120.0:
		var p := origin + direction * travelled
		if p.y <= float(height_at.call(p.x, p.z)):
			var lo := previous
			var hi := travelled
			for i in 8:
				var mid := (lo + hi) * 0.5
				var q := origin + direction * mid
				if q.y <= float(height_at.call(q.x, q.z)):
					hi = mid
				else:
					lo = mid
			var hit := origin + direction * hi
			hit.y = float(height_at.call(hit.x, hit.z))
			return hit
		previous = travelled
		travelled += 0.3
	return Vector3.INF
