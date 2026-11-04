@tool
class_name DeformableSurfaceType
extends Resource
## What the surface is made of: how deep it sinks, how it piles up, how it heals and how it
## looks. Independent of quality (map resolution, mesh density, budgets), which lives in
## DeformableSurfaceQuality.

## Label reported by DeformableSurface.contact (e.g. for footstep audio): "snow", "sand", ...
@export var type_name: StringName = &"snow"

## Optional look (colors, textures, roughness, sparkle). Used when DeformableSurface.material is empty.
@export var material: ShaderMaterial

@export_group("Deformation")
## How deep a fully-pressed surface sinks, in meters.
@export_range(0.01, 1.0, 0.01, "suffix:m") var max_depth := 0.4
## 0 disables berms.
@export_range(0.0, 0.5, 0.01) var berm_strength := 0.15
@export_range(0.0, 0.5, 0.01, "suffix:m") var berm_height := 0.08

@export_group("Starting surface")
## Starts with a procedural bumpy surface instead of a flat one. Recovery heals back to it.
@export var initial_noise_enabled := true
## Optional noise. When empty, a cellular dimple pattern is used (see `initial_noise_frequency`).
@export var initial_noise: FastNoiseLite
## Inverts the pattern to create mounds instead of dimples.
@export var initial_noise_invert := false
## Cellular feature scale when `initial_noise` is empty (lower values make larger dimples).
@export_range(0.1, 4.0, 0.1) var initial_noise_frequency := 0.8
## Maximum starting height variation in meters.
@export_range(0.0, 0.5, 0.001, "suffix:m") var initial_noise_height := 0.2
## Second octave: the same noise again at another scale, layered on top.
## This is its weight relative to the main noise (0 = off). Total height stays within `initial_noise_height`.
@export_range(0.0, 1.0, 0.01) var initial_noise_detail := 0.6
## Frequency multiplier of the second octave: below 1 makes broad hills, above 1 adds fine detail.
@export_range(0.1, 8.0, 0.05) var initial_noise_detail_scale := 0.25
## Height of raised piles/dunes (meters) on top of the base noise. Digging into them goes deeper
## than on flat ground. Limited by `max_depth`; 0 = none.
@export_range(0.0, 1.0, 0.01, "suffix:m") var initial_noise_mound_height := 0.3
## Size of the piles: lower values make larger, more widely spaced dunes.
@export_range(0.02, 1.0, 0.01) var initial_noise_mound_frequency := 0.1

@export_group("Recovery")
## 0 = trails stay forever. 1 = trails heal quickly.
@export_range(0.0, 1.0, 0.05) var recovery_intensity := 0.3
@export_range(0.0, 255.0, 1.0) var refill_levels_per_sec := 16.0

@export_group("Look and effects")
@export var puffs_enabled := true
@export_subgroup("Puff look")
## Particle texture. Empty = soft round dot.
@export var puff_texture: Texture2D
## Color over lifetime. Empty = the surface's color fading out.
@export var puff_color_ramp: Gradient
@export_range(0.0, 10.0, 0.05, "suffix:m/s") var puff_velocity_min := 0.6
@export_range(0.0, 10.0, 0.05, "suffix:m/s") var puff_velocity_max := 1.4
@export_subgroup("")
@export var wrapped_diffuse_lighting := true


## Every exported value by name, so new properties never need to be listed by hand.
func to_dictionary() -> Dictionary:
	var values := {}
	for prop in _property_names():
		values[prop] = get(prop)
	return values


## Sets each property present in `values`, then clamps. Returns an error message, or "" if fine.
func apply_dictionary(values: Dictionary) -> String:
	for prop in _property_names():
		if not values.has(prop):
			continue
		var value: Variant = values[prop]
		match typeof(get(prop)):
			TYPE_FLOAT:
				if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
					return "'%s' must be numeric." % prop
				value = float(value)
			TYPE_BOOL:
				if typeof(value) != TYPE_BOOL:
					return "'%s' must be a boolean." % prop
			TYPE_STRING_NAME:
				value = StringName(value)
		set(prop, value)
	clamp_values()
	return ""


func clamp_values() -> void:
	max_depth = maxf(max_depth, 0.01)
	berm_strength = clampf(berm_strength, 0.0, 0.5)
	berm_height = maxf(berm_height, 0.0)
	recovery_intensity = clampf(recovery_intensity, 0.0, 1.0)
	refill_levels_per_sec = maxf(refill_levels_per_sec, 0.0)


func _property_names() -> PackedStringArray:
	var names := PackedStringArray()
	for info in (get_script() as Script).get_script_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			names.append(info["name"])
	return names

