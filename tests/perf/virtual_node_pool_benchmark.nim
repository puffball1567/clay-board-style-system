## Verifies that stable-key reconciliation follows the bounded materialized
## range rather than the total logical item count.
import std/[monotimes, strformat, times]

import clay_board_style_system

type PoolTiming = object
  nsPerReconcile: float
  materializedItems: int
  arenaCapacity: int

proc keysFor(plan: VirtualRangePlan): seq[int] =
  for item in plan.items:
    result.add item.index

proc benchmark(itemCount, iterations: int): PoolTiming =
  let config = virtualizationConfig(
    22,
    overscanBefore = 88,
    overscanAfter = 132,
    maxMaterializedItems = 64
  )
  let index = initVirtualExtentIndex(itemCount, config.estimatedItemExtent)
  let firstPlan = index.planVirtualRange(virtualViewport(110_000, 440), config)
  let secondPlan = index.planVirtualRange(virtualViewport(110_022, 440), config)
  let firstKeys = firstPlan.keysFor()
  let secondKeys = secondPlan.keysFor()
  let root = initUiRoot()
  let host = root.box()
  var interaction = initInteractionState()
  var pool = initVirtualNodePool[int]()
  let mount = proc(
      logicalIndex: int;
      key: int;
      geometry: VirtualItemGeometry
  ): NodeHandle =
    root.box()

  discard pool.reconcileVirtualNodes(
    root, host, interaction, firstPlan, firstKeys, mount
  )
  for iteration in 0 ..< 100:
    if iteration mod 2 == 0:
      discard pool.reconcileVirtualNodes(
        root, host, interaction, secondPlan, secondKeys, mount
      )
    else:
      discard pool.reconcileVirtualNodes(
        root, host, interaction, firstPlan, firstKeys, mount
      )

  let started = getMonoTime()
  for iteration in 0 ..< iterations:
    if iteration mod 2 == 0:
      discard pool.reconcileVirtualNodes(
        root, host, interaction, secondPlan, secondKeys, mount
      )
    else:
      discard pool.reconcileVirtualNodes(
        root, host, interaction, firstPlan, firstKeys, mount
      )
  result.nsPerReconcile =
    (getMonoTime() - started).inNanoseconds.float / iterations.float
  result.materializedItems = pool.len
  result.arenaCapacity = root.tree.nodes.len

  doAssert root.tree.activeNodeCount() == pool.len + 1
  doAssert root.tree.nodes.len <= config.maxMaterializedItems + 2

when isMainModule:
  const iterations = 20_000
  let hundredThousand = benchmark(100_000, iterations)
  let tenMillion = benchmark(10_000_000, iterations)

  echo "CBSS stable-key virtual node pool benchmark (release, ARC)"
  echo &"  100,000 logical items:   {hundredThousand.nsPerReconcile:.1f} ns/reconcile"
  echo &"  10,000,000 logical items: {tenMillion.nsPerReconcile:.1f} ns/reconcile"
  echo &"  materialized items: {hundredThousand.materializedItems} / " &
    &"{tenMillion.materializedItems}"
  echo &"  node arena capacity: {hundredThousand.arenaCapacity} / " &
    &"{tenMillion.arenaCapacity}"

  doAssert hundredThousand.materializedItems <= 64
  doAssert tenMillion.materializedItems == hundredThousand.materializedItems
  doAssert tenMillion.arenaCapacity == hundredThousand.arenaCapacity
  doAssert tenMillion.nsPerReconcile <=
      hundredThousand.nsPerReconcile * 4.0 + 5_000.0,
    "virtual node reconciliation scaled with the logical item count"
