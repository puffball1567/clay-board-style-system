import std/unittest

import clay_board_style_system

when declared(initCbssTestDriver):
  {.fatal: "test driver leaked through the top-level clay_board_style_system module".}

when declared(initSdl3WaylandDriver):
  {.fatal: "SDL3 Wayland test driver leaked through the top-level clay_board_style_system module".}

when declared(newMotionScene):
  {.fatal: "Motion Scene must remain an opt-in import".}

suite "public import boundary":
  test "top-level module remains usable without testing APIs":
    let ui = initUiRoot()
    check ui.tree.nodes.len == 0
