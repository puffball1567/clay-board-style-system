# SPDX-License-Identifier: Apache-2.0

## Linux OpenGL feasibility fixture. SDL owns the EGL context, texture, and
## window presentation. bgfx borrows the context and writes the same texture.
import std/[options, os, tempfiles]
import bgfx
import clay_board_style_system/backends/bgfx/[
  adapter, sdl3_opengl_compositor, sdl3_opengl_target, sdl3_platform_data]
import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/build/gpu_shader_compiler
import clay_board_style_system/core/[color, geometry, node, raster_surface]
import clay_board_style_system/paint/[gpu_host_compositor, paint_command]
import clay_board_style_system/runtime/[gpu_direct_surface, gpu_host,
  gpu_shader_builder, gpu_shader_package]
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

proc testRendererComposition() =
  doAssert SDL3.setHint("SDL_VIDEO_FORCE_EGL", "1"), sdlError()
  doAssert SDL3.setHint("SDL_RENDER_DRIVER", "opengl"), sdlError()
  var renderer = initSdl3Renderer("CBSS OpenGL compositor", 32, 32)
  defer: renderer.close()
  let native = renderer.nativeSdl3Renderer()
  doAssert $SDL3.getRendererName(native) == "opengl"
  doAssert SDL3.flushRenderer(native), sdlError()
  let eglContext = SDL3.gL_GetCurrentContext()
  doAssert not eglContext.isNil
  doAssert BGFX.renderFrame(0) == BGFX_RENDER_FRAME_NO_CONTEXT
  var options = defaultBgfxHostOptions()
  options.rendererType = BGFX_RENDERER_TYPE_OPENGL
  options.platformData = bgfxPlatformDataFromSdl3Window(SDL3.getRenderWindow(native))
  options.platformData.platform.context = eglContext
  options.flushWithoutPresent = true
  options.directPresentation = newQualifiedBgfxDirectPresentationProfile(
    {gtfRgba8}, alphaModes = {gcamStraight})
  let host = openGpuHost(newBgfxBackend(options), ghoOwned, GpuHostConfig(
    width: 32, height: 32, resetFlags: BGFX_RESET_FLIP_AFTER_RENDER))
  defer: host.close()
  let budget = GpuResourceBudget(persistentBytes: 16_384, maxResources: 24,
    workUnitsPerFrame: 4)
  let composition = host.createGpuNamespace("OpenGL composition", budget)
  let producer = host.createGpuNamespace("OpenGL producer", budget)
  let work = createTempDir("cbss-sdl-layer-shaders-", "")
  defer: removeDir(work)
  let compiler = gpuShaderCompilerConfig(getEnv("CBSS_SHADERC"),
    [getEnv("CBSS_BGFX_SHADER_INCLUDE")], workDirectory = work)
  let shaderTarget = gpuShaderCompileTarget(gsbtOpenGL, gscpLinux, "330")
  let vertex = host.createGpuShader(composition,
    gpuHostDirectCompositeVertexSource().compileGpuShader(shaderTarget, compiler).artifact)
  let fragment = host.createGpuShader(composition,
    gpuHostDirectCompositeFragmentSource().compileGpuShader(shaderTarget, compiler).artifact)
  let layout = @[
    GpuVertexAttribute(semantic: gvsPosition, components: 3, componentType: gvctFloat),
    GpuVertexAttribute(semantic: gvsTexCoord0, components: 2, componentType: gvctFloat)]
  let vertices = [
    [-1'f32, -1, 0, 0, 1], [-1'f32, 1, 0, 0, 0],
    [1'f32, -1, 0, 1, 1], [1'f32, 1, 0, 1, 0]]
  var bytes = newSeq[byte](sizeof(vertices))
  copyMem(addr bytes[0], unsafeAddr vertices[0], bytes.len)
  let buffer = host.createGpuBuffer(composition, GpuBufferDescriptor(
    byteSize: bytes.len.uint64, role: gbrVertex, access: gbaStatic,
    vertexLayout: layout), move(bytes))
  let pipeline = host.createGpuGraphicsPipeline(composition,
    GpuGraphicsPipelineDescriptor(vertexShader: vertex, fragmentShader: fragment,
      vertexLayout: layout, colorFormat: gtfRgba8, topology: gptTriangleStrip,
      cullMode: gcmNone, blend: alphaGpuBlendState()))
  let composite = host.createGpuUniform(composition, GpuUniformDescriptor(
    name: "u_cbssComposite", uniformType: gutVec4, arrayLength: 1))
  let uv = host.createGpuUniform(composition, GpuUniformDescriptor(
    name: "u_cbssUvRect", uniformType: gutVec4, arrayLength: 1))
  let sampler = host.createGpuSampler(composition, GpuSamplerDescriptor(
    name: "s_cbssSurface", addressU: gsamClamp, addressV: gsamClamp,
    minFilter: gsfNearest, magFilter: gsfNearest, mipFilter: gsfNearest))
  var material = GpuHostDirectCompositeMaterial(namespace: composition,
    vertexBuffer: buffer, compositeUniform: composite, uvRectUniform: uv,
    sampler: sampler, vertexCount: 4)
  material.pipelines[gcamStraight] = pipeline
  renderer.setGpuDirectCompositor(
    newSdl3BgfxOpenGlLayerCompositor(native, host, material))
  defer: renderer.clearGpuDirectCompositor()

  let image = host.createGpuTexture(producer, GpuTextureDescriptor(
    width: 1, height: 2, format: gtfRgba8, usage: {gtuSampled}, access: gtaStatic),
    @[255'u8, 0, 0, 255, 0, 255, 0, 255])
  let surface = host.newGpuDirectSurface(producer, defaultGpuDirectSurfaceConfig(1, 2))
  defer: doAssert surface.closeGpuDirectSurface()
  let frame = host.beginGpuFrame()
  doAssert surface.queueGpuDirectSurfaceFrame(image, frame)
  host.endGpuFrame(frame)
  doAssert surface.collectGpuDirectSurfaceFrame()

  let fallback = newRasterSurface(1, 1)
  fallback.updateRegion(rasterRegion(0, 0, 1, 1), [0'u8, 255, 255, 255])
  doAssert fallback.publish()
  let commands = [
    pushLayer(rect(4, 4, 20, 20)),
    fillRect(rect(4, 4, 20, 20), rgb(0, 0, 1)),
    pushClip(rect(7, 5, 9, 7)),
    drawGpuDirectSurface(NodeId(1), surface, rect(6, 4, 12, 10)),
    fillRect(rect(9, 6, 2, 2), rgb(1, 1, 0)),
    popClip(),
    popLayer(),
    drawGpuDirectSurface(NodeId(2), surface, rect(0, 0, 2, 2),
      fallback = fallback)]
  let usage = host.gpuNamespaceUsage(composition)
  for repeat in 0 ..< 2:
    renderer.requestFrameCapture()
    renderer.render(commands, rgb(0, 0, 0))
    let capture = renderer.capturedFrame().get
    proc pixel(x, y: int): array[3, uint8] =
      let i = (y * capture.width + x) * 3
      [capture.pixels[i], capture.pixels[i + 1], capture.pixels[i + 2]]
    doAssert pixel(8, 6) == [255'u8, 0, 0], $pixel(8, 6)
    doAssert pixel(8, 10) == [0'u8, 255, 0], $pixel(8, 10)
    doAssert pixel(6, 6) == [0'u8, 0, 255], $pixel(6, 6)
    doAssert pixel(8, 15) == [0'u8, 0, 255], $pixel(8, 15)
    doAssert pixel(9, 6) == [255'u8, 255, 0], $pixel(9, 6)
    doAssert pixel(1, 1) == [0'u8, 255, 255], $pixel(1, 1)
    doAssert renderer.gpuDirectCompositionStats().presented == 1
    doAssert renderer.gpuDirectCompositionStats().unsupported == 1
    doAssert host.gpuNamespaceUsage(composition).resourceCount == usage.resourceCount
    doAssert host.gpuNamespaceUsage(composition).persistentBytes == usage.persistentBytes

testSharedTarget()
testRendererComposition()
echo "SDL3 and bgfx share an OpenGL render target with SDL-owned presentation"
