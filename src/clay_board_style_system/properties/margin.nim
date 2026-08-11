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

proc setMarginSpec(style: var ComputedStyle; property: string;
    value: Option[LengthValue]) =
  if value.isSome:
    style.ensureSizing()
  if style.layout.sizing.isNil:
    return
  case property
  of "margin":
    style.layout.sizing.marginTop = value
    style.layout.sizing.marginRight = value
    style.layout.sizing.marginBottom = value
    style.layout.sizing.marginLeft = value
  of "margin-top", "margin-block-start":
    style.layout.sizing.marginTop = value
  of "margin-right", "margin-inline-end":
    style.layout.sizing.marginRight = value
  of "margin-bottom", "margin-block-end":
    style.layout.sizing.marginBottom = value
  of "margin-left", "margin-inline-start":
    style.layout.sizing.marginLeft = value
  of "margin-inline":
    style.layout.sizing.marginLeft = value
    style.layout.sizing.marginRight = value
  of "margin-block":
    style.layout.sizing.marginTop = value
    style.layout.sizing.marginBottom = value
  else:
    discard

proc marginSpec(style: ComputedStyle; property: string): Option[LengthValue] =
  if style.layout.sizing.isNil:
    return none(LengthValue)
  case property
  of "margin-top", "margin-block-start":
    style.layout.sizing.marginTop
  of "margin-right", "margin-inline-end":
    style.layout.sizing.marginRight
  of "margin-bottom", "margin-block-end":
    style.layout.sizing.marginBottom
  of "margin-left", "margin-inline-start":
    style.layout.sizing.marginLeft
  else:
    none(LengthValue)

proc hasMarginSpec(style: ComputedStyle; property: string): bool =
  if style.layout.sizing.isNil:
    return false
  case property
  of "margin":
    style.layout.sizing.marginTop.isSome or
      style.layout.sizing.marginRight.isSome or
      style.layout.sizing.marginBottom.isSome or
      style.layout.sizing.marginLeft.isSome
  of "margin-inline":
    style.layout.sizing.marginLeft.isSome or
      style.layout.sizing.marginRight.isSome
  of "margin-block":
    style.layout.sizing.marginTop.isSome or
      style.layout.sizing.marginBottom.isSome
  else:
    style.marginSpec(property).isSome

proc applyMarginLength(style: var ComputedStyle; property: string;
    length: LengthValue) =
  let value = if length.kind == ukPx: length.value else: 0.0'f32
  if property == "margin":
    style.box.margin = some(edges(value))
  else:
    var current =
      if style.box.margin.isSome: style.box.margin.get
      else: edges(0)
    current.setSide(property, value)
    style.box.margin = some(current)
  style.setMarginSpec(property,
    if length.kind == ukPercent: some(length) else: none(LengthValue))

proc inheritMarginSpecs(style: var ComputedStyle; parent: ComputedStyle) =
  if parent.layout.sizing.isNil:
    style.setMarginSpec("margin", none(LengthValue))
    return
  style.setMarginSpec("margin-top", parent.layout.sizing.marginTop)
  style.setMarginSpec("margin-right", parent.layout.sizing.marginRight)
  style.setMarginSpec("margin-bottom", parent.layout.sizing.marginBottom)
  style.setMarginSpec("margin-left", parent.layout.sizing.marginLeft)

proc inheritMarginSpec(style: var ComputedStyle; parent: ComputedStyle;
    property: string) =
  case property
  of "margin-inline":
    style.setMarginSpec("margin-left", parent.marginSpec("margin-left"))
    style.setMarginSpec("margin-right", parent.marginSpec("margin-right"))
  of "margin-block":
    style.setMarginSpec("margin-top", parent.marginSpec("margin-top"))
    style.setMarginSpec("margin-bottom", parent.marginSpec("margin-bottom"))
  else:
    style.setMarginSpec(property, parent.marginSpec(property))

proc currentMarginHasSpec(style: ComputedStyle; env: ResolveEnv;
    property: string): bool =
  if style.box.margin.isSome:
    return style.hasMarginSpec(property)
  env.parent.isSome and env.parent.get.hasMarginSpec(property)

proc currentMargin(style: ComputedStyle; env: ResolveEnv): Option[EdgeSizes] =
  if style.box.margin.isSome:
    return style.box.margin
  if env.parent.isSome and env.parent.get.box.margin.isSome:
    return env.parent.get.box.margin
  none(EdgeSizes)

proc setSide(edges: var EdgeSizes; property: string; value: float32) =
  case property
  of "margin-top", "margin-block-start":
    edges.top = value
  of "margin-right", "margin-inline-end":
    edges.right = value
  of "margin-bottom", "margin-block-end":
    edges.bottom = value
  of "margin-left", "margin-inline-start":
    edges.left = value
  of "margin-inline":
    edges.left = value
    edges.right = value
  of "margin-block":
    edges.top = value
    edges.bottom = value
  else:
    discard

