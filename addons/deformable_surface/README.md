# Deformable Surface

Deformable, sparkly surfaces for Godot 4. The surface responds to footprints and other
deformers, builds small berms beside tracks, gradually heals tracks over time,
and can emit puffs from surface contact.

The addon is designed for the **Compatibility renderer** (WebGL2 and mobile
friendly) and requires **Godot 4.3 or newer**.

## Installation

1. Copy `deformable_surface` into your project's `res://addons/` directory. Keep
   the folder name; scripts and node icons reference it.
2. The addon appears in *Project > Project Settings > Plugins*. Enabling it is
   optional: the nodes register using `class_name` and are available without
   enabling the plugin.
3. Add a `DeformableSurface` node to your scene, then add deformers to the objects that
   should leave tracks.

## Quick start

1. Add a `DeformableSurface` at ground level. Set its `size` (meters) to cover
   the area where tracks should appear. It is always square.
2. Add a `DeformerFootsteps` under each walking character, with its origin at the
   feet and the character facing -Z. For sleds, wheels, or other objects, add
   one or more `Deformer` nodes instead.
3. Optionally set the field's `sun` to the scene's `DirectionalLight3D`.

The editor displays a flat preview of the field. A minimal runtime setup:

```gdscript
var quality := DeformableSurfaceQuality.new()
quality.res = 512
quality.subdiv = 127
var surface := DeformableSurface.new()
surface.size = 24.0
surface.quality = quality   # or DeformableSurfaceQuality.for_platform()
surface.sun = $Sun
add_child(surface)

var runner := Deformer.new()
runner.radius = 0.5
runner.aspect = 3.0
$Sled.add_child(runner)
```

## Nodes

### DeformableSurface

The surface and controller for deformation, track recovery, and puffs. Keep the
field and its parents unrotated and unscaled. The surface is at the field's Y
position; the field is always square (`size` is a single float on the node).

| Property | Default | Description |
|---|---:|---|
| `material` | Empty | Optional `ShaderMaterial` using `shaders/deformable_surface.gdshader`. Each field duplicates the material. Overrides the surface type's material. |
| `size` | `40.0` | Width and depth in meters. Smaller areas give sharper prints at the same quality (density is `res / size`). Changing it at runtime rebuilds the mesh and clears tracks. |
| `surface_type` | Empty | Optional `DeformableSurfaceType` describing what the surface is made of: depth, berms, recovery, puffs, lighting, default material. Ready-made `snow`, `sand`, `mud`, `dirt` and `ash` profiles are in `resources/materials/`. Without one, snow-like defaults apply. |
| `sun` | Empty | Optional directional light that controls sparkle direction. |
| `quality` | Medium | A `DeformableSurfaceQuality` resource: resolution, mesh density and budgets. Use `DeformableSurfaceQuality.low()`, `medium()`, `high()` or `for_platform()`, or your own saved resource. The node listens to resource changes; duplicate shared presets before editing one surface. Changes preserve tracks unless the map resolution changes. |

The following technical settings live in `DeformableSurfaceQuality` and update the surface when changed.

| Setting | Default | Description |
|---|---:|---|
| `res`, `subdiv` | `512`, `127` | Deformation map resolution and mesh subdivisions. |
| `max_stamps_per_frame` | `64` | Maximum deformation stamps drawn per frame. Unfinished tracks continue on later frames. |
| `refill_interval` | `0.25` | Seconds between track-healing passes. |
| `puff`, `puff_min_interval` | `8`, `0.2` | Puff particle budget and minimum seconds between puffs from one deformer. |
| `sparkle` | `1.0` | Quality scale applied on top of the material's `sparkle_strength`. |

The following material settings live in a `DeformableSurfaceType` (`surface_type`). Without one, these defaults apply. The node listens to profile changes; duplicate a shared type before editing one surface. The node exposes `max_depth` (read-only) and `recovery_intensity` and `wrapped_diffuse_lighting` (assignable at runtime); replacing the surface type uses the new profile's values.

