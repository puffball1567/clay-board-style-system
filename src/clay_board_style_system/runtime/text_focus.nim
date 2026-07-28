import std/options

import ../core/[declaration, geometry, node, rule, selector, style_value]
import ../hit/hit_test
import ../input/events
import ./[focus, ui_root]

proc isTextInputTarget*(ui: UiRoot; target: NodeId): bool =
  target.nodeIndex >= 0 and target.nodeIndex < ui.tree.nodes.len and
    (ui.tree.nodes[target.nodeIndex].hasGroup("text-input") or
      ui.tree.nodes[target.nodeIndex].hasGroup("textarea"))

proc isValidTextInputTarget*(ui: UiRoot; target: NodeId): bool =
  target.nodeIndex >= 0 and target.nodeIndex < ui.tree.nodes.len and
    ui.isTextInputTarget(target) and
    esDisabled notin ui.tree.nodes[target.nodeIndex].states

proc inputTargetForHit*(ui: UiRoot; target: Option[NodeId]): Option[NodeId] =
  var current = target
  while current.isSome:
    let id = current.get
    if ui.isTextInputTarget(id):
      if ui.isValidTextInputTarget(id):
        return some(id)
      return none(NodeId)
    current = ui.tree.nodes[id.nodeIndex].parent
  none(NodeId)

proc isTextControlChromeHit*(ui: UiRoot; target: Option[NodeId]): bool =
  var current = target
  while current.isSome:
    let id = current.get
    if id.nodeIndex >= 0 and id.nodeIndex < ui.tree.nodes.len:
      let node = ui.tree.nodes[id.nodeIndex]
      if node.hasGroup("textarea-resize-handle") or
          node.hasGroup("textarea-scrollbar-track") or
          node.hasGroup("textarea-scrollbar-thumb"):
        return true
    current = ui.tree.nodes[id.nodeIndex].parent
  false

proc textControlHitAtPoint*(
    ui: UiRoot;
    regions: openArray[HitRegion];
    point: Vec2
): Option[HitTestResult] =
  var bestTarget = none(NodeId)
  var bestRect = rect(0, 0, 0, 0)
  var bestArea = 0.0'f32
  for region in regions:
    if not region.rect.contains(point):
      continue
    let target = ui.inputTargetForHit(some(region.node))
    if target.isNone or ui.isTextControlChromeHit(some(region.node)):
      continue
    var targetRect = region.rect
    for candidate in regions:
      if candidate.node == target.get:
        targetRect = candidate.rect
        break
    let area = targetRect.w * targetRect.h
    if bestTarget.isNone or area < bestArea:
      bestTarget = target
      bestRect = targetRect
      bestArea = area
  if bestTarget.isSome:
    return some(HitTestResult(
      node: bestTarget.get,
      local: vec2(point.x - bestRect.x, point.y - bestRect.y)
    ))
  none(HitTestResult)

proc localForNodeAtPoint(
    regions: openArray[HitRegion];
    target: NodeId;
    point: Vec2
): Option[Vec2] =
  for region in regions:
    if region.node == target:
      return some(vec2(point.x - region.rect.x, point.y - region.rect.y))
  none(Vec2)

proc normalizeTextControlDispatches*(
    ui: UiRoot;
    regions: openArray[HitRegion];
    dispatches: var seq[DispatchResult]
) =
  for dispatch in dispatches.mitems:
    if dispatch.event.kind notin {iekPointerMove, iekPointerDown, iekPointerUp, iekDrag, iekDragOver}:
      continue
    if dispatch.event.position.isNone:
      continue
    if dispatch.event.kind == iekDrag and dispatch.target.isSome and ui.isTextInputTarget(dispatch.target.get):
      let local = localForNodeAtPoint(regions, dispatch.target.get, dispatch.event.position.get)
      if local.isSome:
        dispatch.local = local
      continue
    let textHit = ui.textControlHitAtPoint(regions, dispatch.event.position.get)
    if textHit.isSome:
      dispatch.target = some(textHit.get.node)
      dispatch.local = some(textHit.get.local)

proc isTextCaretNode*(ui: UiRoot; id: NodeId): bool =
  id.nodeIndex >= 0 and id.nodeIndex < ui.tree.nodes.len and
    (ui.tree.nodes[id.nodeIndex].hasGroup("text-input-caret") or
      ui.tree.nodes[id.nodeIndex].hasGroup("textarea-caret"))

proc collectCaretNodes(ui: UiRoot; id: NodeId; output: var seq[NodeId]) =
  if id.nodeIndex < 0 or id.nodeIndex >= ui.tree.nodes.len:
    return
  if ui.isTextCaretNode(id):
    output.add id
  for child in ui.tree.nodes[id.nodeIndex].children:
    ui.collectCaretNodes(child, output)

proc caretNodesForTarget*(ui: UiRoot; target: NodeId): seq[NodeId] =
  ui.collectCaretNodes(target, result)

proc caretBlinkSheet*(ui: UiRoot; target: NodeId; visible: bool): StyleSheet =
  var rules: seq[StyleRule] = @[]
  let opacityValue = if visible: 1.0'f32 else: 0.0'f32
  for caretNode in ui.caretNodesForTarget(target):
    rules.add rule(
      target(caretNode),
      [decl("opacity", number(opacityValue))],
      priority = 1000
    )
  styleSheet(rules)

proc setCaretBlinkVisible*(
    ui: UiRoot;
    inputState: InteractionState;
    blinkSheetIndex: var Option[int];
    visible: bool
): bool =
  if inputState.focusedTarget.isNone or not ui.isTextInputTarget(inputState.focusedTarget.get):
    return false
  let sheet = ui.caretBlinkSheet(inputState.focusedTarget.get, visible)
  if sheet.rules.len == 0:
    return false
  if blinkSheetIndex.isSome and blinkSheetIndex.get < ui.componentStyles.len:
    ui.componentStyles[blinkSheetIndex.get] = sheet
  else:
    ui.componentStyles.add sheet
    blinkSheetIndex = some(ui.componentStyles.len - 1)
  true

proc clearCaretBlinkSheet*(ui: UiRoot; blinkSheetIndex: var Option[int]) =
  if blinkSheetIndex.isSome and blinkSheetIndex.get < ui.componentStyles.len:
    ui.componentStyles[blinkSheetIndex.get] = styleSheet([])
  blinkSheetIndex = none(int)

proc moveFocusedTextControlCaretToEnd*(ui: UiRoot; target: NodeId) =
  discard ui.events.emit(ui.tree, target, keyDownEvent("End", ctrlKey = true))

proc moveTextControlFocus*(
    ui: UiRoot;
    inputState: var InteractionState;
    direction: int
): bool =
  result = ui.moveFocus(inputState, direction)
  if result and inputState.focusedTarget.isSome and
      ui.isTextInputTarget(inputState.focusedTarget.get):
    ui.moveFocusedTextControlCaretToEnd(inputState.focusedTarget.get)

proc normalizeTextControlFocus*(ui: UiRoot; inputState: var InteractionState; hitTarget: Option[NodeId]) =
  discard ui.normalizeFocus(inputState, hitTarget)
