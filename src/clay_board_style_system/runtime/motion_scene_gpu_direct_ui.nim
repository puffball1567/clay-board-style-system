## Ordinary UI attachment for a directly presented GPU Motion Scene.
import std/options

import ./[gpu_direct_surface_ui, motion_scene_gpu_direct, ui_root]

type GpuMotionSceneDirectHandle* = ref object
  renderer*: GpuMotionSceneDirect
  attachment*: GpuDirectSurfaceHandle

proc valid*(handle: GpuMotionSceneDirectHandle): bool =
  not handle.isNil and not handle.renderer.isClosed and
    handle.attachment.valid and
    handle.attachment.surface == handle.renderer.surface()

proc nodeHandle*(handle: GpuMotionSceneDirectHandle): NodeHandle =
  handle.attachment.nodeHandle

proc gpuMotionSceneDirect*(
    root: UiRoot; renderer: GpuMotionSceneDirect;
    parent = none(NodeHandle); id = ""; code = "";
    groups: openArray[string] = []
): GpuMotionSceneDirectHandle =
  if renderer.isClosed:
    raise newException(ValueError, "Motion Scene GPU direct surface must be open")
  GpuMotionSceneDirectHandle(renderer: renderer,
    attachment: root.gpuDirectSurface(renderer.surface(), parent, id, code, groups))

proc gpuMotionSceneDirect*(
    root: UiRoot; renderer: GpuMotionSceneDirect; style: UiStyle;
    parent = none(NodeHandle); id = ""; code = "";
    groups: openArray[string] = []
): GpuMotionSceneDirectHandle =
  result = root.gpuMotionSceneDirect(renderer, parent, id, code, groups)
  root.applyStyle(result.nodeHandle, style)

proc publish*(handle: GpuMotionSceneDirectHandle): bool {.discardable.} =
  if not handle.valid:
    return false
  handle.renderer.queueFrame()

proc collectGpuFrame*(handle: GpuMotionSceneDirectHandle): bool {.discardable.} =
  if not handle.valid:
    return false
  result = handle.attachment.collectGpuFrame()
  # Retry the latest revision if presentation slots were previously full.
  discard handle.renderer.queueFrame()
