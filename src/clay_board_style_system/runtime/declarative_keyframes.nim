import std/[math, options, strutils, tables]

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
import ./[animation_clock, declarative_transition, frame_scheduler, invalidation]

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

  PreparedColorKeyframe = object
    offset: float64
    value: PreparedColorInterpolation

  PreparedColorKeyframes = object
    values: seq[PreparedColorKeyframe]

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
    baseOpacity: float32
    baseColor: Option[Color]
    baseBackgroundColor: Option[Color]
    paused: bool
    pauseAfterFirstTick: bool

  CompletedDeclarativeAnimation = object
    signature: AnimationSignature
    retainedTrack: Option[DeclarativeAnimationTrack]

  DeclarativeKeyframeRuntime* = object
    definitions: Table[string, RegisteredStyleKeyframes]
    tracks: Table[NodeId, DeclarativeAnimationTrack]
    completed: Table[NodeId, CompletedDeclarativeAnimation]
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

proc styleKeyframe*(
    offset: float64;
    declarations: openArray[Declaration]
): StyleKeyframe =
  if offset.classify in {fcNan, fcInf, fcNegInf} or offset < 0 or offset > 1:
    raise newException(
      ValueError, "style keyframe offset must be finite and between zero and one"
    )
  for declaration in declarations:
    if declaration.property notin ["opacity", "color", "background-color"]:
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
    tracks: initTable[NodeId, DeclarativeAnimationTrack](),
    completed: initTable[NodeId, CompletedDeclarativeAnimation](),
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
  var activeNodes: seq[NodeId]
  for node, track in runtime.tracks.pairs:
    if track.signature.name == normalized:
      activeNodes.add node
  for node in activeNodes:
    discard runtime.clock.cancelAnimation(runtime.tracks[node].animation)
    runtime.tracks.del(node)
  var completedNodes: seq[NodeId]
  for node, completed in runtime.completed.pairs:
    if completed.signature.name == normalized:
      completedNodes.add node
  for node in completedNodes:
    runtime.completed.del(node)
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

proc containsProperty(step: StyleKeyframe; name: string): bool =
  for declaration in step.declarations:
    if declaration.property == name:
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

  opacity.ensureFloatEndpoints(base.visual.opacity)
  foreground.ensureColorEndpoints(base.text.color.get(rgb(0, 0, 0)))
  background.ensureColorEndpoints(
    base.box.backgroundColor.get(rgba(0, 0, 0, 0))
  )
  result.signature = signature
  result.sample = DeclarativeAnimationSample()
  result.baseOpacity = base.visual.opacity
  result.baseColor = base.text.color
  result.baseBackgroundColor = base.box.backgroundColor
  if opacity.len > 0:
    result.opacity = some(floatKeyframes(opacity))
  if foreground.len > 0:
    result.color = some(PreparedColorKeyframes(values: foreground))
  if background.len > 0:
    result.backgroundColor = some(PreparedColorKeyframes(values: background))

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

proc timingFor(style: ComputedStyle): TimingFunction =
  if style.animation.animationTimingFunction.isSome:
    let timing = parseTimingFunction(
      style.animation.animationTimingFunction.get
    )
    if timing.isSome:
      return timing.get
  easeTiming()

proc signatureFor(
    style: ComputedStyle;
    definition: RegisteredStyleKeyframes
): AnimationSignature =
  AnimationSignature(
    name: definition.definition.name,
    definitionRevision: definition.revision,
    duration: style.animation.animationDuration,
    delay: style.animation.animationDelay,
    iterations: style.animation.animationIterationCount,
    direction: style.animation.animationDirection,
    fillMode: style.animation.animationFillMode,
    timing: style.timingFor(),
    composition: style.animation.animationComposition
  )

proc cancelTrack(
    runtime: var DeclarativeKeyframeRuntime;
    node: NodeId
) =
  if node in runtime.tracks:
    discard runtime.clock.cancelAnimation(runtime.tracks[node].animation)
    runtime.tracks.del(node)

proc rememberCompletion(
    runtime: var DeclarativeKeyframeRuntime;
    node: NodeId;
    signature: AnimationSignature;
    retainedTrack = none(DeclarativeAnimationTrack)
) =
  runtime.completed[node] = CompletedDeclarativeAnimation(
    signature: signature,
    retainedTrack: retainedTrack
  )

