import std/[algorithm, hashes, math, options, sequtils, sets, strutils, tables]

import ../core/[
  color,
  color_conversion,
  computed_style,
  declaration,
  diagnostics,
  geometry,
  node,
  property,
  registry,
  style_context,
  style_resolver,
  style_value
]
import ../generated/default_properties
import ./[
  animation_clock,
  declarative_transition,
  frame_scheduler,
  invalidation,
  transform_interpolation
]

const declarativeKeyframeApiVersion* = 1'u32

type
  StyleKeyframe* = object
    offset*: float64
    declarations*: seq[Declaration]

  StyleKeyframes* = object
    name*: string
    steps*: seq[StyleKeyframe]

  RegisteredStyleKeyframes = object
    definition: StyleKeyframes
    revision: uint64

  AnimationSignature = object
    name: string
    definitionRevision: uint64
    duration: float32
    delay: float32
    iterations: Option[float32]
    direction: AnimationDirection
    fillMode: AnimationFillMode
    timing: TimingFunction
    composition: AnimationComposition

  AnimationTrackKey = object
    node: NodeId
    index: int

  PreparedColorKeyframe = object
    offset: float64
    value: PreparedColorInterpolation

  PreparedColorKeyframes = object
    values: seq[PreparedColorKeyframe]

  PreparedTransformKeyframe = object
    offset: float64
    value: ComputedTransformStyle

  PreparedTransformKeyframes = object
    values: seq[PreparedTransformKeyframe]

  DeclarativeAnimationSample = ref object
    pending: bool
    initialized: bool
    value: AnimationSample

  DeclarativeAnimationTrack = object
    animation: AnimationId
    signature: AnimationSignature
    sample: DeclarativeAnimationSample
    opacity: Option[FloatKeyframes]
    color: Option[PreparedColorKeyframes]
    backgroundColor: Option[PreparedColorKeyframes]
    transform: Option[PreparedTransformKeyframes]
    baseOpacity: float32
    baseColor: Option[Color]
    baseBackgroundColor: Option[Color]
    baseTransform: ComputedTransformStyle
    paused: bool
    pauseAfterFirstTick: bool

  CompletedDeclarativeAnimation = object
    signature: AnimationSignature
    retainedTrack: Option[DeclarativeAnimationTrack]

  DeclarativeKeyframeRuntime* = object
    definitions: Table[string, RegisteredStyleKeyframes]
    tracks: Table[AnimationTrackKey, DeclarativeAnimationTrack]
    completed: Table[AnimationTrackKey, CompletedDeclarativeAnimation]
    clock: AnimationClock
    nextDefinitionRevision: uint64

proc `==`(left, right: AnimationSignature): bool =
  left.name == right.name and
    left.definitionRevision == right.definitionRevision and
    left.duration == right.duration and
    left.delay == right.delay and
    left.iterations == right.iterations and
    left.direction == right.direction and
    left.fillMode == right.fillMode and
    left.timing == right.timing and
    left.composition == right.composition

proc `==`(left, right: AnimationTrackKey): bool =
  left.node == right.node and left.index == right.index

proc hash(value: AnimationTrackKey): Hash =
  result = value.node.hash
  result = result !& value.index.hash
  result = !$result

proc styleKeyframe*(
    offset: float64;
    declarations: openArray[Declaration]
): StyleKeyframe =
  if offset.classify in {fcNan, fcInf, fcNegInf} or offset < 0 or offset > 1:
    raise newException(
      ValueError, "style keyframe offset must be finite and between zero and one"
    )
  for declaration in declarations:
    if declaration.property notin [
      "opacity", "color", "background-color", "transform", "translate",
      "scale", "rotate"
    ]:
      raise newException(
        ValueError,
        "declarative keyframes do not yet support " & declaration.property
      )
    if declaration.operation.mode != mmOverwrite or
        declaration.operation.value.isNone or
        declaration.operation.value.get.kind == svFunction:
      raise newException(
        ValueError,
        "style keyframe declarations require a direct overwrite value"
      )
  StyleKeyframe(offset: offset, declarations: @declarations)

