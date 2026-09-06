import std/options

import ./gpu_host

const
  DefaultGpuDirectSurfaceBuffers* = 3
  MinGpuDirectSurfaceBuffers* = 2
  MaxGpuDirectSurfaceBuffers* = 8

type
  GpuDirectSurfaceConfig* = object
    width*, height*: uint32
    format*: GpuTextureFormat
    bufferCount*: int
    acceptComputeOutput*: bool
    alphaMode*: GpuAlphaMode
    label*: string

  GpuDirectSurfaceSlotState* = enum
    gdssFree,
    gdssPending,
    gdssPresented,
    gdssRetired

  GpuDirectSurfaceSlot = object
    state: GpuDirectSurfaceSlotState
    resource: GpuResourceHandle
    completion: GpuFrameToken
    revision: uint64
    leaseCount: uint32

  GpuDirectSurface* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    generation: uint64
    configValue: GpuDirectSurfaceConfig
    slots: seq[GpuDirectSurfaceSlot]
    currentSlot: int
    nextRevision: uint64
    closedValue: bool

  GpuDirectSurfaceFrame* = object
    surface*: GpuDirectSurface
    slotIndex*: int
    resource*: GpuResourceHandle
    backendResource*: GpuBackendResourceId
    provider*: GpuProviderKind
    alphaMode*: GpuAlphaMode
    revision*: uint64
    width*, height*: uint32
    format*: GpuTextureFormat

proc defaultGpuDirectSurfaceConfig*(
    width, height: uint32;
    format = gtfRgba8
): GpuDirectSurfaceConfig =
  GpuDirectSurfaceConfig(
    width: width,
    height: height,
    format: format,
    bufferCount: DefaultGpuDirectSurfaceBuffers,
    alphaMode: gcamStraight,
    label: "gpu-direct-surface"
  )

proc normalized(config: GpuDirectSurfaceConfig): GpuDirectSurfaceConfig =
  result = config
  if result.bufferCount == 0:
    result.bufferCount = DefaultGpuDirectSurfaceBuffers
  if result.label.len == 0:
    result.label = "gpu-direct-surface"
  if result.width == 0 or result.height == 0:
    raise newException(ValueError, "GPU direct surface dimensions must be positive")
  if result.bufferCount < MinGpuDirectSurfaceBuffers or
      result.bufferCount > MaxGpuDirectSurfaceBuffers:
    raise newException(ValueError, "GPU direct surface buffer count is invalid")
  if result.label.len > maxGpuResourceLabelBytes:
    raise newException(ValueError, "GPU direct surface label is too long")

proc supportsGpuDirectSurface*(
    host: GpuHost;
    config: GpuDirectSurfaceConfig
): bool =
  if host.isNil or not host.isReady():
    return false
  let resolved = config.normalized()
  let info = host.backendInfo()
  let pathSupported =
    info.directTexturePresentationSupported or
    info.directRenderTargetPresentationSupported
  pathSupported and resolved.format in info.directPresentationFormats and
    resolved.bufferCount <= int(info.maxDirectPresentationBuffers) and
    (info.maxTextureSize == 0 or
      (resolved.width <= info.maxTextureSize and
       resolved.height <= info.maxTextureSize)) and
    (not resolved.acceptComputeOutput or
      info.directComputeOutputPresentationSupported)

proc newGpuDirectSurface*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    config: GpuDirectSurfaceConfig
): GpuDirectSurface =
  if host.isNil:
    raise newException(ValueError, "GPU direct surface host cannot be nil")
  let resolved = config.normalized()
  if not host.hasGpuNamespace(namespace):
    raise newException(GpuHostError, "GPU direct surface namespace is unknown")
  if not host.supportsGpuDirectSurface(resolved):
    raise newException(GpuHostError, "GPU direct surface is unsupported")
  GpuDirectSurface(
    host: host,
    namespace: namespace,
    generation: host.generation(),
    configValue: resolved,
    slots: newSeq[GpuDirectSurfaceSlot](resolved.bufferCount),
    currentSlot: -1
  )

