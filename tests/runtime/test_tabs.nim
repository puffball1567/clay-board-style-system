import std/unittest

import clay_board_style_system

proc tabItems(): seq[TabItem] =
  @[
    TabItem(label: "Preview", value: "preview"),
    TabItem(label: "Code", value: "code"),
    TabItem(label: "Settings", value: "settings")
  ]

suite "tabs component":
  test "tabs initialize selected value":
    let ui = initUiRoot()
    let editor = ui.tabs(tabItems(), selectedValue = "code")

    check editor.selectedIndex() == 1
    check editor.selectedValue() == "code"
    check esSelected in ui.tree.nodes[editor.tabNodes[1].nodeId.nodeIndex].states

  test "tab click selects value and emits value events":
    let ui = initUiRoot()
    let editor = ui.tabs(tabItems())
    var inputValue = ""
    var changeValue = ""

    editor.onInput = proc(event: DispatchResult): bool =
      inputValue = editor.selectedValue()
      false

    editor.onChange = proc(event: DispatchResult): bool =
      changeValue = editor.selectedValue()
      false

    discard editor.tabNodes[2].emit(InputEvent(kind: iekClick))

    check editor.selectedValue() == "settings"
    check inputValue == "settings"
    check changeValue == "settings"

  test "keyboard navigation selects next and previous tabs":
    let ui = initUiRoot()
    let editor = ui.tabs(tabItems(), selectedValue = "code")

    discard editor.container.emit(keyDownEvent("ArrowRight"))
    check editor.selectedValue() == "settings"

    discard editor.container.emit(keyDownEvent("ArrowLeft"))
    check editor.selectedValue() == "code"

  test "disabled tabs cannot be selected and are skipped":
    let ui = initUiRoot()
    let editor = ui.tabs(@[
      TabItem(label: "Preview", value: "preview"),
      TabItem(label: "Code", value: "code", disabled: true),
      TabItem(label: "Settings", value: "settings")
    ], selectedValue = "preview")
    var changed = false

    editor.onChange = proc(event: DispatchResult): bool =
      changed = true
      false

    discard editor.tabNodes[1].emit(InputEvent(kind: iekClick))
    check editor.selectedValue() == "preview"
    check not changed
    check esDisabled in ui.tree.nodes[editor.tabNodes[1].nodeId.nodeIndex].states

    discard editor.container.emit(keyDownEvent("ArrowRight"))
    check editor.selectedValue() == "settings"

  test "disabled tabs component suppresses interaction":
    let ui = initUiRoot()
    let editor = ui.tabs(tabItems(), selectedValue = "preview", disabled = true)
    var changed = false

    editor.onChange = proc(event: DispatchResult): bool =
      changed = true
      false

    discard editor.tabNodes[1].emit(InputEvent(kind: iekClick))
    discard editor.container.emit(keyDownEvent("ArrowRight"))

    check editor.selectedValue() == "preview"
    check not changed
    check esDisabled in ui.tree.nodes[editor.container.nodeId.nodeIndex].states

  test "setSelectedValue updates without emitting by default":
    let ui = initUiRoot()
    let editor = ui.tabs(tabItems())
    var changed = false

    editor.onChange = proc(event: DispatchResult): bool =
      changed = true
      false

    editor.setSelectedValue("settings")

    check editor.selectedValue() == "settings"
    check not changed
