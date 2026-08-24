import std/[hashes, options, sets]
import ./geometry

const
  nodeIndexBits = 20
  nodeIndexMask = (1'u32 shl nodeIndexBits) - 1'u32
  nodeGenerationMask = (1'u32 shl (32 - nodeIndexBits)) - 1'u32
  maxReusableNodeGeneration = nodeGenerationMask - 1'u32

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
    arStaticText,
    arLink,
    arSwitch,
    arPasswordText

  ElementState* = enum
    esHover,
    esActive,
    esFocus,
    esFocusVisible,
    esDisabled,
    esChecked,
    esSelected,
    esOpen,
    esInvalid

  SemanticInfo* = object
    role*: AccessibleRole
    name*: string
    description*: string
    value*: string
    valueNow*: Option[float32]
    valueMin*: Option[float32]
    valueMax*: Option[float32]
    positionInSet*: Option[int]
    setSize*: Option[int]
    labelledBy*: Option[NodeId]
    describedBy*: Option[NodeId]
    hidden*: bool

  Attribute* = object
    name*: string
    value*: string

  Node* = object
    alive*: bool
    generation*: uint16
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
    renderSurfaceId*: Option[uint64]
    renderOffset*: Vec2
    textRenderWidth*: Option[float32]
    focusable*: bool
    tabIndex*: int
    focusDelegate*: Option[NodeId]
    inert*: bool
    flowCollapsed*: bool

  Tree* = object
    root*: Option[NodeId]
    nodes*: seq[Node]
    semantics*: seq[SemanticInfo]
    focusScopeRoot*: Option[NodeId]
    freeNodeIndices: seq[int]

proc initTree*(): Tree =
  Tree(
    root: none(NodeId),
    nodes: @[],
    semantics: @[],
    focusScopeRoot: none(NodeId),
    freeNodeIndices: @[]
  )

proc nodeRawValue*(id: NodeId): uint32 =
  cast[uint32](int(id))

proc nodeIndex*(id: NodeId): int =
  int(id.nodeRawValue() and nodeIndexMask)

proc nodeGeneration*(id: NodeId): uint32 =
  (id.nodeRawValue() shr nodeIndexBits) and nodeGenerationMask

proc makeNodeId(index: int; generation: uint32): NodeId =
  NodeId(int(
    ((generation and nodeGenerationMask) shl nodeIndexBits) or
      (uint32(index) and nodeIndexMask)
  ))

proc `==`*(a, b: NodeId): bool =
  a.nodeRawValue() == b.nodeRawValue()

proc hash*(id: NodeId): Hash =
  hash(id.nodeRawValue())

proc isValid*(tree: Tree; id: NodeId): bool =
  let index = id.nodeIndex
  index >= 0 and index < tree.nodes.len and
    tree.nodes[index].alive and
    uint32(tree.nodes[index].generation) == id.nodeGeneration()

proc nodeIdAt*(tree: Tree; index: int): Option[NodeId] =
  if index < 0 or index >= tree.nodes.len or not tree.nodes[index].alive:
    return none(NodeId)
  some(makeNodeId(index, uint32(tree.nodes[index].generation)))

proc activeNodeCount*(tree: Tree): int =
  for node in tree.nodes:
    if node.alive:
      inc result

proc addNode*(tree: var Tree; kind: NodeKind; parent = none(NodeId)): NodeId =
  if parent.isSome and not tree.isValid(parent.get):
    raise newException(ValueError, "parent node is not active")

  var index: int
  var generation: uint32
  if tree.freeNodeIndices.len > 0:
    index = tree.freeNodeIndices.pop()
    generation = uint32(tree.nodes[index].generation)
  else:
    index = tree.nodes.len
    if uint32(index) > nodeIndexMask:
      raise newException(ValueError, "node arena capacity exceeded")
    generation = 0
    tree.nodes.add Node()
    tree.semantics.add SemanticInfo()

  result = makeNodeId(index, generation)
  tree.nodes[index] = Node(
    alive: true,
    generation: uint16(generation),
    kind: kind,
    parent: parent,
    children: @[],
    groups: @[],
    attributes: @[],
    tabIndex: -1
  )
  tree.semantics[index] = SemanticInfo()
  if parent.isSome:
    tree.nodes[parent.get.nodeIndex].children.add result
  elif tree.root.isNone:
    tree.root = some(result)

proc disposeSubtree*(tree: var Tree; root: NodeId): seq[NodeId] =
  if not tree.isValid(root):
    return @[]

  var pending = @[root]
  var removed = initHashSet[NodeId]()
  while pending.len > 0:
    let id = pending.pop()
    if not tree.isValid(id) or id in removed:
      continue
    removed.incl id
    result.add id
    for child in tree.nodes[id.nodeIndex].children:
      pending.add child

  let parent = tree.nodes[root.nodeIndex].parent
  if parent.isSome and tree.isValid(parent.get):
    let parentIndex = parent.get.nodeIndex
    for index, child in tree.nodes[parentIndex].children:
      if child == root:
        tree.nodes[parentIndex].children.delete(index)
        break

  if tree.root.isSome and tree.root.get in removed:
    tree.root = none(NodeId)
  if tree.focusScopeRoot.isSome and tree.focusScopeRoot.get in removed:
    tree.focusScopeRoot = none(NodeId)

  for index in 0 ..< tree.nodes.len:
    if not tree.nodes[index].alive:
      continue
    let id = tree.nodeIdAt(index).get
    if id in removed:
      continue
    if tree.nodes[index].focusDelegate.isSome and
        tree.nodes[index].focusDelegate.get in removed:
      tree.nodes[index].focusDelegate = none(NodeId)
    if tree.semantics[index].labelledBy.isSome and
        tree.semantics[index].labelledBy.get in removed:
      tree.semantics[index].labelledBy = none(NodeId)
    if tree.semantics[index].describedBy.isSome and
        tree.semantics[index].describedBy.get in removed:
      tree.semantics[index].describedBy = none(NodeId)

  for id in result:
    let index = id.nodeIndex
    let generation = uint32(tree.nodes[index].generation)
    let nextGeneration = min(nodeGenerationMask, generation + 1'u32)
    tree.nodes[index] = Node(
      alive: false,
      generation: uint16(nextGeneration),
      children: @[],
      groups: @[],
      attributes: @[],
      tabIndex: -1
    )
    tree.semantics[index] = SemanticInfo()
    if generation < maxReusableNodeGeneration:
      tree.freeNodeIndices.add index

  if tree.root.isNone:
    for index in 0 ..< tree.nodes.len:
      if tree.nodes[index].alive and tree.nodes[index].parent.isNone:
        tree.root = tree.nodeIdAt(index)
        break

proc reorderChildren*(
    tree: var Tree;
    parent: NodeId;
    ordered: openArray[NodeId]
): bool {.discardable.} =
  ## Reorder every direct child of `parent` without changing node identity.
  ## The complete child set is required so callers cannot accidentally detach
  ## nodes or move a node across parents while changing paint/focus order.
  if not tree.isValid(parent):
    raise newException(ValueError, "child-order parent is not active")
  let current = tree.nodes[parent.nodeIndex].children
  if ordered.len != current.len:
    raise newException(ValueError, "child order must contain every direct child exactly once")

  var expected = initHashSet[NodeId]()
  for child in current:
    if not tree.isValid(child) or tree.nodes[child.nodeIndex].parent != some(parent):
      raise newException(ValueError, "parent contains an invalid direct child")
    if child in expected:
      raise newException(ValueError, "parent contains a duplicate direct child")
    expected.incl child

  var supplied = initHashSet[NodeId]()
  var changed = false
  for index, child in ordered:
    if child notin expected or child in supplied:
      raise newException(ValueError, "child order must contain every direct child exactly once")
    supplied.incl child
    if current[index] != child:
      changed = true

  if changed:
    tree.nodes[parent.nodeIndex].children = @ordered
  changed

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

proc addRenderSurfaceBox*(
    tree: var Tree;
    surfaceId: uint64;
    parent = none(NodeId);
    id = "";
    code = "";
    groups: openArray[string] = []
): NodeId =
  if surfaceId == 0:
    raise newException(ValueError, "render surface identifier must not be zero")
  result = tree.addBox(parent = parent, id = id, code = code, groups = groups)
  tree.nodes[result.nodeIndex].renderSurfaceId = some(surfaceId)

proc addAttribute*(tree: var Tree; id: NodeId; name, value: string) =
  if not tree.isValid(id):
    return
  tree.nodes[id.nodeIndex].attributes.add Attribute(name: name, value: value)

proc setAttribute*(tree: var Tree; id: NodeId; name, value: string) =
  if not tree.isValid(id):
    return
  for attr in tree.nodes[id.nodeIndex].attributes.mitems:
    if attr.name == name:
      if attr.value == value:
        return
      attr.value = value
      return
  tree.addAttribute(id, name, value)

proc addState*(tree: var Tree; id: NodeId; state: ElementState) =
  if not tree.isValid(id):
    return
  tree.nodes[id.nodeIndex].states.incl state

proc removeState*(tree: var Tree; id: NodeId; state: ElementState) =
  if not tree.isValid(id):
    return
  tree.nodes[id.nodeIndex].states.excl state

proc setState*(tree: var Tree; id: NodeId; state: ElementState; enabled: bool) =
  if enabled:
    tree.addState(id, state)
  else:
    tree.removeState(id, state)

proc clearState*(tree: var Tree; state: ElementState) =
  for node in tree.nodes.mitems:
    if node.alive:
      node.states.excl state

proc setFocusable*(tree: var Tree; id: NodeId; focusable = true; tabIndex = 0) =
  if not tree.isValid(id):
    return
  tree.nodes[id.nodeIndex].focusable = focusable
  tree.nodes[id.nodeIndex].tabIndex = if focusable: tabIndex else: -1

proc setFocusDelegate*(tree: var Tree; id: NodeId; target: Option[NodeId]) =
  if not tree.isValid(id):
    return
  if target.isSome and not tree.isValid(target.get):
    tree.nodes[id.nodeIndex].focusDelegate = none(NodeId)
  else:
    tree.nodes[id.nodeIndex].focusDelegate = target

proc setInert*(tree: var Tree; id: NodeId; inert = true) =
  if not tree.isValid(id):
    return
  tree.nodes[id.nodeIndex].inert = inert

proc setFlowCollapsed*(tree: var Tree; id: NodeId; collapsed = true) =
  ## A collapsed flow root stays mounted at its stable sibling position while
  ## contributing nothing to layout, paint, hit testing, focus, or semantics.
  if not tree.isValid(id):
    return
  tree.nodes[id.nodeIndex].flowCollapsed = collapsed

proc isFlowCollapsed*(tree: Tree; id: NodeId): bool =
  if not tree.isValid(id):
    return true
  var current = some(id)
  while current.isSome:
    if tree.nodes[current.get.nodeIndex].flowCollapsed:
      return true
    current = tree.nodes[current.get.nodeIndex].parent
  false

proc isInert*(tree: Tree; id: NodeId): bool =
  if not tree.isValid(id):
    return true
  var current = some(id)
  while current.isSome:
    if tree.nodes[current.get.nodeIndex].inert or
        tree.nodes[current.get.nodeIndex].flowCollapsed:
      return true
    current = tree.nodes[current.get.nodeIndex].parent
  false

proc isDescendantOrSelf*(tree: Tree; id, ancestor: NodeId): bool =
  if not tree.isValid(id) or not tree.isValid(ancestor):
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
  if root.isSome and not tree.isValid(root.get):
    tree.focusScopeRoot = none(NodeId)
  else:
    tree.focusScopeRoot = root

proc setAccessibleRole*(tree: var Tree; id: NodeId; role: AccessibleRole) =
  if tree.isValid(id):
    tree.semantics[id.nodeIndex].role = role

proc setAccessibleName*(tree: var Tree; id: NodeId; name: string) =
  if tree.isValid(id):
    tree.semantics[id.nodeIndex].name = name

proc setAccessibleDescription*(tree: var Tree; id: NodeId; description: string) =
  if tree.isValid(id):
    tree.semantics[id.nodeIndex].description = description

proc setAccessibleValue*(tree: var Tree; id: NodeId; value: string) =
  if tree.isValid(id):
    tree.semantics[id.nodeIndex].value = value

proc setAccessibleRange*(
    tree: var Tree;
    id: NodeId;
    valueNow, valueMin, valueMax: Option[float32]
) =
  if not tree.isValid(id):
    return
  tree.semantics[id.nodeIndex].valueNow = valueNow
  tree.semantics[id.nodeIndex].valueMin = valueMin
  tree.semantics[id.nodeIndex].valueMax = valueMax

proc setAccessibleSetPosition*(
    tree: var Tree;
    id: NodeId;
    positionInSet, setSize: Option[int]
) =
  ## Describe one semantic item within a logical set without materializing the
  ## complete set. Positions are one-based, matching platform accessibility
  ## APIs rather than zero-based application indices.
  if not tree.isValid(id):
    return
  if positionInSet.isSome and positionInSet.get <= 0:
    raise newException(ValueError, "accessible position in set must be positive")
  if setSize.isSome and setSize.get < 0:
    raise newException(ValueError, "accessible set size cannot be negative")
  if positionInSet.isSome and setSize.isSome and
      positionInSet.get > setSize.get:
    raise newException(
      ValueError,
      "accessible position in set cannot exceed the set size"
    )
  tree.semantics[id.nodeIndex].positionInSet = positionInSet
  tree.semantics[id.nodeIndex].setSize = setSize

proc setAccessibleLabelledBy*(tree: var Tree; id: NodeId; label: Option[NodeId]) =
  if tree.isValid(id):
    tree.semantics[id.nodeIndex].labelledBy =
      if label.isSome and tree.isValid(label.get): label
      else: none(NodeId)

proc setAccessibleDescribedBy*(tree: var Tree; id: NodeId; description: Option[NodeId]) =
  if tree.isValid(id):
    tree.semantics[id.nodeIndex].describedBy =
      if description.isSome and tree.isValid(description.get): description
      else: none(NodeId)

proc setAccessibleHidden*(tree: var Tree; id: NodeId; hidden: bool) =
  if tree.isValid(id):
    tree.semantics[id.nodeIndex].hidden = hidden

proc isAccessibleHidden*(tree: Tree; id: NodeId): bool =
  if not tree.isValid(id):
    return true
  var current = some(id)
  while current.isSome:
    if tree.nodes[current.get.nodeIndex].inert or
        tree.nodes[current.get.nodeIndex].flowCollapsed or
        tree.semantics[current.get.nodeIndex].hidden:
      return true
    current = tree.nodes[current.get.nodeIndex].parent
  false

proc semanticInfo*(tree: Tree; id: NodeId): SemanticInfo =
  if tree.isValid(id):
    tree.semantics[id.nodeIndex]
  else:
    SemanticInfo()

proc isFocusable*(tree: Tree; id: NodeId; forTraversal = false): bool =
  if not tree.isValid(id):
    return false
  if not tree.isWithinFocusScope(id):
    return false
  if tree.isInert(id):
    return false
  if not tree.nodes[id.nodeIndex].focusable or
      (forTraversal and tree.nodes[id.nodeIndex].tabIndex < 0):
    return false
  var current = some(id)
  while current.isSome:
    let index = current.get.nodeIndex
    if esDisabled in tree.nodes[index].states:
      return false
    current = tree.nodes[index].parent
  true

proc focusTargetForHit*(tree: Tree; target: Option[NodeId]): Option[NodeId] =
  if target.isSome and not tree.isWithinFocusScope(target.get):
    return none(NodeId)
  var current = target
  while current.isSome:
    let id = current.get
    if not tree.isValid(id):
      return none(NodeId)
    let delegate = tree.nodes[id.nodeIndex].focusDelegate
    if esDisabled notin tree.nodes[id.nodeIndex].states and
        delegate.isSome and tree.isFocusable(delegate.get):
      return delegate
    if tree.isFocusable(id):
      return some(id)
    current = tree.nodes[id.nodeIndex].parent
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
