import std/options
import ../core/[color, computed_style, declaration, diagnostics, property, style_value]

proc resolvePx(value: StyleValue; property: string; diagnostics: var Diagnostics): Option[float32] =
  if value.kind != svLength:
    diagnostics.addError(property, property & " requires a length value")
    return none(float32)
  if value.length.kind != ukPx:
    diagnostics.addError(property, "only px is supported for initial border implementation")
    return none(float32)
  some(value.length.value)

proc setBorderWidth(style: var ComputedStyle; property: string; value: float32) =
  case property
  of "border-width":
    style.box.borderWidth = value
    style.box.borderWidths = edges(value)
  of "border-top-width", "border-block-start-width":
    style.box.borderWidths.top = value
  of "border-right-width", "border-inline-end-width":
    style.box.borderWidths.right = value
  of "border-bottom-width", "border-block-end-width":
    style.box.borderWidths.bottom = value
  of "border-left-width", "border-inline-start-width":
    style.box.borderWidths.left = value
  of "border-inline-width":
    style.box.borderWidths.left = value
    style.box.borderWidths.right = value
  of "border-block-width":
    style.box.borderWidths.top = value
    style.box.borderWidths.bottom = value
  else:
    discard

proc inheritBorderWidth(style: var ComputedStyle; property: string; parent: ComputedStyle) =
  case property
  of "border-width":
    style.box.borderWidth = parent.box.borderWidth
    style.box.borderWidths = parent.box.borderWidths
  of "border-top-width", "border-block-start-width":
    style.box.borderWidths.top = parent.box.borderWidths.top
  of "border-right-width", "border-inline-end-width":
    style.box.borderWidths.right = parent.box.borderWidths.right
  of "border-bottom-width", "border-block-end-width":
    style.box.borderWidths.bottom = parent.box.borderWidths.bottom
  of "border-left-width", "border-inline-start-width":
    style.box.borderWidths.left = parent.box.borderWidths.left
  of "border-inline-width":
    style.box.borderWidths.left = parent.box.borderWidths.left
    style.box.borderWidths.right = parent.box.borderWidths.right
  of "border-block-width":
    style.box.borderWidths.top = parent.box.borderWidths.top
    style.box.borderWidths.bottom = parent.box.borderWidths.bottom
  else:
    discard

proc applyBorderWidth(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "border-width requires a value")
      return
    let resolved = resolvePx(declaration.operation.value.get, declaration.property, diagnostics)
    if resolved.isSome:
      style.setBorderWidth(declaration.property, resolved.get)
  of mmInitial, mmUnset:
    style.setBorderWidth(declaration.property, 0)
  of mmInherit:
    if env.parent.isSome:
      style.inheritBorderWidth(declaration.property, env.parent.get)
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " relative merge is not implemented yet")

proc setBorderRadius(style: var ComputedStyle; property: string; value: float32) =
  case property
  of "border-radius":
    style.box.borderRadius = value
    style.box.borderRadii = corners(value)
  of "border-top-left-radius", "border-start-start-radius":
    style.box.borderRadii.topLeft = value
  of "border-top-right-radius", "border-start-end-radius":
    style.box.borderRadii.topRight = value
  of "border-bottom-right-radius", "border-end-end-radius":
    style.box.borderRadii.bottomRight = value
  of "border-bottom-left-radius", "border-end-start-radius":
    style.box.borderRadii.bottomLeft = value
  else:
    discard

proc inheritBorderRadius(style: var ComputedStyle; property: string; parent: ComputedStyle) =
  case property
  of "border-radius":
    style.box.borderRadius = parent.box.borderRadius
    style.box.borderRadii = parent.box.borderRadii
  of "border-top-left-radius", "border-start-start-radius":
    style.box.borderRadii.topLeft = parent.box.borderRadii.topLeft
  of "border-top-right-radius", "border-start-end-radius":
    style.box.borderRadii.topRight = parent.box.borderRadii.topRight
  of "border-bottom-right-radius", "border-end-end-radius":
    style.box.borderRadii.bottomRight = parent.box.borderRadii.bottomRight
  of "border-bottom-left-radius", "border-end-start-radius":
    style.box.borderRadii.bottomLeft = parent.box.borderRadii.bottomLeft
  else:
    discard

