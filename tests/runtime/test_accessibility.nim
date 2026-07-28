import std/[options, unittest]

import clay_box_style_system

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
    let input = ui.textInput(TextInputParams(value: "draft"), groups = [])
    let slider = ui.slider(value = 25, min = 0, max = 100, groups = [])
    let semantics = ui.accessibilityTree()

    let buttonNode = semantics.accessibleNodeFor(button.container.nodeId)
    let checkboxNode = semantics.accessibleNodeFor(checkbox.container.nodeId)
    let inputNode = semantics.accessibleNodeFor(input.container.nodeId)
    let sliderNode = semantics.accessibleNodeFor(slider.container.nodeId)

    check buttonNode.isSome
    check buttonNode.get.role == arButton
    check buttonNode.get.name == "Save"
    check checkboxNode.get.role == arCheckBox
    check checkboxNode.get.name == "Remember"
    check inputNode.get.role == arTextBox
    check inputNode.get.value == "draft"
    check sliderNode.get.role == arSlider
    check sliderNode.get.valueNow == some(25.0'f32)
    check sliderNode.get.valueMin == some(0.0'f32)
    check sliderNode.get.valueMax == some(100.0'f32)

  test "semantic values and states follow control updates":
    let ui = initUiRoot()
    let checkbox = ui.checkbox("Remember")
    let disclosure = ui.details("Advanced", "Settings")
    let slider = ui.slider(value = 1, min = 0, max = 10)

    checkbox.setChecked(true)
    checkbox.setDisabled(true)
    disclosure.setOpen(true)
    slider.setValue(7)

    let semantics = ui.accessibilityTree()
    let checkboxNode = semantics.accessibleNodeFor(checkbox.container.nodeId).get
    let disclosureNode = semantics.accessibleNodeFor(disclosure.summaryNode.nodeId).get
    let sliderNode = semantics.accessibleNodeFor(slider.container.nodeId).get

    check checkboxNode.value == "true"
    check esChecked in checkboxNode.states
    check esDisabled in checkboxNode.states
    check not checkboxNode.focusable
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
