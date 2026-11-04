@tool
@icon("res://addons/deformable_surface/icons/deformable_surface.svg")
class_name DeformableSurface
extends Node3D
## Deformable surface. Drop it in a scene, then add Deformer or
## DeformerFootsteps nodes under anything that should leave marks.
##
## Requirements: area_size must be square; keep the node unrotated and unscaled.
## The surface sits at this node's Y position.
##
## How it works: a hidden 2D SubViewport stores a deformation map (R = combined
## height, G/B = surface slopes). Deformers stamp brushes into it; the surface mesh's
## vertex shader displaces from it and its fragment shader reads height and normals
## in one texture fetch. The viewport only renders when something changed.
## Everything runs on the Compatibility renderer (WebGL2).

signal quality_changed(q: Quality)
## Emitted when a stamp starts touching the surface: a Deformer touchdown (footfall) or a
## `stamp_at` call. `depth` is the nominal signed depth in meters (positive = pressed down,
## negative = raised, 0 = smoothed). `surface_type` comes from the material profile.
## `source` is the Deformer, or null for `stamp_at`. `radius` is the stamp radius in meters.
## Touchdown puffs are spawned from this same event.
signal contact(position: Vector3, depth: float, surface_type: StringName, source: Node, radius: float, puff: bool)

static var instances: Array[DeformableSurface] = []

enum Quality { LOW, MEDIUM, HIGH, CUSTOM }
## How a stamp changes the surface: CARVE presses it down (with berms), RAISE builds it up
## (snow accumulation, piles), SMOOTH flattens it toward neutral (a plow, erasing prints).
enum StampMode { CARVE, RAISE, SMOOTH }

const SurfacePuffs = preload("deformers/deformer_particles.gd")
const SURFACE_SHADER: Shader = preload("../shaders/deformable_surface.gdshader")
const REFILL_SHADER: Shader = preload("../shaders/deformable_surface_refill.gdshader")
const STAMP_SHADER: Shader = preload("../shaders/deformable_surface_stamp.gdshader")
const LOW_SURFACE_QUALITY_DEFAULT = preload("../resources/quality/low_surface.tres")
const MEDIUM_SURFACE_QUALITY_DEFAULT = preload("../resources/quality/medium_surface.tres")
const HIGH_SURFACE_QUALITY_DEFAULT = preload("../resources/quality/high_surface.tres")
const CUSTOM_SURFACE_QUALITY_DEFAULT = preload("../resources/quality/custom_surface.tres")
const BERM_REACH := 2.0     # berm ring radius, in brush radii
const BERM_FORWARD := 0.3   # elongated prints push their berm ahead by this fraction
const MAP_NEUTRAL := 128.0 / 255.0
const STAMP_CAPACITY := 512

@export_group("Surface")
## World size of the surface, in meters (centered on this node). Always square; set through
## the quality profile's `area_size`, which overwrites this value at startup.
var area_size := Vector2(40, 40) : set = set_area_size
## Optional. A ShaderMaterial using shaders/deformable_surface.gdshader, to customize colors and
## sparkle. If empty, a default is created. Each DeformableSurface duplicates it, so one
## resource can be shared. Assign before the node enters the tree.
@export var material: ShaderMaterial : set = set_material
## Optional. What the surface is made of: depth, berms, healing, puffs, lighting and a default
## material. Without one, built-in snow-like defaults are used. Quality profiles only control
## resolution, mesh density, budgets and the sparkle quality scale.
@export var material_profile: DeformableSurfaceMaterialProfile : set = set_material_profile
## Optional. The sun: the sparkle shader follows its direction.
@export var sun: DirectionalLight3D
## Enables wrapped diffuse lighting with cool-tinted shadows on footprint bevels.
var wrapped_diffuse_lighting := true : set = set_wrapped_diffuse_lighting
## How deep a fully-pressed surface sinks, in meters.
var max_depth := 0.4

# Starting surface: copied from the material profile.
var initial_noise_enabled := true
var initial_noise: FastNoiseLite
var initial_noise_invert := false
var initial_noise_frequency := 0.8
var initial_noise_height := 0.2
var initial_noise_detail := 0.6
var initial_noise_detail_scale := 0.25
var initial_noise_mound_height := 0.3
var initial_noise_mound_frequency := 0.1

@export_group("Quality")
## Initial quality profile. auto_quality overrides this when enabled.
@export var quality: Quality = Quality.MEDIUM : set = set_quality
## Surface quality profiles. Each node starts with its own copy of the addon presets, so
## editing them in the Inspector never modifies the shared files in the addon.
@export var low_surface_quality: DeformableSurfaceSettings = LOW_SURFACE_QUALITY_DEFAULT.duplicate()
@export var medium_surface_quality: DeformableSurfaceSettings = MEDIUM_SURFACE_QUALITY_DEFAULT.duplicate()
@export var high_surface_quality: DeformableSurfaceSettings = HIGH_SURFACE_QUALITY_DEFAULT.duplicate()
@export var custom_surface_quality: DeformableSurfaceSettings = CUSTOM_SURFACE_QUALITY_DEFAULT.duplicate()
## If true, picks Low on mobile / mobile browsers, Medium on desktop browsers and
## High elsewhere when the scene starts (overrides `quality`).
@export var auto_quality := false

var max_stamps_per_frame := 64

var berm_strength := 0.15   # 0 disables berms
var berm_height := 0.08                       # meters at full berm

## 0 = trails stay forever. 1 = trails heal quickly. Not exported: the quality profile
## sets it (DeformableSurfaceSettings.recovery_intensity); assigning it at runtime overrides it
## until the next quality change.
var recovery_intensity := 0.3 : set = set_recovery_intensity
## Recovery speed parameter at recovery_intensity = 1; height and slopes heal together.
var refill_levels_per_sec := 16.0
var refill_interval := 0.25   # seconds between refill passes

var puffs_enabled := true
var puff_min_interval := 0.2    # per deformer, seconds

var _active_quality_settings: DeformableSurfaceSettings
var _active_quality_custom := false
var _default_material_profile: DeformableSurfaceMaterialProfile

