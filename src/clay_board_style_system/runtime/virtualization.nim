## Bounded viewport/data virtualization planning. This module computes which
## logical items need nodes; it does not replay or own component trees.
import std/[algorithm, math, options]

type
  VirtualViewport* = object
    offset*: float32
    extent*: float32

  VirtualRange* = object
    first*: int
    lastExclusive*: int

  VirtualMeasurement* = object
    index*: int
    extent*: float32

  VirtualizationConfig* = object
    estimatedItemExtent*: float32
    overscanBefore*: float32
    overscanAfter*: float32
    maxMaterializedItems*: int

  VirtualItemGeometry* = object
    index*: int
    offset*: float32
    extent*: float32
    measured*: bool

  VirtualAnchor* = object
    index*: int
    offsetWithinItem*: float32

  VirtualRangePlan* = object
    itemCount*: int
    requestedOffset*: float32
    viewportOffset*: float32
    viewportExtent*: float32
    totalExtent*: float32
    visible*: VirtualRange
    materialized*: VirtualRange
    leadingExtent*: float32
    materializedExtent*: float32
    trailingExtent*: float32
    items*: seq[VirtualItemGeometry]

  PreparedMeasurements = object
    entries: seq[VirtualMeasurement]
    prefixDeltas: seq[float32]

  VirtualExtentIndex* = object
    ## Reusable sparse extent corrections for scroll-time range planning.
    itemCount*: int
    estimatedItemExtent*: float32
    prepared: PreparedMeasurements

proc virtualViewport*(offset, extent: float32): VirtualViewport =
  VirtualViewport(offset: offset, extent: extent)

proc virtualizationConfig*(
    estimatedItemExtent: float32;
    overscanBefore = 0.0'f32;
    overscanAfter = 0.0'f32;
    maxMaterializedItems = 512
): VirtualizationConfig =
  VirtualizationConfig(
    estimatedItemExtent: estimatedItemExtent,
    overscanBefore: overscanBefore,
    overscanAfter: overscanAfter,
    maxMaterializedItems: maxMaterializedItems
  )

proc virtualMeasurement*(index: int; extent: float32): VirtualMeasurement =
  VirtualMeasurement(index: index, extent: extent)

proc isFinite(value: float32): bool {.inline.} =
  value.classify notin {fcNan, fcInf, fcNegInf}

proc compareMeasurement(a, b: VirtualMeasurement): int {.nimcall.} =
  cmp(a.index, b.index)

proc validateInputs(
    itemCount: int;
    viewport: VirtualViewport;
    config: VirtualizationConfig
) =
  if itemCount < 0:
    raise newException(ValueError, "virtual item count cannot be negative")
  if not viewport.offset.isFinite or viewport.offset < 0:
    raise newException(ValueError, "virtual viewport offset must be finite and non-negative")
  if not viewport.extent.isFinite or viewport.extent <= 0:
    raise newException(ValueError, "virtual viewport extent must be finite and positive")
  if not config.estimatedItemExtent.isFinite or config.estimatedItemExtent <= 0:
    raise newException(ValueError, "estimated virtual item extent must be finite and positive")
  if not config.overscanBefore.isFinite or config.overscanBefore < 0 or
      not config.overscanAfter.isFinite or config.overscanAfter < 0:
    raise newException(ValueError, "virtual overscan must be finite and non-negative")
  if config.maxMaterializedItems <= 0:
    raise newException(ValueError, "maximum materialized item count must be positive")

proc prepareMeasurements(
    itemCount: int;
    estimatedExtent: float32;
    measurements: openArray[VirtualMeasurement]
): PreparedMeasurements =
  result.entries = @measurements
  result.entries.sort(compareMeasurement)
  result.prefixDeltas = newSeq[float32](result.entries.len)
  var correction = 0.0'f32
  var previousIndex = -1
  for index, measurement in result.entries:
    if measurement.index < 0 or measurement.index >= itemCount:
      raise newException(ValueError, "virtual measurement index is outside the item range")
    if measurement.index == previousIndex:
      raise newException(ValueError, "virtual measurement indices must be unique")
    if not measurement.extent.isFinite or measurement.extent <= 0:
      raise newException(ValueError, "measured virtual item extent must be finite and positive")
    correction += measurement.extent - estimatedExtent
    if not correction.isFinite:
      raise newException(ValueError, "virtual measurement correction overflowed")
    result.prefixDeltas[index] = correction
    previousIndex = measurement.index

