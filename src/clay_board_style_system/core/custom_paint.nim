import std/strutils

import ./[declaration, style_value]

const
  maxCustomPaintMaterialBytes* = 256
  customPaintUnderlayProperty* = "-cbss-custom-paint-underlay"
  customPaintOverlayProperty* = "-cbss-custom-paint-overlay"
  customPaintMaskProperty* = "-cbss-custom-paint-mask"
  customPaintFilterProperty* = "-cbss-custom-paint-filter"

type
  CustomPaintStage* = enum
    cpsUnderlay,
    cpsOverlay,
    cpsMask,
    cpsFilter

proc customPaintProperty*(stage: CustomPaintStage): string =
  case stage
  of cpsUnderlay:
    customPaintUnderlayProperty
  of cpsOverlay:
    customPaintOverlayProperty
  of cpsMask:
    customPaintMaskProperty
  of cpsFilter:
    customPaintFilterProperty

proc validCustomPaintMaterial*(material: string): bool =
  if material.len == 0 or material.len > maxCustomPaintMaterialBytes or
      material.strip() != material:
    return false
  for character in material:
    if character == '\0' or character in {'\x01' .. '\x1f', '\x7f'}:
      return false
  true

proc customPaint*(
    material: string;
    stage = cpsOverlay;
    sourceOrder = 0
): Declaration =
  ## Refers to a registered paint material without retaining backend objects in
  ## Style. Resolution remains backend-neutral and occurs after layout.
  if not material.validCustomPaintMaterial:
    raise newException(ValueError, "custom paint material name is invalid")
  decl(stage.customPaintProperty, keyword(material), sourceOrder)
