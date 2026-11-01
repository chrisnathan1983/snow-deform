# Deformable Snow

Deformable, sparkly snow for Godot 4. Snow responds to footprints and other
deformers, builds small berms beside tracks, gradually heals tracks during
snowfall, and can emit falling flakes and kicked-up snow puffs.

The addon is designed for the **Compatibility renderer** (WebGL2 and mobile
friendly) and requires **Godot 4.3 or newer**.

## Installation

1. Copy this `deformable_snow` folder into your project's
   `res://addons/deformable_snow/` directory. Keep the folder name; node icons
   reference it.
2. The addon appears in *Project > Project Settings > Plugins*. Enabling it is
   optional: the nodes register using `class_name` and are available without
   enabling the plugin.
3. Add a `SnowField` node to your scene, then add deformers to the objects that
   should leave tracks.

## Quick start

1. Add a `SnowField` at ground level. Set `area_size` to a square that covers
   the area where tracks should appear.
2. Add a `SnowFootsteps` under each walking character, with its origin at the
   feet and the character facing -Z. For sleds, wheels, or other objects, add
   one or more `SnowDeformer` nodes instead.
3. Set the field's `follow_target` to the player and `sun` to the scene's
   `DirectionalLight3D`.

The editor displays a flat preview of the field. A minimal runtime setup:

```gdscript
var snow := SnowField.new()
snow.area_size = Vector2(24, 24)
snow.quality = SnowField.recommended_quality()
snow.sun = $Sun
snow.follow_target = $Player
add_child(snow)

var runner := SnowDeformer.new()
runner.radius = 0.5
runner.aspect = 3.0
$Sled.add_child(runner)
```

## Nodes

### SnowField

The snow surface and controller for deformation, snowfall, and puffs. Keep the
field and its parents unrotated and unscaled. The surface is at the field's Y
position; `area_size` should be square.

| Property | Default | Description |
|---|---:|---|
| `area_size` | `(40, 40)` | Width and depth in meters. Smaller areas give sharper prints at the same quality. The options menu edits this as a square field size. |
| `material` | Empty | Optional `ShaderMaterial` using `shaders/snow.gdshader`. Each field duplicates the material. |
| `sun` | Empty | Optional directional light that controls sparkle direction. |
| `wrapped_diffuse_lighting` | `true` | Enables wrapped diffuse lighting with cool-tinted shadows on footprint bevels; disable to use standard diffuse lighting. |
| `max_depth` | `0.25` | Sink depth in meters at full compression. Deformers above this height are ignored. |
| `quality` | Medium | Starting quality profile. Choose Low, Medium, High, or Custom. Quality changes preserve tracks unless map resolution or field size changes. |
| `low_quality`, `medium_quality`, `high_quality` | Quality resources | Editable `SnowQualitySettings` resources used by each built-in profile. |
| `custom_quality` | Medium-equivalent resource | Editable `SnowQualitySettings` resource used by the Custom profile. Each SnowField duplicates it at runtime. |
| `auto_quality` | `false` | Selects Low on mobile, Medium on desktop browsers, and High elsewhere at startup. Overrides `quality`. |
| `max_stamps_per_frame` | `64` | Maximum deformation stamps drawn per frame. Unfinished tracks continue on later frames. |
| `berm_strength` | `0.15` | Strength of ridges beside tracks; set to `0` to disable berms. |
| `berm_height` | `0.08` | Maximum berm height in meters. |
| `snowfall` | `0.3` | Snowfall intensity from `0` to `1`. Controls flake intensity and track healing; `0` stops flakes and healing. |
| `refill_levels_per_sec` | `16.0` | Track-healing rate at snowfall `1`, measured in 8-bit map levels per second. |
| `berm_decay_mult` | `1.5` | Berms smooth out this many times faster than tracks heal. |
| `refill_interval` | `0.25` | Seconds between track-healing passes. |
| `wind` | `(0.3, 0)` | Horizontal flake drift acceleration in world X/Z, in meters per second squared. |
| `fall_height` | `9.0` | Height of the main flake emitter above the field. |
| `follow_target` | Empty | Node followed by the main emitter. If empty, it follows the active camera. The demo menu selects Camera, Player, or Sled. |
| `puffs_enabled` | `true` | Enables kicked-up puffs from deformers. |
| `puff_min_interval` | `0.2` | Minimum seconds between puffs from one deformer. |

#### Quality resources

