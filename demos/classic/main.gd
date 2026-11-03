extends Node3D
## Connects the scene-authored world, snow system, and demo controls.

const PERSON_SCENE := preload("res://demos/classic/actors/npc.tscn")
const MOUSE_SCENE := preload("res://demos/classic/actors/mouse.tscn")
const LOW_SURFACE_PROFILE: DeformableSurfaceSettings = preload(
	"res://addons/deformable_surface/resources/quality/low_surface.tres"
)
const MEDIUM_SURFACE_PROFILE: DeformableSurfaceSettings = preload(
	"res://addons/deformable_surface/resources/quality/medium_surface.tres"
)
const HIGH_SURFACE_PROFILE: DeformableSurfaceSettings = preload(
	"res://addons/deformable_surface/resources/quality/high_surface.tres"
)
const CUSTOM_SURFACE_PROFILE: DeformableSurfaceSettings = preload(
	"res://addons/deformable_surface/resources/quality/custom_surface.tres"
)
const CALM_WEATHER_PROFILE: SnowWeatherSettings = preload(
	"res://addons/snowfall/resources/weather/calm.tres"
)
const SNOWFALL_WEATHER_PROFILE: SnowWeatherSettings = preload(
	"res://addons/snowfall/resources/weather/snowfall.tres"
)
const BLIZZARD_WEATHER_PROFILE: SnowWeatherSettings = preload(
	"res://addons/snowfall/resources/weather/blizzard.tres"
)

@onready var snow: DeformableSurface = $DeformableSurface
@onready var weather: SnowWorldManager = $SnowWorldManager
@onready var player: Player = $Actors/Player
@onready var npcs: Node3D = $Actors/NPCs
@onready var sled: Node3D = $Actors/Sled
@onready var hud: DemoHud = $HUD
@onready var sun: DirectionalLight3D = $Sun

var _people: Array[Node3D] = []
var _mice: Array[Node3D] = []
var _person_serial := 0
var _mouse_serial := 1
var _real_shadows := false
var _msaa_mode := Viewport.MSAA_2X
var _custom_quality_settings: Dictionary = {}
@export_enum("Camera:0", "Player:1", "Sled:2") var follow_target_mode := 0


func _ready() -> void:
	snow.low_surface_quality = LOW_SURFACE_PROFILE
	snow.medium_surface_quality = MEDIUM_SURFACE_PROFILE
	snow.high_surface_quality = HIGH_SURFACE_PROFILE
	snow.custom_surface_quality = CUSTOM_SURFACE_PROFILE
	snow.set_quality(snow.quality)
	_custom_quality_settings = _get_quality_settings(DeformableSurface.Quality.CUSTOM)
	var initial_settings := _get_active_quality_settings()
	snow.recovery_intensity = float(initial_settings["recovery_intensity"])
	_apply_weather_settings(initial_settings, float(initial_settings["snowfall"]))
	_apply_follow_target(initial_settings["follow_target_mode"])
	snow.quality_changed.connect(_on_quality_changed)
	_on_quality_changed(snow.quality)

	for person in npcs.get_children():
		_people.append(person as Node3D)
	_mice.append($Actors/Mouse as Node3D)
	hud.set_population_counts(_people.size(), _mice.size())

	hud.preset_selected.connect(_on_preset_selected)
	hud.options_previewed.connect(_apply_options)
	hud.options_cancelled.connect(_apply_options)
	hud.options_confirmed.connect(_apply_options)
	hud.reset_pressed.connect(snow.reset_trails)
	hud.jump_pressed.connect(player.request_jump)
	hud.add_person_pressed.connect(_add_person)
	hud.remove_person_pressed.connect(_remove_person)
	hud.add_mouse_pressed.connect(_add_mouse)
	hud.remove_mouse_pressed.connect(_remove_mouse)
	player.touch_stick = hud.stick

	player.add_child(BlobShadow.make(1.2, snow.quality != DeformableSurface.Quality.HIGH))
	for npc in npcs.get_children():
		npc.add_child(BlobShadow.make(1.2, snow.quality != DeformableSurface.Quality.HIGH))
	sled.add_child(BlobShadow.make(2.0, snow.quality != DeformableSurface.Quality.HIGH))


func _on_quality_changed(q: DeformableSurface.Quality) -> void:
	if not hud.options_panel.visible:
		hud.set_current_options(
			q,
			_get_active_quality_settings(),
			snow.recovery_intensity,
			snow.has_custom_quality_settings(),
			_real_shadows,
			_msaa_mode,
			snow.wrapped_diffuse_lighting
		)
	_apply_render_options()


func _apply_render_options() -> void:
	sun.shadow_enabled = _real_shadows
	get_viewport().msaa_3d = _msaa_mode
	for shadow in get_tree().get_nodes_in_group(&"blob_shadow"):
		shadow.visible = not _real_shadows


func _on_preset_selected(q: int) -> void:
	hud.set_draft_preset(q, _get_quality_settings(q as DeformableSurface.Quality))


