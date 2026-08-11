import std/options
import ../core/[computed_style, declaration, diagnostics, property, style_value]
import ./length_resolution

proc resolveSizing(value: StyleValue; env: ResolveEnv; property: string;
    diagnostics: var Diagnostics): Option[LengthValue] =
  normalizeLength(value, env, property, {
    ukPercent, ukContent, ukMinContent, ukMaxContent, ukFitContent, ukAuto,
    ukNone
  }, diagnostics)

proc setWidth(style: var ComputedStyle; value: Option[LengthValue]) =
  if value.isSome and value.get.kind == ukPx:
    style.layout.width = some(value.get.value)
    if not style.layout.sizing.isNil:
      style.layout.sizing.width = none(LengthValue)
  else:
    style.layout.width = none(float32)
    if value.isSome:
      style.ensureSizing()
      style.layout.sizing.width = value
    elif not style.layout.sizing.isNil:
      style.layout.sizing.width = none(LengthValue)

proc setHeight(style: var ComputedStyle; value: Option[LengthValue]) =
  if value.isSome and value.get.kind == ukPx:
    style.layout.height = some(value.get.value)
    if not style.layout.sizing.isNil:
      style.layout.sizing.height = none(LengthValue)
  else:
    style.layout.height = none(float32)
    if value.isSome:
      style.ensureSizing()
      style.layout.sizing.height = value
    elif not style.layout.sizing.isNil:
      style.layout.sizing.height = none(LengthValue)

proc inheritedWidth(style: ComputedStyle): Option[LengthValue] =
  if not style.layout.sizing.isNil and style.layout.sizing.width.isSome:
    style.layout.sizing.width
  elif style.layout.width.isSome:
    some(LengthValue(kind: ukPx, value: style.layout.width.get))
  else:
    none(LengthValue)

proc inheritedHeight(style: ComputedStyle): Option[LengthValue] =
  if not style.layout.sizing.isNil and style.layout.sizing.height.isSome:
    style.layout.sizing.height
  elif style.layout.height.isSome:
    some(LengthValue(kind: ukPx, value: style.layout.height.get))
  else:
    none(LengthValue)

