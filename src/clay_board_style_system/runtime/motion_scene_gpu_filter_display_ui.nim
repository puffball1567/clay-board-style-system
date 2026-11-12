## Ordinary UI attachment for a GPU-filtered Motion Scene display.
import std/options

import ./[gpu_display_surface_ui, motion_scene_gpu_filter_display, ui_root]

type GpuMotionSceneFilterDisplayHandle* = ref object
  renderer*: GpuMotionSceneFilterDisplay
  attachment*: GpuDisplaySurfaceHandle

proc valid*(handle: GpuMotionSceneFilterDisplayHandle): bool =
  not handle.isNil and not handle.renderer.isClosed and
    handle.attachment.valid and
    handle.attachment.surface == handle.renderer.displaySurface()

proc nodeHandle*(handle: GpuMotionSceneFilterDisplayHandle): NodeHandle =
  handle.attachment.nodeHandle

proc gpuMotionSceneFilterDisplay*(
    root: UiRoot; renderer: GpuMotionSceneFilterDisplay;
    parent = none(NodeHandle); id = ""; code = "";
    groups: openArray[string] = []
): GpuMotionSceneFilterDisplayHandle =
  if renderer.isClosed:
    raise newException(ValueError, "filtered Motion Scene GPU display must be open")
  GpuMotionSceneFilterDisplayHandle(renderer: renderer,
    attachment: root.gpuDisplaySurface(
      renderer.displaySurface(), parent, id, code, groups))

proc gpuMotionSceneFilterDisplay*(
    root: UiRoot; renderer: GpuMotionSceneFilterDisplay; style: UiStyle;
    parent = none(NodeHandle); id = ""; code = "";
    groups: openArray[string] = []
): GpuMotionSceneFilterDisplayHandle =
  result = root.gpuMotionSceneFilterDisplay(renderer, parent, id, code, groups)
  root.applyStyle(result.nodeHandle, style)

proc publish*(handle: GpuMotionSceneFilterDisplayHandle): bool {.discardable.} =
  if not handle.valid:
    return false
  handle.renderer.queueFrame()

proc collectGpuFrame*(
    handle: GpuMotionSceneFilterDisplayHandle
): bool {.discardable.} =
  if not handle.valid:
    return false
  result = handle.attachment.collectGpuFrame()
  # Retry the latest revision after display backpressure subsides.
  discard handle.renderer.queueFrame()
