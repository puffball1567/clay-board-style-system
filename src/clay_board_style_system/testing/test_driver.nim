import std/[json, math, options, os, strutils]

import ../core/[computed_style, diagnostics, geometry, node, style_resolver]
import ../generated/default_properties
import ../hit/hit_test
import ../input/events
import ../layout/layout
import ../layout/scroll_state
import ../paint/[paint, paint_command, path_geometry]
import ../runtime/[focus, frame_scheduler, text_focus, ui_root]

type
  CbssQueryKind* = enum
    cqNode,
    cqId,
    cqCode,
    cqGroup,
    cqText,
    cqTextContains,
    cqPlaceholder,
    cqValue,
    cqAttribute

  CbssQuery* = object
    case kind*: CbssQueryKind
    of cqNode:
      node*: NodeId
    of cqId, cqCode, cqGroup, cqText, cqTextContains, cqPlaceholder, cqValue:
      value*: string
    of cqAttribute:
      attrName*: string
      attrValue*: string

  CbssTestDriver* = ref object
    ui*: UiRoot
    viewport*: Size
    input*: InteractionState
    clipboard*: string
    diagnostics*: Diagnostics
    styles*: ResolvedTree
    layout*: LayoutResult
    hitRegions*: seq[HitRegion]
    paintCommands*: seq[PaintCommand]
    lastDispatches*: seq[DispatchResult]
    actionLog*: seq[string]
    nowSeconds*: float64
    scheduler*: FrameScheduler

  CbssScope* = object
    driver*: CbssTestDriver
    parent*: CbssQuery

  CbssSnapshotDiff* = object
    matches*: bool
    expectedLine*: string
    actualLine*: string
    line*: int
    message*: string

  CbssCheckResult* = object
    name*: string
    ok*: bool
    message*: string

  CbssTestRunSummary* = object
    checks*: seq[CbssCheckResult]

  CbssScenario* = object
    name*: string
    driver*: CbssTestDriver
    summary*: CbssTestRunSummary
    artifactDir*: string
    artifacts*: seq[string]

const cbssUpdateSnapshotsEnv* = "CBSS_UPDATE_SNAPSHOTS"
const cbssDefaultActionLogLimit = 80

proc initCbssTestRunSummary*(): CbssTestRunSummary =
  CbssTestRunSummary(checks: @[])

proc record*(
    summary: var CbssTestRunSummary;
    name: string;
    ok: bool;
    message = ""
): bool =
  summary.checks.add CbssCheckResult(name: name, ok: ok, message: message)
  ok

proc record*(
    summary: var CbssTestRunSummary;
    name: string;
    check: tuple[ok: bool, message: string]
): bool =
  summary.record(name, check.ok, check.message)

proc passed*(summary: CbssTestRunSummary): int =
  for check in summary.checks:
    if check.ok:
      inc result

proc failed*(summary: CbssTestRunSummary): int =
  for check in summary.checks:
    if not check.ok:
      inc result

proc ok*(summary: CbssTestRunSummary): bool =
  summary.failed == 0

proc report*(summary: CbssTestRunSummary): string =
  var lines = @[
    "checks: " & $summary.checks.len,
    "passed: " & $summary.passed,
    "failed: " & $summary.failed
  ]
  for check in summary.checks:
    if not check.ok:
      lines.add "- " & check.name & ": " & check.message
  lines.join("\n")

proc save*(summary: CbssTestRunSummary; path: string) =
  let directory = parentDir(path)
  if directory.len > 0:
    createDir(directory)
  writeFile(path, summary.report())

proc rememberAction(driver: CbssTestDriver; action: string) =
  driver.actionLog.add action
  if driver.actionLog.len > cbssDefaultActionLogLimit:
    while driver.actionLog.len > cbssDefaultActionLogLimit:
      driver.actionLog.delete(0)

proc actionSnapshot*(driver: CbssTestDriver): string =
  if driver.actionLog.len == 0:
    return ""
  var lines: seq[string]
  for index, action in driver.actionLog:
    lines.add $index & ": " & action
  lines.join("\n")

proc clearActionLog*(driver: CbssTestDriver) =
  driver.actionLog.setLen(0)

proc node*(id: NodeId): CbssQuery =
  CbssQuery(kind: cqNode, node: id)

proc node*(handle: NodeHandle): CbssQuery =
  CbssQuery(kind: cqNode, node: handle.nodeId)

proc byId*(value: string): CbssQuery =
  CbssQuery(kind: cqId, value: value)

proc byCode*(value: string): CbssQuery =
  CbssQuery(kind: cqCode, value: value)

proc byGroup*(value: string): CbssQuery =
  CbssQuery(kind: cqGroup, value: value)

proc byText*(value: string): CbssQuery =
  CbssQuery(kind: cqText, value: value)

proc byTextContains*(value: string): CbssQuery =
  CbssQuery(kind: cqTextContains, value: value)

proc byPlaceholder*(value: string): CbssQuery =
  CbssQuery(kind: cqPlaceholder, value: value)

proc byValue*(value: string): CbssQuery =
  CbssQuery(kind: cqValue, value: value)

proc byAttribute*(name, value: string): CbssQuery =
  CbssQuery(kind: cqAttribute, attrName: name, attrValue: value)

proc describe*(query: CbssQuery): string =
  case query.kind
  of cqNode:
    "node(" & $query.node.nodeIndex & ")"
  of cqId:
    "byId(" & query.value & ")"
  of cqCode:
    "byCode(" & query.value & ")"
  of cqGroup:
    "byGroup(" & query.value & ")"
  of cqText:
    "byText(" & query.value & ")"
  of cqTextContains:
    "byTextContains(" & query.value & ")"
  of cqPlaceholder:
    "byPlaceholder(" & query.value & ")"
  of cqValue:
    "byValue(" & query.value & ")"
  of cqAttribute:
    "byAttribute(" & query.attrName & "=" & query.attrValue & ")"

proc matches(tree: Tree; id: NodeId; query: CbssQuery): bool =
  if not tree.isValid(id):
    return false
  let item = tree.nodes[id.nodeIndex]
  case query.kind
  of cqNode:
    id == query.node
  of cqId:
    item.id == query.value
  of cqCode:
    item.code == query.value
  of cqGroup:
    item.hasGroup(query.value)
  of cqText:
    item.kind == nkText and item.text == query.value
  of cqTextContains:
    item.kind == nkText and item.text.contains(query.value)
  of cqPlaceholder:
    let value = item.attrValue("placeholder")
    value.isSome and value.get == query.value
  of cqValue:
    let value = item.attrValue("value")
    value.isSome and value.get == query.value
  of cqAttribute:
    let value = item.attrValue(query.attrName)
    value.isSome and value.get == query.attrValue

proc refresh*(driver: CbssTestDriver) =
  driver.diagnostics = Diagnostics()
  let targetStyles = resolveTreeStyles(
    driver.ui.tree,
    driver.ui.styleSheets(),
    defaultProperties(),
    driver.diagnostics,
    viewportSize = some(driver.viewport)
  )
  if driver.styles.styles.len > 0:
    driver.ui.reconcileStyleTransitions(
      driver.styles, targetStyles, driver.nowSeconds
    )
  driver.styles = targetStyles
  driver.scheduler.clearDeadline()
  discard driver.scheduler.consumeDirty()
  discard driver.ui.applyStyleTransitions(
    driver.styles, driver.scheduler, driver.nowSeconds
  )
  driver.layout = computeLayout(driver.ui.tree, driver.styles, driver.viewport, driver.ui.textEngine, driver.ui.fonts)
  driver.ui.scroll.syncScrollState(driver.ui.tree, driver.styles, driver.layout)
  driver.ui.syncRenderSurfaces(driver.styles, driver.layout)
  driver.hitRegions = buildHitRegions(driver.ui.tree, driver.layout, driver.styles, driver.ui.scroll)
  driver.paintCommands = buildPaintCommands(
    driver.ui.tree, driver.styles, driver.layout, driver.ui.scroll,
    driver.ui.canvasPaintProvider()
  )
  discard driver.ui.consumeInvalidation()

proc advanceTime*(driver: CbssTestDriver; elapsedSeconds: float64) =
  ## Advances timed paint work without resolving style, layout, or hit regions.
  ## Tests can therefore assert the same retained-frame behavior as a host loop.
  if elapsedSeconds.classify in {fcNan, fcInf, fcNegInf} or elapsedSeconds < 0:
    raise newException(
      ValueError, "test-driver elapsed time must be finite and non-negative"
    )
  driver.rememberAction("advanceTime " & $elapsedSeconds)
  driver.nowSeconds += elapsedSeconds
  driver.scheduler.clearDeadline()
  discard driver.scheduler.consumeDirty()
  if driver.ui.applyStyleTransitions(
      driver.styles, driver.scheduler, driver.nowSeconds
  ) > 0:
    driver.paintCommands = buildPaintCommands(
      driver.ui.tree, driver.styles, driver.layout, driver.ui.scroll,
      driver.ui.canvasPaintProvider()
    )

