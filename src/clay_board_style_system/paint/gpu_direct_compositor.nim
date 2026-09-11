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

  GpuDirectCompositeTargetKind* = enum
    gdctUnspecified,
    gdctWindow,
    gdctOffscreen

  GpuDirectCompositeContext* = object
    ## Describes the renderer target active for this synchronous submission.
    ## Backend adapters must return gdcsUnsupported when they cannot preserve
    ## these composition constraints.
    targetKind*: GpuDirectCompositeTargetKind
    targetBounds*: Rect
    clipBounds*: Option[Rect]
    requiresClipMask*: bool
    pixelScale*: float32

  GpuDirectCompositeRequest* = object
    frame*: GpuDirectSurfaceFrame
    destination*: Rect
    opacity*: float32
    context*: GpuDirectCompositeContext

  GpuDirectCompositeProc* = proc(
    request: GpuDirectCompositeRequest
  ): GpuDirectCompositeStatus {.closure.}

proc defaultGpuDirectCompositeContext*(): GpuDirectCompositeContext =
  GpuDirectCompositeContext(
    targetKind: gdctUnspecified,
    pixelScale: 1.0'f32
  )

proc compositeGpuDirectSurface*(
    command: PaintCommand;
    context: GpuDirectCompositeContext;
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
      opacity: command.gpuSurfaceOpacity,
      context: context
    ))
  finally:
    discard frame.release()

proc compositeGpuDirectSurface*(
    command: PaintCommand;
    compositor: GpuDirectCompositeProc
): GpuDirectCompositeStatus =
  command.compositeGpuDirectSurface(
    defaultGpuDirectCompositeContext(), compositor
  )
