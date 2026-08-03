import std/unittest

import clay_board_style_system/backends/ppm/raster
import clay_board_style_system/core/[color, geometry]
import clay_board_style_system/paint/paint_command

proc pixel(image: RasterImage; x, y: int): tuple[r, g, b, a: uint8] =
  let colorIndex = (y * image.width + x) * 3
  let alphaIndex = y * image.width + x
  (
    image.pixels[colorIndex],
    image.pixels[colorIndex + 1],
    image.pixels[colorIndex + 2],
    image.alpha[alphaIndex]
  )

suite "offscreen layer raster composition":
  test "source-over applies layer opacity once":
    let image = render([
      fillRect(rect(0, 0, 4, 4), rgb(0, 0, 1)),
      pushLayer(rect(0, 0, 4, 4), opacity = 0.5),
      fillRect(rect(0, 0, 4, 4), rgb(1, 0, 0)),
      popLayer()
    ], 4, 4, rgb(0, 0, 0))

    let sample = image.pixel(2, 2)
    check sample.r in 127'u8 .. 128'u8
    check sample.g == 0
    check sample.b in 127'u8 .. 128'u8
    check sample.a == 255

  test "source-over combines translucent content and layer opacity once each":
    let image = render([
      fillRect(rect(0, 0, 2, 2), rgb(0, 0, 1)),
      pushLayer(rect(0, 0, 2, 2), opacity = 0.5),
      fillRect(rect(0, 0, 2, 2), rgba(1, 0, 0, 0.5)),
      popLayer()
    ], 2, 2, rgb(0, 0, 0))

    let sample = image.pixel(1, 1)
    check sample.r in 63'u8 .. 64'u8
    check sample.g == 0
    check sample.b in 191'u8 .. 192'u8
    check sample.a == 255

  test "copy replaces pixels only inside explicit layer bounds":
    let image = render([
      fillRect(rect(0, 0, 4, 2), rgb(0, 0, 1)),
      pushLayer(rect(1, 0, 2, 2), compositeMode = lcmCopy),
      fillRect(rect(0, 0, 4, 2), rgb(0, 1, 0)),
      popLayer()
    ], 4, 2, rgb(0, 0, 0))

    check image.pixel(0, 0) == (0'u8, 0'u8, 255'u8, 255'u8)
    check image.pixel(1, 0) == (0'u8, 255'u8, 0'u8, 255'u8)
    check image.pixel(2, 0) == (0'u8, 255'u8, 0'u8, 255'u8)
    check image.pixel(3, 0) == (0'u8, 0'u8, 255'u8, 255'u8)

  test "additive composition clamps channels and preserves destination alpha":
    let image = render([
      fillRect(rect(0, 0, 2, 2), rgb(0.2, 0.1, 0.8)),
      pushLayer(rect(0, 0, 2, 2), opacity = 0.5, compositeMode = lcmAdditive),
      fillRect(rect(0, 0, 2, 2), rgb(1, 0.4, 0.6)),
      popLayer()
    ], 2, 2, rgb(0, 0, 0))

    let sample = image.pixel(1, 1)
    check sample.r in 178'u8 .. 179'u8
    check sample.g in 76'u8 .. 77'u8
    check sample.b == 255
    check sample.a == 255

  test "dangling nested layers close deterministically":
    let image = render([
      pushLayer(rect(0, 0, 3, 3), opacity = 0.5),
      pushLayer(rect(0, 0, 3, 3), opacity = 0.5),
      fillRect(rect(0, 0, 3, 3), rgb(1, 0, 0))
    ], 3, 3, rgb(0, 0, 1))

    let sample = image.pixel(1, 1)
    check sample.r in 63'u8 .. 64'u8
    check sample.g == 0
    check sample.b in 191'u8 .. 192'u8
    check sample.a == 255

  test "layers nested in transforms retain one composition boundary":
    let image = render([
      fillRect(rect(0, 0, 6, 4), rgb(0, 0, 1)),
      pushTransform(translationAffine2D(2, 0)),
      pushLayer(rect(1, 1, 2, 2), opacity = 0.5),
      fillRect(rect(1, 1, 2, 2), rgb(1, 0, 0)),
      popLayer(),
      popTransform()
    ], 6, 4, rgb(0, 0, 0))

    let sample = image.pixel(3, 2)
    check sample.r in 127'u8 .. 128'u8
    check sample.g == 0
    check sample.b in 127'u8 .. 128'u8
    check image.pixel(1, 2).b == 255
