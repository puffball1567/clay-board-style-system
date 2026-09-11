import std/[math, options]

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

  GpuDirectCompositeCapabilities* = object
    targetKinds*: set[GpuDirectCompositeTargetKind]
    clipBoundsSupported*: bool
    clipMaskSupported*: bool

  GpuDirectCompositeRequest* = object
    frame*: GpuDirectSurfaceFrame
    destination*: Rect
    opacity*: float32
    context*: GpuDirectCompositeContext

  GpuDirectCompositeProc* = proc(
    request: GpuDirectCompositeRequest
  ): GpuDirectCompositeStatus {.closure.}

  GpuDirectCompositor* = object
    capabilities*: GpuDirectCompositeCapabilities
    submit*: GpuDirectCompositeProc

proc defaultGpuDirectCompositeContext*(): GpuDirectCompositeContext =
  GpuDirectCompositeContext(
    targetKind: gdctUnspecified,
    pixelScale: 1.0'f32
  )

proc gpuDirectCompositeCapabilities*(
    targetKinds: set[GpuDirectCompositeTargetKind];
    clipBoundsSupported = false;
    clipMaskSupported = false
): GpuDirectCompositeCapabilities =
  if targetKinds == {}:
    raise newException(
      ValueError, "GPU direct compositor must support at least one target kind"
    )
  if clipMaskSupported and not clipBoundsSupported:
    raise newException(
      ValueError, "GPU direct clip masks require rectangular clip support"
    )
  GpuDirectCompositeCapabilities(
    targetKinds: targetKinds,
    clipBoundsSupported: clipBoundsSupported,
    clipMaskSupported: clipMaskSupported
  )

proc newGpuDirectCompositor*(
    capabilities: GpuDirectCompositeCapabilities;
    submit: GpuDirectCompositeProc
): GpuDirectCompositor =
  if submit.isNil:
    raise newException(ValueError, "GPU direct compositor callback is required")
  if capabilities.targetKinds == {}:
    raise newException(
      ValueError, "GPU direct compositor capabilities are required"
    )
  if capabilities.clipMaskSupported and not capabilities.clipBoundsSupported:
    raise newException(
      ValueError, "GPU direct clip masks require rectangular clip support"
    )
  GpuDirectCompositor(capabilities: capabilities, submit: submit)

proc isFinite(value: float32): bool {.inline.} =
  value.classify notin {fcNan, fcInf, fcNegInf}

proc isValidBounds(value: Rect; allowEmpty: bool): bool =
  value.x.isFinite and value.y.isFinite and value.w.isFinite and
    value.h.isFinite and value.w >= 0 and value.h >= 0 and
    (allowEmpty or (value.w > 0 and value.h > 0))

proc supports*(
    capabilities: GpuDirectCompositeCapabilities;
    context: GpuDirectCompositeContext
): bool =
  if context.targetKind notin capabilities.targetKinds or
      not context.pixelScale.isFinite or context.pixelScale <= 0:
    return false
  if context.targetKind != gdctUnspecified and
      not context.targetBounds.isValidBounds(false):
    return false
  if context.clipBounds.isSome:
    if not capabilities.clipBoundsSupported or
        not context.clipBounds.get.isValidBounds(true):
      return false
  if context.requiresClipMask and
      (context.clipBounds.isNone or not capabilities.clipMaskSupported):
    return false
  true

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
    context: GpuDirectCompositeContext;
    compositor: GpuDirectCompositor
): GpuDirectCompositeStatus =
  ## Rejects unsupported target constraints before acquiring a frame lease.
  if compositor.submit.isNil or
      not compositor.capabilities.supports(context):
    return gdcsUnsupported
  command.compositeGpuDirectSurface(context, compositor.submit)

proc compositeGpuDirectSurface*(
    command: PaintCommand;
    compositor: GpuDirectCompositeProc
): GpuDirectCompositeStatus =
  command.compositeGpuDirectSurface(
    defaultGpuDirectCompositeContext(), compositor
  )
