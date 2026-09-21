# SPDX-License-Identifier: Apache-2.0

when not defined(cbssGpuBgfx):
  {.error: "compile this fixture with -d:cbssGpuBgfx".}

{.compile: "bgfx_pixel_window.c".}

import std/[math, options, os, strutils, tempfiles]
import bgfx

import clay_board_style_system/backends/bgfx/[adapter, sdl3_platform_data]
import clay_board_style_system/backends/sdl3/config
import clay_board_style_system/build/gpu_shader_compiler
import clay_board_style_system/core/[geometry, node]
import clay_board_style_system/paint/[gpu_direct_compositor,
    gpu_host_compositor, paint_command]
import clay_board_style_system/runtime/[gpu_direct_surface, gpu_host,
    gpu_shader_builder, gpu_shader_package]

when sdl3CompileFlags.len > 0:
  {.passC: sdl3CompileFlags.}
{.passL: sdl3LinkFlags.}

type
  CompositeVertex = object
    x, y, z: float32
    u, v: float32

  Pixel = object
    red, green, blue, alpha: uint8

  Source = object
    surface: GpuDirectSurface
    resource: GpuResourceHandle

proc createWindow(width, height: cint): pointer
  {.importc: "cbss_bgfx_pixel_create_window", cdecl.}
proc sdlError(): cstring {.importc: "cbss_bgfx_pixel_sdl_error", cdecl.}
proc pumpWindow() {.importc: "cbss_bgfx_pixel_pump", cdecl.}
proc destroyWindow(window: pointer)
  {.importc: "cbss_bgfx_pixel_destroy_window", cdecl.}

proc bytesOf[T](values: openArray[T]): seq[byte] =
  result = newSeq[byte](values.len * sizeof(T))
  if result.len > 0:
    copyMem(addr result[0], unsafeAddr values[0], result.len)

proc rgbaPixels(
    width, height: int;
    pixelAt: proc(x, y: int): Pixel
): seq[byte] =
  result = newSeq[byte](width * height * 4)
  for y in 0 ..< height:
    for x in 0 ..< width:
      let value = pixelAt(x, y)
      let offset = (y * width + x) * 4
      result[offset] = value.red
      result[offset + 1] = value.green
      result[offset + 2] = value.blue
      result[offset + 3] = value.alpha

proc pixel(data: GpuReadbackData; x, y: int): Pixel =
  doAssert x >= 0 and x < int(data.width)
  doAssert y >= 0 and y < int(data.height)
  let offset = y * int(data.rowStride) + x * 4
  Pixel(
    red: data.pixels[offset],
    green: data.pixels[offset + 1],
    blue: data.pixels[offset + 2],
    alpha: data.pixels[offset + 3]
  )

proc closeEnough(actual, expected: uint8; tolerance: int): bool {.inline.} =
  abs(int(actual) - int(expected)) <= tolerance

proc requirePixel(
    data: GpuReadbackData;
    x, y: int;
    expected: Pixel;
    label: string;
    tolerance = 3
) =
  let actual = data.pixel(x, y)
  doAssert actual.red.closeEnough(expected.red, tolerance) and
      actual.green.closeEnough(expected.green, tolerance) and
      actual.blue.closeEnough(expected.blue, tolerance) and
      actual.alpha.closeEnough(expected.alpha, tolerance),
    label & " at (" & $x & ", " & $y & "): expected " & $expected &
      ", got " & $actual

proc budget(): GpuResourceBudget =
  GpuResourceBudget(
    persistentBytes: 4 * 1024 * 1024,
    transientBytesPerFrame: 256 * 1024,
    readbackBytesPerFrame: 256 * 1024,
    workUnitsPerFrame: 128,
    maxResources: 96
  )