Each profile is a `SnowQualitySettings` resource containing all settings
exposed in the demo menu. The Inspector displays them in collapsible Surface
(field size, depth, berms, stamp budget, berm decay, refill interval, trail
refill speed, snowfall, and sparkle), Particles (wind, flake and puff settings, and
follow target), and Graphics (map/mesh quality, shadows, MSAA, and wrapped
diffuse lighting) groups. In-game, these groups are separate tabs, and each
setting has a short description in the menu and Inspector. The default
Low, Medium, High, and Custom resources are in `resources/quality_*.tres`;
assign or edit these profiles on the SnowField in the Inspector. Node
references such as `material` and `sun`, and startup-only `auto_quality`,
remain scene settings rather than menu values.
The particle values below are maximum counts at 100% snowfall. The Medium and
High profiles include a second, larger-flake emitter near the camera. Low has
no near-camera emitter.

| Quality | Map resolution | Mesh subdivisions per side | Main flakes | Near-camera flakes | Puff particles per burst |
|---|---:|---:|---:|---:|---:|
| Low | 256 x 256 | 63 | 300 | 0 | 4 |
| Medium | 512 x 512 | 127 | 900 | 120 | 8 |
| High | 1024 x 1024 | 191 | 2000 | 280 | 12 |

Snowfall scales the particle count from zero to the preset maximum. At 100%,
track recovery uses the configured `refill_levels_per_sec` (16 levels per
second by default). Snowfall does not change berm height or the puff rate.

**Methods and signal**

- `SnowField.recommended_quality()` returns a recommended quality for the
  current platform.
- `SnowQualitySettings` is a Resource containing the quality, surface,
  particle, and render-option values.
- `get_quality_settings(q)` returns the selected resource values as a
  dictionary for convenience.
- `get_active_quality_settings()` returns a copy of the active quality settings.
- `has_custom_quality_settings()` reports whether the active settings differ
  from the selected built-in preset.
- `apply_quality_settings(settings)` applies values to the per-field duplicate
  of `custom_quality`, without changing built-in presets or the source resource.
  Supported keys correspond to the fields in `SnowQualitySettings`.
  Applying custom settings marks the active quality as Custom, even if the
  values happen to match a preset. Settings updates preserve existing tracks
  unless the field size or map resolution changes; mesh subdivision changes
  rebuild the mesh without clearing tracks.
- `reset_trails()` clears deformation without changing the mesh, material, or
  particle settings.
- `quality_changed(q)` is emitted when the quality changes.

Changing `quality` rebuilds the mesh and particle budgets. Existing tracks are
preserved unless the map resolution or field size changes. Changes to other
options, including mesh subdivisions, snowfall, lighting, and particle counts,
do not clear the simulation.

### SnowDeformer

Add a deformer under any object that should leave marks. Its world X/Z position
is used for the stamp. Deformers above the field's `max_depth` are ignored.

| Property | Default | Description |
|---|---:|---|
| `field` | Empty | Optional target `SnowField`. Empty means every field in the scene. |
| `stamp_mode` | `FOOTPRINT` | `BULGE_ERASER` continuously adds a temporary blue-channel mound, leaves a faint green trace, and subtracts red-channel pits. |
| `radius` | `0.4` | Print radius in meters. |
| `strength` | `1.0` | Compression strength from `0` to `1`. |
| `active` | `true` | Disables stamping when false; useful when a foot is lifted. |
| `aspect` | `1.0` | Shape ratio from `1` to `8`. `1` is round; larger values elongate along the node's forward (-Z) axis without increasing area. |
| `puff_on_touchdown` | `true` | Emits a puff when stamping starts after contact. |
| `puff_distance` | `0.0` | Also emit a puff every this many meters while moving. `0` disables distance-based puffs. |

For a boot use an aspect around `2`; for a sled runner use around `3`.
The demo mouse uses `BULGE_ERASER` and moves quickly beneath the snow, briefly
popping out now and then. Its temporary bulge erodes immediately as it moves;
the faint green trace heals with the regular snow map.

### SnowFootsteps

Add under a walking character, with the origin at ground level and the character
facing -Z. It creates and moves two alternating `SnowDeformer` nodes. Planted
feet stamp the snow; stride spacing grows with movement speed.

| Property | Default | Description |
|---|---:|---|
| `foot_radius` | `0.17` | Radius of each footprint in meters. |
| `foot_aspect` | `2.0` | Footprint shape ratio. |
| `spread` | `0.15` | Left/right distance from the character center in meters. |
| `stride_min` | `0.14` | Half-stride at a slow walk, in meters. |
| `stride_max` | `0.38` | Half-stride at full speed, in meters. |
| `speed_for_max` | `5.0` | Movement speed in m/s at which `stride_max` is reached. |

The footsteps node needs a `SnowField` in the scene. A stationary character
does not advance its stride. Airborne state is not detected, so disable the
`SnowFootsteps` node or its child deformers while airborne if prints should
pause.

### SnowFall

