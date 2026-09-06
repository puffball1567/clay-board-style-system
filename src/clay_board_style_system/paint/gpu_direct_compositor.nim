import std/options

import ../core/geometry
import ../runtime/gpu_direct_surface
import ./paint_command

type
  GpuDirectCompositeStatus* = enum
    gdcsNoFrame,
    gdcsPresented,
    gdcsRetry,
    gdcsUnsupported,
    gdcsFailed

  GpuDirectCompositeRequest* = object
    frame*: GpuDirectSurfaceFrame
    destination*: Rect
    opacity*: float32

  GpuDirectCompositeProc* = proc(
    request: GpuDirectCompositeRequest
  ): GpuDirectCompositeStatus {.closure.}

proc compositeGpuDirectSurface*(
    command: PaintCommand;
    compositor: GpuDirectCompositeProc
): GpuDirectCompositeStatus =
  ## Acquires the published frame only for the duration of backend submission.
  ## The surrounding renderer remains responsible for applying the active
  ## transform, clip, layer, and stacking scopes from the paint stream.
  if command.kind != pcDrawGpuDirectSurface or compositor.isNil:
    return gdcsUnsupported
  let acquired = command.gpuDirectSurface.acquireGpuDirectSurfaceFrame()
  if acquired.isNone:
    return gdcsNoFrame
  var frame = acquired.get
  try:
    result = compositor(GpuDirectCompositeRequest(
      frame: frame,
      destination: command.gpuSurfaceRect,
      opacity: command.gpuSurfaceOpacity
    ))
  finally:
    discard frame.release()