proc config*(surface: GpuDirectSurface): GpuDirectSurfaceConfig =
  if surface.isNil:
    raise newException(ValueError, "GPU direct surface cannot be nil")
  surface.configValue

proc isClosed*(surface: GpuDirectSurface): bool =
  surface.isNil or surface.closedValue

proc isStale*(surface: GpuDirectSurface): bool =
  surface.isNil or surface.closedValue or not surface.host.isReady() or
    surface.generation != surface.host.generation()

proc pendingFrameCount*(surface: GpuDirectSurface): int =
  if surface.isNil:
    return 0
  for slot in surface.slots:
    if slot.state == gdssPending:
      inc result

proc retainedFrameCount*(surface: GpuDirectSurface): int =
  if surface.isNil:
    return 0
  for slot in surface.slots:
    if slot.state != gdssFree:
      inc result

proc presentedRevision*(surface: GpuDirectSurface): uint64 =
  if surface.isNil or surface.currentSlot < 0:
    0'u64
  else:
    surface.slots[surface.currentSlot].revision

proc releaseSlot(surface: GpuDirectSurface; index: int) =
  if index < 0 or index >= surface.slots.len or
      surface.slots[index].state == gdssFree:
    return
  let resource = surface.slots[index].resource
  if surface.host.isGpuResourceLive(resource):
    discard surface.host.releaseGpuResourceFromPresentation(resource)
  surface.slots[index] = GpuDirectSurfaceSlot()

proc invalidateIfStale(surface: GpuDirectSurface): bool =
  if surface.isNil or surface.closedValue:
    return true
  if surface.host.isReady() and surface.generation == surface.host.generation():
    return false
  for index in 0 ..< surface.slots.len:
    surface.releaseSlot(index)
  surface.currentSlot = -1
  true

proc validateResource(
    surface: GpuDirectSurface;
    resource: GpuResourceHandle
) =
  if surface.invalidateIfStale():
    raise newException(GpuHostError, "GPU direct surface is stale")
  if resource.namespace != surface.namespace:
    raise newException(GpuHostError, "GPU direct surface resource belongs to another namespace")
  let resourceInfo = surface.host.gpuPresentableResourceInfo(resource)
  let backendInfo = surface.host.backendInfo()
  case resourceInfo.kind
  of grkTexture:
    if not backendInfo.directTexturePresentationSupported:
      raise newException(GpuHostError, "direct texture presentation is unsupported")
    if gtuSampled notin resourceInfo.usage:
      raise newException(GpuHostError, "direct texture presentation requires sampled usage")
    if gtuStorage in resourceInfo.usage and
        (not surface.configValue.acceptComputeOutput or
          not backendInfo.directComputeOutputPresentationSupported):
      raise newException(GpuHostError, "direct compute output presentation is unsupported")
  of grkRenderTarget:
    if not backendInfo.directRenderTargetPresentationSupported:
      raise newException(GpuHostError, "direct render-target presentation is unsupported")
    if gtuSampled notin resourceInfo.usage:
      raise newException(
        GpuHostError,
        "direct render-target presentation requires sampled usage"
      )
  else:
    raise newException(GpuHostError, "GPU resource is not presentable")
  if resourceInfo.width != surface.configValue.width or
      resourceInfo.height != surface.configValue.height or
      resourceInfo.format != surface.configValue.format:
    raise newException(GpuHostError, "GPU presentation resource shape does not match the surface")
  if resourceInfo.format notin backendInfo.directPresentationFormats:
    raise newException(GpuHostError, "GPU presentation texture format is unsupported")

