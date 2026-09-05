import std/options

import ../core/[
  computed_style,
  custom_paint,
  declaration,
  diagnostics,
  property,
  style_value
]

proc setCustomPaintMaterial(
    style: var ComputedStyle;
    stage: CustomPaintStage;
    material: Option[string]
) =
  case stage
  of cpsUnderlay:
    style.customPaintStyle().underlay = material
  of cpsOverlay:
    style.customPaintStyle().overlay = material
  of cpsMask:
    style.customPaintStyle().mask = material
  of cpsFilter:
    style.customPaintStyle().filter = material

proc stageForProperty(property: string): CustomPaintStage =
  case property
  of customPaintUnderlayProperty:
    cpsUnderlay
  of customPaintOverlayProperty:
    cpsOverlay
  of customPaintMaskProperty:
    cpsMask
  of customPaintFilterProperty:
    cpsFilter
  else:
    raise newException(ValueError, "unknown custom paint property")

proc applyCustomPaint(
    style: var ComputedStyle;
    declaration: Declaration;
    env: ResolveEnv;
    diagnostics: var Diagnostics
) =
  let stage = declaration.property.stageForProperty
  case declaration.operation.mode
  of mmOverwrite:
    if declaration.operation.value.isNone or
        declaration.operation.value.get.kind != svKeyword:
      diagnostics.addError(
        declaration.property,
        "custom paint requires a material name"
      )
      return
    let material = declaration.operation.value.get.keyword
    if material == "none":
      style.setCustomPaintMaterial(stage, none(string))
    elif material.validCustomPaintMaterial:
      style.setCustomPaintMaterial(stage, some(material))
    else:
      diagnostics.addError(
        declaration.property,
        "custom paint material name is invalid"
      )
  of mmInitial, mmUnset:
    style.setCustomPaintMaterial(stage, none(string))
  of mmInherit:
    diagnostics.addError(
      declaration.property,
      "custom paint is component-local and cannot be inherited"
    )
  of mmRelative:
    diagnostics.addError(
      declaration.property,
      "custom paint does not support relative merge"
    )

let customPaintUnderlayPropertyImpl* = PropertyImpl(
  name: customPaintUnderlayProperty,
  apply: applyCustomPaint
)
let customPaintOverlayPropertyImpl* = PropertyImpl(
  name: customPaintOverlayProperty,
  apply: applyCustomPaint
)
let customPaintMaskPropertyImpl* = PropertyImpl(
  name: customPaintMaskProperty,
  apply: applyCustomPaint
)
let customPaintFilterPropertyImpl* = PropertyImpl(
  name: customPaintFilterProperty,
  apply: applyCustomPaint
)
