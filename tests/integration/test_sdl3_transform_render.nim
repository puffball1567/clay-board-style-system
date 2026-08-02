import std/[math, options, os, unittest]

import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/core/[color, geometry, node]
import clay_board_style_system/paint/paint_command
import clay_board_style_system/runtime/canvas
import clay_board_style_system/text/[cosmic_text_engine, font_registry]

proc pixel(frame: Sdl3CapturedFrame; x, y: int): tuple[r, g, b: uint8] =
  let offset = (y * frame.width + x) * 3
  (frame.pixels[offset], frame.pixels[offset + 1], frame.pixels[offset + 2])

proc transformedCommands(): seq[PaintCommand] =
  let center = vec2(50, 40)
  let transform =
    translationAffine2D(center.x, center.y) *
    rotationAffine2D(PI.float32 / 4.0'f32) *
    translationAffine2D(-center.x, -center.y)
  result = @[
    pushTransform(transform),
    fillRect(rect(30, 30, 40, 20), rgb(1, 0, 0)),
    popTransform()
  ]
  result.resolveTransformBounds()

proc expectRotatedRedRect(frame: Sdl3CapturedFrame) =
  check frame.width == 100
  check frame.height == 80
  let center = frame.pixel(50, 40)
  check center.r > 220
  check center.g < 25
  check center.b < 25

  # This point is outside the source rectangle but inside the rotated quad.
  # It prevents an ignored transform from satisfying only the center check.
  let rotatedOnly = frame.pixel(43, 22)
  check rotatedOnly.r > 180
  check rotatedOnly.g < 40
  check rotatedOnly.b < 40

  # This point is inside the transformed AABB but outside the rotated quad.
  # A backend that merely paints the AABB would incorrectly make it red.
  let emptyCorner = frame.pixel(30, 20)
  check emptyCorner.r < 25
  check emptyCorner.g < 25
  check emptyCorner.b < 25

suite "SDL3 transform rendering":
  test "affine transform composites a bounded offscreen surface":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    var renderer = initSdl3Renderer("CBSS transform test", 100, 80, false)
    defer: renderer.close()
    var commands = transformedCommands()
    renderer.requestFrameCapture()
    renderer.render(commands, rgb(0, 0, 0))
    check renderer.capturedFrame().isSome
    renderer.capturedFrame().get.expectRotatedRedRect()
    let cachedBytes = renderer.cacheUsage().transformTextureBytes
    check cachedBytes > 0
    renderer.render(commands, rgb(0, 0, 0))
    check renderer.cacheUsage().transformTextureBytes == cachedBytes

  test "layered rendering preserves affine transform scopes":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    var renderer = initSdl3Renderer("CBSS layered transform test", 100, 80, false)
    defer: renderer.close()
    var commands = transformedCommands()
    renderer.requestFrameCapture()
    renderer.renderLayered(
      commands,
      CosmicTextEngine(),
      initFontRegistry(),
      rgb(0, 0, 0)
    )
    check renderer.capturedFrame().isSome
    renderer.capturedFrame().get.expectRotatedRedRect()

  test "affine composition preserves an outer rounded clip":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    let center = vec2(50, 40)
    let transform =
      translationAffine2D(center.x, center.y) *
      rotationAffine2D(10.0'f32 * PI.float32 / 180.0'f32) *
      translationAffine2D(-center.x, -center.y)
    var commands = @[
      pushClip(rect(20, 15, 60, 50), 18),
      pushTransform(transform),
      fillRect(rect(10, 5, 80, 70), rgb(1, 0, 0)),
      popTransform(),
      popClip()
    ]
    commands.resolveTransformBounds()

    var renderer = initSdl3Renderer("CBSS transform clip test", 100, 80, false)
    defer: renderer.close()
    renderer.requestFrameCapture()
    renderer.render(commands, rgb(0, 0, 0))
    check renderer.capturedFrame().isSome
    let frame = renderer.capturedFrame().get
    check frame.pixel(50, 40).r > 220
    let roundedCorner = frame.pixel(21, 16)
    check roundedCorner.r < 25
    check roundedCorner.g < 25
    check roundedCorner.b < 25

  test "nested affine scopes compose without losing local coordinates":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    var commands = @[
      pushTransform(translationAffine2D(20, 5)),
      pushTransform(scaleAffine2D(2, 2)),
      fillRect(rect(10, 10, 10, 10), rgb(1, 0, 0)),
      popTransform(),
      popTransform()
    ]
    commands.resolveTransformBounds()

    var renderer = initSdl3Renderer("CBSS nested transform test", 100, 80, false)
    defer: renderer.close()
    renderer.requestFrameCapture()
    renderer.render(commands, rgb(0, 0, 0))
    check renderer.capturedFrame().isSome
    let frame = renderer.capturedFrame().get
    check frame.pixel(50, 35).r > 220
    check frame.pixel(15, 15).r < 25

  test "retained Canvas transforms reach the SDL composition path":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    let canvas = newCanvas2D()
    canvas.save()
    canvas.translate(20, 0)
    canvas.fillRect(rect(10, 30, 20, 10), rgb(1, 0, 0))
    canvas.restore()
    var commands = canvas.paintCommands(NodeId(1), rect(0, 0, 100, 80))

    var renderer = initSdl3Renderer("CBSS Canvas transform test", 100, 80, false)
    defer: renderer.close()
    renderer.requestFrameCapture()
    renderer.render(commands, rgb(0, 0, 0))
    check renderer.capturedFrame().isSome
    let frame = renderer.capturedFrame().get
    check frame.pixel(40, 35).r > 220
    check frame.pixel(15, 35).r < 25

  test "bounded Canvas layers apply portable composition modes":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    var renderer = initSdl3Renderer("CBSS Canvas layer test", 40, 30, false)
    defer: renderer.close()

    let sourceOverCanvas = newCanvas2D()
    sourceOverCanvas.fillRect(rect(0, 0, 40, 30), rgb(0, 0, 1))
    sourceOverCanvas.beginLayer(rect(10, 5, 20, 20), opacity = 0.5)
    sourceOverCanvas.fillRect(rect(10, 5, 20, 20), rgb(1, 0, 0))
    sourceOverCanvas.endLayer()
    renderer.requestFrameCapture()
    renderer.render(
      sourceOverCanvas.paintCommands(NodeId(1), rect(0, 0, 40, 30)),
      rgb(0, 0, 0)
    )
    let sourceOverFrame = renderer.capturedFrame().get
    let mixed = sourceOverFrame.pixel(20, 15)
    check mixed.r in 120'u8 .. 136'u8
    check mixed.g < 10
    check mixed.b in 120'u8 .. 136'u8
    check sourceOverFrame.pixel(5, 15).b > 240

    let additiveCanvas = newCanvas2D()
    additiveCanvas.fillRect(rect(0, 0, 40, 30), rgb(0, 0, 0.4))
    additiveCanvas.beginLayer(
      rect(10, 5, 20, 20), opacity = 0.5,
      compositeMode = lcmAdditive
    )
    additiveCanvas.fillRect(rect(10, 5, 20, 20), rgb(0.8, 0, 0))
    additiveCanvas.endLayer()
    renderer.requestFrameCapture()
    renderer.render(
      additiveCanvas.paintCommands(NodeId(2), rect(0, 0, 40, 30)),
      rgb(0, 0, 0)
    )
    let additive = renderer.capturedFrame().get.pixel(20, 15)
    check additive.r in 96'u8 .. 112'u8
    check additive.g < 10
    check additive.b in 96'u8 .. 112'u8

    let copyCanvas = newCanvas2D()
    copyCanvas.fillRect(rect(0, 0, 40, 30), rgb(0, 0, 1))
    copyCanvas.beginLayer(
      rect(10, 5, 20, 20), compositeMode = lcmCopy
    )
    copyCanvas.fillRect(rect(15, 10, 5, 5), rgb(0, 1, 0))
    copyCanvas.endLayer()
    renderer.requestFrameCapture()
    renderer.render(
      copyCanvas.paintCommands(NodeId(3), rect(0, 0, 40, 30)),
      rgb(0, 0, 0)
    )
    let copyFrame = renderer.capturedFrame().get
    check copyFrame.pixel(17, 12).g > 240
    let cleared = copyFrame.pixel(25, 15)
    check cleared.r < 10
    check cleared.g < 10
    check cleared.b < 10
    check copyFrame.pixel(5, 15).b > 240

    let emptyCopyCanvas = newCanvas2D()
    emptyCopyCanvas.fillRect(rect(0, 0, 40, 30), rgb(0, 0, 1))
    emptyCopyCanvas.beginLayer(
      rect(10, 5, 20, 20), compositeMode = lcmCopy
    )
    emptyCopyCanvas.endLayer()
    renderer.requestFrameCapture()
    renderer.render(
      emptyCopyCanvas.paintCommands(NodeId(4), rect(0, 0, 40, 30)),
      rgb(0, 0, 0)
    )
    let emptyCopyFrame = renderer.capturedFrame().get
    check emptyCopyFrame.pixel(20, 15) == (0'u8, 0'u8, 0'u8)
    check emptyCopyFrame.pixel(5, 15).b > 240
