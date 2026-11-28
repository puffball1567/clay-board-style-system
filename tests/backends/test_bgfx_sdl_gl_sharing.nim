# SPDX-License-Identifier: Apache-2.0

## SDL-owned presentation with OpenGL texture sharing for composition and
## Style color filtering.
import std/[options, os, tempfiles]
import bgfx
import clay_board_style_system/backends/bgfx/[
  adapter, sdl3_opengl_compositor, sdl3_opengl_layer_filter,
  sdl3_opengl_target, sdl3_platform_data]
import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/build/gpu_shader_compiler
import clay_board_style_system/core/[color, custom_paint, declaration, diagnostics, geometry, node,
  raster_surface, style_resolver, style_value]
import clay_board_style_system/core/custom_paint_parameter
import clay_board_style_system/generated/default_properties
import clay_board_style_system/layout/layout
import clay_board_style_system/paint/[gpu_host_compositor, layer_blur, layer_color_filter, paint_command]
import clay_board_style_system/runtime/[gpu_color_matrix, gpu_gaussian_blur, gpu_direct_surface, gpu_host,
  gpu_layer_shader, gpu_shader_builder, gpu_shader_package, frame_scheduler,
  invalidation, motion_scene, motion_scene_gpu, motion_scene_gpu_direct, ui_root]
import clay_board_style_system/text/[cosmic_text_engine, font_registry]
import clay_board_style_system/vendor/sdl3

when defined(linux):
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

proc pixel(capture: Sdl3CapturedFrame; x, y: int): array[3, uint8] =
  let i = (y * capture.width + x) * 3
  [capture.pixels[i], capture.pixels[i + 1], capture.pixels[i + 2]]

proc expectCapture(actual, expected: Sdl3CapturedFrame; tolerance: int) =
  doAssert actual.width == expected.width and actual.height == expected.height
  for index, value in actual.pixels:
    doAssert abs(value.int - expected.pixels[index].int) <= tolerance,
      "filtered pixel " & $(index div 3) & ": " & $value &
        " != " & $expected.pixels[index]

