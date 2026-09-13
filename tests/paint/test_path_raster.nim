import std/[math, unittest]

import clay_board_style_system
import clay_board_style_system/backends/ppm/raster

proc pixel(image: RasterImage; x, y: int): tuple[r, g, b: uint8] =
  let index = (y * image.width + x) * 3
  (image.pixels[index], image.pixels[index + 1], image.pixels[index + 2])

suite "path raster integration":
  test "thick paths rasterize each connected segment":
    let command = strokePath(
      [vec2(2, 2), vec2(12, 2), vec2(12, 12)],
      rgb(1, 0, 0),
      width = 3
    )
    let image = render([command], 16, 16)

    check image.pixel(6, 2) == (255'u8, 0'u8, 0'u8)
    check image.pixel(12, 8) == (255'u8, 0'u8, 0'u8)
    check image.pixel(3, 10) == (255'u8, 255'u8, 255'u8)

  test "closed paths include their final edge":
    let command = strokePath(
      [vec2(2, 2), vec2(12, 2), vec2(12, 12)],
      rgb(0, 0, 1),
      closed = true
    )
    let image = render([command], 16, 16)

    check image.pixel(7, 7) == (0'u8, 0'u8, 255'u8)

  test "path rasterization respects the active clip":
    let commands = [
      pushClip(rect(5, 0, 5, 10)),
      strokePath([vec2(1, 5), vec2(14, 5)], rgb(0, 1, 0), width = 2),
      popClip()
    ]
    let image = render(commands, 16, 10)

    check image.pixel(7, 5) == (0'u8, 255'u8, 0'u8)
    check image.pixel(3, 5) == (255'u8, 255'u8, 255'u8)
    check image.pixel(12, 5) == (255'u8, 255'u8, 255'u8)

  test "degenerate paths are ignored without touching pixels":
    let commands = [
      strokePath([vec2(4, 4)], rgb(1, 0, 0), width = 2),
      strokePath([vec2(1, 1), vec2(8, 8)], rgb(1, 0, 0), width = 0)
    ]
    let image = render(commands, 10, 10)
    check image.pixel(4, 4) == (255'u8, 255'u8, 255'u8)

  test "round and square caps extend beyond butt endpoints":
    let points = [vec2(5, 5), vec2(11, 5)]
    let butt = render([
      strokePath(points, rgb(1, 0, 0), width = 4, lineCap = slcButt)
    ], 16, 10)
    let round = render([
      strokePath(points, rgb(1, 0, 0), width = 4, lineCap = slcRound)
    ], 16, 10)
    let square = render([
      strokePath(points, rgb(1, 0, 0), width = 4, lineCap = slcSquare)
    ], 16, 10)

    check butt.pixel(3, 5) == (255'u8, 255'u8, 255'u8)
    check round.pixel(3, 5).r == 255'u8
    check round.pixel(3, 5).g in 1'u8 .. 128'u8
    check round.pixel(5, 5) == (255'u8, 0'u8, 0'u8)
    check square.pixel(3, 5) == (255'u8, 0'u8, 0'u8)

  test "quadratic and cubic paths reach the shared raster backend":
    var path = initPath2D()
    path.moveTo(vec2(2, 12))
    path.quadraticCurveTo(vec2(8, 0), vec2(14, 12))
    path.bezierCurveTo(vec2(17, 16), vec2(20, 8), vec2(23, 12))
    let image = render([
      strokePath(
        path, rgb(0, 0, 1), width = 2,
        lineCap = slcRound, lineJoin = sljRound
      )
    ], 26, 18)

    check image.pixel(2, 12).b == 255'u8
    check image.pixel(2, 12).r < 255'u8
    check image.pixel(8, 6) == (0'u8, 0'u8, 255'u8)
    check image.pixel(22, 11) == (0'u8, 0'u8, 255'u8)

  test "retained stroke outlines do not rebuild from centerlines during paint":
    var command = strokePath(
      [vec2(2, 5), vec2(12, 5)], rgb(1, 0, 0), width = 3
    )
    check command.pathOutline.fillable
    command.path.clear()
    let image = render([command], 16, 10)
    check image.pixel(7, 5) == (255'u8, 0'u8, 0'u8)

  test "retained arcs rasterize through the shared outline path":
    var path = initPath2D()
    path.arc(vec2(9, 9), 5, 0, PI.float32)
    let image = render([
      strokePath(path, rgb(0, 0, 1), width = 2, lineCap = slcRound)
    ], 20, 16)
    check image.pixel(14, 9).b == 255'u8
    check image.pixel(9, 14).b == 255'u8

  test "stroke outlines follow non-uniform transforms":
    let image = render([
      pushTransform(scaleAffine2D(1, 3)),
      strokePath(
        [vec2(2, 3), vec2(12, 3)], rgb(0, 0, 1),
        width = 2, lineCap = slcButt
      ),
      popTransform()
    ], 16, 16)

    check image.pixel(6, 5) == (255'u8, 255'u8, 255'u8)
    check image.pixel(6, 6).b == 255'u8
    check image.pixel(6, 9) == (0'u8, 0'u8, 255'u8)
    check image.pixel(6, 11).b == 255'u8
    check image.pixel(6, 12) == (255'u8, 255'u8, 255'u8)

  test "concave paths fill without convex triangulation artifacts":
    let path = path2D([
      vec2(2, 2), vec2(14, 2), vec2(14, 6), vec2(7, 6),
      vec2(7, 14), vec2(2, 14)
    ], closed = true)
    let image = render([fillPath(path, rgb(1, 0, 0))], 18, 18)

    check image.pixel(4, 10) == (255'u8, 0'u8, 0'u8)
    check image.pixel(11, 10) == (255'u8, 255'u8, 255'u8)

  test "evenodd fill preserves holes across multiple contours":
    var path = path2D([
      vec2(1, 1), vec2(15, 1), vec2(15, 15), vec2(1, 15)
    ], closed = true)
    path.moveTo(vec2(5, 5))
    path.lineTo(vec2(11, 5))
    path.lineTo(vec2(11, 11))
    path.lineTo(vec2(5, 11))
    path.closePath()
    let image = render([
      fillPath(path, rgb(0, 0, 1), pfrEvenOdd)
    ], 18, 18)

    check image.pixel(3, 3) == (0'u8, 0'u8, 255'u8)
    check image.pixel(8, 8) == (255'u8, 255'u8, 255'u8)

  test "path fill respects transforms clips and opacity":
    let path = path2D([
      vec2(0, 0), vec2(8, 0), vec2(8, 8), vec2(0, 8)
    ], closed = true)
    let image = render([
      pushTransform(translationAffine2D(4, 2)),
      pushClip(rect(2, 0, 4, 8)),
      fillPath(path, rgba(1, 0, 0, 0.5)),
      popClip(),
      popTransform()
    ], 16, 14)

    check image.pixel(7, 5)[0] == 255'u8
    check image.pixel(7, 5)[1] in 127'u8 .. 128'u8
    check image.pixel(5, 5) == (255'u8, 255'u8, 255'u8)
    check image.pixel(11, 5) == (255'u8, 255'u8, 255'u8)

  test "path fill preserves rounded clip corners":
    let path = path2D([
      vec2(0, 0), vec2(10, 0), vec2(10, 10), vec2(0, 10)
    ], closed = true)
    let image = render([
      pushClip(rect(0, 0, 10, 10), radius = 4),
      fillPath(path, rgb(1, 0, 0)),
      popClip()
    ], 12, 12)

    check image.pixel(0, 0) == (255'u8, 255'u8, 255'u8)
    check image.pixel(5, 1) == (255'u8, 0'u8, 0'u8)
