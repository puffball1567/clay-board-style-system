import std/[options, unittest]

import clay_board_style_system

type VirtualRow = ref object of CBSSComponent
  key: string
  mountedKeys: ref seq[string]
  unmountedKeys: ref seq[string]

type FailingUnmountRow = ref object of CBSSComponent
  key: int
  failOnUnmount: bool

proc render(self: VirtualRow) =
  ui.box(self):
    ui.text(self.key)

method onMount(self: VirtualRow) =
  self.mountedKeys[].add self.key

method onUnmount(self: VirtualRow) =
  self.unmountedKeys[].add self.key

proc render(self: FailingUnmountRow) =
  ui.box(self):
    ui.text($self.key)

method onUnmount(self: FailingUnmountRow) =
  if self.failOnUnmount:
    raise newException(ValueError, "unmount failed")

proc planAt(offset: float32; itemCount = 100): VirtualRangePlan =
  planVirtualRange(
    itemCount,
    virtualViewport(offset, 30),
    virtualizationConfig(
      estimatedItemExtent = 10,
      maxMaterializedItems = 8
    )
  )

proc keysFor(plan: VirtualRangePlan): seq[string] =
  for item in plan.items:
    result.add "item-" & $item.index

proc nodeIds[Key](pool: VirtualNodePool[Key]): seq[NodeId] =
  for entry in pool.bindings:
    result.add entry.node.id

proc accessibleNodeFor(
    nodes: openArray[AccessibleNode];
    id: NodeId
): Option[AccessibleNode] =
  for node in nodes:
    if node.node == id:
      return some(node)
  none(AccessibleNode)

