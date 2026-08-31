import std/options

import clay_board_style_system/core/[declaration, style_value]
import clay_board_style_system/runtime/gpu_canvas
import clay_board_style_system/runtime/ui_root

type
  GpuCanvasHandle* = object
    ## Non-owning UI attachment. The application retains and closes `canvas`.
    canvas*: GpuCanvasSurface
    raster*: RasterSurfaceHandle

  GpuVisualLayerPlacement* = enum
    ## Paints behind the ordinary children owned by the component.
    gvlUnderlay,
    ## Paints above the ordinary children without participating in input.
    gvlOverlay

  GpuVisualLayerHandle* = object
    ## A visual-only GPU layer attached to an ordinary semantic component.
    ## The owner remains responsible for layout, input, focus, and accessibility.
    owner*: NodeHandle
    attachment*: GpuCanvasHandle
    placement*: GpuVisualLayerPlacement

proc valid*(handle: GpuCanvasHandle): bool =
  not handle.canvas.isNil and not handle.canvas.isClosed and handle.raster.valid

proc nodeHandle*(handle: GpuCanvasHandle): NodeHandle =
  handle.raster.nodeHandle

proc valid*(handle: GpuVisualLayerHandle): bool =
  handle.owner.valid and handle.attachment.valid

proc nodeHandle*(handle: GpuVisualLayerHandle): NodeHandle =
  handle.attachment.nodeHandle

proc queueGpuFrame*(handle: GpuCanvasHandle): bool {.discardable.} =
  ## Queues one bounded GPU-to-raster transfer without blocking the UI thread.
  if not handle.valid:
    return false
  handle.canvas.queueGpuCanvasFrame()

proc collectGpuFrame*(handle: GpuCanvasHandle): bool {.discardable.} =
  ## Publishes the newest completed frame and invalidates only this UI surface.
  if not handle.valid or not handle.canvas.collectGpuCanvasFrame():
    return false
  handle.raster.publish()

proc queueGpuFrame*(handle: GpuVisualLayerHandle): bool {.discardable.} =
  handle.attachment.queueGpuFrame()

proc collectGpuFrame*(handle: GpuVisualLayerHandle): bool {.discardable.} =
  handle.attachment.collectGpuFrame()

proc gpuCanvas*(
    root: UiRoot;
    value: GpuCanvasSurface;
    parent = none(NodeHandle);
    id = "";
    code = "";
    groups: openArray[string] = []
): GpuCanvasHandle {.discardable.} =
  if root.isNil:
    raise newException(ValueError, "GPU canvas UiRoot cannot be nil")
  if value.isNil or value.isClosed:
    raise newException(ValueError, "GPU canvas value must be open")
  result = GpuCanvasHandle(
    canvas: value,
    raster: root.rasterSurface(
      value.rasterSurface(), parent, id, code, groups
    )
  )

proc gpuCanvas*(
    root: UiRoot;
    value: GpuCanvasSurface;
    style: UiStyle;
    parent = none(NodeHandle);
    id = "";
    code = "";
    groups: openArray[string] = []
): GpuCanvasHandle {.discardable.} =
  result = root.gpuCanvas(value, parent, id, code, groups)
  root.applyStyle(result.nodeHandle, style)

proc gpuVisualLayer*(
    root: UiRoot;
    owner: NodeHandle;
    value: GpuCanvasSurface;
    placement = gvlUnderlay;
    style = UiStyle();
    id = "";
    code = "";
    groups: openArray[string] = []
): GpuVisualLayerHandle {.discardable.} =
  ## Attaches GPU pixels to a normal CBSS component without creating a second
  ## input or semantic hierarchy. Geometry and input invariants are applied
  ## after the caller style so they cannot be accidentally overridden.
  if root.isNil:
    raise newException(ValueError, "GPU visual layer UiRoot cannot be nil")
  if not owner.valid:
    raise newException(ValueError, "GPU visual layer owner must be valid")
  if owner.root != root:
    raise newException(ValueError, "GPU visual layer owner belongs to another UiRoot")

  result = GpuVisualLayerHandle(
    owner: owner,
    attachment: root.gpuCanvas(
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
    decl(
      "z-index",
      number(if placement == gvlUnderlay: -1 else: 1)
    ),
    decl("pointer-events", keyword("none"))
  ]))
  node.setAccessibleHidden(true)
