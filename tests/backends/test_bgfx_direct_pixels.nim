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
import clay_board_style_system/core/raster_surface
import clay_board_style_system/backends/ppm/raster
import clay_board_style_system/runtime/canvas
import clay_board_style_system/runtime/[gpu_canvas, motion_scene,
    gpu_display_surface, motion_scene_gpu, motion_scene_gpu_canvas,
    motion_scene_gpu_direct, motion_scene_gpu_filter_display]
import clay_board_style_system/paint/[gpu_direct_compositor,
    gpu_host_compositor, layer_color_filter, paint_command]
import clay_board_style_system/runtime/[gpu_direct_surface, gpu_host,
    gpu_alpha_mask, gpu_channel_matrix, gpu_color_matrix,
    gpu_composite, gpu_convolution, gpu_displacement,
    gpu_gaussian_blur, gpu_morphology,
    gpu_drop_shadow,
    gpu_filter_chain, gpu_filter_display,
    gpu_raster_filter_display, gpu_shader_builder, gpu_shader_package]

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

proc rasterPixel(data: openArray[byte]; width, x, y: int): Pixel =
  let offset = (y * width + x) * 4
  Pixel(red: data[offset], green: data[offset + 1],
    blue: data[offset + 2], alpha: data[offset + 3])

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

proc requireRasterPixel(
    data: openArray[byte]; width, x, y: int;
    expected: Pixel; label: string; tolerance = 3
) =
  let actual = data.rasterPixel(width, x, y)
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

proc verifyCanvasReadbackCancellation(host: GpuHost) =
  let ns = host.createGpuNamespace("canvas-readback-cancel", budget())
  var config = defaultGpuCanvasConfig(2, 2)
  config.readbackSlots = 2
  let canvas = host.newGpuCanvasSurface(ns, config)
  proc source(color: Pixel; label: string): GpuResourceHandle =
    host.createGpuTexture(ns, GpuTextureDescriptor(
      width: 2, height: 2, format: gtfRgba8,
      usage: {gtuBlitSource}, access: gtaStatic, label: label),
      rgbaPixels(2, 2, proc(x, y: int): Pixel =
        discard x
        discard y
        color))
  let red = source(Pixel(red: 255, alpha: 255), "canvas-red")
  let blue = source(Pixel(blue: 255, alpha: 255), "canvas-blue")

  proc drain(): bool =
    for attempt in 0 ..< 32:
      discard attempt
      pumpWindow()
      if canvas.collectGpuCanvasFrame():
        result = true
      if canvas.pendingFrameCount == 0:
        return
      let progress = host.beginGpuFrame()
      host.endGpuFrame(progress)
    raise newException(IOError, "cancelled GPU canvas readback did not drain")

  let first = host.beginGpuFrame()
  doAssert canvas.queueGpuCanvasFrameFrom(red)
  doAssert canvas.queueGpuCanvasFrameFrom(blue)
  doAssert canvas.cancelGpuCanvasFrame(2)
  host.endGpuFrame(first)
  doAssert not canvas.closeGpuCanvasSurface()
  doAssert drain()
  doAssert canvas.completedFrameNumber == 2
  doAssert canvas.rasterSurface.publish()
  let redPixels = rgbaPixels(2, 2, proc(x, y: int): Pixel =
    discard x
    discard y
    Pixel(red: 255, alpha: 255))
  doAssert canvas.rasterSurface.pixels == redPixels

  let second = host.beginGpuFrame()
  doAssert canvas.queueGpuCanvasFrameFrom(blue)
  doAssert canvas.cancelGpuCanvasFrame(3)
  host.endGpuFrame(second)
  doAssert not drain()
  doAssert canvas.completedFrameNumber == 3
  doAssert not canvas.rasterSurface.publish()
  doAssert canvas.rasterSurface.pixels == redPixels

  let third = host.beginGpuFrame()
  doAssert canvas.queueGpuCanvasFrameFrom(blue)
  host.endGpuFrame(third)
  doAssert drain()
  doAssert canvas.completedFrameNumber == 4
  doAssert canvas.rasterSurface.publish()
  doAssert canvas.rasterSurface.pixels == rgbaPixels(2, 2, proc(x, y: int): Pixel =
    discard x
    discard y
    Pixel(blue: 255, alpha: 255))
  doAssert canvas.closeGpuCanvasSurface()
  doAssert host.releaseGpuResource(red)
  doAssert host.releaseGpuResource(blue)
  doAssert host.closeGpuNamespace(ns)
  echo "GPU canvas: cancelled readbacks drain without publication; slots reuse cleanly"

proc verifyHybridDisplayPixels(host: GpuHost) =
  let ns = host.createGpuNamespace("hybrid-display-pixels", budget())
  var config = defaultGpuDisplaySurfaceConfig(4, 2)
  config.bufferCount = 2
  config.fallback = gdsfRequireHybrid
  let display = host.newGpuDisplaySurface(ns, config)
  doAssert display.path == gdspHybrid
  let rows = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 4, height: 2, format: gtfRgba8,
    usage: {gtuSampled, gtuBlitSource}, access: gtaStatic,
    label: "hybrid-row-source"),
    rgbaPixels(4, 2, proc(x, y: int): Pixel =
      discard x
      if y == 0: Pixel(red: 255, alpha: 255)
      else: Pixel(blue: 255, alpha: 255)))
  let target = host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
    width: 4, height: 2, format: gtfRgba8,
    usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
    label: "hybrid-target-source"))

  proc drain(expected: uint64) =
    for attempt in 0 ..< 32:
      discard attempt
      pumpWindow()
      discard display.collectGpuDisplayFrame()
      if display.readbackSurface().completedFrameNumber == expected and
          display.readbackSurface().pendingFrameCount == 0 and
          display.directSurface().presentedRevision == expected:
        return
      let progress = host.beginGpuFrame()
      host.endGpuFrame(progress)
    raise newException(IOError, "hybrid GPU display readback did not drain")

  let first = host.beginGpuFrame()
  doAssert display.queueGpuDisplayFrame(rows, first)
  host.endGpuFrame(first)
  drain(1)
  doAssert display.readbackSurface().rasterSurface.publish()
  let rowPixels = display.readbackSurface().rasterSurface.pixels
  rowPixels.requireRasterPixel(4, 0, 0, Pixel(red: 255, alpha: 255),
    "hybrid top row")
  rowPixels.requireRasterPixel(4, 3, 1, Pixel(blue: 255, alpha: 255),
    "hybrid bottom row")
  var rowFrame = display.directSurface().acquireGpuDirectSurfaceFrame().get
  doAssert rowFrame.resource == rows
  doAssert rowFrame.release()

  let second = host.beginGpuFrame()
  host.clearGpuGraphicsPass(ns, GpuGraphicsPassDescriptor(
    viewport: GpuViewport(width: 4, height: 2), renderTarget: target,
    clearColorEnabled: true,
    clearColor: GpuClearColor(green: 1, alpha: 1)))
  doAssert display.queueGpuDisplayFrame(target, second)
  host.endGpuFrame(second)
  drain(2)
  doAssert display.readbackSurface().rasterSurface.publish()
  let targetPixels = display.readbackSurface().rasterSurface.pixels
  targetPixels.requireRasterPixel(4, 0, 0, Pixel(green: 255, alpha: 255),
    "hybrid RenderTarget top row")
  targetPixels.requireRasterPixel(4, 3, 1, Pixel(green: 255, alpha: 255),
    "hybrid RenderTarget bottom row")
  var targetFrame = display.directSurface().acquireGpuDirectSurfaceFrame().get
  doAssert targetFrame.resource == target
  doAssert targetFrame.release()
  doAssert display.closeGpuDisplaySurface()
  doAssert host.releaseGpuResource(rows)
  doAssert host.releaseGpuResource(target)
  doAssert host.closeGpuNamespace(ns)
  echo "Hybrid GPU display: Texture and RenderTarget direct/readback pixels passed"

proc verifyGpuColorMatrixPixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("gpu-color-matrix-pixels", budget())
  let material = host.newGpuColorMatrixMaterial(ns,
    compileShader(gpuColorMatrixVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuColorMatrixFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let source = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 2, height: 2, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "color-matrix-source"),
    rgbaPixels(2, 2, proc(x, y: int): Pixel =
      if y == 0 and x == 0: Pixel(red: 100, green: 20, blue: 5, alpha: 128)
      elif y == 0: Pixel()
      elif x == 0: Pixel(green: 128, alpha: 128)
      else: Pixel(red: 30, green: 60, blue: 90, alpha: 255)))
  proc target(label: string): GpuResourceHandle =
    host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
      width: 2, height: 2, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: label))
  let filtered = target("color-matrix-filtered")
  let chained = target("color-matrix-chained")
  let faded = target("color-matrix-faded")
  let grayscale = target("color-matrix-grayscale")
  let sepia = target("color-matrix-sepia")
  let hue = target("color-matrix-hue")
  let swapRedBlue = colorMatrixFilter([
    0'f32, 0, 1, 0,
    0'f32, 1, 0, 0,
    1'f32, 0, 0, 0
  ])
  let frame = host.beginGpuFrame()
  doAssert material.submit(source, filtered, swapRedBlue, gcamPremultiplied)
  doAssert material.submit(filtered, chained, nil, gcamPremultiplied)
  doAssert material.submit(chained, faded, nil,
    gcamPremultiplied, opacity = 0.5)
  doAssert material.submit(source, grayscale, grayscaleColorFilter(1),
    gcamPremultiplied)
  doAssert material.submit(source, sepia, sepiaColorFilter(1),
    gcamPremultiplied)
  doAssert material.submit(source, hue, hueRotateColorFilter(90),
    gcamPremultiplied)
  host.endGpuFrame(frame)
  for output in [filtered, chained]:
    let pixels = host.readPixels(ns, output, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 5, green: 20, blue: 100,
      alpha: 128), "GPU matrix premultiplied top row")
    pixels.requirePixel(1, 0, Pixel(), "GPU matrix transparent pixel")
    pixels.requirePixel(0, 1, Pixel(green: 128, alpha: 128),
      "GPU matrix second row")
    pixels.requirePixel(1, 1, Pixel(red: 90, green: 60, blue: 30,
      alpha: 255), "GPU matrix opaque pixel")
  let fadedPixels = host.readPixels(ns, faded, 2, 2)
  fadedPixels.requirePixel(0, 0, Pixel(red: 3, green: 10, blue: 50,
    alpha: 64), "GPU matrix opacity premultiplied pixel")
  fadedPixels.requirePixel(0, 1, Pixel(green: 64, alpha: 64),
    "GPU matrix opacity translucent pixel")
  fadedPixels.requirePixel(1, 1, Pixel(red: 45, green: 30, blue: 15,
    alpha: 128), "GPU matrix opacity opaque pixel")
  let grayscalePixels = host.readPixels(ns, grayscale, 2, 2)
  grayscalePixels.requirePixel(0, 0, Pixel(red: 36, green: 36,
    blue: 36, alpha: 128), "GPU grayscale translucent pixel")
  grayscalePixels.requirePixel(0, 1, Pixel(red: 92, green: 92,
    blue: 92, alpha: 128), "GPU grayscale green pixel")
  grayscalePixels.requirePixel(1, 1, Pixel(red: 56, green: 56,
    blue: 56, alpha: 255), "GPU grayscale opaque pixel")
  let sepiaPixels = host.readPixels(ns, sepia, 2, 2)
  sepiaPixels.requirePixel(0, 0, Pixel(red: 56, green: 49,
    blue: 39, alpha: 128), "GPU sepia translucent pixel")
  sepiaPixels.requirePixel(0, 1, Pixel(red: 98, green: 88,
    blue: 68, alpha: 128), "GPU sepia green pixel")
  let huePixels = host.readPixels(ns, hue, 2, 2)
  huePixels.requirePixel(0, 0, Pixel(red: 5, green: 52, alpha: 128),
    "GPU hue rotation translucent pixel")
  huePixels.requirePixel(0, 1, Pixel(green: 109, blue: 128, alpha: 128),
    "GPU hue rotation green pixel")
  doAssert host.releaseGpuResource(source)
  doAssert host.releaseGpuResource(filtered)
  doAssert host.releaseGpuResource(chained)
  doAssert host.releaseGpuResource(faded)
  doAssert host.releaseGpuResource(grayscale)
  doAssert host.releaseGpuResource(sepia)
  doAssert host.releaseGpuResource(hue)
  material.release()
  doAssert host.closeGpuNamespace(ns)
  echo "GPU color matrix: premultiplied, grayscale, sepia, hue rotation, and RenderTarget chaining pixels passed"

proc verifyGpuChannelMatrixPixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("gpu-channel-matrix-pixels", budget())
  let material = host.newGpuChannelMatrixMaterial(ns,
    compileShader(gpuChannelMatrixVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuChannelMatrixFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let source = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 2, height: 2, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "channel-matrix-source"),
    rgbaPixels(2, 2, proc(x, y: int): Pixel =
      if y == 0 and x == 0: Pixel(red: 255)
      elif y == 0: Pixel(red: 128, green: 64, alpha: 128)
      elif x == 0: Pixel(green: 255, alpha: 255)
      else: Pixel(blue: 255, alpha: 255)))
  proc target(label: string): GpuResourceHandle =
    host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
      width: 2, height: 2, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: label))
  let direct = target("channel-matrix-direct")
  let chained = target("channel-matrix-chained")
  let scratch = [target("channel-matrix-scratch-0"),
    target("channel-matrix-scratch-1"),
    target("channel-matrix-scratch-2")]
  let matrix = gpuChannelMatrix([
    1'f32, 0, 0, 0.25'f32, 0,
    0'f32, 1, 0, 0, 0,
    0'f32, 0, 1, 0, 0,
    0.5'f32, 0, 0, 0.5'f32, 0.25'f32
  ])
  let chain = host.newGpuFilterChain(ns,
    [channelMatrixStage(identityGpuChannelMatrix()),
      channelMatrixStage(matrix)], channelMatrix = material)
  let frame = host.beginGpuFrame()
  doAssert material.submit(source, direct, matrix)
  doAssert chain.submit(source, chained, scratch)
  host.endGpuFrame(frame)
  let directPixels = host.readPixels(ns, direct, 2, 2)
  directPixels.requirePixel(0, 0, Pixel(red: 191, alpha: 191),
    "RGBA matrix can derive new alpha from straight transparent RGB")
  directPixels.requirePixel(1, 0,
    Pixel(red: 120, green: 48, alpha: 192),
    "RGBA matrix combines color and source alpha in both directions")
  directPixels.requirePixel(0, 1,
    Pixel(red: 48, green: 191, alpha: 191),
    "RGBA matrix applies alpha offset to opaque green")
  let chainedPixels = host.readPixels(ns, chained, 2, 2)
  chainedPixels.requirePixel(0, 0, Pixel(alpha: 64),
    "chain unpremultiplies the prior transparent RenderTarget")
  chainedPixels.requirePixel(1, 0,
    Pixel(red: 120, green: 48, alpha: 192),
    "chain applies RGBA matrix to premultiplied color")
  chainedPixels.requirePixel(1, 1,
    Pixel(red: 48, blue: 191, alpha: 191),
    "chain preserves bottom-row RenderTarget orientation")
  material.release()
  for handle in [source, direct, chained,
      scratch[0], scratch[1], scratch[2]]:
    doAssert host.releaseGpuResource(handle)
  doAssert host.closeGpuNamespace(ns)
  echo "GPU channel matrix: alpha generation and chaining pixels passed"

proc verifyFilteredCanvasReadbackPixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("filtered-canvas-pixels", budget())
  var config = defaultGpuCanvasConfig(2, 2)
  config.alphaMode = gcamPremultiplied
  config.readbackSlots = 1
  config.sampledTarget = true
  let canvas = host.newGpuCanvasSurface(ns, config)
  let material = host.newGpuChannelMatrixMaterial(ns,
    compileShader(gpuChannelMatrixVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuChannelMatrixFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let source = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 2, height: 2, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "filtered-canvas-source"),
    rgbaPixels(2, 2, proc(x, y: int): Pixel =
      discard x
      discard y
      Pixel(red: 255, alpha: 128)))
  proc target(label: string): GpuResourceHandle =
    host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
      width: 2, height: 2, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: label))
  let output = target("filtered-canvas-output")
  let scratch = [target("filtered-canvas-scratch-0"),
    target("filtered-canvas-scratch-1"),
    target("filtered-canvas-scratch-2")]
  let blueFromRed = gpuChannelMatrix([
    0'f32, 0, 0, 0, 0,
    0'f32, 0, 0, 0, 0,
    1'f32, 0, 0, 0, 0,
    0'f32, 0, 0, 1, 0
  ])
  let chain = host.newGpuFilterChain(ns,
    [channelMatrixStage(blueFromRed)], channelMatrix = material)
  let frame = host.beginGpuFrame()
  doAssert material.submit(source, canvas.renderTarget(),
    identityGpuChannelMatrix())
  doAssert canvas.queueFilteredGpuCanvasFrame(chain, output, scratch)
  host.endGpuFrame(frame)
  var completed = false
  for attempt in 0 ..< 32:
    discard attempt
    pumpWindow()
    if canvas.collectGpuCanvasFrame():
      completed = true
      break
    let progress = host.beginGpuFrame()
    host.endGpuFrame(progress)
  doAssert completed
  doAssert canvas.rasterSurface.publish()
  canvas.rasterSurface.pixels.requirePixel(0, 0,
    Pixel(blue: 255, alpha: 128),
    "filtered canvas readback converts premultiplied output to straight RGBA")
  canvas.rasterSurface.pixels.requirePixel(1, 1,
    Pixel(blue: 255, alpha: 128),
    "filtered canvas keeps all pixels through a sampled target")
  doAssert canvas.closeGpuCanvasSurface()
  material.release()
  for handle in [source, output, scratch[0], scratch[1], scratch[2]]:
    doAssert host.releaseGpuResource(handle)
  doAssert host.closeGpuNamespace(ns)
  echo "GPU Canvas filter chain: sampled target and alpha-correct readback passed"

proc verifyFilteredDisplayPixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("filtered-display-pixels", budget())
  var config = defaultGpuDisplaySurfaceConfig(2, 2)
  config.bufferCount = 2
  config.fallback = gdsfRequireHybrid
  config.alphaMode = gcamPremultiplied
  let display = host.newGpuDisplaySurface(ns, config)
  let material = host.newGpuChannelMatrixMaterial(ns,
    compileShader(gpuChannelMatrixVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuChannelMatrixFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let source = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 2, height: 2, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "filtered-display-source"),
    rgbaPixels(2, 2, proc(x, y: int): Pixel =
      discard x
      discard y
      Pixel(red: 255, alpha: 128)))
  proc target(label: string): GpuResourceHandle =
    host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
      width: 2, height: 2, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: label))
  let output = target("filtered-display-output")
  let scratch = [target("filtered-display-scratch-0"),
    target("filtered-display-scratch-1"),
    target("filtered-display-scratch-2")]
  let blueFromRed = gpuChannelMatrix([
    0'f32, 0, 0, 0, 0,
    0'f32, 0, 0, 0, 0,
    1'f32, 0, 0, 0, 0,
    0'f32, 0, 0, 1, 0
  ])
  let chain = host.newGpuFilterChain(ns,
    [channelMatrixStage(blueFromRed)], channelMatrix = material)
  let frame = host.beginGpuFrame()
  doAssert display.queueFilteredGpuDisplayFrame(chain, source, output,
    scratch, frame)
  host.endGpuFrame(frame)
  var completed = false
  for attempt in 0 ..< 32:
    discard attempt
    pumpWindow()
    discard display.collectGpuDisplayFrame()
    if display.readbackSurface().completedFrameNumber == 1 and
        display.directSurface().presentedRevision == 1:
      completed = true
      break
    let progress = host.beginGpuFrame()
    host.endGpuFrame(progress)
  doAssert completed
  doAssert display.readbackSurface().rasterSurface().publish()
  display.readbackSurface().rasterSurface().pixels.requireRasterPixel(2,
    0, 0, Pixel(blue: 255, alpha: 128),
    "filtered hybrid readback converts premultiplied color")
  display.readbackSurface().rasterSurface().pixels.requireRasterPixel(2,
    1, 1, Pixel(blue: 255, alpha: 128),
    "filtered hybrid readback keeps every pixel")
  var directFrame = display.directSurface().acquireGpuDirectSurfaceFrame().get
  doAssert directFrame.resource == output
  doAssert directFrame.alphaMode == gcamPremultiplied
  doAssert directFrame.release()
  doAssert display.closeGpuDisplaySurface()
  material.release()
  for handle in [source, output, scratch[0], scratch[1], scratch[2]]:
    doAssert host.releaseGpuResource(handle)
  doAssert host.closeGpuNamespace(ns)
  echo "GPU filtered display: direct and alpha-correct readback pixels passed"

proc verifyOwnedGpuFilterDisplayPixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("owned-filter-display-pixels", budget())
  let material = host.newGpuChannelMatrixMaterial(ns,
    compileShader(gpuChannelMatrixVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuChannelMatrixFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let blueFromRed = gpuChannelMatrix([
    0'f32, 0, 0, 0, 0,
    0'f32, 0, 0, 0, 0,
    1'f32, 0, 0, 0, 0,
    0'f32, 0, 0, 1, 0
  ])
  let chain = host.newGpuFilterChain(ns,
    [channelMatrixStage(blueFromRed)], channelMatrix = material)
  var config = defaultGpuFilterDisplayConfig(2, 2)
  config.bufferCount = 2
  config.fallback = gdsfRequireHybrid
  let filtered = host.newGpuFilterDisplay(ns, chain, config)
  let display = filtered.displaySurface()
  let source = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 2, height: 2, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "owned-filter-display-source"),
    rgbaPixels(2, 2, proc(x, y: int): Pixel =
      discard x
      discard y
      Pixel(red: 255, alpha: 128)))
  let frame = host.beginGpuFrame()
  doAssert filtered.queueGpuFilterDisplayFrame(source, frame)
  host.endGpuFrame(frame)
  var completed = false
  for attempt in 0 ..< 32:
    discard attempt
    pumpWindow()
    discard filtered.collectGpuFilterDisplayFrame()
    if display.readbackSurface().completedFrameNumber == 1 and
        display.directSurface().presentedRevision == 1:
      completed = true
      break
    let progress = host.beginGpuFrame()
    host.endGpuFrame(progress)
  doAssert completed
  display.readbackSurface().rasterSurface().pixels.requireRasterPixel(2,
    0, 0, Pixel(blue: 255, alpha: 128),
    "owned filter display publishes straight translucent UI pixels")
  var directFrame = display.directSurface().acquireGpuDirectSurfaceFrame().get
  doAssert directFrame.alphaMode == gcamPremultiplied
  doAssert directFrame.release()
  doAssert filtered.closeGpuFilterDisplay()
  material.release()
  doAssert host.releaseGpuResource(source)
  doAssert host.closeGpuNamespace(ns)
  echo "GPU filter display: owned output ring publishes hybrid pixels passed"

proc verifyGpuAlphaMaskPixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("gpu-alpha-mask-pixels", budget())
  let material = host.newGpuAlphaMaskMaterial(ns,
    compileShader(gpuAlphaMaskVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuAlphaMaskFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let matrix = host.newGpuColorMatrixMaterial(ns,
    compileShader(gpuColorMatrixVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuColorMatrixFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let source = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 2, height: 2, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "alpha-mask-source"),
    rgbaPixels(2, 2, proc(x, y: int): Pixel =
      if y == 0 and x == 0: Pixel(red: 255, alpha: 128)
      elif y == 0: Pixel(green: 255, alpha: 255)
      elif x == 0: Pixel(blue: 255, alpha: 255)
      else: Pixel(red: 255)))
  let mask = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 2, height: 2, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "alpha-mask-coverage"),
    rgbaPixels(2, 2, proc(x, y: int): Pixel =
      if y == 0 and x == 0: Pixel(green: 255, alpha: 128)
      elif y == 0: Pixel(red: 255)
      else: Pixel(red: 255, green: 255, alpha: 255)))
  proc target(label: string): GpuResourceHandle =
    host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
      width: 2, height: 2, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: label))
  let output = target("alpha-mask-output")
  let chained = target("alpha-mask-chained")
  let inverted = target("alpha-mask-inverted")
  let softened = target("alpha-mask-softened")
  let unmasked = target("alpha-mask-zero-strength")
  let chainedInverted = target("alpha-mask-chained-inverted")
  let luminance = target("alpha-mask-luminance")
  let premultLuminance = target("alpha-mask-premult-luminance")
  let opaqueLuminance = target("alpha-mask-opaque-luminance")
  let invertedLuminance = target("alpha-mask-inverted-luminance")
  let chainedLuminance = target("alpha-mask-chained-luminance")
  let maskTarget = target("alpha-mask-render-target")
  let scratch = [target("alpha-mask-scratch-0"),
    target("alpha-mask-scratch-1"), target("alpha-mask-scratch-2")]
  let swapRedBlue = colorMatrixFilter([
    0'f32, 0, 1, 0,
    0'f32, 1, 0, 0,
    1'f32, 0, 0, 0
  ])
  let chain = host.newGpuFilterChain(ns,
    [colorMatrixStage(swapRedBlue), alphaMaskStage(maskTarget)],
    colorMatrix = matrix, alphaMask = material)
  let invertedChain = host.newGpuFilterChain(ns,
    [colorMatrixStage(swapRedBlue),
      alphaMaskStage(maskTarget, invertMask = true,
        maskStrength = 0.5'f32)],
    colorMatrix = matrix, alphaMask = material)
  let luminanceChain = host.newGpuFilterChain(ns,
    [colorMatrixStage(swapRedBlue),
      alphaMaskStage(maskTarget, maskMode = gmmLuminance,
        maskAlphaMode = gcamPremultiplied)],
    colorMatrix = matrix, alphaMask = material)
  let frame = host.beginGpuFrame()
  doAssert matrix.submit(mask, maskTarget, nil, gcamStraight)
  doAssert material.submit(source, mask, output, gcamStraight)
  doAssert chain.submit(source, chained, scratch, gcamStraight)
  doAssert material.submit(source, mask, inverted, invertMask = true)
  doAssert material.submit(source, mask, softened, maskStrength = 0.5'f32)
  doAssert material.submit(source, mask, unmasked, maskStrength = 0'f32)
  doAssert invertedChain.submit(source, chainedInverted, scratch)
  doAssert material.submit(source, mask, luminance,
    maskMode = gmmLuminance)
  doAssert material.submit(source, maskTarget, premultLuminance,
    maskMode = gmmLuminance, maskAlphaMode = gcamPremultiplied)
  doAssert material.submit(source, mask, opaqueLuminance,
    maskMode = gmmLuminance, maskAlphaMode = gcamOpaque)
  doAssert material.submit(source, mask, invertedLuminance,
    invertMask = true, maskStrength = 0.5'f32,
    maskMode = gmmLuminance)
  doAssert luminanceChain.submit(source, chainedLuminance, scratch)
  host.endGpuFrame(frame)
  let pixels = host.readPixels(ns, output, 2, 2)
  pixels.requirePixel(0, 0, Pixel(red: 64, alpha: 64),
    "GPU alpha mask combines translucent source and half coverage")
  pixels.requirePixel(1, 0, Pixel(),
    "GPU alpha mask removes fully masked source")
  pixels.requirePixel(0, 1, Pixel(blue: 255, alpha: 255),
    "GPU alpha mask keeps unmasked source without mask RGB")
  pixels.requirePixel(1, 1, Pixel(),
    "GPU alpha mask keeps transparent source empty")
  let chainedPixels = host.readPixels(ns, chained, 2, 2)
  chainedPixels.requirePixel(0, 0, Pixel(blue: 64, alpha: 64),
    "GPU filter chain masks premultiplied matrix output")
  chainedPixels.requirePixel(0, 1, Pixel(red: 255, alpha: 255),
    "GPU filter chain retains opaque masked pixel")
  let invertedPixels = host.readPixels(ns, inverted, 2, 2)
  invertedPixels.requirePixel(0, 0, Pixel(red: 64, alpha: 64),
    "GPU inverted alpha mask keeps complementary half coverage")
  invertedPixels.requirePixel(1, 0, Pixel(green: 255, alpha: 255),
    "GPU inverted alpha mask reveals a zero-mask pixel")
  invertedPixels.requirePixel(0, 1, Pixel(),
    "GPU inverted alpha mask hides a full-mask pixel")
  let softenedPixels = host.readPixels(ns, softened, 2, 2)
  softenedPixels.requirePixel(0, 0, Pixel(red: 96, alpha: 96),
    "GPU mask strength mixes half coverage with unmasked source")
  softenedPixels.requirePixel(1, 0, Pixel(green: 128, alpha: 128),
    "GPU mask strength partially reveals a zero-mask pixel")
  softenedPixels.requirePixel(0, 1, Pixel(blue: 255, alpha: 255),
    "GPU mask strength preserves full-mask coverage")
  let unmaskedPixels = host.readPixels(ns, unmasked, 2, 2)
  unmaskedPixels.requirePixel(0, 0, Pixel(red: 128, alpha: 128),
    "GPU zero-strength mask preserves translucent source")
  unmaskedPixels.requirePixel(1, 0, Pixel(green: 255, alpha: 255),
    "GPU zero-strength mask preserves opaque source")
  let chainedInvertedPixels = host.readPixels(ns, chainedInverted, 2, 2)
  chainedInvertedPixels.requirePixel(0, 0, Pixel(blue: 96, alpha: 96),
    "GPU chain applies inverted mask strength to matrix output")
  chainedInvertedPixels.requirePixel(1, 0, Pixel(green: 255, alpha: 255),
    "GPU chain reveals a zero-mask pixel with inversion")
  chainedInvertedPixels.requirePixel(0, 1, Pixel(red: 128, alpha: 128),
    "GPU chain softens an inverted full-mask pixel")
  for item in [luminance, premultLuminance]:
    let maskPixels = host.readPixels(ns, item, 2, 2)
    maskPixels.requirePixel(0, 0, Pixel(red: 46, alpha: 46),
      "luminance mask multiplies green brightness by mask alpha")
    maskPixels.requirePixel(1, 0, Pixel(),
      "luminance mask removes transparent red")
    maskPixels.requirePixel(0, 1, Pixel(blue: 237, alpha: 237),
      "luminance mask uses red and green brightness")
  let opaqueLuminancePixels = host.readPixels(ns, opaqueLuminance, 2, 2)
  opaqueLuminancePixels.requirePixel(1, 0,
    Pixel(green: 54, alpha: 54),
    "opaque luminance mask ignores sampled alpha")
  let invertedLuminancePixels = host.readPixels(ns, invertedLuminance, 2, 2)
  invertedLuminancePixels.requirePixel(0, 0,
    Pixel(red: 105, alpha: 105),
    "luminance inversion and strength follow coverage calculation")
  invertedLuminancePixels.requirePixel(1, 0,
    Pixel(green: 255, alpha: 255),
    "inverted luminance reveals transparent mask pixels")
  let chainedLuminancePixels = host.readPixels(ns, chainedLuminance, 2, 2)
  chainedLuminancePixels.requirePixel(0, 0,
    Pixel(blue: 46, alpha: 46),
    "filter chain accepts premultiplied luminance masks")
  chainedLuminancePixels.requirePixel(0, 1,
    Pixel(red: 237, alpha: 237),
    "filter chain applies luminance after color matrix")
  material.release()
  matrix.release()
  for handle in [source, mask, output, chained, inverted, softened,
      unmasked, chainedInverted, luminance, premultLuminance,
      opaqueLuminance, invertedLuminance, chainedLuminance, maskTarget,
      scratch[0], scratch[1], scratch[2]]:
    doAssert host.releaseGpuResource(handle)
  doAssert host.closeGpuNamespace(ns)
  echo "GPU alpha mask: direct and chained inversion/strength pixels passed"

proc verifyGpuAlphaMaskPlacementPixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("gpu-alpha-mask-placement-pixels", budget())
  let vertex = compileShader(gpuAlphaMaskVertexSource(), shaderc,
    shaderIncludes, workDirectory)
  let fragment = compileShader(gpuAlphaMaskFragmentSource(), shaderc,
    shaderIncludes, workDirectory)
  let material = host.newGpuAlphaMaskMaterial(ns, vertex, fragment)
  let linearMaterial = host.newGpuAlphaMaskMaterial(ns, vertex, fragment,
    maskFilter = gsfLinear)
  let source = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 4, height: 4, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "placed-mask-source"),
    rgbaPixels(4, 4, proc(x, y: int): Pixel =
      Pixel(red: 255, alpha: 255)))
  let mask = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 2, height: 2, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "placed-mask-coverage"),
    rgbaPixels(2, 2, proc(x, y: int): Pixel =
      if y == 0 and x == 0: Pixel(alpha: 128)
      elif y == 0: Pixel()
      elif x == 0: Pixel(alpha: 255)
      else: Pixel(alpha: 64)))
  proc target(label: string): GpuResourceHandle =
    host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
      width: 4, height: 4, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: label))
  let centered = target("placed-mask-centered")
  let inverted = target("placed-mask-inverted")
  let softened = target("placed-mask-softened")
  let scaled = target("placed-mask-scaled")
  let linearScaled = target("placed-mask-linear-scaled")
  let cropped = target("placed-mask-cropped")
  let croppedChained = target("placed-mask-cropped-chained")
  let clipped = target("placed-mask-clipped")
  let chained = target("placed-mask-chained")
  let linearChained = target("placed-mask-linear-chained")
  let scratch = [target("placed-mask-scratch-0"),
    target("placed-mask-scratch-1"), target("placed-mask-scratch-2")]
  let center = gpuAlphaMaskPlacement(1, 1, 2, 2)
  let chain = host.newGpuFilterChain(ns,
    [alphaMaskStage(mask, invertMask = true, maskStrength = 0.5'f32,
      maskPlacement = center)], alphaMask = material)
  let linearChain = host.newGpuFilterChain(ns,
    [alphaMaskStage(mask,
      maskPlacement = gpuAlphaMaskPlacement(0, 0, 4, 4))],
    alphaMask = linearMaterial)
  let crop = gpuAlphaMaskCrop(0, 0, 1, 2)
  let cropChain = host.newGpuFilterChain(ns,
    [alphaMaskStage(mask, maskCrop = crop)],
    alphaMask = linearMaterial)
  let frame = host.beginGpuFrame()
  doAssert material.submit(source, mask, centered,
    maskPlacement = center)
  doAssert material.submit(source, mask, inverted,
    invertMask = true, maskPlacement = center)
  doAssert material.submit(source, mask, softened,
    maskStrength = 0.5'f32, maskPlacement = center)
  doAssert material.submit(source, mask, scaled,
    maskPlacement = gpuAlphaMaskPlacement(0, 0, 4, 4))
  doAssert linearMaterial.submit(source, mask, linearScaled,
    maskPlacement = gpuAlphaMaskPlacement(0, 0, 4, 4))
  doAssert linearMaterial.submit(source, mask, cropped,
    maskCrop = crop)
  doAssert material.submit(source, mask, clipped,
    maskPlacement = gpuAlphaMaskPlacement(-1, -1, 2, 2))
  doAssert chain.submit(source, chained, scratch)
  doAssert linearChain.submit(source, linearChained, scratch)
  doAssert cropChain.submit(source, croppedChained, scratch)
  host.endGpuFrame(frame)
  let centeredPixels = host.readPixels(ns, centered, 4, 4)
  centeredPixels.requirePixel(0, 0, Pixel(),
    "placed mask clears source outside its bounds")
  centeredPixels.requirePixel(1, 1, Pixel(red: 128, alpha: 128),
    "placed mask applies half coverage at its top-left")
  centeredPixels.requirePixel(2, 1, Pixel(),
    "placed mask keeps zero coverage inside")
  centeredPixels.requirePixel(1, 2, Pixel(red: 255, alpha: 255),
    "placed mask applies full coverage inside")
  let invertedPixels = host.readPixels(ns, inverted, 4, 4)
  invertedPixels.requirePixel(0, 0, Pixel(red: 255, alpha: 255),
    "inverted placed mask reveals source outside its bounds")
  invertedPixels.requirePixel(1, 1, Pixel(red: 127, alpha: 127),
    "inverted placed mask complements half coverage")
  invertedPixels.requirePixel(1, 2, Pixel(),
    "inverted placed mask removes full-coverage source")
  let softenedPixels = host.readPixels(ns, softened, 4, 4)
  softenedPixels.requirePixel(0, 0, Pixel(red: 128, alpha: 128),
    "half-strength placed mask preserves source outside bounds")
  softenedPixels.requirePixel(1, 1, Pixel(red: 192, alpha: 192),
    "half-strength placed mask mixes half coverage")
  softenedPixels.requirePixel(2, 1, Pixel(red: 128, alpha: 128),
    "half-strength placed mask mixes zero coverage")
  let scaledPixels = host.readPixels(ns, scaled, 4, 4)
  scaledPixels.requirePixel(0, 0, Pixel(red: 128, alpha: 128),
    "scaled mask repeats its top-left texel")
  scaledPixels.requirePixel(3, 0, Pixel(),
    "scaled mask keeps its top-right zero texel")
  scaledPixels.requirePixel(0, 3, Pixel(red: 255, alpha: 255),
    "scaled mask reaches bottom-left")
  for item in [linearScaled, linearChained]:
    let pixels = host.readPixels(ns, item, 4, 4)
    pixels.requirePixel(1, 1, Pixel(red: 124, alpha: 124),
      "linear mask interpolates nearby coverage")
    pixels.requirePixel(2, 2, Pixel(red: 92, alpha: 92),
      "linear mask interpolates all four source texels")
  for item in [cropped, croppedChained]:
    let pixels = host.readPixels(ns, item, 4, 4)
    pixels.requirePixel(3, 0, Pixel(red: 128, alpha: 128),
      "cropped mask clamps linear samples to its first column")
    pixels.requirePixel(3, 3, Pixel(red: 255, alpha: 255),
      "cropped mask reaches its lower source texel")
  let clippedPixels = host.readPixels(ns, clipped, 4, 4)
  clippedPixels.requirePixel(0, 0, Pixel(red: 64, alpha: 64),
    "negative mask placement clips to bottom-right texel")
  clippedPixels.requirePixel(1, 0, Pixel(),
    "clipped mask does not smear beyond its bounds")
  let chainedPixels = host.readPixels(ns, chained, 4, 4)
  chainedPixels.requirePixel(0, 0, Pixel(red: 255, alpha: 255),
    "chained inverted mask reveals source outside placement")
  chainedPixels.requirePixel(1, 1, Pixel(red: 191, alpha: 191),
    "chained placed mask combines inversion and strength")
  chainedPixels.requirePixel(1, 2, Pixel(red: 128, alpha: 128),
    "chained placed mask softens inverted full coverage")
  material.release()
  linearMaterial.release()
  for handle in [source, mask, centered, inverted, softened, scaled,
      linearScaled, cropped, croppedChained, clipped, chained, linearChained,
      scratch[0], scratch[1], scratch[2]]:
    doAssert host.releaseGpuResource(handle)
  doAssert host.closeGpuNamespace(ns)
  echo "GPU mask placement: clipping, scaling, inversion, and chaining passed"

proc verifyGpuCompositePixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("gpu-composite-pixels", budget())
  let composite = host.newGpuCompositeMaterial(ns,
    compileShader(gpuCompositeVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuCompositeFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let matrix = host.newGpuColorMatrixMaterial(ns,
    compileShader(gpuColorMatrixVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuColorMatrixFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let backdrop = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 2, height: 2, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "composite-backdrop"),
    rgbaPixels(2, 2, proc(x, y: int): Pixel =
      if y == 0 and x == 0: Pixel(blue: 255, alpha: 128)
      elif y == 0: Pixel(green: 255, alpha: 255)
      elif x == 0: Pixel(red: 255)
      else: Pixel(red: 64, green: 128, blue: 192, alpha: 255)))
  let foreground = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 2, height: 2, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "composite-foreground"),
    rgbaPixels(2, 2, proc(x, y: int): Pixel =
      if y == 0 and x == 0: Pixel(red: 255, alpha: 128)
      elif y == 0: Pixel(green: 255)
      elif x == 0: Pixel(green: 255, alpha: 128)
      else: Pixel(red: 192, green: 96, blue: 32, alpha: 255)))
  proc target(label: string): GpuResourceHandle =
    host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
      width: 2, height: 2, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: label))
  let premultipliedForeground = target("composite-foreground-target")
  let output = target("composite-output")
  let chained = target("composite-chained")
  let multiplied = target("composite-multiplied")
  let screened = target("composite-screened")
  let halfNormal = target("composite-half-normal")
  let halfScreen = target("composite-half-screen")
  let zeroForeground = target("composite-zero-foreground")
  let chainedHalfNormal = target("composite-chained-half-normal")
  let chainedHalfScreen = target("composite-chained-half-screen")
  let overlaid = target("composite-overlaid")
  let darkened = target("composite-darkened")
  let lightened = target("composite-lightened")
  let differenced = target("composite-differenced")
  let excluded = target("composite-excluded")
  let dodged = target("composite-color-dodged")
  let burned = target("composite-color-burned")
  let hardLit = target("composite-hard-lit")
  let softLit = target("composite-soft-lit")
  let hued = target("composite-hued")
  let saturated = target("composite-saturated")
  let colored = target("composite-colored")
  let luminosity = target("composite-luminosity")
  let plusLighter = target("composite-plus-lighter")
  let halfPlusLighter = target("composite-half-plus-lighter")
  let chainedMultiply = target("composite-chained-multiply")
  let chainedScreen = target("composite-chained-screen")
  let chainedOverlay = target("composite-chained-overlay")
  let chainedDarken = target("composite-chained-darken")
  let chainedLighten = target("composite-chained-lighten")
  let chainedDifference = target("composite-chained-difference")
  let chainedExclusion = target("composite-chained-exclusion")
  let chainedDodge = target("composite-chained-dodge")
  let chainedBurn = target("composite-chained-burn")
  let chainedHardLight = target("composite-chained-hard-light")
  let chainedSoftLight = target("composite-chained-soft-light")
  let chainedHue = target("composite-chained-hue")
  let chainedSaturation = target("composite-chained-saturation")
  let chainedColor = target("composite-chained-color")
  let chainedLuminosity = target("composite-chained-luminosity")
  let chainedPlusLighter = target("composite-chained-plus-lighter")
  let scratch = [target("composite-scratch-0"),
    target("composite-scratch-1"), target("composite-scratch-2")]
  let midBackdrop = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 1, height: 1, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "composite-mid-backdrop"),
    rgbaPixels(1, 1, proc(x, y: int): Pixel =
      Pixel(red: 64, green: 160, blue: 192, alpha: 255)))
  let midForeground = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 1, height: 1, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "composite-mid-foreground"),
    rgbaPixels(1, 1, proc(x, y: int): Pixel =
      Pixel(red: 64, green: 192, blue: 128, alpha: 255)))
  proc midTarget(label: string): GpuResourceHandle =
    host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
      width: 1, height: 1, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: label))
  let midDodge = midTarget("composite-mid-dodge")
  let midBurn = midTarget("composite-mid-burn")
  let grayBackdrop = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 1, height: 1, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "composite-gray-backdrop"),
    rgbaPixels(1, 1, proc(x, y: int): Pixel =
      Pixel(red: 128, green: 128, blue: 128, alpha: 255)))
  let grayForeground = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 1, height: 1, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "composite-gray-foreground"),
    rgbaPixels(1, 1, proc(x, y: int): Pixel =
      Pixel(red: 255, alpha: 255)))
  let grayHue = midTarget("composite-gray-hue")
  let graySaturation = midTarget("composite-gray-saturation")
  let chain = host.newGpuFilterChain(ns,
    [compositeStage(foreground)], composite = composite)
  let multiplyChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmMultiply)],
    composite = composite)
  let screenChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmScreen)],
    composite = composite)
  let halfNormalChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, foregroundOpacity = 0.5'f32)],
    composite = composite)
  let halfScreenChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmScreen,
      foregroundOpacity = 0.5'f32)], composite = composite)
  let overlayChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmOverlay)],
    composite = composite)
  let darkenChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmDarken)],
    composite = composite)
  let lightenChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmLighten)],
    composite = composite)
  let differenceChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmDifference)],
    composite = composite)
  let exclusionChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmExclusion)],
    composite = composite)
  let dodgeChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmColorDodge)],
    composite = composite)
  let burnChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmColorBurn)],
    composite = composite)
  let hardLightChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmHardLight)],
    composite = composite)
  let softLightChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmSoftLight)],
    composite = composite)
  let hueChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmHue)],
    composite = composite)
  let saturationChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmSaturation)],
    composite = composite)
  let colorChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmColor)],
    composite = composite)
  let luminosityChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmLuminosity)],
    composite = composite)
  let plusLighterChain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmPlusLighter)],
    composite = composite)
  let frame = host.beginGpuFrame()
  doAssert matrix.submit(foreground, premultipliedForeground, nil)
  doAssert composite.submit(backdrop, premultipliedForeground,
    output, gcamStraight, gcamPremultiplied)
  doAssert chain.submit(backdrop, chained, scratch)
  doAssert composite.submit(backdrop, premultipliedForeground,
    multiplied, gcamStraight, gcamPremultiplied, gcbmMultiply)
  doAssert composite.submit(backdrop, premultipliedForeground,
    screened, gcamStraight, gcamPremultiplied, gcbmScreen)
  doAssert composite.submit(backdrop, premultipliedForeground,
    halfNormal, gcamStraight, gcamPremultiplied,
    foregroundOpacity = 0.5'f32)
  doAssert composite.submit(backdrop, premultipliedForeground,
    halfScreen, gcamStraight, gcamPremultiplied, gcbmScreen, 0.5'f32)
  doAssert composite.submit(backdrop, foreground,
    zeroForeground, foregroundOpacity = 0'f32)
  doAssert halfNormalChain.submit(backdrop, chainedHalfNormal, scratch)
  doAssert halfScreenChain.submit(backdrop, chainedHalfScreen, scratch)
  doAssert composite.submit(backdrop, premultipliedForeground,
    overlaid, gcamStraight, gcamPremultiplied, gcbmOverlay)
  doAssert composite.submit(backdrop, premultipliedForeground,
    darkened, gcamStraight, gcamPremultiplied, gcbmDarken)
  doAssert composite.submit(backdrop, premultipliedForeground,
    lightened, gcamStraight, gcamPremultiplied, gcbmLighten)
  doAssert composite.submit(backdrop, premultipliedForeground,
    differenced, gcamStraight, gcamPremultiplied, gcbmDifference)
  doAssert composite.submit(backdrop, premultipliedForeground,
    excluded, gcamStraight, gcamPremultiplied, gcbmExclusion)
  doAssert composite.submit(backdrop, premultipliedForeground,
    dodged, gcamStraight, gcamPremultiplied, gcbmColorDodge)
  doAssert composite.submit(backdrop, premultipliedForeground,
    burned, gcamStraight, gcamPremultiplied, gcbmColorBurn)
  doAssert composite.submit(backdrop, premultipliedForeground,
    hardLit, gcamStraight, gcamPremultiplied, gcbmHardLight)
  doAssert composite.submit(backdrop, premultipliedForeground,
    softLit, gcamStraight, gcamPremultiplied, gcbmSoftLight)
  doAssert composite.submit(backdrop, premultipliedForeground,
    hued, gcamStraight, gcamPremultiplied, gcbmHue)
  doAssert composite.submit(backdrop, premultipliedForeground,
    saturated, gcamStraight, gcamPremultiplied, gcbmSaturation)
  doAssert composite.submit(backdrop, premultipliedForeground,
    colored, gcamStraight, gcamPremultiplied, gcbmColor)
  doAssert composite.submit(backdrop, premultipliedForeground,
    luminosity, gcamStraight, gcamPremultiplied, gcbmLuminosity)
  doAssert composite.submit(backdrop, premultipliedForeground,
    plusLighter, gcamStraight, gcamPremultiplied, gcbmPlusLighter)
  doAssert composite.submit(backdrop, premultipliedForeground,
    halfPlusLighter, gcamStraight, gcamPremultiplied,
    gcbmPlusLighter, 0.5'f32)
  doAssert multiplyChain.submit(backdrop, chainedMultiply, scratch)
  doAssert screenChain.submit(backdrop, chainedScreen, scratch)
  doAssert overlayChain.submit(backdrop, chainedOverlay, scratch)
  doAssert darkenChain.submit(backdrop, chainedDarken, scratch)
  doAssert lightenChain.submit(backdrop, chainedLighten, scratch)
  doAssert differenceChain.submit(backdrop, chainedDifference, scratch)
  doAssert exclusionChain.submit(backdrop, chainedExclusion, scratch)
  doAssert dodgeChain.submit(backdrop, chainedDodge, scratch)
  doAssert burnChain.submit(backdrop, chainedBurn, scratch)
  doAssert hardLightChain.submit(backdrop, chainedHardLight, scratch)
  doAssert softLightChain.submit(backdrop, chainedSoftLight, scratch)
  doAssert hueChain.submit(backdrop, chainedHue, scratch)
  doAssert saturationChain.submit(backdrop, chainedSaturation, scratch)
  doAssert colorChain.submit(backdrop, chainedColor, scratch)
  doAssert luminosityChain.submit(backdrop, chainedLuminosity, scratch)
  doAssert plusLighterChain.submit(backdrop, chainedPlusLighter, scratch)
  doAssert composite.submit(midBackdrop, midForeground,
    midDodge, blendMode = gcbmColorDodge)
  doAssert composite.submit(midBackdrop, midForeground,
    midBurn, blendMode = gcbmColorBurn)
  doAssert composite.submit(grayBackdrop, grayForeground,
    grayHue, blendMode = gcbmHue)
  doAssert composite.submit(grayBackdrop, grayForeground,
    graySaturation, blendMode = gcbmSaturation)
  host.endGpuFrame(frame)
  for item in [output, chained]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 128, blue: 64, alpha: 192),
      "GPU source-over combines two translucent pixels")
    pixels.requirePixel(1, 0, Pixel(green: 255, alpha: 255),
      "GPU source-over preserves backdrop through transparent foreground")
    pixels.requirePixel(0, 1, Pixel(green: 128, alpha: 128),
      "GPU source-over discards transparent backdrop color")
    pixels.requirePixel(1, 1, Pixel(red: 192, green: 96, blue: 32,
      alpha: 255),
      "GPU source-over keeps opaque foreground")
  for item in [multiplied, chainedMultiply]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 64, blue: 64, alpha: 192),
      "GPU multiply blends two translucent pixels")
    pixels.requirePixel(1, 0, Pixel(green: 255, alpha: 255),
      "GPU multiply preserves backdrop through transparent foreground")
    pixels.requirePixel(0, 1, Pixel(green: 128, alpha: 128),
      "GPU multiply preserves foreground over transparent backdrop")
    pixels.requirePixel(1, 1, Pixel(red: 48, green: 48, blue: 24,
      alpha: 255), "GPU multiply blends opaque midtones")
  for item in [screened, chainedScreen]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 128, blue: 128, alpha: 192),
      "GPU screen blends two translucent pixels")
    pixels.requirePixel(1, 0, Pixel(green: 255, alpha: 255),
      "GPU screen preserves backdrop through transparent foreground")
    pixels.requirePixel(0, 1, Pixel(green: 128, alpha: 128),
      "GPU screen preserves foreground over transparent backdrop")
    pixels.requirePixel(1, 1, Pixel(red: 208, green: 176, blue: 200,
      alpha: 255), "GPU screen blends opaque midtones")
  for item in [halfNormal, chainedHalfNormal]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 64, blue: 96, alpha: 160),
      "GPU half-opacity source-over scales translucent foreground")
    pixels.requirePixel(1, 0, Pixel(green: 255, alpha: 255),
      "GPU half-opacity source-over preserves transparent foreground")
    pixels.requirePixel(1, 1, Pixel(red: 128, green: 112, blue: 112,
      alpha: 255), "GPU half-opacity source-over mixes opaque colors")
  for item in [halfScreen, chainedHalfScreen]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 64, blue: 128, alpha: 160),
      "GPU half-opacity screen scales translucent foreground")
    pixels.requirePixel(1, 1, Pixel(red: 136, green: 152, blue: 196,
      alpha: 255), "GPU half-opacity screen blends opaque colors")
  let zeroPixels = host.readPixels(ns, zeroForeground, 2, 2)
  zeroPixels.requirePixel(0, 0, Pixel(blue: 128, alpha: 128),
    "GPU zero-opacity foreground preserves premultiplied backdrop")
  zeroPixels.requirePixel(1, 1, Pixel(red: 64, green: 128, blue: 192,
    alpha: 255), "GPU zero-opacity foreground preserves opaque backdrop")
  for item in [overlaid, chainedOverlay]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 64, blue: 128, alpha: 192),
      "GPU overlay preserves half-transparent backdrop highlight")
    pixels.requirePixel(1, 1, Pixel(red: 96, green: 97, blue: 145,
      alpha: 255), "GPU overlay selects low and high branches by backdrop")
  for item in [darkened, chainedDarken]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 64, blue: 64, alpha: 192),
      "GPU darken blends translucent colors")
    pixels.requirePixel(1, 1, Pixel(red: 64, green: 96, blue: 32,
      alpha: 255), "GPU darken selects each lower channel")
  for item in [lightened, chainedLighten]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 128, blue: 128, alpha: 192),
      "GPU lighten blends translucent colors")
    pixels.requirePixel(1, 1, Pixel(red: 192, green: 128, blue: 192,
      alpha: 255), "GPU lighten selects each higher channel")
  for item in [differenced, chainedDifference]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 128, blue: 128,
      alpha: 192), "GPU difference blends translucent colors")
    pixels.requirePixel(1, 1, Pixel(red: 128, green: 32,
      blue: 160, alpha: 255), "GPU difference subtracts each channel")
  for item in [excluded, chainedExclusion]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 128, blue: 128,
      alpha: 192), "GPU exclusion blends translucent colors")
    pixels.requirePixel(1, 1, Pixel(red: 160, green: 128,
      blue: 176, alpha: 255), "GPU exclusion keeps lower contrast")
  for item in [dodged, chainedDodge]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 64, blue: 128, alpha: 192),
      "GPU color dodge preserves transparent overlap edges")
    pixels.requirePixel(1, 1, Pixel(red: 255, green: 205,
      blue: 220, alpha: 255), "GPU color dodge brightens midtones")
  for item in [burned, chainedBurn]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 64, blue: 128, alpha: 192),
      "GPU color burn handles zero and unit channels")
    pixels.requirePixel(1, 1, Pixel(red: 1, alpha: 255),
      "GPU color burn darkens midtones")
  for item in [hardLit, chainedHardLight]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 128, blue: 64, alpha: 192),
      "GPU hard light uses source color for its branch")
    pixels.requirePixel(1, 1, Pixel(red: 161, green: 96,
      blue: 48, alpha: 255), "GPU hard light combines low and high channels")
  for item in [softLit, chainedSoftLight]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 64, blue: 128, alpha: 192),
      "GPU soft light blends translucent channel extremes")
    pixels.requirePixel(1, 1, Pixel(red: 96, green: 112,
      blue: 156, alpha: 255), "GPU soft light uses cubic and square-root curves")
  for item in [hued, chainedHue]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 87, blue: 64, alpha: 192),
      "GPU hue blends translucent source color")
    pixels.requirePixel(1, 0, Pixel(green: 255, alpha: 255),
      "GPU hue preserves backdrop through transparent foreground")
    pixels.requirePixel(0, 1, Pixel(green: 128, alpha: 128),
      "GPU hue preserves source over transparent backdrop")
    pixels.requirePixel(1, 1, Pixel(red: 175, green: 98, blue: 47,
      alpha: 255), "GPU hue retains backdrop saturation and luminosity")
  for item in [saturated, chainedSaturation]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 64, blue: 128, alpha: 192),
      "GPU saturation blends translucent source color")
    pixels.requirePixel(1, 1, Pixel(red: 51, green: 131, blue: 211,
      alpha: 255), "GPU saturation retains backdrop hue and luminosity")
  for item in [colored, chainedColor]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 87, blue: 64, alpha: 192),
      "GPU color blends translucent source color")
    pixels.requirePixel(1, 1, Pixel(red: 190, green: 94, blue: 30,
      alpha: 255), "GPU color retains backdrop luminosity")
  for item in [luminosity, chainedLuminosity]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 77, green: 14, blue: 128,
      alpha: 192), "GPU luminosity blends translucent source color")
    pixels.requirePixel(1, 1, Pixel(red: 66, green: 130, blue: 194,
      alpha: 255), "GPU luminosity retains backdrop hue and saturation")
  for item in [plusLighter, chainedPlusLighter]:
    let pixels = host.readPixels(ns, item, 2, 2)
    pixels.requirePixel(0, 0, Pixel(red: 128, blue: 128, alpha: 255),
      "GPU plus-lighter adds translucent premultiplied colors and alpha")
    pixels.requirePixel(1, 0, Pixel(green: 255, alpha: 255),
      "GPU plus-lighter ignores transparent source color")
    pixels.requirePixel(0, 1, Pixel(green: 128, alpha: 128),
      "GPU plus-lighter preserves color over transparent backdrop")
    pixels.requirePixel(1, 1, Pixel(red: 255, green: 224, blue: 224,
      alpha: 255), "GPU plus-lighter saturates opaque overlap")
  let halfPlusPixels = host.readPixels(ns, halfPlusLighter, 2, 2)
  halfPlusPixels.requirePixel(0, 0,
    Pixel(red: 64, blue: 128, alpha: 192),
    "GPU plus-lighter applies foreground opacity before addition")
  halfPlusPixels.requirePixel(1, 1,
    Pixel(red: 160, green: 176, blue: 208, alpha: 255),
    "GPU plus-lighter scales opaque foreground color")
  let midDodgePixels = host.readPixels(ns, midDodge, 1, 1)
  midDodgePixels.requirePixel(0, 0, Pixel(red: 85, green: 255,
    blue: 255, alpha: 255), "GPU color dodge includes unsaturated channels")
  let midBurnPixels = host.readPixels(ns, midBurn, 1, 1)
  midBurnPixels.requirePixel(0, 0, Pixel(green: 129, blue: 129,
    alpha: 255), "GPU color burn includes nonzero channels")
  let grayHuePixels = host.readPixels(ns, grayHue, 1, 1)
  grayHuePixels.requirePixel(0, 0, Pixel(red: 128, green: 128,
    blue: 128, alpha: 255), "GPU hue handles zero backdrop saturation")
  let graySaturationPixels = host.readPixels(ns, graySaturation, 1, 1)
  graySaturationPixels.requirePixel(0, 0, Pixel(red: 128, green: 128,
    blue: 128, alpha: 255), "GPU saturation handles zero backdrop range")
  composite.release()
  matrix.release()
  for handle in [backdrop, foreground, premultipliedForeground,
      output, chained, multiplied, screened, halfNormal, halfScreen,
      zeroForeground, chainedHalfNormal, chainedHalfScreen,
      overlaid, darkened, lightened,
      differenced, excluded, dodged, burned, hardLit, softLit,
      hued, saturated, colored, luminosity, plusLighter, halfPlusLighter,
      chainedMultiply, chainedScreen, chainedOverlay,
      chainedDarken, chainedLighten, chainedDifference, chainedExclusion,
      chainedDodge, chainedBurn, chainedHardLight, chainedSoftLight,
      chainedHue, chainedSaturation, chainedColor, chainedLuminosity,
      chainedPlusLighter,
      scratch[0], scratch[1], scratch[2], midBackdrop, midForeground,
      midDodge, midBurn, grayBackdrop, grayForeground,
      grayHue, graySaturation]:
    doAssert host.releaseGpuResource(handle)
  doAssert host.closeGpuNamespace(ns)
  echo "GPU blend and plus-lighter modes: direct and chained pixels passed"

proc verifyGpuCompositePlacementPixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("gpu-composite-placement-pixels", budget())
  let vertex = compileShader(gpuCompositeVertexSource(), shaderc,
    shaderIncludes, workDirectory)
  let fragment = compileShader(gpuCompositeFragmentSource(), shaderc,
    shaderIncludes, workDirectory)
  let material = host.newGpuCompositeMaterial(ns, vertex, fragment)
  let linearMaterial = host.newGpuCompositeMaterial(ns, vertex, fragment,
    foregroundFilter = gsfLinear)
  let backdrop = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 4, height: 4, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "placement-backdrop"),
    rgbaPixels(4, 4, proc(x, y: int): Pixel =
      Pixel(blue: 255, alpha: 255)))
  let foreground = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 2, height: 2, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "placement-foreground"),
    rgbaPixels(2, 2, proc(x, y: int): Pixel =
      if y == 0 and x == 0: Pixel(red: 255, alpha: 128)
      elif y == 0: Pixel(green: 255)
      elif x == 0: Pixel(green: 255, alpha: 128)
      else: Pixel(red: 192, green: 96, blue: 32, alpha: 255)))
  let premultipliedForeground = host.createGpuTexture(ns,
    GpuTextureDescriptor(width: 2, height: 2, format: gtfRgba8,
      usage: {gtuSampled}, access: gtaStatic,
      label: "placement-premultiplied-foreground"),
    rgbaPixels(2, 2, proc(x, y: int): Pixel =
      if y == 0 and x == 0: Pixel(red: 128, alpha: 128)
      elif y == 0: Pixel()
      elif x == 0: Pixel(green: 128, alpha: 128)
      else: Pixel(red: 192, green: 96, blue: 32, alpha: 255)))
  proc target(label: string): GpuResourceHandle =
    host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
      width: 4, height: 4, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: label))
  let centered = target("placement-centered")
  let clipped = target("placement-clipped")
  let scaled = target("placement-scaled")
  let linearScaled = target("placement-linear-scaled")
  let cropped = target("placement-cropped")
  let croppedChained = target("placement-cropped-chained")
  let opaque = target("placement-opaque")
  let chained = target("placement-chained")
  let linearChained = target("placement-linear-chained")
  let scratch = [target("placement-scratch-0"),
    target("placement-scratch-1"), target("placement-scratch-2")]
  let center = gpuCompositePlacement(1, 1, 2, 2)
  let chain = host.newGpuFilterChain(ns,
    [compositeStage(foreground, blendMode = gcbmScreen,
      foregroundPlacement = center)], composite = material)
  let linearChain = host.newGpuFilterChain(ns,
    [compositeStage(premultipliedForeground, gcamPremultiplied,
      foregroundPlacement = gpuCompositePlacement(0, 0, 4, 4))],
    composite = linearMaterial)
  let crop = gpuCompositeCrop(0, 0, 1, 2)
  let cropChain = host.newGpuFilterChain(ns,
    [compositeStage(premultipliedForeground, gcamPremultiplied,
      foregroundCrop = crop)], composite = linearMaterial)
  let frame = host.beginGpuFrame()
  doAssert material.submit(backdrop, foreground, centered,
    foregroundPlacement = center)
  doAssert material.submit(backdrop, foreground, clipped,
    foregroundPlacement = gpuCompositePlacement(-1, -1, 2, 2))
  doAssert material.submit(backdrop, foreground, scaled,
    foregroundPlacement = gpuCompositePlacement(0, 0, 4, 4))
  doAssert linearMaterial.submit(backdrop, premultipliedForeground,
    linearScaled, foregroundAlphaMode = gcamPremultiplied,
    foregroundPlacement = gpuCompositePlacement(0, 0, 4, 4))
  doAssert linearMaterial.submit(backdrop, premultipliedForeground,
    cropped, foregroundAlphaMode = gcamPremultiplied,
    foregroundCrop = crop)
  doAssert material.submit(backdrop, foreground, opaque,
    foregroundAlphaMode = gcamOpaque, foregroundPlacement = center)
  doAssert chain.submit(backdrop, chained, scratch)
  doAssert linearChain.submit(backdrop, linearChained, scratch)
  doAssert cropChain.submit(backdrop, croppedChained, scratch)
  host.endGpuFrame(frame)
  let centeredPixels = host.readPixels(ns, centered, 4, 4)
  centeredPixels.requirePixel(0, 0, Pixel(blue: 255, alpha: 255),
    "placed GPU foreground leaves the outside backdrop intact")
  centeredPixels.requirePixel(1, 1, Pixel(red: 128, blue: 127, alpha: 255),
    "placed GPU foreground blends its top-left pixel")
  centeredPixels.requirePixel(2, 1, Pixel(blue: 255, alpha: 255),
    "placed GPU foreground preserves a transparent pixel")
  centeredPixels.requirePixel(1, 2, Pixel(green: 128, blue: 127, alpha: 255),
    "placed GPU foreground blends its bottom-left pixel")
  centeredPixels.requirePixel(2, 2, Pixel(red: 192, green: 96,
    blue: 32, alpha: 255), "placed GPU foreground keeps its opaque pixel")
  let clippedPixels = host.readPixels(ns, clipped, 4, 4)
  clippedPixels.requirePixel(0, 0, Pixel(red: 192, green: 96,
    blue: 32, alpha: 255), "negative foreground placement clips to target")
  clippedPixels.requirePixel(1, 0, Pixel(blue: 255, alpha: 255),
    "clipped foreground does not smear beyond its bounds")
  let scaledPixels = host.readPixels(ns, scaled, 4, 4)
  scaledPixels.requirePixel(1, 1, Pixel(red: 128, blue: 127, alpha: 255),
    "scaled foreground repeats the top-left texel")
  scaledPixels.requirePixel(3, 0, Pixel(blue: 255, alpha: 255),
    "scaled foreground keeps transparent source texels")
  scaledPixels.requirePixel(3, 3, Pixel(red: 192, green: 96,
    blue: 32, alpha: 255), "scaled foreground reaches bottom-right")
  for item in [linearScaled, linearChained]:
    let pixels = host.readPixels(ns, item, 4, 4)
    pixels.requirePixel(1, 1, Pixel(red: 84, green: 30, blue: 145,
      alpha: 255), "linear foreground blends nearby premultiplied texels")
    pixels.requirePixel(2, 2, Pixel(red: 116, green: 78, blue: 98,
      alpha: 255), "linear foreground interpolates all four texels")
  for item in [cropped, croppedChained]:
    let pixels = host.readPixels(ns, item, 4, 4)
    pixels.requirePixel(3, 0, Pixel(red: 128, blue: 127, alpha: 255),
      "cropped foreground avoids transparent atlas neighbor")
    pixels.requirePixel(3, 3, Pixel(green: 128, blue: 127, alpha: 255),
      "cropped foreground reaches its lower source texel")
  let opaquePixels = host.readPixels(ns, opaque, 4, 4)
  opaquePixels.requirePixel(0, 0, Pixel(blue: 255, alpha: 255),
    "opaque alpha mode remains transparent outside placement")
  opaquePixels.requirePixel(2, 1, Pixel(green: 255, alpha: 255),
    "opaque alpha mode applies inside placement")
  let chainedPixels = host.readPixels(ns, chained, 4, 4)
  chainedPixels.requirePixel(0, 0, Pixel(blue: 255, alpha: 255),
    "placed chain leaves the outside backdrop intact")
  chainedPixels.requirePixel(1, 1, Pixel(red: 128, blue: 255, alpha: 255),
    "placed chain applies screen blending to translucent source")
  chainedPixels.requirePixel(2, 2, Pixel(red: 192, green: 96,
    blue: 255, alpha: 255), "placed chain screens opaque source")
  material.release()
  linearMaterial.release()
  for handle in [backdrop, foreground, premultipliedForeground,
      centered, clipped, scaled, linearScaled, cropped, croppedChained,
      opaque, chained,
      linearChained, scratch[0], scratch[1], scratch[2]]:
    doAssert host.releaseGpuResource(handle)
  doAssert host.closeGpuNamespace(ns)
  echo "GPU foreground placement: clipping, scaling, and chaining pixels passed"

proc verifyGpuDisplacementPixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("gpu-displacement-pixels", budget())
  let material = host.newGpuDisplacementMaterial(ns,
    compileShader(gpuDisplacementVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuDisplacementFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let matrix = host.newGpuColorMatrixMaterial(ns,
    compileShader(gpuColorMatrixVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuColorMatrixFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let source = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 3, height: 3, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "displacement-source"),
    rgbaPixels(3, 3, proc(x, y: int): Pixel =
      if x == 1 and y == 2:
        Pixel(red: 200, green: 100, blue: 40, alpha: 128)
      else:
        Pixel(red: uint8(x * 70), green: uint8(y * 70),
          blue: 40, alpha: 255)))
  let displacementMap = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 3, height: 3, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "displacement-map"),
    rgbaPixels(3, 3, proc(x, y: int): Pixel =
      Pixel(green: 255, alpha: 255)))
  proc target(label: string): GpuResourceHandle =
    host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
      width: 3, height: 3, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: label))
  let displaced = target("displacement-direct")
  let chained = target("displacement-chained")
  let unchanged = target("displacement-zero-scale")
  let scratch = [target("displacement-scratch-0"),
    target("displacement-scratch-1"),
    target("displacement-scratch-2")]
  let chain = host.newGpuFilterChain(ns,
    [opacityStage(1'f32),
      displacementStage(displacementMap, -1'f32, 1'f32)],
    colorMatrix = matrix, displacement = material)
  let frame = host.beginGpuFrame()
  doAssert material.submit(source, displacementMap, displaced,
    -1'f32, 1'f32)
  doAssert chain.submit(source, chained, scratch)
  doAssert material.submit(source, displacementMap, unchanged,
    0'f32, 0'f32)
  host.endGpuFrame(frame)
  for item in [displaced, chained]:
    let pixels = host.readPixels(ns, item, 3, 3)
    pixels.requirePixel(0, 0, Pixel(red: 70, green: 70,
      blue: 40, alpha: 255),
      "displacement map moves right and down in source pixels")
    pixels.requirePixel(1, 0, Pixel(red: 140, green: 70,
      blue: 40, alpha: 255),
      "displacement map reads the next source column")
    pixels.requirePixel(0, 1, Pixel(red: 100, green: 50,
      blue: 20, alpha: 128),
      "displacement preserves translucent source color through the chain")
    pixels.requirePixel(2, 2, Pixel(red: 140, green: 140,
      blue: 40, alpha: 255),
      "displacement clamps at the source boundary")
  let unchangedPixels = host.readPixels(ns, unchanged, 3, 3)
  unchangedPixels.requirePixel(1, 2, Pixel(red: 100, green: 50,
    blue: 20, alpha: 128),
    "zero displacement retains premultiplied translucent pixels")
  material.release()
  matrix.release()
  for handle in [source, displacementMap, displaced, chained, unchanged,
      scratch[0], scratch[1], scratch[2]]:
    doAssert host.releaseGpuResource(handle)
  doAssert host.closeGpuNamespace(ns)
  echo "GPU displacement: direct, chained, and zero-scale pixels passed"

proc verifyGpuConvolutionPixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("gpu-convolution-pixels", budget())
  let material = host.newGpuConvolutionMaterial(ns,
    compileShader(gpuConvolutionVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuConvolutionFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let source = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 3, height: 3, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "convolution-source"),
    rgbaPixels(3, 3, proc(x, y: int): Pixel =
      if x == 1 and y == 0: Pixel(red: 255, alpha: 255)
      elif x == 1 and y == 1: Pixel(blue: 255, alpha: 128)
      elif x == 1 and y == 2: Pixel(green: 255, alpha: 255)
      else: Pixel(alpha: 255)))
  proc target(label: string): GpuResourceHandle =
    host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
      width: 3, height: 3, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: label))
  let preserved = target("convolution-preserved")
  let replaced = target("convolution-replaced")
  let chained = target("convolution-chained")
  let scratch = [target("convolution-scratch-0"),
    target("convolution-scratch-1"),
    target("convolution-scratch-2")]
  let topNeighbor = gpuConvolutionKernel([
    0'f32, 1, 0, 0, 0, 0, 0, 0, 0])
  let chain = host.newGpuFilterChain(ns,
    [convolutionStage(identityGpuConvolutionKernel()),
      convolutionStage(topNeighbor, preserveAlpha = false)],
    convolution = material)
  let frame = host.beginGpuFrame()
  doAssert material.submit(source, preserved, topNeighbor)
  doAssert material.submit(source, replaced, topNeighbor,
    preserveAlpha = false)
  doAssert chain.submit(source, chained, scratch)
  host.endGpuFrame(frame)
  let preservedPixels = host.readPixels(ns, preserved, 3, 3)
  preservedPixels.requirePixel(1, 1, Pixel(red: 128, alpha: 128),
    "convolution preserves center alpha and clamps premultiplied color")
  preservedPixels.requirePixel(1, 0, Pixel(red: 255, alpha: 255),
    "convolution clamps top-edge sampling")
  let replacedPixels = host.readPixels(ns, replaced, 3, 3)
  replacedPixels.requirePixel(1, 1, Pixel(red: 255, alpha: 255),
    "convolution can filter alpha with the color channels")
  let chainedPixels = host.readPixels(ns, chained, 3, 3)
  chainedPixels.requirePixel(1, 1, Pixel(red: 255, alpha: 255),
    "convolution reads the top row of a premultiplied RenderTarget")
  chainedPixels.requirePixel(1, 2, Pixel(blue: 128, alpha: 128),
    "convolution keeps bottom-row image orientation")
  material.release()
  for handle in [source, preserved, replaced, chained,
      scratch[0], scratch[1], scratch[2]]:
    doAssert host.releaseGpuResource(handle)
  doAssert host.closeGpuNamespace(ns)
  echo "GPU convolution: alpha policy, edge clamp, and chain pixels passed"

proc verifyGpuMorphologyPixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("gpu-morphology-pixels", budget())
  let material = host.newGpuMorphologyMaterial(ns,
    compileShader(gpuMorphologyVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuMorphologyFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let source = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 5, height: 5, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "morphology-source"),
    rgbaPixels(5, 5, proc(x, y: int): Pixel =
      if x == 2 and y == 2:
        Pixel(red: 255, alpha: 128)
      elif x in 1 .. 3 and y in 1 .. 3:
        Pixel(red: 255, alpha: 255)
      else:
        Pixel()))
  proc target(label: string): GpuResourceHandle =
    host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
      width: 5, height: 5, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: label))
  let dilated = target("morphology-dilated")
  let eroded = target("morphology-eroded")
  let unchanged = target("morphology-radius-zero")
  let opened = target("morphology-opened")
  let scratch = [target("morphology-scratch-0"),
    target("morphology-scratch-1"),
    target("morphology-scratch-2")]
  let chain = host.newGpuFilterChain(ns,
    [morphologyStage(gmmErode, 1),
      morphologyStage(gmmDilate, 1)], morphology = material)
  let frame = host.beginGpuFrame()
  doAssert material.submit(source, scratch[2], dilated,
    mode = gmmDilate, radius = 1)
  doAssert material.submit(source, scratch[2], eroded,
    mode = gmmErode, radius = 1)
  doAssert material.submit(source, scratch[2], unchanged,
    radius = 0)
  doAssert chain.submit(source, opened, scratch)
  host.endGpuFrame(frame)
  let dilatedPixels = host.readPixels(ns, dilated, 5, 5)
  for point in [(0, 0), (2, 2), (4, 4)]:
    dilatedPixels.requirePixel(point[0], point[1],
      Pixel(red: 255, alpha: 255),
      "GPU dilation expands premultiplied color and alpha")
  let erodedPixels = host.readPixels(ns, eroded, 5, 5)
  erodedPixels.requirePixel(2, 2, Pixel(red: 128, alpha: 128),
    "GPU erosion keeps the minimum premultiplied center")
  erodedPixels.requirePixel(1, 2, Pixel(),
    "GPU erosion removes edge pixels")
  let unchangedPixels = host.readPixels(ns, unchanged, 5, 5)
  unchangedPixels.requirePixel(2, 2, Pixel(red: 128, alpha: 128),
    "zero-radius morphology normalizes straight alpha")
  unchangedPixels.requirePixel(1, 1, Pixel(red: 255, alpha: 255),
    "zero-radius morphology keeps opaque pixels")
  let openedPixels = host.readPixels(ns, opened, 5, 5)
  openedPixels.requirePixel(1, 1, Pixel(red: 128, alpha: 128),
    "chained erosion then dilation expands the minimum center")
  openedPixels.requirePixel(0, 0, Pixel(),
    "chained morphology keeps the cleared border")
  material.release()
  for handle in [source, dilated, eroded, unchanged, opened,
      scratch[0], scratch[1], scratch[2]]:
    doAssert host.releaseGpuResource(handle)
  doAssert host.closeGpuNamespace(ns)
  echo "GPU morphology: dilation, erosion, zero radius, and chaining pixels passed"

proc verifyGpuGaussianBlurPixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("gpu-gaussian-blur-pixels", budget())
  let material = host.newGpuGaussianBlurMaterial(ns,
    compileShader(gpuGaussianBlurVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuGaussianBlurFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let source = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 5, height: 5, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "gaussian-blur-source"),
    rgbaPixels(5, 5, proc(x, y: int): Pixel =
      if x == 2 and y == 2: Pixel(red: 255, alpha: 128)
      elif x == 0 and y == 0: Pixel(green: 255)
      else: Pixel()))
  proc target(label: string): GpuResourceHandle =
    host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
      width: 5, height: 5, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: label))
  let scratch = target("gaussian-blur-scratch")
  let output = target("gaussian-blur-output")
  let frame = host.beginGpuFrame()
  doAssert material.submit(source, scratch, output, gcamStraight)
  host.endGpuFrame(frame)
  let pixels = host.readPixels(ns, output, 5, 5)
  pixels.requirePixel(2, 2, Pixel(red: 18, alpha: 18),
    "Gaussian blur center")
  pixels.requirePixel(1, 2, Pixel(red: 12, alpha: 12),
    "Gaussian blur horizontal neighbor")
  pixels.requirePixel(2, 1, Pixel(red: 12, alpha: 12),
    "Gaussian blur vertical neighbor")
  pixels.requirePixel(0, 0, Pixel(red: 1, alpha: 1),
    "Gaussian blur transparent source remains transparent")
  let zeroFrame = host.beginGpuFrame()
  doAssert material.submit(source, scratch, output,
    sourceAlphaMode = gcamStraight, radius = 0)
  host.endGpuFrame(zeroFrame)
  let zeroPixels = host.readPixels(ns, output, 5, 5)
  zeroPixels.requirePixel(2, 2, Pixel(red: 128, alpha: 128),
    "zero-radius blur preserves premultiplied source")
  zeroPixels.requirePixel(0, 0, Pixel(),
    "zero-radius blur discards transparent source color")
  let wideFrame = host.beginGpuFrame()
  doAssert material.submit(source, scratch, output,
    sourceAlphaMode = gcamStraight, radius = 4)
  host.endGpuFrame(wideFrame)
  let widePixels = host.readPixels(ns, output, 5, 5)
  widePixels.requirePixel(2, 2, Pixel(red: 10, alpha: 10),
    "radius-four blur spreads premultiplied source")
  let widerFrame = host.beginGpuFrame()
  doAssert material.submit(source, scratch, output,
    sourceAlphaMode = gcamStraight, radius = 8)
  host.endGpuFrame(widerFrame)
  let widerPixels = host.readPixels(ns, output, 5, 5)
  widerPixels.requirePixel(2, 2, Pixel(red: 5, alpha: 5),
    "radius-eight blur spreads premultiplied source", tolerance = 1)
  widerPixels.requirePixel(0, 0, Pixel(red: 1, alpha: 1),
    "radius-eight blur keeps transparent source color out", tolerance = 2)
  let widestFrame = host.beginGpuFrame()
  doAssert material.submit(source, scratch, output,
    sourceAlphaMode = gcamStraight, radius = 16)
  host.endGpuFrame(widestFrame)
  let widestPixels = host.readPixels(ns, output, 5, 5)
  widestPixels.requirePixel(2, 2, Pixel(red: 3, alpha: 3),
    "radius-sixteen blur spreads premultiplied source", tolerance = 1)
  widestPixels.requirePixel(0, 0, Pixel(red: 2, alpha: 2),
    "radius-sixteen blur keeps transparent source color out", tolerance = 2)
  doAssert host.releaseGpuResource(source)
  doAssert host.releaseGpuResource(scratch)
  doAssert host.releaseGpuResource(output)
  material.release()
  doAssert host.closeGpuNamespace(ns)
  echo "GPU Gaussian blur: separable premultiplied pixels passed"

proc verifyGpuDropShadowPixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("gpu-drop-shadow-pixels", budget())
  let material = host.newGpuDropShadowMaterial(ns,
    compileShader(gpuGaussianBlurVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuGaussianBlurFragmentSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuDropShadowVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuDropShadowFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let source = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 5, height: 5, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "drop-shadow-source"),
    rgbaPixels(5, 5, proc(x, y: int): Pixel =
      if x == 2 and y == 2: Pixel(red: 255, alpha: 128)
      elif x == 0 and y == 0: Pixel(green: 255)
      else: Pixel()))
  proc target(label: string): GpuResourceHandle =
    host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
      width: 5, height: 5, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: label))
  let scratch = target("drop-shadow-scratch")
  let blurred = target("drop-shadow-blurred")
  let output = target("drop-shadow-output")
  let frame = host.beginGpuFrame()
  doAssert material.submit(source, scratch, blurred, output,
    1, 0, rgb(0, 0, 1), gcamStraight)
  host.endGpuFrame(frame)
  let pixels = host.readPixels(ns, output, 5, 5)
  pixels.requirePixel(2, 2, Pixel(red: 128, blue: 6, alpha: 134),
    "drop shadow preserves the original above the shadow")
  pixels.requirePixel(3, 2, Pixel(blue: 18, alpha: 18),
    "drop shadow moves the blurred alpha right")
  pixels.requirePixel(0, 0, Pixel(),
    "drop shadow excludes transparent color and out-of-bounds samples")
  let sharpFrame = host.beginGpuFrame()
  doAssert material.submit(source, scratch, blurred, output,
    1, 0, rgb(0, 0, 1), sourceAlphaMode = gcamStraight,
    blurRadius = 0)
  host.endGpuFrame(sharpFrame)
  let sharpPixels = host.readPixels(ns, output, 5, 5)
  sharpPixels.requirePixel(2, 2, Pixel(red: 128, alpha: 128),
    "zero-radius shadow preserves original")
  sharpPixels.requirePixel(3, 2, Pixel(blue: 128, alpha: 128),
    "zero-radius shadow places sharp alpha")
  let wideFrame = host.beginGpuFrame()
  doAssert material.submit(source, scratch, blurred, output,
    1, 0, rgb(0, 0, 1), sourceAlphaMode = gcamStraight,
    blurRadius = 8)
  host.endGpuFrame(wideFrame)
  let widePixels = host.readPixels(ns, output, 5, 5)
  widePixels.requirePixel(3, 2, Pixel(blue: 5, alpha: 5),
    "radius-eight shadow spreads offset alpha", tolerance = 3)
  let widestFrame = host.beginGpuFrame()
  doAssert material.submit(source, scratch, blurred, output,
    1, 0, rgb(0, 0, 1), sourceAlphaMode = gcamStraight,
    blurRadius = 16)
  host.endGpuFrame(widestFrame)
  let widestPixels = host.readPixels(ns, output, 5, 5)
  widestPixels.requirePixel(3, 2, Pixel(blue: 3, alpha: 3),
    "radius-sixteen shadow spreads offset alpha", tolerance = 2)
  doAssert host.releaseGpuResource(source)
  doAssert host.releaseGpuResource(scratch)
  doAssert host.releaseGpuResource(blurred)
  doAssert host.releaseGpuResource(output)
  material.release()
  doAssert host.closeGpuNamespace(ns)
  echo "GPU drop shadow: premultiplied offset pixels passed"

proc verifyGpuFilterChainPixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("gpu-filter-chain-pixels", budget())
  let matrix = host.newGpuColorMatrixMaterial(ns,
    compileShader(gpuColorMatrixVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuColorMatrixFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let blur = host.newGpuGaussianBlurMaterial(ns,
    compileShader(gpuGaussianBlurVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuGaussianBlurFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let swapRedBlue = colorMatrixFilter([
    0'f32, 0, 1, 0,
    0'f32, 1, 0, 0,
    1'f32, 0, 0, 0
  ])
  let chain = host.newGpuFilterChain(ns,
    [colorMatrixStage(swapRedBlue), gaussianBlurStage()],
    colorMatrix = matrix, gaussianBlur = blur)
  let source = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 5, height: 5, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaStatic,
    label: "filter-chain-source"),
    rgbaPixels(5, 5, proc(x, y: int): Pixel =
      if x == 2 and y == 2: Pixel(red: 255, alpha: 128)
      elif x == 0 and y == 0: Pixel(green: 255)
      else: Pixel()))
  proc target(label: string): GpuResourceHandle =
    host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
      width: 5, height: 5, format: gtfRgba8,
      usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label: label))
  let scratch = [target("filter-chain-scratch-a"),
    target("filter-chain-scratch-b"), target("filter-chain-scratch-c")]
  let output = target("filter-chain-output")
  let frame = host.beginGpuFrame()
  doAssert chain.submit(source, output, scratch, gcamStraight)
  host.endGpuFrame(frame)
  let pixels = host.readPixels(ns, output, 5, 5)
  pixels.requirePixel(2, 2, Pixel(blue: 18, alpha: 18),
    "filter chain matrix then blur center")
  pixels.requirePixel(1, 2, Pixel(blue: 12, alpha: 12),
    "filter chain matrix then blur neighbor")
  pixels.requirePixel(0, 0, Pixel(blue: 1, alpha: 1),
    "filter chain discards transparent source color")
  matrix.release()
  blur.release()
  doAssert host.releaseGpuResource(source)
  for handle in [output, scratch[0], scratch[1], scratch[2]]:
    doAssert host.releaseGpuResource(handle)
  doAssert host.closeGpuNamespace(ns)
  echo "GPU filter chain: ordered matrix and blur pixels passed"

proc verifyGpuRasterFilterDisplayPixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("gpu-raster-filter-display-pixels", budget())
  let material = host.newGpuColorMatrixMaterial(ns,
    compileShader(gpuColorMatrixVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuColorMatrixFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let swapRedBlue = colorMatrixFilter([
    0'f32, 0, 1, 0,
    0'f32, 1, 0, 0,
    1'f32, 0, 0, 0
  ])
  let chain = host.newGpuFilterChain(ns,
    [colorMatrixStage(swapRedBlue)], colorMatrix = material)
  let raster = newRasterSurface(5, 5)
  raster.updateRegion(rasterRegion(2, 2, 1, 1), @[255'u8, 0, 0, 128])
  doAssert raster.publish()
  var config = defaultGpuRasterFilterDisplayConfig(5, 5)
  config.fallback = gdsfRequireReadback
  let filtered = host.newGpuRasterFilterDisplay(ns, raster, chain, config)
  let display = filtered.displaySurface()

  proc drain() =
    for attempt in 0 ..< 128:
      discard attempt
      discard display.collectGpuDisplayFrame()
      if display.readbackSurface().pendingFrameCount() == 0 and
          display.readbackSurface().completedFrameNumber > 0:
        return
      let progress = host.beginGpuFrame()
      host.endGpuFrame(progress)
    raise newException(IOError, "GPU raster filter display readback did not drain")

  let first = host.beginGpuFrame()
  doAssert filtered.queueUpdatedGpuRasterFrame(first)
  host.endGpuFrame(first)
  drain()
  doAssert display.readbackSurface().rasterSurface.publish()
  display.readbackSurface().rasterSurface.pixels.requireRasterPixel(
    5, 2, 2, Pixel(blue: 255, alpha: 128),
    "raster upload through GPU matrix and display readback")

  raster.updateRegion(rasterRegion(2, 2, 1, 1), @[0'u8, 0, 255, 128])
  doAssert raster.publish()
  let second = host.beginGpuFrame()
  doAssert filtered.queueUpdatedGpuRasterFrame(second)
  host.endGpuFrame(second)
  drain()
  doAssert display.readbackSurface().rasterSurface.publish()
  display.readbackSurface().rasterSurface.pixels.requireRasterPixel(
    5, 2, 2, Pixel(red: 255, alpha: 128),
    "raster dirty upload through GPU matrix and display readback")
  let replacement = newRasterSurface(5, 5)
  replacement.updateRegion(rasterRegion(1, 1, 1, 1),
    @[0'u8, 255, 0, 255])
  doAssert replacement.publish()
  doAssert filtered.replaceSource(replacement)
  let swapped = host.beginGpuFrame()
  doAssert filtered.queueUpdatedGpuRasterFrame(swapped)
  host.endGpuFrame(swapped)
  drain()
  doAssert display.readbackSurface().rasterSurface.publish()
  display.readbackSurface().rasterSurface.pixels.requireRasterPixel(
    5, 1, 1, Pixel(green: 255, alpha: 255),
    "replacement raster uploads through the existing GPU display")
  display.readbackSurface().rasterSurface.pixels.requireRasterPixel(
    5, 2, 2, Pixel(),
    "replacement raster clears pixels from the previous source")
  let maskMaterial = host.newGpuAlphaMaskMaterial(ns,
    compileShader(gpuAlphaMaskVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuAlphaMaskFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let mask = host.createGpuTexture(ns, GpuTextureDescriptor(
    width: 5, height: 5, format: gtfRgba8,
    usage: {gtuSampled}, access: gtaDynamic,
    label: "raster-filter-dynamic-mask"),
    rgbaPixels(5, 5, proc(x, y: int): Pixel =
      discard x
      discard y
      Pixel(alpha: 255)))
  let alternateChain = host.newGpuFilterChain(ns,
    [colorMatrixStage(sepiaColorFilter(1)), alphaMaskStage(mask)],
    colorMatrix = material, alphaMask = maskMaterial)
  let sourceRevision = replacement.revision
  doAssert filtered.replaceFilterChain(alternateChain)
  doAssert filtered.displaySurface() == display
  doAssert filtered.source().revision == sourceRevision
  let recolored = host.beginGpuFrame()
  doAssert filtered.queueUpdatedGpuRasterFrame(recolored)
  host.endGpuFrame(recolored)
  drain()
  doAssert display.readbackSurface().rasterSurface.publish()
  display.readbackSurface().rasterSurface.pixels.requireRasterPixel(
    5, 1, 1, Pixel(red: 196, green: 175, blue: 136, alpha: 255),
    "updated GPU filter chain reprocesses unchanged raster")
  doAssert filtered.requestReprocess()
  doAssert filtered.lastQueuedRevision == sourceRevision
  let masked = host.beginGpuFrame()
  host.updateGpuTexture(mask,
    GpuTextureUpdateRegion(x: 1, y: 1, width: 1, height: 1),
    @[255'u8, 0, 0, 128])
  doAssert filtered.queueUpdatedGpuRasterFrame(masked)
  host.endGpuFrame(masked)
  drain()
  doAssert display.readbackSurface().rasterSurface.publish()
  display.readbackSurface().rasterSurface.pixels.requireRasterPixel(
    5, 1, 1, Pixel(red: 196, green: 175, blue: 136, alpha: 128),
    "updated GPU mask reprocesses unchanged raster")
  doAssert filtered.source().revision == sourceRevision
  doAssert filtered.lastQueuedRevision == sourceRevision
  doAssert filtered.closeGpuRasterFilterDisplay()
  doAssert host.releaseGpuResource(mask)
  maskMaterial.release()
  material.release()
  doAssert host.closeGpuNamespace(ns)
  echo "GPU raster filter display: initial, dirty, chain replacement, and mask refresh pixels passed"

proc verifyInstancedRects(host: GpuHost; shaderc, shaderIncludes, workDirectory: string) =
  doAssert host.backendInfo.instancingSupported
  let ns = host.createGpuNamespace("instanced-rectangles", budget())
  let vertexSource = gpuMotionRectVertexSource()
  let fragmentSource = gpuMotionRectFragmentSource()
  validateGpuShaderInterface(vertexSource, fragmentSource)
  let material = host.newGpuMotionRectMaterial(ns,
    compileShader(vertexSource, shaderc, shaderIncludes, workDirectory),
    compileShader(fragmentSource, shaderc, shaderIncludes, workDirectory))
  let target = host.createGpuRenderTarget(ns, GpuRenderTargetDescriptor(
    width: 64, height: 64, format: gtfRgba8, usage: {gtuRenderTarget, gtuSampled, gtuBlitSource}))
  let transforms = [translationAffine2D(6, 5),
    translationAffine2D(20, 16) * rotationAffine2D(0.2), translationAffine2D(45, 8)]
  let sizes = [size(24, 22), size(24, 24), size(12, 40)]
  let colors = [rgba(1, 0, 0, 1), rgba(0, 0, 1, 0.5), rgba(0, 1, 0, 1)]
  proc snapshotFor(thirdX: float32): MotionSceneSnapshot =
    motionSceneSnapshot(size(64, 64), [
      motionRect(MotionObjectId(1), rect(0, 0, sizes[0].w, sizes[0].h),
        colors[0], transform = transforms[0], radius = 4),
      motionRect(MotionObjectId(2), rect(0, 0, sizes[1].w, sizes[1].h),
        colors[1], transform = transforms[1], radius = 4),
      motionRect(MotionObjectId(3), rect(0, 0, sizes[2].w, sizes[2].h),
        colors[2], transform = translationAffine2D(thirdX, 8), radius = 4)
    ])
  for access in [gbaStatic, gbaDynamic]:
    let scene = newMotionScene(snapshotFor(45))
    let batch = newGpuMotionRectBatch()
    # Record zero is deliberately not drawn, exercising the instance offset.
    var records: array[4, GpuMotionRectRecord]
    let initial = gpuMotionRectRecords(snapshotFor(45))
    doAssert initial.len == 3
    for index in 0 .. 2:
      records[index + 1] = initial[index]
    var instances: GpuResourceHandle
    if access == gbaDynamic:
      doAssert batch.sync(host, ns, scene)
    else:
      instances = host.createGpuBuffer(
        ns, gpuInstanceBufferDescriptor(gpuMotionRectVec4Count, 4, access),
        gpuMotionRectBytes(records)
      )
    for step in 0 .. (if access == gbaDynamic: 1 else: 0):
      if step == 1:
        discard scene.replaceSnapshot(snapshotFor(50))
        doAssert batch.sync(host, ns, scene)
      let binding = if access == gbaDynamic: batch.instanceBinding else:
        GpuInstanceBinding(buffer: instances, firstInstance: 1,
          instanceCount: 3)
      let token = host.beginGpuFrame()
      let pass = GpuGraphicsPassDescriptor(
        viewport: GpuViewport(width: 64, height: 64), renderTarget: target,
        clearColorEnabled: true, clearColor: GpuClearColor(alpha: 1))
      if access == gbaDynamic:
        doAssert material.submit(batch, pass)
      else:
        doAssert material.submit(binding, pass)
      host.endGpuFrame(token)
      let actual = host.readPixels(ns, target, 64, 64)
      let expected = render(
        scene.canvas.paintCommands(NodeId(0), rect(0, 0, 64, 64)),
        64, 64, rgb(0, 0, 0)
      )
      for point in [(0, 0), (6, 5), (12, 12), (24, 20), (33, 30), (46, 20), (54, 20), (63, 63)]:
        let index = (point[1] * 64 + point[0]) * 3
        actual.requirePixel(point[0], point[1], Pixel(red: expected.pixels[index],
          green: expected.pixels[index + 1], blue: expected.pixels[index + 2], alpha: 255),
          "instanced rounded rectangles match CPU")
    if access == gbaDynamic:
      batch.release()
    else:
      doAssert host.releaseGpuResource(instances)
  let clearFrame = host.beginGpuFrame()
  host.clearGpuGraphicsPass(ns, GpuGraphicsPassDescriptor(
    viewport: GpuViewport(width: 64, height: 64), renderTarget: target,
    clearColorEnabled: true,
    clearColor: GpuClearColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)))
  host.endGpuFrame(clearFrame)
  let cleared = host.readPixels(ns, target, 64, 64)
  for point in [(0, 0), (12, 12), (33, 30), (63, 63)]:
    cleared.requirePixel(point[0], point[1], Pixel(
      red: 51, green: 102, blue: 153, alpha: 255),
      "clear-only pass replaces prior scene pixels")
  let emptyFrame = host.beginGpuFrame()
  host.clearGpuGraphicsPass(ns, GpuGraphicsPassDescriptor(
    viewport: GpuViewport(width: 64, height: 64), renderTarget: target,
    clearColorEnabled: true, clearColor: GpuClearColor()))
  host.endGpuFrame(emptyFrame)
  let transparent = host.readPixels(ns, target, 64, 64)
  for point in [(0, 0), (12, 12), (33, 30), (63, 63)]:
    transparent.requirePixel(point[0], point[1], Pixel(),
      "empty Motion Scene clears to transparent pixels")
  doAssert host.releaseGpuResource(target)
  material.release()
  doAssert host.closeGpuNamespace(ns)
  echo "Instanced rounded rectangles and clear-only pass: CPU pixels passed"

proc verifyMotionSceneCanvas(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("motion-scene-canvas", budget())
  let scene = newMotionScene(motionSceneSnapshot(size(16, 16), [
    motionRect(MotionObjectId(1), rect(4, 4, 8, 8), rgba(1, 0, 0, 1))]))
  var config = defaultGpuMotionSceneCanvasConfig(16, 16)
  config.readbackSlots = 2
  let renderer = host.newGpuMotionSceneCanvas(ns, scene, config,
    compileShader(gpuMotionRectVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuMotionRectFragmentSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuMotionImageFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  proc drain() =
    for attempt in 0 ..< 32:
      discard attempt
      pumpWindow()
      discard renderer.collectFrame()
      if renderer.canvas.pendingFrameCount == 0:
        return
      let progress = host.beginGpuFrame()
      host.endGpuFrame(progress)
    raise newException(IOError, "Motion Scene GPU canvas readback did not drain")
  doAssert renderer.queueFrame()
  drain()
  let pixels = renderer.canvas.rasterSurface.pixels
  doAssert pixels[(5 * 16 + 5) * 4] == 255
  doAssert pixels[(5 * 16 + 5) * 4 + 3] == 255
  doAssert pixels[3] == 0
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), [
    motionRect(MotionObjectId(1), rect(2, 2, 8, 8), rgba(1, 0, 0, 0.5)),
    motionRect(MotionObjectId(2), rect(6, 2, 8, 8), rgba(0, 0, 1, 0.5))]))
  doAssert renderer.queueFrame()
  drain()
  let blended = renderer.canvas.rasterSurface.pixels
  blended.requireRasterPixel(16, 3, 4, Pixel(red: 255, alpha: 128),
    "GPU Canvas straight-alpha red")
  blended.requireRasterPixel(16, 8, 4,
    Pixel(red: 85, blue: 170, alpha: 191),
    "GPU Canvas straight-alpha overlap")
  blended.requireRasterPixel(16, 12, 4, Pixel(blue: 255, alpha: 128),
    "GPU Canvas straight-alpha blue")
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), [
    motionEllipse(MotionObjectId(3), rect(2, 2, 12, 12),
      rgba(0, 1, 0, 1))]))
  doAssert renderer.queueFrame()
  drain()
  let ellipsePixels = renderer.canvas.rasterSurface.pixels
  ellipsePixels.requireRasterPixel(16, 8, 8, Pixel(green: 255, alpha: 255),
    "GPU Canvas ellipse center")
  ellipsePixels.requireRasterPixel(16, 3, 3, Pixel(),
    "GPU Canvas ellipse outside")
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), [
    motionLine(MotionObjectId(4), vec2(2, 8), vec2(14, 8), 4,
      rgba(0, 1, 0, 1))]))
  doAssert renderer.queueFrame()
  drain()
  let linePixels = renderer.canvas.rasterSurface.pixels
  linePixels.requireRasterPixel(16, 8, 8, Pixel(green: 255, alpha: 255),
    "GPU Canvas line center")
  linePixels.requireRasterPixel(16, 8, 3, Pixel(),
    "GPU Canvas line outside")
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), [
    motionTriangle(MotionObjectId(5), vec2(2, 2), vec2(14, 2),
      vec2(2, 14), rgba(0, 1, 0, 1))]))
  doAssert renderer.queueFrame()
  drain()
  let trianglePixels = renderer.canvas.rasterSurface.pixels
  trianglePixels.requireRasterPixel(16, 5, 5,
    Pixel(green: 255, alpha: 255), "GPU Canvas triangle inside")
  trianglePixels.requireRasterPixel(16, 12, 12, Pixel(),
    "GPU Canvas triangle outside")
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), [
    motionRing(MotionObjectId(6), rect(2, 2, 12, 12),
      rgba(0, 1, 0, 1), innerRadius = 0.5)]))
  doAssert renderer.queueFrame()
  drain()
  let ringPixels = renderer.canvas.rasterSurface.pixels
  ringPixels.requireRasterPixel(16, 8, 4,
    Pixel(green: 255, alpha: 255), "GPU Canvas ring band")
  ringPixels.requireRasterPixel(16, 8, 8, Pixel(),
    "GPU Canvas ring hole")
  ringPixels.requireRasterPixel(16, 2, 2, Pixel(),
    "GPU Canvas ring outside")
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), [
    motionSector(MotionObjectId(7), rect(2, 2, 12, 12),
      rgba(0, 1, 0, 1), 0, PI.float32 * 0.5'f32)]))
  doAssert renderer.queueFrame()
  drain()
  let sectorPixels = renderer.canvas.rasterSurface.pixels
  sectorPixels.requireRasterPixel(16, 11, 10,
    Pixel(green: 255, alpha: 255), "GPU Canvas sector inside")
  sectorPixels.requireRasterPixel(16, 8, 8,
    Pixel(green: 255, alpha: 255), "GPU Canvas sector center")
  sectorPixels.requireRasterPixel(16, 5, 10, Pixel(),
    "GPU Canvas sector outside angle")
  sectorPixels.requireRasterPixel(16, 11, 5, Pixel(),
    "GPU Canvas sector outside sweep")
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), [
    motionSector(MotionObjectId(8), rect(2, 2, 12, 12),
      rgba(0, 0, 1, 1), PI.float32 * 1.5'f32, PI.float32)]))
  doAssert renderer.queueFrame()
  drain()
  let wrappedSectorPixels = renderer.canvas.rasterSurface.pixels
  wrappedSectorPixels.requireRasterPixel(16, 11, 5,
    Pixel(blue: 255, alpha: 255), "GPU Canvas wrapped sector before zero")
  wrappedSectorPixels.requireRasterPixel(16, 11, 11,
    Pixel(blue: 255, alpha: 255), "GPU Canvas wrapped sector after zero")
  wrappedSectorPixels.requireRasterPixel(16, 5, 8, Pixel(),
    "GPU Canvas wrapped sector outside")
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), [
    motionAnnularSector(MotionObjectId(9), rect(2, 2, 12, 12),
      rgba(0, 1, 0, 1), 0, PI.float32 * 0.5'f32,
      innerRadius = 0.5)]))
  doAssert renderer.queueFrame()
  drain()
  let annularPixels = renderer.canvas.rasterSurface.pixels
  annularPixels.requireRasterPixel(16, 12, 10,
    Pixel(green: 255, alpha: 255), "GPU Canvas annular sector band")
  annularPixels.requireRasterPixel(16, 9, 9, Pixel(),
    "GPU Canvas annular sector hole")
  annularPixels.requireRasterPixel(16, 5, 10, Pixel(),
    "GPU Canvas annular sector outside angle")
  annularPixels.requireRasterPixel(16, 14, 10, Pixel(),
    "GPU Canvas annular sector outside ellipse")
  let image = newMotionImageAsset(1, 1, @[255'u8, 0, 0, 128])
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), [
    motionRect(MotionObjectId(10), rect(0, 0, 16, 16), rgb(0, 0, 1)),
    motionImage(MotionObjectId(11), rect(2, 2, 8, 8), image),
    motionRect(MotionObjectId(12), rect(5, 5, 3, 3), rgb(0, 1, 0)),
    motionPolygon(MotionObjectId(13),
      @[vec2(11, 11), vec2(15, 11), vec2(15, 15), vec2(11, 15)],
      rgba(1, 1, 0, 0.5))]))
  doAssert renderer.queueFrame()
  drain()
  let imagePixels = renderer.canvas.rasterSurface.pixels
  imagePixels.requireRasterPixel(16, 1, 1,
    Pixel(blue: 255, alpha: 255), "GPU Canvas image backdrop")
  imagePixels.requireRasterPixel(16, 3, 3,
    Pixel(red: 128, blue: 127, alpha: 255), "GPU Canvas image alpha")
  imagePixels.requireRasterPixel(16, 6, 6,
    Pixel(green: 255, alpha: 255), "GPU Canvas image paint order")
  imagePixels.requireRasterPixel(16, 12, 12,
    Pixel(red: 128, green: 128, blue: 127, alpha: 255),
    "GPU Canvas convex polygon shared diagonal")
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), []))
  doAssert renderer.queueFrame()
  drain()
  let emptyPixels = renderer.canvas.rasterSurface.pixels
  for point in [(0, 0), (5, 5), (15, 15)]:
    let offset = (point[1] * 16 + point[0]) * 4
    doAssert emptyPixels[offset] == 0
    doAssert emptyPixels[offset + 1] == 0
    doAssert emptyPixels[offset + 2] == 0
    doAssert emptyPixels[offset + 3] == 0
  doAssert renderer.close()
  doAssert host.closeGpuNamespace(ns)
  echo "Motion Scene GPU canvas: changed and empty revisions publish expected pixels"

