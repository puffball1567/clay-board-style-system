import std/unittest

import clay_board_style_system
import clay_board_style_system/backends/ppm/raster

proc rgbAt(image: RasterImage; x, y: int): array[3, uint8] =
  let offset = (y * image.width + x) * 3
  [image.pixels[offset], image.pixels[offset + 1], image.pixels[offset + 2]]

suite "retained raster surface":
  test "initial pixels are committed with one full dirty revision":
    let surface = newRasterSurface(3, 2, [1'u8, 2'u8, 3'u8, 4'u8])
    check surface.width == 3
    check surface.height == 2
    check surface.format == rpfRgba8
    check surface.colorSpace == rcsSrgb
    check surface.alphaMode == ramStraight
    check surface.revision == 1
    check surface.pixels.len == 24
    check surface.pixels[0 .. 7] == @[1'u8, 2, 3, 4, 1, 2, 3, 4]
    check surface.dirtyRegions == @[rasterRegion(0, 0, 3, 2)]

  test "updates remain invisible until publish and honor source stride":
    let surface = newRasterSurface(3, 2)
    let source = @[
      10'u8, 20, 30, 255, 40, 50, 60, 255, 99, 99, 99, 99,
      70, 80, 90, 255, 100, 110, 120, 255, 88, 88, 88, 88
    ]
    surface.updateRegion(rasterRegion(1, 0, 2, 2), source, sourceStride = 12)
    check surface.pendingUpdateCount == 1
    check surface.revision == 1
    check surface.pixels[4] == 0
    check surface.publish()
    check surface.pendingUpdateCount == 0
    check surface.revision == 2
    check surface.pixels[4 .. 11] == @[10'u8, 20, 30, 255, 40, 50, 60, 255]
    check surface.pixels[16 .. 23] == @[70'u8, 80, 90, 255, 100, 110, 120, 255]
    check surface.dirtyRegions == @[rasterRegion(1, 0, 2, 2)]
    check not surface.publish()
    check surface.revision == 2

  test "touching updates merge and separated updates remain bounded":
    let surface = newRasterSurface(96, 2)
    let pixel = @[255'u8, 0, 0, 255]
    surface.updateRegion(rasterRegion(1, 0, 1, 1), pixel)
    surface.updateRegion(rasterRegion(2, 0, 1, 1), pixel)
    check surface.publish()
    check surface.dirtyRegions == @[rasterRegion(1, 0, 2, 1)]

    for index in 0 .. MaxRasterDirtyRegions:
      surface.updateRegion(rasterRegion(index * 2, 1, 1, 1), pixel)
    check surface.publish()
    check surface.dirtyRegions.len == 1
    check surface.dirtyRegions[0] == rasterRegion(
      0, 1, MaxRasterDirtyRegions * 2 + 1, 1
    )

  test "replace discards older pending patches":
    let surface = newRasterSurface(2, 1)
    surface.updateRegion(rasterRegion(0, 0, 1, 1), @[255'u8, 0, 0, 255])
    surface.replacePixels(@[0'u8, 255, 0, 255, 0, 0, 255, 255])
    check surface.pendingUpdateCount == 1
    check surface.publish()
    check surface.pixels == @[0'u8, 255, 0, 255, 0, 0, 255, 255]
    check surface.dirtyRegions == @[rasterRegion(0, 0, 2, 1)]

  test "invalid replace preserves pending updates and pending bytes are bounded":
    let surface = newRasterSurface(2, 1, maxBytes = 8)
    surface.updateRegion(rasterRegion(0, 0, 1, 1), @[255'u8, 0, 0, 255])
    expect ValueError:
      surface.replacePixels(@[0'u8, 1, 2])
    check surface.pendingUpdateCount == 1
    surface.updateRegion(rasterRegion(1, 0, 1, 1), @[0'u8, 255, 0, 255])
    expect ValueError:
      surface.updateRegion(rasterRegion(0, 0, 1, 1), @[0'u8, 0, 255, 255])
    check surface.pendingUpdateCount == 2
    check surface.publish()
    check surface.pixels == @[255'u8, 0, 0, 255, 0, 255, 0, 255]

  test "invalid dimensions regions strides and byte ranges fail atomically":
    expect ValueError:
      discard newRasterSurface(0, 1)
    expect ValueError:
      discard newRasterSurface(10, 10, maxBytes = 399)

    let surface = newRasterSurface(4, 4)
    expect ValueError:
      surface.updateRegion(rasterRegion(-1, 0, 1, 1), @[0'u8, 0, 0, 0])
    expect ValueError:
      surface.updateRegion(rasterRegion(3, 3, 2, 1), newSeq[uint8](8))
    expect ValueError:
      surface.updateRegion(
        rasterRegion(0, 0, 2, 1), newSeq[uint8](8), sourceStride = 7
      )
    expect ValueError:
      surface.updateRegion(
        rasterRegion(0, 0, 2, 2), newSeq[uint8](15), sourceStride = 8
      )
    check surface.pendingUpdateCount == 0
    check surface.revision == 1

  test "headless rendering scales and alpha-composites committed pixels":
    let surface = newRasterSurface(2, 1)
    surface.replacePixels(@[
      255'u8, 0, 0, 255,
      0, 0, 255, 128
    ])
    check surface.publish()
    let commands = @[
      drawRasterSurface(NodeId(1), surface, rect(0, 0, 4, 2))
    ]
    let image = raster.render(commands, 4, 2, rgb(0, 0, 0))
    check image.rgbAt(0, 0) == [255'u8, 0, 0]
    check image.rgbAt(1, 1) == [255'u8, 0, 0]
    check image.rgbAt(2, 0)[2] in 127'u8 .. 129'u8
    check image.rgbAt(3, 1)[2] in 127'u8 .. 129'u8

  test "nil surfaces reject mutation and paint construction":
    let missing = RasterSurface(nil)
    expect ValueError:
      missing.updateRegion(rasterRegion(0, 0, 1, 1), @[0'u8, 0, 0, 0])
    expect ValueError:
      discard missing.publish()
    expect ValueError:
      discard drawRasterSurface(NodeId(1), missing, rect(0, 0, 1, 1))
