import std/[math, unittest]

import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/input/events
import clay_board_style_system/vendor/sdl3

suite "SDL3 pen input conversion":
  test "every SDL pen axis is capability marked and normalized":
    var pointer = PointerData(device: pdkPenUnknown)

    pointer.applyPenAxis(SDL_PEN_AXIS_PRESSURE, 1.5)
    pointer.applyPenAxis(SDL_PEN_AXIS_XTILT, -120)
    pointer.applyPenAxis(SDL_PEN_AXIS_YTILT, 120)
    pointer.applyPenAxis(SDL_PEN_AXIS_DISTANCE, -0.5)
    pointer.applyPenAxis(SDL_PEN_AXIS_ROTATION, 250)
    pointer.applyPenAxis(SDL_PEN_AXIS_SLIDER, 1.5)
    pointer.applyPenAxis(SDL_PEN_AXIS_TANGENTIAL_PRESSURE, -1.5)

    check pointer.axes == {
      paPressure, paTiltX, paTiltY, paDistance, paRotation, paSlider,
      paTangentialPressure
    }
    check pointer.pressure == 1
    check pointer.tiltX == -90
    check pointer.tiltY == 90
    check pointer.distance == 0
    check pointer.rotation == 180
    check pointer.slider == 1
    check pointer.tangentialPressure == -1

  test "invalid axis samples do not invent capabilities or overwrite values":
    var pointer = PointerData(
      axes: {paPressure},
      pressure: 0.4
    )

    pointer.applyPenAxis(SDL_PEN_AXIS_PRESSURE, NaN.float32)
    pointer.applyPenAxis(SDL_PEN_AXIS_XTILT, Inf.float32)
    pointer.applyPenAxis(SDL_PEN_AXIS_YTILT, NegInf.float32)

    check pointer.axes == {paPressure}
    check abs(pointer.pressure - 0.4) < 0.0001
    check pointer.tiltX == 0
    check pointer.tiltY == 0

  test "pen state flags preserve contact buttons eraser and proximity":
    var pointer = PointerData()
    let flags = SDL_PenInputFlags(
      (1'u32 shl 0) or (1'u32 shl 1) or (1'u32 shl 3) or
      (1'u32 shl 30) or (1'u32 shl 31)
    )

    pointer.applyPenFlags(flags)

    check pointer.contact
    check pointer.buttons == 0b00101
    check pointer.eraser
    check pointer.inProximity

  test "contact implies proximity on SDL versions without a proximity flag":
    var pointer = PointerData()
    pointer.applyPenFlags(SDL_PenInputFlags(1'u32))

    check pointer.contact
    check pointer.inProximity
