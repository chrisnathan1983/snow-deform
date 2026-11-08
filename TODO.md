# TODO

Items are ordered by priority. Findings marked *(audit)* come from a read-through of the code; none were profiled or run, so confirm each before relying on it.

## P0 — Fix correctness and ownership bugs

- [ ] **Make priming robust.**
  - [ ] Measure a preset switch on a no-threads Web export. The export is currently blocked because the Godot 4.7.2 `web_nothreads` templates are not installed in this environment.

## P1 — Simplify the core surface

- [ ] **Move from the tile grid to one scrolling map.** Replace the demo grid only after scrolling, stamps, recovery, and edge behavior are covered. Removes `DeformableSurfaceGrid`, cross-tile reach checks, `owns_contact` bounds, the edge/corner tests, and the recycling queue.
  - [ ] Connect the window state to map rendering, stamps, refill, and recovery; cover edge and teleport behavior before replacing the grid.

## P2 — Verify rendering and engine behavior

- [ ] **Add optional vertex displacement.** Check whether the surface can use its fragment height and slope data without a subdivided mesh. A top-down or orthographic camera (Powder Run) may look fine with normal and darkening alone. If the result holds up, let Low quality skip mesh subdivisions and vertex texture sampling.
- [ ] **Check HDR render targets on Compatibility.** On Godot 4.7, verify `use_hdr_2d` and RGBA16F support on the browser and mobile targets. Only consider dropping baked slopes and 8-bit refill encoding if the target platforms support it reliably.
- [ ] **Recheck the threaded ResourceLoader leak.** Once Godot includes the upstream LoadToken fix, rerun `tests/demo_loading.gd` with threaded loading. Until then, keep the reproduction and workaround documented in `THREADING_LEAK_INVESTIGATION.md` and decide whether the headless test should use synchronous loading.
- [ ] **Decide how to handle carve blending.** The current blend can partially refill a deeper trench when a lighter stamp overlaps it. Document this behavior and keep it as a known limit unless gameplay requires true minimum-height carving and a suitably cheap implementation is available.
- [ ] **Test the GPU noise path on real devices.** Confirm the generated shaders use `highp` on a low-end Android browser, and run the rendered seam check in `initial_noise_seams.gd` (headless runs only verify caching).


## P5 — Finish demo scene and folder cleanup

### Finish export and runtime checks

- [ ] Compile and browser-test the optional custom template using `tools/godot_web_profile.py`. This environment has no Godot executable or installed Web export templates.
- [ ] Time a preset switch and a first-footprint refill in a real browser (see the P0 priming and refill items). Requires a Godot Web export.

## Optional, if gameplay needs it

- To make characters sink into the surface, maintain a small CPU-side coarse height grid (for example, 64×64) alongside stamps. Avoid GPU readback, which would stall Web rendering.

## Done since the last audit

### Completed TODO items

