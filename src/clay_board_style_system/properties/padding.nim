import std/options
import ../core/[
  computed_style,
  declaration,
  diagnostics,
  property,
  style_value
]
import ./length_resolution

proc setSide(edges: var EdgeSizes; property: string; value: float32)

proc setPaddingSpec(style: var ComputedStyle; property: string;
    value: Option[LengthValue]) =
  if value.isSome:
    style.ensureSizing()
  if style.layout.sizing.isNil:
    return
  case property
  of "padding":
    style.layout.sizing.paddingTop = value
    style.layout.sizing.paddingRight = value
    style.layout.sizing.paddingBottom = value
    style.layout.sizing.paddingLeft = value
  of "padding-top", "padding-block-start":
    style.layout.sizing.paddingTop = value
  of "padding-right", "padding-inline-end":
    style.layout.sizing.paddingRight = value
  of "padding-bottom", "padding-block-end":
    style.layout.sizing.paddingBottom = value
  of "padding-left", "padding-inline-start":
    style.layout.sizing.paddingLeft = value
  of "padding-inline":
    style.layout.sizing.paddingLeft = value
    style.layout.sizing.paddingRight = value
  of "padding-block":
    style.layout.sizing.paddingTop = value
    style.layout.sizing.paddingBottom = value
  else:
    discard

proc paddingSpec(style: ComputedStyle; property: string): Option[LengthValue] =
  if style.layout.sizing.isNil:
    return none(LengthValue)
  case property
  of "padding-top", "padding-block-start":
    style.layout.sizing.paddingTop
  of "padding-right", "padding-inline-end":
    style.layout.sizing.paddingRight
  of "padding-bottom", "padding-block-end":
    style.layout.sizing.paddingBottom
  of "padding-left", "padding-inline-start":
    style.layout.sizing.paddingLeft
  else:
    none(LengthValue)

proc hasPaddingSpec(style: ComputedStyle; property: string): bool =
  if style.layout.sizing.isNil:
    return false
  case property
  of "padding":
    style.layout.sizing.paddingTop.isSome or
      style.layout.sizing.paddingRight.isSome or
      style.layout.sizing.paddingBottom.isSome or
      style.layout.sizing.paddingLeft.isSome
  of "padding-inline":
    style.layout.sizing.paddingLeft.isSome or
      style.layout.sizing.paddingRight.isSome
  of "padding-block":
    style.layout.sizing.paddingTop.isSome or
      style.layout.sizing.paddingBottom.isSome
  else:
    style.paddingSpec(property).isSome

proc applyPaddingLength(style: var ComputedStyle; property: string;
    length: LengthValue) =
  let value = if length.kind == ukPx: length.value else: 0.0'f32
  if property == "padding":
    style.box.padding = some(edges(value))
  else:
    var current =
      if style.box.padding.isSome: style.box.padding.get
      else: edges(0)
    current.setSide(property, value)
    style.box.padding = some(current)
  style.setPaddingSpec(property,
    if length.kind == ukPercent: some(length) else: none(LengthValue))

proc inheritPaddingSpecs(style: var ComputedStyle; parent: ComputedStyle) =
  if parent.layout.sizing.isNil:
    style.setPaddingSpec("padding", none(LengthValue))
    return
  style.setPaddingSpec("padding-top", parent.layout.sizing.paddingTop)
  style.setPaddingSpec("padding-right", parent.layout.sizing.paddingRight)
  style.setPaddingSpec("padding-bottom", parent.layout.sizing.paddingBottom)
  style.setPaddingSpec("padding-left", parent.layout.sizing.paddingLeft)

proc inheritPaddingSpec(style: var ComputedStyle; parent: ComputedStyle;
    property: string) =
  case property
  of "padding-inline":
    style.setPaddingSpec("padding-left", parent.paddingSpec("padding-left"))
    style.setPaddingSpec("padding-right", parent.paddingSpec("padding-right"))
  of "padding-block":
    style.setPaddingSpec("padding-top", parent.paddingSpec("padding-top"))
    style.setPaddingSpec("padding-bottom", parent.paddingSpec("padding-bottom"))
  else:
    style.setPaddingSpec(property, parent.paddingSpec(property))

proc currentPaddingHasSpec(style: ComputedStyle; env: ResolveEnv;
    property: string): bool =
  if style.box.padding.isSome:
    return style.hasPaddingSpec(property)
  env.parent.isSome and env.parent.get.hasPaddingSpec(property)

proc currentPadding(style: ComputedStyle; env: ResolveEnv): Option[EdgeSizes] =
  if style.box.padding.isSome:
    return style.box.padding
  if env.parent.isSome and env.parent.get.box.padding.isSome:
    return env.parent.get.box.padding
  none(EdgeSizes)

