@tool
@icon("res://addons/deformable_surface/icons/deformable_surface.svg")
class_name DeformableSurface
extends Node3D
## Deformable surface. Drop it in a scene, then add Deformer or
## DeformerFootsteps nodes under anything that should leave marks.
##
## Requirements: keep the node unrotated and unscaled; the area is square (`size`).
## The surface sits at this node's Y position.
##
## How it works: a hidden 2D SubViewport stores a deformation map (R = combined
## height, G/B = surface slopes). Deformers stamp brushes into it; the surface mesh's
## vertex shader displaces from it and its fragment shader reads height and normals
## in one texture fetch. The viewport only renders when something changed.
## Everything runs on the Compatibility renderer (WebGL2).

signal quality_changed(q: DeformableSurfaceQuality)
## Emitted when a stamp starts touching the surface: a Deformer touchdown (footfall) or a
## `stamp_at` call. `depth` is the nominal signed depth in meters (positive = pressed down,
## negative = raised, 0 = smoothed). `type_name` is the surface type's `type_name`.
## `source` is the Deformer, or null for `stamp_at`. `radius` is the stamp radius in meters.
## Touchdown puffs are spawned from this same event.
signal contact(position: Vector3, depth: float, type_name: StringName, source: Node, radius: float, puff: bool)

static var instances: Array[DeformableSurface] = []

## How a stamp changes the surface: CARVE presses it down (with berms), RAISE builds it up
## (snow accumulation, piles), SMOOTH flattens it toward neutral (a plow, erasing prints).
enum StampMode { CARVE, RAISE, SMOOTH }

const SurfacePuffs = preload("deformers/deformer_particles.gd")
const SURFACE_SHADER: Shader = preload("../shaders/deformable_surface.gdshader")
const REFILL_SHADER: Shader = preload("../shaders/deformable_surface_refill.gdshader")
const STAMP_ANALYTIC_SHADER: Shader = preload("../shaders/deformable_surface_stamp_analytic.gdshader")
const STAMP_SPRITE_SHADER: Shader = preload("../shaders/deformable_surface_stamp.gdshader")
const InitialNoiseTextures = preload("initial_noise_textures.gd")
const StampPipelineScript = preload("deformers/surface_stamp_pipeline.gd")
const DeformerSchedulerScript = preload("deformers/deformer_scheduler.gd")
const ContactDispatcherScript = preload("deformers/surface_contact_dispatcher.gd")
const BERM_REACH := 2.0     # berm ring radius, in brush radii
const BERM_FORWARD := 0.3   # elongated prints push their berm ahead by this fraction
const PRIME_NOISE_TIMEOUT_SEC := 10.0
const MAP_NEUTRAL := 128.0 / 255.0
const STAMP_MAX_ASPECT := 8.0
const STAMP_CAPACITY := 512

@export_group("Surface")
## World size of the surface, in meters: a square centered on this node. Changing it at
## runtime rebuilds the mesh and clears the trails.
@export_range(1.0, 256.0, 1.0, "or_greater") var size := 40.0 : set = set_size
## On: draws the built-in flat snow plane. Off: only the deformation map is maintained, for your
## own terrain or foliage shaders (see get_deform_texture() and get_deform_area_transform()).
## Off also stops deformers being culled or weakened by their height above this node, so
## they work on hills; use Deformer `active` to control contact.
@export var render_mesh := true : set = set_render_mesh
## Square extent derived from `size`; kept as a Vector2 for the stamp math.
var area_size := Vector2(40, 40)
## Optional. A ShaderMaterial using shaders/deformable_surface.gdshader, to customize colors and
## sparkle. If empty, a default is created. Each DeformableSurface duplicates it, so one
## resource can be shared. Assign before the node enters the tree.
@export var material: ShaderMaterial : set = set_material
## Optional. What the surface is made of: depth, berms, healing, puffs, lighting and a default
## look. Without one, built-in snow-like defaults are used. Quality profiles only control
## resolution, mesh density, budgets and the sparkle quality scale.
@export var surface_type: DeformableSurfaceType : set = set_surface_type
## Optional. The sun: the sparkle shader follows its direction.
@export var sun: DirectionalLight3D
# The assigned resources remain the source of truth. Their `changed` signals update runtime state.

