Here are the web-specific improvements I'd make, roughly in priority order.

## ~~1. Fix the thread dependency (likely a real bug on web)~~

The custom `FastNoiseLite` CPU fallback checks the `nothreads` feature tag and advances a shared stateful noise generator in short slices. Worker builds use that same generator off the main thread.

## ~~2. Move the starting-noise generation to the GPU~~

The built-in starting profile now renders world-space value noise and finite-difference slopes in the SubViewport background and recovery shaders. Recycled tiles share the same continuous world pattern without CPU preparation or texture uploads. Custom `FastNoiseLite` resources retain the optimized CPU fallback (`PackedByteArray`, `Image.create_from_data`, and reusable `ImageTexture` buffers).

## ~~3. Fix platform detection~~

`JavaScriptBridge.eval` with a user-agent regex has two problems. It can be blocked by CSP in embedded pages, and iPadOS reports a Mac user agent, so iPads get Medium. Godot 4 has feature tags for this:

```gdscript
static func platform_tier() -> int:
	if OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile"):
		return 0
	if OS.has_feature("web"):
		return 1
	return 2
```

## 4. Reduce fill and render cost

- ~~**3D resolution scale:** `canvas_items` stretch with `expand` renders 3D at full window pixels, which is heavy on high-DPI phones. Set `get_viewport().scaling_3d_scale` to 0.6–0.75 on tier 0, since the Compatibility renderer supports bilinear scaling.~~
- **Replace the 3×3 tile recycling with a single toroidal map.** Nine SubViewports mean nine render passes, nine refill passes, and nine noise generations. The README already lists this as unimplemented. One scrolling map would also remove most of the prefetch logic.
- ~~**Stamp shader:** the textured path does four gradient samples plus eight dilation samples per fragment, and the quad includes the full berm margin (`outer_half_extent`), so overdraw is large. Shrink the quad when `berm_strength == 0`, and skip dilation on tier 0.~~
- ~~**Refill pass:** it renders the full map every `refill_interval`. On low quality, raise the interval or refill in strips.~~
- **Sparkle:** on tier 0, compile a shader variant without it. A runtime `if` on a uniform still costs registers on mobile GPUs.

## 5. Precision issues on mobile GPUs

Many phone GPUs use mediump for fragment float math in WebGL2. In the surface shader, `hash12(floor(world_pos.xz * density))` and the `world_noise` bevel lookups degrade at large world coordinates, which matters in the infinite demos. Subtract the surface origin before hashing, or hash in tile-local coordinates. Explicit `highp` is also worth adding where it matters.

## 6. Avoid first-use hitches

The Compatibility renderer compiles shaders on first draw, so the first footstep, puff, or tread stamp stutters. Warm up at load by drawing one stamp of each type (round, capsule, textured, track) and bursting one puff per pool entry, hidden behind a loading screen. Also, `change_scene_to_file` in the launcher is a synchronous load, so show a "Loading…" label first. Use `ResourceLoader.load_threaded_request` and it will still degrade gracefully when threads are unavailable.

## 7. Per-frame allocations

- `_dirty_deformers.values()` allocates an array every frame.
- Each pending stamp is a `Dictionary`, so use parallel packed arrays or a small `RefCounted` class.
- `set_quality` compares two `to_dictionary()` results.
- `DemoFps` calls `RenderingServer.viewport_set_measure_render_time` and reads GPU time, which isn't available on web. Disable it there, or make it opt-in.

Web builds run in a GC'd single-threaded WASM heap, so avoiding these allocations reduces frame spikes.

## ~~8. Weather particles~~

Tier-0 devices cap CPU snowfall at 250 main flakes plus 50 near-camera flakes and simulate them at `fixed_fps = 20`. Other tiers retain the configured counts and 30 FPS simulation.

## 9. Export and load size

- Exclude `tests/`, `.godot/`, and unused demos via export filters, and ship only what the web build needs.
- Serve with Brotli or gzip.
- Use a custom export template with unused modules disabled (for example 3D physics if you don't need it, but `RigidBody3D` and `AnimatableBody3D` are used in some demos).
- Keep the single-threaded export unless you control the COOP/COEP headers.

## 10. Verify the unverified assumptions

The README admits that `CLEAR_MODE_NEVER` persistence, the blend-based refill, and `amount_ratio` are untested on mobile browsers. I'd add a small startup self-test that stamps once, waits two frames, reads the map back, and falls back to a different strategy (for example ping-pong between two viewports) if the stamp vanished. The one-time readback cost is fine at startup.

The time-sliced CPU generator and its packed-byte texture upload are implemented. A world-space GPU shader remains the next step; it should preserve support for custom `FastNoiseLite` resources.
