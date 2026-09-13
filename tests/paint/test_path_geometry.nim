import std/[math, sequtils, unittest]

import clay_board_style_system

suite "retained path geometry":
  test "polyline helper preserves closure as a path command":
    let path = path2D(
      [vec2(0, 0), vec2(10, 0), vec2(10, 10)],
      closed = true
    )
    check path.segments.len == 4
    check path.segments[0].kind == pskMoveTo
    check path.segments[1].kind == pskLineTo
    check path.segments[^1].kind == pskClose
    let contours = path.flattened()
    check contours.len == 1
    check contours[0].closed
    check contours[0].points == @[vec2(0, 0), vec2(10, 0), vec2(10, 10)]

  test "quadratic and cubic curves flatten to stable endpoints":
    var path = initPath2D()
    path.moveTo(vec2(0, 0))
    path.quadraticCurveTo(vec2(10, 20), vec2(20, 0))
    path.bezierCurveTo(vec2(25, -10), vec2(35, 10), vec2(40, 0))
    let coarse = path.flattened(2)
    let fine = path.flattened(0.1)

    check coarse.len == 1
    check fine.len == 1
    check coarse[0].points[0] == vec2(0, 0)
    check coarse[0].points[^1] == vec2(40, 0)
    check fine[0].points.len > coarse[0].points.len
    check fine[0].points[^1] == vec2(40, 0)

  test "arc and ellipse append bounded cubic geometry":
    var path = initPath2D()
    path.arc(vec2(10, 10), 8, 0, PI.float32 * 0.5'f32)
    check path.segments.len == 2
    check path.segments[0].kind == pskMoveTo
    check path.segments[1].kind == pskCubicTo
    check abs(path.segments[0].endpoint.x - 18) < 0.001
    check abs(path.segments[0].endpoint.y - 10) < 0.001
    check abs(path.segments[1].endpoint.x - 10) < 0.001
    check abs(path.segments[1].endpoint.y - 18) < 0.001

    var ellipsePath = initPath2D()
    ellipsePath.ellipse(
      vec2(20, 20), 10, 4, PI.float32 * 0.5'f32,
      0, PI.float32 * 2.0'f32
    )
    check ellipsePath.segments.len == 5
    check ellipsePath.segments[1 .. ^1].allIt(it.kind == pskCubicTo)
    check ellipsePath.flattened(0.1).len == 1

  test "arc direction connection and invalid input are deterministic":
    var path = path2D([vec2(0, 0), vec2(1, 0)])
    path.arc(
      vec2(5, 5), 3, 0, PI.float32 * 0.5'f32,
      counterClockwise = true
    )
    check path.segments[2].kind == pskLineTo
    check path.segments[3 .. ^1].len == 3
    check path.segments[3 .. ^1].allIt(it.kind == pskCubicTo)

    let retained = path.segments
    path.arc(vec2(0, 0), -1, 0, PI.float32)
    path.ellipse(vec2(0, 0), 1, NaN.float32, 0, 0, PI.float32)
    check path.segments == retained

  test "stroke outlines preserve caps and closed fill contours":
    let centerline = path2D([vec2(5, 5), vec2(11, 5)])
    let butt = centerline.strokeOutline(4, slcButt)
    let round = centerline.strokeOutline(4, slcRound)
    let square = centerline.strokeOutline(4, slcSquare)

    check butt.fillable
    check round.fillable
    check square.fillable
    check abs(butt.bounds.x - 5) < 0.001
    check abs(butt.bounds.w - 6) < 0.001
    check round.bounds.x < 3.01
    check round.bounds.x + round.bounds.w > 12.99
    check square.bounds.x < 3.01
    check square.bounds.x + square.bounds.w > 12.99
    for contour in round.flattened():
      check contour.closed

  test "stroke outlines reject invalid widths and normalize invalid tolerance":
    let centerline = path2D([vec2(2, 2), vec2(8, 2)])
    check not centerline.strokeOutline(NaN.float32).fillable
    check not centerline.strokeOutline(Inf.float32).fillable
    check not centerline.strokeOutline(-1).fillable
    check centerline.strokeOutline(2, tolerance = NaN.float32).fillable

  test "move commands split independent contours":
    var path = initPath2D()
    path.moveTo(vec2(0, 0))
    path.lineTo(vec2(5, 0))
    path.moveTo(vec2(10, 10))
    path.lineTo(vec2(20, 10))
    let contours = path.flattened()
    check contours.len == 2
    check contours[0].points == @[vec2(0, 0), vec2(5, 0)]
    check contours[1].points == @[vec2(10, 10), vec2(20, 10)]

  test "first drawing command starts safely without an implicit origin line":
    var linePath = initPath2D()
    linePath.lineTo(vec2(10, 10))
    check linePath.flattened().len == 0

    var curvePath = initPath2D()
    curvePath.quadraticCurveTo(vec2(3, 4), vec2(8, 9))
    check curvePath.flattened().len == 0

  test "non-finite points and duplicate closes are ignored":
    var path = initPath2D()
    path.moveTo(vec2(0, 0))
    path.lineTo(vec2(NaN.float32, 3))
    path.lineTo(vec2(10, 0))
    path.closePath()
    path.closePath()
    check path.segments.len == 3
    check path.segments[^1].kind == pskClose

  test "translation preserves commands controls and closure":
    var path = initPath2D()
    path.moveTo(vec2(1, 2))
    path.bezierCurveTo(vec2(3, 4), vec2(5, 6), vec2(7, 8))
    path.closePath()
    let moved = path.translated(vec2(10, 20))
    check moved.segments[0].endpoint == vec2(11, 22)
    check moved.segments[1].control1 == vec2(13, 24)
    check moved.segments[1].control2 == vec2(15, 26)
    check moved.segments[1].endpoint == vec2(17, 28)
    check moved.segments[^1].kind == pskClose

  test "nonzero and evenodd rules distinguish same-direction contours":
    var path = initPath2D()
    for points in [
      [vec2(0, 0), vec2(12, 0), vec2(12, 12), vec2(0, 12)],
      [vec2(3, 3), vec2(9, 3), vec2(9, 9), vec2(3, 9)]
    ]:
      path.moveTo(points[0])
      for index in 1 .. points.high:
        path.lineTo(points[index])
      path.closePath()
    let contours = path.flattened()

    check contours.contains(vec2(1, 1), pfrNonZero)
    check contours.contains(vec2(6, 6), pfrNonZero)
    check contours.contains(vec2(1, 1), pfrEvenOdd)
    check not contours.contains(vec2(6, 6), pfrEvenOdd)

  test "opposite contour winding cuts a nonzero hole":
    var path = initPath2D()
    path.moveTo(vec2(0, 0))
    path.lineTo(vec2(12, 0))
    path.lineTo(vec2(12, 12))
    path.lineTo(vec2(0, 12))
    path.closePath()
    path.moveTo(vec2(3, 3))
    path.lineTo(vec2(3, 9))
    path.lineTo(vec2(9, 9))
    path.lineTo(vec2(9, 3))
    path.closePath()

    check not path.flattened().contains(vec2(6, 6), pfrNonZero)

  test "scanline coverage encodes stable antialias samples":
    let path = path2D([
      vec2(1, 1), vec2(3, 1), vec2(3, 3), vec2(1, 3)
    ], closed = true)
    var coverage: seq[uint8]

    path.flattened().fillPathCoverageRow(
      y = 1, xStart = 0, xEnd = 4, fillRule = pfrNonZero,
      coverage = coverage
    )

    check coverage == @[0'u8, 15'u8, 15'u8, 0'u8]
    check coverage[1].pathCoverageCount == 4
    check pathCoverageCount(0b0101'u8) == 2

  test "scanline coverage clears reused storage for empty and outside rows":
    let path = path2D([
      vec2(1, 1), vec2(3, 1), vec2(3, 3), vec2(1, 3)
    ], closed = true)
    let contours = path.flattened()
    var coverage = @[255'u8, 255'u8]

    contours.fillPathCoverageRow(
      y = 8, xStart = 0, xEnd = 2, fillRule = pfrNonZero,
      coverage = coverage
    )
    check coverage == @[0'u8, 0'u8]

    contours.fillPathCoverageRow(
      y = 0, xStart = 2, xEnd = 2, fillRule = pfrEvenOdd,
      coverage = coverage
    )
    check coverage.len == 0