proc setViewport*(driver: CbssTestDriver; viewport: Size) =
  driver.rememberAction("setViewport " & $viewport.w & "x" & $viewport.h)
  driver.viewport = viewport
  driver.refresh()

proc initCbssTestDriver*(ui: UiRoot; viewport: Size): CbssTestDriver =
  result = CbssTestDriver(
    ui: ui,
    viewport: viewport,
    input: initInteractionState(),
    scheduler: initFrameScheduler()
  )
  let driver = result
  result.ui.configureClipboardTextProvider(proc(): string =
    driver.clipboard
  )
  result.ui.configureClipboardTextWriter(proc(text: string) =
    driver.clipboard = text
  )
  result.refresh()

proc initCbssTestDriver*(builder: proc(): UiRoot {.closure.}; viewport: Size): CbssTestDriver =
  initCbssTestDriver(builder(), viewport)

proc all*(driver: CbssTestDriver; query: CbssQuery): seq[NodeId] =
  for index in 0 ..< driver.ui.tree.nodes.len:
    let activeId = driver.ui.tree.nodeIdAt(index)
    if activeId.isNone:
      continue
    let id = activeId.get
    if driver.ui.tree.matches(id, query):
      result.add id

proc count*(driver: CbssTestDriver; query: CbssQuery): int =
  driver.all(query).len

proc exists*(driver: CbssTestDriver; query: CbssQuery): bool =
  driver.count(query) > 0

proc first*(driver: CbssTestDriver; query: CbssQuery): Option[NodeId] =
  let matches = driver.all(query)
  if matches.len == 0:
    none(NodeId)
  else:
    some(matches[0])

proc nodeLabel(driver: CbssTestDriver; id: NodeId): string =
  let item = driver.ui.tree.nodes[id.nodeIndex]
  result = $id.nodeIndex
  if item.id.len > 0:
    result.add " #" & item.id
  if item.code.len > 0:
    result.add " code=" & item.code
  if item.groups.len > 0:
    result.add " ." & item.groups.join(".")
  if item.kind == nkText:
    result.add " text=" & item.text
  for attr in item.attributes:
    result.add " [" & attr.name & "=" & attr.value & "]"

proc treeSnapshot*(driver: CbssTestDriver): string =
  var lines: seq[string]
  for index, item in driver.ui.tree.nodes:
    let activeId = driver.ui.tree.nodeIdAt(index)
    if activeId.isNone:
      continue
    let id = activeId.get
    let parent =
      if item.parent.isSome: $item.parent.get.nodeIndex
      else: "-"
    lines.add driver.nodeLabel(id) & " parent=" & parent
  lines.join("\n")

proc queryReport*(driver: CbssTestDriver; query: CbssQuery): string =
  let matches = driver.all(query)
  var lines = @[
    "query: " & query.describe(),
    "matches: " & $matches.len
  ]
  for id in matches:
    lines.add "  " & driver.nodeLabel(id)
  if matches.len == 0:
    lines.add "tree:"
    lines.add driver.treeSnapshot()
  lines.join("\n")

proc dispatchSnapshot*(driver: CbssTestDriver): string =
  var lines: seq[string]
  for dispatch in driver.lastDispatches:
    let target =
      if dispatch.target.isSome:
        driver.nodeLabel(dispatch.target.get)
      else:
        "-"
    let local =
      if dispatch.local.isSome:
        $dispatch.local.get.x & "," & $dispatch.local.get.y
      else:
        "-"
    lines.add $dispatch.event.kind & " target=" & target & " local=" & local
  lines.join("\n")

proc dispatchCount*(driver: CbssTestDriver; kind: InputEventKind): int =
  for dispatch in driver.lastDispatches:
    if dispatch.event.kind == kind:
      inc result

proc dispatched*(driver: CbssTestDriver; kind: InputEventKind): bool =
  driver.dispatchCount(kind) > 0

proc requireFirst*(driver: CbssTestDriver; query: CbssQuery): NodeId =
  let found = driver.first(query)
  if found.isNone:
    raise newException(ValueError, "CBSS test driver query did not match a node\n" & driver.queryReport(query))
  found.get

proc requireOne*(driver: CbssTestDriver; query: CbssQuery): NodeId =
  let matches = driver.all(query)
  if matches.len == 1:
    return matches[0]
  if matches.len == 0:
    raise newException(ValueError, "CBSS test driver query did not match a node\n" & driver.queryReport(query))
  raise newException(ValueError, "CBSS test driver query matched multiple nodes; use a handle, a narrower query, or allWithin\n" & driver.queryReport(query))

proc isUnique*(driver: CbssTestDriver; query: CbssQuery): bool =
  driver.count(query) == 1

proc isDescendantOf(driver: CbssTestDriver; child, ancestor: NodeId): bool =
  if not driver.ui.tree.isValid(child) or not driver.ui.tree.isValid(ancestor):
    return false
  var current = driver.ui.tree.nodes[child.nodeIndex].parent
  while current.isSome:
    if current.get == ancestor:
      return true
    current = driver.ui.tree.nodes[current.get.nodeIndex].parent
  false

proc allWithin*(driver: CbssTestDriver; parent: CbssQuery; query: CbssQuery): seq[NodeId] =
  let parentId = driver.requireFirst(parent)
  for id in driver.all(query):
    if id == parentId or driver.isDescendantOf(id, parentId):
      result.add id

proc childrenOf*(driver: CbssTestDriver; parent: CbssQuery; query: CbssQuery): seq[NodeId] =
  let parentId = driver.requireFirst(parent)
  for child in driver.ui.tree.nodes[parentId.nodeIndex].children:
    if driver.ui.tree.matches(child, query):
      result.add child

proc firstChildOf*(driver: CbssTestDriver; parent: CbssQuery; query: CbssQuery): Option[NodeId] =
  let matches = driver.childrenOf(parent, query)
  if matches.len == 0:
    none(NodeId)
  else:
    some(matches[0])

proc requireChildOf*(driver: CbssTestDriver; parent: CbssQuery; query: CbssQuery): NodeId =
  let matches = driver.childrenOf(parent, query)
  if matches.len == 1:
    return matches[0]
  if matches.len == 0:
    raise newException(ValueError, "CBSS child query did not match a node\nparent: " &
      parent.describe() & "\n" & driver.queryReport(query))
  raise newException(ValueError, "CBSS child query matched multiple nodes\nparent: " &
    parent.describe() & "\n" & driver.queryReport(query))

proc firstWithin*(driver: CbssTestDriver; parent: CbssQuery; query: CbssQuery): Option[NodeId] =
  let matches = driver.allWithin(parent, query)
  if matches.len == 0:
    none(NodeId)
  else:
    some(matches[0])

proc countWithin*(driver: CbssTestDriver; parent: CbssQuery; query: CbssQuery): int =
  driver.allWithin(parent, query).len

proc within*(driver: CbssTestDriver; parent: CbssQuery): CbssScope =
  discard driver.requireFirst(parent)
  CbssScope(driver: driver, parent: parent)

proc within*(scope: CbssScope; parent: CbssQuery): CbssScope =
  let matches = scope.driver.allWithin(scope.parent, parent)
  if matches.len == 1:
    return CbssScope(driver: scope.driver, parent: node(matches[0]))
  if matches.len == 0:
    raise newException(ValueError, "CBSS nested scope query did not match a node\nwithin: " &
      scope.parent.describe() & "\n" & scope.driver.queryReport(parent))
  raise newException(ValueError, "CBSS nested scope query matched multiple nodes\nwithin: " &
    scope.parent.describe() & "\n" & scope.driver.queryReport(parent))

proc queryReport*(scope: CbssScope; query: CbssQuery): string =
  let parentId = scope.driver.requireFirst(scope.parent)
  let matches = scope.driver.allWithin(scope.parent, query)
  var lines = @[
    "within: " & scope.parent.describe(),
    "parent: " & scope.driver.nodeLabel(parentId),
    "query: " & query.describe(),
    "matches: " & $matches.len
  ]
  for id in matches:
    lines.add "  " & scope.driver.nodeLabel(id)
  if matches.len == 0:
    lines.add "subtree:"
    for id in 0 ..< scope.driver.ui.tree.nodes.len:
      let activeId = scope.driver.ui.tree.nodeIdAt(id)
      if activeId.isNone:
        continue
      let nodeId = activeId.get
      if nodeId == parentId or scope.driver.isDescendantOf(nodeId, parentId):
        lines.add "  " & scope.driver.nodeLabel(nodeId)
  lines.join("\n")