## Enables wrapped diffuse lighting with cool-tinted shadows on footprint bevels.
var wrapped_diffuse_lighting: bool:
	get:
		return _values().wrapped_diffuse_lighting
	set(enabled):
		set_wrapped_diffuse_lighting(enabled)
## How deep a fully-pressed surface sinks, in meters.
var max_depth: float:
	get:
		return _values().max_depth
## 0 = trails stay forever. 1 = trails heal quickly. The first runtime override duplicates an
## assigned surface type for this node, so other surfaces keep their shared profile values.
var recovery_intensity: float:
	get:
		return _values().recovery_intensity
	set(value):
		set_recovery_intensity(value)

@export_group("Quality")
## Resolution, mesh density and budgets (a DeformableSurfaceQuality: use `low()`, `medium()`,
## `high()` or `for_platform()`, or your own). The node listens to resource changes. Duplicate
## shared presets before editing one surface. Empty = the Medium preset.
@export var quality: DeformableSurfaceQuality : set = set_quality

var max_stamps_per_frame := 64

var refill_interval := 0.25   # seconds between refill passes
var puff_min_interval := 0.2    # per deformer, seconds

var _active_quality_settings: DeformableSurfaceQuality
var _default_surface_type: DeformableSurfaceType
var _surface_type_override: DeformableSurfaceType
var _observed_surface_type: DeformableSurfaceType
var _observed_noise: FastNoiseLite
var _observed_puff_ramp: Gradient
var _observed_material: ShaderMaterial
var _configured_material_source: ShaderMaterial
var _applied_surface_state: Array = []
var _applying_surface_type := false
var _configured_quality_res := 0
var _updating_quality := false

var _runtime := false          # true once running in the game (not the editor)
var _mat: ShaderMaterial       # our private copy of the material
var _map: DeformationMap
var _batching_surface_settings := false
var _surface_clear_pending := false
var _mesh: MeshInstance3D
# Per-frame cost of each operation, read through get_frame_costs().
var _cost_deformers_us := 0
var _cost_queued_us := 0
var _cost_puffs_us := 0
var _cost_refill_px := 0.0
var _stamp_pipeline: RefCounted
var _scheduler: RefCounted
var _contact_dispatcher: RefCounted
var _puff_last := {}   # deformer instance_id -> time of last puff (s)
var _prime_frames := 0
var _prime_noise_wait := 0.0
var _prime_noise_fallback := false
var _refill_timer := 0.0
var _refill_idle := 0.0   # seconds since the last stamp
var _sun_dir := Vector3.ZERO
var _hash_origin_valid := false
var _hash_origin := Vector2.ZERO
var _hash_bevel_density := 0.0
var _hash_sparkle_density := 0.0
var _puffs: SurfacePuffs


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
		return
	if not instances.has(self):
		instances.append(self)
	for deformer in Deformer.instances:
		if deformer.field == null or deformer.field == self:
			_register_deformer(deformer)


func _notification(what: int) -> void:
	if Engine.is_editor_hint() and what == NOTIFICATION_TRANSFORM_CHANGED:
		update_configuration_warnings()


func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_preview()
		return

	_contact_dispatcher = ContactDispatcherScript.new()
	_contact_dispatcher.setup(self)
	_adopt_material()
	_configured_material_source = _source_material()
	if not _set_active_quality(quality):
		return
	_connect_quality_changed()
	_apply_profile_values(_active_quality_settings)
	_values().clamp_values()
	_connect_surface_type_changed()
	_applied_surface_state = _surface_type_state()

	_map = DeformationMap.new()
	add_child(_map)
	_map.setup(REFILL_SHADER, STAMP_ANALYTIC_SHADER, STAMP_SPRITE_SHADER,
			mini(max_stamps_per_frame, STAMP_CAPACITY))
	_stamp_pipeline = StampPipelineScript.new()
	_stamp_pipeline.setup(self, _map)
	_scheduler = DeformerSchedulerScript.new()
	_scheduler.setup(self)

	if render_mesh:
		_create_runtime_mesh()

	_runtime = true
	_configure_quality()
	_clear_map()
	quality_changed.emit(_active_quality_settings)


