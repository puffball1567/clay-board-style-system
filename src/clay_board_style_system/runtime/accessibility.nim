import std/options

import ../core/geometry
import ../core/node
import ../layout/layout
import ./ui_root

type
  AccessibleNode* = object
    node*: NodeId
    parent*: Option[NodeId]
    role*: AccessibleRole
    name*: string
    description*: string
    value*: string
    valueNow*: Option[float32]
    valueMin*: Option[float32]
    valueMax*: Option[float32]
    positionInSet*: Option[int]
    setSize*: Option[int]
    states*: set[ElementState]
    focusable*: bool
    hidden*: bool
    bounds*: Option[Rect]

proc descendantText(tree: Tree; id: NodeId): string =
  if not tree.isValid(id):
    return ""
  if tree.nodes[id.nodeIndex].kind == nkText:
    result.add tree.nodes[id.nodeIndex].text
  for child in tree.nodes[id.nodeIndex].children:
    result.add tree.descendantText(child)

proc resolvedAccessibleName*(tree: Tree; id: NodeId): string =
  if not tree.isValid(id):
    return ""
  let info = tree.semanticInfo(id)
  if info.name.len > 0:
    return info.name
  if info.labelledBy.isSome:
    return tree.descendantText(info.labelledBy.get)
  ""

proc resolvedAccessibleDescription*(tree: Tree; id: NodeId): string =
  if not tree.isValid(id):
    return ""
  let info = tree.semanticInfo(id)
  if info.description.len > 0:
    return info.description
  if info.describedBy.isSome:
    return tree.descendantText(info.describedBy.get)
  ""

proc nearestAccessibleParent(tree: Tree; id: NodeId): Option[NodeId] =
  if not tree.isValid(id):
    return none(NodeId)
  var current = tree.nodes[id.nodeIndex].parent
  while current.isSome:
    let parent = current.get
    if not tree.isValid(parent):
      return none(NodeId)
    if tree.semanticInfo(parent).role != arNone:
      return some(parent)
    current = tree.nodes[parent.nodeIndex].parent
  none(NodeId)

proc accessibilityTree*(tree: Tree): seq[AccessibleNode] =
  for index, source in tree.nodes:
    let activeId = tree.nodeIdAt(index)
    if activeId.isNone:
      continue
    let id = activeId.get
    if tree.isFlowCollapsed(id):
      continue
    let info = tree.semanticInfo(id)
    if info.role == arNone:
      continue
    result.add AccessibleNode(
      node: id,
      parent: tree.nearestAccessibleParent(id),
      role: info.role,
      name: tree.resolvedAccessibleName(id),
      description: tree.resolvedAccessibleDescription(id),
      value: info.value,
      valueNow: info.valueNow,
      valueMin: info.valueMin,
      valueMax: info.valueMax,
      positionInSet: info.positionInSet,
      setSize: info.setSize,
      states: source.states,
      focusable: tree.isFocusable(id),
      hidden: tree.isAccessibleHidden(id),
      bounds: none(Rect)
    )

proc accessibilityTree*(ui: UiRoot): seq[AccessibleNode] =
  ui.tree.accessibilityTree()

proc accessibilityTree*(ui: UiRoot; layout: LayoutResult): seq[AccessibleNode] =
  result = ui.accessibilityTree()
  var boundsByNode = newSeq[Option[Rect]](ui.tree.nodes.len)
  for box in layout.boxes:
    if box.node.nodeIndex >= 0 and box.node.nodeIndex < boundsByNode.len:
      boundsByNode[box.node.nodeIndex] = some(box.rect)
  for node in result.mitems:
    node.bounds = boundsByNode[node.node.nodeIndex]
