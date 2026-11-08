# Deformable Snow for Godot 4

Deformable, sparkly snow built for the **Compatibility renderer**, so it can run
in a browser (WebGL2) and on phones. Characters leave boot prints, sleds leave
runner grooves, snow piles up in berms, snowfall slowly heals the trails, and
kicked-up snow puffs fly. World-space noise breaks up smooth stamp bevels into
subtle clumpy edges. The Playground also has a mouse that leaves tiny footprints as it scurries.

> **Pre-release (0.1.0).** The demos and regression checks target Godot 4.7
> with the Compatibility renderer. Mobile and browser behavior varies by device.

## Install

1. Copy either or both of `addons/deformable_surface/` and `addons/snowfall/`
   into your project's `addons/` folder. Each addon can be used independently.
2. (Optional) Enable it in *Project > Project Settings > Plugins*. The nodes
   register through `class_name`, so they work either way.

See the [Deformable Surface addon guide](addons/deformable_surface/README.md)
for the surface and deformer API, quality and material settings, and usage examples.
See the [Snowfall addon guide](addons/snowfall/README.md) for the weather API and presets.

## Demos

Open `project.godot` in Godot 4.7 and run it to open the [launcher](demos/launcher.tscn).
The launcher shows a loading screen while it loads the scene and warms up snow stamps and puffs.
To copy the demos into another project, copy `demos/` and both addons and select the
Compatibility renderer. Open a demo scene and press F6 to run it directly.

| Demo | What to try |
| --- | --- |
| [Powder Run](demos/ski_free.tscn) | Ski an endless slope, jump ramps, dodge obstacles, and score slalom gates alongside ten slope guests. |
| [Playground](demos/playground.tscn) | Leave footprints, push the soccer ball, throw snowballs, or explore a recycled snowfield. |
| [Material Showcase](demos/materials_demo.tscn) | Compare snow, sand, mud, dirt, and ash. Try albedo and normal textures, triplanar mapping, brush modes, and vehicle tracks. |
| [Custom Terrain & Grass](demos/custom_terrain_demo.tscn) | Deform hilly terrain and bend grass using a shared deformation map with `render_mesh` disabled. |

### Playground

WASD or arrows move, Shift runs, and Space jumps. Drag to look, click to throw a
snowball, and use the wheel to zoom. R resets tracks, and 1/2/3 select the quality tier.
On touchscreens, drag on the left to move and on the right to look. Tap to throw, and
use the **Jump** and **Run** buttons while moving.

Open **Menu → Scene → Infinite** to switch from the fenced arena to a recycled
3×3 grid. Both modes include wandering NPCs, a mouse, a soccer ball, bouncing balls,
a sled, a yeti, and a penguin parade. The Scene tab can toggle those actors and start a
snowball storm. Switching modes clears tracks and preserves actor and material settings.
**Surface → Area size** resizes the fenced arena.

Infinite mode uses smaller map presets and relocates one tile per frame. Tiles under
the player take priority after a teleport. Starting noise is sampled from shared,
seamless textures in the GPU map and recovery shaders.

Surface edits wait 120 ms after the last change, then apply to one field per frame.
Brushes can overlap multiple fields,
while only the field containing the contact center emits puffs and contact signals.

### Powder Run

Steer with A/D or Left/Right, tuck with W or Down, brake with S or Up, and jump with
Space. P pauses, R starts a new run, and Esc returns to the launcher. On touchscreens,
drag the left joystick sideways to steer, push it forward to brake, and pull it back to
tuck. Tap **Jump** with another finger. Pausing or rotating the screen releases the stick.

Six skiers, two snowboarders, a sled rider, and a belly-sliding penguin carve smooth
grooves, steer around traffic, and hop rocks and ramps. The skier and guests use reusable
scenes in `demos/slope/`. Trees, rocks, ramps, and gates are scene instances. The obstacle
pool recycles through MultiMeshes, with contact blobs and matte snow in the default
mobile lighting mode.

### Settings and performance overlay

Press **M** to open the demo settings and **Esc** to return to the launcher. Material
Showcase uses the left mouse button for the brush and E for an impact stamp. Both
Material Showcase and Custom Terrain orbit with right-drag and zoom with the wheel.

