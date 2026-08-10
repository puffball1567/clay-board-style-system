import std/[hashes, math, options, strutils, tables]

import ../core/[color, color_conversion, computed_style, node, style_resolver]
import ./[animation_clock, frame_scheduler, invalidation]

const
  declarativeTransitionApiVersion* = 1'u32
  defaultTransitionFramesPerSecond* = 60.0

type
  DeclarativeTransitionProperty* = enum
    dtpOpacity,
    dtpColor,
    dtpBackgroundColor

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

  TransitionTrackKind = enum
    ttkNumber,
    ttkColor

  TransitionTrack = object
    case kind: TransitionTrackKind
    of ttkNumber:
      number: NumberTransition
    of ttkColor:
      color: ColorTransition

  DeclarativeTransitionRuntime* = object
    tracks: Table[TransitionKey, TransitionTrack]
    targetFrameInterval*: float64
    reducedMotion*: bool

proc `==`(left, right: TransitionKey): bool =
  left.node == right.node and left.property == right.property

proc hash(value: TransitionKey): Hash =
  result = hash(value.node)
  result = result !& hash(value.property)
  result = !$result

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
    targetFrameInterval: 1.0 / targetFramesPerSecond
  )

proc transitionPropertyName*(property: DeclarativeTransitionProperty): string =
  case property
  of dtpOpacity: "opacity"
  of dtpColor: "color"
  of dtpBackgroundColor: "background-color"

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

proc selectsProperty(
    authored: Option[string];
    property: DeclarativeTransitionProperty
): bool =
  if authored.isNone:
    return false
  for item in authored.get.split(','):
    let name = item.strip.toLowerAscii
    if name == "all" or name == property.transitionPropertyName:
      return true
  false

proc currentTiming(style: ComputedStyle): TimingFunction =
  let authored = style.animation.transitionTimingFunction
  if authored.isSome:
    let parsed = authored.get.parseTimingFunction()
    if parsed.isSome:
      return parsed.get
  easeTiming()

proc transitionEnabled(
    runtime: DeclarativeTransitionRuntime;
    style: ComputedStyle;
    property: DeclarativeTransitionProperty
): bool =
  not runtime.reducedMotion and
    style.animation.transitionDuration > 0 and
    style.animation.transitionProperty.selectsProperty(property)

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

proc numberTrack(
    startValue, endValue: float32;
    style: ComputedStyle;
    nowSeconds: float64
): TransitionTrack =
  TransitionTrack(kind: ttkNumber, number: NumberTransition(
    startValue: startValue,
    endValue: endValue,
    activeStart: nowSeconds + style.animation.transitionDelay.float64,
    duration: style.animation.transitionDuration.float64,
    timing: style.currentTiming()
  ))

proc transparentLike(value: Color): Color =
  rgba(value.r, value.g, value.b, 0)

proc colorTrack(
    startValue, endValue: Option[Color];
    style: ComputedStyle;
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
    activeStart: nowSeconds + style.animation.transitionDelay.float64,
    duration: style.animation.transitionDuration.float64,
    timing: style.currentTiming()
  ))

proc reconcileNumber(
    runtime: var DeclarativeTransitionRuntime;
    key: TransitionKey;
    startValue, endValue: float32;
    targetStyle: ComputedStyle;
    nowSeconds: float64
) =
  if startValue == endValue or
      not runtime.transitionEnabled(targetStyle, key.property):
    runtime.tracks.del(key)
    return
  if key in runtime.tracks and runtime.tracks[key].sameTarget(endValue):
    return
  runtime.tracks[key] = numberTrack(
    startValue, endValue, targetStyle, nowSeconds
  )

proc reconcileColor(
    runtime: var DeclarativeTransitionRuntime;
    key: TransitionKey;
    startValue, endValue: Option[Color];
    targetStyle: ComputedStyle;
    nowSeconds: float64
) =
  if startValue == endValue or
      not runtime.transitionEnabled(targetStyle, key.property):
    runtime.tracks.del(key)
    return
  if key in runtime.tracks and runtime.tracks[key].sameTarget(endValue):
    return
  runtime.tracks[key] = colorTrack(
    startValue, endValue, targetStyle, nowSeconds
  )

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
  for key, track in runtime.tracks.pairs:
    if not tree.isValid(key.node) or key.node.nodeIndex >= styles.styles.len:
      completed.add key
      continue
    var finished = false
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
    if finished:
      completed.add key
    inc result

  for key in completed:
    runtime.tracks.del(key)
  if result > 0:
    scheduler.markDirty({ddPaint, ddAnimation})

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
    runtime.tracks.del(key)
  removed.len
