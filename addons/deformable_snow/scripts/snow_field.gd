@tool
@icon("res://addons/deformable_snow/icons/snow_field.svg")
class_name SnowField
extends Node3D
## Deformable snow surface. Drop it in a scene, then add SnowDeformer or
## SnowFootsteps nodes under anything that should leave marks.
##
## Requirements: area_size must be square; keep the node unrotated and unscaled.
## The snow surface sits at this node's Y position.
##
## How it works: a hidden 2D SubViewport stores a deformation map
## (R = pit depth, G = berm/ridge, B = temporary bulge). Deformers stamp brushes
## into it; the snow mesh's vertex shader displaces from it and the fragment
## shader derives normals from it. The viewport only renders when something
## changed. Everything runs on the Compatibility renderer (WebGL2).

signal quality_changed(q: Quality)

enum Quality { LOW, MEDIUM, HIGH, CUSTOM }

const SnowPuffs = preload("snow_puffs.gd")
const SNOW_SHADER: Shader = preload("../shaders/snow.gdshader")
const REFILL_SHADER: Shader = preload("../shaders/snow_refill.gdshader")
const SnowQualitySettingsScript = preload("snow_quality_settings.gd")
const LOW_QUALITY_DEFAULT = preload("../resources/quality_low.tres")
const MEDIUM_QUALITY_DEFAULT = preload("../resources/quality_medium.tres")
const HIGH_QUALITY_DEFAULT = preload("../resources/quality_high.tres")
const CUSTOM_QUALITY_DEFAULT = preload("../resources/quality_custom.tres")
const BERM_REACH := 2.0     # berm ring texture radius, in brush radii
const BERM_FORWARD := 0.3   # elongated prints push their berm ahead by this fraction

@export_group("Surface")
## World size of the snow, in meters (centered on this node). Keep it square.
@export var area_size := Vector2(40, 40) : set = set_area_size
## Optional. A ShaderMaterial using shaders/snow.gdshader, to customize colors and
## sparkle. If empty, a default is created. Each SnowField duplicates it, so one
## resource can be shared. Assign before the node enters the tree.
@export var material: ShaderMaterial : set = set_material
## Optional. The sun: the sparkle shader follows its direction.
@export var sun: DirectionalLight3D
## Enables wrapped diffuse lighting with cool-tinted shadows on footprint bevels.
@export var wrapped_diffuse_lighting := true : set = set_wrapped_diffuse_lighting
## How deep fully-pressed snow sinks, in meters.
@export_range(0.01, 1.0, 0.01, "or_greater") var max_depth := 0.25

@export_group("Quality")
## Initial quality profile. auto_quality overrides this when enabled.
@export var quality: Quality = Quality.MEDIUM : set = set_quality
@export var low_quality: SnowQualitySettingsScript = LOW_QUALITY_DEFAULT
@export var medium_quality: SnowQualitySettingsScript = MEDIUM_QUALITY_DEFAULT
@export var high_quality: SnowQualitySettingsScript = HIGH_QUALITY_DEFAULT
@export var custom_quality: SnowQualitySettingsScript = CUSTOM_QUALITY_DEFAULT
## If true, picks Low on mobile / mobile browsers, Medium on desktop browsers and
## High elsewhere when the scene starts (overrides `quality`).
@export var auto_quality := false
@export_range(1, 512, 1, "or_greater") var max_stamps_per_frame := 64

@export_group("Berms")
@export_range(0.0, 0.5) var berm_strength := 0.15   # 0 disables berms
@export var berm_height := 0.08                       # meters at full berm

@export_group("Snowfall")
## 0 = no snow, trails stay forever. 1 = heavy snow, trails heal quickly.
@export_range(0.0, 1.0) var snowfall := 0.3 : set = set_snowfall
## 8-bit levels per second regained at snowfall = 1 (255 = fully healed).
@export var refill_levels_per_sec := 16.0
@export var berm_decay_mult := 1.5      # berms smooth out faster than prints heal
@export_range(0.05, 5.0, 0.05, "or_greater") var refill_interval := 0.25   # seconds between refill passes
@export var wind := Vector2(0.3, 0.0) : set = set_wind   # flake drift (m/s^2, x / z)
@export var fall_height := 9.0
## Flakes are centered above this node. If empty, the active camera is used.
@export var follow_target: Node3D

