import std/unittest

import clay_board_style_system
import clay_board_style_system/backends/ppm/raster

proc pixel(image: RasterImage; x, y: int): tuple[r, g, b: uint8] =
  let index = (y * image.width + x) * 3
  (
    image.pixels[index],
    image.pixels[index + 1],
    image.pixels[index + 2]
  )

suite "gradient raster integration":
  test "PPM rendering uses the selected interpolation space":
    let stops = @[
      colorStop(rgb(1, 0, 0), 0),
      colorStop(rgb(0, 0, 1), 100)
    ]
    let encoded = fillLinearGradient(
      rect(0, 0, 3, 1),
      LinearGradient(
        angle: 90,
        interpolationSpace: cisSrgb,
        stops: stops
      )
    )
    let linear = fillLinearGradient(
      rect(0, 0, 3, 1),
      LinearGradient(
        angle: 90,
        interpolationSpace: cisSrgbLinear,
        stops: stops
      )
    )

    let encodedImage = render([encoded], 3, 1)
    let linearImage = render([linear], 3, 1)
    let encodedMidpoint = encodedImage.pixel(1, 0)
    let linearMidpoint = linearImage.pixel(1, 0)

    check encodedMidpoint.r in 126'u8 .. 129'u8
    check encodedMidpoint.g == 0
    check encodedMidpoint.b in 126'u8 .. 129'u8
    check linearMidpoint.r > 185
    check linearMidpoint.g == 0
    check linearMidpoint.b > 185
