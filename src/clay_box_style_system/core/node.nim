import std/options
import ./geometry

type
  NodeId* = distinct int

  NodeKind* = enum
    nkBox,
    nkText,
    nkImage

  AccessibleRole* = enum
    arNone,
    arApplication,
    arGeneric,
    arButton,
    arCheckBox,
    arRadio,
    arTextBox,
    arTextArea,
    arComboBox,
    arOption,
    arSlider,
    arDisclosure,
    arProgressBar,
    arListBox,
    arListItem,
    arTabList,
    arTab,
    arDialog,
    arGroup,
    arImage,
    arStaticText

  ElementState* = enum
    esHover,
    esActive,
    esFocus,
    esFocusVisible,
    esDisabled,
    esChecked,
    esSelected,
    esOpen

  SemanticInfo* = object
    role*: AccessibleRole
    name*: string
    description*: string
    value*: string
    valueNow*: Option[float32]
    valueMin*: Option[float32]
    valueMax*: Option[float32]
    labelledBy*: Option[NodeId]
    describedBy*: Option[NodeId]
    hidden*: bool

  Attribute* = object
    name*: string
    value*: string

  Node* = object
    kind*: NodeKind
    parent*: Option[NodeId]
    children*: seq[NodeId]
    id*: string
    code*: string
    groups*: seq[string]
    attributes*: seq[Attribute]
    states*: set[ElementState]
    text*: string
    imageSource*: string
    imageWidth*: float32
    imageHeight*: float32
    renderOffset*: Vec2
    textRenderWidth*: Option[float32]
    focusable*: bool
    tabIndex*: int
    focusDelegate*: Option[NodeId]

  Tree* = object
    root*: Option[NodeId]
    nodes*: seq[Node]
    semantics*: seq[SemanticInfo]
    focusScopeRoot*: Option[NodeId]

proc initTree*(): Tree =
  Tree(
    root: none(NodeId),
    nodes: @[],
    semantics: @[],
    focusScopeRoot: none(NodeId)
  )

proc nodeIndex*(id: NodeId): int =
  int(id)

proc `==`*(a, b: NodeId): bool =
  a.nodeIndex == b.nodeIndex

proc addNode*(tree: var Tree; kind: NodeKind; parent = none(NodeId)): NodeId =
  result = NodeId(tree.nodes.len)
  tree.nodes.add Node(
    kind: kind,
    parent: parent,
    children: @[],
    groups: @[],
    attributes: @[],
    tabIndex: -1
  )
  tree.semantics.add SemanticInfo()
  if parent.isSome:
    tree.nodes[parent.get.nodeIndex].children.add result
  elif tree.root.isNone:
    tree.root = some(result)

proc addBox*(tree: var Tree; parent = none(NodeId); id = ""; code = ""; groups: openArray[string] = []): NodeId =
  result = tree.addNode(nkBox, parent)
  tree.nodes[result.nodeIndex].id = id
  tree.nodes[result.nodeIndex].code = code
  for group in groups:
    tree.nodes[result.nodeIndex].groups.add group

proc addText*(tree: var Tree; parent: NodeId; text: string; id = ""; code = ""; groups: openArray[string] = []): NodeId =
  result = tree.addNode(nkText, some(parent))
  tree.nodes[result.nodeIndex].text = text
  tree.nodes[result.nodeIndex].id = id
  tree.nodes[result.nodeIndex].code = code
  for group in groups:
    tree.nodes[result.nodeIndex].groups.add group

proc addImage*(
    tree: var Tree;
    parent: NodeId;
    source: string;
    width = 0.0'f32;
    height = 0.0'f32;
    id = "";
    code = "";
    groups: openArray[string] = []
): NodeId =
  result = tree.addNode(nkImage, some(parent))
  tree.nodes[result.nodeIndex].imageSource = source
  tree.nodes[result.nodeIndex].imageWidth = width
  tree.nodes[result.nodeIndex].imageHeight = height
  tree.nodes[result.nodeIndex].id = id
  tree.nodes[result.nodeIndex].code = code
  for group in groups:
    tree.nodes[result.nodeIndex].groups.add group

proc addAttribute*(tree: var Tree; id: NodeId; name, value: string) =
  tree.nodes[id.nodeIndex].attributes.add Attribute(name: name, value: value)

proc setAttribute*(tree: var Tree; id: NodeId; name, value: string) =
  for attr in tree.nodes[id.nodeIndex].attributes.mitems:
    if attr.name == name:
      if attr.value == value:
        return
      attr.value = value
      return
  tree.addAttribute(id, name, value)

proc addState*(tree: var Tree; id: NodeId; state: ElementState) =
  tree.nodes[id.nodeIndex].states.incl state

proc removeState*(tree: var Tree; id: NodeId; state: ElementState) =
  tree.nodes[id.nodeIndex].states.excl state

proc setState*(tree: var Tree; id: NodeId; state: ElementState; enabled: bool) =
  if enabled:
    tree.addState(id, state)
  else:
    tree.removeState(id, state)

proc clearState*(tree: var Tree; state: ElementState) =
  for node in tree.nodes.mitems:
    node.states.excl state

proc setFocusable*(tree: var Tree; id: NodeId; focusable = true; tabIndex = 0) =
  if id.nodeIndex < 0 or id.nodeIndex >= tree.nodes.len:
    return
  tree.nodes[id.nodeIndex].focusable = focusable
  tree.nodes[id.nodeIndex].tabIndex = if focusable: tabIndex else: -1

