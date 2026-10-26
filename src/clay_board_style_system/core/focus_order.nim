import std/[algorithm, options]

import ./node

type
  FocusOrderEntry = object
    node: NodeId
    tabIndex: int
    treeOrder: int

proc compareFocusOrder(a, b: FocusOrderEntry): int {.nimcall.} =
  let aPositive = a.tabIndex > 0
  let bPositive = b.tabIndex > 0
  if aPositive != bPositive:
    return if aPositive: -1 else: 1
  if aPositive:
    result = cmp(a.tabIndex, b.tabIndex)
    if result != 0:
      return
  result = cmp(a.treeOrder, b.treeOrder)

proc appendFocusEntries(
    tree: Tree;
    root: NodeId;
    entries: var seq[FocusOrderEntry]
) =
  var pending = @[root]
  while pending.len > 0:
    let id = pending.pop()
    if not tree.isValid(id):
      continue
    if tree.isFocusable(id, forTraversal = true):
      entries.add FocusOrderEntry(
        node: id,
        tabIndex: tree.nodes[id.nodeIndex].tabIndex,
        treeOrder: entries.len
      )
    let children = tree.nodes[id.nodeIndex].children
    if children.len > 0:
      for index in countdown(children.high, 0):
        pending.add children[index]

proc orderedFocusTargets(entries: var seq[FocusOrderEntry]): seq[NodeId] =
  entries.sort(compareFocusOrder)
  result = newSeqOfCap[NodeId](entries.len)
  for entry in entries:
    result.add entry.node

proc focusTargets*(tree: Tree): seq[NodeId] =
  ## Positive tab indexes precede zero; ties follow the current tree order.
  var entries: seq[FocusOrderEntry]
  for index in 0 ..< tree.nodes.len:
    let activeId = tree.nodeIdAt(index)
    if activeId.isSome and tree.nodes[index].parent.isNone:
      tree.appendFocusEntries(activeId.get, entries)
  entries.orderedFocusTargets()

proc focusTargets*(tree: Tree; within: NodeId): seq[NodeId] =
  if not tree.isValid(within):
    return @[]
  var entries: seq[FocusOrderEntry]
  tree.appendFocusEntries(within, entries)
  entries.orderedFocusTargets()
