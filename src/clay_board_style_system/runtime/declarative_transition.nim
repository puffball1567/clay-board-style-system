import std/[hashes, math, options, strutils, tables]

import ../core/[color, color_conversion, computed_style, node, style_resolver]
import ./[
  animation_clock, frame_scheduler, invalidation, motion_lifecycle,
  transform_interpolation
]

const
  declarativeTransitionApiVersion* = 1'u32
  defaultTransitionFramesPerSecond* = 60.0

type
  DeclarativeTransitionProperty* = enum
    dtpOpacity,
    dtpColor,
    dtpBackgroundColor,
    dtpTransform,
    dtpTranslate,
    dtpScale,
    dtpRotate

  TransitionKey = object
    node: NodeId
    property: DeclarativeTransitionProperty

  NumberTransition = object
    startValue: float32
    endValue: float32
    activeStart: float64
    duration: float64
    timing: TimingFunction

  ColorTransition = object
    startValue: PreparedColorInterpolation
    endValue: PreparedColorInterpolation
    endPresent: bool
    activeStart: float64
    duration: float64
    timing: TimingFunction

  TransformTransition = object
    startValue: ComputedTransformStyle
    endValue: ComputedTransformStyle
    property: MotionTransformProperty
    activeStart: float64
    duration: float64
    timing: TimingFunction

  TransitionTrackKind = enum
    ttkNumber,
    ttkColor,
    ttkTransform

  TransitionTrack = object
    started: bool
    lastElapsed: float64
    case kind: TransitionTrackKind
    of ttkNumber:
      number: NumberTransition
    of ttkColor:
      color: ColorTransition
    of ttkTransform:
      transform: TransformTransition

  DeclarativeTransitionRuntime* = object
    tracks: Table[TransitionKey, TransitionTrack]
    targetFrameInterval*: float64
    reducedMotion*: bool
    lifecycle: MotionLifecycleQueue

  TransitionParameters = object
    duration: float64
    delay: float64
    timing: TimingFunction
    behavior: TransitionBehavior

proc `==`(left, right: TransitionKey): bool =
  left.node == right.node and left.property == right.property

proc hash(value: TransitionKey): Hash =
  result = hash(value.node)
  result = result !& hash(value.property)
  result = !$result

proc transitionPropertyName*(
    property: DeclarativeTransitionProperty
): string

proc initDeclarativeTransitionRuntime*(
    targetFramesPerSecond = defaultTransitionFramesPerSecond
): DeclarativeTransitionRuntime =
  if targetFramesPerSecond.classify in {fcNan, fcInf, fcNegInf} or
      targetFramesPerSecond <= 0:
    raise newException(
      ValueError, "transition frame rate must be positive and finite"
    )
  DeclarativeTransitionRuntime(
    tracks: initTable[TransitionKey, TransitionTrack](),
    targetFrameInterval: 1.0 / targetFramesPerSecond,
    lifecycle: initMotionLifecycleQueue()
  )

proc queueLifecycle(
    runtime: DeclarativeTransitionRuntime;
    key: TransitionKey;
    kind: MotionLifecycleKind;
    elapsedSeconds = 0.0
) =
  runtime.lifecycle.add MotionLifecycleEvent(
    kind: kind,
    node: key.node,
    name: key.property.transitionPropertyName,
    elapsedSeconds: elapsedSeconds
  )

proc cancelTrack(
    runtime: var DeclarativeTransitionRuntime;
    key: TransitionKey
) =
  if key notin runtime.tracks:
    return
  runtime.queueLifecycle(
    key, mlkTransitionCancel, runtime.tracks[key].lastElapsed
  )
  runtime.tracks.del(key)

proc replaceTrack(
    runtime: var DeclarativeTransitionRuntime;
    key: TransitionKey;
    track: TransitionTrack
) =
  runtime.cancelTrack(key)
  runtime.tracks[key] = track
  runtime.queueLifecycle(key, mlkTransitionRun)

proc takeLifecycleEvents*(
    runtime: var DeclarativeTransitionRuntime
): seq[MotionLifecycleEvent] =
  runtime.lifecycle.take()