proc all*(scope: CbssScope; query: CbssQuery): seq[NodeId] =
  scope.driver.allWithin(scope.parent, query)

proc children*(scope: CbssScope; query: CbssQuery): seq[NodeId] =
  scope.driver.childrenOf(scope.parent, query)

proc firstChild*(scope: CbssScope; query: CbssQuery): Option[NodeId] =
  let matches = scope.children(query)
  if matches.len == 0:
    none(NodeId)
  else:
    some(matches[0])

proc requireChild*(scope: CbssScope; query: CbssQuery): NodeId =
  let matches = scope.children(query)
  if matches.len == 1:
    return matches[0]
  if matches.len == 0:
    raise newException(ValueError, "CBSS scoped child query did not match a node\n" & scope.queryReport(query))
  raise newException(ValueError, "CBSS scoped child query matched multiple nodes\n" & scope.queryReport(query))

proc count*(scope: CbssScope; query: CbssQuery): int =
  scope.all(query).len

proc exists*(scope: CbssScope; query: CbssQuery): bool =
  scope.count(query) > 0

proc first*(scope: CbssScope; query: CbssQuery): Option[NodeId] =
  let matches = scope.all(query)
  if matches.len == 0:
    none(NodeId)
  else:
    some(matches[0])

proc requireFirst*(scope: CbssScope; query: CbssQuery): NodeId =
  let found = scope.first(query)
  if found.isNone:
    raise newException(ValueError, "CBSS scoped query did not match a node\n" & scope.queryReport(query))
  found.get

proc requireOne*(scope: CbssScope; query: CbssQuery): NodeId =
  let matches = scope.all(query)
  if matches.len == 1:
    return matches[0]
  if matches.len == 0:
    raise newException(ValueError, "CBSS scoped query did not match a node\n" & scope.queryReport(query))
  raise newException(ValueError, "CBSS scoped query matched multiple nodes; use a handle or narrower query\n" & scope.queryReport(query))

proc isUnique*(scope: CbssScope; query: CbssQuery): bool =
  scope.count(query) == 1

proc rectFor*(driver: CbssTestDriver; target: NodeId): Option[Rect] =
  for item in driver.layout.boxes:
    if item.node == target:
      return some(item.rect)
  none(Rect)

proc centerFor*(driver: CbssTestDriver; target: NodeId): Vec2 =
  let bounds = driver.rectFor(target)
  if bounds.isNone:
    raise newException(ValueError, "CBSS test driver target has no layout box")
  vec2(bounds.get.x + bounds.get.w / 2.0'f32, bounds.get.y + bounds.get.h / 2.0'f32)

proc rectFor*(driver: CbssTestDriver; query: CbssQuery): Option[Rect] =
  driver.rectFor(driver.requireFirst(query))

proc centerFor*(driver: CbssTestDriver; query: CbssQuery): Vec2 =
  driver.centerFor(driver.requireFirst(query))

proc handleDispatches(driver: CbssTestDriver; dispatches: var seq[DispatchResult]): bool =
  driver.lastDispatches = dispatches
  driver.ui.normalizeTextControlDispatches(driver.hitRegions, dispatches)
  driver.lastDispatches = dispatches
  for dispatch in dispatches:
    if dispatch.event.kind == iekPointerDown:
      if driver.ui.closeOpenPopups(dispatch.target):
        driver.refresh()
        return true
      discard driver.ui.normalizeFocus(driver.input, dispatch.target)
  result = driver.ui.handleEvents(dispatches)
  discard driver.ui.reconcilePointerCapture(driver.input)
  discard driver.ui.reconcileFocus(driver.input)
  driver.refresh()

proc sendPointer*(driver: CbssTestDriver; event: InputEvent): bool =
  let point =
    if event.position.isSome:
      " @" & $event.position.get.x & "," & $event.position.get.y
    else:
      ""
  driver.rememberAction("pointer " & $event.kind & point)
  var dispatches = driver.input.processInput(
    driver.ui.tree, driver.hitRegions, event, driver.ui.scroll
  )
  driver.handleDispatches(dispatches)

proc hitAt*(driver: CbssTestDriver; point: Vec2): Option[NodeId] =
  let hit = hitTest(driver.hitRegions, point)
  if hit.isSome:
    some(hit.get.node)
  else:
    none(NodeId)

proc hitAt*(driver: CbssTestDriver; query: CbssQuery): Option[NodeId] =
  driver.hitAt(driver.centerFor(query))

proc hits*(driver: CbssTestDriver; point: Vec2; query: CbssQuery): bool =
  let hit = driver.hitAt(point)
  hit.isSome and driver.ui.tree.matches(hit.get, query)

proc hits*(driver: CbssTestDriver; point: Vec2; target: NodeId): bool =
  let hit = driver.hitAt(point)
  hit.isSome and hit.get == target

proc hits*(driver: CbssTestDriver; hitQuery, expectedQuery: CbssQuery): bool =
  driver.hits(driver.centerFor(hitQuery), driver.requireFirst(expectedQuery))

proc isVisible*(driver: CbssTestDriver; query: CbssQuery): bool =
  let target = driver.first(query)
  if target.isNone or driver.rectFor(target.get).isNone:
    return false
  var current = target
  while current.isSome:
    let nodeId = current.get
    if not driver.ui.tree.isValid(nodeId):
      return false
    let style = driver.styles.styles[nodeId.nodeIndex]
    if style.layout.display == dkNone or
        (style.visual.contentVisibility.isSome and
          style.visual.contentVisibility.get == "hidden"):
      return false
    current = driver.ui.tree.nodes[nodeId.nodeIndex].parent
  true

proc hover*(driver: CbssTestDriver; point: Vec2): bool =
  let hit = hitTest(driver.hitRegions, point)
  driver.rememberAction("hover @" & $point.x & "," & $point.y)
  discard driver.sendPointer(pointerMoveEvent(point))
  hit.isSome

proc hover*(driver: CbssTestDriver; query: CbssQuery): bool =
  driver.hover(driver.centerFor(query))

proc wheel*(driver: CbssTestDriver; point: Vec2; delta: Vec2): bool =
  let hit = hitTest(driver.hitRegions, point)
  driver.rememberAction("wheel @" & $point.x & "," & $point.y & " delta=" & $delta.x & "," & $delta.y)
  discard driver.sendPointer(wheelEvent(point, delta))
  hit.isSome

proc wheel*(driver: CbssTestDriver; query: CbssQuery; delta: Vec2): bool =
  driver.wheel(driver.centerFor(query), delta)

proc scrollOffset*(driver: CbssTestDriver; query: CbssQuery): Option[Vec2] =
  let target = driver.requireOne(query)
  let metrics = driver.ui.scroll.metricsFor(target)
  if metrics.isNone:
    return none(Vec2)
  some(metrics.get.offset)

proc drag*(driver: CbssTestDriver; startPoint, endPoint: Vec2; steps = 8; button = 0): bool =
  driver.rememberAction("drag @" & $startPoint.x & "," & $startPoint.y &
    " -> " & $endPoint.x & "," & $endPoint.y & " steps=" & $steps)
  let stepCount =
    if steps < 1: 1
    else: steps
  discard driver.sendPointer(pointerDownEvent(startPoint, button))
  for index in 1 .. stepCount:
    let ratio = index.float32 / stepCount.float32
    let point = vec2(
      startPoint.x + (endPoint.x - startPoint.x) * ratio,
      startPoint.y + (endPoint.y - startPoint.y) * ratio
    )
    discard driver.sendPointer(pointerMoveEvent(point))
  discard driver.sendPointer(pointerUpEvent(endPoint, button))
  true

proc drag*(driver: CbssTestDriver; query: CbssQuery; delta: Vec2; steps = 8; button = 0): bool =
  let startPoint = driver.centerFor(query)
  driver.drag(startPoint, vec2(startPoint.x + delta.x, startPoint.y + delta.y), steps, button)

proc click*(driver: CbssTestDriver; point: Vec2; button = 0): bool =
  driver.rememberAction("click @" & $point.x & "," & $point.y & " button=" & $button)
  let hit = hitTest(driver.hitRegions, point)
  let target =
    if hit.isSome: some(hit.get.node)
    else: none(NodeId)
  if driver.ui.closeOpenPopups(target):
    driver.refresh()
    return true
  if target.isNone:
    return false
  discard driver.sendPointer(pointerDownEvent(point, button))
  discard driver.sendPointer(pointerUpEvent(point, button))
  true

proc click*(driver: CbssTestDriver; target: NodeId; button = 0): bool =
  driver.click(driver.centerFor(target), button)

