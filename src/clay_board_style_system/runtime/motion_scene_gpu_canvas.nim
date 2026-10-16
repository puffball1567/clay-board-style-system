## Revision-driven Motion Scene rendering into a GPU Canvas readback surface.
## Call from the UI thread; the scene and host retain their ordinary ownership.
import ../core/[geometry, raster_surface]
import ./[gpu_canvas, gpu_host, gpu_shader_builder, motion_scene,
  motion_scene_gpu]

type GpuMotionSceneCanvas* = ref object
  host: GpuHost
  namespace: GpuNamespaceId
  sceneValue: MotionScene
  canvasValue: GpuCanvasSurface
  material: GpuMotionRectMaterial
  batch: GpuMotionRectBatch
  queuedRevision: uint64
  queuedFrameNumber: uint64
  closedValue: bool

proc defaultGpuMotionSceneCanvasConfig*(width, height: uint32): GpuCanvasConfig =
  result = defaultGpuCanvasConfig(width, height)
  result.alphaMode = gcamPremultiplied

proc isClosed*(renderer: GpuMotionSceneCanvas): bool =
  renderer.isNil or renderer.closedValue or renderer.canvasValue.isClosed

proc canvas*(renderer: GpuMotionSceneCanvas): GpuCanvasSurface =
  if renderer.isClosed:
    raise newException(ValueError, "Motion Scene GPU canvas is closed")
  renderer.canvasValue

proc scene*(renderer: GpuMotionSceneCanvas): MotionScene =
  if renderer.isNil: nil else: renderer.sceneValue

proc newGpuMotionSceneCanvas*(
    host: GpuHost; namespace: GpuNamespaceId; scene: MotionScene;
    config: GpuCanvasConfig;
    vertexArtifact, fragmentArtifact: GpuShaderArtifact
): GpuMotionSceneCanvas =
  if scene.isNil:
    raise newException(ValueError, "Motion Scene GPU canvas requires a scene")
  let viewport = scene.snapshot.viewportSize()
  if viewport.w != float32(config.width) or
      viewport.h != float32(config.height):
    raise newException(ValueError, "Motion Scene and GPU canvas dimensions differ")
  if config.format != gtfRgba8 or config.alphaMode != gcamPremultiplied:
    raise newException(ValueError,
      "Motion Scene GPU canvas requires premultiplied RGBA8 input")
  result = GpuMotionSceneCanvas(host: host, namespace: namespace,
    sceneValue: scene, batch: newGpuMotionRectBatch())
  result.canvasValue = host.newGpuCanvasSurface(namespace, config)
  try:
    result.material = host.newGpuMotionRectMaterial(namespace,
      vertexArtifact, fragmentArtifact)
  except CatchableError:
    discard result.canvasValue.closeGpuCanvasSurface()
    raise

proc queueFrame*(renderer: GpuMotionSceneCanvas): bool {.discardable.} =
  ## Submit only changed revisions. A full readback ring applies backpressure;
  ## call again after collection to render the latest scene revision.
  if renderer.isClosed or renderer.material.isClosed:
    raise newException(ValueError, "Motion Scene GPU canvas is closed")
  let revision = renderer.sceneValue.revision
  if renderer.queuedFrameNumber != 0 and renderer.queuedRevision == revision:
    return false
  let config = renderer.canvasValue.config()
  let viewport = renderer.sceneValue.snapshot.viewportSize()
  if viewport.w != float32(config.width) or
      viewport.h != float32(config.height):
    raise newException(ValueError, "Motion Scene and GPU canvas dimensions differ")
  if renderer.queuedFrameNumber != 0:
    discard renderer.canvasValue.cancelGpuCanvasFrame(
      renderer.queuedFrameNumber)
  if renderer.canvasValue.pendingFrameCount() >= config.readbackSlots:
    return false
  discard renderer.batch.sync(renderer.host, renderer.namespace,
    renderer.sceneValue)
  let pass = GpuGraphicsPassDescriptor(
    viewport: GpuViewport(width: config.width, height: config.height),
    renderTarget: renderer.canvasValue.renderTarget(),
    clearColorEnabled: true,
    clearColor: GpuClearColor(alpha: 0))
  let frame = renderer.host.beginGpuFrame()
  var queued = false
  try:
    if renderer.batch.instanceBinding().instanceCount == 0:
      renderer.host.clearGpuGraphicsPass(renderer.namespace, pass)
    else:
      discard renderer.material.submit(renderer.batch, pass)
    queued = renderer.canvasValue.queueGpuCanvasFrame()
  finally:
    if renderer.host.isGpuFrameActive(frame):
      renderer.host.endGpuFrame(frame)
  if queued:
    renderer.queuedRevision = revision
    renderer.queuedFrameNumber = renderer.canvasValue.queuedFrameNumber()
  queued

proc collectFrame*(renderer: GpuMotionSceneCanvas): bool {.discardable.} =
  if renderer.isClosed:
    return false
  if not renderer.canvasValue.collectGpuCanvasFrame():
    return false
  discard renderer.canvasValue.rasterSurface().publish()
  true

proc close*(renderer: GpuMotionSceneCanvas): bool {.discardable.} =
  ## A pending readback must be collected or drained before closing.
  if renderer.isNil or renderer.closedValue:
    return false
  if not renderer.canvasValue.isClosed and
      not renderer.canvasValue.closeGpuCanvasSurface():
    return false
  renderer.batch.release()
  renderer.material.release()
  renderer.closedValue = true
  true
