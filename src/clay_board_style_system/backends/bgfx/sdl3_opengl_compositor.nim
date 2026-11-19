## Opt-in zero-copy composition into the active SDL OpenGL layer.
import ../../paint/[gpu_direct_compositor, gpu_host_compositor]
import ../../runtime/gpu_host
import ../../vendor/sdl3
import ./[adapter, platform_data, sdl3_opengl_target, sdl3_platform_data]

type
  GlFenceSync = proc(condition, flags: uint32): pointer {.cdecl.}
  GlWaitSync = proc(sync: pointer; flags: uint32; timeout: uint64) {.cdecl.}
  GlDeleteSync = proc(sync: pointer) {.cdecl.}
  GlFlush = proc() {.cdecl.}
  GlIsTexture = proc(name: uint32): uint8 {.cdecl.}

  Sdl3BgfxOpenGlContext* = ref object
    renderer, window: pointer
    sdlContext, gpuContext: SDL_GLContext
    fence: GlFenceSync
    wait: GlWaitSync
    delete: GlDeleteSync
    flush: GlFlush
    isTexture: GlIsTexture

proc newSdl3BgfxOpenGlContext*(renderer: pointer): Sdl3BgfxOpenGlContext =
  ## Create a separate EGL context in the SDL renderer's texture share group.
  ## SDL must be using desktop OpenGL with its context current on this thread.
  if renderer.isNil:
    raise newException(GpuHostError, "an active SDL OpenGL renderer is required")
  let rendererName = SDL3.getRendererName(renderer)
  if rendererName.isNil or $rendererName != "opengl" or
      not SDL3.flushRenderer(renderer):
    raise newException(GpuHostError, "an active SDL OpenGL renderer is required")
  let window = SDL3.getRenderWindow(renderer)
  let sdlContext = SDL3.gL_GetCurrentContext()
  if window.isNil or sdlContext.isNil or SDL3.gL_GetCurrentWindow() != window or
      SDL3.eGL_GetCurrentDisplay().isNil:
    raise newException(GpuHostError, "SDL OpenGL composition requires EGL")

  let context = Sdl3BgfxOpenGlContext(renderer: renderer, window: window,
    sdlContext: sdlContext,
    fence: cast[GlFenceSync](SDL3.gL_GetProcAddress("glFenceSync")),
    wait: cast[GlWaitSync](SDL3.gL_GetProcAddress("glWaitSync")),
    delete: cast[GlDeleteSync](SDL3.gL_GetProcAddress("glDeleteSync")),
    flush: cast[GlFlush](SDL3.gL_GetProcAddress("glFlush")),
    isTexture: cast[GlIsTexture](SDL3.gL_GetProcAddress("glIsTexture")))
  if context.fence.isNil or context.wait.isNil or context.delete.isNil or
      context.flush.isNil or context.isTexture.isNil:
    raise newException(GpuHostError, "OpenGL texture sharing requires fence support")

  var previousShare: cint
  if not SDL3.gL_GetAttribute(SDL_GL_SHARE_WITH_CURRENT_CONTEXT, addr previousShare) or
      not SDL3.gL_SetAttribute(SDL_GL_SHARE_WITH_CURRENT_CONTEXT, 1):
    raise newException(GpuHostError, "SDL could not enable OpenGL context sharing")
  let gpuContext = SDL3.gL_CreateContext(window)
  discard SDL3.gL_SetAttribute(SDL_GL_SHARE_WITH_CURRENT_CONTEXT, previousShare)
  if not SDL3.gL_MakeCurrent(window, sdlContext):
    if not gpuContext.isNil:
      discard SDL3.gL_DestroyContext(gpuContext)
    raise newException(GpuHostError, "SDL could not restore its OpenGL context")
  if gpuContext.isNil:
    raise newException(GpuHostError, "SDL could not create the shared OpenGL context")
  context.gpuContext = gpuContext
  context

