import std/[options, strutils]
import ../core/[computed_style, declaration, diagnostics, property, style_value]
import ./length_resolution

proc fixedLength(value: Option[float32]): Option[LengthValue] =
  if value.isSome:
    return some(LengthValue(kind: ukPx, value: value.get))
  none(LengthValue)

proc gapValue(style: ComputedStyle; property: string): Option[LengthValue] =
  if not style.layout.sizing.isNil:
    let sizing = style.layout.sizing[]
    case property
    of "gap":
      if sizing.gap.isSome: return sizing.gap
    of "row-gap":
      if sizing.rowGap.isSome: return sizing.rowGap
    of "column-gap":
      if sizing.columnGap.isSome: return sizing.columnGap
    else:
      discard
  case property
  of "gap": some(LengthValue(kind: ukPx, value: style.layout.gap))
  of "row-gap": fixedLength(style.layout.rowGap)
  of "column-gap": fixedLength(style.layout.columnGap)
  else: none(LengthValue)

proc setGapValue(style: var ComputedStyle; property: string; value: Option[LengthValue]) =
  let pixelValue =
    if value.isSome and value.get.kind == ukPx: some(value.get.value)
    else: none(float32)
  if value.isSome and value.get.kind != ukPx:
    style.ensureSizing()
  case property
  of "gap":
    style.layout.gap = if pixelValue.isSome: pixelValue.get else: 0.0'f32
    if not style.layout.sizing.isNil:
      style.layout.sizing.gap = if pixelValue.isSome: none(LengthValue) else: value
  of "row-gap":
    style.layout.rowGap = pixelValue
    if not style.layout.sizing.isNil:
      style.layout.sizing.rowGap = if pixelValue.isSome: none(LengthValue) else: value
  of "column-gap":
    style.layout.columnGap = pixelValue
    if not style.layout.sizing.isNil:
      style.layout.sizing.columnGap = if pixelValue.isSome: none(LengthValue) else: value
  else:
    discard

proc parsedGap(value: StyleValue; env: ResolveEnv; property: string;
    diagnostics: var Diagnostics): Option[LengthValue] =
  normalizeLength(value, env, property, {ukPercent}, diagnostics)

proc flexBasisValue(style: ComputedStyle): Option[LengthValue] =
  if not style.layout.sizing.isNil and style.layout.sizing.flexBasis.isSome:
    return style.layout.sizing.flexBasis
  fixedLength(style.layout.flexBasis)

proc setFlexBasisValue(style: var ComputedStyle; value: Option[LengthValue]) =
  if value.isSome and value.get.kind == ukPx:
    style.layout.flexBasis = some(value.get.value)
    if not style.layout.sizing.isNil:
      style.layout.sizing.flexBasis = none(LengthValue)
  else:
    style.layout.flexBasis = none(float32)
    if value.isSome:
      style.ensureSizing()
      style.layout.sizing.flexBasis = value
    elif not style.layout.sizing.isNil:
      style.layout.sizing.flexBasis = none(LengthValue)