proc click*(driver: CbssTestDriver; query: CbssQuery; button = 0): bool =
  driver.rememberAction("click " & query.describe())
  driver.click(driver.requireFirst(query), button)

proc clickOutside*(driver: CbssTestDriver): bool =
  driver.rememberAction("clickOutside")
  if driver.ui.closeOpenPopups(none(NodeId)):
    driver.refresh()
    return true
  false

proc closePopups*(driver: CbssTestDriver): bool =
  driver.clickOutside()

proc openPopup*(driver: CbssTestDriver; query: CbssQuery): bool =
  driver.rememberAction("openPopup " & query.describe())
  let target = driver.requireFirst(query)
  let item = driver.ui.tree.nodes[target.nodeIndex]
  let openAttr = item.attrValue("open")
  if esOpen in item.states or (openAttr.isSome and openAttr.get == "true"):
    return true
  driver.click(query)

proc chooseOpenOption*(driver: CbssTestDriver; optionLabel: string): bool =
  driver.rememberAction("chooseOpenOption " & optionLabel)
  driver.click(byText(optionLabel))

proc choosePopupOption*(driver: CbssTestDriver; popupQuery: CbssQuery; optionLabel: string): bool =
  driver.rememberAction("choosePopupOption " & popupQuery.describe() & " -> " & optionLabel)
  if not driver.openPopup(popupQuery):
    return false
  driver.chooseOpenOption(optionLabel)

proc focusedTarget*(driver: CbssTestDriver): Option[NodeId] =
  driver.input.focusedTarget

proc focus*(driver: CbssTestDriver; target: NodeId): bool =
  driver.rememberAction("focus node(" & $target.nodeIndex & ")")
  if target.nodeIndex < 0 or target.nodeIndex >= driver.ui.tree.nodes.len:
    return false
  if not driver.ui.tree.isFocusable(target):
    return false
  discard driver.ui.setFocus(driver.input, some(target), focusVisible = true)
  driver.refresh()
  true

proc focus*(driver: CbssTestDriver; query: CbssQuery): bool =
  driver.rememberAction("focus " & query.describe())
  driver.focus(driver.requireFirst(query))

proc sendFocused*(driver: CbssTestDriver; event: InputEvent): bool =
  driver.rememberAction("focused " & $event.kind)
  if driver.input.focusedTarget.isNone:
    return false
  let owned = event.markFocusOwned(driver.input)
  if event.kind in {iekKeyDown, iekKeyUp, iekTextInput, iekPaste, iekCopy, iekCut,
      iekCompositionStart, iekCompositionUpdate, iekCompositionEnd}:
    if not driver.input.acceptsFocusOwnedEvent(owned):
      return false
  var dispatchEvent = owned
  dispatchEvent.focusOwner = none(NodeId)
  result = driver.ui.handleEvent(
    DispatchResult(target: driver.input.focusedTarget, local: none(Vec2), event: dispatchEvent)
  )
  discard driver.ui.reconcilePointerCapture(driver.input)
  discard driver.ui.reconcileFocus(driver.input)
  driver.lastDispatches = @[DispatchResult(target: driver.input.focusedTarget, local: none(Vec2), event: dispatchEvent)]
  driver.refresh()

proc press*(driver: CbssTestDriver; key: string; ctrlKey = false; altKey = false; shiftKey = false; metaKey = false): bool =
  driver.rememberAction("press " & key & " ctrl=" & $ctrlKey & " alt=" & $altKey &
    " shift=" & $shiftKey & " meta=" & $metaKey)
  if key == "Tab" and not ctrlKey and not altKey and not metaKey:
    result = driver.ui.moveFocus(driver.input, if shiftKey: -1 else: 1)
    if result and driver.input.focusedTarget.isSome and
        driver.ui.isTextInputTarget(driver.input.focusedTarget.get):
      driver.ui.moveFocusedTextControlCaretToEnd(driver.input.focusedTarget.get)
    driver.refresh()
    return
  driver.sendFocused(keyDownEvent(key, ctrlKey = ctrlKey, altKey = altKey, shiftKey = shiftKey, metaKey = metaKey))

proc typeText*(driver: CbssTestDriver; text: string): bool =
  driver.rememberAction("typeText len=" & $text.len)
  for ch in text:
    discard driver.sendFocused(textInputEvent($ch))
    result = true

proc paste*(driver: CbssTestDriver; text: string): bool =
  driver.rememberAction("paste len=" & $text.len)
  if driver.input.focusedTarget.isNone:
    return false
  discard driver.sendFocused(pasteEvent(text))
  true

proc paste*(driver: CbssTestDriver): bool =
  driver.paste(driver.clipboard)

proc copy*(driver: CbssTestDriver): bool =
  driver.rememberAction("copy")
  if driver.input.focusedTarget.isNone:
    return false
  discard driver.sendFocused(copyEvent())
  true

proc cut*(driver: CbssTestDriver): bool =
  driver.rememberAction("cut")
  if driver.input.focusedTarget.isNone:
    return false
  discard driver.sendFocused(cutEvent())
  true

proc copyShortcut*(driver: CbssTestDriver; metaKey = false): bool =
  driver.press("c", ctrlKey = not metaKey, metaKey = metaKey)

proc cutShortcut*(driver: CbssTestDriver; metaKey = false): bool =
  driver.press("x", ctrlKey = not metaKey, metaKey = metaKey)

proc pasteShortcut*(driver: CbssTestDriver; metaKey = false): bool =
  driver.press("v", ctrlKey = not metaKey, metaKey = metaKey)

proc selectAll*(driver: CbssTestDriver): bool =
  driver.rememberAction("selectAll")
  driver.press("a", ctrlKey = true)

proc selectAllShortcut*(driver: CbssTestDriver; metaKey = false): bool =
  driver.press("a", ctrlKey = not metaKey, metaKey = metaKey)

proc clear*(driver: CbssTestDriver; query: CbssQuery): bool =
  driver.rememberAction("clear " & query.describe())
  if not driver.click(query):
    return false
  discard driver.selectAll()
  discard driver.press("Backspace")
  true

proc fill*(driver: CbssTestDriver; query: CbssQuery; text: string): bool =
  driver.rememberAction("fill " & query.describe() & " len=" & $text.len)
  if not driver.clear(query):
    return false
  driver.paste(text)

proc chooseOption*(driver: CbssTestDriver; selectQuery: CbssQuery; optionLabel: string): bool =
  driver.rememberAction("chooseOption " & selectQuery.describe() & " -> " & optionLabel)
  if not driver.click(selectQuery):
    return false
  driver.click(byText(optionLabel))

proc toggle*(driver: CbssTestDriver; query: CbssQuery): bool =
  driver.rememberAction("toggle " & query.describe())
  driver.click(query)

proc textContent(driver: CbssTestDriver; target: NodeId): string =
  if not driver.ui.tree.isValid(target):
    return ""
  let item = driver.ui.tree.nodes[target.nodeIndex]
  if item.kind == nkText:
    result.add item.text
  for child in item.children:
    result.add driver.textContent(child)

proc textContent*(driver: CbssTestDriver; query: CbssQuery): string =
  driver.textContent(driver.requireFirst(query))

proc value*(driver: CbssTestDriver; query: CbssQuery): string =
  let target = driver.requireFirst(query)
  let attr = driver.ui.tree.nodes[target.nodeIndex].attrValue("value")
  if attr.isSome:
    attr.get
  else:
    driver.textContent(target)

proc values*(driver: CbssTestDriver): seq[tuple[id: string, value: string]] =
  for item in driver.ui.tree.nodes:
    if not item.alive or item.id.len == 0:
      continue
    let value = item.attrValue("value")
    if value.isSome:
      result.add (item.id, value.get)

proc valuesByCode*(driver: CbssTestDriver): seq[tuple[code: string, value: string]] =
  for item in driver.ui.tree.nodes:
    if not item.alive or item.code.len == 0:
      continue
    let value = item.attrValue("value")
    if value.isSome:
      result.add (item.code, value.get)

proc controlValues*(driver: CbssTestDriver): seq[tuple[keyKind: string, key: string, value: string]] =
  for item in driver.ui.tree.nodes:
    if not item.alive:
      continue
    let value = item.attrValue("value")
    if value.isNone:
      continue
    if item.id.len > 0:
      result.add ("id", item.id, value.get)
    if item.code.len > 0:
      result.add ("code", item.code, value.get)

proc formSnapshot*(driver: CbssTestDriver): string =
  var lines: seq[string]
  for item in driver.controlValues():
    lines.add item.keyKind & ":" & item.key & "=" & item.value
  lines.join("\n")

proc valueById*(driver: CbssTestDriver; id: string): Option[string] =
  for item in driver.values():
    if item.id == id:
      return some(item.value)
  none(string)