proc transitionPropertyName*(property: DeclarativeTransitionProperty): string =
  case property
  of dtpOpacity: "opacity"
  of dtpColor: "color"
  of dtpBackgroundColor: "background-color"
  of dtpTransform: "transform"
  of dtpTranslate: "translate"
  of dtpScale: "scale"
  of dtpRotate: "rotate"

proc parseTimingFunction*(value: string): Option[TimingFunction] =
  let normalized = value.strip.toLowerAscii
  case normalized
  of "linear": return some(linearTiming())
  of "ease": return some(easeTiming())
  of "ease-in": return some(easeInTiming())
  of "ease-out": return some(easeOutTiming())
  of "ease-in-out": return some(easeInOutTiming())
  of "step-start": return some(stepStartTiming())
  of "step-end": return some(stepEndTiming())
  else: discard

  const prefix = "cubic-bezier("
  if not normalized.startsWith(prefix) or not normalized.endsWith(")"):
    return none(TimingFunction)
  let arguments = normalized[prefix.len ..< normalized.high].split(',')
  if arguments.len != 4:
    return none(TimingFunction)
  var values: array[4, float64]
  try:
    for index, argument in arguments:
      values[index] = parseFloat(argument.strip)
    some(cubicBezierTiming(values[0], values[1], values[2], values[3]))
  except ValueError:
    none(TimingFunction)

proc transitionParameters(
    runtime: DeclarativeTransitionRuntime;
    style: ComputedStyle;
    property: DeclarativeTransitionProperty
): Option[TransitionParameters] =
  if runtime.reducedMotion:
    return none(TransitionParameters)
  let animation = style.animation
  var properties = animation.transitionProperties
  if properties.len == 0 and animation.transitionProperty.isSome:
    for item in animation.transitionProperty.get.split(','):
      properties.add item.strip
  var matched = -1
  for index, item in properties:
    let name = item.strip.toLowerAscii
    if name == "all" or name == property.transitionPropertyName:
      matched = index
  if matched < 0:
    return none(TransitionParameters)

  let duration =
    if animation.transitionDurations.len > 0:
      animation.transitionDurations[matched mod animation.transitionDurations.len]
    else:
      animation.transitionDuration
  if duration <= 0:
    return none(TransitionParameters)
  let delay =
    if animation.transitionDelays.len > 0:
      animation.transitionDelays[matched mod animation.transitionDelays.len]
    else:
      animation.transitionDelay
  let authoredTiming =
    if animation.transitionTimingFunctions.len > 0:
      some(animation.transitionTimingFunctions[
        matched mod animation.transitionTimingFunctions.len
      ])
    else:
      animation.transitionTimingFunction
  let parsedTiming =
    if authoredTiming.isSome:
      authoredTiming.get.parseTimingFunction()
    else:
      none(TimingFunction)
  let behavior =
    if animation.transitionBehaviors.len > 0:
      animation.transitionBehaviors[matched mod animation.transitionBehaviors.len]
    else:
      animation.transitionBehavior
  some(TransitionParameters(
    duration: duration.float64,
    delay: delay.float64,
    timing: parsedTiming.get(easeTiming()),
    behavior: behavior
  ))

proc sameTarget(track: TransitionTrack; value: float32): bool =
  track.kind == ttkNumber and track.number.endValue == value

proc sameTarget(
    track: TransitionTrack;
    value: Option[Color]
): bool =
  if track.kind != ttkColor or track.color.endPresent != value.isSome:
    return false
  if value.isNone:
    return true
  let prepared = value.get.prepareColorInterpolation(cisOklab)
  track.color.endValue == prepared

proc sameTarget(
    track: TransitionTrack;
    value: ComputedTransformStyle;
    property: MotionTransformProperty
): bool =
  track.kind == ttkTransform and track.transform.property == property and
    track.transform.endValue.sameTransformProperty(value, property)

proc numberTrack(
    startValue, endValue: float32;
    parameters: TransitionParameters;
    nowSeconds: float64
): TransitionTrack =
  TransitionTrack(kind: ttkNumber, number: NumberTransition(
    startValue: startValue,
    endValue: endValue,
    activeStart: nowSeconds + parameters.delay,
    duration: parameters.duration,
    timing: parameters.timing
  ))

proc transparentLike(value: Color): Color =
  rgba(value.r, value.g, value.b, 0)

