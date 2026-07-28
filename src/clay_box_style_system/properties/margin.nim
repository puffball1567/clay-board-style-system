import std/options
import ../core/[
  computed_style,
  declaration,
  diagnostics,
  property,
  style_value
]

proc resolveLength(value: StyleValue; env: ResolveEnv; property: string; diagnostics: var Diagnostics): Option[float32] =
  if value.kind != svLength:
    diagnostics.addError(property, "margin requires a length value")
    return none(float32)

  case value.length.kind
  of ukPx:
    some(value.length.value)
  of ukEm:
    if env.currentFontSize.isSome:
      some(env.currentFontSize.get * value.length.value)
    else:
      diagnostics.addError(property, "em margin requires current font-size")
      none(float32)
  of ukRem:
    if env.rootFontSize.isSome:
      some(env.rootFontSize.get * value.length.value)
    else:
      diagnostics.addError(property, "rem margin requires root font-size")
      none(float32)
  else:
    diagnostics.addError(property, "unsupported margin unit")
    none(float32)

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
    let resolved = resolveLength(declaration.operation.value.get, env, declaration.property, diagnostics)
    if resolved.isSome:
      style.box.margin = some(edges(resolved.get))
  of mmInherit:
    if env.parent.isSome and env.parent.get.box.margin.isSome:
      style.box.margin = env.parent.get.box.margin
    else:
      diagnostics.addError(declaration.property, "cannot inherit margin without parent margin")
  of mmInitial, mmUnset:
    style.box.margin = some(edges(0))
  of mmRelative:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "relative margin requires a value")
      return
    let base = currentMargin(style, env)
    if base.isNone:
      diagnostics.addError(declaration.property, "relative margin requires existing or parent margin")
      return
    let delta = resolveLength(declaration.operation.value.get, env, declaration.property, diagnostics)
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
    let resolved = resolveLength(declaration.operation.value.get, env, declaration.property, diagnostics)
    if resolved.isSome:
      var current =
        if style.box.margin.isSome: style.box.margin.get
        else: edges(0)
      current.setSide(declaration.property, resolved.get)
      style.box.margin = some(current)
  of mmInherit:
    if env.parent.isSome and env.parent.get.box.margin.isSome:
      var current =
        if style.box.margin.isSome: style.box.margin.get
        else: edges(0)
      current.copySide(declaration.property, env.parent.get.box.margin.get)
      style.box.margin = some(current)
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent margin")
  of mmInitial, mmUnset:
    var current =
      if style.box.margin.isSome: style.box.margin.get
      else: edges(0)
    current.setSide(declaration.property, 0)
    style.box.margin = some(current)
  of mmRelative:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "relative " & declaration.property & " requires a value")
      return
    let base = currentMargin(style, env)
    if base.isNone:
      diagnostics.addError(declaration.property, "relative " & declaration.property & " requires existing or parent margin")
      return
    let delta = resolveLength(declaration.operation.value.get, env, declaration.property, diagnostics)
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
