import std/options
import ../core/[color, computed_style, declaration, diagnostics, property,
    style_color, style_value]

proc applyBackgroundColor(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or
        declaration.operation.value.get.kind != svColor:
      diagnostics.addError(declaration.property, "background-color requires a color value")
      return
    style.box.backgroundColor = declaration.operation.value.get.resolveStyleColor(
        style, env)
  of mmInitial, mmUnset:
    style.box.backgroundColor = none(Color)
  of mmInherit:
    if env.parent.isSome:
      style.box.backgroundColor = env.parent.get.box.backgroundColor
    else:
      diagnostics.addError(declaration.property, "cannot inherit background-color without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "background-color does not support relative merge")

let backgroundColorProperty* = PropertyImpl(name: "background-color",
    apply: applyBackgroundColor)

proc applyBackground(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "background requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svColor:
      style.box.backgroundColor = value.resolveStyleColor(style, env)
    of svKeyword:
      if value.keyword == "none":
        style.box.backgroundImage = none(string)
        style.box.backgroundGradient = none(LinearGradient)
      else:
        style.box.backgroundImage = some(value.keyword)
        style.box.backgroundGradient = none(LinearGradient)
    of svLinearGradient:
      style.box.backgroundImage = none(string)
      style.box.backgroundGradient = some(LinearGradient(
          angle: value.gradientAngle,
          interpolationSpace: value.gradientInterpolationSpace,
          stops: value.resolveGradientStops(style.foregroundColor(env))))
    else:
      diagnostics.addError(declaration.property, "background supports color values, image keywords, or linear gradients")
  of mmInitial, mmUnset:
    style.box.backgroundColor = none(Color)
    style.box.backgroundImage = none(string)
    style.box.backgroundGradient = none(LinearGradient)
  of mmInherit:
    if env.parent.isSome:
      style.box.backgroundColor = env.parent.get.box.backgroundColor
      style.box.backgroundImage = env.parent.get.box.backgroundImage
      style.box.backgroundGradient = env.parent.get.box.backgroundGradient
    else:
      diagnostics.addError(declaration.property, "cannot inherit background without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "background does not support relative merge")

proc applyBackgroundImage(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "background-image requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svKeyword:
      if value.keyword == "none":
        style.box.backgroundImage = none(string)
        style.box.backgroundGradient = none(LinearGradient)
      else:
        style.box.backgroundImage = some(value.keyword)
        style.box.backgroundGradient = none(LinearGradient)
    of svLinearGradient:
      style.box.backgroundImage = none(string)
      style.box.backgroundGradient = some(LinearGradient(
          angle: value.gradientAngle,
          interpolationSpace: value.gradientInterpolationSpace,
          stops: value.resolveGradientStops(style.foregroundColor(env))))
    else:
      diagnostics.addError(declaration.property, "background-image requires a keyword or linear gradient value")
  of mmInitial, mmUnset:
    style.box.backgroundImage = none(string)
    style.box.backgroundGradient = none(LinearGradient)
  of mmInherit:
    if env.parent.isSome:
      style.box.backgroundImage = env.parent.get.box.backgroundImage
      style.box.backgroundGradient = env.parent.get.box.backgroundGradient
    else:
      diagnostics.addError(declaration.property, "cannot inherit background-image without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "background-image does not support relative merge")

proc applyBackgroundSize(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "background-size requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svKeyword:
      case value.keyword
      of "auto":
        style.box.backgroundSize = some(BackgroundSize(kind: bgSizeAuto))
      of "cover":
        style.box.backgroundSize = some(BackgroundSize(kind: bgSizeCover))
      of "contain":
        style.box.backgroundSize = some(BackgroundSize(kind: bgSizeContain))
      else:
        diagnostics.addError(declaration.property, "unsupported background-size keyword")
    of svLength:
      if value.length.kind != ukPx:
        diagnostics.addError(declaration.property, "only px is supported for length background-size")
        return
      style.box.backgroundSize = some(BackgroundSize(kind: bgSizeLength,
          width: some(value.length.value), height: none(float32)))
    else:
      diagnostics.addError(declaration.property, "background-size requires a keyword or length value")
  of mmInitial, mmUnset:
    style.box.backgroundSize = some(BackgroundSize(kind: bgSizeAuto))
  of mmInherit:
    if env.parent.isSome:
      style.box.backgroundSize = env.parent.get.box.backgroundSize
    else:
      diagnostics.addError(declaration.property, "cannot inherit background-size without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "background-size does not support relative merge")

proc applyBackgroundPositionAxis(
    style: var ComputedStyle;
    declaration: Declaration;
    diagnostics: var Diagnostics
) =
  if declaration.operation.value.isNone:
    diagnostics.addError(declaration.property, declaration.property & " requires a value")
    return
  let value = declaration.operation.value.get
  var resolved: Option[float32]
  case value.kind
  of svNumber:
    resolved = some(value.number)
  of svLength:
    if value.length.kind in {ukPx, ukPercent}:
      resolved = some(value.length.value)
    else:
      diagnostics.addError(declaration.property, "unsupported background-position unit")
      return
  of svKeyword:
    case value.keyword
    of "left", "top":
      resolved = some(0.0'f32)
    of "center":
      resolved = some(50.0'f32)
    of "right", "bottom":
      resolved = some(100.0'f32)
    else:
      diagnostics.addError(declaration.property, "unsupported background-position keyword")
      return
  else:
    diagnostics.addError(declaration.property, declaration.property & " requires a number, length, or keyword")
    return
  if declaration.property == "background-position-y":
    style.box.backgroundPosition.y = resolved.get
  else:
    style.box.backgroundPosition.x = resolved.get
    if declaration.property == "background-position":
      style.box.backgroundPosition.y = resolved.get

proc applyBackgroundPosition(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    style.applyBackgroundPositionAxis(declaration, diagnostics)
  of mmInitial, mmUnset:
    style.box.backgroundPosition = ObjectPosition(x: 0, y: 0)
  of mmInherit:
    if env.parent.isSome:
      style.box.backgroundPosition = env.parent.get.box.backgroundPosition
    else:
      diagnostics.addError(declaration.property, "cannot inherit " &
          declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc applyBackgroundRepeat(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "background-repeat only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.box.backgroundRepeat = bgRepeat
    return
  if declaration.operation.value.isNone or
      declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "background-repeat requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "repeat":
    style.box.backgroundRepeat = bgRepeat
  of "no-repeat":
    style.box.backgroundRepeat = bgNoRepeat
  of "repeat-x":
    style.box.backgroundRepeat = bgRepeatX
  of "repeat-y":
    style.box.backgroundRepeat = bgRepeatY
  else:
    diagnostics.addError(declaration.property, "unsupported background-repeat keyword")

proc backgroundBoxFrom(value: string): Option[BackgroundBox] =
  case value
  of "border-box":
    some(bgBorderBox)
  of "padding-box":
    some(bgPaddingBox)
  of "content-box":
    some(bgContentBox)
  else:
    none(BackgroundBox)

proc applyBackgroundBox(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, declaration.property & " only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    if declaration.property == "background-origin":
      style.box.backgroundOrigin = bgPaddingBox
    else:
      style.box.backgroundClip = bgBorderBox
    return
  if declaration.operation.value.isNone or
      declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, declaration.property & " requires a keyword value")
    return
  let box = backgroundBoxFrom(declaration.operation.value.get.keyword)
  if box.isNone:
    diagnostics.addError(declaration.property, "unsupported " &
        declaration.property & " keyword")
    return
  if declaration.property == "background-origin":
    style.box.backgroundOrigin = box.get
  else:
    style.box.backgroundClip = box.get

proc applyBackgroundAttachment(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "background-attachment only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.box.backgroundAttachment = bgScroll
    return
  if declaration.operation.value.isNone or
      declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "background-attachment requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "scroll":
    style.box.backgroundAttachment = bgScroll
  of "fixed":
    style.box.backgroundAttachment = bgFixed
  of "local":
    style.box.backgroundAttachment = bgLocal
  else:
    diagnostics.addError(declaration.property, "unsupported background-attachment keyword")

proc applyBackgroundBlendMode(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "background-blend-mode only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.box.backgroundBlendMode = bmNormal
    return
  if declaration.operation.value.isNone or
      declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "background-blend-mode requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "normal":
    style.box.backgroundBlendMode = bmNormal
  of "multiply":
    style.box.backgroundBlendMode = bmMultiply
  of "screen":
    style.box.backgroundBlendMode = bmScreen
  of "overlay":
    style.box.backgroundBlendMode = bmOverlay
  of "darken":
    style.box.backgroundBlendMode = bmDarken
  of "lighten":
    style.box.backgroundBlendMode = bmLighten
  else:
    diagnostics.addError(declaration.property, "unsupported background-blend-mode keyword")

let backgroundProperty* = PropertyImpl(name: "background",
    apply: applyBackground)
let backgroundImageProperty* = PropertyImpl(name: "background-image",
    apply: applyBackgroundImage)
let backgroundSizeProperty* = PropertyImpl(name: "background-size",
    apply: applyBackgroundSize)
let backgroundPositionProperty* = PropertyImpl(name: "background-position",
    apply: applyBackgroundPosition)
let backgroundPositionXProperty* = PropertyImpl(name: "background-position-x",
    apply: applyBackgroundPosition)
let backgroundPositionYProperty* = PropertyImpl(name: "background-position-y",
    apply: applyBackgroundPosition)
let backgroundRepeatProperty* = PropertyImpl(name: "background-repeat",
    apply: applyBackgroundRepeat)
let backgroundClipProperty* = PropertyImpl(name: "background-clip",
    apply: applyBackgroundBox)
let backgroundOriginProperty* = PropertyImpl(name: "background-origin",
    apply: applyBackgroundBox)
let backgroundAttachmentProperty* = PropertyImpl(name: "background-attachment",
    apply: applyBackgroundAttachment)
let backgroundBlendModeProperty* = PropertyImpl(name: "background-blend-mode",
    apply: applyBackgroundBlendMode)