proc colorTrack(
    startValue, endValue: Option[Color];
    parameters: TransitionParameters;
    nowSeconds: float64
): TransitionTrack =
  let startColor =
    if startValue.isSome: startValue.get
    elif endValue.isSome: endValue.get.transparentLike()
    else: rgba(0, 0, 0, 0)
  let endColor =
    if endValue.isSome: endValue.get
    else: startColor.transparentLike()
  TransitionTrack(kind: ttkColor, color: ColorTransition(
    startValue: startColor.prepareColorInterpolation(cisOklab),
    endValue: endColor.prepareColorInterpolation(cisOklab),
    endPresent: endValue.isSome,
    activeStart: nowSeconds + parameters.delay,
    duration: parameters.duration,
    timing: parameters.timing
  ))

proc transformTrack(
    startValue, endValue: ComputedTransformStyle;
    property: MotionTransformProperty;
    parameters: TransitionParameters;
    nowSeconds: float64
): TransitionTrack =
  TransitionTrack(kind: ttkTransform, transform: TransformTransition(
    startValue: startValue,
    endValue: endValue,
    property: property,
    activeStart: nowSeconds + parameters.delay,
    duration: parameters.duration,
    timing: parameters.timing
  ))

proc reconcileNumber(
    runtime: var DeclarativeTransitionRuntime;
    key: TransitionKey;
    startValue, endValue: float32;
    targetStyle: ComputedStyle;
    nowSeconds: float64
) =
  let parameters = runtime.transitionParameters(targetStyle, key.property)
  if startValue == endValue or parameters.isNone:
    runtime.cancelTrack(key)
    return
  if key in runtime.tracks and runtime.tracks[key].sameTarget(endValue):
    return
  runtime.replaceTrack(key, numberTrack(
    startValue, endValue, parameters.get, nowSeconds
  ))

proc reconcileColor(
    runtime: var DeclarativeTransitionRuntime;
    key: TransitionKey;
    startValue, endValue: Option[Color];
    targetStyle: ComputedStyle;
    nowSeconds: float64
) =
  let parameters = runtime.transitionParameters(targetStyle, key.property)
  if startValue == endValue or parameters.isNone:
    runtime.cancelTrack(key)
    return
  if key in runtime.tracks and runtime.tracks[key].sameTarget(endValue):
    return
  runtime.replaceTrack(key, colorTrack(
    startValue, endValue, parameters.get, nowSeconds
  ))

proc reconcileTransform(
    runtime: var DeclarativeTransitionRuntime;
    key: TransitionKey;
    property: MotionTransformProperty;
    startValue, endValue: ComputedTransformStyle;
    targetStyle: ComputedStyle;
    nowSeconds: float64
) =
  let parameters = runtime.transitionParameters(targetStyle, key.property)
  if startValue.sameTransformProperty(endValue, property) or
      parameters.isNone or
      not startValue.canInterpolateTransformStyle(endValue, property):
    runtime.cancelTrack(key)
    return
  if key in runtime.tracks and
      runtime.tracks[key].sameTarget(endValue, property):
    return
  runtime.replaceTrack(key, transformTrack(
    startValue, endValue, property, parameters.get, nowSeconds
  ))

proc reconcileTransitions*(
    runtime: var DeclarativeTransitionRuntime;
    tree: Tree;
    displayed, target: ResolvedTree;
    nowSeconds: float64
) =
  if nowSeconds.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "transition time must be finite")

  for index, targetStyle in target.styles:
    let node = tree.nodeIdAt(index)
    if node.isNone or index >= displayed.styles.len:
      continue
    let displayedStyle = displayed.styles[index]
    runtime.reconcileNumber(
      TransitionKey(node: node.get, property: dtpOpacity),
      displayedStyle.visual.opacity,
      targetStyle.visual.opacity,
      targetStyle,
      nowSeconds
    )
    runtime.reconcileColor(
      TransitionKey(node: node.get, property: dtpColor),
      displayedStyle.text.color,
      targetStyle.text.color,
      targetStyle,
      nowSeconds
    )
    runtime.reconcileTransform(
      TransitionKey(node: node.get, property: dtpTransform),
      mtpTransform,
      displayedStyle.transform,
      targetStyle.transform,
      targetStyle,
      nowSeconds
    )
    runtime.reconcileTransform(
      TransitionKey(node: node.get, property: dtpTranslate),
      mtpTranslate,
      displayedStyle.transform,
      targetStyle.transform,
      targetStyle,
      nowSeconds
    )
    runtime.reconcileTransform(
      TransitionKey(node: node.get, property: dtpScale),
      mtpScale,
      displayedStyle.transform,
      targetStyle.transform,
      targetStyle,
      nowSeconds
    )
    runtime.reconcileTransform(
      TransitionKey(node: node.get, property: dtpRotate),
      mtpRotate,
      displayedStyle.transform,
      targetStyle.transform,
      targetStyle,
      nowSeconds
    )
    runtime.reconcileColor(
      TransitionKey(node: node.get, property: dtpBackgroundColor),
      displayedStyle.box.backgroundColor,
      targetStyle.box.backgroundColor,
      targetStyle,
      nowSeconds
    )

  var stale: seq[TransitionKey]
  for key in runtime.tracks.keys:
    if not tree.isValid(key.node) or key.node.nodeIndex >= target.styles.len:
      stale.add key
  for key in stale:
    runtime.tracks.del(key)