proc initVirtualExtentIndex*(
    itemCount: int;
    estimatedItemExtent: float32;
    measurements: openArray[VirtualMeasurement] = []
): VirtualExtentIndex =
  validateInputs(
    itemCount,
    virtualViewport(0, 1),
    virtualizationConfig(estimatedItemExtent)
  )
  VirtualExtentIndex(
    itemCount: itemCount,
    estimatedItemExtent: estimatedItemExtent,
    prepared: prepareMeasurements(itemCount, estimatedItemExtent, measurements)
  )

proc lowerBoundMeasurement(entries: openArray[VirtualMeasurement]; index: int): int =
  var first = 0
  var last = entries.len
  while first < last:
    let middle = first + (last - first) div 2
    if entries[middle].index < index:
      first = middle + 1
    else:
      last = middle
  first

proc correctionBefore(prepared: PreparedMeasurements; index: int): float32 =
  let position = prepared.entries.lowerBoundMeasurement(index)
  if position == 0: 0.0'f32 else: prepared.prefixDeltas[position - 1]

proc measuredExtent(
    prepared: PreparedMeasurements;
    index: int;
    estimatedExtent: float32
): tuple[extent: float32, measured: bool] =
  let position = prepared.entries.lowerBoundMeasurement(index)
  if position < prepared.entries.len and prepared.entries[position].index == index:
    return (prepared.entries[position].extent, true)
  (estimatedExtent, false)