- **Surface** has quality and material presets, recovery, depth, berms, puffs, lighting, and
  map, mesh, and stamp budgets. Editing technical values selects **Custom** without changing
  the preset resource.
- **Weather** has snowfall, wind, flake counts, and fall height. Increasing snowfall also
  increases track recovery in Playground.
- **Graphics** has sun shadows and MSAA. Playground also has a sun height slider.
- **Scene** has demo-specific actor, vehicle, brush, and texture controls.

Start on **Low** when testing a phone. F3 toggles the FPS graph and F4 opens a
per-operation breakdown. Changing map resolution clears tracks.

### Web export

Install the Web export templates that match your Godot editor. The project's
`Web` preset uses Compatibility and a single thread. It keeps the four launcher
demos and excludes tests, editor tools, and obsolete scenes. Single-threaded
hosting works without COOP or COEP headers. [Godot Web export guide](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html)

From the project root, export and generate Brotli and gzip sidecars with Node.js.

```powershell
New-Item -ItemType Directory -Force export/web | Out-Null
godot --headless --path . --export-release Web export/web/index.html
node tools/precompress_web.mjs
```

Serve `export/web/` over HTTPS or localhost. Configure the host to negotiate
Brotli or gzip from `Accept-Encoding` and return the matching `Content-Encoding`
and `Vary: Accept-Encoding`. Keep the original files for clients that request
uncompressed responses. Serve `.wasm` as `application/wasm`.

For example, on an Nginx installation with its static gzip module, add these
directives to the location serving the export. A host with Brotli support can
serve the `.br` sidecars as well. [Nginx static gzip documentation](https://nginx.org/en/docs/http/ngx_http_gzip_static_module.html)

```nginx
gzip_static on;
gzip_vary on;
```

```sh
curl -I -H "Accept-Encoding: gzip" https://your-host.example/index.wasm
```

For a smaller engine binary, compile the matching Godot source with an activated
Emscripten SDK and SCons. Pass `tools/godot_web_profile.py` as the SCons profile
from the Godot source directory. [Godot Web template build guide](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/compiling_for_web.html)

```sh
scons profile=/path/to/snow-deform/tools/godot_web_profile.py
```

Select the release ZIP from Godot's `bin/` directory under **Web → Custom Template → Release**.
The profile keeps 3D physics for the soccer ball and actors and omits navigation,
XR, and model importers. Launch all four demos after exporting with a custom template.

## Addon documentation

The root README covers installation, demos, and Web export. The
[Deformable Surface addon guide](addons/deformable_surface/README.md) owns the
surface and deformer API, material customization, and custom-terrain integration.
The [Snowfall addon guide](addons/snowfall/README.md) documents world weather and
standalone snow emitters.

## Regression checks

Run an individual check from the repository root after Godot has imported the project.

```sh
godot --headless --editor --path . --import
godot --headless --path . --script tests/playground_modes.gd
godot --headless --path . --script tests/initial_noise_seams.gd
godot --headless --path . --script tests/ski_free_gameplay.gd
```

| Scripts in `tests/` | Coverage |
| --- | --- |
| `demo_loading.gd` | Loading feedback, fallback without threads, and error recovery. Run with rendering to check warm-up draws and the first live puff. |
| `playground_modes.gd` | Launcher, actor toggles, arena sizing, and pending settings across mode changes. |
| `initial_noise_seams.gd` | Shared seamless texture caching headlessly; run with rendering to compare adjacent map edges. |
| `infinite_snow_recycling.gd`, `surface_settings_updates.gd` | Grid recycling, direction reversal, and batched settings edits. |
| `deformer_tile_edges.gd`, `track_profiles.gd` | Cross-tile stamps, contact ownership, smooth grooves, and tread tracks. |
| `ski_free_gameplay.gd` | Touch input, layout, gates, jumps, recycling, and guest tracks. Run with rendering to check MultiMesh transforms. |

Run `infinite_snow_frame_times.gd` with or without `--headless` for frame pacing
through movement, tile crossings, and settings changes. It caps the frame rate
at 120 and writes `.godot/infinite-frame-times.json`. For Powder Run profiling
with rendering, see [the performance notes](tests/SKI_PERFORMANCE.md).

## License
MIT. See `LICENSE`.