var _runtime := false          # true once running in the game (not the editor)
var _mat: ShaderMaterial       # our private copy of the material
var _vp: SubViewport
var _bg: Control
var _initial_map_texture: Texture2D
var _initial_noise_cache: ImageTexture
var _initial_noise_cache_key: Array = []
var _applying_profile := false
var _refill: ColorRect
var _refill_material: ShaderMaterial
var _mesh: MeshInstance3D
var _stamp_tex: GradientTexture2D
var _stamp_add_material: ShaderMaterial
var _stamp_multimesh: MultiMesh
var _stamp_instance: MultiMeshInstance2D
var _stamp_batches: Array[Dictionary] = []
var _stamps_used := 0
# Per-frame cost of each operation, read through get_frame_costs().
var _cost_deformers_us := 0
var _cost_queued_us := 0
var _cost_puffs_us := 0
var _cost_stamp_px := 0.0
var _cost_refill_px := 0.0
var _pending_stamps: Array[Dictionary] = []
var _dirty_deformers: Dictionary = {}
var _known := {}       # deformer instance_id -> true (we've connected its tree_exiting)
var _last := {}        # deformer instance_id -> last stamped pixel pos
var _puff_last := {}   # deformer instance_id -> time of last puff (s)
var _puff_acc := {}    # deformer instance_id -> meters since last moving puff
var _rr := 0           # round-robin start index, so a full stamp budget can't starve anyone
var _prime_frames := 0
var _refill_timer := 0.0
var _refill_idle := 0.0   # seconds since the last stamp
var _sun_dir := Vector3.ZERO
var _puffs: SurfacePuffs


## A sensible default for the current platform.
static func recommended_quality() -> Quality:
	if OS.has_feature("web"):
		var mobile = JavaScriptBridge.eval("/Android|iPhone|iPad/i.test(navigator.userAgent)")
		return Quality.LOW if mobile else Quality.MEDIUM
	if OS.has_feature("mobile"):
		return Quality.LOW
	return Quality.HIGH


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	if not instances.has(self):
		instances.append(self)
	for deformer in Deformer.unassigned:
		_register_deformer(deformer)
	for deformer in Deformer.assigned.get(get_instance_id(), []):
		_register_deformer(deformer)


func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_preview()
		return

	if not contact.is_connected(_on_contact_puff):
		contact.connect(_on_contact_puff)
	_adopt_material()
	if auto_quality:
		quality = recommended_quality()
	if custom_surface_quality == null:
		push_error("DeformableSurface: custom surface quality profile is not assigned.")
		return
	custom_surface_quality = custom_surface_quality.duplicate(true) as DeformableSurfaceSettings
	if not _set_active_quality_profile(quality):
		return
	_apply_profile_values(_active_quality_settings)
	_apply_material_profile_values()

	_make_brushes()

	_vp = SubViewport.new()
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED   # _process requests UPDATE_ONCE
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	add_child(_vp)

	# Draw order inside the map: bg, refill pass, then stamps.
	_refill = _make_refill_rect(REFILL_SHADER)
	_stamp_instance = MultiMeshInstance2D.new()
	_stamp_instance.multimesh = _stamp_multimesh
	_stamp_instance.texture = _stamp_tex
	_stamp_instance.material = _stamp_add_material
	_vp.add_child(_stamp_instance)
	_stamp_batches.append({
		"texture": null,
		"multimesh": _stamp_multimesh,
		"instance": _stamp_instance,
		"used": 0,
	})

	_mesh = MeshInstance3D.new()
	_mesh.extra_cull_margin = 2.0   # vertices get displaced away from the flat AABB
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

	_runtime = true
	_configure_quality(null)
	_clear_map()
	quality_changed.emit(quality)


func _exit_tree() -> void:
	instances.erase(self)
	_dirty_deformers.clear()


func _register_deformer(deformer: Deformer) -> void:
	if not is_instance_valid(deformer):
		return
	_dirty_deformers[deformer.get_instance_id()] = deformer


func _unregister_deformer(deformer: Deformer) -> void:
	if is_instance_valid(deformer):
		_dirty_deformers.erase(deformer.get_instance_id())


func _mark_deformer_dirty(deformer: Deformer) -> void:
	_register_deformer(deformer)


# ------------------------------------------------------------------ public API

## Reconfiguring quality preserves trails unless their encoding scale changes.
func set_quality(q: Quality) -> void:
	if q < Quality.LOW or q > Quality.CUSTOM:
		push_error("DeformableSurface: invalid quality preset.")
		return

	var profile := _quality_profile(q)
	if profile == null:
		push_error("DeformableSurface: quality profile is not assigned.")
		return
	var quality_changed_now := q != quality
	var settings_changed: bool = (
		_active_quality_custom != (q == Quality.CUSTOM)
		or _active_quality_settings == null
		or _active_quality_settings.to_dictionary() != profile.to_dictionary()
	)
	var previous := _active_quality_settings
	var map_resolution_changed: bool = (
		previous == null
		or previous.res != profile.res
	)
	var height_encoding_changed: bool = (
		previous == null
		or not is_equal_approx(previous.area_size, profile.area_size)
	)
	quality = q
	if settings_changed:
		_active_quality_settings = profile.duplicate(true) as DeformableSurfaceSettings
	_active_quality_custom = q == Quality.CUSTOM
	_apply_profile_values(profile)
	if _runtime and (quality_changed_now or settings_changed):
		_configure_quality(previous)
		if map_resolution_changed or height_encoding_changed:
			_clear_map()
		if quality_changed_now:
			quality_changed.emit(quality)


## Flat dictionary of a quality preset's technical settings plus the current material
## profile's values (used by settings UIs).
func get_quality_settings(q: Quality) -> Dictionary:
	if q < Quality.LOW or q > Quality.CUSTOM:
		push_error("DeformableSurface: invalid quality preset.")
		return {}
	var profile := _quality_profile(q)
	if profile == null:
		push_error("DeformableSurface: quality profile is not assigned.")
		return {}
	var settings := profile.to_dictionary()
	settings.merge(_effective_material_profile().to_dictionary(), true)
	return settings


func get_surface_quality_settings(q: Quality) -> DeformableSurfaceSettings:
	if q < Quality.LOW or q > Quality.CUSTOM:
		push_error("DeformableSurface: invalid quality preset.")
		return null
	var profile := _quality_profile(q)
	if profile == null:
		push_error("DeformableSurface: surface quality profile is not assigned.")
		return null
	return profile.duplicate(true) as DeformableSurfaceSettings


