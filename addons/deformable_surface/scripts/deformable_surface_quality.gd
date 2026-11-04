@tool
class_name DeformableSurfaceQuality
extends Resource
## How much a DeformableSurface spends: map resolution, mesh density, stamp and puff
## budgets, and refill cadence. What the surface is made of (depth, berms, recovery, look)
## lives in DeformableSurfaceType. `sparkle` is only a quality scale on top of the
## material's own `sparkle_strength`.
##
## Presets are plain resources: `low()`, `medium()`, `high()` (copies of
## `resources/quality/*.tres`), or `for_platform()` to pick one automatically. A settings
## menu edits a copy of one of these and assigns it to `DeformableSurface.quality`.

const PRESET_DIR := "res://addons/deformable_surface/resources/quality/"

@export_group("Surface")
@export_range(128, 2048, 128) var res := 512
@export_range(1, 512, 1) var subdiv := 127

@export_group("Budgets")
@export_range(1, 512, 1) var max_stamps_per_frame := 64
@export_range(0.05, 5.0, 0.05) var refill_interval := 0.25
@export_range(1, 64, 1) var puff := 8
@export_range(0.0, 10.0, 0.05) var puff_min_interval := 0.2

@export_group("Effects")
## Quality scale for the material's sparkle.
@export_range(0.0, 3.0, 0.1) var sparkle := 1.0


static func low() -> DeformableSurfaceQuality:
	return (load(PRESET_DIR + "low.tres") as DeformableSurfaceQuality).duplicate()


static func medium() -> DeformableSurfaceQuality:
	return (load(PRESET_DIR + "medium.tres") as DeformableSurfaceQuality).duplicate()


static func high() -> DeformableSurfaceQuality:
	return (load(PRESET_DIR + "high.tres") as DeformableSurfaceQuality).duplicate()


## A sensible preset for the current platform (see `platform_tier()`).
static func for_platform() -> DeformableSurfaceQuality:
	return preset(platform_tier())


## 0 = Low, 1 = Medium, 2 = High.
static func preset(tier: int) -> DeformableSurfaceQuality:
	match tier:
		0: return low()
		1: return medium()
		_: return high()


## Low on mobile (and mobile browsers), Medium on desktop browsers, High elsewhere.
static func platform_tier() -> int:
	if OS.has_feature("web"):
		var mobile = JavaScriptBridge.eval("/Android|iPhone|iPad/i.test(navigator.userAgent)")
		return 0 if mobile else 1
	if OS.has_feature("mobile"):
		return 0
	return 2


## Clamps every value into its valid range (for values typed into a menu or a dictionary).
func clamp_values() -> void:
	res = clampi(res, 128, 2048)
	subdiv = clampi(subdiv, 1, 512)
	max_stamps_per_frame = clampi(max_stamps_per_frame, 1, 512)
	refill_interval = clampf(refill_interval, 0.05, 5.0)
	puff = clampi(puff, 1, 64)
	puff_min_interval = clampf(puff_min_interval, 0.0, 10.0)
	sparkle = clampf(sparkle, 0.0, 3.0)


## Every exported value by name, so new settings never need to be listed by hand.
func to_dictionary() -> Dictionary:
	var values := {}
	for info in (get_script() as Script).get_script_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			values[info["name"]] = get(info["name"])
	return values