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
matrix tracks, seeking/reversing an existing timeline, GPU batching, and C ABI
authoring remain follow-ups. `examples/motion_scene_demo.nim` renders a
deterministically sampled timeline to PPM for headless inspection.