@export_group("Puffs")
@export var puffs_enabled := true
@export var puff_min_interval := 0.2    # per deformer, seconds

var _active_quality_settings: SnowQualitySettingsScript
var _active_quality_custom := false

class Stamp:
	var root: Node2D
	var press: Sprite2D
	var berm: Sprite2D
	var bulge: Sprite2D
	var eraser: Sprite2D

var _runtime := false          # true once running in the game (not the editor)
var _mat: ShaderMaterial       # our private copy of the material
var _vp: SubViewport
var _stage: Node2D
var _bg: ColorRect
var _refill: ColorRect
var _mesh: MeshInstance3D
var _press_tex: GradientTexture2D
var _berm_tex: GradientTexture2D
var _channel_stamp_tex: GradientTexture2D
var _press_mat: CanvasItemMaterial
var _berm_mat: CanvasItemMaterial
var _bulge_mat: CanvasItemMaterial
var _eraser_mat: CanvasItemMaterial
var _pool: Array[Stamp] = []
var _pool_used := 0
var _known := {}       # deformer instance_id -> true (we've connected its tree_exiting)
var _last := {}        # deformer instance_id -> last stamped pixel pos
var _puff_last := {}   # deformer instance_id -> time of last puff (s)
var _puff_acc := {}    # deformer instance_id -> meters since last moving puff
var _rr := 0           # round-robin start index, so a full stamp budget can't starve anyone
var _prime_frames := 0
var _refill_timer := 0.0
var _bulge_hold_timer := 0.0
var _sun_dir := Vector3.ZERO
var _puffs: SnowPuffs
var _fall: SnowFall        # fine flakes around the target
var _fall_near: SnowFall   # a few big soft flakes near the camera, for depth


## A sensible default for the current platform.
static func recommended_quality() -> Quality:
	if OS.has_feature("web"):
		var mobile = JavaScriptBridge.eval("/Android|iPhone|iPad/i.test(navigator.userAgent)")
		return Quality.LOW if mobile else Quality.MEDIUM
	if OS.has_feature("mobile"):
		return Quality.LOW
	return Quality.HIGH


func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_preview()
		return

	_adopt_material()
	max_depth = maxf(max_depth, 0.01)
	area_size = area_size.max(Vector2(1.0, 1.0))
	refill_interval = maxf(refill_interval, 0.05)
	max_stamps_per_frame = maxi(max_stamps_per_frame, 1)
	if absf(area_size.x - area_size.y) > 0.01:
		push_warning("SnowField: area_size should be square; prints will be stretched otherwise.")
	if auto_quality:
		quality = recommended_quality()
	if custom_quality == null:
		push_error("SnowField: custom quality profile is not assigned.")
		return
	custom_quality = custom_quality.duplicate(true) as SnowQualitySettingsScript
	if not _set_active_quality_profile(quality):
		return
	_apply_profile_values(_active_quality_settings)

	_make_brushes()

	_vp = SubViewport.new()
	_vp.disable_3d = true
	_vp.transparent_bg = false
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	add_child(_vp)

	# Draw order inside the map: bg, refill pass, then stamps.
	_refill = _make_refill_rect(REFILL_SHADER)
	_stage = Node2D.new()
	_vp.add_child(_stage)

	_mesh = MeshInstance3D.new()
	_mesh.extra_cull_margin = 2.0   # vertices get displaced away from the flat AABB
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

	_puffs = SnowPuffs.new()
	add_child(_puffs)

	_fall = SnowFall.new()
	_fall.height = fall_height
	add_child(_fall)

	_fall_near = SnowFall.new()
	_fall_near.area = Vector2(14.0, 14.0)
	_fall_near.height = 7.0
	_fall_near.fall_speed = Vector2(0.9, 1.5)
	_fall_near.flake_size = 0.35
	_fall_near.flake_color = Color(1, 1, 1, 0.4)
	_fall_near.follow_camera = true   # big soft flakes between the camera and the action
	add_child(_fall_near)

	for f in [_fall, _fall_near]:
		f.set_intensity(snowfall)
		f.set_wind(wind)

	_runtime = true
	_configure_quality()
	_clear_map()
	quality_changed.emit(quality)


