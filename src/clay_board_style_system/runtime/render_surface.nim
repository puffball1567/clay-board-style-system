import std/[algorithm, hashes, math, options, sets, tables]

import ../core/[geometry, node]
import ../input/events

const renderSurfaceApiVersion* = 1'u32

type
  RenderSurfaceId* = distinct uint64

  RenderSurfaceState* = enum
    rssUnmounted,
    rssMounted,
    rssDeviceLost

  RenderSurfaceFrameResult* = enum
    rsfIdle,
    rsfRequestNext

  RenderSurfacePlacement* = object
    ## `bounds` and `clip` use host presentation coordinates. Surface drawing
    ## and input use a local origin at the top-left of `bounds`.
    bounds*: Rect
    sourceBounds*: Rect
    clip*: Rect
    pixelScale*: float32
    opacity*: float32
    transform*: Affine2D
    inverseTransform*: Option[Affine2D]

  RenderSurfaceMount* = object
    apiVersion*: uint32
    surface*: RenderSurfaceId
    node*: NodeId
    placement*: RenderSurfacePlacement
    visible*: bool
    revision*: uint64

  RenderSurfaceUpdate* = object
    surface*: RenderSurfaceId
    revision*: uint64
    placement*: RenderSurfacePlacement

  RenderSurfaceResize* = object
    surface*: RenderSurfaceId
    logicalSize*: Size
    pixelSize*: Size
    pixelScale*: float32

  RenderSurfaceInput* = object
    surface*: RenderSurfaceId
    event*: InputEvent
    localPosition*: Option[Vec2]
    inside*: bool
    captured*: bool

  RenderSurfaceFrame* = object
    surface*: RenderSurfaceId
    frameNumber*: uint64
    nowSeconds*: float64
    deltaSeconds*: float64
    placement*: RenderSurfacePlacement

  RenderSurfaceMountCallback* = proc(event: RenderSurfaceMount) {.closure.}
  RenderSurfaceUpdateCallback* = proc(event: RenderSurfaceUpdate) {.closure.}
  RenderSurfaceResizeCallback* = proc(event: RenderSurfaceResize) {.closure.}
  RenderSurfaceInputCallback* = proc(event: RenderSurfaceInput): bool {.closure.}
  RenderSurfaceFrameCallback* = proc(event: RenderSurfaceFrame): RenderSurfaceFrameResult {.closure.}
  RenderSurfaceVisibilityCallback* = proc(visible: bool) {.closure.}
  RenderSurfaceDeviceCallback* = proc() {.closure.}
  RenderSurfaceUnmountCallback* = proc() {.closure.}

  RenderSurfaceCallbacks* = object
    onMount*: RenderSurfaceMountCallback
    onUpdate*: RenderSurfaceUpdateCallback
    onResize*: RenderSurfaceResizeCallback
    onInput*: RenderSurfaceInputCallback
    onFrame*: RenderSurfaceFrameCallback
    onVisibility*: RenderSurfaceVisibilityCallback
    onDeviceLost*: RenderSurfaceDeviceCallback
    onDeviceRestored*: RenderSurfaceDeviceCallback
    onUnmount*: RenderSurfaceUnmountCallback

  RenderSurfaceDescriptor* = object
    name*: string
    callbacks*: RenderSurfaceCallbacks

  RenderSurfaceEntry = object
    descriptor: RenderSurfaceDescriptor
    state: RenderSurfaceState
    node: Option[NodeId]
    placement: RenderSurfacePlacement
    requestedVisible: bool
    effectiveVisible: bool
    revision: uint64
    frameRequested: bool
    frameNumber: uint64
    lastFrameTime: Option[float64]

  RenderSurfaceRegistry* = object
    nextId: uint64
    entries: Table[RenderSurfaceId, RenderSurfaceEntry]
    runnableFrames: HashSet[RenderSurfaceId]