proc styleKeyframes*(
    name: string;
    steps: openArray[StyleKeyframe]
): StyleKeyframes =
  let normalized = name.strip
  if normalized.len == 0 or normalized == "none" or normalized.contains(','):
    raise newException(ValueError, "style keyframe name must be one non-empty identifier")
  if steps.len == 0:
    raise newException(ValueError, "style keyframes must contain at least one step")
  var previous = -1.0
  for step in steps:
    if step.offset < previous:
      raise newException(ValueError, "style keyframe offsets must be sorted")
    previous = step.offset
  StyleKeyframes(name: normalized, steps: @steps)

proc validatedCopy(definition: StyleKeyframes): StyleKeyframes =
  var steps: seq[StyleKeyframe]
  for step in definition.steps:
    steps.add styleKeyframe(step.offset, step.declarations)
  styleKeyframes(definition.name, steps)

proc initDeclarativeKeyframeRuntime*(
    targetFramesPerSecond = 60.0
): DeclarativeKeyframeRuntime =
  DeclarativeKeyframeRuntime(
    definitions: initTable[string, RegisteredStyleKeyframes](),
    tracks: initTable[AnimationTrackKey, DeclarativeAnimationTrack](),
    completed: initTable[AnimationTrackKey, CompletedDeclarativeAnimation](),
    clock: initAnimationClock(targetFramesPerSecond),
    nextDefinitionRevision: 1
  )

proc registerStyleKeyframes*(
    runtime: var DeclarativeKeyframeRuntime;
    definition: StyleKeyframes
) =
  let checked = definition.validatedCopy()
  if runtime.nextDefinitionRevision == 0:
    raise newException(ValueError, "style keyframe revision space exhausted")
  runtime.definitions[checked.name] = RegisteredStyleKeyframes(
    definition: checked,
    revision: runtime.nextDefinitionRevision
  )
  inc runtime.nextDefinitionRevision

proc unregisterStyleKeyframes*(
    runtime: var DeclarativeKeyframeRuntime;
    name: string
): bool {.discardable.} =
  let normalized = name.strip
  if normalized notin runtime.definitions:
    return false
  runtime.definitions.del(normalized)
  var activeKeys: seq[AnimationTrackKey]
  for key, track in runtime.tracks.pairs:
    if track.signature.name == normalized:
      activeKeys.add key
  for key in activeKeys:
    discard runtime.clock.cancelAnimation(runtime.tracks[key].animation)
    runtime.tracks.del(key)
  var completedKeys: seq[AnimationTrackKey]
  for key, completed in runtime.completed.pairs:
    if completed.signature.name == normalized:
      completedKeys.add key
  for key in completedKeys:
    runtime.completed.del(key)
  true

proc hasStyleKeyframes*(
    runtime: DeclarativeKeyframeRuntime;
    name: string
): bool =
  name.strip in runtime.definitions

