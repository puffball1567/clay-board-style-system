## Revision-driven Motion Scene -> GPU filter chain -> negotiated UI display.
## The renderer owns its shape resources and source target, but borrows the chain.
import ../core/geometry
import ./[gpu_display_surface, gpu_filter_chain,
  gpu_filter_display, gpu_host, gpu_shader_builder,
  motion_scene, motion_scene_gpu]

type GpuMotionSceneFilterDisplay* = ref object
  host: GpuHost
  namespace: GpuNamespaceId
  sceneValue: MotionScene
  filtered: GpuFilterDisplay
  material: GpuMotionRectMaterial
  batch: GpuMotionRectBatch
  sourceTarget: GpuResourceHandle
  queuedRevision: uint64
  hasQueuedFrame: bool
  refreshPending: bool
  closedValue: bool

proc defaultGpuMotionSceneFilterDisplayConfig*(
    width, height: uint32
): GpuDisplaySurfaceConfig =
  defaultGpuFilterDisplayConfig(width, height)

proc isClosed*(renderer: GpuMotionSceneFilterDisplay): bool =
  renderer.isNil or renderer.closedValue or renderer.filtered.isClosed

proc scene*(renderer: GpuMotionSceneFilterDisplay): MotionScene =
  if renderer.isNil: nil else: renderer.sceneValue

proc displaySurface*(renderer: GpuMotionSceneFilterDisplay): GpuDisplaySurface =
  if renderer.isClosed:
    raise newException(ValueError, "filtered Motion Scene GPU display is closed")
  renderer.filtered.displaySurface()

proc hasUnqueuedRevision*(renderer: GpuMotionSceneFilterDisplay): bool =
  not renderer.isClosed and
    (not renderer.hasQueuedFrame or renderer.refreshPending or
      renderer.queuedRevision != renderer.sceneValue.revision)

proc newGpuMotionSceneFilterDisplay*(
    host: GpuHost; namespace: GpuNamespaceId; scene: MotionScene;
    chain: GpuFilterChain; config: GpuDisplaySurfaceConfig;
    vertexArtifact, fragmentArtifact: GpuShaderArtifact
): GpuMotionSceneFilterDisplay =
  if scene.isNil:
    raise newException(ValueError, "filtered Motion Scene requires a scene")
  let viewport = scene.snapshot.viewportSize()
  if viewport.w != float32(config.width) or
      viewport.h != float32(config.height):
    raise newException(ValueError,
      "Motion Scene and filtered display dimensions differ")
  if host.isNil or not chain.belongsTo(host, namespace):
    raise newException(ValueError,
      "filtered Motion Scene requires a chain on the same ready host namespace")
  result = GpuMotionSceneFilterDisplay(host: host, namespace: namespace,
    sceneValue: scene, batch: newGpuMotionRectBatch())
  result.filtered = host.newGpuFilterDisplay(namespace, chain, config)
  try:
    result.material = host.newGpuMotionRectMaterial(namespace,
      vertexArtifact, fragmentArtifact)
    result.sourceTarget = host.createGpuRenderTarget(namespace,
      GpuRenderTargetDescriptor(width: config.width, height: config.height,
        format: gtfRgba8,
        usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
        label: "motion-scene-filter-source"))
  except CatchableError:
    if not result.material.isNil:
      result.material.release()
    discard result.filtered.closeGpuFilterDisplay()
    raise

proc replaceFilterChain*(
    renderer: GpuMotionSceneFilterDisplay; chain: GpuFilterChain
): bool {.discardable.} =
  if renderer.isClosed:
    raise newException(ValueError, "filtered Motion Scene GPU display is closed")
  result = renderer.filtered.replaceFilterChain(chain)
  if result:
    renderer.refreshPending = true

proc requestRefresh*(renderer: GpuMotionSceneFilterDisplay) =
  ## Reprocess a static scene after an external filter input changes.
  if renderer.isClosed:
    raise newException(ValueError, "filtered Motion Scene GPU display is closed")
  renderer.refreshPending = true

proc queueFrame*(renderer: GpuMotionSceneFilterDisplay): bool {.discardable.} =
  if renderer.isClosed or renderer.material.isClosed:
    raise newException(ValueError, "filtered Motion Scene GPU display is closed")
  if not renderer.hasUnqueuedRevision:
    return false
  let config = renderer.displaySurface().config()
  let viewport = renderer.sceneValue.snapshot.viewportSize()
  if viewport.w != float32(config.width) or
      viewport.h != float32(config.height):
    raise newException(ValueError,
      "Motion Scene and filtered display dimensions differ")
  if not renderer.filtered.canQueueGpuFilterDisplayFrame():
    return false
  discard renderer.batch.sync(renderer.host, renderer.namespace,
    renderer.sceneValue)
  let pass = GpuGraphicsPassDescriptor(
    viewport: GpuViewport(width: config.width, height: config.height),
    renderTarget: renderer.sourceTarget,
    clearColorEnabled: true,
    clearColor: GpuClearColor(alpha: 0))
  let frame = renderer.host.beginGpuFrame()
  var queued = false
  try:
    if renderer.batch.instanceBinding().instanceCount == 0:
      renderer.host.clearGpuGraphicsPass(renderer.namespace, pass)
    else:
      discard renderer.material.submit(renderer.batch, pass)
    queued = renderer.filtered.queueGpuFilterDisplayFrame(
      renderer.sourceTarget, frame, gcamPremultiplied)
  finally:
    if renderer.host.isGpuFrameActive(frame):
      renderer.host.endGpuFrame(frame)
  if queued:
    renderer.queuedRevision = renderer.sceneValue.revision
    renderer.hasQueuedFrame = true
    renderer.refreshPending = false
  queued

proc collectFrame*(renderer: GpuMotionSceneFilterDisplay): bool {.discardable.} =
  if renderer.isClosed:
    return false
  renderer.filtered.collectGpuFilterDisplayFrame()

proc close*(renderer: GpuMotionSceneFilterDisplay): bool {.discardable.} =
  ## Drain or release pending display frames before closing.
  if renderer.isNil or renderer.closedValue:
    return false
  if not renderer.filtered.isClosed and
      not renderer.filtered.closeGpuFilterDisplay():
    return false
  if renderer.host.isGpuResourceLive(renderer.sourceTarget):
    discard renderer.host.releaseGpuResource(renderer.sourceTarget)
  renderer.batch.release()
  renderer.material.release()
  renderer.closedValue = true
  true
