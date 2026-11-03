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
The demo world, DeformableSurface, HUD instance, player, NPC placements, and sled are
authored in `demos/classic/main.tscn`; HUD controls are in
`demos/classic/ui/demo_hud.tscn`, and
forest layout settings are available on the Forest node.
Open **Options** in the demo to choose Low / Medium / High and adjust map
resolution, mesh subdivisions, sparkle, flake counts, puff particles, snowfall,
real-time shadows, MSAA (Disabled, 2x, or 4x), and wrapped diffuse lighting.
The in-game options menu uses **Surface**, **Particles**, and
**Graphics** tabs. Surface controls cover field size, depth, berms, stamp
budget, refill interval, trail refill speed, snowfall, and sparkle
intensity; particle controls cover wind, flakes, puffs, and their follow target.
Each setting has an in-menu description, and quality resources expose
collapsible groups with Inspector descriptions. Quality presets choose snow
settings; demo shadows and MSAA remain independent render options. Values can
then be adjusted independently.
Editing a setting changes the selection to
**Custom** without modifying a built-in preset, and each change applies
immediately. **Cancel**
restores the settings that were active when the menu opened; **Confirm** keeps
the changes. Escape also cancels. The rest of the HUD is hidden while the
options menu is open.
The DeformableSurface's starting quality (including Custom) is selectable in its
Inspector; the demo keeps automatic platform selection disabled. The addon
uses `DeformableSurfaceSettings` for surface profiles. The classic demo's
surface profiles use the deformable-snow addon resources, and its weather
profiles use the snowfall addon resources. Follow-target mode remains a
classic-demo setting. Shadows and MSAA are demo render options, not
quality-profile settings.

## Quick start

1. Add a **DeformableSurface** node at ground level. Set `area_size` in its quality
   profile resources (`DeformableSurfaceSettings`; always square).
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
var snow_settings := DeformableSurfaceSettings.new()
snow_settings.area_size = 24.0
var snow := DeformableSurface.new()
snow.apply_surface_quality_settings(snow_settings)   # selects the Custom profile
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
| `material` | Optional ShaderMaterial using `shaders/deformable_surface.gdshader` (colors, sparkle). Duplicated per field. |
| `sun` | Optional light the sparkle follows. |
| `quality`, `auto_quality` | Starting Low / Medium / High profile and optional platform-based override. |
| `low_surface_quality`, `medium_surface_quality`, `high_surface_quality`, `custom_surface_quality` | `DeformableSurfaceSettings` resources for the surface quality presets. |

These per-profile settings live in `DeformableSurfaceSettings` (not on the node; the node copies them at startup and on quality changes):

| Setting | Meaning |
|---|---|
| `area_size` | Size in meters (square). Smaller = sharper prints for the same quality. Pixel density is `res / area_size`: at Medium's default 512 px over 40 m (12.8 px/m) a footprint is only a few pixels wide, so use 10-20 m or a higher `res` for crisp prints. |
| `max_depth` | How deep fully pressed snow sinks (m); deformers above this height don't stamp. |
| `max_stamps_per_frame` | Per-frame brush budget; unfinished trails resume next frame. |
| `berm_strength`, `berm_height` | Ridges beside prints (0 strength disables). |
| `recovery_intensity` | 0..1 (default 0.3). Controls trail healing; 0 = trails permanent. Atmospheric flakes are managed by SnowWorldManager. |
| `refill_levels_per_sec`, `refill_interval` | Packed-height recovery speed and pass rate. |
| `puffs_enabled`, `puff_min_interval` | Kick-up snow bursts. |
| `wrapped_diffuse_lighting` | Wrapped diffuse lighting on footprint bevels. |
Methods and signals: `reset_trails()`, `DeformableSurface.recommended_quality()`,
`quality_changed(q)`. Changing quality rebuilds the mesh but preserves trails
unless the map resolution, field size, maximum depth, or berm height changes.
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
- For phones start on Low; consider MSAA off, no real shadows, and a small `area_size`.
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
    quality/          low, medium, high, custom profiles
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
  classic/            world scene, HUD, actors, and scenery
  infinite_snow/      recycled grid of independent DeformableSurfaces
  procedural_playground/ finite and infinite playground scenes
```
The demo shows: real sun shadows on High (blob shadows otherwise), MSAA by
quality, fog, a snow-dusted pine shader, MultiMesh trees.

## License
MIT. See `LICENSE`.
