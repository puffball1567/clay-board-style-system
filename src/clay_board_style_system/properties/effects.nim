import std/options
import ../core/[color, computed_style, declaration, diagnostics, property,
    style_color, style_value]
import ./length_resolution

proc applyBoxShadow(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "box-shadow requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svKeyword:
      if value.keyword == "none":
        style.box.boxShadow = none(BoxShadow)
      else:
        diagnostics.addError(declaration.property, "unsupported box-shadow keyword")
    of svShadow:
      let offsetX = resolveAbsoluteLength(value.shadowOffsetX, env,
          declaration.property, diagnostics)
      let offsetY = resolveAbsoluteLength(value.shadowOffsetY, env,
          declaration.property, diagnostics)
      if offsetX.isNone or offsetY.isNone:
        return
      var blur = 0.0'f32
      var spread = 0.0'f32
      if value.shadowBlur.isSome:
        let resolved = resolveAbsoluteLength(value.shadowBlur.get, env,
            declaration.property, diagnostics)
        if resolved.isSome:
          blur = resolved.get
      if value.shadowSpread.isSome:
        let resolved = resolveAbsoluteLength(value.shadowSpread.get, env,
            declaration.property, diagnostics)
        if resolved.isSome:
          spread = resolved.get
      style.box.boxShadow = some(BoxShadow(
        offsetX: offsetX.get,
        offsetY: offsetY.get,
        blur: blur,
        spread: spread,
        color: value.resolveShadowColor(style, env)
      ))
    else:
      diagnostics.addError(declaration.property, "box-shadow requires a structured shadow value or none")
  of mmInitial, mmUnset:
    style.box.boxShadow = none(BoxShadow)
  of mmInherit:
    if env.parent.isSome:
      style.box.boxShadow = env.parent.get.box.boxShadow
    else:
      diagnostics.addError(declaration.property, "cannot inherit box-shadow without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "box-shadow does not support relative merge")

proc setVisualEffect(style: var ComputedStyle; property: string; value: Option[string]) =
  if property == "filter":
    style.visual.filter = value
  else:
    style.visual.backdropFilter = value

proc visualEffect(style: ComputedStyle; property: string): Option[string] =
  if property == "filter": style.visual.filter else: style.visual.backdropFilter

proc applyVisualEffect(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or
        declaration.operation.value.get.kind != svKeyword:
      diagnostics.addError(declaration.property, declaration.property & " requires a keyword value")
      return
    let value = declaration.operation.value.get.keyword
    if value == "none":
      style.setVisualEffect(declaration.property, none(string))
    else:
      style.setVisualEffect(declaration.property, some(value))
  of mmInitial, mmUnset:
    style.setVisualEffect(declaration.property, none(string))
  of mmInherit:
    if env.parent.isSome:
      style.setVisualEffect(declaration.property, env.parent.get.visualEffect(
          declaration.property))
    else:
      diagnostics.addError(declaration.property, "cannot inherit " &
          declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc parseBlendMode(keyword: string): Option[BlendMode] =
  case keyword
  of "normal":
    some(bmNormal)
  of "multiply":
    some(bmMultiply)
  of "screen":
    some(bmScreen)
  of "overlay":
    some(bmOverlay)
  of "darken":
    some(bmDarken)
  of "lighten":
    some(bmLighten)
  else:
    none(BlendMode)

proc applyMixBlendMode(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or
        declaration.operation.value.get.kind != svKeyword:
      diagnostics.addError(declaration.property, "mix-blend-mode requires a keyword value")
      return
    let parsed = parseBlendMode(declaration.operation.value.get.keyword)
    if parsed.isSome:
      style.visual.mixBlendMode = parsed.get
    else:
      diagnostics.addError(declaration.property, "unsupported mix-blend-mode keyword")
  of mmInitial, mmUnset:
    style.visual.mixBlendMode = bmNormal
  of mmInherit:
    if env.parent.isSome:
      style.visual.mixBlendMode = env.parent.get.visual.mixBlendMode
    else:
      diagnostics.addError(declaration.property, "cannot inherit mix-blend-mode without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "mix-blend-mode does not support relative merge")

proc applyIsolation(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "isolation only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.visual.isolation = isoAuto
    return
  if declaration.operation.value.isNone or
      declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "isolation requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "auto":
    style.visual.isolation = isoAuto
  of "isolate":
    style.visual.isolation = isoIsolate
  else:
    diagnostics.addError(declaration.property, "unsupported isolation keyword")

proc applyBoxDecorationBreak(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "box-decoration-break only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.box.boxDecorationBreak = bdbSlice
    return
  if declaration.operation.value.isNone or
      declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "box-decoration-break requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "slice":
    style.box.boxDecorationBreak = bdbSlice
  of "clone":
    style.box.boxDecorationBreak = bdbClone
  else:
    diagnostics.addError(declaration.property, "unsupported box-decoration-break keyword")

proc setOutlineWidth(style: var ComputedStyle; value: float32) =
  style.box.outlineWidth = value

proc setOutlineColor(style: var ComputedStyle; value: Option[Color]) =
  style.box.outlineColor = value

proc applyOutlineWidth(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "outline-width requires a value")
      return
    let resolved = resolveAbsoluteLength(declaration.operation.value.get,
        env, declaration.property, diagnostics)
    if resolved.isSome:
      style.setOutlineWidth(resolved.get)
  of mmInitial, mmUnset:
    style.setOutlineWidth(0)
  of mmInherit:
    if env.parent.isSome:
      style.setOutlineWidth(env.parent.get.box.outlineWidth)
    else:
      diagnostics.addError(declaration.property, "cannot inherit outline-width without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "outline-width relative merge is not implemented yet")

proc applyOutlineColor(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or
        declaration.operation.value.get.kind != svColor:
      diagnostics.addError(declaration.property, "outline-color requires a color value")
      return
    style.setOutlineColor(declaration.operation.value.get.resolveStyleColor(
        style, env))
  of mmInitial, mmUnset:
    style.setOutlineColor(some(rgba(0, 0, 0, 1)))
  of mmInherit:
    if env.parent.isSome:
      style.setOutlineColor(env.parent.get.box.outlineColor)
    else:
      diagnostics.addError(declaration.property, "cannot inherit outline-color without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "outline-color does not support relative merge")

proc applyOutlineStyle(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "outline-style only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.box.outlineVisible = true
    return
  if declaration.operation.value.isNone or
      declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "outline-style requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "solid":
    style.box.outlineVisible = true
  of "none", "hidden":
    style.box.outlineVisible = false
  else:
    diagnostics.addError(declaration.property, "only solid, none, and hidden outline styles are supported initially")

proc applyOutlineOffset(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "outline-offset requires a value")
      return
    let resolved = resolveAbsoluteLength(declaration.operation.value.get,
        env, declaration.property, diagnostics)
    if resolved.isSome:
      style.box.outlineOffset = resolved.get
  of mmInitial, mmUnset:
    style.box.outlineOffset = 0
  of mmInherit:
    if env.parent.isSome:
      style.box.outlineOffset = env.parent.get.box.outlineOffset
    else:
      diagnostics.addError(declaration.property, "cannot inherit outline-offset without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "outline-offset relative merge is not implemented yet")

proc applyOutline(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "outline requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svLength:
      let resolved = resolveAbsoluteLength(value, env, declaration.property,
          diagnostics)
      if resolved.isSome:
        style.setOutlineWidth(resolved.get)
    of svColor:
      style.setOutlineColor(value.resolveStyleColor(style, env))
    of svKeyword:
      case value.keyword
      of "solid":
        style.box.outlineVisible = true
      of "none", "hidden":
        style.box.outlineVisible = false
      else:
        diagnostics.addError(declaration.property, "unsupported outline keyword")
    of svBorder:
      if value.borderWidth.isSome:
        let resolved = resolveAbsoluteLength(value.borderWidth.get, env,
            declaration.property, diagnostics)
        if resolved.isSome:
          style.setOutlineWidth(resolved.get)
      let color = value.resolveBorderColor(style, env)
      if color.isSome:
        style.setOutlineColor(color)
      if value.borderStyle.isSome:
        case value.borderStyle.get
        of "solid":
          style.box.outlineVisible = true
        of "none", "hidden":
          style.box.outlineVisible = false
        else:
          diagnostics.addError(declaration.property, "unsupported outline style keyword")
    else:
      diagnostics.addError(declaration.property, "outline requires a length, color, keyword, or structured border value")
  of mmInitial, mmUnset:
    style.box.outlineWidth = 0
    style.box.outlineColor = some(rgba(0, 0, 0, 1))
    style.box.outlineVisible = true
  of mmInherit:
    if env.parent.isSome:
      style.box.outlineWidth = env.parent.get.box.outlineWidth
      style.box.outlineColor = env.parent.get.box.outlineColor
      style.box.outlineVisible = env.parent.get.box.outlineVisible
    else:
      diagnostics.addError(declaration.property, "cannot inherit outline without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "outline relative merge is not implemented yet")

let boxShadowProperty* = PropertyImpl(name: "box-shadow", apply: applyBoxShadow)
let filterProperty* = PropertyImpl(name: "filter", apply: applyVisualEffect)
let backdropFilterProperty* = PropertyImpl(name: "backdrop-filter",
    apply: applyVisualEffect)
let mixBlendModeProperty* = PropertyImpl(name: "mix-blend-mode",
    apply: applyMixBlendMode)
let isolationProperty* = PropertyImpl(name: "isolation", apply: applyIsolation)
let boxDecorationBreakProperty* = PropertyImpl(name: "box-decoration-break",
    apply: applyBoxDecorationBreak)
let outlineProperty* = PropertyImpl(name: "outline", apply: applyOutline)
let outlineWidthProperty* = PropertyImpl(name: "outline-width",
    apply: applyOutlineWidth)
let outlineStyleProperty* = PropertyImpl(name: "outline-style",
    apply: applyOutlineStyle)
let outlineColorProperty* = PropertyImpl(name: "outline-color",
    apply: applyOutlineColor)
let outlineOffsetProperty* = PropertyImpl(name: "outline-offset",
    apply: applyOutlineOffset)
