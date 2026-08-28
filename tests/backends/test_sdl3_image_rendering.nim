import std/unittest

import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/core/computed_style
import clay_board_style_system/vendor/sdl3

suite "SDL3 image-rendering mapping":
  test "auto and smooth use linear filtering":
    check sdlImageScaleMode(irAuto) == SDL_SCALEMODE_LINEAR
    check sdlImageScaleMode(irSmooth) == SDL_SCALEMODE_LINEAR

  test "crisp edges uses nearest-neighbor filtering":
    check sdlImageScaleMode(irCrispEdges) == SDL_SCALEMODE_NEAREST

  test "pixelated uses SDL pixel-art scaling":
    check sdlImageScaleMode(irPixelated) == SDL_SCALEMODE_PIXELART
