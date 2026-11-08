## 1. Cut the demos from 7 to 2

| Keep | Absorbs |
|---|---|
| **Powder Run** (ski_free) | Nothing. It's a game, not a feature demo. |
| **Playground** | `classic`, `snow_demo`, `snow_demo_infinite`, `infinite_snow` |
| **Materials & Vehicles** | `materials_demo` |
| **Custom Terrain** | Keep: it's the only demo of `render_mesh = false` and the `.gdshaderinc`. |

The four snow playgrounds are the same demo built four times: the same explorer, sled, balls, weather, HUD, camera and keyboard handling. Make one Playground scene with an **Infinite** toggle and actor toggles in the Scene tab. From `classic`, bring over the NPCs, mouse, soccer ball and the area-size slider.

The infinite variant currently overrides `_build_actors` by copy-pasting the parent's version (with `#super._build_actors()` commented out). That copy silently dropped the penguins. Instead, split the parent into `_build_player()`, `_build_sled()`, `_build_balls()` and so on, or better, remove the subclass entirely.

## 2. Extract the tile recycler

Tile recycling exists three times: `infinite_snow.gd` (synchronous), `snow_demo_infinite.gd` (async, prefetching) and `ski_free._recycle_snow`. Your README lists "move the field with the player" as not implemented. Turn the `snow_demo_infinite` version into a reusable node, for example `DeformableSurfaceGrid`. It would take a surface type, quality, tile size, radius and a follow target. It could live in the addon or in `demos/shared/`. The tests (`infinite_snow_prefetch`, `_recycling`, `surface_settings_updates`) currently reach into demo internals like `scene._pending_relocations`. Move them to target the grid node.

## 3. Replace the code-built content with scenes

Many things exist both as a `.tscn` and as code that builds the same thing:

- **Characters:** `explorer`, `yeti` and `penguin` have scenes, but `demo_character.gd` still has `_build_explorer/_yeti/_penguin` fallbacks. Delete them. Likewise `DemoBall.build_visual` and `DemoSled.build_visual`.
- **Footstep tuning per kind:** this is a `match kind` in `_ready()` that creates the `DeformerFootsteps` in code. `mouse.tscn` already does it right: the footsteps node sits in the scene with its values set. Do that for all characters and drop `kind`.
- **`DemoCharacter` roles:** one script handles PLAYER, WANDERER and FOLLOWER via a `role` enum. Split it into small behavior scripts (`PlayerController`, `Wander`, `Follow`) attached to the same character scene.
- **Sleds:** `classic_sled.tscn` + `sled.gd` (orbit) and `sled.tscn` + `demo_sled.gd` (figure-8). Merge into one scene with a path-mode export.
- **Forests:** `PineForest` (MultiMesh with the `tree_snow` shader) and `Props.add_forest`/`add_hills`/`add_fence`. Keep `PineForest`, add whatever scatter options the other needs, and make `forest.tscn`, `fence.tscn` and `hills.tscn`. `pine_tree.tscn` looks unused; either delete it or use it for Powder Run.
- **Powder Run:** the skier, trees, rocks, jump ramps and the four slope-guest kinds are all built in code. Make `skier.tscn`, `jump_ramp.tscn` and one scene per guest kind. Reuse `pine_tree.tscn` and `rock.tscn`. `_batch_scenery` already works by iterating mesh children, so it will keep working.
- **Soccer ball vs. `demo_ball`:** two ball systems (RigidBody vs. fake bouncer/thrown). Split `demo_ball.gd` into `bouncing_ball.tscn` and `snowball.tscn` instead of a `Kind` enum.
- **Scene hygiene:** `penguin.tscn` and `yeti.tscn` have stray baked root transforms (position about (3,0,0), rotated), and many nodes are named `@MeshInstance3D@35`. Reset the transforms and give the nodes real names (Body, Head, Beak…).
- **`npc.tscn`:** this is a separate capsule character with its own physics script. Make it an explorer with the Wander behavior, as the CHANGELOG already claims classic does. In `classic.tscn` the "Player" is still a bare Node3D with the script and no `Visual`, so it builds itself in code.

After this, `demo_props.gd` should shrink to nothing or a single `mat()` helper.

## 4. Extract the shared rig

Each demo re-implements the same pieces:

- **Environment/sun/sky/fog:** make `demo_environment.tscn` with a `sun_height` export.
- **Follow/orbit camera:** `DemoCamera`, `snow_demo._update_camera`, `infinite_snow._update_camera`, and the orbit code in `materials_demo` and `custom_terrain_demo`. One `DemoCamera` with FOLLOW and ORBIT modes covers all of them.
- **Mouse brush with `_ground_point`:** it's duplicated in `materials_demo` and `custom_terrain_demo`. Make a `BrushDeformer` node.
- **HUD plumbing:** `DemoNav.attach` + `DemoHud.new` + `DemoSettings.create` + the same 8-line `TouchSticks` overlay setup. Wrap this in a `demo_shell.tscn`. The Powder Run HUD can stay separate.
- **Quality, surface type and weather profiles:** the demos build these in code (`_make_quality_presets`, `_make_surface_type`, `_make_weather_profile`, `_scaled`), partly for a 4.4 workaround that `demos/README.md` mentions. The project is on 4.7 and the addon ships `low/medium/high.tres`, `snow_profile.tres` and the weather presets. Use those, and save any demo-specific tiers (like infinite's smaller maps) as `.tres` files.

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

Update `demos/README.md` (merge it into the root README), the root README's demo section, and the CHANGELOG. They still reference `demos/common/`, `demos/classic/` and `demo_ui`, which no longer exist. The launcher list shrinks to match.

## Suggested order

1. Delete the dead and duplicate code (the `_build_*` fallbacks, `classic_sled`, the commented penguins, `Props.add_forest`).
2. Switch to the addon's `.tres` presets.
3. Extract the shared pieces (camera, brush, shell, grid).
4. Merge the playgrounds.
5. Scene-ify Powder Run.
6. Rewrite the tests and docs.

Doing it in this order means you can run the tests after each step.


## 7. Avoid first-use hitches

The Compatibility renderer compiles shaders on first draw, so the first footstep, puff, or tread stamp stutters. Warm up at load by drawing one stamp of each type (round, capsule, textured, track) and bursting one puff per pool entry, hidden behind a loading screen. Also, `change_scene_to_file` in the launcher is a synchronous load, so show a "Loading…" label first. Use `ResourceLoader.load_threaded_request` and it will still degrade gracefully when threads are unavailable.

## 8. Export and load size

- Exclude `tests/`, `.godot/`, and unused demos via export filters, and ship only what the web build needs.
- Serve with Brotli or gzip.
- Use a custom export template with unused modules disabled (for example 3D physics if you don't need it, but `RigidBody3D` and `AnimatableBody3D` are used in some demos).
- Keep the single-threaded export unless you control the COOP/COEP headers.

