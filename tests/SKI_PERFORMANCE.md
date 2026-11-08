# Native SkiFree performance investigation

## Mobile-first lighting follow-up

The ski scene now defaults to `mobile_lighting = true`: no real-time shadow
maps, batched scenery contact blobs and grounded rider blobs, matte snow with
specular and sparkle disabled, softer deformation normals, and diffuse lighting
tuned to preserve bright snow without clipping. The old lighting is available
only as an A/B option; the benchmark explicitly restores it for the original cases.

Latest native `mobile` case: 169 median draw calls, 1.870 ms median frame time and
2.328 ms p95. The shadowed `optimized` case measured 438 draws and 2.003 ms median.
These remain desktop Godot measurements;
no mobile browser tests were run. Use `-- --mobile-only` for a quick native check.

The measurements below describe the earlier track/scenery investigation with
the original lighting, before this mobile-first default was added.

Run `tests/ski_free_profile.gd` as a Godot script, without `--headless`.
No browser or web benchmark is involved. The script writes measurements and
baseline/optimized screenshots to `.godot/`.

Measured on Godot 4.7.2, Compatibility/OpenGL, RTX 3060 Ti, 1280×720.
Vsync and the frame cap are disabled. Each case reloads the same seeded course,
advances gameplay by 1/60 second per rendered frame, warms up for 90 frames,
then measures 270 frames. These are short comparative desktop measurements,
not a guarantee for other devices. They include a tile transition.

Latest full native run (milliseconds unless otherwise indicated):

| Case | Median frame | p95 frame | Median draw calls | Median stamps |
|---|---:|---:|---:|---:|
| Original white-mask ribbons, individual scenery | 2.270 | 2.677 | 827 | 19 |
| Share one white mask | 2.189 | 2.545 | 819 | 19 |
| Disable tracks | 1.472 | 1.723 | 816 | 0 |
| Replace ribbons with elongated sled brushes | 2.746 | 3.492 | 826 | 42 |
| Disable shadows | 1.971 | 2.287 | 270 | 19 |
| Smooth analytical grooves only | 2.322 | 2.979 | 819 | 19 |
| Batch scenery only | 2.118 | 2.432 | 445 | 19 |
| Smooth grooves + batched scenery | 2.003 | 2.771 | 438 | 19 |

The combined change reduced median frame time by 12% in this run and median draw
calls by 47%. Frame timings vary between short runs; the draw-call reductions were
consistent. Shadows remain enabled.

## Findings and changes

- Each rider previously allocated an identical white texture. Texture identity
  determines stamp batching, so these separated otherwise identical draws.
  Median active stamp batches dropped from 11 to 4 with smooth grooves.
- Even a plain white mask invoked the textured shader branch: alpha lookup,
  four gradient samples, and eight dilation samples per fragment. Smooth mode
  uses the existing analytical capsule brush and no texture samples.
- Tread strips have square segment boundaries; turns can expose joins.
  Smooth grooves have rounded leading caps, like the continuous round brush.
  The actual sled uses elongated overlapping brushes, which also retain ski
  heading. It is not identical to the new capsule profile: replacing every
  rider with that brush increased stamps from 19 to 42 and surface CPU time
  from 0.095 ms to 0.342 ms in this comparison.
- Individual tree parts generated many draws, multiplied by shadow passes.
  Repeated scenery now uses MultiMeshes. Logical obstacles and collision/AI
  behavior stay separate; recycling updates the matching render instances.
- Narrow tracks now split segments within the shader's aspect limit rather
  than silently clamping their proportions. Ground checks also apply per field.

`DeformerTracks.Profile.TREAD` remains the default for existing vehicle users.
The ski scene selects `SMOOTH`; a blank texture is no longer required.
No shared shader, terrain quality, NPC count, or shadow setting was reduced.

## Validation

- `tests/track_profiles.gd`: tile-edge overlap, texture-free batching, narrow
  track aspect, airborne/landing/teleport history, and retained tread texture.
- `tests/ski_free_gameplay.gd`: gameplay, NPCs, pause, touch/layout behavior,
  and batched scenery relocation.
- Native rendered before/after screenshots inspected for scenery and grooves.

The benchmark uses wall-clock frame samples rather than the overlay's CPU
percentage. It does not isolate GPU execution time or establish the remaining
cost of each terrain render pass.