proc verifyFractionalClip(renderer: var Sdl3Renderer; surface: GpuDirectSurface) =
  const logicalSizes =
    when defined(linux): [[32, 32], [24, 21]]
    else: [[32, 32]]
  let background = rgb(0, 0, 1)
  let clip = rect(7.75, 5.25, 9, 7)
  let destination = rect(0, 0, 32, 32)
  let hit = [255'u8, 0, 0]
  let miss = [0'u8, 0, 255]
  let fonts = initFontRegistry()
  let cosmic = CosmicTextEngine()
  when defined(linux):
    defer: scaledWindow = nil

  for dimensions in logicalSizes:
    when defined(linux):
      scaledWindow = renderer.window
      scaledWidth = dimensions[0].cint
      scaledHeight = dimensions[1].cint
    for isolated in [true, false]:
      var commands: seq[PaintCommand]
      if isolated:
        commands.add pushLayer(rect(4, 4, 20, 20))
      commands.add pushClip(clip)
      let paintIndex = commands.len
      # The clipped region samples only the top, solid red texel.
      commands.add fillRect(destination, rgb(1, 0, 0))
      commands.add popClip()
      if isolated:
        commands.add popLayer()

      template capture(): Sdl3CapturedFrame =
        renderer.requestFrameCapture()
        if isolated:
          renderer.render(commands, background)
        else:
          renderer.renderLayered(commands, cosmic, fonts, background)
        renderer.capturedFrame().get

      let reference = capture()
      doAssert reference.pixel(12, 9) == hit
      doAssert reference.pixel(30, 30) == miss
      commands[paintIndex] = drawGpuDirectSurface(NodeId(9), surface, destination)
      let direct = capture()
      doAssert renderer.gpuDirectCompositionStats().presented == 1,
        $renderer.gpuDirectCompositionStats()
      doAssert direct.pixels == reference.pixels,
        "SDL and bgfx clip coverage differs at " & $dimensions &
          " (isolated layer: " & $isolated & ")"

proc verifyMotionAndCompute(
    renderer: var Sdl3Renderer;
    shared: Sdl3BgfxOpenGlContext;
    host: GpuHost;
    compiler: GpuShaderCompilerConfig
) =
  let graphicsTarget = gpuShaderCompileTarget(gsbtOpenGL, gscpLinux, "330")
  let computeTarget = gpuShaderCompileTarget(gsbtOpenGL, gscpLinux, "430")
  let builder = newGpuShaderBuilder(gssCompute, "test-direct-compute")
  builder.setComputeWorkGroupSize(8, 8, 1)
  let output = builder.storageImage("i_output", 0, gtfRgba8, gsaWrite)
  let coordinates = builder.convertValue(gsvtIVec2,
    builder.swizzle(builder.globalInvocationId(), "xy"))
  builder.storeStorageImage(output, coordinates, builder.uniform("u_fill", gsvtVec4))
  let computeArtifact = builder.emitGpuShaderSource().compileGpuShader(
    computeTarget, compiler).artifact
  let motionVertex = gpuMotionRectVertexSource().compileGpuShader(graphicsTarget, compiler).artifact
  let motionFragment = gpuMotionRectFragmentSource().compileGpuShader(graphicsTarget, compiler).artifact
  let viewport = size(8, 8)
  let scene = newMotionScene(motionSceneSnapshot(viewport, [
    motionRect(MotionObjectId(1), rect(0, 0, 4, 4), rgba(1, 0, 0, 0.5))]))

  var motion: GpuMotionSceneDirect
  var compute: GpuDirectSurface
  var motionNamespace, computeNamespace: GpuNamespaceId
  var pipeline, fillUniform: GpuResourceHandle
  var outputs: array[2, GpuResourceHandle]
  let budget = GpuResourceBudget(maxResources: 16, persistentBytes: 64 * 1024,
    workUnitsPerFrame: 4)
  defer:
    shared.withSdl3BgfxOpenGlContext:
      if not compute.isClosed:
        discard compute.closeGpuDirectSurface()
      if not motion.isClosed:
        discard motion.close()
      for namespace in [motionNamespace, computeNamespace]:
        if host.hasGpuNamespace(namespace):
          discard host.closeGpuNamespace(namespace)
  shared.withSdl3BgfxOpenGlContext:
    doAssert host.backendInfo().computeSupported, "OpenGL compute is required"
    motionNamespace = host.createGpuNamespace("Motion producer", budget)
    computeNamespace = host.createGpuNamespace("Compute producer", budget)
    motion = host.newGpuMotionSceneDirect(motionNamespace, scene,
      defaultGpuMotionSceneDirectConfig(8, 8), motionVertex, motionFragment)
    doAssert motion.queueFrame()
    doAssert motion.collectFrame()
    var config = defaultGpuDirectSurfaceConfig(8, 8)
    config.acceptComputeOutput = true
    compute = host.newGpuDirectSurface(computeNamespace, config)
    let shader = host.createGpuShader(computeNamespace, computeArtifact)
    pipeline = host.createGpuComputePipeline(computeNamespace,
      GpuComputePipelineDescriptor(computeShader: shader))
    fillUniform = host.createGpuUniform(computeNamespace,
      GpuUniformDescriptor(name: "u_fill", uniformType: gutVec4, arrayLength: 1))
    for texture in outputs.mitems:
      texture = host.createGpuTexture(computeNamespace,
        GpuTextureDescriptor(width: 8, height: 8, format: gtfRgba8,
          usage: {gtuSampled, gtuStorage}, access: gtaStatic))

  let motionCommand = drawGpuDirectSurface(NodeId(1), motion.surface(), rect(2, 2, 12, 12))
  let computeCommand = drawGpuDirectSurface(NodeId(2), compute, rect(12, 10, 14, 14))
  let bounds = rect(0, 0, 32, 32)
  let background = rgb(0, 0, 1)
  let backdrop = fillRect(bounds, background)
  let motionRevision = motion.surface().presentedRevision()
  for index, color in [[0'f32, 1, 0, 1], [1'f32, 0, 1, 1]]:
    shared.withSdl3BgfxOpenGlContext:
      let frame = host.beginGpuFrame()
      try:
        host.dispatchGpuCompute(computeNamespace, GpuComputeCommand(
          pipeline: pipeline, groupsX: 1, groupsY: 1, groupsZ: 1,
          bindings: GpuBindingSet(
            uniforms: @[GpuUniformBinding(uniform: fillUniform, values: @color)],
            storageImages: @[GpuStorageImageBinding(stage: 0,
              texture: outputs[index], access: gsaWrite)])))
        doAssert compute.queueGpuDirectSurfaceFrame(outputs[index], frame)
      finally:
        host.endGpuFrame(frame)
      doAssert compute.collectGpuDirectSurfaceFrame()
      doAssert compute.presentedRevision() == uint64(index + 1)
      doAssert motion.surface().presentedRevision() == motionRevision

    renderer.requestFrameCapture()
    renderer.render([pushLayer(bounds), backdrop, motionCommand,
      pushClip(rect(12, 12, 8, 8)), computeCommand, popClip(),
      fillRect(rect(16, 16, 2, 2), rgb(1, 1, 0)), popLayer()], rgb(0, 0, 0))
    let pixels = renderer.capturedFrame().get
    doAssert renderer.gpuDirectCompositionStats().presented == 2
    doAssert pixels.pixel(4, 4) == [128'u8, 0, 127],
      $[pixels.pixel(4, 4), pixels.pixel(4, 11), pixels.pixel(14, 14)]
    doAssert pixels.pixel(10, 4) == [0'u8, 0, 255]
    let expected = if index == 0: [0'u8, 255, 0] else: [255'u8, 0, 255]
    doAssert pixels.pixel(14, 14) == expected, $pixels.pixel(14, 14)
    doAssert pixels.pixel(14, 10) == [0'u8, 0, 255]
    doAssert pixels.pixel(16, 16) == [255'u8, 255, 0]

  shared.withSdl3BgfxOpenGlContext:
    doAssert compute.closeGpuDirectSurface()
    doAssert host.closeGpuNamespace(computeNamespace)
    discard scene.replaceSnapshot(motionSceneSnapshot(viewport, [
      motionRect(MotionObjectId(1), rect(0, 0, 4, 4), rgb(0, 1, 1))]))
    doAssert motion.queueFrame()
    doAssert motion.collectFrame()

  renderer.requestFrameCapture()
  renderer.render([pushLayer(bounds), backdrop, motionCommand, popLayer()], rgb(0, 0, 0))
  doAssert renderer.gpuDirectCompositionStats().presented == 1
  doAssert renderer.capturedFrame().get.pixel(4, 4) == [0'u8, 255, 255]
  shared.withSdl3BgfxOpenGlContext:
    doAssert motion.close()
    doAssert host.closeGpuNamespace(motionNamespace)

proc testRendererComposition() =
  doAssert SDL3.setHint("SDL_VIDEO_FORCE_EGL", "1"), sdlError()
  doAssert SDL3.setHint("SDL_RENDER_DRIVER", "opengl"), sdlError()
  var renderer = initSdl3Renderer("CBSS OpenGL compositor", 32, 32)
  defer: renderer.close()
  let native = renderer.nativeSdl3Renderer()
  doAssert $SDL3.getRendererName(native) == "opengl"
  let shared = newSdl3BgfxOpenGlContext(native)
  defer: shared.close()
  var host: GpuHost
  var surface: GpuDirectSurface
  var composition, filterNamespace, limitedNamespace: GpuNamespaceId
  var blurNamespace, limitedBlurNamespace: GpuNamespaceId
  var shaderNamespace: GpuNamespaceId
  var material: GpuHostDirectCompositeMaterial
  var matrix, limitedMatrix: GpuColorMatrixMaterial
  var blur, limitedBlur: GpuGaussianBlurMaterial
  var shader, maskedShader: GpuLayerShaderMaterial
  var verticalMask, horizontalMask: GpuResourceHandle
  let work = createTempDir("cbss-sdl-layer-shaders-", "")
  defer: removeDir(work)
  let compiler = gpuShaderCompilerConfig(getEnv("CBSS_SHADERC"),
    [getEnv("CBSS_BGFX_SHADER_INCLUDE")], workDirectory = work)
  defer:
    renderer.clearGpuDirectCompositor()
    renderer.setGpuLayerColorFilter(nil)
    renderer.setGpuLayerBlur(nil)
    renderer.setGpuLayerShaderFilter(nil)
    if not host.isNil:
      shared.withSdl3BgfxOpenGlContext:
        if not surface.isNil:
          doAssert surface.closeGpuDirectSurface()
        matrix.release()
        limitedMatrix.release()
        blur.release()
        limitedBlur.release()
        shader.release()
        maskedShader.release()
        host.close()

  shared.withSdl3BgfxOpenGlContext:
    doAssert BGFX.renderFrame(0) == BGFX_RENDER_FRAME_NO_CONTEXT
    var options = defaultBgfxHostOptions()
    options.rendererType = BGFX_RENDERER_TYPE_OPENGL
    options.platformData = shared.platformData()
    options.flushWithoutPresent = true
    options.directPresentation = newQualifiedBgfxDirectPresentationProfile(
      {gtfRgba8}, computeOutputSupported = true,
      alphaModes = {gcamStraight, gcamPremultiplied})
    host = openGpuHost(newBgfxBackend(options), ghoOwned, GpuHostConfig(
      width: 32, height: 32, resetFlags: BGFX_RESET_FLIP_AFTER_RENDER))
    let budget = GpuResourceBudget(persistentBytes: 16_384, maxResources: 24,
      workUnitsPerFrame: 4)
    composition = host.createGpuNamespace("OpenGL composition", budget)
    let producer = host.createGpuNamespace("OpenGL producer", budget)
    let shaderTarget = gpuShaderCompileTarget(gsbtOpenGL, gscpLinux, "330")
    let layerVertex = gpuLayerShaderVertexSource()
    let builder = newGpuShaderBuilder(gssFragment, "test-layer-filter")
    let shaderUv = builder.varyingInput(gsisTexCoord0, gsvtVec2)
    let shift = builder.swizzle(builder.uniform("u_shift", gsvtVec4), "xy")
    let source = builder.sampleLayer(shaderUv - shift)
    let gain = builder.swizzle(builder.uniform("u_gain", gsvtVec4), "x")
    builder.setColorOutput(builder.swizzle(source, "bgra") * gain)
    let layerFragment = builder.emitGpuShaderSource()
    validateGpuShaderInterface(layerVertex, layerFragment)
    var vertexPackage = gpuShaderPackage(layerVertex)
    var fragmentPackage = gpuShaderPackage(layerFragment)
    discard vertexPackage.compileAndAddVariant(layerVertex, shaderTarget, compiler)
    discard fragmentPackage.compileAndAddVariant(layerFragment, shaderTarget, compiler)
    shaderNamespace = host.createGpuNamespace("OpenGL authored layer shader", budget)
    let packaged = decodeGpuShaderPackage(fragmentPackage.encodeGpuShaderPackageData())
    doAssertRaises(ValueError):
      discard newGpuLayerShaderMaterial(host, shaderNamespace,
        vertexPackage, packaged, gsbtOpenGL)
    doAssert host.gpuNamespaceUsage(shaderNamespace).resourceCount == 0
    shader = newGpuLayerShaderMaterial(host, shaderNamespace,
      vertexPackage, packaged, gsbtOpenGL,
      customPaintParameters([customPaintFloat("u_gain", 1),
        customPaintVec2("u_shift", 0, 0)]))
    let matrixVertex = gpuColorMatrixVertexSource().compileGpuShader(shaderTarget, compiler).artifact
    let matrixFragment = gpuColorMatrixFragmentSource().compileGpuShader(shaderTarget, compiler).artifact
    verticalMask = host.createGpuTexture(shaderNamespace, GpuTextureDescriptor(
      width: 1, height: 2, format: gtfRgba8, usage: {gtuSampled}, access: gtaStatic),
      @[255'u8, 255, 255, 255, 0, 0, 0, 0])
    horizontalMask = host.createGpuRenderTarget(shaderNamespace, GpuRenderTargetDescriptor(
      width: 2, height: 2, format: gtfRgba8, usage: {gtuSampled, gtuRenderTarget}))
    block:
      # A native OpenGL RenderTarget has a different row order from an upload.
      let maskUpload = host.createGpuTexture(shaderNamespace, GpuTextureDescriptor(
        width: 2, height: 2, format: gtfRgba8, usage: {gtuSampled}, access: gtaStatic),
        @[255'u8, 255, 255, 128, 255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0])
      let copyMaterial = newGpuColorMatrixMaterial(host, shaderNamespace, matrixVertex, matrixFragment)
      let copyFrame = host.beginGpuFrame()
      doAssert copyMaterial.submit(maskUpload, horizontalMask, nil)
      host.endGpuFrame(copyFrame)
      copyMaterial.release()
      doAssert host.releaseGpuResource(maskUpload)
      doAssert host.gpuPresentableResourceInfo(horizontalMask).rowsBottomUp
    let maskBuilder = newGpuShaderBuilder(gssFragment, "test-extra-layer-inputs")
    let maskUv = maskBuilder.varyingInput(gsisTexCoord0, gsvtVec2)
    let maskTop = maskBuilder.swizzle(maskBuilder.sampleLayerInput(4, maskUv), "a")
    let maskLeft = maskBuilder.swizzle(maskBuilder.sampleLayerInput(1, maskUv), "a")
    maskBuilder.setColorOutput(maskBuilder.sampleLayer(maskUv) * maskTop * maskLeft)
    let maskFragment = maskBuilder.emitGpuShaderSource()
    var maskPackage = gpuShaderPackage(maskFragment)
    discard maskPackage.compileAndAddVariant(maskFragment, shaderTarget, compiler)
    let packagedMask = decodeGpuShaderPackage(maskPackage.encodeGpuShaderPackageData())
    let input4 = GpuLayerShaderInput(slot: 4, texture: verticalMask)
    let input1 = GpuLayerShaderInput(slot: 1, texture: horizontalMask)
    let beforeMasks = host.gpuNamespaceUsage(shaderNamespace)
    doAssertRaises(ValueError):
      discard newGpuLayerShaderMaterial(host, shaderNamespace, vertexPackage,
        packagedMask, gsbtOpenGL, inputs = [input1])
    doAssertRaises(ValueError):
      discard newGpuLayerShaderMaterial(host, shaderNamespace, vertexPackage,
        packagedMask, gsbtOpenGL, inputs = [input1, input1])
    doAssertRaises(ValueError):
      discard newGpuLayerShaderMaterial(host, shaderNamespace, vertexPackage,
        packagedMask, gsbtOpenGL, inputs = [input1, GpuLayerShaderInput(slot: 0,
          texture: verticalMask)])
    doAssertRaises(ValueError):
      discard newGpuLayerShaderMaterial(host, shaderNamespace, vertexPackage,
        packagedMask, gsbtOpenGL, inputs = [input4, GpuLayerShaderInput(slot: 2,
          texture: horizontalMask)])
    doAssert host.gpuNamespaceUsage(shaderNamespace).resourceCount == beforeMasks.resourceCount
    doAssert not host.isGpuResourcePresentationRetained(horizontalMask)
    maskedShader = newGpuLayerShaderMaterial(host, shaderNamespace, vertexPackage,
      packagedMask, gsbtOpenGL, inputs = [input4, input1])
    doAssertRaises(GpuHostError):
      discard host.releaseGpuResource(verticalMask)

    block:
      var rollbackBudget = budget
      rollbackBudget.maxResources =
        host.gpuNamespaceUsage(shaderNamespace).resourceCount - beforeMasks.resourceCount
      let rollbackNamespace = host.createGpuNamespace("Layer input rollback", rollbackBudget)
      let rollbackTexture = host.createGpuTexture(rollbackNamespace, GpuTextureDescriptor(
        width: 1, height: 1, format: gtfRgba8, usage: {gtuSampled}, access: gtaStatic),
        @[255'u8, 255, 255, 255])
      doAssertRaises(ValueError):
        discard newGpuLayerShaderMaterial(host, shaderNamespace, vertexPackage,
          packagedMask, gsbtOpenGL, inputs = [input1,
            GpuLayerShaderInput(slot: 4, texture: rollbackTexture)])
      doAssertRaises(GpuHostError):
        discard newGpuLayerShaderMaterial(host, rollbackNamespace, vertexPackage,
          packagedMask, gsbtOpenGL, inputs = [
            GpuLayerShaderInput(slot: 1, texture: rollbackTexture),
            GpuLayerShaderInput(slot: 4, texture: rollbackTexture)])
      doAssert host.gpuNamespaceUsage(rollbackNamespace).resourceCount == 1
      doAssert host.releaseGpuResource(rollbackTexture)
      doAssert host.closeGpuNamespace(rollbackNamespace)

    filterNamespace = host.createGpuNamespace("OpenGL layer filter", budget)
    matrix = newGpuColorMatrixMaterial(host, filterNamespace, matrixVertex, matrixFragment)
    # Leave room for the source import only, so fallback must retire it.
    var limitedBudget = budget
    limitedBudget.maxResources = host.gpuNamespaceUsage(filterNamespace).resourceCount + 1
    limitedNamespace = host.createGpuNamespace("OpenGL limited layer filter", limitedBudget)
    limitedMatrix = newGpuColorMatrixMaterial(host, limitedNamespace, matrixVertex, matrixFragment)
    let blurVertex = gpuGaussianBlurVertexSource().compileGpuShader(shaderTarget, compiler).artifact
    let blurFragment = gpuGaussianBlurFragmentSource().compileGpuShader(shaderTarget, compiler).artifact
    var blurBudget = budget
    blurBudget.persistentBytes = 128 * 1024
    blurNamespace = host.createGpuNamespace("OpenGL layer blur", blurBudget)
    blur = newGpuGaussianBlurMaterial(host, blurNamespace, blurVertex, blurFragment)
    # Both SDL wrappers fit, but the intermediate blur target does not.
    blurBudget.maxResources = host.gpuNamespaceUsage(blurNamespace).resourceCount + 2
    limitedBlurNamespace = host.createGpuNamespace("OpenGL limited layer blur", blurBudget)
    limitedBlur = newGpuGaussianBlurMaterial(host, limitedBlurNamespace, blurVertex, blurFragment)
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
    var pipeline = GpuGraphicsPipelineDescriptor(vertexShader: vertex,
      fragmentShader: fragment, vertexLayout: layout, colorFormat: gtfRgba8,
      topology: gptTriangleStrip, cullMode: gcmNone, blend: alphaGpuBlendState())
    let composite = host.createGpuUniform(composition, GpuUniformDescriptor(
      name: "u_cbssComposite", uniformType: gutVec4, arrayLength: 1))
    let uv = host.createGpuUniform(composition, GpuUniformDescriptor(
      name: "u_cbssUvRect", uniformType: gutVec4, arrayLength: 1))
    let sampler = host.createGpuSampler(composition, GpuSamplerDescriptor(
      name: "s_cbssSurface", addressU: gsamClamp, addressV: gsamClamp,
      minFilter: gsfNearest, magFilter: gsfNearest, mipFilter: gsfNearest))
    material = GpuHostDirectCompositeMaterial(namespace: composition,
      vertexBuffer: buffer, compositeUniform: composite, uvRectUniform: uv,
      sampler: sampler, vertexCount: 4)
    material.pipelines[gcamStraight] = host.createGpuGraphicsPipeline(composition, pipeline)
    pipeline.blend = premultipliedAlphaGpuBlendState()
    material.pipelines[gcamPremultiplied] = host.createGpuGraphicsPipeline(composition, pipeline)
    let image = host.createGpuTexture(producer, GpuTextureDescriptor(
      width: 1, height: 2, format: gtfRgba8, usage: {gtuSampled}, access: gtaStatic),
      @[255'u8, 0, 0, 255, 0, 255, 0, 255])
    surface = host.newGpuDirectSurface(producer, defaultGpuDirectSurfaceConfig(1, 2))
    let frame = host.beginGpuFrame()
    doAssert surface.queueGpuDirectSurfaceFrame(image, frame)
    host.endGpuFrame(frame)
    doAssert surface.collectGpuDirectSurfaceFrame()

  renderer.setGpuDirectCompositor(
    newSdl3BgfxOpenGlLayerCompositor(shared, host, material))

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
    doAssert capture.pixel(8, 6) == [255'u8, 0, 0], $[
      capture.pixel(8, 6), capture.pixel(8, 10), capture.pixel(6, 6),
      capture.pixel(8, 15), capture.pixel(9, 6), capture.pixel(1, 1)] &
      " " & $renderer.gpuDirectCompositionStats()
    doAssert capture.pixel(8, 10) == [0'u8, 255, 0], $capture.pixel(8, 10)
    doAssert capture.pixel(6, 6) == [0'u8, 0, 255], $capture.pixel(6, 6)
    doAssert capture.pixel(8, 15) == [0'u8, 0, 255], $capture.pixel(8, 15)
    doAssert capture.pixel(9, 6) == [255'u8, 255, 0], $capture.pixel(9, 6)
    doAssert capture.pixel(1, 1) == [0'u8, 255, 255], $capture.pixel(1, 1)
    doAssert renderer.gpuDirectCompositionStats().presented == 1
    doAssert renderer.gpuDirectCompositionStats().unsupported == 1
    doAssert host.gpuNamespaceUsage(composition).resourceCount == usage.resourceCount
    doAssert host.gpuNamespaceUsage(composition).persistentBytes == usage.persistentBytes

  renderer.verifyFractionalClip(surface)

  let filteredCommands = [
    pushClip(rect(5, 5, 20, 19)),
    pushLayer(rect(4, 4, 24, 24), opacity = 0.5'f32,
      colorFilter = colorMatrixFilter([0'f32, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 0])),
    fillRect(rect(4, 4, 24, 8), rgba(1, 0, 0, 0.5)),
    fillRect(rect(4, 16, 24, 8), rgb(0, 0, 1)),
    drawGpuDirectSurface(NodeId(3), surface, rect(12, 12, 3, 4)),
    popLayer(), popClip(),
    fillRect(rect(28, 28, 3, 3), rgb(1, 1, 0))]
  renderer.requestFrameCapture()
  renderer.render(filteredCommands, rgb(0, 0, 0))
  let expected = renderer.capturedFrame().get
  doAssert expected.pixel(6, 6)[2] in 63'u8 .. 65'u8
  doAssert expected.pixel(6, 18)[0] in 127'u8 .. 129'u8
  doAssert expected.pixel(13, 15)[1] in 127'u8 .. 129'u8
  doAssert expected.pixel(4, 6) == [0'u8, 0, 0]
  doAssert expected.pixel(6, 14) == [0'u8, 0, 0]
  doAssert expected.pixel(29, 29) == [255'u8, 255, 0]

  for useGpu in [true, false]:
    let namespace = if useGpu: filterNamespace else: limitedNamespace
    let callback = newSdl3BgfxOpenGlLayerColorFilter(shared, host, namespace,
      if useGpu: matrix else: limitedMatrix)
    var calls = 0
    renderer.setGpuLayerColorFilter(
      proc(renderer, destination: pointer; filter: LayerColorFilter): bool =
        inc calls
        result = callback(renderer, destination, filter)
        doAssert result == useGpu)
    let filterUsage = host.gpuNamespaceUsage(namespace)
    for repeat in 0 ..< 2:
      renderer.requestFrameCapture()
      renderer.render(filteredCommands, rgb(0, 0, 0))
      renderer.capturedFrame().get.expectCapture(expected, 1)
      doAssert calls == repeat + 1
      doAssert renderer.gpuDirectCompositionStats().presented == 1
      doAssert host.gpuNamespaceUsage(namespace).resourceCount == filterUsage.resourceCount
      doAssert host.gpuNamespaceUsage(namespace).persistentBytes == filterUsage.persistentBytes
    renderer.setGpuLayerColorFilter(nil)

  for radius in [LayerBlurRadius(2), MaxLayerBlurRadius.LayerBlurRadius]:
    let commands = [
      pushClip(rect(5, 5, 20, 19)),
      pushBlurLayer(rect(4, 4, 24, 24), radius, opacity = 0.5),
      fillRect(rect(6, 6, 5, 4), rgba(1, 0, 0, 0.5)),
      fillRect(rect(19, 17, 4, 4), rgb(0, 0, 1)),
      drawGpuDirectSurface(NodeId(4), surface, rect(12, 12, 3, 4)),
      popLayer(), popClip(),
      fillRect(rect(28, 28, 3, 3), rgb(1, 1, 0))]
    renderer.requestFrameCapture()
    renderer.render(commands, rgb(0, 0, 0))
    let cpu = renderer.capturedFrame().get
    doAssert cpu.pixel(5, 7)[0] > 0
    doAssert cpu.pixel(4, 7) == [0'u8, 0, 0]
    doAssert cpu.pixel(20, 18)[2] > 0
    doAssert cpu.pixel(29, 29) == [255'u8, 255, 0]
    for useGpu in [true, false]:
      let namespace = if useGpu: blurNamespace else: limitedBlurNamespace
      let callback = newSdl3BgfxOpenGlLayerBlur(shared, host, namespace,
        if useGpu: blur else: limitedBlur)
      var calls = 0
      renderer.setGpuLayerBlur(
        proc(renderer, destination: pointer; filterRadius: LayerBlurRadius): bool =
          inc calls
          doAssert filterRadius == radius
          result = callback(renderer, destination, filterRadius)
          doAssert result == useGpu)
      let usage = host.gpuNamespaceUsage(namespace)
      for repeat in 0 ..< 2:
        renderer.requestFrameCapture()
        renderer.render(commands, rgb(0, 0, 0))
        renderer.capturedFrame().get.expectCapture(cpu, 2)
        doAssert calls == repeat + 1
        doAssert renderer.gpuDirectCompositionStats().presented == 1
        doAssert host.gpuNamespaceUsage(namespace).resourceCount == usage.resourceCount
        doAssert host.gpuNamespaceUsage(namespace).persistentBytes == usage.persistentBytes
      renderer.setGpuLayerBlur(nil)

  proc shaderCommands(parameters: CustomPaintParameters;
      material = "layer-swizzle"): seq[PaintCommand] =
    let fallback = colorMatrixFilter([0'f32, 1, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0])
    @[
      pushClip(rect(5, 5, 20, 19)),
      pushShaderFilterLayer(rect(4, 4, 24, 24), LayerShaderFilter(
        material: material, parameters: parameters), fallback = fallback),
      fillRect(rect(6, 6, 5, 4), rgba(1, 0, 0, 0.5)),
      fillRect(rect(19, 17, 4, 4), rgb(0, 0, 1)),
      popLayer(), popClip()]

  let background = rgb(0, 0, 0)
  let tinted = shaderCommands(customPaintParameters([customPaintFloat("u_gain", 0.5)]))
  renderer.requestFrameCapture()
  renderer.render(tinted, background)
  let fallbackFrame = renderer.capturedFrame().get
  doAssert fallbackFrame.pixel(7, 7)[1] in 127'u8 .. 129'u8
  doAssert fallbackFrame.pixel(20, 18) == [0'u8, 0, 255]

  let filter = newSdl3BgfxOpenGlLayerShaderFilter(shared, host, shaderNamespace,
    [("layer-swizzle", shader), ("layer-mask", maskedShader)])
  renderer.setGpuLayerShaderFilter(filter)
  let shaderUsage = host.gpuNamespaceUsage(shaderNamespace)
  for repeat in 0 ..< 2:
    renderer.requestFrameCapture()
    renderer.render(tinted, background)
    let frame = renderer.capturedFrame().get
    doAssert frame.pixel(7, 7)[2] in 63'u8 .. 65'u8, $frame.pixel(7, 7)
    doAssert frame.pixel(20, 18)[0] in 127'u8 .. 129'u8, $frame.pixel(20, 18)
    doAssert frame.pixel(7, 17) == [0'u8, 0, 0]
    doAssert host.gpuNamespaceUsage(shaderNamespace).resourceCount == shaderUsage.resourceCount
    doAssert host.gpuNamespaceUsage(shaderNamespace).persistentBytes == shaderUsage.persistentBytes

  renderer.requestFrameCapture()
  renderer.render(shaderCommands(nil), background)
  doAssert renderer.capturedFrame().get.pixel(20, 18) == [255'u8, 0, 0]
  for commands in [
      shaderCommands(customPaintParameters([customPaintInteger("u_gain", 1)])),
      shaderCommands(customPaintParameters([customPaintFloat("u_unknown", 1)])),
      shaderCommands(nil, material = "missing")]:
    renderer.requestFrameCapture()
    renderer.render(commands, background)
    renderer.capturedFrame().get.expectCapture(fallbackFrame, 1)
    doAssert host.gpuNamespaceUsage(shaderNamespace).resourceCount == shaderUsage.resourceCount

  let maskedCommands = [
    pushShaderFilterLayer(rect(4, 4, 24, 24), LayerShaderFilter(material: "layer-mask")),
    fillRect(rect(6, 6, 5, 4), rgba(1, 0, 0, 0.5)),
    fillRect(rect(19, 6, 4, 4), rgb(0, 1, 0)),
    fillRect(rect(19, 17, 4, 7), rgb(0, 0, 1)),
    popLayer()]
  for repeat in 0 ..< 2:
    renderer.requestFrameCapture()
    renderer.render(maskedCommands, background)
    let frame = renderer.capturedFrame().get
    doAssert frame.pixel(7, 7)[0] in 63'u8 .. 65'u8, $frame.pixel(7, 7)
    doAssert frame.pixel(20, 7)[1] in 238'u8 .. 240'u8, $frame.pixel(20, 7)
    doAssert frame.pixel(22, 7) == [0'u8, 255, 0], $frame.pixel(22, 7)
    doAssert frame.pixel(20, 22) == [0'u8, 0, 0], $frame.pixel(20, 22)
    doAssert host.gpuNamespaceUsage(shaderNamespace).resourceCount == shaderUsage.resourceCount

  block:
    let ui = initUiRoot()
    let registration = ui.registerCustomPaintShaderFilterTracked("layer-swizzle").get
    let panel = ui.box(uiStyle([
      decl("width", px(16)), decl("height", px(16)),
      decl("background-color", colorValue(rgb(1, 0, 0))),
      customPaint("layer-swizzle", cpsFilter,
        parameters = [customPaintFloat("u_gain", 0.25)])]))
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    doAssert not diagnostics.hasErrors
    let layout = computeLayout(ui.tree, styles, size(32, 32))
    discard ui.consumeInvalidation()
    discard ui.animateCustomPaintShaderFloat(panel, registration, "u_gain",
      0.25, 1, durationSeconds = 2, nowSeconds = 20)
    var scheduler = initFrameScheduler()
    let before = renderer.cacheUsage()
    for step in 0 .. 2:
      scheduler.clearDeadline()
      doAssert ui.tickOwnedAnimations(scheduler, 20 + step.float64) == 1
      doAssert scheduler.consumeDirty() == {ddPaint}
      renderer.requestFrameCapture()
      renderer.render(ui.buildPaintCommands(styles, layout), background)
      let actual = renderer.capturedFrame().get.pixel(7, 7)
      doAssert actual[0] == 0 and actual[1] == 0, $actual
      doAssert abs(actual[2].int - [64, 159, 255][step]) <= 1, $actual
    doAssert scheduler.nextDeadline.isNone
    doAssert renderer.cacheUsage().shaderSourceBuilds == before.shaderSourceBuilds + 1
    doAssert renderer.cacheUsage().shaderSourceHits == before.shaderSourceHits + 2

  block:
    let surface = newRasterSurface(1, 1, [255'u8, 0, 0, 255])
    let bounds = rect(0, 0, 12, 12)
    let commands = [
      pushShaderFilterLayer(bounds, LayerShaderFilter(material: "layer-swizzle")),
      drawRasterSurface(NodeId(1), surface, bounds),
      popLayer()]
    let before = renderer.cacheUsage()
    for expected in [[0'u8, 0, 255], [0'u8, 0, 255], [255'u8, 0, 0]]:
      if expected[0] == 255:
        surface.updateRegion(rasterRegion(0, 0, 1, 1), [0'u8, 0, 255, 255])
        doAssert surface.publish()
      renderer.requestFrameCapture()
      renderer.render(commands, background)
      doAssert renderer.capturedFrame().get.pixel(6, 6) == expected
    doAssert renderer.cacheUsage().shaderSourceBuilds == before.shaderSourceBuilds + 2
    doAssert renderer.cacheUsage().shaderSourceHits == before.shaderSourceHits + 1

  block:
    let ui = initUiRoot()
    let viewport = ui.box(uiStyle([
      decl("width", px(18)), decl("height", px(32)),
      decl("overflow", keyword("hidden"))]))
    discard ui.box(uiStyle([
      decl("width", px(8)), decl("height", px(8)),
      decl("position", keyword("absolute")), decl("left", px(8)), decl("top", px(8)),
      decl("background-color", colorValue(rgb(1, 0, 0))),
      customPaint("layer-swizzle", cpsFilter,
        parameters = [customPaintVec2("u_shift", 0.25, 0)])]), parent = some(viewport))
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    doAssert not diagnostics.hasErrors
    let layout = computeLayout(ui.tree, styles, size(32, 32))
    doAssert ui.registerCustomPaintShaderFilter("layer-swizzle", effectOutset = 4)
    let commands = ui.buildPaintCommands(styles, layout)
    renderer.requestFrameCapture()
    renderer.render(commands, background)
    let frame = renderer.capturedFrame().get
    doAssert frame.pixel(16, 10) == [0'u8, 0, 255]
    doAssert frame.pixel(18, 10) == [0'u8, 0, 0]
    doAssert frame.pixel(8, 10) == [0'u8, 0, 0]

  renderer.setGpuLayerShaderFilter(nil)
  shared.withSdl3BgfxOpenGlContext:
    maskedShader.release()
    doAssert host.releaseGpuResource(horizontalMask)
    doAssert host.releaseGpuResource(verticalMask)
  renderer.requestFrameCapture()
  renderer.render(tinted, background)
  renderer.capturedFrame().get.expectCapture(fallbackFrame, 1)

  renderer.verifyMotionAndCompute(shared, host, compiler)

testSharedTarget()
testRendererComposition()
echo "SDL3 and bgfx share OpenGL render targets for composition and Style filtering"
