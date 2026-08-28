import std/[options, tables]

import ../../core/[geometry, node]
import ../../input/events
import ../../layout/layout
import ../../runtime/[accessibility, ui_root]

const
  atspiRootPath* = "/org/a11y/atspi/accessible/root"
  atspiNullPath* = "/org/a11y/atspi/null"

type
  AtspiRole* = enum
    atrApplication,
    atrPanel,
    atrPushButton,
    atrCheckBox,
    atrRadioButton,
    atrEntry,
    atrText,
    atrComboBox,
    atrListItem,
    atrSlider,
    atrProgressBar,
    atrList,
    atrPageTabList,
    atrPageTab,
    atrDialog,
    atrImage,
    atrStatic,
    atrLink,
    atrToggleButton,
    atrPasswordText

  AtspiState* = enum
    atsActive,
    atsChecked,
    atsEnabled,
    atsExpanded,
    atsFocusable,
    atsFocused,
    atsSelected,
    atsSensitive,
    atsShowing,
    atsVisible,
    atsInvalid

  AtspiInterface* = enum
    atiAccessible,
    atiAction,
    atiApplication,
    atiComponent,
    atiEditableText,
    atiText,
    atiValue

  AtspiNode* = object
    source*: Option[NodeId]
    objectPath*: string
    parentPath*: string
    childPaths*: seq[string]
    accessibleId*: string
    role*: AtspiRole
    name*: string
    description*: string
    value*: string
    valueNow*: Option[float32]
    valueMin*: Option[float32]
    valueMax*: Option[float32]
    positionInSet*: Option[int]
    setSize*: Option[int]
    states*: set[AtspiState]
    interfaces*: set[AtspiInterface]
    actions*: seq[string]
    bounds*: Option[Rect]

  AtspiSnapshot* = object
    applicationName*: string
    toolkitName*: string
    toolkitVersion*: string
    nodes*: seq[AtspiNode]

  AtspiChangeKind* = enum
    ackAdded,
    ackRemoved,
    ackName,
    ackDescription,
    ackValue,
    ackState,
    ackBounds,
    ackChildren,
    ackSetPosition

  AtspiChange* = object
    kind*: AtspiChangeKind
    objectPath*: string

  AtspiPublishProc* = proc(
    snapshot: AtspiSnapshot;
    changes: seq[AtspiChange]
  ): bool {.closure.}

  AtspiTransport* = object
    publish*: AtspiPublishProc

  AtspiAdapter* = ref object
    transport*: AtspiTransport
    snapshot*: AtspiSnapshot
    published*: bool

proc objectPathFor*(id: NodeId): string =
  "/org/a11y/atspi/accessible/node_" & $id.nodeRawValue()

proc roleFor(role: AccessibleRole): AtspiRole =
  case role
  of arApplication: atrApplication
  of arButton, arDisclosure: atrPushButton
  of arCheckBox: atrCheckBox
  of arRadio: atrRadioButton
  of arTextBox: atrEntry
  of arPasswordText: atrPasswordText
  of arTextArea: atrText
  of arComboBox: atrComboBox
  of arOption, arListItem: atrListItem
  of arSlider: atrSlider
  of arProgressBar: atrProgressBar
  of arListBox: atrList
  of arTabList: atrPageTabList
  of arTab: atrPageTab
  of arDialog: atrDialog
  of arImage: atrImage
  of arStaticText: atrStatic
  of arLink: atrLink
  of arSwitch: atrToggleButton
  of arNone, arGeneric, arGroup: atrPanel

proc actionsFor(role: AccessibleRole): seq[string] =
  case role
  of arButton, arCheckBox, arRadio, arComboBox, arOption, arDisclosure, arSwitch,
      arListItem, arTab, arLink:
    @["activate"]
  else:
    @[]

proc statesFor(node: AccessibleNode): set[AtspiState] =
  if esDisabled notin node.states:
    result.incl atsEnabled
    result.incl atsSensitive
  if esActive in node.states:
    result.incl atsActive
  if esChecked in node.states:
    result.incl atsChecked
  if esOpen in node.states:
    result.incl atsExpanded
  if esSelected in node.states:
    result.incl atsSelected
  if node.focusable:
    result.incl atsFocusable
  if esFocus in node.states:
    result.incl atsFocused
  if esInvalid in node.states:
    result.incl atsInvalid
  if node.bounds.isSome and not node.hidden:
    result.incl atsShowing
    result.incl atsVisible

proc interfacesFor(node: AccessibleNode; actions: openArray[string]): set[AtspiInterface] =
  result = {atiAccessible}
  if node.bounds.isSome:
    result.incl atiComponent
  if actions.len > 0:
    result.incl atiAction
  # Value/Text/EditableText stay unadvertised until their complete AT-SPI
  # method surfaces have consumers. The snapshot may still carry those values.

