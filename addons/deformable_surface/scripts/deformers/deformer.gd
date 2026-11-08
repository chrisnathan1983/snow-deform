@icon("res://addons/deformable_surface/icons/deformer.svg")
class_name Deformer
extends Node3D
## Add as a child of anything that should leave marks on the surface.
## X/Z determines the print position; DeformableSurface ignores deformers above max_depth.

## Active deformers are registered once; each surface filters by `field` when it enters.
static var instances: Array[Deformer] = []

## Which DeformableSurface this affects. Leave empty to affect every DeformableSurface.
@export var field: DeformableSurface : set = set_field

@export_range(0.02, 5.0, 0.01, "or_greater") var radius := 0.4 : set = set_radius
@export_range(0.0, 1.0) var strength := 1.0 : set = set_strength
@export var active := true : set = set_active
## CARVE presses the surface down, RAISE builds it up (e.g. dumping snow), SMOOTH flattens it
## (a snow plow). See DeformableSurface.StampMode.
@export var mode: DeformableSurface.StampMode = DeformableSurface.StampMode.CARVE : set = set_mode

var stamp_texture: Texture2D : set = set_stamp_texture
var stamp_flip_x := false : set = set_stamp_flip_x

@export_group("Shape")
## 1 = round. >1 = elongated along this node's forward (-Z) axis, same area.
## Use ~2 for a boot print, ~3 for a sled runner.
@export_range(1.0, 8.0) var aspect := 1.0 : set = set_aspect

@export_group("Puffs")
@export var puff_on_touchdown := true   # puff when contact starts (footfalls)
@export var puff_distance := 0.0        # >0: also spray a puff every N meters while moving

func _enter_tree() -> void:
	set_notify_transform(true)
	if not instances.has(self):
		instances.append(self)
	_register()
	_mark_changed()


func _exit_tree() -> void:
	_unregister()
	instances.erase(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_mark_changed()


func set_field(value: DeformableSurface) -> void:
	if field == value:
		return
	if is_inside_tree():
		_unregister()
	field = value
	if is_inside_tree():
		_register()
		_mark_changed()


func set_radius(value: float) -> void:
	var updated := clampf(value, 0.02, 5.0)
	if is_equal_approx(radius, updated):
		return
	radius = updated
	_mark_changed()


func set_strength(value: float) -> void:
	var updated := clampf(value, 0.0, 1.0)
	if is_equal_approx(strength, updated):
		return
	strength = updated
	_mark_changed()


func set_active(value: bool) -> void:
	if active == value:
		return
	active = value
	_mark_changed()


func set_stamp_texture(value: Texture2D) -> void:
	if stamp_texture == value:
		return
	stamp_texture = value
	_mark_changed()


func set_stamp_flip_x(value: bool) -> void:
	if stamp_flip_x == value:
		return
	stamp_flip_x = value
	_mark_changed()


func set_aspect(value: float) -> void:
	var updated := clampf(value, 1.0, 8.0)
	if is_equal_approx(aspect, updated):
		return
	aspect = updated
	_mark_changed()


func set_mode(value: DeformableSurface.StampMode) -> void:
	if mode == value:
		return
	mode = value
	_mark_changed()


func _register() -> void:
	if field != null:
		if is_instance_valid(field):
			field._register_deformer(self)
		return
	for surface in DeformableSurface.instances:
		surface._register_deformer(self)


func _unregister() -> void:
	if field != null:
		if is_instance_valid(field):
			field._unregister_deformer(self)
		return
	for surface in DeformableSurface.instances:
		surface._unregister_deformer(self)


func _mark_changed() -> void:
	if not is_inside_tree():
		return
	if field != null:
		if is_instance_valid(field):
			field._mark_deformer_dirty(self)
		return
	for surface in DeformableSurface.instances:
		surface._mark_deformer_dirty(self)


## Angle of this node's forward axis in surface-map space (map x = world X, map y = world Z).
## Assumes the DeformableSurface itself is not rotated.
func map_heading() -> float:
	var f := -global_basis.z
	return atan2(f.z, f.x)