proc resolveStepStyle(
    base: ComputedStyle;
    step: StyleKeyframe;
    viewportSize: Option[Size]
): ComputedStyle =
  result = base
  var diagnostics: Diagnostics
  let registry = defaultProperties()
  let declarations = styleContext(step.declarations).declarations
  let fontSize = base.text.fontSize.get(16.0'f32)
  let lineHeight = base.text.lineHeight.get(fontSize * 1.2'f32)
  let env = ResolveEnv(
    rootFontSize: some(fontSize),
    currentFontSize: some(fontSize),
    rootLineHeight: some(lineHeight),
    currentLineHeight: some(lineHeight),
    viewportSize: viewportSize
  )
  for declaration in declarations:
    let property = registry.getProperty(declaration.property)
    property.apply(result, declaration, env, diagnostics)
  if diagnostics.hasErrors:
    let item = diagnostics.items[0]
    raise newException(
      ValueError,
      "invalid " & item.property & " keyframe declaration: " & item.message
    )

proc ensureFloatEndpoints(
    values: var seq[FloatKeyframe];
    baseValue: float64
) =
  if values.len == 0:
    return
  if values[0].offset > 0:
    values.insert(FloatKeyframe(offset: 0, value: baseValue), 0)
  if values[^1].offset < 1:
    values.add FloatKeyframe(offset: 1, value: baseValue)

proc ensureColorEndpoints(
    values: var seq[PreparedColorKeyframe];
    baseValue: Color
) =
  if values.len == 0:
    return
  let prepared = baseValue.prepareColorInterpolation(cisOklab)
  if values[0].offset > 0:
    values.insert(PreparedColorKeyframe(offset: 0, value: prepared), 0)
  if values[^1].offset < 1:
    values.add PreparedColorKeyframe(offset: 1, value: prepared)

proc ensureTransformEndpoints(
    values: var seq[PreparedTransformKeyframe];
    baseValue: ComputedTransformStyle
) =
  if values.len == 0:
    return
  if values[0].offset > 0:
    values.insert(PreparedTransformKeyframe(
      offset: 0, value: baseValue
    ), 0)
  if values[^1].offset < 1:
    values.add PreparedTransformKeyframe(offset: 1, value: baseValue)

proc containsProperty(step: StyleKeyframe; name: string): bool =
  for declaration in step.declarations:
    if declaration.property == name:
      return true
  false

proc containsTransformProperty(step: StyleKeyframe): bool =
  for declaration in step.declarations:
    if declaration.property in ["transform", "translate", "scale", "rotate"]:
      return true
  false

proc compileTrack(
    definition: RegisteredStyleKeyframes;
    signature: AnimationSignature;
    base: ComputedStyle;
    viewportSize: Option[Size]
): DeclarativeAnimationTrack =
  var opacity: seq[FloatKeyframe]
  var foreground: seq[PreparedColorKeyframe]
  var background: seq[PreparedColorKeyframe]
  var transforms: seq[PreparedTransformKeyframe]
  for step in definition.definition.steps:
    let resolved = base.resolveStepStyle(step, viewportSize)
    if step.containsProperty("opacity"):
      opacity.add FloatKeyframe(
        offset: step.offset,
        value: resolved.visual.opacity.float64
      )
    if step.containsProperty("color"):
      let value = resolved.text.color.get(rgb(0, 0, 0))
      foreground.add PreparedColorKeyframe(
        offset: step.offset,
        value: value.prepareColorInterpolation(cisOklab)
      )
    if step.containsProperty("background-color"):
      let value = resolved.box.backgroundColor.get(rgba(0, 0, 0, 0))
      background.add PreparedColorKeyframe(
        offset: step.offset,
        value: value.prepareColorInterpolation(cisOklab)
      )
    if step.containsTransformProperty():
      transforms.add PreparedTransformKeyframe(
        offset: step.offset,
        value: resolved.transform
      )

  opacity.ensureFloatEndpoints(base.visual.opacity)
  foreground.ensureColorEndpoints(base.text.color.get(rgb(0, 0, 0)))
  background.ensureColorEndpoints(
    base.box.backgroundColor.get(rgba(0, 0, 0, 0))
  )
  transforms.ensureTransformEndpoints(base.transform)
  result.signature = signature
  result.sample = DeclarativeAnimationSample()
  result.baseOpacity = base.visual.opacity
  result.baseColor = base.text.color
  result.baseBackgroundColor = base.box.backgroundColor
  result.baseTransform = base.transform
  if opacity.len > 0:
    result.opacity = some(floatKeyframes(opacity))
  if foreground.len > 0:
    result.color = some(PreparedColorKeyframes(values: foreground))
  if background.len > 0:
    result.backgroundColor = some(PreparedColorKeyframes(values: background))
  if transforms.len > 0:
    result.transform = some(PreparedTransformKeyframes(values: transforms))

proc colorSpan(
    values: openArray[PreparedColorKeyframe];
    progress: float64
): tuple[left, right: int; amount: float64] =
  let value = clamp(progress, 0.0, 1.0)
  if value <= values[0].offset:
    return (0, 0, 0)
  if value >= values[^1].offset:
    return (values.high, values.high, 0)
  for index in 0 ..< values.high:
    if value <= values[index + 1].offset:
      let distance = values[index + 1].offset - values[index].offset
      return (
        index,
        index + 1,
        if distance <= 0: 1 else: (value - values[index].offset) / distance
      )
  (values.high, values.high, 0)

proc sample(values: PreparedColorKeyframes; progress: float64): Color =
  let span = values.values.colorSpan(progress)
  if span.left == span.right:
    return interpolateColor(
      values.values[span.left].value,
      values.values[span.left].value,
      0
    )
  interpolateColor(
    values.values[span.left].value,
    values.values[span.right].value,
    span.amount
  )

proc sample(
    values: PreparedTransformKeyframes;
    progress: float64
): ComputedTransformStyle =
  let value = clamp(progress, 0.0, 1.0)
  if value <= values.values[0].offset:
    return values.values[0].value
  if value >= values.values[^1].offset:
    return values.values[^1].value
  for index in 0 ..< values.values.high:
    let left = values.values[index]
    let right = values.values[index + 1]
    if value <= right.offset:
      let distance = right.offset - left.offset
      let amount =
        if distance <= 0: 1.0
        else: (value - left.offset) / distance
      let interpolated = interpolateTransformStyle(
        left.value, right.value, mtpAll, amount.float32
      )
      if interpolated.isSome:
        return interpolated.get
      return if amount < 0.5: left.value else: right.value
  values.values[^1].value

proc cycled[T](values: seq[T]; fallback: T; index: int): T =
  if values.len == 0:
    fallback
  else:
    values[index mod values.len]

proc animationNames(style: ComputedStyle): seq[string] =
  if style.animation.animationNames.len > 0:
    return style.animation.animationNames
  if style.animation.animationName.isSome:
    return @[style.animation.animationName.get]

proc timingFor(style: ComputedStyle; index: int): TimingFunction =
  let authored = style.animation.animationTimingFunctions.cycled(
    style.animation.animationTimingFunction.get("ease"), index
  )
  if authored.len > 0:
    let timing = parseTimingFunction(authored)
    if timing.isSome:
      return timing.get
  easeTiming()

proc playStateFor(style: ComputedStyle; index: int): AnimationPlayState =
  style.animation.animationPlayStates.cycled(
    style.animation.animationPlayState, index
  )

proc signatureFor(
    style: ComputedStyle;
    definition: RegisteredStyleKeyframes;
    index: int
): AnimationSignature =
  AnimationSignature(
    name: definition.definition.name,
    definitionRevision: definition.revision,
    duration: style.animation.animationDurations.cycled(
      style.animation.animationDuration, index
    ),
    delay: style.animation.animationDelays.cycled(
      style.animation.animationDelay, index
    ),
    iterations: style.animation.animationIterationCounts.cycled(
      style.animation.animationIterationCount, index
    ),
    direction: style.animation.animationDirections.cycled(
      style.animation.animationDirection, index
    ),
    fillMode: style.animation.animationFillModes.cycled(
      style.animation.animationFillMode, index
    ),
    timing: style.timingFor(index),
    composition: style.animation.animationCompositions.cycled(
      style.animation.animationComposition, index
    )
  )

proc cancelTrack(
    runtime: var DeclarativeKeyframeRuntime;
    key: AnimationTrackKey
) =
  if key in runtime.tracks:
    discard runtime.clock.cancelAnimation(runtime.tracks[key].animation)
    runtime.tracks.del(key)

proc rememberCompletion(
    runtime: var DeclarativeKeyframeRuntime;
    key: AnimationTrackKey;
    signature: AnimationSignature;
    retainedTrack = none(DeclarativeAnimationTrack)
) =
  runtime.completed[key] = CompletedDeclarativeAnimation(
    signature: signature,
    retainedTrack: retainedTrack
  )

proc startTrack(
    runtime: var DeclarativeKeyframeRuntime;
    key: AnimationTrackKey;
    definition: RegisteredStyleKeyframes;
    style: ComputedStyle;
    playState: AnimationPlayState;
    viewportSize: Option[Size];
    nowSeconds: float64
) =
  let signature = style.signatureFor(definition, key.index)
  if signature.composition != acReplace or
      (signature.iterations.isSome and signature.iterations.get <= 0):
    runtime.rememberCompletion(key, signature)
    return
  var track = definition.compileTrack(signature, style, viewportSize)
  if track.opacity.isNone and track.color.isNone and
      track.backgroundColor.isNone and track.transform.isNone:
    runtime.rememberCompletion(key, signature)
    return
  let sampleState = track.sample
  let dirtyDomains =
    if track.transform.isSome: {ddPaint, ddHit, ddAnimation}
    else: {ddPaint, ddAnimation}
  let animation = runtime.clock.startAnimation(animationSpec(
    durationSeconds = signature.duration,
    delaySeconds = signature.delay,
    iterations = signature.iterations.map(proc(value: float32): float64 = value),
    direction = signature.direction,
    fillMode = signature.fillMode,
    timing = signature.timing,
    dirtyDomains = dirtyDomains,
    onSample = proc(sample: AnimationSample) =
      sampleState.value = sample
      sampleState.pending = true
      sampleState.initialized = true
  ), nowSeconds)
  track.animation = animation
  if playState == apsPaused:
    track.pauseAfterFirstTick = true
  runtime.tracks[key] = track

proc applySample(
    track: DeclarativeAnimationTrack;
    style: var ComputedStyle
)

proc reconcileAnimations*(
    runtime: var DeclarativeKeyframeRuntime;
    tree: Tree;
    target: var ResolvedTree;
    nowSeconds: float64
) =
  if nowSeconds.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "animation reconciliation time must be finite")
  var desired = initHashSet[AnimationTrackKey]()
  for index, style in target.styles:
    let node = tree.nodeIdAt(index)
    if node.isNone:
      continue
    let id = node.get
    let names = style.animationNames()
    for animationIndex, name in names:
      let key = AnimationTrackKey(node: id, index: animationIndex)
      desired.incl key
      if name notin runtime.definitions:
        runtime.cancelTrack(key)
        runtime.completed.del(key)
        continue
      let definition = runtime.definitions[name]
      let signature = style.signatureFor(definition, animationIndex)
      let playState = style.playStateFor(animationIndex)
      if key in runtime.tracks and runtime.tracks[key].signature == signature:
        var track = runtime.tracks[key]
        if track.sample.initialized:
          track.applySample(target.styles[index])
        let shouldPause = playState == apsPaused
        if shouldPause and not track.paused and not track.pauseAfterFirstTick:
          discard runtime.clock.pauseAnimation(track.animation, nowSeconds)
          track.paused = true
        elif not shouldPause and track.paused:
          discard runtime.clock.resumeAnimation(track.animation, nowSeconds)
          track.paused = false
        if not shouldPause:
          track.pauseAfterFirstTick = false
        runtime.tracks[key] = track
        continue
      if key in runtime.completed and
          runtime.completed[key].signature == signature:
        let completed = runtime.completed[key]
        if completed.retainedTrack.isSome:
          completed.retainedTrack.get.applySample(target.styles[index])
        continue
      runtime.cancelTrack(key)
      runtime.completed.del(key)
      runtime.startTrack(
        key, definition, style, playState, target.viewportSize, nowSeconds
      )

  var stale: seq[AnimationTrackKey]
  for key in runtime.tracks.keys:
    if key notin desired or not tree.isValid(key.node) or
        key.node.nodeIndex >= target.styles.len:
      stale.add key
  for key in stale:
    runtime.cancelTrack(key)
    runtime.completed.del(key)
  stale.setLen(0)
  for key in runtime.completed.keys:
    if key notin desired or not tree.isValid(key.node) or
        key.node.nodeIndex >= target.styles.len:
      stale.add key
  for key in stale:
    runtime.completed.del(key)

proc restoreBase(track: DeclarativeAnimationTrack; style: var ComputedStyle) =
  style.visual.opacity = track.baseOpacity
  style.text.color = track.baseColor
  style.box.backgroundColor = track.baseBackgroundColor
  if track.transform.isSome:
    style.transform = track.baseTransform

proc applySample(
    track: DeclarativeAnimationTrack;
    style: var ComputedStyle
) =
  let sample = track.sample.value
  if sample.phase == apAfter and
      track.signature.fillMode notin {afForwards, afBoth}:
    track.restoreBase(style)
    return
  if track.opacity.isSome:
    style.visual.opacity = track.opacity.get.sample(sample.progress).float32
  if track.color.isSome:
    style.text.color = some(track.color.get.sample(sample.progress))
  if track.backgroundColor.isSome:
    style.box.backgroundColor = some(
      track.backgroundColor.get.sample(sample.progress)
    )
  if track.transform.isSome:
    style.transform = track.transform.get.sample(sample.progress)

proc applyAnimations*(
    runtime: var DeclarativeKeyframeRuntime;
    tree: Tree;
    styles: var ResolvedTree;
    scheduler: var FrameScheduler;
    nowSeconds: float64
): int {.discardable.} =
  if nowSeconds.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "animation time must be finite")
  discard runtime.clock.tickAnimations(scheduler, nowSeconds)
  var orderedKeys = toSeq(runtime.tracks.keys)
  orderedKeys.sort(proc(left, right: AnimationTrackKey): int =
    result = cmp(left.node.nodeIndex, right.node.nodeIndex)
    if result == 0:
      result = cmp(left.index, right.index)
  )
  var completed: seq[AnimationTrackKey]
  for key in orderedKeys:
    if key notin runtime.tracks:
      continue
    if not tree.isValid(key.node) or key.node.nodeIndex >= styles.styles.len:
      completed.add key
      continue
    var track = runtime.tracks[key]
    if track.pauseAfterFirstTick:
      discard runtime.clock.pauseAnimation(track.animation, nowSeconds)
      track.pauseAfterFirstTick = false
      track.paused = true
    if track.sample.pending:
      track.applySample(styles.styles[key.node.nodeIndex])
      track.sample.pending = false
      inc result
    if not runtime.clock.hasAnimation(track.animation):
      let retained =
        if track.signature.fillMode in {afForwards, afBoth}:
          some(track)
        else:
          none(DeclarativeAnimationTrack)
      runtime.rememberCompletion(key, track.signature, retained)
      completed.add key
    else:
      runtime.tracks[key] = track
  for key in completed:
    runtime.tracks.del(key)
  if result > 0:
    var domains = {ddPaint, ddAnimation}
    for track in runtime.tracks.values:
      if track.transform.isSome:
        domains.incl ddHit
        break
    scheduler.markDirty(domains)

proc activeAnimationCount*(runtime: DeclarativeKeyframeRuntime): int =
  runtime.tracks.len

proc setReducedMotion*(
    runtime: var DeclarativeKeyframeRuntime;
    enabled: bool
) =
  runtime.clock.reducedMotion = enabled

proc cancelAnimations*(
    runtime: var DeclarativeKeyframeRuntime;
    nodes: openArray[NodeId]
): int {.discardable.} =
  var requested = initHashSet[NodeId]()
  for node in nodes:
    requested.incl node
  var activeKeys: seq[AnimationTrackKey]
  for key in runtime.tracks.keys:
    if key.node in requested:
      activeKeys.add key
  for key in activeKeys:
    runtime.cancelTrack(key)
    inc result
  var completedKeys: seq[AnimationTrackKey]
  for key in runtime.completed.keys:
    if key.node in requested:
      completedKeys.add key
  for key in completedKeys:
    runtime.completed.del(key)
