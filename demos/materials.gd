extends Node3D
## Showcases the material presets, albedo/normal texture inputs and triplanar mode.
## Hold the left mouse button to carve the surface; right-drag to orbit; wheel to zoom.

const PRESET_DIR := "res://addons/deformable_surface/resources/materials/"
const PRESETS := ["snow", "sand", "mud", "dirt", "ash"]
const AREA := 24.0
const QUALITY_PRESETS: Array[DeformableSurfaceQuality] = [
	preload("res://demos/resources/materials/low.tres"),
	preload("res://demos/resources/materials/medium.tres"),
	preload("res://demos/resources/materials/high.tres"),
]

var _surface: DeformableSurface
var _deformer: BrushDeformer
var _camera: DemoCamera
var _sun: DirectionalLight3D
var _demo_environment: DemoEnvironment
var _material: ShaderMaterial
var _preset := "snow"
var _use_albedo := false
var _use_normal := false
var _triplanar := false
var _texture_scale := 0.5
var _uv_tiling := 8.0
var _normal_strength := 1.0

var _albedo_tex: NoiseTexture2D
var _normal_tex: NoiseTexture2D

var _drive := false
var _drive_time := 0.0
var _vehicle: Node3D
var _tracks: DeformerTracks
var _autopilot_time := 0.0
var _hud: DemoHud
var _shell: DemoShell


func _ready() -> void:
	_shell = DemoShell.attach(self)
	_build_world()
	_build_textures()
	_build_ui()
	_apply_preset("snow")


func _build_world() -> void:
	_demo_environment = preload("res://demos/shared/demo_environment.tscn").instantiate() as DemoEnvironment
	_demo_environment.sun_height = 50.0
	_demo_environment.shadows_enabled = true
	add_child(_demo_environment)
	_sun = _demo_environment.sun

	_surface = DeformableSurface.new()
	_surface.sun = _sun
	_surface.size = AREA
	_surface.quality = QUALITY_PRESETS[1]
	_surface.surface_type = DemoSettings.SNOW_PROFILE
	add_child(_surface)

	_deformer = BrushDeformer.new()
	_deformer.field = _surface
	_deformer.radius = 0.6
	_deformer.puff_distance = 0.8
	_deformer.active = false
	add_child(_deformer)

	_vehicle = Node3D.new()
	_vehicle.visible = false
	add_child(_vehicle)
	_tracks = DeformerTracks.new()
	_tracks.field = _surface
	_tracks.active = false
	_vehicle.add_child(_tracks)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.5, 2.0)
	body.mesh = box
	body.position.y = 0.55
	_vehicle.add_child(body)

	_camera = DemoCamera.new()
	_camera.auto_update = false
	_camera.mode = DemoCamera.Mode.ORBIT
	_camera.pitch = 0.9
	_camera.distance = 14.0
	_camera.pitch_limits = Vector2(0.25, 1.45)
	_camera.distance_limits = Vector2(4.0, 30.0)
	add_child(_camera)
	_camera.update_view()
	_deformer.camera = _camera
	_deformer.is_blocked = _shell.hud.over_ui


func _build_textures() -> void:
	var albedo_noise := FastNoiseLite.new()
	albedo_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	albedo_noise.frequency = 0.03
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.55, 0.55))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	_albedo_tex = NoiseTexture2D.new()
	_albedo_tex.noise = albedo_noise
	_albedo_tex.color_ramp = ramp
	_albedo_tex.seamless = true
	_albedo_tex.width = 512
	_albedo_tex.height = 512

	var normal_noise := FastNoiseLite.new()
	normal_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	normal_noise.frequency = 0.05
	normal_noise.fractal_octaves = 4
	_normal_tex = NoiseTexture2D.new()
	_normal_tex.noise = normal_noise
	_normal_tex.as_normal_map = true
	_normal_tex.bump_strength = 6.0
	_normal_tex.seamless = true
	_normal_tex.width = 512
	_normal_tex.height = 512


func _apply_preset(preset: String) -> void:
	_preset = preset
	var profile := load(PRESET_DIR + preset + "_profile.tres") as DeformableSurfaceType
	_material = profile.material.duplicate() as ShaderMaterial
	# Each preset starts with its own noise (carried by the surface type).
	_surface.surface_type = profile
	_push_material()


func _push_material() -> void:
	_material.set_shader_parameter("albedo_texture", _albedo_tex if _use_albedo else null)
	_material.set_shader_parameter("normal_texture", _normal_tex if _use_normal else null)
	_material.set_shader_parameter("triplanar", _triplanar)
	_material.set_shader_parameter("texture_scale", _texture_scale)
	_material.set_shader_parameter("uv_tiling", _uv_tiling)
	_material.set_shader_parameter("texture_normal_strength", _normal_strength)
	# Toggling textures keeps trails; switching presets changes depth and clears them.
	_surface.material = _material
	_refresh_info()