func _exit_tree() -> void:
	instances.erase(self)
	if _scheduler != null:
		_scheduler.clear()


func _create_runtime_mesh() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.extra_cull_margin = 2.0   # vertices get displaced away from the flat AABB
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _register_deformer(deformer: Deformer) -> void:
	if _scheduler != null:
		_scheduler.register(deformer)


func _unregister_deformer(deformer: Deformer) -> void:
	if _scheduler != null:
		_scheduler.unregister(deformer)


func _mark_deformer_dirty(deformer: Deformer) -> void:
	_register_deformer(deformer)


# ------------------------------------------------------------------ public API

## Applies material/quality changes together, clearing the map only once at the final resolution.
func apply_surface_settings(profile: DeformableSurfaceType, settings: DeformableSurfaceQuality) -> void:
	_batching_surface_settings = true
	set_surface_type(profile)
	set_quality(settings)
	_batching_surface_settings = false
	if _surface_clear_pending:
		_surface_clear_pending = false
		_clear_map()


## Assigns a quality resource. Reconfiguring preserves trails unless the map resolution changes.
func set_quality(q: DeformableSurfaceQuality) -> void:
	if quality == q:
		return
	_disconnect_quality_changed()
	quality = q
	if not _runtime:
		return
	if not _set_active_quality(q):
		return
	_connect_quality_changed()
	_on_quality_resource_changed()


func _connect_quality_changed() -> void:
	if _active_quality_settings != null \
			and not _active_quality_settings.changed.is_connected(_on_quality_resource_changed):
		_active_quality_settings.changed.connect(_on_quality_resource_changed)


func _disconnect_quality_changed() -> void:
	if _active_quality_settings != null \
			and _active_quality_settings.changed.is_connected(_on_quality_resource_changed):
		_active_quality_settings.changed.disconnect(_on_quality_resource_changed)


func _on_quality_resource_changed() -> void:
	if not _runtime or _active_quality_settings == null or _updating_quality:
		return
	_updating_quality = true
	_active_quality_settings.clamp_values()
	_apply_profile_values(_active_quality_settings)
	var previous_res := _configured_quality_res
	_configure_quality()
	if previous_res != 0 and previous_res != _active_quality_settings.res:
		_clear_map()
	quality_changed.emit(_active_quality_settings)
	_updating_quality = false


func _set_active_quality(q: DeformableSurfaceQuality) -> bool:
	var source := q if q != null else DeformableSurfaceQuality.medium()
	if source == null:
		push_error("DeformableSurface: quality preset could not be loaded.")
		return false
	_active_quality_settings = source
	_active_quality_settings.clamp_values()
	return true


func _apply_profile_values(profile: DeformableSurfaceQuality) -> void:
	max_stamps_per_frame = profile.max_stamps_per_frame
	refill_interval = profile.refill_interval
	puff_min_interval = profile.puff_min_interval


## The assigned surface type, or the built-in defaults (snow-like) when none is set.
func _effective_surface_type() -> DeformableSurfaceType:
	if surface_type != null:
		return surface_type
	if _default_surface_type == null:
		_default_surface_type = DeformableSurfaceType.new()
	return _default_surface_type


## The assigned surface type, or the node's built-in default.
func _values() -> DeformableSurfaceType:
	return _effective_surface_type()


## Stamps drawn this frame, out of `max_stamps_per_frame` (for performance readouts).
func get_stamps_used() -> int:
	return _stamp_pipeline.get_used_count() if _stamp_pipeline != null else 0


## Number of stamp texture batches allocated by this surface.
func get_stamp_batch_count() -> int:
	return _stamp_pipeline.get_batch_count() if _stamp_pipeline != null else 0


## Number of stamp texture batches used during the current frame.
func get_active_stamp_batch_count() -> int:
	return _stamp_pipeline.get_active_batch_count() if _stamp_pipeline != null else 0


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
		"stamp_mpx": (_map.stamp_renderer.cost_pixels if _map != null else 0.0) / 1000000.0,
		"refill_mpx": _cost_refill_px / 1000000.0,
		"mesh_kverts": verts / 1000.0,
	}