proc valueByCode*(driver: CbssTestDriver; code: string): Option[string] =
  for item in driver.valuesByCode():
    if item.code == code:
      return some(item.value)
  none(string)

proc attribute*(driver: CbssTestDriver; query: CbssQuery; name: string): Option[string] =
  driver.ui.tree.nodes[driver.requireFirst(query).nodeIndex].attrValue(name)

proc caret*(driver: CbssTestDriver; query: CbssQuery): Option[int] =
  let value = driver.attribute(query, "caret")
  if value.isNone:
    return none(int)
  try:
    some(parseInt(value.get))
  except ValueError:
    none(int)

proc selectionRange*(driver: CbssTestDriver; query: CbssQuery): Option[tuple[first, last: int]] =
  let first = driver.attribute(query, "selection-start")
  let last = driver.attribute(query, "selection-end")
  if first.isNone or last.isNone:
    return none(tuple[first, last: int])
  try:
    some((parseInt(first.get), parseInt(last.get)))
  except ValueError:
    none(tuple[first, last: int])

proc selectedText*(driver: CbssTestDriver; query: CbssQuery): string =
  let value = driver.value(query)
  let range = driver.selectionRange(query)
  if range.isNone:
    return ""
  let bounds = range.get
  let first = max(0, min(bounds.first, value.len))
  let last = max(first, min(bounds.last, value.len))
  if first == last:
    return ""
  value[first ..< last]

proc scrollY*(driver: CbssTestDriver; query: CbssQuery): Option[float32] =
  let value = driver.attribute(query, "scroll-y")
  if value.isNone:
    return none(float32)
  try:
    some(parseFloat(value.get).float32)
  except ValueError:
    none(float32)

proc rectSnapshot(rect: Rect): string =
  $rect.x & "," & $rect.y & "," & $rect.w & "," & $rect.h

proc pathSnapshot(path: Path2D): string =
  var values = newSeqOfCap[string](path.segments.len)
  for segment in path.segments:
    var value = $segment.kind
    case segment.kind
    of pskMoveTo, pskLineTo:
      value.add "(" & $segment.endpoint.x & "," & $segment.endpoint.y & ")"
    of pskQuadraticTo:
      value.add "(" & $segment.control1.x & "," & $segment.control1.y &
        ";" & $segment.endpoint.x & "," & $segment.endpoint.y & ")"
    of pskCubicTo:
      value.add "(" & $segment.control1.x & "," & $segment.control1.y &
        ";" & $segment.control2.x & "," & $segment.control2.y &
        ";" & $segment.endpoint.x & "," & $segment.endpoint.y & ")"
    of pskClose:
      discard
    values.add value
  values.join(";")

proc layoutSnapshot*(driver: CbssTestDriver): string =
  var lines: seq[string]
  for item in driver.layout.boxes:
    let node = driver.ui.tree.nodes[item.node.nodeIndex]
    let label =
      if node.id.len > 0: "#" & node.id
      elif node.groups.len > 0: "." & node.groups.join(".")
      else: $item.node.nodeIndex
    lines.add label & " " & rectSnapshot(item.rect) & " z=" & $item.zIndex
  lines.join("\n")

proc layoutSnapshot*(driver: CbssTestDriver; query: CbssQuery): string =
  let target = driver.requireFirst(query)
  var lines: seq[string]
  for item in driver.layout.boxes:
    if item.node == target:
      lines.add driver.nodeLabel(target) & " " & rectSnapshot(item.rect) & " z=" & $item.zIndex
  lines.join("\n")

proc paintSnapshot*(driver: CbssTestDriver): string =
  var lines: seq[string]
  for command in driver.paintCommands:
    case command.kind
    of pcPushTransform:
      lines.add "push-transform"
    of pcPopTransform:
      lines.add "pop-transform"
    of pcPushLayer:
      lines.add "push-layer " & rectSnapshot(command.layerBounds) &
        " opacity=" & $command.layerOpacity &
        " composite=" & $command.layerCompositeMode
    of pcPopLayer:
      lines.add "pop-layer"
    of pcPushClip:
      lines.add "push-clip " & rectSnapshot(command.clipRect)
    of pcPopClip:
      lines.add "pop-clip"
    of pcBoxShadow:
      lines.add "box-shadow " & rectSnapshot(command.shadowRect)
    of pcFillRect:
      lines.add "fill-rect " & rectSnapshot(command.rect)
    of pcFillLinearGradient:
      lines.add "linear-gradient " & rectSnapshot(command.gradientRect)
    of pcStrokeRect:
      lines.add "stroke-rect " & rectSnapshot(command.strokeRect) & " width=" & $command.strokeWidth
    of pcStrokePath:
      lines.add "stroke-path " & pathSnapshot(command.path) &
        " width=" & $command.pathWidth & " cap=" & $command.pathLineCap &
        " join=" & $command.pathLineJoin
    of pcDrawText:
      lines.add "draw-text " & $command.node.nodeIndex & " " & command.text & " @" & $command.position.x & "," & $command.position.y
    of pcDrawImage:
      lines.add "draw-image " & $command.imageNode.nodeIndex & " " & command.imageSource & " " & rectSnapshot(command.imageRect)
  lines.join("\n")

proc paintSnapshot*(driver: CbssTestDriver; query: CbssQuery): string =
  let target = driver.requireFirst(query)
  var lines: seq[string]
  for command in driver.paintCommands:
    let matches =
      case command.kind
      of pcDrawText:
        command.node == target
      of pcDrawImage:
        command.imageNode == target
      else:
        false
    if matches:
      case command.kind
      of pcDrawText:
        lines.add "draw-text " & $command.node.nodeIndex & " " & command.text & " @" & $command.position.x & "," & $command.position.y
      of pcDrawImage:
        lines.add "draw-image " & $command.imageNode.nodeIndex & " " & command.imageSource & " " & rectSnapshot(command.imageRect)
      else:
        discard
  lines.join("\n")

proc snapshot*(driver: CbssTestDriver): string =
  "layout:\n" & driver.layoutSnapshot() & "\npaint:\n" & driver.paintSnapshot()

proc rectJson(rect: Rect): JsonNode =
  %*{
    "x": rect.x,
    "y": rect.y,
    "w": rect.w,
    "h": rect.h
  }

proc structuredSnapshotJson*(driver: CbssTestDriver): JsonNode =
  result = newJObject()
  result["viewport"] = %*{
    "w": driver.viewport.w,
    "h": driver.viewport.h
  }
  result["focused"] =
    if driver.input.focusedTarget.isSome: %driver.input.focusedTarget.get.nodeIndex
    else: newJNull()

  var nodes = newJArray()
  for index, item in driver.ui.tree.nodes:
    if not item.alive:
      continue
    var attrs = newJObject()
    for attr in item.attributes:
      attrs[attr.name] = %attr.value
    var children = newJArray()
    for child in item.children:
      children.add %child.nodeIndex
    nodes.add %*{
      "index": index,
      "kind": $item.kind,
      "parent": (
        if item.parent.isSome: %item.parent.get.nodeIndex
        else: newJNull()
      ),
      "children": children,
      "id": item.id,
      "code": item.code,
      "groups": item.groups,
      "text": item.text,
      "attributes": attrs
    }
  result["nodes"] = nodes

  var layout = newJArray()
  for item in driver.layout.boxes:
    layout.add %*{
      "node": item.node.nodeIndex,
      "rect": rectJson(item.rect),
      "zIndex": item.zIndex
    }
  result["layout"] = layout

  var paint = newJArray()
  for command in driver.paintCommands:
    var entry = newJObject()
    entry["kind"] = %($command.kind)
    case command.kind
    of pcPushTransform:
      entry["matrix"] = %*[
        command.transform.m11, command.transform.m12,
        command.transform.m21, command.transform.m22,
        command.transform.tx, command.transform.ty
      ]
    of pcPopTransform:
      discard
    of pcPushLayer:
      entry["rect"] = rectJson(command.layerBounds)
      entry["opacity"] = %command.layerOpacity
      entry["compositeMode"] = %($command.layerCompositeMode)
    of pcPopLayer:
      discard
    of pcPushClip:
      entry["rect"] = rectJson(command.clipRect)
    of pcPopClip:
      discard
    of pcBoxShadow:
      entry["rect"] = rectJson(command.shadowRect)
    of pcFillRect:
      entry["rect"] = rectJson(command.rect)
    of pcFillLinearGradient:
      entry["rect"] = rectJson(command.gradientRect)
    of pcStrokeRect:
      entry["rect"] = rectJson(command.strokeRect)
      entry["width"] = %command.strokeWidth
    of pcStrokePath:
      var segments = newJArray()
      for segment in command.path.segments:
        segments.add %*{
          "kind": $segment.kind,
          "control1": {"x": segment.control1.x, "y": segment.control1.y},
          "control2": {"x": segment.control2.x, "y": segment.control2.y},
          "endpoint": {"x": segment.endpoint.x, "y": segment.endpoint.y}
        }
      entry["segments"] = segments
      entry["width"] = %command.pathWidth
      entry["lineCap"] = %($command.pathLineCap)
      entry["lineJoin"] = %($command.pathLineJoin)
      entry["miterLimit"] = %command.pathMiterLimit
    of pcDrawText:
      entry["node"] = %command.node.nodeIndex
      entry["text"] = %command.text
      entry["x"] = %command.position.x
      entry["y"] = %command.position.y
    of pcDrawImage:
      entry["node"] = %command.imageNode.nodeIndex
      entry["source"] = %command.imageSource
      entry["rect"] = rectJson(command.imageRect)
    paint.add entry
  result["paint"] = paint

  var values = newJArray()
  for item in driver.controlValues():
    values.add %*{
      "keyKind": item.keyKind,
      "key": item.key,
      "value": item.value
    }
  result["values"] = values

  var actions = newJArray()
  for action in driver.actionLog:
    actions.add %action
  result["actions"] = actions

