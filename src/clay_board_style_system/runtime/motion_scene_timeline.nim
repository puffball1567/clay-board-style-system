## Typed CPU scene tracks driven by the existing AnimationClock and shared
## FrameScheduler. All operations run on the UI thread using its monotonic time.
import std/[math, options, sets, tables]

import ../core/computed_style
import ./[animation_clock, frame_scheduler, invalidation, motion_scene]

const
  maxMotionTimelineTracks* = 65_536
  maxMotionTrackKeyframes* = 1024
  maxMotionTimelineKeyframes* = 262_144
  maxMotionTimelineIterations* = 1_000_000

type
  MotionSceneProperty* = enum
    mspX, mspY, mspWidth, mspHeight, mspOpacity, mspRadius,
    mspTranslateX, mspTranslateY

  MotionFloatTrack* = object
    target: MotionObjectId
    property: MotionSceneProperty
    frames: FloatKeyframes

  MotionTimelineState* = enum
    mtsRunning, mtsPaused, mtsFinished, mtsCancelled

  MotionTimelineSample = ref object
    value: Option[AnimationSample]

  BoundMotionTrack = object
    index: int
    track: MotionFloatTrack

  MotionTimeline* = ref object
    target: MotionScene
    base, expected: MotionSceneSnapshot
    tracks: seq[BoundMotionTrack]
    clock: AnimationClock
    animation: AnimationId
    sample: MotionTimelineSample
    fillMode: AnimationFillMode
    status: MotionTimelineState
    lastTime: float64

proc finite(value: float64): bool =
  value.classify notin {fcNan, fcInf, fcNegInf}

proc motionTrack*(
    target: MotionObjectId; property: MotionSceneProperty;
    keyframes: openArray[FloatKeyframe]
): MotionFloatTrack =
  if uint64(target) == 0:
    raise newException(ValueError, "motion track target must be nonzero")
  if keyframes.len == 0 or keyframes.len > maxMotionTrackKeyframes:
    raise newException(ValueError, "motion track keyframe count is outside the limit")
  for keyframe in keyframes:
    if not keyframe.value.finite or abs(keyframe.value) > 3.4028234663852886e38:
      raise newException(ValueError, "motion track values must fit finite float32")
    case property
    of mspWidth, mspHeight, mspRadius:
      if keyframe.value < 0:
        raise newException(ValueError, "motion track dimensions must be non-negative")
    of mspOpacity:
      if keyframe.value < 0 or keyframe.value > 1:
        raise newException(ValueError, "motion track opacity must be in the unit interval")
    else: discard
  MotionFloatTrack(target: target, property: property,
    frames: floatKeyframes(keyframes))

proc newMotionTimeline*(
    scene: MotionScene; tracks: openArray[MotionFloatTrack];
    durationSeconds, nowSeconds: float64;
    delaySeconds = 0.0; iterations = 1; direction = adNormal;
    fillMode = afForwards; timing = linearTiming();
    reducedMotion = false; essentialMotion = false;
    targetFramesPerSecond = 60.0
): MotionTimeline =
  if scene.isNil:
    raise newException(ValueError, "motion timeline scene must not be nil")
  if tracks.len == 0 or tracks.len > maxMotionTimelineTracks:
    raise newException(ValueError, "motion timeline track count is outside the limit")
  if iterations <= 0 or iterations > maxMotionTimelineIterations:
    raise newException(ValueError, "motion timeline iterations are outside the limit")
  if not nowSeconds.finite or
      not (nowSeconds + delaySeconds).finite or
      not (nowSeconds + delaySeconds + durationSeconds * iterations.float64).finite:
    raise newException(ValueError, "motion timeline time range must be finite")
  for value in [timing.x1, timing.y1, timing.x2, timing.y2]:
    if not value.finite:
      raise newException(ValueError, "motion timeline timing must be finite")
  if timing.kind == tfCubicBezier:
    discard cubicBezierTiming(timing.x1, timing.y1, timing.x2, timing.y2)
  let sample = MotionTimelineSample()
  let spec = animationSpec(durationSeconds, delaySeconds,
    iterations = some(iterations.float64), direction = direction,
    fillMode = fillMode, timing = timing, essentialMotion = essentialMotion,
    onSample = proc(value: AnimationSample) = sample.value = some(value))
  let base = scene.snapshot
  var indices = initTable[uint64, int]()
  for index in 0 ..< base.objectCount:
    indices[uint64(base.objectAt(index).get.id)] = index
  var seen = initHashSet[tuple[id: uint64, property: MotionSceneProperty]]()
  var bound: seq[BoundMotionTrack]
  var count = 0
  for track in tracks:
    let key = (id: uint64(track.target), property: track.property)
    if key.id notin indices or key in seen:
      raise newException(ValueError, "motion track target is missing or property is duplicated")
    seen.incl key
    count += track.frames.values.len
    if count > maxMotionTimelineKeyframes:
      raise newException(ValueError, "motion timeline keyframe budget exceeded")
    # Revalidate default-constructed values, and own a copy of every stop.
    let copied = motionTrack(track.target, track.property, track.frames.values)
    bound.add BoundMotionTrack(index: indices.getOrDefault(key.id), track: copied)
  result = MotionTimeline(target: scene, base: base, expected: base,
    tracks: bound, clock: initAnimationClock(targetFramesPerSecond),
    sample: sample, fillMode: fillMode, status: mtsRunning, lastTime: nowSeconds)
  result.clock.reducedMotion = reducedMotion
  result.animation = result.clock.startAnimation(spec, nowSeconds)

