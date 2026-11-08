# Deformable Snow for Godot 4

Deformable, sparkly snow built for the **Compatibility renderer**, so it can run
in a browser (WebGL2) and on phones. Characters leave boot prints, sleds leave
runner grooves, snow piles up in berms, snowfall slowly heals the trails, and
kicked-up snow puffs fly. World-space noise breaks up smooth stamp bevels into
subtle clumpy edges. The Playground also has a mouse that leaves tiny footprints as it scurries.

> **Pre-release (0.1.0).** The demos and regression checks target Godot 4.7
> with the Compatibility renderer. Mobile and browser behavior varies by device.

## Install

1. Copy either or both of `addons/deformable_surface/` and `addons/snowfall/`
   into your project's `addons/` folder. Each addon can be used independently.
2. (Optional) Enable it in *Project > Project Settings > Plugins*. The nodes
   register through `class_name`, so they work either way.

## Demos

Open `project.godot` in Godot 4.7 and run it to open the [launcher](demos/launcher.tscn).
To copy the demos into another project, copy `demos/` and both addons and select the
Compatibility renderer. Open a demo scene and press F6 to run it directly.

| Demo | What to try |
| --- | --- |
| [Powder Run](demos/ski_free.tscn) | Ski an endless slope, jump ramps, dodge obstacles, and score slalom gates alongside ten slope guests. |
| [Playground](demos/playground.tscn) | Leave footprints, push the soccer ball, throw snowballs, or explore a recycled snowfield. |
| [Material Showcase](demos/materials_demo.tscn) | Compare snow, sand, mud, dirt, and ash. Try albedo and normal textures, triplanar mapping, brush modes, and vehicle tracks. |
| [Custom Terrain & Grass](demos/custom_terrain_demo.tscn) | Deform hilly terrain and bend grass using a shared deformation map with `render_mesh` disabled. |

### Playground

WASD or arrows move, Shift runs, and Space jumps. Drag to look, click to throw a
snowball, and use the wheel to zoom. R resets tracks, and 1/2/3 select the quality tier.
On touchscreens, drag on the left to move and on the right to look. Tap to throw, and
use the **Jump** and **Run** buttons while moving.

Open **Menu → Scene → Infinite** to switch from the fenced arena to a recycled
3×3 grid. Both modes include wandering NPCs, a mouse, a soccer ball, bouncing balls,
a sled, a yeti, and a penguin parade. The Scene tab can toggle those actors and start a
snowball storm. Switching modes clears tracks and preserves actor and material settings.
**Surface → Area size** resizes the fenced arena.

Infinite mode uses smaller map presets and relocates one tile per frame. Near a tile
boundary the grid prepares the next row or column in the direction of travel. For
materials with a CPU noise resource, it prepares the next texture separately from the
active one. The default snow profile generates its starting surface on the GPU.
Tiles under the player take priority after a teleport.

Surface edits wait 120 ms after the last change, then apply to one field per frame.
The grid waits for pending edits before recycling. Brushes can overlap multiple fields,
while only the field containing the contact center emits puffs and contact signals.

### Powder Run

Steer with A/D or Left/Right, tuck with W or Down, brake with S or Up, and jump with
Space. P pauses, R starts a new run, and Esc returns to the launcher. On touchscreens,
drag the left joystick sideways to steer, push it forward to brake, and pull it back to
tuck. Tap **Jump** with another finger. Pausing or rotating the screen releases the stick.

Six skiers, two snowboarders, a sled rider, and a belly-sliding penguin carve smooth
grooves, steer around traffic, and hop rocks and ramps. The skier and guests use reusable
scenes in `demos/slope/`. Trees, rocks, ramps, and gates are scene instances. The obstacle
pool recycles through MultiMeshes, with contact blobs and matte snow in the default
mobile lighting mode.

### Settings and performance overlay

Press **M** to open the demo settings and **Esc** to return to the launcher. Material
Showcase uses the left mouse button for the brush and E for an impact stamp. Both
Material Showcase and Custom Terrain orbit with right-drag and zoom with the wheel.

