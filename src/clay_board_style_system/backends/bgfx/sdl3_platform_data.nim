when not defined(cbssGpuBgfx):
  {.error: "SDL3 bgfx platform data requires -d:cbssGpuBgfx and the optional bgfxim package".}

import bgfx

import ../../vendor/sdl3
import ./platform_data

when not defined(cbssTestSdl3PlatformData):
  import ../sdl3/config

  when sdl3CompileFlags.len > 0:
    {.passC: sdl3CompileFlags.}
  {.passL: sdl3LinkFlags.}

const
  sdlPropCocoaWindow = "SDL.window.cocoa.window"
  sdlPropWin32Window = "SDL.window.win32.hwnd"
  sdlPropWaylandDisplay = "SDL.window.wayland.display"
  sdlPropWaylandSurface = "SDL.window.wayland.surface"
  sdlPropX11Display = "SDL.window.x11.display"
  sdlPropX11Window = "SDL.window.x11.window"

proc requiredPointer(properties: SDL_PropertiesID; name: string): pointer =
  result = SDL3.getPointerProperty(properties, name.cstring, nil)
  if result.isNil:
    raise newException(BgfxPlatformDataError, "SDL3 window property is missing: " & name)

proc bgfxPlatformDataFromSdl3Window*(window: pointer): bgfx_platform_data_t =
  if window.isNil:
    raise newException(BgfxPlatformDataError, "SDL3 window is nil")
  let properties = SDL3.getWindowProperties(window)
  if properties == SDL_PropertiesID(0):
    raise newException(BgfxPlatformDataError, "SDL3 window properties are unavailable")
  let rawDriver = SDL3.getCurrentVideoDriver()
  if rawDriver.isNil:
    raise newException(BgfxPlatformDataError, "SDL3 video driver is unavailable")

  let driver = $rawDriver
  case driver
  of "x11":
    let windowNumber = SDL3.getNumberProperty(properties, sdlPropX11Window, 0)
    if windowNumber <= 0:
      raise newException(BgfxPlatformDataError, "SDL3 X11 window handle is missing")
    result = bgfxPlatformData(BgfxNativeWindowHandles(
      system: bnwsX11,
      display: requiredPointer(properties, sdlPropX11Display),
      window: cast[pointer](uint64(windowNumber))
    ))
  of "wayland":
    result = bgfxPlatformData(BgfxNativeWindowHandles(
      system: bnwsWayland,
      display: requiredPointer(properties, sdlPropWaylandDisplay),
      window: requiredPointer(properties, sdlPropWaylandSurface)
    ))
  of "windows":
    result = bgfxPlatformData(BgfxNativeWindowHandles(
      system: bnwsWin32,
      window: requiredPointer(properties, sdlPropWin32Window)
    ))
  of "cocoa":
    result = bgfxPlatformData(BgfxNativeWindowHandles(
      system: bnwsCocoa,
      window: requiredPointer(properties, sdlPropCocoaWindow)
    ))
  else:
    raise newException(
      BgfxPlatformDataError,
      "SDL3 video driver is not supported by the bgfx adapter: " & driver
    )