proc itemOffset(
    prepared: PreparedMeasurements;
    index: int;
    estimatedExtent: float32
): float32 =
  result = index.float32 * estimatedExtent + prepared.correctionBefore(index)
  if not result.isFinite:
    raise newException(ValueError, "virtual content extent overflowed")
  result = max(0.0'f32, result)

proc lowerBoundOffset(
    prepared: PreparedMeasurements;
    itemCount: int;
    estimatedExtent, target: float32
): int =
  var first = 0
  var last = itemCount
  while first < last:
    let middle = first + (last - first) div 2
    if prepared.itemOffset(middle, estimatedExtent) < target:
      first = middle + 1
    else:
      last = middle
  first

proc itemAtOffset(
    prepared: PreparedMeasurements;
    itemCount: int;
    estimatedExtent, target: float32
): int =
  if itemCount == 0:
    return 0
  var first = 0
  var last = itemCount
  while first < last:
    let middle = first + (last - first) div 2
    if prepared.itemOffset(middle, estimatedExtent) <= target:
      first = middle + 1
    else:
      last = middle
  min(itemCount - 1, max(0, first - 1))

proc trimOverscan(
    desired, visible: VirtualRange;
    maximum: int
): VirtualRange =
  let visibleCount = visible.lastExclusive - visible.first
  if visibleCount > maximum:
    raise newException(
      ValueError,
      "visible virtual range exceeds the configured materialization limit"
    )
  if desired.lastExclusive - desired.first <= maximum:
    return desired

  let beforeAvailable = visible.first - desired.first
  let afterAvailable = desired.lastExclusive - visible.lastExclusive
  var remaining = maximum - visibleCount
  var before = min(beforeAvailable, remaining div 2)
  var after = min(afterAvailable, remaining - before)
  remaining -= before + after
  if remaining > 0:
    let extraBefore = min(beforeAvailable - before, remaining)
    before += extraBefore
    remaining -= extraBefore
  if remaining > 0:
    after += min(afterAvailable - after, remaining)
  VirtualRange(
    first: visible.first - before,
    lastExclusive: visible.lastExclusive + after
  )

proc planVirtualRangePrepared(
    itemCount: int;
    viewport: VirtualViewport;
    config: VirtualizationConfig;
    prepared: PreparedMeasurements
): VirtualRangePlan =
  validateInputs(itemCount, viewport, config)
  let totalExtent = prepared.itemOffset(itemCount, config.estimatedItemExtent)
  let maximumOffset = max(0.0'f32, totalExtent - viewport.extent)
  let viewportOffset = min(viewport.offset, maximumOffset)

  result = VirtualRangePlan(
    itemCount: itemCount,
    requestedOffset: viewport.offset,
    viewportOffset: viewportOffset,
    viewportExtent: viewport.extent,
    totalExtent: totalExtent
  )
  if itemCount == 0:
    return

  let viewportEnd = min(totalExtent, viewportOffset + viewport.extent)
  result.visible = VirtualRange(
    first: prepared.itemAtOffset(
      itemCount, config.estimatedItemExtent, viewportOffset
    ),
    lastExclusive: prepared.lowerBoundOffset(
      itemCount, config.estimatedItemExtent, viewportEnd
    )
  )
  if result.visible.lastExclusive <= result.visible.first:
    result.visible.lastExclusive = min(itemCount, result.visible.first + 1)

  let overscanStart = max(0.0'f32, viewportOffset - config.overscanBefore)
  let overscanEnd = min(totalExtent, viewportEnd + config.overscanAfter)
  let desired = VirtualRange(
    first: prepared.itemAtOffset(
      itemCount, config.estimatedItemExtent, overscanStart
    ),
    lastExclusive: prepared.lowerBoundOffset(
      itemCount, config.estimatedItemExtent, overscanEnd
    )
  )
  var completeDesired = desired
  if completeDesired.lastExclusive <= completeDesired.first:
    completeDesired.lastExclusive = min(itemCount, completeDesired.first + 1)
  result.materialized = trimOverscan(
    completeDesired, result.visible, config.maxMaterializedItems
  )

  result.leadingExtent = prepared.itemOffset(
    result.materialized.first, config.estimatedItemExtent
  )
  let materializedEnd = prepared.itemOffset(
    result.materialized.lastExclusive, config.estimatedItemExtent
  )
  result.materializedExtent = materializedEnd - result.leadingExtent
  result.trailingExtent = max(0.0'f32, totalExtent - materializedEnd)
  result.items = newSeqOfCap[VirtualItemGeometry](
    result.materialized.lastExclusive - result.materialized.first
  )
  for index in result.materialized.first ..< result.materialized.lastExclusive:
    let item = prepared.measuredExtent(index, config.estimatedItemExtent)
    result.items.add VirtualItemGeometry(
      index: index,
      offset: prepared.itemOffset(index, config.estimatedItemExtent),
      extent: item.extent,
      measured: item.measured
    )

proc planVirtualRange*(
    extentIndex: VirtualExtentIndex;
    viewport: VirtualViewport;
    config: VirtualizationConfig
): VirtualRangePlan =
  if extentIndex.itemCount < 0 or
      extentIndex.estimatedItemExtent != config.estimatedItemExtent:
    raise newException(
      ValueError,
      "virtual extent index does not match the planning configuration"
    )
  planVirtualRangePrepared(
    extentIndex.itemCount, viewport, config, extentIndex.prepared
  )

proc planVirtualRange*(
    itemCount: int;
    viewport: VirtualViewport;
    config: VirtualizationConfig;
    measurements: openArray[VirtualMeasurement] = []
): VirtualRangePlan =
  let extentIndex = initVirtualExtentIndex(
    itemCount, config.estimatedItemExtent, measurements
  )
  extentIndex.planVirtualRange(viewport, config)

proc viewportAnchor*(plan: VirtualRangePlan): Option[VirtualAnchor] =
  if plan.itemCount == 0 or plan.visible.first >= plan.visible.lastExclusive:
    return none(VirtualAnchor)
  var itemOffset = 0.0'f32
  for item in plan.items:
    if item.index == plan.visible.first:
      itemOffset = item.offset
      break
  some(VirtualAnchor(
    index: plan.visible.first,
    offsetWithinItem: max(0.0'f32, plan.viewportOffset - itemOffset)
  ))

proc offsetForAnchor*(
    anchor: VirtualAnchor;
    itemCount: int;
    config: VirtualizationConfig;
    measurements: openArray[VirtualMeasurement] = []
): float32 =
  validateInputs(itemCount, virtualViewport(0, 1), config)
  if anchor.index < 0 or anchor.index >= itemCount or
      not anchor.offsetWithinItem.isFinite or anchor.offsetWithinItem < 0:
    raise newException(ValueError, "virtual anchor is outside the item range")
  let prepared = prepareMeasurements(
    itemCount, config.estimatedItemExtent, measurements
  )
  let item = prepared.measuredExtent(anchor.index, config.estimatedItemExtent)
  prepared.itemOffset(anchor.index, config.estimatedItemExtent) +
    min(anchor.offsetWithinItem, item.extent)

proc offsetForAnchor*(
    anchor: VirtualAnchor;
    extentIndex: VirtualExtentIndex
): float32 =
  if anchor.index < 0 or anchor.index >= extentIndex.itemCount or
      not anchor.offsetWithinItem.isFinite or anchor.offsetWithinItem < 0:
    raise newException(ValueError, "virtual anchor is outside the item range")
  let item = extentIndex.prepared.measuredExtent(
    anchor.index, extentIndex.estimatedItemExtent
  )
  extentIndex.prepared.itemOffset(
    anchor.index, extentIndex.estimatedItemExtent
  ) + min(anchor.offsetWithinItem, item.extent)