# ------------------------------------------------------------------ public API

## Reconfiguring quality preserves trails unless the map resolution changes.
func set_quality(q: Quality) -> void:
	if q < Quality.LOW or q > Quality.CUSTOM:
		push_error("SnowField: invalid quality preset.")
		return

	var profile := _quality_profile(q)
	if profile == null:
		push_error("SnowField: quality profile is not assigned.")
		return
	var quality_changed_now := q != quality
	var settings_changed: bool = (
		_active_quality_custom != (q == Quality.CUSTOM)
		or _active_quality_settings == null
		or _active_quality_settings.to_dictionary() != profile.to_dictionary()
	)
	var map_resolution_changed: bool = (
		_active_quality_settings == null
		or _active_quality_settings.res != profile.res
	)
	quality = q
	_active_quality_settings = profile.duplicate(true) as SnowQualitySettingsScript
	_active_quality_custom = q == Quality.CUSTOM
	_apply_profile_values(profile)
	if _runtime and (quality_changed_now or settings_changed):
		_configure_quality()
		if map_resolution_changed:
			_clear_map()
		if quality_changed_now:
			quality_changed.emit(quality)


func get_quality_settings(q: Quality) -> Dictionary:
	if q < Quality.LOW or q > Quality.CUSTOM:
		push_error("SnowField: invalid quality preset.")
		return {}
	var profile := _quality_profile(q)
	if profile == null:
		push_error("SnowField: quality profile is not assigned.")
		return {}
	return profile.to_dictionary()


func get_active_quality_settings() -> Dictionary:
	if _active_quality_settings == null:
		return {}
	var settings := _active_quality_settings.to_dictionary()
	settings["area_size"] = area_size.x
	settings["max_depth"] = max_depth
	settings["berm_strength"] = berm_strength
	settings["berm_height"] = berm_height
	settings["max_stamps_per_frame"] = max_stamps_per_frame
	settings["snowfall"] = snowfall
	settings["refill_levels_per_sec"] = refill_levels_per_sec
	settings["berm_decay_mult"] = berm_decay_mult
	settings["refill_interval"] = refill_interval
	settings["wind_x"] = wind.x
	settings["wind_z"] = wind.y
	settings["fall_height"] = fall_height
	settings["puffs_enabled"] = puffs_enabled
	settings["puff_min_interval"] = puff_min_interval
	settings["wrapped_diffuse_lighting"] = wrapped_diffuse_lighting
	return settings


func has_custom_quality_settings() -> bool:
	return _active_quality_custom


