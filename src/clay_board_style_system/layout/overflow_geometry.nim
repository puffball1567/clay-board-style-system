import std/[math, options]

import ../core/[computed_style, geometry]

const unboundedClipExtent = 1_000_000.0'f32

proc clipsOverflowX*(style: ComputedStyle): bool =
  style.layout.overflowX != omVisible or
    (style.visual.overflowInline.isSome and
      style.visual.overflowInline.get in ["hidden", "clip", "auto", "scroll"])

proc clipsOverflowY*(style: ComputedStyle): bool =
  style.layout.overflowY != omVisible or
    (style.visual.overflowBlock.isSome and
      style.visual.overflowBlock.get in ["hidden", "clip", "auto", "scroll"])

proc clipsOverflow*(style: ComputedStyle): bool =
  style.clipsOverflowX() or style.clipsOverflowY()

proc scrollbarThickness*(style: ComputedStyle): float32 =
  case style.visual.scrollbarWidth
  of swNone: 0.0'f32
  of swThin: 6.0'f32
  of swAuto: 10.0'f32

proc scrollbarGutterInsets*(style: ComputedStyle): EdgeSizes =
  ## A stable gutter reserves content space; auto remains overlay-like.
  if style.visual.scrollbarGutter.isNone:
    return edges(0)
  let thickness = style.scrollbarThickness()
  if thickness <= 0:
    return edges(0)
  let bothEdges = style.visual.scrollbarGutter.get == "stable both-edges"
  if style.layout.overflowY in {omAuto, omScroll}:
    result.right = thickness
    if bothEdges:
      result.left = thickness
  if style.layout.overflowX in {omAuto, omScroll}:
    result.bottom = thickness
    if bothEdges:
      result.top = thickness

proc overflowContentRect*(base: Rect; style: ComputedStyle): Rect =
  result = base
  if style.box.padding.isSome:
    let pad = style.box.padding.get
    result = Rect(
      x: base.x + pad.left,
      y: base.y + pad.top,
      w: max(0.0'f32, base.w - pad.left - pad.right),
      h: max(0.0'f32, base.h - pad.top - pad.bottom)
    )

proc overflowClipRect*(base: Rect; style: ComputedStyle): Rect =
  let content = overflowContentRect(base, style)

  result = Rect(
    x: if style.clipsOverflowX(): content.x else: -unboundedClipExtent,
    y: if style.clipsOverflowY(): content.y else: -unboundedClipExtent,
    w: if style.clipsOverflowX(): content.w else: unboundedClipExtent * 2,
    h: if style.clipsOverflowY(): content.h else: unboundedClipExtent * 2
  )