proc structuredSnapshot*(driver: CbssTestDriver): string =
  driver.structuredSnapshotJson().pretty()

proc debugReport*(driver: CbssTestDriver): string =
  var lines = @[
    "viewport: " & $driver.viewport.w & "x" & $driver.viewport.h,
    "focused: " & (
      if driver.input.focusedTarget.isSome: driver.nodeLabel(driver.input.focusedTarget.get)
      else: "-"
    ),
    "values:"
  ]
  let values = driver.formSnapshot()
  if values.len == 0:
    lines.add "  <none>"
  else:
    for line in values.splitLines():
      lines.add "  " & line
  lines.add "dispatch:"
  let dispatch = driver.dispatchSnapshot()
  if dispatch.len == 0:
    lines.add "  <none>"
  else:
    for line in dispatch.splitLines():
      lines.add "  " & line
  lines.add "actions:"
  let actions = driver.actionSnapshot()
  if actions.len == 0:
    lines.add "  <none>"
  else:
    for line in actions.splitLines():
      lines.add "  " & line
  lines.add "diagnostics:"
  if driver.diagnostics.items.len == 0:
    lines.add "  <none>"
  else:
    for item in driver.diagnostics.items:
      lines.add "  " & $item.severity & " " & item.property & ": " & item.message
  lines.join("\n")

proc debugBundle*(driver: CbssTestDriver; query = none(CbssQuery)): string =
  var lines = @["debug:"]
  lines.add driver.debugReport()
  if query.isSome:
    lines.add "query-report:"
    lines.add driver.queryReport(query.get)
  lines.add "layout:"
  lines.add driver.layoutSnapshot()
  lines.add "paint:"
  lines.add driver.paintSnapshot()
  lines.add "dispatch:"
  let dispatch = driver.dispatchSnapshot()
  if dispatch.len == 0:
    lines.add "<none>"
  else:
    lines.add dispatch
  lines.add "actions:"
  let actions = driver.actionSnapshot()
  if actions.len == 0:
    lines.add "<none>"
  else:
    lines.add actions
  lines.join("\n")

proc saveDebugBundle*(driver: CbssTestDriver; path: string; query = none(CbssQuery)) =
  let directory = parentDir(path)
  if directory.len > 0:
    createDir(directory)
  writeFile(path, driver.debugBundle(query))

proc safeArtifactName(name: string): string =
  for ch in name:
    if ch in {'a'..'z'} or ch in {'A'..'Z'} or ch in {'0'..'9'} or ch in {'-', '_'}:
      result.add ch
    elif result.len == 0 or result[^1] != '_':
      result.add '_'
  result = result.strip(chars = {'_'})
  if result.len == 0:
    result = "artifact"

proc initCbssScenario*(
    name: string;
    driver: CbssTestDriver;
    artifactDir = ""
): CbssScenario =
  CbssScenario(
    name: name,
    driver: driver,
    summary: initCbssTestRunSummary(),
    artifactDir: artifactDir,
    artifacts: @[]
  )

proc scenarioArtifactPath(scenario: CbssScenario; stepName: string): string =
  let index = scenario.summary.checks.len + 1
  scenario.artifactDir / ($index & "_" & safeArtifactName(stepName) & ".txt")

proc saveScenarioArtifact(
    scenario: var CbssScenario;
    stepName: string;
    message: string;
    query = none(CbssQuery)
) =
  if scenario.artifactDir.len == 0:
    return
  let path = scenario.scenarioArtifactPath(stepName)
  let directory = parentDir(path)
  if directory.len > 0:
    createDir(directory)
  writeFile(path, "scenario: " & scenario.name & "\nstep: " & stepName &
    "\nmessage: " & message & "\n\n" & scenario.driver.debugBundle(query))
  scenario.artifacts.add path

proc step*(
    scenario: var CbssScenario;
    name: string;
    action: proc(): bool {.closure.};
    query = none(CbssQuery)
): bool =
  scenario.driver.rememberAction("scenario step " & name)
  var message = "step passed"
  try:
    result = action()
    if not result:
      message = "step returned false"
  except CatchableError as error:
    result = false
    message = error.msg
  discard scenario.summary.record(name, result, message)
  if not result:
    scenario.saveScenarioArtifact(name, message, query)

proc expect*(
    scenario: var CbssScenario;
    name: string;
    check: tuple[ok: bool, message: string];
    query = none(CbssQuery)
): bool =
  result = scenario.summary.record(name, check)
  if not result:
    scenario.saveScenarioArtifact(name, check.message, query)

proc ok*(scenario: CbssScenario): bool =
  scenario.summary.ok

proc report*(scenario: CbssScenario): string =
  var text = "scenario: " & scenario.name & "\n" & scenario.summary.report()
  if scenario.artifacts.len > 0:
    text.add "\nartifacts:"
    for path in scenario.artifacts:
      text.add "\n- " & path
  text

proc diffSnapshot*(expected, actual: string): CbssSnapshotDiff =
  if expected == actual:
    return CbssSnapshotDiff(matches: true, message: "snapshots match")
  let expectedLines = expected.splitLines()
  let actualLines = actual.splitLines()
  let maxLen = max(expectedLines.len, actualLines.len)
  for index in 0 ..< maxLen:
    let expectedLine =
      if index < expectedLines.len: expectedLines[index]
      else: "<missing>"
    let actualLine =
      if index < actualLines.len: actualLines[index]
      else: "<missing>"
    if expectedLine != actualLine:
      return CbssSnapshotDiff(
        matches: false,
        expectedLine: expectedLine,
        actualLine: actualLine,
        line: index + 1,
        message: "snapshot mismatch at line " & $(index + 1) &
          "\nexpected: " & expectedLine &
          "\nactual:   " & actualLine
      )
  CbssSnapshotDiff(matches: false, message: "snapshot mismatch")

proc diffSnapshot*(driver: CbssTestDriver; expected: string): CbssSnapshotDiff =
  diffSnapshot(expected, driver.snapshot())

proc approvedSnapshot*(driver: CbssTestDriver; structured = true): string =
  if structured:
    driver.structuredSnapshot()
  else:
    driver.snapshot()

proc shouldUpdateApprovedSnapshots*(): bool =
  let value = getEnv(cbssUpdateSnapshotsEnv).toLowerAscii()
  value in ["1", "true", "yes", "y", "update", "overwrite"]

proc approvedSnapshotPath*(directory, name: string; structured = true): string =
  let extension =
    if structured: ".json"
    else: ".txt"
  directory / (name & extension)

proc actualSnapshotPath*(approvedPath: string): string =
  approvedPath & ".actual"

proc saveApprovedSnapshot*(driver: CbssTestDriver; path: string; structured = true) =
  let directory = parentDir(path)
  if directory.len > 0:
    createDir(directory)
  writeFile(path, driver.approvedSnapshot(structured = structured))

proc approvedSnapshotDiff*(
    driver: CbssTestDriver;
    path: string;
    structured = true
): CbssSnapshotDiff =
  if not fileExists(path):
    return CbssSnapshotDiff(
      matches: false,
      message: "approved snapshot file does not exist: " & path
    )
  diffSnapshot(readFile(path), driver.approvedSnapshot(structured = structured))