proc applyWidth(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "width requires a value")
      return
    style.setWidth(resolveSizing(declaration.operation.value.get, env, declaration.property, diagnostics))
  of mmInitial, mmUnset:
    style.setWidth(none(LengthValue))
  of mmInherit:
    if env.parent.isSome:
      style.setWidth(env.parent.get.inheritedWidth())
    else:
      diagnostics.addError(declaration.property, "cannot inherit width without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "width relative merge is not implemented yet")

proc applyHeight(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "height requires a value")
      return
    style.setHeight(resolveSizing(declaration.operation.value.get, env, declaration.property, diagnostics))
  of mmInitial, mmUnset:
    style.setHeight(none(LengthValue))
  of mmInherit:
    if env.parent.isSome:
      style.setHeight(env.parent.get.inheritedHeight())
    else:
      diagnostics.addError(declaration.property, "cannot inherit height without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "height relative merge is not implemented yet")

proc setSizeSlot(style: var ComputedStyle; property: string; value: Option[LengthValue]) =
  let pixelValue =
    if value.isSome and value.get.kind == ukPx: some(value.get.value)
    else: none(float32)
  if value.isSome and value.get.kind != ukPx:
    style.ensureSizing()
  case property
  of "min-width", "min-inline-size":
    style.layout.minWidth = pixelValue
    if not style.layout.sizing.isNil:
      style.layout.sizing.minWidth = if pixelValue.isSome: none(LengthValue) else: value
  of "max-width", "max-inline-size":
    style.layout.maxWidth = pixelValue
    if not style.layout.sizing.isNil:
      style.layout.sizing.maxWidth = if pixelValue.isSome: none(LengthValue) else: value
  of "min-height", "min-block-size":
    style.layout.minHeight = pixelValue
    if not style.layout.sizing.isNil:
      style.layout.sizing.minHeight = if pixelValue.isSome: none(LengthValue) else: value
  of "max-height", "max-block-size":
    style.layout.maxHeight = pixelValue
    if not style.layout.sizing.isNil:
      style.layout.sizing.maxHeight = if pixelValue.isSome: none(LengthValue) else: value
  else:
    discard

proc applySizeConstraint(
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
    style.setSizeSlot(declaration.property, resolveSizing(declaration.operation.value.get, env, declaration.property, diagnostics))
  of mmInitial, mmUnset:
    style.setSizeSlot(declaration.property, none(LengthValue))
  of mmInherit:
    if env.parent.isNone:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
      return
    let parent = env.parent.get
    let inherited =
      case declaration.property
      of "min-width", "min-inline-size":
        if not parent.layout.sizing.isNil and parent.layout.sizing.minWidth.isSome:
          parent.layout.sizing.minWidth
        elif parent.layout.minWidth.isSome:
          some(LengthValue(kind: ukPx, value: parent.layout.minWidth.get))
        else: none(LengthValue)
      of "max-width", "max-inline-size":
        if not parent.layout.sizing.isNil and parent.layout.sizing.maxWidth.isSome:
          parent.layout.sizing.maxWidth
        elif parent.layout.maxWidth.isSome:
          some(LengthValue(kind: ukPx, value: parent.layout.maxWidth.get))
        else: none(LengthValue)
      of "min-height", "min-block-size":
        if not parent.layout.sizing.isNil and parent.layout.sizing.minHeight.isSome:
          parent.layout.sizing.minHeight
        elif parent.layout.minHeight.isSome:
          some(LengthValue(kind: ukPx, value: parent.layout.minHeight.get))
        else: none(LengthValue)
      of "max-height", "max-block-size":
        if not parent.layout.sizing.isNil and parent.layout.sizing.maxHeight.isSome:
          parent.layout.sizing.maxHeight
        elif parent.layout.maxHeight.isSome:
          some(LengthValue(kind: ukPx, value: parent.layout.maxHeight.get))
        else: none(LengthValue)
      else:
        none(LengthValue)
    style.setSizeSlot(declaration.property, inherited)
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " relative merge is not implemented yet")

proc applyAspectRatio(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "aspect-ratio requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svNumber:
      if value.number <= 0:
        diagnostics.addError(declaration.property, "aspect-ratio must be positive")
      else:
        style.layout.aspectRatio = some(value.number)
    of svKeyword:
      if value.keyword == "auto":
        style.layout.aspectRatio = none(float32)
      else:
        diagnostics.addError(declaration.property, "unsupported aspect-ratio keyword")
    else:
      diagnostics.addError(declaration.property, "aspect-ratio requires a number or auto")
  of mmInitial, mmUnset:
    style.layout.aspectRatio = none(float32)
  of mmInherit:
    if env.parent.isSome:
      style.layout.aspectRatio = env.parent.get.layout.aspectRatio
    else:
      diagnostics.addError(declaration.property, "cannot inherit aspect-ratio without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "aspect-ratio relative merge is not implemented yet")

proc applyBoxSizing(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "box-sizing only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.layout.boxSizing = bsContentBox
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "box-sizing requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "content-box":
    style.layout.boxSizing = bsContentBox
  of "border-box":
    style.layout.boxSizing = bsBorderBox
  else:
    diagnostics.addError(declaration.property, "unsupported box-sizing keyword")

let widthProperty* = PropertyImpl(name: "width", apply: applyWidth)
let heightProperty* = PropertyImpl(name: "height", apply: applyHeight)
let inlineSizeProperty* = PropertyImpl(name: "inline-size", apply: applyWidth)
let blockSizeProperty* = PropertyImpl(name: "block-size", apply: applyHeight)
let minWidthProperty* = PropertyImpl(name: "min-width", apply: applySizeConstraint)
let maxWidthProperty* = PropertyImpl(name: "max-width", apply: applySizeConstraint)
let minHeightProperty* = PropertyImpl(name: "min-height", apply: applySizeConstraint)
let maxHeightProperty* = PropertyImpl(name: "max-height", apply: applySizeConstraint)
let minInlineSizeProperty* = PropertyImpl(name: "min-inline-size", apply: applySizeConstraint)
let maxInlineSizeProperty* = PropertyImpl(name: "max-inline-size", apply: applySizeConstraint)
let minBlockSizeProperty* = PropertyImpl(name: "min-block-size", apply: applySizeConstraint)
let maxBlockSizeProperty* = PropertyImpl(name: "max-block-size", apply: applySizeConstraint)
let aspectRatioProperty* = PropertyImpl(name: "aspect-ratio", apply: applyAspectRatio)
let boxSizingProperty* = PropertyImpl(name: "box-sizing", apply: applyBoxSizing)
