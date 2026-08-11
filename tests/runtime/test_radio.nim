import std/unittest

import clay_board_style_system

suite "radio component":
  test "radio set keeps one selected value":
    let ui = initUiRoot()
    let density = initRadioSet()
    let compact = ui.radio(density, "Compact", "compact", checked = true)
    let roomy = ui.radio(density, "Roomy", "roomy")
    var changed = ""

    roomy.onChange = proc(event: DispatchResult): EventOutcome =
      changed = roomy.value()
      false

    discard roomy.container.emit(InputEvent(kind: iekClick))

    check not compact.checked()
    check roomy.checked()
    check density.selectedValue == "roomy"
    check changed == "roomy"
    check esChecked notin ui.tree.nodes[compact.container.nodeId.nodeIndex].states
    check esChecked in ui.tree.nodes[roomy.container.nodeId.nodeIndex].states
    check esChecked notin ui.tree.nodes[compact.markerNode.nodeId.nodeIndex].states
    check esChecked in ui.tree.nodes[roomy.markerNode.nodeId.nodeIndex].states

  test "initial selected value checks matching radio":
    let ui = initUiRoot()
    let density = initRadioSet("roomy")
    let compact = ui.radio(density, "Compact", "compact")
    let roomy = ui.radio(density, "Roomy", "roomy")

    check not compact.checked()
    check roomy.checked()

  test "select does not emit when already checked":
    let ui = initUiRoot()
    let density = initRadioSet()
    let compact = ui.radio(density, "Compact", "compact", checked = true)
    var changed = false

    compact.onChange = proc(event: DispatchResult): EventOutcome =
      changed = true
      false

    compact.select()

    check compact.checked()
    check not changed

  test "keyboard activation uses click path":
    let ui = initUiRoot()
    let density = initRadioSet()
    let compact = ui.radio(density, "Compact", "compact")
    var clicked = 0
    var changed = 0

    compact.onClick = proc(event: DispatchResult): EventOutcome =
      inc clicked
      false

    compact.onChange = proc(event: DispatchResult): EventOutcome =
      inc changed
      false

    discard compact.container.emit(keyDownEvent(" "))

    check compact.checked()
    check clicked == 1
    check changed == 1

  test "pointer down selects without waiting for click synthesis":
    let ui = initUiRoot()
    let density = initRadioSet("compact")
    let compact = ui.radio(density, "Compact", "compact")
    let roomy = ui.radio(density, "Roomy", "roomy")
    var changed = 0

    roomy.onChange = proc(event: DispatchResult): EventOutcome =
      inc changed
      false

    discard roomy.container.emit(InputEvent(kind: iekPointerDown))
    discard roomy.container.emit(InputEvent(kind: iekClick))

    check not compact.checked()
    check roomy.checked()
    check density.selectedValue == "roomy"
    check changed == 1

  test "rapid alternating pointer downs keep radio set consistent":
    let ui = initUiRoot()
    let density = initRadioSet("compact")
    let compact = ui.radio(density, "Compact", "compact")
    let roomy = ui.radio(density, "Roomy", "roomy")

    for _ in 0 ..< 8:
      discard roomy.container.emit(InputEvent(kind: iekPointerDown))
      check not compact.checked()
      check roomy.checked()
      check density.selectedValue == "roomy"

      discard compact.container.emit(InputEvent(kind: iekPointerDown))
      check compact.checked()
      check not roomy.checked()
      check density.selectedValue == "compact"

    check esChecked in ui.tree.nodes[compact.markerNode.nodeId.nodeIndex].states
    check esChecked in ui.tree.nodes[compact.state.indicatorNode.nodeId.nodeIndex].states
    check esChecked notin ui.tree.nodes[roomy.markerNode.nodeId.nodeIndex].states
    check esChecked notin ui.tree.nodes[roomy.state.indicatorNode.nodeId.nodeIndex].states

  test "disabled radio suppresses pointer and keyboard changes":
    let ui = initUiRoot()
    let density = initRadioSet()
    let compact = ui.radio(
      RadioParams(label: "Compact", value: "compact", disabled: true),
      density
    )
    var changed = false
    var clicked = false

    compact.onChange = proc(event: DispatchResult): EventOutcome =
      changed = true
      false

    compact.onClick = proc(event: DispatchResult): EventOutcome =
      clicked = true
      false

    discard compact.container.emit(InputEvent(kind: iekClick))
    discard compact.container.emit(keyDownEvent("Enter"))

    check not compact.checked()
    check not changed
    check not clicked
    check esDisabled in ui.tree.nodes[compact.container.nodeId.nodeIndex].states

  test "setLabel and setDisabled update visible state":
    let ui = initUiRoot()
    let density = initRadioSet()
    let compact = ui.radio(density, "Compact", "compact")

    compact.setLabel("Dense")
    compact.setDisabled(true)

    check ui.tree.nodes[compact.labelNode.nodeId.nodeIndex].text == "Dense"
    check compact.disabled()
    check esDisabled in ui.tree.nodes[compact.container.nodeId.nodeIndex].states