proc expectApprovedSnapshot*(
    driver: CbssTestDriver;
    path: string;
    update = false;
    structured = true;
    writeActual = true
): tuple[ok: bool, message: string] =
  let shouldUpdate = update or shouldUpdateApprovedSnapshots()
  if shouldUpdate:
    driver.saveApprovedSnapshot(path, structured = structured)
    return (true, "approved snapshot updated: " & path)
  let diff = driver.approvedSnapshotDiff(path, structured = structured)
  if not diff.matches and writeActual:
    let actualPath = path.actualSnapshotPath()
    let directory = parentDir(actualPath)
    if directory.len > 0:
      createDir(directory)
    writeFile(actualPath, driver.approvedSnapshot(structured = structured))
    return (false, diff.message & "\nactual snapshot written: " & actualPath)
  (diff.matches, diff.message)

proc expectApprovedSnapshot*(
    driver: CbssTestDriver;
    directory, name: string;
    update = false;
    structured = true;
    writeActual = true
): tuple[ok: bool, message: string] =
  driver.expectApprovedSnapshot(
    approvedSnapshotPath(directory, name, structured = structured),
    update = update,
    structured = structured,
    writeActual = writeActual
  )

proc expectValue*(driver: CbssTestDriver; query: CbssQuery; expected: string): tuple[ok: bool, message: string] =
  let actual = driver.value(query)
  if actual == expected:
    (true, "value matched for " & query.describe())
  else:
    (false, "value mismatch for " & query.describe() & ": expected `" & expected & "`, got `" & actual & "`")

proc expectTextContains*(driver: CbssTestDriver; query: CbssQuery; expected: string): tuple[ok: bool, message: string] =
  let actual = driver.textContent(query)
  if actual.contains(expected):
    (true, "text contained `" & expected & "` for " & query.describe())
  else:
    (false, "text for " & query.describe() & " did not contain `" & expected & "`; got `" & actual & "`")

proc expectSnapshot*(driver: CbssTestDriver; expected: string): tuple[ok: bool, message: string] =
  let diff = driver.diffSnapshot(expected)
  (diff.matches, diff.message)

proc expectExists*(driver: CbssTestDriver; query: CbssQuery): tuple[ok: bool, message: string] =
  if driver.exists(query):
    (true, "query matched: " & query.describe())
  else:
    (false, driver.queryReport(query))

proc expectNotExists*(driver: CbssTestDriver; query: CbssQuery): tuple[ok: bool, message: string] =
  if not driver.exists(query):
    (true, "query did not match: " & query.describe())
  else:
    (false, "query unexpectedly matched\n" & driver.queryReport(query))

proc expectUnique*(driver: CbssTestDriver; query: CbssQuery): tuple[ok: bool, message: string] =
  let matches = driver.count(query)
  if matches == 1:
    (true, "query matched one node: " & query.describe())
  else:
    (false, "query expected one match but found " & $matches & "\n" & driver.queryReport(query))

proc expectCount*(driver: CbssTestDriver; query: CbssQuery; expected: int): tuple[ok: bool, message: string] =
  let actual = driver.count(query)
  if actual == expected:
    (true, "count matched for " & query.describe())
  else:
    (false, "count mismatch for " & query.describe() & ": expected " & $expected & ", got " & $actual &
      "\n" & driver.queryReport(query))

proc expectAttribute*(driver: CbssTestDriver; query: CbssQuery; name, expected: string): tuple[ok: bool, message: string] =
  let actual = driver.attribute(query, name)
  if actual.isSome and actual.get == expected:
    (true, "attribute matched for " & query.describe() & " [" & name & "]")
  elif actual.isSome:
    (false, "attribute mismatch for " & query.describe() & " [" & name & "]: expected `" &
      expected & "`, got `" & actual.get & "`")
  else:
    (false, "attribute missing for " & query.describe() & " [" & name & "]")

proc expectNoDiagnostics*(driver: CbssTestDriver): tuple[ok: bool, message: string] =
  if not driver.diagnostics.hasErrors():
    return (true, "no diagnostics")
  var lines = @["diagnostics contained errors:"]
  for item in driver.diagnostics.items:
    if item.severity == dsError:
      lines.add item.property & ": " & item.message
  (false, lines.join("\n"))

proc expectVisible*(driver: CbssTestDriver; query: CbssQuery; expected = true): tuple[ok: bool, message: string] =
  let actual = driver.isVisible(query)
  if actual == expected:
    (true, "visibility matched for " & query.describe())
  else:
    (false, "visibility mismatch for " & query.describe() & ": expected " & $expected &
      ", got " & $actual & "\n" & driver.queryReport(query))

proc expectDispatched*(driver: CbssTestDriver; kind: InputEventKind; expected = true): tuple[ok: bool, message: string] =
  let actual = driver.dispatched(kind)
  if actual == expected:
    (true, "dispatch matched for " & $kind)
  else:
    (false, "dispatch mismatch for " & $kind & ": expected " & $expected &
      ", got " & $actual & "\n" & driver.dispatchSnapshot())

proc expectSelectedText*(driver: CbssTestDriver; query: CbssQuery; expected: string): tuple[ok: bool, message: string] =
  let actual = driver.selectedText(query)
  if actual == expected:
    (true, "selected text matched for " & query.describe())
  else:
    (false, "selected text mismatch for " & query.describe() & ": expected `" &
      expected & "`, got `" & actual & "`")

proc expectCaret*(driver: CbssTestDriver; query: CbssQuery; expected: int): tuple[ok: bool, message: string] =
  let actual = driver.caret(query)
  if actual.isSome and actual.get == expected:
    (true, "caret matched for " & query.describe())
  elif actual.isSome:
    (false, "caret mismatch for " & query.describe() & ": expected " & $expected &
      ", got " & $actual.get)
  else:
    (false, "caret missing for " & query.describe())

proc expectScrollYAtLeast*(driver: CbssTestDriver; query: CbssQuery; expected: float32): tuple[ok: bool, message: string] =
  let actual = driver.scrollY(query)
  if actual.isSome and actual.get >= expected:
    (true, "scroll-y matched for " & query.describe())
  elif actual.isSome:
    (false, "scroll-y mismatch for " & query.describe() & ": expected at least " &
      $expected & ", got " & $actual.get)
  else:
    (false, "scroll-y missing for " & query.describe())

proc boolAttribute(driver: CbssTestDriver; query: CbssQuery; name: string): bool =
  let value = driver.attribute(query, name)
  value.isSome and value.get == "true"

proc hasState*(driver: CbssTestDriver; query: CbssQuery; state: ElementState): bool =
  let target = driver.requireFirst(query)
  state in driver.ui.tree.nodes[target.nodeIndex].states

proc isOpen*(driver: CbssTestDriver; query: CbssQuery): bool =
  driver.hasState(query, esOpen)

proc isFocused*(driver: CbssTestDriver; query: CbssQuery): bool =
  let target = driver.requireFirst(query)
  driver.input.focusedTarget == some(target) or esFocus in driver.ui.tree.nodes[target.nodeIndex].states

proc isChecked*(driver: CbssTestDriver; query: CbssQuery): bool =
  driver.hasState(query, esChecked) or driver.boolAttribute(query, "checked")

proc isSelected*(driver: CbssTestDriver; query: CbssQuery): bool =
  driver.hasState(query, esSelected) or driver.boolAttribute(query, "selected")

proc isDisabled*(driver: CbssTestDriver; query: CbssQuery): bool =
  driver.hasState(query, esDisabled) or driver.boolAttribute(query, "disabled")

proc expectState*(driver: CbssTestDriver; query: CbssQuery; state: ElementState; expected = true): tuple[ok: bool, message: string] =
  let actual = driver.hasState(query, state)
  if actual == expected:
    (true, "state matched for " & query.describe() & ": " & $state)
  else:
    (false, "state mismatch for " & query.describe() & ": expected " & $expected &
      " for " & $state & ", got " & $actual)

proc expectFocused*(driver: CbssTestDriver; query: CbssQuery; expected = true): tuple[ok: bool, message: string] =
  let actual = driver.isFocused(query)
  if actual == expected:
    (true, "focus matched for " & query.describe())
  else:
    (false, "focus mismatch for " & query.describe() & ": expected " & $expected & ", got " & $actual)

proc expectChecked*(driver: CbssTestDriver; query: CbssQuery; expected = true): tuple[ok: bool, message: string] =
  let actual = driver.isChecked(query)
  if actual == expected:
    (true, "checked state matched for " & query.describe())
  else:
    (false, "checked mismatch for " & query.describe() & ": expected " & $expected & ", got " & $actual)

proc expectOpen*(driver: CbssTestDriver; query: CbssQuery; expected = true): tuple[ok: bool, message: string] =
  let actual = driver.isOpen(query)
  if actual == expected:
    (true, "open state matched for " & query.describe())
  else:
    (false, "open mismatch for " & query.describe() & ": expected " & $expected & ", got " & $actual)

proc expectClosed*(driver: CbssTestDriver; query: CbssQuery): tuple[ok: bool, message: string] =
  driver.expectOpen(query, expected = false)