proc setSide(edges: var EdgeSizes; property: string; value: float32) =
  case property
  of "padding-top", "padding-block-start":
    edges.top = value
  of "padding-right", "padding-inline-end":
    edges.right = value
  of "padding-bottom", "padding-block-end":
    edges.bottom = value
  of "padding-left", "padding-inline-start":
    edges.left = value
  of "padding-inline":
    edges.left = value
    edges.right = value
  of "padding-block":
    edges.top = value
    edges.bottom = value
  else:
    discard

proc sideValue(edges: EdgeSizes; property: string): float32 =
  case property
  of "padding-top", "padding-block-start":
    edges.top
  of "padding-right", "padding-inline-end":
    edges.right
  of "padding-bottom", "padding-block-end":
    edges.bottom
  of "padding-left", "padding-inline-start":
    edges.left
  else:
    0

proc copySide(edges: var EdgeSizes; property: string; source: EdgeSizes) =
  case property
  of "padding-inline":
    edges.left = source.left
    edges.right = source.right
  of "padding-block":
    edges.top = source.top
    edges.bottom = source.bottom
  else:
    edges.setSide(property, source.sideValue(property))

proc applyPadding(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "padding requires a value")
      return
    let resolved = normalizeLength(declaration.operation.value.get, env,
        declaration.property, {ukPercent}, diagnostics)
    if resolved.isSome:
      style.applyPaddingLength(declaration.property, resolved.get)
  of mmInherit:
    if env.parent.isSome and env.parent.get.box.padding.isSome:
      style.box.padding = env.parent.get.box.padding
      style.inheritPaddingSpecs(env.parent.get)
    else:
      diagnostics.addError(declaration.property, "cannot inherit padding without parent padding")
  of mmInitial, mmUnset:
    style.box.padding = some(edges(0))
    style.setPaddingSpec("padding", none(LengthValue))
  of mmRelative:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "relative padding requires a value")
      return
    let base = currentPadding(style, env)
    if base.isNone:
      diagnostics.addError(declaration.property, "relative padding requires existing or parent padding")
      return
    if style.currentPaddingHasSpec(env, declaration.property):
      diagnostics.addError(declaration.property,
          "relative padding requires a resolved absolute base")
      return
    let delta = resolveAbsoluteLength(declaration.operation.value.get, env, declaration.property, diagnostics)
    if delta.isSome:
      let b = base.get
      let d = delta.get
      style.box.padding = some(edges(b.top + d, b.right + d, b.bottom + d, b.left + d))

let paddingProperty* = PropertyImpl(name: "padding", apply: applyPadding)

proc applyPaddingSide(
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
    let resolved = normalizeLength(declaration.operation.value.get, env,
        declaration.property, {ukPercent}, diagnostics)
    if resolved.isSome:
      style.applyPaddingLength(declaration.property, resolved.get)
  of mmInherit:
    if env.parent.isSome and env.parent.get.box.padding.isSome:
      var current =
        if style.box.padding.isSome: style.box.padding.get
        else: edges(0)
      current.copySide(declaration.property, env.parent.get.box.padding.get)
      style.box.padding = some(current)
      style.inheritPaddingSpec(env.parent.get, declaration.property)
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent padding")
  of mmInitial, mmUnset:
    var current =
      if style.box.padding.isSome: style.box.padding.get
      else: edges(0)
    current.setSide(declaration.property, 0)
    style.box.padding = some(current)
    style.setPaddingSpec(declaration.property, none(LengthValue))
  of mmRelative:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "relative " & declaration.property & " requires a value")
      return
    let base = currentPadding(style, env)
    if base.isNone:
      diagnostics.addError(declaration.property, "relative " & declaration.property & " requires existing or parent padding")
      return
    if style.currentPaddingHasSpec(env, declaration.property):
      diagnostics.addError(declaration.property,
          "relative padding requires a resolved absolute base")
      return
    let delta = resolveAbsoluteLength(declaration.operation.value.get, env, declaration.property, diagnostics)
    if delta.isSome:
      var current = base.get
      current.setSide(declaration.property, current.sideValue(declaration.property) + delta.get)
      style.box.padding = some(current)

let paddingTopProperty* = PropertyImpl(name: "padding-top", apply: applyPaddingSide)
let paddingRightProperty* = PropertyImpl(name: "padding-right", apply: applyPaddingSide)
let paddingBottomProperty* = PropertyImpl(name: "padding-bottom", apply: applyPaddingSide)
let paddingLeftProperty* = PropertyImpl(name: "padding-left", apply: applyPaddingSide)
let paddingInlineProperty* = PropertyImpl(name: "padding-inline", apply: applyPaddingSide)
let paddingInlineStartProperty* = PropertyImpl(name: "padding-inline-start", apply: applyPaddingSide)
let paddingInlineEndProperty* = PropertyImpl(name: "padding-inline-end", apply: applyPaddingSide)
let paddingBlockProperty* = PropertyImpl(name: "padding-block", apply: applyPaddingSide)
let paddingBlockStartProperty* = PropertyImpl(name: "padding-block-start", apply: applyPaddingSide)
let paddingBlockEndProperty* = PropertyImpl(name: "padding-block-end", apply: applyPaddingSide)