func apply_quality_settings(settings: Dictionary) -> void:
	if custom_quality == null:
		push_error("SnowField: custom quality profile is not assigned.")
		return
	var required := ["res", "subdiv", "sparkle", "flakes", "near", "puff"]
	for key in required:
		if not settings.has(key):
			push_error("SnowField: custom quality settings are missing '%s'." % key)
			return
		var type := typeof(settings[key])
		if type != TYPE_INT and type != TYPE_FLOAT:
			push_error("SnowField: custom quality setting '%s' must be numeric." % key)
			return
	for key in ["snowfall", "msaa"]:
		if settings.has(key):
			var type := typeof(settings[key])
			if type != TYPE_INT and type != TYPE_FLOAT:
				push_error("SnowField: custom quality setting '%s' must be numeric." % key)
				return
	for key in ["shadows", "wrapped_diffuse_lighting"]:
		if settings.has(key) and typeof(settings[key]) != TYPE_BOOL:
			push_error("SnowField: custom quality setting '%s' must be a boolean." % key)
			return

	var updated := custom_quality.duplicate(true) as SnowQualitySettingsScript
	if updated == null:
		push_error("SnowField: custom quality profile could not be duplicated.")
		return
	updated.res = clampi(roundi(float(settings["res"])), 128, 2048)
	updated.subdiv = clampi(roundi(float(settings["subdiv"])), 1, 512)
	updated.sparkle = clampf(float(settings["sparkle"]), 0.0, 3.0)
	updated.flakes = clampi(roundi(float(settings["flakes"])), 1, 10000)
	updated.near = clampi(roundi(float(settings["near"])), 0, 5000)
	updated.puff = clampi(roundi(float(settings["puff"])), 1, 64)
	updated.area_size = maxf(float(settings.get("area_size", updated.area_size)), 1.0)
	updated.max_depth = maxf(float(settings.get("max_depth", updated.max_depth)), 0.01)
	updated.berm_strength = clampf(float(settings.get("berm_strength", updated.berm_strength)), 0.0, 0.5)
	updated.berm_height = maxf(float(settings.get("berm_height", updated.berm_height)), 0.0)
	updated.max_stamps_per_frame = maxi(
		roundi(float(settings.get("max_stamps_per_frame", updated.max_stamps_per_frame))),
		1
	)
	updated.snowfall = clampf(float(settings.get("snowfall", updated.snowfall)), 0.0, 1.0)
	updated.refill_levels_per_sec = maxf(
		float(settings.get("refill_levels_per_sec", updated.refill_levels_per_sec)),
		0.0
	)
	updated.berm_decay_mult = maxf(
		float(settings.get("berm_decay_mult", updated.berm_decay_mult)),
		0.0
	)
	updated.refill_interval = maxf(float(settings.get("refill_interval", updated.refill_interval)), 0.05)
	updated.wind_x = float(settings.get("wind_x", updated.wind_x))
	updated.wind_z = float(settings.get("wind_z", updated.wind_z))
	updated.fall_height = maxf(float(settings.get("fall_height", updated.fall_height)), 0.0)
	updated.follow_target_mode = clampi(
		roundi(float(settings.get("follow_target_mode", updated.follow_target_mode))),
		0,
		2
	)
	updated.puffs_enabled = bool(settings.get("puffs_enabled", updated.puffs_enabled))
	updated.puff_min_interval = maxf(
		float(settings.get("puff_min_interval", updated.puff_min_interval)),
		0.0
	)
	updated.shadows = bool(settings.get("shadows", updated.shadows))
	updated.msaa = clampi(roundi(float(settings.get("msaa", updated.msaa))), 0, 2)
	updated.wrapped_diffuse_lighting = bool(
		settings.get("wrapped_diffuse_lighting", updated.wrapped_diffuse_lighting)
	)
	var updated_values := updated.to_dictionary()
	var settings_changed := (
		_active_quality_settings == null
		or _active_quality_settings.to_dictionary() != updated_values
	)
	var custom_changed := not _active_quality_custom
	var map_changed: bool = (
		_active_quality_settings == null
		or _active_quality_settings.res != updated.res
	)
	custom_quality = updated
	_active_quality_settings = updated
	_active_quality_custom = true
	_apply_profile_values(updated)
	if _runtime and (settings_changed or custom_changed):
		_configure_quality()
		if map_changed:
			_clear_map()


func _quality_profile(q: Quality) -> SnowQualitySettingsScript:
	match q:
		Quality.LOW:
			return low_quality
		Quality.MEDIUM:
			return medium_quality
		Quality.HIGH:
			return high_quality
		Quality.CUSTOM:
			return custom_quality
		_:
			return null


func _set_active_quality_profile(q: Quality) -> bool:
	var profile := _quality_profile(q)
	if profile == null:
		push_error("SnowField: quality profile is not assigned.")
		return false
	_active_quality_settings = profile.duplicate(true) as SnowQualitySettingsScript
	_active_quality_custom = q == Quality.CUSTOM
	return true


