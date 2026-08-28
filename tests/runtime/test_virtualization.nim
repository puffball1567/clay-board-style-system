import std/[math, options, sequtils, unittest]

import clay_board_style_system

suite "virtual range planner":
  test "empty data produces an empty bounded plan":
    let plan = planVirtualRange(
      0,
      virtualViewport(0, 300),
      virtualizationConfig(24, overscanBefore = 48, overscanAfter = 48)
    )

    check plan.itemCount == 0
    check plan.totalExtent == 0
    check plan.visible == VirtualRange(first: 0, lastExclusive: 0)
    check plan.materialized == VirtualRange(first: 0, lastExclusive: 0)
    check plan.items.len == 0
    check plan.viewportAnchor().isNone

  test "one hundred thousand uniform rows only materialize the viewport":
    let plan = planVirtualRange(
      100_000,
      virtualViewport(1_000_000, 400),
      virtualizationConfig(
        20, overscanBefore = 40, overscanAfter = 60,
        maxMaterializedItems = 64
      )
    )

    check plan.totalExtent == 2_000_000
    check plan.visible == VirtualRange(first: 50_000, lastExclusive: 50_020)
    check plan.materialized == VirtualRange(first: 49_998, lastExclusive: 50_023)
    check plan.items.len == 25
    check plan.leadingExtent == 999_960
    check plan.materializedExtent == 500
    check plan.trailingExtent == 999_540
    check plan.items[0] == VirtualItemGeometry(
      index: 49_998, offset: 999_960, extent: 20, measured: false
    )

  test "sparse measurements correct offsets without retaining every row":
    let measurements = [
      virtualMeasurement(0, 30),
      virtualMeasurement(4, 5),
      virtualMeasurement(8, 25)
    ]
    let plan = planVirtualRange(
      10,
      virtualViewport(45, 30),
      virtualizationConfig(10, maxMaterializedItems = 16),
      measurements
    )

    check plan.totalExtent == 130
    check plan.visible == VirtualRange(first: 2, lastExclusive: 6)
    check plan.items.len == 4
    check plan.items[0] == VirtualItemGeometry(
      index: 2, offset: 40, extent: 10, measured: false
    )
    check plan.items[2] == VirtualItemGeometry(
      index: 4, offset: 60, extent: 5, measured: true
    )
    check plan.items[3] == VirtualItemGeometry(
      index: 5, offset: 65, extent: 10, measured: false
    )

  test "a prepared extent index is reusable across viewport changes":
    let config = virtualizationConfig(
      12, overscanBefore = 12, overscanAfter = 24,
      maxMaterializedItems = 16
    )
    let extentIndex = initVirtualExtentIndex(
      1_000, config.estimatedItemExtent,
      [virtualMeasurement(10, 20), virtualMeasurement(500, 8)]
    )
    let first = extentIndex.planVirtualRange(
      virtualViewport(100, 48), config
    )
    let second = extentIndex.planVirtualRange(
      virtualViewport(6_000, 48), config
    )

    check extentIndex.itemCount == 1_000
    check first.items.len <= config.maxMaterializedItems
    check second.items.len <= config.maxMaterializedItems
    check first.visible != second.visible
    let anchor = second.viewportAnchor().get
    check anchor.offsetForAnchor(extentIndex) == second.viewportOffset

  test "viewport offsets clamp to the final scroll position":
    let plan = planVirtualRange(
      5,
      virtualViewport(10_000, 25),
      virtualizationConfig(10, maxMaterializedItems = 8)
    )

    check plan.requestedOffset == 10_000
    check plan.viewportOffset == 25
    check plan.visible == VirtualRange(first: 2, lastExclusive: 5)

  test "exact viewport boundaries do not retain the following row":
    let plan = planVirtualRange(
      20,
      virtualViewport(30, 20),
      virtualizationConfig(10, maxMaterializedItems = 8)
    )

    check plan.visible == VirtualRange(first: 3, lastExclusive: 5)
    check plan.materialized == plan.visible
    check plan.items.mapIt(it.index) == @[3, 4]

  test "a viewport larger than the content materializes every available row":
    let plan = planVirtualRange(
      3,
      virtualViewport(500, 100),
      virtualizationConfig(10, maxMaterializedItems = 8)
    )

    check plan.viewportOffset == 0
    check plan.visible == VirtualRange(first: 0, lastExclusive: 3)
    check plan.leadingExtent == 0
    check plan.materializedExtent == 30
    check plan.trailingExtent == 0

  test "unsorted sparse measurements produce contiguous geometry":
    let plan = planVirtualRange(
      12,
      virtualViewport(15, 50),
      virtualizationConfig(
        10, overscanBefore = 10, overscanAfter = 15,
        maxMaterializedItems = 12
      ),
      [
        virtualMeasurement(7, 4),
        virtualMeasurement(1, 25),
        virtualMeasurement(4, 6)
      ]
    )

    check plan.items.len ==
      plan.materialized.lastExclusive - plan.materialized.first
    for index in 1 ..< plan.items.len:
      check plan.items[index].index == plan.items[index - 1].index + 1
      check plan.items[index].offset ==
        plan.items[index - 1].offset + plan.items[index - 1].extent
    check plan.leadingExtent + plan.materializedExtent + plan.trailingExtent ==
      plan.totalExtent

  test "materialization caps trim overscan but never visible rows":
    let plan = planVirtualRange(
      1_000,
      virtualViewport(500, 100),
      virtualizationConfig(
        10, overscanBefore = 1_000, overscanAfter = 1_000,
        maxMaterializedItems = 16
      )
    )

    check plan.visible == VirtualRange(first: 50, lastExclusive: 60)
    check plan.materialized.first <= plan.visible.first
    check plan.materialized.lastExclusive >= plan.visible.lastExclusive
    check plan.items.len == 16

  test "anchors preserve the same visual item after measured correction":
    let initial = planVirtualRange(
      20,
      virtualViewport(25, 20),
      virtualizationConfig(10, maxMaterializedItems = 16)
    )
    let anchor = initial.viewportAnchor().get

    check anchor == VirtualAnchor(index: 2, offsetWithinItem: 5)
    check anchor.offsetForAnchor(
      20,
      virtualizationConfig(10, maxMaterializedItems = 16),
      [virtualMeasurement(0, 30)]
    ) == 45

  test "invalid and ambiguous inputs fail explicitly":
    let config = virtualizationConfig(10, maxMaterializedItems = 8)

    expect ValueError:
      discard planVirtualRange(-1, virtualViewport(0, 20), config)
    expect ValueError:
      discard planVirtualRange(2, virtualViewport(0, 0), config)
    expect ValueError:
      discard planVirtualRange(
        2, virtualViewport(NaN.float32, 20), config
      )
    expect ValueError:
      discard planVirtualRange(
        2, virtualViewport(0, 20), virtualizationConfig(0)
      )
    expect ValueError:
      discard planVirtualRange(
        2, virtualViewport(0, 20), config,
        [virtualMeasurement(2, 10)]
      )
    expect ValueError:
      discard planVirtualRange(
        2, virtualViewport(0, 20), config,
        [virtualMeasurement(0, 10), virtualMeasurement(0, 12)]
      )
    expect ValueError:
      discard planVirtualRange(
        2, virtualViewport(0, 20), config,
        [virtualMeasurement(0, -1)]
      )
    expect ValueError:
      discard planVirtualRange(
        2, virtualViewport(0, 20), config,
        [virtualMeasurement(0, Inf.float32)]
      )
    expect ValueError:
      discard planVirtualRange(
        2, virtualViewport(0, 20),
        virtualizationConfig(10, overscanAfter = Inf.float32)
      )
    expect ValueError:
      let extentIndex = initVirtualExtentIndex(2, 10)
      discard extentIndex.planVirtualRange(
        virtualViewport(0, 20), virtualizationConfig(12)
      )

  test "a hard cap rejects an incomplete visible range":
    expect ValueError:
      discard planVirtualRange(
        100,
        virtualViewport(0, 100),
        virtualizationConfig(1, maxMaterializedItems = 20)
      )
