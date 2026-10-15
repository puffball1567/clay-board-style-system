## Revision-driven Motion Scene rendering into a directly presented GPU surface.
## Call from the UI thread; the scene and host retain their ordinary ownership.
import ../core/geometry
import ./[gpu_direct_surface, gpu_host, gpu_shader_builder, motion_scene,
  motion_scene_gpu]

type GpuMotionSceneDirect* = ref object
  host: GpuHost
  namespace: GpuNamespaceId
  sceneValue: MotionScene
  surfaceValue: GpuDirectSurface
  material: GpuMotionRectMaterial
  batch: GpuMotionRectBatch
  targets: seq[GpuResourceHandle]
  queuedRevision: uint64
  queuedTarget: GpuResourceHandle
  hasQueuedFrame: bool
  closedValue: bool

proc isClosed*(renderer: GpuMotionSceneDirect): bool =
  renderer.isNil or renderer.closedValue or renderer.surfaceValue.isClosed

proc surface*(renderer: GpuMotionSceneDirect): GpuDirectSurface =
  if renderer.isClosed:
    raise newException(ValueError, "Motion Scene GPU direct surface is closed")
  renderer.surfaceValue

proc scene*(renderer: GpuMotionSceneDirect): MotionScene =
  if renderer.isNil: nil else: renderer.sceneValue

proc newGpuMotionSceneDirect*(
    host: GpuHost; namespace: GpuNamespaceId; scene: MotionScene;
    config: GpuDirectSurfaceConfig;
    vertexArtifact, fragmentArtifact: GpuShaderArtifact
): GpuMotionSceneDirect =
  if scene.isNil:
    raise newException(ValueError, "Motion Scene GPU direct surface requires a scene")
  let viewport = scene.snapshot.viewportSize()
  if viewport.w != float32(config.width) or
      viewport.h != float32(config.height):
    raise newException(ValueError, "Motion Scene and GPU direct surface dimensions differ")
  if config.format != gtfRgba8 or config.alphaMode != gcamStraight:
    raise newException(ValueError,
      "Motion Scene GPU direct surface requires straight RGBA8 pixels")
  if host.isNil or not host.isReady() or
      not host.backendInfo().directRenderTargetPresentationSupported:
    raise newException(GpuHostError,
      "Motion Scene GPU direct surface requires render-target presentation")
  result = GpuMotionSceneDirect(host: host, namespace: namespace,
    sceneValue: scene, batch: newGpuMotionRectBatch())
  result.surfaceValue = host.newGpuDirectSurface(namespace, config)
  try:
    result.material = host.newGpuMotionRectMaterial(namespace,
      vertexArtifact, fragmentArtifact)
    let surfaceConfig = result.surfaceValue.config()
    for index in 0 ..< surfaceConfig.bufferCount:
      result.targets.add host.createGpuRenderTarget(namespace,
        GpuRenderTargetDescriptor(
          width: surfaceConfig.width,
          height: surfaceConfig.height,
          format: surfaceConfig.format,
          usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
          label: "motion-scene-direct-" & $index))
  except CatchableError:
    for target in result.targets:
      discard host.releaseGpuResource(target)
    if not result.material.isNil:
      result.material.release()
    discard result.surfaceValue.closeGpuDirectSurface()
    raise

proc queueFrame*(renderer: GpuMotionSceneDirect): bool {.discardable.} =
  ## Submit changed revisions without writing a queued or presented target.
  ## Collection frees slots; call again when backpressure has subsided.
  if renderer.isClosed or renderer.material.isClosed:
    raise newException(ValueError, "Motion Scene GPU direct surface is closed")
  let revision = renderer.sceneValue.revision
  if renderer.hasQueuedFrame and renderer.queuedRevision == revision:
    return false
  let config = renderer.surfaceValue.config()
  let viewport = renderer.sceneValue.snapshot.viewportSize()
  if viewport.w != float32(config.width) or
      viewport.h != float32(config.height):
    raise newException(ValueError, "Motion Scene and GPU direct surface dimensions differ")
  if renderer.hasQueuedFrame:
    discard renderer.surfaceValue.cancelGpuDirectSurfaceFrame(
      renderer.queuedTarget)
  if renderer.surfaceValue.retainedFrameCount() >= config.bufferCount:
    return false
  var target: GpuResourceHandle
  var found = false
  for candidate in renderer.targets:
    if not renderer.host.isGpuResourcePresentationRetained(candidate):
      target = candidate
      found = true
      break
  if not found:
    return false
  discard renderer.batch.sync(renderer.host, renderer.namespace,
    renderer.sceneValue)
  let pass = GpuGraphicsPassDescriptor(
    viewport: GpuViewport(width: config.width, height: config.height),
    renderTarget: target,
    clearColorEnabled: true,
    clearColor: GpuClearColor(alpha: 0))
  let frame = renderer.host.beginGpuFrame()
  var queued = false
  try:
    if renderer.batch.instanceBinding().instanceCount == 0:
      renderer.host.clearGpuGraphicsPass(renderer.namespace, pass)
    else:
      discard renderer.material.submit(renderer.batch, pass)
    queued = renderer.surfaceValue.queueGpuDirectSurfaceFrame(target, frame)
  finally:
    if renderer.host.isGpuFrameActive(frame):
      renderer.host.endGpuFrame(frame)
  if queued:
    renderer.queuedRevision = revision
    renderer.queuedTarget = target
    renderer.hasQueuedFrame = true
  queued

proc collectFrame*(renderer: GpuMotionSceneDirect): bool {.discardable.} =
  if renderer.isClosed:
    return false
  renderer.surfaceValue.collectGpuDirectSurfaceFrame()

proc close*(renderer: GpuMotionSceneDirect): bool {.discardable.} =
  ## Pending frames and presentation leases must drain before targets are freed.
  if renderer.isNil or renderer.closedValue:
    return false
  if not renderer.surfaceValue.isClosed and
      not renderer.surfaceValue.closeGpuDirectSurface():
    return false
  for target in renderer.targets:
    discard renderer.host.releaseGpuResource(target)
  renderer.batch.release()
  renderer.material.release()
  renderer.closedValue = true
  true
