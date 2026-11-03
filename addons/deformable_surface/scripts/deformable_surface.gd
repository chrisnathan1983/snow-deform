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

static var instances: Array[DeformableSurface] = []

enum Quality { LOW, MEDIUM, HIGH, CUSTOM }

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
## Optional. The sun: the sparkle shader follows its direction.
@export var sun: DirectionalLight3D
## Enables wrapped diffuse lighting with cool-tinted shadows on footprint bevels.
var wrapped_diffuse_lighting := true : set = set_wrapped_diffuse_lighting
## How deep a fully-pressed surface sinks, in meters.
var max_depth := 0.25

@export_group("Starting Surface")
## Adds a procedural starting surface; disabled by default to keep it flat.
@export var initial_noise_enabled := true
## Optional noise override. When empty, a cellular dimple pattern is used.
@export var initial_noise: FastNoiseLite
## Inverts the starting pattern to create mounds instead of dimples.
@export var initial_noise_invert := false
## Cellular feature scale when using the built-in noise (lower values make larger dimples).
@export_range(0.1, 4.0, 0.1) var initial_noise_frequency := 0.8
## Maximum starting height variation in meters.
@export_range(0.0, 0.25, 0.001, "suffix:m") var initial_noise_height := 0.15

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
		or not is_equal_approx(previous.max_depth, profile.max_depth)
		or not is_equal_approx(previous.area_size, profile.area_size)
		or not is_equal_approx(previous.berm_height, profile.berm_height)
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


func get_quality_settings(q: Quality) -> Dictionary:
	if q < Quality.LOW or q > Quality.CUSTOM:
		push_error("DeformableSurface: invalid quality preset.")
		return {}
	var profile := _quality_profile(q)
	if profile == null:
		push_error("DeformableSurface: quality profile is not assigned.")
		return {}
	return profile.to_dictionary()


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
	updated.max_depth = maxf(float(settings.get("max_depth", updated.max_depth)), 0.01)
	updated.berm_strength = clampf(float(settings.get("berm_strength", updated.berm_strength)), 0.0, 0.5)
	updated.berm_height = maxf(float(settings.get("berm_height", updated.berm_height)), 0.0)
	updated.max_stamps_per_frame = maxi(roundi(float(settings.get(
		"max_stamps_per_frame", updated.max_stamps_per_frame
	))), 1)
	updated.recovery_intensity = clampf(
		float(settings.get("recovery_intensity", updated.recovery_intensity)),
		0.0,
		1.0
	)
	updated.refill_levels_per_sec = maxf(float(settings.get(
		"refill_levels_per_sec", updated.refill_levels_per_sec
	)), 0.0)
	updated.refill_interval = maxf(float(settings.get("refill_interval", updated.refill_interval)), 0.05)
	updated.puffs_enabled = bool(settings.get("puffs_enabled", updated.puffs_enabled))
	updated.puff_min_interval = maxf(
		float(settings.get("puff_min_interval", updated.puff_min_interval)),
		0.0
	)
	updated.wrapped_diffuse_lighting = bool(
		settings.get("wrapped_diffuse_lighting", updated.wrapped_diffuse_lighting)
	)
	custom_surface_quality = updated
	set_quality(Quality.CUSTOM)


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
	max_depth = maxf(profile.max_depth, 0.01)
	berm_strength = clampf(profile.berm_strength, 0.0, 0.5)
	berm_height = maxf(profile.berm_height, 0.0)
	max_stamps_per_frame = maxi(profile.max_stamps_per_frame, 1)
	recovery_intensity = profile.recovery_intensity
	refill_levels_per_sec = maxf(profile.refill_levels_per_sec, 0.0)
	refill_interval = maxf(profile.refill_interval, 0.05)
	puffs_enabled = profile.puffs_enabled
	puff_min_interval = maxf(profile.puff_min_interval, 0.0)
	wrapped_diffuse_lighting = profile.wrapped_diffuse_lighting


