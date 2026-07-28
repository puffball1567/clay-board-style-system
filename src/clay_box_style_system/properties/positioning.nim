import std/options
import ../core/[computed_style, declaration, diagnostics, property, style_value]

type InsetEdge = enum
  ieTop,
  ieRight,
  ieBottom,
  ieLeft

proc resolveInset(value: StyleValue; property: string; diagnostics: var Diagnostics): Option[LengthValue] =
  if value.kind != svLength:
    diagnostics.addError(property, property & " requires a length value")
    return none(LengthValue)
  case value.length.kind
  of ukPx, ukPercent:
    some(value.length)
  of ukAuto:
    none(LengthValue)
  else:
    diagnostics.addError(property, property & " supports px, percentage, or auto")
    none(LengthValue)

proc applyPosition(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "position only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.position = pkStatic
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "position requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "static":
    style.layout.position = pkStatic
  of "relative":
    style.layout.position = pkRelative
  of "absolute":
    style.layout.position = pkAbsolute
  else:
    diagnostics.addError(declaration.property, "unsupported position keyword")

proc insetValue(style: ComputedStyle; edge: InsetEdge): Option[LengthValue] =
  if not style.layout.sizing.isNil:
    let sizing = style.layout.sizing[]
    case edge
    of ieTop:
      if sizing.insetTop.isSome: return sizing.insetTop
    of ieRight:
      if sizing.insetRight.isSome: return sizing.insetRight
    of ieBottom:
      if sizing.insetBottom.isSome: return sizing.insetBottom
    of ieLeft:
      if sizing.insetLeft.isSome: return sizing.insetLeft
  let pixelValue =
    case edge
    of ieTop: style.layout.inset.top
    of ieRight: style.layout.inset.right
    of ieBottom: style.layout.inset.bottom
    of ieLeft: style.layout.inset.left
  if pixelValue.isSome:
    some(LengthValue(kind: ukPx, value: pixelValue.get))
  else:
    none(LengthValue)

proc setInsetEdge(style: var ComputedStyle; edge: InsetEdge; value: Option[LengthValue]) =
  let pixelValue =
    if value.isSome and value.get.kind == ukPx: some(value.get.value)
    else: none(float32)
  if value.isSome and value.get.kind != ukPx:
    style.ensureSizing()
  case edge
  of ieTop:
    style.layout.inset.top = pixelValue
    if not style.layout.sizing.isNil:
      style.layout.sizing.insetTop = if pixelValue.isSome: none(LengthValue) else: value
  of ieRight:
    style.layout.inset.right = pixelValue
    if not style.layout.sizing.isNil:
      style.layout.sizing.insetRight = if pixelValue.isSome: none(LengthValue) else: value
  of ieBottom:
    style.layout.inset.bottom = pixelValue
    if not style.layout.sizing.isNil:
      style.layout.sizing.insetBottom = if pixelValue.isSome: none(LengthValue) else: value
  of ieLeft:
    style.layout.inset.left = pixelValue
    if not style.layout.sizing.isNil:
      style.layout.sizing.insetLeft = if pixelValue.isSome: none(LengthValue) else: value

proc setInset(style: var ComputedStyle; property: string; value: Option[LengthValue]) =
  case property
  of "inset":
    for edge in InsetEdge:
      style.setInsetEdge(edge, value)
  of "inset-block":
    style.setInsetEdge(ieTop, value)
    style.setInsetEdge(ieBottom, value)
  of "inset-inline":
    style.setInsetEdge(ieLeft, value)
    style.setInsetEdge(ieRight, value)
  of "inset-block-start":
    style.setInsetEdge(ieTop, value)
  of "inset-block-end":
    style.setInsetEdge(ieBottom, value)
  of "inset-inline-start":
    style.setInsetEdge(ieLeft, value)
  of "inset-inline-end":
    style.setInsetEdge(ieRight, value)
  of "top":
    style.setInsetEdge(ieTop, value)
  of "right":
    style.setInsetEdge(ieRight, value)
  of "bottom":
    style.setInsetEdge(ieBottom, value)
  of "left":
    style.setInsetEdge(ieLeft, value)
  else:
    discard

proc inheritInset(style: var ComputedStyle; property: string; parent: ComputedStyle) =
  case property
  of "inset":
    for edge in InsetEdge:
      style.setInsetEdge(edge, parent.insetValue(edge))
  of "inset-block":
    style.setInsetEdge(ieTop, parent.insetValue(ieTop))
    style.setInsetEdge(ieBottom, parent.insetValue(ieBottom))
  of "inset-inline":
    style.setInsetEdge(ieLeft, parent.insetValue(ieLeft))
    style.setInsetEdge(ieRight, parent.insetValue(ieRight))
  of "inset-block-start", "top":
    style.setInsetEdge(ieTop, parent.insetValue(ieTop))
  of "inset-block-end", "bottom":
    style.setInsetEdge(ieBottom, parent.insetValue(ieBottom))
  of "inset-inline-start", "left":
    style.setInsetEdge(ieLeft, parent.insetValue(ieLeft))
  of "inset-inline-end", "right":
    style.setInsetEdge(ieRight, parent.insetValue(ieRight))
  else:
    discard

proc applyInset(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, declaration.property & " requires a value")
      return
    style.setInset(
      declaration.property,
      resolveInset(declaration.operation.value.get, declaration.property, diagnostics)
    )
  of mmInitial, mmUnset:
    style.setInset(declaration.property, none(LengthValue))
  of mmInherit:
    if env.parent.isSome:
      style.inheritInset(declaration.property, env.parent.get)
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " relative merge is not implemented yet")

let positionProperty* = PropertyImpl(name: "position", apply: applyPosition)
let insetProperty* = PropertyImpl(name: "inset", apply: applyInset)
let insetBlockProperty* = PropertyImpl(name: "inset-block", apply: applyInset)
let insetBlockStartProperty* = PropertyImpl(name: "inset-block-start", apply: applyInset)
let insetBlockEndProperty* = PropertyImpl(name: "inset-block-end", apply: applyInset)
let insetInlineProperty* = PropertyImpl(name: "inset-inline", apply: applyInset)
let insetInlineStartProperty* = PropertyImpl(name: "inset-inline-start", apply: applyInset)
let insetInlineEndProperty* = PropertyImpl(name: "inset-inline-end", apply: applyInset)
let topProperty* = PropertyImpl(name: "top", apply: applyInset)
let rightProperty* = PropertyImpl(name: "right", apply: applyInset)
let bottomProperty* = PropertyImpl(name: "bottom", apply: applyInset)
let leftProperty* = PropertyImpl(name: "left", apply: applyInset)

proc applyZIndex(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "z-index only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.zIndex = 0
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svNumber:
    diagnostics.addError(declaration.property, "z-index requires a number value")
    return
  style.layout.zIndex = int(declaration.operation.value.get.number)

let zIndexProperty* = PropertyImpl(name: "z-index", apply: applyZIndex)