proc startTrack(
    runtime: var DeclarativeKeyframeRuntime;
    node: NodeId;
    definition: RegisteredStyleKeyframes;
    style: ComputedStyle;
    viewportSize: Option[Size];
    nowSeconds: float64
) =
  let signature = style.signatureFor(definition)
  if signature.composition != acReplace or
      (signature.iterations.isSome and signature.iterations.get <= 0):
    runtime.rememberCompletion(node, signature)
    return
  var track = definition.compileTrack(signature, style, viewportSize)
  if track.opacity.isNone and track.color.isNone and
      track.backgroundColor.isNone:
    runtime.rememberCompletion(node, signature)
    return
  let sampleState = track.sample
  let animation = runtime.clock.startAnimation(animationSpec(
    durationSeconds = signature.duration,
    delaySeconds = signature.delay,
    iterations = signature.iterations.map(proc(value: float32): float64 = value),
    direction = signature.direction,
    fillMode = signature.fillMode,
    timing = signature.timing,
    dirtyDomains = {ddPaint, ddAnimation},
    onSample = proc(sample: AnimationSample) =
      sampleState.value = sample
      sampleState.pending = true
      sampleState.initialized = true
  ), nowSeconds)
  track.animation = animation
  if style.animation.animationPlayState == apsPaused:
    track.pauseAfterFirstTick = true
  runtime.tracks[node] = track

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
  for index, style in target.styles:
    let node = tree.nodeIdAt(index)
    if node.isNone:
      continue
    let id = node.get
    if style.animation.animationName.isNone or
        style.animation.animationName.get notin runtime.definitions:
      runtime.cancelTrack(id)
      runtime.completed.del(id)
      continue
    let definition = runtime.definitions[style.animation.animationName.get]
    let signature = style.signatureFor(definition)
    if id in runtime.tracks and runtime.tracks[id].signature == signature:
      var track = runtime.tracks[id]
      if track.sample.initialized:
        track.applySample(target.styles[index])
      let shouldPause = style.animation.animationPlayState == apsPaused
      if shouldPause and not track.paused and not track.pauseAfterFirstTick:
        discard runtime.clock.pauseAnimation(track.animation, nowSeconds)
        track.paused = true
      elif not shouldPause and track.paused:
        discard runtime.clock.resumeAnimation(track.animation, nowSeconds)
        track.paused = false
      if not shouldPause:
        track.pauseAfterFirstTick = false
      runtime.tracks[id] = track
      continue
    if id in runtime.completed and runtime.completed[id].signature == signature:
      let completed = runtime.completed[id]
      if completed.retainedTrack.isSome:
        completed.retainedTrack.get.applySample(target.styles[index])
      continue
    runtime.cancelTrack(id)
    runtime.completed.del(id)
    runtime.startTrack(id, definition, style, target.viewportSize, nowSeconds)

  var stale: seq[NodeId]
  for node in runtime.tracks.keys:
    if not tree.isValid(node) or node.nodeIndex >= target.styles.len:
      stale.add node
  for node in stale:
    runtime.cancelTrack(node)
    runtime.completed.del(node)
  stale.setLen(0)
  for node in runtime.completed.keys:
    if not tree.isValid(node) or node.nodeIndex >= target.styles.len:
      stale.add node
  for node in stale:
    runtime.completed.del(node)

proc restoreBase(track: DeclarativeAnimationTrack; style: var ComputedStyle) =
  style.visual.opacity = track.baseOpacity
  style.text.color = track.baseColor
  style.box.backgroundColor = track.baseBackgroundColor

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
  var completed: seq[NodeId]
  for node, track in runtime.tracks.mpairs:
    if not tree.isValid(node) or node.nodeIndex >= styles.styles.len:
      completed.add node
      continue
    if track.pauseAfterFirstTick:
      discard runtime.clock.pauseAnimation(track.animation, nowSeconds)
      track.pauseAfterFirstTick = false
      track.paused = true
    if track.sample.pending:
      track.applySample(styles.styles[node.nodeIndex])
      track.sample.pending = false
      inc result
    if not runtime.clock.hasAnimation(track.animation):
      let retained =
        if track.signature.fillMode in {afForwards, afBoth}:
          some(track)
        else:
          none(DeclarativeAnimationTrack)
      runtime.rememberCompletion(node, track.signature, retained)
      completed.add node
  for node in completed:
    runtime.tracks.del(node)
  if result > 0:
    scheduler.markDirty({ddPaint, ddAnimation})

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
  for node in nodes:
    if node in runtime.tracks:
      runtime.cancelTrack(node)
      inc result
    runtime.completed.del(node)
