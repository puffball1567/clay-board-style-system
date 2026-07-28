import std/[algorithm, options]

import ../core/node
import ../input/events
import ./ui_root

type
  FocusOrderEntry = object
    node: NodeId
    tabIndex: int

proc compareFocusOrder(a, b: FocusOrderEntry): int {.nimcall.} =
  let aPositive = a.tabIndex > 0
  let bPositive = b.tabIndex > 0
  if aPositive != bPositive:
    return if aPositive: -1 else: 1
  if aPositive:
    result = cmp(a.tabIndex, b.tabIndex)
    if result != 0:
      return
  result = cmp(a.node.nodeIndex, b.node.nodeIndex)

proc focusTargets*(ui: UiRoot): seq[NodeId] =
  var entries: seq[FocusOrderEntry]
  for index in 0 ..< ui.tree.nodes.len:
    let id = NodeId(index)
    if ui.tree.isFocusable(id, forTraversal = true):
      entries.add FocusOrderEntry(node: id, tabIndex: ui.tree.nodes[index].tabIndex)
  entries.sort(compareFocusOrder)
  result = newSeqOfCap[NodeId](entries.len)
  for entry in entries:
    result.add entry.node

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
  ui.tree.clearState(esFocus)
  ui.tree.clearState(esFocusVisible)
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
  if not request.pending:
    return false
  ui.setFocus(state, request.target, focusVisible = true)

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