proc compileShader(
    source: GpuShaderSource;
    shaderc, includeDirectory, workDirectory: string
): GpuShaderArtifact =
  source.compileGpuShader(
    gpuShaderCompileTarget(gsbtOpenGL, gscpLinux, "330"),
    gpuShaderCompilerConfig(
      shaderc,
      [includeDirectory],
      workDirectory = workDirectory
    )
  ).artifact

proc createSource(
    host: GpuHost;
    namespace: GpuNamespaceId;
    width, height: uint32;
    pixels: sink seq[byte];
    label: string;
    alphaMode = gcamStraight
): Source =
  result.resource = host.createGpuTexture(
    namespace,
    GpuTextureDescriptor(
      width: width,
      height: height,
      format: gtfRgba8,
      usage: {gtuSampled},
      access: gtaStatic,
      label: label & "-texture"
    ),
    move(pixels)
  )
  var config = defaultGpuDirectSurfaceConfig(width, height)
  config.bufferCount = 2
  config.alphaMode = alphaMode
  config.label = label & "-surface"
  result.surface = host.newGpuDirectSurface(namespace, config)

proc publishSources(host: GpuHost; sources: varargs[Source]) =
  let token = host.beginGpuFrame()
  for source in sources:
    doAssert source.surface.queueGpuDirectSurfaceFrame(source.resource, token)
  host.endGpuFrame(token)
  for source in sources:
    doAssert source.surface.collectGpuDirectSurfaceFrame()

proc draw(
    host: GpuHost;
    compositor: GpuDirectCompositor;
    target: GpuResourceHandle;
    targetBounds, destination: Rect;
    source: Source;
    opacity = 1.0'f32;
    pixelScale = 1.0'f32;
    clip = none(Rect);
    rounded = none(GpuDirectClipMask)
) =
  var context = GpuDirectCompositeContext(
    targetKind: gdctOffscreen,
    targetBounds: targetBounds,
    clipBounds: clip,
    offscreenTarget: target,
    pixelScale: pixelScale
  )
  if rounded.isSome:
    if context.clipBounds.isNone:
      context.clipBounds = some(rounded.get.bounds)
    doAssert context.addGpuDirectClipMask(rounded.get)
  let command = drawGpuDirectSurface(
    NodeId(1), source.surface, destination, opacity
  )
  let status = command.compositeGpuDirectSurface(context, compositor)
  doAssert status == gdcsPresented, "direct compositor returned " & $status

proc readPixels(
    host: GpuHost;
    namespace: GpuNamespaceId;
    target: GpuResourceHandle;
    width, height: uint32
): GpuReadbackData =
  let staging = host.createGpuTexture(
    namespace,
    GpuTextureDescriptor(
      width: width,
      height: height,
      format: gtfRgba8,
      usage: {gtuBlitDestination, gtuReadback},
      access: gtaStatic,
      label: "pixel-conformance-readback"
    )
  )
  let token = host.beginGpuFrame()
  host.copyGpuTexture(namespace, target, staging)
  let readback = host.requestGpuReadback(namespace, staging)
  host.endGpuFrame(token)

  for attempt in 0 ..< 32:
    discard attempt
    pumpWindow()
    if host.tryTakeGpuReadback(readback, result):
      doAssert host.releaseGpuResource(staging)
      return
    let progress = host.beginGpuFrame()
    host.endGpuFrame(progress)
  raise newException(IOError, "GPU readback did not complete within 32 frames")

