## Opt-in zero-copy composition into the active SDL OpenGL layer.
import ../../paint/[gpu_direct_compositor, gpu_host_compositor]
import ../../runtime/gpu_host
import ../../vendor/sdl3
import ./sdl3_opengl_target

proc newSdl3BgfxOpenGlLayerCompositor*(
    renderer: pointer;
    host: GpuHost;
    material: GpuHostDirectCompositeMaterial
): GpuDirectCompositor =
  ## SDL owns presentation. The offscreen bgfx host must use the same EGL
  ## context and run its render work synchronously on the SDL thread.
  ## Close the host while its SDL context is still alive.
  if renderer.isNil or not host.isReady() or host.provider() != gpkBgfx or
      host.config().presentation:
    raise newException(ValueError, "SDL OpenGL composition requires an offscreen bgfx host")
  let compositor = host.newGpuHostDirectCompositor(material)
  var capabilities = compositor.capabilities
  # The SDL paint context has no typed target yet. The underlying compositor
  # checks it after this callback imports the active layer.
  capabilities.typedOffscreenTargetRequired = false
  newGpuDirectCompositor(capabilities,
    proc(request: GpuDirectCompositeRequest): GpuDirectCompositeStatus =
      if not host.isReady() or host.hasActiveGpuFrame():
        return gdcsRetry
      let texture = SDL3.getRenderTarget(renderer)
      if texture.isNil:
        return gdcsUnsupported
      var target: GpuResourceHandle
      try:
        target = host.importSdl3BgfxOpenGlRenderTarget(material.namespace, renderer)
      except GpuHostError:
        return gdcsUnsupported
      try:
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
          if host.releaseGpuResource(target):
            let retirement = host.beginGpuFrame()
            host.endGpuFrame(retirement)
      except GpuHostError:
        result = gdcsFailed
      finally:
        # bgfx leaves its framebuffer bound. Rebind the SDL target even
        # when composition was rejected so subsequent SDL paint stays ordered.
        if not SDL3.setRenderTarget(renderer, nil) or
            not SDL3.setRenderTarget(renderer, texture):
          raise newException(IOError, "could not restore SDL OpenGL layer: " & $SDL3.getError())
  )
