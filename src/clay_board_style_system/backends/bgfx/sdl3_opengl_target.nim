## Optional bridge for an SDL renderer sharing OpenGL textures with bgfx.
import ../../runtime/gpu_host
import ../../vendor/sdl3
import ../sdl3/config
import ./adapter

{.passL: sdl3LinkFlags.}

const
  sdlGlTextureName = "SDL.texture.opengl.texture"
  sdlGlTextureTarget = "SDL.texture.opengl.target"
  sdlTextureFormat = "SDL.texture.format"
  sdlTextureAccess = "SDL.texture.access"
  glTexture2d = 0x0DE1

type Sdl3OpenGlTarget* = tuple[descriptor: GpuRenderTargetDescriptor, name: uint32]

proc describeSdl3OpenGlTarget*(
    renderer, texture: pointer;
    sampled = false
): Sdl3OpenGlTarget =
  ## Inspect an SDL-owned RGBA32 target on the SDL thread.
  if renderer.isNil:
    raise newException(GpuHostError, "SDL renderer is missing")
  let rendererName = SDL3.getRendererName(renderer)
  if rendererName.isNil or $rendererName != "opengl":
    raise newException(GpuHostError, "SDL layer import requires the OpenGL renderer")
  if texture.isNil:
    raise newException(GpuHostError, "SDL texture target is missing")
  let properties = SDL3.getTextureProperties(texture)
  let nativeTexture = SDL3.getNumberProperty(properties, sdlGlTextureName, 0)
  if nativeTexture <= 0 or nativeTexture > high(uint32).int64 or
      SDL3.getNumberProperty(properties, sdlGlTextureTarget, 0) != glTexture2d or
      SDL3.getNumberProperty(properties, sdlTextureAccess, -1) !=
        SDL_TEXTUREACCESS_TARGET.int64 or
      SDL3.getNumberProperty(properties, sdlTextureFormat, 0) !=
        SDL_PIXELFORMAT_RGBA32.uint32.int64:
    raise newException(GpuHostError, "SDL layer is not a shareable RGBA32 texture")
  var width, height: cfloat
  if not SDL3.getTextureSize(texture, addr width, addr height) or
      not (width >= 1 and width <= high(uint16).cfloat and
           height >= 1 and height <= high(uint16).cfloat):
    raise newException(GpuHostError, "SDL layer dimensions exceed OpenGL import limits")
  (GpuRenderTargetDescriptor(
    width: width.uint32, height: height.uint32, format: gtfRgba8,
    usage: (if sampled: {gtuRenderTarget, gtuSampled} else: {gtuRenderTarget}),
    label: "SDL OpenGL layer"
  ), nativeTexture.uint32)

proc describeActiveSdl3OpenGlTarget*(renderer: pointer;
    sampled = false): Sdl3OpenGlTarget =
  if renderer.isNil:
    raise newException(GpuHostError, "SDL renderer is missing")
  describeSdl3OpenGlTarget(renderer, SDL3.getRenderTarget(renderer), sampled)

proc importSdl3BgfxOpenGlRenderTarget*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    renderer: pointer
): GpuResourceHandle =
  ## Import on the current SDL context. The caller keeps the SDL texture
  ## alive until the import is released and a retirement frame is submitted.
  if not host.isReady() or host.hasActiveGpuFrame():
    raise newException(GpuHostError, "SDL layer import requires an idle GPU host")
  let source = describeActiveSdl3OpenGlTarget(renderer)
  if not SDL3.flushRenderer(renderer):
    raise newException(GpuHostError, "SDL renderer could not flush its layer")
  host.importBgfxOpenGlRenderTarget(namespace, source.descriptor,
    SDL3.gL_GetCurrentContext(), source.name, rowsTopDown = true)
