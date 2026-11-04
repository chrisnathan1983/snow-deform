@icon("res://addons/deformable_surface/icons/deformer.svg")
class_name DeformerTracks
extends Node3D
## Lays continuous tread tracks behind wheels or tracked belts. Add under a vehicle (origin at
## ground level, facing -Z). Each wheel draws an unbroken ribbon along its own path, so front
## and rear wheels follow their own arcs through a turn. The tread texture is laid by distance
## travelled, so the pattern stays continuous across frames, speeds and turns.
## Built on DeformableSurface.stamp_segment; needs a DeformableSurface in the scene.

enum Preset { CUSTOM, CAR, TRUCK, MOTORCYCLE, TRACKED }

## Wheel movement below this (meters) is accumulated until it is long enough to draw.
const MIN_STEP := 0.05
## Longer moves are split into straight pieces of at most this length.
const MAX_SEGMENT := 1.0
## A single-frame jump beyond this is treated as a teleport: no track is drawn across it.
const TELEPORT_DISTANCE := 6.0

static var _default_tread: ImageTexture

## CAR: 4 wheels. TRUCK: 6 wheels (3 axles). MOTORCYCLE: 2 wheels on the centerline.
## TRACKED: one wide belt per side. CUSTOM uses `wheel_offsets`.
@export var preset := Preset.CAR : set = set_preset
## Distance between left and right wheels, in meters.
@export_range(0.1, 10.0, 0.05, "or_greater") var track_gauge := 1.6 : set = set_track_gauge
## Distance between front and rear axles (TRUCK: front to rear of three).
@export_range(0.1, 20.0, 0.05, "or_greater") var wheelbase := 2.6 : set = set_wheelbase
## CUSTOM preset only: wheel contact points as (x = right, y = local Z, negative is forward) in meters.
@export var wheel_offsets := PackedVector2Array([Vector2(-0.8, -1.3), Vector2(0.8, -1.3),
		Vector2(-0.8, 1.3), Vector2(0.8, 1.3)])
@export_range(0.05, 3.0, 0.01, "or_greater") var wheel_width := 0.3
## Alpha-mask tread pattern; its top edge faces the direction of travel. One tile spans the
## track width and is as long as the texture's height/width ratio implies. Empty uses a
## built-in chevron tread.
@export var tread_texture: Texture2D
@export_range(0.0, 1.0) var strength := 0.8
@export var mode: DeformableSurface.StampMode = DeformableSurface.StampMode.CARVE
@export var active := true
## Which DeformableSurface this affects. Leave empty to affect every DeformableSurface.
@export var field: DeformableSurface

var _last: Array = []   # per wheel: last drawn position (Vector3) or null
var _dist: Array = []   # per wheel: distance travelled since the path started


func _ready() -> void:
	_rebuild_wheels()


func set_preset(value: Preset) -> void:
	preset = value
	_last.clear()


func set_track_gauge(value: float) -> void:
	track_gauge = value
	_last.clear()


func set_wheelbase(value: float) -> void:
	wheelbase = value
	_last.clear()


## Wheel contact points in local space (x = right, y = Z).
func get_wheel_offsets() -> PackedVector2Array:
	var g := track_gauge * 0.5
	var w := wheelbase * 0.5
	match preset:
		Preset.CAR:
			return PackedVector2Array([Vector2(-g, -w), Vector2(g, -w), Vector2(-g, w), Vector2(g, w)])
		Preset.TRUCK:
			return PackedVector2Array([Vector2(-g, -w), Vector2(g, -w), Vector2(-g, 0.0),
					Vector2(g, 0.0), Vector2(-g, w), Vector2(g, w)])
		Preset.MOTORCYCLE:
			return PackedVector2Array([Vector2(0.0, -w), Vector2(0.0, w)])
		Preset.TRACKED:
			return PackedVector2Array([Vector2(-g, 0.0), Vector2(g, 0.0)])
	return wheel_offsets


## Forgets where the wheels last drew (use after teleporting the vehicle).
func reset_path() -> void:
	_rebuild_wheels()


func _rebuild_wheels() -> void:
	var count := get_wheel_offsets().size()
	_last.clear()
	_last.resize(count)
	_dist.clear()
	_dist.resize(count)
	_dist.fill(0.0)


func _surfaces() -> Array:
	if field != null:
		return [field] if is_instance_valid(field) else []
	return DeformableSurface.instances


func _process(_delta: float) -> void:
	var offsets := get_wheel_offsets()
	if _last.size() != offsets.size():
		_rebuild_wheels()
	if not active:
		_last.fill(null)
		return

	var texture := tread_texture if tread_texture != null else _get_default_tread()
	var tile_length := wheel_width * float(texture.get_height()) / float(texture.get_width())

	for i in offsets.size():
		var o := offsets[i]
		var pos := to_global(Vector3(o.x, 0.0, o.y))
		var grounded := false
		for surface in _surfaces():
			if surface.to_local(pos).y <= surface.max_depth:
				grounded = true
				break
		if not grounded:
			_last[i] = null
			continue
		if _last[i] == null:
			_last[i] = pos
			continue

		var prev: Vector3 = _last[i]
		var delta := Vector3(pos.x - prev.x, 0.0, pos.z - prev.z)
		var dist := delta.length()
		if dist < MIN_STEP:
			continue
		if dist > TELEPORT_DISTANCE:
			_last[i] = pos
			continue

		var pieces := ceili(dist / MAX_SEGMENT)
		var from := prev
		for k in pieces:
			var to := prev.lerp(pos, float(k + 1) / pieces)
			var phase := float(_dist[i]) / tile_length
			for surface in _surfaces():
				surface.stamp_segment(from, to, wheel_width, strength, texture, mode, phase)
			_dist[i] += from.distance_to(to)
			from = to
		_last[i] = pos


static func _get_default_tread() -> ImageTexture:
	if _default_tread != null:
		return _default_tread
	var w := 32
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var v := float(y) / h
		for x in w:
			var u := float(x) / (w - 1)
			var lug := fposmod(v * 2.0 + absf(u - 0.5) * 1.2, 1.0) < 0.5
			var a := 1.0 if lug else 0.45
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_default_tread = ImageTexture.create_from_image(img)
	return _default_tread
