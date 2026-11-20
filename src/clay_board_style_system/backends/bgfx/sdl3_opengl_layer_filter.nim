## Apply the Style RGB matrix to an SDL layer through shared OpenGL storage.
import ../../paint/layer_color_filter
import ../../runtime/[gpu_color_matrix, gpu_host]
import ../sdl3/renderer
import ./[sdl3_opengl_context, sdl3_opengl_target]

proc newSdl3BgfxOpenGlLayerColorFilter*(
    context: Sdl3BgfxOpenGlContext;
    host: GpuHost;
    namespace: GpuNamespaceId;
    material: GpuColorMatrixMaterial
): Sdl3LayerColorFilterProc =
  ## SDL owns the source, destination and final composition of the layer.
  if context.nativeRenderer().isNil or not host.isReady() or
      host.provider() != gpkBgfx or host.config().presentation or
      not material.belongsTo(host, namespace):
    raise newException(ValueError, "SDL OpenGL layer filtering requires an offscreen bgfx color matrix material")

  result = proc(renderer, destination: pointer; filter: LayerColorFilter): bool =
    if renderer != context.nativeRenderer() or not host.isReady() or
        host.hasActiveGpuFrame() or not material.belongsTo(host, namespace):
      return false
    try:
      let source = describeActiveSdl3OpenGlTarget(renderer, sampled = true)
      let output = describeSdl3OpenGlTarget(renderer, destination)
      if source.name == output.name or
          source.descriptor.width != output.descriptor.width or
          source.descriptor.height != output.descriptor.height:
        return false
      context.withSdl3BgfxOpenGlContext:
        var sourceHandle, outputHandle: GpuResourceHandle
        try:
          sourceHandle = context.importSdl3OpenGlTarget(host, namespace, source)
          outputHandle = context.importSdl3OpenGlTarget(host, namespace, output)
          let frame = host.beginGpuFrame()
          try:
            result = material.submit(sourceHandle, outputHandle, filter, gcamPremultiplied)
          finally:
            host.endGpuFrame(frame)
        finally:
          host.retireSdl3OpenGlTargets([outputHandle, sourceHandle])
    except GpuHostError:
      result = false
