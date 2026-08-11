import std/[math, options, parseutils, strutils]
import ../core/[computed_style, declaration, diagnostics, property, style_value]

proc requireKeyword(
    declaration: Declaration;
    diagnostics: var Diagnostics
): Option[string]

proc splitMotionList(value: string): Option[seq[string]] =
  result = some(newSeq[string]())
  var depth = 0
  var start = 0
  for index, character in value:
    case character
    of '(':
      inc depth
    of ')':
      dec depth
      if depth < 0:
        return none(seq[string])
    of ',':
      if depth == 0:
        let item = value[start ..< index].strip
        if item.len == 0:
          return none(seq[string])
        result.get.add item
        start = index + 1
    else:
      discard
  if depth != 0:
    return none(seq[string])
  let item = value[start .. ^1].strip
  if item.len == 0:
    return none(seq[string])
  result.get.add item

proc requireKeywordList(
    declaration: Declaration;
    diagnostics: var Diagnostics
): Option[seq[string]] =
  let value = requireKeyword(declaration, diagnostics)
  if value.isNone:
    return none(seq[string])
  result = splitMotionList(value.get)
  if result.isNone:
    diagnostics.addError(
      declaration.property,
      declaration.property & " requires a non-empty comma-separated list"
    )

proc requireNumberList(
    declaration: Declaration;
    diagnostics: var Diagnostics
): Option[seq[float32]] =
  if declaration.operation.value.isNone:
    diagnostics.addError(
      declaration.property, declaration.property & " requires a number list"
    )
    return none(seq[float32])
  let value = declaration.operation.value.get
  if value.kind == svNumber:
    if value.number.classify in {fcNan, fcInf, fcNegInf}:
      diagnostics.addError(
        declaration.property,
        declaration.property & " contains an invalid finite number"
      )
      return none(seq[float32])
    return some(@[value.number])
  if value.kind != svKeyword:
    diagnostics.addError(
      declaration.property, declaration.property & " requires a number list"
    )
    return none(seq[float32])
  let items = splitMotionList(value.keyword)
  if items.isNone:
    diagnostics.addError(
      declaration.property, declaration.property & " has an invalid number list"
    )
    return none(seq[float32])
  var values: seq[float32]
  for item in items.get:
    var parsed: float
    let consumed = parseFloat(item, parsed)
    if consumed != item.len or parsed.classify in {fcNan, fcInf, fcNegInf}:
      diagnostics.addError(
        declaration.property,
        declaration.property & " contains an invalid finite number"
      )
      return none(seq[float32])
    let normalized = parsed.float32
    if normalized.classify in {fcNan, fcInf, fcNegInf}:
      diagnostics.addError(
        declaration.property,
        declaration.property & " contains a number outside the supported range"
      )
      return none(seq[float32])
    values.add normalized
  some(values)

proc requireIterationList(
    declaration: Declaration;
    diagnostics: var Diagnostics
): Option[seq[Option[float32]]] =
  if declaration.operation.value.isNone:
    diagnostics.addError(
      declaration.property,
      "animation-iteration-count requires numbers or infinite"
    )
    return none(seq[Option[float32]])
  let value = declaration.operation.value.get
  let items =
    case value.kind
    of svNumber: @[ $value.number ]
    of svKeyword:
      let parsed = splitMotionList(value.keyword)
      if parsed.isNone:
        diagnostics.addError(
          declaration.property, "invalid animation iteration list"
        )
        return none(seq[Option[float32]])
      parsed.get
    else:
      diagnostics.addError(
        declaration.property,
        "animation-iteration-count requires numbers or infinite"
      )
      return none(seq[Option[float32]])
  var resultValues: seq[Option[float32]]
  for item in items:
    if item == "infinite":
      resultValues.add none(float32)
      continue
    var parsed: float
    let consumed = parseFloat(item, parsed)
    let normalized = parsed.float32
    if consumed != item.len or parsed.classify in {fcNan, fcInf, fcNegInf} or
        normalized.classify in {fcNan, fcInf, fcNegInf} or normalized < 0:
      diagnostics.addError(
        declaration.property, "invalid animation iteration count"
      )
      return none(seq[Option[float32]])
    resultValues.add some(normalized)
  some(resultValues)

proc requireKeyword(declaration: Declaration; diagnostics: var Diagnostics): Option[string] =
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, declaration.property & " requires a keyword value")
    return none(string)
  some(declaration.operation.value.get.keyword)

