## 1. Cut the demos from 7 to 4

Done. The launcher now opens Playground, Powder Run, Material Showcase, and Custom Terrain & Grass.
Playground includes the fenced arena, Infinite mode, actor toggles, and the area-size slider.

## 2. Extract the tile recycler

Done. `demos/shared/deformable_surface_grid.gd` is shared by Playground and Powder Run.
The recycling, prefetch, and settings tests exercise the grid directly.

## 3. Replace the code-built content with scenes

- **Footstep tuning per kind:** this is a `match kind` in `_ready()` that creates the `DeformerFootsteps` in code. `mouse.tscn` already does it right: the footsteps node sits in the scene with its values set. Do that for all characters and drop `kind`.
- **`DemoCharacter` roles:** one script handles PLAYER, WANDERER and FOLLOWER via a `role` enum. Split it into small behavior scripts (`PlayerController`, `Wander`, `Follow`) attached to the same character scene.
- **Scenery:** Move the shared `PineForest` and the Playground fence and hills into reusable scenes.
- **Soccer ball vs. `demo_ball`:** two ball systems (RigidBody vs. fake bouncer/thrown). Split `demo_ball.gd` into `bouncing_ball.tscn` and `snowball.tscn` instead of a `Kind` enum.
- **Scene hygiene:** `penguin.tscn` and `yeti.tscn` have stray baked root transforms (position about (3,0,0), rotated), and many nodes are named `@MeshInstance3D@35`. Reset the transforms and give the nodes real names (Body, Head, Beak…).
- **`npc.tscn`:** Replace the capsule NPC with an explorer using the Wander behavior while retaining its soccer-ball interaction.

After this, `demo_props.gd` should shrink to nothing or a single `mat()` helper.

## 4. Extract the shared rig

The demos share the camera, brush, shell, grid, and preset resources. Environment setup still
varies by demo. Move the shared sun, sky, and fog setup into `demo_environment.tscn` with a
`sun_height` export.

## 5. Folder layout

Organize by feature, with scripts next to their scenes:

```
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

This removes the flat `demos/scripts/` dump.

## 6. Docs

Done. The root README includes the demo guide and regression commands, and the changelog
describes the current demos and shared components.

## Suggested order

- [x] Delete dead and duplicate code.
- [x] Switch to the addon's `.tres` presets.
- [x] Extract the shared camera, brush, shell, and grid.
- [x] Merge the playgrounds.
- [x] Move Powder Run actors and course props into scenes.
- [x] Update the tests and docs.

## 7. Avoid first-use hitches

Done. The launcher displays a loading screen before requesting the scene, with a synchronous
fallback on builds without threads. While the screen is up, it draws round, capsule, textured,
and tread stamps and starts every puff emitter. It clears the samples before gameplay resumes.

## 8. Export and load size

- Exclude `tests/`, `.godot/`, and unused demos via export filters, and ship only what the web build needs.
- Serve with Brotli or gzip.
- Use a custom export template with unused modules disabled (for example 3D physics if you don't need it, but `RigidBody3D` and `AnimatableBody3D` are used in some demos).
- Keep the single-threaded export unless you control the COOP/COEP headers.
