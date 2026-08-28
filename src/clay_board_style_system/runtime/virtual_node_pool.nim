## Stable-key materialization for a bounded `VirtualRangePlan`.
##
## A pool owns every direct child of one dedicated host Box. Nodes whose keys
## remain materialized retain their generation-checked identity; nodes leaving
## the range are disposed through `UiRoot`, and newly visible keys are mounted
## through one caller-provided factory. This is retained reconciliation, not
## virtual-DOM replay.
import std/[options, sets, tables]

import ../core/node
import ../input/events
import ./invalidation
import ./ui_root
import ./virtual_focus
import ./virtualization

type
  VirtualNodeBinding*[Key] = object
    key*: Key
    index*: int
    geometry*: VirtualItemGeometry
    node*: NodeHandle

  VirtualNodePool*[Key] = object
    entries: seq[VirtualNodeBinding[Key]]

  VirtualNodeMountProc*[Key] = proc(
    index: int;
    key: Key;
    geometry: VirtualItemGeometry
  ): NodeHandle {.closure.}

  VirtualNodeRefreshProc*[Key] = proc(
    node: NodeHandle;
    index: int;
    key: Key;
    geometry: VirtualItemGeometry
  ) {.closure.}

  VirtualNodeReconcileResult* = object
    retained*: int
    mounted*: int
    disposed*: int
    reordered*: bool

proc initVirtualNodePool*[Key](): VirtualNodePool[Key] =
  VirtualNodePool[Key](entries: @[])

proc len*[Key](pool: VirtualNodePool[Key]): int {.inline.} =
  pool.entries.len

proc bindings*[Key](pool: VirtualNodePool[Key]): lent seq[VirtualNodeBinding[Key]] =
  pool.entries

proc nodeForKey*[Key](
    pool: VirtualNodePool[Key];
    key: Key
): Option[NodeHandle] =
  for entry in pool.entries:
    if entry.key == key:
      return some(entry.node)
  none(NodeHandle)

proc validatePlanAndKeys[Key](
    plan: VirtualRangePlan;
    keys: openArray[Key]
) =
  if keys.len != plan.items.len:
    raise newException(
      ValueError,
      "virtual key count must match the materialized geometry count"
    )
  if plan.materialized.lastExclusive - plan.materialized.first != plan.items.len:
    raise newException(ValueError, "virtual plan has inconsistent materialized geometry")

  var seen = initHashSet[Key]()
  for position, item in plan.items:
    if item.index != plan.materialized.first + position or
        item.index < 0 or item.index >= plan.itemCount:
      raise newException(ValueError, "virtual plan item indices must be contiguous and in range")
    if keys[position] in seen:
      raise newException(ValueError, "virtual item keys must be unique within a materialized range")
    seen.incl keys[position]

proc validateHost[Key](
    pool: VirtualNodePool[Key];
    root: UiRoot;
    host: NodeHandle
) =
  if root.isNil or host.root != root or not host.valid:
    raise newException(ValueError, "virtual node host does not belong to this UiRoot")
  let children = root.tree.nodes[host.id.nodeIndex].children
  if children.len != pool.entries.len:
    raise newException(ValueError, "virtual node host must contain only nodes owned by its pool")

  var expected = initHashSet[NodeId]()
  var keys = initHashSet[Key]()
  for entry in pool.entries:
    if entry.key in keys:
      raise newException(ValueError, "virtual node pool contains a duplicate stable key")
    keys.incl entry.key
    if entry.node.root != root or not entry.node.valid or
        root.tree.nodes[entry.node.id.nodeIndex].parent != some(host.id):
      raise newException(ValueError, "virtual node pool contains a stale or foreign node")
    if entry.node.id in expected:
      raise newException(ValueError, "virtual node pool contains a duplicate node")
    expected.incl entry.node.id
  for child in children:
    if child notin expected:
      raise newException(ValueError, "virtual node host contains a node not owned by its pool")

proc addedChildren(
    root: UiRoot;
    host: NodeHandle;
    before: HashSet[NodeId]
): seq[NodeHandle] =
  if root.isNil or not host.valid:
    return
  for child in root.tree.nodes[host.id.nodeIndex].children:
    if child notin before and root.tree.isValid(child):
      result.add NodeHandle(root: root, id: child)

proc disposeAll(
    root: UiRoot;
    nodes: openArray[NodeHandle];
    interaction: var InteractionState
): ref CatchableError =
  for node in nodes:
    if not node.valid:
      continue
    try:
      discard root.disposeSubtree(node, interaction)
    except CatchableError as error:
      if result.isNil:
        result = error

proc mountOne[Key](
    root: UiRoot;
    host: NodeHandle;
    interaction: var InteractionState;
    index: int;
    key: Key;
    geometry: VirtualItemGeometry;
    mount: VirtualNodeMountProc[Key]
): NodeHandle =
  var before = initHashSet[NodeId]()
  for child in root.tree.nodes[host.id.nodeIndex].children:
    before.incl child

  var callbackFailure: ref CatchableError
  root.pushParent(host)
  try:
    result = mount(index, key, geometry)
  except CatchableError as error:
    callbackFailure = error
  finally:
    root.popParent()

  let added = root.addedChildren(host, before)
  let validResult = callbackFailure.isNil and result.root == root and result.valid and
    root.tree.nodes[result.id.nodeIndex].parent == some(host.id) and
    added.len == 1 and added[0].id == result.id
  if not validResult:
    let cleanupFailure = root.disposeAll(added, interaction)
    if not callbackFailure.isNil:
      raise callbackFailure
    if not cleanupFailure.isNil:
      raise cleanupFailure
    raise newException(
      ValueError,
      "virtual mount must create and return exactly one direct child of its host"
    )