proc applyRawAnimation(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone:
      return
    if value.get == "none":
      style.animation.rawAnimation = none(string)
      style.animation.animationName = none(string)
    else:
      style.animation.rawAnimation = value
  of mmInitial, mmUnset:
    style.animation.rawAnimation = none(string)
    style.animation.animationName = none(string)
    style.animation.animationDuration = 0
    style.animation.animationDelay = 0
    style.animation.animationTimingFunction = some("ease")
    style.animation.animationIterationCount = some(1.0'f32)
    style.animation.animationDirection = adNormal
    style.animation.animationFillMode = afNone
    style.animation.animationPlayState = apsRunning
    style.animation.animationComposition = acReplace
    style.animation.animationNames.setLen(0)
    style.animation.animationDurations.setLen(0)
    style.animation.animationDelays.setLen(0)
    style.animation.animationTimingFunctions.setLen(0)
    style.animation.animationIterationCounts.setLen(0)
    style.animation.animationDirections.setLen(0)
    style.animation.animationFillModes.setLen(0)
    style.animation.animationPlayStates.setLen(0)
    style.animation.animationCompositions.setLen(0)
  of mmInherit:
    if env.parent.isSome:
      style.animation = env.parent.get.animation
    else:
      diagnostics.addError(declaration.property, "cannot inherit animation without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "animation does not support relative merge")

proc applyAnimationName(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let values = requireKeywordList(declaration, diagnostics)
    if values.isNone:
      return
    if "none" in values.get and values.get.len != 1:
      diagnostics.addError(
        declaration.property, "animation-name cannot mix none with other names"
      )
      return
    if values.get == @["none"]:
      style.animation.animationName = none(string)
      style.animation.animationNames.setLen(0)
    else:
      style.animation.animationName = some(values.get[0])
      style.animation.animationNames = values.get
  of mmInitial, mmUnset:
    style.animation.animationName = none(string)
    style.animation.animationNames.setLen(0)
  of mmInherit:
    if env.parent.isSome:
      style.animation.animationName = env.parent.get.animation.animationName
      style.animation.animationNames = env.parent.get.animation.animationNames
    else:
      diagnostics.addError(declaration.property, "cannot inherit animation-name without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "animation-name does not support relative merge")

proc applyAnimationTime(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let values = requireNumberList(declaration, diagnostics)
    if values.isNone:
      return
    if declaration.property == "animation-duration":
      for value in values.get:
        if value < 0:
          diagnostics.addError(
            declaration.property, "animation-duration values cannot be negative"
          )
          return
      style.animation.animationDurations = values.get
      style.animation.animationDuration = values.get[0]
    else:
      style.animation.animationDelays = values.get
      style.animation.animationDelay = values.get[0]
  of mmInitial, mmUnset:
    if declaration.property == "animation-duration":
      style.animation.animationDuration = 0
      style.animation.animationDurations.setLen(0)
    else:
      style.animation.animationDelay = 0
      style.animation.animationDelays.setLen(0)
  of mmInherit:
    if env.parent.isSome:
      if declaration.property == "animation-duration":
        style.animation.animationDuration = env.parent.get.animation.animationDuration
        style.animation.animationDurations = env.parent.get.animation.animationDurations
      else:
        style.animation.animationDelay = env.parent.get.animation.animationDelay
        style.animation.animationDelays = env.parent.get.animation.animationDelays
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc applyAnimationTimingFunction(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let values = requireKeywordList(declaration, diagnostics)
    if values.isNone:
      return
    style.animation.animationTimingFunction = some(values.get[0])
    style.animation.animationTimingFunctions = values.get
  of mmInitial, mmUnset:
    style.animation.animationTimingFunction = some("ease")
    style.animation.animationTimingFunctions.setLen(0)
  of mmInherit:
    if env.parent.isSome:
      style.animation.animationTimingFunction = env.parent.get.animation.animationTimingFunction
      style.animation.animationTimingFunctions = env.parent.get.animation.animationTimingFunctions
    else:
      diagnostics.addError(declaration.property, "cannot inherit animation-timing-function without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "animation-timing-function does not support relative merge")

proc applyAnimationIterationCount(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let values = requireIterationList(declaration, diagnostics)
    if values.isNone:
      return
    style.animation.animationIterationCount = values.get[0]
    style.animation.animationIterationCounts = values.get
  of mmInitial, mmUnset:
    style.animation.animationIterationCount = some(1.0'f32)
    style.animation.animationIterationCounts.setLen(0)
  of mmInherit:
    if env.parent.isSome:
      style.animation.animationIterationCount = env.parent.get.animation.animationIterationCount
      style.animation.animationIterationCounts = env.parent.get.animation.animationIterationCounts
    else:
      diagnostics.addError(declaration.property, "cannot inherit animation-iteration-count without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "animation-iteration-count does not support relative merge")

proc applyAnimationDirection(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.animation.animationDirection = adNormal
    style.animation.animationDirections.setLen(0)
    return
  if declaration.operation.mode == mmInherit:
    if env.parent.isSome:
      style.animation.animationDirection = env.parent.get.animation.animationDirection
      style.animation.animationDirections = env.parent.get.animation.animationDirections
    else:
      diagnostics.addError(declaration.property, "cannot inherit animation-direction without parent")
    return
  if declaration.operation.mode == mmRelative:
    diagnostics.addError(declaration.property, "animation-direction does not support relative merge")
    return
  let values = requireKeywordList(declaration, diagnostics)
  if values.isNone:
    return
  var parsed: seq[AnimationDirection]
  for value in values.get:
    case value
    of "normal": parsed.add adNormal
    of "reverse": parsed.add adReverse
    of "alternate": parsed.add adAlternate
    of "alternate-reverse": parsed.add adAlternateReverse
    else:
      diagnostics.addError(declaration.property, "unsupported animation-direction keyword")
      return
  style.animation.animationDirection = parsed[0]
  style.animation.animationDirections = parsed

proc applyAnimationFillMode(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.animation.animationFillMode = afNone
    style.animation.animationFillModes.setLen(0)
    return
  if declaration.operation.mode == mmInherit:
    if env.parent.isSome:
      style.animation.animationFillMode = env.parent.get.animation.animationFillMode
      style.animation.animationFillModes = env.parent.get.animation.animationFillModes
    else:
      diagnostics.addError(declaration.property, "cannot inherit animation-fill-mode without parent")
    return
  if declaration.operation.mode == mmRelative:
    diagnostics.addError(declaration.property, "animation-fill-mode does not support relative merge")
    return
  let values = requireKeywordList(declaration, diagnostics)
  if values.isNone:
    return
  var parsed: seq[AnimationFillMode]
  for value in values.get:
    case value
    of "none": parsed.add afNone
    of "forwards": parsed.add afForwards
    of "backwards": parsed.add afBackwards
    of "both": parsed.add afBoth
    else:
      diagnostics.addError(declaration.property, "unsupported animation-fill-mode keyword")
      return
  style.animation.animationFillMode = parsed[0]
  style.animation.animationFillModes = parsed

proc applyAnimationPlayState(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.animation.animationPlayState = apsRunning
    style.animation.animationPlayStates.setLen(0)
    return
  if declaration.operation.mode == mmInherit:
    if env.parent.isSome:
      style.animation.animationPlayState = env.parent.get.animation.animationPlayState
      style.animation.animationPlayStates = env.parent.get.animation.animationPlayStates
    else:
      diagnostics.addError(declaration.property, "cannot inherit animation-play-state without parent")
    return
  if declaration.operation.mode == mmRelative:
    diagnostics.addError(declaration.property, "animation-play-state does not support relative merge")
    return
  let values = requireKeywordList(declaration, diagnostics)
  if values.isNone:
    return
  var parsed: seq[AnimationPlayState]
  for value in values.get:
    case value
    of "running": parsed.add apsRunning
    of "paused": parsed.add apsPaused
    else:
      diagnostics.addError(declaration.property, "unsupported animation-play-state keyword")
      return
  style.animation.animationPlayState = parsed[0]
  style.animation.animationPlayStates = parsed

proc applyAnimationComposition(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.animation.animationComposition = acReplace
    style.animation.animationCompositions.setLen(0)
    return
  if declaration.operation.mode == mmInherit:
    if env.parent.isSome:
      style.animation.animationComposition = env.parent.get.animation.animationComposition
      style.animation.animationCompositions = env.parent.get.animation.animationCompositions
    else:
      diagnostics.addError(declaration.property, "cannot inherit animation-composition without parent")
    return
  if declaration.operation.mode == mmRelative:
    diagnostics.addError(declaration.property, "animation-composition does not support relative merge")
    return
  let values = requireKeywordList(declaration, diagnostics)
  if values.isNone:
    return
  var parsed: seq[AnimationComposition]
  for value in values.get:
    case value
    of "replace": parsed.add acReplace
    of "add": parsed.add acAdd
    of "accumulate": parsed.add acAccumulate
    else:
      diagnostics.addError(declaration.property, "unsupported animation-composition keyword")
      return
  style.animation.animationComposition = parsed[0]
  style.animation.animationCompositions = parsed

proc applyAnimationPassthrough(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone:
      return
    case declaration.property
    of "animation-range":
      style.animation.animationRange = value
    of "animation-range-start":
      style.animation.animationRangeStart = value
    of "animation-range-end":
      style.animation.animationRangeEnd = value
    of "animation-timeline":
      style.animation.animationTimeline = value
    of "animation-trigger":
      style.animation.animationTrigger = value
    of "timeline-trigger":
      style.animation.timelineTrigger = value
    of "timeline-trigger-activation-range":
      style.animation.timelineTriggerActivationRange = value
    of "timeline-trigger-activation-range-end":
      style.animation.timelineTriggerActivationRangeEnd = value
    of "timeline-trigger-activation-range-start":
      style.animation.timelineTriggerActivationRangeStart = value
    of "timeline-trigger-active-range":
      style.animation.timelineTriggerActiveRange = value
    of "timeline-trigger-active-range-end":
      style.animation.timelineTriggerActiveRangeEnd = value
    of "timeline-trigger-active-range-start":
      style.animation.timelineTriggerActiveRangeStart = value
    of "timeline-trigger-name":
      style.animation.timelineTriggerName = value
    of "timeline-trigger-source":
      style.animation.timelineTriggerSource = value
    of "trigger-scope":
      style.animation.triggerScope = value
    else:
      discard
  of mmInitial, mmUnset:
    case declaration.property
    of "animation-range":
      style.animation.animationRange = none(string)
    of "animation-range-start":
      style.animation.animationRangeStart = none(string)
    of "animation-range-end":
      style.animation.animationRangeEnd = none(string)
    of "animation-timeline":
      style.animation.animationTimeline = none(string)
    of "animation-trigger":
      style.animation.animationTrigger = none(string)
    of "timeline-trigger":
      style.animation.timelineTrigger = none(string)
    of "timeline-trigger-activation-range":
      style.animation.timelineTriggerActivationRange = none(string)
    of "timeline-trigger-activation-range-end":
      style.animation.timelineTriggerActivationRangeEnd = none(string)
    of "timeline-trigger-activation-range-start":
      style.animation.timelineTriggerActivationRangeStart = none(string)
    of "timeline-trigger-active-range":
      style.animation.timelineTriggerActiveRange = none(string)
    of "timeline-trigger-active-range-end":
      style.animation.timelineTriggerActiveRangeEnd = none(string)
    of "timeline-trigger-active-range-start":
      style.animation.timelineTriggerActiveRangeStart = none(string)
    of "timeline-trigger-name":
      style.animation.timelineTriggerName = none(string)
    of "timeline-trigger-source":
      style.animation.timelineTriggerSource = none(string)
    of "trigger-scope":
      style.animation.triggerScope = none(string)
    else:
      discard
  of mmInherit:
    if env.parent.isSome:
      case declaration.property
      of "animation-range":
        style.animation.animationRange = env.parent.get.animation.animationRange
      of "animation-range-start":
        style.animation.animationRangeStart = env.parent.get.animation.animationRangeStart
      of "animation-range-end":
        style.animation.animationRangeEnd = env.parent.get.animation.animationRangeEnd
      of "animation-timeline":
        style.animation.animationTimeline = env.parent.get.animation.animationTimeline
      of "animation-trigger":
        style.animation.animationTrigger = env.parent.get.animation.animationTrigger
      of "timeline-trigger":
        style.animation.timelineTrigger = env.parent.get.animation.timelineTrigger
      of "timeline-trigger-activation-range":
        style.animation.timelineTriggerActivationRange = env.parent.get.animation.timelineTriggerActivationRange
      of "timeline-trigger-activation-range-end":
        style.animation.timelineTriggerActivationRangeEnd = env.parent.get.animation.timelineTriggerActivationRangeEnd
      of "timeline-trigger-activation-range-start":
        style.animation.timelineTriggerActivationRangeStart = env.parent.get.animation.timelineTriggerActivationRangeStart
      of "timeline-trigger-active-range":
        style.animation.timelineTriggerActiveRange = env.parent.get.animation.timelineTriggerActiveRange
      of "timeline-trigger-active-range-end":
        style.animation.timelineTriggerActiveRangeEnd = env.parent.get.animation.timelineTriggerActiveRangeEnd
      of "timeline-trigger-active-range-start":
        style.animation.timelineTriggerActiveRangeStart = env.parent.get.animation.timelineTriggerActiveRangeStart
      of "timeline-trigger-name":
        style.animation.timelineTriggerName = env.parent.get.animation.timelineTriggerName
      of "timeline-trigger-source":
        style.animation.timelineTriggerSource = env.parent.get.animation.timelineTriggerSource
      of "trigger-scope":
        style.animation.triggerScope = env.parent.get.animation.triggerScope
      else:
        discard
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc applyRawTransition(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    style.animation.rawTransition = requireKeyword(declaration, diagnostics)
  of mmInitial, mmUnset:
    style.animation.rawTransition = none(string)
    style.animation.transitionProperty = some("all")
    style.animation.transitionDuration = 0
    style.animation.transitionDelay = 0
    style.animation.transitionTimingFunction = some("ease")
    style.animation.transitionBehavior = tbNormal
    style.animation.transitionProperties.setLen(0)
    style.animation.transitionDurations.setLen(0)
    style.animation.transitionDelays.setLen(0)
    style.animation.transitionTimingFunctions.setLen(0)
    style.animation.transitionBehaviors.setLen(0)
  of mmInherit:
    if env.parent.isSome:
      style.animation.rawTransition = env.parent.get.animation.rawTransition
    else:
      diagnostics.addError(declaration.property, "cannot inherit transition without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "transition does not support relative merge")

proc applyTransitionProperty(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let values = requireKeywordList(declaration, diagnostics)
    if values.isNone:
      return
    if "none" in values.get and values.get.len != 1:
      diagnostics.addError(
        declaration.property, "transition-property cannot mix none with other values"
      )
      return
    if values.get == @["none"]:
      style.animation.transitionProperty = none(string)
      style.animation.transitionProperties.setLen(0)
    else:
      style.animation.transitionProperty = some(values.get.join(", "))
      style.animation.transitionProperties = values.get
  of mmInitial, mmUnset:
    style.animation.transitionProperty = some("all")
    style.animation.transitionProperties.setLen(0)
  of mmInherit:
    if env.parent.isSome:
      style.animation.transitionProperty = env.parent.get.animation.transitionProperty
      style.animation.transitionProperties = env.parent.get.animation.transitionProperties
    else:
      diagnostics.addError(declaration.property, "cannot inherit transition-property without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "transition-property does not support relative merge")

proc applyTransitionTime(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let values = requireNumberList(declaration, diagnostics)
    if values.isNone:
      return
    if declaration.property == "transition-duration":
      for value in values.get:
        if value < 0:
          diagnostics.addError(
            declaration.property, "transition-duration values cannot be negative"
          )
          return
      style.animation.transitionDurations = values.get
      style.animation.transitionDuration = values.get[0]
    else:
      # A negative delay starts the transition partway through its active
      # interval, matching CSS transition timing semantics.
      style.animation.transitionDelays = values.get
      style.animation.transitionDelay = values.get[0]
  of mmInitial, mmUnset:
    if declaration.property == "transition-duration":
      style.animation.transitionDuration = 0
      style.animation.transitionDurations.setLen(0)
    else:
      style.animation.transitionDelay = 0
      style.animation.transitionDelays.setLen(0)
  of mmInherit:
    if env.parent.isSome:
      if declaration.property == "transition-duration":
        style.animation.transitionDuration = env.parent.get.animation.transitionDuration
        style.animation.transitionDurations = env.parent.get.animation.transitionDurations
      else:
        style.animation.transitionDelay = env.parent.get.animation.transitionDelay
        style.animation.transitionDelays = env.parent.get.animation.transitionDelays
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc applyTransitionTimingFunction(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    let values = requireKeywordList(declaration, diagnostics)
    if values.isNone:
      return
    style.animation.transitionTimingFunctions = values.get
    style.animation.transitionTimingFunction = some(values.get[0])
  of mmInitial, mmUnset:
    style.animation.transitionTimingFunction = some("ease")
    style.animation.transitionTimingFunctions.setLen(0)
  of mmInherit:
    if env.parent.isSome:
      style.animation.transitionTimingFunction = env.parent.get.animation.transitionTimingFunction
      style.animation.transitionTimingFunctions = env.parent.get.animation.transitionTimingFunctions
    else:
      diagnostics.addError(declaration.property, "cannot inherit transition-timing-function without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "transition-timing-function does not support relative merge")

proc applyTransitionBehavior(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "transition-behavior only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.animation.transitionBehavior = tbNormal
    style.animation.transitionBehaviors.setLen(0)
    return
  let values = requireKeywordList(declaration, diagnostics)
  if values.isNone:
    return
  var behaviors: seq[TransitionBehavior]
  for value in values.get:
    case value
    of "normal":
      behaviors.add tbNormal
    of "allow-discrete":
      behaviors.add tbAllowDiscrete
    else:
      diagnostics.addError(
        declaration.property, "unsupported transition-behavior keyword"
      )
      return
  style.animation.transitionBehaviors = behaviors
  style.animation.transitionBehavior = behaviors[0]

let animationProperty* = PropertyImpl(name: "animation", apply: applyRawAnimation)
let animationNameProperty* = PropertyImpl(name: "animation-name", apply: applyAnimationName)
let animationDurationProperty* = PropertyImpl(name: "animation-duration", apply: applyAnimationTime)
let animationDelayProperty* = PropertyImpl(name: "animation-delay", apply: applyAnimationTime)
let animationTimingFunctionProperty* = PropertyImpl(name: "animation-timing-function", apply: applyAnimationTimingFunction)
let animationIterationCountProperty* = PropertyImpl(name: "animation-iteration-count", apply: applyAnimationIterationCount)
let animationDirectionProperty* = PropertyImpl(name: "animation-direction", apply: applyAnimationDirection)
let animationFillModeProperty* = PropertyImpl(name: "animation-fill-mode", apply: applyAnimationFillMode)
let animationPlayStateProperty* = PropertyImpl(name: "animation-play-state", apply: applyAnimationPlayState)
let animationCompositionProperty* = PropertyImpl(name: "animation-composition", apply: applyAnimationComposition)
let animationRangeProperty* = PropertyImpl(name: "animation-range", apply: applyAnimationPassthrough)
let animationRangeStartProperty* = PropertyImpl(name: "animation-range-start", apply: applyAnimationPassthrough)
let animationRangeEndProperty* = PropertyImpl(name: "animation-range-end", apply: applyAnimationPassthrough)
let animationTimelineProperty* = PropertyImpl(name: "animation-timeline", apply: applyAnimationPassthrough)
let animationTriggerProperty* = PropertyImpl(name: "animation-trigger", apply: applyAnimationPassthrough)
let timelineTriggerProperty* = PropertyImpl(name: "timeline-trigger", apply: applyAnimationPassthrough)
let timelineTriggerActivationRangeProperty* = PropertyImpl(name: "timeline-trigger-activation-range", apply: applyAnimationPassthrough)
let timelineTriggerActivationRangeEndProperty* = PropertyImpl(name: "timeline-trigger-activation-range-end", apply: applyAnimationPassthrough)
let timelineTriggerActivationRangeStartProperty* = PropertyImpl(name: "timeline-trigger-activation-range-start", apply: applyAnimationPassthrough)
let timelineTriggerActiveRangeProperty* = PropertyImpl(name: "timeline-trigger-active-range", apply: applyAnimationPassthrough)
let timelineTriggerActiveRangeEndProperty* = PropertyImpl(name: "timeline-trigger-active-range-end", apply: applyAnimationPassthrough)
let timelineTriggerActiveRangeStartProperty* = PropertyImpl(name: "timeline-trigger-active-range-start", apply: applyAnimationPassthrough)
let timelineTriggerNameProperty* = PropertyImpl(name: "timeline-trigger-name", apply: applyAnimationPassthrough)
let timelineTriggerSourceProperty* = PropertyImpl(name: "timeline-trigger-source", apply: applyAnimationPassthrough)
let triggerScopeProperty* = PropertyImpl(name: "trigger-scope", apply: applyAnimationPassthrough)
let transitionProperty* = PropertyImpl(name: "transition", apply: applyRawTransition)
let transitionPropertyProperty* = PropertyImpl(name: "transition-property", apply: applyTransitionProperty)
let transitionDurationProperty* = PropertyImpl(name: "transition-duration", apply: applyTransitionTime)
let transitionDelayProperty* = PropertyImpl(name: "transition-delay", apply: applyTransitionTime)
let transitionTimingFunctionProperty* = PropertyImpl(name: "transition-timing-function", apply: applyTransitionTimingFunction)
let transitionBehaviorProperty* = PropertyImpl(name: "transition-behavior", apply: applyTransitionBehavior)
