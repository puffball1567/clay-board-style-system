## Typed CPU scene tracks driven by the existing AnimationClock and shared
## FrameScheduler. All operations run on the UI thread using its monotonic time.
import std/[math, options, sets, tables]

import ../core/computed_style
import ../core/raster_surface
import ./[animation_clock, frame_scheduler, invalidation, motion_scene]

const
  maxMotionTimelineTracks* = 65_536
  maxMotionTrackKeyframes* = 1024
  maxMotionTimelineKeyframes* = 262_144
  maxMotionTimelineIterations* = 1_000_000
  motionTimelineFullTurn = PI.float32 * 2.0'f32

type
  MotionSceneProperty* = enum
    mspX, mspY, mspWidth, mspHeight, mspOpacity, mspRadius,
    mspTranslateX, mspTranslateY,
    mspColorR, mspColorG, mspColorB, mspColorA,
    mspStartAngle, mspSweepAngle

  MotionFloatTrack* = object
    target: MotionObjectId
    property: MotionSceneProperty
    frames: FloatKeyframes

  MotionSpriteKeyframe* = object
    offset*: float64
    sourceRegion*: RasterRegion

  MotionSpriteTrack* = object
    target: MotionObjectId
    frames: seq[MotionSpriteKeyframe]

  MotionTimelineState* = enum
    mtsRunning, mtsPaused, mtsFinished, mtsCancelled

  MotionTimelineSample = ref object
    value: Option[AnimationSample]

  BoundMotionTrack = object
    index: int
    track: MotionFloatTrack

  BoundSpriteTrack = object
    index: int
    track: MotionSpriteTrack

  MotionTimeline* = ref object
    target: MotionScene
    base, expected: MotionSceneSnapshot
    tracks: seq[BoundMotionTrack]
    spriteTracks: seq[BoundSpriteTrack]
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
    of mspOpacity, mspColorR, mspColorG, mspColorB, mspColorA:
      if keyframe.value < 0 or keyframe.value > 1:
        raise newException(ValueError,
          "motion track opacity and color must be in the unit interval")
    of mspSweepAngle:
      if keyframe.value <= 0 or
          keyframe.value > motionTimelineFullTurn.float64:
        raise newException(ValueError,
          "motion sector sweep track must be in (0, 2π]")
    else: discard
  MotionFloatTrack(target: target, property: property,
    frames: floatKeyframes(keyframes))

proc motionSpriteTrack*(
    target: MotionObjectId; keyframes: openArray[MotionSpriteKeyframe]
): MotionSpriteTrack =
  ## Source regions change at their authored offsets; the last region holds.
  if uint64(target) == 0 or keyframes.len == 0 or
      keyframes.len > maxMotionTrackKeyframes:
    raise newException(ValueError,
      "motion sprite track target or keyframe count is invalid")
  var previous = -1.0
  for frame in keyframes:
    if not frame.offset.finite or frame.offset < 0 or frame.offset > 1 or
        frame.offset <= previous or
        frame.sourceRegion.x < 0 or frame.sourceRegion.y < 0 or
        frame.sourceRegion.width <= 0 or frame.sourceRegion.height <= 0:
      raise newException(ValueError,
        "motion sprite frames must have ordered offsets and positive regions")
    previous = frame.offset
  if keyframes[0].offset != 0:
    raise newException(ValueError,
      "motion sprite frames must start at offset zero")
  result = MotionSpriteTrack(target: target,
    frames: newSeq[MotionSpriteKeyframe](keyframes.len))
  for index, frame in keyframes:
    result.frames[index] = frame

proc newMotionTimeline*(
    scene: MotionScene; tracks: openArray[MotionFloatTrack];
    durationSeconds, nowSeconds: float64;
    delaySeconds = 0.0; iterations = 1; direction = adNormal;
    fillMode = afForwards; timing = linearTiming();
    reducedMotion = false; essentialMotion = false;
    targetFramesPerSecond = 60.0;
    spriteTracks: openArray[MotionSpriteTrack] = []
): MotionTimeline =
  if scene.isNil:
    raise newException(ValueError, "motion timeline scene must not be nil")
  if tracks.len + spriteTracks.len == 0 or
      tracks.len + spriteTracks.len > maxMotionTimelineTracks:
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
  var boundSprites: seq[BoundSpriteTrack]
  var seenSprites = initHashSet[uint64]()
  var count = 0
  for track in tracks:
    let key = (id: uint64(track.target), property: track.property)
    if key.id notin indices or key in seen:
      raise newException(ValueError, "motion track target is missing or property is duplicated")
    if track.property in {mspStartAngle, mspSweepAngle} and
        base.objectAt(indices.getOrDefault(key.id)).get.shape notin
          {msSector, msAnnularSector}:
      raise newException(ValueError,
        "motion angle tracks require a sector or annular sector")
    seen.incl key
    count += track.frames.values.len
    if count > maxMotionTimelineKeyframes:
      raise newException(ValueError, "motion timeline keyframe budget exceeded")
    # Revalidate default-constructed values, and own a copy of every stop.
    let copied = motionTrack(track.target, track.property, track.frames.values)
    bound.add BoundMotionTrack(index: indices.getOrDefault(key.id), track: copied)
  for track in spriteTracks:
    let id = uint64(track.target)
    if id notin indices or id in seenSprites:
      raise newException(ValueError,
        "motion sprite target is missing or duplicated")
    seenSprites.incl id
    let copied = motionSpriteTrack(track.target, track.frames)
    count += copied.frames.len
    if count > maxMotionTimelineKeyframes:
      raise newException(ValueError, "motion timeline keyframe budget exceeded")
    let index = indices.getOrDefault(id)
    let targetObject = base.objectAt(index).get
    if targetObject.shape != msImage or targetObject.image.isNil:
      raise newException(ValueError,
        "motion sprite tracks require image objects")
    for frame in copied.frames:
      let region = frame.sourceRegion
      if region.width > targetObject.image.width or
          region.height > targetObject.image.height or
          region.x > targetObject.image.width - region.width or
          region.y > targetObject.image.height - region.height:
        raise newException(ValueError,
          "motion sprite frame is outside its image atlas")
    boundSprites.add BoundSpriteTrack(index: index, track: copied)
  result = MotionTimeline(target: scene, base: base, expected: base,
    tracks: bound, spriteTracks: boundSprites,
    clock: initAnimationClock(targetFramesPerSecond),
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
  of mspColorR: value.color.r = sample
  of mspColorG: value.color.g = sample
  of mspColorB: value.color.b = sample
  of mspColorA: value.color.a = sample
  of mspStartAngle: value.startAngle = sample
  of mspSweepAngle: value.sweepAngle = sample

proc sample(track: MotionSpriteTrack; progress: float64): RasterRegion =
  var low = 0
  var high = track.frames.len
  while low + 1 < high:
    let middle = low + (high - low) div 2
    if track.frames[middle].offset <= progress:
      low = middle
    else:
      high = middle
  track.frames[low].sourceRegion

proc sampledSnapshot(timeline: MotionTimeline; progress: float64): MotionSceneSnapshot =
  var objects = newSeq[MotionObject](timeline.base.objectCount)
  for index in 0 ..< objects.len:
    objects[index] = timeline.base.objectAt(index).get
  for bound in timeline.tracks:
    objects[bound.index].apply(bound.track.property,
      float32(bound.track.frames.sample(progress)))
  for bound in timeline.spriteTracks:
    objects[bound.index].sourceRegion = bound.track.sample(progress)
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
