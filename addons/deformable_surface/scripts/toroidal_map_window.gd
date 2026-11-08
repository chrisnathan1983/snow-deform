class_name ToroidalMapWindow
extends RefCounted
## Logical window for a toroidal height map. The world window snaps to map texels;
## scrolling preserves existing texture cells and reports only newly exposed strips.
## Configure with 96 m for the current 3x3 Playground grid or 120 m for Powder Run.

var resolution := Vector2i.ZERO
var world_size := Vector2.ZERO
var world_origin := Vector2.ZERO
var ring_origin := Vector2i.ZERO


func configure(map_resolution: Vector2i, map_world_size: Vector2, focus: Vector2) -> Array[Rect2i]:
	resolution = Vector2i(maxi(map_resolution.x, 1), maxi(map_resolution.y, 1))
	world_size = map_world_size.max(Vector2.ONE)
	ring_origin = Vector2i.ZERO
	world_origin = _snapped_origin(focus)
	return [Rect2i(Vector2i.ZERO, resolution)]


## Returns physical texture rectangles that need their starting height and slopes repainted.
## A teleport of one full map extent or more invalidates the complete window.
func scroll_to(focus: Vector2) -> Array[Rect2i]:
	if resolution.x <= 0 or resolution.y <= 0 or world_size.x <= 0.0 or world_size.y <= 0.0:
		return []
	var next_origin := _snapped_origin(focus)
	var texel_size := world_size / Vector2(resolution)
	var shift_f := (next_origin - world_origin) / texel_size
	var shift := Vector2i(roundi(shift_f.x), roundi(shift_f.y))
	if shift == Vector2i.ZERO:
		return []
	world_origin = next_origin
	if abs(shift.x) >= resolution.x or abs(shift.y) >= resolution.y:
		ring_origin = Vector2i.ZERO
		return [Rect2i(Vector2i.ZERO, resolution)]

	ring_origin = Vector2i(
		posmod(ring_origin.x + shift.x, resolution.x),
		posmod(ring_origin.y + shift.y, resolution.y))
	var logical_regions: Array[Rect2i] = []
	var x_start := 0
	var x_width := resolution.x
	if shift.x > 0:
		logical_regions.append(Rect2i(resolution.x - shift.x, 0, shift.x, resolution.y))
		x_width -= shift.x
	elif shift.x < 0:
		logical_regions.append(Rect2i(0, 0, -shift.x, resolution.y))
		x_start = -shift.x
		x_width -= -shift.x
	if shift.y > 0:
		logical_regions.append(Rect2i(x_start, resolution.y - shift.y, x_width, shift.y))
	elif shift.y < 0:
		logical_regions.append(Rect2i(x_start, 0, x_width, -shift.y))

	return _to_physical_regions(logical_regions)


## Maps a world position to the wrapped, texel-centered UV used by the height texture.
func world_to_uv(world_position: Vector2) -> Vector2:
	if resolution.x <= 0 or resolution.y <= 0:
		return Vector2.ZERO
	var physical_pixel := world_to_pixel(world_position) + Vector2(0.5, 0.5)
	return Vector2(fposmod(physical_pixel.x, resolution.x) / resolution.x,
		fposmod(physical_pixel.y, resolution.y) / resolution.y)


## Maps a world position to continuous physical texture coordinates for stamp placement.
func world_to_pixel(world_position: Vector2) -> Vector2:
	var logical_pixel := (world_position - world_origin) / (world_size / Vector2(resolution))
	return logical_pixel + Vector2(ring_origin)


## Returns additional center positions when a stamp's outer extent crosses a texture seam.
## `outer_extent` must include the stamp and any berm dilation in texels.
func wrapped_stamp_centers(world_position: Vector2, outer_extent: Vector2) -> Array[Vector2]:
	var pixel := world_to_pixel(world_position)
	var center := Vector2(fposmod(pixel.x, resolution.x), fposmod(pixel.y, resolution.y))
	var xs: Array[float] = [center.x]
	var ys: Array[float] = [center.y]
	if center.x - outer_extent.x < 0.0:
		xs.append(center.x + resolution.x)
	elif center.x + outer_extent.x > resolution.x:
		xs.append(center.x - resolution.x)
	if center.y - outer_extent.y < 0.0:
		ys.append(center.y + resolution.y)
	elif center.y + outer_extent.y > resolution.y:
		ys.append(center.y - resolution.y)
	var centers: Array[Vector2] = []
	for x in xs:
		for y in ys:
			centers.append(Vector2(x, y))
	return centers


## The complete visible history; footprints older than this window are discarded.
func history_extent() -> Vector2:
	return world_size


func _snapped_origin(focus: Vector2) -> Vector2:
	var texel_size := world_size / Vector2(resolution)
	var desired := focus - world_size * 0.5
	return Vector2(roundf(desired.x / texel_size.x) * texel_size.x,
		roundf(desired.y / texel_size.y) * texel_size.y)


func _to_physical_regions(regions: Array[Rect2i]) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	for region in regions:
		var xs := _split_axis(region.position.x + ring_origin.x, region.size.x, resolution.x)
		var ys := _split_axis(region.position.y + ring_origin.y, region.size.y, resolution.y)
		for x in xs:
			for y in ys:
				result.append(Rect2i(Vector2i(x.x, y.x), Vector2i(x.y, y.y)))
	return result


func _split_axis(start: int, length: int, extent: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if length <= 0:
		return result
	var wrapped_start := posmod(start, extent)
	var first_length := mini(length, extent - wrapped_start)
	result.append(Vector2i(wrapped_start, first_length))
	if first_length < length:
		result.append(Vector2i(0, length - first_length))
	return result
