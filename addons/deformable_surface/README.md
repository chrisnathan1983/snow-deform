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

1. Add a `DeformableSurface` at ground level. Set `area_size` in the Low/Medium/High/Custom
   quality profile resources (`DeformableSurfaceSettings`) to a size that covers
   the area where tracks should appear. It is always square.
2. Add a `DeformerFootsteps` under each walking character, with its origin at the
   feet and the character facing -Z. For sleds, wheels, or other objects, add
   one or more `Deformer` nodes instead.
3. Optionally set the field's `sun` to the scene's `DirectionalLight3D`.

The editor displays a flat preview of the field. A minimal runtime setup:

```gdscript
var settings := DeformableSurfaceSettings.new()
settings.area_size = 24.0
settings.res = 512
settings.subdiv = 127
var surface := DeformableSurface.new()
surface.apply_surface_quality_settings(settings)   # selects the Custom profile
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
position; the field is always square (`area_size` is a single float in the profile).

| Property | Default | Description |
|---|---:|---|
| `material` | Empty | Optional `ShaderMaterial` using `shaders/deformable_surface.gdshader`. Each field duplicates the material. |
| `sun` | Empty | Optional directional light that controls sparkle direction. |
| `initial_noise_enabled` | `true` | Starts with a procedural bumpy surface instead of a flat one. |
| `initial_noise` | Empty | Optional `FastNoiseLite` override. When empty, uses Cellular noise with Euclidean Squared distance, Distance return, jitter `0.9`, and no fractal. |
| `initial_noise_invert` | `false` | Inverts the generated pattern to create mounds instead of dimples. |
| `initial_noise_frequency` | `0.8` | Built-in cellular feature scale; lower values create larger dimples. |
| `initial_noise_height` | `0.15` | Maximum starting height variation in meters. |
| `quality` | Medium | Starting quality profile. Choose Low, Medium, High, or Custom. Quality changes preserve tracks unless map resolution, field size, maximum depth, or berm height changes. |
| `low_surface_quality`, `medium_surface_quality`, `high_surface_quality`, `custom_surface_quality` | Quality resources | Editable `DeformableSurfaceSettings` profiles used by each quality level. Each node starts with its own copy of the addon presets, so Inspector edits don't change the addon's `.tres` files; assign your own saved resource to share one across nodes. Each DeformableSurface also duplicates the selected profile at runtime. |
| `auto_quality` | `false` | Selects Low on mobile, Medium on desktop browsers, and High elsewhere at startup. Overrides `quality`. |

The following settings live in the `DeformableSurfaceSettings` profile for the active quality level; the runtime node copies them at startup and on quality changes, so set them in the profile resources (or via `apply_surface_quality_settings()`), not on the node. `recovery_intensity` may still be assigned on the node at runtime, but the next quality change restores the profile's value.

| Setting | Default | Description |
|---|---:|---|
| `area_size` | `40.0` | Width and depth in meters. Smaller areas give sharper prints at the same quality. The options menu edits this as a square field size. |
| `wrapped_diffuse_lighting` | `true` | Enables wrapped diffuse lighting with cool-tinted shadows on footprint bevels; disable to use standard diffuse lighting. |
| `max_depth` | `0.25` | Sink depth in meters at full compression. Deformers above this height are ignored. |
| `max_stamps_per_frame` | `64` | Maximum deformation stamps drawn per frame. Unfinished tracks continue on later frames. |
| `berm_strength` | `0.15` | Strength of ridges beside tracks; set to `0` to disable berms. |
| `berm_height` | `0.08` | Maximum berm height in meters. |
| `recovery_intensity` | `0.3` | Surface recovery intensity from `0` to `1`; `0` stops trail healing. |
| `refill_levels_per_sec` | `16.0` | Packed-height recovery speed at recovery intensity `1`. Height and slopes recover together. |
| `refill_interval` | `0.25` | Seconds between track-healing passes. |
| `puffs_enabled` | `true` | Enables kicked-up puffs from deformers. |
| `puff_min_interval` | `0.2` | Minimum seconds between puffs from one deformer. |

**Print size vs. resolution:** the map is `res` pixels across `area_size` meters. At the default
Medium profile (512 px over 40 m, about 12.8 px/m) a footprint is only a few pixels wide, and
Low (256 px) is about half that. For crisp prints, lower `area_size` to what the player can
actually reach (for example 10-20 m) or raise `res`; pixel density is `res / area_size`.

To get distinct dropped-sphere dimples, keep `initial_noise_enabled` on (the default); the default
pattern uses cellular Euclidean Squared distance with Distance return, jitter `0.9`,
frequency `0.8`, and `0.15` m height variation. Toggle `initial_noise_invert` for
mounds. Assign a `FastNoiseLite` resource to `initial_noise` to customize it. For
smaller dimples nested inside larger ones, use FBM with two octaves. Height gradients
are calculated into the deformation map and used for normal lighting; no separate
normal-map texture is needed. Recovery restores deformed areas toward this
starting pattern, keeping the dimples while tracks gradually refill.

#### Quality resources

`DeformableSurfaceSettings` contains per-surface settings: map resolution, mesh
subdivisions, depth and berms, stamp budget, recovery, sparkle, puff budget, and
wrapped lighting.

The classic demo uses the `DeformableSurfaceSettings` resources here together
with weather presets from the weather addon. The surface addon uses only
`DeformableSurfaceSettings` for surface profiles.

The existing Low, Medium, High, and Custom resources are in
`resources/quality/`; assign or edit these profiles on DeformableSurface in the
Inspector. Node references such as `material` and `sun`, and startup-only
`auto_quality`, remain scene settings rather than menu values.
Pits, berms, and their baked slopes recover together; recovery does not change
berm height or the puff rate.

**Methods and signal**

- `DeformableSurface.recommended_quality()` returns a recommended quality for the
  current platform.
- `DeformableSurfaceSettings` contains surface settings.
- `get_quality_settings(q)` returns the selected surface resource as a dictionary.
- `get_surface_quality_settings(q)` returns a copy of the selected surface
  resource; `apply_surface_quality_settings(settings)` applies surface-only
  settings as the Custom quality.
- `get_active_quality_settings()` returns a copy of the active quality settings.
- `has_custom_quality_settings()` reports whether the active settings differ
  from the selected built-in preset.
- `apply_quality_settings(settings)` applies values to the per-field duplicate
  of the custom surface profile, without changing built-in presets or the
  source resource. It accepts surface settings from a dictionary.
  Applying custom settings marks the active quality as Custom, even if the
  values happen to match a preset. Settings updates preserve existing tracks
  unless the field size, map resolution, maximum depth, or berm height changes;
  mesh subdivision changes rebuild the mesh without clearing tracks.
- `reset_trails()` clears deformation without changing the mesh, material, or
  particle settings.
- `quality_changed(q)` is emitted when the quality changes.

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
| `puff_on_touchdown` | `true` | Emits a puff when stamping starts after contact. |
| `puff_distance` | `0.0` | Also emit a puff every this many meters while moving. `0` disables distance-based puffs. |

For a boot use an aspect around `2`; for a sled runner use around `3`.
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

## Customizing the surface material

Create a `ShaderMaterial`, assign `shaders/deformable_surface.gdshader`, and set it as
`DeformableSurface.material`. Each field makes a private duplicate of the material.
Useful shader uniforms include:

| Uniform | Description |
|---|---|
| `surface_color` | Main surface color. |
| `shadow_color` | Color in compressed tracks. |
| `normal_strength` | Strength of surface shading from track details. |
| `wrapped_diffuse_lighting` | Enables wrapped diffuse lighting with cool-tinted shadows; `false` uses standard diffuse lighting. |
| `bevel_noise_scale` | World-space noise frequency in cells per meter for stamp bevels. |
| `bevel_noise_strength` | Amount of noise applied to the deformation slope at stamp edges. |
| `sparkle_intensity` | Sparkle brightness; `0` disables the sparkle effect. |
| `sparkle_density` | Sparkle cells per meter. |
| `sparkle_threshold` | Specular threshold for sparkle. |
| `sparkle_fade_start`, `sparkle_fade_end` | Distance range where sparkle fades. |
| `sun_dir` | Direction toward the light; normally updated by `DeformableSurface.sun`. |

Avoid pure-white albedo: lighting can clip the surface and make sparkle
disappear.

Wrapped diffuse lighting is enabled by default to keep steep footprint bevels
brighter on the side facing away from the light. Disable it on `DeformableSurface` or
set the shader uniform to `false` to use standard diffuse lighting instead.
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
  shadows, and keep `area_size` as small as practical.
- The deformation map uses approximately 256², 512², or 1024² RGB8 texels for
  Low, Medium, and High respectively.
- `area_size` should be square. Keep the field and its parents unrotated and
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
- `scripts/deformers/deformer_particles.gd` contains the per-field surface-puff pool.
- `scripts/deformable_surface_settings.gd` contains surface quality settings.
- `resources/quality/` contains Low, Medium, High, and Custom profiles.
- `shaders/` contains the surface, additive/subtractive stamp, and map
  refill shaders.
- `icons/` contains the node icons.
- `plugin.cfg` and `plugin.gd` make the addon visible in Godot's plugin list;
  no editor integration is required for the nodes to work.

## License

MIT. See [LICENSE](LICENSE).
