import std/options
import ../core/[color, computed_style, declaration, diagnostics, property, style_value]

proc setVectorKeyword(style: var ComputedStyle; property: string; value: Option[string]) =
  style.ensureVector()
  case property
  of "color-interpolation-filters":
    style.vector.colorInterpolationFilters = value
  of "fill":
    style.vector.fill = value
  of "fill-rule":
    style.vector.fillRule = value
  of "marker":
    style.vector.marker = value
  of "paint-order":
    style.vector.paintOrder = value
  of "stroke":
    style.vector.stroke = value
  of "stroke-dasharray":
    style.vector.strokeDasharray = value
  of "stroke-linecap":
    style.vector.strokeLinecap = value
  of "stroke-linejoin":
    style.vector.strokeLinejoin = value
  of "vector-effect":
    style.vector.vectorEffect = value
  of "d":
    style.vector.d = value
  else:
    discard

proc vectorKeyword(style: ComputedStyle; property: string): Option[string] =
  if style.vector.isNil:
    return none(string)
  case property
  of "color-interpolation-filters":
    style.vector.colorInterpolationFilters
  of "fill":
    style.vector.fill
  of "fill-rule":
    style.vector.fillRule
  of "marker":
    style.vector.marker
  of "paint-order":
    style.vector.paintOrder
  of "stroke":
    style.vector.stroke
  of "stroke-dasharray":
    style.vector.strokeDasharray
  of "stroke-linecap":
    style.vector.strokeLinecap
  of "stroke-linejoin":
    style.vector.strokeLinejoin
  of "vector-effect":
    style.vector.vectorEffect
  of "d":
    style.vector.d
  else:
    none(string)

