## Ordinary UI attachment for a revision-driven GPU Motion Scene canvas.
import std/options

import ./[gpu_canvas_ui, motion_scene_gpu_canvas, ui_root]

type GpuMotionSceneHandle* = ref object
  renderer*: GpuMotionSceneCanvas
  attachment*: GpuCanvasHandle

proc valid*(handle: GpuMotionSceneHandle): bool =
  not handle.isNil and not handle.renderer.isClosed and
    handle.attachment.valid and
    handle.attachment.canvas == handle.renderer.canvas()

proc nodeHandle*(handle: GpuMotionSceneHandle): NodeHandle =
  handle.attachment.nodeHandle

proc gpuMotionScene*(
    root: UiRoot; renderer: GpuMotionSceneCanvas;
    parent = none(NodeHandle); id = ""; code = "";
    groups: openArray[string] = []
): GpuMotionSceneHandle =
  if renderer.isClosed:
    raise newException(ValueError, "Motion Scene GPU canvas must be open")
  GpuMotionSceneHandle(renderer: renderer,
    attachment: root.gpuCanvas(renderer.canvas(), parent, id, code, groups))

proc gpuMotionScene*(
    root: UiRoot; renderer: GpuMotionSceneCanvas; style: UiStyle;
    parent = none(NodeHandle); id = ""; code = "";
    groups: openArray[string] = []
): GpuMotionSceneHandle =
  result = root.gpuMotionScene(renderer, parent, id, code, groups)
  root.applyStyle(result.nodeHandle, style)

proc publish*(handle: GpuMotionSceneHandle): bool {.discardable.} =
  ## Queue only a changed scene revision. Collection publishes GPU pixels.
  if not handle.valid:
    return false
  handle.renderer.queueFrame()

proc collectGpuFrame*(handle: GpuMotionSceneHandle): bool {.discardable.} =
  if not handle.valid:
    return false
  result = handle.attachment.collectGpuFrame()
  # A newer revision may have waited for a free readback slot.
  discard handle.renderer.queueFrame()