proc `==`*(a, b: RenderSurfaceId): bool {.borrow.}
proc `<`*(a, b: RenderSurfaceId): bool {.borrow.}
proc hash*(id: RenderSurfaceId): Hash {.borrow.}

proc renderSurfaceIdValue*(id: RenderSurfaceId): uint64 =
  uint64(id)

proc initRenderSurfaceRegistry*(): RenderSurfaceRegistry =
  RenderSurfaceRegistry(
    nextId: 1'u64,
    entries: initTable[RenderSurfaceId, RenderSurfaceEntry](),
    runnableFrames: initHashSet[RenderSurfaceId]()
  )

proc validFinite(value: float32): bool =
  value.classify notin {fcNan, fcInf, fcNegInf}

proc validatePlacement(placement: RenderSurfacePlacement) =
  let values = [
    placement.bounds.x, placement.bounds.y,
    placement.bounds.w, placement.bounds.h,
    placement.sourceBounds.x, placement.sourceBounds.y,
    placement.sourceBounds.w, placement.sourceBounds.h,
    placement.clip.x, placement.clip.y,
    placement.clip.w, placement.clip.h,
    placement.pixelScale, placement.opacity,
    placement.transform.m11, placement.transform.m12,
    placement.transform.m21, placement.transform.m22,
    placement.transform.tx, placement.transform.ty
  ]
  for value in values:
    if not value.validFinite:
      raise newException(ValueError, "render surface placement must be finite")
  if placement.bounds.w < 0 or placement.bounds.h < 0 or
      placement.sourceBounds.w < 0 or placement.sourceBounds.h < 0 or
      placement.clip.w < 0 or placement.clip.h < 0:
    raise newException(ValueError, "render surface sizes must not be negative")
  if placement.pixelScale <= 0:
    raise newException(ValueError, "render surface pixel scale must be positive")
  if placement.opacity < 0 or placement.opacity > 1:
    raise newException(ValueError, "render surface opacity must be between zero and one")

proc renderSurfacePlacement*(
    bounds: Rect;
    clip: Rect;
    pixelScale = 1.0'f32;
    opacity = 1.0'f32;
    transform = identityAffine2D()
): RenderSurfacePlacement =
  let transformedBounds = transform.transformedBounds(bounds)
  result = RenderSurfacePlacement(
    bounds: transformedBounds,
    sourceBounds: bounds,
    clip: clip,
    pixelScale: pixelScale,
    opacity: opacity,
    transform: transform,
    inverseTransform: transform.inverse
  )
  result.validatePlacement()

proc localBounds*(placement: RenderSurfacePlacement): Rect =
  rect(0, 0, placement.sourceBounds.w, placement.sourceBounds.h)

proc pixelSize*(placement: RenderSurfacePlacement): Size =
  size(
    round(placement.sourceBounds.w * placement.pixelScale),
    round(placement.sourceBounds.h * placement.pixelScale)
  )

proc toLocal*(placement: RenderSurfacePlacement; point: Vec2): Vec2 =
  let sourcePoint =
    if placement.inverseTransform.isSome:
      placement.inverseTransform.get.transformPoint(point)
    else:
      point
  vec2(
    sourcePoint.x - placement.sourceBounds.x,
    sourcePoint.y - placement.sourceBounds.y
  )

proc effectiveClip*(placement: RenderSurfacePlacement): Rect =
  placement.bounds.intersection(placement.clip)

proc isRenderable*(placement: RenderSurfacePlacement): bool =
  placement.bounds.w > 0 and placement.bounds.h > 0 and
    placement.opacity > 0 and placement.inverseTransform.isSome and
    not placement.effectiveClip.isEmpty

proc hasSurface*(registry: RenderSurfaceRegistry; id: RenderSurfaceId): bool =
  id in registry.entries

proc surfaceState*(registry: RenderSurfaceRegistry; id: RenderSurfaceId): RenderSurfaceState =
  if id notin registry.entries:
    return rssUnmounted
  registry.entries[id].state

