# TODO

Items are ordered by priority. Findings marked *(audit)* come from a read-through of the code; none were profiled or run, so confirm each before relying on it.

## P0 — Fix correctness and ownership bugs

- [x] **Repair `tests/ski_free_profile.gd` parse error.** Fixed the stray indentation on `batch_count`.
- [x] **Rerun the ski benchmark.** Ran all nine native cases and updated `tests/SKI_PERFORMANCE.md`; frame times varied, while draw-call counts remained consistent.
- [x] **Stop `set_recovery_intensity()` and `set_wrapped_diffuse_lighting()` from mutating the shared resource.** The first runtime override now duplicates the assigned `DeformableSurfaceType` for this node, and the recovery property comment describes the per-node behavior.
- [x] **Reset `_sun_dir` when the source material changes.** `_on_surface_material_changed` now resets the cached direction after adopting the new material, so `_process` reapplies it.
- [ ] **Make priming robust.**
  - [x] Add a 10-second timeout; if a noise bake never finishes, switch the starting and refill targets to neutral and let priming complete.
  - [x] Share the mound texture across profiles using its seed as a separate cache key.
  - [x] Cache the noise key per profile, invalidating it when the profile or its source noise changes.
  - [ ] Measure a preset switch on a no-threads Web export. The export is currently blocked because the Godot 4.7.2 `web_nothreads` templates are not installed in this environment.
- [x] **Bake the refill target once.** Each map clear now renders its starting surface to a target texture once; refill passes sample that texture instead of reevaluating the noise and slope shader.
- [x] **Warm up the refill shader.** `warm_up_effects` now shows the refill rect while the loader draws its covered warmup frames, then hides it before gameplay.

## P1 — Simplify the core surface

- [ ] **Move from the tile grid to one scrolling map.** Prototype a toroidal height map that follows the target. Update only newly exposed rows or columns, snap the surface to texel increments, and document how much history remains visible. Replace the demo grid only after scrolling, stamps, recovery, and edge behavior are covered. Removes `DeformableSurfaceGrid`, cross-tile reach checks, `owns_contact` bounds, the edge/corner tests, and the recycling queue.
- [ ] **Finish splitting `DeformableSurface`.** `DeformationMap`, `StampBatchRenderer`, and the puff pool already own parts of the work, but the node is still about 900 lines. Move the remaining stamp queue, deformer scheduling, and contact orchestration behind focused components or APIs so the node becomes a thin coordinator. Keep tests from depending on its private viewport and queue state (`_vp`, `_pending_stamps`, `_prime_frames`).
- [ ] **Audit remaining resource-state bookkeeping.** Keep the `changed` signal subscriptions. Simplify `_surface_type_state` and any compatibility accessors only where they duplicate resource state; retain the minimal logic needed to decide when changing a profile must clear the map.
- [ ] **Share stamp shader math.** The analytic and sprite stamp shaders are near-copies. Move the pit, berm, and slope math into a shared `.gdshaderinc` so a change such as `normal_strength` handling cannot land in only one.

## P2 — Verify rendering and engine behavior

- [ ] **Add optional vertex displacement.** Check whether the surface can use its fragment height and slope data without a subdivided mesh. A top-down or orthographic camera (Powder Run) may look fine with normal and darkening alone. If the result holds up, let Low quality skip mesh subdivisions and vertex texture sampling.
- [ ] **Check HDR render targets on Compatibility.** On Godot 4.7, verify `use_hdr_2d` and RGBA16F support on the browser and mobile targets. Only consider dropping baked slopes and 8-bit refill encoding if the target platforms support it reliably.
- [ ] **Recheck the threaded ResourceLoader leak.** Once Godot includes the upstream LoadToken fix, rerun `tests/demo_loading.gd` with threaded loading. Until then, keep the reproduction and workaround documented in `THREADING_LEAK_INVESTIGATION.md` and decide whether the headless test should use synchronous loading.
- [ ] **Decide how to handle carve blending.** The current blend can partially refill a deeper trench when a lighter stamp overlaps it. Document this behavior and keep it as a known limit unless gameplay requires true minimum-height carving and a suitably cheap implementation is available.
- [ ] **Test the GPU noise path on real devices.** Confirm the generated shaders use `highp` on a low-end Android browser, and run the rendered seam check in `initial_noise_seams.gd` (headless runs only verify caching).

## P2 — Bring docs back in sync

