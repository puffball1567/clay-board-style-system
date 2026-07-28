import std/options
import ../core/[computed_style, declaration, diagnostics, property, style_value]

proc requireKeyword(declaration: Declaration; diagnostics: var Diagnostics): Option[string] =
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, declaration.property & " requires a keyword value")
    return none(string)
  some(declaration.operation.value.get.keyword)

proc requireNumber(declaration: Declaration; diagnostics: var Diagnostics): Option[float32] =
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svNumber:
    diagnostics.addError(declaration.property, declaration.property & " requires a number value")
    return none(float32)
  some(declaration.operation.value.get.number)

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
    let value = requireKeyword(declaration, diagnostics)
    if value.isNone:
      return
    if value.get == "none":
      style.animation.animationName = none(string)
    else:
      style.animation.animationName = value
  of mmInitial, mmUnset:
    style.animation.animationName = none(string)
  of mmInherit:
    if env.parent.isSome:
      style.animation.animationName = env.parent.get.animation.animationName
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
    let value = requireNumber(declaration, diagnostics)
    if value.isNone:
      return
    let seconds = max(0.0'f32, value.get)
    if declaration.property == "animation-duration":
      style.animation.animationDuration = seconds
    else:
      style.animation.animationDelay = seconds
  of mmInitial, mmUnset:
    if declaration.property == "animation-duration":
      style.animation.animationDuration = 0
    else:
      style.animation.animationDelay = 0
  of mmInherit:
    if env.parent.isSome:
      if declaration.property == "animation-duration":
        style.animation.animationDuration = env.parent.get.animation.animationDuration
      else:
        style.animation.animationDelay = env.parent.get.animation.animationDelay
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
    style.animation.animationTimingFunction = requireKeyword(declaration, diagnostics)
  of mmInitial, mmUnset:
    style.animation.animationTimingFunction = some("ease")
  of mmInherit:
    if env.parent.isSome:
      style.animation.animationTimingFunction = env.parent.get.animation.animationTimingFunction
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
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "animation-iteration-count requires a number or infinite")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svNumber:
      style.animation.animationIterationCount = some(max(0.0'f32, value.number))
    of svKeyword:
      if value.keyword == "infinite":
        style.animation.animationIterationCount = none(float32)
      else:
        diagnostics.addError(declaration.property, "unsupported animation-iteration-count keyword")
    else:
      diagnostics.addError(declaration.property, "animation-iteration-count requires a number or infinite")
  of mmInitial, mmUnset:
    style.animation.animationIterationCount = some(1.0'f32)
  of mmInherit:
    if env.parent.isSome:
      style.animation.animationIterationCount = env.parent.get.animation.animationIterationCount
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
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "animation-direction only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.animation.animationDirection = adNormal
    return
  let value = requireKeyword(declaration, diagnostics)
  if value.isNone:
    return
  case value.get
  of "normal":
    style.animation.animationDirection = adNormal
  of "reverse":
    style.animation.animationDirection = adReverse
  of "alternate":
    style.animation.animationDirection = adAlternate
  of "alternate-reverse":
    style.animation.animationDirection = adAlternateReverse
  else:
    diagnostics.addError(declaration.property, "unsupported animation-direction keyword")

proc applyAnimationFillMode(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "animation-fill-mode only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.animation.animationFillMode = afNone
    return
  let value = requireKeyword(declaration, diagnostics)
  if value.isNone:
    return
  case value.get
  of "none":
    style.animation.animationFillMode = afNone
  of "forwards":
    style.animation.animationFillMode = afForwards
  of "backwards":
    style.animation.animationFillMode = afBackwards
  of "both":
    style.animation.animationFillMode = afBoth
  else:
    diagnostics.addError(declaration.property, "unsupported animation-fill-mode keyword")

proc applyAnimationPlayState(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "animation-play-state only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.animation.animationPlayState = apsRunning
    return
  let value = requireKeyword(declaration, diagnostics)
  if value.isNone:
    return
  case value.get
  of "running":
    style.animation.animationPlayState = apsRunning
  of "paused":
    style.animation.animationPlayState = apsPaused
  else:
    diagnostics.addError(declaration.property, "unsupported animation-play-state keyword")

proc applyAnimationComposition(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "animation-composition only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.animation.animationComposition = acReplace
    return
  let value = requireKeyword(declaration, diagnostics)
  if value.isNone:
    return
  case value.get
  of "replace":
    style.animation.animationComposition = acReplace
  of "add":
    style.animation.animationComposition = acAdd
  of "accumulate":
    style.animation.animationComposition = acAccumulate
  else:
    diagnostics.addError(declaration.property, "unsupported animation-composition keyword")

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
    let value = requireKeyword(declaration, diagnostics)
    if value.isSome:
      if value.get == "none":
        style.animation.transitionProperty = none(string)
      else:
        style.animation.transitionProperty = value
  of mmInitial, mmUnset:
    style.animation.transitionProperty = some("all")
  of mmInherit:
    if env.parent.isSome:
      style.animation.transitionProperty = env.parent.get.animation.transitionProperty
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
    let value = requireNumber(declaration, diagnostics)
    if value.isNone:
      return
    if declaration.property == "transition-duration":
      style.animation.transitionDuration = max(0.0'f32, value.get)
    else:
      style.animation.transitionDelay = max(0.0'f32, value.get)
  of mmInitial, mmUnset:
    if declaration.property == "transition-duration":
      style.animation.transitionDuration = 0
    else:
      style.animation.transitionDelay = 0
  of mmInherit:
    if env.parent.isSome:
      if declaration.property == "transition-duration":
        style.animation.transitionDuration = env.parent.get.animation.transitionDuration
      else:
        style.animation.transitionDelay = env.parent.get.animation.transitionDelay
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
    style.animation.transitionTimingFunction = requireKeyword(declaration, diagnostics)
  of mmInitial, mmUnset:
    style.animation.transitionTimingFunction = some("ease")
  of mmInherit:
    if env.parent.isSome:
      style.animation.transitionTimingFunction = env.parent.get.animation.transitionTimingFunction
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
    return
  let value = requireKeyword(declaration, diagnostics)
  if value.isNone:
    return
  case value.get
  of "normal":
    style.animation.transitionBehavior = tbNormal
  of "allow-discrete":
    style.animation.transitionBehavior = tbAllowDiscrete
  else:
    diagnostics.addError(declaration.property, "unsupported transition-behavior keyword")

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
