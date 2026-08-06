import std/[options, unittest]

import clay_board_style_system

suite "checkbox component":
  test "checkbox toggles checked state on click and emits value events":
    let ui = initUiRoot()
    let remember = ui.checkbox("Remember")
    var inputValue = ""
    var changeValue = ""

    remember.onInput = proc(event: DispatchResult): EventOutcome =
      inputValue = $remember.checked()
      false

    remember.onChange = proc(event: DispatchResult): EventOutcome =
      changeValue = $remember.checked()
      false

    discard remember.container.emit(InputEvent(kind: iekClick))

    check remember.checked()
    check inputValue == "true"
    check changeValue == "true"
    check esChecked in ui.tree.nodes[remember.container.nodeId.nodeIndex].states
    check esChecked in ui.tree.nodes[remember.markerNode.nodeId.nodeIndex].states
    check esChecked in ui.tree.nodes[remember.indicatorNode.nodeId.nodeIndex].states

  test "checkbox uses an internal check indicator instead of changing label text":
    let ui = initUiRoot()
    let remember = ui.checkbox("Remember")

    check ui.tree.nodes[remember.indicatorNode.nodeId.nodeIndex].text == "✓"
    check ui.tree.nodes[remember.labelNode.nodeId.nodeIndex].text == "Remember"

    discard remember.container.emit(InputEvent(kind: iekClick))

    check ui.tree.nodes[remember.indicatorNode.nodeId.nodeIndex].text == "✓"
    check ui.tree.nodes[remember.labelNode.nodeId.nodeIndex].text == "Remember"

  test "setChecked updates state without emitting by default":
    let ui = initUiRoot()
    let remember = ui.checkbox("Remember")
    var changed = false

    remember.onChange = proc(event: DispatchResult): EventOutcome =
      changed = true
      false

    remember.setChecked(true)

    check remember.checked()
    check not changed
    check esChecked in ui.tree.nodes[remember.container.nodeId.nodeIndex].states

  test "setChecked can emit input and change":
    let ui = initUiRoot()
    let remember = ui.checkbox("Remember")
    var seen: seq[InputEventKind] = @[]

    remember.onInput = proc(event: DispatchResult): EventOutcome =
      seen.add event.event.kind
      false

    remember.onChange = proc(event: DispatchResult): EventOutcome =
      seen.add event.event.kind
      false

    remember.setChecked(true, emitEvents = true)

    check seen == @[iekInput, iekChange]

  test "keyboard activation toggles through click path":
    let ui = initUiRoot()
    let remember = ui.checkbox("Remember")
    var clicked = 0

    remember.onClick = proc(event: DispatchResult): EventOutcome =
      inc clicked
      false

    discard remember.container.emit(keyDownEvent(" "))
    discard remember.container.emit(keyDownEvent("Enter"))

    check not remember.checked()
    check clicked == 2

  test "disabled checkbox suppresses pointer and keyboard changes":
    let ui = initUiRoot()
    let remember = ui.checkbox(CheckboxParams(label: "Remember", checked: true, disabled: true))
    var changed = false
    var clicked = false

    remember.onChange = proc(event: DispatchResult): EventOutcome =
      changed = true
      false

    remember.onClick = proc(event: DispatchResult): EventOutcome =
      clicked = true
      false

    discard remember.container.emit(InputEvent(kind: iekClick))
    discard remember.container.emit(keyDownEvent(" "))

    check remember.checked()
    check not changed
    check not clicked
    check esDisabled in ui.tree.nodes[remember.container.nodeId.nodeIndex].states

  test "setDisabled toggles disabled state":
    let ui = initUiRoot()
    let remember = ui.checkbox("Remember")

    remember.setDisabled(true)
    check remember.disabled()
    check esDisabled in ui.tree.nodes[remember.container.nodeId.nodeIndex].states

    remember.setDisabled(false)
    check not remember.disabled()
    check esDisabled notin ui.tree.nodes[remember.container.nodeId.nodeIndex].states

  test "preventDefault keeps the checked state unchanged":
    let ui = initUiRoot()
    let remember = ui.checkbox("Remember")

    remember.onClick = proc(event: DispatchResult): EventOutcome =
      preventedEvent()

    let outcome = ui.events.dispatchEvent(ui.tree, DispatchResult(
      target: some(remember.container.nodeId),
      event: clickEvent(vec2(0, 0))
    ))

    check not remember.checked()
    check outcome.preventDefault

  test "setLabel updates visible label":
    let ui = initUiRoot()
    let remember = ui.checkbox("Remember")

    remember.setLabel("Keep signed in")

    check ui.tree.nodes[remember.labelNode.nodeId.nodeIndex].text == "Keep signed in"
