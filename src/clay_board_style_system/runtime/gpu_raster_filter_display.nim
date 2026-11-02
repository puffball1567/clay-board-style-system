## Retained RasterSurface -> GPU filter chain -> negotiated UI display.
## Owns the upload texture and bounded reusable output/scratch targets.
import ../core/raster_surface
import ./[gpu_canvas, gpu_display_surface, gpu_filter_chain, gpu_host,
  gpu_raster_texture]

type
  GpuRasterFilterDisplay* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    chain: GpuFilterChain
    upload: GpuRasterTexture
    display: GpuDisplaySurface
    scratch: array[3, GpuResourceHandle]
    outputs: seq[GpuResourceHandle]
    nextOutput: int
    lastQueuedRevisionValue: uint64
    completedEpochValue: uint64
    closedValue: bool

proc defaultGpuRasterFilterDisplayConfig*(
    width, height: uint32
): GpuDisplaySurfaceConfig =
  result = defaultGpuDisplaySurfaceConfig(width, height)
  result.alphaMode = gcamPremultiplied

proc releaseTargets(surface: GpuRasterFilterDisplay) =
  if surface.isNil or surface.host.isNil:
    return
  for handle in surface.outputs:
    if surface.host.isGpuResourceLive(handle):
      discard surface.host.releaseGpuResource(handle)
  for handle in surface.scratch:
    if surface.host.isGpuResourceLive(handle):
      discard surface.host.releaseGpuResource(handle)

proc newGpuRasterFilterDisplay*(
    host: GpuHost; namespace: GpuNamespaceId;
    source: RasterSurface; chain: GpuFilterChain;
    config: GpuDisplaySurfaceConfig
): GpuRasterFilterDisplay =
  if host.isNil or not host.isReady() or not host.hasGpuNamespace(namespace):
    raise newException(ValueError,
      "GPU raster filter display requires a ready host namespace")
  if source.isNil or source.width <= 0 or source.height <= 0 or
      uint64(source.width) > uint64(high(uint32)) or
      uint64(source.height) > uint64(high(uint32)):
    raise newException(ValueError,
      "GPU raster filter display source dimensions are invalid")
  if not chain.belongsTo(host, namespace):
    raise newException(ValueError,
      "GPU raster filter chain belongs to another host namespace")
  if config.width != uint32(source.width) or
      config.height != uint32(source.height) or
      config.format != gtfRgba8 or
      config.alphaMode != gcamPremultiplied:
    raise newException(ValueError,
      "GPU raster filter display requires matching premultiplied RGBA8 configuration")
  result = GpuRasterFilterDisplay(host: host, namespace: namespace, chain: chain)
  try:
    result.display = host.newGpuDisplaySurface(namespace, config)
    result.upload = host.newGpuRasterTexture(namespace, source)
    for index in 0 ..< result.scratch.len:
      result.scratch[index] = host.createGpuRenderTarget(namespace,
        GpuRenderTargetDescriptor(
          width: config.width, height: config.height,
          format: gtfRgba8,
          usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
          label: "gpu-raster-filter-scratch-" & $index))
    for index in 0 ..< result.display.config().bufferCount:
      result.outputs.add host.createGpuRenderTarget(namespace,
        GpuRenderTargetDescriptor(
          width: config.width, height: config.height,
          format: gtfRgba8,
          usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
          label: "gpu-raster-filter-output-" & $index))
  except CatchableError:
    result.releaseTargets()
    if not result.upload.isNil:
      discard result.upload.closeGpuRasterTexture()
    if not result.display.isNil:
      discard result.display.closeGpuDisplaySurface()
    raise

proc isClosed*(surface: GpuRasterFilterDisplay): bool =
  surface.isNil or surface.closedValue

proc isStale*(surface: GpuRasterFilterDisplay): bool =
  surface.isClosed or not surface.host.isReady() or
    surface.upload.isStale or surface.display.isClosed or
    not surface.chain.belongsTo(surface.host, surface.namespace)

proc displaySurface*(surface: GpuRasterFilterDisplay): GpuDisplaySurface =
  if surface.isStale:
    raise newException(GpuHostError, "GPU raster filter display is stale")
  surface.display

proc source*(surface: GpuRasterFilterDisplay): RasterSurface =
  if surface.isStale:
    raise newException(GpuHostError, "GPU raster filter display is stale")
  surface.upload.source()

proc lastQueuedRevision*(surface: GpuRasterFilterDisplay): uint64 =
  if surface.isNil: 0'u64 else: surface.lastQueuedRevisionValue

proc completedEpoch*(surface: GpuRasterFilterDisplay): uint64 =
  ## Advances when this adapter collects a completed display frame.
  if surface.isNil: 0'u64 else: surface.completedEpochValue

proc collectGpuRasterFrame*(
    surface: GpuRasterFilterDisplay
): bool {.discardable.} =
  ## Collect once for all UI consumers, publishing fallback pixels as needed.
  if surface.isStale:
    return false
  let display = surface.display
  if not display.collectGpuDisplayFrame():
    return false
  if display.path in {gdspReadback, gdspHybrid}:
    discard display.readbackSurface().rasterSurface().publish()
  inc surface.completedEpochValue
  true

proc queueUpdatedGpuRasterFrame*(
    surface: GpuRasterFilterDisplay; frame: GpuFrameToken
): bool {.discardable.} =
  ## Called in the source host frame after publishing RasterSurface changes.
  ## Returns false for unchanged pixels or bounded display backpressure.
  if surface.isStale:
    raise newException(GpuHostError, "GPU raster filter display is stale")
  if not surface.host.isGpuFrameActive(frame):
    raise newException(GpuHostError,
      "GPU raster filter display requires its active host frame")
  let revision = surface.upload.source().revision
  if revision == surface.lastQueuedRevisionValue:
    return false
  var selected = -1
  for offset in 0 ..< surface.outputs.len:
    let index = (surface.nextOutput + offset) mod surface.outputs.len
    if not surface.host.isGpuResourcePresentationRetained(surface.outputs[index]):
      selected = index
      break
  if selected < 0:
    return false
  let output = surface.outputs[selected]
  discard surface.upload.syncGpuRasterTexture()
  discard surface.chain.submit(surface.upload.texture(), output,
    surface.scratch, gcamStraight)
  if not surface.display.queueGpuDisplayFrame(output, frame):
    return false
  surface.lastQueuedRevisionValue = revision
  surface.nextOutput = (selected + 1) mod surface.outputs.len
  true

proc closeGpuRasterFilterDisplay*(
    surface: GpuRasterFilterDisplay
): bool {.discardable.} =
  if surface.isClosed:
    return false
  if surface.host.hasActiveGpuFrame():
    raise newException(GpuHostError,
      "GPU raster filter display cannot close during a frame")
  if not surface.display.isClosed and
      not surface.display.closeGpuDisplaySurface():
    return false
  surface.releaseTargets()
  discard surface.upload.closeGpuRasterTexture()
  surface.closedValue = true
  true
