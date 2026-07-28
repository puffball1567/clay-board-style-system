import std/options
import ../core/[computed_style, declaration, diagnostics, property, style_value]

proc setMaskMetadata(style: var ComputedStyle; property: string; value: Option[string]) =
  style.ensureMask()
  case property
  of "mask":
    style.mask.mask = value
  of "mask-border":
    style.mask.maskBorder = value
  of "mask-border-mode":
    style.mask.maskBorderMode = value
  of "mask-border-outset":
    style.mask.maskBorderOutset = value
  of "mask-border-repeat":
    style.mask.maskBorderRepeat = value
  of "mask-border-slice":
    style.mask.maskBorderSlice = value
  of "mask-border-source":
    style.mask.maskBorderSource = value
  of "mask-border-width":
    style.mask.maskBorderWidth = value
  of "mask-clip":
    style.mask.maskClip = value
  of "mask-composite":
    style.mask.maskComposite = value
  of "mask-image":
    style.mask.maskImage = value
  of "mask-mode":
    style.mask.maskMode = value
  of "mask-origin":
    style.mask.maskOrigin = value
  of "mask-position":
    style.mask.maskPosition = value
  of "mask-repeat":
    style.mask.maskRepeat = value
  of "mask-size":
    style.mask.maskSize = value
  of "mask-type":
    style.mask.maskType = value
  else:
    discard

proc maskMetadata(style: ComputedStyle; property: string): Option[string] =
  if style.mask.isNil:
    return none(string)
  case property
  of "mask":
    style.mask.mask
  of "mask-border":
    style.mask.maskBorder
  of "mask-border-mode":
    style.mask.maskBorderMode
  of "mask-border-outset":
    style.mask.maskBorderOutset
  of "mask-border-repeat":
    style.mask.maskBorderRepeat
  of "mask-border-slice":
    style.mask.maskBorderSlice
  of "mask-border-source":
    style.mask.maskBorderSource
  of "mask-border-width":
    style.mask.maskBorderWidth
  of "mask-clip":
    style.mask.maskClip
  of "mask-composite":
    style.mask.maskComposite
  of "mask-image":
    style.mask.maskImage
  of "mask-mode":
    style.mask.maskMode
  of "mask-origin":
    style.mask.maskOrigin
  of "mask-position":
    style.mask.maskPosition
  of "mask-repeat":
    style.mask.maskRepeat
  of "mask-size":
    style.mask.maskSize
  of "mask-type":
    style.mask.maskType
  else:
    none(string)

proc applyMaskMetadata(
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
      style.setMaskMetadata(declaration.property, none(string))
    else:
      style.setMaskMetadata(declaration.property, some(value))
  of mmInitial, mmUnset:
    style.setMaskMetadata(declaration.property, none(string))
  of mmInherit:
    if env.parent.isSome:
      style.setMaskMetadata(declaration.property, env.parent.get.maskMetadata(declaration.property))
    else:
      diagnostics.addError(declaration.property, "cannot inherit " & declaration.property & " without parent")
  of mmRelative:
    diagnostics.addError(declaration.property, declaration.property & " does not support relative merge")

let maskProperty* = PropertyImpl(name: "mask", apply: applyMaskMetadata)
let maskBorderProperty* = PropertyImpl(name: "mask-border", apply: applyMaskMetadata)
let maskBorderModeProperty* = PropertyImpl(name: "mask-border-mode", apply: applyMaskMetadata)
let maskBorderOutsetProperty* = PropertyImpl(name: "mask-border-outset", apply: applyMaskMetadata)
let maskBorderRepeatProperty* = PropertyImpl(name: "mask-border-repeat", apply: applyMaskMetadata)
let maskBorderSliceProperty* = PropertyImpl(name: "mask-border-slice", apply: applyMaskMetadata)
let maskBorderSourceProperty* = PropertyImpl(name: "mask-border-source", apply: applyMaskMetadata)
let maskBorderWidthProperty* = PropertyImpl(name: "mask-border-width", apply: applyMaskMetadata)
let maskClipProperty* = PropertyImpl(name: "mask-clip", apply: applyMaskMetadata)
let maskCompositeProperty* = PropertyImpl(name: "mask-composite", apply: applyMaskMetadata)
let maskImageProperty* = PropertyImpl(name: "mask-image", apply: applyMaskMetadata)
let maskModeProperty* = PropertyImpl(name: "mask-mode", apply: applyMaskMetadata)
let maskOriginProperty* = PropertyImpl(name: "mask-origin", apply: applyMaskMetadata)
let maskPositionProperty* = PropertyImpl(name: "mask-position", apply: applyMaskMetadata)
let maskRepeatProperty* = PropertyImpl(name: "mask-repeat", apply: applyMaskMetadata)
let maskSizeProperty* = PropertyImpl(name: "mask-size", apply: applyMaskMetadata)
let maskTypeProperty* = PropertyImpl(name: "mask-type", apply: applyMaskMetadata)
