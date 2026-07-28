import std/unittest

import clay_board_style_system

suite "fieldset element":
  test "fieldset block supports declarative controls without discard":
    let ui = initUiRoot()

    let contact = ui.fieldset("Contact"):
      let name = ui.textInput(TextInputParams(placeholder: "Name"))
      ui.label("Name", name)

      let message = ui.textArea(TextAreaParams(placeholder: "Message"))
      ui.label("Message", message)

      let subscribe = ui.checkbox("Subscribe")
      ui.label("Subscribe to updates", subscribe)

    check contact.legend() == "Contact"
    check ui.tree.nodes[contact.legendNode.nodeId.nodeIndex].text == "Contact"

  test "fieldset disabled suppresses checkbox radio input and textarea interaction":
    let ui = initUiRoot()
    let choices = initRadioSet()
    var accept: CheckboxHandle
    var choice: RadioHandle
    var name: TextInputHandle
    var message: TextAreaHandle

    let group = ui.fieldset("Preferences"):
      accept = ui.checkbox("Accept")
      choice = ui.radio(choices, "Large", "large")
      name = ui.textInput(TextInputParams())
      message = ui.textArea(TextAreaParams())

    group.setDisabled(true)

    discard accept.container.emit(InputEvent(kind: iekClick))
    discard choice.container().emit(InputEvent(kind: iekClick))
    discard name.container.emit(textInputEvent("A"))
    discard message.container.emit(textInputEvent("B"))

    check not accept.checked()
    check not choice.checked()
    check name.value() == ""
    check message.value() == ""
    check esDisabled in ui.tree.nodes[group.container.nodeId.nodeIndex].states
    check esDisabled in ui.tree.nodes[accept.container.nodeId.nodeIndex].states
    check esDisabled in ui.tree.nodes[name.container.nodeId.nodeIndex].states

    group.setDisabled(false)

    discard accept.container.emit(InputEvent(kind: iekClick))
    discard choice.container().emit(InputEvent(kind: iekClick))
    discard name.container.emit(textInputEvent("A"))
    discard message.container.emit(textInputEvent("B"))

    check accept.checked()
    check choice.checked()
    check name.value() == "A"
    check message.value() == "B"

  test "fieldset disabled preserves controls that were disabled before registration":
    let ui = initUiRoot()
    var locked: CheckboxHandle

    let group = ui.fieldset("Locked"):
      locked = ui.checkbox(CheckboxParams(label: "Locked", disabled: true))

    check locked.disabled()

    group.setDisabled(true)
    group.setDisabled(false)

    check locked.disabled()

  test "fieldset legend can be updated":
    let ui = initUiRoot()
    let group = ui.fieldset("Old")

    group.setLegend("New")

    check group.legend() == "New"
    check ui.tree.nodes[group.legendNode.nodeId.nodeIndex].text == "New"
