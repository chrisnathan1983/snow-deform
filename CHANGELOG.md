# Changelog

## 0.1.0 (unreleased)
First packaged release.

- Breaking: `DeformableSurfaceMaterialProfile` is now `DeformableSurfaceType` and `material_profile` is
  `surface_type` (its label field is `type_name`). `area_size` moved from the quality resources to
  `DeformableSurface.size`.
- Breaking: quality is one resource. `DeformableSurfaceSettings` is now `DeformableSurfaceQuality`, and
  `DeformableSurface.quality` takes it directly (`DeformableSurfaceQuality.low()` / `medium()` / `high()` /
  `for_platform()`). Removed: the `Quality` enum, `auto_quality`, the four `*_surface_quality` slots,
  `recommended_quality()`, and the dictionary methods (`get_quality_settings`, `get_surface_quality_settings`,
  `apply_surface_quality_settings`, `get_active_quality_settings`, `has_custom_quality_settings`,
  `apply_quality_settings`). The `custom_surface.tres` preset is gone; any resource you create is custom.
  `quality_changed` now passes the quality resource.

- DeformableSurface: persistent deformation map (SubViewport), berms, oriented prints,
  snowfall healing, sparkle shader, Low / Medium / High presets, editor preview.
- Deformer, DeformerFootsteps: anything can dent the snow; characters get
  alternating boot prints with speed-based stride.
- `DeformableSurface.contact(position, depth, surface_type, source, radius, puff)` signal on footfalls and
  `stamp_at` impacts; surface types gained a `type_name` label.
- The launcher opens Playground, Powder Run, Material Showcase, and Custom Terrain & Grass.
  Playground combines the fenced arena and infinite snowfields. Its Scene tab switches modes and
  toggles actors, including wandering NPCs, the mouse, and the pushable soccer ball.
- The demos share follow/orbit camera code, the flat and height-function mouse brush, and a HUD shell
  with navigation and optional touch sticks. The showcase demos apply their settings live.
- Playground and Powder Run use a reusable tile grid. Playground prepares CPU noise for upcoming
  tiles when its profile supplies a noise resource, and Powder Run recycles full rows downhill.
- Demos use the addon's `.tres` presets and keep their own tuning in `demos/resources/`.
- Powder Run uses authored skier, guest, ramp, and gate scenes and reuses the pine and rock props.
  All slope guests carve smooth grooves, and obstacles keep their batched rendering when recycled.
- Regression coverage includes launcher and Playground mode switches, grid prefetch and settings
  changes, CPU noise seams, and Powder Run gameplay with rendered scenery checks.
- New `disturbed_darkening` material uniform (used by mud and dirt) darkens any disturbed ground.
- Starting-surface noise gained a second octave, controlled by
  `initial_noise_detail` and `initial_noise_detail_scale` on the surface type.
- Added raised piles and dunes to the starting surface (`initial_noise_mound_height`,
  `initial_noise_mound_frequency`), giving areas that can be dug deeper; Surface tab sliders added.
- Default and preset `max_depth` values were raised (default 0.4 m; snow 0.5, mud 0.35, ash 0.3, sand 0.2, dirt 0.1)
  and the presets' starting heights increased.
- Moving round deformers draw continuous capsule strokes; the stamp cap per move is 40.
- Added `get_stamps_used()` and `get_frame_costs()`, and a demo performance overlay (F3 graph, F4 breakdown).
- Starting-surface noise settings now live on the surface type. Presets have their own noise,
  including snow dimples, sand ripples, lumpy mud, clumpy dirt, and soft ash drifts.
- Preset depth/berm values retuned per material (mud deep with heavy ridges, dirt firm and shallow,
  sand and ash soft with low berms, snow deepest).
- Preset review: material `.tres` files now store float params as floats (integer `0`/`1`
  were ignored, so every preset got snow's sparkle, glaze and cool shading); albedos
  rebalanced per material.
- DeformerTracks: tiled tread prints along each wheel's path, with CAR / TRUCK / MOTORCYCLE /
  TRACKED vehicle presets, drawn as continuous ribbons via `DeformableSurface.stamp_segment`; `stamp_at` gained `silent`. Try it in the materials demo.
- One-shot `DeformableSurface.stamp_at(...)` and stamp modes (carve, raise, smooth);
  `Deformer.mode` lets a deformer raise or plow. Try it in the materials demo (E key, brush picker).
- Material presets (snow, sand, mud, dirt, ash) in `addons/deformable_surface/resources/materials/`;
  assign a profile to `DeformableSurface.surface_type`. The shader now has `albedo_texture`, `normal_texture`,
  an optional `triplanar` mode, and roughness / glaze / specular / sparkle controls
  (`sparkle_strength` is a per-material multiplier on the quality-level sparkle).
- The preset files in `resources/materials/*_profile.tres` pair depth, berms, recovery, puffs,
  and lighting settings with a default shader material.
- SnowFall: falling flakes (usable standalone). Puffs: pooled kick-up bursts.
