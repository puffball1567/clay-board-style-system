import std/[math, unittest]

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
