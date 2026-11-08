@tool
class_name DeformableSurfaceType
extends Resource
## What the surface is made of: how deep it sinks, how it piles up, how it heals and how it
## looks. Independent of quality (map resolution, mesh density, budgets), which lives in
## DeformableSurfaceQuality.

## Label reported by DeformableSurface.contact (e.g. for footstep audio): "snow", "sand", ...
@export var type_name: StringName = &"snow":
	set(value):
		if type_name == value:
			return
		type_name = value
		emit_changed()

## Optional look (colors, textures, roughness, sparkle). Used when DeformableSurface.material is empty.
@export var material: ShaderMaterial:
	set(value):
		if material == value:
			return
		material = value
		emit_changed()

@export_group("Deformation")
## How deep a fully-pressed surface sinks, in meters.
@export_range(0.01, 1.0, 0.01, "suffix:m") var max_depth := 0.4:
	set(value):
		if is_equal_approx(max_depth, value):
			return
		max_depth = value
		emit_changed()
## 0 disables berms.
@export_range(0.0, 0.5, 0.01) var berm_strength := 0.15:
	set(value):
		if is_equal_approx(berm_strength, value):
			return
		berm_strength = value
		emit_changed()
@export_range(0.0, 0.5, 0.01, "suffix:m") var berm_height := 0.08:
	set(value):
		if is_equal_approx(berm_height, value):
			return
		berm_height = value
		emit_changed()

@export_group("Starting surface")
## Starts with a procedural bumpy surface instead of a flat one. Recovery heals back to it.
@export var initial_noise_enabled := true:
	set(value):
		if initial_noise_enabled == value:
			return
		initial_noise_enabled = value
		emit_changed()
## Optional noise. When empty, a cellular dimple pattern is used (see `initial_noise_frequency`).
@export var initial_noise: FastNoiseLite:
	set(value):
		if initial_noise == value:
			return
		initial_noise = value
		emit_changed()
## Inverts the pattern to create mounds instead of dimples.
@export var initial_noise_invert := false:
	set(value):
		if initial_noise_invert == value:
			return
		initial_noise_invert = value
		emit_changed()
## Cellular feature scale when `initial_noise` is empty (lower values make larger dimples).
@export_range(0.1, 4.0, 0.1) var initial_noise_frequency := 0.8:
	set(value):
		if is_equal_approx(initial_noise_frequency, value):
			return
		initial_noise_frequency = value
		emit_changed()
## Maximum starting height variation in meters.
@export_range(0.0, 0.5, 0.001, "suffix:m") var initial_noise_height := 0.2:
	set(value):
		if is_equal_approx(initial_noise_height, value):
			return
		initial_noise_height = value
		emit_changed()
## Second octave: the same noise again at another scale, layered on top.
## This is its weight relative to the main noise (0 = off). Total height stays within `initial_noise_height`.
@export_range(0.0, 1.0, 0.01) var initial_noise_detail := 0.6:
	set(value):
		if is_equal_approx(initial_noise_detail, value):
			return
		initial_noise_detail = value
		emit_changed()
## Frequency multiplier of the second octave: below 1 makes broad hills, above 1 adds fine detail.
@export_range(0.1, 8.0, 0.05) var initial_noise_detail_scale := 0.25:
	set(value):
		if is_equal_approx(initial_noise_detail_scale, value):
			return
		initial_noise_detail_scale = value
		emit_changed()
## Height of raised piles/dunes (meters) on top of the base noise. Digging into them goes deeper
## than on flat ground. Limited by `max_depth`; 0 = none.
@export_range(0.0, 1.0, 0.01, "suffix:m") var initial_noise_mound_height := 0.3:
	set(value):
		if is_equal_approx(initial_noise_mound_height, value):
			return
		initial_noise_mound_height = value
		emit_changed()
## Size of the piles: lower values make larger, more widely spaced dunes.
@export_range(0.02, 1.0, 0.01) var initial_noise_mound_frequency := 0.1:
	set(value):
		if is_equal_approx(initial_noise_mound_frequency, value):
			return
		initial_noise_mound_frequency = value
		emit_changed()

@export_group("Recovery")
## 0 = trails stay forever. 1 = trails heal quickly.
@export_range(0.0, 1.0, 0.05) var recovery_intensity := 0.3:
	set(value):
		if is_equal_approx(recovery_intensity, value):
			return
		recovery_intensity = value
		emit_changed()
@export_range(0.0, 255.0, 1.0) var refill_levels_per_sec := 16.0:
	set(value):
		if is_equal_approx(refill_levels_per_sec, value):
			return
		refill_levels_per_sec = value
		emit_changed()

@export_group("Look and effects")
@export var puffs_enabled := true:
	set(value):
		if puffs_enabled == value:
			return
		puffs_enabled = value
		emit_changed()
@export_subgroup("Puff look")
## Particle texture. Empty = soft round dot.
@export var puff_texture: Texture2D:
	set(value):
		if puff_texture == value:
			return
		puff_texture = value
		emit_changed()
## Color over lifetime. Empty = the surface's color fading out.
@export var puff_color_ramp: Gradient:
	set(value):
		if puff_color_ramp == value:
			return
		puff_color_ramp = value
		emit_changed()
@export_range(0.0, 10.0, 0.05, "suffix:m/s") var puff_velocity_min := 0.6:
	set(value):
		if is_equal_approx(puff_velocity_min, value):
			return
		puff_velocity_min = value
		emit_changed()
@export_range(0.0, 10.0, 0.05, "suffix:m/s") var puff_velocity_max := 1.4:
	set(value):
		if is_equal_approx(puff_velocity_max, value):
			return
		puff_velocity_max = value
		emit_changed()
@export_subgroup("")
@export var wrapped_diffuse_lighting := true:
	set(value):
		if wrapped_diffuse_lighting == value:
			return
		wrapped_diffuse_lighting = value
		emit_changed()


func clamp_values() -> void:
	max_depth = maxf(max_depth, 0.01)
	berm_strength = clampf(berm_strength, 0.0, 0.5)
	berm_height = maxf(berm_height, 0.0)
	recovery_intensity = clampf(recovery_intensity, 0.0, 1.0)
	refill_levels_per_sec = maxf(refill_levels_per_sec, 0.0)

