# Snowfall

Atmospheric snowfall for Godot 4. Install this addon independently by copying
the `snowfall` folder into your project's `res://addons/` directory.

`SnowWorldManager` provides a shared weather setup for a world.
`SnowWeather` is the legacy manager, and `SnowFall` is the low-level standalone
emitter. Weather presets are available in `resources/weather/`:
`calm.tres`, `snowfall.tres`, and `blizzard.tres`.

```gdscript
var weather := SnowWorldManager.new()
add_child(weather)
weather.follow_target = $Player
weather.weather_settings = load("res://addons/snowfall/resources/weather/snowfall.tres")
```

The manager and emitters operate independently of terrain or surface nodes.
