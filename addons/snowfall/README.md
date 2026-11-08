# Snowfall

Atmospheric snowfall for Godot 4. Install this addon independently by copying
the `snowfall` folder into your project's `res://addons/` directory.

`SnowWorldManager` provides a shared weather setup for a world, and `SnowFall`
is the low-level standalone emitter. Weather presets are available in `resources/weather/`:
`calm.tres`, `snowfall.tres`, and `blizzard.tres`.

## [`SnowWorldManager`](scripts/core/snow_world_manager.gd)

Add one manager per world. It creates and follows two emitters: a broad main
field and a smaller near-camera field. It can be used without a
`DeformableSurface`.

| Property | Default | Description |
|---|---:|---|
| `snowfall_intensity` | `0.3` | Weather intensity from `0` to `1`. |
| `wind` | `(0.3, 0)` | Horizontal wind vector. |
| `follow_target` | Empty | Target node for the emitter area. |
| `follow_camera` | `false` | Follow the active camera instead of `follow_target`. |
| `fall_height` | `9.0` | Emitter height above ground in meters. |
| `emitter_area` | `(30, 30)` | Width and depth of the emitter area in meters. |
| `flake_count` | `900` | Main emitter particle budget. |
| `near_flake_count` | `120` | Near-camera emitter particle budget. |
| `weather_enabled` | `true` | Enables or pauses both emitters. |
| `weather_settings` | Empty | Optional `SnowWeatherSettings` resource. When assigned, its settings are applied to the manager. |

The matching setters are `set_snowfall_intensity()`, `set_wind()`,
`set_weather_enabled()`, `set_follow_target()`, `set_follow_camera()`,
`set_fall_height()`, `set_emitter_area()`, `set_flake_count()`,
`set_near_flake_count()`, and `set_weather_settings()`. Use
`set_weather_preset(resource)` to copy settings from a preset resource.
`weather_quality` reports the selected `SnowWeatherSettings.Quality` tier.

## [`SnowWeatherSettings`](scripts/settings/snow_weather_settings.gd)

This resource groups the manager's settings for saving and sharing:

| Property | Default | Description |
|---|---:|---|
| `flake_count` | `900` | Main emitter particle budget. |
| `near_flake_count` | `120` | Near-camera particle budget. |
| `wind` | `(0.3, 0)` | Horizontal wind vector. |
| `fall_height` | `9.0` | Emitter height above ground in meters. |
| `emitter_area` | `(30, 30)` | Emitter width and depth in meters. |
| `snowfall_intensity` | `0.3` | Intensity from `0` to `1`. |
| `follow_target_path` | Empty | Optional target path used by the manager. |
| `follow_camera` | `false` | Follow the active camera. |
| `quality` | `MEDIUM` | `LOW`, `MEDIUM`, or `HIGH`; sets the manager's weather particle budgets. |

## [`SnowFall`](scripts/particles/snow_fall.gd)

Use this `CPUParticles3D` node on its own for a local emitter. By default it
follows `follow_target`, or the active camera when no target is assigned (or
`follow_camera` is true). `area` sets the emitter width/depth; `height` is above
`ground_y`. `fall_speed` is the minimum and maximum fall speed in m/s. `flake_size`
and `flake_color` control the billboard particles.

| Property | Default | Description |
|---|---:|---|
| `area` | `(30, 30)` | Emitter box width and depth in meters. |
| `height` | `9.0` | Emitter height above `ground_y`. |
| `ground_y` | `0.0` | World Y level under the emitter. |
| `fall_speed` | `(1.4, 2.2)` | Minimum and maximum flake speed. |
| `flake_size` | `0.1` | Flake quad size. |
| `flake_color` | White | Flake tint and alpha. |
| `follow_target` | Empty | Node to follow; defaults to active camera. |
| `follow_camera` | `false` | Follow active camera even when a target is assigned. |

Methods: `set_intensity(0..1)` scales particle count, `set_wind(Vector2)`
sets horizontal drift, `set_max_amount(n)` sets the particle budget, and
`set_enabled(bool)` pauses or resumes emission.

```gdscript
var weather := SnowWorldManager.new()
add_child(weather)
weather.follow_target = $Player
weather.weather_settings = load("res://addons/snowfall/resources/weather/snowfall.tres")
```

The manager and emitters operate independently of terrain or surface nodes.
