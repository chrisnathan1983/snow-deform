class_name DeformationMap
extends Node
## Owns the hidden viewport and render resources for one deformable surface.

const StampBatchRendererScript = preload("deformers/stamp_batch_renderer.gd")
const InitialNoiseTextures = preload("initial_noise_textures.gd")
const INITIAL_NOISE_SHADER: Shader = preload("../shaders/deformable_surface_initial_noise.gdshader")
const MAP_NEUTRAL := 128.0 / 255.0

var viewport: SubViewport
var refill: ColorRect
var refill_material: ShaderMaterial
var background: Control
var stamp_renderer: StampBatchRenderer


func setup(refill_shader: Shader, analytic_stamp_shader: Shader,
		sprite_stamp_shader: Shader, capacity: int) -> void:
	viewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	add_child(viewport)

	refill = ColorRect.new()
	var material := ShaderMaterial.new()
	material.shader = refill_shader
	refill.material = material
	refill_material = material
	refill.visible = false
	viewport.add_child(refill)

	stamp_renderer = StampBatchRendererScript.new()
	stamp_renderer.setup(viewport, analytic_stamp_shader, sprite_stamp_shader, capacity)


func configure_resolution(resolution: int) -> void:
	viewport.size = Vector2i(resolution, resolution)
	refill.size = Vector2(resolution, resolution)


func configure_stamp_material(profile: DeformableSurfaceType,
		textured_berm_dilation: bool) -> void:
	stamp_renderer.configure_materials(profile, textured_berm_dilation)


func configure_stamp_capacity(capacity: int) -> void:
	stamp_renderer.set_capacity(capacity)


func clear(profile: DeformableSurfaceType, area_size: Vector2, world_position: Vector3) -> void:
	if is_instance_valid(background):
		background.queue_free()
	var next_background := ColorRect.new()
	next_background.size = Vector2(viewport.size)
	if profile.initial_noise_enabled:
		var material := ShaderMaterial.new()
		material.shader = INITIAL_NOISE_SHADER
		configure_initial_noise(material, profile, area_size, world_position)
		next_background.material = material
		next_background.color = Color.WHITE
	else:
		next_background.color = Color(MAP_NEUTRAL, MAP_NEUTRAL, MAP_NEUTRAL)
	background = next_background
	refill_material.set_shader_parameter("initial_noise_enabled", profile.initial_noise_enabled)
	if profile.initial_noise_enabled:
		configure_initial_noise(refill_material, profile, area_size, world_position)
	viewport.add_child(background)
	viewport.move_child(background, 0)


func configure_initial_noise(material: ShaderMaterial, profile: DeformableSurfaceType,
		area_size: Vector2, world_position: Vector3) -> void:
	var textures := InitialNoiseTextures.for_profile(profile)
	material.set_shader_parameter("initial_noise_texture", textures["base"])
	material.set_shader_parameter("initial_noise_detail_texture", textures["detail"])
	material.set_shader_parameter("initial_noise_mound_texture", textures["mound"])
	material.set_shader_parameter("initial_noise_origin",
		Vector2(world_position.x, world_position.z) - area_size * 0.5)
	material.set_shader_parameter("initial_noise_area", area_size)
	material.set_shader_parameter("initial_noise_resolution", float(viewport.size.x))
	material.set_shader_parameter("initial_noise_depth", profile.max_depth)
	material.set_shader_parameter("initial_noise_world_period", InitialNoiseTextures.WORLD_PERIOD)
	var noise_frequency := profile.initial_noise.frequency if profile.initial_noise != null \
			else profile.initial_noise_frequency
	material.set_shader_parameter("initial_noise_frequency", noise_frequency)
	material.set_shader_parameter("initial_noise_height", profile.initial_noise_height)
	material.set_shader_parameter("initial_noise_detail", profile.initial_noise_detail)
	material.set_shader_parameter("initial_noise_detail_scale", profile.initial_noise_detail_scale)
	material.set_shader_parameter("initial_noise_mound_height", profile.initial_noise_mound_height)
	material.set_shader_parameter("initial_noise_mound_frequency", profile.initial_noise_mound_frequency)
	material.set_shader_parameter("initial_noise_invert", profile.initial_noise_invert)


func finish_priming() -> void:
	if is_instance_valid(background):
		background.queue_free()
		background = null


func run_refill(now: bool, dt: float, recovery_intensity: float,
		refill_levels_per_sec: float) -> void:
	if refill.visible != now:
		refill.visible = now
	if not now:
		return
	var levels := recovery_intensity * refill_levels_per_sec * dt
	var recovery_alpha := 1.0 - exp(-4.0 * levels / 255.0)
	refill_material.set_shader_parameter("recovery_alpha", recovery_alpha)
	refill_material.set_shader_parameter("seed", randf() * 1000.0)


func request_render() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func get_texture() -> Texture2D:
	return viewport.get_texture() if viewport != null else null