proc applyBorderRadius(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "border-radius requires a value")
      return
    let resolved = resolvePx(declaration.operation.value.get, declaration.property, diagnostics)
    if resolved.isSome:
      style.setBorderRadius(declaration.property, resolved.get)
  of mmInitial, mmUnset:
    style.setBorderRadius(declaration.property, 0)
  of mmInherit:
    if env.parent.isSome:
      style.inheritBorderRadius(declaration.property, env.parent.get)
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " relative merge is not implemented yet")

proc setBorderColor(style: var ComputedStyle; property: string; value: Option[Color]) =
  case property
  of "border-color":
    style.box.borderColor = value
    style.box.borderColors = edgeColors(value)
  of "border-top-color", "border-block-start-color":
    style.box.borderColors.top = value
  of "border-right-color", "border-inline-end-color":
    style.box.borderColors.right = value
  of "border-bottom-color", "border-block-end-color":
    style.box.borderColors.bottom = value
  of "border-left-color", "border-inline-start-color":
    style.box.borderColors.left = value
  of "border-inline-color":
    style.box.borderColors.left = value
    style.box.borderColors.right = value
  of "border-block-color":
    style.box.borderColors.top = value
    style.box.borderColors.bottom = value
  else:
    discard

proc inheritBorderColor(style: var ComputedStyle; property: string; parent: ComputedStyle) =
  case property
  of "border-color":
    style.box.borderColor = parent.box.borderColor
    style.box.borderColors = parent.box.borderColors
  of "border-top-color", "border-block-start-color":
    style.box.borderColors.top = parent.box.borderColors.top
  of "border-right-color", "border-inline-end-color":
    style.box.borderColors.right = parent.box.borderColors.right
  of "border-bottom-color", "border-block-end-color":
    style.box.borderColors.bottom = parent.box.borderColors.bottom
  of "border-left-color", "border-inline-start-color":
    style.box.borderColors.left = parent.box.borderColors.left
  of "border-inline-color":
    style.box.borderColors.left = parent.box.borderColors.left
    style.box.borderColors.right = parent.box.borderColors.right
  of "border-block-color":
    style.box.borderColors.top = parent.box.borderColors.top
    style.box.borderColors.bottom = parent.box.borderColors.bottom
  else:
    discard