proc applyDisplay(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "display only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.display = dkFlex
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "display requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "flex":
    style.layout.display = dkFlex
  of "none":
    style.layout.display = dkNone
  else:
    diagnostics.addError(declaration.property, "unsupported display keyword")

proc applyFlexDirection(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "flex-direction only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.direction = fdColumn
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "flex-direction requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "row":
    style.layout.direction = fdRow
  of "row-reverse":
    style.layout.direction = fdRowReverse
  of "column":
    style.layout.direction = fdColumn
  of "column-reverse":
    style.layout.direction = fdColumnReverse
  else:
    diagnostics.addError(declaration.property, "unsupported flex-direction keyword")

proc parseFlexDirectionKeyword(property, value: string; diagnostics: var Diagnostics): Option[FlexDirection] =
  case value
  of "row":
    some(fdRow)
  of "row-reverse":
    some(fdRowReverse)
  of "column":
    some(fdColumn)
  of "column-reverse":
    some(fdColumnReverse)
  else:
    diagnostics.addError(property, "unsupported flex-direction keyword")
    none(FlexDirection)

proc parseFlexWrapKeyword(property, value: string; diagnostics: var Diagnostics): Option[FlexWrap] =
  case value
  of "nowrap":
    some(fwNoWrap)
  of "wrap":
    some(fwWrap)
  of "wrap-reverse":
    some(fwWrapReverse)
  else:
    diagnostics.addError(property, "unsupported flex-wrap keyword")
    none(FlexWrap)

proc applyFlexWrap(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "flex-wrap only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.flexWrap = fwNoWrap
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "flex-wrap requires a keyword value")
    return
  let parsed = parseFlexWrapKeyword(declaration.property, declaration.operation.value.get.keyword, diagnostics)
  if parsed.isSome:
    style.layout.flexWrap = parsed.get

proc applyFlexFlow(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "flex-flow only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.direction = fdColumn
    style.layout.flexWrap = fwNoWrap
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "flex-flow requires a keyword value")
    return
  let parts = declaration.operation.value.get.keyword.splitWhitespace()
  if parts.len == 0 or parts.len > 2:
    diagnostics.addError(declaration.property, "flex-flow expects one or two keywords")
    return
  var directionSet = false
  var wrapSet = false
  for part in parts:
    if part in ["row", "row-reverse", "column", "column-reverse"]:
      if directionSet:
        diagnostics.addError(declaration.property, "flex-flow direction is duplicated")
        return
      let parsed = parseFlexDirectionKeyword(declaration.property, part, diagnostics)
      if parsed.isSome:
        style.layout.direction = parsed.get
        directionSet = true
    elif part in ["nowrap", "wrap", "wrap-reverse"]:
      if wrapSet:
        diagnostics.addError(declaration.property, "flex-flow wrap is duplicated")
        return
      let parsed = parseFlexWrapKeyword(declaration.property, part, diagnostics)
      if parsed.isSome:
        style.layout.flexWrap = parsed.get
        wrapSet = true
    else:
      diagnostics.addError(declaration.property, "unsupported flex-flow keyword")
      return

proc applyGap(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "gap requires a length value")
      return
    style.setGapValue("gap", parsedGap(declaration.operation.value.get, env, declaration.property, diagnostics))
  of mmInitial, mmUnset:
    style.setGapValue("gap", none(LengthValue))
  of mmInherit:
    if env.parent.isSome:
      style.setGapValue("gap", env.parent.get.gapValue("gap"))
    else:
      diagnostics.addError(declaration.property, "cannot inherit gap without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "gap relative merge is not implemented yet")

proc applyAxisGap(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, declaration.property & " requires a length value")
      return
    style.setGapValue(
      declaration.property,
      parsedGap(declaration.operation.value.get, env, declaration.property, diagnostics)
    )
  of mmInitial, mmUnset:
    style.setGapValue(declaration.property, none(LengthValue))
  of mmInherit:
    if env.parent.isSome:
      style.setGapValue(
        declaration.property,
        env.parent.get.gapValue(declaration.property)
      )
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " relative merge is not implemented yet")

let displayProperty* = PropertyImpl(name: "display", apply: applyDisplay)
let flexDirectionProperty* = PropertyImpl(name: "flex-direction", apply: applyFlexDirection)
let flexWrapProperty* = PropertyImpl(name: "flex-wrap", apply: applyFlexWrap)
let flexFlowProperty* = PropertyImpl(name: "flex-flow", apply: applyFlexFlow)
let gapProperty* = PropertyImpl(name: "gap", apply: applyGap)
let rowGapProperty* = PropertyImpl(name: "row-gap", apply: applyAxisGap)
let columnGapProperty* = PropertyImpl(name: "column-gap", apply: applyAxisGap)

proc applyFlexNumber(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, declaration.property & " only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    if declaration.property == "flex-grow":
      style.layout.flexGrow = 0
    else:
      style.layout.flexShrink = 1
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svNumber:
    diagnostics.addError(declaration.property, declaration.property & " requires a number value")
    return
  let value = max(0.0'f32, declaration.operation.value.get.number)
  if declaration.property == "flex-grow":
    style.layout.flexGrow = value
  else:
    style.layout.flexShrink = value

proc applyFlexBasis(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "flex-basis requires a value")
      return
    let value = declaration.operation.value.get
    if value.kind == svKeyword and value.keyword == "auto":
      style.setFlexBasisValue(none(LengthValue))
      return
    if value.kind != svLength:
      diagnostics.addError(declaration.property, "flex-basis requires a length value or auto")
      return
    let normalized = normalizeLength(value, env, declaration.property, {
      ukPercent, ukContent, ukMinContent, ukMaxContent, ukFitContent, ukAuto
    }, diagnostics)
    if normalized.isNone:
      return
    if normalized.get.kind == ukAuto:
      style.setFlexBasisValue(none(LengthValue))
    else:
      style.setFlexBasisValue(normalized)
  of mmInitial, mmUnset:
    style.setFlexBasisValue(none(LengthValue))
  of mmInherit:
    if env.parent.isSome:
      style.setFlexBasisValue(env.parent.get.flexBasisValue())
    else:
      diagnostics.addError(declaration.property, "cannot inherit flex-basis without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "flex-basis relative merge is not implemented yet")

proc applyFlex(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "flex requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svNumber:
      let flexGrow = max(0.0'f32, value.number)
      style.layout.flexGrow = flexGrow
      style.layout.flexShrink = 1
      style.setFlexBasisValue(none(LengthValue))
    of svLength:
      let normalized = normalizeLength(value, env, declaration.property, {
        ukPercent, ukContent, ukMinContent, ukMaxContent, ukFitContent, ukAuto
      }, diagnostics)
      if normalized.isNone:
        return
      style.layout.flexGrow = 1
      style.layout.flexShrink = 1
      if normalized.get.kind == ukAuto:
        style.setFlexBasisValue(none(LengthValue))
      else:
        style.setFlexBasisValue(normalized)
    of svKeyword:
      case value.keyword
      of "none":
        style.layout.flexGrow = 0
        style.layout.flexShrink = 0
        style.setFlexBasisValue(none(LengthValue))
      of "auto":
        style.layout.flexGrow = 1
        style.layout.flexShrink = 1
        style.setFlexBasisValue(none(LengthValue))
      of "initial":
        style.layout.flexGrow = 0
        style.layout.flexShrink = 1
        style.setFlexBasisValue(none(LengthValue))
      else:
        diagnostics.addError(declaration.property, "unsupported flex keyword")
    else:
      diagnostics.addError(declaration.property, "flex requires a number, sizing value, or keyword")
  of mmInitial, mmUnset:
    style.layout.flexGrow = 0
    style.layout.flexShrink = 1
    style.setFlexBasisValue(none(LengthValue))
  of mmInherit:
    if env.parent.isSome:
      style.layout.flexGrow = env.parent.get.layout.flexGrow
      style.layout.flexShrink = env.parent.get.layout.flexShrink
      style.setFlexBasisValue(env.parent.get.flexBasisValue())
    else:
      diagnostics.addError(declaration.property, "cannot inherit flex without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "flex does not support relative merge")

let flexProperty* = PropertyImpl(name: "flex", apply: applyFlex)
let flexGrowProperty* = PropertyImpl(name: "flex-grow", apply: applyFlexNumber)
let flexShrinkProperty* = PropertyImpl(name: "flex-shrink", apply: applyFlexNumber)
let flexBasisProperty* = PropertyImpl(name: "flex-basis", apply: applyFlexBasis)

proc keywordValue(declaration: Declaration; diagnostics: var Diagnostics): Option[string] =
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, declaration.property & " requires a keyword value")
    return none(string)
  some(declaration.operation.value.get.keyword)

proc parseAlignItemsKeyword(property, value: string; diagnostics: var Diagnostics): Option[AlignItems] =
  case value
  of "start", "flex-start":
    some(aiStart)
  of "center":
    some(aiCenter)
  of "end", "flex-end":
    some(aiEnd)
  of "stretch":
    some(aiStretch)
  of "baseline":
    some(aiBaseline)
  else:
    diagnostics.addError(property, "unsupported " & property & " keyword")
    none(AlignItems)

proc parseJustifyContentKeyword(property, value: string; diagnostics: var Diagnostics): Option[JustifyContent] =
  case value
  of "start", "flex-start":
    some(jcStart)
  of "center":
    some(jcCenter)
  of "end", "flex-end":
    some(jcEnd)
  of "space-between":
    some(jcSpaceBetween)
  of "space-around":
    some(jcSpaceAround)
  of "space-evenly":
    some(jcSpaceEvenly)
  of "stretch":
    some(jcStretch)
  else:
    diagnostics.addError(property, "unsupported " & property & " keyword")
    none(JustifyContent)

proc parseSelfAlignmentKeyword(property, value: string; diagnostics: var Diagnostics): Option[SelfAlignment] =
  case value
  of "start", "flex-start":
    some(saStart)
  of "center":
    some(saCenter)
  of "end", "flex-end":
    some(saEnd)
  of "stretch":
    some(saStretch)
  else:
    diagnostics.addError(property, "unsupported " & property & " keyword")
    none(SelfAlignment)

proc applyOrder(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "order only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.order = 0
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svNumber:
    diagnostics.addError(declaration.property, "order requires a number value")
    return
  style.layout.order = declaration.operation.value.get.number.int

proc applyAlignItems(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "align-items only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.alignItems = aiStart
    return
  let value = keywordValue(declaration, diagnostics)
  if value.isNone:
    return
  let parsed = parseAlignItemsKeyword(declaration.property, value.get, diagnostics)
  if parsed.isSome:
    style.layout.alignItems = parsed.get

proc applyAlignSelf(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "align-self only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.alignSelf = none(AlignItems)
    return
  let value = keywordValue(declaration, diagnostics)
  if value.isNone:
    return
  if value.get == "auto":
    style.layout.alignSelf = none(AlignItems)
    return
  let parsed = parseAlignItemsKeyword(declaration.property, value.get, diagnostics)
  if parsed.isSome:
    style.layout.alignSelf = parsed

proc applyJustifyContent(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "justify-content only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.justifyContent = jcStart
    return
  let value = keywordValue(declaration, diagnostics)
  if value.isNone:
    return
  let parsed = parseJustifyContentKeyword(declaration.property, value.get, diagnostics)
  if parsed.isSome:
    style.layout.justifyContent = parsed.get

proc applyAlignContent(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "align-content only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.alignContent = jcStart
    return
  let value = keywordValue(declaration, diagnostics)
  if value.isNone:
    return
  let parsed = parseJustifyContentKeyword(declaration.property, value.get, diagnostics)
  if parsed.isSome:
    style.layout.alignContent = parsed.get

proc applyJustifyItems(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "justify-items only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.justifyItems = none(SelfAlignment)
    return
  let value = keywordValue(declaration, diagnostics)
  if value.isNone:
    return
  let parsed = parseSelfAlignmentKeyword(declaration.property, value.get, diagnostics)
  if parsed.isSome:
    style.layout.justifyItems = parsed

proc applyJustifySelf(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "justify-self only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.justifySelf = none(SelfAlignment)
    return
  let value = keywordValue(declaration, diagnostics)
  if value.isNone:
    return
  if value.get == "auto":
    style.layout.justifySelf = none(SelfAlignment)
    return
  let parsed = parseSelfAlignmentKeyword(declaration.property, value.get, diagnostics)
  if parsed.isSome:
    style.layout.justifySelf = parsed

proc applyPlaceContent(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "place-content only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.alignContent = jcStart
    style.layout.justifyContent = jcStart
    return
  let value = keywordValue(declaration, diagnostics)
  if value.isNone:
    return
  let parts = value.get.splitWhitespace()
  if parts.len notin 1 .. 2:
    diagnostics.addError(
      declaration.property,
      "place-content expects one or two alignment keywords"
    )
    return
  let align = parseJustifyContentKeyword(
    declaration.property, parts[0], diagnostics
  )
  if align.isNone:
    return
  let justify =
    if parts.len == 2:
      parseJustifyContentKeyword(declaration.property, parts[1], diagnostics)
    else:
      align
  if justify.isNone:
    return
  style.layout.alignContent = align.get
  style.layout.justifyContent = justify.get

proc applyPlaceItems(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "place-items only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.alignItems = aiStart
    style.layout.justifyItems = none(SelfAlignment)
    return
  let value = keywordValue(declaration, diagnostics)
  if value.isNone:
    return
  let align = parseAlignItemsKeyword(declaration.property, value.get, diagnostics)
  let justify = parseSelfAlignmentKeyword(declaration.property, value.get, diagnostics)
  if align.isSome and justify.isSome:
    style.layout.alignItems = align.get
    style.layout.justifyItems = justify

proc applyPlaceSelf(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "place-self only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.alignSelf = none(AlignItems)
    style.layout.justifySelf = none(SelfAlignment)
    return
  let value = keywordValue(declaration, diagnostics)
  if value.isNone:
    return
  if value.get == "auto":
    style.layout.alignSelf = none(AlignItems)
    style.layout.justifySelf = none(SelfAlignment)
    return
  let align = parseAlignItemsKeyword(declaration.property, value.get, diagnostics)
  let justify = parseSelfAlignmentKeyword(declaration.property, value.get, diagnostics)
  if align.isSome and justify.isSome:
    style.layout.alignSelf = align
    style.layout.justifySelf = justify

let orderProperty* = PropertyImpl(name: "order", apply: applyOrder)
let alignItemsProperty* = PropertyImpl(name: "align-items", apply: applyAlignItems)
let alignSelfProperty* = PropertyImpl(name: "align-self", apply: applyAlignSelf)
let alignContentProperty* = PropertyImpl(name: "align-content", apply: applyAlignContent)
let justifyContentProperty* = PropertyImpl(name: "justify-content", apply: applyJustifyContent)
let justifyItemsProperty* = PropertyImpl(name: "justify-items", apply: applyJustifyItems)
let justifySelfProperty* = PropertyImpl(name: "justify-self", apply: applyJustifySelf)
let placeContentProperty* = PropertyImpl(name: "place-content", apply: applyPlaceContent)
let placeItemsProperty* = PropertyImpl(name: "place-items", apply: applyPlaceItems)
let placeSelfProperty* = PropertyImpl(name: "place-self", apply: applyPlaceSelf)

proc applyOverflow(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "overflow only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    if declaration.property in ["overflow", "overflow-x"]:
      style.layout.overflowX = omVisible
    if declaration.property in ["overflow", "overflow-y"]:
      style.layout.overflowY = omVisible
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "overflow requires a keyword value")
    return
  let mode =
    case declaration.operation.value.get.keyword
    of "visible": omVisible
    of "hidden": omHidden
    of "clip": omClip
    of "auto": omAuto
    of "scroll": omScroll
    else:
      diagnostics.addError(declaration.property, "unsupported overflow keyword")
      return
  if declaration.property in ["overflow", "overflow-x"]:
    style.layout.overflowX = mode
  if declaration.property in ["overflow", "overflow-y"]:
    style.layout.overflowY = mode

let overflowProperty* = PropertyImpl(name: "overflow", apply: applyOverflow)
let overflowXProperty* = PropertyImpl(name: "overflow-x", apply: applyOverflow)
let overflowYProperty* = PropertyImpl(name: "overflow-y", apply: applyOverflow)

proc setLayoutMetadata(style: var ComputedStyle; property: string; value: Option[string]) =
  case property
  of "align-tracks":
    style.layout.alignTracks = value
  of "justify-tracks":
    style.layout.justifyTracks = value
  of "margin-trim":
    style.layout.marginTrim = value
  of "box-align":
    style.layout.legacyBoxAlign = value
  of "box-direction":
    style.layout.legacyBoxDirection = value
  of "box-flex":
    style.layout.legacyBoxFlex = value
  of "box-flex-group":
    style.layout.legacyBoxFlexGroup = value
  of "box-lines":
    style.layout.legacyBoxLines = value
  of "box-ordinal-group":
    style.layout.legacyBoxOrdinalGroup = value
  of "box-orient":
    style.layout.legacyBoxOrient = value
  of "box-pack":
    style.layout.legacyBoxPack = value
  else:
    discard

proc layoutMetadata(style: ComputedStyle; property: string): Option[string] =
  case property
  of "align-tracks":
    style.layout.alignTracks
  of "justify-tracks":
    style.layout.justifyTracks
  of "margin-trim":
    style.layout.marginTrim
  of "box-align":
    style.layout.legacyBoxAlign
  of "box-direction":
    style.layout.legacyBoxDirection
  of "box-flex":
    style.layout.legacyBoxFlex
  of "box-flex-group":
    style.layout.legacyBoxFlexGroup
  of "box-lines":
    style.layout.legacyBoxLines
  of "box-ordinal-group":
    style.layout.legacyBoxOrdinalGroup
  of "box-orient":
    style.layout.legacyBoxOrient
  of "box-pack":
    style.layout.legacyBoxPack
  else:
    none(string)

proc applyLayoutMetadata(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, declaration.property & " requires a metadata value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svKeyword:
      if value.keyword in ["normal", "auto", "none"]:
        style.setLayoutMetadata(declaration.property, none(string))
      else:
        style.setLayoutMetadata(declaration.property, some(value.keyword))
    of svNumber:
      style.setLayoutMetadata(declaration.property, some($value.number))
    of svLength:
      style.setLayoutMetadata(declaration.property, some($value.length.value))
    else:
      diagnostics.addError(declaration.property, declaration.property & " requires a keyword, number, or length value")
  of mmInitial, mmUnset:
    style.setLayoutMetadata(declaration.property, none(string))
  of mmInherit:
    if env.parent.isSome:
      style.setLayoutMetadata(declaration.property, env.parent.get.layoutMetadata(declaration.property))
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

let alignTracksProperty* = PropertyImpl(name: "align-tracks", apply: applyLayoutMetadata)
let justifyTracksProperty* = PropertyImpl(name: "justify-tracks", apply: applyLayoutMetadata)
let marginTrimProperty* = PropertyImpl(name: "margin-trim", apply: applyLayoutMetadata)
let boxAlignProperty* = PropertyImpl(name: "box-align", apply: applyLayoutMetadata)
let boxDirectionProperty* = PropertyImpl(name: "box-direction", apply: applyLayoutMetadata)
let boxFlexProperty* = PropertyImpl(name: "box-flex", apply: applyLayoutMetadata)
let boxFlexGroupProperty* = PropertyImpl(name: "box-flex-group", apply: applyLayoutMetadata)
let boxLinesProperty* = PropertyImpl(name: "box-lines", apply: applyLayoutMetadata)
let boxOrdinalGroupProperty* = PropertyImpl(name: "box-ordinal-group", apply: applyLayoutMetadata)
let boxOrientProperty* = PropertyImpl(name: "box-orient", apply: applyLayoutMetadata)
let boxPackProperty* = PropertyImpl(name: "box-pack", apply: applyLayoutMetadata)