| Setting | Default | Description |
|---|---:|---|
| `type_name` | `snow` | Label reported by the `contact` signal (for example footstep audio). |
| `material` | Empty | Default `ShaderMaterial` used when the node's `material` is empty. |
| `max_depth` | `0.4` | Sink depth in meters at full compression (range 0.01 to 1). Deformers above this height are ignored. |
| `berm_strength` | `0.15` | Strength of ridges beside tracks; set to `0` to disable berms. |
| `berm_height` | `0.08` | Maximum berm height in meters. |
| `recovery_intensity` | `0.3` | Surface recovery intensity from `0` to `1`; `0` stops trail healing. |
| `refill_levels_per_sec` | `16.0` | Packed-height recovery speed at recovery intensity `1`. Height and slopes recover together. |
| `puffs_enabled` | `true` | Enables kicked-up puffs from deformers. |
| `puff_texture` | Empty | Particle texture; empty is a soft round dot. |
| `puff_color_ramp` | Empty | Puff color over its lifetime; empty is the surface color fading out. |
| `puff_velocity_min`, `puff_velocity_max` | `0.6`, `1.4` | Puff launch speed range in m/s. |
| `wrapped_diffuse_lighting` | `true` | Adds a cool tint to the material's shadow color; diffuse and specular lighting use Godot's built-in model. |
| `initial_noise_enabled` | `true` | Starts with a procedural bumpy surface instead of a flat one; recovery heals back to it. |
| `initial_noise` | Empty | Optional `FastNoiseLite`. Empty uses Cellular noise with Euclidean Squared distance, Distance return, jitter `0.9`, and no fractal. Each profile is baked to shared seamless noise textures and sampled in world space. The sand, mud, dirt and ash profiles each ship their own noise. |
| `initial_noise_invert` | `false` | Inverts the pattern to create mounds instead of dimples. |
| `initial_noise_frequency` | `0.8` | Built-in cellular feature scale when `initial_noise` is empty; lower values create larger dimples. |
| `initial_noise_height` | `0.2` | Maximum starting height variation in meters (up to 0.5), covering the base noise and its second octave. |
| `initial_noise_detail` | `0.6` | Second octave: the same noise again, with its own seed, weighted against the main noise (`0` = off). Total height still peaks at `initial_noise_height`. |
| `initial_noise_detail_scale` | `0.25` | Frequency multiplier of the second octave (0.1 to 8). Below `1` makes broad hills; above `1` adds fine grain. |
| `initial_noise_mound_height` | `0.3` | Height in meters of raised piles and dunes (`0` = none). The noise multiplies the surface level, so mounds carry proportionally stronger texture. Capped by `max_depth`. Digging into a mound goes deeper than on flat ground. |
| `initial_noise_mound_frequency` | `0.1` | Mound size: lower values make larger, more widely spaced dunes (0.02 to 1). |

The ready-made profiles override depth and starting height: snow `0.5` / `0.25` (max depth / noise height) with `0.4` mounds, mud `0.35` / `0.08` / `0.1`, ash `0.3` / `0.1` / `0.2`, sand `0.2` / `0.1` / `0.18`, dirt `0.1` / `0.025` / `0.04`.

**Print size vs. resolution:** the map is `res` pixels across `size` meters. At the default
Medium profile (512 px over 40 m, about 12.8 px/m) a footprint is only a few pixels wide, and
Low (256 px) is about half that. For crisp prints, lower `size` to what the player can
actually reach (for example 10-20 m) or raise `res`; pixel density is `res / size`.

The starting surface is part of the surface type. To get distinct dropped-sphere dimples (the snow look), keep `initial_noise_enabled` on (the default) and leave `initial_noise` empty; the default
pattern uses cellular Euclidean Squared distance with Distance return, jitter `0.9`,
frequency `0.8`, and `0.2` m height variation. A second octave of the same noise (a
low `initial_noise_detail_scale` gives broad hills, a high one fine grain) is layered on
top, and `initial_noise_mound_height` adds raised piles or dunes with flat ground between
them. Toggle `initial_noise_invert` for
mounds. Assign a `FastNoiseLite` resource to `initial_noise` to customize it. For
smaller dimples nested inside larger ones, use FBM with two octaves. Height gradients
are calculated into the deformation map and used for normal lighting; no separate
normal-map texture is needed. Recovery restores deformed areas toward this
starting pattern, keeping the dimples while tracks gradually refill.

