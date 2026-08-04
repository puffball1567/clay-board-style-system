import std/[math, options]

import ../core/[computed_style, geometry]

const degreesToRadians = PI.float32 / 180.0'f32

proc resolvedLength(
    length: ComputedLength;
    reference: float32;
    fontSize: float32;
    rootFontSize: float32
): Option[float32] =
  case length.kind
  of cukPx:
    some(length.value)
  of cukPercent:
    some(reference * length.value / 100.0'f32)
  of cukEm:
    some(fontSize * length.value)
  of cukRem:
    some(rootFontSize * length.value)
  of cukFill, cukContent, cukMinContent, cukMaxContent, cukFitContent,
      cukAuto, cukNone, cukVw, cukVh, cukVmin, cukVmax:
    none(float32)

proc transformReferenceBounds*(bounds: Rect; style: ComputedStyle): Rect =
  let transform = style.transform
  if transform.transformBox != tboxContentBox:
    return bounds

  let padding =
    if style.box.padding.isSome: style.box.padding.get
    else: edges(0)
  let border = style.box.borderWidths
  let left = padding.left +
    (if style.box.borderSideVisible.left: border.left else: 0.0'f32)
  let right = padding.right +
    (if style.box.borderSideVisible.right: border.right else: 0.0'f32)
  let top = padding.top +
    (if style.box.borderSideVisible.top: border.top else: 0.0'f32)
  let bottom = padding.bottom +
    (if style.box.borderSideVisible.bottom: border.bottom else: 0.0'f32)
  rect(
    bounds.x + left,
    bounds.y + top,
    max(0.0'f32, bounds.w - left - right),
    max(0.0'f32, bounds.h - top - bottom)
  )

proc operationMatrix(
    operation: TransformOperation;
    reference: Rect;
    fontSize: float32;
    rootFontSize: float32
): Affine2D =
  case operation.kind
  of ctkTranslate:
    let x =
      if operation.xLength.isSome:
        operation.xLength.get.resolvedLength(reference.w, fontSize, rootFontSize).get(0)
      else:
        0.0'f32
    let y =
      if operation.yLength.isSome:
        operation.yLength.get.resolvedLength(reference.h, fontSize, rootFontSize).get(0)
      else:
        0.0'f32
    translationAffine2D(x, y)
  of ctkScale:
    let x = operation.xNumber.get(1.0'f32)
    let y = operation.yNumber.get(x)
    scaleAffine2D(x, y)
  of ctkRotate:
    rotationAffine2D(operation.angle * degreesToRadians)

proc resolvedTransform*(
    style: ComputedStyle;
    bounds: Rect;
    rootFontSize = 16.0'f32
): Affine2D =
  if not style.hasTransformStyle:
    return identityAffine2D()

  let transform = style.transform
  let reference = transformReferenceBounds(bounds, style)
  let fontSize = style.text.fontSize.get(rootFontSize)
  let originX = transform.originX.resolvedLength(
    reference.w, fontSize, rootFontSize
  ).get(reference.w * 0.5'f32)
  let originY = transform.originY.resolvedLength(
    reference.h, fontSize, rootFontSize
  ).get(reference.h * 0.5'f32)
  let origin = vec2(reference.x + originX, reference.y + originY)

  var local = identityAffine2D()
  if transform.translateX.isSome or transform.translateY.isSome:
    let x =
      if transform.translateX.isSome:
        transform.translateX.get.resolvedLength(
          reference.w, fontSize, rootFontSize
        ).get(0)
      else:
        0.0'f32
    let y =
      if transform.translateY.isSome:
        transform.translateY.get.resolvedLength(
          reference.h, fontSize, rootFontSize
        ).get(0)
      else:
        0.0'f32
    local = local * translationAffine2D(x, y)
  if transform.rotate.isSome:
    local = local * rotationAffine2D(transform.rotate.get * degreesToRadians)
  if transform.scaleX.isSome or transform.scaleY.isSome:
    let x = transform.scaleX.get(1.0'f32)
    let y = transform.scaleY.get(x)
    local = local * scaleAffine2D(x, y)
  for operation in transform.operations:
    local = local * operation.operationMatrix(reference, fontSize, rootFontSize)

  translationAffine2D(origin.x, origin.y) * local *
    translationAffine2D(-origin.x, -origin.y)