proc surfaceName*(registry: RenderSurfaceRegistry; id: RenderSurfaceId): string =
  if id notin registry.entries:
    return ""
  registry.entries[id].descriptor.name

proc registerSurface*(
    registry: var RenderSurfaceRegistry;
    descriptor: RenderSurfaceDescriptor
): RenderSurfaceId =
  if registry.nextId == 0'u64:
    raise newException(ValueError, "render surface identifier space exhausted")
  result = RenderSurfaceId(registry.nextId)
  inc registry.nextId
  registry.entries[result] = RenderSurfaceEntry(
    descriptor: descriptor,
    state: rssUnmounted,
    node: none(NodeId),
    placement: renderSurfacePlacement(rect(0, 0, 0, 0), rect(0, 0, 0, 0)),
    requestedVisible: false,
    effectiveVisible: false,
    lastFrameTime: none(float64)
  )

proc resizeEvent(id: RenderSurfaceId; placement: RenderSurfacePlacement): RenderSurfaceResize =
  RenderSurfaceResize(
    surface: id,
    logicalSize: size(placement.bounds.w, placement.bounds.h),
    pixelSize: placement.pixelSize,
    pixelScale: placement.pixelScale
  )

proc computedVisibility(entry: RenderSurfaceEntry): bool =
  entry.requestedVisible and entry.state == rssMounted and
    entry.placement.isRenderable

proc syncRunnableFrame(
    registry: var RenderSurfaceRegistry;
    id: RenderSurfaceId
) =
  if id notin registry.entries:
    registry.runnableFrames.excl id
    return
  let entry = registry.entries[id]
  if entry.frameRequested and entry.effectiveVisible and
      entry.state == rssMounted:
    registry.runnableFrames.incl id
  else:
    registry.runnableFrames.excl id

proc mountSurface*(
    registry: var RenderSurfaceRegistry;
    id: RenderSurfaceId;
    node: NodeId;
    placement: RenderSurfacePlacement;
    visible = true;
    revision = 0'u64
) =
  placement.validatePlacement()
  if id notin registry.entries:
    raise newException(ValueError, "render surface is not registered")
  var entry = registry.entries[id]
  if entry.state != rssUnmounted or entry.node.isSome:
    raise newException(ValueError, "render surface is already mounted")
  entry.state = rssMounted
  entry.node = some(node)
  entry.placement = placement
  entry.requestedVisible = visible
  entry.effectiveVisible = entry.computedVisibility()
  entry.revision = revision
  entry.frameRequested = false
  entry.frameNumber = 0
  entry.lastFrameTime = none(float64)
  registry.entries[id] = entry
  registry.syncRunnableFrame(id)
  if not entry.descriptor.callbacks.onMount.isNil:
    entry.descriptor.callbacks.onMount(RenderSurfaceMount(
      apiVersion: renderSurfaceApiVersion,
      surface: id,
      node: node,
      placement: placement,
      visible: entry.effectiveVisible,
      revision: revision
    ))

proc updateSurface*(
    registry: var RenderSurfaceRegistry;
    id: RenderSurfaceId;
    revision: uint64
): bool {.discardable.} =
  if id notin registry.entries:
    return false
  var entry = registry.entries[id]
  if entry.state == rssUnmounted or revision == entry.revision:
    return false
  entry.revision = revision
  registry.entries[id] = entry
  if not entry.descriptor.callbacks.onUpdate.isNil:
    entry.descriptor.callbacks.onUpdate(RenderSurfaceUpdate(
      surface: id,
      revision: revision,
      placement: entry.placement
    ))
  true