#### Quality resources

`DeformableSurfaceQuality` contains technical per-surface settings: map resolution, mesh
subdivisions, stamp and puff budgets, refill cadence, and the sparkle quality scale.
`DeformableSurfaceType` contains what the surface is made of: depth, berms,
recovery, puffs, lighting and the default material.

The Low, Medium and High presets are resources in `resources/quality/`, also available as
`DeformableSurfaceQuality.low()`, `medium()` and `high()` (each returns a fresh copy), with
`for_platform()` picking one for the current device (`platform_tier()` returns 0, 1 or 2).
There is no Custom preset: any `DeformableSurfaceQuality` you create is a custom quality. A
settings menu edits a duplicate and assigns it to `quality`. Node references such as `material`
and `sun` remain scene settings rather than menu values.
Pits, berms, and their baked slopes recover together; recovery does not change
berm height or the puff rate.

**Methods and signal**

- `quality_changed(q)` is emitted (with the node's copy of the quality) when the quality changes.
- `reset_trails()` clears deformation without changing the mesh, material, or
  particle settings.
- `get_stamps_used()` returns the stamps drawn this frame, for performance readouts.
- `get_frame_costs()` returns this frame's cost per operation (`deformers_ms`, `queued_ms`,
  `puffs_ms`, `stamp_mpx`, `refill_mpx`, `mesh_kverts`). CPU values are milliseconds; the GPU
  values are estimates in millions of map pixels shaded, not timings.
- `stamp_segment(from, to, width, strength, shape, mode, phase)` draws one continuous strip
  of track between two world positions; `DeformerTracks` uses it.
- `stamp_at(world_pos, radius = 0.5, strength = 1.0, shape = null, mode = StampMode.CARVE, heading = 0.0, aspect = 1.0, puff = false, silent = false)`
  applies a one-shot stamp (explosions, falling objects, projectile impacts) with no
  persistent `Deformer`. `shape` is an optional alpha-mask `Texture2D`. Stamps are queued
  and respect `max_stamps_per_frame`; positions outside the field are ignored.
- `StampMode`: `CARVE` presses down, `RAISE` piles up (snow accumulation, digging
  spoil; height is capped at about `max_depth`), `SMOOTH` levels toward flat (a snow plow / erase).
- `contact(position, depth, type_name, source, radius, puff)` is emitted when a `Deformer` touches
  down (each footfall) or a `stamp_at` lands. Use it for footstep audio and gameplay.
  `depth` is the nominal signed depth in meters (positive = pressed down, negative = raised,
  `0` = smoothed), `type_name` is the surface type's `type_name` (`snow`, `sand`,
  `mud`, `dirt`, `ash` for the presets, or your own), and `source` is the `Deformer`
  (`null` for `stamp_at`); `radius` is the stamp radius in meters. `puff` says whether this contact wants a puff; the surface's own puff emitter is just a listener on this signal. Continuous trail stamps while moving don't re-emit.

Changing `quality` rebuilds the surface mesh and stamp/puff budgets. Existing tracks are
preserved unless the map resolution or field size changes. Changes to other
options, including mesh subdivisions, recovery intensity, lighting, and particle counts,
do not clear the simulation.

### Deformer

Add a deformer under any object that should leave marks. Its world X/Z position
is used for the stamp. Deformers above the field's `max_depth` are ignored.

| Property | Default | Description |
|---|---:|---|
| `field` | Empty | Optional target `DeformableSurface`. Empty means every field in the scene. |
| `radius` | `0.4` | Print radius in meters. |
| `strength` | `1.0` | Compression strength from `0` to `1`. |
| `active` | `true` | Disables stamping when false; useful when a foot is lifted. |
| `aspect` | `1.0` | Shape ratio from `1` to `8`. `1` is round; larger values elongate along the node's forward (-Z) axis without increasing area. |
| `mode` | `CARVE` | `DeformableSurface.StampMode`: `CARVE`, `RAISE` or `SMOOTH`. A `SMOOTH` deformer works as a plow. |
| `puff_on_touchdown` | `true` | Emits a puff when stamping starts after contact. |
| `puff_distance` | `0.0` | Also emit a puff every this many meters while moving. `0` disables distance-based puffs. |

