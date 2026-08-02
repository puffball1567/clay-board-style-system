import std/[algorithm, hashes, math, options, tables]

import ../core/[color, color_conversion, color_value, computed_style]
import ./[frame_scheduler, invalidation]

type
  AnimationId* = distinct uint64

  AnimationPhase* = enum
    apBefore,
    apActive,
    apAfter

  TimingFunctionKind* = enum
    tfLinear,
    tfEase,
    tfEaseIn,
    tfEaseOut,
    tfEaseInOut,
    tfStepStart,
    tfStepEnd,
    tfCubicBezier

  TimingFunction* = object
    kind*: TimingFunctionKind
    x1*, y1*, x2*, y2*: float64

  AnimationSample* = object
    animation*: AnimationId
    phase*: AnimationPhase
    iteration*: uint64
    linearProgress*: float64
    progress*: float64
    elapsedSeconds*: float64

  AnimationSampleCallback* = proc(sample: AnimationSample) {.closure.}
  AnimationLifecycleCallback* = proc(animation: AnimationId) {.closure.}
  AnimationIterationCallback* = proc(animation: AnimationId; iteration: uint64) {.closure.}

  AnimationSpec* = object
    durationSeconds*: float64
    delaySeconds*: float64
    iterations*: Option[float64]
    direction*: AnimationDirection
    fillMode*: AnimationFillMode
    timing*: TimingFunction
    dirtyDomains*: set[DirtyDomain]
    essentialMotion*: bool
    onSample*: AnimationSampleCallback
    onStart*: AnimationLifecycleCallback
    onIteration*: AnimationIterationCallback
    onEnd*: AnimationLifecycleCallback

  AnimationTrack = object
    spec: AnimationSpec
    startTime: float64
    pausedAt: Option[float64]
    started: bool
    lastIteration: Option[uint64]

  AnimationClock* = object
    nextId: uint64
    tracks: Table[AnimationId, AnimationTrack]
    targetFrameInterval*: float64
    reducedMotion*: bool

  FloatKeyframe* = object
    offset*: float64
    value*: float64

  FloatKeyframes* = object
    values*: seq[FloatKeyframe]

  ColorKeyframe* = object
    offset*: float64
    value*: ColorValue

  ColorKeyframes* = object
    values*: seq[ColorKeyframe]
    interpolationSpace*: ColorInterpolationSpace

proc `==`*(a, b: AnimationId): bool {.borrow.}
proc `<`*(a, b: AnimationId): bool {.borrow.}
proc hash*(id: AnimationId): Hash {.borrow.}

proc animationIdValue*(id: AnimationId): uint64 = uint64(id)

proc linearTiming*(): TimingFunction = TimingFunction(kind: tfLinear)
proc easeTiming*(): TimingFunction = TimingFunction(kind: tfEase)
proc easeInTiming*(): TimingFunction = TimingFunction(kind: tfEaseIn)
proc easeOutTiming*(): TimingFunction = TimingFunction(kind: tfEaseOut)
proc easeInOutTiming*(): TimingFunction = TimingFunction(kind: tfEaseInOut)
proc stepStartTiming*(): TimingFunction = TimingFunction(kind: tfStepStart)
proc stepEndTiming*(): TimingFunction = TimingFunction(kind: tfStepEnd)

proc cubicBezierTiming*(x1, y1, x2, y2: float64): TimingFunction =
  for value in [x1, y1, x2, y2]:
    if value.classify in {fcNan, fcInf, fcNegInf}:
      raise newException(ValueError, "cubic bezier coordinates must be finite")
  if x1 < 0 or x1 > 1 or x2 < 0 or x2 > 1:
    raise newException(ValueError, "cubic bezier x coordinates must be between zero and one")
  TimingFunction(kind: tfCubicBezier, x1: x1, y1: y1, x2: x2, y2: y2)

proc animationSpec*(
    durationSeconds: float64;
    delaySeconds = 0.0;
    iterations = some(1.0);
    direction = adNormal;
    fillMode = afNone;
    timing = easeTiming();
    dirtyDomains: set[DirtyDomain] = {ddPaint};
    essentialMotion = false;
    onSample: AnimationSampleCallback = nil;
    onStart: AnimationLifecycleCallback = nil;
    onIteration: AnimationIterationCallback = nil;
    onEnd: AnimationLifecycleCallback = nil
): AnimationSpec =
  if durationSeconds.classify in {fcNan, fcInf, fcNegInf} or durationSeconds < 0:
    raise newException(ValueError, "animation duration must be finite and non-negative")
  if delaySeconds.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "animation delay must be finite")
  if iterations.isSome and
      (iterations.get.classify in {fcNan, fcInf, fcNegInf} or iterations.get <= 0):
    raise newException(ValueError, "animation iterations must be positive and finite")
  AnimationSpec(
    durationSeconds: durationSeconds,
    delaySeconds: delaySeconds,
    iterations: iterations,
    direction: direction,
    fillMode: fillMode,
    timing: timing,
    dirtyDomains: dirtyDomains,
    essentialMotion: essentialMotion,
    onSample: onSample,
    onStart: onStart,
    onIteration: onIteration,
    onEnd: onEnd
  )

