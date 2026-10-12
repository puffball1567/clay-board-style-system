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