proc applyBorderColor(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or declaration.operation.value.get.kind != svColor:
      diagnostics.addError(declaration.property, "border-color requires a color value")
      return
    style.setBorderColor(declaration.property, some(declaration.operation.value.get.color))
  of mmInitial, mmUnset:
    style.setBorderColor(declaration.property, some(rgba(0, 0, 0, 1)))
  of mmInherit:
    if env.parent.isSome:
      style.inheritBorderColor(declaration.property, env.parent.get)
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc setBorderVisibility(style: var ComputedStyle; property: string; visible: bool) =
  case property
  of "border-style":
    style.box.borderVisible = visible
    style.box.borderSideVisible = edgeVisibility(visible)
  of "border-top-style", "border-block-start-style":
    style.box.borderSideVisible.top = visible
  of "border-right-style", "border-inline-end-style":
    style.box.borderSideVisible.right = visible
  of "border-bottom-style", "border-block-end-style":
    style.box.borderSideVisible.bottom = visible
  of "border-left-style", "border-inline-start-style":
    style.box.borderSideVisible.left = visible
  of "border-inline-style":
    style.box.borderSideVisible.left = visible
    style.box.borderSideVisible.right = visible
  of "border-block-style":
    style.box.borderSideVisible.top = visible
    style.box.borderSideVisible.bottom = visible
  else:
    discard

proc inheritBorderVisibility(style: var ComputedStyle; property: string; parent: ComputedStyle) =
  case property
  of "border-style":
    style.box.borderVisible = parent.box.borderVisible
    style.box.borderSideVisible = parent.box.borderSideVisible
  of "border-top-style", "border-block-start-style":
    style.box.borderSideVisible.top = parent.box.borderSideVisible.top
  of "border-right-style", "border-inline-end-style":
    style.box.borderSideVisible.right = parent.box.borderSideVisible.right
  of "border-bottom-style", "border-block-end-style":
    style.box.borderSideVisible.bottom = parent.box.borderSideVisible.bottom
  of "border-left-style", "border-inline-start-style":
    style.box.borderSideVisible.left = parent.box.borderSideVisible.left
  of "border-inline-style":
    style.box.borderSideVisible.left = parent.box.borderSideVisible.left
    style.box.borderSideVisible.right = parent.box.borderSideVisible.right
  of "border-block-style":
    style.box.borderSideVisible.top = parent.box.borderSideVisible.top
    style.box.borderSideVisible.bottom = parent.box.borderSideVisible.bottom
  else:
    discard

proc applyBorderStyle(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
      diagnostics.addError(declaration.property, declaration.property & " requires a keyword value")
      return
    case declaration.operation.value.get.keyword
    of "solid":
      style.setBorderVisibility(declaration.property, true)
    of "none", "hidden":
      style.setBorderVisibility(declaration.property, false)
    else:
      diagnostics.addError(declaration.property, "only solid, none, and hidden border styles are supported initially")
  of mmInitial, mmUnset:
    style.setBorderVisibility(declaration.property, true)
  of mmInherit:
    if env.parent.isSome:
      style.inheritBorderVisibility(declaration.property, env.parent.get)
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc widthPropertyForShorthand(property: string): string =
  case property
  of "border": "border-width"
  of "border-top": "border-top-width"
  of "border-right": "border-right-width"
  of "border-bottom": "border-bottom-width"
  of "border-left": "border-left-width"
  of "border-inline": "border-inline-width"
  of "border-inline-start": "border-inline-start-width"
  of "border-inline-end": "border-inline-end-width"
  of "border-block": "border-block-width"
  of "border-block-start": "border-block-start-width"
  of "border-block-end": "border-block-end-width"
  else: property

proc colorPropertyForShorthand(property: string): string =
  case property
  of "border": "border-color"
  of "border-top": "border-top-color"
  of "border-right": "border-right-color"
  of "border-bottom": "border-bottom-color"
  of "border-left": "border-left-color"
  of "border-inline": "border-inline-color"
  of "border-inline-start": "border-inline-start-color"
  of "border-inline-end": "border-inline-end-color"
  of "border-block": "border-block-color"
  of "border-block-start": "border-block-start-color"
  of "border-block-end": "border-block-end-color"
  else: property

proc stylePropertyForShorthand(property: string): string =
  case property
  of "border": "border-style"
  of "border-top": "border-top-style"
  of "border-right": "border-right-style"
  of "border-bottom": "border-bottom-style"
  of "border-left": "border-left-style"
  of "border-inline": "border-inline-style"
  of "border-inline-start": "border-inline-start-style"
  of "border-inline-end": "border-inline-end-style"
  of "border-block": "border-block-style"
  of "border-block-start": "border-block-start-style"
  of "border-block-end": "border-block-end-style"
  else: property

proc applyBorderStyleKeyword(
    style: var ComputedStyle;
    property, value: string;
    diagnostics: var Diagnostics
) =
  case value
  of "solid":
    style.setBorderVisibility(stylePropertyForShorthand(property), true)
  of "none", "hidden":
    style.setBorderWidth(widthPropertyForShorthand(property), 0)
    style.setBorderVisibility(stylePropertyForShorthand(property), false)
  else:
    diagnostics.addError(property, "unsupported border shorthand keyword")

proc applyStructuredBorder(
    style: var ComputedStyle;
    property: string;
    value: StyleValue;
    diagnostics: var Diagnostics
) =
  let widthProperty = widthPropertyForShorthand(property)
  let colorProperty = colorPropertyForShorthand(property)

  if value.borderWidth.isSome:
    let width = StyleValue(kind: svLength, length: value.borderWidth.get)
    let resolved = resolvePx(width, property, diagnostics)
    if resolved.isSome:
      style.setBorderWidth(widthProperty, resolved.get)

  if value.borderStyle.isSome:
    style.applyBorderStyleKeyword(property, value.borderStyle.get, diagnostics)

  if value.borderColor.isSome:
    style.setBorderColor(colorProperty, some(value.borderColor.get))

proc applyBorderShorthand(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  let widthProperty = widthPropertyForShorthand(declaration.property)
  let colorProperty = colorPropertyForShorthand(declaration.property)
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, declaration.property & " requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svLength:
      let resolved = resolvePx(value, declaration.property, diagnostics)
      if resolved.isSome:
        style.setBorderWidth(widthProperty, resolved.get)
    of svColor:
      style.setBorderColor(colorProperty, some(value.color))
    of svColorPair:
      diagnostics.addError(declaration.property, declaration.property & " does not support color pair values")
    of svKeyword:
      style.applyBorderStyleKeyword(declaration.property, value.keyword, diagnostics)
    of svNumber:
      diagnostics.addError(declaration.property, declaration.property & " does not support number values")
    of svBorder:
      style.applyStructuredBorder(declaration.property, value, diagnostics)
    of svShadow:
      diagnostics.addError(declaration.property, declaration.property & " does not support shadow values")
    of svLinearGradient:
      diagnostics.addError(declaration.property, declaration.property & " does not support gradient values")
    of svTransform, svTransformOperation:
      diagnostics.addError(declaration.property, declaration.property & " does not support transform values")
    of svFunction:
      diagnostics.addError(declaration.property, declaration.property & " received an unevaluated function value")
  of mmInitial, mmUnset:
    style.setBorderWidth(widthProperty, 0)
    style.setBorderColor(colorProperty, some(rgba(0, 0, 0, 1)))
  of mmInherit:
    if env.parent.isSome:
      style.inheritBorderWidth(widthProperty, env.parent.get)
      style.inheritBorderColor(colorProperty, env.parent.get)
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " relative merge is not implemented yet")

proc setBorderMetadata(style: var ComputedStyle; property: string; value: Option[string]) =
  case property
  of "border-image":
    style.box.borderImage = value
  of "border-image-outset":
    style.box.borderImageOutset = value
  of "border-image-repeat":
    style.box.borderImageRepeat = value
  of "border-image-slice":
    style.box.borderImageSlice = value
  of "border-image-source":
    style.box.borderImageSource = value
  of "border-image-width":
    style.box.borderImageWidth = value
  of "border-collapse":
    style.box.borderCollapse = value
  of "border-shape":
    style.box.borderShape = value
  of "border-spacing":
    style.box.borderSpacing = value
  of "corner-shape":
    style.box.cornerShape = value
  of "corner-top-shape":
    style.box.cornerTopShape = value
  of "corner-right-shape":
    style.box.cornerRightShape = value
  of "corner-bottom-shape":
    style.box.cornerBottomShape = value
  of "corner-left-shape":
    style.box.cornerLeftShape = value
  of "corner-top-left-shape":
    style.box.cornerTopLeftShape = value
  of "corner-top-right-shape":
    style.box.cornerTopRightShape = value
  of "corner-bottom-right-shape":
    style.box.cornerBottomRightShape = value
  of "corner-bottom-left-shape":
    style.box.cornerBottomLeftShape = value
  of "corner-block-start-shape":
    style.box.cornerBlockStartShape = value
  of "corner-block-end-shape":
    style.box.cornerBlockEndShape = value
  of "corner-inline-start-shape":
    style.box.cornerInlineStartShape = value
  of "corner-inline-end-shape":
    style.box.cornerInlineEndShape = value
  of "corner-start-start-shape":
    style.box.cornerStartStartShape = value
  of "corner-start-end-shape":
    style.box.cornerStartEndShape = value
  of "corner-end-start-shape":
    style.box.cornerEndStartShape = value
  of "corner-end-end-shape":
    style.box.cornerEndEndShape = value
  else:
    discard

proc borderMetadata(style: ComputedStyle; property: string): Option[string] =
  case property
  of "border-image":
    style.box.borderImage
  of "border-image-outset":
    style.box.borderImageOutset
  of "border-image-repeat":
    style.box.borderImageRepeat
  of "border-image-slice":
    style.box.borderImageSlice
  of "border-image-source":
    style.box.borderImageSource
  of "border-image-width":
    style.box.borderImageWidth
  of "border-collapse":
    style.box.borderCollapse
  of "border-shape":
    style.box.borderShape
  of "border-spacing":
    style.box.borderSpacing
  of "corner-shape":
    style.box.cornerShape
  of "corner-top-shape":
    style.box.cornerTopShape
  of "corner-right-shape":
    style.box.cornerRightShape
  of "corner-bottom-shape":
    style.box.cornerBottomShape
  of "corner-left-shape":
    style.box.cornerLeftShape
  of "corner-top-left-shape":
    style.box.cornerTopLeftShape
  of "corner-top-right-shape":
    style.box.cornerTopRightShape
  of "corner-bottom-right-shape":
    style.box.cornerBottomRightShape
  of "corner-bottom-left-shape":
    style.box.cornerBottomLeftShape
  of "corner-block-start-shape":
    style.box.cornerBlockStartShape
  of "corner-block-end-shape":
    style.box.cornerBlockEndShape
  of "corner-inline-start-shape":
    style.box.cornerInlineStartShape
  of "corner-inline-end-shape":
    style.box.cornerInlineEndShape
  of "corner-start-start-shape":
    style.box.cornerStartStartShape
  of "corner-start-end-shape":
    style.box.cornerStartEndShape
  of "corner-end-start-shape":
    style.box.cornerEndStartShape
  of "corner-end-end-shape":
    style.box.cornerEndEndShape
  else:
    none(string)

proc applyBorderMetadata(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
      diagnostics.addError(declaration.property, declaration.property & " requires a keyword metadata value")
      return
    let value = declaration.operation.value.get.keyword
    if value == "none" or value == "normal" or value == "initial":
      style.setBorderMetadata(declaration.property, none(string))
    else:
      style.setBorderMetadata(declaration.property, some(value))
  of mmInitial, mmUnset:
    style.setBorderMetadata(declaration.property, none(string))
  of mmInherit:
    if env.parent.isSome:
      style.setBorderMetadata(declaration.property, env.parent.get.borderMetadata(declaration.property))
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

let borderProperty* = PropertyImpl(name: "border", apply: applyBorderShorthand)
let borderTopProperty* = PropertyImpl(name: "border-top", apply: applyBorderShorthand)
let borderRightProperty* = PropertyImpl(name: "border-right", apply: applyBorderShorthand)
let borderBottomProperty* = PropertyImpl(name: "border-bottom", apply: applyBorderShorthand)
let borderLeftProperty* = PropertyImpl(name: "border-left", apply: applyBorderShorthand)
let borderInlineProperty* = PropertyImpl(name: "border-inline", apply: applyBorderShorthand)
let borderInlineStartProperty* = PropertyImpl(name: "border-inline-start", apply: applyBorderShorthand)
let borderInlineEndProperty* = PropertyImpl(name: "border-inline-end", apply: applyBorderShorthand)
let borderBlockProperty* = PropertyImpl(name: "border-block", apply: applyBorderShorthand)
let borderBlockStartProperty* = PropertyImpl(name: "border-block-start", apply: applyBorderShorthand)
let borderBlockEndProperty* = PropertyImpl(name: "border-block-end", apply: applyBorderShorthand)
let borderWidthProperty* = PropertyImpl(name: "border-width", apply: applyBorderWidth)
let borderTopWidthProperty* = PropertyImpl(name: "border-top-width", apply: applyBorderWidth)
let borderRightWidthProperty* = PropertyImpl(name: "border-right-width", apply: applyBorderWidth)
let borderBottomWidthProperty* = PropertyImpl(name: "border-bottom-width", apply: applyBorderWidth)
let borderLeftWidthProperty* = PropertyImpl(name: "border-left-width", apply: applyBorderWidth)
let borderInlineWidthProperty* = PropertyImpl(name: "border-inline-width", apply: applyBorderWidth)
let borderInlineStartWidthProperty* = PropertyImpl(name: "border-inline-start-width", apply: applyBorderWidth)
let borderInlineEndWidthProperty* = PropertyImpl(name: "border-inline-end-width", apply: applyBorderWidth)
let borderBlockWidthProperty* = PropertyImpl(name: "border-block-width", apply: applyBorderWidth)
let borderBlockStartWidthProperty* = PropertyImpl(name: "border-block-start-width", apply: applyBorderWidth)
let borderBlockEndWidthProperty* = PropertyImpl(name: "border-block-end-width", apply: applyBorderWidth)
let borderRadiusProperty* = PropertyImpl(name: "border-radius", apply: applyBorderRadius)
let borderTopLeftRadiusProperty* = PropertyImpl(name: "border-top-left-radius", apply: applyBorderRadius)
let borderTopRightRadiusProperty* = PropertyImpl(name: "border-top-right-radius", apply: applyBorderRadius)
let borderBottomRightRadiusProperty* = PropertyImpl(name: "border-bottom-right-radius", apply: applyBorderRadius)
let borderBottomLeftRadiusProperty* = PropertyImpl(name: "border-bottom-left-radius", apply: applyBorderRadius)
let borderStartStartRadiusProperty* = PropertyImpl(name: "border-start-start-radius", apply: applyBorderRadius)
let borderStartEndRadiusProperty* = PropertyImpl(name: "border-start-end-radius", apply: applyBorderRadius)
let borderEndStartRadiusProperty* = PropertyImpl(name: "border-end-start-radius", apply: applyBorderRadius)
let borderEndEndRadiusProperty* = PropertyImpl(name: "border-end-end-radius", apply: applyBorderRadius)
let borderColorProperty* = PropertyImpl(name: "border-color", apply: applyBorderColor)
let borderTopColorProperty* = PropertyImpl(name: "border-top-color", apply: applyBorderColor)
let borderRightColorProperty* = PropertyImpl(name: "border-right-color", apply: applyBorderColor)
let borderBottomColorProperty* = PropertyImpl(name: "border-bottom-color", apply: applyBorderColor)
let borderLeftColorProperty* = PropertyImpl(name: "border-left-color", apply: applyBorderColor)
let borderInlineColorProperty* = PropertyImpl(name: "border-inline-color", apply: applyBorderColor)
let borderInlineStartColorProperty* = PropertyImpl(name: "border-inline-start-color", apply: applyBorderColor)
let borderInlineEndColorProperty* = PropertyImpl(name: "border-inline-end-color", apply: applyBorderColor)
let borderBlockColorProperty* = PropertyImpl(name: "border-block-color", apply: applyBorderColor)
let borderBlockStartColorProperty* = PropertyImpl(name: "border-block-start-color", apply: applyBorderColor)
let borderBlockEndColorProperty* = PropertyImpl(name: "border-block-end-color", apply: applyBorderColor)
let borderStyleProperty* = PropertyImpl(name: "border-style", apply: applyBorderStyle)
let borderTopStyleProperty* = PropertyImpl(name: "border-top-style", apply: applyBorderStyle)
let borderRightStyleProperty* = PropertyImpl(name: "border-right-style", apply: applyBorderStyle)
let borderBottomStyleProperty* = PropertyImpl(name: "border-bottom-style", apply: applyBorderStyle)
let borderLeftStyleProperty* = PropertyImpl(name: "border-left-style", apply: applyBorderStyle)
let borderInlineStyleProperty* = PropertyImpl(name: "border-inline-style", apply: applyBorderStyle)
let borderInlineStartStyleProperty* = PropertyImpl(name: "border-inline-start-style", apply: applyBorderStyle)
let borderInlineEndStyleProperty* = PropertyImpl(name: "border-inline-end-style", apply: applyBorderStyle)
let borderBlockStyleProperty* = PropertyImpl(name: "border-block-style", apply: applyBorderStyle)
let borderBlockStartStyleProperty* = PropertyImpl(name: "border-block-start-style", apply: applyBorderStyle)
let borderBlockEndStyleProperty* = PropertyImpl(name: "border-block-end-style", apply: applyBorderStyle)
let borderImageProperty* = PropertyImpl(name: "border-image", apply: applyBorderMetadata)
let borderImageOutsetProperty* = PropertyImpl(name: "border-image-outset", apply: applyBorderMetadata)
let borderImageRepeatProperty* = PropertyImpl(name: "border-image-repeat", apply: applyBorderMetadata)
let borderImageSliceProperty* = PropertyImpl(name: "border-image-slice", apply: applyBorderMetadata)
let borderImageSourceProperty* = PropertyImpl(name: "border-image-source", apply: applyBorderMetadata)
let borderImageWidthProperty* = PropertyImpl(name: "border-image-width", apply: applyBorderMetadata)
let borderCollapseProperty* = PropertyImpl(name: "border-collapse", apply: applyBorderMetadata)
let borderShapeProperty* = PropertyImpl(name: "border-shape", apply: applyBorderMetadata)
let borderSpacingProperty* = PropertyImpl(name: "border-spacing", apply: applyBorderMetadata)
let cornerShapeProperty* = PropertyImpl(name: "corner-shape", apply: applyBorderMetadata)
let cornerTopShapeProperty* = PropertyImpl(name: "corner-top-shape", apply: applyBorderMetadata)
let cornerRightShapeProperty* = PropertyImpl(name: "corner-right-shape", apply: applyBorderMetadata)
let cornerBottomShapeProperty* = PropertyImpl(name: "corner-bottom-shape", apply: applyBorderMetadata)
let cornerLeftShapeProperty* = PropertyImpl(name: "corner-left-shape", apply: applyBorderMetadata)
let cornerTopLeftShapeProperty* = PropertyImpl(name: "corner-top-left-shape", apply: applyBorderMetadata)
let cornerTopRightShapeProperty* = PropertyImpl(name: "corner-top-right-shape", apply: applyBorderMetadata)
let cornerBottomRightShapeProperty* = PropertyImpl(name: "corner-bottom-right-shape", apply: applyBorderMetadata)
let cornerBottomLeftShapeProperty* = PropertyImpl(name: "corner-bottom-left-shape", apply: applyBorderMetadata)
let cornerBlockStartShapeProperty* = PropertyImpl(name: "corner-block-start-shape", apply: applyBorderMetadata)
let cornerBlockEndShapeProperty* = PropertyImpl(name: "corner-block-end-shape", apply: applyBorderMetadata)
let cornerInlineStartShapeProperty* = PropertyImpl(name: "corner-inline-start-shape", apply: applyBorderMetadata)
let cornerInlineEndShapeProperty* = PropertyImpl(name: "corner-inline-end-shape", apply: applyBorderMetadata)
let cornerStartStartShapeProperty* = PropertyImpl(name: "corner-start-start-shape", apply: applyBorderMetadata)
let cornerStartEndShapeProperty* = PropertyImpl(name: "corner-start-end-shape", apply: applyBorderMetadata)
let cornerEndStartShapeProperty* = PropertyImpl(name: "corner-end-start-shape", apply: applyBorderMetadata)
let cornerEndEndShapeProperty* = PropertyImpl(name: "corner-end-end-shape", apply: applyBorderMetadata)
