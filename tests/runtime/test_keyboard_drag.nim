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
    source.setAccessibleName("Card 42")
    target.setAccessibleName("Archive")
    var state = initInteractionState()
    var events: seq[InputEventKind]
    var announcements: seq[KeyboardDragAnnouncement]
    let announce: KeyboardDragAnnounceProc =
      proc(item: KeyboardDragAnnouncement) =
        announcements.add item
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
      state, keyDownEvent(" "), source.id, {dgoMove}, some(data), announce
    )
    check state.keyboardDragging
    check ui.handleKeyboardDragKey(
      state, keyDownEvent("Tab"), source.id, {dgoMove}, announce = announce
    )
    check state.focusedTarget == some(target.id)
    check ui.handleKeyboardDragKey(
      state, keyDownEvent("Enter"), source.id, {dgoMove}, announce = announce
    )
    check events == @[
      iekDragStart, iekDragEnter, iekDragOver, iekDrop, iekDragEnd
    ]
    check not state.keyboardDragging
    check state.dragData.isNone
    check announcements.len == 3
    check announcements[0].kind == kdaStarted
    check announcements[0].sourceName == "Card 42"
    check announcements[1].kind == kdaTargetChanged
    check announcements[1].target == some(target.id)
    check announcements[1].targetName == "Archive"
    check announcements[1].operation == some(dgoMove)
    check announcements[2].kind == kdaDropped
    check announcements[2].targetName == "Archive"
    check announcements[2].operation == some(dgoMove)

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
    var announcements: seq[KeyboardDragAnnouncementKind]
    let announce: KeyboardDragAnnounceProc =
      proc(item: KeyboardDragAnnouncement) =
        announcements.add item.kind
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
      state, keyDownEvent("Space"), source.id, {dgoCopy},
      announce = announce
    )
    check ui.handleKeyboardDragKey(
      state, keyDownEvent("Tab", shiftKey = true), source.id, {dgoCopy},
      announce = announce
    )
    check state.focusedTarget == some(target.id)
    check ui.handleKeyboardDragKey(
      state, keyDownEvent("Escape"), source.id, {dgoCopy},
      announce = announce
    )
    check leaves == 1
    check drops == 0
    check ends == 1
    check not state.keyboardDragging
    check announcements == @[kdaStarted, kdaTargetChanged, kdaCanceled]
    check not ui.handleKeyboardDragKey(
      state, keyDownEvent("Enter"), source.id, {dgoCopy}
    )

    check not ui.handleKeyboardDragKey(
      state, keyDownEvent(" "), source.id, {dgoCopy}
    )

  test "unaccepted target is announced as rejected on completion":
    let ui = initUiRoot()
    let root = ui.box()
    let source = ui.box(parent = some(root))
    let target = ui.box(parent = some(root))
    source.setFocusable()
    target.setFocusable()
    target.setAccessibleName("Unavailable")
    var state = initInteractionState()
    var announcements: seq[KeyboardDragAnnouncement]
    let announce: KeyboardDragAnnounceProc =
      proc(item: KeyboardDragAnnouncement) =
        announcements.add item

    check ui.setFocus(state, some(source.id))
    check ui.handleKeyboardDragKey(
      state, keyDownEvent(" "), source.id, {dgoCopy},
      announce = announce
    )
    check ui.handleKeyboardDragKey(
      state, keyDownEvent("Tab"), source.id, {dgoCopy},
      announce = announce
    )
    check ui.handleKeyboardDragKey(
      state, keyDownEvent("Enter"), source.id, {dgoCopy},
      announce = announce
    )
    check announcements.len == 3
    check announcements[1].kind == kdaTargetChanged
    check announcements[1].operation.isNone
    check announcements[2].kind == kdaRejected
    check announcements[2].target == some(target.id)
    check announcements[2].targetName == "Unavailable"
    check announcements[2].operation.isNone