proc verifyFilteredMotionScenePixels(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("motion-scene-filtered", budget())
  let matrix = host.newGpuColorMatrixMaterial(ns,
    compileShader(gpuColorMatrixVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuColorMatrixFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let swapRedBlue = colorMatrixFilter([
    0'f32, 0, 1, 0,
    0'f32, 1, 0, 0,
    1'f32, 0, 0, 0
  ])
  let chain = host.newGpuFilterChain(ns,
    [colorMatrixStage(swapRedBlue)], colorMatrix = matrix)
  let scene = newMotionScene(motionSceneSnapshot(size(16, 16), [
    motionAnnularSector(MotionObjectId(1), rect(2, 2, 12, 12),
      rgba(1, 0, 0, 1), 0, PI.float32 * 0.5'f32,
      innerRadius = 0.5)]))
  var config = defaultGpuMotionSceneFilterDisplayConfig(16, 16)
  config.bufferCount = 2
  config.fallback = gdsfRequireReadback
  let renderer = host.newGpuMotionSceneFilterDisplay(ns, scene, chain, config,
    compileShader(gpuMotionRectVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuMotionRectFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  let display = renderer.displaySurface()
  proc drain() =
    for attempt in 0 ..< 64:
      discard attempt
      pumpWindow()
      discard renderer.collectFrame()
      if display.readbackSurface().pendingFrameCount() == 0:
        return
      let progress = host.beginGpuFrame()
      host.endGpuFrame(progress)
    raise newException(IOError, "filtered Motion Scene readback did not drain")
  doAssert renderer.queueFrame()
  drain()
  let pixels = display.readbackSurface().rasterSurface().pixels
  pixels.requireRasterPixel(16, 12, 10,
    Pixel(blue: 255, alpha: 255), "filtered Motion Scene band")
  pixels.requireRasterPixel(16, 9, 9, Pixel(),
    "filtered Motion Scene hole")
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), []))
  doAssert renderer.queueFrame()
  drain()
  display.readbackSurface().rasterSurface().pixels.requireRasterPixel(
    16, 12, 10, Pixel(), "filtered Motion Scene empty revision")
  doAssert renderer.close()
  matrix.release()
  doAssert host.closeGpuNamespace(ns)
  echo "Filtered Motion Scene: GPU shape, effect, and readback pixels passed"

proc verifyMotionSceneDirect(host: GpuHost;
    shaderc, shaderIncludes, workDirectory: string) =
  let ns = host.createGpuNamespace("motion-scene-direct", budget())
  let scene = newMotionScene(motionSceneSnapshot(size(16, 16), [
    motionRect(MotionObjectId(1), rect(4, 4, 8, 8), rgba(1, 0, 0, 1))]))
  var config = defaultGpuMotionSceneDirectConfig(16, 16)
  config.bufferCount = 2
  let renderer = host.newGpuMotionSceneDirect(ns, scene, config,
    compileShader(gpuMotionRectVertexSource(), shaderc,
      shaderIncludes, workDirectory),
    compileShader(gpuMotionRectFragmentSource(), shaderc,
      shaderIncludes, workDirectory))
  proc drain() =
    for attempt in 0 ..< 32:
      discard attempt
      pumpWindow()
      if renderer.collectFrame():
        return
      let progress = host.beginGpuFrame()
      host.endGpuFrame(progress)
    raise newException(IOError, "Motion Scene GPU direct frame did not complete")
  doAssert renderer.queueFrame()
  drain()
  var first = renderer.surface().acquireGpuDirectSurfaceFrame().get
  let pixels = host.readPixels(ns, first.resource, 16, 16)
  pixels.requirePixel(5, 5, Pixel(red: 255, alpha: 255),
    "direct Motion Scene rectangle")
  pixels.requirePixel(0, 0, Pixel(), "direct Motion Scene background")
  doAssert first.release()
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), [
    motionRect(MotionObjectId(1), rect(2, 2, 8, 8), rgba(1, 0, 0, 0.5)),
    motionRect(MotionObjectId(2), rect(6, 2, 8, 8), rgba(0, 0, 1, 0.5))]))
  doAssert renderer.queueFrame()
  drain()
  var blended = renderer.surface().acquireGpuDirectSurfaceFrame().get
  doAssert blended.alphaMode == gcamPremultiplied
  let blendedPixels = host.readPixels(ns, blended.resource, 16, 16)
  blendedPixels.requirePixel(3, 4, Pixel(red: 128, alpha: 128),
    "direct Motion Scene premultiplied red")
  blendedPixels.requirePixel(8, 4,
    Pixel(red: 64, blue: 128, alpha: 191),
    "direct Motion Scene premultiplied overlap")
  blendedPixels.requirePixel(12, 4, Pixel(blue: 128, alpha: 128),
    "direct Motion Scene premultiplied blue")
  doAssert blended.release()
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), [
    motionEllipse(MotionObjectId(3), rect(2, 2, 12, 12),
      rgba(0, 1, 0, 1))]))
  doAssert renderer.queueFrame()
  drain()
  var ellipse = renderer.surface().acquireGpuDirectSurfaceFrame().get
  let ellipsePixels = host.readPixels(ns, ellipse.resource, 16, 16)
  ellipsePixels.requirePixel(8, 8, Pixel(green: 255, alpha: 255),
    "direct Motion Scene ellipse center")
  ellipsePixels.requirePixel(3, 3, Pixel(),
    "direct Motion Scene ellipse outside")
  doAssert ellipse.release()
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), [
    motionLine(MotionObjectId(4), vec2(2, 8), vec2(14, 8), 4,
      rgba(0, 1, 0, 1))]))
  doAssert renderer.queueFrame()
  drain()
  var line = renderer.surface().acquireGpuDirectSurfaceFrame().get
  let linePixels = host.readPixels(ns, line.resource, 16, 16)
  linePixels.requirePixel(8, 8, Pixel(green: 255, alpha: 255),
    "direct Motion Scene line center")
  linePixels.requirePixel(8, 3, Pixel(),
    "direct Motion Scene line outside")
  doAssert line.release()
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), [
    motionTriangle(MotionObjectId(5), vec2(2, 2), vec2(14, 2),
      vec2(2, 14), rgba(0, 1, 0, 1))]))
  doAssert renderer.queueFrame()
  drain()
  var triangle = renderer.surface().acquireGpuDirectSurfaceFrame().get
  let trianglePixels = host.readPixels(ns, triangle.resource, 16, 16)
  trianglePixels.requirePixel(5, 5, Pixel(green: 255, alpha: 255),
    "direct Motion Scene triangle inside")
  trianglePixels.requirePixel(12, 12, Pixel(),
    "direct Motion Scene triangle outside")
  doAssert triangle.release()
  discard scene.replaceSnapshot(motionSceneSnapshot(size(16, 16), []))
  doAssert renderer.queueFrame()
  drain()
  var empty = renderer.surface().acquireGpuDirectSurfaceFrame().get
  let emptyPixels = host.readPixels(ns, empty.resource, 16, 16)
  for point in [(0, 0), (5, 5), (15, 15)]:
    emptyPixels.requirePixel(point[0], point[1], Pixel(),
      "direct Motion Scene empty revision")
  doAssert empty.release()
  doAssert renderer.close()
  doAssert host.closeGpuNamespace(ns)
  echo "Motion Scene GPU direct: changed and empty revisions publish expected pixels"

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
    host.verifyCanvasReadbackCancellation()
    host.verifyHybridDisplayPixels()
    host.verifyGpuColorMatrixPixels(shaderc, shaderIncludes, workDirectory)
    host.verifyGpuChannelMatrixPixels(shaderc, shaderIncludes, workDirectory)
    host.verifyFilteredCanvasReadbackPixels(shaderc, shaderIncludes,
      workDirectory)
    host.verifyFilteredDisplayPixels(shaderc, shaderIncludes, workDirectory)
    host.verifyOwnedGpuFilterDisplayPixels(shaderc, shaderIncludes,
      workDirectory)
    host.verifyGpuAlphaMaskPixels(shaderc, shaderIncludes, workDirectory)
    host.verifyGpuAlphaMaskPlacementPixels(shaderc, shaderIncludes,
      workDirectory)
    host.verifyGpuGaussianBlurPixels(shaderc, shaderIncludes, workDirectory)
    host.verifyGpuConvolutionPixels(shaderc, shaderIncludes, workDirectory)
    host.verifyGpuMorphologyPixels(shaderc, shaderIncludes, workDirectory)
    host.verifyGpuDisplacementPixels(shaderc, shaderIncludes, workDirectory)
    host.verifyGpuDropShadowPixels(shaderc, shaderIncludes, workDirectory)
    host.verifyGpuFilterChainPixels(shaderc, shaderIncludes, workDirectory)
    host.verifyGpuCompositePixels(shaderc, shaderIncludes, workDirectory)
    host.verifyGpuCompositePlacementPixels(shaderc, shaderIncludes, workDirectory)
    host.verifyGpuRasterFilterDisplayPixels(shaderc, shaderIncludes, workDirectory)
    host.verifyInstancedRects(shaderc, shaderIncludes, workDirectory)
    host.verifyMotionSceneCanvas(shaderc, shaderIncludes, workDirectory)
    host.verifyFilteredMotionScenePixels(shaderc, shaderIncludes,
      workDirectory)
    host.verifyMotionSceneDirect(shaderc, shaderIncludes, workDirectory)

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
      # A quarter physical-pixel offset maps the probed destination centers
      # onto source texel centers. A half-pixel offset lands exactly between
      # nearest-filter texels, where hardware may choose either neighbor.
      compositor, scaledTarget, scaledBounds, rect(10.125, 20, 2, 2), pattern,
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