For a boot use an aspect around `2`; for a sled runner use around `3`.
A moving round, untextured deformer draws one continuous capsule-shaped stroke per
frame (up to 20 radii of travel) so the trail has no gaps at speed; textured or elongated
deformers stamp every half radius instead. The per-frame `max_stamps_per_frame` budget
can end a long trail early, and it continues on later frames.
The demo mouse moves underground while hidden and disables its deformer; when it
pops out, it leaves footprints.

### DeformerFootsteps

Add under a walking character, with the origin at ground level and the character
facing -Z. It creates and moves two alternating `Deformer` nodes. Planted
feet stamp the surface; stride spacing grows with movement speed.

| Property | Default | Description |
|---|---:|---|
| `foot_radius` | `0.17` | Radius of each footprint in meters. |
| `foot_aspect` | `2.0` | Footprint shape ratio. |
| `footprint_texture` | Empty | Optional texture with its top facing forward; its alpha defines the print silhouette, scaled to `foot_radius` and `foot_aspect`. Left and right prints are mirrored automatically. |
| `spread` | `0.15` | Left/right distance from the character center in meters. |
| `stride_min` | `0.14` | Half-stride at a slow walk, in meters. |
| `stride_max` | `0.38` | Half-stride at full speed, in meters. |
| `speed_for_max` | `5.0` | Movement speed in m/s at which `stride_max` is reached. |
| `active` | `true` | Set to `false` to suppress prints, for example while airborne. |
| `puff_on_touchdown` | `true` | Emits a puff each time a foot lands. |

The footsteps node needs a `DeformableSurface` in the scene. A stationary character
does not advance its stride. Airborne state is not detected, so disable the
`DeformerFootsteps` node or its child deformers while airborne if prints should
pause.

### DeformerTracks

Lays tread tracks behind wheels or tracked belts. Add under a vehicle with its origin at
ground level, facing -Z. Each wheel draws one unbroken ribbon (through `stamp_segment`)
along its own path, so front and rear wheels trace separate arcs in a turn. The tread
texture is laid by distance travelled, so the pattern stays continuous at any speed or
frame rate. Tracks don't emit `contact` or puffs.

| Property | Default | Description |
|---|---:|---|
| `preset` | `CAR` | `CAR` (4 wheels), `TRUCK` (6, three axles), `MOTORCYCLE` (2 on the centerline), `TRACKED` (one belt per side) or `CUSTOM` (uses `wheel_offsets`). |
| `track_gauge` | `1.6` | Left/right wheel distance in meters. |
| `wheelbase` | `2.6` | Front-to-rear axle distance in meters. |
| `wheel_offsets` | 4 wheels | `CUSTOM` only: contact points as (x = right, y = local Z) in meters. |
| `wheel_width` | `0.3` | Width of each track in meters (use ~0.7 for `TRACKED`). |
| `tread_texture` | Built-in chevron | Alpha-mask tread pattern; its top edge faces the direction of travel. One tile spans the track width and is as long as the texture's height/width ratio implies. |
| `profile` | `TREAD` | `TREAD` retains patterned vehicle ribbons. `SMOOTH` ignores the texture and uses rounded analytical grooves for skis, boards, and sled runners; all smooth tracks share the untextured stamp batch. |
| `strength`, `mode`, `active`, `field` | `0.8`, `CARVE`, `true`, empty | As for `Deformer`. |

Wheels that are above the field's `max_depth` leave no print. Call `reset_path()` after
teleporting the vehicle.

## Customizing the surface material

Create a `ShaderMaterial`, assign `shaders/deformable_surface.gdshader`, and set it as
`DeformableSurface.material`. Each field makes a private duplicate of the material.
Useful shader uniforms include:

