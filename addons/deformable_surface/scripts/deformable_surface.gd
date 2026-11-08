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
const STAMP_SHADER: Shader = preload("../shaders/deformable_surface_stamp.gdshader")
const InitialNoiseGenerator = preload("initial_noise_generator.gd")
const BERM_REACH := 2.0     # berm ring radius, in brush radii
const BERM_FORWARD := 0.3   # elongated prints push their berm ahead by this fraction
const MAP_NEUTRAL := 128.0 / 255.0
const STAMP_MIN_RADIUS_PX := 0.5
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
# The values below come from the surface type. The node keeps one private snapshot of it
# (`_mp`), so there is a single copy to read and nothing to keep in sync by hand.

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
## 0 = trails stay forever. 1 = trails heal quickly. Assigning it at runtime overrides the
## surface type's value until the type is replaced.
var recovery_intensity: float:
	get:
		return _values().recovery_intensity
	set(value):
		set_recovery_intensity(value)

@export_group("Quality")
## Resolution, mesh density and budgets (a DeformableSurfaceQuality: use `low()`, `medium()`,
## `high()` or `for_platform()`, or your own). The node keeps its own copy, so assign a changed
## resource again to apply edits. Empty = the Medium preset.
@export var quality: DeformableSurfaceQuality : set = set_quality

var max_stamps_per_frame := 64

var refill_interval := 0.25   # seconds between refill passes
var puff_min_interval := 0.2    # per deformer, seconds

var _active_quality_settings: DeformableSurfaceQuality
var _default_surface_type: DeformableSurfaceType
var _mp: DeformableSurfaceType   # clamped snapshot of the effective surface type

var _runtime := false          # true once running in the game (not the editor)
var _mat: ShaderMaterial       # our private copy of the material
var _vp: SubViewport
var _bg: Control
var _initial_map_texture: Texture2D
var _initial_noise_cache: ImageTexture
var _initial_noise_cache_key: Array = []
var _prepared_noise_texture: ImageTexture
var _prepared_noise_key: Array = []
var _initial_noise_thread: Thread
var _initial_noise_thread_key: Array = []
var _initial_noise_generator
var _initial_noise_generator_key: Array = []
var _initial_noise_force_sliced := false
var _batching_surface_settings := false
var _surface_clear_pending := false
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


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)
		return
	if not instances.has(self):
		instances.append(self)
	for deformer in Deformer.unassigned:
		_register_deformer(deformer)
	for deformer in Deformer.assigned.get(get_instance_id(), []):
		_register_deformer(deformer)


func _notification(what: int) -> void:
	if Engine.is_editor_hint() and what == NOTIFICATION_TRANSFORM_CHANGED:
		update_configuration_warnings()


func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_preview()
		return

	if not contact.is_connected(_on_contact_puff):
		contact.connect(_on_contact_puff)
	_adopt_material()
	if not _set_active_quality(quality):
		return
	_apply_profile_values(_active_quality_settings)
	_apply_surface_type_values()

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

	if render_mesh:
		_create_runtime_mesh()

	_runtime = true
	_configure_quality(null)
	_clear_map()
	quality_changed.emit(_active_quality_settings)


func _exit_tree() -> void:
	if _initial_noise_thread != null:
		_initial_noise_thread.wait_to_finish()
		_initial_noise_thread = null
	instances.erase(self)
	_dirty_deformers.clear()


func _create_runtime_mesh() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.extra_cull_margin = 2.0   # vertices get displaced away from the flat AABB
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


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

## Applies prepared material/quality changes together, clearing the map only once at
## the final resolution. Call prepare_initial_noise_at() with these settings first.
func apply_surface_settings(profile: DeformableSurfaceType, settings: DeformableSurfaceQuality) -> void:
	_batching_surface_settings = true
	set_surface_type(profile)
	set_quality(settings)
	_batching_surface_settings = false
	if _surface_clear_pending:
		_surface_clear_pending = false
		_clear_map()


## Assigns a quality (the node keeps a clamped copy). Reconfiguring preserves trails unless the
## map resolution changes.
func set_quality(q: DeformableSurfaceQuality) -> void:
	quality = q
	if not _runtime:
		return
	var previous := _active_quality_settings
	if not _set_active_quality(q):
		return
	if previous != null and previous.to_dictionary() == _active_quality_settings.to_dictionary():
		return
	_apply_profile_values(_active_quality_settings)
	_configure_quality(previous)
	if previous == null or previous.res != _active_quality_settings.res:
		_clear_map()
	quality_changed.emit(_active_quality_settings)


