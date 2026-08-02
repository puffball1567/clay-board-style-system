import std/unittest

import clay_board_style_system
import clay_board_style_system/backends/ppm/raster
import clay_board_style_system/generated/default_properties

proc pixel(image: RasterImage; x, y: int): tuple[r, g, b: uint8] =
  let index = (y * image.width + x) * 3
  (image.pixels[index], image.pixels[index + 1], image.pixels[index + 2])

suite "transformed paint stream":
  test "PPM fills the transformed quad without filling its AABB corners":
    let transform = translationAffine2D(30, 20) * rotationAffine2D(0.7853982)
    let image = render([
      pushTransform(transform),
      fillRect(rect(0, 0, 20, 10), rgb(1, 0, 0)),
      popTransform()
    ], 80, 60)
    let center = transform.transformPoint(vec2(10, 5))
    check image.pixel(center.x.int, center.y.int) == (255'u8, 0'u8, 0'u8)
    let bounds = transform.transformedBounds(rect(0, 0, 20, 10))
    check image.pixel(bounds.x.int, bounds.y.int) == (255'u8, 255'u8, 255'u8)

  test "PPM transforms retained path geometry":
    let transform = translationAffine2D(20, 15) * scaleAffine2D(2, 2)
    let image = render([
      pushTransform(transform),
      strokePath([vec2(0, 0), vec2(10, 0)], rgb(0, 0, 1), width = 2),
      popTransform()
    ], 60, 40)
    check image.pixel(30, 15) == (0'u8, 0'u8, 255'u8)

  test "PPM evaluates transformed clips in source coordinates":
    let transform = translationAffine2D(30, 20) * rotationAffine2D(0.7853982)
    let image = render([
      pushTransform(transform),
      pushClip(rect(0, 0, 20, 10)),
      fillRect(rect(-10, -10, 40, 30), rgb(1, 0, 0)),
      popClip(),
      popTransform()
    ], 80, 60)
    let center = transform.transformPoint(vec2(10, 5))
    check image.pixel(center.x.int, center.y.int) == (255'u8, 0'u8, 0'u8)
    let bounds = transform.transformedBounds(rect(0, 0, 20, 10))
    check image.pixel(bounds.x.int, bounds.y.int) == (255'u8, 255'u8, 255'u8)

  test "PPM samples a gradient through the inverse transform":
    let transform = translationAffine2D(30, 20) * rotationAffine2D(0.7853982)
    let gradient = LinearGradient(
      angle: 90,
      interpolationSpace: cisSrgb,
      stops: @[
        colorStop(rgb(1, 0, 0), 0),
        colorStop(rgb(0, 0, 1), 100)
      ]
    )
    let image = render([
      pushTransform(transform),
      fillLinearGradient(rect(0, 0, 20, 10), gradient),
      popTransform()
    ], 80, 60)
    let midpoint = transform.transformPoint(vec2(10, 5))
    let color = image.pixel(midpoint.x.int, midpoint.y.int)
    check color.r in 110'u8 .. 145'u8
    check color.b in 110'u8 .. 145'u8

  test "transform bounds include nested transformed visual overflow":
    var commands = @[
      pushTransform(scaleAffine2D(2, 2)),
      fillRect(rect(1, 2, 3, 4), rgb(1, 0, 0)),
      pushTransform(translationAffine2D(10, 0)),
      drawBoxShadow(
        rect(2, 3, 4, 5), rgb(0, 0, 0),
        offsetX = 1, offsetY = 2, blur = 3, spread = 2
      ),
      popTransform(),
      popTransform()
    ]
    commands.resolveTransformBounds()
    check commands[2].transformBounds == rect(-2, 0, 14, 15)
    check commands[0].transformBounds == rect(1, 0, 21, 15)

  test "styled nodes emit a balanced transform scope":
    var tree = initTree()
    discard tree.addBox(id = "root")
    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(30)),
        decl("height", px(20)),
        decl("background-color", rgb(1, 0, 0)),
        decl("transform", transformValue(translate(px(8), px(4)), rotate(15)))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree, [sheet], defaultProperties(), diagnostics
    )
    check not diagnostics.hasErrors
    let layout = computeLayout(tree, styles, size(100, 80))
    let commands = buildPaintCommands(tree, styles, layout)
    check commands.len == 3
    check commands[0].kind == pcPushTransform
    check commands[0].transformBounds == rect(0, 0, 30, 20)
    check commands[1].kind == pcFillRect
    check commands[2].kind == pcPopTransform