proc platformData*(context: Sdl3BgfxOpenGlContext): BgfxPlatformData =
  if context.isNil or context.gpuContext.isNil:
    raise newException(GpuHostError, "SDL shared OpenGL context is closed")
  result = bgfxPlatformDataFromSdl3Window(context.window)
  result.platform.context = context.gpuContext

proc switchContext(context: Sdl3BgfxOpenGlContext; next: SDL_GLContext): bool =
  const glSyncGpuCommandsComplete = 0x9117'u32
  let sync = context.fence(glSyncGpuCommandsComplete, 0)
  if sync.isNil:
    return false
  context.flush()
  if not SDL3.gL_MakeCurrent(context.window, next):
    context.delete(sync)
    return false
  # Queue the dependency on the receiving context's GPU stream.
  context.wait(sync, 0, high(uint64))
  context.delete(sync)
  true

proc enterGpuContext(context: Sdl3BgfxOpenGlContext) =
  if context.isNil or context.gpuContext.isNil or
      SDL3.gL_GetCurrentContext() != context.sdlContext or
      not SDL3.flushRenderer(context.renderer) or
      not context.switchContext(context.gpuContext):
    raise newException(GpuHostError, "could not acquire the shared OpenGL context")

proc leaveGpuContext(context: Sdl3BgfxOpenGlContext) =
  if SDL3.gL_GetCurrentContext() != context.gpuContext or
      not context.switchContext(context.sdlContext):
    discard SDL3.gL_MakeCurrent(context.window, context.sdlContext)
    raise newException(IOError, "could not synchronize the SDL OpenGL context")

template withSdl3BgfxOpenGlContext*(context: Sdl3BgfxOpenGlContext; body: untyped) =
  ## Run host initialization, producer work, or host teardown on the bgfx
  ## context, then restore SDL's context with ordered GPU access.
  let sharedContext = context
  sharedContext.enterGpuContext()
  try:
    body
  finally:
    sharedContext.leaveGpuContext()

proc close*(context: Sdl3BgfxOpenGlContext) =
  ## Close the associated bgfx host first, inside its context scope.
  if context.isNil or context.gpuContext.isNil:
    return
  if SDL3.gL_GetCurrentContext() == context.gpuContext or
      not SDL3.gL_DestroyContext(context.gpuContext):
    raise newException(GpuHostError, "could not close the shared OpenGL context")
  context.gpuContext = nil

proc newSdl3BgfxOpenGlLayerCompositor*(
    context: Sdl3BgfxOpenGlContext;
    host: GpuHost;
    material: GpuHostDirectCompositeMaterial
): GpuDirectCompositor =
  ## SDL owns presentation. bgfx runs synchronously on the SDL thread
  ## in the second context.
  if context.isNil or context.gpuContext.isNil or not host.isReady() or
      host.provider() != gpkBgfx or host.config().presentation:
    raise newException(ValueError, "SDL OpenGL composition requires an offscreen bgfx host")
  let compositor = host.newGpuHostDirectCompositor(material)
  var capabilities = compositor.capabilities
  # The SDL paint context has no typed target yet. The underlying compositor
  # checks it after this callback imports the active layer.
  capabilities.typedOffscreenTargetRequired = false
  newGpuDirectCompositor(capabilities,
    proc(request: GpuDirectCompositeRequest): GpuDirectCompositeStatus =
      if context.gpuContext.isNil:
        return gdcsUnsupported
      if not host.isReady() or host.hasActiveGpuFrame():
        return gdcsRetry
      try:
        let source = describeActiveSdl3OpenGlTarget(context.renderer)
        context.withSdl3BgfxOpenGlContext:
          if context.isTexture(source.name) == 0:
            return gdcsUnsupported
          let target = host.importBgfxOpenGlRenderTarget(material.namespace,
            source.descriptor, context.gpuContext, source.name)
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
        result = gdcsUnsupported
  )