proc scene*(timeline: MotionTimeline): MotionScene =
  if timeline.isNil: nil else: timeline.target

proc state*(timeline: MotionTimeline): MotionTimelineState =
  if timeline.isNil: mtsCancelled else: timeline.status

proc checkedTime(timeline: MotionTimeline; nowSeconds: float64): float64 =
  if timeline.isNil or not nowSeconds.finite:
    raise newException(ValueError, "timeline and finite monotonic time are required")
  result = max(timeline.lastTime, nowSeconds)
  timeline.lastTime = result

proc cancel*(timeline: MotionTimeline; restoreBase = false): bool {.discardable.} =
  if timeline.isNil or timeline.status notin {mtsRunning, mtsPaused}:
    return false
  discard timeline.clock.cancelAnimation(timeline.animation)
  timeline.status = mtsCancelled
  if restoreBase and timeline.target.snapshot == timeline.expected:
    discard timeline.target.replaceSnapshot(timeline.base)
    timeline.expected = timeline.target.snapshot
  true

proc setReducedMotion*(timeline: MotionTimeline; enabled: bool) =
  if timeline.isNil:
    raise newException(ValueError, "motion timeline must not be nil")
  timeline.clock.reducedMotion = enabled

proc apply(value: var MotionObject; property: MotionSceneProperty; sample: float32) =
  case property
  of mspX: value.bounds.x = sample
  of mspY: value.bounds.y = sample
  of mspWidth: value.bounds.w = sample
  of mspHeight: value.bounds.h = sample
  of mspOpacity: value.opacity = sample
  of mspRadius: value.radius = sample
  of mspTranslateX: value.transform.tx = sample
  of mspTranslateY: value.transform.ty = sample

proc sampledSnapshot(timeline: MotionTimeline; progress: float64): MotionSceneSnapshot =
  var objects = newSeq[MotionObject](timeline.base.objectCount)
  for index in 0 ..< objects.len:
    objects[index] = timeline.base.objectAt(index).get
  for bound in timeline.tracks:
    objects[bound.index].apply(bound.track.property,
      float32(bound.track.frames.sample(progress)))
  motionSceneSnapshot(timeline.base.viewportSize, objects)

proc advance*(
    timeline: MotionTimeline; scheduler: var FrameScheduler; nowSeconds: float64
): bool {.discardable.} =
  ## Merge this timeline's deadline and effective paint dirt into the event loop.
  ## The caller clears consumed deadlines before advancing all motion producers.
  let now = timeline.checkedTime(nowSeconds)
  if timeline.status notin {mtsRunning, mtsPaused}: return false
  if timeline.target.snapshot != timeline.expected:
    discard timeline.cancel()
    return false
  if timeline.status == mtsPaused: return false
  var local = initFrameScheduler()
  timeline.sample.value = none(AnimationSample)
  discard timeline.clock.tickAnimations(local, now)
  try:
    if timeline.sample.value.isSome:
      let sample = timeline.sample.value.get
      let next =
        if sample.phase == apAfter and timeline.fillMode notin {afForwards, afBoth}:
          timeline.base
        else:
          timeline.sampledSnapshot(sample.progress)
      result = timeline.target.replaceSnapshot(next)
      timeline.expected = timeline.target.snapshot
  except CatchableError:
    discard timeline.cancel()
    raise
  if not timeline.clock.hasAnimation(timeline.animation):
    timeline.status = mtsFinished
  if result: scheduler.markDirty(ddPaint)
  if local.nextDeadline.isSome: scheduler.requestDeadline(local.nextDeadline.get)

proc pause*(timeline: MotionTimeline; nowSeconds: float64): bool {.discardable.} =
  ## Samples the pause point first; publish the scene if this changes its revision.
  var scheduler = initFrameScheduler()
  discard timeline.advance(scheduler, nowSeconds)
  if timeline.status != mtsRunning: return false
  result = timeline.clock.pauseAnimation(timeline.animation, timeline.lastTime)
  if result: timeline.status = mtsPaused

proc resume*(timeline: MotionTimeline; nowSeconds: float64): bool {.discardable.} =
  let now = timeline.checkedTime(nowSeconds)
  if timeline.status != mtsPaused: return false
  if timeline.target.snapshot != timeline.expected:
    discard timeline.cancel()
    return false
  result = timeline.clock.resumeAnimation(timeline.animation, now)
  if result: timeline.status = mtsRunning