- [ ] **Separate project and addon documentation.** Keep installation and demo instructions in the root README. Keep the deformable-surface API in `addons/deformable_surface/README.md`; remove duplicated API sections from the root README after checking that links still work.
- [ ] **Fix the contact signal in the changelog.** It currently names the argument `surface_type`; the signal and addon README use `type_name`.
- [ ] **Resolve the Medium subdivision mismatch.** `DeformableSurfaceQuality` and the docs use `subdiv = 127`, while `resources/quality/medium.tres` uses 128. Choose the intended value and update the preset and docs consistently.
- [ ] **Remove stale README statements.**
  - The root README's "subtract-blend refill pass" is outdated; refill uses `blend_mix`.
  - The README layout omits `deformation_map.gd`, `stamp_batch_renderer.gd`, `initial_noise_textures.gd`, and the analytic stamp and initial-noise shaders, and still lists `snowfall/scripts/utilities/`.
- [ ] **State the supported engine version honestly.** The addon README says "Godot 4.3 or newer", but the project only targets and tests 4.7. Either test on 4.3 or change the wording.
- [ ] **Document moving a surface.** Moving a `DeformableSurface` after setup leaves the noise origin stale until `reset_trails()`. Document it or handle it in the node.

## P3 — Minor cleanups

- [ ] `_dirty_deformers.has()` and `find()` are O(n) per transform notification; use a set or an index map.
- [ ] `_configure_hash_origins` allocates a key array per field per frame; compare the values directly.
- [ ] `StampBatchRenderer` never frees batches, so many unique footprint textures would accumulate. Cap or recycle them.

## P3 — Finish demo scene and folder cleanup

### Replace code-built content with scenes

- **Footstep tuning per kind:** this is a `match kind` in `_ready()` that creates the `DeformerFootsteps` in code. `mouse.tscn` already does it right: the footsteps node sits in the scene with its values set. Do that for all characters and drop `kind`.
- **`DemoCharacter` roles:** one script handles PLAYER, WANDERER and FOLLOWER via a `role` enum. Split it into small behavior scripts (`PlayerController`, `Wander`, `Follow`) attached to the same character scene.
- **Scenery:** Move the shared `PineForest` and the Playground fence and hills into reusable scenes.
- **Soccer ball vs. `demo_ball`:** two ball systems (RigidBody vs. fake bouncer/thrown). Split `demo_ball.gd` into `bouncing_ball.tscn` and `snowball.tscn` instead of a `Kind` enum.
- **Scene hygiene:** `penguin.tscn` and `yeti.tscn` have stray baked root transforms (position about (3,0,0), rotated), and many nodes are named `@MeshInstance3D@35`. Reset the transforms and give the nodes real names (Body, Head, Beak…).
- **`npc.tscn`:** Replace the capsule NPC with an explorer using the Wander behavior while retaining its soccer-ball interaction.

After this, `demo_props.gd` should shrink to nothing or a single `mat()` helper.

### Extract the shared rig

The demos share the camera, brush, shell, grid, and preset resources. Environment setup still varies by demo. Move the shared sun, sky, and fog setup into `demo_environment.tscn` with a `sun_height` export.

### Organize the demo folders

Organize by feature, with scripts next to their scenes:

```text
demos/
  launcher.tscn/.gd
  playground.tscn   powder_run.tscn   materials.tscn   custom_terrain.tscn
  shared/   demo_shell, demo_hud, demo_settings, demo_nav, demo_fps,
			demo_theme, touch_sticks, demo_camera, demo_environment,
			brush_deformer, surface_grid
  actors/   explorer, yeti, penguin, mouse (+ behavior scripts)
  props/    sled, bouncing_ball, snowball, soccer_ball, rock, snowman,
			pine_tree, forest, fence, hills, jump_ramp, blob_shadow
  slope/    skier, guests/
  shaders/
```

This removes the flat `demos/scripts/` dump. The demo HUD, FPS, and settings scaffolding already live under `demos/`, so the addons do not depend on them.

### Finish export and runtime checks

- [x] Filter tests, editor tooling, and unused demos out of the single-threaded Web export.
- [x] Generate Brotli and gzip sidecars and document how to serve them.
- [ ] Compile and browser-test the optional custom template using `tools/godot_web_profile.py`.
- [ ] Time a preset switch and a first-footprint refill in a real browser (see the P0 priming and refill items).

## Optional, if gameplay needs it

- To make characters sink into the surface, maintain a small CPU-side coarse height grid (for example, 64×64) alongside stamps. Avoid GPU readback, which would stall Web rendering.

## Done since the last audit

- [x] Editor preview now assigns its material.
- [x] Removed the custom `light()` function; wrap and cool tint are computed in `fragment()`, so specular and roughness uniforms take effect.
- [x] One noise pipeline: seamless `NoiseTexture2D`s sampled in world space. The thread, prefetch, and sliced fallback are gone.
- [x] Resource state flows through `changed` signals.
- [x] Stamp rendering split into analytic and sprite shaders; textured berm dilation is opt-in.
- [x] `DeformationMap` and `StampBatchRenderer` extracted from the node.