proc initAnimationClock*(targetFramesPerSecond = 60.0): AnimationClock =
  if targetFramesPerSecond.classify in {fcNan, fcInf, fcNegInf} or
      targetFramesPerSecond <= 0:
    raise newException(ValueError, "target frame rate must be positive and finite")
  AnimationClock(
    nextId: 1,
    tracks: initTable[AnimationId, AnimationTrack](),
    targetFrameInterval: 1.0 / targetFramesPerSecond
  )

proc cubicCoordinate(t, first, second: float64): float64 =
  let inverse = 1.0 - t
  3.0 * inverse * inverse * t * first +
    3.0 * inverse * t * t * second + t * t * t

proc cubicDerivative(t, first, second: float64): float64 =
  3.0 * (1.0 - t) * (1.0 - t) * first +
    6.0 * (1.0 - t) * t * (second - first) +
    3.0 * t * t * (1.0 - second)

proc cubicBezierProgress(value: float64; timing: TimingFunction): float64 =
  var t = value
  for discardIndex in 0 ..< 8:
    let difference = cubicCoordinate(t, timing.x1, timing.x2) - value
    if abs(difference) < 0.000001:
      break
    let derivative = cubicDerivative(t, timing.x1, timing.x2)
    if abs(derivative) < 0.000001:
      break
    t = clamp(t - difference / derivative, 0.0, 1.0)
  var low = 0.0
  var high = 1.0
  for discardIndex in 0 ..< 12:
    let x = cubicCoordinate(t, timing.x1, timing.x2)
    if abs(x - value) < 0.000001:
      break
    if x < value: low = t else: high = t
    t = (low + high) * 0.5
  cubicCoordinate(t, timing.y1, timing.y2)

proc applyTiming*(timing: TimingFunction; progress: float64): float64 =
  let value = clamp(progress, 0.0, 1.0)
  case timing.kind
  of tfLinear:
    value
  of tfEase:
    cubicBezierProgress(value, cubicBezierTiming(0.25, 0.1, 0.25, 1.0))
  of tfEaseIn:
    cubicBezierProgress(value, cubicBezierTiming(0.42, 0.0, 1.0, 1.0))
  of tfEaseOut:
    cubicBezierProgress(value, cubicBezierTiming(0.0, 0.0, 0.58, 1.0))
  of tfEaseInOut:
    cubicBezierProgress(value, cubicBezierTiming(0.42, 0.0, 0.58, 1.0))
  of tfStepStart:
    1.0
  of tfStepEnd:
    if value < 1: 0.0 else: 1.0
  of tfCubicBezier:
    cubicBezierProgress(value, timing)

proc directedProgress(
    direction: AnimationDirection;
    iteration: uint64;
    progress: float64
): float64 =
  let reverse =
    case direction
    of adNormal: false
    of adReverse: true
    of adAlternate: iteration mod 2 == 1
    of adAlternateReverse: iteration mod 2 == 0
  if reverse: 1.0 - progress else: progress

proc hasAnimation*(clock: AnimationClock; id: AnimationId): bool =
  id in clock.tracks

proc hasActiveAnimations*(clock: AnimationClock): bool =
  for track in clock.tracks.values:
    if track.pausedAt.isNone:
      return true
  false

proc startAnimation*(
    clock: var AnimationClock;
    spec: AnimationSpec;
    nowSeconds: float64
): AnimationId =
  if nowSeconds.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "animation start time must be finite")
  if clock.nextId == 0:
    raise newException(ValueError, "animation identifier space exhausted")
  result = AnimationId(clock.nextId)
  inc clock.nextId
  clock.tracks[result] = AnimationTrack(
    spec: spec,
    startTime: nowSeconds,
    pausedAt: none(float64),
    lastIteration: none(uint64)
  )

proc cancelAnimation*(clock: var AnimationClock; id: AnimationId): bool {.discardable.} =
  if id notin clock.tracks:
    return false
  clock.tracks.del(id)
  true

proc pauseAnimation*(
    clock: var AnimationClock;
    id: AnimationId;
    nowSeconds: float64
): bool {.discardable.} =
  if id notin clock.tracks or clock.tracks[id].pausedAt.isSome:
    return false
  var track = clock.tracks[id]
  track.pausedAt = some(nowSeconds)
  clock.tracks[id] = track
  true

proc resumeAnimation*(
    clock: var AnimationClock;
    id: AnimationId;
    nowSeconds: float64
): bool {.discardable.} =
  if id notin clock.tracks or clock.tracks[id].pausedAt.isNone:
    return false
  var track = clock.tracks[id]
  track.startTime += max(0.0, nowSeconds - track.pausedAt.get)
  track.pausedAt = none(float64)
  clock.tracks[id] = track
  true

