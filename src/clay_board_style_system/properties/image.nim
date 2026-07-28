import std/options
import ../core/[computed_style, declaration, diagnostics, property, style_value]

proc applyObjectFit(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
      diagnostics.addError(declaration.property, "object-fit requires a keyword value")
      return
    case declaration.operation.value.get.keyword
    of "fill":
      style.image.objectFit = some(ofFill)
    of "contain":
      style.image.objectFit = some(ofContain)
    of "cover":
      style.image.objectFit = some(ofCover)
    of "none":
      style.image.objectFit = some(ofNone)
    of "scale-down":
      style.image.objectFit = some(ofScaleDown)
    else:
      diagnostics.addError(declaration.property, "unsupported object-fit keyword")
  of mmInitial, mmUnset:
    style.image.objectFit = some(ofFill)
  of mmInherit:
    if env.parent.isSome:
      style.image.objectFit = env.parent.get.image.objectFit
    else:
      diagnostics.addError(declaration.property, "cannot inherit object-fit without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "object-fit does not support relative merge")

proc positionFromKeyword(keyword: string): Option[ObjectPosition] =
  case keyword
  of "center":
    some(ObjectPosition(x: 50, y: 50))
  of "left":
    some(ObjectPosition(x: 0, y: 50))
  of "right":
    some(ObjectPosition(x: 100, y: 50))
  of "top":
    some(ObjectPosition(x: 50, y: 0))
  of "bottom":
    some(ObjectPosition(x: 50, y: 100))
  else:
    none(ObjectPosition)

proc applyObjectPosition(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone:
      diagnostics.addError(declaration.property, "object-position requires a value")
      return
    let value = declaration.operation.value.get
    case value.kind
    of svKeyword:
      let position = positionFromKeyword(value.keyword)
      if position.isSome:
        style.image.objectPosition = position
      else:
        diagnostics.addError(declaration.property, "unsupported object-position keyword")
    of svLength:
      if value.length.kind != ukPercent:
        diagnostics.addError(declaration.property, "only percent is supported for initial object-position implementation")
        return
      style.image.objectPosition = some(ObjectPosition(x: value.length.value, y: value.length.value))
    else:
      diagnostics.addError(declaration.property, "object-position requires a keyword or percent value")
  of mmInitial, mmUnset:
    style.image.objectPosition = some(ObjectPosition(x: 50, y: 50))
  of mmInherit:
    if env.parent.isSome:
      style.image.objectPosition = env.parent.get.image.objectPosition
    else:
      diagnostics.addError(declaration.property, "cannot inherit object-position without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, "object-position does not support relative merge")

proc applyImageRendering(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  if declaration.operation.mode notin {mmOverwrite, mmInitial, mmUnset}:
    diagnostics.addError(declaration.property, "image-rendering only supports overwrite, initial, and unset")
    return
  if declaration.operation.mode in {mmInitial, mmUnset}:
    style.image.imageRendering = irAuto
    return
  if declaration.operation.value.isNone or declaration.operation.value.get.kind != svKeyword:
    diagnostics.addError(declaration.property, "image-rendering requires a keyword value")
    return
  case declaration.operation.value.get.keyword
  of "auto":
    style.image.imageRendering = irAuto
  of "smooth":
    style.image.imageRendering = irSmooth
  of "crisp-edges":
    style.image.imageRendering = irCrispEdges
  of "pixelated":
    style.image.imageRendering = irPixelated
  else:
    diagnostics.addError(declaration.property, "unsupported image-rendering keyword")

let objectFitProperty* = PropertyImpl(name: "object-fit", apply: applyObjectFit)
let objectPositionProperty* = PropertyImpl(name: "object-position", apply: applyObjectPosition)
let imageRenderingProperty* = PropertyImpl(name: "image-rendering", apply: applyImageRendering)

proc setImageMetadata(style: var ComputedStyle; property: string; value: Option[string]) =
  case property
  of "image-orientation":
    style.image.imageOrientation = value
  of "image-resolution":
    style.image.imageResolution = value
  of "object-view-box":
    style.image.objectViewBox = value
  else:
    discard

proc imageMetadata(style: ComputedStyle; property: string): Option[string] =
  case property
  of "image-orientation":
    style.image.imageOrientation
  of "image-resolution":
    style.image.imageResolution
  of "object-view-box":
    style.image.objectViewBox
  else:
    none(string)

proc applyImageMetadata(
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
    if value == "initial" or value == "auto":
      style.setImageMetadata(declaration.property, none(string))
    else:
      style.setImageMetadata(declaration.property, some(value))
  of mmInitial, mmUnset:
    style.setImageMetadata(declaration.property, none(string))
  of mmInherit:
    if env.parent.isSome:
      style.setImageMetadata(declaration.property, env.parent.get.imageMetadata(declaration.property))
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

let imageOrientationProperty* = PropertyImpl(name: "image-orientation", apply: applyImageMetadata)
let imageResolutionProperty* = PropertyImpl(name: "image-resolution", apply: applyImageMetadata)
let objectViewBoxProperty* = PropertyImpl(name: "object-view-box", apply: applyImageMetadata)
