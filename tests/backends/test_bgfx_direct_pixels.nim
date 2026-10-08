# SPDX-License-Identifier: Apache-2.0

when not defined(cbssGpuBgfx):
  {.error: "compile this fixture with -d:cbssGpuBgfx".}

{.compile: "bgfx_pixel_window.c".}

import std/[math, options, os, strutils, tempfiles]
import bgfx

import clay_board_style_system/backends/bgfx/[adapter, sdl3_platform_data]
import clay_board_style_system/backends/sdl3/config
import clay_board_style_system/build/gpu_shader_compiler
import clay_board_style_system/core/[color, geometry, node]
import clay_board_style_system/backends/ppm/raster
import clay_board_style_system/runtime/canvas
import ../fixtures/gpu_instanced_rects
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
proc resizeWindow(
    window: pointer;
    width, height: cint;
    pixelWidth, pixelHeight: ptr cint
): bool {.importc: "cbss_bgfx_pixel_resize_window", cdecl.}
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

proc verifyInstancedRects(host: GpuHost; shaderc, shaderIncludes, workDirectory: string) =
  doAssert host.backendInfo.instancingSupported
  let ns = host.createGpuNamespace("instanced-rectangles", budget())
  let vertexSource = instancedRectVertexSource()
  let fragmentSource = instancedRectFragmentSource()
  validateGpuShaderInterface(vertexSource, fragmentSource)
  let vertex = host.createGpuShader(ns, compileShader(vertexSource, shaderc, shaderIncludes, workDirectory))
  let fragment = host.createGpuShader(ns, compileShader(fragmentSource, shaderc, shaderIncludes, workDirectory))
  let layout = @[GpuVertexAttribute(semantic: gvsPosition, components: 2, componentType: gvctFloat)]
  let pipeline = host.createGpuGraphicsPipeline(ns, GpuGraphicsPipelineDescriptor(
    vertexShader: vertex, fragmentShader: fragment, vertexLayout: layout,
    instanceDataVec4Count: 5, colorFormat: gtfRgba8, topology: gptTriangleStrip,
    cullMode: gcmNone, blend: alphaGpuBlendState()))
  let quad = [[0'f32, 0], [0'f32, 1], [1'f32, 0], [1'f32, 1]]
  let vertices = host.createGpuBuffer(ns, GpuBufferDescriptor(byteSize: 32,
    role: gbrVertex, access: gbaStatic, vertexLayout: layout), quad.bytesOf())
  let target = host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
    width: 64, height: 64, format: gtfRgba8, usage: {gtuRenderTarget, gtuSampled, gtuBlitSource}))
  let transforms = [translationAffine2D(6, 5),
    translationAffine2D(20, 16) * rotationAffine2D(0.2), translationAffine2D(45, 8)]
  let sizes = [size(24, 22), size(24, 24), size(12, 40)]
  let colors = [rgba(1, 0, 0, 1), rgba(0, 0, 1, 0.5), rgba(0, 1, 0, 1)]
  for access in [gbaStatic, gbaDynamic]:
    # Record zero is deliberately not drawn, exercising the instance offset.
    var records: array[4, array[5, array[4, float32]]]
    for index in 0 .. 2:
      let t = transforms[index]
      let c = colors[index]
      records[index + 1] = [[t.m11, t.m21, t.tx, 0'f32],
        [t.m12, t.m22, t.ty, 0'f32], [sizes[index].w, sizes[index].h, 4'f32, 0'f32],
        [c.r, c.g, c.b, c.a], [1'f32 / 64, 1'f32 / 64, 0, 0]]
    let instances = host.createGpuBuffer(ns, gpuInstanceBufferDescriptor(5, 4, access), records.bytesOf())
    for step in 0 .. (if access == gbaDynamic: 1 else: 0):
      if step == 1:
        records[3][0][2] = 50
        host.updateGpuBuffer(instances, 0, records.bytesOf())
      let token = host.beginGpuFrame()
      host.submitGpuDraw(ns, GpuGraphicsPassDescriptor(
        viewport: GpuViewport(width: 64, height: 64), renderTarget: target,
        clearColorEnabled: true, clearColor: GpuClearColor(alpha: 1)),
        GpuDrawCommand(pipeline: pipeline, vertexBuffer: vertices, vertexCount: 4,
          instances: GpuInstanceBinding(buffer: instances, firstInstance: 1, instanceCount: 3)))
      host.endGpuFrame(token)
      let actual = host.readPixels(ns, target, 64, 64)
      let canvas = newCanvas2D()
      for index in 0 .. 2:
        var transform = transforms[index]
        if index == 2 and step == 1: transform.tx = 50
        let bounds = rect(0, 0, sizes[index].w, sizes[index].h)
        canvas.save()
        canvas.transform(transform)
        canvas.pushClip(bounds, 4)
        canvas.fillRect(bounds, colors[index])
        canvas.restore()
      let expected = render(canvas.paintCommands(NodeId(0), rect(0, 0, 64, 64)), 64, 64, rgb(0, 0, 0))
      for point in [(0, 0), (6, 5), (12, 12), (24, 20), (33, 30), (46, 20), (54, 20), (63, 63)]:
        let index = (point[1] * 64 + point[0]) * 3
        actual.requirePixel(point[0], point[1], Pixel(red: expected.pixels[index],
          green: expected.pixels[index + 1], blue: expected.pixels[index + 2], alpha: 255),
          "instanced rounded rectangles match CPU")
    doAssert host.releaseGpuResource(instances)
  echo "Instanced rounded rectangles: static/dynamic, affine, opacity, order, subrange, update, CPU pixels passed"

proc checkProducerPressure(
    host: GpuHost;
    compositor: GpuDirectCompositor;
    compositorNamespace: GpuNamespaceId;
    bufferCount: int
) =
  const Cycles = 64
  var namespaces: array[2, GpuNamespaceId]
  var sources: array[2, Source]
  var resources: array[2, seq[GpuResourceHandle]]
  var current: array[2, int]
  var leases: array[2, GpuDirectSurfaceFrame]
  var expected: array[2, Pixel]
  let bounds = rect(0, 0, 4, 2)
  let target = host.createGpuRenderTarget(
    compositorNamespace,
    GpuRenderTargetDescriptor(
      width: 4, height: 2, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: "producer-pressure-target"
    )
  )
  try:
    for producer in 0 .. 1:
      namespaces[producer] = host.createGpuNamespace(
        "pressure-" & $bufferCount & "-" & $producer,
        GpuResourceBudget(
          persistentBytes: uint64((bufferCount + 1) * 4),
          transientBytesPerFrame: 64,
          workUnitsPerFrame: uint32(bufferCount - 1),
          maxResources: uint32(bufferCount + 1)
        )
      )
      var config = defaultGpuDirectSurfaceConfig(1, 1)
      config.bufferCount = bufferCount
      sources[producer].surface = host.newGpuDirectSurface(
        namespaces[producer], config
      )
      # One extra resource probes rejection when every surface slot is occupied.
      for index in 0 .. bufferCount:
        resources[producer].add host.createGpuTexture(
          namespaces[producer],
          GpuTextureDescriptor(
            width: 1, height: 1, format: gtfRgba8,
            usage: {gtuSampled}, access: gtaDynamic,
            label: "pressure-buffer-" & $index
          ),
          solid(0, 0, 0)
        )
      sources[producer].resource = resources[producer][0]
    publishSources(host, sources[0], sources[1])

    for cycle in 1 .. Cycles:
      for producer in 0 .. 1:
        leases[producer] = sources[producer].surface
          .acquireGpuDirectSurfaceFrame().get
      let token = host.beginGpuFrame()
      for producer in 0 .. 1:
        let surface = sources[producer].surface
        let previous = current[producer]
        for step in 1 ..< bufferCount:
          let index = (previous + step) mod resources[producer].len
          # Each producer and revision has a distinct color, including frames
          # dropped by latest-ready coalescing in the triple-buffered case.
          expected[producer] = Pixel(
            red: uint8(cycle * 3), green: uint8(producer * 160 + step * 30),
            blue: uint8(255 - cycle * 3), alpha: 255
          )
          let color = expected[producer]
          host.updateGpuTexture(
            resources[producer][index],
            solid(color.red, color.green, color.blue)
          )
          doAssert surface.queueGpuDirectSurfaceFrame(
            resources[producer][index], token
          )
          current[producer] = index
        let overflow = resources[producer][
          (previous + bufferCount) mod resources[producer].len
        ]
        doAssert not surface.queueGpuDirectSurfaceFrame(overflow, token)
        doAssert not host.isGpuResourcePresentationRetained(overflow)
        doAssert surface.retainedFrameCount == bufferCount
        doAssert surface.pendingFrameCount == bufferCount - 1
      host.endGpuFrame(token)

      for producer in 0 .. 1:
        let surface = sources[producer].surface
        doAssert surface.collectGpuDirectSurfaceFrame()
        doAssert surface.presentedRevision == uint64(1 + cycle * (bufferCount - 1))
        doAssert surface.pendingFrameCount == 0
        doAssert surface.retainedFrameCount == 2
        doAssert host.isGpuResourcePresentationRetained(leases[producer].resource)
        doAssert not surface.closeGpuDirectSurface()
        let retired = leases[producer].resource
        doAssert leases[producer].release()
        doAssert not host.isGpuResourcePresentationRetained(retired)
        doAssert surface.retainedFrameCount == 1
        sources[producer].resource = resources[producer][current[producer]]
        let usage = host.gpuNamespaceUsage(namespaces[producer])
        doAssert usage.resourceCount == uint32(bufferCount + 1)
        doAssert usage.persistentBytes == uint64((bufferCount + 1) * 4)

      let compose = host.beginGpuFrame()
      for producer in 0 .. 1:
        host.draw(
          compositor, target, bounds, rect(float32(producer * 2), 0, 2, 2),
          sources[producer]
        )
      host.endGpuFrame(compose)
      # Reuse the buffers across ordered GPU frames without a CPU readback
      # wait on each cycle; inspect every pixel at each batch boundary.
      if cycle mod 8 == 0:
        let pixels = host.readPixels(compositorNamespace, target, 4, 2)
        for y in 0 .. 1:
          for x in 0 .. 3:
            pixels.requirePixel(
              x, y, expected[x div 2],
              "producer pressure buffers=" & $bufferCount & " cycle=" & $cycle
            )

    # Closing one owner must leave the other owner's retained source usable.
    doAssert sources[0].surface.closeGpuDirectSurface()
    doAssert host.closeGpuNamespace(namespaces[0])
    let survivor = host.beginGpuFrame()
    host.draw(compositor, target, bounds, bounds, sources[1])
    host.endGpuFrame(survivor)
    let pixels = host.readPixels(compositorNamespace, target, 4, 2)
    for y in 0 .. 1:
      for x in 0 .. 3:
        pixels.requirePixel(x, y, expected[1], "surviving producer")
  finally:
    for producer in 0 .. 1:
      discard leases[producer].release()
      if not sources[producer].surface.isClosed:
        doAssert sources[producer].surface.closeGpuDirectSurface()
      if host.hasGpuNamespace(namespaces[producer]):
        doAssert host.closeGpuNamespace(namespaces[producer])
    doAssert host.releaseGpuResource(target)

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
      maxBuffers = 3,
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
    host.verifyInstancedRects(shaderc, shaderIncludes, workDirectory)

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

    let partialTexture = host.createGpuTexture(
      sourceNamespace,
      GpuTextureDescriptor(
        width: 2, height: 2, format: gtfRgba8,
        usage: {gtuSampled, gtuBlitSource}, access: gtaDynamic,
        label: "padded-partial-updates"
      ),
      rgbaPixels(2, 2, proc(x, y: int): Pixel =
        discard x
        discard y
        Pixel(green: 255, alpha: 255)
      )
    )
    for stride in [4, 7, 8, 65534, 65535, 65536]:
      var update = newSeq[byte](stride + 4)
      for offset in 0 ..< update.len:
        update[offset] = 123
      update[0] = 255
      update[1] = 0
      update[2] = 0
      update[3] = 255
      update[stride] = 0
      update[stride + 1] = 0
      update[stride + 2] = 255
      update[stride + 3] = 255
      let updateFrame = host.beginGpuFrame()
      host.updateGpuTexture(
        partialTexture, GpuTextureUpdateRegion(x: 1, width: 1, height: 2),
        update, uint32(stride)
      )
      host.endGpuFrame(updateFrame)
      let updated = host.readPixels(sourceNamespace, partialTexture, 2, 2)
      updated.requirePixel(
        1, 0, Pixel(red: 255, alpha: 255), "padded upload top " & $stride
      )
      updated.requirePixel(
        1, 1, Pixel(blue: 255, alpha: 255), "padded upload bottom " & $stride
      )
      for y in 0 .. 1:
        updated.requirePixel(
          0, y, Pixel(green: 255, alpha: 255), "untouched column " & $stride
        )
    let singleRowFrame = host.beginGpuFrame()
    host.updateGpuTexture(
      partialTexture, GpuTextureUpdateRegion(x: 1, y: 1, width: 1, height: 1),
      solid(255, 0, 255), high(uint32)
    )
    host.endGpuFrame(singleRowFrame)
    let singleRow = host.readPixels(sourceNamespace, partialTexture, 2, 2)
    singleRow.requirePixel(
      1, 1, Pixel(red: 255, blue: 255, alpha: 255), "single-row maximum stride"
    )
    singleRow.requirePixel(
      1, 0, Pixel(red: 255, alpha: 255), "single-row preserves preceding row"
    )
    doAssert host.releaseGpuResource(partialTexture)

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

    let fractionalFrame = host.beginGpuFrame()
    host.draw(
      compositor, scaledTarget, scaledBounds, scaledBounds, black,
      pixelScale = 2
    )
    host.draw(
      compositor, scaledTarget, scaledBounds, rect(10.25, 20, 2, 2), pattern,
      pixelScale = 2
    )
    host.endGpuFrame(fractionalFrame)
    let fractionalPixels = host.readPixels(
      compositorNamespace, scaledTarget, 8, 4
    )
    for x, colorIndex in [0, 2, 4, 6, 7]:
      fractionalPixels.requirePixel(
        x, 1, patternColors[colorIndex],
        "fractional origin keeps source texels aligned " & $x
      )
    fractionalPixels.requirePixel(
      5, 1, Pixel(alpha: 255), "fractional destination edge"
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

    let multipassTarget = host.createGpuRenderTarget(
      compositorNamespace,
      GpuRenderTargetDescriptor(
        width: 4,
        height: 4,
        format: gtfRgba8,
        usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
        label: "ordinary-multipass-target"
      )
    )
    let sourceUv =
      if host.gpuPresentableResourceInfo(renderTargetSource).rowsBottomUp:
        @[0.0'f32, 1.0'f32, 1.0'f32, 0.0'f32]
      else:
        @[0.0'f32, 0.0'f32, 1.0'f32, 1.0'f32]
    let multipassFrame = host.beginGpuFrame()
    host.submitGpuDraw(
      compositorNamespace,
      GpuGraphicsPassDescriptor(
        viewport: GpuViewport(width: 4, height: 4),
        renderTarget: multipassTarget
      ),
      GpuDrawCommand(
        pipeline: straightPipeline,
        vertexBuffer: vertexBuffer,
        vertexCount: uint32(vertices.len),
        bindings: GpuBindingSet(
          uniforms: @[
            GpuUniformBinding(
              uniform: compositeUniform,
              values: @[1.0'f32, float32(ord(gcamStraight)), 0.0'f32, 0.0'f32]
            ),
            GpuUniformBinding(uniform: uvUniform, values: sourceUv)
          ],
          textures: @[
            GpuTextureBinding(
              stage: 0,
              sampler: sampler,
              texture: renderTargetSource
            )
          ]
        )
      )
    )
    host.endGpuFrame(multipassFrame)
    let multipassPixels = host.readPixels(
      compositorNamespace, multipassTarget, 4, 4
    )
    multipassPixels.requirePixel(
      2, 0, Pixel(red: 255, alpha: 255), "ordinary multipass top row"
    )
    multipassPixels.requirePixel(
      2, 3, Pixel(green: 255, blue: 255, alpha: 255),
      "ordinary multipass bottom row"
    )

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

    var resizedWidth, resizedHeight: cint
    doAssert resizeWindow(
      window, 40, 30, addr resizedWidth, addr resizedHeight
    ), "SDL3 window resize failed: " & $sdlError()
    doAssert resizedWidth > 0 and resizedHeight > 0
    host.resizeGpuHost(uint32(resizedWidth), uint32(resizedHeight))
    let windowBounds = rect(
      0, 0, resizedWidth.float32, resizedHeight.float32
    )
    let windowContext = GpuDirectCompositeContext(
      targetKind: gdctWindow,
      targetBounds: windowBounds,
      pixelScale: 1
    )
    let windowCommand = drawGpuDirectSurface(
      NodeId(1), red.surface, windowBounds
    )
    let windowFrame = host.beginGpuFrame()
    let staleWindowContext = GpuDirectCompositeContext(
      targetKind: gdctWindow,
      targetBounds: rect(0, 0, 64, 64),
      pixelScale: 1
    )
    doAssert windowCommand.compositeGpuDirectSurface(
      staleWindowContext, compositor
    ) == gdcsUnsupported
    doAssert windowCommand.compositeGpuDirectSurface(
      windowContext, compositor
    ) == gdcsPresented
    host.endGpuFrame(windowFrame)
    let resizedTarget = host.createGpuRenderTarget(
      compositorNamespace,
      GpuRenderTargetDescriptor(
        width: 12,
        height: 6,
        format: gtfRgba8,
        usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
        label: "post-window-resize-target"
      )
    )
    let resizedBounds = rect(0, 0, 12, 6)
    let resizedFrame = host.beginGpuFrame()
    host.draw(compositor, resizedTarget, resizedBounds, resizedBounds, black)
    host.draw(
      compositor, resizedTarget, resizedBounds, rect(3, 2, 5, 2), cyan
    )
    host.endGpuFrame(resizedFrame)
    let resizedPixels = host.readPixels(
      compositorNamespace, resizedTarget, 12, 6
    )
    resizedPixels.requirePixel(
      2, 2, Pixel(alpha: 255), "post-resize background"
    )
    resizedPixels.requirePixel(
      3, 2, Pixel(green: 255, blue: 255, alpha: 255),
      "post-resize destination origin"
    )
    resizedPixels.requirePixel(
      7, 3, Pixel(green: 255, blue: 255, alpha: 255),
      "post-resize destination extent"
    )
    resizedPixels.requirePixel(
      8, 3, Pixel(alpha: 255), "post-resize background after destination"
    )
    for bufferCount in [2, 3]:
      host.checkProducerPressure(compositor, compositorNamespace, bufferCount)
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
