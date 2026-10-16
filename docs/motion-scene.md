# CPU Motion Scene

The opt-in `runtime/motion_scene` module keeps many visual objects in one
retained Canvas. This first CPU reference path supports rounded rectangles,
affine transforms, opacity, z-order, viewport clipping, stable application IDs,
and inverse-transform hit testing. It runs without a GPU or window.

```nim
import clay_board_style_system
import clay_board_style_system/runtime/[motion_scene, motion_scene_ui]

let initial = motionSceneSnapshot(size(320, 200), [
  motionRect(MotionObjectId(1), rect(20, 20, 80, 40), rgb(1, 0.3, 0.1),
    radius = 8),
  motionRect(MotionObjectId(2), rect(60, 40, 80, 40), rgb(0.1, 0.4, 1),
    opacity = 0.8, zIndex = 1)
])
let scene = newMotionScene(initial)
let ui = initUiRoot()
let view = ui.motionScene(scene,
  uiStyle([decl("width", px(320)), decl("height", px(200))]))

# Replace an entire visual frame, then invalidate only this Canvas's paint.
discard scene.replaceSnapshot(motionSceneSnapshot(size(320, 200), [
  motionRect(MotionObjectId(1), rect(30, 20, 80, 40), rgb(1, 0.3, 0.1), radius = 8)
]))
discard view.publish()
let hit = scene.hitTest(vec2(40, 30))
```

A scene creates no UI nodes per object. `motion_scene_ui` mounts its Canvas as
one ordinary layout participant. A scene may have multiple attachments; call
`publish` on each attachment after a change. Publishing unchanged content or a
disposed attachment is a no-op. Publication dirties only the owning node's
paint and never requests continuous frames. The application owns the UiRoot
lifetime, just as for ordinary Canvas handles.

Snapshots copy value-type objects and keep their storage private. Query methods
return value copies. IDs must be unique, nonzero `uint64` values and remain
application-controlled across replacement, reordering, and removal. A snapshot
accepts at most 65,536 objects; oversized input, invalid colors, negative sizes,
non-finite values, and overflowing transformed geometry fail before publication.
Colors and opacity must be in `[0, 1]`. Radius is clamped to half the shortest
side. Hidden, empty, fully transparent, and singular-transform objects retain
their identity but produce no pixels or hits.

Paint order is ascending z-index, with authoring order breaking ties. Picking
walks the same order backwards, respects rounded corners and the scene viewport,
and returns coordinates relative to the object's untransformed top-left corner.
`hitTestable = false` keeps an object visible while allowing hits to pass through.
Pass Canvas-local positions from RenderSurface input to `hitTest`; the scene does
not synthesize ordinary UI events or accessibility nodes for its objects.

`replaceSnapshot` applies synchronously and preserves the application's requested
frame order for deterministic rendering and export. Equal snapshot values keep
the Canvas revision unchanged. The display list belongs to the scene: the
`canvas` accessor is for mounting or paint conversion, not direct command edits.

For previews whose calculations may complete out of order, use update tokens:

```nim
let older = scene.beginUpdate()
let newer = scene.beginUpdate()
# Results are delivered back to the UI thread by the application's transport.
assert older.complete(initial) == msuStale
discard newer.cancel()
assert newer.complete(initial) == msuStale
```

Only the newest pending token can complete. Cancellation leaves the last
committed frame visible. A successful completion returns `msuApplied` or
`msuUnchanged` and consumes its token; a stale or cancelled token returns
`msuStale`. Direct replacement cancels a pending token too. Invalid active
completion leaves the request pending so the application can retry or cancel.

All scene mutation, token operations, mounting, and publication belong to the
UI thread. Snapshots are immutable values, but this module does not implement
cross-thread transfer or a worker queue; applications must use an appropriate
ownership-transfer mechanism when producing results elsewhere. Tokens retain
the scene until released and do not retain UI nodes.

## GPU rectangle batches

Import `runtime/motion_scene_gpu` explicitly to pack the drawable rounded
rectangles of a snapshot into five-vec4 GPU instance records:

```nim
import clay_board_style_system/runtime/motion_scene_gpu

let batch = newGpuMotionRectBatch()
discard batch.sync(host, resources, scene) # Before beginGpuFrame.
let material = host.newGpuMotionRectMaterial(
  resources, vertexArtifact, fragmentArtifact)
let frame = host.beginGpuFrame()
discard material.submit(batch, pass)
host.endGpuFrame(frame)
# After the final frame, while the host remains open:
batch.release()
material.release()
```

The records follow the CPU's z-index and authoring order, omit hidden and
degenerate objects, combine the authored bounds with each affine transform,
and preserve color alpha times object opacity. Compile
`gpuMotionRectVertexSource()` and `gpuMotionRectFragmentSource()` into the
`vertexArtifact` and `fragmentArtifact` for the selected backend. The material
owns those shaders, its instanced pipeline, and a four-corner unit quad. The
application supplies a graphics `pass` with viewport and scissor set to the
snapshot's viewport and owns its frame and render target. `submit` returns
`false` for an empty batch and submits no pass, so clearing an empty scene is
the application's responsibility. The same shader pair is compiled for OpenGL
and Vulkan, and the OpenGL pixel fixture compares its output with CPU Motion
Scene rendering.

`GpuMotionRectBatch.sync` follows the scene revision, skips unchanged frames,
updates only contiguous changed instance records, and recreates the buffer when
the drawable count exceeds its capacity. It keeps the prior CPU record cache if
an update fails, so the next sync retries the affected records. Sync and release
belong outside an active GPU frame. Release the batch before changing its host
or namespace; the application still owns shader compilation, material lifetime,
and frame submission. A material can also submit a static `GpuInstanceBinding`.
GPU execution for other scene primitives remains a follow-up.

For an ordinary UI Canvas attachment, `motion_scene_gpu_canvas` owns the
material, batch, and GPU readback surface together. The UI wrapper queues a
frame only when the scene revision changes:

```nim
import clay_board_style_system/runtime/[gpu_canvas, motion_scene_gpu_canvas,
  motion_scene_gpu_canvas_ui]

let renderer = host.newGpuMotionSceneCanvas(resources, scene,
  defaultGpuCanvasConfig(320, 200), vertexArtifact, fragmentArtifact)
let gpuView = ui.gpuMotionScene(renderer)
discard gpuView.publish()          # Queue the current scene revision.
# In the UI loop, collect completed readbacks and publish changed revisions.
discard gpuView.collectGpuFrame()
# After draining pending readbacks, release the renderer before closing host.
discard renderer.close()
```

The scene viewport must match the canvas dimensions, and this path uses
straight RGBA8 pixels. `publish` submits one instanced rectangle draw, or a
clear-only pass when no rectangles remain. It cancels an obsolete queued
readback and applies backpressure when the ring is full; `collectGpuFrame`
retries the newest revision once a slot becomes available. Collection
invalidates only the attached Canvas paint. No continuous frame loop is
started. Compile the built-in shader artifacts for the selected backend before
constructing the renderer. The CPU Motion Scene attachment remains available
for hosts without compatible GPU support.

On a host that supports direct render-target presentation, the Motion Scene can
also stay on the GPU through UI composition:

```nim
import clay_board_style_system/runtime/[gpu_direct_surface,
  motion_scene_gpu_direct, motion_scene_gpu_direct_ui]

let renderer = host.newGpuMotionSceneDirect(resources, scene,
  defaultGpuDirectSurfaceConfig(320, 200), vertexArtifact, fragmentArtifact)
let gpuView = ui.gpuMotionSceneDirect(renderer)
discard gpuView.publish()
discard gpuView.collectGpuFrame() # Invalidates paint when the frame completes.
discard renderer.close()
```

This path requires straight RGBA8 and direct render-target presentation. It
owns one target per presentation buffer and never redraws a target while the
surface retains it. A full ring applies backpressure; `collectGpuFrame` retries
the latest scene revision when a target becomes free. Outstanding presentation
leases must be released before closing the renderer. Unlike the GPU Canvas
path, normal presentation does not copy pixels back to the CPU.

## Typed timelines

Import `runtime/motion_scene_timeline` to animate a whole batch through the
existing `AnimationClock`, numeric keyframe interpolation, and `FrameScheduler`.
Each timeline has one clock track, irrespective of its object count. The
application supplies the same monotonic timestamps it uses for UI motion; the
module starts no timer, thread, or separate frame loop.

