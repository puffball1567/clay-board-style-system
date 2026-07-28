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
    diagnostics.addError(property, "font-size requires a length value")
    return none(float32)

  case value.length.kind
  of ukPx:
    some(value.length.value)
  of ukPercent:
    if env.parent.isSome and env.parent.get.text.fontSize.isSome:
      some(env.parent.get.text.fontSize.get * value.length.value / 100.0'f32)
    else:
      diagnostics.addError(property, "percent font-size requires parent font-size")
      none(float32)
  of ukEm:
    if env.currentFontSize.isSome:
      some(env.currentFontSize.get * value.length.value)
    else:
      diagnostics.addError(property, "em font-size requires current font-size")
      none(float32)
  of ukRem:
    if env.rootFontSize.isSome:
      some(env.rootFontSize.get * value.length.value)
    else:
      diagnostics.addError(property, "rem font-size requires root font-size")
      none(float32)
  else:
    diagnostics.addError(property, "unsupported font-size unit")
    none(float32)

proc applyFontSize(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "font-size requires a value")
      return
    let resolved = resolveLength(declaration.operation.value.get, env, declaration.property, diagnostics)
    if resolved.isSome:
      style.text.fontSize = resolved
  of mmInherit:
    if env.parent.isSome and env.parent.get.text.fontSize.isSome:
      style.text.fontSize = env.parent.get.text.fontSize
    else:
      diagnostics.addError(declaration.property, "cannot inherit font-size without parent font-size")
  of mmInitial, mmUnset:
    style.text.fontSize = some(16.0'f32)
  of mmRelative:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "relative font-size requires a value")
      return
    let base =
      if env.parent.isSome and env.parent.get.text.fontSize.isSome:
        env.parent.get.text.fontSize.get
      else:
        diagnostics.addError(declaration.property, "relative font-size requires parent font-size")
        return
    let delta = resolveLength(declaration.operation.value.get, env, declaration.property, diagnostics)
    if delta.isSome:
      style.text.fontSize = some(base + delta.get)

let fontSizeProperty* = PropertyImpl(name: "font-size", apply: applyFontSize)
