## FrameScheduler integration without installing a second frame loop or clock.
import ./[frame_scheduler, invalidation, motion_scene_timeline, motion_scene_ui]

proc advance*(
    timeline: MotionTimeline; view: MotionSceneHandle;
    scheduler: var FrameScheduler; nowSeconds: float64
): bool {.discardable.} =
  if timeline.isNil or view.isNil or timeline.scene != view.scene:
    raise newException(ValueError, "timeline and view must refer to the same scene")
  if not view.valid:
    discard timeline.cancel()
    return false
  discard timeline.advance(scheduler, nowSeconds)
  result = view.publish()
  if result: scheduler.markDirty(ddPaint)
