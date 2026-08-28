import std/[options, unittest]

import clay_board_style_system

proc accessibleNodeFor(nodes: openArray[AccessibleNode]; id: NodeId): Option[AccessibleNode] =
  for node in nodes:
    if node.node == id:
      return some(node)
  none(AccessibleNode)

suite "accessibility semantics":
  test "standard controls expose typed roles without ids or style groups":
    let ui = initUiRoot()
    let button = ui.button("Save", groups = [])
    let checkbox = ui.checkbox("Remember", groups = [])
    let switchControl = ui.switch("Live updates", groups = [])
    let input = ui.textInput(TextInputParams(value: "draft"), groups = [])
    let slider = ui.slider(value = 25, min = 0, max = 100, groups = [])
    let semantics = ui.accessibilityTree()

    let buttonNode = semantics.accessibleNodeFor(button.container.nodeId)
    let checkboxNode = semantics.accessibleNodeFor(checkbox.container.nodeId)
    let switchNode = semantics.accessibleNodeFor(switchControl.container.nodeId)
    let inputNode = semantics.accessibleNodeFor(input.container.nodeId)
    let sliderNode = semantics.accessibleNodeFor(slider.container.nodeId)

    check buttonNode.isSome
    check buttonNode.get.role == arButton
    check buttonNode.get.name == "Save"
    check checkboxNode.get.role == arCheckBox
    check checkboxNode.get.name == "Remember"
    check switchNode.get.role == arSwitch
    check switchNode.get.name == "Live updates"
    check switchNode.get.value == "false"
    check inputNode.get.role == arTextBox
    check inputNode.get.value == "draft"
    check sliderNode.get.role == arSlider
    check sliderNode.get.valueNow == some(25.0'f32)
    check sliderNode.get.valueMin == some(0.0'f32)
    check sliderNode.get.valueMax == some(100.0'f32)

  test "password inputs expose protected semantics without plaintext values":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(
      value: "secret",
      inputType: TextInputType.password
    ))

    let semantic = ui.accessibilityTree()
      .accessibleNodeFor(input.container.nodeId).get
    check semantic.role == arPasswordText
    check semantic.value == "******"
    check ui.tree.nodes[input.container.nodeId.nodeIndex].attrValue("value") ==
      some("secret")

  test "semantic values and states follow control updates":
    let ui = initUiRoot()
    let checkbox = ui.checkbox("Remember")
    let switchControl = ui.switch("Live updates")
    let disclosure = ui.details("Advanced", "Settings")
    let slider = ui.slider(value = 1, min = 0, max = 10)

    checkbox.setChecked(true)
    checkbox.setDisabled(true)
    switchControl.setChecked(true)
    disclosure.setOpen(true)
    slider.setValue(7)

    let semantics = ui.accessibilityTree()
    let checkboxNode = semantics.accessibleNodeFor(checkbox.container.nodeId).get
    let switchNode = semantics.accessibleNodeFor(switchControl.container.nodeId).get
    let disclosureNode = semantics.accessibleNodeFor(disclosure.summaryNode.nodeId).get
    let sliderNode = semantics.accessibleNodeFor(slider.container.nodeId).get

    check checkboxNode.value == "true"
    check esChecked in checkboxNode.states
    check esDisabled in checkboxNode.states
    check not checkboxNode.focusable
    check switchNode.value == "true"
    check esChecked in switchNode.states
    check disclosureNode.role == arDisclosure
    check disclosureNode.value == "expanded"
    check esOpen in disclosureNode.states
    check sliderNode.valueNow == some(7.0'f32)

  test "label relations resolve names and follow later label text changes":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: ""))
    let caption = ui.label("Account name", target = some(input.container))

    check ui.tree.resolvedAccessibleName(input.container.nodeId) == "Account name"
    caption.setText("Display name")
    check ui.tree.resolvedAccessibleName(input.container.nodeId) == "Display name"

    caption.clearTarget()
    check ui.tree.resolvedAccessibleName(input.container.nodeId) == ""

  test "explicit semantic metadata takes precedence over relations":
    let ui = initUiRoot()
    let control = ui.box()
    control.setFocusable()
    control.setAccessibleRole(arButton)
    control.setAccessibleName("Explicit name")
    control.setAccessibleDescription("Explicit description")
    let label = ui.box()
    discard ui.text(label, "Related label")
    control.setAccessibleLabelledBy(some(label))

    let semantic = ui.accessibilityTree().accessibleNodeFor(control.nodeId).get
    check semantic.name == "Explicit name"
    check semantic.description == "Explicit description"

  test "logical set positions are one-based and preserve unknown fields":
    let ui = initUiRoot()
    let item = ui.box()
    item.setAccessibleRole(arListItem)

    item.setAccessibleSetPosition(some(501), some(100_000))
    let semantic = ui.accessibilityTree().accessibleNodeFor(item.nodeId).get
    check semantic.positionInSet == some(501)
    check semantic.setSize == some(100_000)

    item.setAccessibleSetPosition(none(int), some(100_000))
    let sizeOnly = ui.accessibilityTree().accessibleNodeFor(item.nodeId).get
    check sizeOnly.positionInSet.isNone
    check sizeOnly.setSize == some(100_000)

    item.setAccessibleSetPosition(none(int), none(int))
    let cleared = ui.accessibilityTree().accessibleNodeFor(item.nodeId).get
    check cleared.positionInSet.isNone
    check cleared.setSize.isNone

  test "invalid logical set positions fail without changing prior semantics":
    let ui = initUiRoot()
    let item = ui.box()
    item.setAccessibleRole(arListItem)
    item.setAccessibleSetPosition(some(2), some(5))

    expect ValueError:
      item.setAccessibleSetPosition(some(0), some(5))
    expect ValueError:
      item.setAccessibleSetPosition(some(-1), some(5))
    expect ValueError:
      item.setAccessibleSetPosition(some(6), some(5))
    expect ValueError:
      item.setAccessibleSetPosition(none(int), some(-1))

    let semantic = ui.accessibilityTree().accessibleNodeFor(item.nodeId).get
    check semantic.positionInSet == some(2)
    check semantic.setSize == some(5)

  test "semantic parent skips presentational nodes":
    let ui = initUiRoot()
    let dialog = ui.dialog("Confirm", "Proceed?", open = true)
    let nestedPresentation = ui.box(parent = some(dialog.container))
    let button = ui.button("OK")
    ui.tree.nodes[button.container.nodeId.nodeIndex].parent = some(nestedPresentation.nodeId)
    ui.tree.nodes[nestedPresentation.nodeId.nodeIndex].children.add button.container.nodeId

    let semantic = ui.accessibilityTree().accessibleNodeFor(button.container.nodeId).get
    check semantic.parent == some(dialog.container.nodeId)

  test "accessibility hidden state is inherited and follows dialog visibility":
    let ui = initUiRoot()
    let dialog = ui.dialog("Confirm", "Continue?")
    ui.pushParent(dialog.container)
    let accept = ui.button("Accept")
    ui.popParent()

    var semantics = ui.accessibilityTree()
    check semantics.accessibleNodeFor(dialog.container.nodeId).get.hidden
    check semantics.accessibleNodeFor(accept.container.nodeId).get.hidden

    check dialog.show()
    semantics = ui.accessibilityTree()
    check not semantics.accessibleNodeFor(dialog.container.nodeId).get.hidden
    check not semantics.accessibleNodeFor(accept.container.nodeId).get.hidden

  test "invalid controls expose state alongside an author-owned error description":
    let ui = initUiRoot()
    let input = ui.textInput(
      "",
      validationRules[string]().required("Username is required"),
      reportOn = ValidationReport.onSubmit
    )
    let error = ui.box()
    discard ui.text(error, "Username is required")
    input.container.setAccessibleDescribedBy(some(error))

    let initial = ui.accessibilityTree()
      .accessibleNodeFor(input.container.nodeId).get
    check esInvalid notin initial.states
    check not input.reportValidity()
    let semantic = ui.accessibilityTree().accessibleNodeFor(input.container.nodeId).get
    check esInvalid in semantic.states
    check semantic.description == "Username is required"

    input.setDisabled(true)
    let disabledSemantic = ui.accessibilityTree()
      .accessibleNodeFor(input.container.nodeId).get
    check esDisabled in disabledSemantic.states
    check esInvalid notin disabledSemantic.states
