import std/unittest

import clay_board_style_system/backends/sdl3/renderer

suite "SDL3 wheel coalescing":
  test "stationary wheel samples retain summed deltas and latest timestamp":
    var aggregate = Sdl3Event(
      kind: sekWheel, timestamp: 10,
      wheelX: 1, wheelY: -2,
      wheelMouseX: 24, wheelMouseY: 36
    )
    let next = Sdl3Event(
      kind: sekWheel, timestamp: 11,
      wheelX: 0.5, wheelY: -1,
      wheelMouseX: 24, wheelMouseY: 36
    )

    check aggregate.mergeWheelEvent(next)
    check aggregate.wheelX == 1.5
    check aggregate.wheelY == -3
    check aggregate.wheelMouseX == 24
    check aggregate.wheelMouseY == 36
    check aggregate.timestamp == 11

  test "a changed hit position keeps the next scroll dispatch separate":
    var aggregate = Sdl3Event(
      kind: sekWheel, timestamp: 10,
      wheelX: 0, wheelY: -2,
      wheelMouseX: 24, wheelMouseY: 36
    )
    let next = Sdl3Event(
      kind: sekWheel, timestamp: 11,
      wheelX: 0, wheelY: -1,
      wheelMouseX: 80, wheelMouseY: 36
    )

    check not aggregate.mergeWheelEvent(next)
    check aggregate.wheelY == -2
    check aggregate.wheelMouseX == 24
    check aggregate.timestamp == 10

  test "non-wheel events remain a dispatch boundary":
    var aggregate = Sdl3Event(
      kind: sekWheel, timestamp: 10, wheelY: -1,
      wheelMouseX: 24, wheelMouseY: 36
    )
    check not aggregate.mergeWheelEvent(Sdl3Event(
      kind: sekPointerMove, timestamp: 11, x: 24, y: 36
    ))
    check aggregate.wheelY == -1
    check aggregate.timestamp == 10
