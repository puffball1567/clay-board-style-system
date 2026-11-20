## Opt-in zero-copy composition into the active SDL OpenGL layer.
import ../../paint/[gpu_direct_compositor, gpu_host_compositor]
import ../../runtime/gpu_host
import ./[sdl3_opengl_context, sdl3_opengl_target]

export sdl3_opengl_context

proc newSdl3BgfxOpenGlLayerCompositor*(
    context: Sdl3BgfxOpenGlContext;
    host: GpuHost;
    material: GpuHostDirectCompositeMaterial
): GpuDirectCompositor =
  ## SDL owns presentation. bgfx runs synchronously on the SDL thread
  ## in the second context.
  if context.nativeRenderer().isNil or not host.isReady() or
      host.provider() != gpkBgfx or host.config().presentation:
    raise newException(ValueError, "SDL OpenGL composition requires an offscreen bgfx host")
  let compositor = host.newGpuHostDirectCompositor(material)
  var capabilities = compositor.capabilities
  # The SDL paint context has no typed target yet. The underlying compositor
  # checks it after this callback imports the active layer.
  capabilities.typedOffscreenTargetRequired = false
  newGpuDirectCompositor(capabilities,
    proc(request: GpuDirectCompositeRequest): GpuDirectCompositeStatus =
      let native = context.nativeRenderer()
      if native.isNil:
        return gdcsUnsupported
      if not host.isReady() or host.hasActiveGpuFrame():
        return gdcsRetry
      try:
        let source = describeActiveSdl3OpenGlTarget(native)
        context.withSdl3BgfxOpenGlContext:
          let target = context.importSdl3OpenGlTarget(host, material.namespace, source)
          try:
            var submission = request
            submission.context.offscreenTarget = target
            submission.context.offscreenTargetTopDown = true
            let frame = host.beginGpuFrame()
            try:
              result = compositor.submit(submission)
            finally:
              host.endGpuFrame(frame)
          finally:
            host.retireSdl3OpenGlTargets([target])
      except GpuHostError:
        result = gdcsUnsupported
  )
