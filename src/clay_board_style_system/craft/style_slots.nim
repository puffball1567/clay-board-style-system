import std/[algorithm, options, sets]

import ../core/[node, rule]
import ./style

type
  PublicStyleSlot* = object
    owner*: NodeId
    target*: NodeId
    component*: string
    name*: string

  CraftStyleReplacementDiagnosticCode* = enum
    csrUnsupportedRuleTarget,
    csrUndeclaredStyleSlot,
    csrInvalidStyleSlot,
    csrInvalidCraftStyle

  CraftStyleReplacementDiagnostic* = object
    code*: CraftStyleReplacementDiagnosticCode
    path*: string
    message*: string

  CraftStyleReplacementResult* = object
    applied*: bool
    diagnostics*: seq[CraftStyleReplacementDiagnostic]
    affectedNodes*: seq[NodeId]

  CraftStyleLoadResult* = object
    applied*: bool
    parseDiagnostics*: seq[CraftStyleDiagnostic]
    replacementDiagnostics*: seq[CraftStyleReplacementDiagnostic]
    affectedNodes*: seq[NodeId]

  ActiveCraftStyle = object
    value: CraftStyle
    sheet: StyleSheet
    targets: seq[NodeId]

  CraftStyleSlotRuntime* = object
    slots: seq[PublicStyleSlot]
    activeStyles: seq[ActiveCraftStyle]

proc initCraftStyleSlotRuntime*(): CraftStyleSlotRuntime =
  CraftStyleSlotRuntime(slots: @[], activeStyles: @[])

proc addDiagnostic(
    result: var CraftStyleReplacementResult;
    code: CraftStyleReplacementDiagnosticCode;
    path, message: string
) =
  result.diagnostics.add CraftStyleReplacementDiagnostic(
    code: code,
    path: path,
    message: message
  )

proc publicStyleSlots*(runtime: CraftStyleSlotRuntime): seq[PublicStyleSlot] =
  runtime.slots

proc craftStyleSheets*(runtime: CraftStyleSlotRuntime): seq[StyleSheet] =
  for active in runtime.activeStyles:
    result.add active.sheet

proc activeCraftStyleNames*(runtime: CraftStyleSlotRuntime): seq[string] =
  for active in runtime.activeStyles:
    result.add active.value.name

proc targetsPublicStyleSlot*(
    runtime: CraftStyleSlotRuntime;
    component, name: string
): bool =
  for active in runtime.activeStyles:
    for target in active.value.targets:
      if target.component == some(component) and target.slot == some(name):
        return true

proc compileForSlots(
    runtime: CraftStyleSlotRuntime;
    tree: Tree;
    style: CraftStyle;
    requireMountedTarget: bool
): tuple[
    sheet: StyleSheet,
    targets: seq[NodeId],
    diagnostics: seq[CraftStyleReplacementDiagnostic]
] =
  if style.targets.len != style.sheet.rules.len:
    result.diagnostics.add CraftStyleReplacementDiagnostic(
      code: csrInvalidCraftStyle,
      path: "$.rules",
      message: "Craft Style rule and target metadata counts differ"
    )
    return

  var targetSet = initHashSet[NodeId]()
  for ruleIndex, item in style.sheet.rules:
    let target = style.targets[ruleIndex]
    let path = "$.rules[" & $ruleIndex & "].selector"
    if target.component.isNone or target.slot.isNone:
      result.diagnostics.add CraftStyleReplacementDiagnostic(
        code: csrUnsupportedRuleTarget,
        path: path,
        message: "replaceable Craft Style rules require component and slot selectors"
      )
      continue

    var matched = false
    for binding in runtime.slots:
      if binding.component != target.component.get or
          binding.name != target.slot.get or
          not tree.isValid(binding.owner) or
          not tree.isValid(binding.target):
        continue
      matched = true
      var condition = item.selector
      condition.nodeId = some(binding.target)
      result.sheet.rules.add rule(
        condition,
        item.declarations,
        priority = item.priority,
        sourceOrder = item.sourceOrder,
        cascadeLayer = -1
      )
      targetSet.incl binding.target

    if requireMountedTarget and not matched:
      result.diagnostics.add CraftStyleReplacementDiagnostic(
        code: csrUndeclaredStyleSlot,
        path: path,
        message: "no mounted component declares public Style Slot '" &
          target.component.get & "." & target.slot.get & "'"
      )

  for target in targetSet:
    result.targets.add target
  result.targets.sort(proc(a, b: NodeId): int = cmp(a.nodeIndex, b.nodeIndex))

