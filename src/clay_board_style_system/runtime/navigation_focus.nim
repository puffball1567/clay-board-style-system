import std/[options, sets, tables]

import ../core/node
import ../input/events
import ./[focus, navigation, ui_root]

type
  NavigationFocusMemory* = ref object
    savedFocus: Table[NavigationEntryId, NodeId]
    pendingEntryId: Option[NavigationEntryId]

proc initNavigationFocusMemory*(): NavigationFocusMemory =
  NavigationFocusMemory(
    savedFocus: initTable[NavigationEntryId, NodeId](),
    pendingEntryId: none(NavigationEntryId)
  )

proc pendingEntry*(memory: NavigationFocusMemory): Option[NavigationEntryId] =
  memory.pendingEntryId

proc rememberedEntryCount*(memory: NavigationFocusMemory): int =
  memory.savedFocus.len

proc rememberFocus*(
    memory: NavigationFocusMemory;
    entry: NavigationEntryId;
    target: NodeId
) =
  memory.savedFocus[entry] = target

proc forgetFocus*(memory: NavigationFocusMemory; entry: NavigationEntryId) =
  memory.savedFocus.del(entry)

proc clear*(memory: NavigationFocusMemory) =
  memory.savedFocus.clear()
  memory.pendingEntryId = none(NavigationEntryId)

proc requestRestore*(
    memory: NavigationFocusMemory;
    entry: NavigationEntryId
) =
  memory.pendingEntryId = some(entry)

proc retainEntries*[Destination](
    memory: NavigationFocusMemory;
    snapshot: NavigationSnapshot[Destination]
) =
  var retained = initHashSet[NavigationEntryId]()
  for entry in snapshot.entries:
    retained.incl entry.id
  var stale: seq[NavigationEntryId]
  for entry in memory.savedFocus.keys:
    if entry notin retained:
      stale.add entry
  for entry in stale:
    memory.savedFocus.del(entry)

proc captureFocus*[Destination](
    memory: NavigationFocusMemory;
    change: NavigationChange[Destination];
    interaction: InteractionState
) =
  if change.previous.isSome and interaction.focusedTarget.isSome:
    memory.rememberFocus(
      change.previous.get.id,
      interaction.focusedTarget.get
    )
  case change.kind
  of nckReplace:
    if change.previous.isSome:
      memory.forgetFocus(change.previous.get.id)
  of nckPush:
    memory.retainEntries(change.snapshot)
  of nckBack, nckForward:
    discard
  memory.pendingEntryId =
    if change.current.isSome: some(change.current.get.id)
    else: none(NavigationEntryId)

proc validScreenTarget(
    ui: UiRoot;
    screenRoot: NodeId;
    target: NodeId
): bool =
  ui.tree.isDescendantOrSelf(target, screenRoot) and ui.tree.isFocusable(target)

proc scanFirstScreenFocusTarget(
    ui: UiRoot;
    id: NodeId;
    positiveTarget: var Option[NodeId];
    positiveTabIndex: var int;
    zeroTarget: var Option[NodeId]
) =
  if not ui.tree.isValid(id):
    return
  if ui.tree.isFocusable(id, forTraversal = true):
    let tabIndex = ui.tree.nodes[id.nodeIndex].tabIndex
    if tabIndex > 0 and
        (positiveTarget.isNone or tabIndex < positiveTabIndex or
          (tabIndex == positiveTabIndex and
            id.nodeIndex < positiveTarget.get.nodeIndex)):
      positiveTarget = some(id)
      positiveTabIndex = tabIndex
    elif tabIndex == 0 and
        (zeroTarget.isNone or id.nodeIndex < zeroTarget.get.nodeIndex):
      zeroTarget = some(id)
  for child in ui.tree.nodes[id.nodeIndex].children:
    ui.scanFirstScreenFocusTarget(
      child,
      positiveTarget,
      positiveTabIndex,
      zeroTarget
    )

proc firstScreenFocusTarget(ui: UiRoot; screenRoot: NodeId): Option[NodeId] =
  if not ui.tree.isValid(screenRoot):
    return none(NodeId)
  var positiveTarget = none(NodeId)
  var positiveTabIndex = int.high
  var zeroTarget = none(NodeId)
  ui.scanFirstScreenFocusTarget(
    screenRoot,
    positiveTarget,
    positiveTabIndex,
    zeroTarget
  )
  if positiveTarget.isSome: positiveTarget else: zeroTarget

proc restoreFocus*(
    memory: NavigationFocusMemory;
    ui: UiRoot;
    interaction: var InteractionState;
    screenRoot: NodeHandle;
    fallback = none(NodeHandle)
): bool {.discardable.} =
  if screenRoot.root != ui:
    raise newException(ValueError, "navigation screen root belongs to another UiRoot")
  if fallback.isSome and fallback.get.root != ui:
    raise newException(ValueError, "navigation focus fallback belongs to another UiRoot")
  if memory.pendingEntryId.isNone:
    return false

  let entryId = memory.pendingEntryId.get
  memory.pendingEntryId = none(NavigationEntryId)
  var target = none(NodeId)

  if memory.savedFocus.hasKey(entryId):
    let saved = memory.savedFocus[entryId]
    if ui.validScreenTarget(screenRoot.id, saved):
      target = some(saved)
    else:
      memory.savedFocus.del(entryId)

  if target.isNone and fallback.isSome and
      ui.validScreenTarget(screenRoot.id, fallback.get.id):
    target = some(fallback.get.id)

  if target.isNone:
    target = ui.firstScreenFocusTarget(screenRoot.id)

  ui.setFocus(interaction, target, focusVisible = true)
