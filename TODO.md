Here are the web-specific improvements I'd make, roughly in priority order.

## 1. Fix the thread dependency (likely a real bug on web)

`prepare_initial_noise_at()` relies on `Thread`, but the README recommends single-threaded web exports for phone compatibility. Without thread support, `Thread.start()` fails, the code does `push_error` and returns `false`, and every caller polls until it returns `true`. That means:

- `DemoSettings._process` never applies a surface update.
- `_recenter_fields` in the infinite demos never finishes a relocation.

Minimum fix is to guard on `OS.can_use_threads()` and fall back to time-sliced generation on the main thread:

```gdscript
if not OS.can_use_threads():
    return _prepare_noise_sliced(key, snapshot, resolution, origin)  # N rows per frame, ~2 ms budget
```

Refactor `_generate_initial_noise_image` into a stateful generator with a `step(budget_usec)` method that processes a few rows per call. The same code can then serve both the thread and no-thread paths.

## 2. Move the starting-noise generation to the GPU

The per-pixel GDScript loop is the biggest CPU cost: up to 514² samples × 2–3 `FastNoiseLite` calls, plus `Image.set_pixel`. It's slow even with threads, and very slow on single-threaded WASM. Options:

- **Best:** render the initial map in a shader into the existing SubViewport. Use a hash-based cellular or value noise keyed on world position, with analytic or finite-difference slopes. This removes the worker thread, the cache keys, the prefetch machinery, and the upload. Tile seams are free because the noise is a function of world position.
- **Cheaper:** pre-bake one tileable noise texture and sample it with a world-space offset in the refill and background pass.
- **If you keep the CPU path:** write into a `PackedByteArray` and use `Image.create_from_data`, and use `ImageTexture.update()` on an existing texture instead of allocating a new one per relocation.

## 3. Fix platform detection

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

- **3D resolution scale:** `canvas_items` stretch with `expand` renders 3D at full window pixels, which is heavy on high-DPI phones. Set `get_viewport().scaling_3d_scale` to 0.6–0.75 on tier 0, since the Compatibility renderer supports bilinear scaling.
- **Replace the 3×3 tile recycling with a single toroidal map.** Nine SubViewports mean nine render passes, nine refill passes, and nine noise generations. The README already lists this as unimplemented. One scrolling map would also remove most of the prefetch logic.
- **Stamp shader:** the textured path does four gradient samples plus eight dilation samples per fragment, and the quad includes the full berm margin (`outer_half_extent`), so overdraw is large. Shrink the quad when `berm_strength == 0`, and skip dilation on tier 0.
- **Refill pass:** it renders the full map every `refill_interval`. On low quality, raise the interval or refill in strips.
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

## 8. Weather particles

`CPUParticles3D` is the safe choice, but 900 + 120 flakes simulated in single-threaded WASM is noticeable. On tier 0, use roughly 200–300 flakes and `fixed_fps = 20`. `GPUParticles3D` also works in Compatibility on WebGL2 if you want to test it on your target devices.

## 9. Export and load size

- Exclude `tests/`, `.godot/`, and unused demos via export filters, and ship only what the web build needs.
- Serve with Brotli or gzip.
- Use a custom export template with unused modules disabled (for example 3D physics if you don't need it, but `RigidBody3D` and `AnimatableBody3D` are used in some demos).
- Keep the single-threaded export unless you control the COOP/COEP headers.

## 10. Verify the unverified assumptions

The README admits that `CLEAR_MODE_NEVER` persistence, the blend-based refill, and `amount_ratio` are untested on mobile browsers. I'd add a small startup self-test that stamps once, waits two frames, reads the map back, and falls back to a different strategy (for example ping-pong between two viewports) if the stamp vanished. The one-time readback cost is fine at startup.

If you tell me which of these matters most (phone Safari, Chrome Android, or single- vs multi-threaded export), I can write the time-sliced noise generator or the GPU noise shader.
