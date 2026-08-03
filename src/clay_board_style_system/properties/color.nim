import std/options
import ../core/[
  color,
  computed_style,
  declaration,
  diagnostics,
  property,
  style_color,
  style_value
]

proc applyColor(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or
        declaration.operation.value.get.kind != svColor:
      diagnostics.addError(declaration.property, "color requires a color value")
      return
    style.text.color = declaration.operation.value.get.resolveStyleColor(
      env.inheritedForegroundColor()
    )
  of mmInherit:
    if env.parent.isSome and env.parent.get.text.color.isSome:
      style.text.color = env.parent.get.text.color
    else:
      diagnostics.addError(declaration.property, "cannot inherit color without parent color")
  of mmInitial, mmUnset:
    style.text.color = some(rgba(0, 0, 0, 1))
  of mmRelative:
    diagnostics.addError(declaration.property, "color does not support relative merge")

let colorProperty* = PropertyImpl(name: "color", apply: applyColor)
