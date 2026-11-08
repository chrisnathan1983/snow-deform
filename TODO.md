## 1. Replace the code-built content with scenes

- **Footstep tuning per kind:** this is a `match kind` in `_ready()` that creates the `DeformerFootsteps` in code. `mouse.tscn` already does it right: the footsteps node sits in the scene with its values set. Do that for all characters and drop `kind`.
- **`DemoCharacter` roles:** one script handles PLAYER, WANDERER and FOLLOWER via a `role` enum. Split it into small behavior scripts (`PlayerController`, `Wander`, `Follow`) attached to the same character scene.
- **Scenery:** Move the shared `PineForest` and the Playground fence and hills into reusable scenes.
- **Soccer ball vs. `demo_ball`:** two ball systems (RigidBody vs. fake bouncer/thrown). Split `demo_ball.gd` into `bouncing_ball.tscn` and `snowball.tscn` instead of a `Kind` enum.
- **Scene hygiene:** `penguin.tscn` and `yeti.tscn` have stray baked root transforms (position about (3,0,0), rotated), and many nodes are named `@MeshInstance3D@35`. Reset the transforms and give the nodes real names (Body, Head, Beak…).
- **`npc.tscn`:** Replace the capsule NPC with an explorer using the Wander behavior while retaining its soccer-ball interaction.

After this, `demo_props.gd` should shrink to nothing or a single `mat()` helper.

## 2. Extract the shared rig

The demos share the camera, brush, shell, grid, and preset resources. Environment setup still
varies by demo. Move the shared sun, sky, and fog setup into `demo_environment.tscn` with a
`sun_height` export.

## 3. Folder layout

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

## 4. Export and load size

- [x] Filter tests, editor tooling, and unused demos out of the single-threaded Web export.
- [x] Generate Brotli and gzip sidecars and document how to serve them.
- [ ] Compile and browser-test the optional custom template using `tools/godot_web_profile.py`.
