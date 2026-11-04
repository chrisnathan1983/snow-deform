# Deformable Snow for Godot 4

Deformable, sparkly snow built for the **Compatibility renderer**, so it can run
in a browser (WebGL2) and on phones. Characters leave boot prints, sleds leave
runner grooves, snow piles up in berms, snowfall slowly heals the trails, and
kicked-up snow puffs fly. World-space noise breaks up smooth stamp bevels into
subtle clumpy edges. The demo also includes a fast-scurrying mouse that travels
underground while hidden, briefly popping out to leave footprints.

> **Status: pre-release (0.1.0).** It was written without access to a Godot
> runtime, so it has not been verified on a range of devices. Please test early
> on your target phones and browsers (see [Known limits](#known-limits)).

Requires **Godot 4.3 or newer**.

## Install

1. Copy either or both of `addons/deformable_surface/` and `addons/snowfall/`
   into your project's `addons/` folder. Each addon can be used independently.
2. (Optional) Enable it in *Project > Project Settings > Plugins*. The nodes
   register through `class_name`, so they work either way.

Run the project to open the demo launcher, or run `demos/launcher.tscn`
directly. The `demos/` folder contains the launcher and one folder per demo:
`classic/`, `infinite_snow/`, and `procedural_playground/`.
The infinite snow example (`demos/infinite_snow/infinite_snow.tscn`) recycles
a 3x3 grid of independent DeformableSurfaces around the player while one
SnowWorldManager supplies shared weather.
The procedural playground also has an infinite, fence-free variant at
`demos/procedural_playground/snow_demo_infinite.tscn`, with the same actors,
controls, and quality settings as the original playground.
Move with WASD, arrow keys, a gamepad stick, or the on-screen touch stick.
Jump with Space, gamepad A, or the on-screen **Jump** button. The player can
move in the air; footprints pause while airborne and resume on landing.
The demo world, DeformableSurface, player, NPC placements, and sled are
authored in `demos/classic/main.tscn`; forest layout settings are available on the Forest node.
Every demo shares one HUD (`demos/common/demo_hud.gd`) and one theme: press **Menu** (or **M**)
to open a tabbed settings panel. The standard tabs come from `demos/common/demo_settings.gd` and
apply live:

- **Surface**: Low / Medium / High / Custom quality, material preset (snow, sand, mud, dirt, ash),
  recovery, max depth, berm strength and height, puffs, wrapped lighting, reset tracks, and the
  technical settings (map resolution, mesh subdivisions, stamp budget, refill interval, puff
  budget and interval, sparkle; area size in the classic demo). Editing a technical setting
  switches the quality to **Custom** (it edits a copy, never an addon preset).
- **Weather** (demos with a SnowWorldManager): snowfall, wind, flakes, near flakes, fall height.
- **Graphics**: sun shadows and MSAA (Off, 2x, 4x), plus sun height in the playground.
- **Scene**: demo-specific controls (classic: people, mice, weather follow target; playground:
  sled, balls, yeti, penguins, snowball storm; materials: textures, triplanar, brush, vehicle).

The DeformableSurface's `quality` is a `DeformableSurfaceQuality` resource; each demo assigns
its own Low / Medium / High resources (the classic demo uses `DeformableSurfaceQuality.high()`),
and the menu's Custom entry is any edited copy. The classic demo's weather
profiles use the snowfall addon resources. Follow-target mode remains a
classic-demo setting. Shadows and MSAA are demo render options, not
quality settings.

## Quick start

1. Add a **DeformableSurface** node at ground level. Set its `size` (meters, always square).
   You'll see a flat preview in the editor.
2. Under each character add a **DeformerFootsteps** node (origin at the feet,
   character facing -Z). For anything else (sleds, boxes, wheels) add a
   **Deformer**.
3. Optionally add a **SnowWorldManager** for atmospheric flakes and set its
   `follow_target` (your player). Set the DeformableSurface's `sun` (your
   DirectionalLight3D) for sparkle. The weather manager and DeformableSurface operate
   independently.

In code:

```gdscript
var snow := DeformableSurface.new()
snow.size = 24.0
snow.quality = DeformableSurfaceQuality.for_platform()
snow.sun = $Sun
add_child(snow)

var weather := SnowWorldManager.new()
add_child(weather)

var weather_settings := SnowWeatherSettings.new()
weather_settings.flake_count = 900
weather_settings.near_flake_count = 120
weather.weather_settings = weather_settings
weather.follow_target = $Player

var d := Deformer.new()      # e.g. a sled runner
d.radius = 0.5
d.aspect = 3.0                   # long and narrow, along the node's -Z
$Sled.add_child(d)
```

## Nodes

### DeformableSurface
The snow surface. Keep it unrotated and unscaled; the surface is at its Y.

| Property | Meaning |
|---|---|
| `material` | Optional `ShaderMaterial` using `shaders/deformable_surface.gdshader` (colors, sparkle). Duplicated per field. Overrides the surface type's material. |
| `size` | Width and depth in meters (square). Smaller = sharper prints for the same quality: pixel density is `res / size`. At Medium's default 512 px over 40 m (12.8 px/m) a footprint is only a few pixels wide, so use 10-20 m or a higher `res` for crisp prints. |
| `surface_type` | Optional `DeformableSurfaceType`: what the surface is made of (see below). Presets in `resources/materials/*_profile.tres`. |
| `sun` | Optional light the sparkle follows. |
| `quality` | A `DeformableSurfaceQuality` resource (technical settings below). Use `DeformableSurfaceQuality.low()`, `medium()`, `high()` or `for_platform()`, or your own. The node keeps its own copy; assign a changed resource again to apply it. Empty = Medium. |

Technical settings live in `DeformableSurfaceQuality` (not on the node; the node copies them when assigned):

| Setting | Meaning |
|---|---|
| `res`, `subdiv` | Deformation map resolution and mesh subdivisions. |
| `max_stamps_per_frame` | Per-frame brush budget; unfinished trails resume next frame. |
| `refill_interval` | Pass rate of the trail-healing refill. |
| `puff`, `puff_min_interval` | Puff particle budget and per-deformer rate limit. |
| `sparkle` | Quality scale for the material's `sparkle_strength`. |

Material-specific settings live in `DeformableSurfaceType` (`surface_type`); without one, snow-like defaults apply:

| Setting | Meaning |
|---|---|
| `material` | Default look (`ShaderMaterial`) used when the node's `material` is empty. |
| `max_depth` | How deep fully pressed material sinks (m); deformers above this height don't stamp. |
| `berm_strength`, `berm_height` | Ridges beside prints (0 strength disables). |
| `recovery_intensity` | 0..1 (default 0.3). Controls trail healing; 0 = trails permanent. Atmospheric flakes are managed by SnowWorldManager. |
| `refill_levels_per_sec` | Packed-height recovery speed at recovery intensity 1. |
| `puffs_enabled` | Kick-up bursts. |
| `wrapped_diffuse_lighting` | Wrapped diffuse lighting on footprint bevels. |

Changing the surface type's depth or berm height clears existing trails.
Methods and signals: `reset_trails()`, `quality_changed(q)`. Changing quality rebuilds the mesh but preserves trails
unless the map resolution changes.
Editing other options (such as snowfall, lighting, or particle counts) does not
reset the simulation.
`reset_trails()` explicitly clears the map.

### Deformer
Marks the snow under its X/Z position.

| Property | Meaning |
|---|---|
| `field` | Target DeformableSurface. Empty = affects every DeformableSurface. |
| `radius`, `strength` | Size (m) and depth (0..1). |
| `active` | Manually suppress stamps, e.g. while a foot is lifted. Deformers above the DeformableSurface's `max_depth` are ignored automatically. |
| `aspect` | 1 = round; ~2 boot; ~3 sled runner. Elongated along the node's -Z. |
| `puff_on_touchdown`, `puff_distance` | Puff when contact starts / every N meters while moving. |

### DeformerFootsteps
Two alternating feet with speed-based stride; add under a character. Properties:
`foot_radius`, `foot_aspect`, optional `footprint_texture` (top facing forward,
alpha silhouette, alternately mirrored), `spread`, `stride_min`, `stride_max`,
`speed_for_max`, `active` (suppress prints, e.g. while airborne), `puff_on_touchdown`.

### SnowWorldManager
Shared atmospheric snowfall manager. Add one per world to avoid duplicating
flakes across multiple DeformableSurfaces. It owns the main and camera-relative
emitters and controls intensity, wind, height, and follow target. Assign a
`SnowWeatherSettings` resource for world-level quality settings. DeformableSurfaces
retain their own terrain recovery and deformation puffs. This node, along with
`SnowWeather`, `SnowFall`, and the weather presets, is provided by
`addons/snowfall/`; the presets are in
`res://addons/snowfall/resources/weather/`.

### SnowWeather
Legacy shared weather manager, retained for existing scenes. Use
`SnowWorldManager` for new scenes.

### SnowFall
Low-level falling-flake emitter in world space. Use SnowWorldManager for scene-wide
atmospheric snow; SnowFall also works standalone with `follow_target` (or an
empty target to follow the camera). Methods: `set_intensity(0..1)`,
`set_wind(Vector2)`, `set_max_amount(n)`, `set_enabled(bool)`.

## Customizing the look
Create a ShaderMaterial in the inspector, pick `shaders/deformable_surface.gdshader`, and assign it to
`DeformableSurface.material`. Useful uniforms: `surface_color`, `shadow_color` (compressed surface),
`normal_strength`, `sparkle_density`, `sparkle_threshold`, and
`sparkle_fade_*`.
Keep snow albedo slightly below pure white, or lighting clips to a flat sheet and
sparkles disappear.

## Performance notes
- The deformation map renders **only when something changed** (or every
  `refill_interval` while it is snowing).
- The map stores combined height in red (`0.5` is flat, lower is pressed,
  higher is bermed) and baked X/Z height gradients in green and blue.
- Stamp brushes are submitted together through one `MultiMeshInstance2D`.
- Deformers are processed only after a transform or stamp-property change;
  field-assigned deformers are isolated from unrelated DeformableSurfaces.
- Map memory: 256² / 512² / 1024² RGB8 for Low / Medium / High.
- For phones start on Low; consider MSAA off, no real shadows, and a small `size`.
- Larger worlds: use a small DeformableSurface and move it with the player in whole-texel
  steps (not implemented yet).

## Known limits
- 8-bit map: roughly 127 levels are available on either side of neutral height
  for pits and berms. Height and baked slopes recover toward neutral together.
- Snow depth can't be read back on the CPU (that would stall WebGL); fake character
  sinking visually if you need it.
- Needs a square, unrotated DeformableSurface.
- Snow particles use `CPUParticles3D` for broader Web/mobile browser reliability.
- Unverified on devices so far: persistence of the map (`CLEAR_MODE_NEVER`), the
  subtract-blend refill pass, and `amount_ratio` on mobile browsers. If trails
  flicker or vanish on a device, please open an issue.

## Layout
```
addons/deformable_surface/
  plugin.cfg, plugin.gd
  icons/              node icons
  scripts/
    deformable_surface.gd
    deformers/        Deformer, DeformerFootsteps, and SurfacePuffs
    settings/         surface and legacy quality resources
  resources/
    quality/          low, medium, high presets
  shaders/            deformable_surface.gdshader, deformable_surface_refill.gdshader,
                      deformable_surface_stamp.gdshader
addons/snowfall/
  icons/              weather node icon
  scripts/
    core/             SnowWorldManager and legacy SnowWeather
    particles/        SnowFall
    settings/         SnowWeatherSettings
    utilities/        shared particle utilities
  resources/weather/  Calm, Snowfall, and Blizzard presets
demos/
  launcher.tscn       start screen for all demos
  common/             shared demo code: DemoHud + DemoSettings + DemoTheme (one HUD), DemoNav (back-to-launcher button + Esc), TouchSticks, props, character
  materials/          material preset showcase, brush modes and vehicle tracks
  classic/            world scene, actors, and scenery
  infinite_snow/      recycled grid of independent DeformableSurfaces
  procedural_playground/ finite and infinite playground scenes
```
The demo shows: real sun shadows on High (blob shadows otherwise), MSAA by
quality, fog, a snow-dusted pine shader, MultiMesh trees.

## License
MIT. See `LICENSE`.