func apply_surface_quality_settings(settings: DeformableSurfaceSettings) -> void:
	if settings == null:
		push_error("DeformableSurface: surface quality settings are not assigned.")
		return
	custom_surface_quality = settings.duplicate(true) as DeformableSurfaceSettings
	set_quality(Quality.CUSTOM)


func get_active_quality_settings() -> Dictionary:
	if _active_quality_settings == null:
		return {}
	var settings := _active_quality_settings.to_dictionary()
	settings["area_size"] = area_size.x
	settings["max_depth"] = max_depth
	settings["berm_strength"] = berm_strength
	settings["berm_height"] = berm_height
	settings["max_stamps_per_frame"] = max_stamps_per_frame
	settings["recovery_intensity"] = recovery_intensity
	settings["refill_levels_per_sec"] = refill_levels_per_sec
	settings["refill_interval"] = refill_interval
	settings["puffs_enabled"] = puffs_enabled
	settings["puff_min_interval"] = puff_min_interval
	settings["wrapped_diffuse_lighting"] = wrapped_diffuse_lighting
	return settings


func has_custom_quality_settings() -> bool:
	return _active_quality_custom


func apply_quality_settings(settings: Dictionary) -> void:
	if custom_surface_quality == null:
		push_error("DeformableSurface: custom surface quality profile is not assigned.")
		return
	var required := ["res", "subdiv", "sparkle", "puff"]
	for key in required:
		if not settings.has(key):
			push_error("DeformableSurface: custom quality settings are missing '%s'." % key)
			return
	for key in [
		"res", "subdiv", "sparkle", "puff", "area_size", "max_depth",
		"berm_strength", "berm_height", "max_stamps_per_frame",
		"recovery_intensity", "refill_levels_per_sec", "refill_interval",
		"puff_min_interval",
	]:
		if not settings.has(key):
			continue
		var type := typeof(settings[key])
		if type != TYPE_INT and type != TYPE_FLOAT:
			push_error("DeformableSurface: custom quality setting '%s' must be numeric." % key)
			return
	for key in ["puffs_enabled", "wrapped_diffuse_lighting"]:
		if settings.has(key) and typeof(settings[key]) != TYPE_BOOL:
			push_error("DeformableSurface: custom quality setting '%s' must be a boolean." % key)
			return

	var updated := custom_surface_quality.duplicate(true) as DeformableSurfaceSettings
	if updated == null:
		push_error("DeformableSurface: custom surface quality profile could not be duplicated.")
		return
	updated.res = clampi(roundi(float(settings["res"])), 128, 2048)
	updated.subdiv = clampi(roundi(float(settings["subdiv"])), 1, 512)
	updated.sparkle = clampf(float(settings["sparkle"]), 0.0, 3.0)
	updated.puff = clampi(roundi(float(settings["puff"])), 1, 64)
	updated.area_size = maxf(float(settings.get("area_size", updated.area_size)), 1.0)
	updated.max_stamps_per_frame = maxi(roundi(float(settings.get(
		"max_stamps_per_frame", updated.max_stamps_per_frame
	))), 1)
	updated.refill_interval = maxf(float(settings.get("refill_interval", updated.refill_interval)), 0.05)
	updated.puff_min_interval = maxf(
		float(settings.get("puff_min_interval", updated.puff_min_interval)),
		0.0
	)
	custom_surface_quality = updated
	set_quality(Quality.CUSTOM)

	var current := _effective_material_profile()
	var updated_material := current.duplicate() as DeformableSurfaceMaterialProfile
	updated_material.max_depth = maxf(float(settings.get("max_depth", current.max_depth)), 0.01)
	updated_material.berm_strength = clampf(float(settings.get("berm_strength", current.berm_strength)), 0.0, 0.5)
	updated_material.berm_height = maxf(float(settings.get("berm_height", current.berm_height)), 0.0)
	updated_material.recovery_intensity = clampf(
		float(settings.get("recovery_intensity", current.recovery_intensity)), 0.0, 1.0
	)
	updated_material.refill_levels_per_sec = maxf(float(settings.get(
		"refill_levels_per_sec", current.refill_levels_per_sec
	)), 0.0)
	updated_material.puffs_enabled = bool(settings.get("puffs_enabled", current.puffs_enabled))
	updated_material.wrapped_diffuse_lighting = bool(
		settings.get("wrapped_diffuse_lighting", current.wrapped_diffuse_lighting)
	)
	if updated_material.to_dictionary() != current.to_dictionary():
		set_material_profile(updated_material)


func _quality_profile(q: Quality) -> DeformableSurfaceSettings:
	var surface_profile: DeformableSurfaceSettings
	match q:
		Quality.LOW:
			surface_profile = low_surface_quality
		Quality.MEDIUM:
			surface_profile = medium_surface_quality
		Quality.HIGH:
			surface_profile = high_surface_quality
		Quality.CUSTOM:
			surface_profile = custom_surface_quality
		_:
			return null
	return surface_profile


func _set_active_quality_profile(q: Quality) -> bool:
	var profile := _quality_profile(q)
	if profile == null:
		push_error("DeformableSurface: quality profile is not assigned.")
		return false
	_active_quality_settings = profile.duplicate(true) as DeformableSurfaceSettings
	_active_quality_custom = q == Quality.CUSTOM
	return true


func _apply_profile_values(profile: DeformableSurfaceSettings) -> void:
	_applying_profile = true
	area_size = Vector2.ONE * maxf(profile.area_size, 1.0)
	_applying_profile = false
	max_stamps_per_frame = maxi(profile.max_stamps_per_frame, 1)
	refill_interval = maxf(profile.refill_interval, 0.05)
	puff_min_interval = maxf(profile.puff_min_interval, 0.0)


## The assigned material profile, or the built-in defaults (snow-like) when none is set.
func _effective_material_profile() -> DeformableSurfaceMaterialProfile:
	if material_profile != null:
		return material_profile
	if _default_material_profile == null:
		_default_material_profile = DeformableSurfaceMaterialProfile.new()
	return _default_material_profile


