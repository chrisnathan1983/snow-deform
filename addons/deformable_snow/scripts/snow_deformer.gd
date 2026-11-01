@icon("res://addons/deformable_snow/icons/snow_deformer.svg")
class_name SnowDeformer
extends Node3D
## Add as a child of anything that should leave marks in the snow.
## X/Z determines the print position; SnowField ignores deformers above max_depth.

## Every deformer currently in the tree. SnowFields read this directly, which is
## cheaper than querying a node group every frame.
static var all: Array[SnowDeformer] = []

enum StampMode { FOOTPRINT, BULGE_ERASER }

## Which SnowField this affects. Leave empty to affect every SnowField.
@export var field: SnowField

## Footprint stamps pits and berms; Bulge Eraser raises temporary snow and fills pits.
@export var stamp_mode: StampMode = StampMode.FOOTPRINT
@export_range(0.02, 5.0, 0.01, "or_greater") var radius := 0.4
@export_range(0.0, 1.0) var strength := 1.0
@export var active := true   # set false to suppress prints (e.g. a lifted foot)

@export_group("Shape")
## 1 = round. >1 = elongated along this node's forward (-Z) axis, same area.
## Use ~2 for a boot print, ~3 for a sled runner.
@export_range(1.0, 8.0) var aspect := 1.0

@export_group("Puffs")
@export var puff_on_touchdown := true   # puff when contact starts (footfalls)
@export var puff_distance := 0.0        # >0: also spray a puff every N meters while moving


func _enter_tree() -> void:
	if not all.has(self):
		all.append(self)


func _exit_tree() -> void:
	all.erase(self)


## Angle of this node's forward axis in snow-map space (map x = world X, map y = world Z).
## Assumes the SnowField itself is not rotated.
func map_heading() -> float:
	var f := -global_basis.z
	return atan2(f.z, f.x)
