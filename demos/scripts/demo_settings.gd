class_name DemoSettings
extends Node
## Standard settings tabs shared by every demo, wired to a list of DeformableSurface nodes and
## optionally a SnowWorldManager and a sun. Controls apply live and also re-emit through
## `DemoHud.changed` (keys "surface.*", "weather.*", "gfx.*") so a demo can react.
##
## `preset_handler` (Callable(name: String)) replaces the default material-preset swap, and
## `sun_handler` (Callable(height_deg: float)) replaces the default sun-height rotation.

const PRESET_DIR := "res://addons/deformable_surface/resources/materials/"
const PRESETS := ["snow", "sand", "mud", "dirt", "ash"]
const QUALITY_NAMES := ["Low", "Medium", "High", "Custom"]
const RESOLUTIONS := [192, 256, 320, 384, 512, 768, 1024, 1536, 2048]
const MSAA_NAMES := ["Off", "2x", "4x"]
const SNOW_PROFILE := preload("res://addons/deformable_surface/resources/materials/snow_profile.tres")
const QUALITY_PRESETS: Array[DeformableSurfaceQuality] = [
	preload("res://addons/deformable_surface/resources/quality/low.tres"),
	preload("res://addons/deformable_surface/resources/quality/medium.tres"),
	preload("res://addons/deformable_surface/resources/quality/high.tres"),
]
const WEATHER_PRESETS: Array[SnowWeatherSettings] = [
	preload("res://addons/snowfall/resources/weather/calm.tres"),
	preload("res://addons/snowfall/resources/weather/snowfall.tres"),
	preload("res://addons/snowfall/resources/weather/blizzard.tres"),
]

var hud: DemoHud
var fields: Array[DeformableSurface] = []
var weather: SnowWorldManager
var sun: DirectionalLight3D
var preset_handler: Callable
var sun_handler: Callable
var area_handler: Callable
## Low / Medium / High resources behind the menu (the demo may supply its own); index 3 is Custom.
var quality_presets: Array[DeformableSurfaceQuality] = QUALITY_PRESETS
var quality_index := 1
var _preset_name := ""
var _pending_surface_updates: Dictionary = {}
var _surface_edit_delay := 0.0


func has_pending_surface_updates() -> bool:
	return not _pending_surface_updates.is_empty()


func _queue_surface_update(f: DeformableSurface, profile: DeformableSurfaceType,
		settings: DeformableSurfaceQuality) -> void:
	profile.clamp_values()
	settings.clamp_values()
	_pending_surface_updates[f] = {"profile": profile, "quality": settings}
	_surface_edit_delay = 0.12


func _process(delta: float) -> void:
	if not has_pending_surface_updates():
		return
	_surface_edit_delay = maxf(0.0, _surface_edit_delay - delta)
	if _surface_edit_delay > 0.0:
		return
	# Prepare and apply one field at a time so uploads/rebuilds are spread over frames.
	var f: DeformableSurface = _pending_surface_updates.keys()[0]
	if not is_instance_valid(f):
		_pending_surface_updates.erase(f)
		return
	var update: Dictionary = _pending_surface_updates[f]
	var profile: DeformableSurfaceType = update["profile"]
	var settings: DeformableSurfaceQuality = update["quality"]
	if not f.prepare_initial_noise_at(f.global_position, profile, settings):
		return
	f.apply_surface_settings(profile, settings)
	_pending_surface_updates.erase(f)


static func create(p_hud: DemoHud, p_fields: Array[DeformableSurface]) -> DemoSettings:
	var s := DemoSettings.new()
	s.hud = p_hud
	s.fields = p_fields
	p_hud.add_child(s)
	p_hud.changed.connect(s._on_changed)
	return s


func _quality_of(f: DeformableSurface) -> DeformableSurfaceQuality:
	if _pending_surface_updates.has(f):
		return _pending_surface_updates[f]["quality"]
	return f.quality if f.quality != null else DeformableSurfaceQuality.medium()


## Include edits still waiting to be applied when rebuilding the field layout.
func current_profile() -> DeformableSurfaceType:
	return _profile_of(_primary())


