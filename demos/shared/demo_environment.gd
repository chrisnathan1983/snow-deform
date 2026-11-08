class_name DemoEnvironment
extends Node3D
## Shared demo sky, fog, ambient light, and directional sun rig.

@export_range(6.0, 70.0, 1.0) var sun_height := 30.0:
	set(value):
		sun_height = value
		if is_node_ready():
			_update_sun()
@export var sun_azimuth := -35.0
@export var shadows_enabled := true
@export var shadow_distance := 40.0
@export var fog_enabled := true
@export_range(0.0, 0.1, 0.001) var fog_density := 0.008
@export var powder_run_style := false
@export_range(0.0, 2.0, 0.01) var powder_ambient_energy := 0.55
@export_range(0.0, 2.0, 0.01) var powder_sun_energy := 0.65

var environment: Environment
var sky_material: ProceduralSkyMaterial
var sun: DirectionalLight3D


func _ready() -> void:
	_build()
	_update_sun()


func _build() -> void:
	sky_material = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment = Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if powder_run_style:
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color("dbeaf2")
		environment.ambient_light_color = Color("c7ddec")
		environment.ambient_light_energy = powder_ambient_energy
		environment.fog_enabled = false
	else:
		environment.background_mode = Environment.BG_SKY
		environment.sky = sky
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.fog_enabled = fog_enabled
		environment.fog_density = fog_density
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = shadows_enabled
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = shadow_distance
	sun.shadow_bias = 0.05
	add_child(sun)


func _update_sun() -> void:
	if not is_instance_valid(sun):
		return
	sun.rotation_degrees = Vector3(-sun_height, sun_azimuth, 0.0)
	if powder_run_style:
		sun.light_color = Color("fff0da")
		sun.light_energy = powder_sun_energy
		return
	var daylight := inverse_lerp(6.0, 70.0, sun_height)
	sun.light_color = Color(1.0, 0.76, 0.58).lerp(
			Color(1.0, 0.97, 0.93), clampf(daylight * 1.6, 0.0, 1.0))
	sun.light_energy = lerpf(0.65, 0.85, daylight)
	var horizon := Color(0.93, 0.70, 0.58).lerp(
			Color(0.74, 0.85, 0.96), clampf(daylight * 1.5, 0.0, 1.0))
	sky_material.sky_top_color = Color(0.24, 0.32, 0.58).lerp(
			Color(0.33, 0.57, 0.9), daylight)
	sky_material.sky_horizon_color = horizon
	sky_material.ground_horizon_color = horizon
	sky_material.ground_bottom_color = horizon.darkened(0.1)
	environment.fog_light_color = horizon
	environment.ambient_light_color = Color(0.55, 0.64, 0.85).lerp(
			Color(0.62, 0.72, 0.92), daylight)
	environment.ambient_light_energy = lerpf(0.5, 0.6, daylight)
