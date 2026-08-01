import ../../runtime/platform_links
import ../../vendor/sdl3
import ./config

when sdl3CompileFlags.len > 0:
  {.passC: sdl3CompileFlags.}
{.passL: sdl3LinkFlags.}

proc sdl3ExternalUrlAdapter*(): ExternalUrlAdapter =
  externalUrlAdapter(proc(url: string): bool = SDL3.openURL(url.cstring))