- [x] Replaced `DemoCharacter`'s role enum with player, wander, and follow behavior scripts attached to the character scenes.
- [x] Moved PineForest, the Playground fence, and hills into reusable scenes.
- [x] Split bouncing balls and thrown snowballs into dedicated scenes and scripts.
- [x] Reset the baked root and visual transforms in `penguin.tscn` and `yeti.tscn`, named their body parts, and gave the explorer meshes real names.
- [x] Replaced the capsule `npc.tscn` with an explorer using random Wander behavior and a soccer-ball contact area.
- [x] Reduced the demo prop helper to `mat()` and moved the shared sun, sky, and fog setup into `demo_environment.tscn` with a `sun_height` export.
- [x] Organized demo files by feature, moved scripts alongside their scenes, renamed the demo scenes to `powder_run`, `materials`, and `custom_terrain`, and removed the flat `demos/scripts/` folder.
- [x] Fixed editor errors exposed after the scene move: corrected the NPC script resource ID, removed preload aliases that shadowed the `DemoCharacter` and `DemoSnowball` global classes, updated NPC speed overrides to `move_speed`, and removed the unused cached footsteps field.
- [x] **Repair `tests/ski_free_profile.gd` parse error.** Fixed the stray indentation on `batch_count`.
- [x] **Rerun the ski benchmark.** Ran all nine native cases and updated `tests/SKI_PERFORMANCE.md`; frame times varied, while draw-call counts remained consistent.
- [x] **Stop `set_recovery_intensity()` and `set_wrapped_diffuse_lighting()` from mutating the shared resource.** The first runtime override now duplicates the assigned `DeformableSurfaceType` for this node, and the recovery property comment describes the per-node behavior.
- [x] **Reset `_sun_dir` when the source material changes.** `_on_surface_material_changed` now resets the cached direction after adopting the new material, so `_process` reapplies it.
- [x] Add a 10-second timeout; if a noise bake never finishes, switch the starting and refill targets to neutral and let priming complete.
- [x] Share the mound texture across profiles using its seed as a separate cache key.
- [x] Cache the noise key per profile, invalidating it when the profile or its source noise changes.
- [x] **Bake the refill target once.** Each map clear now renders its starting surface to a target texture once; refill passes sample that texture instead of reevaluating the noise and slope shader.
- [x] **Warm up the refill shader.** `warm_up_effects` now shows the refill rect while the loader draws its covered warmup frames, then hides it before gameplay.
- [x] Prototype and cover texel-snapped toroidal window state, ring offsets, wrapped exposed-strip rectangles, retained UVs, stamp copies at edges/corners, and teleports; document the current 96 m Playground and 120 m Powder Run history extents.
- [x] **Finish splitting `DeformableSurface`.** `SurfaceStampPipeline` owns queued stamp state, packing and batch submission; `DeformerScheduler` owns deformer scheduling and movement history; `SurfaceContactDispatcher` normalizes contacts and routes puffs. Removed the `_vp` alias and moved tests to public surface diagnostics for map images, resolution, pending stamps and priming state.
- [x] **Audit remaining resource-state bookkeeping.** Kept the resource `changed` subscriptions and clear-state snapshot, but ignored inactive noise settings and the unused fallback frequency when a custom noise resource supplies its own frequency.
- [x] **Share stamp shader math.** Both analytic and sprite stamps now use the shared pit, berm, and slope calculations in `deformable_surface_stamp_profile.gdshaderinc`.
- [x] **Separate project and addon documentation.** Keep installation and demo instructions in the root README. Keep the deformable-surface API in `addons/deformable_surface/README.md`; remove duplicated API sections from the root README after checking that links still work.
- [x] **Fix the contact signal in the changelog.** The signal signature now names the argument `type_name`, matching the signal and addon README.
- [x] **Resolve the Medium subdivision mismatch.** `DeformableSurfaceQuality` and the docs use `subdiv = 127`, while `resources/quality/medium.tres` uses 128. Choose the intended value and update the preset and docs consistently.
- [x] **Remove stale README statements.**
  - The root README's "subtract-blend refill pass" is outdated; refill uses `blend_mix`.
  - The README layout omits `deformation_map.gd`, `stamp_batch_renderer.gd`, `initial_noise_textures.gd`, and the analytic stamp and initial-noise shaders, and still lists `snowfall/scripts/utilities/`.
- [x] **State the supported engine version honestly.** The addon README now says this release targets and is tested on Godot 4.7; earlier minor versions are unverified.
- [x] **Document moving a surface.** Moving a `DeformableSurface` after setup leaves the noise origin stale until `reset_trails()`. Document it or handle it in the node.
- [x] `_dirty_deformers.has()` and `find()` are O(n) per transform notification; use an index map and swap removal.
- [x] `_configure_hash_origins` allocates a key array per field per frame; compare the values directly.
- [x] `StampBatchRenderer` never frees batches, so many unique footprint textures would accumulate. Retain at most 32 batches between frames, pruning idle batches at frame reset.
- [x] **Footstep tuning per kind:** moved footsteps and per-character movement/animation values into `explorer.tscn`, `yeti.tscn` and `penguin.tscn`, matching the scene-owned setup in `mouse.tscn`. Removed `DemoCharacter.kind`.
- [x] Filter tests, editor tooling, and unused demos out of the single-threaded Web export.
- [x] Generate Brotli and gzip sidecars and document how to serve them.

- [x] Editor preview now assigns its material.
- [x] Removed the custom `light()` function; wrap and cool tint are computed in `fragment()`, so specular and roughness uniforms take effect.
- [x] One noise pipeline: seamless `NoiseTexture2D`s sampled in world space. The thread, prefetch, and sliced fallback are gone.
- [x] Resource state flows through `changed` signals.
- [x] Stamp rendering split into analytic and sprite shaders; textured berm dilation is opt-in.
- [x] `DeformationMap` and `StampBatchRenderer` extracted from the node.