proc placeSurface*(
    registry: var RenderSurfaceRegistry;
    id: RenderSurfaceId;
    placement: RenderSurfacePlacement
): bool {.discardable.} =
  placement.validatePlacement()
  if id notin registry.entries:
    return false
  var entry = registry.entries[id]
  if entry.state == rssUnmounted:
    return false
  if entry.placement == placement:
    return false
  let resized =
    entry.placement.bounds.w != placement.bounds.w or
    entry.placement.bounds.h != placement.bounds.h or
    entry.placement.pixelScale != placement.pixelScale
  entry.placement = placement
  let previousVisibility = entry.effectiveVisible
  entry.effectiveVisible = entry.computedVisibility()
  registry.entries[id] = entry
  registry.syncRunnableFrame(id)
  if resized and not entry.descriptor.callbacks.onResize.isNil:
    entry.descriptor.callbacks.onResize(resizeEvent(id, placement))
  if not entry.descriptor.callbacks.onUpdate.isNil:
    entry.descriptor.callbacks.onUpdate(RenderSurfaceUpdate(
      surface: id,
      revision: entry.revision,
      placement: placement
    ))
  if previousVisibility != entry.effectiveVisible and
      not entry.descriptor.callbacks.onVisibility.isNil:
    entry.descriptor.callbacks.onVisibility(entry.effectiveVisible)
  true

proc setSurfaceVisible*(
    registry: var RenderSurfaceRegistry;
    id: RenderSurfaceId;
    visible: bool
): bool {.discardable.} =
  if id notin registry.entries:
    return false
  var entry = registry.entries[id]
  if entry.state == rssUnmounted or entry.requestedVisible == visible:
    return false
  let previousVisibility = entry.effectiveVisible
  entry.requestedVisible = visible
  entry.effectiveVisible = entry.computedVisibility()
  registry.entries[id] = entry
  registry.syncRunnableFrame(id)
  if previousVisibility != entry.effectiveVisible and
      not entry.descriptor.callbacks.onVisibility.isNil:
    entry.descriptor.callbacks.onVisibility(entry.effectiveVisible)
  true

proc requestSurfaceFrame*(
    registry: var RenderSurfaceRegistry;
    id: RenderSurfaceId
): bool {.discardable.} =
  if id notin registry.entries:
    return false
  var entry = registry.entries[id]
  if entry.state == rssUnmounted:
    return false
  entry.frameRequested = true
  registry.entries[id] = entry
  registry.syncRunnableFrame(id)
  true

proc surfaceNeedsFrame*(registry: RenderSurfaceRegistry; id: RenderSurfaceId): bool =
  if id notin registry.entries:
    return false
  id in registry.runnableFrames

proc needsSurfaceFrame*(registry: RenderSurfaceRegistry): bool =
  registry.runnableFrames.len > 0

proc runSurfaceFrames*(
    registry: var RenderSurfaceRegistry;
    nowSeconds: float64
): int {.discardable.} =
  if nowSeconds.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "render surface frame time must be finite")
  var pending: seq[RenderSurfaceId]
  for id in registry.runnableFrames:
    pending.add id
  pending.sort()

  for id in pending:
    if id notin registry.entries:
      continue
    var entry = registry.entries[id]
    if not entry.frameRequested or not entry.effectiveVisible or entry.state != rssMounted:
      continue
    entry.frameRequested = false
    inc entry.frameNumber
    let delta =
      if entry.lastFrameTime.isSome:
        max(0.0, nowSeconds - entry.lastFrameTime.get)
      else:
        0.0
    entry.lastFrameTime = some(nowSeconds)
    registry.entries[id] = entry
    registry.syncRunnableFrame(id)
    var frameResult = rsfIdle
    if not entry.descriptor.callbacks.onFrame.isNil:
      frameResult = entry.descriptor.callbacks.onFrame(RenderSurfaceFrame(
        surface: id,
        frameNumber: entry.frameNumber,
        nowSeconds: nowSeconds,
        deltaSeconds: delta,
        placement: entry.placement
      ))
    if id in registry.entries:
      entry = registry.entries[id]
      if entry.state != rssUnmounted and frameResult == rsfRequestNext:
        entry.frameRequested = true
      registry.entries[id] = entry
      registry.syncRunnableFrame(id)
    inc result