func _apply_material_profile_values() -> void:
	var p := _effective_material_profile()
	max_depth = maxf(p.max_depth, 0.01)
	berm_strength = clampf(p.berm_strength, 0.0, 0.5)
	berm_height = maxf(p.berm_height, 0.0)
	recovery_intensity = clampf(p.recovery_intensity, 0.0, 1.0)
	refill_levels_per_sec = maxf(p.refill_levels_per_sec, 0.0)
	puffs_enabled = p.puffs_enabled
	wrapped_diffuse_lighting = p.wrapped_diffuse_lighting
	initial_noise_enabled = p.initial_noise_enabled
	initial_noise = p.initial_noise
	initial_noise_invert = p.initial_noise_invert
	initial_noise_frequency = p.initial_noise_frequency
	initial_noise_height = p.initial_noise_height
	initial_noise_detail = p.initial_noise_detail
	initial_noise_detail_scale = p.initial_noise_detail_scale
	initial_noise_mound_height = p.initial_noise_mound_height
	initial_noise_mound_frequency = p.initial_noise_mound_frequency

## Stamps drawn this frame, out of `max_stamps_per_frame` (for performance readouts).
func get_stamps_used() -> int:
	return _stamps_used


## What this frame cost, per operation, for performance readouts. CPU values are milliseconds.
## GPU values are estimates in millions of map pixels shaded: `stamp_mpx` is every stamp's quad
## (including its berm margin, so overdraw counts), `refill_mpx` is the full-map recovery pass.
func get_frame_costs() -> Dictionary:
	var verts := 0.0
	if _active_quality_settings != null:
		verts = pow(_active_quality_settings.subdiv + 1.0, 2.0)
	return {
		"deformers_ms": _cost_deformers_us / 1000.0,
		"queued_ms": _cost_queued_us / 1000.0,
		"puffs_ms": _cost_puffs_us / 1000.0,
		"stamp_mpx": _cost_stamp_px / 1000000.0,
		"refill_mpx": _cost_refill_px / 1000000.0,
		"mesh_kverts": verts / 1000.0,
	}


## Wipes all trails. Cheap: does not touch the mesh, material or particles.
func reset_trails() -> void:
	if _runtime:
		_pending_stamps.clear()
		_clear_map()


## One-shot stamp at a world position: explosions, impacts, falling objects, a snow plow
## blade. No Deformer needed. Ignores the Y position; positions outside the area are dropped.
## `strength` is 0..1, `shape` an optional alpha-mask footprint, `mode` a StampMode,
## `heading` the yaw in radians (matters for `shape` and `aspect` > 1), `puff` kicks up
## a particle burst, `silent` skips the `contact` signal. Stamps are queued and drawn within
## the per-frame stamp budget.
func stamp_at(
	world_pos: Vector3,
	radius := 0.5,
	strength := 1.0,
	shape: Texture2D = null,
	mode := StampMode.CARVE,
	heading := 0.0,
	aspect := 1.0,
	puff := false,
	silent := false
) -> void:
	if not _runtime:
		return
	var local := to_local(world_pos)
	var reach := radius * (1.0 + BERM_REACH) * maxf(aspect, 1.0)
	if absf(local.x) > area_size.x * 0.5 + reach or absf(local.z) > area_size.y * 0.5 + reach:
		return
	_pending_stamps.append({
		"local": local, "radius": maxf(radius, 0.01), "strength": clampf(strength, 0.0, 1.0),
		"shape": shape, "mode": mode, "heading": heading, "aspect": maxf(aspect, 1.0),
		"puff": puff, "silent": silent, "track": false, "phase": 0.0,
	})


## One continuous strip of track from `from` to `to`: flat-bottomed, with side ridges only.
## `shape` is an alpha-mask tread whose top edge faces the direction of travel; one tile is
## `width` * (texture height / texture width) meters long. `phase` is how many tiles of tread
## precede `from` along the path (running distance / tile length), so consecutive segments
## continue the same pattern. Used by DeformerTracks.
func stamp_segment(
	from: Vector3,
	to: Vector3,
	width := 0.3,
	strength := 1.0,
	shape: Texture2D = null,
	mode := StampMode.CARVE,
	phase := 0.0
) -> void:
	if not _runtime:
		return
	var delta := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var length := delta.length()
	if length < 0.001:
		return
	var mid := to_local((from + to) * 0.5)
	var half_len := length * 0.5
	var half_w := maxf(width, 0.02) * 0.5
	if shape != null:
		# The shader samples the tread relative to the segment center.
		phase += half_len / (width * float(shape.get_height()) / float(shape.get_width()))
	var reach := (half_len + half_w) * (1.0 + BERM_REACH)
	if absf(mid.x) > area_size.x * 0.5 + reach or absf(mid.z) > area_size.y * 0.5 + reach:
		return
	_pending_stamps.append({
		"local": mid, "radius": sqrt(half_len * half_w), "strength": clampf(strength, 0.0, 1.0),
		"shape": shape, "mode": mode, "heading": atan2(delta.z, delta.x), "aspect": half_len / half_w,
		"puff": false, "silent": true, "track": true, "phase": phase,
	})


## Every contact goes through here. Puffs are spawned by a listener on `contact`.
func _emit_contact(world_pos: Vector3, strength: float, mode: int, source: Node, radius: float, puff: bool) -> void:
	var depth := strength * max_depth
	if mode == StampMode.RAISE:
		depth = -depth
	elif mode == StampMode.SMOOTH:
		depth = 0.0
		puff = false
	contact.emit(world_pos, depth, _effective_material_profile().surface_type, source, radius, puff)


func _on_contact_puff(world_pos: Vector3, _depth: float, _surface_type: StringName,
		source: Node, radius: float, puff: bool) -> void:
	if puff:
		_spawn_puff(world_pos, radius, Vector3.ZERO, source)


func _flush_pending_stamps(res: Vector2, px_per_m: float) -> void:
	var remaining: Array[Dictionary] = []
	for s in _pending_stamps:
		var local: Vector3 = s["local"]
		var pos := (Vector2(local.x, local.z) / area_size + Vector2(0.5, 0.5)) * res
		if _prime_frames > 0 or not _stamp(
			pos, float(s["radius"]) * px_per_m, float(s["heading"]), float(s["aspect"]),
			float(s["strength"]), false, s["shape"], false, s["mode"], bool(s["track"]), float(s["phase"])
		):
			remaining.append(s)
			continue
		if not s["silent"]:
			_emit_contact(to_global(Vector3(local.x, 0.0, local.z)), float(s["strength"]), int(s["mode"]),
					null, float(s["radius"]), bool(s["puff"]))
	_pending_stamps = remaining


