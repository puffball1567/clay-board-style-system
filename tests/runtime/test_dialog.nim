import std/[options, unittest]

import clay_board_style_system

suite "dialog component":
  test "dialog initializes closed and can show":
    let ui = initUiRoot()
    let confirm = ui.dialog(title = "Confirm", body = "Continue?")
    var shown = false

    confirm.onShow = proc(event: DispatchResult): EventOutcome =
      shown = true
      false

    check not confirm.isOpen()
    check esDisabled in ui.tree.nodes[confirm.container.nodeId.nodeIndex].states

    check confirm.show()
    check confirm.isOpen()
    check shown
    check confirm.showCount() == 1
    check esActive in ui.tree.nodes[confirm.container.nodeId.nodeIndex].states
    check esDisabled notin ui.tree.nodes[confirm.container.nodeId.nodeIndex].states

  test "close emits onClose and disables dialog":
    let ui = initUiRoot()
    let confirm = ui.dialog(title = "Confirm", body = "Continue?", open = true)
    var closed = false

    confirm.onClose = proc(event: DispatchResult): EventOutcome =
      closed = true
      false

    check confirm.close()
    check not confirm.isOpen()
    check closed
    check confirm.closeCount() == 1
    check esDisabled in ui.tree.nodes[confirm.container.nodeId.nodeIndex].states

  test "cancel emits cancel then close":
    let ui = initUiRoot()
    let confirm = ui.dialog(open = true)
    var seen: seq[InputEventKind] = @[]

    confirm.onCancel = proc(event: DispatchResult): EventOutcome =
      seen.add event.event.kind
      false

    confirm.onClose = proc(event: DispatchResult): EventOutcome =
      seen.add event.event.kind
      false

    check confirm.cancel()
    check seen == @[iekCancel, iekClose]
    check confirm.cancelCount() == 1
    check confirm.closeCount() == 1
    check not confirm.isOpen()

  test "escape cancels open dialog":
    let ui = initUiRoot()
    let confirm = ui.dialog(open = true)
    var canceled = false

    confirm.onCancel = proc(event: DispatchResult): EventOutcome =
      canceled = true
      false

    discard confirm.container.emit(keyDownEvent("Escape"))

    check canceled
    check not confirm.isOpen()

  test "closed dialog suppresses key handlers":
    let ui = initUiRoot()
    let confirm = ui.dialog()
    var keySeen = false

    confirm.container.onKeyDown = proc(event: DispatchResult): EventOutcome =
      keySeen = true
      false

    discard confirm.container.emit(keyDownEvent("Escape"))

    check not keySeen
    check not confirm.isOpen()

  test "setTitle and setBody update visible text":
    let ui = initUiRoot()
    let confirm = ui.dialog(title = "Old", body = "Body")

    confirm.setTitle("New")
    confirm.setBody("Updated")

    check ui.tree.nodes[confirm.titleNode.nodeId.nodeIndex].text == "New"
    check ui.tree.nodes[confirm.bodyNode.nodeId.nodeIndex].text == "Updated"

  test "modal dialog traps traversal and restores the opening focus":
    let ui = initUiRoot()
    let opener = ui.button("Open")
    let confirm = ui.dialog(title = "Confirm", body = "Continue?", modal = true)
    ui.pushParent(confirm.container)
    let cancelButton = ui.button("Cancel")
    let acceptButton = ui.button("Accept")
    ui.popParent()
    var interaction = initInteractionState()

    check ui.setFocus(interaction, some(opener.container.nodeId), focusVisible = true)
    check confirm.show(interaction)
    check ui.tree.focusScopeRoot == some(confirm.container.nodeId)
    check interaction.focusedTarget == some(cancelButton.container.nodeId)
    check ui.focusTargets() == @[
      cancelButton.container.nodeId,
      acceptButton.container.nodeId
    ]

    check ui.moveFocus(interaction, 1)
    check interaction.focusedTarget == some(acceptButton.container.nodeId)
    check ui.moveFocus(interaction, 1)
    check interaction.focusedTarget == some(cancelButton.container.nodeId)
    check not ui.setFocus(interaction, some(opener.container.nodeId))
    check interaction.focusedTarget == some(cancelButton.container.nodeId)

    check confirm.close(interaction)
    check ui.tree.focusScopeRoot.isNone
    check interaction.focusedTarget == some(opener.container.nodeId)

  test "escape requests focus restoration through the host reconciliation path":
    let ui = initUiRoot()
    let opener = ui.button("Open")
    let confirm = ui.dialog(title = "Confirm", body = "Continue?", modal = true)
    ui.pushParent(confirm.container)
    let acceptButton = ui.button("Accept")
    ui.popParent()
    var interaction = initInteractionState()

    discard ui.setFocus(interaction, some(opener.container.nodeId), focusVisible = true)
    check confirm.show(interaction)
    check interaction.focusedTarget == some(acceptButton.container.nodeId)

    discard confirm.container.emit(keyDownEvent("Escape"))
    check ui.focusRequestPending
    check ui.reconcileFocus(interaction)
    check interaction.focusedTarget == some(opener.container.nodeId)
    check not ui.focusRequestPending
    check esFocus in ui.tree.nodes[opener.container.nodeId.nodeIndex].states

  test "repeated show does not overwrite the captured restoration target":
    let ui = initUiRoot()
    let opener = ui.button("Open")
    let confirm = ui.dialog(modal = true)
    ui.pushParent(confirm.container)
    discard ui.button("Accept")
    ui.popParent()
    var interaction = initInteractionState()

    discard ui.setFocus(interaction, some(opener.container.nodeId))
    check confirm.show(interaction)
    check not confirm.show(interaction)
    check confirm.close(interaction)
    check interaction.focusedTarget == some(opener.container.nodeId)

  test "modal dialog accepts an explicit initial focus target":
    let ui = initUiRoot()
    let confirm = ui.dialog(modal = true)
    ui.pushParent(confirm.container)
    let first = ui.button("First")
    let preferred = ui.button("Preferred")
    ui.popParent()
    var interaction = initInteractionState()

    check confirm.show(interaction, initialFocus = some(preferred.container.nodeId))
    check interaction.focusedTarget == some(preferred.container.nodeId)
    check interaction.focusedTarget != some(first.container.nodeId)

  test "modal dialog itself receives focus when it has no interactive child":
    let ui = initUiRoot()
    let confirm = ui.dialog(modal = true)
    var interaction = initInteractionState()

    check confirm.show(interaction)
    check interaction.focusedTarget == some(confirm.container.nodeId)
    check ui.focusTargets().len == 0
    check confirm.cancel(interaction)
    check interaction.focusedTarget.isNone

  test "modal focus scope makes background pointer input inert":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let background = tree.addBox(parent = some(root), id = "background")
    let modal = tree.addBox(parent = some(root), id = "modal")
    let inside = tree.addBox(parent = some(modal), id = "inside")
    tree.setFocusable(background)
    tree.setFocusable(inside)
    tree.setFocusScope(some(modal))
    let regions = @[
      HitRegion(node: root, rect: rect(0, 0, 200, 100), zIndex: 0),
      HitRegion(node: background, rect: rect(0, 0, 80, 40), zIndex: 1),
      HitRegion(node: modal, rect: rect(100, 0, 100, 100), zIndex: 2),
      HitRegion(node: inside, rect: rect(110, 10, 60, 30), zIndex: 3)
    ]
    var interaction = initInteractionState()
    discard interaction.setFocusedTarget(some(inside))
    tree.addState(inside, esFocus)

    let dispatches = interaction.processInput(
      tree,
      regions,
      pointerDownEvent(vec2(20, 20))
    )

    check interaction.focusedTarget == some(inside)
    check interaction.pressedTarget.isNone
    check esActive notin tree.nodes[background.nodeIndex].states
    for dispatch in dispatches:
      check dispatch.target != some(background)

  test "modal scope cancels existing background interaction bookkeeping":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let background = tree.addBox(parent = some(root), id = "background")
    let modal = tree.addBox(parent = some(root), id = "modal")
    let inside = tree.addBox(parent = some(modal), id = "inside")
    tree.setFocusable(background)
    tree.setFocusable(inside)
    var interaction = initInteractionState()
    interaction.hoveredTarget = some(background)
    interaction.pressedTarget = some(background)
    interaction.pointerCaptureTarget = some(background)
    interaction.dragTarget = some(background)
    interaction.dragOverTarget = some(background)
    interaction.pointerDownPosition = some(vec2(4, 4))
    tree.addState(background, esHover)
    tree.addState(background, esActive)
    tree.setFocusScope(some(modal))
    discard interaction.setFocusedTarget(some(inside))

    discard interaction.processInput(tree, @[], pointerMoveEvent(vec2(20, 20)))

    check interaction.hoveredTarget.isNone
    check interaction.pressedTarget.isNone
    check interaction.pointerCaptureTarget.isNone
    check interaction.dragTarget.isNone
    check interaction.dragOverTarget.isNone
    check interaction.pointerDownPosition.isNone
    check esHover notin tree.nodes[background.nodeIndex].states
    check esActive notin tree.nodes[background.nodeIndex].states