func _apply_profile_values(profile: SnowQualitySettingsScript) -> void:
	area_size = Vector2.ONE * maxf(profile.area_size, 1.0)
	max_depth = maxf(profile.max_depth, 0.01)
	berm_strength = clampf(profile.berm_strength, 0.0, 0.5)
	berm_height = maxf(profile.berm_height, 0.0)
	max_stamps_per_frame = maxi(profile.max_stamps_per_frame, 1)
	snowfall = profile.snowfall
	refill_levels_per_sec = maxf(profile.refill_levels_per_sec, 0.0)
	berm_decay_mult = maxf(profile.berm_decay_mult, 0.0)
	refill_interval = maxf(profile.refill_interval, 0.05)
	wind = Vector2(profile.wind_x, profile.wind_z)
	fall_height = maxf(profile.fall_height, 0.0)
	puffs_enabled = profile.puffs_enabled
	puff_min_interval = maxf(profile.puff_min_interval, 0.0)
	wrapped_diffuse_lighting = profile.wrapped_diffuse_lighting
	if _fall:
		_fall.height = fall_height


## Wipes all trails. Cheap: does not touch the mesh, material or particles.
func reset_trails() -> void:
	if _runtime:
		_clear_map()


func set_snowfall(v: float) -> void:
	snowfall = clampf(v, 0.0, 1.0)
	if _fall:
		_fall.set_intensity(snowfall)
		_fall_near.set_intensity(snowfall)


func set_wind(v: Vector2) -> void:
	wind = v
	if _fall:
		_fall.set_wind(v)
		_fall_near.set_wind(v)


func set_wrapped_diffuse_lighting(enabled: bool) -> void:
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
	elif _runtime:
		_configure_quality()
		_clear_map()


func set_material(m: ShaderMaterial) -> void:
	material = m
	if Engine.is_editor_hint():
		_refresh_preview()
	elif _runtime:
		_adopt_material()
		_configure_quality()
		_sun_dir = Vector3.ZERO   # force the sun direction to be re-applied


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
	if absf(area_size.x - area_size.y) > 0.01:
		w.append("area_size should be square.")
	if not global_basis.is_equal_approx(Basis.IDENTITY):
		w.append("Keep the SnowField unrotated and unscaled (also its parents).")
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
		m.shader = SNOW_SHADER
	var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
	img.fill(Color(0, 0, 0))   # untouched snow
	m.set_shader_parameter("deform_map", ImageTexture.create_from_image(img))
	m.set_shader_parameter("wrapped_diffuse_lighting", wrapped_diffuse_lighting)
	_mesh.material_override = m


# ------------------------------------------------------------------ setup

func _adopt_material() -> void:
	if material != null:
		_mat = material.duplicate() as ShaderMaterial
	else:
		_mat = ShaderMaterial.new()
		_mat.shader = SNOW_SHADER


func _make_refill_rect(shader: Shader) -> ColorRect:
	var r := ColorRect.new()
	var m := ShaderMaterial.new()
	m.shader = shader
	r.material = m
	r.visible = false
	_vp.add_child(r)
	return r