func _apply_options(
	q: int,
	custom: bool,
	settings: Dictionary,
	snowfall: float,
	shadows: bool,
	msaa: int,
	wrapped_diffuse_lighting: bool
) -> void:
	var selected_quality := q as DeformableSurface.Quality
	_real_shadows = shadows
	_msaa_mode = msaa as Viewport.MSAA
	if custom and selected_quality == snow.quality:
		snow.apply_quality_settings(settings)
	else:
		snow.quality = selected_quality
		if custom:
			snow.apply_quality_settings(settings)
	if custom:
		_custom_quality_settings = settings.duplicate(true)
	snow.recovery_intensity = snowfall
	_apply_weather_settings(settings, snowfall)
	snow.wrapped_diffuse_lighting = wrapped_diffuse_lighting
	_apply_follow_target(settings["follow_target_mode"])
	_apply_render_options()


func _get_quality_settings(q: DeformableSurface.Quality) -> Dictionary:
	var surface_settings := snow.get_surface_quality_settings(q)
	if surface_settings == null:
		push_error("Classic demo: surface quality profile is not assigned.")
		return {}
	var weather_profile: SnowWeatherSettings
	match q:
		DeformableSurface.Quality.LOW:
			weather_profile = CALM_WEATHER_PROFILE
		DeformableSurface.Quality.MEDIUM:
			weather_profile = SNOWFALL_WEATHER_PROFILE
		DeformableSurface.Quality.HIGH:
			weather_profile = BLIZZARD_WEATHER_PROFILE
		DeformableSurface.Quality.CUSTOM:
			if not _custom_quality_settings.is_empty():
				var current := _custom_quality_settings.duplicate(true)
				current.merge(surface_settings.to_dictionary(), true)
				return current
			weather_profile = BLIZZARD_WEATHER_PROFILE
		_:
			push_error("Classic demo: invalid quality profile.")
			return {}
	var settings := weather_profile.to_dictionary()
	settings.merge(surface_settings.to_dictionary(), true)
	settings["follow_target_mode"] = follow_target_mode
	settings["snowfall"] = weather_profile.snowfall_intensity
	return settings


func _get_active_quality_settings() -> Dictionary:
	var settings := _get_quality_settings(snow.quality)
	var snowfall := float(settings.get("snowfall", snow.recovery_intensity))
	settings.merge(snow.get_active_quality_settings(), true)
	settings["snowfall"] = snowfall
	return settings


func _apply_weather_settings(settings: Dictionary, intensity: float) -> void:
	var weather_settings := SnowWeatherSettings.new()
	weather_settings.flake_count = int(settings.get("flakes", weather.flake_count))
	weather_settings.near_flake_count = int(settings.get("near", weather.near_flake_count))
	weather_settings.wind = Vector2(
		float(settings.get("wind_x", weather.wind.x)),
		float(settings.get("wind_z", weather.wind.y))
	)
	weather_settings.fall_height = float(settings.get("fall_height", weather.fall_height))
	var emitter_area: Variant = settings.get("emitter_area", weather.emitter_area)
	if emitter_area is Vector2:
		weather_settings.emitter_area = emitter_area
	weather_settings.snowfall_intensity = intensity
	weather_settings.follow_target_path = NodePath("../Actors/Player")
	weather_settings.follow_camera = bool(settings.get("follow_camera", weather.follow_camera))
	weather_settings.quality = snow.quality as SnowWeatherSettings.Quality
	weather.weather_settings = weather_settings


func _apply_follow_target(mode: int) -> void:
	match mode:
		1:
			weather.set_follow_target(player)
		2:
			weather.set_follow_target(sled)
		_:
			weather.set_follow_target(null)


func _add_person() -> void:
	var person := PERSON_SCENE.instantiate() as SnowNPC
	if person == null:
		push_error("Demo: could not instantiate a person.")
		return
	_person_serial += 1
	person.name = "Person%d" % _person_serial
	person.position = Vector3(randf_range(-9.0, 9.0), 0.0, randf_range(-9.0, 9.0))
	person.speed = randf_range(2.0, 3.2)
	npcs.add_child(person)
	person.add_child(BlobShadow.make(1.2, snow.quality != DeformableSurface.Quality.HIGH))
	_people.append(person)
	hud.set_population_counts(_people.size(), _mice.size())


func _remove_person() -> void:
	if _people.is_empty():
		return
	_people.pop_back().queue_free()
	hud.set_population_counts(_people.size(), _mice.size())


func _add_mouse() -> void:
	var mouse := MOUSE_SCENE.instantiate() as Node3D
	if mouse == null:
		push_error("Demo: could not instantiate a mouse.")
		return
	_mouse_serial += 1
	mouse.name = "Mouse%d" % _mouse_serial
	mouse.position = Vector3(randf_range(-9.0, 9.0), 0.0, randf_range(-9.0, 9.0))
	$Actors.add_child(mouse)
	_mice.append(mouse)
	hud.set_population_counts(_people.size(), _mice.size())


func _remove_mouse() -> void:
	if _mice.is_empty():
		return
	_mice.pop_back().queue_free()
	hud.set_population_counts(_people.size(), _mice.size())