```nim
import clay_board_style_system/runtime/[motion_scene_timeline,
  motion_scene_timeline_ui]

let timeline = newMotionTimeline(scene, [
  motionTrack(MotionObjectId(1), mspX, [
    FloatKeyframe(offset: 0, value: 30),
    FloatKeyframe(offset: 1, value: 180)
  ])
], durationSeconds = 2, nowSeconds = 10, timing = easeInOutTiming())

var scheduler = initFrameScheduler()
# In a UI loop, clear consumed deadlines once, then advance all producers.
discard timeline.advance(view, scheduler, nowSeconds = 11)
# Headless callers use timeline.advance(scheduler, nowSeconds) instead.
```

With either GPU Canvas or GPU direct attachment, import
`runtime/motion_scene_timeline_gpu_ui` and pass its `gpuView`. In each UI-loop
wake-up, clear the consumed deadline, then sample and collect using the same
monotonic time:

```nim
import clay_board_style_system/runtime/motion_scene_timeline_gpu_ui

scheduler.clearDeadline()
discard timeline.advance(gpuView, scheduler, nowSeconds)
discard gpuView.collectGpuFrame(scheduler, nowSeconds)
```

The GPU overloads keep the timeline's next sample deadline in the shared
`FrameScheduler`. Canvas requests a bounded poll while readback is pending;
direct presentation polls while a frame is pending or the newest revision is
blocked by a retained presentation target. Sampling can queue a GPU frame
without dirtying UI paint. Only a completed frame marks `ddPaint` and
invalidates its attachment node. Once the timeline finishes and its final
frame is collected, it requests no further wake-up. The application still
owns its UI loop and GPU host.

Tracks address existing stable IDs and set absolute `mspX`, `mspY`, `mspWidth`,
`mspHeight`, `mspOpacity`, `mspRadius`, `mspTranslateX`, or `mspTranslateY` values.
Translation tracks change the affine transform's translation components while
preserving its linear components. Unanimated properties come from the snapshot
captured at construction. Keyframes are copied, offsets must be ordered in
`[0, 1]`, values must fit finite float32, dimensions must be nonnegative, and
opacity must stay in `[0, 1]`. Scene validation and radius clamping still apply
at every sampled frame. Duplicate object/property pairs and unknown IDs fail
before any scene changes. A timeline accepts at most 65,536 tracks, 1,024 stops
per track, and 262,144 stops in total.

Timing options use the ordinary motion types: `timing`, `delaySeconds`,
`direction`, and `fillMode`. `iterations` is a positive integer capped at
1,000,000. The default is one forward iteration with forwards fill. With no
forwards fill, completion restores the captured base snapshot. Finite timestamps
are required; backwards timestamps clamp to the last supplied time. Unchanged
samples do not dirty paint. Active motion contributes its next deadline without
overwriting another producer's earlier deadline; delayed motion sleeps until its
start. Finished, paused, and cancelled timelines contribute no new deadlines.

`pause(nowSeconds)` samples the pause point before freezing. `resume(nowSeconds)`
excludes the paused interval. `cancel()` freezes the last committed frame;
`cancel(restoreBase = true)` restores the captured base only while the timeline
still owns the scene. After directly pausing or restoring, publish attachments
(or call the UI `advance` overload) to expose any changed revision. Setting
`reducedMotion = true`, or calling `setReducedMotion(true)`, makes nonessential
motion finish on its next eligible sample; `essentialMotion = true` keeps it
running. This follows the existing AnimationClock policy, including delays.

A timeline owns publication only while the scene still has its expected
snapshot. An external replacement cancels it at the next advance or resume, so
an old timeline cannot overwrite newer content. Use one active timeline per
scene. Timeline writes also cancel pending preview tokens. Invalid sampled
geometry cancels the timeline, raises `ValueError`, and preserves the last
committed frame. The UI overload checks the scene/view pairing and cancels when
the attachment is disposed. All timeline operations belong to the UI thread.

Paths/text/images as scene objects, nested effect groups, color and arbitrary
matrix tracks, seeking/reversing an existing timeline, and C ABI
authoring remain follow-ups. `examples/motion_scene_demo.nim` renders a
deterministically sampled timeline to PPM for headless inspection.