func current_quality() -> DeformableSurfaceQuality:
	return _quality_of(_primary())


func replace_fields(new_fields: Array[DeformableSurface]) -> void:
	if not fields.is_empty() and is_instance_valid(fields[0]):
		if fields[0].quality_changed.is_connected(_on_quality_changed):
			fields[0].quality_changed.disconnect(_on_quality_changed)
	_pending_surface_updates.clear()
	_surface_edit_delay = 0.0
	fields = new_fields
	if not fields.is_empty():
		fields[0].quality_changed.connect(_on_quality_changed)
	_sync_surface()


func add_surface_tab() -> void:
	var tab := hud.add_tab("Surface")
	var f := _primary()
	if f == null:
		return
	var active := _quality_of(f)
	var profile := _profile_of(f)
	_preset_name = String(profile.type_name)
	hud.add_heading(tab, "Quality")
	hud.add_option(tab, "surface.quality", "Preset", QUALITY_NAMES, quality_index)
	hud.add_option(tab, "surface.preset", "Material", PRESETS.map(func(n): return n.capitalize()),
			_preset_index())
	hud.add_heading(tab, "Material")
	hud.add_slider(tab, "surface.recovery", "Recovery", 0.0, 1.0, 0.01, profile.recovery_intensity)
	hud.add_slider(tab, "surface.max_depth", "Max depth (m)", 0.02, 1.0, 0.01, profile.max_depth)
	hud.add_slider(tab, "surface.berm_strength", "Berm strength", 0.0, 0.5, 0.01, profile.berm_strength)
	hud.add_slider(tab, "surface.berm_height", "Berm height (m)", 0.0, 0.15, 0.005, profile.berm_height)
	hud.add_slider(tab, "surface.noise_detail", "Noise 2nd octave", 0.0, 1.0, 0.05, profile.initial_noise_detail)
	hud.add_slider(tab, "surface.mound_height", "Pile/dune height (m)", 0.0, 1.0, 0.01, profile.initial_noise_mound_height)
	hud.add_slider(tab, "surface.mound_freq", "Pile/dune frequency", 0.02, 0.5, 0.01, profile.initial_noise_mound_frequency)
	hud.add_slider(tab, "surface.noise_scale", "2nd octave scale (<1 = hills)", 0.1, 8.0, 0.05, profile.initial_noise_detail_scale)
	hud.add_toggle(tab, "surface.puffs", "Puff particles", profile.puffs_enabled)
	hud.add_toggle(tab, "surface.wrapped", "Cool shadow tint", profile.wrapped_diffuse_lighting)
	hud.add_button(tab, "surface.reset", "Reset tracks")
	if area_handler.is_valid():
		hud.add_slider(tab, "surface.area_size", "Area size (m)", 8, 80, 2, f.size)
	hud.add_heading(tab, "Technical (switches to Custom)")
	hud.add_option(tab, "surface.res", "Map resolution", RESOLUTIONS,
			_nearest(RESOLUTIONS, active.res))
	hud.add_slider(tab, "surface.subdiv", "Mesh subdivisions", 16, 256, 8, active.subdiv)
	hud.add_slider(tab, "surface.max_stamps", "Max stamps / frame", 8, 256, 8, active.max_stamps_per_frame)
	hud.add_slider(tab, "surface.refill_interval", "Refill interval (s)", 0.05, 1.0, 0.05, active.refill_interval)
	hud.add_slider(tab, "surface.puff_budget", "Puff budget", 1, 64, 1, active.puff)
	hud.add_slider(tab, "surface.puff_interval", "Puff interval (s)", 0.0, 0.5, 0.01, active.puff_min_interval)
	hud.add_slider(tab, "surface.sparkle", "Sparkle", 0.0, 3.0, 0.1, active.sparkle)
	f.quality_changed.connect(_on_quality_changed)


