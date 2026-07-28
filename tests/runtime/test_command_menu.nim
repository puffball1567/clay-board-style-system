import std/unittest

import clay_board_style_system

proc menuItems(): seq[CommandMenuItem] =
  @[
    CommandMenuItem(label: "Open", value: "open"),
    CommandMenuItem(label: "Save", value: "save"),
    CommandMenuItem(label: "Close", value: "close")
  ]

suite "command menu widget":
  test "command menu shows and closes":
    let ui = initUiRoot()
    let file = ui.commandMenu(menuItems())
    var shown = false
    var closed = false

    file.onShow = proc(event: DispatchResult): bool =
      shown = true
      false

    file.onClose = proc(event: DispatchResult): bool =
      closed = true
      false

    check file.show()
    check file.isOpen()
    check shown
    check esActive in ui.tree.nodes[file.container.nodeId.nodeIndex].states

    check file.close()
    check not file.isOpen()
    check closed
    check esDisabled in ui.tree.nodes[file.container.nodeId.nodeIndex].states

  test "item click activates selected value and closes":
    let ui = initUiRoot()
    let file = ui.commandMenu(menuItems(), open = true)
    var changed = ""

    file.onChange = proc(event: DispatchResult): bool =
      changed = file.selectedValue()
      false

    discard file.itemNodes[1].emit(InputEvent(kind: iekClick))

    check file.selectedValue() == "save"
    check changed == "save"
    check not file.isOpen()

  test "keyboard navigation and activation":
    let ui = initUiRoot()
    let file = ui.commandMenu(menuItems(), open = true)

    discard file.container.emit(keyDownEvent("ArrowDown"))
    check file.activeIndex() == 1

    discard file.container.emit(keyDownEvent("Enter"))
    check file.selectedValue() == "save"
    check not file.isOpen()

  test "escape closes command menu":
    let ui = initUiRoot()
    let file = ui.commandMenu(menuItems(), open = true)

    discard file.container.emit(keyDownEvent("Escape"))

    check not file.isOpen()

  test "disabled command menu suppresses interaction":
    let ui = initUiRoot()
    let file = ui.commandMenu(menuItems(), open = true, disabled = true)
    var changed = false

    file.onChange = proc(event: DispatchResult): bool =
      changed = true
      false

    discard file.itemNodes[1].emit(InputEvent(kind: iekClick))
    discard file.container.emit(keyDownEvent("ArrowDown"))

    check not changed
    check file.selectedValue() == ""
    check esDisabled in ui.tree.nodes[file.container.nodeId.nodeIndex].states

  test "disabled command menu items cannot activate and are skipped":
    let ui = initUiRoot()
    let file = ui.commandMenu(@[
      CommandMenuItem(label: "Open", value: "open"),
      CommandMenuItem(label: "Save", value: "save", disabled: true),
      CommandMenuItem(label: "Close", value: "close")
    ], open = true)

    discard file.itemNodes[1].emit(InputEvent(kind: iekClick))
    check file.selectedValue() == ""
    check file.isOpen()

    discard file.container.emit(keyDownEvent("ArrowDown"))
    check file.activeIndex() == 2