## Takes a clamped private copy of `q` (Medium when null).
func _set_active_quality(q: DeformableSurfaceQuality) -> bool:
	var source := q if q != null else DeformableSurfaceQuality.medium()
	if source == null:
		push_error("DeformableSurface: quality preset could not be loaded.")
		return false
	_active_quality_settings = source.duplicate() as DeformableSurfaceQuality
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


## The node's view of the surface type: the snapshot once running, else the type itself.
func _values() -> DeformableSurfaceType:
	return _mp if _mp != null else _effective_surface_type()


func _apply_surface_type_values() -> void:
	_mp = _effective_surface_type().duplicate() as DeformableSurfaceType
	_mp.clamp_values()


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
	_pending_stamps.append({
		"local": mid, "radius": sqrt(half_len * half_w), "strength": clampf(strength, 0.0, 1.0),
		"shape": shape, "mode": mode, "heading": atan2(delta.z, delta.x), "aspect": half_len / half_w,
		"puff": false, "silent": true, "track": not rounded, "phase": phase, "capsule": rounded,
	})


## Every contact goes through here. Puffs are spawned by a listener on `contact`.
func _emit_contact(world_pos: Vector3, strength: float, mode: int, source: Node, radius: float, puff: bool) -> void:
	var depth := strength * max_depth
	if mode == StampMode.RAISE:
		depth = -depth
	elif mode == StampMode.SMOOTH:
		depth = 0.0
		puff = false
	contact.emit(world_pos, depth, _effective_surface_type().type_name, source, radius, puff)


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
			float(s["strength"]), false, s["shape"], false, s["mode"], bool(s["track"]), float(s["phase"]), bool(s.get("capsule", false))
		):
			remaining.append(s)
			continue
		if not s["silent"]:
			_emit_contact(to_global(Vector3(local.x, 0.0, local.z)), float(s["strength"]), int(s["mode"]),
					null, float(s["radius"]), bool(s["puff"]))
	_pending_stamps = remaining


func set_recovery_intensity(value: float) -> void:
	if _mp != null:
		_mp.recovery_intensity = clampf(value, 0.0, 1.0)


func set_wrapped_diffuse_lighting(enabled: bool) -> void:
	if _mp == null or _mp.wrapped_diffuse_lighting == enabled:
		return
	_mp.wrapped_diffuse_lighting = enabled
	if _mat:
		_mat.set_shader_parameter("wrapped_diffuse_lighting", enabled)


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
	return _vp.get_texture() if _vp != null else null


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
		_adopt_material()
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
	if surface_type != null:
		return surface_type.material
	return null


func set_surface_type(p: DeformableSurfaceType) -> void:
	if surface_type == p:
		return
	var previous_source := _source_material()
	var previous_depth := max_depth
	var previous_berm_height := _values().berm_height
	var previous_noise_key := _starting_surface_key()
	surface_type = p
	if Engine.is_editor_hint():
		_refresh_preview()
		return
	if not _runtime:
		return
	_apply_surface_type_values()
	if _source_material() != previous_source:
		_adopt_material()
	_configure_material()
	_configure_stamp_material(_stamp_add_material)
	_configure_particles()
	_sun_dir = Vector3.ZERO   # force the sun direction to be re-applied
	if not is_equal_approx(previous_depth, max_depth) \
			or not is_equal_approx(previous_berm_height, _mp.berm_height) \
			or previous_noise_key != _starting_surface_key():
		_clear_map()


func _starting_surface_key() -> Array:
	return [_values().initial_noise_enabled, _initial_noise_key(512)]


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
func _configure_quality(previous: DeformableSurfaceQuality) -> void:
	var current := _active_quality_settings
	var map_changed := previous == null or previous.res != current.res
	if map_changed:
		_configure_deformation_map()

	var plane := _mesh.mesh as PlaneMesh if is_instance_valid(_mesh) else null
	if (is_instance_valid(_mesh) and (plane == null
			or not plane.size.is_equal_approx(area_size)
			or plane.subdivide_width != current.subdiv
			or plane.subdivide_depth != current.subdiv)):
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
	if is_instance_valid(_mesh):
		_mesh.material_override = _mat
	_mat.set_shader_parameter("deform_map", _vp.get_texture())
	_mat.set_shader_parameter("max_depth", max_depth)
	_mat.set_shader_parameter("sparkle_intensity", _active_quality_settings.sparkle)
	_mat.set_shader_parameter("wrapped_diffuse_lighting", wrapped_diffuse_lighting)


func _configure_particles() -> void:
	if not _mp.puffs_enabled:
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
	for batch in _stamp_batches:
		var multimesh := batch["multimesh"] as MultiMesh
		if multimesh.instance_count != capacity:
			multimesh.instance_count = capacity


