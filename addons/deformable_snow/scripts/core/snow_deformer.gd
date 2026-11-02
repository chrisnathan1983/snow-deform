@icon("res://addons/deformable_snow/icons/snow_deformer.svg")
class_name SnowDeformer
extends Node3D
## Add as a child of anything that should leave marks in the snow.
## X/Z determines the print position; SnowField ignores deformers above max_depth.

## Deformers without a field assignment affect each SnowField.
static var unassigned: Array[SnowDeformer] = []
## SnowField instance ID -> explicitly assigned deformers.
static var assigned: Dictionary = {}

## Which SnowField this affects. Leave empty to affect every SnowField.
@export var field: SnowField : set = set_field

@export_range(0.02, 5.0, 0.01, "or_greater") var radius := 0.4 : set = set_radius
@export_range(0.0, 1.0) var strength := 1.0 : set = set_strength
@export var active := true : set = set_active

var stamp_texture: Texture2D : set = set_stamp_texture
var stamp_flip_x := false : set = set_stamp_flip_x

@export_group("Shape")
## 1 = round. >1 = elongated along this node's forward (-Z) axis, same area.
## Use ~2 for a boot print, ~3 for a sled runner.
@export_range(1.0, 8.0) var aspect := 1.0 : set = set_aspect

@export_group("Puffs")
@export var puff_on_touchdown := true   # puff when contact starts (footfalls)
@export var puff_distance := 0.0        # >0: also spray a puff every N meters while moving

var _registered_field_id := 0


func _enter_tree() -> void:
	set_notify_transform(true)
	set_notify_local_transform(true)
	_register()
	_mark_changed()


func _exit_tree() -> void:
	_unregister()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		_mark_changed()


func set_field(value: SnowField) -> void:
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


func _register() -> void:
	if field == null:
		_registered_field_id = 0
		if not unassigned.has(self):
			unassigned.append(self)
		for snow_field in SnowField.instances:
			snow_field._register_deformer(self)
		return

	var field_id := field.get_instance_id()
	_registered_field_id = field_id
	var field_deformers: Array = assigned.get(field_id, [])
	if not field_deformers.has(self):
		field_deformers.append(self)
	assigned[field_id] = field_deformers
	field._register_deformer(self)


func _unregister() -> void:
	if _registered_field_id == 0:
		unassigned.erase(self)
		for snow_field in SnowField.instances:
			snow_field._unregister_deformer(self)
		return

	var field_id := _registered_field_id
	_registered_field_id = 0
	var field_deformers: Array = assigned.get(field_id, [])
	field_deformers.erase(self)
	if field_deformers.is_empty():
		assigned.erase(field_id)
	else:
		assigned[field_id] = field_deformers
	if is_instance_valid(field):
		field._unregister_deformer(self)


func _mark_changed() -> void:
	if not is_inside_tree():
		return
	if field != null:
		if is_instance_valid(field):
			field._mark_deformer_dirty(self)
		return
	if _registered_field_id != 0:
		_unregister()
		_register()
	for snow_field in SnowField.instances:
		snow_field._mark_deformer_dirty(self)


## Angle of this node's forward axis in snow-map space (map x = world X, map y = world Z).
## Assumes the SnowField itself is not rotated.
func map_heading() -> float:
	var f := -global_basis.z
	return atan2(f.z, f.x)
