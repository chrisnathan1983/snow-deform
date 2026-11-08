# Threaded ResourceLoader leak investigation

## Summary

The `ObjectDB` leak warning seen when running `tests/demo_loading.gd` is reproducible with Godot 4.7.2's threaded `ResourceLoader`. A minimal probe that threaded-loads `res://demos/playground.tscn` reproduces leaked `RefCounted` objects. The same probe using a synchronous `load()` exits without the warning.

The evidence points to Godot's threaded resource loading and nested script preloads, rather than leaked snow deformation nodes or stamp renderer resources. No project workaround was retained as part of this investigation.

## What was tested

- The complete `demo_loading.gd` run emitted an ObjectDB leak warning, with the count varying between runs.
- Threading only the `playground.tscn` load reproduced the warning.
- A minimal standalone probe that called `ResourceLoader.load_threaded_request()` and collected the result with `load_threaded_get()` also reproduced it. The observed count varied around 10–11 leaked `RefCounted` objects.
- Replacing the probe's threaded request with `load()` produced no ObjectDB warning.
- Setting `DemoLoader.use_threads = false` also made the demo loading run exit without the warning.
- Waiting additional frames after the load did not clear the leak. Explicitly releasing the loaded `PackedScene` reference did not clear it either.
- Temporary instance-ID tracing did not match the reported leaked IDs to `DeformableSurface` or `StampBatchRenderer` instances.

The precise count is not a reliable project metric: it depends on the resources reached through the threaded scene load and varied between runs. The important control was that the threaded path warned while the synchronous path did not.

## Likely engine-level cause

Godot issue [#120661](https://github.com/godotengine/godot/issues/120661) describes the same `RefCounted`/`LoadToken` leak. Although its original title refers to `use_sub_threads = true`, later reports reproduce it in pure GDScript with the default `use_sub_threads = false` on Godot 4.7.2.

The reported trigger is a scene loaded in the background whose scripts `preload()` resources that are not already cached. Those nested loads can schedule worker-pool tasks. In the reported failure path, a `LoadToken`'s reference count reaches zero but the token is not deleted. That explanation fits this project's result: threaded scene loading warns, while synchronous loading does not. This is a match to the upstream report, not an independent inspection of Godot's C++ runtime.

As checked on 2026-11-08, the issue is open and assigned to the Godot 4.8 milestone. The proposed fix is [PR #121025](https://github.com/godotengine/godot/pull/121025), which is also open and has not yet been verified against this project.

## Workaround

For a local check, set `DemoLoader.use_threads = false` before opening demos. This bypasses the threaded request and uses synchronous `load()`, which removed the warning in the reproduction. It also means the loading screen cannot hide the resource load time as effectively.

The long-term fix belongs in Godot. Recheck this project with an engine build containing the upstream fix, then restore threaded loading and rerun `tests/demo_loading.gd`. Avoid treating additional frame waits or manual scene-reference release as a fix; neither resolved the warning in the reproduction.

## Reproduction outline

From the project root, run the demo-loading SceneTree test with Godot 4.7.2 in headless mode. For a narrow control, create a temporary SceneTree script that:

1. Calls `ResourceLoader.load_threaded_request("res://demos/playground.tscn")`.
2. Awaits frames while `load_threaded_get_status()` is `THREAD_LOAD_IN_PROGRESS`.
3. Calls `ResourceLoader.load_threaded_get()` and exits after a few frames.
4. Repeats with `ResourceLoader.load()` instead; the synchronous control should not report the same leak.

The temporary probe used during this investigation has been removed from the repository.
