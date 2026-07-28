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
    diagnostics.addError(property, "padding requires a length value")
    return none(float32)

  case value.length.kind
  of ukPx:
    some(value.length.value)
  of ukEm:
    if env.currentFontSize.isSome:
      some(env.currentFontSize.get * value.length.value)
    else:
      diagnostics.addError(property, "em padding requires current font-size")
      none(float32)
  of ukRem:
    if env.rootFontSize.isSome:
      some(env.rootFontSize.get * value.length.value)
    else:
      diagnostics.addError(property, "rem padding requires root font-size")
      none(float32)
  else:
    diagnostics.addError(property, "unsupported padding unit")
    none(float32)

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
    let resolved = resolveLength(declaration.operation.value.get, env, declaration.property, diagnostics)
    if resolved.isSome:
      style.box.padding = some(edges(resolved.get))
  of mmInherit:
    if env.parent.isSome and env.parent.get.box.padding.isSome:
      style.box.padding = env.parent.get.box.padding
    else:
      diagnostics.addError(declaration.property, "cannot inherit padding without parent padding")
  of mmInitial, mmUnset:
    style.box.padding = some(edges(0))
  of mmRelative:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "relative padding requires a value")
      return
    let base = currentPadding(style, env)
    if base.isNone:
      diagnostics.addError(declaration.property, "relative padding requires existing or parent padding")
      return
    let delta = resolveLength(declaration.operation.value.get, env, declaration.property, diagnostics)
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
    let resolved = resolveLength(declaration.operation.value.get, env, declaration.property, diagnostics)
    if resolved.isSome:
      var current =
        if style.box.padding.isSome: style.box.padding.get
        else: edges(0)
      current.setSide(declaration.property, resolved.get)
      style.box.padding = some(current)
  of mmInherit:
    if env.parent.isSome and env.parent.get.box.padding.isSome:
      var current =
        if style.box.padding.isSome: style.box.padding.get
        else: edges(0)
      current.copySide(declaration.property, env.parent.get.box.padding.get)
      style.box.padding = some(current)
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent padding")
  of mmInitial, mmUnset:
    var current =
      if style.box.padding.isSome: style.box.padding.get
      else: edges(0)
    current.setSide(declaration.property, 0)
    style.box.padding = some(current)
  of mmRelative:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "relative " & declaration.property & " requires a value")
      return
    let base = currentPadding(style, env)
    if base.isNone:
      diagnostics.addError(declaration.property, "relative " & declaration.property & " requires existing or parent padding")
      return
    let delta = resolveLength(declaration.operation.value.get, env, declaration.property, diagnostics)
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
