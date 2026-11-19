# SPDX-License-Identifier: Apache-2.0

## Linux OpenGL feasibility fixture. SDL owns the EGL context, texture, and
## window presentation. bgfx borrows the context and writes the same texture.
import bgfx
import clay_board_style_system/backends/bgfx/[
  adapter, sdl3_opengl_target, sdl3_platform_data]
import clay_board_style_system/runtime/gpu_host
import clay_board_style_system/vendor/sdl3

const
  textureSize = 8
  sdlInitVideo = SDL_InitFlags(0x20)
  sdlWindowOpenGl = SDL_WindowFlags(0x02)
  sdlWindowHidden = SDL_WindowFlags(0x08)

proc sdlError(): string =
  $SDL3.getError()

proc expectPixel(renderer: pointer; x, y: cint; expected: array[4, uint8]) =
  let surface = SDL3.renderReadPixels(renderer, nil)
  doAssert not surface.isNil, sdlError()
  defer: SDL3.destroySurface(surface)
  var actual: array[4, uint8]
  doAssert SDL3.readSurfacePixel(surface, x, y, addr actual[0],
    addr actual[1], addr actual[2], addr actual[3]), sdlError()
  doAssert actual == expected, "pixel (" & $x & ", " & $y & "): " &
    $actual & " != " & $expected