proc setFocusDelegate*(tree: var Tree; id: NodeId; target: Option[NodeId]) =
  if id.nodeIndex < 0 or id.nodeIndex >= tree.nodes.len:
    return
  if target.isSome and
      (target.get.nodeIndex < 0 or target.get.nodeIndex >= tree.nodes.len):
    tree.nodes[id.nodeIndex].focusDelegate = none(NodeId)
  else:
    tree.nodes[id.nodeIndex].focusDelegate = target

proc isDescendantOrSelf*(tree: Tree; id, ancestor: NodeId): bool =
  if id.nodeIndex < 0 or id.nodeIndex >= tree.nodes.len or
      ancestor.nodeIndex < 0 or ancestor.nodeIndex >= tree.nodes.len:
    return false
  var current = some(id)
  while current.isSome:
    if current.get == ancestor:
      return true
    current = tree.nodes[current.get.nodeIndex].parent
  false

proc isWithinFocusScope*(tree: Tree; id: NodeId): bool =
  tree.focusScopeRoot.isNone or tree.isDescendantOrSelf(id, tree.focusScopeRoot.get)

proc setFocusScope*(tree: var Tree; root: Option[NodeId]) =
  if root.isSome and
      (root.get.nodeIndex < 0 or root.get.nodeIndex >= tree.nodes.len):
    tree.focusScopeRoot = none(NodeId)
  else:
    tree.focusScopeRoot = root

proc setAccessibleRole*(tree: var Tree; id: NodeId; role: AccessibleRole) =
  if id.nodeIndex >= 0 and id.nodeIndex < tree.semantics.len:
    tree.semantics[id.nodeIndex].role = role

proc setAccessibleName*(tree: var Tree; id: NodeId; name: string) =
  if id.nodeIndex >= 0 and id.nodeIndex < tree.semantics.len:
    tree.semantics[id.nodeIndex].name = name

proc setAccessibleDescription*(tree: var Tree; id: NodeId; description: string) =
  if id.nodeIndex >= 0 and id.nodeIndex < tree.semantics.len:
    tree.semantics[id.nodeIndex].description = description

proc setAccessibleValue*(tree: var Tree; id: NodeId; value: string) =
  if id.nodeIndex >= 0 and id.nodeIndex < tree.semantics.len:
    tree.semantics[id.nodeIndex].value = value

proc setAccessibleRange*(
    tree: var Tree;
    id: NodeId;
    valueNow, valueMin, valueMax: Option[float32]
) =
  if id.nodeIndex < 0 or id.nodeIndex >= tree.semantics.len:
    return
  tree.semantics[id.nodeIndex].valueNow = valueNow
  tree.semantics[id.nodeIndex].valueMin = valueMin
  tree.semantics[id.nodeIndex].valueMax = valueMax

proc setAccessibleLabelledBy*(tree: var Tree; id: NodeId; label: Option[NodeId]) =
  if id.nodeIndex >= 0 and id.nodeIndex < tree.semantics.len:
    tree.semantics[id.nodeIndex].labelledBy = label

proc setAccessibleDescribedBy*(tree: var Tree; id: NodeId; description: Option[NodeId]) =
  if id.nodeIndex >= 0 and id.nodeIndex < tree.semantics.len:
    tree.semantics[id.nodeIndex].describedBy = description

proc setAccessibleHidden*(tree: var Tree; id: NodeId; hidden: bool) =
  if id.nodeIndex >= 0 and id.nodeIndex < tree.semantics.len:
    tree.semantics[id.nodeIndex].hidden = hidden

proc isAccessibleHidden*(tree: Tree; id: NodeId): bool =
  if id.nodeIndex < 0 or id.nodeIndex >= tree.nodes.len:
    return true
  var current = some(id)
  while current.isSome:
    if tree.semantics[current.get.nodeIndex].hidden:
      return true
    current = tree.nodes[current.get.nodeIndex].parent
  false

proc semanticInfo*(tree: Tree; id: NodeId): SemanticInfo =
  if id.nodeIndex >= 0 and id.nodeIndex < tree.semantics.len:
    tree.semantics[id.nodeIndex]
  else:
    SemanticInfo()

proc isFocusable*(tree: Tree; id: NodeId; forTraversal = false): bool =
  if id.nodeIndex < 0 or id.nodeIndex >= tree.nodes.len:
    return false
  if not tree.isWithinFocusScope(id):
    return false
  let target = tree.nodes[id.nodeIndex]
  if not target.focusable or (forTraversal and target.tabIndex < 0):
    return false
  var current = some(id)
  while current.isSome:
    let node = tree.nodes[current.get.nodeIndex]
    if esDisabled in node.states:
      return false
    current = node.parent
  true

proc focusTargetForHit*(tree: Tree; target: Option[NodeId]): Option[NodeId] =
  if target.isSome and not tree.isWithinFocusScope(target.get):
    return none(NodeId)
  var current = target
  while current.isSome:
    let id = current.get
    if id.nodeIndex < 0 or id.nodeIndex >= tree.nodes.len:
      return none(NodeId)
    let node = tree.nodes[id.nodeIndex]
    if esDisabled notin node.states and node.focusDelegate.isSome and
        tree.isFocusable(node.focusDelegate.get):
      return node.focusDelegate
    if tree.isFocusable(id):
      return some(id)
    current = node.parent
  none(NodeId)

proc hasGroup*(node: Node; group: string): bool =
  for item in node.groups:
    if item == group:
      return true
  false

proc attrValue*(node: Node; name: string): Option[string] =
  for attr in node.attributes:
    if attr.name == name:
      return some(attr.value)
  none(string)