func _make_brushes() -> void:
	# White RGB lets each special stamp tint write only its selected channels.
	# A broad plateau makes one stamp fully raise the blue-channel bulge.
	var channel_gradient := Gradient.new()
	channel_gradient.set_color(0, Color(1, 1, 1, 1.0))
	channel_gradient.add_point(0.45, Color(1, 1, 1, 0.85))
	channel_gradient.set_color(1, Color(1, 1, 1, 0.0))
	_channel_stamp_tex = GradientTexture2D.new()
	_channel_stamp_tex.gradient = channel_gradient
	_channel_stamp_tex.fill = GradientTexture2D.FILL_RADIAL
	_channel_stamp_tex.fill_from = Vector2(0.5, 0.5)
	_channel_stamp_tex.fill_to = Vector2(1.0, 0.5)
	_channel_stamp_tex.width = 64
	_channel_stamp_tex.height = 64

	# Presses add pit depth to R; overlapping stamps saturate.
	var g := Gradient.new()
	g.set_color(0, Color(1, 0, 0, 0.7))
	g.set_color(1, Color(1, 0, 0, 0.0))
	_press_tex = GradientTexture2D.new()
	_press_tex.gradient = g
	_press_tex.fill = GradientTexture2D.FILL_RADIAL
	_press_tex.fill_from = Vector2(0.5, 0.5)
	_press_tex.fill_to = Vector2(1.0, 0.5)
	_press_tex.width = 64
	_press_tex.height = 64

	_press_mat = CanvasItemMaterial.new()
	_press_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_bulge_mat = CanvasItemMaterial.new()
	_bulge_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_eraser_mat = CanvasItemMaterial.new()
	_eraser_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB

	# Berm: soft ring, drawn into the G channel with additive blending.
	var rg := Gradient.new()
	rg.set_color(0, Color(0, 1, 0, 0.0))
	rg.set_color(1, Color(0, 1, 0, 0.0))
	rg.add_point(0.40, Color(0, 1, 0, 0.0))
	rg.add_point(0.62, Color(0, 1, 0, 1.0))
	_berm_tex = GradientTexture2D.new()
	_berm_tex.gradient = rg
	_berm_tex.fill = GradientTexture2D.FILL_RADIAL
	_berm_tex.fill_from = Vector2(0.5, 0.5)
	_berm_tex.fill_to = Vector2(1.0, 0.5)
	_berm_tex.width = 64
	_berm_tex.height = 64

	_berm_mat = CanvasItemMaterial.new()
	_berm_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


## Applies the quality preset: map size, mesh density, shader params, particle counts.
func _configure_quality() -> void:
	var p := _active_quality_settings
	var res: int = p.res
	_vp.size = Vector2i(res, res)
	_refill.size = Vector2(res, res)

	var plane := PlaneMesh.new()
	plane.size = area_size
	plane.subdivide_width = p.subdiv
	plane.subdivide_depth = p.subdiv
	_mesh.mesh = plane
	_mesh.material_override = _mat

	_mat.set_shader_parameter("deform_map", _vp.get_texture())
	_mat.set_shader_parameter("map_texel", 1.0 / res)
	_mat.set_shader_parameter("vertex_texel", 1.0 / (p.subdiv + 1))
	_mat.set_shader_parameter("max_depth", max_depth)
	_mat.set_shader_parameter("berm_height", berm_height)
	_mat.set_shader_parameter("sparkle_intensity", p.sparkle)
	_mat.set_shader_parameter("wrapped_diffuse_lighting", wrapped_diffuse_lighting)

	_puffs.set_amount(p.puff)
	_fall.set_max_amount(p.flakes)
	var near: int = p.near
	_fall_near.set_enabled(near > 0)
	_fall_near.set_max_amount(maxi(near, 1))


## Re-primes the map: R = 0 (untouched), G = 0 (no berm).
func _clear_map() -> void:
	if is_instance_valid(_bg):
		_bg.queue_free()
	_bg = ColorRect.new()
	_bg.color = Color(0, 0, 0)
	_bg.size = Vector2(_vp.size)
	_vp.add_child(_bg)
	_vp.move_child(_bg, 0)
	_prime_frames = 3
	_refill_timer = 0.0
	_last.clear()
	_puff_acc.clear()