proc trackProgress(
    activeStart, duration, nowSeconds: float64;
    timing: TimingFunction
): tuple[progress: float64, complete: bool] =
  if nowSeconds < activeStart:
    return (0.0, false)
  if duration <= 0 or nowSeconds >= activeStart + duration:
    return (1.0, true)
  let linear = clamp((nowSeconds - activeStart) / duration, 0.0, 1.0)
  (timing.applyTiming(linear), false)

proc applyNumber(
    track: NumberTransition;
    style: var ComputedStyle;
    nowSeconds: float64
): bool =
  let sample = trackProgress(
    track.activeStart, track.duration, nowSeconds, track.timing
  )
  style.visual.opacity =
    track.startValue + (track.endValue - track.startValue) * sample.progress.float32
  sample.complete

proc finishNumber(track: NumberTransition; style: var ComputedStyle) =
  style.visual.opacity = track.endValue

proc sampledColor(track: ColorTransition; progress: float64): Color =
  interpolateColor(track.startValue, track.endValue, progress)

proc applyColor(
    track: ColorTransition;
    property: DeclarativeTransitionProperty;
    style: var ComputedStyle;
    nowSeconds: float64
): bool =
  let sample = trackProgress(
    track.activeStart, track.duration, nowSeconds, track.timing
  )
  let value =
    if sample.complete and not track.endPresent: none(Color)
    else: some(track.sampledColor(sample.progress))
  case property
  of dtpColor:
    style.text.color = value
  of dtpBackgroundColor:
    style.box.backgroundColor = value
  of dtpOpacity:
    discard
  of dtpTransform, dtpTranslate, dtpScale, dtpRotate:
    discard
  sample.complete

proc finishColor(
    track: ColorTransition;
    property: DeclarativeTransitionProperty;
    style: var ComputedStyle
) =
  let value =
    if track.endPresent: some(track.sampledColor(1.0))
    else: none(Color)
  case property
  of dtpColor:
    style.text.color = value
  of dtpBackgroundColor:
    style.box.backgroundColor = value
  of dtpOpacity:
    discard
  of dtpTransform, dtpTranslate, dtpScale, dtpRotate:
    discard

proc applyTransform(
    track: TransformTransition;
    style: var ComputedStyle;
    nowSeconds: float64
): bool =
  let sample = trackProgress(
    track.activeStart, track.duration, nowSeconds, track.timing
  )
  let value = interpolateTransformStyle(
    track.startValue,
    track.endValue,
    track.property,
    sample.progress.float32
  )
  if value.isSome:
    case track.property
    of mtpTransform:
      style.transform.rawTransform = value.get.rawTransform
      style.transform.operations = value.get.operations
    of mtpTranslate:
      style.transform.translateX = value.get.translateX
      style.transform.translateY = value.get.translateY
      style.transform.translateZ = value.get.translateZ
    of mtpScale:
      style.transform.scaleX = value.get.scaleX
      style.transform.scaleY = value.get.scaleY
      style.transform.scaleZ = value.get.scaleZ
    of mtpRotate:
      style.transform.rotate = value.get.rotate
    of mtpAll:
      style.transform = value.get
  sample.complete

