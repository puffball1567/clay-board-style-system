import std/[options, unittest]

import clay_board_style_system

suite "inert subtrees":
  test "invalid node IDs are inert and mutations are ignored":
    let ui = initUiRoot()
    let invalid = NodeId(99_999)

    check ui.tree.isInert(invalid)
    ui.tree.setInert(invalid)
    ui.tree.setInert(NodeId(-1), false)
    check ui.tree.nodes.len == 0

  test "inert state is inherited and nested state survives ancestor toggles":
    let ui = initUiRoot()
    let parent = ui.box()
    let child = ui.box(parent = some(parent))
    let grandchild = ui.box(parent = some(child))

    check not parent.inert()
    check not child.inert()
    check not grandchild.inert()

    parent.setInert()
    check parent.inert()
    check child.inert()
    check grandchild.inert()

    child.setInert()
    parent.setInert(false)
    check not parent.inert()
    check child.inert()
    check grandchild.inert()

    child.setInert(false)
    check not child.inert()
    check not grandchild.inert()

  test "inert toggles preserve disabled and explicit accessibility state":
    let ui = initUiRoot()
    let parent = ui.box()
    let child = ui.box(parent = some(parent))
    child.setState(esDisabled, true)
    child.setAccessibleHidden(true)

    parent.setInert()
    parent.setInert(false)

    check esDisabled in ui.tree.nodes[child.id.nodeIndex].states
    check ui.tree.semanticInfo(child.id).hidden
    check ui.tree.isAccessibleHidden(child.id)

  test "tree-aware events neither dispatch nor bubble from inert subtrees":
    let ui = initUiRoot()
    let parent = ui.box()
    let child = ui.box(parent = some(parent))
    var childCalls = 0
    var parentCalls = 0
    child.onClick = proc(event: DispatchResult): bool =
      inc childCalls
      false
    parent.onClick = proc(event: DispatchResult): bool =
      inc parentCalls
      true

    parent.setInert()
    check not child.emit(InputEvent(kind: iekClick))
    check childCalls == 0
    check parentCalls == 0

    parent.setInert(false)
    check child.emit(InputEvent(kind: iekClick))
    check childCalls == 1
    check parentCalls == 1

  test "inert descendants cannot receive direct or delegated focus":
    let ui = initUiRoot()
    let parent = ui.box()
    ui.pushParent(parent)
    let target = ui.button("Target")
    let delegate = ui.box()
    ui.popParent()
    delegate.setFocusDelegate(some(target.container))
    var interaction = initInteractionState()

    parent.setInert()
    check not ui.setFocus(
      interaction,
      some(target.container.nodeId),
      focusVisible = true
    )
    check ui.tree.focusTargetForHit(some(delegate.id)).isNone
    check target.container.nodeId notin ui.focusTargets()

    parent.setInert(false)
    check ui.tree.focusTargetForHit(some(delegate.id)) ==
      some(target.container.nodeId)
    check ui.setFocus(
      interaction,
      some(target.container.nodeId),
      focusVisible = true
    )

  test "accessibility descendants hide and recover with their ancestor":
    let ui = initUiRoot()
    let parent = ui.box()
    ui.pushParent(parent)
    let button = ui.button("Action")
    ui.popParent()

    parent.setInert()
    var hidden = false
    for node in ui.accessibilityTree():
      if node.node == button.container.nodeId:
        hidden = node.hidden
    check hidden

    parent.setInert(false)
    var visible = false
    for node in ui.accessibilityTree():
      if node.node == button.container.nodeId:
        visible = not node.hidden
    check visible

  test "making a focused subtree inert clears focus on reconciliation":
    let ui = initUiRoot()
    let parent = ui.box()
    ui.pushParent(parent)
    let button = ui.button("Action")
    ui.popParent()
    var interaction = initInteractionState()
    check ui.setFocus(
      interaction,
      some(button.container.nodeId),
      focusVisible = true
    )

    parent.setInert()
    check ui.setFocus(
      interaction,
      interaction.focusedTarget,
      focusVisible = true
    )
    check interaction.focusedTarget.isNone
    check esFocus notin ui.tree.nodes[button.container.nodeId.nodeIndex].states
    check esFocusVisible notin ui.tree.nodes[button.container.nodeId.nodeIndex].states