func set_recovery_intensity(value: float) -> void:
	recovery_intensity = clampf(value, 0.0, 1.0)


func set_wrapped_diffuse_lighting(enabled: bool) -> void:
	if wrapped_diffuse_lighting == enabled:
		return
	wrapped_diffuse_lighting = enabled
	if _mat:
		_mat.set_shader_parameter("wrapped_diffuse_lighting", enabled)


func set_area_size(v: Vector2) -> void:
	var new_size := v.max(Vector2(1.0, 1.0))
	if area_size.is_equal_approx(new_size):
		return
	area_size = new_size
	if Engine.is_editor_hint():
		_refresh_preview()
		update_configuration_warnings()
	elif _runtime and not _applying_profile:
		_configure_mesh()
		_clear_map()


func set_material(m: ShaderMaterial) -> void:
	if material == m:
		return
	material = m
	if Engine.is_editor_hint():
		_refresh_preview()
	elif _runtime:
		_adopt_material()
		_configure_material()
		_configure_particles()
		_sun_dir = Vector3.ZERO   # force the sun direction to be re-applied


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if absf(area_size.x - area_size.y) > 0.01:
		w.append("area_size should be square.")
	if not global_basis.is_equal_approx(Basis.IDENTITY):
		w.append("Keep the DeformableSurface unrotated and unscaled (also its parents).")
	return w


# ------------------------------------------------------------------ editor preview

## In the editor, show a flat plane so the area is visible and placeable.
func _refresh_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _mesh == null:
		_mesh = MeshInstance3D.new()
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh)   # no owner set: not saved with the scene, hidden from the dock
	var plane := PlaneMesh.new()
	plane.size = area_size
	_mesh.mesh = plane
	var m: ShaderMaterial
	var source := _source_material()
	if source != null:
		m = source.duplicate() as ShaderMaterial
	else:
		m = ShaderMaterial.new()
		m.shader = SURFACE_SHADER
	var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
	img.fill(Color(MAP_NEUTRAL, MAP_NEUTRAL, MAP_NEUTRAL))
	m.set_shader_parameter("deform_map", ImageTexture.create_from_image(img))
	m.set_shader_parameter("wrapped_diffuse_lighting", _effective_material_profile().wrapped_diffuse_lighting)


# ------------------------------------------------------------------ setup

func _adopt_material() -> void:
	var source := _source_material()
	if source != null:
		_mat = source.duplicate() as ShaderMaterial
	else:
		_mat = ShaderMaterial.new()
		_mat.shader = SURFACE_SHADER


func _source_material() -> ShaderMaterial:
	if material != null:
		return material
	if material_profile != null:
		return material_profile.material
	return null


func set_material_profile(p: DeformableSurfaceMaterialProfile) -> void:
	if material_profile == p:
		return
	var previous_source := _source_material()
	var previous_depth := max_depth
	var previous_berm_height := berm_height
	var previous_noise_key := _starting_surface_key()
	material_profile = p
	if Engine.is_editor_hint():
		_refresh_preview()
		return
	if not _runtime:
		return
	_apply_material_profile_values()
	if _source_material() != previous_source:
		_adopt_material()
	_configure_material()
	_configure_stamp_material(_stamp_add_material)
	_configure_particles()
	_sun_dir = Vector3.ZERO   # force the sun direction to be re-applied
	if not is_equal_approx(previous_depth, max_depth) \
			or not is_equal_approx(previous_berm_height, berm_height) \
			or previous_noise_key != _starting_surface_key():
		_clear_map()


func _starting_surface_key() -> Array:
	return [initial_noise_enabled, _initial_noise_key(512)]


func _make_refill_rect(shader: Shader) -> ColorRect:
	var r := ColorRect.new()
	var m := ShaderMaterial.new()
	m.shader = shader
	r.material = m
	_refill_material = m
	r.visible = false
	_vp.add_child(r)
	return r


func _make_brushes() -> void:
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color.WHITE)
	_stamp_tex = GradientTexture2D.new()
	_stamp_tex.gradient = g
	_stamp_tex.width = 1
	_stamp_tex.height = 1
	_stamp_add_material = ShaderMaterial.new()
	_stamp_add_material.shader = STAMP_SHADER
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_stamp_multimesh = MultiMesh.new()
	_stamp_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_stamp_multimesh.use_colors = true
	_stamp_multimesh.use_custom_data = true
	_stamp_multimesh.mesh = quad
	_stamp_multimesh.instance_count = mini(max_stamps_per_frame, STAMP_CAPACITY)
	_stamp_multimesh.visible_instance_count = 0

## Applies the quality preset: map size, mesh density, shader params, particle counts.
func _configure_quality(previous: DeformableSurfaceSettings) -> void:
	var current := _active_quality_settings
	var map_changed := previous == null or previous.res != current.res
	if map_changed:
		_configure_deformation_map()

	var plane := _mesh.mesh as PlaneMesh
	if (plane == null
			or not plane.size.is_equal_approx(area_size)
			or plane.subdivide_width != current.subdiv
			or plane.subdivide_depth != current.subdiv):
		_configure_mesh()

	if (previous == null
			or map_changed
			or not is_equal_approx(previous.sparkle, current.sparkle)):
		_configure_material()
	if previous == null or map_changed:
		_configure_stamp_material(_stamp_add_material)
	if (previous == null
			or previous.max_stamps_per_frame != current.max_stamps_per_frame):
		_configure_stamp_capacity()
	if previous == null or previous.puff != current.puff:
		_configure_particles()


func _configure_deformation_map() -> void:
	var res: int = _active_quality_settings.res
	_vp.size = Vector2i(res, res)
	_refill.size = Vector2(res, res)


func _configure_mesh() -> void:
	var plane := PlaneMesh.new()
	plane.size = area_size
	plane.subdivide_width = _active_quality_settings.subdiv
	plane.subdivide_depth = _active_quality_settings.subdiv
	_mesh.mesh = plane