func _forget(id: int) -> void:
	_known.erase(id)
	_last.erase(id)
	_puff_last.erase(id)
	_puff_acc.erase(id)


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if not _runtime:
		return

	if is_instance_valid(sun):
		var dir := sun.global_basis.z   # direction TOWARD the light
		if not dir.is_equal_approx(_sun_dir):
			_sun_dir = dir
			_mat.set_shader_parameter("sun_dir", dir)

	for i in _pool_used:
		_pool[i].root.visible = false
	_pool_used = 0

	var res := Vector2(_vp.size)
	var px_per_m := res.x / area_size.x

	var list := SnowDeformer.all
	var n := list.size()
	var bulge_decay_active := false
	for k in n:
		var d := list[(k + _rr) % n]
		if d.field != null and d.field != self:
			continue
		var id := d.get_instance_id()
		if not _known.has(id):
			_known[id] = true
			d.tree_exiting.connect(_forget.bind(id), CONNECT_ONE_SHOT)

		if _prime_frames > 0:
			continue   # the clear background is still being rendered

		if not d.active:
			_last.erase(id)   # lifted: next touchdown starts a fresh print
			continue
		var local := to_local(d.global_position)
		if local.y > max_depth or absf(local.x) > area_size.x * 0.5 or absf(local.z) > area_size.y * 0.5:
			_last.erase(id)
			continue
		if d.stamp_mode == SnowDeformer.StampMode.BULGE_ERASER:
			bulge_decay_active = true
			_bulge_hold_timer = 0.30

		var pos := (Vector2(local.x, local.z) / area_size + Vector2(0.5, 0.5)) * res
		var r_px := maxf(d.radius, 0.01) * px_per_m
		var heading := d.map_heading()
		var aspect := maxf(d.aspect, 1.0)

		if d.stamp_mode == SnowDeformer.StampMode.BULGE_ERASER:
			if not _stamp(pos, r_px, d, heading, aspect):
				continue
			if _last.has(id) and d.puff_distance > 0.0:
				var prev_b: Vector2 = _last[id]
				var dist_b := prev_b.distance_to(pos)
				var acc_b: float = _puff_acc.get(id, 0.0) + dist_b / px_per_m
				if acc_b >= d.puff_distance:
					acc_b = 0.0
					var move_b := pos - prev_b
					_try_puff(d, id, -Vector3(move_b.x, 0.0, move_b.y))
				_puff_acc[id] = acc_b
			_last[id] = pos
			continue

		# `done` = the last position we actually finished stamping. If the stamp
		# budget runs out mid-trail we only advance that far, and pick up from
		# there next frame instead of leaving a gap.
		var done := pos
		if _last.has(id):
			var prev: Vector2 = _last[id]
			var dist := prev.distance_to(pos)
			if dist < r_px * 0.15:
				continue   # barely moved; skip (and keep accumulating distance)
			if dist > r_px * 20.0:
				if not _stamp(pos, r_px, d, heading, aspect):   # teleport: no streak
					continue
			else:
				var steps := clampi(ceili(dist / (r_px * 0.5)), 1, 8)
				done = prev
				for s in range(1, steps + 1):
					var sp := prev.lerp(pos, float(s) / steps)
					if not _stamp(sp, r_px, d, heading, aspect):
						break
					done = sp
				if done == prev:
					continue   # no budget at all: retry next frame
				if d.puff_distance > 0.0:
					var acc: float = _puff_acc.get(id, 0.0) + dist / px_per_m
					if acc >= d.puff_distance:
						acc = 0.0
						var move := pos - prev
						_try_puff(d, id, -Vector3(move.x, 0.0, move.y))
					_puff_acc[id] = acc
		else:
			if not _stamp(pos, r_px, d, heading, aspect):
				continue
			if d.puff_on_touchdown:
				_try_puff(d, id, Vector3.ZERO)
		_last[id] = done

	if n > 0:
		_rr = (_rr + 1) % n

	# Snowfall refill: a few times per second, not every frame.
	var refill_now := false
	var refill_dt := 0.0
	if snowfall > 0.001 and _prime_frames == 0:
		_refill_timer += delta
		if _refill_timer >= refill_interval:
			refill_dt = _refill_timer
			_refill_timer = 0.0
			refill_now = true
	if _bulge_hold_timer > 0.0:
		_bulge_hold_timer = maxf(_bulge_hold_timer - delta, 0.0)
		bulge_decay_active = true
	_run_refill(refill_now, refill_dt, bulge_decay_active, delta)

	# Only spend GPU time when something actually changed
	if _prime_frames > 0:
		_prime_frames -= 1
		if _prime_frames == 0 and is_instance_valid(_bg):
			_bg.queue_free()
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	elif _pool_used > 0 or refill_now or bulge_decay_active:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

	_fall.follow_target = follow_target
	_fall.ground_y = global_position.y
	_fall_near.ground_y = global_position.y


