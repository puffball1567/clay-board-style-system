import std/[math, options, unittest]

import clay_board_style_system

const epsilon = 0.001'f32

proc near(actual, expected: float32): bool =
  abs(actual - expected) <= epsilon

proc checkPoint(actual, expected: Vec2) =
  check actual.x.near(expected.x)
  check actual.y.near(expected.y)

suite "2D transform geometry":
  test "affine composition and inverse preserve points":
    let transform = translationAffine2D(20, -4) *
      rotationAffine2D(PI.float32 / 2) * scaleAffine2D(2, 3)
    let point = vec2(4, 5)
    let transformed = transform.transformPoint(point)
    checkPoint(transformed, vec2(5, 4))
    check transform.inverse.isSome
    checkPoint(transform.inverse.get.transformPoint(transformed), point)

  test "singular affine transforms have no inverse":
    check scaleAffine2D(0, 1).inverse.isNone

  test "transformed bounds enclose all rotated corners":
    let transformed = rotationAffine2D(PI.float32 / 2).transformedBounds(
      rect(10, 20, 30, 40)
    )
    check transformed.x.near(-60)
    check transformed.y.near(10)
    check transformed.w.near(40)
    check transformed.h.near(30)

  test "default transform origin is the border box center":
    var style = initialComputedStyle()
    style.transform.operations = @[
      TransformOperation(kind: ctkRotate, angle: 180)
    ]
    let matrix = resolvedTransform(style, rect(10, 20, 100, 40))
    checkPoint(matrix.transformPoint(vec2(10, 20)), vec2(110, 60))
    checkPoint(matrix.transformPoint(vec2(60, 40)), vec2(60, 40))

  test "percent translation resolves against the selected reference box":
    var style = initialComputedStyle()
    style.box.padding = some(edges(10))
    style.transform.transformBox = tboxContentBox
    style.transform.operations = @[
      TransformOperation(
        kind: ctkTranslate,
        xLength: some(ComputedLength(kind: cukPercent, value: 50)),
        yLength: some(ComputedLength(kind: cukPercent, value: 100))
      )
    ]
    let matrix = resolvedTransform(style, rect(0, 0, 100, 60))
    checkPoint(matrix.transformPoint(vec2(0, 0)), vec2(40, 40))

  test "individual properties precede the transform function list":
    var style = initialComputedStyle()
    style.transform.translateX = some(ComputedLength(kind: cukPx, value: 10))
    style.transform.scaleX = some(2.0'f32)
    style.transform.scaleY = some(2.0'f32)
    style.transform.operations = @[
      TransformOperation(
        kind: ctkTranslate,
        xLength: some(ComputedLength(kind: cukPx, value: 5))
      )
    ]
    style.transform.originX = ComputedLength(kind: cukPx, value: 0)
    style.transform.originY = ComputedLength(kind: cukPx, value: 0)
    let matrix = resolvedTransform(style, rect(0, 0, 20, 20))
    checkPoint(matrix.transformPoint(vec2(1, 0)), vec2(22, 0))

  test "unsupported intrinsic transform lengths fall back safely":
    var style = initialComputedStyle()
    style.transform.translateX = some(
      ComputedLength(kind: cukContent, value: 1)
    )
    check resolvedTransform(style, rect(0, 0, 20, 20)).isIdentity
