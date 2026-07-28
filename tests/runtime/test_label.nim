import std/[options, unittest]

import clay_box_style_system

suite "label element":
  test "label click toggles an associated checkbox":
    let ui = initUiRoot()
    let accept = ui.checkbox("Accept")
    let caption = ui.label("Accept terms", target = some(accept.container))
    var changed = false

    accept.onChange = proc(event: DispatchResult): bool =
      changed = true
      false

    discard caption.container.emit(InputEvent(kind: iekClick))

    check accept.checked()
    check changed

  test "label keyboard activation selects an associated radio":
    let ui = initUiRoot()
    let choices = initRadioSet()
    let small = ui.radio(choices, "Small", "s")
    let large = ui.radio(choices, "Large", "l")
    let caption = ui.label("Large", target = some(large.container()))

    discard caption.container.emit(keyDownEvent(" "))

    check not small.checked()
    check large.checked()

  test "label focuses an associated text input":
    let ui = initUiRoot()
    let name = ui.textInput(TextInputParams(value: ""))
    let caption = ui.label("Name", target = some(name.container))

    discard caption.container.emit(InputEvent(kind: iekClick))

    check esFocus in ui.tree.nodes[name.container.nodeId.nodeIndex].states

  test "label focuses an associated textarea":
    let ui = initUiRoot()
    let bio = ui.textArea(TextAreaParams(value: ""))
    let caption = ui.label("Bio", target = some(bio.container))

    discard caption.container.emit(InputEvent(kind: iekClick))

    check esFocus in ui.tree.nodes[bio.container.nodeId.nodeIndex].states

  test "disabled label does not activate target":
    let ui = initUiRoot()
    let accept = ui.checkbox("Accept")
    let caption = ui.label("Accept terms", target = some(accept.container), disabled = true)

    discard caption.container.emit(InputEvent(kind: iekClick))

    check not accept.checked()
    check esDisabled in ui.tree.nodes[caption.container.nodeId.nodeIndex].states

  test "label target can be changed or cleared":
    let ui = initUiRoot()
    let first = ui.checkbox("First")
    let second = ui.checkbox("Second")
    let caption = ui.label("Choice", target = some(first.container))

    caption.setTarget(second.container)
    discard caption.container.emit(InputEvent(kind: iekClick))

    check not first.checked()
    check second.checked()

    caption.clearTarget()
    discard caption.container.emit(InputEvent(kind: iekClick))

    check second.checked()