Standalone falling snow emitter, implemented with `CPUParticles3D`. A
`SnowField` creates its own emitters; use `SnowFall` directly when you only need
falling flakes.

| Property | Default | Description |
|---|---:|---|
| `area` | `(30, 30)` | Emitter width and depth in meters. |
| `height` | `9.0` | Emitter height above `ground_y`. |
| `ground_y` | `0.0` | World Y position of the ground beneath the emitter. |
| `fall_speed` | `(1.4, 2.2)` | Minimum and maximum downward particle speeds. |
| `flake_size` | `0.1` | Flake quad size in meters. |
| `flake_color` | White, alpha `0.9` | Particle color and opacity. |
| `follow_target` | Empty | Node to follow. If empty, uses the active camera. |
| `follow_camera` | `false` | Follow the active camera even when `follow_target` is set. |

Methods:

- `set_intensity(value)` scales the particle count from `0` to `1`; `0` stops
  emission.
- `set_max_amount(count)` sets the maximum particle count.
- `set_enabled(enabled)` enables or disables emission.
- `set_wind(Vector2(x, z))` sets horizontal drift acceleration in m/s^2.

## Customizing the snow material

Create a `ShaderMaterial`, assign `shaders/snow.gdshader`, and set it as
`SnowField.material`. Each field makes a private duplicate of the material.
Useful shader uniforms include:

| Uniform | Description |
|---|---|
| `snow_color` | Main snow color. |
| `shadow_color` | Color in compressed tracks. |
| `normal_strength` | Strength of surface shading from track details. |
| `bulge_height` | Displacement in meters at full blue-channel bulge; defaults to `0.24`. |
| `wrapped_diffuse_lighting` | Enables wrapped diffuse lighting with cool-tinted shadows; `false` uses standard diffuse lighting. |
| `bevel_noise_scale` | World-space noise frequency in cells per meter for stamp bevels. |
| `bevel_noise_strength` | Amount of noise applied to the deformation slope at stamp edges. |
| `sparkle_intensity` | Sparkle brightness; `0` disables the sparkle effect. |
| `sparkle_density` | Sparkle cells per meter. |
| `sparkle_threshold` | Specular threshold for sparkle. |
| `sparkle_fade_start`, `sparkle_fade_end` | Distance range where sparkle fades. |
| `sun_dir` | Direction toward the light; normally updated by `SnowField.sun`. |

Avoid pure-white albedo: lighting can clip the surface and make sparkle
disappear.

Wrapped diffuse lighting is enabled by default to keep steep footprint bevels
brighter on the side facing away from the light. Disable it on `SnowField` or
set the shader uniform to `false` to use standard diffuse lighting instead.
World-space value noise subtly varies the deformation slope at stamp edges,
breaking up smooth bevels without increasing deformation-map resolution. Tune
its scale and strength with `bevel_noise_scale` and `bevel_noise_strength`.

## How it works

- A hidden 2D viewport stores deformation in an 8-bit texture: red is pit depth
  (`0` untouched, `1` fully pressed), and green is berm height.
- The snow mesh shader displaces vertices from that map and derives surface
  shading from nearby samples.
- World-space noise modulates the stamp-edge slopes in the shader, keeping the
  roughened detail independent of deformation-map resolution.
- Snowfall reduces pit depth and erodes berms at configurable rates. Stochastic
  rounding lets gradual recovery progress despite the 8-bit map.
- The shader scales berm height by `1 - pit_depth`, so depressions always
  suppress overlapping rims.
- Deformation stamps are sprites. The viewport updates when the map changes,
  rather than rendering continuously.
- Flakes and puffs use CPU particles for broader Compatibility-renderer and
  Web/mobile support.

## Performance and limitations

- Start with Low quality on phones. Consider disabling MSAA and real-time
  shadows, and keep `area_size` as small as practical.
- The deformation map uses approximately 256², 512², or 1024² RGB8 texels for
  Low, Medium, and High respectively.
- `area_size` should be square. Keep the field and its parents unrotated and
  unscaled; otherwise prints may stretch or map incorrectly.
- Snow depth is not available on the CPU; reading it back would stall rendering.
  Add visual sinking separately if characters need to appear to sink.
- Device/browser behavior has not been verified across all hardware. In
  particular, persistent viewport contents and blend behavior may vary by
  device. Test on your target platforms.

## Files

- `scripts/` contains the four public nodes and internal particle helpers.
- `shaders/` contains the snow surface shader and a single two-channel map
  refill shader for pit and berm erosion.
- `icons/` contains the node icons.
- `plugin.cfg` and `plugin.gd` make the addon visible in Godot's plugin list;
  no editor integration is required for the nodes to work.

## License

MIT. See [LICENSE](LICENSE).
