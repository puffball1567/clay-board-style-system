import std/unittest

import clay_board_style_system

proc listItems(): seq[ListItem] =
  @[
    ListItem(label: "Alpha", value: "alpha"),
    ListItem(label: "Beta", value: "beta"),
    ListItem(label: "Gamma", value: "gamma")
  ]

suite "list box component":
  test "list box initializes selected value":
    let ui = initUiRoot()
    let files = ui.listBox(listItems(), selectedValue = "beta")

    check files.selectedIndex() == 1
    check files.selectedValue() == "beta"
    check esSelected in ui.tree.nodes[files.itemNodes[1].nodeId.nodeIndex].states

  test "item click selects value and emits value events":
    let ui = initUiRoot()
    let files = ui.listBox(listItems())
    var inputValue = ""
    var changeValue = ""

    files.onInput = proc(event: DispatchResult): bool =
      inputValue = files.selectedValue()
      false

    files.onChange = proc(event: DispatchResult): bool =
      changeValue = files.selectedValue()
      false

    discard files.itemNodes[2].emit(InputEvent(kind: iekClick))

    check files.selectedValue() == "gamma"
    check inputValue == "gamma"
    check changeValue == "gamma"

  test "keyboard navigation supports arrows home and end":
    let ui = initUiRoot()
    let files = ui.listBox(listItems(), selectedValue = "beta")

    discard files.container.emit(keyDownEvent("ArrowDown"))
    check files.selectedValue() == "gamma"

    discard files.container.emit(keyDownEvent("Home"))
    check files.selectedValue() == "alpha"

    discard files.container.emit(keyDownEvent("End"))
    check files.selectedValue() == "gamma"

    discard files.container.emit(keyDownEvent("ArrowUp"))
    check files.selectedValue() == "beta"

  test "disabled items cannot be selected and are skipped":
    let ui = initUiRoot()
    let files = ui.listBox(@[
      ListItem(label: "Alpha", value: "alpha"),
      ListItem(label: "Beta", value: "beta", disabled: true),
      ListItem(label: "Gamma", value: "gamma")
    ], selectedValue = "alpha")
    var changed = false

    files.onChange = proc(event: DispatchResult): bool =
      changed = true
      false

    discard files.itemNodes[1].emit(InputEvent(kind: iekClick))
    check files.selectedValue() == "alpha"
    check not changed
    check esDisabled in ui.tree.nodes[files.itemNodes[1].nodeId.nodeIndex].states

    discard files.container.emit(keyDownEvent("ArrowDown"))
    check files.selectedValue() == "gamma"

  test "disabled list box suppresses interaction":
    let ui = initUiRoot()
    let files = ui.listBox(listItems(), selectedValue = "alpha", disabled = true)
    var changed = false

    files.onChange = proc(event: DispatchResult): bool =
      changed = true
      false

    discard files.itemNodes[1].emit(InputEvent(kind: iekClick))
    discard files.container.emit(keyDownEvent("ArrowDown"))

    check files.selectedValue() == "alpha"
    check not changed
    check esDisabled in ui.tree.nodes[files.container.nodeId.nodeIndex].states

  test "setSelectedValue updates without emitting by default":
    let ui = initUiRoot()
    let files = ui.listBox(listItems())
    var changed = false

    files.onChange = proc(event: DispatchResult): bool =
      changed = true
      false

    files.setSelectedValue("gamma")

    check files.selectedValue() == "gamma"
    check not changed
