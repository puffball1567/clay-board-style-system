import std/options

import clay_board_style_system/runtime/gpu_canvas
import clay_board_style_system/runtime/ui_root

type GpuCanvasHandle* = object
  ## Non-owning UI attachment. The application retains and closes `canvas`.
  canvas*: GpuCanvasSurface
  raster*: RasterSurfaceHandle

proc valid*(handle: GpuCanvasHandle): bool =
  not handle.canvas.isNil and not handle.canvas.isClosed and handle.raster.valid

proc nodeHandle*(handle: GpuCanvasHandle): NodeHandle =
  handle.raster.nodeHandle

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