func add_weather_tab(manager: SnowWorldManager) -> void:
	weather = manager
	var tab := hud.add_tab("Weather")
	hud.add_slider(tab, "weather.snowfall", "Snowfall", 0.0, 1.0, 0.05, weather.snowfall_intensity)
	hud.add_slider(tab, "weather.wind_x", "Wind X", -4.0, 4.0, 0.1, weather.wind.x)
	hud.add_slider(tab, "weather.wind_z", "Wind Z", -4.0, 4.0, 0.1, weather.wind.y)
	hud.add_slider(tab, "weather.flakes", "Flakes", 100, 4000, 100, weather.flake_count)
	hud.add_slider(tab, "weather.near_flakes", "Near flakes", 0, 600, 20, weather.near_flake_count)
	hud.add_slider(tab, "weather.fall_height", "Fall height (m)", 2, 30, 0.5, weather.fall_height)


func add_graphics_tab(p_sun: DirectionalLight3D, sun_height := -1.0) -> void:
	sun = p_sun
	var tab := hud.add_tab("Graphics")
	hud.add_toggle(tab, "gfx.shadows", "Sun shadows", sun.shadow_enabled)
	hud.add_option(tab, "gfx.msaa", "MSAA", MSAA_NAMES, int(hud.get_viewport().msaa_3d))
	if sun_height >= 0.0:
		hud.add_slider(tab, "gfx.sun", "Sun height", 6.0, 70.0, 1.0, sun_height)


# ---------------------------------------------------------------- handlers

func _on_changed(key: String, value: Variant) -> void:
	match key:
		"surface.quality": set_quality(int(value))
		"surface.preset": _set_preset(int(value))
		"surface.recovery": edit_profile("recovery_intensity", float(value))
		"surface.max_depth": edit_profile("max_depth", float(value))
		"surface.berm_strength": edit_profile("berm_strength", float(value))
		"surface.berm_height": edit_profile("berm_height", float(value))
		"surface.noise_detail": edit_profile("initial_noise_detail", float(value))
		"surface.mound_height": edit_profile("initial_noise_mound_height", float(value))
		"surface.mound_freq": edit_profile("initial_noise_mound_frequency", float(value))
		"surface.noise_scale": edit_profile("initial_noise_detail_scale", float(value))
		"surface.puffs": edit_profile("puffs_enabled", bool(value))
		"surface.wrapped": edit_profile("wrapped_diffuse_lighting", bool(value))
		"surface.reset":
			for f in fields:
				f.reset_trails()
		"surface.res": _edit_technical("res", RESOLUTIONS[int(value)])
		"surface.subdiv": _edit_technical("subdiv", value)
		"surface.area_size":
			if area_handler.is_valid():
				area_handler.call(float(value))
		"surface.max_stamps": _edit_technical("max_stamps_per_frame", value)
		"surface.refill_interval": _edit_technical("refill_interval", value)
		"surface.puff_budget": _edit_technical("puff", value)
		"surface.puff_interval": _edit_technical("puff_min_interval", value)
		"surface.sparkle": _edit_technical("sparkle", value)
		"weather.snowfall":
			if weather:
				weather.snowfall_intensity = float(value)
			edit_profile("recovery_intensity", float(value))
			hud.set_value("surface.recovery", float(value))
		"weather.wind_x":
			if weather:
				weather.wind = Vector2(float(value), weather.wind.y)
		"weather.wind_z":
			if weather:
				weather.wind = Vector2(weather.wind.x, float(value))
		"weather.flakes":
			if weather:
				weather.flake_count = int(value)
		"weather.near_flakes":
			if weather:
				weather.near_flake_count = int(value)
		"weather.fall_height":
			if weather:
				weather.fall_height = float(value)
		"gfx.shadows":
			if sun:
				sun.shadow_enabled = bool(value)
		"gfx.msaa":
			hud.get_viewport().msaa_3d = int(value) as Viewport.MSAA
		"gfx.sun":
			if sun_handler.is_valid():
				sun_handler.call(float(value))
			elif sun:
				sun.rotation_degrees.x = -float(value)


func set_quality(index: int) -> void:
	quality_index = index
	if index < 3:
		for f in fields:
			_queue_surface_update(f, _profile_of(f).duplicate() as DeformableSurfaceType,
					quality_presets[index].duplicate() as DeformableSurfaceQuality)
	if weather and index < WEATHER_PRESETS.size():
		var preset := WEATHER_PRESETS[index]
		weather.flake_count = preset.flake_count
		weather.near_flake_count = preset.near_flake_count
		hud.set_value("weather.flakes", weather.flake_count)
		hud.set_value("weather.near_flakes", weather.near_flake_count)
	_sync_surface()


