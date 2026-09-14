import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/backends/ppm/retained_canvas
import clay_board_style_system/backends/ppm/raster

proc rgbAt(image: RasterImage; x, y: int): array[3, uint8] =
  let offset = (y * image.width + x) * 3
  [image.pixels[offset], image.pixels[offset + 1], image.pixels[offset + 2]]

suite "retained CPU canvas raster":
  test "paint command equality detects every command variant":
    for kind in PaintCommandKind:
      let first = PaintCommand(kind: kind)
      var changed = first
      check samePaintCommand(first, changed)
      case kind
      of pcPushTransform:
        changed.transform.tx = 1
      of pcPopTransform, pcPopLayer, pcPopClip:
        changed.owner = some(NodeId(1))
      of pcPushLayer:
        changed.layerOpacity = 0.5
      of pcPushClip:
        changed.clipRadius = 1
      of pcBoxShadow:
        changed.shadowBlur = 1
      of pcFillRect:
        changed.radius = 1
      of pcFillLinearGradient:
        changed.gradientRadius = 1
      of pcStrokeRect:
        changed.strokeWidth = 1
      of pcFillPath:
        changed.fillPathColor = rgb(1, 0, 0)
      of pcStrokePath:
        changed.pathWidth = 1
      of pcDrawText:
        changed.text = "changed"
      of pcDrawImage:
        changed.imageSource = "changed.png"
      of pcDrawRasterSurface:
        changed.rasterRect = rect(0, 0, 1, 1)
      of pcDrawGpuDirectSurface:
        changed.gpuSurfaceRect = rect(0, 0, 1, 1)
      check not samePaintCommand(first, changed)

  test "first update paints all tiles and identical input paints none":
    let cache = newRetainedRasterCanvas(96, 64, tileSize = 32)
    let commands = @[fillRect(rect(2, 2, 12, 12), rgb(1, 0, 0))]
    let first = cache.update(commands)
    check first.fullRepaint
    check first.dirtyTiles == 6
    check first.totalTiles == 6
    check first.regions == @[rect(0, 0, 96, 64)]
    check cache.image.rgbAt(4, 4) == [255'u8, 0, 0]

    let unchanged = cache.update(commands)
    check not unchanged.fullRepaint
    check unchanged.dirtyTiles == 0
    check unchanged.regions.len == 0

  test "moving a bounded command redraws only old and new tiles":
    let cache = newRetainedRasterCanvas(128, 32, tileSize = 32)
    discard cache.update(@[fillRect(rect(2, 2, 8, 8), rgb(1, 0, 0))])
    let changed = cache.update(@[
      fillRect(rect(98, 2, 8, 8), rgb(0, 0, 1))
    ])
    check not changed.fullRepaint
    check changed.dirtyTiles == 2
    check changed.regions == @[
      rect(0, 0, 32, 32),
      rect(96, 0, 32, 32)
    ]
    check cache.image.rgbAt(4, 4) == [255'u8, 255, 255]
    check cache.image.rgbAt(100, 4) == [0'u8, 0, 255]
    check cache.image.rgbAt(64, 4) == [255'u8, 255, 255]

  test "removed commands restore only their previous tile":
    let cache = newRetainedRasterCanvas(64, 32, tileSize = 16)
    discard cache.update(@[
      fillRect(rect(1, 1, 8, 8), rgb(1, 0, 0)),
      fillRect(rect(49, 1, 8, 8), rgb(0, 1, 0))
    ])
    let changed = cache.update(@[
      fillRect(rect(1, 1, 8, 8), rgb(1, 0, 0))
    ])
    check changed.dirtyTiles == 1
    check changed.regions == @[rect(48, 0, 16, 16)]
    check cache.image.rgbAt(4, 4) == [255'u8, 0, 0]
    check cache.image.rgbAt(52, 4) == [255'u8, 255, 255]

  test "unchanged transform scopes retain localized transformed damage":
    let cache = newRetainedRasterCanvas(128, 64, tileSize = 32)
    let first = @[
      pushTransform(translationAffine2D(64, 0)),
      fillRect(rect(2, 2, 8, 8), rgb(1, 0, 0)),
      popTransform()
    ]
    discard cache.update(first)
    let second = @[
      pushTransform(translationAffine2D(64, 0)),
      fillRect(rect(2, 2, 8, 8), rgb(0, 1, 0)),
      popTransform()
    ]
    let changed = cache.update(second)
    check not changed.fullRepaint
    check changed.dirtyTiles == 1
    check changed.regions == @[rect(64, 0, 32, 32)]
    check cache.image.rgbAt(68, 4) == [0'u8, 255, 0]

  test "scope and text changes use conservative full damage":
    let cache = newRetainedRasterCanvas(64, 64, tileSize = 16)
    discard cache.update(@[
      pushClip(rect(0, 0, 32, 32)),
      fillRect(rect(1, 1, 8, 8), rgb(1, 0, 0)),
      popClip()
    ])
    let scopeChanged = cache.update(@[
      pushClip(rect(0, 0, 48, 48)),
      fillRect(rect(1, 1, 8, 8), rgb(1, 0, 0)),
      popClip()
    ])
    check scopeChanged.fullRepaint
    check scopeChanged.dirtyTiles == 16

    var style = ComputedTextStyle()
    style.fontSize = some(14.0'f32)
    discard cache.update(@[
      drawText(NodeId(1), "first", vec2(2, 2), rgb(0, 0, 0), style)
    ])
    let textChanged = cache.update(@[
      drawText(NodeId(1), "second", vec2(2, 2), rgb(0, 0, 0), style)
    ])
    check textChanged.fullRepaint

  test "published raster revisions invalidate their destination tiles":
    let surface = newRasterSurface(2, 2)
    let cache = newRetainedRasterCanvas(64, 32, tileSize = 16)
    let commands = @[
      drawRasterSurface(NodeId(1), surface, rect(33, 1, 16, 16))
    ]
    discard cache.update(commands)
    surface.updateRegion(
      rasterRegion(0, 0, 1, 1), @[255'u8, 20, 30, 255]
    )
    check surface.publish()
    let changed = cache.update(commands)
    check not changed.fullRepaint
    check changed.dirtyTiles == 1
    check changed.regions == @[rect(32, 0, 16, 16)]
    check cache.image.rgbAt(34, 2)[0] > 0

  test "raster dirty regions honor retained transform and clip scopes":
    let surface = newRasterSurface(4, 4)
    let cache = newRetainedRasterCanvas(128, 64, tileSize = 16)
    let commands = @[
      pushTransform(translationAffine2D(64, 0)),
      pushClip(rect(0, 0, 24, 32)),
      drawRasterSurface(NodeId(1), surface, rect(0, 0, 32, 32)),
      popClip(),
      popTransform()
    ]
    discard cache.update(commands)
    surface.updateRegion(
      rasterRegion(2, 0, 2, 2), newSeq[uint8](2 * 2 * 4)
    )
    check surface.publish()
    let changed = cache.update(commands)
    check not changed.fullRepaint
    check changed.dirtyTiles == 1
    check changed.regions == @[rect(80, 0, 16, 16)]

  test "background changes and invalid targets are handled safely":
    let cache = newRetainedRasterCanvas(32, 32, tileSize = 16)
    discard cache.update(newSeq[PaintCommand]())
    let changed = cache.update(newSeq[PaintCommand](), rgb(0, 0, 0))
    check changed.fullRepaint
    check changed.dirtyTiles == 4
    check cache.image.rgbAt(0, 0) == [0'u8, 0, 0]

    expect ValueError:
      discard RetainedRasterCanvas(nil).update(newSeq[PaintCommand]())
    var invalid: RasterImage
    expect ValueError:
      invalid.renderInto(newSeq[PaintCommand](), rect(0, 0, 1, 1))