## Wipes all trails. Cheap: does not touch the mesh, material or particles.
func reset_trails() -> void:
	if _runtime:
		_clear_pending_stamps()
		_clear_map()


## Draw sample brushes and start every puff emitter while the scene is covered.
## Call on a paused surface at startup, then call finish_effects_warmup after drawing.
func warm_up_effects(tread: Texture2D, puff_position: Vector3) -> void:
	if not _runtime:
		return
	var budget := max_stamps_per_frame
	if budget < 4:
		max_stamps_per_frame = 4
		_configure_stamp_capacity()
	_reset_stamp_counts()
	var center := Vector2(_map.viewport.size) * 0.5
	_stamp_pipeline.stamp_request(_stamp_pipeline.prepare(center + Vector2(-16, 0), 4.0, 0.0, 1.0, 0.5))
	var capsule = _stamp_pipeline.prepare(center + Vector2(-5, 0), 4.0, 0.0, 2.0, 0.5)
	capsule.capsule = true
	_stamp_pipeline.stamp_request(capsule)
	var sprite = _stamp_pipeline.prepare(center + Vector2(5, 0), 4.0, 0.0, 1.0, 0.5)
	sprite.texture = tread
	_stamp_pipeline.stamp_request(sprite)
	var track = _stamp_pipeline.prepare(center + Vector2(16, 0), 4.0, 0.0, 2.0, 0.5)
	track.texture = tread
	track.track = true
	_stamp_pipeline.stamp_request(track)
	max_stamps_per_frame = budget
	_stamp_pipeline.submit()
	_map.run_refill(true, refill_interval, _values().recovery_intensity,
			_values().refill_levels_per_sec)
	_map.request_render()
	if _values().puffs_enabled:
		_ensure_puff_pool()
		_puffs.warm_up(puff_position)


## Remove the startup samples before exposing the field to gameplay.
func finish_effects_warmup() -> void:
	if not _runtime:
		return
	if is_instance_valid(_puffs):
		_puffs.finish_warmup()
	_map.run_refill(false, 0.0, _values().recovery_intensity,
			_values().refill_levels_per_sec)
	_reset_stamp_counts()
	_configure_stamp_capacity()
	_submit_stamp_batches()
	_clear_map()
	_map.request_render()


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
	_stamp_pipeline.queue(local, maxf(radius, 0.01), clampf(strength, 0.0, 1.0),
		shape, mode, heading, maxf(aspect, 1.0), puff, silent, false, 0.0, false)