proc applyVectorKeyword(
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
    if value == "none":
      style.setVectorKeyword(declaration.property, none(string))
    else:
      style.setVectorKeyword(declaration.property, some(value))
  of mmInitial, mmUnset:
    style.setVectorKeyword(declaration.property, none(string))
  of mmInherit:
    if env.parent.isSome:
      style.setVectorKeyword(declaration.property, env.parent.get.vectorKeyword(declaration.property))
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc setVectorColor(style: var ComputedStyle; property: string; value: Option[Color]) =
  style.ensureVector()
  case property
  of "fill":
    style.vector.fillColor = value
    style.vector.fill = none(string)
  of "flood-color":
    style.vector.floodColor = value
  of "lighting-color":
    style.vector.lightingColor = value
  of "stop-color":
    style.vector.stopColor = value
  of "stroke", "stroke-color":
    style.vector.strokeColor = value
    if property == "stroke":
      style.vector.stroke = none(string)
  else:
    discard

proc vectorColor(style: ComputedStyle; property: string): Option[Color] =
  if style.vector.isNil:
    return none(Color)
  case property
  of "fill":
    style.vector.fillColor
  of "flood-color":
    style.vector.floodColor
  of "lighting-color":
    style.vector.lightingColor
  of "stop-color":
    style.vector.stopColor
  of "stroke", "stroke-color":
    style.vector.strokeColor
  else:
    none(Color)

proc applyVectorColor(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, declaration.property & " requires a color or keyword value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svColor:
      style.setVectorColor(declaration.property, some(value.color))
    of svKeyword:
      if declaration.property in ["fill", "stroke"]:
        if value.keyword == "none":
          style.setVectorColor(declaration.property, none(Color))
          style.setVectorKeyword(declaration.property, none(string))
        else:
          style.setVectorKeyword(declaration.property, some(value.keyword))
      else:
        diagnostics.addError(declaration.property, declaration.property & " requires a color value")
    else:
      diagnostics.addError(declaration.property, declaration.property & " requires a color value")
  of mmInitial, mmUnset:
    style.setVectorColor(declaration.property, none(Color))
  of mmInherit:
    if env.parent.isSome:
      style.setVectorColor(declaration.property, env.parent.get.vectorColor(declaration.property))
      if declaration.property in ["fill", "stroke"]:
        style.setVectorKeyword(declaration.property, env.parent.get.vectorKeyword(declaration.property))
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

proc setVectorNumber(style: var ComputedStyle; property: string; value: Option[float32]) =
  style.ensureVector()
  case property
  of "fill-opacity":
    style.vector.fillOpacity = value
  of "flood-opacity":
    style.vector.floodOpacity = value
  of "stop-opacity":
    style.vector.stopOpacity = value
  of "stroke-dashoffset":
    style.vector.strokeDashoffset = value
  of "stroke-miterlimit":
    style.vector.strokeMiterlimit = value
  of "stroke-opacity":
    style.vector.strokeOpacity = value
  of "stroke-width":
    style.vector.strokeWidth = value
  of "x":
    style.vector.x = value
  of "y":
    style.vector.y = value
  of "cx":
    style.vector.cx = value
  of "cy":
    style.vector.cy = value
  of "r":
    style.vector.r = value
  of "rx":
    style.vector.rx = value
  of "ry":
    style.vector.ry = value
  else:
    discard

proc vectorNumber(style: ComputedStyle; property: string): Option[float32] =
  if style.vector.isNil:
    return none(float32)
  case property
  of "fill-opacity":
    style.vector.fillOpacity
  of "flood-opacity":
    style.vector.floodOpacity
  of "stop-opacity":
    style.vector.stopOpacity
  of "stroke-dashoffset":
    style.vector.strokeDashoffset
  of "stroke-miterlimit":
    style.vector.strokeMiterlimit
  of "stroke-opacity":
    style.vector.strokeOpacity
  of "stroke-width":
    style.vector.strokeWidth
  of "x":
    style.vector.x
  of "y":
    style.vector.y
  of "cx":
    style.vector.cx
  of "cy":
    style.vector.cy
  of "r":
    style.vector.r
  of "rx":
    style.vector.rx
  of "ry":
    style.vector.ry
  else:
    none(float32)

proc applyVectorNumber(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, declaration.property & " requires a number or px length value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svNumber:
      style.setVectorNumber(declaration.property, some(value.number))
    of svLength:
      if value.length.kind == ukPx:
        style.setVectorNumber(declaration.property, some(value.length.value))
      else:
        diagnostics.addError(declaration.property, declaration.property & " only supports px lengths")
    else:
      diagnostics.addError(declaration.property, declaration.property & " requires a number or px length value")
  of mmInitial, mmUnset:
    style.setVectorNumber(declaration.property, none(float32))
  of mmInherit:
    if env.parent.isSome:
      style.setVectorNumber(declaration.property, env.parent.get.vectorNumber(declaration.property))
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

let colorInterpolationFiltersProperty* = PropertyImpl(name: "color-interpolation-filters", apply: applyVectorKeyword)
let fillProperty* = PropertyImpl(name: "fill", apply: applyVectorColor)
let fillOpacityProperty* = PropertyImpl(name: "fill-opacity", apply: applyVectorNumber)
let fillRuleProperty* = PropertyImpl(name: "fill-rule", apply: applyVectorKeyword)
let floodColorProperty* = PropertyImpl(name: "flood-color", apply: applyVectorColor)
let floodOpacityProperty* = PropertyImpl(name: "flood-opacity", apply: applyVectorNumber)
let lightingColorProperty* = PropertyImpl(name: "lighting-color", apply: applyVectorColor)
let markerProperty* = PropertyImpl(name: "marker", apply: applyVectorKeyword)
let paintOrderProperty* = PropertyImpl(name: "paint-order", apply: applyVectorKeyword)
let stopColorProperty* = PropertyImpl(name: "stop-color", apply: applyVectorColor)
let stopOpacityProperty* = PropertyImpl(name: "stop-opacity", apply: applyVectorNumber)
let strokeProperty* = PropertyImpl(name: "stroke", apply: applyVectorColor)
let strokeColorProperty* = PropertyImpl(name: "stroke-color", apply: applyVectorColor)
let strokeDasharrayProperty* = PropertyImpl(name: "stroke-dasharray", apply: applyVectorKeyword)
let strokeDashoffsetProperty* = PropertyImpl(name: "stroke-dashoffset", apply: applyVectorNumber)
let strokeLinecapProperty* = PropertyImpl(name: "stroke-linecap", apply: applyVectorKeyword)
let strokeLinejoinProperty* = PropertyImpl(name: "stroke-linejoin", apply: applyVectorKeyword)
let strokeMiterlimitProperty* = PropertyImpl(name: "stroke-miterlimit", apply: applyVectorNumber)
let strokeOpacityProperty* = PropertyImpl(name: "stroke-opacity", apply: applyVectorNumber)
let strokeWidthProperty* = PropertyImpl(name: "stroke-width", apply: applyVectorNumber)
let vectorEffectProperty* = PropertyImpl(name: "vector-effect", apply: applyVectorKeyword)
let xProperty* = PropertyImpl(name: "x", apply: applyVectorNumber)
let yProperty* = PropertyImpl(name: "y", apply: applyVectorNumber)
let cxProperty* = PropertyImpl(name: "cx", apply: applyVectorNumber)
let cyProperty* = PropertyImpl(name: "cy", apply: applyVectorNumber)
let dProperty* = PropertyImpl(name: "d", apply: applyVectorKeyword)
let rProperty* = PropertyImpl(name: "r", apply: applyVectorNumber)
let rxProperty* = PropertyImpl(name: "rx", apply: applyVectorNumber)
let ryProperty* = PropertyImpl(name: "ry", apply: applyVectorNumber)
