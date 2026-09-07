when not defined(cbssGpuBgfx):
  {.error: "bgfx platform data requires -d:cbssGpuBgfx and the optional bgfxim package".}

import bgfx

type
  BgfxNativeWindowSystem* = enum
    bnwsX11,
    bnwsWayland,
    bnwsWin32,
    bnwsCocoa

  BgfxNativeWindowHandles* = object
    system*: BgfxNativeWindowSystem
    display*: pointer
    window*: pointer

  BgfxPlatformDataError* = object of CatchableError

proc bgfxPlatformData*(handles: BgfxNativeWindowHandles): bgfx_platform_data_t =
  if handles.window.isNil:
    raise newException(BgfxPlatformDataError, "native window handle is missing")
  if handles.system in {bnwsX11, bnwsWayland} and handles.display.isNil:
    raise newException(BgfxPlatformDataError, "native display handle is missing")
  if handles.system in {bnwsWin32, bnwsCocoa} and not handles.display.isNil:
    raise newException(BgfxPlatformDataError, "native display handle is not valid for this window system")

  result.ndt = handles.display
  result.nwh = handles.window
  result.type =
    if handles.system == bnwsWayland:
      BGFX_NATIVE_WINDOW_HANDLE_TYPE_WAYLAND
    else:
      BGFX_NATIVE_WINDOW_HANDLE_TYPE_DEFAULT