proc reconcileVirtualNodes*[Key](
    pool: var VirtualNodePool[Key];
    root: UiRoot;
    host: NodeHandle;
    interaction: var InteractionState;
    plan: VirtualRangePlan;
    keys: openArray[Key];
    mount: VirtualNodeMountProc[Key];
    refresh: VirtualNodeRefreshProc[Key] = nil;
    focusMemory: VirtualFocusMemory[Key] = nil
): VirtualNodeReconcileResult =
  ## Reconcile a bounded materialized range by stable key. The host is an
  ## exclusive item container; leading/trailing spacers belong outside it.
  ## `refresh`, when supplied, patches retained nodes after all new mounts have
  ## succeeded. It should use normal retained mutation APIs and may invalidate
  ## only the domains affected by its data change. Neither callback may add,
  ## remove, or reparent other direct children of the dedicated host.
  if mount.isNil:
    raise newException(ValueError, "virtual node mount callback cannot be nil")
  validatePlanAndKeys(plan, keys)
  pool.validateHost(root, host)
  if not focusMemory.isNil:
    discard focusMemory.cancelSupersededVirtualFocus(interaction)

  var oldByKey = initTable[Key, int]()
  for index, entry in pool.entries:
    oldByKey[entry.key] = index
  var retainedOld = newSeq[bool](pool.entries.len)
  var nextEntries = newSeqOfCap[VirtualNodeBinding[Key]](keys.len)
  var newlyMounted: seq[NodeHandle]

  try:
    for position, key in keys:
      let geometry = plan.items[position]
      if key in oldByKey:
        let oldIndex = oldByKey[key]
        retainedOld[oldIndex] = true
        var entry = pool.entries[oldIndex]
        entry.index = geometry.index
        entry.geometry = geometry
        nextEntries.add entry
        inc result.retained
      else:
        let node = root.mountOne(
          host, interaction, geometry.index, key, geometry, mount
        )
        newlyMounted.add node
        nextEntries.add VirtualNodeBinding[Key](
          key: key,
          index: geometry.index,
          geometry: geometry,
          node: node
        )
        inc result.mounted

    if not refresh.isNil:
      for entry in nextEntries:
        if entry.key in oldByKey:
          refresh(entry.node, entry.index, entry.key, entry.geometry)

    for entry in nextEntries:
      entry.node.setAccessibleSetPosition(
        some(entry.index + 1),
        some(plan.itemCount)
      )
  except CatchableError:
    let failure = getCurrentException()
    discard root.disposeAll(newlyMounted, interaction)
    raise failure

  var stale = newSeqOfCap[NodeHandle](pool.entries.len - result.retained)
  for index, entry in pool.entries:
    if not retainedOld[index]:
      stale.add entry.node
  result.disposed = stale.len

  var capturedFocus = false
  if not focusMemory.isNil and interaction.focusedTarget.isSome:
    for index, entry in pool.entries:
      if not retainedOld[index] and focusMemory.captureVirtualFocus(
          root, interaction, entry.key, entry.node
      ):
        capturedFocus = true
        break

  # Publish the valid retained/new set before teardown callbacks run. Even if a
  # user unmount hook fails, the pool never points at a generation that teardown
  # has already retired.
  pool.entries = nextEntries
  let unmountFailure = root.disposeAll(stale, interaction)
  if capturedFocus:
    focusMemory.armVirtualFocus(interaction)

  var ordered = newSeqOfCap[NodeId](pool.entries.len)
  for entry in pool.entries:
    ordered.add entry.node.id
  result.reordered = root.tree.reorderChildren(host.id, ordered)
  if result.mounted > 0 or result.disposed > 0 or result.reordered:
    root.invalidate(host.id, {ddLayout, ddPaint, ddHit})

  if not focusMemory.isNil:
    for entry in pool.entries:
      if focusMemory.restoreVirtualFocus(root, interaction, entry.key, entry.node):
        break

  if not unmountFailure.isNil:
    raise unmountFailure

proc clearVirtualNodes*[Key](
    pool: var VirtualNodePool[Key];
    root: UiRoot;
    host: NodeHandle;
    interaction: var InteractionState;
    focusMemory: VirtualFocusMemory[Key] = nil
): int {.discardable.} =
  pool.validateHost(root, host)
  var nodes = newSeqOfCap[NodeHandle](pool.entries.len)
  for entry in pool.entries:
    nodes.add entry.node
  result = nodes.len
  var capturedFocus = false
  if not focusMemory.isNil:
    discard focusMemory.cancelSupersededVirtualFocus(interaction)
    for entry in pool.entries:
      if focusMemory.captureVirtualFocus(
          root, interaction, entry.key, entry.node
      ):
        capturedFocus = true
        break
  pool.entries.setLen(0)
  let unmountFailure = root.disposeAll(nodes, interaction)
  if capturedFocus:
    focusMemory.armVirtualFocus(interaction)
  discard root.tree.reorderChildren(host.id, [])
  if result > 0:
    root.invalidate(host.id, {ddLayout, ddPaint, ddHit})
  if not unmountFailure.isNil:
    raise unmountFailure
