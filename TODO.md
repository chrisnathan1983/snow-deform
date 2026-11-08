# TODO

## P1 — Simplify the core surface

- **Move from the tile grid to one scrolling map.** Prototype a toroidal height map that follows the target. Update only newly exposed rows or columns, snap the surface to texel increments, and document how much history remains visible. Replace the demo grid only after scrolling, stamps, recovery, and edge behavior are covered.
- **Finish splitting `DeformableSurface`.** `DeformationMap`, `StampBatchRenderer`, and the puff pool already own parts of the work. Move the remaining stamp queue, deformer scheduling, and contact orchestration behind focused components or APIs so the node becomes a thin coordinator. Keep tests from depending on its private viewport and queue state.
- **Audit remaining resource-state bookkeeping.** Keep the `changed` signal subscriptions. Simplify `_surface_type_state` and any compatibility accessors only where they duplicate resource state; retain the minimal logic needed to decide when changing a profile must clear the map.

## P2 — Verify rendering and engine behavior

- **Add optional vertex displacement.** Check whether the surface can use its fragment height and slope data without a subdivided mesh. If the visual result holds up, let Low quality skip mesh subdivisions and vertex texture sampling.
- **Check HDR render targets on Compatibility.** On Godot 4.7, verify `use_hdr_2d` and RGBA16F support on the browser and mobile targets. Only consider dropping baked slopes and 8-bit refill encoding if the target platforms support it reliably.
- **Recheck the threaded ResourceLoader leak.** Once Godot includes the upstream LoadToken fix, rerun `tests/demo_loading.gd` with threaded loading. Until then, keep the reproduction and workaround documented in `THREADING_LEAK_INVESTIGATION.md` and decide whether the headless test should use synchronous loading.
- **Decide how to handle carve blending.** The current blend can partially refill a deeper trench when a lighter stamp overlaps it. Document this behavior and keep it as a known limit unless gameplay requires true minimum-height carving and a suitably cheap implementation is available.

## P2 — Bring docs back in sync

- **Separate project and addon documentation.** Keep installation and demo instructions in the root README. Keep the deformable-surface API in `addons/deformable_surface/README.md`; remove duplicated API sections from the root README after checking that links still work.
- **Fix the contact signal in the changelog.** It currently names the argument `surface_type`; the signal and addon README use `type_name`.
- **Resolve the Medium subdivision mismatch.** `DeformableSurfaceQuality` and the docs use `subdiv = 127`, while `resources/quality/medium.tres` uses 128. Choose the intended value and update the preset and docs consistently.

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

This removes the flat `demos/scripts/` dump. Consider moving demo HUD, FPS, and settings scaffolding out of the shipped addon package.

### Finish export and runtime checks

- [x] Filter tests, editor tooling, and unused demos out of the single-threaded Web export.
- [x] Generate Brotli and gzip sidecars and document how to serve them.
- [ ] Compile and browser-test the optional custom template using `tools/godot_web_profile.py`.

## Optional, if gameplay needs it

- To make characters sink into the surface, maintain a small CPU-side coarse height grid (for example, 64×64) alongside stamps. Avoid GPU readback, which would stall Web rendering.