func _configure_material() -> void:
	_mesh.material_override = _mat
	_mat.set_shader_parameter("deform_map", _vp.get_texture())
	_mat.set_shader_parameter("max_depth", max_depth)
	_mat.set_shader_parameter("sparkle_intensity", _active_quality_settings.sparkle)
	_mat.set_shader_parameter("wrapped_diffuse_lighting", wrapped_diffuse_lighting)


func _configure_particles() -> void:
	if not puffs_enabled:
		if is_instance_valid(_puffs):
			_puffs.queue_free()
			_puffs = null
		return
	if is_instance_valid(_puffs):
		_puffs.set_amount(_active_quality_settings.puff)
		_apply_puff_look()


## Puffs follow the surface: profile texture/ramp, else the surface color fading out.
func _apply_puff_look() -> void:
	var p := _effective_material_profile()
	var texture := p.puff_texture
	if texture == null and _mat != null:
		var albedo_texture: Variant = _mat.get_shader_parameter("albedo_texture")
		if albedo_texture is Texture2D:
			texture = albedo_texture
	var ramp := p.puff_color_ramp
	if ramp == null:
		var surface_color := Color(0.9, 0.93, 0.98)
		var albedo_tint := Color.WHITE
		if _mat != null:
			surface_color = _material_color("surface_color", surface_color)
			albedo_tint = _material_color("albedo_tint", albedo_tint)
		ramp = Gradient.new()
		var puff_color := Color(
			surface_color.r * albedo_tint.r,
			surface_color.g * albedo_tint.g,
			surface_color.b * albedo_tint.b
		)
		ramp.set_color(0, Color(puff_color, 0.85))
		ramp.set_color(1, Color(puff_color, 0.0))
	_puffs.configure(texture, ramp, p.puff_velocity_min, p.puff_velocity_max)


func _material_color(parameter: StringName, default: Color) -> Color:
	var value: Variant = _mat.get_shader_parameter(parameter)
	if value is Color:
		return value
	if value is Vector3:
		return Color(value.x, value.y, value.z)
	return default


func _configure_stamp_capacity() -> void:
	var capacity := mini(max_stamps_per_frame, STAMP_CAPACITY)
	for batch in _stamp_batches:
		var multimesh := batch["multimesh"] as MultiMesh
		if multimesh.instance_count != capacity:
			multimesh.instance_count = capacity


func _configure_stamp_material(stamp_material: ShaderMaterial) -> void:
	stamp_material.set_shader_parameter("berm_strength", berm_strength)
	stamp_material.set_shader_parameter("berm_height_ratio", berm_height / maxf(max_depth, 0.01))
	stamp_material.set_shader_parameter("map_resolution", float(_vp.size.x))


## Restores the starting surface and clears tracks.
func _clear_map() -> void:
	if is_instance_valid(_bg):
		_bg.queue_free()
	if initial_noise_enabled:
		_initial_map_texture = _get_initial_noise_texture()
		var background := TextureRect.new()
		background.texture = _initial_map_texture
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_SCALE
		background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		background.size = Vector2(_vp.size)
		_bg = background
	else:
		_initial_map_texture = null
		var background := ColorRect.new()
		background.color = Color(MAP_NEUTRAL, MAP_NEUTRAL, MAP_NEUTRAL)
		background.size = Vector2(_vp.size)
		_bg = background
	_refill_material.set_shader_parameter("recovery_target", _initial_map_texture)
	_refill_material.set_shader_parameter("recovery_target_enabled", initial_noise_enabled)
	_vp.add_child(_bg)
	_vp.move_child(_bg, 0)
	_prime_frames = 3
	_refill_timer = 0.0
	_refill_idle = 0.0
	_puff_acc.clear()
	for deformer in Deformer.unassigned:
		_register_deformer(deformer)
	for deformer in Deformer.assigned.get(get_instance_id(), []):
		_register_deformer(deformer)


func _initial_noise_key(resolution: int) -> Array:
	var noise_key: Array = [null]
	if initial_noise != null:
		noise_key = [
			initial_noise, initial_noise.seed, initial_noise.frequency,
			initial_noise.noise_type, initial_noise.fractal_type,
		]
	return [
		resolution, area_size, max_depth, initial_noise_invert,
		initial_noise_frequency, initial_noise_height, noise_key,
		initial_noise_detail, initial_noise_detail_scale,
		initial_noise_mound_height, initial_noise_mound_frequency,
	]


## Regenerating is a per-pixel GDScript loop, so reuse the texture while its inputs are unchanged.
func _get_initial_noise_texture() -> Texture2D:
	var key := _initial_noise_key(mini(_vp.size.x, 512))
	if _initial_noise_cache == null or _initial_noise_cache_key != key:
		_initial_noise_cache = ImageTexture.create_from_image(_make_initial_noise_image())
		_initial_noise_cache_key = key
	return _initial_noise_cache


