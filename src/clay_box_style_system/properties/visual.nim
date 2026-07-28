import std/options
import ../core/[color, computed_style, declaration, diagnostics, property, style_value]

proc clampOpacity(value: float32): float32 =
  max(0.0'f32, min(1.0'f32, value))

proc applyVisibility(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "visibility only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.visual.visible = true
    return
  if declaration.operation.value.isSome and declaration.operation.value.get.kind == svKeyword:
    case declaration.operation.value.get.keyword
    of "visible":
      style.visual.visible = true
    of "hidden":
      style.visual.visible = false
    else:
      diagnostics.addError(declaration.property, "unsupported visibility keyword")
  else:
    diagnostics.addError(declaration.property, "visibility requires a keyword value")

proc applyOpacity(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or declaration.operation.value.get.kind != svNumber:
      diagnostics.addError(declaration.property, "opacity requires a number value")
      return
    style.visual.opacity = clampOpacity(declaration.operation.value.get.number)
  of mmInitial, mmUnset:
    style.visual.opacity = 1.0'f32
  of mmInherit:
    if env.parent.isSome:
      style.visual.opacity = env.parent.get.visual.opacity
    else:
      diagnostics.addError(declaration.property, "cannot inherit opacity without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "opacity relative merge is not implemented yet")

let visibilityProperty* = PropertyImpl(name: "visibility", apply: applyVisibility)
let opacityProperty* = PropertyImpl(name: "opacity", apply: applyOpacity)

proc applyColorScheme(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
      diagnostics.addError(declaration.property, "color-scheme requires a keyword value")
      return
    let value = declaration.operation.value.get.keyword
    if value == "normal":
      style.visual.colorScheme = none(string)
    else:
      style.visual.colorScheme = some(value)
  of mmInitial, mmUnset:
    style.visual.colorScheme = none(string)
  of mmInherit:
    if env.parent.isSome:
      style.visual.colorScheme = env.parent.get.visual.colorScheme
    else:
      diagnostics.addError(declaration.property, "cannot inherit color-scheme without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "color-scheme does not support relative merge")

proc applyForcedColorAdjust(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "forced-color-adjust only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.visual.forcedColorAdjust = caAuto
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "forced-color-adjust requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "auto":
    style.visual.forcedColorAdjust = caAuto
  of "none":
    style.visual.forcedColorAdjust = caNone
  else:
    diagnostics.addError(declaration.property, "unsupported forced-color-adjust keyword")

proc applyPrintColorAdjust(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "print-color-adjust only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.visual.printColorAdjust = pcaEconomy
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "print-color-adjust requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "economy":
    style.visual.printColorAdjust = pcaEconomy
  of "exact":
    style.visual.printColorAdjust = pcaExact
  else:
    diagnostics.addError(declaration.property, "unsupported print-color-adjust keyword")

proc applyWillChange(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
      diagnostics.addError(declaration.property, "will-change requires a keyword value")
      return
    let value = declaration.operation.value.get.keyword
    if value == "auto":
      style.visual.willChange = none(string)
    else:
      style.visual.willChange = some(value)
  of mmInitial, mmUnset:
    style.visual.willChange = none(string)
  of mmInherit:
    if env.parent.isSome:
      style.visual.willChange = env.parent.get.visual.willChange
    else:
      diagnostics.addError(declaration.property, "cannot inherit will-change without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "will-change does not support relative merge")

let colorSchemeProperty* = PropertyImpl(name: "color-scheme", apply: applyColorScheme)
let forcedColorAdjustProperty* = PropertyImpl(name: "forced-color-adjust", apply: applyForcedColorAdjust)
let printColorAdjustProperty* = PropertyImpl(name: "print-color-adjust", apply: applyPrintColorAdjust)
let willChangeProperty* = PropertyImpl(name: "will-change", apply: applyWillChange)

proc resolvePx(value: StyleValue; property: string; diagnostics: var Diagnostics): Option[float32] =
  if value.kind != svLength or value.length.kind != ukPx:
    diagnostics.addError(property, property & " requires a px length value")
    return none(float32)
  some(value.length.value)

proc applyScrollbarWidth(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "scrollbar-width only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.visual.scrollbarWidth = swAuto
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "scrollbar-width requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "auto":
    style.visual.scrollbarWidth = swAuto
  of "thin":
    style.visual.scrollbarWidth = swThin
  of "none":
    style.visual.scrollbarWidth = swNone
  else:
    diagnostics.addError(declaration.property, "unsupported scrollbar-width keyword")

proc applyScrollbarVisibility(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "scrollbar-visibility only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.visual.scrollbarVisibility = svAlways
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "scrollbar-visibility requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "always":
    style.visual.scrollbarVisibility = svAlways
  of "scrolling":
    style.visual.scrollbarVisibility = svScrolling
  else:
    diagnostics.addError(declaration.property, "unsupported scrollbar-visibility keyword")

proc applyScrollbarColor(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "scrollbar-color requires auto or a color pair")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svKeyword:
      if value.keyword == "auto":
        style.visual.scrollbarThumbColor = none(Color)
        style.visual.scrollbarTrackColor = none(Color)
      else:
        diagnostics.addError(declaration.property, "unsupported scrollbar-color keyword")
    of svColorPair:
      style.visual.scrollbarThumbColor = some(value.firstColor)
      style.visual.scrollbarTrackColor = some(value.secondColor)
    else:
      diagnostics.addError(declaration.property, "scrollbar-color requires auto or a color pair")
  of mmInitial, mmUnset:
    style.visual.scrollbarThumbColor = none(Color)
    style.visual.scrollbarTrackColor = none(Color)
  of mmInherit:
    if env.parent.isSome:
      style.visual.scrollbarThumbColor = env.parent.get.visual.scrollbarThumbColor
      style.visual.scrollbarTrackColor = env.parent.get.visual.scrollbarTrackColor
    else:
      diagnostics.addError(declaration.property, "cannot inherit scrollbar-color without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "scrollbar-color does not support relative merge")

proc applyScrollbarGutter(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
      diagnostics.addError(declaration.property, "scrollbar-gutter requires a keyword value")
      return
    let value = declaration.operation.value.get.keyword
    if value == "auto":
      style.visual.scrollbarGutter = none(string)
    elif value in ["stable", "stable both-edges"]:
      style.visual.scrollbarGutter = some(value)
    else:
      diagnostics.addError(declaration.property, "unsupported scrollbar-gutter keyword")
  of mmInitial, mmUnset:
    style.visual.scrollbarGutter = none(string)
  of mmInherit:
    if env.parent.isSome:
      style.visual.scrollbarGutter = env.parent.get.visual.scrollbarGutter
    else:
      diagnostics.addError(declaration.property, "cannot inherit scrollbar-gutter without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "scrollbar-gutter does not support relative merge")

proc applyScrollBehavior(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "scroll-behavior only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.visual.scrollBehavior = sbAuto
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "scroll-behavior requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "auto":
    style.visual.scrollBehavior = sbAuto
  of "smooth":
    style.visual.scrollBehavior = sbSmooth
  else:
    diagnostics.addError(declaration.property, "unsupported scroll-behavior keyword")

proc parseOverscroll(value: string): Option[OverscrollBehavior] =
  case value
  of "auto":
    some(obAuto)
  of "contain":
    some(obContain)
  of "none":
    some(obNone)
  else:
    none(OverscrollBehavior)

proc setOverscroll(style: var ComputedStyle; property: string; value: OverscrollBehavior) =
  case property
  of "overscroll-behavior":
    style.visual.overscrollBehaviorX = value
    style.visual.overscrollBehaviorY = value
  of "overscroll-behavior-x":
    style.visual.overscrollBehaviorX = value
  of "overscroll-behavior-y":
    style.visual.overscrollBehaviorY = value
  of "overscroll-behavior-block":
    style.visual.overscrollBehaviorBlock = value
  of "overscroll-behavior-inline":
    style.visual.overscrollBehaviorInline = value
  else:
    discard

proc applyOverscrollBehavior(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, declaration.property & " only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.setOverscroll(declaration.property, obAuto)
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, declaration.property & " requires a keyword value")
    return
  let parsed = parseOverscroll(declaration.operation.value.get.keyword)
  if parsed.isSome:
    style.setOverscroll(declaration.property, parsed.get)
  else:
    diagnostics.addError(declaration.property, "unsupported " & declaration.property & " keyword")

proc applyOverflowAnchor(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "overflow-anchor only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.visual.overflowAnchor = true
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "overflow-anchor requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "auto":
    style.visual.overflowAnchor = true
  of "none":
    style.visual.overflowAnchor = false
  else:
    diagnostics.addError(declaration.property, "unsupported overflow-anchor keyword")

proc applyOverflowClipMargin(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "overflow-clip-margin requires a length value")
      return
    let resolved = resolvePx(declaration.operation.value.get, declaration.property, diagnostics)
    if resolved.isSome:
      style.visual.overflowClipMargin = resolved
  of mmInitial, mmUnset:
    style.visual.overflowClipMargin = none(float32)
  of mmInherit:
    if env.parent.isSome:
      style.visual.overflowClipMargin = env.parent.get.visual.overflowClipMargin
    else:
      diagnostics.addError(declaration.property, "cannot inherit overflow-clip-margin without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "overflow-clip-margin does not support relative merge")

proc applyTouchAction(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "touch-action only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.visual.touchAction = taAutoTouch
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "touch-action requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "auto":
    style.visual.touchAction = taAutoTouch
  of "none":
    style.visual.touchAction = taNoneTouch
  of "manipulation":
    style.visual.touchAction = taManipulation
  of "pan-x":
    style.visual.touchAction = taPanX
  of "pan-y":
    style.visual.touchAction = taPanY
  of "pinch-zoom":
    style.visual.touchAction = taPinchZoom
  else:
    diagnostics.addError(declaration.property, "unsupported touch-action keyword")

proc applyReadingFlow(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "reading-flow only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.visual.readingFlow = rfNormal
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "reading-flow requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "normal":
    style.visual.readingFlow = rfNormal
  of "flex-visual":
    style.visual.readingFlow = rfFlexVisual
  of "flex-flow":
    style.visual.readingFlow = rfFlexFlow
  of "grid-rows":
    style.visual.readingFlow = rfGridRows
  of "grid-columns":
    style.visual.readingFlow = rfGridColumns
  of "grid-order":
    style.visual.readingFlow = rfGridOrder
  else:
    diagnostics.addError(declaration.property, "unsupported reading-flow keyword")

proc applyReadingOrder(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or declaration.operation.value.get.kind != svNumber:
      diagnostics.addError(declaration.property, "reading-order requires a number value")
      return
    style.visual.readingOrder = declaration.operation.value.get.number.int
  of mmInitial, mmUnset:
    style.visual.readingOrder = 0
  of mmInherit:
    if env.parent.isSome:
      style.visual.readingOrder = env.parent.get.visual.readingOrder
    else:
      diagnostics.addError(declaration.property, "cannot inherit reading-order without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "reading-order does not support relative merge")

proc setVisualMetadata(style: var ComputedStyle; property: string; value: Option[string]) =
  case property
  of "appearance":
    style.visual.appearance = value
  of "content-visibility":
    style.visual.contentVisibility = value
  of "caret-animation":
    style.visual.caretAnimation = value
  of "caret":
    style.visual.caret = value
  of "caret-shape":
    style.visual.caretShape = value
  of "clip-path":
    style.visual.clipPath = value
  of "clip-rule":
    style.visual.clipRule = value
  of "dynamic-range-limit":
    style.visual.dynamicRangeLimit = value
  of "field-sizing":
    style.visual.fieldSizing = value
  of "interactivity":
    style.visual.interactivity = value
  of "interpolate-size":
    style.visual.interpolateSize = value
  of "overlay":
    style.visual.overlay = value
  of "overflow-block":
    style.visual.overflowBlock = value
  of "overflow-clip-box":
    style.visual.overflowClipBox = value
  of "overflow-inline":
    style.visual.overflowInline = value
  of "interest-delay":
    style.visual.interestDelay = value
  of "interest-delay-end":
    style.visual.interestDelayEnd = value
  of "interest-delay-start":
    style.visual.interestDelayStart = value
  of "scroll-initial-target":
    style.visual.scrollInitialTarget = value
  of "scroll-marker-group":
    style.visual.scrollMarkerGroup = value
  of "scroll-target-group":
    style.visual.scrollTargetGroup = value
  of "view-transition-scope":
    style.visual.viewTransitionScope = value
  of "zoom":
    style.visual.zoom = value
  else:
    discard

proc visualMetadata(style: ComputedStyle; property: string): Option[string] =
  case property
  of "appearance":
    style.visual.appearance
  of "content-visibility":
    style.visual.contentVisibility
  of "caret-animation":
    style.visual.caretAnimation
  of "caret":
    style.visual.caret
  of "caret-shape":
    style.visual.caretShape
  of "clip-path":
    style.visual.clipPath
  of "clip-rule":
    style.visual.clipRule
  of "dynamic-range-limit":
    style.visual.dynamicRangeLimit
  of "field-sizing":
    style.visual.fieldSizing
  of "interactivity":
    style.visual.interactivity
  of "interpolate-size":
    style.visual.interpolateSize
  of "overlay":
    style.visual.overlay
  of "overflow-block":
    style.visual.overflowBlock
  of "overflow-clip-box":
    style.visual.overflowClipBox
  of "overflow-inline":
    style.visual.overflowInline
  of "interest-delay":
    style.visual.interestDelay
  of "interest-delay-end":
    style.visual.interestDelayEnd
  of "interest-delay-start":
    style.visual.interestDelayStart
  of "scroll-initial-target":
    style.visual.scrollInitialTarget
  of "scroll-marker-group":
    style.visual.scrollMarkerGroup
  of "scroll-target-group":
    style.visual.scrollTargetGroup
  of "view-transition-scope":
    style.visual.viewTransitionScope
  of "zoom":
    style.visual.zoom
  else:
    none(string)

proc visualMetadataValue(property: string; value: StyleValue; diagnostics: var Diagnostics): Option[string] =
  case value.kind
  of svKeyword:
    some(value.keyword)
  of svNumber:
    if property == "zoom":
      some($value.number)
    else:
      diagnostics.addError(property, property & " requires a keyword value")
      none(string)
  of svLength:
    if property == "zoom" and value.length.kind == ukPercent:
      some($(value.length.value / 100.0'f32))
    else:
      diagnostics.addError(property, property & " requires a keyword value")
      none(string)
  else:
    diagnostics.addError(property, property & " requires a keyword value")
    none(string)

proc applyVisualMetadata(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, declaration.property & " requires a keyword value")
      return
    let parsed = visualMetadataValue(declaration.property, declaration.operation.value.get, diagnostics)
    if parsed.isNone:
      return
    let value = parsed.get
    if value == "none":
      style.setVisualMetadata(declaration.property, none(string))
    else:
      style.setVisualMetadata(declaration.property, some(value))
  of mmInitial, mmUnset:
    style.setVisualMetadata(declaration.property, none(string))
  of mmInherit:
    if env.parent.isSome:
      style.setVisualMetadata(declaration.property, env.parent.get.visualMetadata(declaration.property))
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

let appearanceProperty* = PropertyImpl(name: "appearance", apply: applyVisualMetadata)
let contentVisibilityProperty* = PropertyImpl(name: "content-visibility", apply: applyVisualMetadata)
let caretProperty* = PropertyImpl(name: "caret", apply: applyVisualMetadata)
let caretAnimationProperty* = PropertyImpl(name: "caret-animation", apply: applyVisualMetadata)
let caretShapeProperty* = PropertyImpl(name: "caret-shape", apply: applyVisualMetadata)
let clipPathProperty* = PropertyImpl(name: "clip-path", apply: applyVisualMetadata)
let clipRuleProperty* = PropertyImpl(name: "clip-rule", apply: applyVisualMetadata)
let dynamicRangeLimitProperty* = PropertyImpl(name: "dynamic-range-limit", apply: applyVisualMetadata)
let fieldSizingProperty* = PropertyImpl(name: "field-sizing", apply: applyVisualMetadata)
let interactivityProperty* = PropertyImpl(name: "interactivity", apply: applyVisualMetadata)
let interpolateSizeProperty* = PropertyImpl(name: "interpolate-size", apply: applyVisualMetadata)
let overlayProperty* = PropertyImpl(name: "overlay", apply: applyVisualMetadata)
let overflowBlockProperty* = PropertyImpl(name: "overflow-block", apply: applyVisualMetadata)
let overflowClipBoxProperty* = PropertyImpl(name: "overflow-clip-box", apply: applyVisualMetadata)
let overflowInlineProperty* = PropertyImpl(name: "overflow-inline", apply: applyVisualMetadata)
let interestDelayProperty* = PropertyImpl(name: "interest-delay", apply: applyVisualMetadata)
let interestDelayEndProperty* = PropertyImpl(name: "interest-delay-end", apply: applyVisualMetadata)
let interestDelayStartProperty* = PropertyImpl(name: "interest-delay-start", apply: applyVisualMetadata)
let scrollInitialTargetProperty* = PropertyImpl(name: "scroll-initial-target", apply: applyVisualMetadata)
let scrollMarkerGroupProperty* = PropertyImpl(name: "scroll-marker-group", apply: applyVisualMetadata)
let scrollTargetGroupProperty* = PropertyImpl(name: "scroll-target-group", apply: applyVisualMetadata)
let viewTransitionScopeProperty* = PropertyImpl(name: "view-transition-scope", apply: applyVisualMetadata)
let zoomProperty* = PropertyImpl(name: "zoom", apply: applyVisualMetadata)

let scrollbarWidthProperty* = PropertyImpl(name: "scrollbar-width", apply: applyScrollbarWidth)
let scrollbarVisibilityProperty* = PropertyImpl(name: "scrollbar-visibility", apply: applyScrollbarVisibility)
let scrollbarColorProperty* = PropertyImpl(name: "scrollbar-color", apply: applyScrollbarColor)
let scrollbarGutterProperty* = PropertyImpl(name: "scrollbar-gutter", apply: applyScrollbarGutter)
let scrollBehaviorProperty* = PropertyImpl(name: "scroll-behavior", apply: applyScrollBehavior)
let overscrollBehaviorProperty* = PropertyImpl(name: "overscroll-behavior", apply: applyOverscrollBehavior)
let overscrollBehaviorXProperty* = PropertyImpl(name: "overscroll-behavior-x", apply: applyOverscrollBehavior)
let overscrollBehaviorYProperty* = PropertyImpl(name: "overscroll-behavior-y", apply: applyOverscrollBehavior)
let overscrollBehaviorBlockProperty* = PropertyImpl(name: "overscroll-behavior-block", apply: applyOverscrollBehavior)
let overscrollBehaviorInlineProperty* = PropertyImpl(name: "overscroll-behavior-inline", apply: applyOverscrollBehavior)
let overflowAnchorProperty* = PropertyImpl(name: "overflow-anchor", apply: applyOverflowAnchor)
let overflowClipMarginProperty* = PropertyImpl(name: "overflow-clip-margin", apply: applyOverflowClipMargin)
let touchActionProperty* = PropertyImpl(name: "touch-action", apply: applyTouchAction)
let readingFlowProperty* = PropertyImpl(name: "reading-flow", apply: applyReadingFlow)
let readingOrderProperty* = PropertyImpl(name: "reading-order", apply: applyReadingOrder)