func _set_preset(index: int) -> void:
	var preset: String = PRESETS[index]
	_preset_name = preset
	if preset_handler.is_valid():
		preset_handler.call(preset)
		_sync_surface()
		return
	var source := load(PRESET_DIR + preset + "_profile.tres") as DeformableSurfaceType
	if source == null:
		return
	for f in fields:
		var previous := _profile_of(f)
		var p := source.duplicate() as DeformableSurfaceType
		p.recovery_intensity = previous.recovery_intensity
		p.initial_noise_enabled = previous.initial_noise_enabled and p.initial_noise_enabled
		_queue_surface_update(f, p, _quality_of(f).duplicate() as DeformableSurfaceQuality)
	_sync_surface()


## Applies a surface-type property to every surface (on a duplicate, never the shared resource).
func edit_profile(prop: String, value: Variant) -> void:
	for f in fields:
		var p := _profile_of(f).duplicate() as DeformableSurfaceType
		p.set(prop, value)
		_queue_surface_update(f, p, _quality_of(f).duplicate() as DeformableSurfaceQuality)


func _edit_technical(key: String, value: Variant) -> void:
	for f in fields:
		var q := _quality_of(f).duplicate() as DeformableSurfaceQuality
		var numeric_value: Variant
		if q.get(key) is int:
			numeric_value = int(value)
		else:
			numeric_value = float(value)
		q.set(key, numeric_value)
		_queue_surface_update(f, _profile_of(f).duplicate() as DeformableSurfaceType, q)
	quality_index = 3
	hud.set_value("surface.quality", quality_index)


## Pulls the surface's real values back into the controls after a preset or quality switch.
func _sync_surface() -> void:
	var f := _primary()
	if f == null or not hud.has_control("surface.quality"):
		return
	var p := _profile_of(f)
	var active := _quality_of(f)
	hud.set_value("surface.quality", quality_index)
	hud.set_value("surface.preset", _preset_index())
	hud.set_value("surface.recovery", p.recovery_intensity)
	hud.set_value("surface.max_depth", p.max_depth)
	hud.set_value("surface.berm_strength", p.berm_strength)
	hud.set_value("surface.berm_height", p.berm_height)
	hud.set_value("surface.noise_detail", p.initial_noise_detail)
	hud.set_value("surface.noise_scale", p.initial_noise_detail_scale)
	hud.set_value("surface.mound_height", p.initial_noise_mound_height)
	hud.set_value("surface.mound_freq", p.initial_noise_mound_frequency)
	hud.set_value("surface.puffs", p.puffs_enabled)
	hud.set_value("surface.wrapped", p.wrapped_diffuse_lighting)
	hud.set_value("surface.res", _nearest(RESOLUTIONS, active.res))
	hud.set_value("surface.subdiv", float(active.subdiv))
	hud.set_value("surface.area_size", f.size)
	hud.set_value("surface.max_stamps", float(active.max_stamps_per_frame))
	hud.set_value("surface.refill_interval", active.refill_interval)
	hud.set_value("surface.puff_budget", float(active.puff))
	hud.set_value("surface.puff_interval", active.puff_min_interval)
	hud.set_value("surface.sparkle", active.sparkle)


func _on_quality_changed(_quality: DeformableSurfaceQuality) -> void:
	_sync_surface()


func _primary() -> DeformableSurface:
	return fields[0] if not fields.is_empty() else null


func _profile_of(f: DeformableSurface) -> DeformableSurfaceType:
	if _pending_surface_updates.has(f):
		return _pending_surface_updates[f]["profile"]
	if f.surface_type != null:
		return f.surface_type
	return DeformableSurfaceType.new()


func _preset_index() -> int:
	return PRESETS.find(_preset_name)


func _nearest(list: Array, value: int) -> int:
	var best := 0
	for i in list.size():
		if absi(int(list[i]) - value) < absi(int(list[best]) - value):
			best = i
	return best