func _make_initial_noise_image() -> Image:
	var resolution := mini(_vp.size.x, 512)
	var pixel_count := resolution * resolution
	var noise := initial_noise
	if noise == null:
		noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_CELLULAR
		noise.frequency = maxf(initial_noise_frequency, 0.01)
		noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN_SQUARED
		noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		noise.cellular_jitter = 0.9

	# Second octave: a finer copy of the same noise with its own seed so the two don't line up.
	var detail := clampf(initial_noise_detail, 0.0, 1.0)
	var fine_noise: FastNoiseLite = null
	if detail > 0.0:
		fine_noise = noise.duplicate() as FastNoiseLite
		fine_noise.seed = noise.seed + 1013
		fine_noise.frequency = noise.frequency * maxf(initial_noise_detail_scale, 0.05)
	# Mounds only rise above the base surface, leaving flat ground between piles/dunes.
	# A stamp carves down to a fixed floor, so these are the places that can be dug deepest.
	var mound_height := clampf(initial_noise_mound_height, 0.0, max_depth)
	var mound_noise: FastNoiseLite = null
	if mound_height > 0.0:
		mound_noise = FastNoiseLite.new()
		mound_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		mound_noise.seed = noise.seed + 7919
		mound_noise.frequency = maxf(initial_noise_mound_frequency, 0.005)
	var heights := PackedFloat32Array()
	heights.resize(pixel_count)
	var image := Image.create(resolution, resolution, false, Image.FORMAT_RGB8)
	var height_amplitude := clampf(initial_noise_height, 0.0, max_depth)
	var pixel_world_size_x := area_size.x / float(resolution - 1)
	var pixel_world_size_z := area_size.y / float(resolution - 1)
	for y in resolution:
		var world_z := (float(y) / float(resolution - 1) - 0.5) * area_size.y
		for x in resolution:
			var world_x := (float(x) / float(resolution - 1) - 0.5) * area_size.x
			var noise_value := noise.get_noise_2d(world_x, world_z)
			if fine_noise != null:
				# Normalized so the combined height still peaks at initial_noise_height.
				noise_value = (noise_value + detail * fine_noise.get_noise_2d(world_x, world_z)) / (1.0 + detail)
			if initial_noise_invert:
				noise_value = -noise_value
			var height := noise_value * height_amplitude
			if mound_noise != null:
				var mound := smoothstep(-0.1, 0.6, mound_noise.get_noise_2d(world_x, world_z))
				height = minf(height + mound * mound_height, max_depth)
			heights[y * resolution + x] = height

	for y in resolution:
		var previous_y := maxi(y - 1, 0)
		var next_y := mini(y + 1, resolution - 1)
		for x in resolution:
			var previous_x := maxi(x - 1, 0)
			var next_x := mini(x + 1, resolution - 1)
			var height := heights[y * resolution + x]
			var slope_x := (
				heights[y * resolution + next_x] - heights[y * resolution + previous_x]
			) / (float(next_x - previous_x) * pixel_world_size_x)
			var slope_z := (
				heights[next_y * resolution + x] - heights[previous_y * resolution + x]
			) / (float(next_y - previous_y) * pixel_world_size_z)
			image.set_pixel(
				x,
				y,
				Color(
					MAP_NEUTRAL + height / (2.0 * max_depth),
					MAP_NEUTRAL + slope_x / 16.0,
					MAP_NEUTRAL + slope_z / 16.0
				)
			)
	return image


func _forget(id: int) -> void:
	_known.erase(id)
	_last.erase(id)
	_dirty_deformers.erase(id)
	_puff_last.erase(id)
	_puff_acc.erase(id)


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if not _runtime:
		return

	if is_instance_valid(sun):
		var dir := sun.global_basis.z.normalized()   # direction TOWARD the light
		if not dir.is_equal_approx(_sun_dir):
			_sun_dir = dir
			_mat.set_shader_parameter("sun_dir", dir)

	_stamps_used = 0
	_cost_puffs_us = 0
	_cost_stamp_px = 0.0
	_cost_refill_px = 0.0
	for batch in _stamp_batches:
		batch["used"] = 0

	var list: Array = []
	var n := _dirty_deformers.size()
	var res := Vector2(_vp.size)
	var px_per_m := res.x / area_size.x
	var queued_start := Time.get_ticks_usec()
	if not _pending_stamps.is_empty():
		_flush_pending_stamps(res, px_per_m)
	_cost_queued_us = Time.get_ticks_usec() - queued_start
	var deformers_start := Time.get_ticks_usec()
	if n > 0:
		list = _dirty_deformers.values()
	for k in n:
		var d := list[(k + _rr) % n] as Deformer
		if not is_instance_valid(d):
			continue
		var id := d.get_instance_id()
		if not _known.has(id):
			_known[id] = true
			d.tree_exiting.connect(_forget.bind(id), CONNECT_ONE_SHOT)

		if _prime_frames > 0:
			continue   # the clear background is still being rendered

		if not d.active:
			_last.erase(id)   # lifted: next touchdown starts a fresh print
			_dirty_deformers.erase(id)
			continue
		if d.strength <= 0.0:
			_last.erase(id)
			_dirty_deformers.erase(id)
			continue
		var local := to_local(d.global_position)
		if local.y > max_depth or absf(local.x) > area_size.x * 0.5 or absf(local.z) > area_size.y * 0.5:
			_last.erase(id)
			_dirty_deformers.erase(id)
			continue
		var depth_ratio := clampf(1.0 - (local.y / max_depth), 0.1, 1.0)
		var effective_strength := d.strength * depth_ratio
		var pos := (Vector2(local.x, local.z) / area_size + Vector2(0.5, 0.5)) * res
		var r_px := maxf(d.radius, 0.01) * px_per_m
		var heading := d.map_heading()
		var aspect := maxf(d.aspect, 1.0)

		# `done` = the last position we actually finished stamping. If the stamp
		# budget runs out mid-trail we only advance that far, and pick up from
		# there next frame instead of leaving a gap.
		var done := pos
		if _last.has(id):
			var prev: Vector2 = _last[id]
			var dist := prev.distance_to(pos)
			if dist < r_px * 0.15:
				_dirty_deformers.erase(id)
				continue
			# Keep elongated prints (boots/skis) aligned to node heading; orient round prints to travel
			var move_heading := heading if (aspect > 1.05 or d.stamp_texture != null) else (pos - prev).angle()
			if dist > r_px * 20.0:
				if not _stamp(pos, r_px, heading, aspect, effective_strength, false, d.stamp_texture, d.stamp_flip_x, d.mode):
					continue
			else:
				done = prev
				if aspect <= 1.05 and d.stamp_texture == null:
					# Round brush: one capsule (segment with a rounded front) per move, so the
					# trail is a single continuous corridor at any speed.
					var half_len := dist * 0.5
					if not _stamp(prev.lerp(pos, 0.5), sqrt(half_len * r_px), move_heading,
							half_len / r_px, effective_strength, false, null, false, d.mode, false, 0.0, true):
						continue
					done = pos
				else:
					# Half-radius spacing across the whole move; the stamp budget still bounds
					# the cost and resumes from `done` next frame.
					var steps := clampi(ceili(dist / (r_px * 0.5)), 1, 40)
					for s in range(1, steps + 1):
						var sp := prev.lerp(pos, float(s) / steps)
						if not _stamp(sp, r_px, move_heading, aspect, effective_strength, true, d.stamp_texture, d.stamp_flip_x, d.mode):
							break
						done = sp
					if done == prev:
						continue
				if d.puff_distance > 0.0:
					var stamped_move := done - prev
					var acc: float = _puff_acc.get(id, 0.0) + stamped_move.length() / px_per_m
					if acc >= d.puff_distance:
						acc = 0.0
						_try_puff(d, id, -Vector3(stamped_move.x, 0.0, stamped_move.y))
					_puff_acc[id] = acc
		else:
			if not _stamp(pos, r_px, heading, aspect, effective_strength, false, d.stamp_texture, d.stamp_flip_x, d.mode):
				continue
			_emit_contact(d.global_position, effective_strength, d.mode, d, d.radius, d.puff_on_touchdown)
		_last[id] = done
		if done.distance_to(pos) < 0.001:
			_dirty_deformers.erase(id)

	# Puffs spawned inside the loop are timed separately, so take them out of this figure.
	_cost_deformers_us = maxi(Time.get_ticks_usec() - deformers_start - _cost_puffs_us, 0)

	if n > 0:
		_rr = (_rr + 1) % n

	for batch in _stamp_batches:
		var multimesh := batch["multimesh"] as MultiMesh
		var visible_count: int = batch["used"]
		if multimesh.visible_instance_count != visible_count:
			multimesh.visible_instance_count = visible_count

	# Surface recovery: a few times per second, not every frame, and only until the map has
	# healed after the last stamp (about 5.5 time constants covers 8-bit precision).
	if _stamps_used > 0 or _prime_frames > 0:
		_refill_idle = 0.0
	else:
		_refill_idle += delta
	var refill_now := false
	var refill_dt := 0.0
	var heal_rate := 4.0 * recovery_intensity * refill_levels_per_sec / 255.0
	if heal_rate > 0.0001 and recovery_intensity > 0.001 and _prime_frames == 0 \
			and _refill_idle < 5.5 / heal_rate:
		_refill_timer += delta
		if _refill_timer >= refill_interval:
			refill_dt = _refill_timer
			_refill_timer = 0.0
			refill_now = true
	_run_refill(refill_now, refill_dt)
	if refill_now:
		_cost_refill_px = res.x * res.y

	# Only spend GPU time when something actually changed
	if _prime_frames > 0:
		_prime_frames -= 1
		if _prime_frames == 0 and is_instance_valid(_bg):
			_bg.queue_free()
	if _prime_frames > 0 or _stamps_used > 0 or refill_now:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

