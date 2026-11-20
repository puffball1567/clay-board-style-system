## Filter SDL layers through shared OpenGL storage.
import ../../paint/[layer_blur, layer_color_filter]
import ../../runtime/[gpu_color_matrix, gpu_gaussian_blur, gpu_host]
import ../sdl3/renderer
import ./[sdl3_opengl_context, sdl3_opengl_target]

type Sdl3OpenGlLayerPass = proc(source, scratch, output: GpuResourceHandle): bool {.closure.}

proc filterSharedLayer(
    context: Sdl3BgfxOpenGlContext;
    host: GpuHost;
    namespace: GpuNamespaceId;
    renderer, destination: pointer;
    needsScratch: bool;
    submit: Sdl3OpenGlLayerPass
): bool =
  if renderer != context.nativeRenderer() or not host.isReady() or
      host.hasActiveGpuFrame():
    return false
  try:
    let source = describeActiveSdl3OpenGlTarget(renderer, sampled = true)
    let output = describeSdl3OpenGlTarget(renderer, destination)
    if source.name == output.name or
        source.descriptor.width != output.descriptor.width or
        source.descriptor.height != output.descriptor.height:
      return false
    context.withSdl3BgfxOpenGlContext:
      var sourceHandle, scratch, outputHandle: GpuResourceHandle
      try:
        sourceHandle = context.importSdl3OpenGlTarget(host, namespace, source)
        outputHandle = context.importSdl3OpenGlTarget(host, namespace, output)
        if needsScratch:
          var descriptor = source.descriptor
          descriptor.label = "UI blur scratch"
          scratch = host.createGpuRenderTarget(namespace, descriptor)
        let frame = host.beginGpuFrame()
        try:
          result = submit(sourceHandle, scratch, outputHandle)
        finally:
          host.endGpuFrame(frame)
      finally:
        host.retireSdl3OpenGlTargets([outputHandle, scratch, sourceHandle])
  except GpuHostError:
    result = false

proc supportsLayerFilters(context: Sdl3BgfxOpenGlContext; host: GpuHost): bool =
  not context.nativeRenderer().isNil and host.isReady() and
    host.provider() == gpkBgfx and not host.config().presentation

proc newSdl3BgfxOpenGlLayerColorFilter*(
    context: Sdl3BgfxOpenGlContext;
    host: GpuHost;
    namespace: GpuNamespaceId;
    material: GpuColorMatrixMaterial
): Sdl3LayerColorFilterProc =
  ## SDL owns the source, destination and final composition of the layer.
  if not context.supportsLayerFilters(host) or not material.belongsTo(host, namespace):
    raise newException(ValueError, "SDL OpenGL layer filtering requires an offscreen bgfx color matrix material")
  result = proc(renderer, destination: pointer; filter: LayerColorFilter): bool =
    if not material.belongsTo(host, namespace):
      return false
    context.filterSharedLayer(host, namespace, renderer, destination, false,
      proc(source, scratch, output: GpuResourceHandle): bool =
        material.submit(source, output, filter, gcamPremultiplied))

proc newSdl3BgfxOpenGlLayerBlur*(
    context: Sdl3BgfxOpenGlContext;
    host: GpuHost;
    namespace: GpuNamespaceId;
    material: GpuGaussianBlurMaterial
): Sdl3LayerBlurProc =
  ## Blur both axes on the shared host and return the result to SDL.
  if not context.supportsLayerFilters(host) or not material.belongsTo(host, namespace):
    raise newException(ValueError, "SDL OpenGL layer blur requires an offscreen bgfx Gaussian blur material")
  result = proc(renderer, destination: pointer; radius: LayerBlurRadius): bool =
    if not material.belongsTo(host, namespace):
      return false
    context.filterSharedLayer(host, namespace, renderer, destination, true,
      proc(source, scratch, output: GpuResourceHandle): bool =
        material.submit(source, scratch, output, gcamPremultiplied, radius.int))
