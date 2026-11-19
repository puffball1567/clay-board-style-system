## Optional bridge for an SDL renderer sharing the bgfx host's OpenGL context.
import ../../runtime/gpu_host
import ../../vendor/sdl3
import ../sdl3/config
import ./adapter

{.passL: sdl3LinkFlags.}

const
  sdlGlTextureName = "SDL.texture.opengl.texture"
  sdlGlTextureTarget = "SDL.texture.opengl.target"
  sdlTextureFormat = "SDL.texture.format"
  glTexture2d = 0x0DE1

proc importSdl3BgfxOpenGlRenderTarget*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    renderer: pointer
): GpuResourceHandle =
  ## Import the active RGBA32 SDL layer between GPU frames on the SDL thread.
  ## Keep the SDL texture alive until the handle is released and its bgfx
  ## retirement frame is submitted on the shared context.
  if renderer.isNil:
    raise newException(GpuHostError, "SDL renderer is missing")
  if not host.isReady() or host.hasActiveGpuFrame():
    raise newException(GpuHostError, "SDL layer import requires an idle GPU host")
  let rendererName = SDL3.getRendererName(renderer)
  if rendererName.isNil or $rendererName != "opengl":
    raise newException(GpuHostError, "SDL layer import requires the OpenGL renderer")
  let target = SDL3.getRenderTarget(renderer)
  if target.isNil:
    raise newException(GpuHostError, "SDL renderer has no active texture target")
  let properties = SDL3.getTextureProperties(target)
  let nativeTexture = SDL3.getNumberProperty(properties, sdlGlTextureName, 0)
  if nativeTexture <= 0 or nativeTexture > high(uint32).int64 or
      SDL3.getNumberProperty(properties, sdlGlTextureTarget, 0) != glTexture2d or
      SDL3.getNumberProperty(properties, sdlTextureFormat, 0) !=
        SDL_PIXELFORMAT_RGBA32.uint32.int64:
    raise newException(GpuHostError, "SDL layer is not a shareable RGBA32 texture")
  var width, height: cfloat
  if not SDL3.getTextureSize(target, addr width, addr height) or
      not (width >= 1 and width <= high(uint16).cfloat and
           height >= 1 and height <= high(uint16).cfloat):
    raise newException(GpuHostError, "SDL layer dimensions exceed OpenGL import limits")
  if not SDL3.flushRenderer(renderer):
    raise newException(GpuHostError, "SDL renderer could not flush its layer")
  host.importBgfxOpenGlRenderTarget(namespace, GpuRenderTargetDescriptor(
    width: width.uint32, height: height.uint32, format: gtfRgba8,
    usage: {gtuRenderTarget}, label: "SDL OpenGL layer"
  ), SDL3.gL_GetCurrentContext(), nativeTexture.uint32)