func _configure_stamp_material(stamp_material: ShaderMaterial) -> void:
	stamp_material.set_shader_parameter("berm_strength", _mp.berm_strength)
	stamp_material.set_shader_parameter("berm_height_ratio", _mp.berm_height / maxf(max_depth, 0.01))
	stamp_material.set_shader_parameter("map_resolution", float(_vp.size.x))


## Restores the starting surface and clears tracks.
func _clear_map() -> void:
	if _batching_surface_settings:
		_surface_clear_pending = true
		return
	if is_instance_valid(_bg):
		_bg.queue_free()
	if _mp.initial_noise_enabled:
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
	_refill_material.set_shader_parameter("recovery_target_enabled", _mp.initial_noise_enabled)
	_vp.add_child(_bg)
	_vp.move_child(_bg, 0)
	_prime_frames = 3
	_refill_timer = 0.0
	_refill_idle = 0.0
	_puff_acc.clear()
	_last.clear()
	for deformer in Deformer.unassigned:
		_register_deformer(deformer)
	for deformer in Deformer.assigned.get(get_instance_id(), []):
		_register_deformer(deformer)


func _initial_noise_key(resolution: int, profile: DeformableSurfaceType = null) -> Array:
	var p := profile if profile != null else _values()
	# Surface types can be assigned before this node is added to the scene.
	var origin := global_position if is_inside_tree() else position
	var noise_key: Array = [null]
	if p.initial_noise != null:
		noise_key = [
			p.initial_noise, p.initial_noise.seed, p.initial_noise.frequency,
			p.initial_noise.noise_type, p.initial_noise.fractal_type,
		]
	return [
		resolution, area_size, Vector2(origin.x, origin.z),
		p.max_depth, p.initial_noise_invert,
		p.initial_noise_frequency, p.initial_noise_height, noise_key,
		p.initial_noise_detail, p.initial_noise_detail_scale,
		p.initial_noise_mound_height, p.initial_noise_mound_frequency,
	]


## Prepares noise for a future relocation without blocking a frame. Poll until true, then
## move the surface and call reset_trails(). Texture creation stays on the main thread;
## the worker only reads a private settings snapshot and writes its own Image.
## Optional profile/quality arguments prepare a settings change at its final resolution;
## pass the same resources to apply_surface_settings() once preparation is complete.
func prepare_initial_noise_at(world_position: Vector3, profile: DeformableSurfaceType = null,
		settings: DeformableSurfaceQuality = null) -> bool:
	var target := profile if profile != null else _values()
	if not _runtime or not target.initial_noise_enabled:
		return true
	var resolution := mini(clampi(settings.res, 128, 2048) if settings != null else _vp.size.x, 512)
	var key := _initial_noise_key(resolution, target)
	key[2] = Vector2(world_position.x, world_position.z)
	if (_initial_noise_cache != null and _initial_noise_cache_key == key
			or _prepared_noise_texture != null and _prepared_noise_key == key):
		return true
	if _initial_noise_thread != null:
		if _initial_noise_thread.is_alive():
			return false
		var image: Image = _initial_noise_thread.wait_to_finish()
		_initial_noise_thread = null
		# Discard obsolete results before uploading them after a direction/settings change.
		if _initial_noise_thread_key == key:
			_prepared_noise_texture = ImageTexture.create_from_image(image)
			_prepared_noise_key = key
			return true
	var origin := Vector2(world_position.x, world_position.z) - area_size * 0.5
	if not OS.can_use_threads() or _initial_noise_force_sliced:
		if _initial_noise_generator == null or _initial_noise_generator_key != key:
			var snapshot := target.duplicate(true) as DeformableSurfaceType
			snapshot.clamp_values()
			_initial_noise_generator = InitialNoiseGenerator.new(snapshot, resolution, area_size, origin)
			_initial_noise_generator_key = key
		if not _initial_noise_generator.step(2000):
			return false
		_prepared_noise_texture = ImageTexture.create_from_image(_initial_noise_generator.image)
		_prepared_noise_key = key
		_initial_noise_generator = null
		_initial_noise_generator_key = []
		return true
	_initial_noise_generator = null
	_initial_noise_generator_key = []
	var snapshot := target.duplicate(true) as DeformableSurfaceType
	snapshot.clamp_values()
	_initial_noise_thread = Thread.new()
	_initial_noise_thread_key = key
	var error := _initial_noise_thread.start(
		InitialNoiseGenerator.new(snapshot, resolution, area_size, origin).run_to_completion)
	if error != OK:
		_initial_noise_thread = null
		# Thread support can be reported by the platform but fail at runtime; keep
		# the operation alive and finish it incrementally on the main thread.
		_initial_noise_force_sliced = true
		_initial_noise_generator = InitialNoiseGenerator.new(snapshot, resolution, area_size, origin)
		_initial_noise_generator_key = key
	return false