proc testSharedTarget() =
  doAssert SDL3.setHint("SDL_VIDEO_FORCE_EGL", "1"), sdlError()
  doAssert SDL3.init(sdlInitVideo), sdlError()
  defer: SDL3.quit()
  let window = SDL3.createWindow("CBSS OpenGL texture sharing", 32, 32,
    sdlWindowHidden or sdlWindowOpenGl)
  doAssert not window.isNil, sdlError()
  defer: SDL3.destroyWindow(window)
  let renderer = SDL3.createRenderer(window, "opengl")
  doAssert not renderer.isNil, sdlError()
  defer: SDL3.destroyRenderer(renderer)
  let target = SDL3.createTexture(renderer, SDL_PIXELFORMAT_RGBA32,
    SDL_TEXTUREACCESS_TARGET, textureSize, textureSize)
  doAssert not target.isNil, sdlError()
  defer: SDL3.destroyTexture(target)
  let composed = SDL3.createTexture(renderer, SDL_PIXELFORMAT_RGBA32,
    SDL_TEXTUREACCESS_TARGET, textureSize * 2, textureSize * 2)
  doAssert not composed.isNil, sdlError()
  defer: SDL3.destroyTexture(composed)
  doAssert SDL3.setRenderTarget(renderer, target), sdlError()
  doAssert SDL3.setRenderDrawColor(renderer, 0, 0, 255, 255), sdlError()
  doAssert SDL3.renderClear(renderer), sdlError()
  doAssert SDL3.flushRenderer(renderer), sdlError()

  let context = SDL3.gL_GetCurrentContext()
  doAssert not context.isNil

  block:
    # A caller-provided context must be current on bgfx's render thread.
    # Running bgfx on this thread also orders both APIs' OpenGL commands.
    doAssert BGFX.renderFrame(0) == BGFX_RENDER_FRAME_NO_CONTEXT
    var options = defaultBgfxHostOptions()
    options.rendererType = BGFX_RENDERER_TYPE_OPENGL
    options.platformData = bgfxPlatformDataFromSdl3Window(window)
    options.platformData.platform.context = context
    options.flushWithoutPresent = true
    let host = openGpuHost(newBgfxBackend(options), ghoOwned, GpuHostConfig(
      width: 32, height: 32, resetFlags: BGFX_RESET_FLIP_AFTER_RENDER))
    defer: host.close()
    doAssert BGFX.getRendererType() == BGFX_RENDERER_TYPE_OPENGL
    let ns = host.createGpuNamespace("SDL layer", GpuResourceBudget(
      maxResources: 1, persistentBytes: textureSize * textureSize * 4,
      workUnitsPerFrame: 1))
    doAssert SDL3.setRenderTarget(renderer, nil), sdlError()
    try:
      discard host.importSdl3BgfxOpenGlRenderTarget(ns, renderer)
      doAssert false, "window backbuffer must not be imported as a layer"
    except GpuHostError:
      doAssert host.gpuNamespaceUsage(ns).resourceCount == 0
    doAssert SDL3.setRenderTarget(renderer, target), sdlError()
    let layer = host.importSdl3BgfxOpenGlRenderTarget(ns, renderer)
    doAssert host.gpuNamespaceUsage(ns).resourceCount == 1
    var pass = GpuGraphicsPassDescriptor(
      viewport: GpuViewport(width: textureSize div 2, height: textureSize),
      clearColorEnabled: true, clearColor: GpuClearColor(red: 1, alpha: 1),
      renderTarget: layer)
    let first = host.beginGpuFrame()
    host.clearGpuGraphicsPass(ns, pass)
    host.endGpuFrame(first)

    # SDL composites the shared texture before the first test readback.
    doAssert SDL3.setRenderTarget(renderer, composed), sdlError()
    doAssert SDL3.renderTexture(renderer, target, nil, nil), sdlError()
    renderer.expectPixel(2, 6, [255'u8, 0, 0, 255])
    renderer.expectPixel(12, 6, [0'u8, 0, 255, 255])

    # SDL writes into the shared target and hands it back to bgfx for
    # another partial write. The second composition must preserve both.
    doAssert SDL3.setRenderTarget(renderer, target), sdlError()
    doAssert SDL3.setRenderDrawColor(renderer, 0, 255, 0, 255), sdlError()
    var overlay = SDL_FRect(x: 6, y: 0, w: 2, h: textureSize)
    doAssert SDL3.renderFillRect(renderer, addr overlay), sdlError()
    doAssert SDL3.flushRenderer(renderer), sdlError()
    pass.clearColor.green = 1
    let second = host.beginGpuFrame()
    host.clearGpuGraphicsPass(ns, pass)
    host.endGpuFrame(second)
    doAssert SDL3.setRenderTarget(renderer, composed), sdlError()
    doAssert SDL3.renderTexture(renderer, target, nil, nil), sdlError()
    renderer.expectPixel(2, 6, [255'u8, 255, 0, 255])
    renderer.expectPixel(14, 6, [0'u8, 255, 0, 255])
    doAssert SDL3.flushRenderer(renderer), sdlError()
    doAssert host.releaseGpuResource(layer)
    doAssert not host.isGpuResourceLive(layer)
    doAssert host.gpuNamespaceUsage(ns).persistentBytes == 0
    let retirement = host.beginGpuFrame()
    host.endGpuFrame(retirement)
    doAssert host.closeGpuNamespace(ns)

  # bgfx must leave both the SDL-owned context and its texture usable.
  doAssert SDL3.setRenderTarget(renderer, nil), sdlError()
  doAssert SDL3.setRenderTarget(renderer, target), sdlError()
  renderer.expectPixel(1, 3, [255'u8, 255, 0, 255])
  doAssert SDL3.setRenderDrawColor(renderer, 255, 0, 255, 255), sdlError()
  var overlay = SDL_FRect(x: 6, y: 3, w: 1, h: 1)
  doAssert SDL3.renderFillRect(renderer, addr overlay), sdlError()
  renderer.expectPixel(6, 3, [255'u8, 0, 255, 255])
  renderer.expectPixel(5, 3, [0'u8, 0, 255, 255])
  doAssert SDL3.setRenderTarget(renderer, nil), sdlError()
  doAssert SDL3.renderTexture(renderer, target, nil, nil), sdlError()
  doAssert SDL3.renderPresent(renderer), sdlError()

testSharedTarget()
echo "SDL3 and bgfx share an OpenGL render target with SDL-owned presentation"
