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
- Demos share one player: the playground explorer (`demos/common/characters/*.tscn`, built on
  `DemoCharacter`). Classic uses it instead of its capsule body (walls and the soccer ball are
  handled by clamping and a proximity push rather than physics).
- Reusable demo scripts now live in `demos/common/`: `demo_ball`, `demo_sled`, `snow_angel`,
  `blob_shadow`, `demo_camera`, `pine_forest` and `tree_snow.gdshader`.
- Procedural playground props are now scenes in `demos/common/props/` (`rock`, `snowman`, `pine_tree`,
  `sled`, `ball`); `DemoSled` and `DemoBall` use an authored `Visual` child when present.
- New `disturbed_darkening` material uniform (used by mud and dirt) darkens any disturbed ground.
- Demos: new `demos/common/` folder holds shared code (props, character) and `DemoNav`, a
  bottom-left "Launcher (Esc)" button added to every demo to return to the launcher.
- Starting-surface noise gained a second octave (`initial_noise_detail`, `initial_noise_detail_scale` on the
  material profile): the same noise layered on top, with a low scale giving broad hills. On by default; the
  demos' Surface tab has "Noise 2nd octave" and scale sliders. Infinite snowfields turns starting noise off and is unaffected.
- Added raised piles and dunes to the starting surface (`initial_noise_mound_height`,
  `initial_noise_mound_frequency`), giving areas that can be dug deeper; Surface tab sliders added.
- Default and preset `max_depth` values were raised (default 0.4 m; snow 0.5, mud 0.35, ash 0.3, sand 0.2, dirt 0.1)
  and the presets' starting heights increased.
- Moving round deformers draw continuous capsule strokes; the stamp cap per move is 40.
- Added `get_stamps_used()` and `get_frame_costs()`, and a demo performance overlay (F3 graph, F4 breakdown).
- Starting-surface noise (`initial_noise*`) moved from the DeformableSurface node into the material profile;
- Demos: every demo now uses one shared HUD (`DemoHud`, `DemoSettings`, `DemoTheme` in `demos/common/`)
  with Surface, Weather, Graphics and demo-specific Scene tabs; all settings apply live (the classic
  confirm/cancel options flow is gone). `classic/ui/demo_hud` and `procedural_playground/demo_ui` were removed.
- Demos: one shared `TouchSticks` control replaces the two touch sticks. A drag on the left half moves the
  character, a drag on the right half shows a joystick and turns the camera, and a quick tap throws a snowball in
  the playgrounds. The classic camera now orbits and classic movement is camera-relative. Infinite snow gained touch controls.
  each preset starts with its own noise (snow dimples, sand ripples, lumpy mud, clumpy dirt, soft ash drifts).
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
  assign one to `DeformableSurface.material`. The shader now has `albedo_texture`, `normal_texture`,
  an optional `triplanar` mode, and roughness / glaze / specular / sparkle controls
  (`sparkle_strength` is a per-material multiplier on the quality-level sparkle).
- Settings split in two: quality profiles (`DeformableSurfaceSettings`) stay technical
  (resolution, subdivisions, budgets); the new   `DeformableSurfaceType`
    (`surface_type`) holds depth, berms, recovery, puffs, lighting and a default material.
  Presets: `resources/materials/*_profile.tres`.
- SnowFall: falling flakes (usable standalone). Puffs: pooled kick-up bursts.
- Demo project (`demos/classic/`) with player, wandering NPCs, a sled, and touch controls.
