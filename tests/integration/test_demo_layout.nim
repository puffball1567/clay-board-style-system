import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/testing/test_driver
import ../../examples/sdl3_demo

proc containsRect(outerRect, innerRect: Rect; tolerance = 0.5'f32): bool =
  innerRect.x >= outerRect.x - tolerance and
    innerRect.y >= outerRect.y - tolerance and
    innerRect.x + innerRect.w <= outerRect.x + outerRect.w + tolerance and
    innerRect.y + innerRect.h <= outerRect.y + outerRect.h + tolerance

suite "SDL3 demo layout regressions":
  test "command menu and absolute badge stay inside their visual parents":
    let harness = initDemoHarness()
    let driver = initCbssTestDriver(buildDemoHarnessUi(harness), size(1200, 980))

    let menuRow = driver.rectFor(byGroup("command-menu-row"))
    let listBox = driver.rectFor(byId("catalog-list-box"))
    let commandMenu = driver.rectFor(byId("catalog-command-menu"))
    let commandMenuLabel = driver.rectFor(byId("catalog-command-menu-label"))
    let demoBody = driver.rectFor(byGroup("demo-body"))
    let badge = driver.rectFor(byGroup("absolute-badge"))

    check menuRow.isSome
    check listBox.isSome
    check commandMenu.isSome
    check commandMenuLabel.isSome
    check commandMenuLabel.get.h <= 14.5'f32
    check menuRow.get.containsRect(listBox.get)
    check menuRow.get.containsRect(commandMenu.get)
    check menuRow.get.containsRect(commandMenuLabel.get)

    for item in driver.allWithin(byId("catalog-command-menu"), byGroup("command-menu-item")):
      let itemRect = driver.rectFor(item)
      check itemRect.isSome
      check commandMenu.get.containsRect(itemRect.get)

    check demoBody.isSome
    check badge.isSome
    check demoBody.get.containsRect(badge.get)