suite "stable-key virtual node pool":
  test "forward and reverse ranges retain keyed nodes and restore child order":
    let root = initUiRoot()
    let host = root.box(id = "host")
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[string]()
    var mountCalls = 0
    let mount = proc(index: int; key: string; geometry: VirtualItemGeometry): NodeHandle =
      inc mountCalls
      root.box(id = key)

    let firstPlan = planAt(0)
    let first = pool.reconcileVirtualNodes(
      root, host, interaction, firstPlan, firstPlan.keysFor(), mount
    )
    check first.retained == 0
    check first.mounted == 3
    check first.disposed == 0
    check pool.len == 3
    let originalTwo = pool.nodeForKey("item-2").get.id

    let forwardPlan = planAt(20)
    let forward = pool.reconcileVirtualNodes(
      root, host, interaction, forwardPlan, forwardPlan.keysFor(), mount
    )
    check forward.retained == 1
    check forward.mounted == 2
    check forward.disposed == 2
    check pool.nodeForKey("item-2").get.id == originalTwo
    check root.tree.nodes[host.id.nodeIndex].children == pool.nodeIds()

    let reversePlan = planAt(10)
    let reverse = pool.reconcileVirtualNodes(
      root, host, interaction, reversePlan, reversePlan.keysFor(), mount
    )
    check reverse.retained == 2
    check reverse.mounted == 1
    check reverse.disposed == 1
    check reverse.reordered
    check pool.bindings[0].key == "item-1"
    check pool.bindings[1].key == "item-2"
    check pool.bindings[2].key == "item-3"
    check pool.nodeForKey("item-2").get.id == originalTwo
    check root.tree.nodes[host.id.nodeIndex].children == pool.nodeIds()
    check mountCalls == 6
    check root.tree.activeNodeCount() == 4

  test "stable data keys survive logical reordering":
    let root = initUiRoot()
    let host = root.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[string]()
    let plan = planAt(0)
    let mount = proc(index: int; key: string; geometry: VirtualItemGeometry): NodeHandle =
      root.box(id = key)

    discard pool.reconcileVirtualNodes(
      root, host, interaction, plan, ["alpha", "beta", "gamma"], mount
    )
    let alpha = pool.nodeForKey("alpha").get.id
    let gamma = pool.nodeForKey("gamma").get.id
    var refreshed: seq[string]
    let refresh = proc(
        node: NodeHandle;
        index: int;
        key: string;
        geometry: VirtualItemGeometry
    ) =
      refreshed.add key & ":" & $index

    let change = pool.reconcileVirtualNodes(
      root,
      host,
      interaction,
      plan,
      ["gamma", "alpha", "delta"],
      mount,
      refresh
    )

    check change.retained == 2
    check change.mounted == 1
    check change.disposed == 1
    check change.reordered
    check pool.nodeForKey("gamma").get.id == gamma
    check pool.nodeForKey("alpha").get.id == alpha
    check refreshed == @["gamma:0", "alpha:1"]
    check root.tree.nodes[host.id.nodeIndex].children == pool.nodeIds()

  test "materialized roots expose logical positions without allocating every item":
    let root = initUiRoot()
    let host = root.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[int]()
    let plan = planVirtualRange(
      100_000,
      virtualViewport(5_000, 30),
      virtualizationConfig(
        estimatedItemExtent = 10,
        maxMaterializedItems = 8
      )
    )
    var keys: seq[int]
    for item in plan.items:
      keys.add item.index
    let mount = proc(
        index: int;
        key: int;
        geometry: VirtualItemGeometry
    ): NodeHandle =
      result = root.box()
      result.setAccessibleRole(arListItem)
      result.setAccessibleName("Row " & $(index + 1))

    discard pool.reconcileVirtualNodes(
      root, host, interaction, plan, keys, mount
    )

    check pool.len <= 8
    check root.tree.activeNodeCount() == pool.len + 1
    for binding in pool.bindings:
      let semantic = root.tree.semanticInfo(binding.node.id)
      check semantic.positionInSet == some(binding.index + 1)
      check semantic.setSize == some(100_000)
      let accessible = root.accessibilityTree()
        .accessibleNodeFor(binding.node.id).get
      check accessible.positionInSet == semantic.positionInSet
      check accessible.setSize == semantic.setSize

  test "retained nodes update logical positions after data reordering":
    let root = initUiRoot()
    let host = root.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[string]()
    let plan = planAt(0, itemCount = 10)
    let mount = proc(
        index: int;
        key: string;
        geometry: VirtualItemGeometry
    ): NodeHandle =
      result = root.box()
      result.setAccessibleRole(arListItem)

    discard pool.reconcileVirtualNodes(
      root, host, interaction, plan, ["alpha", "beta", "gamma"], mount
    )
    let alpha = pool.nodeForKey("alpha").get
    let gamma = pool.nodeForKey("gamma").get

    discard pool.reconcileVirtualNodes(
      root, host, interaction, plan, ["gamma", "alpha", "delta"], mount
    )

    check pool.nodeForKey("alpha").get.id == alpha.id
    check pool.nodeForKey("gamma").get.id == gamma.id
    check root.tree.semanticInfo(gamma.id).positionInSet == some(1)
    check root.tree.semanticInfo(alpha.id).positionInSet == some(2)
    check root.tree.semanticInfo(alpha.id).setSize == some(10)

  test "unchanged range performs no structural work":
    let root = initUiRoot()
    let host = root.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[int]()
    let plan = planAt(0)
    let mount = proc(index: int; key: int; geometry: VirtualItemGeometry): NodeHandle =
      root.box()
    let keys = @[0, 1, 2]
    discard pool.reconcileVirtualNodes(root, host, interaction, plan, keys, mount)
    discard root.consumeInvalidation()

    let unchanged = pool.reconcileVirtualNodes(
      root, host, interaction, plan, keys, mount
    )

    check unchanged.retained == 3
    check unchanged.mounted == 0
    check unchanged.disposed == 0
    check not unchanged.reordered
    check not root.hasPendingInvalidation

  test "duplicate or mismatched keys fail before mounting":
    let root = initUiRoot()
    let host = root.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[string]()
    let plan = planAt(0)
    var mountCalls = 0
    let mount = proc(index: int; key: string; geometry: VirtualItemGeometry): NodeHandle =
      inc mountCalls
      root.box()

    expect ValueError:
      discard pool.reconcileVirtualNodes(
        root, host, interaction, plan, ["same", "same", "other"], mount
      )
    expect ValueError:
      discard pool.reconcileVirtualNodes(
        root, host, interaction, plan, ["too", "short"], mount
      )

    check mountCalls == 0
    check pool.len == 0
    check root.tree.nodes[host.id.nodeIndex].children.len == 0

  test "mount failure rolls back every child added by the callback":
    let root = initUiRoot()
    let host = root.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[string]()
    let plan = planAt(0)
    var calls = 0
    let failingMount = proc(
        index: int;
        key: string;
        geometry: VirtualItemGeometry
    ): NodeHandle =
      inc calls
      result = root.box(id = key)
      if calls == 2:
        raise newException(ValueError, "mount failed")

    expect ValueError:
      discard pool.reconcileVirtualNodes(
        root, host, interaction, plan, plan.keysFor(), failingMount
      )

    check pool.len == 0
    check root.tree.nodes[host.id.nodeIndex].children.len == 0
    check root.tree.activeNodeCount() == 1

  test "component roots retain lifecycle by key and unmount when stale":
    let root = initUiRoot()
    let host = root.box()
    let mountedKeys = new seq[string]
    let unmountedKeys = new seq[string]
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[string]()
    let mount = proc(
        index: int;
        key: string;
        geometry: VirtualItemGeometry
    ): NodeHandle =
      root.mount(VirtualRow(
        key: key,
        mountedKeys: mountedKeys,
        unmountedKeys: unmountedKeys
      )).node

    let firstPlan = planAt(0)
    discard pool.reconcileVirtualNodes(
      root, host, interaction, firstPlan, firstPlan.keysFor(), mount
    )
    let retained = pool.nodeForKey("item-2").get.id
    let secondPlan = planAt(20)
    discard pool.reconcileVirtualNodes(
      root, host, interaction, secondPlan, secondPlan.keysFor(), mount
    )

    check mountedKeys[] == @[
      "item-0", "item-1", "item-2", "item-3", "item-4"
    ]
    check unmountedKeys[] == @["item-0", "item-1"]
    check pool.nodeForKey("item-2").get.id == retained

    check pool.clearVirtualNodes(root, host, interaction) == 3
    check unmountedKeys[] == @[
      "item-0", "item-1", "item-2", "item-3", "item-4"
    ]

  test "refresh failure removes new nodes and keeps the previous pool valid":
    let root = initUiRoot()
    let host = root.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[string]()
    let plan = planAt(0)
    let mount = proc(index: int; key: string; geometry: VirtualItemGeometry): NodeHandle =
      root.box(id = key)
    discard pool.reconcileVirtualNodes(
      root, host, interaction, plan, ["alpha", "beta", "gamma"], mount
    )
    let previousIds = pool.nodeIds()
    let refresh = proc(
        node: NodeHandle;
        index: int;
        key: string;
        geometry: VirtualItemGeometry
    ) =
      raise newException(ValueError, "refresh failed")

    expect ValueError:
      discard pool.reconcileVirtualNodes(
        root,
        host,
        interaction,
        plan,
        ["new", "alpha", "beta"],
        mount,
        refresh
      )

    check pool.bindings[0].key == "alpha"
    check pool.bindings[1].key == "beta"
    check pool.bindings[2].key == "gamma"
    check pool.nodeIds() == previousIds
    check root.tree.nodes[host.id.nodeIndex].children == previousIds

  test "unmount failure cannot leave retired nodes in the published pool":
    let root = initUiRoot()
    let host = root.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[int]()
    let mount = proc(
        index: int;
        key: int;
        geometry: VirtualItemGeometry
    ): NodeHandle =
      root.mount(FailingUnmountRow(
        key: key,
        failOnUnmount: key == 0
      )).node

    let firstPlan = planAt(0)
    discard pool.reconcileVirtualNodes(
      root, host, interaction, firstPlan, [0, 1, 2], mount
    )
    let retiredZero = pool.nodeForKey(0).get
    let retiredOne = pool.nodeForKey(1).get
    let retainedTwo = pool.nodeForKey(2).get.id

    let secondPlan = planAt(20)
    expect ValueError:
      discard pool.reconcileVirtualNodes(
        root, host, interaction, secondPlan, [2, 3, 4], mount
      )

    check not retiredZero.valid
    check not retiredOne.valid
    check pool.len == 3
    check pool.nodeForKey(0).isNone
    check pool.nodeForKey(1).isNone
    check pool.nodeForKey(2).get.id == retainedTwo
    check root.tree.nodes[host.id.nodeIndex].children == pool.nodeIds()
    check root.tree.activeNodeCount() == 7

  test "callbacks cannot mount multiple direct roots":
    let root = initUiRoot()
    let host = root.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[int]()
    let plan = planAt(0)
    let invalidMount = proc(
        index: int;
        key: int;
        geometry: VirtualItemGeometry
    ): NodeHandle =
      result = root.box()
      discard root.box()

    expect ValueError:
      discard pool.reconcileVirtualNodes(
        root, host, interaction, plan, [0, 1, 2], invalidMount
      )

    check pool.len == 0
    check root.tree.nodes[host.id.nodeIndex].children.len == 0

  test "foreign or shared hosts are rejected without mutation":
    let root = initUiRoot()
    let host = root.box()
    let unrelated = root.box(parent = some(host))
    let foreignRoot = initUiRoot()
    let foreignHost = foreignRoot.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[int]()
    let plan = planAt(0)
    let mount = proc(index: int; key: int; geometry: VirtualItemGeometry): NodeHandle =
      root.box()

    expect ValueError:
      discard pool.reconcileVirtualNodes(
        root, host, interaction, plan, [0, 1, 2], mount
      )
    expect ValueError:
      discard pool.reconcileVirtualNodes(
        root, foreignHost, interaction, plan, [0, 1, 2], mount
      )

    check unrelated.valid
    check root.tree.nodes[host.id.nodeIndex].children == @[unrelated.id]

  test "disposed keys retire stale ids and bounded slots are reusable":
    let root = initUiRoot()
    let host = root.box()
    var interaction = initInteractionState()
    var pool = initVirtualNodePool[int]()
    let mount = proc(index: int; key: int; geometry: VirtualItemGeometry): NodeHandle =
      root.box()

    let firstPlan = planAt(0)
    discard pool.reconcileVirtualNodes(
      root, host, interaction, firstPlan, [0, 1, 2], mount
    )
    let stale = pool.nodeForKey(0).get
    let capacity = root.tree.nodes.len
    let nextPlan = planAt(30)
    discard pool.reconcileVirtualNodes(
      root, host, interaction, nextPlan, [3, 4, 5], mount
    )

    check not stale.valid
    check root.tree.nodes.len <= capacity + 3
    check root.tree.activeNodeCount() == 4

    check pool.clearVirtualNodes(root, host, interaction) == 3
    check pool.len == 0
    check root.tree.nodes[host.id.nodeIndex].children.len == 0
    check root.tree.activeNodeCount() == 1

  test "tree child ordering requires the exact direct-child set":
    var tree = initTree()
    let host = tree.addBox()
    let first = tree.addBox(parent = some(host))
    let second = tree.addBox(parent = some(host))
    let outsider = tree.addBox()

    check tree.reorderChildren(host, [second, first])
    check tree.nodes[host.nodeIndex].children == @[second, first]
    check not tree.reorderChildren(host, [second, first])
    expect ValueError:
      discard tree.reorderChildren(host, [first])
    expect ValueError:
      discard tree.reorderChildren(host, [first, first])
    expect ValueError:
      discard tree.reorderChildren(host, [first, outsider])
    check tree.nodes[host.nodeIndex].children == @[second, first]
