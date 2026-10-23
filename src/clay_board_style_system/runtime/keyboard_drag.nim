import std/options

import ../core/node
import ../data/form_data
import ../input/events
import ./accessibility
import ./focus
import ./ui_root

type
  KeyboardDragAnnouncementKind* = enum
    kdaStarted,
    kdaTargetChanged,
    kdaDropped,
    kdaRejected,
    kdaCanceled

  KeyboardDragAnnouncement* = object
    kind*: KeyboardDragAnnouncementKind
    source*: NodeId
    sourceName*: string
    target*: Option[NodeId]
    targetName*: string
    operation*: Option[DragOperation]

  KeyboardDragAnnounceProc* = proc(
    announcement: KeyboardDragAnnouncement
  ) {.closure.}

proc announceDrag(
    ui: UiRoot;
    announce: KeyboardDragAnnounceProc;
    kind: KeyboardDragAnnouncementKind;
    source: NodeId;
    target = none(NodeId);
    operation = none(DragOperation)
) =
  if announce == nil:
    return
  announce(KeyboardDragAnnouncement(
    kind: kind,
    source: source,
    sourceName: ui.tree.resolvedAccessibleName(source),
    target: target,
    targetName:
      if target.isSome: ui.tree.resolvedAccessibleName(target.get) else: "",
    operation: operation
  ))

proc handleKeyboardDragKey*(
    ui: UiRoot;
    state: var InteractionState;
    event: InputEvent;
    source: NodeId;
    operations: set[DragOperation];
    data = none(FormData);
    announce: KeyboardDragAnnounceProc = nil
): bool =
  ## Opt-in keyboard binding for a drag-enabled source. Call before ordinary
  ## key dispatch and skip that dispatch when this returns true. Space starts
  ## a drag from the focused node; Tab moves focus; Enter or Space drops;
  ## Escape cancels. The optional callback carries typed, localization-ready
  ## status; the host sends announcements to its platform accessibility API.
  if event.kind != iekKeyDown or event.key.isNone or
      event.ctrlKey or event.altKey or event.metaKey:
    return false

  let key = event.key.get
  if state.keyboardDragging:
    if state.dragTarget != some(source):
      return false
    case key
    of "Tab":
      let previousTarget = state.dragOverTarget
      let previousOperation = state.dropOperation
      discard ui.moveFocus(state, if event.shiftKey: -1 else: 1)
      discard ui.dispatchEvents(state, state.advanceKeyboardDrag(ui.tree))
      if not state.keyboardDragging:
        ui.announceDrag(announce, kdaCanceled, source)
      elif state.dragOverTarget != previousTarget or
          state.dropOperation != previousOperation:
        ui.announceDrag(announce, kdaTargetChanged, source,
          state.dragOverTarget, state.dropOperation)
      return true
    of "Enter", " ", "Space":
      if event.shiftKey:
        return false
      var target = state.focusedTarget
      let completed = state.finishKeyboardDrag(ui.tree)
      var dropped = false
      var operation = none(DragOperation)
      for dispatch in completed:
        if dispatch.event.kind == iekDrop:
          dropped = true
          target = dispatch.target
          operation = dispatch.dropOperation
      let sourceName = ui.tree.resolvedAccessibleName(source)
      let targetName =
        if target.isSome: ui.tree.resolvedAccessibleName(target.get) else: ""
      discard ui.dispatchEvents(state, completed)
      if announce != nil:
        announce(KeyboardDragAnnouncement(
          kind: if dropped: kdaDropped else: kdaRejected,
          source: source,
          sourceName: sourceName,
          target: target,
          targetName: targetName,
          operation: operation
        ))
      return true
    of "Escape":
      if event.shiftKey:
        return false
      discard ui.dispatchEvents(state, state.cancelKeyboardDrag())
      ui.announceDrag(announce, kdaCanceled, source)
      return true
    else:
      return false

  if key notin [" ", "Space"] or event.shiftKey or
      state.focusedTarget != some(source):
    return false
  let started = state.startKeyboardDrag(
    ui.tree, source, operations, data
  )
  if started.isNone:
    return false
  discard ui.dispatchEvent(started.get)
  if state.keyboardDragging:
    ui.announceDrag(announce, kdaStarted, source)
  true
