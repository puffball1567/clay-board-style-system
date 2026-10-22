import std/options

import ../core/node
import ../data/form_data
import ../input/events
import ./focus
import ./ui_root

proc handleKeyboardDragKey*(
    ui: UiRoot;
    state: var InteractionState;
    event: InputEvent;
    source: NodeId;
    operations: set[DragOperation];
    data = none(FormData)
): bool =
  ## Opt-in keyboard binding for a drag-enabled source. Call before ordinary
  ## key dispatch and skip that dispatch when this returns true. Space starts
  ## a drag from the focused node; Tab moves focus; Enter or Space drops;
  ## Escape cancels. The host supplies announcements and any other bindings.
  if event.kind != iekKeyDown or event.key.isNone or
      event.ctrlKey or event.altKey or event.metaKey:
    return false

  let key = event.key.get
  if state.keyboardDragging:
    if state.dragTarget != some(source):
      return false
    case key
    of "Tab":
      discard ui.moveFocus(state, if event.shiftKey: -1 else: 1)
      discard ui.dispatchEvents(state.advanceKeyboardDrag(ui.tree))
      return true
    of "Enter", " ", "Space":
      if event.shiftKey:
        return false
      discard ui.dispatchEvents(state.finishKeyboardDrag(ui.tree))
      return true
    of "Escape":
      if event.shiftKey:
        return false
      discard ui.dispatchEvents(state.cancelKeyboardDrag())
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
  true
