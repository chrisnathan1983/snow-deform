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

1. Copy `addons/deformable_snow/` into your project's `addons/` folder.
   Keep the folder name, because the node icons use that path.
2. (Optional) Enable it in *Project > Project Settings > Plugins*. The nodes
   register through `class_name`, so they work either way.

To see it first, open this folder as a project and run `demo/main.tscn`.
Move with WASD, arrow keys, a gamepad stick, or the on-screen touch stick.
Jump with Space, gamepad A, or the on-screen **Jump** button. The player can
move in the air; footprints pause while airborne and resume on landing.
The demo world, SnowField, HUD instance, player, NPC placements, and sled are
authored in `demo/main.tscn`; HUD controls are in `demo/ui/demo_hud.tscn`, and
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
The SnowField's starting quality (including Custom) is selectable in its
Inspector; the demo keeps automatic platform selection disabled. Low, Medium,
High, and Custom profiles are editable `SnowQualitySettings` resources and
include snow options such as snowfall and wrapped diffuse lighting. Shadows
and MSAA are demo render options, not quality-profile settings.

## Quick start

1. Add a **SnowField** node at ground level. Set `area_size` (it must be square).
   You'll see a flat preview in the editor.
2. Under each character add a **SnowFootsteps** node (origin at the feet,
   character facing -Z). For anything else (sleds, boxes, wheels) add a
   **SnowDeformer**.
3. Add one **SnowWeather** node to the scene and set its `follow_target` (your
   player). Set the SnowField's `sun` (your DirectionalLight3D) for sparkle.
   The weather node owns shared snowfall; each SnowField handles its own terrain.

In code:

```gdscript
var snow := SnowField.new()
snow.area_size = Vector2(24, 24)
snow.quality = SnowField.recommended_quality()   # Low on phones, High on desktop
snow.sun = $Sun
add_child(snow)

var weather := SnowWeather.new()
weather.follow_target = $Player
add_child(weather)
weather.apply_quality_settings(snow.get_active_quality_settings(), snow.snowfall)

var d := SnowDeformer.new()      # e.g. a sled runner
d.radius = 0.5
d.aspect = 3.0                   # long and narrow, along the node's -Z
$Sled.add_child(d)
```

## Nodes

### SnowField
The snow surface. Keep it unrotated and unscaled; the surface is at its Y.

| Property | Meaning |
|---|---|
| `area_size` | Size in meters (square). Smaller = sharper prints for the same quality. |
| `material` | Optional ShaderMaterial using `shaders/snow.gdshader` (colors, sparkle). Duplicated per field. |
| `sun` | Optional light the sparkle follows. |
| `max_depth` | How deep fully pressed snow sinks (m); deformers above this height don't stamp. |
| `quality`, `auto_quality` | Starting Low / Medium / High profile and optional platform-based override. |
| `low_quality`, `medium_quality`, `high_quality`, `custom_quality` | Editable `SnowQualitySettings` resources for each profile. |
| `max_stamps_per_frame` | Per-frame brush budget; unfinished trails resume next frame. |
| `berm_strength`, `berm_height` | Ridges beside prints (0 strength disables). |
| `snowfall` | 0..1. Controls this field's trail healing; 0 = trails permanent. Atmospheric flakes are managed by SnowWeather. |
| `refill_levels_per_sec`, `refill_interval` | Packed-height recovery speed and pass rate. |
| `puffs_enabled`, `puff_min_interval` | Kick-up snow bursts. |

Methods and signals: `reset_trails()`, `SnowField.recommended_quality()`,
`quality_changed(q)`. Changing quality rebuilds the mesh but preserves trails
unless the map resolution, field size, maximum depth, or berm height changes.
Editing other options (such as snowfall, lighting, or particle counts) does not
reset the simulation.
`reset_trails()` explicitly clears the map.

### SnowDeformer
Marks the snow under its X/Z position.

| Property | Meaning |
|---|---|
| `field` | Target SnowField. Empty = affects every SnowField. |
| `radius`, `strength` | Size (m) and depth (0..1). |
| `active` | Manually suppress stamps, e.g. while a foot is lifted. Deformers above the SnowField's `max_depth` are ignored automatically. |
| `aspect` | 1 = round; ~2 boot; ~3 sled runner. Elongated along the node's -Z. |
| `puff_on_touchdown`, `puff_distance` | Puff when contact starts / every N meters while moving. |

### SnowFootsteps
Two alternating feet with speed-based stride; add under a character. Properties:
`foot_radius`, `foot_aspect`, `spread`, `stride_min`, `stride_max`, `speed_for_max`.

### SnowWeather
Shared atmospheric snowfall manager. Add one per scene to avoid duplicating
flakes across multiple SnowFields. It owns the main emitter and camera-relative
near flakes, and controls their intensity, wind, height, and follow target.
The demo applies its active quality profile to this node. SnowFields retain
their own terrain recovery and deformation puffs.

### SnowFall
Low-level falling-flake emitter in world space. Use SnowWeather for scene-wide
atmospheric snow; SnowFall also works standalone with `follow_target` (or an
empty target to follow the camera). Methods: `set_intensity(0..1)`,
`set_wind(Vector2)`, `set_max_amount(n)`, `set_enabled(bool)`.

## Customizing the look
Create a ShaderMaterial in the inspector, pick `shaders/snow.gdshader`, and assign it to
`SnowField.material`. Useful uniforms: `snow_color`, `shadow_color` (compressed snow),
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
  field-assigned deformers are isolated from unrelated SnowFields.
- Map memory: 256² / 512² / 1024² RGB8 for Low / Medium / High.
- For phones start on Low; consider MSAA off, no real shadows, and a small `area_size`.
- Larger worlds: use a small SnowField and move it with the player in whole-texel
  steps (not implemented yet).

## Known limits
- 8-bit map: roughly 127 levels are available on either side of neutral height
  for pits and berms. Height and baked slopes recover toward neutral together.
- Snow depth can't be read back on the CPU (that would stall WebGL); fake character
  sinking visually if you need it.
- Needs a square, unrotated SnowField.
- Snow particles use `CPUParticles3D` for broader Web/mobile browser reliability.
- Unverified on devices so far: persistence of the map (`CLEAR_MODE_NEVER`), the
  subtract-blend refill pass, and `amount_ratio` on mobile browsers. If trails
  flicker or vanish on a device, please open an issue.

## Layout
```
addons/deformable_snow/
  plugin.cfg, plugin.gd
  icons/              node icons
  scripts/            SnowField, SnowDeformer, SnowFootsteps, SnowFall (+ internal puffs/util)
  shaders/            snow.gdshader, snow_refill.gdshader
demo/                 playable demo; main.tscn contains the world, SnowField,
                      HUD, actors, and sled; reusable components are separate scenes
```
The demo shows: real sun shadows on High (blob shadows otherwise), MSAA by
quality, fog, a snow-dusted pine shader, MultiMesh trees.

## License
MIT. See `LICENSE`.
