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
const RESOLUTIONS := [256, 384, 512, 768, 1024, 1536, 2048]
const MSAA_NAMES := ["Off", "2x", "4x"]
const FLAKES := [[300, 0], [900, 120], [2000, 280]]

var hud: DemoHud
var fields: Array[DeformableSurface] = []
var weather: SnowWorldManager
var sun: DirectionalLight3D
var preset_handler: Callable
var sun_handler: Callable
var allow_area := false
var _preset_name := ""


static func create(p_hud: DemoHud, p_fields: Array[DeformableSurface]) -> DemoSettings:
	var s := DemoSettings.new()
	s.hud = p_hud
	s.fields = p_fields
	p_hud.add_child(s)
	p_hud.changed.connect(s._on_changed)
	return s


func add_surface_tab() -> void:
	var tab := hud.add_tab("Surface")
	var f := _primary()
	if f == null:
		return
	var active := f.get_active_quality_settings()
	var profile := _profile_of(f)
	_preset_name = profile.resource_path.get_file().get_basename().trim_suffix("_profile")
	hud.add_heading(tab, "Quality")
	hud.add_option(tab, "surface.quality", "Preset", QUALITY_NAMES, int(f.quality))
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
	hud.add_toggle(tab, "surface.wrapped", "Wrapped diffuse lighting", profile.wrapped_diffuse_lighting)
	hud.add_button(tab, "surface.reset", "Reset tracks")
	hud.add_heading(tab, "Technical (switches to Custom)")
	hud.add_option(tab, "surface.res", "Map resolution", RESOLUTIONS,
			_nearest(RESOLUTIONS, int(active.get("res", 768))))
	hud.add_slider(tab, "surface.subdiv", "Mesh subdivisions", 16, 256, 8, float(active.get("subdiv", 128)))
	if allow_area:
		hud.add_slider(tab, "surface.area_size", "Area size (m)", 8, 80, 2, float(active.get("area_size", 32)))
	hud.add_slider(tab, "surface.max_stamps", "Max stamps / frame", 8, 256, 8,
			float(active.get("max_stamps_per_frame", 64)))
	hud.add_slider(tab, "surface.refill_interval", "Refill interval (s)", 0.05, 1.0, 0.05,
			float(active.get("refill_interval", 0.25)))
	hud.add_slider(tab, "surface.puff_budget", "Puff budget", 1, 64, 1, float(active.get("puff", 8)))
	hud.add_slider(tab, "surface.puff_interval", "Puff interval (s)", 0.0, 0.5, 0.01,
			float(active.get("puff_min_interval", 0.0)))
	hud.add_slider(tab, "surface.sparkle", "Sparkle", 0.0, 3.0, 0.1, float(active.get("sparkle", 1.0)))
	f.quality_changed.connect(func(_q): _sync_surface())


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
		"surface.area_size": _edit_technical("area_size", value)
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
	for f in fields:
		if index == DeformableSurface.Quality.CUSTOM:
			f.apply_quality_settings(f.get_active_quality_settings())
		else:
			f.quality = index as DeformableSurface.Quality
	if weather and index < FLAKES.size():
		weather.flake_count = FLAKES[index][0]
		weather.near_flake_count = FLAKES[index][1]
		hud.set_value("weather.flakes", FLAKES[index][0])
		hud.set_value("weather.near_flakes", FLAKES[index][1])
	_sync_surface()


func _set_preset(index: int) -> void:
	var preset: String = PRESETS[index]
	_preset_name = preset
	if preset_handler.is_valid():
		preset_handler.call(preset)
		_sync_surface()
		return
	var source := load(PRESET_DIR + preset + "_profile.tres") as DeformableSurfaceMaterialProfile
	if source == null:
		return
	for f in fields:
		var previous := _profile_of(f)
		var p := source.duplicate() as DeformableSurfaceMaterialProfile
		p.recovery_intensity = previous.recovery_intensity
		p.initial_noise_enabled = previous.initial_noise_enabled and p.initial_noise_enabled
		f.material_profile = p
	_sync_surface()


## Applies a material-profile property to every surface (on a duplicate, never the shared resource).
func edit_profile(prop: String, value: Variant) -> void:
	for f in fields:
		var p := _profile_of(f).duplicate() as DeformableSurfaceMaterialProfile
		p.set(prop, value)
		f.material_profile = p


func _edit_technical(key: String, value: Variant) -> void:
	for f in fields:
		var settings := f.get_active_quality_settings()
		settings[key] = value
		f.apply_quality_settings(settings)
	hud.set_value("surface.quality", DeformableSurface.Quality.CUSTOM)


## Pulls the surface's real values back into the controls after a preset or quality switch.
func _sync_surface() -> void:
	var f := _primary()
	if f == null or not hud.has_control("surface.quality"):
		return
	var p := _profile_of(f)
	var active := f.get_active_quality_settings()
	hud.set_value("surface.quality", int(f.quality))
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
	hud.set_value("surface.res", _nearest(RESOLUTIONS, int(active.get("res", 768))))
	hud.set_value("surface.subdiv", float(active.get("subdiv", 128)))
	hud.set_value("surface.area_size", float(active.get("area_size", 32)))
	hud.set_value("surface.max_stamps", float(active.get("max_stamps_per_frame", 64)))
	hud.set_value("surface.refill_interval", float(active.get("refill_interval", 0.25)))
	hud.set_value("surface.puff_budget", float(active.get("puff", 8)))
	hud.set_value("surface.puff_interval", float(active.get("puff_min_interval", 0.0)))
	hud.set_value("surface.sparkle", float(active.get("sparkle", 1.0)))


func _primary() -> DeformableSurface:
	return fields[0] if not fields.is_empty() else null


func _profile_of(f: DeformableSurface) -> DeformableSurfaceMaterialProfile:
	if f.material_profile != null:
		return f.material_profile
	return DeformableSurfaceMaterialProfile.new()


func _preset_index() -> int:
	return PRESETS.find(_preset_name)


func _nearest(list: Array, value: int) -> int:
	var best := 0
	for i in list.size():
		if absi(int(list[i]) - value) < absi(int(list[best]) - value):
			best = i
	return best
