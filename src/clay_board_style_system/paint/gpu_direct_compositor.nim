import std/[math, options]

import ../core/geometry
import ../runtime/gpu_direct_surface
import ../runtime/gpu_host
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
    sourceProviders*: set[GpuProviderKind]
    sourceKinds*: set[GpuResourceKind]
    sourceFormats*: set[GpuTextureFormat]
    alphaModes*: set[GpuAlphaMode]
    maxSourceWidth*, maxSourceHeight*: uint32

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
    clipMaskSupported = false;
    sourceProviders: set[GpuProviderKind] = {gpkCustom, gpkBgfx};
    sourceKinds: set[GpuResourceKind] = {grkTexture, grkRenderTarget};
    sourceFormats: set[GpuTextureFormat] = {
      gtfR8, gtfRgba8, gtfBgra8, gtfR16F, gtfR32F, gtfRg16F, gtfRg32F,
      gtfRgba16F, gtfRgba32F
    };
    alphaModes: set[GpuAlphaMode] = {
      gcamStraight, gcamPremultiplied, gcamOpaque
    };
    maxSourceWidth = 0'u32;
    maxSourceHeight = 0'u32
): GpuDirectCompositeCapabilities =
  if targetKinds == {}:
    raise newException(
      ValueError, "GPU direct compositor must support at least one target kind"
    )
  if clipMaskSupported and not clipBoundsSupported:
    raise newException(
      ValueError, "GPU direct clip masks require rectangular clip support"
    )
  if sourceProviders == {}:
    raise newException(
      ValueError, "GPU direct compositor must support at least one provider"
    )
  if sourceKinds == {} or
      (sourceKinds - {grkTexture, grkRenderTarget}) != {}:
    raise newException(
      ValueError,
      "GPU direct compositor source kinds must contain only Texture or RenderTarget"
    )
  if sourceFormats == {}:
    raise newException(
      ValueError, "GPU direct compositor must support at least one source format"
    )
  if alphaModes == {}:
    raise newException(
      ValueError, "GPU direct compositor must support at least one alpha mode"
    )
  GpuDirectCompositeCapabilities(
    targetKinds: targetKinds,
    clipBoundsSupported: clipBoundsSupported,
    clipMaskSupported: clipMaskSupported,
    sourceProviders: sourceProviders,
    sourceKinds: sourceKinds,
    sourceFormats: sourceFormats,
    alphaModes: alphaModes,
    maxSourceWidth: maxSourceWidth,
    maxSourceHeight: maxSourceHeight
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
  if capabilities.sourceProviders == {} or
      capabilities.sourceKinds == {} or
      (capabilities.sourceKinds - {grkTexture, grkRenderTarget}) != {} or
      capabilities.sourceFormats == {} or capabilities.alphaModes == {}:
    raise newException(
      ValueError, "GPU direct compositor source capabilities are invalid"
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

proc supports*(
    capabilities: GpuDirectCompositeCapabilities;
    frame: GpuDirectSurfaceFrame
): bool =
  if frame.surface.isNil or frame.slotIndex < 0 or
      frame.provider notin capabilities.sourceProviders or
      frame.resource.kind notin capabilities.sourceKinds or
      frame.format notin capabilities.sourceFormats or
      frame.alphaMode notin capabilities.alphaModes or
      frame.width == 0 or frame.height == 0:
    return false
  if capabilities.maxSourceWidth != 0 and
      frame.width > capabilities.maxSourceWidth:
    return false
  if capabilities.maxSourceHeight != 0 and
      frame.height > capabilities.maxSourceHeight:
    return false
  true

proc submitGpuDirectFrame(
    command: PaintCommand;
    context: GpuDirectCompositeContext;
    frame: GpuDirectSurfaceFrame;
    submit: GpuDirectCompositeProc
): GpuDirectCompositeStatus =
  submit(GpuDirectCompositeRequest(
    frame: frame,
    destination: command.gpuSurfaceRect,
    opacity: command.gpuSurfaceOpacity,
    context: context
  ))

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
    result = command.submitGpuDirectFrame(context, frame, compositor)
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
  if command.kind != pcDrawGpuDirectSurface:
    return gdcsUnsupported
  let acquired = command.gpuDirectSurface.acquireGpuDirectSurfaceFrame()
  if acquired.isNone:
    return gdcsNoFrame
  var frame = acquired.get
  try:
    if not compositor.capabilities.supports(frame):
      return gdcsUnsupported
    result = command.submitGpuDirectFrame(context, frame, compositor.submit)
  finally:
    discard frame.release()

proc compositeGpuDirectSurface*(
    command: PaintCommand;
    compositor: GpuDirectCompositeProc
): GpuDirectCompositeStatus =
  command.compositeGpuDirectSurface(
    defaultGpuDirectCompositeContext(), compositor
  )