proc refreshActiveStyles(runtime: var CraftStyleSlotRuntime; tree: Tree) =
  for active in runtime.activeStyles.mitems:
    let compiled = runtime.compileForSlots(
      tree,
      active.value,
      requireMountedTarget = false
    )
    active.sheet = compiled.sheet
    active.targets = compiled.targets

proc exposePublicStyleSlot*(
    runtime: var CraftStyleSlotRuntime;
    tree: Tree;
    owner, target: NodeId;
    component, name: string
): bool {.discardable.} =
  if component.len == 0 or name.len == 0:
    raise newException(ValueError, "public Style Slot names cannot be empty")
  if not tree.isValid(owner) or not tree.isValid(target):
    raise newException(ValueError, "public Style Slot nodes must be alive")
  if not tree.isDescendantOrSelf(target, owner):
    raise newException(
      ValueError,
      "public Style Slot target must belong to its component subtree"
    )
  for slot in runtime.slots:
    if slot.owner == owner and slot.component != component:
      raise newException(
        ValueError,
        "a mounted component cannot expose multiple Craft component names"
      )
    if slot.owner == owner and slot.target == target and
        slot.component == component and slot.name == name:
      return false
  runtime.slots.add PublicStyleSlot(
    owner: owner,
    target: target,
    component: component,
    name: name
  )
  runtime.refreshActiveStyles(tree)
  true

proc removePublicStyleSlots*(
    runtime: var CraftStyleSlotRuntime;
    tree: Tree;
    removed: HashSet[NodeId]
): seq[NodeId] =
  var affected = initHashSet[NodeId]()
  var retained = newSeqOfCap[PublicStyleSlot](runtime.slots.len)
  for slot in runtime.slots:
    if slot.owner in removed or slot.target in removed:
      affected.incl slot.target
    else:
      retained.add slot
  if retained.len == runtime.slots.len:
    return
  runtime.slots = retained
  runtime.refreshActiveStyles(tree)
  for target in affected:
    result.add target

proc replaceCraftStyle*(
    runtime: var CraftStyleSlotRuntime;
    tree: Tree;
    style: CraftStyle
): CraftStyleReplacementResult =
  if style.name.len == 0:
    result.addDiagnostic(
      csrInvalidCraftStyle,
      "$.name",
      "Craft Style name cannot be empty"
    )
    return

  let compiled = runtime.compileForSlots(
    tree,
    style,
    requireMountedTarget = true
  )
  result.diagnostics = compiled.diagnostics
  if result.diagnostics.len > 0:
    return

  var affected = initHashSet[NodeId]()
  var replacementIndex = -1
  for index, active in runtime.activeStyles:
    if active.value.name == style.name:
      replacementIndex = index
      for target in active.targets:
        affected.incl target
      break
  for target in compiled.targets:
    affected.incl target

  let replacement = ActiveCraftStyle(
    value: style,
    sheet: compiled.sheet,
    targets: compiled.targets
  )
  if replacementIndex >= 0:
    runtime.activeStyles[replacementIndex] = replacement
  else:
    runtime.activeStyles.add replacement

  for target in affected:
    result.affectedNodes.add target
  result.affectedNodes.sort(proc(a, b: NodeId): int = cmp(a.nodeIndex, b.nodeIndex))
  result.applied = true

proc replaceCraftStyle*(
    runtime: var CraftStyleSlotRuntime;
    tree: Tree;
    source: string
): CraftStyleLoadResult =
  let parsed = parseCraftStyle(source)
  result.parseDiagnostics = parsed.diagnostics
  if not parsed.isOk:
    return
  let replacement = runtime.replaceCraftStyle(tree, parsed.value.get)
  result.applied = replacement.applied
  result.replacementDiagnostics = replacement.diagnostics
  result.affectedNodes = replacement.affectedNodes

proc removeCraftStyle*(
    runtime: var CraftStyleSlotRuntime;
    name: string
): tuple[removed: bool, targets: seq[NodeId]] =
  for index, active in runtime.activeStyles:
    if active.value.name != name:
      continue
    result.removed = true
    result.targets = active.targets
    runtime.activeStyles.delete(index)
    return
