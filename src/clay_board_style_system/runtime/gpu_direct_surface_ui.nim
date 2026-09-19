import std/options

import ../core/[declaration, style_value]
import ./[canvas, gpu_direct_surface, gpu_host, invalidation, ui_root]

type
  GpuDirectSurfaceHandle* = object
    root* {.cursor.}: UiRoot
    surface*: GpuDirectSurface
    canvas*: CanvasHandle

  GpuDirectVisualLayerPlacement* = enum
    gdvlUnderlay,
    gdvlOverlay

  GpuDirectVisualLayerHandle* = object
    owner*: NodeHandle
    attachment*: GpuDirectSurfaceHandle
    placement*: GpuDirectVisualLayerPlacement

proc valid*(handle: GpuDirectSurfaceHandle): bool =
  not handle.root.isNil and not handle.surface.isNil and
    not handle.surface.isClosed and handle.canvas.node.valid

proc valid*(handle: GpuDirectVisualLayerHandle): bool =
  handle.owner.valid and handle.attachment.valid

proc nodeHandle*(handle: GpuDirectSurfaceHandle): NodeHandle =
  handle.canvas.node

proc nodeHandle*(handle: GpuDirectVisualLayerHandle): NodeHandle =
  handle.attachment.nodeHandle

proc queueGpuFrame*(
    handle: GpuDirectSurfaceHandle;
    resource: GpuResourceHandle;
    completion: GpuFrameToken
): bool {.discardable.} =
  if not handle.valid:
    return false
  handle.surface.queueGpuDirectSurfaceFrame(resource, completion)

proc collectGpuFrame*(handle: GpuDirectSurfaceHandle): bool {.discardable.} =
  if not handle.valid or not handle.surface.collectGpuDirectSurfaceFrame():
    return false
  handle.root.invalidate(handle.canvas.node.id, {ddPaint})
  true

proc queueGpuFrame*(
    handle: GpuDirectVisualLayerHandle;
    resource: GpuResourceHandle;
    completion: GpuFrameToken
): bool {.discardable.} =
  handle.attachment.queueGpuFrame(resource, completion)

proc collectGpuFrame*(
    handle: GpuDirectVisualLayerHandle
): bool {.discardable.} =
  handle.attachment.collectGpuFrame()

proc gpuDirectSurface*(
    root: UiRoot;
    value: GpuDirectSurface;
    parent = none(NodeHandle);
    id = "";
    code = "";
    groups: openArray[string] = []
): GpuDirectSurfaceHandle {.discardable.} =
  if root.isNil:
    raise newException(ValueError, "GPU direct surface UiRoot cannot be nil")
  if value.isNil or value.isClosed:
    raise newException(ValueError, "GPU direct surface value must be open")
  let drawing = newCanvas2D()
  drawing.drawGpuDirectSurfaceToContent(value)
  result = GpuDirectSurfaceHandle(
    root: root,
    surface: value,
    canvas: root.canvas(drawing, parent, id, code, groups)
  )
  let config = value.config()
  root.applyStyle(result.nodeHandle, uiStyle([
    decl("width", px(config.width)),
    decl("height", px(config.height))
  ]))

proc gpuDirectSurface*(
    root: UiRoot;
    value: GpuDirectSurface;
    style: UiStyle;
    parent = none(NodeHandle);
    id = "";
    code = "";
    groups: openArray[string] = []
): GpuDirectSurfaceHandle {.discardable.} =
  result = root.gpuDirectSurface(value, parent, id, code, groups)
  root.applyStyle(result.nodeHandle, style)

proc gpuDirectVisualLayer*(
    root: UiRoot;
    owner: NodeHandle;
    value: GpuDirectSurface;
    placement = gdvlUnderlay;
    style = UiStyle();
    id = "";
    code = "";
    groups: openArray[string] = []
): GpuDirectVisualLayerHandle {.discardable.} =
  if root.isNil:
    raise newException(ValueError, "GPU direct visual layer UiRoot cannot be nil")
  if not owner.valid or owner.root != root:
    raise newException(ValueError, "GPU direct visual layer owner is invalid")
  result = GpuDirectVisualLayerHandle(
    owner: owner,
    attachment: root.gpuDirectSurface(
      value,
      parent = some(owner),
      id = id,
      code = code,
      groups = groups
    ),
    placement: placement
  )
  let node = result.nodeHandle
  root.applyStyle(node, style)
  root.applyStyle(node, uiStyle([
    decl("position", keyword("absolute")),
    decl("inset", px(0)),
    decl("width", percent(100)),
    decl("height", percent(100)),
    decl("z-index", number(if placement == gdvlUnderlay: -1 else: 1)),
    decl("pointer-events", keyword("none"))
  ]))
  node.setAccessibleHidden(true)
