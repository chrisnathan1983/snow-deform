# Deformable Snow - demo scene

A self-contained playground for the `deformable_surface` addon. No external assets: everything is
built from code and primitive meshes.

## Install
1. Make sure the addon is at `res://addons/deformable_surface/`.
2. Copy the repository's `demos/` folder into your project's `res://` folder. Runnable scenes
   live directly in `demos/`, with scripts in `demos/scripts/`, shared components in
   `demos/shared/`, shaders in `demos/shaders/`, and actor scenes in
   `demos/characters/` and `demos/props/`.
3. Project Settings -> Rendering -> Renderer: **Compatibility** (needed for Web / mobile).
4. Open `res://demos/playground.tscn` and press **F6**, or choose **Playground** in the launcher.
   Use **Menu → Scene → Infinite** to switch between the fenced arena and the recycled snowfields.

The demos use the addon presets for standard quality, snow and weather settings. Demo-specific
profiles, including the smaller tile maps for Infinite mode, live in `demos/resources/`.
One `SnowWorldManager` handles atmospheric flakes, while each DeformableSurface handles its own
recovery and contact puffs.

Switching modes keeps the actor and material settings and clears existing tracks.
The **Area size** slider on the Surface tab applies to the fenced arena.

## What's in it
| Thing | Shows off |
|---|---|
| Explorer (you) | Footprints, run/walk stride, pausing footsteps while jumping |
| Wandering NPCs, mouse, soccer ball | Footsteps, tiny tracks, and a pushable physics ball |
| Penguin parade | Tiny feet following you in a conga line |
| Yeti | Heavy, wide, deep footprints on a patrol loop |
| Sled | Long grooves with side berms, puffs while sliding (aspect + `puff_distance`) |
| Bouncing balls | Craters + puffs on every landing (deformers ignored while airborne) |
| Tap / click to throw | Snowball arcs from you and splats into a crater |
| Snowball storm | 14 snowballs dropped around you |
| Menu | Shared tabbed HUD: surface (quality, material preset, depth, berms, technical), weather, graphics, scene toggles |

Infinite mode keeps the same playground controls and actors but removes
the fence and recycles a 3x3 grid of DeformableSurfaces around the player. Field
relocations are spread across frames to avoid a large reset spike when crossing
a tile boundary. Moving within eight meters of a boundary starts preparing the
next row or column without moving any active fields. Recycling prioritizes nearby
tiles and favors visible terrain; a teleport prioritizes the field under the player.
Prepared textures are stored separately so resetting tracks can reuse the active
texture while future tiles are being generated.

Surface settings wait 120 ms after the last edit, prepare noise in a background
thread, and apply one field per frame. Rapid slider edits keep the latest values.
Tile recycling waits for the settings batch to finish so both operations share
the noise cache safely. Footprint brushes overlap neighboring fields at tile
edges and corners; contact effects are emitted only by the field containing the
brush center.

## Regression checks

Run the scripts in `tests/` with `godot --headless --path . --script <script>`.
`playground_modes.gd` checks the launcher, mode switches, and arena resizing.
`infinite_snow_prefetch.gd` checks early preparation, resets during preparation,
priority after teleports, and direction reversals. `infinite_snow_frame_times.gd`
measures complete frame intervals during movement, noise edits, and quality
changes, and writes its samples to `.godot/infinite-frame-times.json`. Omit
`--headless` for a benchmark that includes rendering and texture uploads. It caps
the frame rate at 120 and reports a stationary baseline alongside the workload;
results depend on the machine and frame pacing.

## Controls
- **Desktop:** WASD/arrows move, Shift run, Space jump, drag = look, click = throw,
  wheel = zoom, M = menu, R = reset tracks, 1/2/3 = quality.
- **Touch:** left half drag = move joystick; right half drag = camera joystick;
  quick tap = throw; JUMP / RUN buttons bottom-right; MENU top-right.

## Things to try on a phone
- Start on **Low**, then bump to Medium/High and watch the FPS graph (top center; F3 toggles it, F4 shows a per-operation breakdown).
- Switch quality while tracks exist: the map clears when resolution changes.
- Drag the **Snowfall** slider: visual snowfall increases and tracks heal faster.
- Lower the **Sun height** for long shadows and strong sparkle.

## Notes
- Web export: use the Compatibility renderer, disable thread support for widest phone
  compatibility, and serve over HTTPS (or localhost) so the browser allows the page to run.