func _refresh_info() -> void:
	if _hud:
		_hud.set_info("%s  |  albedo tex %s  |  normal tex %s  |  triplanar %s" % [
			_preset.capitalize(), _on_off(_use_albedo), _on_off(_use_normal), _on_off(_triplanar)])


func _on_off(value: bool) -> String:
	return "on" if value else "off"


func _build_ui() -> void:
	_hud = _shell.hud
	_hud.set_title("Materials")
	var fields: Array[DeformableSurface] = [_surface]
	var settings := _shell.bind_surfaces(fields)
	settings.preset_handler = _apply_preset
	settings.quality_presets = QUALITY_PRESETS
	settings.add_surface_tab()
	settings.add_graphics_tab(_sun)

	var tab := _hud.add_tab("Scene")
	_hud.add_heading(tab, "Textures")
	_hud.add_toggle(tab, "albedo", "Albedo texture", _use_albedo)
	_hud.add_toggle(tab, "normal", "Normal texture", _use_normal)
	_hud.add_toggle(tab, "triplanar", "Triplanar projection", _triplanar)
	_hud.add_slider(tab, "texture_scale", "Triplanar tiles / m", 0.1, 3.0, 0.05, _texture_scale)
	_hud.add_slider(tab, "uv_tiling", "UV tiling", 1.0, 32.0, 0.5, _uv_tiling)
	_hud.add_slider(tab, "normal_strength", "Texture normal strength", 0.0, 3.0, 0.05, _normal_strength)
	_hud.add_heading(tab, "Brush")
	_hud.add_option(tab, "brush", "Mode", ["Carve", "Raise", "Smooth (plow)"], 0)
	_hud.add_heading(tab, "Vehicle")
	_hud.add_toggle(tab, "drive", "Drive vehicle", false)
	_hud.add_option(tab, "vehicle", "Type", ["Car", "Truck", "Motorcycle", "Tracked"], 0)
	_hud.changed.connect(_on_hud_changed)
	_hud.set_hint("LMB brush | E explosion | RMB drag orbit | wheel zoom | M menu", 12.0)
	_refresh_info()


func _on_hud_changed(key: String, value: Variant) -> void:
	match key:
		"albedo":
			_use_albedo = bool(value)
			_push_material()
		"normal":
			_use_normal = bool(value)
			_push_material()
		"triplanar":
			_triplanar = bool(value)
			_push_material()
		"texture_scale":
			_texture_scale = float(value)
			_material.set_shader_parameter("texture_scale", _texture_scale)
		"uv_tiling":
			_uv_tiling = float(value)
			_material.set_shader_parameter("uv_tiling", _uv_tiling)
		"normal_strength":
			_normal_strength = float(value)
			_material.set_shader_parameter("texture_normal_strength", _normal_strength)
		"brush":
			_deformer.mode = [DeformableSurface.StampMode.CARVE, DeformableSurface.StampMode.RAISE,
					DeformableSurface.StampMode.SMOOTH][int(value)]
		"drive":
			_drive = bool(value)
			_vehicle.visible = _drive
			_tracks.reset_path()
		"vehicle":
			_tracks.preset = [DeformerTracks.Preset.CAR, DeformerTracks.Preset.TRUCK,
					DeformerTracks.Preset.MOTORCYCLE, DeformerTracks.Preset.TRACKED][int(value)]
			_tracks.wheel_width = 0.7 if _tracks.preset == DeformerTracks.Preset.TRACKED else 0.3


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_E:
		var hit := _deformer.ground_point(get_viewport().get_mouse_position())
		if hit != Vector3.INF:
			_surface.stamp_at(hit, 2.0, 1.0, null, DeformableSurface.StampMode.CARVE, 0.0, 1.0, true)
			_surface.stamp_at(hit, 0.8, 1.0, null, DeformableSurface.StampMode.RAISE)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.zoom(-0.8)
			_camera.update_view()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.zoom(0.8)
			_camera.update_view()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_camera.drag(event.relative, 0.005)
		_camera.update_view()


func _process(delta: float) -> void:
	if _drive:
		_drive_time += delta
		var a := _drive_time * 0.45
		_vehicle.position = Vector3(cos(a) * 7.0, 0.0, sin(a) * 7.0)
		_vehicle.rotation.y = -a - PI
	_tracks.active = _drive
	if _deformer.painting:
		_deformer.paint_at_pointer()
	elif not Input.is_anything_pressed():
		# Idle: trace a slow figure so tracks appear right away.
		_autopilot_time += delta
		var t := _autopilot_time * 0.6
		_deformer.active = true
		_deformer.global_position = Vector3(sin(t) * 5.0, 0.0, sin(t * 2.0) * 3.0)
	else:
		_deformer.active = false