proc dispatchSurfaceInput*(
    registry: var RenderSurfaceRegistry;
    id: RenderSurfaceId;
    event: InputEvent;
    captured = false
): bool {.discardable.} =
  if id notin registry.entries:
    return false
  let entry = registry.entries[id]
  if entry.state != rssMounted or not entry.effectiveVisible or
      entry.descriptor.callbacks.onInput.isNil:
    return false

  var localPosition = none(Vec2)
  var inside = true
  if event.position.isSome:
    let position = event.position.get
    localPosition = some(entry.placement.toLocal(position))
    inside = entry.placement.effectiveClip.contains(position) and
      transformedRect(
        entry.placement.sourceBounds, entry.placement.transform
      ).contains(position)
    if not captured and not inside:
      return false
  entry.descriptor.callbacks.onInput(RenderSurfaceInput(
    surface: id,
    event: event,
    localPosition: localPosition,
    inside: inside,
    captured: captured
  ))

proc loseSurfaceDevice*(
    registry: var RenderSurfaceRegistry;
    id: RenderSurfaceId
): bool {.discardable.} =
  if id notin registry.entries:
    return false
  var entry = registry.entries[id]
  if entry.state != rssMounted:
    return false
  entry.state = rssDeviceLost
  let wasVisible = entry.effectiveVisible
  entry.effectiveVisible = false
  registry.entries[id] = entry
  registry.syncRunnableFrame(id)
  if wasVisible and not entry.descriptor.callbacks.onVisibility.isNil:
    entry.descriptor.callbacks.onVisibility(false)
  if not entry.descriptor.callbacks.onDeviceLost.isNil:
    entry.descriptor.callbacks.onDeviceLost()
  true

proc restoreSurfaceDevice*(
    registry: var RenderSurfaceRegistry;
    id: RenderSurfaceId
): bool {.discardable.} =
  if id notin registry.entries:
    return false
  var entry = registry.entries[id]
  if entry.state != rssDeviceLost:
    return false
  entry.state = rssMounted
  let previousVisibility = entry.effectiveVisible
  entry.effectiveVisible = entry.computedVisibility()
  registry.entries[id] = entry
  registry.syncRunnableFrame(id)
  if not entry.descriptor.callbacks.onDeviceRestored.isNil:
    entry.descriptor.callbacks.onDeviceRestored()
  if previousVisibility != entry.effectiveVisible and
      not entry.descriptor.callbacks.onVisibility.isNil:
    entry.descriptor.callbacks.onVisibility(entry.effectiveVisible)
  true

proc unmountSurface*(
    registry: var RenderSurfaceRegistry;
    id: RenderSurfaceId
): bool {.discardable.} =
  if id notin registry.entries:
    return false
  var entry = registry.entries[id]
  if entry.state == rssUnmounted:
    return false
  let wasVisible = entry.effectiveVisible
  entry.state = rssUnmounted
  entry.node = none(NodeId)
  entry.requestedVisible = false
  entry.effectiveVisible = false
  entry.frameRequested = false
  entry.lastFrameTime = none(float64)
  registry.entries[id] = entry
  registry.syncRunnableFrame(id)
  if wasVisible and not entry.descriptor.callbacks.onVisibility.isNil:
    entry.descriptor.callbacks.onVisibility(false)
  if not entry.descriptor.callbacks.onUnmount.isNil:
    entry.descriptor.callbacks.onUnmount()
  true

proc unregisterSurface*(
    registry: var RenderSurfaceRegistry;
    id: RenderSurfaceId
): bool {.discardable.} =
  if id notin registry.entries:
    return false
  discard registry.unmountSurface(id)
  registry.entries.del(id)
  registry.runnableFrames.excl id
  true

proc unmountAllSurfaces*(registry: var RenderSurfaceRegistry) =
  var ids: seq[RenderSurfaceId]
  for id in registry.entries.keys:
    ids.add id
  ids.sort()
  for id in ids:
    discard registry.unmountSurface(id)
