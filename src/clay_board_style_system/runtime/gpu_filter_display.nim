## Retained GPU-owned source -> filter chain -> negotiated UI display.
## Owns bounded reusable output and scratch targets, but not source or materials.
import ../core/raster_surface
import ./[gpu_canvas, gpu_display_surface,
  gpu_filter_chain, gpu_host]

type
  GpuFilterDisplay* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    chain: GpuFilterChain
    display: GpuDisplaySurface
    scratch: array[3, GpuResourceHandle]
    outputs: seq[GpuResourceHandle]
    nextOutput: int
    closedValue: bool

proc defaultGpuFilterDisplayConfig*(
    width, height: uint32
): GpuDisplaySurfaceConfig =
  result = defaultGpuDisplaySurfaceConfig(width, height)
  result.alphaMode = gcamPremultiplied

proc releaseTargets(surface: GpuFilterDisplay) =
  if surface.isNil or surface.host.isNil:
    return
  for handle in surface.outputs:
    if surface.host.isGpuResourceLive(handle):
      discard surface.host.releaseGpuResource(handle)
  for handle in surface.scratch:
    if surface.host.isGpuResourceLive(handle):
      discard surface.host.releaseGpuResource(handle)

proc newGpuFilterDisplay*(
    host: GpuHost; namespace: GpuNamespaceId;
    chain: GpuFilterChain; config: GpuDisplaySurfaceConfig
): GpuFilterDisplay =
  if host.isNil or not host.isReady() or not host.hasGpuNamespace(namespace):
    raise newException(ValueError,
      "GPU filter display requires a ready host namespace")
  if not chain.belongsTo(host, namespace):
    raise newException(ValueError,
      "GPU filter display chain belongs to another host namespace")
  if config.width == 0 or config.height == 0 or
      config.format != gtfRgba8 or
      config.alphaMode != gcamPremultiplied:
    raise newException(ValueError,
      "GPU filter display requires premultiplied RGBA8 configuration")
  result = GpuFilterDisplay(host: host, namespace: namespace, chain: chain)
  try:
    result.display = host.newGpuDisplaySurface(namespace, config)
    let resolved = result.display.config()
    for index in 0 ..< result.scratch.len:
      result.scratch[index] = host.createGpuRenderTarget(namespace,
        GpuRenderTargetDescriptor(
          width: resolved.width, height: resolved.height,
          format: gtfRgba8,
          usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
          label: "gpu-filter-display-scratch-" & $index))
    for index in 0 ..< resolved.bufferCount:
      result.outputs.add host.createGpuRenderTarget(namespace,
        GpuRenderTargetDescriptor(
          width: resolved.width, height: resolved.height,
          format: gtfRgba8,
          usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
          label: "gpu-filter-display-output-" & $index))
  except CatchableError:
    result.releaseTargets()
    if not result.display.isNil:
      discard result.display.closeGpuDisplaySurface()
    raise

proc isClosed*(surface: GpuFilterDisplay): bool =
  surface.isNil or surface.closedValue

proc isStale*(surface: GpuFilterDisplay): bool =
  if surface.isClosed or not surface.host.isReady() or
      surface.display.isClosed or
      not surface.chain.belongsTo(surface.host, surface.namespace):
    return true
  for handle in surface.outputs:
    if not surface.host.isGpuResourceLive(handle): return true
  for handle in surface.scratch:
    if not surface.host.isGpuResourceLive(handle): return true
  false

proc displaySurface*(surface: GpuFilterDisplay): GpuDisplaySurface =
  if surface.isStale:
    raise newException(GpuHostError, "GPU filter display is stale")
  surface.display

proc replaceFilterChain*(
    surface: GpuFilterDisplay; chain: GpuFilterChain
): bool {.discardable.} =
  if surface.isStale:
    raise newException(GpuHostError, "GPU filter display is stale")
  if not chain.belongsTo(surface.host, surface.namespace):
    raise newException(ValueError,
      "GPU filter display chain belongs to another host namespace")
  if chain == surface.chain:
    return false
  surface.chain = chain
  true

proc queueGpuFilterDisplayFrame*(
    surface: GpuFilterDisplay;
    source: GpuResourceHandle; frame: GpuFrameToken;
    sourceAlphaMode = gcamStraight
): bool {.discardable.} =
  ## Each call represents one new GPU image revision. A full ring returns
  ## false without filtering; the caller may retry after collection.
  if surface.isStale:
    raise newException(GpuHostError, "GPU filter display is stale")
  if not surface.host.isGpuFrameActive(frame):
    raise newException(GpuHostError,
      "GPU filter display requires its active host frame")
  var selected = -1
  for offset in 0 ..< surface.outputs.len:
    let index = (surface.nextOutput + offset) mod surface.outputs.len
    if not surface.host.isGpuResourcePresentationRetained(surface.outputs[index]):
      selected = index
      break
  if selected < 0:
    return false
  if not surface.display.queueFilteredGpuDisplayFrame(surface.chain,
      source, surface.outputs[selected], surface.scratch, frame,
      sourceAlphaMode):
    return false
  surface.nextOutput = (selected + 1) mod surface.outputs.len
  true

proc collectGpuFilterDisplayFrame*(
    surface: GpuFilterDisplay
): bool {.discardable.} =
  ## Poll without waiting and publish the readback fallback when available.
  if surface.isStale or not surface.display.collectGpuDisplayFrame():
    return false
  if surface.display.path in {gdspReadback, gdspHybrid}:
    discard surface.display.readbackSurface().rasterSurface().publish()
  true

proc closeGpuFilterDisplay*(
    surface: GpuFilterDisplay
): bool {.discardable.} =
  if surface.isClosed:
    return false
  if surface.host.hasActiveGpuFrame():
    raise newException(GpuHostError,
      "GPU filter display cannot close during a frame")
  if not surface.display.isClosed and
      not surface.display.closeGpuDisplaySurface():
    return false
  surface.releaseTargets()
  surface.closedValue = true
  true
