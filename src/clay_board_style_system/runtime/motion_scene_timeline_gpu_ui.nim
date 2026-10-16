## Motion Timeline deadlines and GPU Canvas completion share one UI scheduler.
import std/[math, options]

import ./[frame_scheduler, gpu_canvas, gpu_direct_surface, invalidation,
  motion_scene_gpu_canvas,
  motion_scene_gpu_canvas_ui, motion_scene_gpu_direct,
  motion_scene_gpu_direct_ui, motion_scene_timeline]

const gpuMotionReadbackPollSeconds* = 1.0 / 60.0
const gpuMotionDirectPollSeconds* = 1.0 / 60.0

proc requireFiniteTime(nowSeconds: float64) =
  if nowSeconds.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "finite monotonic time is required")

proc requestReadbackPoll(
    view: GpuMotionSceneHandle; scheduler: var FrameScheduler;
    nowSeconds: float64
) =
  if view.renderer.canvas().pendingFrameCount() > 0:
    let next = nowSeconds + gpuMotionReadbackPollSeconds
    scheduler.requestDeadline(
      if next.classify in {fcInf, fcNegInf}: nowSeconds else: next)

proc requestDirectPoll(
    view: GpuMotionSceneDirectHandle; scheduler: var FrameScheduler;
    nowSeconds: float64
) =
  if view.renderer.surface().pendingFrameCount() > 0 or
      view.renderer.hasUnqueuedRevision():
    let next = nowSeconds + gpuMotionDirectPollSeconds
    scheduler.requestDeadline(
      if next.classify in {fcInf, fcNegInf}: nowSeconds else: next)

proc advance*(
    timeline: MotionTimeline; view: GpuMotionSceneHandle;
    scheduler: var FrameScheduler; nowSeconds: float64
): bool {.discardable.} =
  ## Sample the timeline and queue its newest GPU revision. Paint is marked
  ## dirty only when collectGpuFrame publishes completed pixels.
  if timeline.isNil or view.isNil or timeline.scene != view.renderer.scene:
    raise newException(ValueError, "timeline and GPU view must refer to the same scene")
  if not view.valid:
    discard timeline.cancel()
    return false
  var local = initFrameScheduler()
  discard timeline.advance(local, nowSeconds)
  result = view.publish()
  if local.nextDeadline.isSome:
    scheduler.requestDeadline(local.nextDeadline.get)
  view.requestReadbackPoll(scheduler, nowSeconds)

proc collectGpuFrame*(
    view: GpuMotionSceneHandle; scheduler: var FrameScheduler;
    nowSeconds: float64
): bool {.discardable.} =
  ## Poll without a second frame loop. A pending readback requests another
  ## bounded wake-up; an idle scene leaves the scheduler asleep.
  nowSeconds.requireFiniteTime()
  if not view.valid:
    return false
  result = view.collectGpuFrame()
  if result:
    scheduler.markDirty(ddPaint)
  view.requestReadbackPoll(scheduler, nowSeconds)

proc advance*(
    timeline: MotionTimeline; view: GpuMotionSceneDirectHandle;
    scheduler: var FrameScheduler; nowSeconds: float64
): bool {.discardable.} =
  ## Queue sampled revisions without dirtying UI paint before presentation.
  if timeline.isNil or view.isNil or timeline.scene != view.renderer.scene:
    raise newException(ValueError, "timeline and GPU view must refer to the same scene")
  if not view.valid:
    discard timeline.cancel()
    return false
  var local = initFrameScheduler()
  discard timeline.advance(local, nowSeconds)
  result = view.publish()
  if local.nextDeadline.isSome:
    scheduler.requestDeadline(local.nextDeadline.get)
  view.requestDirectPoll(scheduler, nowSeconds)

proc collectGpuFrame*(
    view: GpuMotionSceneDirectHandle; scheduler: var FrameScheduler;
    nowSeconds: float64
): bool {.discardable.} =
  ## Keep polling until both presentation and any backpressured revision drain.
  nowSeconds.requireFiniteTime()
  if not view.valid:
    return false
  result = view.collectGpuFrame()
  if result:
    scheduler.markDirty(ddPaint)
  view.requestDirectPoll(scheduler, nowSeconds)