proc solid(red, green, blue: uint8; alpha = 255'u8): seq[byte] =
  rgbaPixels(1, 1, proc(x, y: int): Pixel =
    discard x
    discard y
    Pixel(red: red, green: green, blue: blue, alpha: alpha)
  )

proc run() =
  let shaderc = getEnv("CBSS_SHADERC")
  let shaderIncludes = getEnv("CBSS_BGFX_SHADER_INCLUDE")
  if shaderc.len == 0 or not fileExists(shaderc) or
      shaderIncludes.len == 0 or not dirExists(shaderIncludes):
    raise newException(
      ValueError,
      "CBSS_SHADERC and CBSS_BGFX_SHADER_INCLUDE are required"
    )

  let window = createWindow(64, 64)
  if window.isNil:
    raise newException(IOError, "SDL3 window creation failed: " & $sdlError())
  let workDirectory = createTempDir("cbss-bgfx-pixels-", "")
  var host: GpuHost
  var surfaces: seq[GpuDirectSurface]
  try:
    var options = defaultBgfxHostOptions()
    options.rendererType = BGFX_RENDERER_TYPE_OPENGL
    options.platformData = bgfxPlatformDataFromSdl3Window(window)
    options.directPresentation = newQualifiedBgfxDirectPresentationProfile(
      {gtfRgba8},
      maxBuffers = 2,
      textureSupported = true,
      renderTargetSupported = true,
      alphaModes = {gcamStraight, gcamPremultiplied, gcamOpaque},
      maxWidth = 64,
      maxHeight = 64
    )
    host = openGpuHost(
      newBgfxBackend(options),
      ghoOwned,
      GpuHostConfig(
        width: 64,
        height: 64,
        presentation: true,
        viewIdBase: 16,
        viewIdCount: 64
      )
    )
    doAssert host.backendInfo.rendererName.toLowerAscii.contains("opengl")

    let compositorNamespace = host.createGpuNamespace(
      "pixel-compositor", budget()
    )
    let sourceNamespace = host.createGpuNamespace("pixel-sources", budget())
    let vertexSource = gpuHostDirectCompositeVertexSource()
    let fragmentSource = gpuHostDirectCompositeFragmentSource()
    let maskedSource = gpuHostDirectCompositeMaskedFragmentSource()
    validateGpuShaderInterface(vertexSource, fragmentSource)
    validateGpuShaderInterface(vertexSource, maskedSource)
    let vertexShader = host.createGpuShader(
      compositorNamespace,
      compileShader(vertexSource, shaderc, shaderIncludes, workDirectory)
    )
    let fragmentShader = host.createGpuShader(
      compositorNamespace,
      compileShader(fragmentSource, shaderc, shaderIncludes, workDirectory)
    )
    let maskedShader = host.createGpuShader(
      compositorNamespace,
      compileShader(maskedSource, shaderc, shaderIncludes, workDirectory)
    )

    let layout = @[
      GpuVertexAttribute(
        semantic: gvsPosition, components: 3, componentType: gvctFloat
      ),
      GpuVertexAttribute(
        semantic: gvsTexCoord0, components: 2, componentType: gvctFloat
      )
    ]
    let vertices = [
      CompositeVertex(x: -1, y: -1, z: 0, u: 0, v: 1),
      CompositeVertex(x: -1, y: 1, z: 0, u: 0, v: 0),
      CompositeVertex(x: 1, y: -1, z: 0, u: 1, v: 1),
      CompositeVertex(x: 1, y: 1, z: 0, u: 1, v: 0)
    ]
    let vertexBuffer = host.createGpuBuffer(
      compositorNamespace,
      GpuBufferDescriptor(
        byteSize: uint64(sizeof(vertices)),
        role: gbrVertex,
        access: gbaStatic,
        vertexLayout: layout,
        label: "pixel-compositor-quad"
      ),
      vertices.bytesOf()
    )
    proc createPipeline(
        fragment: GpuResourceHandle;
        blend: GpuBlendState;
        label: string
    ): GpuResourceHandle =
      host.createGpuGraphicsPipeline(
        compositorNamespace,
        GpuGraphicsPipelineDescriptor(
          vertexShader: vertexShader,
          fragmentShader: fragment,
          vertexLayout: layout,
          colorFormat: gtfRgba8,
          topology: gptTriangleStrip,
          cullMode: gcmNone,
          frontFace: gffCounterClockwise,
          blend: blend,
          label: label
        )
      )
    let straightPipeline = createPipeline(
      fragmentShader, alphaGpuBlendState(), "pixel-compositor-straight"
    )
    let premultipliedPipeline = createPipeline(
      fragmentShader,
      premultipliedAlphaGpuBlendState(),
      "pixel-compositor-premultiplied"
    )
    let opaquePipeline = createPipeline(
      fragmentShader, alphaGpuBlendState(), "pixel-compositor-opaque"
    )
    let maskedStraightPipeline = createPipeline(
      maskedShader, alphaGpuBlendState(), "pixel-compositor-masked-straight"
    )
    let maskedPremultipliedPipeline = createPipeline(
      maskedShader,
      premultipliedAlphaGpuBlendState(),
      "pixel-compositor-masked-premultiplied"
    )
    let maskedOpaquePipeline = createPipeline(
      maskedShader, alphaGpuBlendState(), "pixel-compositor-masked-opaque"
    )
    let compositeUniform = host.createGpuUniform(
      compositorNamespace,
      GpuUniformDescriptor(
        name: "u_cbssComposite", uniformType: gutVec4, arrayLength: 1,
        label: "pixel-composite-uniform"
      )
    )
    let uvUniform = host.createGpuUniform(
      compositorNamespace,
      GpuUniformDescriptor(
        name: "u_cbssUvRect", uniformType: gutVec4, arrayLength: 1,
        label: "pixel-uv-uniform"
      )
    )
    let clipUniform = host.createGpuUniform(
      compositorNamespace,
      GpuUniformDescriptor(
        name: "u_cbssClipMasks", uniformType: gutVec4,
        arrayLength: gpuHostDirectCompositeClipUniformArrayLength,
        label: "pixel-clip-uniform"
      )
    )
    let sampler = host.createGpuSampler(
      compositorNamespace,
      GpuSamplerDescriptor(
        name: "s_cbssSurface",
        addressU: gsamClamp,
        addressV: gsamClamp,
        addressW: gsamClamp,
        minFilter: gsfNearest,
        magFilter: gsfNearest,
        mipFilter: gsfNearest,
        label: "pixel-compositor-sampler"
      )
    )
    var pipelines: array[GpuAlphaMode, GpuResourceHandle]
    var maskedPipelines: array[GpuAlphaMode, GpuResourceHandle]
    pipelines[gcamStraight] = straightPipeline
    pipelines[gcamPremultiplied] = premultipliedPipeline
    pipelines[gcamOpaque] = opaquePipeline
    maskedPipelines[gcamStraight] = maskedStraightPipeline
    maskedPipelines[gcamPremultiplied] = maskedPremultipliedPipeline
    maskedPipelines[gcamOpaque] = maskedOpaquePipeline
    let compositor = newGpuHostDirectCompositor(
      host,
      GpuHostDirectCompositeMaterial(
        namespace: compositorNamespace,
        pipelines: pipelines,
        maskedPipelines: maskedPipelines,
        vertexBuffer: vertexBuffer,
        compositeUniform: compositeUniform,
        uvRectUniform: uvUniform,
        clipMasksUniform: clipUniform,
        sampler: sampler,
        vertexCount: uint32(vertices.len)
      )
    )

    let black = createSource(host, sourceNamespace, 1, 1, solid(0, 0, 0), "black")
    surfaces.add black.surface
    let patternColors = [
      Pixel(red: 255, alpha: 255),
      Pixel(red: 255, green: 128, alpha: 255),
      Pixel(red: 255, green: 255, alpha: 255),
      Pixel(green: 255, alpha: 255),
      Pixel(green: 255, blue: 255, alpha: 255),
      Pixel(blue: 255, alpha: 255),
      Pixel(red: 128, blue: 255, alpha: 255),
      Pixel(red: 255, blue: 255, alpha: 255)
    ]
    let pattern = createSource(
      host, sourceNamespace, 8, 4,
      rgbaPixels(8, 4, proc(x, y: int): Pixel =
        discard y
        patternColors[x]
      ),
      "pattern"
    )
    surfaces.add pattern.surface
    let red = createSource(host, sourceNamespace, 1, 1, solid(255, 0, 0), "red")
    surfaces.add red.surface
    let cyan = createSource(host, sourceNamespace, 1, 1, solid(0, 255, 255), "cyan")
    surfaces.add cyan.surface
    let straightHalf = createSource(
      host, sourceNamespace, 1, 1, solid(255, 0, 0, 128),
      "straight-half", gcamStraight
    )
    surfaces.add straightHalf.surface
    let premultipliedHalf = createSource(
      host, sourceNamespace, 1, 1, solid(128, 0, 0, 128),
      "premultiplied-half", gcamPremultiplied
    )
    surfaces.add premultipliedHalf.surface
    let opaqueTransparent = createSource(
      host, sourceNamespace, 1, 1, solid(0, 255, 0, 0),
      "opaque-transparent", gcamOpaque
    )
    surfaces.add opaqueTransparent.surface
    publishSources(
      host,
      black,
      pattern,
      red,
      cyan,
      straightHalf,
      premultipliedHalf,
      opaqueTransparent
    )

    let uploadedRows = host.createGpuTexture(
      sourceNamespace,
      GpuTextureDescriptor(
        width: 2,
        height: 2,
        format: gtfRgba8,
        usage: {gtuSampled, gtuBlitSource},
        access: gtaStatic,
        label: "uploaded-row-orientation"
      ),
      rgbaPixels(2, 2, proc(x, y: int): Pixel =
        discard x
        if y == 0:
          Pixel(red: 255, alpha: 255)
        else:
          Pixel(blue: 255, alpha: 255)
      )
    )
    let uploadedPixels = host.readPixels(
      sourceNamespace, uploadedRows, 2, 2
    )
    uploadedPixels.requirePixel(
      0, 0, Pixel(red: 255, alpha: 255), "uploaded top row"
    )
    uploadedPixels.requirePixel(
      0, 1, Pixel(blue: 255, alpha: 255), "uploaded bottom row"
    )

    let target = host.createGpuRenderTarget(
      compositorNamespace,
      GpuRenderTargetDescriptor(
        width: 16,
        height: 8,
        format: gtfRgba8,
        usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
        label: "pixel-composition-target"
      )
    )
    let targetBounds = rect(0, 0, 16, 8)
    let compose = host.beginGpuFrame()
    host.draw(compositor, target, targetBounds, targetBounds, black)
    host.draw(
      compositor, target, targetBounds, rect(2, 2, 8, 4), pattern,
      clip = some(rect(4, 2, 4, 4))
    )
    host.draw(
      compositor, target, targetBounds, rect(10, 2, 4, 4), red,
      opacity = 0.5
    )
    host.draw(
      compositor, target, targetBounds, rect(0, 0, 4, 4), cyan,
      rounded = some(gpuDirectClipMask(rect(0, 0, 4, 4), 2))
    )
    host.endGpuFrame(compose)

    let pixels = host.readPixels(compositorNamespace, target, 16, 8)
    pixels.requirePixel(8, 0, Pixel(alpha: 255), "background")
    pixels.requirePixel(2, 5, Pixel(alpha: 255), "left clipped area")
    pixels.requirePixel(3, 5, Pixel(alpha: 255), "left clip boundary")
    for x in 4 .. 7:
      pixels.requirePixel(x, 5, patternColors[x - 2], "cropped UV " & $x)
    pixels.requirePixel(8, 5, Pixel(alpha: 255), "right clipped area")
    pixels.requirePixel(
      11, 3, Pixel(red: 128, alpha: 255), "straight opacity", tolerance = 5
    )
    pixels.requirePixel(
      0, 0, Pixel(green: 82, blue: 82, alpha: 255),
      "rounded antialiasing", tolerance = 8
    )
    pixels.requirePixel(
      1, 1, Pixel(green: 255, blue: 255, alpha: 255), "rounded center"
    )

    let alphaTarget = host.createGpuRenderTarget(
      compositorNamespace,
      GpuRenderTargetDescriptor(
        width: 6,
        height: 2,
        format: gtfRgba8,
        usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
        label: "pixel-alpha-target"
      )
    )
    let alphaBounds = rect(0, 0, 6, 2)
    let alphaFrame = host.beginGpuFrame()
    host.draw(compositor, alphaTarget, alphaBounds, alphaBounds, black)
    host.draw(
      compositor, alphaTarget, alphaBounds, rect(0, 0, 2, 2),
      straightHalf, opacity = 0.5
    )
    host.draw(
      compositor, alphaTarget, alphaBounds, rect(2, 0, 2, 2),
      premultipliedHalf, opacity = 0.5
    )
    host.draw(
      compositor, alphaTarget, alphaBounds, rect(4, 0, 2, 2),
      opaqueTransparent, opacity = 0.5
    )
    host.endGpuFrame(alphaFrame)
    let alphaPixels = host.readPixels(
      compositorNamespace, alphaTarget, 6, 2
    )
    alphaPixels.requirePixel(
      0, 0, Pixel(red: 64, alpha: 255), "straight alpha and opacity",
      tolerance = 5
    )
    alphaPixels.requirePixel(
      2, 0, Pixel(red: 64, alpha: 255), "premultiplied alpha and opacity",
      tolerance = 5
    )
    alphaPixels.requirePixel(
      4, 0, Pixel(green: 128, alpha: 255), "opaque alpha and opacity",
      tolerance = 5
    )

    let scaledTarget = host.createGpuRenderTarget(
      compositorNamespace,
      GpuRenderTargetDescriptor(
        width: 8,
        height: 4,
        format: gtfRgba8,
        usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
        label: "pixel-scale-and-stacking-target"
      )
    )
    let scaledBounds = rect(10, 20, 4, 2)
    let scaledFrame = host.beginGpuFrame()
    host.draw(
      compositor, scaledTarget, scaledBounds, scaledBounds, black,
      pixelScale = 2
    )
    host.draw(
      compositor, scaledTarget, scaledBounds, rect(11, 20.5, 2, 1), red,
      pixelScale = 2
    )
    host.draw(
      compositor, scaledTarget, scaledBounds, rect(12, 21, 1, 0.5), cyan,
      pixelScale = 2
    )
    host.draw(
      compositor, scaledTarget, scaledBounds, rect(12.5, 21, 0.5, 0.5), red,
      pixelScale = 2
    )
    host.endGpuFrame(scaledFrame)
    let scaledPixels = host.readPixels(
      compositorNamespace, scaledTarget, 8, 4
    )
    scaledPixels.requirePixel(
      1, 1, Pixel(alpha: 255), "scaled target background before destination"
    )
    scaledPixels.requirePixel(
      2, 1, Pixel(red: 255, alpha: 255), "two-times pixel-scale origin"
    )
    scaledPixels.requirePixel(
      5, 1, Pixel(red: 255, alpha: 255), "two-times pixel-scale extent"
    )
    scaledPixels.requirePixel(
      4, 2, Pixel(green: 255, blue: 255, alpha: 255),
      "later surface overlays earlier surface"
    )
    scaledPixels.requirePixel(
      5, 2, Pixel(red: 255, alpha: 255),
      "last surface wins at the same stacking position"
    )
    scaledPixels.requirePixel(
      6, 2, Pixel(alpha: 255), "scaled target background after destination"
    )

    var latestConfig = defaultGpuDirectSurfaceConfig(1, 1)
    latestConfig.bufferCount = 2
    latestConfig.label = "latest-ready-surface"
    let latestSurface = host.newGpuDirectSurface(sourceNamespace, latestConfig)
    surfaces.add latestSurface
    let oldFrame = host.beginGpuFrame()
    doAssert latestSurface.queueGpuDirectSurfaceFrame(red.resource, oldFrame)
    host.endGpuFrame(oldFrame)
    let latestFrame = host.beginGpuFrame()
    doAssert latestSurface.queueGpuDirectSurfaceFrame(cyan.resource, latestFrame)
    host.endGpuFrame(latestFrame)
    doAssert latestSurface.collectGpuDirectSurfaceFrame()
    let latestTarget = host.createGpuRenderTarget(
      compositorNamespace,
      GpuRenderTargetDescriptor(
        width: 1,
        height: 1,
        format: gtfRgba8,
        usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
        label: "latest-ready-target"
      )
    )
    let latestCompose = host.beginGpuFrame()
    host.draw(
      compositor,
      latestTarget,
      rect(0, 0, 1, 1),
      rect(0, 0, 1, 1),
      Source(surface: latestSurface, resource: cyan.resource)
    )
    host.endGpuFrame(latestCompose)
    let latestPixels = host.readPixels(
      compositorNamespace, latestTarget, 1, 1
    )
    latestPixels.requirePixel(
      0, 0, Pixel(green: 255, blue: 255, alpha: 255),
      "latest-ready surface frame"
    )

    let renderTargetSource = host.createGpuRenderTarget(
      compositorNamespace,
      GpuRenderTargetDescriptor(
        width: 4,
        height: 4,
        format: gtfRgba8,
        usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
        label: "render-target-source"
      )
    )
    let renderSourceFrame = host.beginGpuFrame()
    host.draw(
      compositor, renderTargetSource, rect(0, 0, 4, 4),
      rect(0, 0, 4, 4), red
    )
    host.draw(
      compositor, renderTargetSource, rect(0, 0, 4, 4),
      rect(0, 2, 4, 2), cyan
    )
    host.endGpuFrame(renderSourceFrame)
    var rtConfig = defaultGpuDirectSurfaceConfig(4, 4)
    rtConfig.bufferCount = 2
    rtConfig.label = "render-target-direct-surface"
    let rtSurface = host.newGpuDirectSurface(compositorNamespace, rtConfig)
    surfaces.add rtSurface
    let publication = host.beginGpuFrame()
    doAssert rtSurface.queueGpuDirectSurfaceFrame(renderTargetSource, publication)
    host.endGpuFrame(publication)
    doAssert rtSurface.collectGpuDirectSurfaceFrame()
    let rtInput = Source(surface: rtSurface, resource: renderTargetSource)
    let secondTarget = host.createGpuRenderTarget(
      compositorNamespace,
      GpuRenderTargetDescriptor(
        width: 4,
        height: 4,
        format: gtfRgba8,
        usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
        label: "render-target-output"
      )
    )
    let rtCompose = host.beginGpuFrame()
    host.draw(
      compositor, secondTarget, rect(0, 0, 4, 4),
      rect(0, 0, 4, 4), rtInput
    )
    host.endGpuFrame(rtCompose)
    let rtPixels = host.readPixels(
      compositorNamespace, secondTarget, 4, 4
    )
    rtPixels.requirePixel(
      2, 0, Pixel(red: 255, alpha: 255), "render-target top row"
    )
    rtPixels.requirePixel(
      2, 3, Pixel(green: 255, blue: 255, alpha: 255),
      "render-target bottom row"
    )
    echo "CBSS bgfx direct pixel conformance passed (", host.backendInfo.rendererName,
      ")"
  finally:
    if not host.isNil:
      for index in countdown(surfaces.high, 0):
        if not surfaces[index].isClosed:
          discard surfaces[index].closeGpuDirectSurface()
      host.close()
    try:
      removeDir(workDirectory)
    except OSError:
      discard
    destroyWindow(window)

run()