func _run_refill(now: bool, dt: float) -> void:
	if _refill.visible != now:
		_refill.visible = now
	if not now:
		return
	var levels := recovery_intensity * refill_levels_per_sec * dt
	var recovery_alpha := 1.0 - exp(-4.0 * levels / 255.0)
	_refill_material.set_shader_parameter("recovery_alpha", recovery_alpha)
	_refill_material.set_shader_parameter("seed", randf() * 1000.0)

func _try_puff(d: Deformer, _id: int, push: Vector3) -> void:
	_spawn_puff(d.global_position, d.radius, push, d)


## Spawns a puff at a contact. Deformer sources are rate-limited by puff_min_interval.
func _spawn_puff(world_pos: Vector3, radius: float, push: Vector3, source: Node) -> void:
	if not puffs_enabled:
		return
	var puff_start := Time.get_ticks_usec()
	var now := Time.get_ticks_msec() * 0.001
	if source != null:
		var id := source.get_instance_id()
		if now - float(_puff_last.get(id, -10.0)) < puff_min_interval:
			return
		_puff_last[id] = now
	if not is_instance_valid(_puffs):
		_puffs = SurfacePuffs.new()
		_puffs.set_amount(_active_quality_settings.puff)
		add_child(_puffs)
		_apply_puff_look()
	_puffs.burst(Vector3(world_pos.x, global_position.y, world_pos.z), radius, push)
	_cost_puffs_us += Time.get_ticks_usec() - puff_start


## Returns false if the per-frame stamp budget is exhausted.
func _stamp(
	pos: Vector2,
	r_px: float,
	heading: float,
	aspect: float,
	strength: float,
	sliding := false,
	stamp_texture: Texture2D = null,
	flip_x := false,
	mode := StampMode.CARVE,
	track := false,
	phase := 0.0,
	capsule := false
) -> bool:
	if _stamps_used >= max_stamps_per_frame:
		return false
	var batch := _get_stamp_batch(stamp_texture)
	var multimesh := batch["multimesh"] as MultiMesh
	if int(batch["used"]) >= multimesh.instance_count:
		return false

	var len_r := r_px * sqrt(aspect)
	var wid_r := r_px / sqrt(aspect)
	var berm_radius := Vector2(len_r, wid_r) * BERM_REACH
	var berm_offset_x := len_r * BERM_FORWARD * clampf(aspect - 1.0, 0.0, 1.0)
	var outer_half_extent := Vector2(
		maxf(len_r, absf(berm_offset_x) + berm_radius.x),
		maxf(wid_r, berm_radius.y)
	)
	if capsule:
		# For a capsule len_r is the half length and wid_r the brush radius (see the shader).
		outer_half_extent = Vector2(len_r + berm_radius.y, berm_radius.y)

	var instance: int = batch["used"]
	multimesh.set_instance_transform_2d(
		instance,
		Transform2D(heading, outer_half_extent, 0.0, pos)
	)
	multimesh.set_instance_color(
		instance,
		Color(strength, r_px / float(_vp.size.x), float(mode) * 0.25, fposmod(phase, 1.0))
	)
	multimesh.set_instance_custom_data(
		instance,
		Color(
			aspect / 8.0,
			3.0 if capsule else (2.0 if track else (1.0 if sliding else 0.0)),
			wrapf(heading, -PI, PI) / TAU + 0.5,
			(2.0 if flip_x else 1.0) if stamp_texture != null else 0.0
		)
	)
	batch["used"] = instance + 1
	_stamps_used += 1
	_cost_stamp_px += 4.0 * outer_half_extent.x * outer_half_extent.y
	return true


func _get_stamp_batch(stamp_texture: Texture2D) -> Dictionary:
	for batch in _stamp_batches:
		if batch["texture"] == stamp_texture:
			return batch

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _stamp_multimesh.mesh
	multimesh.instance_count = _stamp_multimesh.instance_count
	multimesh.visible_instance_count = 0
	var instance := MultiMeshInstance2D.new()
	instance.multimesh = multimesh
	instance.texture = stamp_texture
	instance.material = _stamp_add_material
	_vp.add_child(instance)
	var batch := {
		"texture": stamp_texture,
		"multimesh": multimesh,
		"instance": instance,
		"used": 0,
	}
	_stamp_batches.append(batch)
	return batch
