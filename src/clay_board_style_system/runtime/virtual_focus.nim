## Focus retention for stable-key virtualized items.
##
## A materialized item may leave the viewport and release its Node IDs. This
## module records the logical item key plus a target locator, then restores
## focus only if no later focus operation has superseded that loss.
import std/options

import ../core/node
import ../input/events
import ./focus
import ./ui_root

type
  VirtualFocusLocator = object
    code: string
    childPath: seq[int]

  PendingVirtualFocus[Key] = object
    key: Key
    locator: VirtualFocusLocator
    focusVisible: bool
    expectedFocusSerial: int

  VirtualFocusMemory*[Key] = ref object
    pending: Option[PendingVirtualFocus[Key]]

proc initVirtualFocusMemory*[Key](): VirtualFocusMemory[Key] =
  VirtualFocusMemory[Key](pending: none(PendingVirtualFocus[Key]))

proc hasPendingFocus*[Key](memory: VirtualFocusMemory[Key]): bool =
  not memory.isNil and memory.pending.isSome

proc pendingKey*[Key](memory: VirtualFocusMemory[Key]): Option[Key] =
  if memory.isNil or memory.pending.isNone:
    return none(Key)
  some(memory.pending.get.key)

proc clear*[Key](memory: VirtualFocusMemory[Key]) =
  if not memory.isNil:
    memory.pending = none(PendingVirtualFocus[Key])

proc relativeChildPath(
    tree: Tree;
    ancestor, target: NodeId
): Option[seq[int]] =
  if not tree.isValid(ancestor) or not tree.isValid(target) or
      not tree.isDescendantOrSelf(target, ancestor):
    return none(seq[int])

  var reversed: seq[int]
  var current = target
  while current != ancestor:
    let parent = tree.nodes[current.nodeIndex].parent
    if parent.isNone or not tree.isValid(parent.get):
      return none(seq[int])
    var position = -1
    for index, child in tree.nodes[parent.get.nodeIndex].children:
      if child == current:
        position = index
        break
    if position < 0:
      return none(seq[int])
    reversed.add position
    current = parent.get

  var path = newSeq[int](reversed.len)
  for index in 0 ..< reversed.len:
    path[reversed.high - index] = reversed[index]
  some(path)

proc resolveChildPath(
    tree: Tree;
    ancestor: NodeId;
    path: openArray[int]
): Option[NodeId] =
  if not tree.isValid(ancestor):
    return none(NodeId)
  var current = ancestor
  for position in path:
    if position < 0 or position >= tree.nodes[current.nodeIndex].children.len:
      return none(NodeId)
    current = tree.nodes[current.nodeIndex].children[position]
    if not tree.isValid(current):
      return none(NodeId)
  some(current)

proc findFocusableCode(
    tree: Tree;
    root: NodeId;
    code: string
): Option[NodeId] =
  if code.len == 0 or not tree.isValid(root):
    return none(NodeId)
  var pending = @[root]
  var match = none(NodeId)
  while pending.len > 0:
    let current = pending.pop()
    if tree.nodes[current.nodeIndex].code == code and tree.isFocusable(current):
      if match.isSome:
        return none(NodeId)
      match = some(current)
    for child in tree.nodes[current.nodeIndex].children:
      if tree.isValid(child):
        pending.add child
  match

proc captureVirtualFocus*[Key](
    memory: VirtualFocusMemory[Key];
    ui: UiRoot;
    interaction: InteractionState;
    key: Key;
    itemRoot: NodeHandle
): bool {.discardable.} =
  ## Capture focus only when it currently belongs to `itemRoot`. The memory is
  ## armed after disposal so its serial represents the blur caused by removal.
  if memory.isNil:
    raise newException(ValueError, "virtual focus memory cannot be nil")
  if ui.isNil or itemRoot.root != ui or not itemRoot.valid or
      interaction.focusedTarget.isNone:
    return false
  let target = interaction.focusedTarget.get
  if not ui.tree.isDescendantOrSelf(target, itemRoot.id):
    return false
  let path = ui.tree.relativeChildPath(itemRoot.id, target)
  if path.isNone:
    return false
  memory.pending = some(PendingVirtualFocus[Key](
    key: key,
    locator: VirtualFocusLocator(
      code: ui.tree.nodes[target.nodeIndex].code,
      childPath: path.get
    ),
    focusVisible: esFocusVisible in ui.tree.nodes[target.nodeIndex].states,
    expectedFocusSerial: -1
  ))
  true

proc armVirtualFocus*[Key](
    memory: VirtualFocusMemory[Key];
    interaction: InteractionState
) =
  ## Call after the captured subtree has been disposed and its blur applied.
  if memory.isNil or memory.pending.isNone:
    return
  var pending = memory.pending.get
  pending.expectedFocusSerial = interaction.focusSerial
  memory.pending = some(pending)

proc cancelSupersededVirtualFocus*[Key](
    memory: VirtualFocusMemory[Key];
    interaction: InteractionState
): bool {.discardable.} =
  if memory.isNil or memory.pending.isNone:
    return false
  let pending = memory.pending.get
  if pending.expectedFocusSerial >= 0 and
      (interaction.focusSerial != pending.expectedFocusSerial or
        interaction.focusedTarget.isSome):
    memory.clear()
    return true
  false

proc restoreVirtualFocus*[Key](
    memory: VirtualFocusMemory[Key];
    ui: UiRoot;
    interaction: var InteractionState;
    key: Key;
    itemRoot: NodeHandle
): bool {.discardable.} =
  ## Restore a matching logical item once. Explicit node `code` wins over the
  ## structural path so internal child reordering does not redirect focus.
  if memory.isNil:
    raise newException(ValueError, "virtual focus memory cannot be nil")
  discard memory.cancelSupersededVirtualFocus(interaction)
  if memory.pending.isNone or memory.pending.get.key != key:
    return false
  let pending = memory.pending.get
  memory.clear()
  if pending.expectedFocusSerial < 0 or ui.isNil or itemRoot.root != ui or
      not itemRoot.valid or interaction.focusedTarget.isSome:
    return false

  let target =
    if pending.locator.code.len > 0:
      ui.tree.findFocusableCode(itemRoot.id, pending.locator.code)
    else:
      ui.tree.resolveChildPath(itemRoot.id, pending.locator.childPath)
  if target.isNone or not ui.tree.isFocusable(target.get):
    return false
  ui.setFocus(interaction, target, pending.focusVisible)