proc finishTransform(
    track: TransformTransition;
    style: var ComputedStyle
) =
  case track.property
  of mtpTransform:
    style.transform.rawTransform = track.endValue.rawTransform
    style.transform.operations = track.endValue.operations
  of mtpTranslate:
    style.transform.translateX = track.endValue.translateX
    style.transform.translateY = track.endValue.translateY
    style.transform.translateZ = track.endValue.translateZ
  of mtpScale:
    style.transform.scaleX = track.endValue.scaleX
    style.transform.scaleY = track.endValue.scaleY
    style.transform.scaleZ = track.endValue.scaleZ
  of mtpRotate:
    style.transform.rotate = track.endValue.rotate
  of mtpAll:
    style.transform = track.endValue

proc applyTransitions*(
    runtime: var DeclarativeTransitionRuntime;
    tree: Tree;
    styles: var ResolvedTree;
    scheduler: var FrameScheduler;
    nowSeconds: float64
): int {.discardable.} =
  if nowSeconds.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "transition time must be finite")

  var completed: seq[TransitionKey]
  var transformed = false
  for key, track in runtime.tracks.mpairs:
    if not tree.isValid(key.node) or key.node.nodeIndex >= styles.styles.len:
      completed.add key
      continue
    var finished = false
    let activeStart =
      case track.kind
      of ttkNumber: track.number.activeStart
      of ttkColor: track.color.activeStart
      of ttkTransform: track.transform.activeStart
    let duration =
      case track.kind
      of ttkNumber: track.number.duration
      of ttkColor: track.color.duration
      of ttkTransform: track.transform.duration
    track.lastElapsed = clamp(nowSeconds - activeStart, 0.0, duration)
    if not track.started and nowSeconds >= activeStart:
      track.started = true
      runtime.queueLifecycle(
        key, mlkTransitionStart, track.lastElapsed
      )
    case track.kind
    of ttkNumber:
      if runtime.reducedMotion:
        track.number.finishNumber(styles.styles[key.node.nodeIndex])
        finished = true
      else:
        finished = track.number.applyNumber(
          styles.styles[key.node.nodeIndex], nowSeconds
        )
      if not finished:
        scheduler.requestDeadline(
          if nowSeconds < track.number.activeStart:
            track.number.activeStart
          else:
            nowSeconds + runtime.targetFrameInterval
        )
    of ttkColor:
      if runtime.reducedMotion:
        track.color.finishColor(
          key.property, styles.styles[key.node.nodeIndex]
        )
        finished = true
      else:
        finished = track.color.applyColor(
          key.property, styles.styles[key.node.nodeIndex], nowSeconds
        )
      if not finished:
        scheduler.requestDeadline(
          if nowSeconds < track.color.activeStart:
            track.color.activeStart
          else:
            nowSeconds + runtime.targetFrameInterval
        )
    of ttkTransform:
      transformed = true
      if runtime.reducedMotion:
        track.transform.finishTransform(styles.styles[key.node.nodeIndex])
        finished = true
      else:
        finished = track.transform.applyTransform(
          styles.styles[key.node.nodeIndex], nowSeconds
        )
      if not finished:
        scheduler.requestDeadline(
          if nowSeconds < track.transform.activeStart:
            track.transform.activeStart
          else:
            nowSeconds + runtime.targetFrameInterval
        )
    if finished:
      runtime.queueLifecycle(key, mlkTransitionEnd, duration)
      completed.add key
    inc result

  for key in completed:
    runtime.tracks.del(key)
  if result > 0:
    scheduler.markDirty(
      if transformed: {ddPaint, ddHit, ddAnimation}
      else: {ddPaint, ddAnimation}
    )

proc activeTransitionCount*(runtime: DeclarativeTransitionRuntime): int =
  runtime.tracks.len

proc hasActiveTransitions*(runtime: DeclarativeTransitionRuntime): bool =
  runtime.tracks.len > 0

proc cancelTransitions*(
    runtime: var DeclarativeTransitionRuntime;
    nodes: openArray[NodeId]
): int {.discardable.} =
  var removed: seq[TransitionKey]
  for key in runtime.tracks.keys:
    for node in nodes:
      if key.node == node:
        removed.add key
        break
  for key in removed:
    runtime.cancelTrack(key)
  removed.len