## One continuous strip of track from `from` to `to`: flat-bottomed, with side ridges only.
## `shape` is an alpha-mask tread whose top edge faces the direction of travel; one tile is
## `width` * (texture height / texture width) meters long. `phase` is how many tiles of tread
## precede `from` along the path (running distance / tile length), so consecutive segments
## continue the same pattern. Used by DeformerTracks.
## `rounded` uses an untextured capsule brush, with a rounded leading cap for smooth grooves.
func stamp_segment(
	from: Vector3,
	to: Vector3,
	width := 0.3,
	strength := 1.0,
	shape: Texture2D = null,
	mode := StampMode.CARVE,
	phase := 0.0,
	rounded := false
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
	_stamp_pipeline.queue(mid, sqrt(half_len * half_w), clampf(strength, 0.0, 1.0),
		shape, mode, atan2(delta.z, delta.x), half_len / half_w,
		false, true, not rounded, phase, rounded)


func _clear_pending_stamps() -> void:
	_stamp_pipeline.clear_pending()


## Every contact goes through here. Puffs are spawned by a listener on `contact`.
func _emit_contact(world_pos: Vector3, strength: float, mode: int, source: Node, radius: float, puff: bool) -> void:
	_contact_dispatcher.emit(world_pos, strength, mode, source, radius, puff)


func set_recovery_intensity(value: float) -> void:
	if not _runtime:
		return
	var intensity := clampf(value, 0.0, 1.0)
	if is_equal_approx(_values().recovery_intensity, intensity):
		return
	_local_surface_type_for_override().recovery_intensity = intensity


func set_wrapped_diffuse_lighting(enabled: bool) -> void:
	if not _runtime or _values().wrapped_diffuse_lighting == enabled:
		return
	_local_surface_type_for_override().wrapped_diffuse_lighting = enabled


func _local_surface_type_for_override() -> DeformableSurfaceType:
	if surface_type == null:
		return _effective_surface_type()
	if surface_type != _surface_type_override:
		_surface_type_override = surface_type.duplicate() as DeformableSurfaceType
		set_surface_type(_surface_type_override)
	return _surface_type_override


func set_render_mesh(value: bool) -> void:
	if render_mesh == value:
		return
	render_mesh = value
	if Engine.is_editor_hint():
		_refresh_preview()
	elif _runtime:
		if render_mesh:
			_create_runtime_mesh()
			_configure_mesh()
			_configure_material()
		elif is_instance_valid(_mesh):
			_mesh.queue_free()
			_mesh = null


## The live deformation map (R = height, G/B = X/Z slopes), or null before the surface is ready.
## Bind it in your own shader and decode it with deformable_surface.gdshaderinc.
func get_deform_texture() -> Texture2D:
	return _map.get_texture() if _map != null else null


## Read-only image snapshot for diagnostics and rendered seam checks.
func get_deform_image() -> Image:
	return _map.viewport.get_texture().get_image() if _map != null else null


## Current square deformation-map resolution, or zero before setup.
func get_deform_resolution() -> Vector2i:
	return _map.viewport.size if _map != null else Vector2i.ZERO


## Number of stamps waiting for the per-frame rendering budget.
func get_pending_stamp_count() -> int:
	return _stamp_pipeline.get_pending_count() if _stamp_pipeline != null else 0


## Read-only stamp details for diagnostics: capsule, shape, aspect and track.
func get_pending_stamp_info(index: int) -> Dictionary:
	return _stamp_pipeline.get_pending_info(index) if _stamp_pipeline != null else {}


## True while the starting map is still being prepared.
func is_priming() -> bool:
	return _prime_frames > 0


## Read-only movement-history query for diagnostics.
func has_deformer_history(deformer: Deformer) -> bool:
	return _scheduler.has_history(deformer) if _scheduler != null else false


## (center_x, center_z, 1 / size_x, 1 / size_z) in world space, for deform_world_to_uv().
func get_deform_area_transform() -> Vector4:
	var gp := global_position
	return Vector4(gp.x, gp.z, 1.0 / area_size.x, 1.0 / area_size.y)


func set_size(v: float) -> void:
	size = maxf(v, 1.0)
	var new_area := Vector2.ONE * size
	if area_size.is_equal_approx(new_area):
		return
	area_size = new_area
	if Engine.is_editor_hint():
		_refresh_preview()
		update_configuration_warnings()
	elif _runtime:
		if is_instance_valid(_mesh):
			_configure_mesh()
		_clear_map()


func set_material(m: ShaderMaterial) -> void:
	if material == m:
		return
	material = m
	if Engine.is_editor_hint():
		_refresh_preview()
	elif _runtime:
		_connect_surface_material_changed()
		_adopt_material()
		_configured_material_source = _source_material()
		_configure_material()
		_configure_particles()
		_sun_dir = Vector3.ZERO   # force the sun direction to be re-applied


func _get_configuration_warnings() -> PackedStringArray:
	var w := PackedStringArray()
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
	_mesh.visible = render_mesh
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
	m.set_shader_parameter("wrapped_diffuse_lighting", _effective_surface_type().wrapped_diffuse_lighting)
	_mesh.material_override = m


# ------------------------------------------------------------------ setup

func _adopt_material() -> void:
	var source := _source_material()
	if source != null:
		_mat = source.duplicate() as ShaderMaterial
	else:
		_mat = ShaderMaterial.new()
		_mat.shader = SURFACE_SHADER
	_hash_origin_valid = false


func _source_material() -> ShaderMaterial:
	if material != null:
		return material
	if surface_type != null:
		return surface_type.material
	return null


func set_surface_type(p: DeformableSurfaceType) -> void:
	if surface_type == p:
		return
	_disconnect_surface_type_changed()
	surface_type = p
	if Engine.is_editor_hint():
		_refresh_preview()
		return
	if not _runtime:
		return
	_on_surface_type_changed()


func _connect_surface_type_changed() -> void:
	var profile := _effective_surface_type()
	if _observed_surface_type != profile:
		_disconnect_surface_type_changed()
		_observed_surface_type = profile
	if not profile.changed.is_connected(_on_surface_type_changed):
		profile.changed.connect(_on_surface_type_changed)
	if _observed_noise != profile.initial_noise:
		if _observed_noise != null and _observed_noise.changed.is_connected(_on_initial_noise_changed):
			_observed_noise.changed.disconnect(_on_initial_noise_changed)
		_observed_noise = profile.initial_noise
		if _observed_noise != null:
			_observed_noise.changed.connect(_on_initial_noise_changed)
	if _observed_puff_ramp != profile.puff_color_ramp:
		if _observed_puff_ramp != null and _observed_puff_ramp.changed.is_connected(_on_puff_ramp_changed):
			_observed_puff_ramp.changed.disconnect(_on_puff_ramp_changed)
		_observed_puff_ramp = profile.puff_color_ramp
		if _observed_puff_ramp != null:
			_observed_puff_ramp.changed.connect(_on_puff_ramp_changed)
	_connect_surface_material_changed()


func _disconnect_surface_type_changed() -> void:
	if _observed_surface_type != null \
			and _observed_surface_type.changed.is_connected(_on_surface_type_changed):
		_observed_surface_type.changed.disconnect(_on_surface_type_changed)
	if _observed_noise != null and _observed_noise.changed.is_connected(_on_initial_noise_changed):
		_observed_noise.changed.disconnect(_on_initial_noise_changed)
	if _observed_puff_ramp != null and _observed_puff_ramp.changed.is_connected(_on_puff_ramp_changed):
		_observed_puff_ramp.changed.disconnect(_on_puff_ramp_changed)
	_observed_surface_type = null
	_observed_noise = null
	_observed_puff_ramp = null
	_disconnect_surface_material_changed()


func _connect_surface_material_changed() -> void:
	var source := _source_material()
	if _observed_material == source:
		return
	_disconnect_surface_material_changed()
	_observed_material = source
	if source != null:
		source.changed.connect(_on_surface_material_changed)


func _disconnect_surface_material_changed() -> void:
	if _observed_material != null \
			and _observed_material.changed.is_connected(_on_surface_material_changed):
		_observed_material.changed.disconnect(_on_surface_material_changed)
	_observed_material = null


func _on_surface_type_changed() -> void:
	if not _runtime or _applying_surface_type:
		return
	_applying_surface_type = true
	_values().clamp_values()
	_connect_surface_type_changed()
	if _configured_material_source != _source_material():
		_adopt_material()
		_configured_material_source = _source_material()
	_configure_material()
	_map.configure_stamp_material(_values(), _active_quality_settings.textured_berm_dilation)
	_configure_particles()
	_sun_dir = Vector3.ZERO
	var current_state := _surface_type_state()
	if (not _applied_surface_state.is_empty()
			and (not is_equal_approx(_applied_surface_state[0], current_state[0])
				or not is_equal_approx(_applied_surface_state[1], current_state[1])
				or _applied_surface_state[2] != current_state[2])):
		_clear_map()
	_applied_surface_state = current_state
	_applying_surface_type = false


func _on_initial_noise_changed() -> void:
	if _runtime and _values().initial_noise_enabled:
		_clear_map()


func _on_puff_ramp_changed() -> void:
	if _runtime:
		_apply_puff_look()


func _on_surface_material_changed() -> void:
	if not _runtime:
		return
	_adopt_material()
	_sun_dir = Vector3.ZERO
	_configure_material()
	_configure_particles()
	_connect_surface_material_changed()


func _starting_surface_key() -> Array:
	var p := _values()
	if not p.initial_noise_enabled:
		return [false]
	var noise_frequency := p.initial_noise.frequency if p.initial_noise != null \
			else p.initial_noise_frequency
	return [true, p.initial_noise, noise_frequency, p.initial_noise_invert,
		p.initial_noise_height, p.initial_noise_detail,
		p.initial_noise_detail_scale, p.initial_noise_mound_height,
		p.initial_noise_mound_frequency]


func _surface_type_state() -> Array:
	var p := _values()
	return [p.max_depth, p.berm_height, _starting_surface_key()]


## Applies the quality preset: map size, mesh density, shader params, particle counts.
func _configure_quality() -> void:
	var current := _active_quality_settings
	if _map.viewport.size != Vector2i(current.res, current.res):
		_configure_deformation_map()
	if is_instance_valid(_mesh):
		_configure_mesh()
	_configure_material()
	_map.configure_stamp_material(_values(), _active_quality_settings.textured_berm_dilation)
	_configure_stamp_capacity()
	_configure_particles()
	_configured_quality_res = current.res


func _configure_deformation_map() -> void:
	var res: int = _active_quality_settings.res
	_map.configure_resolution(res)


func _configure_mesh() -> void:
	var plane := PlaneMesh.new()
	plane.size = area_size
	plane.subdivide_width = _active_quality_settings.subdiv
	plane.subdivide_depth = _active_quality_settings.subdiv
	_mesh.mesh = plane


func _configure_material() -> void:
	if is_instance_valid(_mesh):
		_mesh.material_override = _mat
	_mat.set_shader_parameter("deform_map", _map.get_texture())
	_mat.set_shader_parameter("max_depth", max_depth)
	_mat.set_shader_parameter("sparkle_intensity", _active_quality_settings.sparkle)
	_mat.set_shader_parameter("wrapped_diffuse_lighting", wrapped_diffuse_lighting)
	_configure_hash_origins()


func _configure_hash_origins() -> void:
	if _mat == null or _mat.shader != SURFACE_SHADER:
		return
	var origin := Vector2(global_position.x, global_position.z)
	var bevel_density := _shader_float_parameter("bevel_noise_scale", 32.0)
	var sparkle_density := _shader_float_parameter("sparkle_density", 24.0)
	if _hash_origin_valid and origin == _hash_origin \
			and bevel_density == _hash_bevel_density \
			and sparkle_density == _hash_sparkle_density:
		return
	_hash_origin = origin
	_hash_bevel_density = bevel_density
	_hash_sparkle_density = sparkle_density
	_hash_origin_valid = true
	_set_hash_origin("bevel", origin, maxf(bevel_density, 0.0001))
	_set_hash_origin("sparkle", origin, maxf(sparkle_density, 0.0001))


func _shader_float_parameter(parameter: StringName, fallback: float) -> float:
	var value: Variant = _mat.get_shader_parameter(parameter)
	return float(value) if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT else fallback


func _set_hash_origin(prefix: String, origin: Vector2, density: float) -> void:
	var scaled := origin * density
	var integer_origin := Vector2i(floori(scaled.x), floori(scaled.y))
	var fraction := scaled - Vector2(integer_origin)
	var wrapped_origin := Vector2(
		_positive_hash_mod(integer_origin.x),
		_positive_hash_mod(integer_origin.y)
	)
	_mat.set_shader_parameter(StringName(prefix + "_origin_fraction"), fraction)
	_mat.set_shader_parameter(StringName(prefix + "_origin_cell"), wrapped_origin)


func _positive_hash_mod(value: int) -> int:
	return ((value % 8192) + 8192) % 8192


func _configure_particles() -> void:
	if not _values().puffs_enabled:
		if is_instance_valid(_puffs):
			_puffs.queue_free()
			_puffs = null
		return
	if is_instance_valid(_puffs):
		_puffs.set_amount(_active_quality_settings.puff)
		_apply_puff_look()


## Puffs follow the surface type: its texture/ramp, else a soft dot in the surface color fading out.
func _apply_puff_look() -> void:
	var p := _effective_surface_type()
	var texture := p.puff_texture
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
	_map.configure_stamp_capacity(capacity)


## Restores the starting surface and clears tracks.
func _clear_map() -> void:
	if _batching_surface_settings:
		_surface_clear_pending = true
		return
	_map.clear(_values(), area_size, global_position)
	_prime_frames = 3
	_prime_noise_wait = 0.0
	_prime_noise_fallback = false
	_refill_timer = 0.0
	_refill_idle = 0.0
	_scheduler.reset()
	for deformer in Deformer.instances:
		if deformer.field == null or deformer.field == self:
			_register_deformer(deformer)
func _forget(deformer: Deformer) -> void:
	if _scheduler != null:
		_scheduler.forget(deformer)
	_puff_last.erase(deformer.get_instance_id())


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if not _runtime:
		return
	_configure_hash_origins()

	if is_instance_valid(sun):
		var dir := sun.global_basis.z.normalized()   # direction TOWARD the light
		if not dir.is_equal_approx(_sun_dir):
			_sun_dir = dir
			_mat.set_shader_parameter("sun_dir", dir)

	_reset_stamp_counts()
	_cost_puffs_us = 0
	_cost_refill_px = 0.0

	var res := Vector2(_map.viewport.size)
	var px_per_m := res.x / area_size.x
	var queued_start := Time.get_ticks_usec()
	if _stamp_pipeline.get_pending_count() > 0:
		_stamp_pipeline.flush(res, px_per_m, _prime_frames > 0)
	_cost_queued_us = Time.get_ticks_usec() - queued_start
	_cost_deformers_us = maxi(_scheduler.process_deformers(res, px_per_m,
			_prime_frames > 0) - _cost_puffs_us, 0)

	_submit_stamp_batches()

	# Surface recovery: a few times per second, not every frame, and only until the map has
	# healed after the last stamp (about 5.5 time constants covers 8-bit precision).
	if get_stamps_used() > 0 or _prime_frames > 0:
		_refill_idle = 0.0
	else:
		_refill_idle += delta
	var refill_now := false
	var refill_dt := 0.0
	var heal_rate := 4.0 * _values().recovery_intensity * _values().refill_levels_per_sec / 255.0
	if heal_rate > 0.0001 and _values().recovery_intensity > 0.001 and _prime_frames == 0 \
			and _refill_idle < 5.5 / heal_rate:
		_refill_timer += delta
		if _refill_timer >= refill_interval:
			refill_dt = _refill_timer
			_refill_timer = 0.0
			refill_now = true
	_map.run_refill(refill_now, refill_dt,
		_values().recovery_intensity, _values().refill_levels_per_sec)
	if refill_now:
		_cost_refill_px = res.x * res.y

	# Only spend GPU time when something actually changed
	if _prime_frames > 0:
		if _prime_noise_fallback or InitialNoiseTextures.ready_for_profile(_values()):
			if not _map.is_starting_target_baked():
				_map.request_starting_target_bake()
			else:
				_prime_frames -= 1
				if _prime_frames == 0:
					_map.finish_priming()
		else:
			_prime_noise_wait += delta
			if _prime_noise_wait >= PRIME_NOISE_TIMEOUT_SEC:
				push_warning("DeformableSurface: initial noise did not finish baking; using a flat starting surface.")
				_map.fallback_to_flat()
				_prime_noise_fallback = true
				_prime_frames = 3
	if _prime_frames > 0 or get_stamps_used() > 0 or refill_now:
		_map.request_render()


func _reset_stamp_counts() -> void:
	_stamp_pipeline.reset_counts()


func _submit_stamp_batches() -> void:
	_stamp_pipeline.submit()

func _try_puff(d: Deformer, _id: int, push: Vector3) -> void:
	_spawn_puff(d.global_position, d.radius, push, d)


## Spawns a puff at a contact. Deformer sources are rate-limited by puff_min_interval.
func _spawn_puff(world_pos: Vector3, radius: float, push: Vector3, source: Node) -> void:
	if not _values().puffs_enabled:
		return
	var puff_start := Time.get_ticks_usec()
	var now := Time.get_ticks_msec() * 0.001
	if source != null:
		var id := source.get_instance_id()
		if now - float(_puff_last.get(id, -10.0)) < puff_min_interval:
			return
		_puff_last[id] = now
	_ensure_puff_pool()
	var puff_y := global_position.y if render_mesh else world_pos.y
	_puffs.burst(Vector3(world_pos.x, puff_y, world_pos.z), radius, push)
	_cost_puffs_us += Time.get_ticks_usec() - puff_start


func _ensure_puff_pool() -> void:
	if not is_instance_valid(_puffs):
		_puffs = SurfacePuffs.new()
		_puffs.set_amount(_active_quality_settings.puff)
		add_child(_puffs)
		_apply_puff_look()