proc queueGpuDirectSurfaceFrame*(
    surface: GpuDirectSurface;
    resource: GpuResourceHandle;
    completion: GpuFrameToken
): bool {.discardable.} =
  surface.validateResource(resource)
  if not surface.host.isGpuFrameKnown(completion):
    raise newException(GpuHostError, "GPU direct surface completion token is invalid")
  for slot in surface.slots:
    if slot.state != gdssFree and slot.resource == resource:
      raise newException(GpuHostError, "GPU resource is already queued for presentation")
  var freeSlot = -1
  for index, slot in surface.slots:
    if slot.state == gdssFree:
      freeSlot = index
      break
  if freeSlot < 0:
    return false
  if surface.nextRevision == high(uint64):
    raise newException(ValueError, "GPU direct surface revision space exhausted")
  surface.host.retainGpuResourceForPresentation(resource)
  inc surface.nextRevision
  surface.slots[freeSlot] = GpuDirectSurfaceSlot(
    state: gdssPending,
    resource: resource,
    completion: completion,
    revision: surface.nextRevision
  )
  true

proc collectGpuDirectSurfaceFrame*(surface: GpuDirectSurface): bool {.discardable.} =
  if surface.invalidateIfStale():
    return false
  var newest = -1
  for index, slot in surface.slots:
    if slot.state == gdssPending and
        surface.host.isGpuFrameComplete(slot.completion):
      if newest < 0 or slot.revision > surface.slots[newest].revision:
        newest = index
  if newest < 0:
    return false

  for index in 0 ..< surface.slots.len:
    if index == newest:
      continue
    case surface.slots[index].state
    of gdssPending:
      if surface.host.isGpuFrameComplete(surface.slots[index].completion):
        surface.releaseSlot(index)
    of gdssPresented:
      surface.slots[index].state = gdssRetired
      if surface.slots[index].leaseCount == 0:
        surface.releaseSlot(index)
    of gdssRetired:
      if surface.slots[index].leaseCount == 0:
        surface.releaseSlot(index)
    of gdssFree:
      discard

  surface.slots[newest].state = gdssPresented
  surface.currentSlot = newest
  true

proc acquireGpuDirectSurfaceFrame*(
    surface: GpuDirectSurface
): Option[GpuDirectSurfaceFrame] =
  if surface.invalidateIfStale() or surface.currentSlot < 0:
    return none(GpuDirectSurfaceFrame)
  let index = surface.currentSlot
  if surface.slots[index].state != gdssPresented or
      surface.slots[index].leaseCount == high(uint32):
    return none(GpuDirectSurfaceFrame)
  inc surface.slots[index].leaseCount
  some(GpuDirectSurfaceFrame(
    surface: surface,
    slotIndex: index,
    resource: surface.slots[index].resource,
    backendResource: surface.host.gpuPresentableResourceInfo(
      surface.slots[index].resource
    ).backendResource,
    provider: surface.host.provider(),
    alphaMode: surface.configValue.alphaMode,
    revision: surface.slots[index].revision,
    width: surface.configValue.width,
    height: surface.configValue.height,
    format: surface.configValue.format
  ))

proc release*(frame: var GpuDirectSurfaceFrame): bool {.discardable.} =
  let surface = frame.surface
  if surface.isNil or frame.slotIndex < 0 or
      frame.slotIndex >= surface.slots.len:
    return false
  let index = frame.slotIndex
  if surface.slots[index].leaseCount == 0 or
      surface.slots[index].revision != frame.revision or
      surface.slots[index].resource != frame.resource:
    return false
  dec surface.slots[index].leaseCount
  if surface.slots[index].state == gdssRetired and
      surface.slots[index].leaseCount == 0:
    surface.releaseSlot(index)
  frame = GpuDirectSurfaceFrame(slotIndex: -1)
  true

proc closeGpuDirectSurface*(surface: GpuDirectSurface): bool {.discardable.} =
  if surface.isNil or surface.closedValue:
    return false
  discard surface.invalidateIfStale()
  for slot in surface.slots:
    if slot.leaseCount != 0:
      return false
    if slot.state == gdssPending and
        not surface.host.isGpuFrameComplete(slot.completion):
      return false
  for index in 0 ..< surface.slots.len:
    surface.releaseSlot(index)
  surface.currentSlot = -1
  surface.closedValue = true
  true
