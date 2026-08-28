import std/[math, options]

import ../core/[computed_style, geometry, style_value]

type
  BackgroundPaintGeometry* = object
    originRect*: Rect
    clipRect*: Rect
    clipRadius*: float32
    tileRect*: Rect
    paintRect*: Rect
    repeat*: BackgroundRepeat

proc sanitizedInset(value, limit: float32): float32 =
  if value.classify in {fcNan, fcInf, fcNegInf}:
    return 0
  clamp(value, 0.0'f32, max(0.0'f32, limit))

proc insetRect(bounds: Rect; edges: EdgeSizes): Rect =
  let left = edges.left.sanitizedInset(bounds.w)
  let right = edges.right.sanitizedInset(max(0.0'f32, bounds.w - left))
  let top = edges.top.sanitizedInset(bounds.h)
  let bottom = edges.bottom.sanitizedInset(max(0.0'f32, bounds.h - top))
  rect(
    bounds.x + left,
    bounds.y + top,
    max(0.0'f32, bounds.w - left - right),
    max(0.0'f32, bounds.h - top - bottom)
  )

proc backgroundAreaRect*(
    bounds: Rect;
    padding, border: EdgeSizes;
    area: BackgroundBox
): Rect =
  case area
  of bgBorderBox:
    bounds
  of bgPaddingBox:
    bounds.insetRect(border)
  of bgContentBox:
    bounds.insetRect(border).insetRect(padding)

proc backgroundAreaRadius*(
    radius: float32;
    padding, border: EdgeSizes;
    area: BackgroundBox
): float32 =
  let inset =
    case area
    of bgBorderBox:
      0.0'f32
    of bgPaddingBox:
      max(max(border.left, border.right), max(border.top, border.bottom))
    of bgContentBox:
      max(
        max(border.left + padding.left, border.right + padding.right),
        max(border.top + padding.top, border.bottom + padding.bottom)
      )
  max(0.0'f32, radius - max(0.0'f32, inset))

proc resolvedDimension(
    value: Option[LengthValue];
    legacy: Option[float32];
    reference, fallback: float32
): float32 =
  if value.isSome:
    let length = value.get
    let resolved =
      if length.kind == ukPercent:
        reference * length.value / 100.0'f32
      else:
        length.value
    if resolved.classify notin {fcNan, fcInf, fcNegInf}:
      return max(0.0'f32, resolved)
  if legacy.isSome and legacy.get.classify notin {fcNan, fcInf, fcNegInf}:
    return max(0.0'f32, legacy.get)
  max(0.0'f32, fallback)

proc resolvedBackgroundSize(
    style: ComputedBoxStyle;
    origin: Rect
): Size =
  if style.backgroundSize.isNone:
    return size(origin.w, origin.h)
  let authored = style.backgroundSize.get
  case authored.kind
  of bgSizeAuto, bgSizeCover, bgSizeContain:
    # CSS gradients have no intrinsic dimensions or aspect ratio. Their
    # concrete auto/cover/contain size is the positioning area.
    size(origin.w, origin.h)
  of bgSizeLength:
    size(
      resolvedDimension(
        authored.widthValue, authored.width, origin.w, origin.w
      ),
      resolvedDimension(
        authored.heightValue, authored.height, origin.h, origin.h
      )
    )

proc positionOffset(value: LengthValue; remaining: float32): float32 =
  if value.value.classify in {fcNan, fcInf, fcNegInf}:
    return 0
  if value.kind == ukPercent:
    remaining * value.value / 100.0'f32
  else:
    value.value

proc repeatedPaintRect(
    tile, clip: Rect;
    repeat: BackgroundRepeat
): Rect =
  case repeat
  of bgRepeat:
    clip
  of bgRepeatX:
    rect(clip.x, tile.y, clip.w, tile.h).intersection(clip)
  of bgRepeatY:
    rect(tile.x, clip.y, tile.w, clip.h).intersection(clip)
  of bgNoRepeat:
    tile.intersection(clip)

proc backgroundPaintGeometry*(
    bounds: Rect;
    style: ComputedBoxStyle;
    padding: EdgeSizes
): BackgroundPaintGeometry =
  let border = style.borderWidths
  result.originRect = backgroundAreaRect(
    bounds, padding, border, style.backgroundOrigin
  )
  result.clipRect = backgroundAreaRect(
    bounds, padding, border, style.backgroundClip
  )
  result.clipRadius = backgroundAreaRadius(
    style.borderRadius, padding, border, style.backgroundClip
  )
  result.repeat = style.backgroundRepeat
  let tileSize = style.resolvedBackgroundSize(result.originRect)
  let x = result.originRect.x + style.backgroundPositionValue.x.positionOffset(
    result.originRect.w - tileSize.w
  )
  let y = result.originRect.y + style.backgroundPositionValue.y.positionOffset(
    result.originRect.h - tileSize.h
  )
  result.tileRect = rect(x, y, tileSize.w, tileSize.h)
  if result.tileRect.isEmpty or result.clipRect.isEmpty:
    result.paintRect = rect(result.clipRect.x, result.clipRect.y, 0, 0)
  else:
    result.paintRect = repeatedPaintRect(
      result.tileRect, result.clipRect, result.repeat
    )
