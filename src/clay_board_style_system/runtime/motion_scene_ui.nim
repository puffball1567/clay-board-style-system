## Optional ordinary-UI attachment for CPU Motion Scene snapshots.
import std/options

import ./[invalidation, motion_scene, render_surface, ui_root]

type MotionSceneHandle* = ref object
  ## The scene may be shared by several mounts; publish each changed mount.
  scene*: MotionScene
  attachment*: CanvasHandle
  publishedRevision: uint64

proc valid*(handle: MotionSceneHandle): bool =
  not handle.isNil and not handle.scene.isNil and handle.attachment.valid and
    handle.attachment.canvas == handle.scene.canvas

proc nodeHandle*(handle: MotionSceneHandle): NodeHandle =
  handle.attachment.nodeHandle

proc motionScene*(
    root: UiRoot; scene: MotionScene; parent = none(NodeHandle);
    id = ""; code = ""; groups: openArray[string] = []
): MotionSceneHandle =
  if scene.isNil:
    raise newException(ValueError, "motion scene must not be nil")
  MotionSceneHandle(scene: scene,
    attachment: root.canvas(scene.canvas, parent, id, code, groups),
    publishedRevision: scene.revision)

proc motionScene*(
    root: UiRoot; scene: MotionScene; style: UiStyle;
    parent = none(NodeHandle); id = ""; code = "";
    groups: openArray[string] = []
): MotionSceneHandle =
  result = root.motionScene(scene, parent, id, code, groups)
  root.applyStyle(result.nodeHandle, style)

proc publish*(handle: MotionSceneHandle): bool {.discardable.} =
  ## Invalidates only the owning Canvas's paint, without scheduling frames.
  if not handle.valid or handle.publishedRevision == handle.scene.revision:
    return false
  handle.publishedRevision = handle.scene.revision
  handle.attachment.node.root.invalidate(handle.attachment.node.id, {ddPaint})
  discard handle.attachment.node.root.surfaces.updateSurface(
    handle.attachment.surface, handle.publishedRevision)
  true
