import std/[math, unittest]

import clay_board_style_system
import clay_board_style_system/backends/ppm/[raster, retained_canvas]

proc pixel(image: RasterImage; x, y: int): array[4, uint8] =
  let offset = y * image.width + x
  [image.pixels[offset * 3], image.pixels[offset * 3 + 1],
    image.pixels[offset * 3 + 2], image.alpha[offset]]

proc swapRedGreen(): LayerColorFilter =
  colorMatrixFilter([0.0'f32, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0])

suite "retained layer color filters":
  test "named color filters preserve alpha and share the matrix contract":
    let input = rgba(0.25, 0.5, 0.75, 0.4)
    for identity in [
        brightnessColorFilter(1), contrastColorFilter(1),
        saturationColorFilter(1), grayscaleColorFilter(0),
        invertColorFilter(0), sepiaColorFilter(0),
        hueRotateColorFilter(0), hueRotateColorFilter(360),
        hueRotateColorFilter(-360)]:
      check identity.isNil
    check brightnessColorFilter(2).applyLayerColorFilter(input) ==
      rgba(0.5, 1, 1, 0.4)
    check contrastColorFilter(0).applyLayerColorFilter(input) ==
      rgba(0.5, 0.5, 0.5, 0.4)
    let desaturated = saturationColorFilter(0).applyLayerColorFilter(input)
    check abs(desaturated.r - 0.4649) < 0.0001
    check abs(desaturated.g - desaturated.r) < 0.0001
    check abs(desaturated.b - desaturated.r) < 0.0001
    check sameLayerColorFilter(
      grayscaleColorFilter(1), saturationColorFilter(0))
    check invertColorFilter(1).applyLayerColorFilter(input) ==
      rgba(0.75, 0.5, 0.25, 0.4)
    for invalid in [NaN.float32, Inf.float32, NegInf.float32, -0.1'f32]:
      expect ValueError:
        discard brightnessColorFilter(invalid)
      expect ValueError:
        discard grayscaleColorFilter(invalid)
    expect ValueError:
      discard contrastColorFilter(4.1)
    expect ValueError:
      discard saturationColorFilter(4.1)
    expect ValueError:
      discard grayscaleColorFilter(1.1)
    expect ValueError:
      discard invertColorFilter(1.1)

  test "sepia and hue rotation share the layer matrix path":
    let translucentRed = rgba(1, 0, 0, 0.4)
    let sepia = sepiaColorFilter(1).applyLayerColorFilter(translucentRed)
    check abs(sepia.r - 0.393) < 0.0001
    check abs(sepia.g - 0.349) < 0.0001
    check abs(sepia.b - 0.272) < 0.0001
    check sepia.a == translucentRed.a
    let halfSepia = sepiaColorFilter(0.5).applyLayerColorFilter(translucentRed)
    check abs(halfSepia.r - 0.6965) < 0.0001
    check abs(halfSepia.g - 0.1745) < 0.0001
    check abs(halfSepia.b - 0.136) < 0.0001
    let rotated = hueRotateColorFilter(90).applyLayerColorFilter(translucentRed)
    check rotated.r < 0.0001
    check abs(rotated.g - 0.356) < 0.0001
    check rotated.b == 0
    check rotated.a == translucentRed.a
    check sameLayerColorFilter(hueRotateColorFilter(30),
      hueRotateColorFilter(390))
    let image = render([
      pushLayer(rect(0, 0, 1, 1), colorFilter = sepiaColorFilter(1)),
      fillRect(rect(0, 0, 1, 1), rgb(1, 0, 0)), popLayer(),
      pushLayer(rect(1, 0, 1, 1), colorFilter = hueRotateColorFilter(90)),
      fillRect(rect(1, 0, 1, 1), rgb(1, 0, 0)), popLayer()
    ], 2, 1)
    check image.pixel(0, 0) == [100'u8, 89, 69, 255]
    check image.pixel(1, 0) == [0'u8, 91, 0, 255]
    for invalid in [NaN.float32, Inf.float32, NegInf.float32]:
      expect ValueError:
        discard sepiaColorFilter(invalid)
      expect ValueError:
        discard hueRotateColorFilter(invalid)
    for invalid in [-0.1'f32, 1.1'f32]:
      expect ValueError:
        discard sepiaColorFilter(invalid)

  test "matrices are copied, finite, and evaluated before channel clamping":
    var matrix = identityColorMatrix
    matrix[0] = -1
    matrix[3] = 1
    let filter = colorMatrixFilter(matrix)
    matrix[3] = 0
    check filter.applyLayerColorFilter(rgba(0.25, 0.5, 0.75, 0.5)) ==
      rgba(0.75, 0.5, 0.75, 0.5)
    check filter.applyLayerColorFilter(rgba(1, 1, 1, 0)) == rgba(0, 0, 0, 0)
    check colorMatrixFilter(identityColorMatrix).isNil
    for invalid in [NaN.float32, Inf.float32, NegInf.float32]:
      matrix[0] = invalid
      expect ValueError:
        discard colorMatrixFilter(matrix)
    matrix = identityColorMatrix
    matrix[0] = 3.0e38'f32
    matrix[1] = -3.0e38'f32
    matrix[3] = 0.5
    check colorMatrixFilter(matrix).applyLayerColorFilter(rgb(1, 1, 0)).r == 0.5

  test "filter applies to the completed layer and opacity is applied once":
    let image = render([
      fillRect(rect(0, 0, 4, 2), rgb(0, 0, 1)),
      pushLayer(rect(1, 0, 2, 2), opacity = 0.5, colorFilter = swapRedGreen()),
      fillRect(rect(0, 0, 4, 2), rgba(1, 0, 0, 0.5)),
      popLayer()
    ], 4, 2)
    check image.pixel(0, 0) == [0'u8, 0, 255, 255]
    check image.pixel(1, 0)[0] == 0
    check image.pixel(1, 0)[1] in 63'u8 .. 64'u8
    check image.pixel(1, 0)[2] in 191'u8 .. 192'u8
    check image.pixel(3, 0) == [0'u8, 0, 255, 255]

  test "nested filters preserve transforms, clipping, and transparent holes":
    var tint = identityColorMatrix
    tint[3] = 1
    let image = render([
      pushTransform(translationAffine2D(2, 1)),
      pushClip(rect(0, 0, 2, 2)),
      pushLayer(rect(0, 0, 3, 2), colorFilter = colorMatrixFilter(tint)),
      pushLayer(rect(0, 0, 3, 2), colorFilter = swapRedGreen()),
      fillRect(rect(1, 0, 2, 1), rgb(1, 0, 0)),
      popLayer(), popLayer(), popClip(), popTransform()
    ], 6, 4, rgb(0, 0, 1))
    check image.pixel(3, 1) == [255'u8, 255, 0, 255]
    check image.pixel(2, 1) == [0'u8, 0, 255, 255]
    check image.pixel(4, 1) == [0'u8, 0, 255, 255]
    check image.pixel(3, 2) == [0'u8, 0, 255, 255]

  test "copy and additive composition use filtered RGB and preserve alpha":
    for mode in [lcmCopy, lcmAdditive]:
      let image = render([
        fillRect(rect(0, 0, 2, 1), rgb(0, 0, 1)),
        pushLayer(rect(0, 0, 1, 1), compositeMode = mode,
          colorFilter = swapRedGreen()),
        fillRect(rect(0, 0, 1, 1), rgba(1, 0, 0, 0.5)),
        popLayer()
      ], 2, 1)
      if mode == lcmCopy:
        check image.pixel(0, 0) == [0'u8, 255, 0, 128]
      else:
        check image.pixel(0, 0) == [0'u8, 128, 255, 255]
      check image.pixel(1, 0) == [0'u8, 0, 255, 255]

  test "Canvas retains filters through save restore and command placement":
    let canvas = newCanvas2D()
    canvas.save()
    canvas.saveLayer(rect(0, 0, 2, 2), colorFilter = swapRedGreen())
    canvas.fillRect(rect(0, 0, 2, 2), rgb(1, 0, 0))
    canvas.restore()
    let commands = canvas.paintCommands(NodeId(1), rect(3, 4, 2, 2))
    check commands.len == 3
    check commands[0].layerBounds == rect(3, 4, 2, 2)
    check sameLayerColorFilter(commands[0].layerColorFilter, swapRedGreen())
    check render(commands, 6, 7).pixel(3, 4) == [0'u8, 255, 0, 255]

  test "equal matrices reuse retained pixels and changed matrices invalidate":
    let cache = newRetainedRasterCanvas(8, 8, tileSize = 4)
    var commands = @[
      pushLayer(rect(0, 0, 8, 8), colorFilter = swapRedGreen()),
      fillRect(rect(0, 0, 8, 8), rgb(1, 0, 0)), popLayer()
    ]
    discard cache.update(commands)
    commands[0] = pushLayer(rect(0, 0, 8, 8), colorFilter = swapRedGreen())
    check cache.update(commands).dirtyTiles == 0
    commands[0] = pushLayer(rect(0, 0, 8, 8))
    check cache.update(commands).fullRepaint
    check cache.image.pixel(0, 0) == [255'u8, 0, 0, 255]