## Regenerating is a per-pixel GDScript loop, so reuse the texture while its inputs are unchanged.
func _get_initial_noise_texture() -> Texture2D:
	var key := _initial_noise_key(mini(_vp.size.x, 512))
	if _prepared_noise_texture != null and _prepared_noise_key == key:
		_initial_noise_cache = _prepared_noise_texture
		_initial_noise_cache_key = _prepared_noise_key
		_prepared_noise_texture = null
		_prepared_noise_key = []
	if _initial_noise_cache == null or _initial_noise_cache_key != key:
		_initial_noise_cache = ImageTexture.create_from_image(_make_initial_noise_image())
		_initial_noise_cache_key = key
	return _initial_noise_cache


func _make_initial_noise_image() -> Image:
	var resolution := mini(_vp.size.x, 512)
	var origin := Vector2(global_position.x, global_position.z) - area_size * 0.5
	var generator = InitialNoiseGenerator.new(_values(), resolution, area_size, origin)
	return generator.run_to_completion()


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
		# Include the whole elongated brush and its berms, even when the center is
		# on a neighboring tile. The viewport clips the stamp to this surface.
		var reach := d.radius * sqrt(clampf(d.aspect, 1.0, STAMP_MAX_ASPECT)) * (BERM_REACH + BERM_FORWARD)
		if (render_mesh and local.y > max_depth) or absf(local.x) > area_size.x * 0.5 + reach or absf(local.z) > area_size.y * 0.5 + reach:
			_last.erase(id)
			_dirty_deformers.erase(id)
			continue
		var depth_ratio := clampf(1.0 - (local.y / max_depth), 0.1, 1.0) if render_mesh else 1.0
		var effective_strength := d.strength * depth_ratio
		# Half-open bounds give shared edges a single owner for audio and particles.
		var owns_contact := (local.x >= -area_size.x * 0.5 and local.x < area_size.x * 0.5
				and local.z >= -area_size.y * 0.5 and local.z < area_size.y * 0.5)
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
				if d.puff_distance > 0.0 and owns_contact:
					var stamped_move := done - prev
					var acc: float = _puff_acc.get(id, 0.0) + stamped_move.length() / px_per_m
					if acc >= d.puff_distance:
						acc = 0.0
						_try_puff(d, id, -Vector3(stamped_move.x, 0.0, stamped_move.y))
					_puff_acc[id] = acc
		else:
			if not _stamp(pos, r_px, heading, aspect, effective_strength, false, d.stamp_texture, d.stamp_flip_x, d.mode):
				continue
			if owns_contact:
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
	var heal_rate := 4.0 * _mp.recovery_intensity * _mp.refill_levels_per_sec / 255.0
	if heal_rate > 0.0001 and _mp.recovery_intensity > 0.001 and _prime_frames == 0 \
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
	var levels := _mp.recovery_intensity * _mp.refill_levels_per_sec * dt
	var recovery_alpha := 1.0 - exp(-4.0 * levels / 255.0)
	_refill_material.set_shader_parameter("recovery_alpha", recovery_alpha)
	_refill_material.set_shader_parameter("seed", randf() * 1000.0)

func _try_puff(d: Deformer, _id: int, push: Vector3) -> void:
	_spawn_puff(d.global_position, d.radius, push, d)


## Spawns a puff at a contact. Deformer sources are rate-limited by puff_min_interval.
func _spawn_puff(world_pos: Vector3, radius: float, push: Vector3, source: Node) -> void:
	if not _mp.puffs_enabled:
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
	var puff_y := global_position.y if render_mesh else world_pos.y
	_puffs.burst(Vector3(world_pos.x, puff_y, world_pos.z), radius, push)
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

	# Match the shader's radius floor and keep the packed aspect within its 0..1 range.
	var stamp_radius_px := maxf(r_px, STAMP_MIN_RADIUS_PX)
	var stamp_aspect := clampf(aspect, 0.001, STAMP_MAX_ASPECT)
	var len_r := stamp_radius_px * sqrt(stamp_aspect)
	var wid_r := stamp_radius_px / sqrt(stamp_aspect)
	var berm_radius := Vector2(len_r, wid_r) * BERM_REACH
	var berm_offset_x := len_r * BERM_FORWARD * clampf(stamp_aspect - 1.0, 0.0, 1.0)
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
		Color(strength, stamp_radius_px / float(_vp.size.x), float(mode) * 0.25, fposmod(phase, 1.0))
	)
	multimesh.set_instance_custom_data(
		instance,
		Color(
			stamp_aspect / STAMP_MAX_ASPECT,
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