| Uniform | Description |
|---|---|
| `surface_color` | Main surface color. |
| `shadow_color` | Color in compressed tracks. |
| `normal_strength` | Strength of surface shading from track details. |
| `wrapped_diffuse_lighting` | Adds a cool tint to the shadow color, guided by `sun_dir`; `false` disables the tint. |
| `bevel_noise_scale` | World-space noise frequency in cells per meter for stamp bevels. |
| `bevel_noise_strength` | Amount of noise applied to the deformation slope at stamp edges. |
| `sparkle_intensity` | Sparkle brightness; `0` disables the sparkle effect. |
| `sparkle_density` | Sparkle cells per meter. |
| `sparkle_threshold` | Specular threshold for sparkle. |
| `sparkle_fade_start`, `sparkle_fade_end` | Distance range where sparkle fades. |
| `sun_dir` | Direction toward the light; normally updated by `DeformableSurface.sun`. |

Avoid pure-white albedo: lighting can clip the surface and make sparkle
disappear.

The cool shadow tint is enabled by default and follows `sun_dir`. Godot's built-in
diffuse and specular lighting handle the actual light response.
World-space value noise subtly varies the deformation slope at stamp edges,
breaking up smooth bevels without increasing deformation-map resolution. Tune
its scale and strength with `bevel_noise_scale` and `bevel_noise_strength`.

## How it works

- A hidden 2D viewport stores deformation in an 8-bit texture: red stores
  combined height (`0.5` flat, lower for pits, higher for berms); green and blue
  store baked X/Z height gradients.
- The vertex shader samples height for displacement. The fragment shader reads
  packed height and gradients in one deformation-map texture lookup.
- World-space noise modulates baked stamp-edge slopes in the shader, keeping the
  roughened detail independent of deformation-map resolution.
- Trail recovery moves combined height and baked gradients toward their neutral
  values at the same rate.
- Deformation stamps bake height and its slopes into the map. A single
  `MultiMeshInstance2D` batches the brushes; the viewport updates when the map
  changes, rather than rendering continuously.
- Deformers notify their assigned field when their transform or stamp properties
  change, so stationary objects do not need per-frame deformation calculations.
  Unassigned deformers are shared across DeformableSurfaces.
- Puffs use CPU particles for broad Compatibility-renderer and Web/mobile
  support.

## Performance and limitations

- Start with Low quality on phones. Consider disabling MSAA and real-time
  shadows, and keep `size` as small as practical.
- The deformation map uses approximately 256², 512², or 1024² RGB8 texels for
  Low, Medium, and High respectively.
- The field is always square (`size`). Keep the field and its parents unrotated and
  unscaled; otherwise prints may stretch or map incorrectly.
- Surface depth is not available on the CPU; reading it back would stall rendering.
  Add visual sinking separately if characters need to appear to sink.
- Device/browser behavior has not been verified across all hardware. In
  particular, persistent viewport contents and blend behavior may vary by
  device. Test on your target platforms.

## Files

- `scripts/deformable_surface.gd` defines `DeformableSurface`.
- `scripts/deformers/deformer.gd` defines `Deformer`.
- `scripts/deformers/deformer_footsteps.gd` defines `DeformerFootsteps`.
- `scripts/deformers/deformer_tracks.gd` defines `DeformerTracks`.
- `scripts/deformers/deformer_particles.gd` contains the per-field surface-puff pool.
- `scripts/deformable_surface_quality.gd` defines `DeformableSurfaceQuality`.
- `scripts/deformable_surface_type.gd` defines `DeformableSurfaceType`.
- `resources/quality/` contains the Low, Medium and High quality presets.
- `resources/materials/` contains the snow, sand, mud, dirt and ash surface types and their materials.
- `shaders/` contains the surface, additive/subtractive stamp, and map
  refill shaders.
- `icons/` contains the node icons.
- `plugin.cfg` and `plugin.gd` make the addon visible in Godot's plugin list;
  no editor integration is required for the nodes to work.

## License

MIT. See [LICENSE](LICENSE).
