The problem is that the addon has accumulated more machinery than the feature needs.

## Fix now

- **Editor preview never gets its material.** In `_refresh_preview()` you build `m` and set its parameters, but nothing assigns it (`_mesh.material_override = m` is missing). The preview is probably a plain white plane.
- **Specular and roughness controls are likely inert.** `deformable_surface.gdshader` defines `light()` and only adds to `DIFFUSE_LIGHT`. In Godot a custom `light()` replaces the built-in lighting, so `specular_amount`, `base_roughness`, `pressed_roughness`, `glaze_*` and `SPECULAR` probably do nothing. Please verify. Either add `SPECULAR_LIGHT` or drop those uniforms. A cheaper alternative is to remove `light()`, use `render_mode diffuse_lambert_wrap`, and fake the cool shadow tint in `fragment()` from the `sun_dir` uniform you already have. That also avoids the extra per-light pass.
- **The documented default dimple pattern isn't what renders.** The README describes cellular noise (Euclidean squared, jitter 0.9). With `initial_noise == null` the GPU path uses value noise. The cellular fallback in `initial_noise_generator.gd` is only reachable from tests, so it is effectively dead.
- **Dead and stale files.**
  - `demos/classic.tscn` and `demos/snow_demo_infinite.tscn` reference scripts that aren't in the repo.
  - `noise_cellular.tres` appears unused.
  - `SnowWeather` is a legacy duplicate of `SnowWorldManager` in a 0.1.0 package, so delete it.
  - Remove `Quality.CUSTOM`.
  - Remove `to_dictionary`/`apply_dictionary` on the resources if nothing calls them.
  - The README layout lists `snowfall/scripts/utilities/`, which isn't shown.
- **Docs drift.** The addon README says `subdiv = 127` while `medium.tres` says 128. The changelog describes the `contact` signal differently from the code. The root README and addon README duplicate each other. Keep the API in the addon README and demos/install in the root.

## Where the complexity comes from

1. **Two noise pipelines.** GPU value noise (the default) and a CPU `FastNoiseLite` path (for presets) with a worker thread, a sliced fallback, prepared/spare textures, cache keys and seam tests. The tile grid's prefetch logic and `settings.has_pending_surface_updates` blocking exist mostly to serve the CPU path. Using one world-space GPU path removes all of it. To keep preset variety, bake each preset's `FastNoiseLite` into a seamless `NoiseTexture2D` once and sample it in the refill/initial shader with world-space UVs. Slopes come from finite differences or a packed gradient channel.
2. **A 9-tile grid instead of a scrolling map.** `DeformableSurfaceGrid`, cross-tile reach checks, `owns_contact` half-open bounds, the edge/corner tests and the recycling queue all exist because one map covers one fixed square.
3. **State-sync machinery around resources.**
   - The `_mp` snapshot, `_values()` and the hand-written property forwarders on the node.
   - `_quality_settings_equal`, which hand-lists fields despite a comment saying nothing is hand-listed.
   - The static `unassigned`/`assigned` registries, the dirty list with tombstones, round-robin and compaction.
   - Godot resources already have `emit_changed()`/`changed`. Hold the references and react to that signal.
4. **`deformable_surface.gd` is a god class.** It does mesh, material, viewport, stamp queueing, refill, noise threading, puffs and editor preview. `_stamp()` takes 12 positional arguments while `PendingStamp` already exists. Split it into a `DeformationMap` (viewport, stamp batches, refill), a puff pool, and a thin node. The tests also reach into privates (`_vp`, `_pending_stamps`, `_prime_frames`), which a split would clean up.
5. **The stamp shader does too much.** It handles round, ellipse, capsule, track segment and sprite, plus berm dilation (8 extra samples) and sprite gradients, all behind branches. Consider two shaders: analytic brush, and sprite/tread. Make textured berm dilation opt-in.

## Is there a better method?

Keep the render-target heightmap, but change how it's arranged:

- **One map that follows the target, with toroidal addressing, instead of a tile grid.** Scroll via a UV offset with repeat. When the target moves a texel or more, redraw only the newly exposed rows with the noise shader. Snap the mesh to the texel grid. This deletes the grid, the tile-edge logic, prefetch and recycling, and with GPU noise the reset is trivial. The tradeoff is that tracks outside the window (say 32 m) are forgotten, which is usually fine for both Powder Run and infinite Playground.
- **Make vertex displacement optional.** Your fragment shader already reads height and slope. For a top-down or orthographic camera like Powder Run, normal and darkening alone look good on a flat plane. A `displace` flag lets Low tier skip the subdivided mesh and vertex texture fetch.
- **Check `use_hdr_2d` on `SubViewport` for Compatibility in 4.7.** If an RGBA16F target works across your browser and mobile targets, you could drop the baked-slope encoding and the 8-bit dither refill. WebGL2 float-render support is uneven on mobile, so test it before committing.
- **Known limitation: carve replaces instead of taking the minimum.** `blend_mix` writes toward the target height, so a light stamp over a deep trench can partially fill it. Godot 2D has no min/max blend, and the screen-texture workaround is costly on mobile. I'd document this rather than fight it.
- **Gameplay depth.** If you ever want characters to sink, keep a small CPU-side coarse height grid (for example 64×64) updated alongside stamps, rather than a GPU readback.

I considered decals or per-footprint meshes. They are simpler but lose berms, healing and continuous ski grooves, so they don't fit your goals.

## Suggested order

1. Fix the preview bug and the specular/`light()` issue, and delete the dead files and legacy `SnowWeather`.
2. Move to GPU-only noise, with presets baked to textures. Delete the generator, threading and prepare/prefetch paths.
3. Replace the resource snapshot, dirty-list and registry code with `changed` signals and a simple registry.
4. Split `deformable_surface.gd` and the stamp shader.
5. Add the scrolling single-map mode. Once it works, delete the grid and its tests.
6. Finish the TODO's scene and folder cleanup, and consider moving the demo HUD/FPS/settings scaffolding out of the shipped package, since it outweighs the addon itself.