proc sideValue(edges: EdgeSizes; property: string): float32 =
  case property
  of "margin-top", "margin-block-start":
    edges.top
  of "margin-right", "margin-inline-end":
    edges.right
  of "margin-bottom", "margin-block-end":
    edges.bottom
  of "margin-left", "margin-inline-start":
    edges.left
  else:
    0

proc copySide(edges: var EdgeSizes; property: string; source: EdgeSizes) =
  case property
  of "margin-inline":
    edges.left = source.left
    edges.right = source.right
  of "margin-block":
    edges.top = source.top
    edges.bottom = source.bottom
  else:
    edges.setSide(property, source.sideValue(property))

proc applyMargin(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "margin requires a value")
      return
    let resolved = normalizeLength(declaration.operation.value.get, env,
        declaration.property, {ukPercent}, diagnostics)
    if resolved.isSome:
      style.applyMarginLength(declaration.property, resolved.get)
  of mmInherit:
    if env.parent.isSome and env.parent.get.box.margin.isSome:
      style.box.margin = env.parent.get.box.margin
      style.inheritMarginSpecs(env.parent.get)
    else:
      diagnostics.addError(declaration.property, "cannot inherit margin without parent margin")
  of mmInitial, mmUnset:
    style.box.margin = some(edges(0))
    style.setMarginSpec("margin", none(LengthValue))
  of mmRelative:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "relative margin requires a value")
      return
    let base = currentMargin(style, env)
    if base.isNone:
      diagnostics.addError(declaration.property, "relative margin requires existing or parent margin")
      return
    if style.currentMarginHasSpec(env, declaration.property):
      diagnostics.addError(declaration.property,
          "relative margin requires a resolved absolute base")
      return
    let delta = resolveAbsoluteLength(declaration.operation.value.get, env, declaration.property, diagnostics)
    if delta.isSome:
      let b = base.get
      let d = delta.get
      style.box.margin = some(edges(b.top + d, b.right + d, b.bottom + d, b.left + d))

let marginProperty* = PropertyImpl(name: "margin", apply: applyMargin)

proc applyMarginSide(
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
      style.applyMarginLength(declaration.property, resolved.get)
  of mmInherit:
    if env.parent.isSome and env.parent.get.box.margin.isSome:
      var current =
        if style.box.margin.isSome: style.box.margin.get
        else: edges(0)
      current.copySide(declaration.property, env.parent.get.box.margin.get)
      style.box.margin = some(current)
      style.inheritMarginSpec(env.parent.get, declaration.property)
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent margin")
  of mmInitial, mmUnset:
    var current =
      if style.box.margin.isSome: style.box.margin.get
      else: edges(0)
    current.setSide(declaration.property, 0)
    style.box.margin = some(current)
    style.setMarginSpec(declaration.property, none(LengthValue))
  of mmRelative:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "relative " & declaration.property & " requires a value")
      return
    let base = currentMargin(style, env)
    if base.isNone:
      diagnostics.addError(declaration.property, "relative " & declaration.property & " requires existing or parent margin")
      return
    if style.currentMarginHasSpec(env, declaration.property):
      diagnostics.addError(declaration.property,
          "relative margin requires a resolved absolute base")
      return
    let delta = resolveAbsoluteLength(declaration.operation.value.get, env, declaration.property, diagnostics)
    if delta.isSome:
      var current = base.get
      current.setSide(declaration.property, current.sideValue(declaration.property) + delta.get)
      style.box.margin = some(current)

let marginTopProperty* = PropertyImpl(name: "margin-top", apply: applyMarginSide)
let marginRightProperty* = PropertyImpl(name: "margin-right", apply: applyMarginSide)
let marginBottomProperty* = PropertyImpl(name: "margin-bottom", apply: applyMarginSide)
let marginLeftProperty* = PropertyImpl(name: "margin-left", apply: applyMarginSide)
let marginInlineProperty* = PropertyImpl(name: "margin-inline", apply: applyMarginSide)
let marginInlineStartProperty* = PropertyImpl(name: "margin-inline-start", apply: applyMarginSide)
let marginInlineEndProperty* = PropertyImpl(name: "margin-inline-end", apply: applyMarginSide)
let marginBlockProperty* = PropertyImpl(name: "margin-block", apply: applyMarginSide)
let marginBlockStartProperty* = PropertyImpl(name: "margin-block-start", apply: applyMarginSide)
let marginBlockEndProperty* = PropertyImpl(name: "margin-block-end", apply: applyMarginSide)
