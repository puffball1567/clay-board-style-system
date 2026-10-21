import std/[options, unittest]

import clay_board_style_system

suite "keyboard drag binding":
  test "Space Tab and Enter dispatch a negotiated drop":
    let ui = initUiRoot()
    let root = ui.box()
    let source = ui.box(parent = some(root))
    let target = ui.box(parent = some(root))
    source.setFocusable()
    target.setFocusable()
    var state = initInteractionState()
    var events: seq[InputEventKind]
    var builder = initFormDataBuilder()
    builder.addText("text/plain", "card-42")
    let data = builder.finish()

    source.onDragStart = proc(event: DispatchResult): EventOutcome =
      check event.dragInputMethod == some(dimKeyboard)
      events.add event.event.kind
      handledEvent()
    target.onDragEnter = proc(event: DispatchResult): EventOutcome =
      events.add event.event.kind
      handledEvent()
    target.onDragOver = proc(event: DispatchResult): EventOutcome =
      events.add event.event.kind
      check state.acceptDropDataEntry(
        target.id, dgoMove, "text/plain", fdvText
      )
      handledEvent()
    target.onDrop = proc(event: DispatchResult): EventOutcome =
      events.add event.event.kind
      check event.dropOperation == some(dgoMove)
      check event.dropDataEntry.isSome
      check event.dropDataEntry.get.text == "card-42"
      handledEvent()
    source.onDragEnd = proc(event: DispatchResult): EventOutcome =
      events.add event.event.kind
      check event.dropOperation == some(dgoMove)
      handledEvent()

    check ui.setFocus(state, some(source.id))
    check ui.handleKeyboardDragKey(
      state, keyDownEvent(" "), source.id, {dgoMove}, some(data)
    )
    check state.keyboardDragging
    check ui.handleKeyboardDragKey(
      state, keyDownEvent("Tab"), source.id, {dgoMove}
    )
    check state.focusedTarget == some(target.id)
    check ui.handleKeyboardDragKey(
      state, keyDownEvent("Enter"), source.id, {dgoMove}
    )
    check events == @[
      iekDragStart, iekDragEnter, iekDragOver, iekDrop, iekDragEnd
    ]
    check not state.keyboardDragging
    check state.dragData.isNone

  test "Shift Tab reverses focus and Escape cancels without a drop":
    let ui = initUiRoot()
    let root = ui.box()
    let target = ui.box(parent = some(root))
    let source = ui.box(parent = some(root))
    target.setFocusable()
    source.setFocusable()
    var state = initInteractionState()
    var leaves = 0
    var drops = 0
    var ends = 0
    target.onDragLeave = proc(event: DispatchResult): EventOutcome =
      inc leaves
      handledEvent()
    target.onDrop = proc(event: DispatchResult): EventOutcome =
      inc drops
      handledEvent()
    source.onDragEnd = proc(event: DispatchResult): EventOutcome =
      inc ends
      check event.dropOperation.isNone
      handledEvent()

    check ui.setFocus(state, some(source.id))
    check not ui.handleKeyboardDragKey(
      state, keyDownEvent(" ", ctrlKey = true), source.id, {dgoCopy}
    )
    check not state.keyboardDragging
    check ui.handleKeyboardDragKey(
      state, keyDownEvent("Space"), source.id, {dgoCopy}
    )
    check ui.handleKeyboardDragKey(
      state, keyDownEvent("Tab", shiftKey = true), source.id, {dgoCopy}
    )
    check state.focusedTarget == some(target.id)
    check ui.handleKeyboardDragKey(
      state, keyDownEvent("Escape"), source.id, {dgoCopy}
    )
    check leaves == 1
    check drops == 0
    check ends == 1
    check not state.keyboardDragging
    check not ui.handleKeyboardDragKey(
      state, keyDownEvent("Enter"), source.id, {dgoCopy}
    )

    check not ui.handleKeyboardDragKey(
      state, keyDownEvent(" "), source.id, {dgoCopy}
    )
