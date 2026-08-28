## Verifies that virtual range planning follows sparse measurements and the
## materialized range instead of allocating or scanning one entry per logical
## item.
import std/[monotimes, strformat, times]

import clay_board_style_system

type VirtualizationTiming = object
  nsPerPlan: float
  materializedItems: int

proc benchmark(itemCount, iterations: int): VirtualizationTiming =
  let config = virtualizationConfig(
    22,
    overscanBefore = 88,
    overscanAfter = 132,
    maxMaterializedItems = 64
  )
  let measurements = [
    virtualMeasurement(1, 28),
    virtualMeasurement(itemCount div 2, 34),
    virtualMeasurement(itemCount - 2, 18)
  ]
  let extentIndex = initVirtualExtentIndex(
    itemCount, config.estimatedItemExtent, measurements
  )
  var checksum = 0

  for index in 0 ..< 100:
    let plan = planVirtualRange(
      extentIndex,
      virtualViewport((itemCount.float32 * 11) + index.float32, 440),
      config
    )
    checksum += plan.items.len

  let started = getMonoTime()
  for index in 0 ..< iterations:
    let plan = planVirtualRange(
      extentIndex,
      virtualViewport((itemCount.float32 * 11) + index.float32, 440),
      config
    )
    checksum += plan.items.len
    result.materializedItems = plan.items.len
  result.nsPerPlan =
    (getMonoTime() - started).inNanoseconds.float / iterations.float
  doAssert checksum > 0

when isMainModule:
  const iterations = 10_000
  let hundredThousand = benchmark(100_000, iterations)
  let tenMillion = benchmark(10_000_000, iterations)

  echo "CBSS virtual range planner benchmark (release, ARC)"
  echo &"  100,000 logical items:  {hundredThousand.nsPerPlan:.1f} ns/plan"
  echo &"  10,000,000 logical items: {tenMillion.nsPerPlan:.1f} ns/plan"
  echo &"  materialized items: {hundredThousand.materializedItems} / " &
    &"{tenMillion.materializedItems}"

  doAssert hundredThousand.materializedItems <= 64
  doAssert tenMillion.materializedItems == hundredThousand.materializedItems
  doAssert tenMillion.nsPerPlan <= hundredThousand.nsPerPlan * 4.0 + 2_000.0,
    "virtual range planning scaled with the logical item count"