proc expectHit*(driver: CbssTestDriver; point: Vec2; query: CbssQuery): tuple[ok: bool, message: string] =
  let actual = driver.hitAt(point)
  if actual.isSome and driver.ui.tree.matches(actual.get, query):
    (true, "hit matched " & query.describe())
  elif actual.isSome:
    (false, "hit mismatch: expected " & query.describe() & ", got " & driver.nodeLabel(actual.get))
  else:
    (false, "hit mismatch: expected " & query.describe() & ", got no target")

proc expectLayoutStable*(driver: CbssTestDriver; action: proc(): bool {.closure.}): tuple[ok: bool, message: string] =
  let before = driver.layoutSnapshot()
  discard action()
  let after = driver.layoutSnapshot()
  let diff = diffSnapshot(before, after)
  if diff.matches:
    (true, "layout stayed stable")
  else:
    (false, diff.message)

proc expectPaintStable*(driver: CbssTestDriver; action: proc(): bool {.closure.}): tuple[ok: bool, message: string] =
  let before = driver.paintSnapshot()
  discard action()
  let after = driver.paintSnapshot()
  let diff = diffSnapshot(before, after)
  if diff.matches:
    (true, "paint stayed stable")
  else:
    (false, diff.message)

proc paintCommandCount*(driver: CbssTestDriver; kind: PaintCommandKind): int =
  for command in driver.paintCommands:
    if command.kind == kind:
      inc result

proc diagnosticsOk*(driver: CbssTestDriver): bool =
  not driver.diagnostics.hasErrors()

proc paintCommandsOf*(driver: CbssTestDriver; kind: PaintCommandKind): seq[PaintCommand] =
  for command in driver.paintCommands:
    if command.kind == kind:
      result.add command

proc rectFor*(scope: CbssScope; query: CbssQuery): Option[Rect] =
  scope.driver.rectFor(scope.requireFirst(query))

proc centerFor*(scope: CbssScope; query: CbssQuery): Vec2 =
  scope.driver.centerFor(scope.requireFirst(query))

proc click*(scope: CbssScope; query: CbssQuery; button = 0): bool =
  scope.driver.click(scope.requireOne(query), button)

proc hover*(scope: CbssScope; query: CbssQuery): bool =
  scope.driver.hover(scope.centerFor(query))

proc drag*(scope: CbssScope; query: CbssQuery; delta: Vec2; steps = 8; button = 0): bool =
  let startPoint = scope.centerFor(query)
  scope.driver.drag(startPoint, vec2(startPoint.x + delta.x, startPoint.y + delta.y), steps, button)

proc focus*(scope: CbssScope; query: CbssQuery): bool =
  scope.driver.focus(scope.requireOne(query))

proc clear*(scope: CbssScope; query: CbssQuery): bool =
  if not scope.click(query):
    return false
  discard scope.driver.selectAll()
  discard scope.driver.press("Backspace")
  true

proc fill*(scope: CbssScope; query: CbssQuery; text: string): bool =
  if not scope.clear(query):
    return false
  scope.driver.paste(text)

proc chooseOption*(scope: CbssScope; selectQuery: CbssQuery; optionLabel: string): bool =
  if not scope.click(selectQuery):
    return false
  scope.driver.click(byText(optionLabel))

proc toggle*(scope: CbssScope; query: CbssQuery): bool =
  scope.click(query)

proc textContent*(scope: CbssScope; query: CbssQuery): string =
  scope.driver.textContent(node(scope.requireOne(query)))

proc value*(scope: CbssScope; query: CbssQuery): string =
  scope.driver.value(node(scope.requireOne(query)))

proc attribute*(scope: CbssScope; query: CbssQuery; name: string): Option[string] =
  scope.driver.attribute(node(scope.requireOne(query)), name)

proc isFocused*(scope: CbssScope; query: CbssQuery): bool =
  scope.driver.isFocused(node(scope.requireOne(query)))

proc isChecked*(scope: CbssScope; query: CbssQuery): bool =
  scope.driver.isChecked(node(scope.requireOne(query)))

proc isOpen*(scope: CbssScope; query: CbssQuery): bool =
  scope.driver.isOpen(node(scope.requireOne(query)))

proc expectExists*(scope: CbssScope; query: CbssQuery): tuple[ok: bool, message: string] =
  if scope.exists(query):
    (true, "scoped query matched: " & query.describe())
  else:
    (false, scope.queryReport(query))

proc expectUnique*(scope: CbssScope; query: CbssQuery): tuple[ok: bool, message: string] =
  let matches = scope.count(query)
  if matches == 1:
    (true, "scoped query matched one node: " & query.describe())
  else:
    (false, "scoped query expected one match but found " & $matches & "\n" & scope.queryReport(query))

proc expectValue*(scope: CbssScope; query: CbssQuery; expected: string): tuple[ok: bool, message: string] =
  let actual = scope.value(query)
  if actual == expected:
    (true, "value matched for scoped " & query.describe())
  else:
    (false, "value mismatch for scoped " & query.describe() & ": expected `" & expected & "`, got `" & actual & "`")

proc expectVisible*(scope: CbssScope; query: CbssQuery; expected = true): tuple[ok: bool, message: string] =
  let actual = scope.driver.isVisible(node(scope.requireOne(query)))
  if actual == expected:
    (true, "visibility matched for scoped " & query.describe())
  else:
    (false, "visibility mismatch for scoped " & query.describe() & ": expected " &
      $expected & ", got " & $actual & "\n" & scope.queryReport(query))

proc expectChecked*(scope: CbssScope; query: CbssQuery; expected = true): tuple[ok: bool, message: string] =
  let actual = scope.isChecked(query)
  if actual == expected:
    (true, "checked state matched for scoped " & query.describe())
  else:
    (false, "checked mismatch for scoped " & query.describe() & ": expected " &
      $expected & ", got " & $actual)

proc waitFor*(driver: CbssTestDriver; condition: proc(): bool {.closure.}; ticks = 8): tuple[ok: bool, message: string] =
  let maxTicks =
    if ticks < 1: 1
    else: ticks
  for index in 0 ..< maxTicks:
    driver.refresh()
    if condition():
      return (true, "condition matched at tick " & $index)
  (false, "condition did not match after " & $maxTicks & " ticks")

proc waitForExists*(driver: CbssTestDriver; query: CbssQuery; ticks = 8): tuple[ok: bool, message: string] =
  let waited = driver.waitFor(proc(): bool =
    driver.exists(query)
  , ticks = ticks)
  if waited.ok:
    return (true, "query matched after wait: " & query.describe())
  (false, waited.message & "\n" & driver.queryReport(query))

proc waitForValue*(driver: CbssTestDriver; query: CbssQuery; expected: string; ticks = 8): tuple[ok: bool, message: string] =
  let waited = driver.waitFor(proc(): bool =
    driver.exists(query) and driver.value(query) == expected
  , ticks = ticks)
  if waited.ok:
    return (true, "value matched after wait for " & query.describe())
  let actual =
    if driver.exists(query): driver.value(query)
    else: "<missing>"
  (false, waited.message & "\nvalue mismatch for " & query.describe() &
    ": expected `" & expected & "`, got `" & actual & "`")

proc waitForDispatched*(driver: CbssTestDriver; kind: InputEventKind; ticks = 8): tuple[ok: bool, message: string] =
  let waited = driver.waitFor(proc(): bool =
    driver.dispatched(kind)
  , ticks = ticks)
  if waited.ok:
    return (true, "dispatch observed after wait: " & $kind)
  (false, waited.message & "\n" & driver.dispatchSnapshot())

proc waitFor*(scope: CbssScope; condition: proc(): bool {.closure.}; ticks = 8): tuple[ok: bool, message: string] =
  scope.driver.waitFor(condition, ticks = ticks)

proc waitForExists*(scope: CbssScope; query: CbssQuery; ticks = 8): tuple[ok: bool, message: string] =
  let waited = scope.waitFor(proc(): bool =
    scope.exists(query)
  , ticks = ticks)
  if waited.ok:
    return (true, "scoped query matched after wait: " & query.describe())
  (false, waited.message & "\n" & scope.queryReport(query))

proc waitForValue*(scope: CbssScope; query: CbssQuery; expected: string; ticks = 8): tuple[ok: bool, message: string] =
  let waited = scope.waitFor(proc(): bool =
    scope.exists(query) and scope.value(query) == expected
  , ticks = ticks)
  if waited.ok:
    return (true, "scoped value matched after wait for " & query.describe())
  let actual =
    if scope.exists(query): scope.value(query)
    else: "<missing>"
  (false, waited.message & "\nscoped value mismatch for " & query.describe() &
    ": expected `" & expected & "`, got `" & actual & "`")