## Wipes all trails. Cheap: does not touch the mesh, material or particles.
func reset_trails() -> void:
	if _runtime:
		_clear_map()


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
	if material != null:
		m = material.duplicate() as ShaderMaterial
	else:
		m = ShaderMaterial.new()
		m.shader = SURFACE_SHADER
	var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
	img.fill(Color(MAP_NEUTRAL, MAP_NEUTRAL, MAP_NEUTRAL))
	m.set_shader_parameter("deform_map", ImageTexture.create_from_image(img))
	m.set_shader_parameter("wrapped_diffuse_lighting", wrapped_diffuse_lighting)
	_mesh.material_override = m


# ------------------------------------------------------------------ setup

func _adopt_material() -> void:
	if material != null:
		_mat = material.duplicate() as ShaderMaterial
	else:
		_mat = ShaderMaterial.new()
		_mat.shader = SURFACE_SHADER


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
			or not is_equal_approx(previous.max_depth, current.max_depth)
			or not is_equal_approx(previous.sparkle, current.sparkle)
			or previous.wrapped_diffuse_lighting != current.wrapped_diffuse_lighting):
		_configure_material()
	if (previous == null
			or map_changed
			or not is_equal_approx(previous.berm_strength, current.berm_strength)
			or not is_equal_approx(previous.berm_height, current.berm_height)
			or not is_equal_approx(previous.max_depth, current.max_depth)):
		_configure_stamp_material(_stamp_add_material)
	if (previous == null
			or previous.max_stamps_per_frame != current.max_stamps_per_frame):
		_configure_stamp_capacity()
	if (previous == null
			or previous.puff != current.puff
			or previous.puffs_enabled != current.puffs_enabled):
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
			if initial_noise_invert:
				noise_value = -noise_value
			var height := noise_value * height_amplitude
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
	for batch in _stamp_batches:
		batch["used"] = 0

	var list: Array = []
	var n := _dirty_deformers.size()
	var res := Vector2.ZERO
	var px_per_m := 0.0
	if n > 0:
		list = _dirty_deformers.values()
		res = Vector2(_vp.size)
		px_per_m = res.x / area_size.x
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
				if not _stamp(pos, r_px, heading, aspect, effective_strength, false, d.stamp_texture, d.stamp_flip_x):
					continue
			else:
				var steps := clampi(ceili(dist / (r_px * 0.5)), 1, 8)
				done = prev
				for s in range(1, steps + 1):
					var sp := prev.lerp(pos, float(s) / steps)
					if not _stamp(sp, r_px, move_heading, aspect, effective_strength, true, d.stamp_texture, d.stamp_flip_x):
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
			if not _stamp(pos, r_px, heading, aspect, effective_strength, false, d.stamp_texture, d.stamp_flip_x):
				continue
			if d.puff_on_touchdown:
				_try_puff(d, id, Vector3.ZERO)
		_last[id] = done
		if done.distance_to(pos) < 0.001:
			_dirty_deformers.erase(id)

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

func _try_puff(d: Deformer, id: int, push: Vector3) -> void:
	if not puffs_enabled:
		return
	var now := Time.get_ticks_msec() * 0.001
	if now - float(_puff_last.get(id, -10.0)) < puff_min_interval:
		return
	if not is_instance_valid(_puffs):
		_puffs = SurfacePuffs.new()
		_puffs.set_amount(_active_quality_settings.puff)
		add_child(_puffs)
	_puff_last[id] = now
	var wp := d.global_position
	_puffs.burst(Vector3(wp.x, global_position.y, wp.z), d.radius, push)


## Returns false if the per-frame stamp budget is exhausted.
func _stamp(
	pos: Vector2,
	r_px: float,
	heading: float,
	aspect: float,
	strength: float,
	sliding := false,
	stamp_texture: Texture2D = null,
	flip_x := false
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

	var instance: int = batch["used"]
	multimesh.set_instance_transform_2d(
		instance,
		Transform2D(heading, outer_half_extent, 0.0, pos)
	)
	multimesh.set_instance_color(
		instance,
		Color(strength, r_px / float(_vp.size.x), 1.0, 1.0)
	)
	multimesh.set_instance_custom_data(
		instance,
		Color(
			aspect / 8.0,
			1.0 if sliding else 0.0,
			wrapf(heading, -PI, PI) / TAU + 0.5,
			(2.0 if flip_x else 1.0) if stamp_texture != null else 0.0
		)
	)
	batch["used"] = instance + 1
	_stamps_used += 1
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