- **Surface** has quality and material presets, recovery, depth, berms, puffs, lighting, and
  map, mesh, and stamp budgets. Editing technical values selects **Custom** without changing
  the preset resource.
- **Weather** has snowfall, wind, flake counts, and fall height. Increasing snowfall also
  increases track recovery in Playground.
- **Graphics** has sun shadows and MSAA. Playground also has a sun height slider.
- **Scene** has demo-specific actor, vehicle, brush, and texture controls.

Start on **Low** when testing a phone. F3 toggles the FPS graph and F4 opens a
per-operation breakdown. Changing map resolution clears tracks. For web exports,
use Compatibility and disable thread support for wider phone compatibility. Serve
the build over HTTPS or localhost.

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
| `render_mesh` | On (default): draws the built-in flat plane. Off: only the deformation map is kept, and deformers are no longer culled or weakened by their height above the node, so it works as a deformation server for hills (see "Custom terrain and foliage"). |
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

## Custom terrain and foliage
Set `render_mesh` to false, then feed your own shaders from the map. Each frame:

```gdscript
var mat: ShaderMaterial = terrain.material_override
mat.set_shader_parameter("deform_map", surface.get_deform_texture())
mat.set_shader_parameter("deform_area", surface.get_deform_area_transform())
mat.set_shader_parameter("deform_max_depth", surface.max_depth)
```

In the shader, `#include "res://addons/deformable_surface/shaders/deformable_surface.gdshaderinc"`
and use `sample_deformation_height()` in `vertex()` to displace terrain, or `sample_deformation()`
(height, pit depth, slope) to blend color, roughness and normals. The slope points away from the
middle of a footprint, so grass shaders can also use it as a bend direction.

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
- For larger worlds, see the demo-side [tile grid](demos/shared/deformable_surface_grid.gd).
  It reuses fields around a follow target and clears their tracks when moving them.

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
    deformers/        footprint, track, and particle deformers
    deformable_surface_type.gd
    deformable_surface_quality.gd
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
  playground.tscn     fenced arena and infinite snowfields
  ski_free.tscn       Powder Run arcade skiing demo
  materials_demo.tscn material preset showcase
  custom_terrain_demo.tscn hilly terrain and grass driven by the deformation map
  scripts/           demo controllers, actors, HUD, and settings
  shared/            shared shell, brush, and tile grid
  shaders/           terrain, grass, tree snow, and soccer ball shaders
  characters/        explorer, penguin, yeti, NPC, and mouse sub-scenes
  props/             balls, trees, rocks, sleds, and snowman sub-scenes
  resources/         demo-specific surface and quality presets
  slope/             Powder Run skier and guest scenes
```
## Regression checks

Run an individual check from the repository root after Godot has imported the project.

```sh
godot --headless --editor --path . --import
godot --headless --path . --script tests/playground_modes.gd
godot --headless --path . --script tests/initial_noise_seams.gd
godot --headless --path . --script tests/ski_free_gameplay.gd
```

| Scripts in `tests/` | Coverage |
| --- | --- |
| `playground_modes.gd` | Launcher, actor toggles, arena sizing, and pending settings across mode changes. |
| `initial_noise_seams.gd` | CPU height and normal seams, cache keys, and prepared textures. Run with rendering to compare texture bytes as well. |
| `infinite_snow_prefetch.gd`, `infinite_snow_recycling.gd`, `surface_settings_updates.gd` | Grid recycling, prefetch priority, direction reversal, and concurrent settings edits. |
| `deformer_tile_edges.gd`, `track_profiles.gd` | Cross-tile stamps, contact ownership, smooth grooves, and tread tracks. |
| `ski_free_gameplay.gd` | Touch input, layout, gates, jumps, recycling, and guest tracks. Run with rendering to check MultiMesh transforms. |

Run `infinite_snow_frame_times.gd` with or without `--headless` for frame pacing
through movement, tile crossings, and settings changes. It caps the frame rate
at 120 and writes `.godot/infinite-frame-times.json`. For Powder Run profiling
with rendering, see [the performance notes](tests/SKI_PERFORMANCE.md).

## License
MIT. See `LICENSE`.
