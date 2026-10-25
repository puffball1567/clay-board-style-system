import std/options

import ../core/[dirty_domain, node]
import ./drop_indicator
import ./ui_root

proc moveChildForDrop*(
    root: UiRoot;
    parent, source, target: NodeId;
    side: DropInsertionSide
): bool {.discardable.} =
  ## Move a direct child before or after a sibling without replacing nodes.
  ## Applications call this after deciding what an accepted move drop means.
  if root.isNil or source == target or
      not root.tree.isValid(parent) or not root.tree.isValid(source) or
      not root.tree.isValid(target) or
      root.tree.nodes[source.nodeIndex].parent != some(parent) or
      root.tree.nodes[target.nodeIndex].parent != some(parent):
    return false

  let current = root.tree.nodes[parent.nodeIndex].children
  var ordered = newSeqOfCap[NodeId](current.len)
  var foundSource = false
  var foundTarget = false
  for child in current:
    if child == source:
      foundSource = true
      continue
    if child == target:
      foundTarget = true
      if side == disBefore:
        ordered.add source
    ordered.add child
    if child == target and side == disAfter:
      ordered.add source

  if not foundSource or not foundTarget:
    return false

  result = root.tree.reorderChildren(parent, ordered)
  if result:
    root.invalidate(parent, {ddLayout, ddPaint, ddHit})

proc moveChildByStep*(
    root: UiRoot;
    parent, source: NodeId;
    direction: int
): bool {.discardable.} =
  ## Move a direct child one sibling backward (-1) or forward (+1).
  ## A keyboard handler can map its own shortcuts to these two directions.
  if root.isNil or direction notin [-1, 1] or
      not root.tree.isValid(parent) or not root.tree.isValid(source) or
      root.tree.nodes[source.nodeIndex].parent != some(parent):
    return false

  let siblings = root.tree.nodes[parent.nodeIndex].children
  for index, child in siblings:
    if child != source:
      continue
    let neighborIndex = index + direction
    if neighborIndex < 0 or neighborIndex >= siblings.len:
      return false
    return root.moveChildForDrop(
      parent, source, siblings[neighborIndex],
      if direction < 0: disBefore else: disAfter
    )
