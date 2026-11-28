import std/[math, options, os, tempfiles, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties
import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/backends/ppm/raster as ppm
import clay_board_style_system/core/[color, geometry, node, raster_surface]
import clay_board_style_system/paint/dirty_tiles
import clay_board_style_system/paint/gpu_direct_compositor
import clay_board_style_system/paint/paint_command
import clay_board_style_system/paint/layer_color_filter
import clay_board_style_system/paint/path_geometry
import clay_board_style_system/runtime/motion_scene
import clay_board_style_system/runtime/[motion_scene_timeline, frame_scheduler, animation_clock]
import clay_board_style_system/runtime/canvas
import clay_board_style_system/text/[cosmic_text_engine, font_registry]
import clay_board_style_system/vendor/sdl3

when defined(linux):
  # Give CBSS a logical size independent of the SDL dummy driver's pixel size.
  {.passL: "-Wl,--wrap=SDL_GetWindowSize".}
  var scaledWindow: pointer
  var scaledWidth, scaledHeight: cint

  proc realWindowSize(window: pointer; width, height: ptr cint): bool {.
    importc: "__real_SDL_GetWindowSize", cdecl.}

  proc wrappedWindowSize(window: pointer; width, height: ptr cint): bool {.
    exportc: "__wrap_SDL_GetWindowSize", cdecl.} =
    if scaledWindow.isNil or window != scaledWindow:
      return realWindowSize(window, width, height)
    if not width.isNil: width[] = scaledWidth
    if not height.isNil: height[] = scaledHeight
    true

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
  when defined(linux):
    test "retained SDL rendering uses output pixels across density changes":
      let previousDriver = getEnv("SDL_VIDEODRIVER")
      putEnv("SDL_VIDEODRIVER", "dummy")
      defer:
        if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
        else: delEnv("SDL_VIDEODRIVER")
      var renderer = initSdl3Renderer("CBSS retained density test", 160, 80)
      defer: renderer.close()
      scaledWindow = renderer.window
      scaledWidth = 128
      scaledHeight = 64
      defer: scaledWindow = nil

      let fonts = initFontRegistry()
      let cosmic = CosmicTextEngine()
      let background = rgb(0, 0, 0)
      var commands = [
        fillRect(rect(2, 2, 1, 24), rgb(1, 1, 1)),
        fillRect(rect(106, 51, 6, 8), rgb(0, 1, 0))]
      for step, dimensions in [[160, 80], [256, 128], [161, 81]]:
        if step > 0:
          require SDL3.setWindowSize(renderer.window, cint(dimensions[0]), cint(dimensions[1]))
        check renderer.windowSize() == size(128, 64)
        renderer.requestFrameCapture()
        renderer.render(commands, cosmic, fonts, background)
        let reference = renderer.capturedFrame().get
        check reference.width == dimensions[0]
        check reference.height == dimensions[1]

        renderer.requestFrameCapture()
        renderer.renderLayered(commands, cosmic, fonts, background, rebuildStatic = false)
        let retained = renderer.capturedFrame().get
        check retained.pixels == reference.pixels
        check renderer.retainedLayerStats().fullRepaints == uint64(step + 1)

        if step == 1:
          continue
        commands[1].color = if step == 0: rgb(1, 0, 0) else: rgb(0, 1, 0)
        renderer.requestFrameCapture()
        renderer.renderLayered(commands, cosmic, fonts, background)
        let repainted = renderer.capturedFrame().get
        renderer.requestFrameCapture()
        renderer.render(commands, cosmic, fonts, background)
        check repainted.pixels == renderer.capturedFrame().get.pixels
        check renderer.retainedLayerStats().lastDirtyTiles == (if step == 0: 1 else: 2)

      renderer.renderLayered(commands, cosmic, fonts, background)
      check renderer.retainedLayerStats().lastDirtyTiles == 0

      var event: Sdl3Event
      while renderer.pollEvent(event): discard
      var scaleChange: SDL_Event
      scaleChange.window = SDL_WindowEvent(
        `type`: SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED, windowID: SDL3.getWindowID(renderer.window))
      require SDL3.pushEvent(addr scaleChange)
      require renderer.pollEvent(event)
      check event.kind == sekExpose

    test "software layer composition reads and writes native output pixels":
      let previousDriver = getEnv("SDL_VIDEODRIVER")
      putEnv("SDL_VIDEODRIVER", "dummy")
      defer:
        if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
        else: delEnv("SDL_VIDEODRIVER")

      let cosmic = CosmicTextEngine()
      let fonts = initFontRegistry()
      let background = rgb(0, 0, 0)
      let bounds = rect(24, 16, 64, 24)
      let leftBounds = rect(24, 16, 32, 24)
      var commands = @[
        fillRect(rect(24, 16, 16, 24), rgb(0, 1, 0)),
        fillRect(rect(40, 16, 48, 24), rgb(0, 0, 1)),
        pushClip(bounds, radius = 8),
        pushLayer(bounds, opacity = 0.5),
        pushLayer(leftBounds),
        fillRect(leftBounds, rgb(1, 0, 0)),
        popLayer(),
        fillRect(rect(56, 16, 32, 24), rgb(1, 0, 0)),
        popLayer(),
        fillRect(rect(18, 30, 10, 4), rgb(1, 1, 1)),
        popClip(),
        fillRect(rect(104, 48, 8, 8), rgb(1, 1, 0))]

      for dimensions in [[128, 64], [160, 88], [256, 128]]:
        var renderer = initSdl3Renderer("CBSS software layer density test",
          dimensions[0], dimensions[1], false)
        defer: renderer.close()
        require $SDL3.getRendererName(renderer.renderer) == "software"
        scaledWindow = renderer.window
        scaledWidth = 128
        scaledHeight = 64
        defer: scaledWindow = nil

        proc at(frame: Sdl3CapturedFrame; x, y: int): tuple[r, g, b: uint8] =
          frame.pixel(x * dimensions[0] div 128, y * dimensions[1] div 64)

        commands[5].color = rgb(1, 0, 0)
        renderer.requestFrameCapture()
        renderer.render(commands, background)
        let immediate = renderer.capturedFrame().get
        let greenHalf = immediate.at(32, 24)
        check greenHalf.r in 127'u8 .. 128'u8
        check greenHalf.g in 127'u8 .. 128'u8
        check greenHalf.b == 0
        let blueHalf = immediate.at(48, 24)
        check blueHalf.r in 127'u8 .. 128'u8
        check blueHalf.g == 0
        check blueHalf.b in 127'u8 .. 128'u8
        check immediate.at(24, 16) == (0'u8, 255'u8, 0'u8)
        check immediate.at(23, 24) == (0'u8, 0'u8, 0'u8)
        check immediate.at(88, 24) == (0'u8, 0'u8, 0'u8)
        check immediate.at(21, 31) == (0'u8, 0'u8, 0'u8)
        check immediate.at(26, 31) == (255'u8, 255'u8, 255'u8)
        check immediate.at(108, 52) == (255'u8, 255'u8, 0'u8)

        renderer.requestFrameCapture()
        renderer.renderLayered(commands, cosmic, fonts, background)
        let retainedMatches = renderer.capturedFrame().get.pixels == immediate.pixels
        check retainedMatches

        commands[5].color = rgb(0, 1, 0)
        renderer.requestFrameCapture()
        renderer.renderLayered(commands, cosmic, fonts, background)
        let repainted = renderer.capturedFrame().get
        check renderer.retainedLayerStats().lastDirtyTiles == 1
        check renderer.retainedLayerStats().partialRepaints == 1
        renderer.requestFrameCapture()
        renderer.render(commands, background)
        let partialMatches = renderer.capturedFrame().get.pixels == repainted.pixels
        check partialMatches
        let updated = repainted.at(48, 24)
        check updated.r == 0
        check updated.g in 127'u8 .. 128'u8
        check updated.b in 127'u8 .. 128'u8
        check repainted.at(76, 24) == immediate.at(76, 24)
        check repainted.at(108, 52) == (255'u8, 255'u8, 0'u8)

  test "rounded file images preserve layer coordinates and alpha across cache reuse":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")
    let tempDir = createTempDir("cbss-rounded-image-", "")
    defer: removeDir(tempDir)
    let source = tempDir / "translucent.pam"
    # A straight RGBA source with half-alpha red.
    writeFile(source, "P7\nWIDTH 1\nHEIGHT 1\nDEPTH 4\nMAXVAL 255\n" &
      "TUPLTYPE RGB_ALPHA\nENDHDR\n\xFF\x00\x00\x80")

    const densities = when defined(linux): [1.0'f32, 1.25, 1.30, 2.0] else: [1.0'f32]
    for density in densities:
      proc outputPixel(position: int): int =
        int(round(position.float32 * density))

      var renderer = initSdl3Renderer("CBSS rounded image layer test",
        outputPixel(96), outputPixel(64), false)
      defer: renderer.close()
      when defined(linux):
        scaledWindow = renderer.window
        scaledWidth = 96
        scaledHeight = 64
        defer: scaledWindow = nil

      let style = ComputedImageStyle(imageRendering: irCrispEdges)
      var commands = @[
        pushTransform(translationAffine2D(20, 12)),
        pushClip(rect(4, 4, 16, 16), radius = 8),
        drawImage(NodeId(1), source, rect(4, 4, 16, 16), 1, style),
        popClip(),
        fillRect(rect(28, 4, 6, 6), rgb(0, 1, 0)),
        popTransform(),
        drawImage(NodeId(2), source, rect(64, 16, 16, 16), 0.5, style)]
      commands.resolveTransformBounds()
      let background = rgb(0, 0, 1)
      renderer.requestFrameCapture()
      renderer.render(commands, background)
      let cold = renderer.capturedFrame().get
      let center = cold.pixel(outputPixel(32), outputPixel(24))
      check center.r in 127'u8 .. 129'u8
      check center.g == 0
      check center.b in 126'u8 .. 128'u8
      check cold.pixel(outputPixel(24), outputPixel(16)) == (0'u8, 0'u8, 255'u8)
      check cold.pixel(outputPixel(50), outputPixel(18)) == (0'u8, 255'u8, 0'u8)
      let unrounded = cold.pixel(outputPixel(70), outputPixel(22))
      check unrounded.r in 63'u8 .. 65'u8
      check unrounded.g == 0
      check unrounded.b in 190'u8 .. 192'u8
      let textureExtent = ceil(16.0'f32 * density).uint64
      check renderer.cacheUsage().roundedTextureBytes == 4 * textureExtent * textureExtent
      renderer.requestFrameCapture()
      renderer.render(commands, background)
      let warm = renderer.capturedFrame().get
      let samePixels = cold.pixels == warm.pixels
      check samePixels

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

  test "readback raster pixels survive an SDL texture-backed transform":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    let surface = newRasterSurface(2, 2, [255'u8, 0'u8, 0'u8, 255'u8])
    var commands = @[
      pushTransform(translationAffine2D(10, 8)),
      drawRasterSurface(NodeId(1), surface, rect(0, 0, 12, 12)),
      popTransform()
    ]
    commands.resolveTransformBounds()
    var renderer = initSdl3Renderer("CBSS GPU fallback layer test", 32, 32, false)
    defer: renderer.close()
    renderer.requestFrameCapture()
    renderer.render(commands, rgb(0, 0, 0))
    check renderer.capturedFrame().isSome
    let frame = renderer.capturedFrame().get
    check frame.pixel(14, 12).r > 220
    check frame.pixel(14, 12).g < 25
    check frame.pixel(4, 4).r < 25

  test "GPU direct command paints its raster fallback in an SDL offscreen layer":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    let surface = newRasterSurface(2, 2, [0'u8, 255'u8, 0'u8, 255'u8])
    var commands = @[
      pushTransform(translationAffine2D(10, 8)),
      PaintCommand(
        kind: pcDrawGpuDirectSurface, owner: some(NodeId(1)),
        gpuFallbackSurface: surface,
        gpuSurfaceRect: rect(0, 0, 12, 12),
        gpuSurfaceOpacity: 1.0'f32
      ),
      popTransform()
    ]
    commands.resolveTransformBounds()
    var renderer = initSdl3Renderer("CBSS hybrid GPU layer test", 64, 32, false)
    defer: renderer.close()
    renderer.requestFrameCapture()
    renderer.render(commands, rgb(0, 0, 0))
    check renderer.gpuDirectCompositionStats().unsupported == 1
    check renderer.capturedFrame().isSome
    let frame = renderer.capturedFrame().get
    check frame.pixel(14, 12).g > 220
    check frame.pixel(14, 12).r < 25
    check frame.pixel(4, 4).g < 25
    renderer.requestFrameCapture()
    renderer.renderLayered(commands, CosmicTextEngine(), initFontRegistry(),
      rgb(0, 0, 0))
    check renderer.capturedFrame().isSome
    check renderer.capturedFrame().get.pixel(14, 12).g > 220

    surface.updateRegion(rasterRegion(0, 0, 2, 2), [
      0'u8, 0, 255, 255, 0, 0, 255, 255,
      0, 0, 255, 255, 0, 0, 255, 255])
    check surface.publish()
    renderer.requestFrameCapture()
    renderer.renderLayered(commands, CosmicTextEngine(), initFontRegistry(),
      rgb(0, 0, 0))
    let updated = renderer.capturedFrame().get
    check updated.pixel(14, 12) == (0'u8, 0'u8, 255'u8)
    check updated.pixel(4, 4) == (0'u8, 0'u8, 0'u8)
    check renderer.retainedLayerStats().partialRepaints == 1
    check renderer.retainedLayerStats().lastDirtyTiles == 1

    renderer.renderLayered(commands, CosmicTextEngine(), initFontRegistry(),
      rgb(0, 0, 0))
    check renderer.retainedLayerStats().skippedRepaints == 1

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

  test "rounded affine clips preserve sampling and composition bounds":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    when defined(cbssTestSdlOpenGl):
      putEnv("SDL_VIDEODRIVER", "x11")
    else:
      putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")

    const outputSizes =
      when defined(linux): [[128, 64], [166, 86], [256, 128]]
      else: [[128, 64]]
    let bounds = rect(24, 16, 72, 32)
    let clip = rect(20, 12, 88, 40)
    let radius = 14.0'f32
    let background = rgb(0, 0, 1)
    let marker = fillRect(rect(114, 4, 8, 8), rgb(1, 1, 0))
    let transform = translationAffine2D(60.25, 32.75) *
      rotationAffine2D(PI.float32 / 12.0'f32) *
      translationAffine2D(-60, -32)
    for dimensions in outputSizes:
      var renderer = initSdl3Renderer("CBSS affine rounded clip test",
        dimensions[0], dimensions[1], false)
      defer: renderer.close()
      when defined(cbssTestSdlOpenGl):
        require $SDL3.getRendererName(renderer.renderer) == "opengl"
      when defined(linux):
        scaledWindow = renderer.window
        scaledWidth = 128
        scaledHeight = 64
        defer: scaledWindow = nil
      let sx = dimensions[0].float32 / 128.0'f32
      let sy = dimensions[1].float32 / 64.0'f32
      for mode in LayerCompositeMode:
        var commands = @[pushClip(clip)]
        if mode == lcmSourceOver:
          commands.add pushTransform(transform)
          commands.add fillRect(rect(24, 16, 23, 32), rgba(1, 0, 0, 0.5))
          commands.add fillRect(rect(47, 16, 49, 32), rgba(0, 1, 0, 0.75))
          commands.add popTransform()
        else:
          commands.add pushLayer(bounds, opacity = 0.75, compositeMode = mode)
          commands.add fillRect(bounds, rgb(1, 0, 0))
          commands.add popLayer()
        commands.add popClip()
        commands.add marker
        commands.resolveTransformBounds()

        renderer.requestFrameCapture()
        renderer.render(commands, background)
        let reference = renderer.capturedFrame().get
        commands[0].clipRadius = radius
        renderer.requestFrameCapture()
        renderer.render(commands, background)
        let clipped = renderer.capturedFrame().get

        var mismatchedPixels = 0
        for y in floor(clip.y * sy).int ..< ceil((clip.y + clip.h) * sy).int:
          for x in floor(clip.x * sx).int ..< ceil((clip.x + clip.w) * sx).int:
            let px = (x.float32 + 0.5'f32) / sx
            let py = (y.float32 + 0.5'f32) / sy
            let dx = px - clamp(px, clip.x + radius, clip.x + clip.w - radius)
            let dy = py - clamp(py, clip.y + radius, clip.y + clip.h - radius)
            let expected =
              if dx * dx + dy * dy <= radius * radius: reference.pixel(x, y)
              else: (0'u8, 0'u8, 255'u8)
            if clipped.pixel(x, y) != expected:
              inc mismatchedPixels
        checkpoint("composite mode " & $mode & " at " & $dimensions)
        check mismatchedPixels == 0
        check clipped.pixel((118.0'f32 * sx).int, (8.0'f32 * sy).int) ==
          (255'u8, 255'u8, 0'u8)

  test "rounded texture clips preserve text gradient and shadow sampling":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    when defined(cbssTestSdlOpenGl):
      putEnv("SDL_VIDEODRIVER", "x11")
    else:
      putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")

    let fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer: cosmic.close()
    let clip = rect(16, 12, 96, 40)
    let radius = 14.0'f32
    let black = rgb(0, 0, 0)
    let decorationBounds = rect(10.25, 8.75, 106.5, 48.5)
    let fixtures = [
      drawText(NodeId(1), "MMMMMMMMMM", vec2(16, 0), rgb(1, 1, 1),
        ComputedTextStyle(fontSize: some(32.0'f32),
          fontFamilies: @["sans-serif"], whiteSpace: some(wsNoWrap)),
        some(70.0'f32)),
      fillLinearGradient(decorationBounds, LinearGradient(angle: 0, stops: @[
        GradientStop(color: rgba(1, 0, 0, 0.5), offset: 0),
        GradientStop(color: rgba(0, 1, 0, 0.75), offset: 100)])),
      drawBoxShadow(rect(22.25, 18.5, 84.5, 29), rgba(1, 0.5, 0, 0.75),
        offsetX = 0, offsetY = 0, blur = 10, spread = 0)]

    const outputSizes =
      when defined(linux): [[128, 64], [166, 86], [256, 128]]
      else: [[128, 64]]
    for dimensions in outputSizes:
      var renderer = initSdl3Renderer("CBSS rounded texture clip test",
        dimensions[0], dimensions[1], false)
      defer: renderer.close()
      when defined(cbssTestSdlOpenGl):
        require $SDL3.getRendererName(renderer.renderer) == "opengl"
      else:
        require $SDL3.getRendererName(renderer.renderer) == "software"
      when defined(linux):
        scaledWindow = renderer.window
        scaledWidth = 128
        scaledHeight = 64
        defer: scaledWindow = nil
      let sx = dimensions[0].float32 / 128.0'f32
      let sy = dimensions[1].float32 / 64.0'f32
      for fixture in fixtures:
        var commands = @[pushClip(clip), fixture, popClip(),
          fillRect(rect(116, 4, 8, 8), rgb(1, 1, 0))]
        renderer.requestFrameCapture()
        renderer.render(commands, cosmic, fonts, black)
        let reference = renderer.capturedFrame().get
        commands[0].clipRadius = radius
        renderer.requestFrameCapture()
        renderer.render(commands, cosmic, fonts, black)
        let clipped = renderer.capturedFrame().get
        var maxInteriorError, leakedPixels, visiblePixels, clippedPixels, leakedTextPixels: int
        let textRight = floor(16.0'f32 * sx).int + ceil(70.0'f32 * sx).int
        for y in floor(clip.y * sy).int ..< ceil((clip.y + clip.h) * sy).int:
          for x in floor(clip.x * sx).int ..< ceil((clip.x + clip.w) * sx).int:
            let px = (x.float32 + 0.5'f32) / sx
            let py = (y.float32 + 0.5'f32) / sy
            let dx = px - clamp(px, clip.x + radius, clip.x + clip.w - radius)
            let dy = py - clamp(py, clip.y + radius, clip.y + clip.h - radius)
            let referencePixel = reference.pixel(x, y)
            let inside = dx * dx + dy * dy <= radius * radius
            if referencePixel != (0'u8, 0'u8, 0'u8):
              if inside: inc visiblePixels
              else: inc clippedPixels
            let actual = clipped.pixel(x, y)
            if inside:
              maxInteriorError = max(maxInteriorError, max(
                abs(actual.r.int - referencePixel.r.int), max(
                abs(actual.g.int - referencePixel.g.int), abs(actual.b.int - referencePixel.b.int))))
            elif actual != (0'u8, 0'u8, 0'u8):
              inc leakedPixels
            if fixture.kind == pcDrawText and x >= textRight and
                actual != (0'u8, 0'u8, 0'u8):
              inc leakedTextPixels
        checkpoint($fixture.kind & " at " & $dimensions)
        check visiblePixels > 0
        check clippedPixels > 0
        when defined(cbssTestSdlOpenGl):
          check maxInteriorError == 0
        else:
          check maxInteriorError <= 1
        check leakedPixels == 0
        check leakedTextPixels == 0
        check clipped.pixel((120.0'f32 * sx).int, (8.0'f32 * sy).int) ==
          (255'u8, 255'u8, 0'u8)

        if fixture.kind == pcFillLinearGradient:
          commands.insert(fillRect(rect(24, 20, 12, 12), rgb(0, 0, 1)), 0)
          renderer.renderLayered(commands, cosmic, fonts, black)
          commands[0].color = rgb(1, 0, 1)
          renderer.requestFrameCapture()
          renderer.renderLayered(commands, cosmic, fonts, black)
          let repainted = renderer.capturedFrame().get
          check renderer.retainedLayerStats().lastDirtyTiles == 1
          renderer.requestFrameCapture()
          renderer.render(commands, cosmic, fonts, black)
          let matches = repainted.pixels == renderer.capturedFrame().get.pixels
          check matches

  test "rounded gradient repeats match rectangular sampling and retained damage":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    when defined(cbssTestSdlOpenGl):
      putEnv("SDL_VIDEODRIVER", "x11")
    else:
      putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")

    const outputSizes =
      when defined(linux): [[128, 64], [166, 86], [256, 128]]
      else: [[128, 64]]
    let clip = rect(16, 12, 96, 40)
    let tile = rect(12.75, 9.5, 29.25, 19.75)
    let roundRadius = 14.0'f32
    let gradient = LinearGradient(angle: 45, stops: @[
      GradientStop(color: rgba(1, 0, 0, 0.5), offset: 0),
      GradientStop(color: rgba(0, 1, 0, 0.75), offset: 100)])
    let background = rgb(0, 0, 1)
    let fonts = initFontRegistry()
    let cosmic = CosmicTextEngine()
    for dimensions in outputSizes:
      var renderer = initSdl3Renderer("CBSS rounded gradient repeat test",
        dimensions[0], dimensions[1], false)
      defer: renderer.close()
      when defined(cbssTestSdlOpenGl):
        require $SDL3.getRendererName(renderer.renderer) == "opengl"
      when defined(linux):
        scaledWindow = renderer.window
        scaledWidth = 128
        scaledHeight = 64
        defer: scaledWindow = nil
      let sx = dimensions[0].float32 / 128.0'f32
      let sy = dimensions[1].float32 / 64.0'f32
      for repeat in [bgRepeat, bgRepeatX, bgRepeatY]:
        let paintBounds =
          case repeat
          of bgRepeatX: rect(clip.x, tile.y, clip.w, tile.h)
          of bgRepeatY: rect(tile.x, clip.y, tile.w, clip.h)
          else: clip
        var commands = @[
          fillLinearGradient(tile, gradient, paintRect = some(paintBounds),
            clipRect = some(clip), repeat = repeat),
          fillRect(rect(116, 4, 8, 8), rgb(1, 1, 0))]
        renderer.requestFrameCapture()
        renderer.render(commands, background)
        let reference = renderer.capturedFrame().get
        commands[0].gradientRadius = roundRadius
        renderer.requestFrameCapture()
        renderer.render(commands, background)
        let rounded = renderer.capturedFrame().get

        var maxInteriorError, leakedPixels, visiblePixels, clippedPixels: int
        for y in floor(clip.y * sy).int ..< ceil((clip.y + clip.h) * sy).int:
          for x in floor(clip.x * sx).int ..< ceil((clip.x + clip.w) * sx).int:
            let px = (x.float32 + 0.5'f32) / sx
            let py = (y.float32 + 0.5'f32) / sy
            let dx = px - clamp(px, clip.x + roundRadius, clip.x + clip.w - roundRadius)
            let dy = py - clamp(py, clip.y + roundRadius, clip.y + clip.h - roundRadius)
            let inside = dx * dx + dy * dy <= roundRadius * roundRadius
            let original = reference.pixel(x, y)
            if original != (0'u8, 0'u8, 255'u8):
              if inside: inc visiblePixels
              else: inc clippedPixels
            let actual = rounded.pixel(x, y)
            if inside:
              maxInteriorError = max(maxInteriorError, max(
                abs(actual.r.int - original.r.int), max(
                abs(actual.g.int - original.g.int), abs(actual.b.int - original.b.int))))
            elif actual != (0'u8, 0'u8, 255'u8):
              inc leakedPixels
        checkpoint($repeat & " at " & $dimensions)
        check visiblePixels > 0
        check clippedPixels > 0
        when defined(cbssTestSdlOpenGl):
          check maxInteriorError == 0
        else:
          check maxInteriorError <= 1
        check leakedPixels == 0
        check rounded.pixel((120.0'f32 * sx).int, (8.0'f32 * sy).int) ==
          (255'u8, 255'u8, 0'u8)

        commands.insert(fillRect(rect(25, 18, 10, 8), rgb(1, 0, 0)), 0)
        renderer.renderLayered(commands, cosmic, fonts, background)
        commands[0].color = rgb(1, 0, 1)
        renderer.requestFrameCapture()
        renderer.renderLayered(commands, cosmic, fonts, background)
        let repainted = renderer.capturedFrame().get
        check renderer.retainedLayerStats().lastDirtyTiles == 1
        renderer.requestFrameCapture()
        renderer.render(commands, background)
        let matches = repainted.pixels == renderer.capturedFrame().get.pixels
        check matches

  test "rounded solid backgrounds blend once per output pixel":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    when defined(cbssTestSdlOpenGl):
      putEnv("SDL_VIDEODRIVER", "x11")
    else:
      putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")

    const outputSizes =
      when defined(linux): [[128, 64], [166, 86], [256, 128]]
      else: [[128, 64]]
    let clip = rect(16, 12, 96, 40)
    let bounds = rect(8, 8, 112, 48)
    let halfPixelBounds = rect(8.25, 18.25, 112, 28)
    let radius = 14.0'f32
    let background = rgb(0, 0, 1)
    let tinted = rgba(1, 0, 0, 0.5)
    let fonts = initFontRegistry()
    let cosmic = CosmicTextEngine()
    let fixtures = [
      fillRect(bounds, tinted),
      fillRect(bounds, tinted, radius = 16),
      fillLinearGradient(bounds, LinearGradient(stops: @[
        GradientStop(color: tinted, offset: 0)]), repeat = bgRepeat),
      fillRect(halfPixelBounds, tinted)]

    for dimensions in outputSizes:
      var renderer = initSdl3Renderer("CBSS rounded background test",
        dimensions[0], dimensions[1], false)
      defer: renderer.close()
      when defined(cbssTestSdlOpenGl):
        require $SDL3.getRendererName(renderer.renderer) == "opengl"
      when defined(linux):
        scaledWindow = renderer.window
        scaledWidth = 128
        scaledHeight = 64
        defer: scaledWindow = nil
      let sx = dimensions[0].float32 / 128.0'f32
      let sy = dimensions[1].float32 / 64.0'f32
      for index, command in fixtures:
        var commands = @[pushClip(clip), command, popClip(),
          fillRect(rect(116, 4, 8, 8), rgb(1, 1, 0))]
        renderer.requestFrameCapture()
        renderer.render(commands, background)
        let reference = renderer.capturedFrame().get
        commands[0].clipRadius = radius
        renderer.requestFrameCapture()
        renderer.render(commands, background)
        let rounded = renderer.capturedFrame().get

        var errors, insidePixels, clippedPixels: int
        let center = reference.pixel((64.0'f32 * sx).int, (32.0'f32 * sy).int)
        for y in floor(clip.y * sy).int ..< ceil((clip.y + clip.h) * sy).int:
          for x in floor(clip.x * sx).int ..< ceil((clip.x + clip.w) * sx).int:
            let px = (x.float32 + 0.5'f32) / sx
            let py = (y.float32 + 0.5'f32) / sy
            let dx = px - clamp(px, clip.x + radius, clip.x + clip.w - radius)
            let dy = py - clamp(py, clip.y + radius, clip.y + clip.h - radius)
            let inside = dx * dx + dy * dy <= radius * radius
            let expected =
              if not inside: (0'u8, 0'u8, 255'u8)
              elif defined(cbssTestSdlOpenGl) and index == fixtures.high:
                if py >= halfPixelBounds.y and py < halfPixelBounds.y + halfPixelBounds.h:
                  center
                else:
                  (0'u8, 0'u8, 255'u8)
              else:
                reference.pixel(x, y)
            if rounded.pixel(x, y) != expected:
              inc errors
            if reference.pixel(x, y) != (0'u8, 0'u8, 255'u8):
              if inside: inc insidePixels
              else: inc clippedPixels
        checkpoint("solid fill " & $index & " at " & $dimensions)
        check insidePixels > 0
        check clippedPixels > 0
        check errors == 0
        let middle = rounded.pixel((64.0'f32 * sx).int, (32.0'f32 * sy).int)
        check middle.r in 127'u8 .. 128'u8
        check middle.g == 0
        check middle.b in 126'u8 .. 128'u8
        for row in (20.0'f32 * sy).int .. (44.0'f32 * sy).int:
          check rounded.pixel((64.0'f32 * sx).int, row) == middle
        check rounded.pixel((120.0'f32 * sx).int, (8.0'f32 * sy).int) ==
          (255'u8, 255'u8, 0'u8)

        commands.insert(fillRect(rect(24, 20, 12, 12), rgb(0, 1, 0)), 0)
        renderer.renderLayered(commands, cosmic, fonts, background)
        commands[0].color = rgb(1, 0, 1)
        renderer.requestFrameCapture()
        renderer.renderLayered(commands, cosmic, fonts, background)
        let repainted = renderer.capturedFrame().get
        check renderer.retainedLayerStats().lastDirtyTiles == 1
        renderer.requestFrameCapture()
        renderer.render(commands, background)
        let matches = repainted.pixels == renderer.capturedFrame().get.pixels
        check matches

  test "translucent borders keep output pixel coverage and retained damage":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    when defined(cbssTestSdlOpenGl):
      putEnv("SDL_VIDEODRIVER", "x11")
    else:
      putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")

    proc coveredWidth(box: Rect; radius, y, left, right: float32): float32 =
      if box.w <= 0 or box.h <= 0 or y < box.y or y >= box.y + box.h:
        return 0
      let dy = y - clamp(y, box.y + radius, box.y + box.h - radius)
      let halfChord = sqrt(max(0.0'f32, radius * radius - dy * dy))
      let start = box.x + radius - halfChord
      let stop = box.x + box.w - radius + halfChord
      max(0.0'f32, min(right, stop) - max(left, start))

    const outputSizes =
      when defined(linux): [[128, 64], [166, 86], [256, 128]]
      else: [[128, 64]]
    let bounds = rect(12.25, 10.25, 103.5, 43.5)
    let clip = rect(16, 12, 96, 40)
    let clipRadius = 12.0'f32
    let background = rgb(0, 0, 1)
    let translucent = rgba(1, 0, 0, 0.5)
    let fonts = initFontRegistry()
    let cosmic = CosmicTextEngine()
    let fixtures = [
      strokeRect(bounds, translucent, width = 6.125),
      strokeRect(bounds, translucent, width = 6.125),
      strokeRect(bounds, translucent, width = 6.25, radius = 16),
      strokeRect(rect(61.25, 26.25, 4.5, 12), translucent, width = 2),
      strokeRect(rect(54, 28, 20, 8), translucent, width = 6, radius = 4)]

    for dimensions in outputSizes:
      var renderer = initSdl3Renderer("CBSS scaled border test",
        dimensions[0], dimensions[1], false)
      defer: renderer.close()
      when defined(cbssTestSdlOpenGl):
        require $SDL3.getRendererName(renderer.renderer) == "opengl"
      when defined(linux):
        scaledWindow = renderer.window
        scaledWidth = 128
        scaledHeight = 64
        defer: scaledWindow = nil
      let sx = dimensions[0].float32 / 128.0'f32
      let sy = dimensions[1].float32 / 64.0'f32
      for index, command in fixtures:
        let outer = command.strokeRect
        let width = command.strokeWidth
        let inner = rect(outer.x + width, outer.y + width,
          outer.w - 2 * width, outer.h - 2 * width)
        let innerRadius = max(0.0'f32, command.strokeRadius - width)
        var commands =
          if index == 0: @[command]
          else: @[pushClip(clip, clipRadius), command, popClip()]
        commands.add fillRect(rect(116, 2, 8, 4), rgb(1, 1, 0))
        renderer.requestFrameCapture()
        renderer.render(commands, background)
        let frame = renderer.capturedFrame().get

        var mismatches, paintedPixels, edgePixels: int
        for y in floor(8 * sy).int ..< ceil(58 * sy).int:
          let py = (y.float32 + 0.5'f32) / sy
          for x in 0 ..< dimensions[0]:
            let px = (x.float32 + 0.5'f32) / sx
            let dx = px - clamp(px, clip.x + clipRadius, clip.x + clip.w - clipRadius)
            let dy = py - clamp(py, clip.y + clipRadius, clip.y + clip.h - clipRadius)
            var coverage = 0.0'f32
            if index == 0 or dx * dx + dy * dy <= clipRadius * clipRadius:
              let left = x.float32 / sx
              let right = (x.float32 + 1) / sx
              coverage = (coveredWidth(outer, command.strokeRadius, py, left, right) -
                coveredWidth(inner, innerRadius, py, left, right)) * sx
            if coverage > 0.99'f32: inc paintedPixels
            elif coverage > 0.02'f32: inc edgePixels
            let expected = round(clamp(coverage, 0.0'f32, 1.0'f32) * 127.5'f32).int
            let actual = frame.pixel(x, y)
            if abs(actual.r.int - expected) > 2 or actual.g != 0 or
                abs(actual.b.int - (255 - expected)) > 2:
              inc mismatches
        checkpoint("border " & $index & " at " & $dimensions)
        check paintedPixels > 0
        check edgePixels > 0
        check mismatches == 0
        check frame.pixel((120 * sx).int, (4 * sy).int) == (255'u8, 255'u8, 0'u8)

        commands.insert(fillRect(rect(20, 24, 43, 9), rgb(0, 1, 0)), 0)
        renderer.renderLayered(commands, cosmic, fonts, background)
        commands[0].color = rgb(1, 0, 1)
        renderer.requestFrameCapture()
        renderer.renderLayered(commands, cosmic, fonts, background)
        let repainted = renderer.capturedFrame().get
        check renderer.retainedLayerStats().lastDirtyTiles == 1
        renderer.requestFrameCapture()
        renderer.render(commands, background)
        check repainted.pixels == renderer.capturedFrame().get.pixels

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

  test "retained filled paths reach the SDL composition path":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    var path = path2D([
      vec2(5, 5), vec2(35, 5), vec2(35, 35), vec2(5, 35)
    ], closed = true)
    path.moveTo(vec2(15, 15))
    path.lineTo(vec2(25, 15))
    path.lineTo(vec2(25, 25))
    path.lineTo(vec2(15, 25))
    path.closePath()
    let commands = @[fillPath(path, rgb(1, 0, 0), pfrEvenOdd)]

    var renderer = initSdl3Renderer("CBSS filled path test", 40, 40, false)
    defer: renderer.close()
    renderer.requestFrameCapture()
    renderer.render(commands, rgb(0, 0, 0))
    check renderer.capturedFrame().isSome
    let frame = renderer.capturedFrame().get
    check frame.pixel(10, 10).r > 220
    check frame.pixel(20, 20).r < 25
    check frame.pixel(2, 2).r < 25

  test "filled and stroked paths sample output pixels under rounded clips":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    when defined(cbssTestSdlOpenGl):
      putEnv("SDL_VIDEODRIVER", "x11")
    else:
      putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")

    const outputSizes =
      when defined(linux): [[128, 64], [166, 86], [256, 128]]
      else: [[128, 64]]
    let clip = rect(16, 12, 96, 40)
    let radius = 14.0'f32
    let background = rgb(0, 0, 1)
    let translucent = rgba(1, 0, 0, 0.5)
    let fonts = initFontRegistry()
    let cosmic = CosmicTextEngine()
    var path = path2D([vec2(8, 8), vec2(120, 8), vec2(120, 56), vec2(8, 56)],
      closed = true)
    path.moveTo(vec2(47.5, 23.5))
    path.lineTo(vec2(83.25, 28.75))
    path.lineTo(vec2(59.75, 43.25))
    path.closePath()
    let fixtures = [fillPath(path, translucent, pfrEvenOdd),
      strokePath([vec2(10.25, 17), vec2(64, 40.5), vec2(117.75, 19)],
        translucent, width = 11, lineJoin = sljRound)]

    for dimensions in outputSizes:
      var renderer = initSdl3Renderer("CBSS scaled path test",
        dimensions[0], dimensions[1], false)
      defer: renderer.close()
      when defined(cbssTestSdlOpenGl):
        require $SDL3.getRendererName(renderer.renderer) == "opengl"
      when defined(linux):
        scaledWindow = renderer.window
        scaledWidth = 128
        scaledHeight = 64
        defer: scaledWindow = nil
      let sx = dimensions[0].float32 / 128.0'f32
      let sy = dimensions[1].float32 / 64.0'f32
      for command in fixtures:
        let (shape, rule) =
          if command.kind == pcFillPath: (command.fillPathValue, pfrEvenOdd)
          else: (command.pathOutline, pfrNonZero)
        let contours = shape.transformed(scaleAffine2D(sx, sy)).flattened()
        var commands = @[pushClip(clip, radius), command, popClip(),
          fillRect(rect(116, 4, 8, 8), rgb(1, 1, 0))]
        renderer.requestFrameCapture()
        renderer.render(commands, background)
        let full = renderer.capturedFrame().get

        var mismatches, solidPixels, edgePixels, maskedPixels: int
        for y in floor((clip.y - 1) * sy).int ..< ceil((clip.y + clip.h + 1) * sy).int:
          for x in floor((clip.x - 1) * sx).int ..< ceil((clip.x + clip.w + 1) * sx).int:
            let px = (x.float32 + 0.5'f32) / sx
            let py = (y.float32 + 0.5'f32) / sy
            let dx = px - clamp(px, clip.x + radius, clip.x + clip.w - radius)
            let dy = py - clamp(py, clip.y + radius, clip.y + clip.h - radius)
            let insideClip = dx * dx + dy * dy <= radius * radius
            var samples = 0
            for offsetY in [0.25'f32, 0.75'f32]:
              for offsetX in [0.25'f32, 0.75'f32]:
                if contours.contains(vec2(x.float32 + offsetX, y.float32 + offsetY), rule):
                  inc samples
            if not insideClip and samples > 0:
              inc maskedPixels
              samples = 0
            if samples == 4: inc solidPixels
            elif samples > 0: inc edgePixels
            let actual = full.pixel(x, y)
            let red = round(127.5'f32 * samples.float32 / 4.0'f32).int
            if abs(actual.r.int - red) > 2 or actual.g != 0 or
                abs(actual.b.int - (255 - red)) > 2:
              inc mismatches
        checkpoint($command.kind & " at " & $dimensions)
        check solidPixels > 0
        check edgePixels > 0
        check maskedPixels > 0
        check mismatches == 0
        check full.pixel((120.0'f32 * sx).int, (8.0'f32 * sy).int) ==
          (255'u8, 255'u8, 0'u8)

        commands.insert(fillRect(rect(24, 20, 12, 12), rgb(0, 1, 0)), 0)
        renderer.renderLayered(commands, cosmic, fonts, background)
        commands[0].color = rgb(1, 0, 1)
        renderer.requestFrameCapture()
        renderer.renderLayered(commands, cosmic, fonts, background)
        let repainted = renderer.capturedFrame().get
        check renderer.retainedLayerStats().lastDirtyTiles == 1
        renderer.requestFrameCapture()
        renderer.render(commands, background)
        check repainted.pixels == renderer.capturedFrame().get.pixels

  test "rounded raster surfaces and GPU fallbacks preserve scaled source rows":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")

    const outputSizes = when defined(linux): [[128, 64], [160, 88], [166, 86], [256, 128]]
      else: [[128, 64]]
    let cosmic = CosmicTextEngine()
    let fonts = initFontRegistry()
    let background = rgb(0, 0, 1)
    let rasterBounds = rect(8, 8, 32, 32)
    let fallbackBounds = rect(72, 8, 32, 32)
    for dimensions in outputSizes:
      var renderer = initSdl3Renderer("CBSS rounded raster test",
        dimensions[0], dimensions[1], false)
      defer: renderer.close()
      when defined(linux):
        scaledWindow = renderer.window
        scaledWidth = 128
        scaledHeight = 64
        defer: scaledWindow = nil
      proc at(frame: Sdl3CapturedFrame; x, y: int): tuple[r, g, b: uint8] =
        frame.pixel(x * dimensions[0] div 128, y * dimensions[1] div 64)

      let surface = newRasterSurface(2, 2, [255'u8, 255, 0, 255])
      surface.updateRegion(rasterRegion(1, 0, 1, 2),
        [255'u8, 0, 0, 128, 0, 255, 0, 128])
      require surface.publish()
      let fallback = newRasterSurface(1, 2, [0'u8, 0, 0, 0])
      fallback.updateRegion(rasterRegion(0, 0, 1, 2),
        [255'u8, 0, 0, 128, 0, 255, 0, 128])
      require fallback.publish()
      let commands = @[
        drawRasterSurface(NodeId(1), surface, rect(44, 8, 8, 8), 0.25,
          tint = rgb(0, 0, 1)),
        pushClip(rasterBounds, radius = 10),
        drawRasterSurface(NodeId(2), surface, rasterBounds, 0.5,
          sourceRegion = rasterRegion(1, 0, 1, 2), tint = rgb(0.5, 1, 1)),
        popClip(),
        pushClip(fallbackBounds, radius = 10),
        PaintCommand(kind: pcDrawGpuDirectSurface, owner: some(NodeId(3)),
          gpuFallbackSurface: fallback, gpuSurfaceRect: fallbackBounds, gpuSurfaceOpacity: 0.5),
        popClip(),
        fillRect(rect(112, 16, 8, 8), rgb(1, 1, 0))]
      var rectangular = commands
      rectangular[1].clipRadius = 0
      rectangular[4].clipRadius = 0
      renderer.requestFrameCapture()
      renderer.render(rectangular, cosmic, fonts, background)
      let reference = renderer.capturedFrame().get

      renderer.requestFrameCapture()
      renderer.renderLayered(commands, cosmic, fonts, background)
      let rounded = renderer.capturedFrame().get
      check renderer.gpuDirectCompositionStats().unsupported == 1
      check rounded.at(8, 8) == (0'u8, 0'u8, 255'u8)
      check rounded.at(72, 8) == (0'u8, 0'u8, 255'u8)
      check rounded.at(24, 12).r in 31'u8 .. 33'u8
      check rounded.at(24, 36).g in 63'u8 .. 65'u8
      check rounded.at(88, 12).r in 63'u8 .. 65'u8
      check rounded.at(88, 36).g in 63'u8 .. 65'u8
      for y in 12 .. 36:
        check rounded.at(24, y) == reference.at(24, y)
        check rounded.at(88, y) == reference.at(88, y)

      surface.updateRegion(rasterRegion(1, 1, 1, 1), [255'u8, 255, 255, 255])
      require surface.publish()
      renderer.requestFrameCapture()
      renderer.renderLayered(commands, cosmic, fonts, background)
      let updated = renderer.capturedFrame().get
      check updated.at(24, 36).g in 127'u8 .. 128'u8
      check updated.at(88, 36) == rounded.at(88, 36)
      check updated.at(116, 20) == (255'u8, 255'u8, 0'u8)
      check renderer.retainedLayerStats().lastDirtyTiles == 1
      check renderer.cacheUsage().rasterFullUploads == 2
      check renderer.cacheUsage().rasterPartialUploads == 1

  test "raster surfaces use partial uploads for consecutive revisions":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    let surface = newRasterSurface(4, 4, [0'u8, 0'u8, 0'u8, 255'u8])
    let commands = @[
      drawRasterSurface(NodeId(1), surface, rect(0, 0, 40, 40))
    ]
    var renderer = initSdl3Renderer("CBSS raster update test", 40, 40, false)
    defer: renderer.close()

    renderer.requestFrameCapture()
    renderer.render(commands, rgb(0, 0, 0))
    check renderer.cacheUsage.rasterFullUploads == 1
    check renderer.cacheUsage.rasterPartialUploads == 0
    check renderer.capturedFrame().get.pixel(15, 15) == (0'u8, 0'u8, 0'u8)

    surface.updateRegion(
      rasterRegion(1, 1, 1, 1), @[255'u8, 0, 0, 255]
    )
    check surface.publish()
    renderer.requestFrameCapture()
    renderer.render(commands, rgb(0, 0, 0))
    check renderer.cacheUsage.rasterFullUploads == 1
    check renderer.cacheUsage.rasterPartialUploads == 1
    check renderer.capturedFrame().get.pixel(15, 15).r > 220
    check renderer.capturedFrame().get.pixel(5, 5).r < 10

    surface.updateRegion(
      rasterRegion(2, 2, 1, 1), @[0'u8, 255, 0, 255]
    )
    check surface.publish()
    surface.updateRegion(
      rasterRegion(3, 3, 1, 1), @[0'u8, 0, 255, 255]
    )
    check surface.publish()
    renderer.render(commands, rgb(0, 0, 0))
    check renderer.cacheUsage.rasterFullUploads == 2
    check renderer.cacheUsage.rasterPartialUploads == 1

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

    let maskCommands = @[
      fillRect(rect(0, 0, 40, 30), rgb(0, 0, 1)),
      pushLayer(rect(10, 5, 20, 20)),
      fillRect(rect(10, 5, 20, 20), rgb(1, 0, 0)),
      pushLayer(
        rect(10, 5, 20, 20), compositeMode = lcmDestinationIn
      ),
      fillRect(rect(10, 5, 10, 20), rgba(1, 1, 1, 0.5)),
      popLayer(),
      popLayer()
    ]
    renderer.requestFrameCapture()
    renderer.render(maskCommands, rgb(0, 0, 0))
    let maskFrame = renderer.capturedFrame().get
    check maskFrame.pixel(15, 15).r in 127'u8 .. 128'u8
    check maskFrame.pixel(15, 15).b in 127'u8 .. 128'u8
    check maskFrame.pixel(25, 15).r < 10
    check maskFrame.pixel(25, 15).b > 240

  test "color-filtered layers match CPU pixels on every render path":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")
    var renderer = initSdl3Renderer("CBSS layer filter test", 16, 12, false)
    defer: renderer.close()
    let filter = colorMatrixFilter([
      0.0'f32, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0
    ])
    var tint = identityColorMatrix
    tint[3] = 0.25
    for alpha in [1.0'f32, 0.5'f32]:
      for mode in [lcmSourceOver, lcmAdditive]:
        var commands = @[
          fillRect(rect(0, 0, 16, 12), rgb(0, 0, 1)),
          pushClip(rect(3, 2, 9, 7)),
          pushTransform(translationAffine2D(2, 1)),
          pushLayer(rect(0, 0, 10, 8), opacity = 0.5,
            compositeMode = mode, colorFilter = filter),
          fillRect(rect(2, 2, 6, 4), rgba(1, 0, 0, alpha)),
          popLayer(), popTransform(), popClip()
        ]
        if mode == lcmAdditive:
          # Additive composition targets the parent directly. A transform's
          # isolated transparent target has no destination alpha to retain.
          commands.delete(commands.len - 2)
          commands.delete(2)
        commands.resolveTransformBounds()
        let reference = ppm.render(commands, 16, 12, rgb(0, 0, 0))
        for path in 0 .. 2:
          renderer.requestFrameCapture()
          case path
          of 0: renderer.render(commands, rgb(0, 0, 0))
          of 1:
            renderer.render(commands, CosmicTextEngine(), initFontRegistry(), rgb(0, 0, 0))
          else:
            renderer.renderLayered(commands, CosmicTextEngine(), initFontRegistry(), rgb(0, 0, 0))
          let frame = renderer.capturedFrame().get
          for index in 0 ..< reference.pixels.len:
            check abs(int(frame.pixels[index]) - int(reference.pixels[index])) <= 3

    let nested = @[
      pushLayer(rect(0, 0, 16, 12), colorFilter = colorMatrixFilter(tint)),
      pushLayer(rect(2, 2, 8, 6), colorFilter = filter),
      fillRect(rect(3, 3, 4, 3), rgb(1, 0, 0)),
      popLayer(), popLayer()
    ]
    renderer.requestFrameCapture()
    renderer.render(nested, rgb(0, 0, 1))
    let nestedFrame = renderer.capturedFrame().get
    check nestedFrame.pixel(4, 4) == (64'u8, 255'u8, 0'u8)
    check nestedFrame.pixel(2, 2) == (0'u8, 0'u8, 255'u8)

  test "filtered retained layers invalidate by value and suppress oversized scopes":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")
    var renderer = initSdl3Renderer("CBSS retained filter test", 16, 12, false)
    defer: renderer.close()
    let matrix = [0.0'f32, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]
    var commands = @[
      pushLayer(rect(0, 0, 16, 12), colorFilter = colorMatrixFilter(matrix)),
      fillRect(rect(0, 0, 16, 12), rgb(1, 0, 0)), popLayer()
    ]
    renderer.renderLayered(commands, CosmicTextEngine(), initFontRegistry())
    let first = renderer.retainedLayerStats()
    commands[0] = pushLayer(rect(0, 0, 16, 12), colorFilter = colorMatrixFilter(matrix))
    renderer.renderLayered(commands, CosmicTextEngine(), initFontRegistry())
    check renderer.retainedLayerStats().skippedRepaints == first.skippedRepaints + 1
    commands[0] = pushLayer(rect(0, 0, 16, 12))
    renderer.requestFrameCapture()
    renderer.renderLayered(commands, CosmicTextEngine(), initFontRegistry())
    check renderer.retainedLayerStats().fullRepaints == first.fullRepaints + 1
    check renderer.capturedFrame().get.pixel(4, 4) == (255'u8, 0'u8, 0'u8)
    let previousBytes = renderer.cacheUsage().transformTextureBytes
    commands[0] = pushLayer(rect(0, 0, 100000, 100000),
      colorFilter = colorMatrixFilter(matrix))
    renderer.requestFrameCapture()
    renderer.render(commands, rgb(0, 0, 1))
    check renderer.capturedFrame().get.pixel(4, 4) == (0'u8, 0'u8, 255'u8)
    check renderer.cacheUsage().transformTextureBytes == previousBytes

  test "Style filters compose child overlays through all SDL render paths":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")
    var renderer = initSdl3Renderer("CBSS Style filter test", 16, 12, false)
    defer: renderer.close()
    let ui = initUiRoot()
    let panel = ui.box(uiStyle([
      width(16), height(12), decl("opacity", number(0.5)),
      decl("background-color", colorValue(rgb(1, 0, 0))),
      customPaint("swap", cpsFilter)
    ]))
    discard ui.box(uiStyle([
      width(8), height(6), decl("position", keyword("absolute")),
      decl("left", px(4)), decl("top", px(3)), decl("z-index", number(10)),
      decl("background-color", colorValue(rgb(1, 0, 0)))
    ]), parent = some(panel))
    let filter = colorMatrixFilter([
      0.0'f32, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0
    ])
    check ui.registerCustomPaintFilter("swap",
      proc(request: CustomPaintRequest): LayerColorFilter = filter)
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let layout = computeLayout(ui.tree, styles, size(16, 12))
    for registered in [true, false]:
      if not registered:
        check ui.unregisterCustomPaintMaterial("swap")
      let commands = ui.buildPaintCommands(styles, layout)
      let reference = ppm.render(commands, 16, 12, rgb(0, 0, 1))
      for path in 0 .. 2:
        renderer.requestFrameCapture()
        case path
        of 0: renderer.render(commands, rgb(0, 0, 1))
        of 1:
          renderer.render(commands, CosmicTextEngine(), initFontRegistry(), rgb(0, 0, 1))
        else:
          renderer.renderLayered(commands, CosmicTextEngine(), initFontRegistry(), rgb(0, 0, 1))
        let frame = renderer.capturedFrame().get
        for index in 0 ..< reference.pixels.len:
          check abs(int(frame.pixels[index]) - int(reference.pixels[index])) <= 3

  test "GPU direct commands use the configured compositor on every render path":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    var renderer = initSdl3Renderer("CBSS GPU compositor test", 40, 30, false)
    defer: renderer.close()
    let directCommand = PaintCommand(
      kind: pcDrawGpuDirectSurface,
      owner: some(NodeId(5)),
      gpuDirectSurface: nil,
      gpuSurfaceRect: rect(2, 3, 20, 10),
      gpuSurfaceOpacity: 0.75'f32
    )

    renderer.render([directCommand], rgb(0, 0, 0))
    check renderer.gpuDirectCompositionStats() ==
      Sdl3GpuDirectCompositionStats(unsupported: 1)

    var callbackCalls = 0
    renderer.setGpuDirectCompositor(
      proc(request: GpuDirectCompositeRequest): GpuDirectCompositeStatus =
      discard request
      inc callbackCalls
      gdcsPresented
    )
    renderer.render(
      [directCommand],
      CosmicTextEngine(),
      initFontRegistry(),
      rgb(0, 0, 0)
    )
    check callbackCalls == 0
    check renderer.gpuDirectCompositionStats() ==
      Sdl3GpuDirectCompositionStats(noFrame: 1)

    renderer.renderLayered(
      [directCommand],
      CosmicTextEngine(),
      initFontRegistry(),
      rgb(0, 0, 0),
      dynamicNodes = [NodeId(5)]
    )
    check callbackCalls == 0
    check renderer.gpuDirectCompositionStats() ==
      Sdl3GpuDirectCompositionStats(noFrame: 1)

    renderer.render([fillRect(rect(0, 0, 1, 1), rgb(1, 0, 0))])
    check renderer.gpuDirectCompositionStats() ==
      Sdl3GpuDirectCompositionStats()

  test "installing or clearing the GPU compositor refreshes a retained layer":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")
    var renderer = initSdl3Renderer("CBSS retained GPU compositor test", 32, 32, false)
    defer: renderer.close()
    let fonts = initFontRegistry()
    let cosmic = CosmicTextEngine()
    let fallback = newRasterSurface(1, 1, [0'u8, 255, 0, 255])
    let commands = [PaintCommand(kind: pcDrawGpuDirectSurface,
      owner: some(NodeId(1)), gpuFallbackSurface: fallback,
      gpuSurfaceRect: rect(0, 0, 8, 8), gpuSurfaceOpacity: 1)]
    renderer.renderLayered(commands, cosmic, fonts, rebuildStatic = false)
    check renderer.gpuDirectCompositionStats().unsupported == 1

    renderer.setGpuDirectCompositor(newGpuDirectCompositor(
      gpuDirectCompositeCapabilities({gdctOffscreen}, clipBoundsSupported = true),
      proc(request: GpuDirectCompositeRequest): GpuDirectCompositeStatus =
        gdcsPresented))
    renderer.renderLayered(commands, cosmic, fonts, rebuildStatic = false)
    check renderer.gpuDirectCompositionStats().noFrame == 1
    check renderer.retainedLayerStats().fullRepaints == 2

    renderer.clearGpuDirectCompositor()
    renderer.renderLayered(commands, cosmic, fonts, rebuildStatic = false)
    check renderer.gpuDirectCompositionStats().unsupported == 1
    check renderer.retainedLayerStats().fullRepaints == 3

  test "retained GPU composition retries its damaged tile until presented":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")
    var renderer = initSdl3Renderer("CBSS retained GPU retry test", 128, 64, false)
    defer: renderer.close()

    # Publish a real surface lease without needing a GPU for the retry policy.
    let backend = GpuBackendVTable(apiVersion: gpuHostApiVersion,
      context: GpuBackendContext(),
      openOwned: proc(context: GpuBackendContext; config: GpuHostConfig;
          info: var GpuBackendInfo): GpuBackendStatus =
        info = GpuBackendInfo(directTexturePresentationSupported: true,
          directPresentationFormats: {gtfRgba8},
          directPresentationAlphaModes: {gcamStraight},
          maxDirectPresentationBuffers: 2)
        gbsOk,
      createTexture: proc(context: GpuBackendContext; descriptor: GpuTextureDescriptor;
          initialData: seq[byte]; resource: var GpuBackendResourceId): GpuBackendStatus =
        resource = GpuBackendResourceId(1)
        gbsOk,
      destroyResource: proc(context: GpuBackendContext; resource: GpuBackendResourceId;
          kind: GpuResourceKind) = discard)
    let host = openGpuHost(backend, ghoOwned)
    defer: host.close()
    let namespace = host.createGpuNamespace("Retry fixture",
      GpuResourceBudget(maxResources: 1, persistentBytes: 4))
    let texture = host.createGpuTexture(namespace, GpuTextureDescriptor(
      width: 1, height: 1, format: gtfRgba8, usage: {gtuSampled}, access: gtaStatic),
      @[255'u8, 0, 0, 255])
    var config = defaultGpuDirectSurfaceConfig(1, 1)
    config.bufferCount = 2
    let surface = host.newGpuDirectSurface(namespace, config)
    defer: check surface.closeGpuDirectSurface()
    let frame = host.beginGpuFrame()
    check surface.queueGpuDirectSurfaceFrame(texture, frame)
    host.endGpuFrame(frame)
    check surface.collectGpuDirectSurfaceFrame()

    var busyFrames = 0
    let native = renderer.nativeSdl3Renderer()
    renderer.setGpuDirectCompositor(
      proc(request: GpuDirectCompositeRequest): GpuDirectCompositeStatus =
        if busyFrames > 0:
          dec busyFrames
          return gdcsRetry
        let bounds = request.destination
        var pixels = SDL_FRect(x: bounds.x, y: bounds.y, w: bounds.w, h: bounds.h)
        if SDL3.setRenderDrawColor(native, 255, 0, 0, 255) and
            SDL3.renderFillRect(native, addr pixels):
          gdcsPresented
        else:
          gdcsFailed)
    let fallback = newRasterSurface(1, 1, [0'u8, 255, 0, 255])
    let fonts = initFontRegistry()
    let cosmic = CosmicTextEngine()
    let background = rgb(0, 0, 0)
    var commands = [fillRect(rect(104, 4, 8, 8), rgb(0, 0, 1)),
      drawGpuDirectSurface(NodeId(1), surface, rect(80, 4, 8, 8), fallback = fallback)]
    renderer.renderLayered(commands, cosmic, fonts, background)
    check renderer.gpuDirectCompositionStats().presented == 1

    busyFrames = 2
    commands[0].color = rgb(1, 1, 0)
    for step in 0 .. 1:
      renderer.requestFrameCapture()
      renderer.renderLayered(commands, cosmic, fonts, background, rebuildStatic = step == 0)
      check renderer.gpuDirectCompositionStats().retry == 1
      check renderer.capturedFrame().get.pixel(82, 6) == (0'u8, 255'u8, 0'u8)
      check renderer.retainedLayerStats().lastDirtyTiles == 1

    renderer.requestFrameCapture()
    renderer.renderLayered(commands, cosmic, fonts, background, rebuildStatic = false)
    check renderer.gpuDirectCompositionStats().presented == 1
    check renderer.capturedFrame().get.pixel(82, 6) == (255'u8, 0'u8, 0'u8)
    check renderer.retainedLayerStats().lastDirtyTiles == 1
    renderer.renderLayered(commands, cosmic, fonts, background)
    check renderer.retainedLayerStats().lastDirtyTiles == 0
    check renderer.gpuDirectCompositionStats() == Sdl3GpuDirectCompositionStats()

  test "changing the Style shader hook invalidates a retained layer":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")
    var renderer = initSdl3Renderer("CBSS retained shader test", 16, 12, false)
    defer: renderer.close()
    let fonts = initFontRegistry()
    let cosmic = CosmicTextEngine()
    let commands = [
      pushShaderFilterLayer(rect(0, 0, 16, 12), LayerShaderFilter(material: "tint")),
      fillRect(rect(0, 0, 16, 12), rgb(1, 0, 0)),
      popLayer()]
    renderer.renderLayered(commands, cosmic, fonts, rebuildStatic = false)
    var calls = 0
    renderer.setGpuLayerShaderFilter(
      proc(renderer, destination: pointer; shader: LayerShaderFilter): bool =
        inc calls
        check shader.material == "tint"
        false)
    renderer.renderLayered(commands, cosmic, fonts, rebuildStatic = false)
    check renderer.retainedLayerStats().fullRepaints == 2
    check calls == 1
    renderer.setGpuLayerShaderFilter(nil)
    renderer.renderLayered(commands, cosmic, fonts, rebuildStatic = false)
    check renderer.retainedLayerStats().fullRepaints == 3
    check calls == 1

  test "Style shader source reuse follows paint and layer bounds":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")
    var renderer = initSdl3Renderer("CBSS shader source test", 16, 12, false)
    defer: renderer.close()
    var calls = 0
    renderer.setGpuLayerShaderFilter(
      proc(renderer, destination: pointer; shader: LayerShaderFilter): bool =
        inc calls
        false)
    let fonts = initFontRegistry()
    let cosmic = CosmicTextEngine()
    var commands = [
      pushShaderFilterLayer(rect(0, 0, 12, 12), LayerShaderFilter(material: "first")),
      fillRect(rect(0, 0, 12, 12), rgb(1, 0, 0)),
      popLayer()]
    renderer.renderLayered(commands, cosmic, fonts)
    check renderer.cacheUsage().shaderSourceBuilds == 1

    commands[0].layerShaderFilter.material = "second"
    renderer.renderLayered(commands, cosmic, fonts)
    check calls == 2
    check renderer.cacheUsage().shaderSourceHits == 1

    commands[1].color = rgb(0, 1, 0)
    renderer.requestFrameCapture()
    renderer.renderLayered(commands, cosmic, fonts)
    check renderer.capturedFrame().get.pixel(6, 6) == (0'u8, 255'u8, 0'u8)
    check renderer.cacheUsage().shaderSourceBuilds == 2

    commands[0].layerBounds = rect(0, 0, 4, 12)
    renderer.requestFrameCapture()
    renderer.renderLayered(commands, cosmic, fonts)
    let frame = renderer.capturedFrame().get
    check frame.pixel(2, 6) == (0'u8, 255'u8, 0'u8)
    check frame.pixel(6, 6) == (255'u8, 255'u8, 255'u8)
    check calls == 4
    check renderer.cacheUsage().shaderSourceBuilds == 3
    check renderer.cacheUsage().shaderSourceHits == 1

  test "layered rendering updates only damaged retained tiles":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    var renderer = initSdl3Renderer("CBSS retained damage test", 128, 64, false)
    defer: renderer.close()
    let fonts = initFontRegistry()
    let cosmic = CosmicTextEngine()
    let initial = @[
      fillRect(rect(4, 4, 20, 20), rgb(1, 0, 0)),
      fillRect(rect(100, 4, 20, 20), rgb(0, 0, 1))
    ]
    renderer.renderLayered(initial, cosmic, fonts, rgb(1, 1, 1))
    let firstStats = renderer.retainedLayerStats()
    check firstStats.fullRepaints == 1
    check firstStats.partialRepaints == 0
    check firstStats.lastDirtyTiles == 2
    check firstStats.totalTiles == 2

    let changed = @[
      fillRect(rect(4, 4, 20, 20), rgb(0, 1, 0)),
      fillRect(rect(100, 4, 20, 20), rgb(0, 0, 1))
    ]
    renderer.requestFrameCapture()
    renderer.renderLayered(changed, cosmic, fonts, rgb(1, 1, 1))
    let changedStats = renderer.retainedLayerStats()
    check changedStats.fullRepaints == 1
    check changedStats.partialRepaints == 1
    check changedStats.lastDirtyTiles == 1
    let changedFrame = renderer.capturedFrame().get
    check changedFrame.pixel(10, 10).g > 220
    check changedFrame.pixel(110, 10).b > 220

    renderer.renderLayered(changed, cosmic, fonts, rgb(1, 1, 1))
    let unchangedStats = renderer.retainedLayerStats()
    check unchangedStats.skippedRepaints == 1
    check unchangedStats.lastDirtyTiles == 0

    renderer.requestFrameCapture()
    renderer.renderLayered(changed[0 .. 0], cosmic, fonts, rgb(1, 1, 1))
    let removedStats = renderer.retainedLayerStats()
    check removedStats.partialRepaints == 2
    check removedStats.lastDirtyTiles == 1
    let removedFrame = renderer.capturedFrame().get
    check removedFrame.pixel(10, 10).g > 220
    check removedFrame.pixel(110, 10) == (255'u8, 255'u8, 255'u8)

  test "retained damage clips transformed updates in final coordinates":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    var renderer = initSdl3Renderer("CBSS transformed damage test", 128, 64, false)
    defer: renderer.close()
    let fonts = initFontRegistry()
    let cosmic = CosmicTextEngine()
    let transform = translationAffine2D(64, 0)
    var initial = @[
      pushTransform(transform, rect(0, 0, 32, 32)),
      fillRect(rect(4, 4, 20, 20), rgb(1, 0, 0)),
      popTransform(),
      fillRect(rect(4, 4, 20, 20), rgb(0, 0, 1))
    ]
    initial.resolveTransformBounds()
    renderer.renderLayered(initial, cosmic, fonts, rgb(1, 1, 1))

    var changed = @[
      pushTransform(transform, rect(0, 0, 32, 32)),
      fillRect(rect(4, 4, 20, 20), rgb(0, 1, 0)),
      popTransform(),
      fillRect(rect(4, 4, 20, 20), rgb(0, 0, 1))
    ]
    changed.resolveTransformBounds()
    renderer.requestFrameCapture()
    renderer.renderLayered(changed, cosmic, fonts, rgb(1, 1, 1))
    let stats = renderer.retainedLayerStats()
    check stats.partialRepaints == 1
    check stats.lastDirtyTiles == 1
    let frame = renderer.capturedFrame().get
    check frame.pixel(74, 10).g > 220
    check frame.pixel(10, 10).b > 220

  test "retained raster publication updates its destination tile only":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    let surface = newRasterSurface(4, 4, [0'u8, 0'u8, 0'u8, 255'u8])
    let commands = @[
      fillRect(rect(4, 4, 20, 20), rgb(0, 0, 1)),
      drawRasterSurface(NodeId(7), surface, rect(96, 0, 32, 32))
    ]
    var renderer = initSdl3Renderer("CBSS raster damage test", 128, 64, false)
    defer: renderer.close()
    let fonts = initFontRegistry()
    let cosmic = CosmicTextEngine()
    renderer.renderLayered(commands, cosmic, fonts, rgb(1, 1, 1))

    surface.updateRegion(
      rasterRegion(0, 0, 1, 1), @[255'u8, 0, 0, 255]
    )
    check surface.publish()
    renderer.requestFrameCapture()
    renderer.renderLayered(commands, cosmic, fonts, rgb(1, 1, 1))
    let stats = renderer.retainedLayerStats()
    check stats.partialRepaints == 1
    check stats.lastDirtyTiles == 1
    let frame = renderer.capturedFrame().get
    check frame.pixel(100, 4).r > 220
    check frame.pixel(10, 10).b > 220

  test "many sparse damage regions use a bounded replay count":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    var initial: seq[PaintCommand]
    var changed: seq[PaintCommand]
    for index in 0 ..< 9:
      let x = (index * 2 * DefaultDirtyTileSize + 4).float32
      initial.add fillRect(rect(x, 4, 16, 16), rgb(1, 0, 0))
      changed.add fillRect(rect(x, 4, 16, 16), rgb(0, 1, 0))
    var renderer = initSdl3Renderer(
      "CBSS bounded damage passes", 18 * DefaultDirtyTileSize, 64, false
    )
    defer: renderer.close()
    let fonts = initFontRegistry()
    let cosmic = CosmicTextEngine()
    renderer.renderLayered(initial, cosmic, fonts, rgb(1, 1, 1))
    renderer.renderLayered(changed, cosmic, fonts, rgb(1, 1, 1))
    let stats = renderer.retainedLayerStats()
    check stats.partialRepaints == 1
    check stats.lastDirtyTiles == 9
    check stats.lastDamagePasses == 1
    check stats.coalescedRepaints == 1

  test "dynamic command changes do not invalidate the retained static texture":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0:
        putEnv("SDL_VIDEODRIVER", previousDriver)
      else:
        delEnv("SDL_VIDEODRIVER")

    let dynamicOwner = NodeId(12)
    let initial = @[
      fillRect(rect(4, 4, 20, 20), rgb(0, 0, 1)),
      fillRect(
        rect(96, 4, 20, 20), rgb(1, 0, 0), owner = some(dynamicOwner)
      )
    ]
    let changed = @[
      fillRect(rect(4, 4, 20, 20), rgb(0, 0, 1)),
      fillRect(
        rect(96, 4, 20, 20), rgb(0, 1, 0), owner = some(dynamicOwner)
      )
    ]
    var renderer = initSdl3Renderer("CBSS dynamic retained test", 128, 64, false)
    defer: renderer.close()
    let fonts = initFontRegistry()
    let cosmic = CosmicTextEngine()
    renderer.renderLayered(
      initial, cosmic, fonts, rgb(1, 1, 1), dynamicNodes = [dynamicOwner]
    )
    renderer.requestFrameCapture()
    renderer.renderLayered(
      changed, cosmic, fonts, rgb(1, 1, 1), dynamicNodes = [dynamicOwner]
    )
    let stats = renderer.retainedLayerStats()
    check stats.fullRepaints == 1
    check stats.partialRepaints == 0
    check stats.skippedRepaints == 1
    let frame = renderer.capturedFrame().get
    check frame.pixel(10, 10).b > 220
    check frame.pixel(106, 10).g > 220

  test "CPU Motion Scene snapshots and timelines update every SDL rendering path":
    let previousDriver = getEnv("SDL_VIDEODRIVER")
    putEnv("SDL_VIDEODRIVER", "dummy")
    defer:
      if previousDriver.len > 0: putEnv("SDL_VIDEODRIVER", previousDriver)
      else: delEnv("SDL_VIDEODRIVER")
    var renderer = initSdl3Renderer("CBSS scene test", 24, 20, false)
    defer: renderer.close()
    let scene = newMotionScene(motionSceneSnapshot(size(24, 20), []))
    for color in [rgb(1, 0, 0), rgb(0, 1, 0)]:
      discard scene.replaceSnapshot(motionSceneSnapshot(size(24, 20), [
        motionRect(MotionObjectId(1), rect(0, 0, 12, 12), color,
          transform = translationAffine2D(4, 3), radius = 3),
        motionRect(MotionObjectId(2), rect(8, 6, 4, 4), rgb(0, 0, 1), zIndex = 1)
      ]))
      let commands = scene.canvas.paintCommands(NodeId(0), rect(0, 0, 24, 20))
      for path in 0 .. 2:
        renderer.requestFrameCapture()
        case path
        of 0: renderer.render(commands, rgb(0, 0, 0))
        of 1: renderer.render(commands, CosmicTextEngine(), initFontRegistry(), rgb(0, 0, 0))
        else: renderer.renderLayered(commands, CosmicTextEngine(), initFontRegistry(), rgb(0, 0, 0))
        let frame = renderer.capturedFrame().get
        check frame.pixel(6, 8) == (uint8(color.r * 255), uint8(color.g * 255), 0'u8)
        check frame.pixel(9, 8) == (0'u8, 0'u8, 255'u8)
        check frame.pixel(4, 3) == (0'u8, 0'u8, 0'u8)
        check frame.pixel(19, 8) == (0'u8, 0'u8, 0'u8)
    let timeline = newMotionTimeline(scene, [
      motionTrack(MotionObjectId(2), mspX, [
        FloatKeyframe(offset: 0, value: 8), FloatKeyframe(offset: 1, value: 16)
      ])
    ], 1, 0)
    for time in [0.5, 1.0]:
      var scheduler = initFrameScheduler()
      discard timeline.advance(scheduler, time)
      let commands = scene.canvas.paintCommands(NodeId(0), rect(0, 0, 24, 20))
      for path in 0 .. 2:
        renderer.requestFrameCapture()
        case path
        of 0: renderer.render(commands, rgb(0, 0, 0))
        of 1: renderer.render(commands, CosmicTextEngine(), initFontRegistry(), rgb(0, 0, 0))
        else: renderer.renderLayered(commands, CosmicTextEngine(), initFontRegistry(), rgb(0, 0, 0))
        let frame = renderer.capturedFrame().get
        check frame.pixel(9, 8) == (0'u8, 255'u8, 0'u8)
        check frame.pixel(9 + int(8 * time), 8) == (0'u8, 0'u8, 255'u8)
