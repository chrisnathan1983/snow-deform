# Deformable Snow - demo scene

A self-contained playground for the `deformable_surface` addon. No external assets: everything is
built from code and primitive meshes.

## Install
1. Make sure the addon is at `res://addons/deformable_surface/`.
2. Drag this `demos/procedural_playground` folder and `demos/common` (shared HUD, props, character and
   the launcher button) into your project's `res://demos/` folder.
3. Project Settings -> Rendering -> Renderer: **Compatibility** (needed for Web / mobile).
4. Open `res://demos/procedural_playground/snow_demo.tscn` and press **F6**
   (or set it as the main scene for a Web export).
   For the fence-free infinite version, open
   `res://demos/procedural_playground/snow_demo_infinite.tscn`.

Tested on Godot 4.4.1 and 4.6 (the scene works around the addon's preset-loading problem on 4.4
by creating `DeformableSurfaceQuality` and `SnowWeatherSettings` profiles in code). Atmospheric
flakes are managed by one `SnowWorldManager`; the DeformableSurface keeps its own recovery and contact puffs.

The repository also includes `res://demos/infinite_snow/infinite_snow.tscn`, a separate streaming-world
example with nine recycled DeformableSurfaces and one shared SnowWorldManager. Run with WASD/arrows,
hold Shift to run, press Space to jump, right-drag to look, use the mouse wheel to zoom, and
press R to reset the currently loaded fields. Each surface has its own recovery profile; recycled
tiles clear their deformation map when they are moved to a new world location.

## What's in it
| Thing | Shows off |
|---|---|
| Explorer (you) | Footprints, run/walk stride, pausing footsteps while jumping |
| Penguin parade | Tiny feet following you in a conga line |
| Yeti | Heavy, wide, deep footprints on a patrol loop |
| Sled | Long grooves with side berms, puffs while sliding (aspect + `puff_distance`) |
| Bouncing balls | Craters + puffs on every landing (deformers ignored while airborne) |
| Tap / click to throw | Snowball arcs from you and splats into a crater |
| Snowball storm | 14 snowballs dropped around you |
| Menu | Shared tabbed HUD: surface (quality, material preset, depth, berms, technical), weather, graphics, scene toggles |

The infinite variant keeps the same playground controls and actors but removes
the fence and recycles a 3x3 grid of DeformableSurfaces around the player. Field
relocations are spread across frames to avoid a large reset spike when crossing
a tile boundary.

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
