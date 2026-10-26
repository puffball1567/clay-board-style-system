import std/options

import ../core/focus_order
import ../core/node
import ../input/events
import ./ui_root

proc focusTargets*(ui: UiRoot): seq[NodeId] =
  ui.tree.focusTargets()

proc focusTargets*(ui: UiRoot; within: NodeId): seq[NodeId] =
  ui.tree.focusTargets(within)

proc setFocus*(
    ui: UiRoot;
    state: var InteractionState;
    target: Option[NodeId];
    focusVisible = false
): bool =
  if target.isSome and not ui.tree.isWithinFocusScope(target.get):
    return false
  let next =
    if target.isSome and ui.tree.isFocusable(target.get): target
    else: none(NodeId)

  if state.focusedTarget == next:
    if next.isSome:
      ui.tree.setState(next.get, esFocusVisible, focusVisible)
    return false

  let previous = state.focusedTarget
  if previous.isSome:
    discard ui.events.emit(ui.tree, previous.get, iekBlur)
    if previous.get.nodeIndex >= 0 and
        previous.get.nodeIndex < ui.tree.nodes.len:
      ui.tree.removeState(previous.get, esFocus)
      ui.tree.removeState(previous.get, esFocusVisible)
  discard state.setFocusedTarget(next)
  if next.isSome:
    ui.tree.addState(next.get, esFocus)
    ui.tree.setState(next.get, esFocusVisible, focusVisible)
    discard ui.events.emit(ui.tree, next.get, iekFocus)
  true

proc normalizeFocus*(
    ui: UiRoot;
    state: var InteractionState;
    hitTarget: Option[NodeId]
): bool =
  if hitTarget.isSome and not ui.tree.isWithinFocusScope(hitTarget.get):
    return false
  ui.setFocus(state, ui.tree.focusTargetForHit(hitTarget), focusVisible = false)

proc reconcileFocus*(ui: UiRoot; state: var InteractionState): bool =
  let request = ui.takeFocusRequest()
  if request.pending:
    return ui.setFocus(state, request.target, focusVisible = true)
  if state.focusedTarget.isSome and
      not ui.tree.isFocusable(state.focusedTarget.get):
    return ui.setFocus(state, state.focusedTarget, focusVisible = true)
  false

proc moveFocus*(ui: UiRoot; state: var InteractionState; direction: int): bool =
  let targets = ui.focusTargets()
  if targets.len == 0:
    return false

  var currentIndex = -1
  if state.focusedTarget.isSome:
    for index, target in targets:
      if target == state.focusedTarget.get:
        currentIndex = index
        break

  let nextIndex =
    if direction >= 0:
      if currentIndex < 0: 0 else: (currentIndex + 1) mod targets.len
    else:
      if currentIndex < 0: targets.high else: (currentIndex - 1 + targets.len) mod targets.len
  let next = targets[nextIndex]
  if state.focusedTarget == some(next):
    ui.tree.nodes[next.nodeIndex].states.incl esFocusVisible
    return true
  discard ui.setFocus(state, some(next), focusVisible = true)
  true