func _run_refill(now: bool, dt: float, bulge_decay_active: bool, delta: float) -> void:
	_refill.visible = now or bulge_decay_active
	if not _refill.visible:
		return
	var levels := snowfall * refill_levels_per_sec * dt if now else 0.0
	var bulge_drain := 255.0 * delta / 0.07 if bulge_decay_active else levels * 4.0
	var material := _refill.material as ShaderMaterial
	material.set_shader_parameter("pit_levels", levels)
	material.set_shader_parameter("berm_levels", levels * berm_decay_mult)
	material.set_shader_parameter("bulge_levels", bulge_drain)
	material.set_shader_parameter("seed", randf() * 100.0)

func _try_puff(d: SnowDeformer, id: int, push: Vector3) -> void:
	if not puffs_enabled:
		return
	var now := Time.get_ticks_msec() * 0.001
	if now - float(_puff_last.get(id, -10.0)) < puff_min_interval:
		return
	_puff_last[id] = now
	var wp := d.global_position
	_puffs.burst(Vector3(wp.x, global_position.y, wp.z), d.radius, push)


## Returns false if the per-frame stamp budget is exhausted (nothing was drawn).
func _stamp(pos: Vector2, r_px: float, d: SnowDeformer, heading: float, aspect: float) -> bool:
	if _pool_used >= max_stamps_per_frame:
		return false
	if _pool_used >= _pool.size():
		_pool.append(_make_stamp())
	var s := _pool[_pool_used]
	_pool_used += 1

	# Same area for any aspect: long radius * short radius = r^2.
	var len_r := r_px * sqrt(aspect)
	var wid_r := r_px / sqrt(aspect)

	s.root.visible = true
	s.root.position = pos
	s.root.rotation = heading   # sprite local +x = the deformer's forward direction
	if d.stamp_mode == SnowDeformer.StampMode.BULGE_ERASER:
		s.press.visible = false
		s.berm.visible = false
		s.bulge.visible = true
		s.eraser.visible = true
		var scale := Vector2(len_r, wid_r) * (2.0 / _press_tex.width)
		s.bulge.scale = scale
		s.eraser.scale = scale
	else:
		s.press.visible = true
		s.berm.visible = berm_strength > 0.0
		s.bulge.visible = false
		s.eraser.visible = false
		s.press.scale = Vector2(len_r, wid_r) * (2.0 / _press_tex.width)
		s.press.modulate.a = d.strength
		s.berm.position = Vector2(len_r * BERM_FORWARD * clampf(aspect - 1.0, 0.0, 1.0), 0.0)
		s.berm.scale = Vector2(len_r, wid_r) * (BERM_REACH * 2.0 / _berm_tex.width)
		s.berm.modulate.a = d.strength * berm_strength
	return true


func _make_stamp() -> Stamp:
	var s := Stamp.new()
	s.root = Node2D.new()
	s.berm = Sprite2D.new()
	s.berm.texture = _berm_tex
	s.berm.material = _berm_mat
	s.press = Sprite2D.new()
	s.press.texture = _press_tex
	s.press.material = _press_mat
	s.bulge = Sprite2D.new()
	s.bulge.texture = _channel_stamp_tex
	s.bulge.modulate = Color(0.0, 0.0, 1.0, 1.0)
	s.bulge.material = _bulge_mat
	s.bulge.visible = false
	s.eraser = Sprite2D.new()
	s.eraser.texture = _channel_stamp_tex
	s.eraser.modulate = Color(0.15, 0.0, 0.0, 1.0)
	s.eraser.material = _eraser_mat
	s.eraser.visible = false
	s.root.add_child(s.berm)
	s.root.add_child(s.press)
	s.root.add_child(s.bulge)
	s.root.add_child(s.eraser)
	_stage.add_child(s.root)
	return s
