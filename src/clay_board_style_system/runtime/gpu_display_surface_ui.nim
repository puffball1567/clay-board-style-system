import std/options

import ../core/[declaration, raster_surface, style_value]
import ./[canvas, gpu_canvas, gpu_display_surface, gpu_host, invalidation, ui_root]

type
  GpuDisplaySurfaceHandle* = object
    root* {.cursor.}: UiRoot
    surface*: GpuDisplaySurface
    canvas*: CanvasHandle

  GpuDisplayVisualLayerPlacement* = enum
    gdsvUnderlay,
    gdsvOverlay

  GpuDisplayVisualLayerHandle* = object
    owner*: NodeHandle
    attachment*: GpuDisplaySurfaceHandle
    placement*: GpuDisplayVisualLayerPlacement

proc valid*(handle: GpuDisplaySurfaceHandle): bool =
  not handle.root.isNil and not handle.surface.isNil and
    not handle.surface.isClosed and handle.canvas.node.valid

proc valid*(handle: GpuDisplayVisualLayerHandle): bool =
  handle.owner.valid and handle.attachment.valid

proc nodeHandle*(handle: GpuDisplaySurfaceHandle): NodeHandle =
  handle.canvas.node

proc nodeHandle*(handle: GpuDisplayVisualLayerHandle): NodeHandle =
  handle.attachment.nodeHandle

proc queueGpuFrame*(
    handle: GpuDisplaySurfaceHandle;
    resource: GpuResourceHandle;
    completion: GpuFrameToken
): bool {.discardable.} =
  if not handle.valid:
    return false
  handle.surface.queueGpuDisplayFrame(resource, completion)

proc collectGpuFrame*(handle: GpuDisplaySurfaceHandle): bool {.discardable.} =
  if not handle.valid or not handle.surface.collectGpuDisplayFrame():
    return false
  if handle.surface.path == gdspReadback:
    discard handle.surface.readbackSurface().rasterSurface().publish()
  handle.root.invalidate(handle.canvas.node.id, {ddPaint})
  true

proc queueGpuFrame*(
    handle: GpuDisplayVisualLayerHandle;
    resource: GpuResourceHandle;
    completion: GpuFrameToken
): bool {.discardable.} =
  handle.attachment.queueGpuFrame(resource, completion)

proc collectGpuFrame*(
    handle: GpuDisplayVisualLayerHandle
): bool {.discardable.} =
  handle.attachment.collectGpuFrame()

proc gpuDisplaySurface*(
    root: UiRoot;
    value: GpuDisplaySurface;
    parent = none(NodeHandle);
    id = "";
    code = "";
    groups: openArray[string] = []
): GpuDisplaySurfaceHandle {.discardable.} =
  if root.isNil:
    raise newException(ValueError, "GPU display surface UiRoot cannot be nil")
  if value.isNil or value.isClosed:
    raise newException(ValueError, "GPU display surface value must be open")
  let drawing = newCanvas2D()
  case value.path
  of gdspDirect:
    drawing.drawGpuDirectSurfaceToContent(value.directSurface())
  of gdspReadback:
    drawing.drawRasterSurfaceToContent(value.readbackSurface().rasterSurface())
  result = GpuDisplaySurfaceHandle(
    root: root,
    surface: value,
    canvas: root.canvas(drawing, parent, id, code, groups)
  )
  let config = value.config()
  root.applyStyle(result.nodeHandle, uiStyle([
    decl("width", px(config.width)),
    decl("height", px(config.height))
  ]))

proc gpuDisplaySurface*(
    root: UiRoot;
    value: GpuDisplaySurface;
    style: UiStyle;
    parent = none(NodeHandle);
    id = "";
    code = "";
    groups: openArray[string] = []
): GpuDisplaySurfaceHandle {.discardable.} =
  result = root.gpuDisplaySurface(value, parent, id, code, groups)
  root.applyStyle(result.nodeHandle, style)

proc gpuDisplayVisualLayer*(
    root: UiRoot;
    owner: NodeHandle;
    value: GpuDisplaySurface;
    placement = gdsvUnderlay;
    style = UiStyle();
    id = "";
    code = "";
    groups: openArray[string] = []
): GpuDisplayVisualLayerHandle {.discardable.} =
  if root.isNil:
    raise newException(ValueError, "GPU display visual layer UiRoot cannot be nil")
  if not owner.valid or owner.root != root:
    raise newException(ValueError, "GPU display visual layer owner is invalid")
  result = GpuDisplayVisualLayerHandle(
    owner: owner,
    attachment: root.gpuDisplaySurface(
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
    decl("z-index", number(if placement == gdsvUnderlay: -1 else: 1)),
    decl("pointer-events", keyword("none"))
  ]))
  node.setAccessibleHidden(true)