proc buildAtspiSnapshot*(
    ui: UiRoot;
    layout: LayoutResult;
    applicationName: string;
    toolkitVersion = "0.1.0"
): AtspiSnapshot =
  result.applicationName = applicationName
  result.toolkitName = "CBSS"
  result.toolkitVersion = toolkitVersion
  result.nodes.add AtspiNode(
    source: none(NodeId),
    objectPath: atspiRootPath,
    parentPath: atspiNullPath,
    role: atrApplication,
    name: applicationName,
    states: {atsEnabled, atsSensitive},
    interfaces: {atiAccessible, atiApplication}
  )

  let semanticNodes = ui.accessibilityTree(layout)
  for semantic in semanticNodes:
    let actions = actionsFor(semantic.role)
    let source = ui.tree.nodes[semantic.node.nodeIndex]
    result.nodes.add AtspiNode(
      source: some(semantic.node),
      objectPath: objectPathFor(semantic.node),
      parentPath:
        if semantic.parent.isSome: objectPathFor(semantic.parent.get)
        else: atspiRootPath,
      accessibleId:
        if source.code.len > 0: source.code
        else: source.id,
      role: roleFor(semantic.role),
      name: semantic.name,
      description: semantic.description,
      value: semantic.value,
      valueNow: semantic.valueNow,
      valueMin: semantic.valueMin,
      valueMax: semantic.valueMax,
      positionInSet: semantic.positionInSet,
      setSize: semantic.setSize,
      states: statesFor(semantic),
      interfaces: interfacesFor(semantic, actions),
      actions: actions,
      bounds: semantic.bounds
    )

  var indexByPath = initTable[string, int]()
  for index, node in result.nodes:
    indexByPath[node.objectPath] = index
  for node in result.nodes:
    if node.objectPath == atspiRootPath:
      continue
    if indexByPath.hasKey(node.parentPath):
      result.nodes[indexByPath[node.parentPath]].childPaths.add node.objectPath

proc nodeAt*(snapshot: AtspiSnapshot; objectPath: string): Option[AtspiNode] =
  for node in snapshot.nodes:
    if node.objectPath == objectPath:
      return some(node)
  none(AtspiNode)

proc diffAtspiSnapshots*(previous, current: AtspiSnapshot): seq[AtspiChange] =
  var previousByPath = initTable[string, AtspiNode]()
  var currentByPath = initTable[string, AtspiNode]()
  for node in previous.nodes:
    previousByPath[node.objectPath] = node
  for node in current.nodes:
    currentByPath[node.objectPath] = node

  for path, node in currentByPath:
    if not previousByPath.hasKey(path):
      result.add AtspiChange(kind: ackAdded, objectPath: path)
      continue
    let old = previousByPath[path]
    if old.name != node.name:
      result.add AtspiChange(kind: ackName, objectPath: path)
    if old.description != node.description:
      result.add AtspiChange(kind: ackDescription, objectPath: path)
    if old.value != node.value or old.valueNow != node.valueNow or
        old.valueMin != node.valueMin or old.valueMax != node.valueMax:
      result.add AtspiChange(kind: ackValue, objectPath: path)
    if old.states != node.states:
      result.add AtspiChange(kind: ackState, objectPath: path)
    if old.bounds != node.bounds:
      result.add AtspiChange(kind: ackBounds, objectPath: path)
    if old.childPaths != node.childPaths:
      result.add AtspiChange(kind: ackChildren, objectPath: path)
    if old.positionInSet != node.positionInSet or old.setSize != node.setSize:
      result.add AtspiChange(kind: ackSetPosition, objectPath: path)

  for path in previousByPath.keys:
    if not currentByPath.hasKey(path):
      result.add AtspiChange(kind: ackRemoved, objectPath: path)

proc performAtspiAction*(
    ui: UiRoot;
    snapshot: AtspiSnapshot;
    objectPath: string;
    action = "activate"
): bool =
  let target = snapshot.nodeAt(objectPath)
  if target.isNone or target.get.source.isNone or action notin target.get.actions:
    return false
  if atsEnabled notin target.get.states or
      atsSensitive notin target.get.states or
      atsShowing notin target.get.states or
      atsVisible notin target.get.states:
    return false
  discard ui.events.emit(ui.tree, target.get.source.get, iekClick)
  true

proc initAtspiAdapter*(transport = AtspiTransport()): AtspiAdapter =
  AtspiAdapter(transport: transport)

proc refresh*(
    adapter: AtspiAdapter;
    ui: UiRoot;
    layout: LayoutResult;
    applicationName: string;
    toolkitVersion = "0.1.0"
): bool =
  let next = ui.buildAtspiSnapshot(layout, applicationName, toolkitVersion)
  let changes =
    if adapter.published: diffAtspiSnapshots(adapter.snapshot, next)
    else:
      var initial: seq[AtspiChange]
      for node in next.nodes:
        initial.add AtspiChange(kind: ackAdded, objectPath: node.objectPath)
      initial
  if adapter.transport.publish != nil and
      not adapter.transport.publish(next, changes):
    return false
  adapter.snapshot = next
  adapter.published = true
  true
