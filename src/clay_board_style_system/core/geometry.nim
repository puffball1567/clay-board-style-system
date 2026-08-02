import std/[math, options]

type
  Vec2* = object
    x*, y*: float32

  Size* = object
    w*, h*: float32

  Rect* = object
    x*, y*, w*, h*: float32

  Affine2D* = object
    ## Column-vector 2D affine transform:
    ## x' = m11*x + m21*y + tx, y' = m12*x + m22*y + ty.
    m11*, m12*, m21*, m22*, tx*, ty*: float32

  TransformedRect* = object
    source*: Rect
    bounds*: Rect
    transform*: Affine2D
    inverseTransform*: Option[Affine2D]

proc vec2*(x, y: float32): Vec2 =
  Vec2(x: x, y: y)

proc size*(w, h: float32): Size =
  Size(w: w, h: h)

proc rect*(x, y, w, h: float32): Rect =
  Rect(x: x, y: y, w: w, h: h)

proc identityAffine2D*(): Affine2D =
  Affine2D(m11: 1, m22: 1)

proc translationAffine2D*(x, y: float32): Affine2D =
  Affine2D(m11: 1, m22: 1, tx: x, ty: y)

proc scaleAffine2D*(x, y: float32): Affine2D =
  Affine2D(m11: x, m22: y)

proc rotationAffine2D*(radians: float32): Affine2D =
  let cosine = cos(radians)
  let sine = sin(radians)
  Affine2D(m11: cosine, m12: sine, m21: -sine, m22: cosine)

proc `*`*(left, right: Affine2D): Affine2D =
  ## Composes transforms so `(left * right).transformPoint(p)` applies
  ## `right` first and then `left`.
  Affine2D(
    m11: left.m11 * right.m11 + left.m21 * right.m12,
    m12: left.m12 * right.m11 + left.m22 * right.m12,
    m21: left.m11 * right.m21 + left.m21 * right.m22,
    m22: left.m12 * right.m21 + left.m22 * right.m22,
    tx: left.m11 * right.tx + left.m21 * right.ty + left.tx,
    ty: left.m12 * right.tx + left.m22 * right.ty + left.ty
  )

proc transformPoint*(transform: Affine2D; point: Vec2): Vec2 =
  vec2(
    transform.m11 * point.x + transform.m21 * point.y + transform.tx,
    transform.m12 * point.x + transform.m22 * point.y + transform.ty
  )

proc determinant*(transform: Affine2D): float32 =
  transform.m11 * transform.m22 - transform.m12 * transform.m21

proc inverse*(transform: Affine2D): Option[Affine2D] =
  let determinant = transform.determinant
  if determinant.classify in {fcNan, fcInf, fcNegInf} or
      abs(determinant) <= 1.0e-7'f32:
    return none(Affine2D)
  let reciprocal = 1.0'f32 / determinant
  let linear = Affine2D(
    m11: transform.m22 * reciprocal,
    m12: -transform.m12 * reciprocal,
    m21: -transform.m21 * reciprocal,
    m22: transform.m11 * reciprocal
  )
  some(Affine2D(
    m11: linear.m11,
    m12: linear.m12,
    m21: linear.m21,
    m22: linear.m22,
    tx: -(linear.m11 * transform.tx + linear.m21 * transform.ty),
    ty: -(linear.m12 * transform.tx + linear.m22 * transform.ty)
  ))

proc transformedBounds*(transform: Affine2D; bounds: Rect): Rect =
  let topLeft = transform.transformPoint(vec2(bounds.x, bounds.y))
  let topRight = transform.transformPoint(vec2(bounds.x + bounds.w, bounds.y))
  let bottomLeft = transform.transformPoint(vec2(bounds.x, bounds.y + bounds.h))
  let bottomRight = transform.transformPoint(vec2(bounds.x + bounds.w, bounds.y + bounds.h))
  let left = min(min(topLeft.x, topRight.x), min(bottomLeft.x, bottomRight.x))
  let right = max(max(topLeft.x, topRight.x), max(bottomLeft.x, bottomRight.x))
  let top = min(min(topLeft.y, topRight.y), min(bottomLeft.y, bottomRight.y))
  let bottom = max(max(topLeft.y, topRight.y), max(bottomLeft.y, bottomRight.y))
  rect(left, top, max(0.0'f32, right - left), max(0.0'f32, bottom - top))

proc isIdentity*(transform: Affine2D; epsilon = 1.0e-6'f32): bool =
  abs(transform.m11 - 1) <= epsilon and abs(transform.m12) <= epsilon and
    abs(transform.m21) <= epsilon and abs(transform.m22 - 1) <= epsilon and
    abs(transform.tx) <= epsilon and abs(transform.ty) <= epsilon

proc transformedRect*(source: Rect; transform: Affine2D): TransformedRect =
  TransformedRect(
    source: source,
    bounds: transform.transformedBounds(source),
    transform: transform,
    inverseTransform: transform.inverse
  )

proc contains*(rect: Rect; point: Vec2): bool =
  point.x >= rect.x and point.y >= rect.y and
    point.x < rect.x + rect.w and point.y < rect.y + rect.h

proc contains*(shape: TransformedRect; point: Vec2): bool =
  if not shape.bounds.contains(point) or shape.inverseTransform.isNone:
    return false
  shape.source.contains(shape.inverseTransform.get.transformPoint(point))

proc translated*(rect: Rect; offset: Vec2): Rect =
  Rect(x: rect.x + offset.x, y: rect.y + offset.y, w: rect.w, h: rect.h)

proc translated*(point: Vec2; offset: Vec2): Vec2 =
  Vec2(x: point.x + offset.x, y: point.y + offset.y)

proc intersection*(a, b: Rect): Rect =
  let left = max(a.x, b.x)
  let top = max(a.y, b.y)
  let right = min(a.x + a.w, b.x + b.w)
  let bottom = min(a.y + a.h, b.y + b.h)
  Rect(
    x: left,
    y: top,
    w: max(0.0'f32, right - left),
    h: max(0.0'f32, bottom - top)
  )

proc isEmpty*(rect: Rect): bool =
  rect.w <= 0 or rect.h <= 0
