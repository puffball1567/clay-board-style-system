import std/[options, os, unittest]

import clay_board_style_system/backends/sdl3/image_loader

const onePixelPpm = "P6\n1 1\n255\n\xFF\x00\x00"

suite "SDL3 image loader":
  test "empty and missing sources fail without an image":
    check loadRgbaImage("").isNone
    check loadRgbaImage("/definitely/missing/cbss-image.png").isNone

  test "CBSS bridge decodes an RGBA8 image":
    let path =
      getTempDir() / ("cbss-image-loader-" & $getCurrentProcessId() & ".ppm")
    writeFile(path, onePixelPpm)
    defer:
      if fileExists(path):
        removeFile(path)

    let loaded = loadRgbaImage(path)
    require loaded.isSome
    check loaded.get.width == 1
    check loaded.get.height == 1
    check loaded.get.pixels == @[255'u8, 0'u8, 0'u8, 255'u8]
