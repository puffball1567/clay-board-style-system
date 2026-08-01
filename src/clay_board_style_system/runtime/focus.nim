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
    let activeId = ui.tree.nodeIdAt(index)
    if activeId.isNone:
      continue
    let id = activeId.get
    if ui.tree.isFocusable(id, forTraversal = true):
      entries.add FocusOrderEntry(node: id, tabIndex: ui.tree.nodes[index].tabIndex)
  entries.sort(compareFocusOrder)
  result = newSeqOfCap[NodeId](entries.len)
  for entry in entries:
    result.add entry.node

proc focusTargets*(ui: UiRoot; within: NodeId): seq[NodeId] =
  if not ui.tree.isValid(within):
    return @[]
  var entries: seq[FocusOrderEntry]
  var pending = @[within]
  while pending.len > 0:
    let id = pending.pop()
    if not ui.tree.isValid(id):
      continue
    if ui.tree.isFocusable(id, forTraversal = true):
      entries.add FocusOrderEntry(
        node: id,
        tabIndex: ui.tree.nodes[id.nodeIndex].tabIndex
      )
    let children = ui.tree.nodes[id.nodeIndex].children
    if children.len > 0:
      for index in countdown(children.high, 0):
        pending.add children[index]
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
