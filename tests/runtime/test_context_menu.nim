import std/[options, unittest]

import clay_board_style_system

suite "default context menu":
  test "default context menu requires a mounted menu and target":
    let ui = initUiRoot()
    let root = ui.box()
    let target = ui.box(parent = some(root))

    check not ui.showDefaultContextMenu(some(target.nodeId), vec2(10, 10))

    discard ui.mountDefaultContextMenu(root)

    check not ui.showDefaultContextMenu(none(NodeId), vec2(10, 10))
    check ui.showDefaultContextMenu(some(target.nodeId), vec2(10, 10))
    check ui.defaultContextMenuOpen
    check ui.defaultContextMenuTarget == some(target.nodeId)

  test "default context menu hit testing respects item gaps":
    let ui = initUiRoot()
    let root = ui.box()
    let target = ui.box(parent = some(root))

    discard ui.mountDefaultContextMenu(root)
    check ui.showDefaultContextMenu(some(target.nodeId), vec2(20, 30))

    check ui.defaultContextMenuItemAt(vec2(24, 36)) == some(0)
    check ui.defaultContextMenuItemAt(vec2(24, 62)).isNone
    check ui.defaultContextMenuItemAt(vec2(24, 64)) == some(1)
    check ui.defaultContextMenuItemAt(vec2(500, 500)).isNone

  test "default context menu dispatches copy and closes":
    let ui = initUiRoot()
    let root = ui.box()
    let target = ui.box(parent = some(root))
    var copied = false

    ui.events.onCopy(target.nodeId, proc(event: DispatchResult): EventOutcome =
      copied = true
      true
    )

    discard ui.mountDefaultContextMenu(root)
    check ui.showDefaultContextMenu(some(target.nodeId), vec2(20, 30))

    check ui.activateDefaultContextMenuAt(vec2(24, 64))
    check copied
    check not ui.defaultContextMenuOpen
    check ui.defaultContextMenuTarget.isNone

  test "default context menu dispatches paste provider text":
    let ui = initUiRoot()
    let root = ui.box()
    let target = ui.box(parent = some(root))
    var pasted = ""

    ui.configureClipboardTextProvider(proc(): string = "from-clipboard")
    ui.events.onPaste(target.nodeId, proc(event: DispatchResult): EventOutcome =
      if event.event.text.isSome:
        pasted = event.event.text.get
      true
    )

    discard ui.mountDefaultContextMenu(root)
    check ui.showDefaultContextMenu(some(target.nodeId), vec2(20, 30))

    check ui.activateDefaultContextMenuAt(vec2(24, 92))
    check pasted == "from-clipboard"
    check not ui.defaultContextMenuOpen

  test "disabled default context menu item closes without dispatching":
    let ui = initUiRoot()
    let root = ui.box()
    let target = ui.box(parent = some(root))
    var copied = false

    ui.events.onCopy(target.nodeId, proc(event: DispatchResult): EventOutcome =
      copied = true
      true
    )

    discard ui.mountDefaultContextMenu(root, [
      ContextMenuItem(label: "Copy", action: cmaCopy, disabled: true)
    ])
    check ui.showDefaultContextMenu(some(target.nodeId), vec2(20, 30))

    check ui.activateDefaultContextMenuAt(vec2(24, 36))
    check not copied
    check not ui.defaultContextMenuOpen
    check esDisabled in ui.tree.nodes[ui.defaultContextMenuItemNodes[0].nodeIndex].states

  test "default context menu escape handler closes menu":
    let ui = initUiRoot()
    let root = ui.box()
    let target = ui.box(parent = some(root))
    let menu = ui.mountDefaultContextMenu(root)

    check ui.showDefaultContextMenu(some(target.nodeId), vec2(20, 30))
    discard menu.emit(keyDownEvent("Escape"))

    check not ui.defaultContextMenuOpen