proc tickAnimations*(
    clock: var AnimationClock;
    scheduler: var FrameScheduler;
    nowSeconds: float64
): int {.discardable.} =
  if nowSeconds.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "animation clock time must be finite")
  var ids: seq[AnimationId]
  for id in clock.tracks.keys:
    ids.add id
  ids.sort()

  for id in ids:
    if id notin clock.tracks:
      continue
    var track = clock.tracks[id]
    if track.pausedAt.isSome:
      continue
    let duration =
      if clock.reducedMotion and not track.spec.essentialMotion: 0.0
      else: track.spec.durationSeconds
    let activeStart = track.startTime + track.spec.delaySeconds
    let elapsed = nowSeconds - activeStart
    if elapsed < 0:
      if track.spec.fillMode in {afBackwards, afBoth} and
          not track.spec.onSample.isNil:
        let linear = directedProgress(track.spec.direction, 0, 0)
        track.spec.onSample(AnimationSample(
          animation: id,
          phase: apBefore,
          iteration: 0,
          linearProgress: linear,
          progress: track.spec.timing.applyTiming(linear),
          elapsedSeconds: elapsed
        ))
        scheduler.markDirty(track.spec.dirtyDomains)
        inc result
      scheduler.requestDeadline(activeStart)
      clock.tracks[id] = track
      continue

    if not track.started:
      track.started = true
      if not track.spec.onStart.isNil:
        track.spec.onStart(id)

    let finite = track.spec.iterations.isSome
    let iterationCount =
      if finite: track.spec.iterations.get
      else: Inf
    let completed = duration <= 0 or
      (finite and elapsed >= duration * iterationCount)
    var iteration: uint64
    var fraction: float64
    if completed:
      iteration =
        if finite: uint64(max(0.0, ceil(iterationCount) - 1.0))
        else: 0
      fraction = 1.0
    else:
      iteration = uint64(floor(elapsed / duration))
      fraction = (elapsed - iteration.float64 * duration) / duration

    if track.lastIteration.isSome and iteration != track.lastIteration.get and
        not track.spec.onIteration.isNil:
      track.spec.onIteration(id, iteration)
    track.lastIteration = some(iteration)
    let linear = directedProgress(track.spec.direction, iteration, fraction)
    if not track.spec.onSample.isNil:
      track.spec.onSample(AnimationSample(
        animation: id,
        phase: if completed: apAfter else: apActive,
        iteration: iteration,
        linearProgress: linear,
        progress: track.spec.timing.applyTiming(linear),
        elapsedSeconds: max(0.0, elapsed)
      ))
    scheduler.markDirty(track.spec.dirtyDomains)
    inc result

    if completed:
      if not track.spec.onEnd.isNil:
        track.spec.onEnd(id)
      clock.tracks.del(id)
    else:
      clock.tracks[id] = track
      scheduler.requestDeadline(nowSeconds + clock.targetFrameInterval)

proc validateOffsets[T](values: openArray[T]) =
  if values.len == 0:
    raise newException(ValueError, "keyframes must not be empty")
  var previous = -1.0
  for value in values:
    if value.offset.classify in {fcNan, fcInf, fcNegInf} or
        value.offset < 0 or value.offset > 1:
      raise newException(ValueError, "keyframe offsets must be finite and between zero and one")
    if value.offset < previous:
      raise newException(ValueError, "keyframe offsets must be sorted")
    previous = value.offset

proc floatKeyframes*(values: openArray[FloatKeyframe]): FloatKeyframes =
  values.validateOffsets()
  FloatKeyframes(values: @values)

proc colorKeyframes*(
    values: openArray[ColorKeyframe];
    interpolationSpace = cisOklab
): ColorKeyframes =
  values.validateOffsets()
  ColorKeyframes(values: @values, interpolationSpace: interpolationSpace)

proc keyframeSpan[T](values: openArray[T]; progress: float64): tuple[left, right: int; amount: float64] =
  let value = clamp(progress, 0.0, 1.0)
  if value <= values[0].offset:
    return (0, 0, 0.0)
  if value >= values[^1].offset:
    return (values.high, values.high, 0.0)
  for index in 0 ..< values.high:
    if value <= values[index + 1].offset:
      let span = values[index + 1].offset - values[index].offset
      return (index, index + 1,
        if span <= 0: 1.0 else: (value - values[index].offset) / span)
  (values.high, values.high, 0.0)

proc sample*(keyframes: FloatKeyframes; progress: float64): float64 =
  let span = keyframes.values.keyframeSpan(progress)
  if span.left == span.right:
    return keyframes.values[span.left].value
  let first = keyframes.values[span.left].value
  first + (keyframes.values[span.right].value - first) * span.amount

proc sample*(
    keyframes: ColorKeyframes;
    progress: float64;
    currentColor = rgb(0, 0, 0)
): Color =
  let span = keyframes.values.keyframeSpan(progress)
  if span.left == span.right:
    return resolveColor(keyframes.values[span.left].value, currentColor)
  interpolateColor(
    keyframes.values[span.left].value,
    keyframes.values[span.right].value,
    span.amount,
    keyframes.interpolationSpace,
    currentColor
  )
