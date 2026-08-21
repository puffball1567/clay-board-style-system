import std/[algorithm, atomics, locks, math, options, sets, strutils, tables]

import ./core/[color, color_conversion, color_mix, color_mix_parser,
  color_parser, color_value, declaration, diagnostics, geometry, node, rule,
  selector, style_resolver, style_value]
import ./data/[blob, form_data, stream_bridge, stream_mailbox]
import ./core/computed_style as computed_style_types
import ./craft/[pack, style, style_slots]
import ./generated/craft_driver_contract
import ./generated/default_properties
import ./hit/hit_test
import ./input/events
import ./layout/[layout, presentation, scroll_state]
import ./paint/[paint, paint_command, path_geometry]
import ./runtime/[canvas, declarative_keyframes, declarative_transition,
  frame_scheduler, invalidation, motion_lifecycle, render_surface]

var cbssRuntimeInitialized: bool
cbssRuntimeInitialized = true

proc NimMain() {.importc, cdecl.}

proc ensureNimRuntime() {.inline.} =
  ## Shared libraries initialize Nim from their loader constructor. Static
  ## libraries have no loader, so the first owning-handle constructor performs
  ## the same initialization before touching managed values.
  if not cbssRuntimeInitialized:
    NimMain()

const
  CbssMaxEagerBlobBytes* = 64'u64 * 1024'u64 * 1024'u64
  CbssMaxBlobMimeBytes* = 1024
  CbssMaxFormDataEntries* = 65_536
  CbssMaxFormDataNameBytes* = 65_536
  CbssMaxFormDataTextBytes* = 16 * 1024 * 1024
  CbssMaxStreamErrorBytes* = 65_536
  CbssNodeNone* = high(uint32)

  CbssOk* = 0'i32
  CbssInvalidArgument* = 1'i32
  CbssInvalidHandle* = 2'i32
  CbssOutOfRange* = 3'i32
  CbssStyleError* = 4'i32
  CbssInternalError* = 5'i32
  CbssNotAvailable* = 6'i32

  CbssFormDataText* = 0'u32
  CbssFormDataBlob* = 1'u32

  CbssStreamOfferAccepted* = 0'u32
  CbssStreamOfferBackpressure* = 1'u32
  CbssStreamOfferInvalidState* = 2'u32
  CbssStreamOfferDisposed* = 3'u32
  CbssStreamOfferInvalidArgument* = 4'u32

  CbssStreamEventHasTotal* = 1'u32 shl 0

  CbssInputHasPosition* = 1'u32 shl 0
  CbssInputHasDelta* = 1'u32 shl 1
  CbssInputHasButton* = 1'u32 shl 2
  CbssInputHasKey* = 1'u32 shl 3
  CbssInputHasText* = 1'u32 shl 4
  CbssInputHasPointer* = 1'u32 shl 5
  CbssInputFlagsMask* = (1'u32 shl 6) - 1

  CbssModifierCtrl* = 1'u32 shl 0
  CbssModifierAlt* = 1'u32 shl 1
  CbssModifierShift* = 1'u32 shl 2
  CbssModifierMeta* = 1'u32 shl 3
  CbssModifierMask* = (1'u32 shl 4) - 1

  CbssEventHasLocal* = 1'u32 shl 0
  CbssEventHasPosition* = 1'u32 shl 1
  CbssEventHasDelta* = 1'u32 shl 2
  CbssEventHasButton* = 1'u32 shl 3
  CbssEventHasKey* = 1'u32 shl 4
  CbssEventHasText* = 1'u32 shl 5
  CbssEventHasPointer* = 1'u32 shl 6
  CbssEventBubbles* = 1'u32 shl 7
  CbssEventCancelable* = 1'u32 shl 8
  CbssEventPhaseTarget* = 1'u32 shl 9
  CbssEventPhaseBubble* = 1'u32 shl 10

  CbssEventOutcomeHandled* = 1'u8 shl 0
  CbssEventOutcomeStopPropagation* = 1'u8 shl 1
  CbssEventOutcomePreventDefault* = 1'u8 shl 2

  CbssPointerAxisPressure* = 1'u32 shl 0
  CbssPointerAxisTangentialPressure* = 1'u32 shl 1
  CbssPointerAxisTiltX* = 1'u32 shl 2
  CbssPointerAxisTiltY* = 1'u32 shl 3
  CbssPointerAxisRotation* = 1'u32 shl 4
  CbssPointerAxisDistance* = 1'u32 shl 5
  CbssPointerAxisSlider* = 1'u32 shl 6
  CbssPointerAxesMask* = (1'u32 shl 7) - 1

  CbssBorderHasWidth* = 1'u32 shl 0
  CbssBorderHasStyle* = 1'u32 shl 1
  CbssBorderHasColor* = 1'u32 shl 2

  CbssShadowHasBlur* = 1'u32 shl 0
  CbssShadowHasSpread* = 1'u32 shl 1
  CbssShadowHasColor* = 1'u32 shl 2

  CbssTransformHasX* = 1'u32 shl 0
  CbssTransformHasY* = 1'u32 shl 1
  CbssTransformHasZ* = 1'u32 shl 2

  CbssAccessibleHasValueNow* = 1'u32 shl 0
  CbssAccessibleHasValueMin* = 1'u32 shl 1
  CbssAccessibleHasValueMax* = 1'u32 shl 2

  CbssColorMissingFirst* = 1'u32 shl 0
  CbssColorMissingSecond* = 1'u32 shl 1
  CbssColorMissingThird* = 1'u32 shl 2
  CbssColorMissingAlpha* = 1'u32 shl 3
  CbssColorMissingMask* = (1'u32 shl 4) - 1

  CbssColorMixHasFirstPercentage* = 1'u32 shl 0
  CbssColorMixHasSecondPercentage* = 1'u32 shl 1
  CbssColorMixFlagsMask* = (1'u32 shl 2) - 1

  CbssSurfaceVisible* = 1'u32 shl 0
  CbssSurfaceInside* = 1'u32 shl 1
  CbssSurfaceCaptured* = 1'u32 shl 2
  CbssSurfaceHasLocalPosition* = 1'u32 shl 3

  CbssSurfaceHandled* = 1'u32 shl 0
  CbssSurfaceRequestNextFrame* = 1'u32 shl 1

  CbssTextHasFontSize* = 1'u32 shl 0
  CbssTextHasLineHeight* = 1'u32 shl 1
  CbssTextHasFontWeight* = 1'u32 shl 2
  CbssTextHasLetterSpacing* = 1'u32 shl 3
  CbssTextHasFontStyle* = 1'u32 shl 4
  CbssTextFlagsMask* = (1'u32 shl 5) - 1

  CbssEventHasMotion* = 1'u32 shl 11
  CbssMaxKeyframeSteps* = 16_384'u32
  CbssMaxCraftStyleSourceBytes* = uint32(maxCraftStyleSourceBytes)
  CbssMaxCraftPackSourceBytes* = uint32(maxCraftPackSourceBytes)

  CbssCraftDiagnosticStyleParse* = 0'u32
  CbssCraftDiagnosticStyleReplacement* = 1'u32
  CbssCraftDiagnosticPack* = 2'u32

type
  CbssRectC* {.bycopy.} = object
    x*, y*, w*, h*: cfloat

  CbssColorC* {.bycopy.} = object
    r*, g*, b*, a*: cfloat

  CbssAffineTransformC* {.bycopy.} = object
    m11*, m12*, m21*, m22*, tx*, ty*: cfloat

  CbssPathSegmentC* {.bycopy.} = object
    kind*: uint32
    control1X*, control1Y*: cfloat
    control2X*, control2Y*: cfloat
    endpointX*, endpointY*: cfloat

  CbssLayoutBoxC* {.bycopy.} = object
    node*: uint32
    rect*: CbssRectC
    zIndex*: int32

  CbssHitResultC* {.bycopy.} = object
    node*: uint32
    localX*, localY*: cfloat
    kind*: uint32
    cursor*: uint32
    hasCursor*: uint8

  CbssPaintCommandC* {.bycopy.} = object
    kind*: uint32
    owner*: uint32
    rect*: CbssRectC
    color*: CbssColorC
    radius*: cfloat
    value0*, value1*, value2*, value3*: cfloat
    stringBytes*: uint32

  CbssTextStyleC* {.bycopy.} = object
    flags*: uint32
    fontSize*: cfloat
    lineHeight*: cfloat
    fontWeight*: cfloat
    letterSpacing*: cfloat
    fontStyle*: uint32

  CbssGradientStopC* {.bycopy.} = object
    color*: CbssColorC
    offset*: cfloat

  CbssColorValueGradientStopC* {.bycopy.} = object
    color*: CbssColorValueHandle
    offset*: cfloat

  CbssTransformOperationC* {.bycopy.} = object
    kind*, flags*, xUnit*, yUnit*, zUnit*: uint32
    x*, y*, z*, angle*: cfloat

  CbssPointerDataC* {.bycopy.} = object
    device*, axes*: uint32
    deviceId*: uint64
    pressure*, tangentialPressure*: cfloat
    tiltX*, tiltY*, rotation*, distance*, slider*: cfloat
    buttons*: uint32
    contact*, primary*, eraser*, inProximity*: uint8

  CbssInputEventC* {.bycopy.} = object
    kind*, flags*, modifiers*: uint32
    button*: int32
    x*, y*, deltaX*, deltaY*: cfloat
    key*, text*: cstring
    pointer*: CbssPointerDataC
    timestamp*: uint64

  CbssEventC* {.bycopy.} = object
    kind*, target*, currentTarget*, flags*: uint32
    localX*, localY*, x*, y*, deltaX*, deltaY*: cfloat
    button*: int32
    modifiers*: uint32
    key*, text*: cstring
    pointer*: CbssPointerDataC
    timestamp*: uint64
    motionName*: cstring
    motionElapsedSeconds*: cdouble
    motionIteration*: uint64

  CbssMotionStateC* {.bycopy.} = object
    activeAnimations*, activeTransitions*: uint32
    sampledAnimations*, sampledTransitions*: uint32
    dirtyDomains*: uint32
    hasDeadline*, reducedMotion*: uint8
    nextDeadline*, nowSeconds*: cdouble

  CbssDispatchSummaryC* {.bycopy.} = object
    target*, dispatchCount*: uint32
    handled*, outcome*, needsCompute*, paintChanged*, focusChanged*: uint8

  CbssScrollMetricsC* {.bycopy.} = object
    offsetX*, offsetY*: cfloat
    viewportWidth*, viewportHeight*: cfloat
    contentWidth*, contentHeight*: cfloat
    maxOffsetX*, maxOffsetY*: cfloat
    enabledX*, enabledY*, scrolling*: uint8

  CbssAccessibilityC* {.bycopy.} = object
    role*, flags*: uint32
    valueNow*, valueMin*, valueMax*: cfloat
    labelledBy*, describedBy*: uint32
    hidden*: uint8

  CbssRenderSurfacePlacementC* {.bycopy.} = object
    bounds*, clip*: CbssRectC
    pixelScale*, opacity*: cfloat

  CbssRenderSurfaceEventC* {.bycopy.} = object
    kind*, flags*: uint32
    surface*: uint64
    node*, apiVersion*: uint32
    revision*, frameNumber*: uint64
    nowSeconds*, deltaSeconds*: cdouble
    placement*: CbssRenderSurfacePlacementC
    localX*, localY*: cfloat
    logicalWidth*, logicalHeight*: cfloat
    pixelWidth*, pixelHeight*: cfloat
    input*: CbssInputEventC

  CbssStreamPumpResultC* {.bycopy.} = object
    processed*, rejected*: uint32
    changed*, backpressured*, pending*: uint8

  CbssStreamEventC* {.bycopy.} = object
    kind*, flags*: uint32
    blob*: CbssBlobHandle
    weight*: uint64
    completed*, total*: uint64
    messageBytes*: uint32

  CbssCraftDiagnosticC* {.bycopy.} = object
    domain*, code*, pathBytes*, messageBytes*: uint32

  CbssContextHandle* = ptr CbssContextObj
  CbssStyleHandle* = ptr CbssStyleObj
  CbssKeyframesHandle* = ptr CbssKeyframesObj
  CbssColorValueHandle* = ptr CbssColorValueObj
  CbssBlobHandle* = ptr CbssBlobObj
  CbssFormDataBuilderHandle* = ptr CbssFormDataBuilderObj
  CbssFormDataHandle* = ptr CbssFormDataObj
  CbssEventViewHandle* = ptr CbssEventViewObj
  CbssBlobStreamHandle* = ptr CbssBlobStreamObj
  CbssStreamProducerHandle* = ptr CbssStreamProducerObj
  CbssEventCallback* = proc(
    context: CbssContextHandle;
    event: ptr CbssEventC;
    userData: pointer
  ): uint8 {.cdecl.}
  CbssEventViewCallback* = proc(
    context: CbssContextHandle;
    view: CbssEventViewHandle;
    userData: pointer
  ): uint8 {.cdecl.}
  CbssRenderSurfaceCallback* = proc(
    context: CbssContextHandle;
    event: ptr CbssRenderSurfaceEventC;
    userData: pointer
  ): uint32 {.cdecl.}
  CbssStreamWakeCallback* = proc(
    userData: pointer
  ) {.cdecl, gcsafe, raises: [].}
  CbssBlobProviderReadCallback* = proc(
    userData: pointer;
    offset: uint64;
    output: pointer;
    capacity: uint32;
    outputRead: ptr uint32
  ): int32 {.cdecl, gcsafe, raises: [].}
  CbssBlobProviderReleaseCallback* = proc(
    userData: pointer
  ) {.cdecl, gcsafe, raises: [].}

  CbssRenderSurfaceBinding = ref object
    context: CbssContextHandle
    surface: RenderSurfaceId
    mountedNode: uint32
    callback: CbssRenderSurfaceCallback
    userData: pointer
    canvas: Canvas2D
    committedCanvas: Canvas2D
    committedCanvasRevision: uint64
    publishedRevision: uint64

  CbssAppliedStyle = object
    node: NodeId
    stateMask: uint32
    priority: int
    sourceOrder: int
    declarations: seq[Declaration]

  CbssCraftDiagnosticRecord = object
    domain: uint32
    code: uint32
    path: string
    message: string

  CbssContextObj = object
    tree: Tree
    sheets: seq[StyleSheet]
    appliedStyles: seq[CbssAppliedStyle]
    craftPacks: CraftPackRegistry
    craftStyles: CraftStyleSlotRuntime
    craftDiagnostics: seq[CbssCraftDiagnosticRecord]
    resolved: ResolvedTree
    layout: LayoutResult
    commands: seq[PaintCommand]
    hits: seq[HitRegion]
    scroll: ScrollState
    interaction: InteractionState
    events: EventRegistry
    eventSubscriptions: Table[uint64, EventSubscription]
    surfaces: RenderSurfaceRegistry
    surfaceBindings: Table[RenderSurfaceId, CbssRenderSurfaceBinding]
    surfacePaintProvider: SurfacePaintProvider
    pixelScale: float32
    diagnostics: Diagnostics
    lastError: string
    computed: bool
    hasViewport: bool
    viewportWidth, viewportHeight: float32
    refreshingPresentation: bool
    presentationRefreshPending: bool
    keyframes: DeclarativeKeyframeRuntime
    transitions: DeclarativeTransitionRuntime
    motionScheduler: FrameScheduler
    motionNow: float64
    motionTimeInitialized: bool
    reducedMotion: bool
    motionDirtyDomains: uint32

  CbssStyleObj = object
    declarations: seq[Declaration]

  CbssKeyframesObj = object
    name: string
    steps: seq[StyleKeyframe]

  CbssColorValueKind = enum
    ccvValue,
    ccvMix

  CbssColorValueObj = object
    case kind: CbssColorValueKind
    of ccvValue:
      value: ColorValue
    of ccvMix:
      mix: ColorMixValue

  CbssBlobObj = object
    bytes: pointer
    length: uint64
    mimeBytes: pointer
    mimeLength: uint32
    references: Atomic[uint32]
    providerGate: Lock
    providerRead: CbssBlobProviderReadCallback
    providerRelease: CbssBlobProviderReleaseCallback
    providerData: pointer
    providerBacked: bool

  CbssFormDataEntryObj = object
    nameBytes: pointer
    nameLength: uint32
    kind: uint32
    textBytes: pointer
    textLength: uint32
    blob: CbssBlobHandle
    fileNameBytes: pointer
    fileNameLength: uint32

  CbssFormDataBuilderObj = object
    entries: seq[CbssFormDataEntryObj]
    finished: bool

  CbssFormDataObj = object
    entries: pointer
    length: uint32
    references: Atomic[uint32]

  CbssEventViewObj = object
    event: CbssEventC
    formData: CbssFormDataHandle
    formDataStatus: int32

  CbssStreamBlobPayload = object
    blob: CbssBlobHandle

  CbssBlobStreamObj = object
    mailbox: StreamMailbox[CbssStreamBlobPayload]
    bridge: StreamBridge[CbssStreamBlobPayload]
    lastError: string

  CbssStreamProducerObj = object
    producer: StreamProducer[CbssStreamBlobPayload]
    references: Atomic[uint32]

static:
  doAssert sizeof(CbssRectC) == 16
  doAssert sizeof(CbssColorC) == 16
  doAssert sizeof(CbssLayoutBoxC) == 24
  doAssert sizeof(CbssHitResultC) == 24
  doAssert sizeof(CbssPaintCommandC) == 64
  doAssert sizeof(CbssAffineTransformC) == 24
  doAssert sizeof(CbssPathSegmentC) == 28
  doAssert sizeof(CbssTextStyleC) == 24
  doAssert sizeof(CbssGradientStopC) == 20
  doAssert sizeof(CbssTransformOperationC) == 36
  doAssert sizeof(CbssPointerDataC) == 56
  doAssert sizeof(CbssInputEventC) == 112
  doAssert sizeof(CbssEventC) == 152
  doAssert sizeof(CbssMotionStateC) == 40
  doAssert sizeof(CbssDispatchSummaryC) == 16
  doAssert sizeof(CbssScrollMetricsC) == 36
  doAssert sizeof(CbssAccessibilityC) == 32
  doAssert sizeof(CbssRenderSurfacePlacementC) == 40
  doAssert sizeof(CbssRenderSurfaceEventC) == 232
  doAssert sizeof(CbssStreamPumpResultC) == 12
  doAssert sizeof(CbssStreamEventC) == 48
  doAssert sizeof(CbssCraftDiagnosticC) == 16

proc retainBlobHandle(blob: CbssBlobHandle): int32 {.raises: [].}
proc releaseBlobHandle(blob: CbssBlobHandle) {.raises: [].}
proc boundedCStringLength(value: cstring; maximum: int): int

proc `=destroy`(payload: var CbssStreamBlobPayload) =
  if not payload.blob.isNil:
    releaseBlobHandle(payload.blob)
    payload.blob = nil

proc `=copy`(
    destination: var CbssStreamBlobPayload;
    source: CbssStreamBlobPayload
) =
  if destination.blob == source.blob:
    return
  if not source.blob.isNil:
    discard retainBlobHandle(source.blob)
  `=destroy`(destination)
  destination.blob = source.blob

proc `=sink`(
    destination: var CbssStreamBlobPayload;
    source: CbssStreamBlobPayload
) =
  `=destroy`(destination)
  destination.blob = source.blob

proc takeBlob(payload: var CbssStreamBlobPayload): CbssBlobHandle =
  result = payload.blob
  payload.blob = nil

proc toRect(value: Rect): CbssRectC {.inline.} =
  CbssRectC(x: value.x, y: value.y, w: value.w, h: value.h)

proc toPlacement(
    value: RenderSurfacePlacement
): CbssRenderSurfacePlacementC {.inline.} =
  CbssRenderSurfacePlacementC(
    bounds: value.bounds.toRect(),
    clip: value.clip.toRect(),
    pixelScale: value.pixelScale,
    opacity: value.opacity
  )

proc toColor(value: Color): CbssColorC {.inline.} =
  CbssColorC(r: value.r, g: value.g, b: value.b, a: value.a)

proc toMissingComponents(mask: uint32): set[ColorComponent] {.inline.} =
  if (mask and CbssColorMissingFirst) != 0:
    result.incl ccFirst
  if (mask and CbssColorMissingSecond) != 0:
    result.incl ccSecond
  if (mask and CbssColorMissingThird) != 0:
    result.incl ccThird
  if (mask and CbssColorMissingAlpha) != 0:
    result.incl ccAlpha

proc colorSpaceFromC(value: uint32): Option[ColorSpace] =
  case value
  of 0: some(csSrgb)
  of 1: some(csSrgbLinear)
  of 2: some(csDisplayP3)
  of 3: some(csA98Rgb)
  of 4: some(csProPhotoRgb)
  of 5: some(csRec2020)
  of 6: some(csXyzD50)
  of 7: some(csXyzD65)
  of 8: some(csHsl)
  of 9: some(csHwb)
  of 10: some(csLab)
  of 11: some(csLch)
  of 12: some(csOklab)
  of 13: some(csOklch)
  of 14: some(csDisplayP3Linear)
  else: none(ColorSpace)

proc interpolationSpaceFromC(
    value: uint32
): Option[ColorInterpolationSpace] =
  case value
  of 0: some(cisSrgb)
  of 1: some(cisSrgbLinear)
  of 2: some(cisOklab)
  else: none(ColorInterpolationSpace)

proc interpolationSpaceToC(value: ColorInterpolationSpace): uint32 =
  case value
  of cisSrgb: 0
  of cisSrgbLinear: 1
  of cisOklab: 2

proc layerCompositeModeFromC(value: uint32): Option[LayerCompositeMode] =
  case value
  of 0: some(lcmSourceOver)
  of 1: some(lcmCopy)
  of 2: some(lcmAdditive)
  else: none(LayerCompositeMode)

proc strokeLineCapFromC(value: uint32): Option[StrokeLineCap] =
  case value
  of 0: some(slcButt)
  of 1: some(slcRound)
  of 2: some(slcSquare)
  else: none(StrokeLineCap)

proc strokeLineJoinFromC(value: uint32): Option[StrokeLineJoin] =
  case value
  of 0: some(sljMiter)
  of 1: some(sljRound)
  of 2: some(sljBevel)
  else: none(StrokeLineJoin)

proc colorValueOf(value: CbssColorValueHandle): ColorValue {.inline.} =
  value.value

proc resolveColor(value: CbssColorValueHandle; current: Color): Color {.inline.} =
  case value.kind
  of ccvValue:
    value.value.resolveColor(current)
  of ccvMix:
    value.mix.resolveColor(current)

proc fromCString(value: cstring): string {.inline.} =
  if value.isNil: "" else: $value

proc toRect(value: CbssRectC): Rect {.inline.} =
  rect(value.x, value.y, value.w, value.h)

proc toColor(value: CbssColorC): Color {.inline.} =
  rgba(value.r, value.g, value.b, value.a)

proc toAffine(value: CbssAffineTransformC): Affine2D {.inline.} =
  Affine2D(
    m11: value.m11,
    m12: value.m12,
    m21: value.m21,
    m22: value.m22,
    tx: value.tx,
    ty: value.ty
  )

proc finite(value: float32): bool {.inline.} =
  value.classify notin {fcNan, fcInf, fcNegInf}

proc validPointerData(value: CbssPointerDataC): bool =
  if value.device > uint32(ord(high(PointerDeviceKind))) or
      (value.axes and not CbssPointerAxesMask) != 0 or
      value.contact > 1 or value.primary > 1 or value.eraser > 1 or
      value.inProximity > 1:
    return false
  if not (value.pressure.finite and value.tangentialPressure.finite and
      value.tiltX.finite and value.tiltY.finite and value.rotation.finite and
      value.distance.finite and value.slider.finite):
    return false
  if (value.axes and CbssPointerAxisPressure) != 0 and
      (value.pressure < 0 or value.pressure > 1):
    return false
  if (value.axes and CbssPointerAxisTangentialPressure) != 0 and
      (value.tangentialPressure < -1 or value.tangentialPressure > 1):
    return false
  if (value.axes and CbssPointerAxisTiltX) != 0 and
      (value.tiltX < -90 or value.tiltX > 90):
    return false
  if (value.axes and CbssPointerAxisTiltY) != 0 and
      (value.tiltY < -90 or value.tiltY > 90):
    return false
  if (value.axes and CbssPointerAxisRotation) != 0 and
      (value.rotation < -180 or value.rotation > 180):
    return false
  if (value.axes and CbssPointerAxisDistance) != 0 and
      (value.distance < 0 or value.distance > 1):
    return false
  if (value.axes and CbssPointerAxisSlider) != 0 and
      (value.slider < 0 or value.slider > 1):
    return false
  true

proc validInputEvent(value: CbssInputEventC): bool =
  if value.kind > uint32(ord(high(InputEventKind))) or
      (value.flags and not CbssInputFlagsMask) != 0 or
      (value.modifiers and not CbssModifierMask) != 0:
    return false
  if (value.flags and CbssInputHasPosition) != 0 and
      not (value.x.finite and value.y.finite):
    return false
  if (value.flags and CbssInputHasDelta) != 0 and
      not (value.deltaX.finite and value.deltaY.finite):
    return false
  if (value.flags and CbssInputHasKey) != 0 and value.key.isNil:
    return false
  if (value.flags and CbssInputHasText) != 0 and value.text.isNil:
    return false
  if (value.flags and CbssInputHasPointer) != 0 and
      not value.pointer.validPointerData():
    return false
  true

proc validRect(value: CbssRectC; allowEmpty = false): bool {.inline.} =
  value.x.finite and value.y.finite and value.w.finite and value.h.finite and
    value.w >= 0 and value.h >= 0 and
    (allowEmpty or (value.w > 0 and value.h > 0))

proc validColor(value: CbssColorC): bool {.inline.} =
  value.r.finite and value.g.finite and value.b.finite and value.a.finite

proc surfaceBinding(
    context: CbssContextHandle;
    surfaceValue: uint64
): CbssRenderSurfaceBinding {.inline.} =
  if context.isNil or surfaceValue == 0:
    return nil
  let surface = RenderSurfaceId(surfaceValue)
  if surface in context.surfaceBindings:
    context.surfaceBindings[surface]
  else:
    nil

proc checkedSurfaceCanvas(
    context: CbssContextHandle;
    surfaceValue: uint64
): tuple[status: int32, binding: CbssRenderSurfaceBinding] {.inline.} =
  if context.isNil:
    return (CbssInvalidHandle, nil)
  let binding = context.surfaceBinding(surfaceValue)
  if binding.isNil:
    return (CbssOutOfRange, nil)
  (CbssOk, binding)

proc copyCanvasCommands(source: Canvas2D): seq[CanvasCommand] =
  ## Presentation reads only snapshots published by commit. Nested strings,
  ## gradients, and paths are immutable through the C adapter and remain
  ## reference-counted values inside the copied command sequence.
  result = newSeqOfCap[CanvasCommand](source.commands.len)
  for command in source.commands:
    result.add command

template guardedCanvasMutation(
    context: CbssContextHandle;
    body: untyped
): int32 =
  try:
    body
    CbssOk
  except CatchableError as error:
    context.setError(error.msg)
    CbssInternalError

proc validNode(context: CbssContextHandle; node: uint32): bool {.inline.} =
  not context.isNil and node != CbssNodeNone and
    context.tree.isValid(NodeId(int(node)))

proc nodeId(node: uint32): NodeId {.inline.} =
  NodeId(int(node))

proc invalidate(context: CbssContextHandle) {.inline.} =
  context.computed = false
  context.lastError = ""

proc setError(context: CbssContextHandle; message: string) {.inline.} =
  if not context.isNil:
    context.lastError = message

proc copyString(value: string; buffer: cstring; capacity: uint32): uint32 =
  result =
    if value.len > int(high(uint32)): high(uint32)
    else: uint32(value.len)
  if buffer.isNil or capacity == 0:
    return
  let copyLen = min(value.len, int(capacity) - 1)
  if copyLen > 0:
    copyMem(buffer, unsafeAddr value[0], copyLen)
  cast[ptr UncheckedArray[char]](buffer)[copyLen] = '\0'

proc putDeclaration(style: CbssStyleHandle; property: string; value: StyleValue) =
  for index in 0 ..< style.declarations.len:
    if style.declarations[index].property == property:
      style.declarations[index] = decl(property, value, sourceOrder = index)
      return
  style.declarations.add decl(
    property, value, sourceOrder = style.declarations.len
  )

proc copyDeclarations(values: openArray[Declaration]): seq[Declaration] =
  result = newSeqOfCap[Declaration](values.len)
  for value in values:
    result.add value

proc selectorFor(node: NodeId; stateMask: uint32): SelectorCondition =
  result = target(node)
  for state in ElementState:
    if (stateMask and (1'u32 shl uint32(ord(state)))) != 0:
      result.requiredStates.incl state

proc rebuildStyleSheets(context: CbssContextHandle) =
  context.sheets.setLen(0)
  for sheet in context.craftStyles.craftStyleSheets():
    context.sheets.add sheet
  for applied in context.appliedStyles:
    context.sheets.add styleSheet([
      rule(
        selectorFor(applied.node, applied.stateMask),
        applied.declarations,
        priority = applied.priority,
        sourceOrder = applied.sourceOrder
      )
    ])

proc checkedStyleInput(
    style: CbssStyleHandle;
    property: cstring
): tuple[status: int32, name: string] =
  if style.isNil:
    return (CbssInvalidHandle, "")
  if property.isNil:
    return (CbssInvalidArgument, "")
  let name = fromCString(property).strip()
  if name.len == 0:
    return (CbssInvalidArgument, "")
  (CbssOk, name)

proc commandString(command: PaintCommand): string =
  case command.kind
  of pcDrawText:
    command.text
  of pcDrawImage:
    command.imageSource
  else:
    ""

proc commandKindToC(command: PaintCommand): uint32 =
  ## Public ABI values are append-only and must not follow Nim enum ordinals.
  case command.kind
  of pcPushClip: 0
  of pcPopClip: 1
  of pcBoxShadow: 2
  of pcFillRect: 3
  of pcFillLinearGradient: 4
  of pcStrokeRect: 5
  of pcDrawText: 6
  of pcDrawImage: 7
  of pcStrokePath: 8
  of pcPushTransform: 9
  of pcPopTransform: 10
  of pcPushLayer: 11
  of pcPopLayer: 12

proc commandRect(command: PaintCommand): Rect =
  case command.kind
  of pcPushTransform, pcPopTransform, pcPopLayer:
    rect(0, 0, 0, 0)
  of pcPushLayer:
    command.layerBounds
  of pcPushClip:
    command.clipRect
  of pcPopClip:
    rect(0, 0, 0, 0)
  of pcBoxShadow:
    command.shadowRect
  of pcFillRect:
    command.rect
  of pcFillLinearGradient:
    command.gradientRect
  of pcStrokeRect:
    command.strokeRect
  of pcStrokePath:
    command.path.bounds()
  of pcDrawText:
    rect(
      command.position.x,
      command.position.y,
      if command.textMaxWidth.isSome: command.textMaxWidth.get else: 0,
      0
    )
  of pcDrawImage:
    command.imageRect

proc commandColor(command: PaintCommand): Color =
  case command.kind
  of pcBoxShadow:
    command.shadowColor
  of pcFillRect:
    command.color
  of pcStrokeRect:
    command.strokeColor
  of pcStrokePath:
    command.pathColor
  of pcDrawText:
    command.textColor
  else:
    rgba(0, 0, 0, 0)

proc commandRadius(command: PaintCommand): float32 =
  case command.kind
  of pcPushClip:
    command.clipRadius
  of pcBoxShadow:
    command.shadowRadius
  of pcFillRect:
    command.radius
  of pcFillLinearGradient:
    command.gradientRadius
  of pcStrokeRect:
    command.strokeRadius
  else:
    0

proc refreshPresentation(context: CbssContextHandle) =
  if context.refreshingPresentation:
    context.presentationRefreshPending = true
    return
  context.refreshingPresentation = true
  try:
    while true:
      context.presentationRefreshPending = false
      context.commands = buildPaintCommands(
        context.tree, context.resolved, context.layout, context.scroll,
        context.surfacePaintProvider
      )
      context.hits = buildHitRegions(
        context.tree, context.layout, context.resolved, context.scroll
      )
      for index, node in context.tree.nodes:
        if not node.alive or node.renderSurfaceId.isNone:
          continue
        let nodeId = context.tree.nodeIdAt(index)
        if nodeId.isNone:
          continue
        let surface = RenderSurfaceId(node.renderSurfaceId.get)
        if not context.surfaces.hasSurface(surface):
          continue
        let presented = presentationForNode(
          context.tree, context.layout, context.resolved, nodeId.get,
          context.scroll
        )
        let placement =
          if presented.isSome:
            let style {.cursor.} = context.resolved.styles[nodeId.get.nodeIndex]
            renderSurfacePlacement(
              presented.get.contentBounds(style),
              presented.get.contentClip(style),
              pixelScale = context.pixelScale,
              opacity = max(0.0'f32, min(1.0'f32, presented.get.opacity))
            )
          else:
            renderSurfacePlacement(
              rect(0, 0, 0, 0), rect(0, 0, 0, 0),
              pixelScale = context.pixelScale, opacity = 0
            )
        let visible = presented.isSome and presented.get.visible and
          not placement.effectiveClip.isEmpty
        if context.surfaces.surfaceState(surface) == rssUnmounted:
          let revision =
            if surface in context.surfaceBindings:
              context.surfaceBindings[surface].publishedRevision
            else:
              0'u64
          context.surfaces.mountSurface(
            surface, nodeId.get, placement, visible = visible,
            revision = revision
          )
        else:
          discard context.surfaces.placeSurface(surface, placement)
          discard context.surfaces.setSurfaceVisible(surface, visible)
      if not context.presentationRefreshPending:
        break
  finally:
    context.refreshingPresentation = false

proc eventModifiers(event: InputEvent): uint32 {.inline.} =
  (if event.ctrlKey: CbssModifierCtrl else: 0'u32) or
    (if event.altKey: CbssModifierAlt else: 0'u32) or
    (if event.shiftKey: CbssModifierShift else: 0'u32) or
    (if event.metaKey: CbssModifierMeta else: 0'u32)

proc pointerAxes(value: set[PointerAxis]): uint32 {.inline.} =
  for axis in value:
    result = result or (1'u32 shl uint32(ord(axis)))

proc pointerDataC(value: PointerData): CbssPointerDataC {.inline.} =
  CbssPointerDataC(
    device: uint32(ord(value.device)),
    axes: value.axes.pointerAxes(),
    deviceId: value.deviceId,
    pressure: value.pressure,
    tangentialPressure: value.tangentialPressure,
    tiltX: value.tiltX,
    tiltY: value.tiltY,
    rotation: value.rotation,
    distance: value.distance,
    slider: value.slider,
    buttons: value.buttons,
    contact: uint8(ord(value.contact)),
    primary: uint8(ord(value.primary)),
    eraser: uint8(ord(value.eraser)),
    inProximity: uint8(ord(value.inProximity))
  )

proc pointerData(value: CbssPointerDataC): PointerData {.inline.} =
  var axes: set[PointerAxis]
  for axis in PointerAxis:
    if (value.axes and (1'u32 shl uint32(ord(axis)))) != 0:
      axes.incl axis
  PointerData(
    device: PointerDeviceKind(value.device),
    deviceId: value.deviceId,
    axes: axes,
    pressure: value.pressure,
    tangentialPressure: value.tangentialPressure,
    tiltX: value.tiltX,
    tiltY: value.tiltY,
    rotation: value.rotation,
    distance: value.distance,
    slider: value.slider,
    buttons: value.buttons,
    contact: value.contact != 0,
    primary: value.primary != 0,
    eraser: value.eraser != 0,
    inProximity: value.inProximity != 0
  )

proc inputEvent(value: CbssInputEventC): InputEvent =
  result = InputEvent(
    kind: InputEventKind(value.kind),
    timestamp: value.timestamp,
    ctrlKey: (value.modifiers and CbssModifierCtrl) != 0,
    altKey: (value.modifiers and CbssModifierAlt) != 0,
    shiftKey: (value.modifiers and CbssModifierShift) != 0,
    metaKey: (value.modifiers and CbssModifierMeta) != 0
  )
  if (value.flags and CbssInputHasPosition) != 0:
    result.position = some(vec2(value.x, value.y))
  if (value.flags and CbssInputHasDelta) != 0:
    result.delta = some(vec2(value.deltaX, value.deltaY))
  if (value.flags and CbssInputHasButton) != 0:
    result.button = some(int(value.button))
  if (value.flags and CbssInputHasKey) != 0:
    result.key = some(fromCString(value.key))
  if (value.flags and CbssInputHasText) != 0:
    result.text = some(fromCString(value.text))
  if (value.flags and CbssInputHasPointer) != 0:
    result.pointer = some(value.pointer.pointerData())

proc inputEventC(value: InputEvent): CbssInputEventC =
  result = CbssInputEventC(
    kind: uint32(ord(value.kind)),
    modifiers: value.eventModifiers(),
    timestamp: value.timestamp
  )
  if value.position.isSome:
    result.flags = result.flags or CbssInputHasPosition
    result.x = value.position.get.x
    result.y = value.position.get.y
  if value.delta.isSome:
    result.flags = result.flags or CbssInputHasDelta
    result.deltaX = value.delta.get.x
    result.deltaY = value.delta.get.y
  if value.button.isSome:
    result.flags = result.flags or CbssInputHasButton
    result.button = int32(value.button.get)
  if value.key.isSome:
    result.flags = result.flags or CbssInputHasKey
    result.key = cstring(value.key.get)
  if value.text.isSome:
    result.flags = result.flags or CbssInputHasText
    result.text = cstring(value.text.get)
  if value.pointer.isSome:
    result.flags = result.flags or CbssInputHasPointer
    result.pointer = value.pointer.get.pointerDataC()

proc surfaceEvent(
    kind: uint32;
    surface: RenderSurfaceId;
    node = CbssNodeNone;
    flags = 0'u32;
    revision = 0'u64;
    frameNumber = 0'u64;
    nowSeconds = 0.0;
    deltaSeconds = 0.0;
    placement = renderSurfacePlacement(rect(0, 0, 0, 0), rect(0, 0, 0, 0));
    localPosition = none(Vec2);
    logicalSize = size(0, 0);
    pixelSize = size(0, 0);
    input = InputEvent()
): CbssRenderSurfaceEventC =
  result = CbssRenderSurfaceEventC(
    kind: kind,
    flags: flags,
    surface: surface.renderSurfaceIdValue,
    node: node,
    apiVersion: renderSurfaceApiVersion,
    revision: revision,
    frameNumber: frameNumber,
    nowSeconds: nowSeconds,
    deltaSeconds: deltaSeconds,
    placement: placement.toPlacement(),
    logicalWidth: logicalSize.w,
    logicalHeight: logicalSize.h,
    pixelWidth: pixelSize.w,
    pixelHeight: pixelSize.h,
    input: input.inputEventC()
  )
  if localPosition.isSome:
    result.flags = result.flags or CbssSurfaceHasLocalPosition
    result.localX = localPosition.get.x
    result.localY = localPosition.get.y

proc cRenderSurfaceDescriptor(
    binding: CbssRenderSurfaceBinding;
    name: string
): RenderSurfaceDescriptor =
  template invoke(event: CbssRenderSurfaceEventC): uint32 =
    var callbackValue = event
    binding.callback(binding.context, addr callbackValue, binding.userData)

  RenderSurfaceDescriptor(
    name: name,
    callbacks: RenderSurfaceCallbacks(
      onMount: proc(event: RenderSurfaceMount) =
        binding.mountedNode = event.node.nodeRawValue()
        let flags = if event.visible: CbssSurfaceVisible else: 0'u32
        discard invoke(surfaceEvent(
          0, event.surface, binding.mountedNode, flags, event.revision,
          placement = event.placement
        )),
      onUpdate: proc(event: RenderSurfaceUpdate) =
        discard invoke(surfaceEvent(
          1, event.surface, binding.mountedNode, revision = event.revision,
          placement = event.placement
        )),
      onResize: proc(event: RenderSurfaceResize) =
        discard invoke(surfaceEvent(
          2, event.surface, binding.mountedNode,
          logicalSize = event.logicalSize,
          pixelSize = event.pixelSize
        )),
      onInput: proc(event: RenderSurfaceInput): bool =
        var flags = 0'u32
        if event.inside:
          flags = flags or CbssSurfaceInside
        if event.captured:
          flags = flags or CbssSurfaceCaptured
        let response = invoke(surfaceEvent(
          3, event.surface, binding.mountedNode, flags,
          localPosition = event.localPosition, input = event.event
        ))
        (response and CbssSurfaceHandled) != 0,
      onFrame: proc(event: RenderSurfaceFrame): RenderSurfaceFrameResult =
        let response = invoke(surfaceEvent(
          4, event.surface, binding.mountedNode,
          frameNumber = event.frameNumber,
          nowSeconds = event.nowSeconds,
          deltaSeconds = event.deltaSeconds,
          placement = event.placement
        ))
        if (response and CbssSurfaceRequestNextFrame) != 0:
          rsfRequestNext
        else:
          rsfIdle,
      onVisibility: proc(visible: bool) =
        let flags = if visible: CbssSurfaceVisible else: 0'u32
        discard invoke(surfaceEvent(
          5, binding.surface, binding.mountedNode, flags
        )),
      onDeviceLost: proc() =
        discard invoke(surfaceEvent(
          6, binding.surface, binding.mountedNode
        )),
      onDeviceRestored: proc() =
        discard invoke(surfaceEvent(
          7, binding.surface, binding.mountedNode
        )),
      onUnmount: proc() =
        discard invoke(surfaceEvent(
          8, binding.surface, binding.mountedNode
        ))
        binding.mountedNode = CbssNodeNone
    )
  )

proc eventFlags(dispatch: DispatchResult; includeLocal: bool): uint32 =
  if includeLocal and dispatch.local.isSome:
    result = result or CbssEventHasLocal
  if dispatch.event.position.isSome:
    result = result or CbssEventHasPosition
  if dispatch.event.delta.isSome:
    result = result or CbssEventHasDelta
  if dispatch.event.button.isSome:
    result = result or CbssEventHasButton
  if dispatch.event.key.isSome:
    result = result or CbssEventHasKey
  if dispatch.event.text.isSome:
    result = result or CbssEventHasText
  if dispatch.event.pointer.isSome:
    result = result or CbssEventHasPointer
  if dispatch.event.kind.eventDefinition.payload.contains(epfMotion):
    result = result or CbssEventHasMotion
  if dispatch.event.kind.bubbles:
    result = result or CbssEventBubbles
  if dispatch.event.kind.cancelable:
    result = result or CbssEventCancelable
  case dispatch.phase
  of epTarget:
    result = result or CbssEventPhaseTarget
  of epBubble:
    result = result or CbssEventPhaseBubble
  else:
    discard

proc callbackEvent(
    dispatch: DispatchResult;
    originalTarget, currentTarget: NodeId
): CbssEventC =
  let includeLocal = currentTarget == originalTarget
  result = CbssEventC(
    kind: dispatch.event.kind.eventDefinition.abiCode,
    target: originalTarget.nodeRawValue(),
    currentTarget: currentTarget.nodeRawValue(),
    flags: dispatch.eventFlags(includeLocal),
    timestamp: dispatch.event.timestamp,
    button:
      if dispatch.event.button.isSome:
        int32(dispatch.event.button.get)
      else:
        0,
    modifiers: dispatch.event.eventModifiers()
  )
  if includeLocal and dispatch.local.isSome:
    result.localX = dispatch.local.get.x
    result.localY = dispatch.local.get.y
  if dispatch.event.position.isSome:
    result.x = dispatch.event.position.get.x
    result.y = dispatch.event.position.get.y
  if dispatch.event.delta.isSome:
    result.deltaX = dispatch.event.delta.get.x
    result.deltaY = dispatch.event.delta.get.y
  if dispatch.event.key.isSome:
    result.key = dispatch.event.key.get.cstring
  if dispatch.event.text.isSome:
    result.text = dispatch.event.text.get.cstring
  if dispatch.event.pointer.isSome:
    result.pointer = dispatch.event.pointer.get.pointerDataC()
  if (result.flags and CbssEventHasMotion) != 0:
    result.motionElapsedSeconds = dispatch.motionElapsedSeconds
    result.motionIteration = dispatch.motionIteration

proc dispatchMotionLifecycle(
    context: CbssContextHandle;
    events: openArray[MotionLifecycleEvent]
) =
  for item in events:
    if not context.validNode(item.node.nodeRawValue()):
      continue
    let kind =
      case item.kind
      of mlkAnimationStart: iekAnimationStart
      of mlkAnimationIteration: iekAnimationIteration
      of mlkAnimationEnd: iekAnimationEnd
      of mlkAnimationCancel: iekAnimationCancel
      of mlkTransitionRun: iekTransitionRun
      of mlkTransitionStart: iekTransitionStart
      of mlkTransitionEnd: iekTransitionEnd
      of mlkTransitionCancel: iekTransitionCancel
    discard context.events.dispatchEvent(context.tree, DispatchResult(
      target: some(item.node),
      event: motionEvent(
        kind, item.name, item.elapsedSeconds, item.iteration
      )
    ))

proc dispatchPendingMotionLifecycle(context: CbssContextHandle) =
  context.dispatchMotionLifecycle(context.transitions.takeLifecycleEvents())
  context.dispatchMotionLifecycle(context.keyframes.takeLifecycleEvents())

proc cancelAllMotion(context: CbssContextHandle) =
  if context.isNil:
    return
  var nodes: seq[NodeId]
  for index, item in context.tree.nodes:
    if item.alive:
      let node = context.tree.nodeIdAt(index)
      if node.isSome:
        nodes.add node.get
  discard context.transitions.cancelTransitions(nodes)
  discard context.keyframes.cancelAnimations(nodes)
  context.dispatchPendingMotionLifecycle()

proc dirtyDomainBits(domains: set[DirtyDomain]): uint32 =
  for domain in domains:
    result = result or (1'u32 shl uint32(ord(domain)))

proc fillMotionState(
    context: CbssContextHandle;
    output: ptr CbssMotionStateC;
    sampledAnimations = 0;
    sampledTransitions = 0
) =
  output[] = CbssMotionStateC(
    activeAnimations: uint32(context.keyframes.activeAnimationCount),
    activeTransitions: uint32(context.transitions.activeTransitionCount),
    sampledAnimations: uint32(max(0, sampledAnimations)),
    sampledTransitions: uint32(max(0, sampledTransitions)),
    dirtyDomains: context.motionDirtyDomains,
    hasDeadline: uint8(ord(context.motionScheduler.nextDeadline.isSome)),
    reducedMotion: uint8(ord(context.reducedMotion)),
    nextDeadline:
      if context.motionScheduler.nextDeadline.isSome:
        context.motionScheduler.nextDeadline.get
      else:
        0.0,
    nowSeconds: context.motionNow
  )

proc callbackOutcome(value: uint8): EventOutcome =
  EventOutcome(
    handled: (value and CbssEventOutcomeHandled) != 0,
    stopPropagation: (value and CbssEventOutcomeStopPropagation) != 0,
    preventDefault: (value and CbssEventOutcomePreventDefault) != 0
  )

proc cEventHandler(
    context: CbssContextHandle;
    callback: CbssEventCallback;
    userData: pointer
): EventHandler =
  result = proc(dispatch: DispatchResult): EventOutcome =
    if callback.isNil or dispatch.target.isNone or
        dispatch.currentTarget.isNone:
      return ignoredEvent()
    var event = dispatch.callbackEvent(
      dispatch.target.get, dispatch.currentTarget.get
    )
    let motionName = dispatch.motionName
    if (event.flags and CbssEventHasMotion) != 0:
      event.motionName = motionName.cstring
    callbackOutcome(callback(context, addr event, userData))

proc invokeCallbacks(
    context: CbssContextHandle;
    dispatch: DispatchResult
): EventOutcome =
  context.events.dispatchEvent(context.tree, dispatch)

proc invokeRenderSurface(
    context: CbssContextHandle;
    dispatch: DispatchResult
): bool =
  if dispatch.target.isNone or not context.tree.isValid(dispatch.target.get):
    return false
  let target = dispatch.target.get
  let surfaceValue = context.tree.nodes[target.nodeIndex].renderSurfaceId
  if surfaceValue.isNone:
    return false
  let surface = RenderSurfaceId(surfaceValue.get)
  if not context.surfaces.hasSurface(surface):
    return false
  context.surfaces.dispatchSurfaceInput(
    surface,
    dispatch.event,
    captured = context.interaction.pointerCaptureTarget == some(target)
  )

proc dispatchAll(
    context: CbssContextHandle;
    dispatches: openArray[DispatchResult]
): tuple[outcome: EventOutcome, count: int] =
  for dispatch in dispatches:
    inc result.count
    result.outcome.mergeOutcome(context.invokeCallbacks(dispatch))
    if context.invokeRenderSurface(dispatch):
      result.outcome.handled = true

type
  FocusOrderEntry = object
    node: NodeId
    tabIndex: int

proc compareFocusOrder(a, b: FocusOrderEntry): int {.nimcall.} =
  let aPositive = a.tabIndex > 0
  let bPositive = b.tabIndex > 0
  if aPositive != bPositive:
    return if aPositive: -1 else: 1
  if aPositive:
    result = cmp(a.tabIndex, b.tabIndex)
    if result != 0:
      return
  result = cmp(a.node.nodeIndex, b.node.nodeIndex)

proc focusTargets(context: CbssContextHandle): seq[NodeId] =
  var entries: seq[FocusOrderEntry]
  for index in 0 ..< context.tree.nodes.len:
    let activeId = context.tree.nodeIdAt(index)
    if activeId.isNone:
      continue
    let id = activeId.get
    if context.tree.isFocusable(id, forTraversal = true):
      entries.add FocusOrderEntry(
        node: id,
        tabIndex: context.tree.nodes[index].tabIndex
      )
  entries.sort(compareFocusOrder)
  result = newSeqOfCap[NodeId](entries.len)
  for entry in entries:
    result.add entry.node

proc setContextFocus(
    context: CbssContextHandle;
    target: Option[NodeId];
    focusVisible: bool
): tuple[changed, handled: bool, dispatchCount: int] =
  let next =
    if target.isSome and context.tree.isFocusable(target.get):
      target
    else:
      none(NodeId)
  if context.interaction.focusedTarget == next:
    if next.isSome:
      context.tree.setState(next.get, esFocusVisible, focusVisible)
    return
  var dispatches: seq[DispatchResult]
  if context.interaction.focusedTarget.isSome:
    let previous = context.interaction.focusedTarget.get
    dispatches.add blurEvent(previous)
    if previous.nodeIndex >= 0 and previous.nodeIndex < context.tree.nodes.len:
      context.tree.removeState(previous, esFocus)
      context.tree.removeState(previous, esFocusVisible)
  discard context.interaction.setFocusedTarget(next)
  if next.isSome:
    context.tree.addState(next.get, esFocus)
    context.tree.setState(next.get, esFocusVisible, focusVisible)
    dispatches.add focusEvent(next.get)
  context.invalidate()
  let dispatched = context.dispatchAll(dispatches)
  result = (
    changed: true,
    handled: dispatched.outcome.handled,
    dispatchCount: dispatched.count
  )

proc collectSubtreeNodes(
    context: CbssContextHandle;
    root: NodeId
): tuple[ids: seq[NodeId], members: HashSet[NodeId]] =
  var pending = @[root]
  while pending.len > 0:
    let id = pending.pop()
    if not context.tree.isValid(id) or id in result.members:
      continue
    result.members.incl id
    result.ids.add id
    for child in context.tree.nodes[id.nodeIndex].children:
      pending.add child

proc clearRemovedInteractionTargets(
    context: CbssContextHandle;
    removed: HashSet[NodeId]
) =
  if context.interaction.focusedTarget.isSome and
      context.interaction.focusedTarget.get in removed:
    discard context.setContextFocus(none(NodeId), focusVisible = false)

  template clearTarget(field: untyped) =
    if field.isSome and field.get in removed:
      field = none(NodeId)

  if context.interaction.pressedTarget.isSome and
      context.interaction.pressedTarget.get in removed:
    context.interaction.pressedTarget = none(NodeId)
    context.interaction.pointerDownPosition = none(Vec2)
  clearTarget(context.interaction.hoveredTarget)
  clearTarget(context.interaction.pointerCaptureTarget)
  clearTarget(context.interaction.lastClickTarget)
  clearTarget(context.interaction.dragTarget)
  clearTarget(context.interaction.dragOverTarget)
  clearTarget(context.interaction.scrollTarget)
  clearTarget(context.interaction.scrollbarPointerTarget)
  if context.interaction.lastClickTarget.isNone:
    context.interaction.clickCount = 0
  if context.interaction.scrollbarPointerTarget.isNone:
    context.interaction.scrollbarDragging = false

proc removeSubtreeEventState(
    context: CbssContextHandle;
    removed: HashSet[NodeId]
) =
  discard context.events.removeEventHandlers(removed)
  var staleSubscriptions: seq[uint64]
  for id, subscription in context.eventSubscriptions.pairs:
    if subscription.node in removed:
      staleSubscriptions.add id
  for id in staleSubscriptions:
    context.eventSubscriptions.del(id)

proc removeSubtreeStyleState(
    context: CbssContextHandle;
    removed: HashSet[NodeId]
) =
  var retained = newSeqOfCap[CbssAppliedStyle](context.appliedStyles.len)
  var changed = false
  for applied in context.appliedStyles:
    if applied.node in removed:
      changed = true
    else:
      retained.add applied
  if changed:
    context.appliedStyles = retained
    for sourceOrder in 0 ..< context.appliedStyles.len:
      context.appliedStyles[sourceOrder].sourceOrder = sourceOrder

  let removedSlots = context.craftStyles.removePublicStyleSlots(
    context.tree, removed
  )
  if changed or removedSlots.len > 0:
    context.rebuildStyleSheets()

proc removeSubtreeSurfaceState(
    context: CbssContextHandle;
    removedIds: openArray[NodeId]
) =
  var surfaces: seq[RenderSurfaceId]
  for id in removedIds:
    let surface = context.tree.nodes[id.nodeIndex].renderSurfaceId
    if surface.isSome:
      surfaces.add RenderSurfaceId(surface.get)
  for surface in surfaces:
    discard context.surfaces.unregisterSurface(surface)
    context.surfaceBindings.del(surface)

proc removeContextSubtree(
    context: CbssContextHandle;
    root: NodeId
): int =
  let subtree = context.collectSubtreeNodes(root)
  if subtree.ids.len == 0:
    return 0

  context.clearRemovedInteractionTargets(subtree.members)
  discard context.transitions.cancelTransitions(subtree.ids)
  discard context.keyframes.cancelAnimations(subtree.ids)
  context.dispatchPendingMotionLifecycle()
  context.removeSubtreeEventState(subtree.members)
  context.removeSubtreeStyleState(subtree.members)
  context.scroll.clearNodes(subtree.ids)
  context.removeSubtreeSurfaceState(subtree.ids)
  result = context.tree.disposeSubtree(root).len
  context.resolved.styles.setLen(0)
  context.layout = LayoutResult(boxes: @[], overflowMetrics: @[])
  context.commands.setLen(0)
  context.hits.setLen(0)
  context.invalidate()

proc cbssAbiVersion(): uint32 {.
    exportc: "cbss_abi_version", cdecl, dynlib, raises: [].} =
  CbssAbiVersion

proc cbssDriverContractVersion(): uint32 {.
    exportc: "cbss_driver_contract_version", cdecl, dynlib, raises: [].} =
  CbssDriverContractVersion

proc cbssCapabilityCount(): uint32 {.
    exportc: "cbss_capability_count", cdecl, dynlib, raises: [].} =
  uint32(CbssCapabilities.len)

proc cbssCapabilityAt(
    index: uint32;
    output: ptr CbssCapabilityInfoC
): int32 {.exportc: "cbss_capability_at", cdecl, dynlib, raises: [].} =
  if output.isNil:
    return CbssInvalidArgument
  output[] = default(CbssCapabilityInfoC)
  if index >= uint32(CbssCapabilities.len):
    return CbssOutOfRange
  let capability = CbssCapabilities[int(index)]
  output[] = CbssCapabilityInfoC(
    id: capability.id,
    version: capability.version,
    sinceAbi: capability.sinceAbi,
    flags: CbssCapabilityAvailable,
    nameBytes: uint32(capability.name.len)
  )
  CbssOk

proc cbssHasCapability(capability, minimumVersion: uint32): uint8 {.
    exportc: "cbss_has_capability", cdecl, dynlib, raises: [].} =
  for item in CbssCapabilities:
    if item.id == capability:
      return uint8(item.version >= minimumVersion)
  0'u8

proc cbssCapabilityName(
    capability: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_capability_name", cdecl, dynlib, raises: [].} =
  for item in CbssCapabilities:
    if item.id == capability:
      return copyString(item.name, buffer, capacity)
  if not buffer.isNil and capacity > 0:
    cast[ptr UncheckedArray[char]](buffer)[0] = '\0'
  0'u32

proc cbssThreadAttach() {.
    exportc: "cbss_thread_attach", cdecl, dynlib, raises: [].} =
  setupForeignThreadGc()

proc cbssThreadDetach() {.
    exportc: "cbss_thread_detach", cdecl, dynlib, raises: [].} =
  tearDownForeignThreadGc()

proc cbssBlobCreate(
    bytes: pointer;
    length: uint64;
    mimeType: cstring;
    output: ptr CbssBlobHandle
): int32 {.exportc: "cbss_blob_create", cdecl, dynlib.} =
  ensureNimRuntime()
  if output.isNil:
    return CbssInvalidArgument
  output[] = nil
  if length > 0 and bytes.isNil:
    return CbssInvalidArgument
  if length > CbssMaxEagerBlobBytes or length > uint64(high(int)):
    return CbssOutOfRange

  let mimeLength = if mimeType.isNil: 0 else: mimeType.len
  if mimeLength > CbssMaxBlobMimeBytes:
    return CbssOutOfRange

  let allocated = cast[CbssBlobHandle](allocShared0(sizeof(CbssBlobObj)))
  if allocated.isNil:
    return CbssInternalError
  if length > 0:
    allocated.bytes = allocShared(int(length))
    if allocated.bytes.isNil:
      deallocShared(allocated)
      return CbssInternalError
    copyMem(allocated.bytes, bytes, int(length))
  if mimeLength > 0:
    allocated.mimeBytes = allocShared(mimeLength + 1)
    if allocated.mimeBytes.isNil:
      if not allocated.bytes.isNil:
        deallocShared(allocated.bytes)
      deallocShared(allocated)
      return CbssInternalError
    copyMem(allocated.mimeBytes, mimeType, mimeLength)
    cast[ptr UncheckedArray[char]](allocated.mimeBytes)[mimeLength] = '\0'
  allocated.length = length
  allocated.mimeLength = uint32(mimeLength)
  allocated.references.store(1)
  output[] = allocated
  CbssOk

proc cbssBlobCreateProvider(
    length: uint64;
    mimeType: cstring;
    readCallback: CbssBlobProviderReadCallback;
    releaseCallback: CbssBlobProviderReleaseCallback;
    userData: pointer;
    output: ptr CbssBlobHandle
): int32 {.exportc: "cbss_blob_create_provider", cdecl, dynlib.} =
  ensureNimRuntime()
  if output.isNil:
    return CbssInvalidArgument
  output[] = nil
  if readCallback == nil:
    return CbssInvalidArgument
  let mimeLength = if mimeType.isNil: 0 else: mimeType.len
  if mimeLength > CbssMaxBlobMimeBytes:
    return CbssOutOfRange

  let allocated = cast[CbssBlobHandle](allocShared0(sizeof(CbssBlobObj)))
  if allocated.isNil:
    return CbssInternalError
  if mimeLength > 0:
    allocated.mimeBytes = allocShared(mimeLength + 1)
    if allocated.mimeBytes.isNil:
      deallocShared(allocated)
      return CbssInternalError
    copyMem(allocated.mimeBytes, mimeType, mimeLength)
    cast[ptr UncheckedArray[char]](allocated.mimeBytes)[mimeLength] = '\0'
  initLock(allocated.providerGate)
  allocated.length = length
  allocated.mimeLength = uint32(mimeLength)
  allocated.providerRead = readCallback
  allocated.providerRelease = releaseCallback
  allocated.providerData = userData
  allocated.providerBacked = true
  allocated.references.store(1)
  output[] = allocated
  CbssOk

proc retainBlobHandle(blob: CbssBlobHandle): int32 {.raises: [].} =
  if blob.isNil:
    return CbssInvalidHandle
  var current = blob.references.load()
  while current > 0 and current < high(uint32):
    var expected = current
    if blob.references.compareExchange(expected, current + 1):
      return CbssOk
    current = expected
  if current == high(uint32): CbssOutOfRange else: CbssInvalidHandle

proc cbssBlobRetain(blob: CbssBlobHandle): int32 {.
    exportc: "cbss_blob_retain", cdecl, dynlib, raises: [].} =
  retainBlobHandle(blob)

proc releaseBlobHandle(blob: CbssBlobHandle) {.raises: [].} =
  if blob.isNil:
    return
  let previous = blob.references.fetchSub(1)
  if previous != 1:
    return
  if blob.providerBacked:
    if blob.providerRelease != nil:
      blob.providerRelease(blob.providerData)
    deinitLock(blob.providerGate)
  elif not blob.bytes.isNil:
    deallocShared(blob.bytes)
  if not blob.mimeBytes.isNil:
    deallocShared(blob.mimeBytes)
  deallocShared(blob)

proc cbssBlobRelease(blob: CbssBlobHandle) {.
    exportc: "cbss_blob_release", cdecl, dynlib, raises: [].} =
  releaseBlobHandle(blob)

proc cbssBlobSize(blob: CbssBlobHandle): uint64 {.
    exportc: "cbss_blob_size", cdecl, dynlib, raises: [].} =
  if blob.isNil: 0'u64 else: blob.length

proc cbssBlobMimeType(
    blob: CbssBlobHandle;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_blob_mime_type", cdecl, dynlib.} =
  if blob.isNil:
    return 0
  result = blob.mimeLength
  if buffer.isNil or capacity == 0:
    return
  let copyLength = min(int(blob.mimeLength), int(capacity) - 1)
  if copyLength > 0:
    copyMem(buffer, blob.mimeBytes, copyLength)
  cast[ptr UncheckedArray[char]](buffer)[copyLength] = '\0'

proc cbssBlobRead(
    blob: CbssBlobHandle;
    offset: uint64;
    output: pointer;
    capacity: uint32;
    outputRead: ptr uint32
): int32 {.exportc: "cbss_blob_read", cdecl, dynlib.} =
  if blob.isNil:
    return CbssInvalidHandle
  if outputRead.isNil or (capacity > 0 and output.isNil):
    return CbssInvalidArgument
  outputRead[] = 0
  if offset > blob.length:
    return CbssOutOfRange
  let available = blob.length - offset
  let count = min(available, uint64(capacity))
  if blob.providerBacked:
    if count == 0:
      return CbssOk
    var providerRead = 0'u32
    var status = CbssInternalError
    acquire(blob.providerGate)
    try:
      status = blob.providerRead(
        blob.providerData,
        offset,
        output,
        uint32(count),
        addr providerRead
      )
    finally:
      release(blob.providerGate)
    if status != CbssOk:
      return if status in CbssInvalidArgument .. CbssNotAvailable:
        status
      else:
        CbssInternalError
    if providerRead > uint32(count):
      return CbssInternalError
    outputRead[] = providerRead
    return CbssOk
  if count > 0:
    let source = cast[ptr UncheckedArray[byte]](blob.bytes)
    copyMem(output, unsafeAddr source[int(offset)], int(count))
  outputRead[] = uint32(count)
  CbssOk

proc toCStreamOffer(value: StreamMailboxOfferResult): uint32 {.inline.} =
  case value
  of smorAccepted: CbssStreamOfferAccepted
  of smorBackpressure: CbssStreamOfferBackpressure
  of smorInvalidState: CbssStreamOfferInvalidState
  of smorDisposed: CbssStreamOfferDisposed

proc cbssBlobStreamCreate(
    maxQueuedItems: uint32;
    maxQueuedWeight: uint64;
    output: ptr CbssBlobStreamHandle
): int32 {.exportc: "cbss_blob_stream_create", cdecl, dynlib.} =
  ensureNimRuntime()
  if output.isNil:
    return CbssInvalidArgument
  output[] = nil
  if maxQueuedItems == 0 or uint64(maxQueuedItems) > uint64(high(int)) or
      maxQueuedWeight == 0 or maxQueuedWeight > uint64(high(int64)):
    return CbssOutOfRange
  var stream: CbssBlobStreamHandle
  try:
    stream = create(CbssBlobStreamObj)
    stream.mailbox = initStreamMailbox[CbssStreamBlobPayload](
      int(maxQueuedItems), int64(maxQueuedWeight)
    )
    stream.bridge = initStreamBridge[CbssStreamBlobPayload](
      int(maxQueuedItems), int64(maxQueuedWeight)
    )
    output[] = stream
    CbssOk
  except CatchableError:
    if not stream.isNil:
      `=destroy`(stream[])
      dealloc(stream)
    CbssInternalError

proc cbssBlobStreamDestroy(stream: CbssBlobStreamHandle) {.
    exportc: "cbss_blob_stream_destroy", cdecl, dynlib.} =
  if stream.isNil:
    return
  discard stream.mailbox.dispose()
  discard stream.bridge.close()
  discard stream.bridge.drain()
  `=destroy`(stream[])
  dealloc(stream)

proc cbssBlobStreamProducer(
    stream: CbssBlobStreamHandle;
    output: ptr CbssStreamProducerHandle
): int32 {.exportc: "cbss_blob_stream_producer", cdecl, dynlib.} =
  if stream.isNil:
    return CbssInvalidHandle
  if output.isNil:
    return CbssInvalidArgument
  output[] = nil
  let allocated = cast[CbssStreamProducerHandle](
    allocShared0(sizeof(CbssStreamProducerObj))
  )
  if allocated.isNil:
    return CbssInternalError
  allocated.references.store(1, moRelaxed)
  allocated.producer = stream.mailbox.producer()
  output[] = allocated
  CbssOk

proc cbssStreamProducerRetain(
    producer: CbssStreamProducerHandle
): int32 {.exportc: "cbss_stream_producer_retain", cdecl, dynlib.} =
  if producer.isNil:
    return CbssInvalidHandle
  var current = producer.references.load(moRelaxed)
  while current > 0 and current < high(uint32):
    var expected = current
    if producer.references.compareExchange(
        expected, current + 1, moAcquireRelease, moRelaxed
    ):
      return CbssOk
    current = expected
  if current == high(uint32): CbssOutOfRange else: CbssInvalidHandle

proc cbssStreamProducerRelease(producer: CbssStreamProducerHandle) {.
    exportc: "cbss_stream_producer_release", cdecl, dynlib.} =
  if producer.isNil:
    return
  if producer.references.fetchSub(1, moAcquireRelease) != 1:
    return
  reset(producer.producer)
  deallocShared(producer)

proc cbssBlobStreamSetWakeCallback(
    stream: CbssBlobStreamHandle;
    callback: CbssStreamWakeCallback;
    userData: pointer
): int32 {.exportc: "cbss_blob_stream_set_wake_callback", cdecl, dynlib.} =
  if stream.isNil:
    return CbssInvalidHandle
  stream.mailbox.setWakeCallback(callback, userData)
  CbssOk

proc cbssStreamProducerState(
    producer: CbssStreamProducerHandle
): uint32 {.exportc: "cbss_stream_producer_state", cdecl, dynlib.} =
  if producer.isNil:
    return uint32(ssClosed.ord)
  uint32(producer.producer.state.ord)

proc cbssStreamProducerOpen(
    producer: CbssStreamProducerHandle
): uint32 {.exportc: "cbss_stream_producer_open", cdecl, dynlib.} =
  if producer.isNil:
    return CbssStreamOfferDisposed
  producer.producer.open().toCStreamOffer()

proc cbssStreamProducerPushBlob(
    producer: CbssStreamProducerHandle;
    blob: CbssBlobHandle;
    weight: uint64
): uint32 {.exportc: "cbss_stream_producer_push_blob", cdecl, dynlib.} =
  if producer.isNil:
    return CbssStreamOfferDisposed
  if blob.isNil or weight > uint64(high(int64)):
    return CbssStreamOfferInvalidArgument
  if cbssBlobRetain(blob) != CbssOk:
    return CbssStreamOfferInvalidArgument
  var payload = CbssStreamBlobPayload(blob: blob)
  producer.producer.pushData(move(payload), int64(weight)).toCStreamOffer()

proc cbssStreamProducerProgress(
    producer: CbssStreamProducerHandle;
    completed, total: uint64;
    hasTotal: uint8
): uint32 {.exportc: "cbss_stream_producer_progress", cdecl, dynlib.} =
  if producer.isNil:
    return CbssStreamOfferDisposed
  if hasTotal > 1 or (hasTotal == 1 and completed > total):
    return CbssStreamOfferInvalidArgument
  let totalValue = if hasTotal == 1: some(total) else: none(uint64)
  producer.producer.reportProgress(completed, totalValue).toCStreamOffer()

proc cbssStreamProducerFinish(
    producer: CbssStreamProducerHandle
): uint32 {.exportc: "cbss_stream_producer_finish", cdecl, dynlib.} =
  if producer.isNil:
    return CbssStreamOfferDisposed
  producer.producer.finish().toCStreamOffer()

proc cbssStreamProducerFail(
    producer: CbssStreamProducerHandle;
    message: cstring
): uint32 {.exportc: "cbss_stream_producer_fail", cdecl, dynlib.} =
  if producer.isNil:
    return CbssStreamOfferDisposed
  let length = boundedCStringLength(message, CbssMaxStreamErrorBytes)
  if length <= 0 or length > CbssMaxStreamErrorBytes:
    return CbssStreamOfferInvalidArgument
  producer.producer.fail($message).toCStreamOffer()

proc cbssStreamProducerCancel(
    producer: CbssStreamProducerHandle
): uint32 {.exportc: "cbss_stream_producer_cancel", cdecl, dynlib.} =
  if producer.isNil:
    return CbssStreamOfferDisposed
  producer.producer.cancel().toCStreamOffer()

proc cbssStreamProducerClose(
    producer: CbssStreamProducerHandle
): uint32 {.exportc: "cbss_stream_producer_close", cdecl, dynlib.} =
  if producer.isNil:
    return CbssStreamOfferDisposed
  producer.producer.close().toCStreamOffer()

proc cbssBlobStreamPump(
    stream: CbssBlobStreamHandle;
    maxMessages: uint32;
    output: ptr CbssStreamPumpResultC
): int32 {.exportc: "cbss_blob_stream_pump", cdecl, dynlib.} =
  if stream.isNil:
    return CbssInvalidHandle
  if output.isNil or maxMessages == 0 or
      uint64(maxMessages) > uint64(high(int)):
    return CbssInvalidArgument
  output[] = default(CbssStreamPumpResultC)
  let pumped = stream.mailbox.pumpInto(stream.bridge, int(maxMessages))
  output.processed = uint32(pumped.processed)
  output.rejected = uint32(pumped.rejected)
  output.changed = uint8(pumped.changed)
  output.backpressured = uint8(pumped.backpressured)
  output.pending = uint8(pumped.pending)
  CbssOk

proc cbssBlobStreamNext(
    stream: CbssBlobStreamHandle;
    output: ptr CbssStreamEventC
): int32 {.exportc: "cbss_blob_stream_next", cdecl, dynlib.} =
  if stream.isNil:
    return CbssInvalidHandle
  if output.isNil:
    return CbssInvalidArgument
  output[] = default(CbssStreamEventC)
  var events = stream.bridge.drain(1)
  if events.len == 0:
    return CbssNotAvailable
  var event = move(events[0])
  output.kind = uint32(event.kind.ord)
  case event.kind
  of sekData:
    output.blob = event.data.takeBlob()
    output.weight = uint64(event.weight)
  of sekProgress:
    output.completed = event.completed
    if event.total.isSome:
      output.flags = CbssStreamEventHasTotal
      output.total = event.total.get
  of sekError:
    stream.lastError = move(event.message)
    output.messageBytes = uint32(stream.lastError.len)
  else:
    discard
  CbssOk

proc cbssBlobStreamErrorMessage(
    stream: CbssBlobStreamHandle;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_blob_stream_error_message", cdecl, dynlib.} =
  if stream.isNil:
    return 0
  result = uint32(stream.lastError.len)
  if buffer.isNil or capacity == 0:
    return
  let copyLength = int(min(uint32(stream.lastError.len), capacity - 1))
  if copyLength > 0:
    copyMem(buffer, unsafeAddr stream.lastError[0], copyLength)
  cast[ptr UncheckedArray[char]](buffer)[copyLength] = '\0'

proc cbssBlobStreamHasPending(
    stream: CbssBlobStreamHandle
): uint8 {.exportc: "cbss_blob_stream_has_pending", cdecl, dynlib.} =
  if stream.isNil:
    return 0
  uint8(stream.mailbox.hasPending or stream.bridge.hasPending)

proc releaseFormDataEntry(entry: var CbssFormDataEntryObj) =
  if not entry.nameBytes.isNil:
    deallocShared(entry.nameBytes)
    entry.nameBytes = nil
  if not entry.textBytes.isNil:
    deallocShared(entry.textBytes)
    entry.textBytes = nil
  if not entry.fileNameBytes.isNil:
    deallocShared(entry.fileNameBytes)
    entry.fileNameBytes = nil
  if not entry.blob.isNil:
    cbssBlobRelease(entry.blob)
    entry.blob = nil

proc releaseFormDataEntries(entries: var seq[CbssFormDataEntryObj]) =
  for entry in entries.mitems:
    entry.releaseFormDataEntry()
  entries.setLen(0)

proc sharedCStringCopy(value: cstring; length: int): pointer =
  if length <= 0:
    return nil
  result = allocShared(length)
  if not result.isNil:
    copyMem(result, value, length)

proc sharedStringCopy(value: string): pointer =
  if value.len == 0:
    return nil
  result = allocShared(value.len)
  if not result.isNil:
    copyMem(result, unsafeAddr value[0], value.len)

proc copySharedString(
    bytes: pointer;
    length: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 =
  result = length
  if buffer.isNil or capacity == 0:
    return
  let copyLength = min(int(length), int(capacity) - 1)
  if copyLength > 0:
    copyMem(buffer, bytes, copyLength)
  cast[ptr UncheckedArray[char]](buffer)[copyLength] = '\0'

proc boundedCStringLength(value: cstring; maximum: int): int =
  if value.isNil:
    return -1
  let bytes = cast[ptr UncheckedArray[char]](value)
  while result <= maximum and bytes[result] != '\0':
    inc result

proc finishFormDataEntries(
    entries: var seq[CbssFormDataEntryObj];
    output: ptr CbssFormDataHandle
): int32 =
  if output.isNil:
    return CbssInvalidArgument
  output[] = nil
  let snapshot = cast[CbssFormDataHandle](
    allocShared0(sizeof(CbssFormDataObj))
  )
  if snapshot.isNil:
    return CbssInternalError
  let count = entries.len
  if count > 0:
    snapshot.entries = allocShared(count * sizeof(CbssFormDataEntryObj))
    if snapshot.entries.isNil:
      deallocShared(snapshot)
      return CbssInternalError
    copyMem(
      snapshot.entries,
      unsafeAddr entries[0],
      count * sizeof(CbssFormDataEntryObj)
    )
    for entry in entries.mitems:
      entry.nameBytes = nil
      entry.textBytes = nil
      entry.fileNameBytes = nil
      entry.blob = nil
  snapshot.length = uint32(count)
  snapshot.references.store(1)
  entries.setLen(0)
  output[] = snapshot
  CbssOk

proc cbssFormDataBuilderCreate(): CbssFormDataBuilderHandle {.
    exportc: "cbss_form_data_builder_create", cdecl, dynlib.} =
  ensureNimRuntime()
  try:
    result = create(CbssFormDataBuilderObj)
    result[] = CbssFormDataBuilderObj(entries: @[])
  except CatchableError:
    result = nil

proc cbssFormDataBuilderDestroy(builder: CbssFormDataBuilderHandle) {.
    exportc: "cbss_form_data_builder_destroy", cdecl, dynlib.} =
  if builder.isNil:
    return
  builder.entries.releaseFormDataEntries()
  `=destroy`(builder[])
  dealloc(builder)

proc cbssFormDataBuilderAddText(
    builder: CbssFormDataBuilderHandle;
    name, value: cstring
): int32 {.exportc: "cbss_form_data_builder_add_text", cdecl, dynlib.} =
  if builder.isNil:
    return CbssInvalidHandle
  if builder.finished:
    return CbssInvalidArgument
  if builder.entries.len >= CbssMaxFormDataEntries:
    return CbssOutOfRange
  let nameLength = boundedCStringLength(name, CbssMaxFormDataNameBytes)
  let valueLength = boundedCStringLength(value, CbssMaxFormDataTextBytes)
  if nameLength <= 0 or valueLength < 0:
    return CbssInvalidArgument
  if nameLength > CbssMaxFormDataNameBytes or
      valueLength > CbssMaxFormDataTextBytes:
    return CbssOutOfRange
  var entry = CbssFormDataEntryObj(
    nameBytes: sharedCStringCopy(name, nameLength),
    nameLength: uint32(nameLength),
    kind: CbssFormDataText,
    textBytes: sharedCStringCopy(value, valueLength),
    textLength: uint32(valueLength)
  )
  if entry.nameBytes.isNil or (valueLength > 0 and entry.textBytes.isNil):
    entry.releaseFormDataEntry()
    return CbssInternalError
  try:
    builder.entries.add entry
    CbssOk
  except CatchableError:
    entry.releaseFormDataEntry()
    CbssInternalError

proc cbssFormDataBuilderAddBlob(
    builder: CbssFormDataBuilderHandle;
    name: cstring;
    blob: CbssBlobHandle;
    fileName: cstring
): int32 {.exportc: "cbss_form_data_builder_add_blob", cdecl, dynlib.} =
  if builder.isNil or blob.isNil:
    return CbssInvalidHandle
  if builder.finished:
    return CbssInvalidArgument
  if builder.entries.len >= CbssMaxFormDataEntries:
    return CbssOutOfRange
  let nameLength = boundedCStringLength(name, CbssMaxFormDataNameBytes)
  let fileNameLength = boundedCStringLength(
    fileName, CbssMaxFormDataNameBytes
  )
  if nameLength <= 0:
    return CbssInvalidArgument
  if nameLength > CbssMaxFormDataNameBytes or
      fileNameLength > CbssMaxFormDataNameBytes:
    return CbssOutOfRange
  let retainStatus = cbssBlobRetain(blob)
  if retainStatus != CbssOk:
    return retainStatus
  var entry = CbssFormDataEntryObj(
    nameBytes: sharedCStringCopy(name, nameLength),
    nameLength: uint32(nameLength),
    kind: CbssFormDataBlob,
    blob: blob,
    fileNameBytes:
      if fileNameLength > 0:
        sharedCStringCopy(fileName, fileNameLength)
      else:
        nil,
    fileNameLength: uint32(max(fileNameLength, 0))
  )
  if entry.nameBytes.isNil or
      (fileNameLength > 0 and entry.fileNameBytes.isNil):
    entry.releaseFormDataEntry()
    return CbssInternalError
  try:
    builder.entries.add entry
    CbssOk
  except CatchableError:
    entry.releaseFormDataEntry()
    CbssInternalError

proc cbssFormDataBuilderFinish(
    builder: CbssFormDataBuilderHandle;
    output: ptr CbssFormDataHandle
): int32 {.exportc: "cbss_form_data_builder_finish", cdecl, dynlib.} =
  if builder.isNil:
    return CbssInvalidHandle
  if output.isNil:
    return CbssInvalidArgument
  output[] = nil
  if builder.finished:
    return CbssInvalidArgument
  let status = finishFormDataEntries(builder.entries, output)
  if status != CbssOk:
    return status
  builder.finished = true
  CbssOk

proc cbssFormDataRetain(data: CbssFormDataHandle): int32 {.
    exportc: "cbss_form_data_retain", cdecl, dynlib.} =
  if data.isNil:
    return CbssInvalidHandle
  var current = data.references.load()
  while current > 0 and current < high(uint32):
    var expected = current
    if data.references.compareExchange(expected, current + 1):
      return CbssOk
    current = expected
  if current == high(uint32): CbssOutOfRange else: CbssInvalidHandle

proc cbssFormDataRelease(data: CbssFormDataHandle) {.
    exportc: "cbss_form_data_release", cdecl, dynlib.} =
  if data.isNil:
    return
  let previous = data.references.fetchSub(1)
  if previous != 1:
    return
  if not data.entries.isNil:
    let entries = cast[ptr UncheckedArray[CbssFormDataEntryObj]](data.entries)
    for index in 0 ..< int(data.length):
      entries[index].releaseFormDataEntry()
    deallocShared(data.entries)
  deallocShared(data)

proc cbssFormDataLength(data: CbssFormDataHandle): uint32 {.
    exportc: "cbss_form_data_length", cdecl, dynlib, raises: [].} =
  if data.isNil: 0'u32 else: data.length

proc cbssFormDataEntryKind(
    data: CbssFormDataHandle;
    index: uint32;
    output: ptr uint32
): int32 {.exportc: "cbss_form_data_entry_kind", cdecl, dynlib.} =
  if data.isNil:
    return CbssInvalidHandle
  if output.isNil:
    return CbssInvalidArgument
  if index >= data.length:
    return CbssOutOfRange
  let entries = cast[ptr UncheckedArray[CbssFormDataEntryObj]](data.entries)
  output[] = entries[int(index)].kind
  CbssOk

proc cbssFormDataEntryName(
    data: CbssFormDataHandle;
    index: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_form_data_entry_name", cdecl, dynlib.} =
  if data.isNil or index >= data.length:
    return 0
  let entries = cast[ptr UncheckedArray[CbssFormDataEntryObj]](data.entries)
  let entry = entries[int(index)]
  copySharedString(entry.nameBytes, entry.nameLength, buffer, capacity)

proc cbssFormDataEntryText(
    data: CbssFormDataHandle;
    index: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_form_data_entry_text", cdecl, dynlib.} =
  if data.isNil or index >= data.length:
    return 0
  let entries = cast[ptr UncheckedArray[CbssFormDataEntryObj]](data.entries)
  let entry = entries[int(index)]
  if entry.kind != CbssFormDataText:
    return 0
  copySharedString(entry.textBytes, entry.textLength, buffer, capacity)

proc cbssFormDataEntryFileName(
    data: CbssFormDataHandle;
    index: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_form_data_entry_file_name", cdecl, dynlib.} =
  if data.isNil or index >= data.length:
    return 0
  let entries = cast[ptr UncheckedArray[CbssFormDataEntryObj]](data.entries)
  let entry = entries[int(index)]
  if entry.kind != CbssFormDataBlob:
    return 0
  copySharedString(
    entry.fileNameBytes, entry.fileNameLength, buffer, capacity
  )

proc cbssFormDataEntryBlob(
    data: CbssFormDataHandle;
    index: uint32;
    output: ptr CbssBlobHandle
): int32 {.exportc: "cbss_form_data_entry_blob", cdecl, dynlib.} =
  if data.isNil:
    return CbssInvalidHandle
  if output.isNil:
    return CbssInvalidArgument
  output[] = nil
  if index >= data.length:
    return CbssOutOfRange
  let entries = cast[ptr UncheckedArray[CbssFormDataEntryObj]](data.entries)
  let entry = entries[int(index)]
  if entry.kind != CbssFormDataBlob or entry.blob.isNil:
    return CbssInvalidArgument
  let status = cbssBlobRetain(entry.blob)
  if status == CbssOk:
    output[] = entry.blob
  status

proc cBlobSnapshot(value: Blob; output: ptr CbssBlobHandle): int32 =
  if output.isNil:
    return CbssInvalidArgument
  output[] = nil
  if not value.isValid:
    return CbssInvalidArgument
  if value.size > CbssMaxEagerBlobBytes:
    return CbssOutOfRange
  let bytes = value.readAll(int(CbssMaxEagerBlobBytes))
  let mime = if value.mimeType.isSome: value.mimeType.get else: ""
  if mime.len > CbssMaxBlobMimeBytes or '\0' in mime:
    return CbssOutOfRange
  cbssBlobCreate(
    if bytes.len > 0: unsafeAddr bytes[0] else: nil,
    uint64(bytes.len),
    if mime.len > 0: mime.cstring else: nil,
    output
  )

proc cFormDataSnapshot(
    value: FormData;
    output: ptr CbssFormDataHandle
): int32 =
  if output.isNil:
    return CbssInvalidArgument
  output[] = nil
  if value.len > CbssMaxFormDataEntries:
    return CbssOutOfRange
  var converted = newSeqOfCap[CbssFormDataEntryObj](value.len)
  try:
    for item in value.items:
      if item.name.len == 0:
        converted.releaseFormDataEntries()
        return CbssInvalidArgument
      if item.name.len > CbssMaxFormDataNameBytes:
        converted.releaseFormDataEntries()
        return CbssOutOfRange
      var entry = CbssFormDataEntryObj(
        nameBytes: sharedStringCopy(item.name),
        nameLength: uint32(item.name.len)
      )
      if entry.nameBytes.isNil:
        entry.releaseFormDataEntry()
        converted.releaseFormDataEntries()
        return CbssInternalError
      case item.kind
      of fdvText:
        if item.text.len > CbssMaxFormDataTextBytes:
          entry.releaseFormDataEntry()
          converted.releaseFormDataEntries()
          return CbssOutOfRange
        entry.kind = CbssFormDataText
        entry.textBytes = sharedStringCopy(item.text)
        entry.textLength = uint32(item.text.len)
        if item.text.len > 0 and entry.textBytes.isNil:
          entry.releaseFormDataEntry()
          converted.releaseFormDataEntries()
          return CbssInternalError
      of fdvBlob:
        entry.kind = CbssFormDataBlob
        let blobStatus = cBlobSnapshot(item.blob, addr entry.blob)
        if blobStatus != CbssOk:
          entry.releaseFormDataEntry()
          converted.releaseFormDataEntries()
          return blobStatus
        if item.fileName.isSome:
          let fileName = item.fileName.get
          if fileName.len > CbssMaxFormDataNameBytes:
            entry.releaseFormDataEntry()
            converted.releaseFormDataEntries()
            return CbssOutOfRange
          entry.fileNameBytes = sharedStringCopy(fileName)
          entry.fileNameLength = uint32(fileName.len)
          if fileName.len > 0 and entry.fileNameBytes.isNil:
            entry.releaseFormDataEntry()
            converted.releaseFormDataEntries()
            return CbssInternalError
      converted.add entry
    finishFormDataEntries(converted, output)
  except CatchableError:
    converted.releaseFormDataEntries()
    CbssInternalError

proc copiedString(bytes: pointer; length: uint32): string =
  if length == 0:
    return ""
  result = newString(int(length))
  copyMem(addr result[0], bytes, int(length))

proc nimFormDataSnapshot(
    value: CbssFormDataHandle;
    output: var FormData
): int32 =
  if value.isNil:
    return CbssInvalidHandle
  var builder = initFormDataBuilder()
  try:
    let entries = cast[ptr UncheckedArray[CbssFormDataEntryObj]](
      value.entries
    )
    for index in 0 ..< int(value.length):
      let entry = entries[index]
      let name = copiedString(entry.nameBytes, entry.nameLength)
      if name.len == 0:
        return CbssInvalidArgument
      case entry.kind
      of CbssFormDataText:
        builder.addText(name, copiedString(entry.textBytes, entry.textLength))
      of CbssFormDataBlob:
        if entry.blob.isNil or entry.blob.length > CbssMaxEagerBlobBytes:
          return CbssOutOfRange
        var bytes = newSeq[byte](int(entry.blob.length))
        if bytes.len > 0:
          copyMem(addr bytes[0], entry.blob.bytes, bytes.len)
        let mime = copiedString(entry.blob.mimeBytes, entry.blob.mimeLength)
        builder.addBlob(
          name,
          newBlob(bytes, mime),
          copiedString(entry.fileNameBytes, entry.fileNameLength)
        )
      else:
        return CbssInvalidArgument
    output = builder.finish()
    CbssOk
  except CatchableError:
    CbssInternalError

proc cbssEventViewEvent(view: CbssEventViewHandle): ptr CbssEventC {.
    exportc: "cbss_event_view_event", cdecl, dynlib, raises: [].} =
  if view.isNil: nil else: addr view.event

proc cbssEventViewFormData(
    view: CbssEventViewHandle;
    output: ptr CbssFormDataHandle
): int32 {.exportc: "cbss_event_view_form_data", cdecl, dynlib.} =
  if output.isNil:
    return CbssInvalidArgument
  output[] = nil
  if view.isNil:
    return CbssInvalidHandle
  if view.formData.isNil:
    return view.formDataStatus
  let status = cbssFormDataRetain(view.formData)
  if status == CbssOk:
    output[] = view.formData
  status

proc cEventViewHandler(
    context: CbssContextHandle;
    callback: CbssEventViewCallback;
    userData: pointer
): EventHandler =
  result = proc(dispatch: DispatchResult): EventOutcome =
    if callback.isNil or dispatch.target.isNone or
        dispatch.currentTarget.isNone:
      return ignoredEvent()
    var view = CbssEventViewObj(
      event: dispatch.callbackEvent(
        dispatch.target.get, dispatch.currentTarget.get
      ),
      formDataStatus: CbssNotAvailable
    )
    let motionName = dispatch.motionName
    if (view.event.flags and CbssEventHasMotion) != 0:
      view.event.motionName = motionName.cstring
    let payload = dispatch.formData()
    if payload.isSome:
      let status = cFormDataSnapshot(payload.get, addr view.formData)
      view.formDataStatus = status
      if status != CbssOk:
        context.setError(
          "event FormData payload could not cross the C ABI: " & $status
        )
    let outcome = callbackOutcome(callback(context, addr view, userData))
    if not view.formData.isNil:
      cbssFormDataRelease(view.formData)
    outcome

proc cbssContextCreate(): CbssContextHandle {.
    exportc: "cbss_context_create", cdecl, dynlib.} =
  ensureNimRuntime()
  var allocated: CbssContextHandle = nil
  try:
    allocated = create(CbssContextObj)
    allocated[] = CbssContextObj(
      tree: initTree(),
      sheets: @[],
      appliedStyles: @[],
      craftPacks: initCraftPackRegistry(),
      craftStyles: initCraftStyleSlotRuntime(),
      craftDiagnostics: @[],
      resolved: ResolvedTree(styles: @[]),
      layout: LayoutResult(boxes: @[], overflowMetrics: @[]),
      commands: @[],
      hits: @[],
      scroll: initScrollState(),
      interaction: initInteractionState(),
      events: initEventRegistry(),
      eventSubscriptions: initTable[uint64, EventSubscription](),
      surfaces: initRenderSurfaceRegistry(),
      surfaceBindings: initTable[RenderSurfaceId, CbssRenderSurfaceBinding](),
      pixelScale: 1.0'f32,
      diagnostics: Diagnostics(items: @[]),
      computed: false,
      hasViewport: false,
      keyframes: initDeclarativeKeyframeRuntime(),
      transitions: initDeclarativeTransitionRuntime(),
      motionScheduler: initFrameScheduler(),
      motionNow: 0,
      motionTimeInitialized: false,
      reducedMotion: false,
      motionDirtyDomains: 0
    )
    let owner = allocated
    allocated.surfacePaintProvider = proc(
        surfaceValue: uint64;
        node: NodeId;
        bounds: Rect;
        opacity: float32
    ): seq[PaintCommand] =
      let binding = owner.surfaceBinding(surfaceValue)
      if not binding.isNil:
        result = binding.committedCanvas.paintCommands(
          node, bounds, opacity, resolveBounds = false
        )
    result = allocated
  except CatchableError:
    if not allocated.isNil:
      `=destroy`(allocated[])
      dealloc(allocated)
    result = nil

proc cbssContextDestroy(context: CbssContextHandle) {.
    exportc: "cbss_context_destroy", cdecl, dynlib.} =
  if context.isNil:
    return
  context.computed = false
  try:
    context.cancelAllMotion()
  except CatchableError:
    discard
  context.surfaces.unmountAllSurfaces()
  context.surfacePaintProvider = nil
  `=destroy`(context[])
  dealloc(context)

proc cbssContextReset(context: CbssContextHandle): int32 {.
    exportc: "cbss_context_reset", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  try:
    context.computed = false
    context.cancelAllMotion()
    context.surfaces.unmountAllSurfaces()
    context.tree = initTree()
    context.sheets.setLen(0)
    context.appliedStyles.setLen(0)
    context.craftPacks = initCraftPackRegistry()
    context.craftStyles = initCraftStyleSlotRuntime()
    context.craftDiagnostics.setLen(0)
    context.resolved.styles.setLen(0)
    context.layout = LayoutResult(boxes: @[], overflowMetrics: @[])
    context.commands.setLen(0)
    context.hits.setLen(0)
    context.scroll = initScrollState()
    context.interaction = initInteractionState()
    context.events = initEventRegistry()
    context.eventSubscriptions.clear()
    context.pixelScale = 1.0'f32
    context.diagnostics.items.setLen(0)
    context.lastError = ""
    context.computed = false
    context.hasViewport = false
    context.viewportWidth = 0
    context.viewportHeight = 0
    context.keyframes = initDeclarativeKeyframeRuntime()
    context.transitions = initDeclarativeTransitionRuntime()
    context.motionScheduler = initFrameScheduler()
    context.motionNow = 0
    context.motionTimeInitialized = false
    context.reducedMotion = false
    context.motionDirtyDomains = 0
    CbssOk
  except CatchableError as error:
    context.setError(error.msg)
    CbssInternalError

proc cbssContextLastError(
    context: CbssContextHandle;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_context_last_error", cdecl, dynlib.} =
  if context.isNil:
    return copyString("invalid CBSS context", buffer, capacity)
  copyString(context.lastError, buffer, capacity)

proc craftStyleParseCode(code: CraftStyleDiagnosticCode): uint32 =
  case code
  of csdcInvalidJson: 0
  of csdcInvalidDocument: 1
  of csdcUnsupportedVersion: 2
  of csdcMissingField: 3
  of csdcUnknownField: 4
  of csdcInvalidType: 5
  of csdcInvalidValue: 6
  of csdcUnknownProperty: 7
  of csdcDuplicateField: 8
  of csdcLimitExceeded: 9

proc craftStyleReplacementCode(
    code: CraftStyleReplacementDiagnosticCode
): uint32 =
  case code
  of csrUnsupportedRuleTarget: 0
  of csrUndeclaredStyleSlot: 1
  of csrInvalidStyleSlot: 2
  of csrInvalidCraftStyle: 3

proc craftPackCode(code: CraftPackDiagnosticCode): uint32 =
  case code
  of cpdcInvalidJson: 0
  of cpdcInvalidDocument: 1
  of cpdcUnsupportedVersion: 2
  of cpdcMissingField: 3
  of cpdcUnknownField: 4
  of cpdcInvalidType: 5
  of cpdcInvalidValue: 6
  of cpdcDuplicateField: 7
  of cpdcDuplicateValue: 8
  of cpdcLimitExceeded: 9
  of cpdcIncompatibleAbi: 10
  of cpdcIncompatibleDriverContract: 11
  of cpdcMissingCapability: 12

proc clearCraftDiagnostics(context: CbssContextHandle) =
  context.craftDiagnostics.setLen(0)

proc addCraftDiagnostic(
    context: CbssContextHandle;
    domain, code: uint32;
    path, message: string
) =
  context.craftDiagnostics.add CbssCraftDiagnosticRecord(
    domain: domain,
    code: code,
    path: path,
    message: message
  )

proc recordCraftStyleDiagnostics(
    context: CbssContextHandle;
    loaded: CraftStyleLoadResult
) =
  context.clearCraftDiagnostics()
  for diagnostic in loaded.parseDiagnostics:
    context.addCraftDiagnostic(
      CbssCraftDiagnosticStyleParse,
      craftStyleParseCode(diagnostic.code),
      diagnostic.path,
      diagnostic.message
    )
  for diagnostic in loaded.replacementDiagnostics:
    context.addCraftDiagnostic(
      CbssCraftDiagnosticStyleReplacement,
      craftStyleReplacementCode(diagnostic.code),
      diagnostic.path,
      diagnostic.message
    )

proc recordCraftPackDiagnostics(
    context: CbssContextHandle;
    loaded: CraftPackLoadResult
) =
  context.clearCraftDiagnostics()
  for diagnostic in loaded.diagnostics:
    context.addCraftDiagnostic(
      CbssCraftDiagnosticPack,
      craftPackCode(diagnostic.code),
      diagnostic.path,
      diagnostic.message
    )

proc setFirstCraftError(context: CbssContextHandle; fallback: string) =
  if context.craftDiagnostics.len > 0:
    context.setError(context.craftDiagnostics[0].message)
  else:
    context.setError(fallback)

proc sourceFromBytes(
    bytes: pointer;
    length, maximum: uint32;
    output: var string
): int32 =
  if bytes.isNil or length == 0:
    return CbssInvalidArgument
  if length > maximum or uint64(length) > uint64(high(int)):
    return CbssOutOfRange
  output = newString(int(length))
  copyMem(addr output[0], bytes, int(length))
  CbssOk

proc cbssContextCraftDiagnosticCount(
    context: CbssContextHandle
): uint32 {.exportc: "cbss_context_craft_diagnostic_count", cdecl, dynlib.} =
  if context.isNil:
    return 0
  uint32(min(context.craftDiagnostics.len, int(high(uint32))))

proc cbssContextCraftDiagnosticAt(
    context: CbssContextHandle;
    index: uint32;
    output: ptr CbssCraftDiagnosticC
): int32 {.exportc: "cbss_context_craft_diagnostic_at", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if output.isNil:
    return CbssInvalidArgument
  if index >= uint32(context.craftDiagnostics.len):
    return CbssOutOfRange
  let diagnostic = context.craftDiagnostics[int(index)]
  output[] = CbssCraftDiagnosticC(
    domain: diagnostic.domain,
    code: diagnostic.code,
    pathBytes: uint32(min(diagnostic.path.len, int(high(uint32)))),
    messageBytes: uint32(min(diagnostic.message.len, int(high(uint32))))
  )
  CbssOk

proc cbssContextCraftDiagnosticPath(
    context: CbssContextHandle;
    index: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_context_craft_diagnostic_path", cdecl, dynlib.} =
  if context.isNil or index >= uint32(context.craftDiagnostics.len):
    return 0
  copyString(context.craftDiagnostics[int(index)].path, buffer, capacity)

proc cbssContextCraftDiagnosticMessage(
    context: CbssContextHandle;
    index: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_context_craft_diagnostic_message", cdecl, dynlib.} =
  if context.isNil or index >= uint32(context.craftDiagnostics.len):
    return 0
  copyString(context.craftDiagnostics[int(index)].message, buffer, capacity)

proc cbssNodeExposeCraftStyleSlot(
    context: CbssContextHandle;
    owner, target: uint32;
    component, slot: cstring
): int32 {.exportc: "cbss_node_expose_craft_style_slot", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(owner) or not context.validNode(target) or
      component.isNil or slot.isNil:
    return CbssInvalidArgument
  let componentLength = boundedCStringLength(component, maxCraftPackStringBytes)
  let slotLength = boundedCStringLength(slot, maxCraftPackStringBytes)
  if componentLength <= 0 or componentLength > maxCraftPackStringBytes or
      slotLength <= 0 or slotLength > maxCraftPackStringBytes:
    return CbssInvalidArgument
  try:
    let componentName = fromCString(component)
    let slotName = fromCString(slot)
    let added = context.craftStyles.exposePublicStyleSlot(
      context.tree,
      owner.nodeId,
      target.nodeId,
      componentName,
      slotName
    )
    if added:
      context.rebuildStyleSheets()
      if context.craftStyles.targetsPublicStyleSlot(componentName, slotName):
        context.invalidate()
    context.lastError = ""
    CbssOk
  except ValueError as error:
    context.setError(error.msg)
    CbssInvalidArgument
  except CatchableError as error:
    context.setError(error.msg)
    CbssInternalError

proc cbssContextReplaceCraftStyleJson(
    context: CbssContextHandle;
    bytes: pointer;
    length: uint32
): int32 {.exportc: "cbss_context_replace_craft_style_json", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  var source: string
  let sourceStatus = sourceFromBytes(
    bytes,
    length,
    CbssMaxCraftStyleSourceBytes,
    source
  )
  if sourceStatus != CbssOk:
    return sourceStatus
  try:
    let loaded = context.craftStyles.replaceCraftStyle(context.tree, source)
    context.recordCraftStyleDiagnostics(loaded)
    if not loaded.applied:
      context.setFirstCraftError("Craft Style replacement failed")
      return CbssStyleError
    context.rebuildStyleSheets()
    context.invalidate()
    context.lastError = ""
    CbssOk
  except CatchableError as error:
    context.setError(error.msg)
    CbssInternalError

proc cbssContextRemoveCraftStyle(
    context: CbssContextHandle;
    name: cstring;
    outputRemoved: ptr uint8
): int32 {.exportc: "cbss_context_remove_craft_style", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if name.isNil or outputRemoved.isNil:
    return CbssInvalidArgument
  let nameLength = boundedCStringLength(name, maxCraftPackStringBytes)
  if nameLength <= 0 or nameLength > maxCraftPackStringBytes:
    return CbssInvalidArgument
  let removed = context.craftStyles.removeCraftStyle(fromCString(name))
  outputRemoved[] = uint8(if removed.removed: 1 else: 0)
  if removed.removed:
    context.rebuildStyleSheets()
    context.invalidate()
  context.clearCraftDiagnostics()
  context.lastError = ""
  CbssOk

proc cbssContextActiveCraftStyleCount(
    context: CbssContextHandle
): uint32 {.exportc: "cbss_context_active_craft_style_count", cdecl, dynlib.} =
  if context.isNil:
    return 0
  uint32(min(context.craftStyles.activeCraftStyleNames().len, int(high(uint32))))

proc cbssContextActiveCraftStyleName(
    context: CbssContextHandle;
    index: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_context_active_craft_style_name", cdecl, dynlib.} =
  if context.isNil:
    return 0
  let names = context.craftStyles.activeCraftStyleNames()
  if index >= uint32(names.len):
    return 0
  copyString(names[int(index)], buffer, capacity)

proc cbssContextReplaceCraftPackJson(
    context: CbssContextHandle;
    bytes: pointer;
    length: uint32
): int32 {.exportc: "cbss_context_replace_craft_pack_json", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  var source: string
  let sourceStatus = sourceFromBytes(
    bytes,
    length,
    CbssMaxCraftPackSourceBytes,
    source
  )
  if sourceStatus != CbssOk:
    return sourceStatus
  try:
    let loaded = context.craftPacks.replaceCraftPack(source)
    context.recordCraftPackDiagnostics(loaded)
    if not loaded.loaded:
      context.setFirstCraftError("Craft Pack loading failed")
      return CbssStyleError
    context.lastError = ""
    CbssOk
  except CatchableError as error:
    context.setError(error.msg)
    CbssInternalError

proc cbssContextRemoveCraftPack(
    context: CbssContextHandle;
    id: cstring;
    outputRemoved: ptr uint8
): int32 {.exportc: "cbss_context_remove_craft_pack", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if id.isNil or outputRemoved.isNil:
    return CbssInvalidArgument
  let idLength = boundedCStringLength(id, maxCraftPackStringBytes)
  if idLength <= 0 or idLength > maxCraftPackStringBytes:
    return CbssInvalidArgument
  outputRemoved[] = uint8(if context.craftPacks.removeCraftPack(fromCString(id)): 1 else: 0)
  context.clearCraftDiagnostics()
  context.lastError = ""
  CbssOk

proc cbssContextActiveCraftPackCount(
    context: CbssContextHandle
): uint32 {.exportc: "cbss_context_active_craft_pack_count", cdecl, dynlib.} =
  if context.isNil:
    return 0
  uint32(min(context.craftPacks.craftPackCount(), int(high(uint32))))

proc cbssContextActiveCraftPackId(
    context: CbssContextHandle;
    index: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_context_active_craft_pack_id", cdecl, dynlib.} =
  if context.isNil:
    return 0
  let pack = context.craftPacks.craftPackAt(int(index))
  if pack.isNone:
    return 0
  copyString(pack.get.id, buffer, capacity)

proc cbssContextActiveCraftPackVersion(
    context: CbssContextHandle;
    index: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_context_active_craft_pack_version", cdecl, dynlib.} =
  if context.isNil:
    return 0
  let pack = context.craftPacks.craftPackAt(int(index))
  if pack.isNone:
    return 0
  copyString(pack.get.version, buffer, capacity)

proc cbssContextNodeCount(context: CbssContextHandle): uint32 {.
    exportc: "cbss_context_node_count", cdecl, dynlib.} =
  if context.isNil:
    return 0
  uint32(min(context.tree.nodes.len, int(high(uint32))))

proc cbssNodeKind(
    context: CbssContextHandle;
    node: uint32
): uint32 {.exportc: "cbss_node_kind", cdecl, dynlib.} =
  if context.isNil or not context.validNode(node):
    return high(uint32)
  uint32(ord(context.tree.nodes[node.nodeId.nodeIndex].kind))

proc cbssNodeParent(
    context: CbssContextHandle;
    node: uint32
): uint32 {.exportc: "cbss_node_parent", cdecl, dynlib.} =
  if context.isNil or not context.validNode(node):
    return CbssNodeNone
  let parent = context.tree.nodes[node.nodeId.nodeIndex].parent
  if parent.isSome: parent.get.nodeRawValue() else: CbssNodeNone

proc cbssNodeChildCount(
    context: CbssContextHandle;
    node: uint32
): uint32 {.exportc: "cbss_node_child_count", cdecl, dynlib.} =
  if context.isNil or not context.validNode(node):
    return 0
  uint32(min(
    context.tree.nodes[node.nodeId.nodeIndex].children.len,
    int(high(uint32))
  ))

proc cbssNodeChild(
    context: CbssContextHandle;
    node, index: uint32
): uint32 {.exportc: "cbss_node_child", cdecl, dynlib.} =
  if context.isNil or not context.validNode(node):
    return CbssNodeNone
  let children = context.tree.nodes[node.nodeId.nodeIndex].children
  if uint64(index) >= uint64(children.len):
    return CbssNodeNone
  children[int(index)].nodeRawValue()

proc cbssNodeIdentifier(
    context: CbssContextHandle;
    node: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_node_identifier", cdecl, dynlib.} =
  if context.isNil or not context.validNode(node):
    return 0
  copyString(
    context.tree.nodes[node.nodeId.nodeIndex].id, buffer, capacity
  )

proc cbssNodeText(
    context: CbssContextHandle;
    node: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_node_text", cdecl, dynlib.} =
  if context.isNil or not context.validNode(node):
    return 0
  let value = context.tree.nodes[node.nodeId.nodeIndex]
  if value.kind != nkText:
    return 0
  copyString(value.text, buffer, capacity)

proc cbssNodeImageSource(
    context: CbssContextHandle;
    node: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_node_image_source", cdecl, dynlib.} =
  if context.isNil or not context.validNode(node):
    return 0
  let value = context.tree.nodes[node.nodeId.nodeIndex]
  if value.kind != nkImage:
    return 0
  copyString(value.imageSource, buffer, capacity)

proc cbssContextRemoveSubtree(
    context: CbssContextHandle;
    root: uint32;
    outputRemovedCount: ptr uint32
): int32 {.exportc: "cbss_context_remove_subtree", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if outputRemovedCount.isNil:
    return CbssInvalidArgument
  outputRemovedCount[] = 0
  if not context.validNode(root):
    return CbssInvalidArgument
  try:
    let removedCount = context.removeContextSubtree(root.nodeId)
    outputRemovedCount[] = uint32(min(removedCount, int(high(uint32))))
    context.lastError = ""
    CbssOk
  except CatchableError as error:
    context.setError(error.msg)
    CbssInternalError

proc cbssContextAddBox(
    context: CbssContextHandle;
    parent: uint32;
    identifier: cstring
): uint32 {.exportc: "cbss_context_add_box", cdecl, dynlib.} =
  if context.isNil:
    return CbssNodeNone
  if parent == CbssNodeNone:
    if context.tree.root.isSome:
      context.setError("a CBSS context can have only one root node")
      return CbssNodeNone
  elif not context.validNode(parent):
    context.setError("invalid parent node")
    return CbssNodeNone
  try:
    let id = context.tree.addBox(
      parent =
        if parent == CbssNodeNone: none(NodeId)
        else: some(parent.nodeId),
      id = fromCString(identifier)
    )
    context.invalidate()
    id.nodeRawValue()
  except CatchableError as error:
    context.setError(error.msg)
    CbssNodeNone

proc cbssContextAddText(
    context: CbssContextHandle;
    parent: uint32;
    text: cstring;
    identifier: cstring
): uint32 {.exportc: "cbss_context_add_text", cdecl, dynlib.} =
  if context.isNil:
    return CbssNodeNone
  if not context.validNode(parent) or text.isNil:
    context.setError("text nodes require a valid parent and non-null text")
    return CbssNodeNone
  try:
    let id = context.tree.addText(
      parent.nodeId, fromCString(text), id = fromCString(identifier)
    )
    context.invalidate()
    id.nodeRawValue()
  except CatchableError as error:
    context.setError(error.msg)
    CbssNodeNone

proc cbssContextAddImage(
    context: CbssContextHandle;
    parent: uint32;
    source: cstring;
    width, height: cfloat;
    identifier: cstring
): uint32 {.exportc: "cbss_context_add_image", cdecl, dynlib.} =
  if context.isNil:
    return CbssNodeNone
  if not context.validNode(parent) or source.isNil:
    context.setError("image nodes require a valid parent and non-null source")
    return CbssNodeNone
  try:
    let id = context.tree.addImage(
      parent.nodeId,
      fromCString(source),
      width = width,
      height = height,
      id = fromCString(identifier)
    )
    context.invalidate()
    id.nodeRawValue()
  except CatchableError as error:
    context.setError(error.msg)
    CbssNodeNone

proc cbssContextRegisterRenderSurface(
    context: CbssContextHandle;
    name: cstring;
    callback: CbssRenderSurfaceCallback;
    userData: pointer;
    output: ptr uint64
): int32 {.exportc: "cbss_context_register_render_surface", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if callback.isNil or output.isNil:
    return CbssInvalidArgument
  output[] = 0'u64
  try:
    let binding = CbssRenderSurfaceBinding(
      context: context,
      surface: RenderSurfaceId(0),
      mountedNode: CbssNodeNone,
      callback: callback,
      userData: userData,
      canvas: newCanvas2D(),
      committedCanvas: newCanvas2D(),
      committedCanvasRevision: 1,
      publishedRevision: 0
    )
    let surface = context.surfaces.registerSurface(
      binding.cRenderSurfaceDescriptor(fromCString(name))
    )
    binding.surface = surface
    context.surfaceBindings[surface] = binding
    output[] = surface.renderSurfaceIdValue
    CbssOk
  except CatchableError as error:
    context.setError(error.msg)
    CbssInternalError

proc cbssContextUnregisterRenderSurface(
    context: CbssContextHandle;
    surfaceValue: uint64
): int32 {.exportc: "cbss_context_unregister_render_surface", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if surfaceValue == 0:
    return CbssInvalidArgument
  let surface = RenderSurfaceId(surfaceValue)
  if not context.surfaces.hasSurface(surface):
    return CbssOutOfRange
  for node in context.tree.nodes.mitems:
    if node.renderSurfaceId == some(surfaceValue):
      node.renderSurfaceId = none(uint64)
  discard context.surfaces.unregisterSurface(surface)
  context.surfaceBindings.del(surface)
  context.invalidate()
  CbssOk

proc cbssContextAddRenderSurface(
    context: CbssContextHandle;
    parent: uint32;
    surfaceValue: uint64;
    identifier: cstring
): uint32 {.exportc: "cbss_context_add_render_surface", cdecl, dynlib.} =
  if context.isNil:
    return CbssNodeNone
  let surface = RenderSurfaceId(surfaceValue)
  if surfaceValue == 0 or not context.surfaces.hasSurface(surface):
    context.setError("render surface is not registered")
    return CbssNodeNone
  if parent == CbssNodeNone:
    if context.tree.root.isSome:
      context.setError("a CBSS context can have only one root node")
      return CbssNodeNone
  elif not context.validNode(parent):
    context.setError("invalid parent node")
    return CbssNodeNone
  for node in context.tree.nodes:
    if node.alive and node.renderSurfaceId == some(surfaceValue):
      context.setError("render surface is already assigned to a node")
      return CbssNodeNone
  try:
    let id = context.tree.addRenderSurfaceBox(
      surfaceValue,
      parent =
        if parent == CbssNodeNone: none(NodeId)
        else: some(parent.nodeId),
      id = fromCString(identifier)
    )
    context.invalidate()
    id.nodeRawValue()
  except CatchableError as error:
    context.setError(error.msg)
    CbssNodeNone

proc cbssRenderSurfaceUpdate(
    context: CbssContextHandle;
    surfaceValue, revision: uint64
): int32 {.exportc: "cbss_render_surface_update", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  let surface = RenderSurfaceId(surfaceValue)
  if surfaceValue == 0 or not context.surfaces.hasSurface(surface):
    return CbssOutOfRange
  let binding = context.surfaceBinding(surfaceValue)
  if not binding.isNil:
    binding.publishedRevision = revision
  discard context.surfaces.updateSurface(surface, revision)
  CbssOk

proc cbssRenderSurfaceRequestFrame(
    context: CbssContextHandle;
    surfaceValue: uint64
): int32 {.exportc: "cbss_render_surface_request_frame", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  let surface = RenderSurfaceId(surfaceValue)
  if surfaceValue == 0 or not context.surfaces.hasSurface(surface):
    return CbssOutOfRange
  if not context.surfaces.requestSurfaceFrame(surface):
    return CbssInvalidArgument
  CbssOk

proc cbssContextRunRenderSurfaceFrames(
    context: CbssContextHandle;
    nowSeconds: cdouble;
    outputCount: ptr uint32
): int32 {.exportc: "cbss_context_run_render_surface_frames", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  try:
    let count = context.surfaces.runSurfaceFrames(nowSeconds)
    if not outputCount.isNil:
      outputCount[] = uint32(min(count, int(high(uint32))))
    CbssOk
  except ValueError as error:
    context.setError(error.msg)
    CbssInvalidArgument
  except CatchableError as error:
    context.setError(error.msg)
    CbssInternalError

proc cbssContextNeedsRenderSurfaceFrame(
    context: CbssContextHandle
): uint8 {.exportc: "cbss_context_needs_render_surface_frame", cdecl, dynlib.} =
  if context.isNil:
    return 0
  uint8(ord(context.surfaces.needsSurfaceFrame()))

proc cbssRenderSurfaceSetDeviceAvailable(
    context: CbssContextHandle;
    surfaceValue: uint64;
    available: uint8
): int32 {.exportc: "cbss_render_surface_set_device_available", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  let surface = RenderSurfaceId(surfaceValue)
  if surfaceValue == 0 or not context.surfaces.hasSurface(surface):
    return CbssOutOfRange
  let changed =
    if available != 0:
      context.surfaces.restoreSurfaceDevice(surface)
    else:
      context.surfaces.loseSurfaceDevice(surface)
  if not changed:
    return CbssInvalidArgument
  CbssOk

proc cbssRenderSurfaceCanvasClear(
    context: CbssContextHandle;
    surfaceValue: uint64
): int32 {.exportc: "cbss_render_surface_canvas_clear", cdecl, dynlib.} =
  let checked = context.checkedSurfaceCanvas(surfaceValue)
  if checked.status != CbssOk:
    return checked.status
  guardedCanvasMutation(context):
    checked.binding.canvas.clear()

proc cbssRenderSurfaceCanvasSave(
    context: CbssContextHandle;
    surfaceValue: uint64
): int32 {.exportc: "cbss_render_surface_canvas_save", cdecl, dynlib.} =
  let checked = context.checkedSurfaceCanvas(surfaceValue)
  if checked.status != CbssOk:
    return checked.status
  guardedCanvasMutation(context):
    checked.binding.canvas.save()

proc cbssRenderSurfaceCanvasRestore(
    context: CbssContextHandle;
    surfaceValue: uint64
): int32 {.exportc: "cbss_render_surface_canvas_restore", cdecl, dynlib.} =
  let checked = context.checkedSurfaceCanvas(surfaceValue)
  if checked.status != CbssOk:
    return checked.status
  guardedCanvasMutation(context):
    checked.binding.canvas.restore()

proc cbssRenderSurfaceCanvasTransform(
    context: CbssContextHandle;
    surfaceValue: uint64;
    transform: CbssAffineTransformC
): int32 {.exportc: "cbss_render_surface_canvas_transform", cdecl, dynlib.} =
  let checked = context.checkedSurfaceCanvas(surfaceValue)
  if checked.status != CbssOk:
    return checked.status
  let values = [
    transform.m11, transform.m12, transform.m21,
    transform.m22, transform.tx, transform.ty
  ]
  for value in values:
    if not value.finite:
      return CbssInvalidArgument
  guardedCanvasMutation(context):
    checked.binding.canvas.transform(transform.toAffine)

proc cbssRenderSurfaceCanvasPushClip(
    context: CbssContextHandle;
    surfaceValue: uint64;
    bounds: CbssRectC;
    radius: cfloat
): int32 {.exportc: "cbss_render_surface_canvas_push_clip", cdecl, dynlib.} =
  let checked = context.checkedSurfaceCanvas(surfaceValue)
  if checked.status != CbssOk:
    return checked.status
  if not bounds.validRect or not radius.finite or radius < 0:
    return CbssInvalidArgument
  guardedCanvasMutation(context):
    checked.binding.canvas.pushClip(bounds.toRect, radius)

proc cbssRenderSurfaceCanvasPopClip(
    context: CbssContextHandle;
    surfaceValue: uint64
): int32 {.exportc: "cbss_render_surface_canvas_pop_clip", cdecl, dynlib.} =
  let checked = context.checkedSurfaceCanvas(surfaceValue)
  if checked.status != CbssOk:
    return checked.status
  guardedCanvasMutation(context):
    checked.binding.canvas.popClip()

proc cbssRenderSurfaceCanvasBeginLayer(
    context: CbssContextHandle;
    surfaceValue: uint64;
    bounds: CbssRectC;
    opacity: cfloat;
    compositeMode: uint32
): int32 {.exportc: "cbss_render_surface_canvas_begin_layer", cdecl, dynlib.} =
  let checked = context.checkedSurfaceCanvas(surfaceValue)
  if checked.status != CbssOk:
    return checked.status
  let mode = compositeMode.layerCompositeModeFromC
  if not bounds.validRect or not opacity.finite or opacity < 0 or opacity > 1 or
      mode.isNone:
    return CbssInvalidArgument
  guardedCanvasMutation(context):
    checked.binding.canvas.beginLayer(bounds.toRect, opacity, mode.get)

proc cbssRenderSurfaceCanvasEndLayer(
    context: CbssContextHandle;
    surfaceValue: uint64
): int32 {.exportc: "cbss_render_surface_canvas_end_layer", cdecl, dynlib.} =
  let checked = context.checkedSurfaceCanvas(surfaceValue)
  if checked.status != CbssOk:
    return checked.status
  guardedCanvasMutation(context):
    checked.binding.canvas.endLayer()

proc cbssRenderSurfaceCanvasFillRect(
    context: CbssContextHandle;
    surfaceValue: uint64;
    bounds: CbssRectC;
    color: CbssColorC;
    radius: cfloat
): int32 {.exportc: "cbss_render_surface_canvas_fill_rect", cdecl, dynlib.} =
  let checked = context.checkedSurfaceCanvas(surfaceValue)
  if checked.status != CbssOk:
    return checked.status
  if not bounds.validRect or not color.validColor or
      not radius.finite or radius < 0:
    return CbssInvalidArgument
  guardedCanvasMutation(context):
    checked.binding.canvas.fillRect(bounds.toRect, color.toColor, radius)

proc cbssRenderSurfaceCanvasFillLinearGradient(
    context: CbssContextHandle;
    surfaceValue: uint64;
    bounds: CbssRectC;
    angle: cfloat;
    interpolationSpace: uint32;
    stops: ptr CbssGradientStopC;
    stopCount: uint32;
    radius: cfloat
): int32 {.
    exportc: "cbss_render_surface_canvas_fill_linear_gradient", cdecl, dynlib.} =
  let checked = context.checkedSurfaceCanvas(surfaceValue)
  if checked.status != CbssOk:
    return checked.status
  let gradientSpace = interpolationSpace.interpolationSpaceFromC
  if not bounds.validRect or not angle.finite or not radius.finite or radius < 0 or
      gradientSpace.isNone or stops.isNil or stopCount == 0 or stopCount > 4_096:
    return CbssInvalidArgument
  guardedCanvasMutation(context):
    let values = cast[ptr UncheckedArray[CbssGradientStopC]](stops)
    var gradientStops = newSeqOfCap[color.GradientStop](int(stopCount))
    for index in 0 ..< int(stopCount):
      let stop = values[index]
      if not stop.color.validColor or not stop.offset.finite:
        return CbssInvalidArgument
      gradientStops.add colorStop(stop.color.toColor, stop.offset)
    checked.binding.canvas.fillLinearGradient(
      bounds.toRect,
      computed_style_types.LinearGradient(
        angle: angle,
        interpolationSpace: gradientSpace.get,
        stops: gradientStops
      ),
      radius
    )

proc cbssRenderSurfaceCanvasStrokeRect(
    context: CbssContextHandle;
    surfaceValue: uint64;
    bounds: CbssRectC;
    color: CbssColorC;
    width, radius: cfloat
): int32 {.exportc: "cbss_render_surface_canvas_stroke_rect", cdecl, dynlib.} =
  let checked = context.checkedSurfaceCanvas(surfaceValue)
  if checked.status != CbssOk:
    return checked.status
  if not bounds.validRect or not color.validColor or not width.finite or
      not radius.finite or width <= 0 or radius < 0:
    return CbssInvalidArgument
  guardedCanvasMutation(context):
    checked.binding.canvas.strokeRect(
      bounds.toRect, color.toColor, width, radius
    )

proc pathFromC(
    segments: ptr CbssPathSegmentC;
    segmentCount: uint32
): Option[Path2D] =
  if segments.isNil or segmentCount == 0 or segmentCount > 1_048_576:
    return none(Path2D)
  let values = cast[ptr UncheckedArray[CbssPathSegmentC]](segments)
  var path = initPath2D()
  for index in 0 ..< int(segmentCount):
    let segment = values[index]
    let endpoint = vec2(segment.endpointX, segment.endpointY)
    let control1 = vec2(segment.control1X, segment.control1Y)
    let control2 = vec2(segment.control2X, segment.control2Y)
    case segment.kind
    of 0:
      if not segment.endpointX.finite or not segment.endpointY.finite:
        return none(Path2D)
      path.moveTo(endpoint)
    of 1:
      if not segment.endpointX.finite or not segment.endpointY.finite:
        return none(Path2D)
      path.lineTo(endpoint)
    of 2:
      if not segment.control1X.finite or not segment.control1Y.finite or
          not segment.endpointX.finite or not segment.endpointY.finite:
        return none(Path2D)
      path.quadraticCurveTo(control1, endpoint)
    of 3:
      if not segment.control1X.finite or not segment.control1Y.finite or
          not segment.control2X.finite or not segment.control2Y.finite or
          not segment.endpointX.finite or not segment.endpointY.finite:
        return none(Path2D)
      path.bezierCurveTo(control1, control2, endpoint)
    of 4:
      path.closePath()
    else:
      return none(Path2D)
  some(path)

proc cbssRenderSurfaceCanvasStrokePath(
    context: CbssContextHandle;
    surfaceValue: uint64;
    segments: ptr CbssPathSegmentC;
    segmentCount: uint32;
    color: CbssColorC;
    width: cfloat;
    lineCap, lineJoin: uint32;
    miterLimit: cfloat
): int32 {.exportc: "cbss_render_surface_canvas_stroke_path", cdecl, dynlib.} =
  let checked = context.checkedSurfaceCanvas(surfaceValue)
  if checked.status != CbssOk:
    return checked.status
  if not color.validColor or not width.finite or width <= 0 or
      not miterLimit.finite or miterLimit < 1:
    return CbssInvalidArgument
  let cap = lineCap.strokeLineCapFromC
  let join = lineJoin.strokeLineJoinFromC
  if cap.isNone or join.isNone:
    return CbssInvalidArgument
  guardedCanvasMutation(context):
    let path = pathFromC(segments, segmentCount)
    if path.isNone:
      return CbssInvalidArgument
    checked.binding.canvas.strokePath(
      path.get, color.toColor, width, cap.get, join.get, miterLimit
    )

proc textStyleFromC(
    value: ptr CbssTextStyleC;
    fontFamily: cstring
): tuple[valid: bool, style: computed_style_types.ComputedTextStyle] =
  result.valid = true
  if not value.isNil:
    if (value.flags and not CbssTextFlagsMask) != 0:
      return (false, computed_style_types.ComputedTextStyle())
    if (value.flags and CbssTextHasFontSize) != 0:
      if not value.fontSize.finite or value.fontSize <= 0:
        return (false, computed_style_types.ComputedTextStyle())
      result.style.fontSize = some(value.fontSize)
    if (value.flags and CbssTextHasLineHeight) != 0:
      if not value.lineHeight.finite or value.lineHeight <= 0:
        return (false, computed_style_types.ComputedTextStyle())
      result.style.lineHeight = some(value.lineHeight)
    if (value.flags and CbssTextHasFontWeight) != 0:
      if not value.fontWeight.finite or value.fontWeight <= 0:
        return (false, computed_style_types.ComputedTextStyle())
      result.style.fontWeight = some(value.fontWeight)
    if (value.flags and CbssTextHasLetterSpacing) != 0:
      if not value.letterSpacing.finite:
        return (false, computed_style_types.ComputedTextStyle())
      result.style.letterSpacing = some(value.letterSpacing)
    if (value.flags and CbssTextHasFontStyle) != 0:
      if value.fontStyle > uint32(ord(high(computed_style_types.FontStyle))):
        return (false, computed_style_types.ComputedTextStyle())
      result.style.fontStyle = some(computed_style_types.FontStyle(value.fontStyle))
  let family = fromCString(fontFamily).strip()
  if family.len > 0:
    result.style.fontFamily = some(family)
    result.style.fontFamilies = @[family]

proc cbssRenderSurfaceCanvasDrawText(
    context: CbssContextHandle;
    surfaceValue: uint64;
    text: cstring;
    x, y: cfloat;
    color: CbssColorC;
    style: ptr CbssTextStyleC;
    fontFamily: cstring;
    maxWidth: cfloat;
    hasMaxWidth: uint8
): int32 {.exportc: "cbss_render_surface_canvas_draw_text", cdecl, dynlib.} =
  let checked = context.checkedSurfaceCanvas(surfaceValue)
  if checked.status != CbssOk:
    return checked.status
  if text.isNil or not x.finite or not y.finite or not color.validColor or
      (hasMaxWidth != 0 and
      (not maxWidth.finite or maxWidth <= 0)):
    return CbssInvalidArgument
  guardedCanvasMutation(context):
    let convertedStyle = textStyleFromC(style, fontFamily)
    if not convertedStyle.valid:
      return CbssInvalidArgument
    checked.binding.canvas.drawText(
      fromCString(text), vec2(x, y), color.toColor, convertedStyle.style,
      if hasMaxWidth != 0: some(maxWidth.float32) else: none(float32)
    )

proc cbssRenderSurfaceCanvasDrawImage(
    context: CbssContextHandle;
    surfaceValue: uint64;
    source: cstring;
    bounds: CbssRectC;
    opacity: cfloat
): int32 {.exportc: "cbss_render_surface_canvas_draw_image", cdecl, dynlib.} =
  let checked = context.checkedSurfaceCanvas(surfaceValue)
  if checked.status != CbssOk:
    return checked.status
  if source.isNil or not bounds.validRect or not opacity.finite or
      opacity < 0 or opacity > 1:
    return CbssInvalidArgument
  guardedCanvasMutation(context):
    let sourceValue = fromCString(source)
    if sourceValue.len == 0:
      return CbssInvalidArgument
    checked.binding.canvas.drawImage(sourceValue, bounds.toRect, opacity)

proc cbssRenderSurfaceCanvasCommit(
    context: CbssContextHandle;
    surfaceValue: uint64;
    outputRevision: ptr uint64
): int32 {.exportc: "cbss_render_surface_canvas_commit", cdecl, dynlib.} =
  let checked = context.checkedSurfaceCanvas(surfaceValue)
  if checked.status != CbssOk:
    return checked.status
  guardedCanvasMutation(context):
    let binding = checked.binding
    if binding.canvas.revision != binding.committedCanvasRevision:
      let snapshot = binding.canvas.copyCanvasCommands()
      binding.committedCanvas.commands = snapshot
      binding.committedCanvas.revision = binding.canvas.revision
      binding.committedCanvasRevision = binding.canvas.revision
      if binding.publishedRevision == high(uint64):
        binding.publishedRevision = 1
      else:
        inc binding.publishedRevision
      discard context.surfaces.updateSurface(
        binding.surface, binding.publishedRevision
      )
      if context.computed:
        context.refreshPresentation()
    if not outputRevision.isNil:
      outputRevision[] = binding.publishedRevision

proc cbssContextSetPixelScale(
    context: CbssContextHandle;
    pixelScale: cfloat
): int32 {.exportc: "cbss_context_set_pixel_scale", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if pixelScale.classify in {fcNan, fcInf, fcNegInf} or pixelScale <= 0:
    return CbssInvalidArgument
  if context.pixelScale == pixelScale:
    return CbssOk
  context.pixelScale = pixelScale
  if context.computed:
    context.refreshPresentation()
  CbssOk

proc cbssNodeSetText(
    context: CbssContextHandle;
    node: uint32;
    text: cstring
): int32 {.exportc: "cbss_node_set_text", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node) or text.isNil:
    return CbssInvalidArgument
  if context.tree.nodes[node.nodeId.nodeIndex].kind != nkText:
    context.setError("node is not a text node")
    return CbssInvalidArgument
  context.tree.nodes[node.nodeId.nodeIndex].text = fromCString(text)
  context.invalidate()
  CbssOk

proc cbssNodeSetImage(
    context: CbssContextHandle;
    node: uint32;
    source: cstring;
    width, height: cfloat
): int32 {.exportc: "cbss_node_set_image", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node) or source.isNil or width < 0 or height < 0:
    return CbssInvalidArgument
  let index = node.nodeId.nodeIndex
  if context.tree.nodes[index].kind != nkImage:
    context.setError("node is not an image node")
    return CbssInvalidArgument
  context.tree.nodes[index].imageSource = fromCString(source)
  context.tree.nodes[index].imageWidth = width
  context.tree.nodes[index].imageHeight = height
  context.invalidate()
  CbssOk

proc cbssNodeAddGroup(
    context: CbssContextHandle;
    node: uint32;
    group: cstring
): int32 {.exportc: "cbss_node_add_group", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node) or group.isNil:
    return CbssInvalidArgument
  let value = fromCString(group)
  if value.len == 0:
    return CbssInvalidArgument
  if not context.tree.nodes[node.nodeId.nodeIndex].hasGroup(value):
    context.tree.nodes[node.nodeId.nodeIndex].groups.add value
    context.invalidate()
  CbssOk

proc cbssNodeSetAttribute(
    context: CbssContextHandle;
    node: uint32;
    name, value: cstring
): int32 {.exportc: "cbss_node_set_attribute", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node) or name.isNil or value.isNil:
    return CbssInvalidArgument
  context.tree.setAttribute(node.nodeId, fromCString(name), fromCString(value))
  context.invalidate()
  CbssOk

proc cbssNodeSetState(
    context: CbssContextHandle;
    node, state: uint32;
    enabled: uint8
): int32 {.exportc: "cbss_node_set_state", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node) or state > uint32(ord(high(ElementState))):
    return CbssInvalidArgument
  context.tree.setState(node.nodeId, ElementState(state), enabled != 0)
  context.invalidate()
  CbssOk

proc cbssNodeSetAccessibility(
    context: CbssContextHandle;
    node, role: uint32;
    name, description: cstring
): int32 {.exportc: "cbss_node_set_accessibility", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node) or role > uint32(ord(high(AccessibleRole))):
    return CbssInvalidArgument
  context.tree.setAccessibleRole(node.nodeId, AccessibleRole(role))
  context.tree.setAccessibleName(node.nodeId, fromCString(name))
  context.tree.setAccessibleDescription(node.nodeId, fromCString(description))
  CbssOk

proc cbssNodeSetAccessibleValue(
    context: CbssContextHandle;
    node: uint32;
    value: cstring
): int32 {.exportc: "cbss_node_set_accessible_value", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node) or value.isNil:
    return CbssInvalidArgument
  context.tree.setAccessibleValue(node.nodeId, fromCString(value))
  CbssOk

proc cbssNodeSetAccessibleRange(
    context: CbssContextHandle;
    node, flags: uint32;
    valueNow, valueMin, valueMax: cfloat
): int32 {.exportc: "cbss_node_set_accessible_range", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node):
    return CbssInvalidArgument
  context.tree.setAccessibleRange(
    node.nodeId,
    if (flags and CbssAccessibleHasValueNow) != 0:
      some(float32(valueNow))
    else:
      none(float32),
    if (flags and CbssAccessibleHasValueMin) != 0:
      some(float32(valueMin))
    else:
      none(float32),
    if (flags and CbssAccessibleHasValueMax) != 0:
      some(float32(valueMax))
    else:
      none(float32)
  )
  CbssOk

proc cbssNodeSetAccessibleRelations(
    context: CbssContextHandle;
    node, labelledBy, describedBy: uint32
): int32 {.exportc: "cbss_node_set_accessible_relations", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node) or
      (labelledBy != CbssNodeNone and not context.validNode(labelledBy)) or
      (describedBy != CbssNodeNone and not context.validNode(describedBy)):
    return CbssInvalidArgument
  context.tree.setAccessibleLabelledBy(
    node.nodeId,
    if labelledBy == CbssNodeNone: none(NodeId)
    else: some(labelledBy.nodeId)
  )
  context.tree.setAccessibleDescribedBy(
    node.nodeId,
    if describedBy == CbssNodeNone: none(NodeId)
    else: some(describedBy.nodeId)
  )
  CbssOk

proc cbssNodeSetAccessibleHidden(
    context: CbssContextHandle;
    node: uint32;
    hidden: uint8
): int32 {.exportc: "cbss_node_set_accessible_hidden", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node):
    return CbssInvalidArgument
  context.tree.setAccessibleHidden(node.nodeId, hidden != 0)
  CbssOk

proc cbssNodeAccessibility(
    context: CbssContextHandle;
    node: uint32;
    output: ptr CbssAccessibilityC
): int32 {.exportc: "cbss_node_accessibility", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node) or output.isNil:
    return CbssInvalidArgument
  let semantic = context.tree.semanticInfo(node.nodeId)
  var flags = 0'u32
  if semantic.valueNow.isSome:
    flags = flags or CbssAccessibleHasValueNow
  if semantic.valueMin.isSome:
    flags = flags or CbssAccessibleHasValueMin
  if semantic.valueMax.isSome:
    flags = flags or CbssAccessibleHasValueMax
  output[] = CbssAccessibilityC(
    role: uint32(ord(semantic.role)),
    flags: flags,
    valueNow: if semantic.valueNow.isSome: semantic.valueNow.get else: 0,
    valueMin: if semantic.valueMin.isSome: semantic.valueMin.get else: 0,
    valueMax: if semantic.valueMax.isSome: semantic.valueMax.get else: 0,
    labelledBy:
      if semantic.labelledBy.isSome:
        semantic.labelledBy.get.nodeRawValue()
      else:
        CbssNodeNone,
    describedBy:
      if semantic.describedBy.isSome:
        semantic.describedBy.get.nodeRawValue()
      else:
        CbssNodeNone,
    hidden: uint8(ord(context.tree.isAccessibleHidden(node.nodeId)))
  )
  CbssOk

proc cbssNodeAccessibleName(
    context: CbssContextHandle;
    node: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_node_accessible_name", cdecl, dynlib.} =
  if context.isNil or not context.validNode(node):
    return 0
  copyString(
    context.tree.semanticInfo(node.nodeId).name, buffer, capacity
  )

proc cbssNodeAccessibleDescription(
    context: CbssContextHandle;
    node: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_node_accessible_description", cdecl, dynlib.} =
  if context.isNil or not context.validNode(node):
    return 0
  copyString(
    context.tree.semanticInfo(node.nodeId).description, buffer, capacity
  )

proc cbssNodeAccessibleValue(
    context: CbssContextHandle;
    node: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_node_accessible_value", cdecl, dynlib.} =
  if context.isNil or not context.validNode(node):
    return 0
  copyString(
    context.tree.semanticInfo(node.nodeId).value, buffer, capacity
  )

proc cbssNodeSetFocusable(
    context: CbssContextHandle;
    node: uint32;
    focusable: uint8;
    tabIndex: int32
): int32 {.exportc: "cbss_node_set_focusable", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node):
    return CbssInvalidArgument
  context.tree.setFocusable(
    node.nodeId, focusable != 0, int(tabIndex)
  )
  if focusable == 0 and
      context.interaction.focusedTarget == some(node.nodeId):
    discard context.setContextFocus(none(NodeId), focusVisible = false)
    context.invalidate()
  CbssOk

proc cbssNodeSetEventHandler(
    context: CbssContextHandle;
    node, kind: uint32;
    callback: CbssEventCallback;
    userData: pointer
): int32 {.exportc: "cbss_node_set_event_handler", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node) or
      kind > uint32(ord(high(InputEventKind))):
    return CbssInvalidArgument
  let eventKind = InputEventKind(kind)
  if callback.isNil:
    discard context.events.clearEventHandler(node.nodeId, eventKind)
  else:
    context.events.setEventHandler(
      node.nodeId,
      eventKind,
      cEventHandler(context, callback, userData)
    )
  CbssOk

proc cbssNodeSetEventViewHandler(
    context: CbssContextHandle;
    node, kind: uint32;
    callback: CbssEventViewCallback;
    userData: pointer
): int32 {.exportc: "cbss_node_set_event_view_handler", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node) or
      kind > uint32(ord(high(InputEventKind))):
    return CbssInvalidArgument
  let eventKind = InputEventKind(kind)
  if callback.isNil:
    discard context.events.clearEventHandler(node.nodeId, eventKind)
  else:
    context.events.setEventHandler(
      node.nodeId,
      eventKind,
      cEventViewHandler(context, callback, userData)
    )
  CbssOk

proc cbssNodeSubscribeEvent(
    context: CbssContextHandle;
    node, kind: uint32;
    callback: CbssEventCallback;
    userData: pointer;
    outputSubscription: ptr uint64
): int32 {.exportc: "cbss_node_subscribe_event", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if outputSubscription.isNil or callback.isNil or
      not context.validNode(node) or
      kind > uint32(ord(high(InputEventKind))):
    return CbssInvalidArgument
  outputSubscription[] = 0
  let subscription = context.events.subscribe(
    node.nodeId,
    InputEventKind(kind),
    cEventHandler(context, callback, userData)
  )
  context.eventSubscriptions[subscription.id] = subscription
  outputSubscription[] = subscription.id
  CbssOk

proc cbssNodeSubscribeEventView(
    context: CbssContextHandle;
    node, kind: uint32;
    callback: CbssEventViewCallback;
    userData: pointer;
    outputSubscription: ptr uint64
): int32 {.exportc: "cbss_node_subscribe_event_view", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if outputSubscription.isNil or callback.isNil or
      not context.validNode(node) or
      kind > uint32(ord(high(InputEventKind))):
    return CbssInvalidArgument
  outputSubscription[] = 0
  let subscription = context.events.subscribe(
    node.nodeId,
    InputEventKind(kind),
    cEventViewHandler(context, callback, userData)
  )
  context.eventSubscriptions[subscription.id] = subscription
  outputSubscription[] = subscription.id
  CbssOk

proc cbssContextUnsubscribeEvent(
    context: CbssContextHandle;
    subscriptionId: uint64
): int32 {.exportc: "cbss_context_unsubscribe_event", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if subscriptionId == 0 or subscriptionId notin context.eventSubscriptions:
    return CbssInvalidArgument
  let subscription = context.eventSubscriptions[subscriptionId]
  if not context.events.removeEventHandler(subscription):
    context.eventSubscriptions.del(subscriptionId)
    return CbssInvalidArgument
  context.eventSubscriptions.del(subscriptionId)
  CbssOk

proc cbssStyleCreate(): CbssStyleHandle {.
    exportc: "cbss_style_create", cdecl, dynlib.} =
  ensureNimRuntime()
  try:
    result = create(CbssStyleObj)
    result[] = CbssStyleObj(declarations: @[])
  except CatchableError:
    result = nil

proc cbssStyleDestroy(style: CbssStyleHandle) {.
    exportc: "cbss_style_destroy", cdecl, dynlib.} =
  if style.isNil:
    return
  `=destroy`(style[])
  dealloc(style)

proc cbssStyleClear(style: CbssStyleHandle): int32 {.
    exportc: "cbss_style_clear", cdecl, dynlib.} =
  if style.isNil:
    return CbssInvalidHandle
  style.declarations.setLen(0)
  CbssOk

proc cbssKeyframesCreate(
    name: cstring;
    output: ptr CbssKeyframesHandle
): int32 {.exportc: "cbss_keyframes_create", cdecl, dynlib.} =
  if output.isNil or name.isNil:
    return CbssInvalidArgument
  output[] = nil
  let normalized = fromCString(name).strip()
  if normalized.len == 0 or normalized == "none" or ',' in normalized:
    return CbssInvalidArgument
  ensureNimRuntime()
  var handle: CbssKeyframesHandle = nil
  try:
    handle = create(CbssKeyframesObj)
    handle[] = CbssKeyframesObj(name: normalized, steps: @[])
    output[] = handle
    CbssOk
  except CatchableError:
    if not handle.isNil:
      `=destroy`(handle[])
      dealloc(handle)
    CbssInternalError

proc cbssKeyframesDestroy(keyframes: CbssKeyframesHandle) {.
    exportc: "cbss_keyframes_destroy", cdecl, dynlib.} =
  if keyframes.isNil:
    return
  `=destroy`(keyframes[])
  dealloc(keyframes)

proc cbssKeyframesClear(keyframes: CbssKeyframesHandle): int32 {.
    exportc: "cbss_keyframes_clear", cdecl, dynlib.} =
  if keyframes.isNil:
    return CbssInvalidHandle
  keyframes.steps.setLen(0)
  CbssOk

proc cbssKeyframesAddStep(
    keyframes: CbssKeyframesHandle;
    offset: cdouble;
    style: CbssStyleHandle
): int32 {.exportc: "cbss_keyframes_add_step", cdecl, dynlib.} =
  if keyframes.isNil or style.isNil:
    return CbssInvalidHandle
  if keyframes.steps.len >= int(CbssMaxKeyframeSteps):
    return CbssOutOfRange
  if offset.classify in {fcNan, fcInf, fcNegInf} or offset < 0 or offset > 1:
    return CbssInvalidArgument
  if keyframes.steps.len > 0 and offset < keyframes.steps[^1].offset:
    return CbssInvalidArgument
  try:
    keyframes.steps.add styleKeyframe(
      offset, copyDeclarations(style.declarations)
    )
    CbssOk
  except ValueError:
    CbssStyleError
  except CatchableError:
    CbssInternalError

proc cbssContextRegisterKeyframes(
    context: CbssContextHandle;
    keyframes: CbssKeyframesHandle
): int32 {.exportc: "cbss_context_register_keyframes", cdecl, dynlib.} =
  if context.isNil or keyframes.isNil:
    return CbssInvalidHandle
  try:
    context.keyframes.registerStyleKeyframes(styleKeyframes(
      keyframes.name, keyframes.steps
    ))
    context.invalidate()
    CbssOk
  except ValueError as error:
    context.setError(error.msg)
    CbssInvalidArgument
  except CatchableError as error:
    context.setError(error.msg)
    CbssInternalError

proc cbssContextUnregisterKeyframes(
    context: CbssContextHandle;
    name: cstring
): int32 {.exportc: "cbss_context_unregister_keyframes", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if name.isNil:
    return CbssInvalidArgument
  try:
    if not context.keyframes.unregisterStyleKeyframes(fromCString(name)):
      return CbssOutOfRange
    context.dispatchPendingMotionLifecycle()
    context.invalidate()
    CbssOk
  except CatchableError as error:
    context.setError(error.msg)
    CbssInternalError

proc cbssContextHasKeyframes(
    context: CbssContextHandle;
    name: cstring
): uint8 {.exportc: "cbss_context_has_keyframes", cdecl, dynlib.} =
  if context.isNil or name.isNil:
    return 0
  try:
    uint8(ord(context.keyframes.hasStyleKeyframes(fromCString(name))))
  except CatchableError as error:
    context.setError(error.msg)
    0

proc cbssColorValueCreate(
    space: uint32;
    first, second, third, alpha: cfloat;
    missingMask: uint32;
    output: ptr CbssColorValueHandle
): int32 {.exportc: "cbss_color_value_create", cdecl, dynlib.} =
  if output.isNil:
    return CbssInvalidArgument
  output[] = nil
  let authoredSpace = space.colorSpaceFromC
  if authoredSpace.isNone or (missingMask and not CbssColorMissingMask) != 0:
    return CbssInvalidArgument
  ensureNimRuntime()
  try:
    let value = colorIn(
      authoredSpace.get,
      first,
      second,
      third,
      alpha.float64,
      missingMask.toMissingComponents
    )
    let handle = create(CbssColorValueObj)
    handle[] = CbssColorValueObj(kind: ccvValue, value: value)
    output[] = handle
    CbssOk
  except CatchableError:
    CbssInvalidArgument

proc cbssColorValueCurrent(
    output: ptr CbssColorValueHandle
): int32 {.exportc: "cbss_color_value_current", cdecl, dynlib.} =
  if output.isNil:
    return CbssInvalidArgument
  output[] = nil
  ensureNimRuntime()
  try:
    let handle = create(CbssColorValueObj)
    handle[] = CbssColorValueObj(kind: ccvValue, value: currentColor())
    output[] = handle
    CbssOk
  except CatchableError:
    CbssInternalError

proc cbssColorValueParse(
    input: cstring;
    output: ptr CbssColorValueHandle;
    errorBuffer: cstring;
    errorCapacity: uint32
): int32 {.exportc: "cbss_color_value_parse", cdecl, dynlib.} =
  if output.isNil or input.isNil:
    return CbssInvalidArgument
  output[] = nil
  ensureNimRuntime()
  try:
    let parsed = parseColor(fromCString(input))
    if not parsed.isOk:
      if parsed.error.isSome:
        discard copyString(parsed.error.get.message, errorBuffer, errorCapacity)
      return CbssInvalidArgument
    let handle = create(CbssColorValueObj)
    handle[] = CbssColorValueObj(kind: ccvValue, value: parsed.value.get)
    output[] = handle
    CbssOk
  except CatchableError:
    CbssInternalError

proc cbssColorMixParse(
    input: cstring;
    output: ptr CbssColorValueHandle;
    errorBuffer: cstring;
    errorCapacity: uint32
): int32 {.exportc: "cbss_color_mix_parse", cdecl, dynlib.} =
  if output.isNil or input.isNil:
    return CbssInvalidArgument
  output[] = nil
  ensureNimRuntime()
  try:
    let parsed = parseColorMix(fromCString(input))
    if not parsed.isOk:
      if parsed.error.isSome:
        discard copyString(parsed.error.get.message, errorBuffer, errorCapacity)
      return CbssInvalidArgument
    let handle = create(CbssColorValueObj)
    handle[] = CbssColorValueObj(kind: ccvMix, mix: parsed.value.get)
    output[] = handle
    CbssOk
  except CatchableError:
    CbssInternalError

proc cbssColorMixCreate(
    first, second: CbssColorValueHandle;
    interpolationSpace, flags: uint32;
    firstPercentage, secondPercentage: cfloat;
    output: ptr CbssColorValueHandle
): int32 {.exportc: "cbss_color_mix_create", cdecl, dynlib.} =
  if output.isNil:
    return CbssInvalidArgument
  output[] = nil
  let mixingSpace = interpolationSpace.interpolationSpaceFromC
  if first.isNil or second.isNil or first.kind != ccvValue or
      second.kind != ccvValue or mixingSpace.isNone or
      (flags and not CbssColorMixFlagsMask) != 0:
    return CbssInvalidArgument
  ensureNimRuntime()
  try:
    let firstWeight =
      if (flags and CbssColorMixHasFirstPercentage) != 0:
        some(firstPercentage.float64)
      else:
        none(float64)
    let secondWeight =
      if (flags and CbssColorMixHasSecondPercentage) != 0:
        some(secondPercentage.float64)
      else:
        none(float64)
    let mix = normalizedColorMix(
      first.colorValueOf,
      second.colorValueOf,
      firstWeight,
      secondWeight,
      mixingSpace.get
    )
    let handle = create(CbssColorValueObj)
    handle[] = CbssColorValueObj(kind: ccvMix, mix: mix)
    output[] = handle
    CbssOk
  except CatchableError:
    CbssInvalidArgument

proc cbssColorValueResolve(
    value: CbssColorValueHandle;
    current: CbssColorC;
    output: ptr CbssColorC
): int32 {.exportc: "cbss_color_value_resolve", cdecl, dynlib.} =
  if value.isNil or output.isNil:
    return CbssInvalidArgument
  try:
    output[] = value.resolveColor(
      rgba(current.r, current.g, current.b, current.a)
    ).toColor
    CbssOk
  except CatchableError:
    CbssInternalError

proc cbssColorValueDestroy(value: CbssColorValueHandle) {.
    exportc: "cbss_color_value_destroy", cdecl, dynlib.} =
  if value.isNil:
    return
  `=destroy`(value[])
  dealloc(value)

proc cbssStyleSetLength(
    style: CbssStyleHandle;
    property: cstring;
    unit: uint32;
    value: cfloat
): int32 {.exportc: "cbss_style_set_length", cdecl, dynlib.} =
  let input = checkedStyleInput(style, property)
  if input.status != CbssOk:
    return input.status
  if unit > uint32(ord(high(UnitKind))):
    return CbssInvalidArgument
  style.putDeclaration(
    input.name,
    StyleValue(
      kind: svLength,
      length: LengthValue(kind: UnitKind(unit), value: value)
    )
  )
  CbssOk

proc cbssStyleSetNumber(
    style: CbssStyleHandle;
    property: cstring;
    value: cfloat
): int32 {.exportc: "cbss_style_set_number", cdecl, dynlib.} =
  let input = checkedStyleInput(style, property)
  if input.status != CbssOk:
    return input.status
  style.putDeclaration(input.name, number(value))
  CbssOk

proc cbssStyleSetKeyword(
    style: CbssStyleHandle;
    property, value: cstring
): int32 {.exportc: "cbss_style_set_keyword", cdecl, dynlib.} =
  let input = checkedStyleInput(style, property)
  if input.status != CbssOk or value.isNil:
    return if input.status != CbssOk: input.status else: CbssInvalidArgument
  style.putDeclaration(input.name, keyword(fromCString(value)))
  CbssOk

proc cbssStyleSetColor(
    style: CbssStyleHandle;
    property: cstring;
    color: CbssColorC
): int32 {.exportc: "cbss_style_set_color", cdecl, dynlib.} =
  let input = checkedStyleInput(style, property)
  if input.status != CbssOk:
    return input.status
  style.putDeclaration(
    input.name, colorValue(rgba(color.r, color.g, color.b, color.a))
  )
  CbssOk

proc cbssStyleSetColorValue(
    style: CbssStyleHandle;
    property: cstring;
    value: CbssColorValueHandle
): int32 {.exportc: "cbss_style_set_color_value", cdecl, dynlib.} =
  let input = checkedStyleInput(style, property)
  if input.status != CbssOk or value.isNil:
    return if input.status != CbssOk: input.status else: CbssInvalidArgument
  case value.kind
  of ccvValue:
    style.putDeclaration(input.name, colorValue(value.value))
  of ccvMix:
    style.putDeclaration(input.name, colorValue(value.mix))
  CbssOk

proc cbssStyleSetColorPair(
    style: CbssStyleHandle;
    property: cstring;
    first, second: CbssColorC
): int32 {.exportc: "cbss_style_set_color_pair", cdecl, dynlib.} =
  let input = checkedStyleInput(style, property)
  if input.status != CbssOk:
    return input.status
  style.putDeclaration(
    input.name,
    colorPairValue(
      rgba(first.r, first.g, first.b, first.a),
      rgba(second.r, second.g, second.b, second.a)
    )
  )
  CbssOk

proc cbssStyleSetBorder(
    style: CbssStyleHandle;
    property: cstring;
    flags, widthUnit: uint32;
    width: cfloat;
    lineStyle: cstring;
    color: CbssColorC
): int32 {.exportc: "cbss_style_set_border", cdecl, dynlib.} =
  let input = checkedStyleInput(style, property)
  if input.status != CbssOk:
    return input.status
  if (flags and CbssBorderHasWidth) != 0 and
      widthUnit > uint32(ord(high(UnitKind))):
    return CbssInvalidArgument
  if (flags and CbssBorderHasStyle) != 0 and lineStyle.isNil:
    return CbssInvalidArgument
  var value = StyleValue(kind: svBorder)
  if (flags and CbssBorderHasWidth) != 0:
    value.borderWidth = some(LengthValue(
      kind: UnitKind(widthUnit), value: width
    ))
  if (flags and CbssBorderHasStyle) != 0:
    value.borderStyle = some(fromCString(lineStyle))
  if (flags and CbssBorderHasColor) != 0:
    value.borderColor = some(rgba(color.r, color.g, color.b, color.a))
  style.putDeclaration(input.name, value)
  CbssOk

proc cbssStyleSetShadow(
    style: CbssStyleHandle;
    property: cstring;
    offsetXUnit: uint32;
    offsetX: cfloat;
    offsetYUnit: uint32;
    offsetY: cfloat;
    flags, blurUnit: uint32;
    blur: cfloat;
    spreadUnit: uint32;
    spread: cfloat;
    color: CbssColorC
): int32 {.exportc: "cbss_style_set_shadow", cdecl, dynlib.} =
  let input = checkedStyleInput(style, property)
  if input.status != CbssOk:
    return input.status
  if offsetXUnit > uint32(ord(high(UnitKind))) or
      offsetYUnit > uint32(ord(high(UnitKind))) or
      ((flags and CbssShadowHasBlur) != 0 and
        blurUnit > uint32(ord(high(UnitKind)))) or
      ((flags and CbssShadowHasSpread) != 0 and
        spreadUnit > uint32(ord(high(UnitKind)))):
    return CbssInvalidArgument
  var value = StyleValue(
    kind: svShadow,
    shadowOffsetX: LengthValue(
      kind: UnitKind(offsetXUnit), value: offsetX
    ),
    shadowOffsetY: LengthValue(
      kind: UnitKind(offsetYUnit), value: offsetY
    )
  )
  if (flags and CbssShadowHasBlur) != 0:
    value.shadowBlur = some(LengthValue(
      kind: UnitKind(blurUnit), value: blur
    ))
  if (flags and CbssShadowHasSpread) != 0:
    value.shadowSpread = some(LengthValue(
      kind: UnitKind(spreadUnit), value: spread
    ))
  if (flags and CbssShadowHasColor) != 0:
    value.shadowColor = some(rgba(color.r, color.g, color.b, color.a))
  style.putDeclaration(input.name, value)
  CbssOk

proc setLinearGradient(
    style: CbssStyleHandle;
    property: cstring;
    angle: cfloat;
    stops: ptr CbssGradientStopC;
    stopCount, interpolationSpace: uint32
): int32 =
  let input = checkedStyleInput(style, property)
  if input.status != CbssOk:
    return input.status
  let gradientSpace = interpolationSpace.interpolationSpaceFromC
  if stops.isNil or stopCount == 0 or stopCount > 4_096 or
      gradientSpace.isNone:
    return CbssInvalidArgument
  let values = cast[ptr UncheckedArray[CbssGradientStopC]](stops)
  var gradientStops = newSeqOfCap[GradientValueStop](int(stopCount))
  for index in 0 ..< int(stopCount):
    let stop = values[index]
    gradientStops.add gradientValueStop(colorStop(
      rgba(stop.color.r, stop.color.g, stop.color.b, stop.color.a),
      stop.offset
    ))
  style.putDeclaration(
    input.name,
    StyleValue(
      kind: svLinearGradient,
      gradientAngle: angle,
      gradientInterpolationSpace: gradientSpace.get,
      gradientStops: gradientStops
    )
  )
  CbssOk

proc cbssStyleSetLinearGradient(
    style: CbssStyleHandle;
    property: cstring;
    angle: cfloat;
    stops: ptr CbssGradientStopC;
    stopCount: uint32
): int32 {.exportc: "cbss_style_set_linear_gradient", cdecl, dynlib.} =
  setLinearGradient(
    style, property, angle, stops, stopCount, cisSrgb.interpolationSpaceToC
  )

proc cbssStyleSetLinearGradientIn(
    style: CbssStyleHandle;
    property: cstring;
    angle: cfloat;
    interpolationSpace: uint32;
    stops: ptr CbssGradientStopC;
    stopCount: uint32
): int32 {.exportc: "cbss_style_set_linear_gradient_in", cdecl, dynlib.} =
  setLinearGradient(
    style, property, angle, stops, stopCount, interpolationSpace
  )

proc cbssStyleSetLinearGradientColorValues(
    style: CbssStyleHandle;
    property: cstring;
    angle: cfloat;
    interpolationSpace: uint32;
    stops: ptr CbssColorValueGradientStopC;
    stopCount: uint32
): int32 {.exportc: "cbss_style_set_linear_gradient_color_values", cdecl,
    dynlib.} =
  let input = checkedStyleInput(style, property)
  if input.status != CbssOk:
    return input.status
  let gradientSpace = interpolationSpace.interpolationSpaceFromC
  if stops.isNil or stopCount == 0 or stopCount > 4_096 or
      gradientSpace.isNone:
    return CbssInvalidArgument

  let values = cast[ptr UncheckedArray[CbssColorValueGradientStopC]](stops)
  var gradientStops = newSeqOfCap[GradientValueStop](int(stopCount))
  for index in 0 ..< int(stopCount):
    let stop = values[index]
    if stop.color.isNil:
      return CbssInvalidArgument
    case stop.color.kind
    of ccvValue:
      gradientStops.add colorStop(stop.color.value, stop.offset)
    of ccvMix:
      gradientStops.add colorStop(stop.color.mix, stop.offset)

  style.putDeclaration(
    input.name,
    StyleValue(
      kind: svLinearGradient,
      gradientAngle: angle,
      gradientInterpolationSpace: gradientSpace.get,
      gradientStops: gradientStops
    )
  )
  CbssOk

proc toTransformOperation(
    value: CbssTransformOperationC;
    output: var TransformOperationValue
): int32 =
  if value.kind > uint32(ord(high(style_value.TransformOperationKind))):
    return CbssInvalidArgument
  output.kind = style_value.TransformOperationKind(value.kind)
  case output.kind
  of tokTranslate:
    if ((value.flags and CbssTransformHasX) != 0 and
          value.xUnit > uint32(ord(high(UnitKind)))) or
        ((value.flags and CbssTransformHasY) != 0 and
          value.yUnit > uint32(ord(high(UnitKind)))) or
        ((value.flags and CbssTransformHasZ) != 0 and
          value.zUnit > uint32(ord(high(UnitKind)))):
      return CbssInvalidArgument
    if (value.flags and CbssTransformHasX) != 0:
      output.xLength = some(LengthValue(
        kind: UnitKind(value.xUnit), value: value.x
      ))
    if (value.flags and CbssTransformHasY) != 0:
      output.yLength = some(LengthValue(
        kind: UnitKind(value.yUnit), value: value.y
      ))
    if (value.flags and CbssTransformHasZ) != 0:
      output.zLength = some(LengthValue(
        kind: UnitKind(value.zUnit), value: value.z
      ))
  of tokScale:
    if (value.flags and CbssTransformHasX) != 0:
      output.xNumber = some(value.x)
    if (value.flags and CbssTransformHasY) != 0:
      output.yNumber = some(value.y)
    if (value.flags and CbssTransformHasZ) != 0:
      output.zNumber = some(value.z)
  of tokRotate:
    output.angle = value.angle
  CbssOk

proc cbssStyleSetTransformOperation(
    style: CbssStyleHandle;
    property: cstring;
    operation: CbssTransformOperationC
): int32 {.exportc: "cbss_style_set_transform_operation", cdecl, dynlib.} =
  let input = checkedStyleInput(style, property)
  if input.status != CbssOk:
    return input.status
  var value: TransformOperationValue
  let status = operation.toTransformOperation(value)
  if status != CbssOk:
    return status
  style.putDeclaration(
    input.name,
    StyleValue(kind: svTransformOperation, transformOperation: value)
  )
  CbssOk

proc cbssStyleSetTransform(
    style: CbssStyleHandle;
    property: cstring;
    operations: ptr CbssTransformOperationC;
    operationCount: uint32
): int32 {.exportc: "cbss_style_set_transform", cdecl, dynlib.} =
  let input = checkedStyleInput(style, property)
  if input.status != CbssOk:
    return input.status
  if operations.isNil or operationCount == 0 or operationCount > 1_024:
    return CbssInvalidArgument
  let values = cast[ptr UncheckedArray[CbssTransformOperationC]](operations)
  var transformed = newSeqOfCap[TransformOperationValue](int(operationCount))
  for index in 0 ..< int(operationCount):
    var operation: TransformOperationValue
    let status = values[index].toTransformOperation(operation)
    if status != CbssOk:
      return status
    transformed.add operation
  style.putDeclaration(
    input.name,
    StyleValue(kind: svTransform, transformOperations: transformed)
  )
  CbssOk

proc cbssNodeApplyStyle(
    context: CbssContextHandle;
    node: uint32;
    style: CbssStyleHandle;
    stateMask: uint32;
    priority: int32
): int32 {.exportc: "cbss_node_apply_style", cdecl, dynlib.} =
  if context.isNil or style.isNil:
    return CbssInvalidHandle
  if not context.validNode(node):
    return CbssInvalidArgument
  for applied in context.appliedStyles.mitems:
    if applied.node == node.nodeId and applied.stateMask == stateMask and
        applied.priority == int(priority):
      applied.declarations = copyDeclarations(style.declarations)
      context.rebuildStyleSheets()
      context.invalidate()
      return CbssOk
  context.appliedStyles.add CbssAppliedStyle(
    node: node.nodeId,
    stateMask: stateMask,
    priority: int(priority),
    sourceOrder: context.appliedStyles.len,
    declarations: copyDeclarations(style.declarations)
  )
  context.rebuildStyleSheets()
  context.invalidate()
  CbssOk

proc cbssNodeClearStyle(
    context: CbssContextHandle;
    node, stateMask: uint32;
    priority: int32
): int32 {.exportc: "cbss_node_clear_style", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node):
    return CbssInvalidArgument
  for index in 0 ..< context.appliedStyles.len:
    let applied = context.appliedStyles[index]
    if applied.node == node.nodeId and applied.stateMask == stateMask and
        applied.priority == int(priority):
      context.appliedStyles.delete(index)
      for sourceOrder in 0 ..< context.appliedStyles.len:
        context.appliedStyles[sourceOrder].sourceOrder = sourceOrder
      context.rebuildStyleSheets()
      context.invalidate()
      return CbssOk
  CbssOutOfRange

proc computeContextAt(
    context: CbssContextHandle;
    width, height: cfloat;
    nowSeconds: cdouble
): int32 =
  if context.isNil:
    return CbssInvalidHandle
  if width.classify in {fcNan, fcInf, fcNegInf} or
      height.classify in {fcNan, fcInf, fcNegInf} or
      nowSeconds.classify in {fcNan, fcInf, fcNegInf} or
      width < 0 or height < 0:
    context.setError("layout constraints and motion time must be finite")
    return CbssInvalidArgument
  if context.motionTimeInitialized and nowSeconds < context.motionNow:
    context.setError("motion time must be monotonic")
    return CbssInvalidArgument
  if context.tree.root.isNone:
    context.setError("cannot compute an empty CBSS tree")
    return CbssInvalidArgument
  try:
    context.diagnostics = Diagnostics(items: @[])
    var target = resolveTreeStyles(
      context.tree,
      context.sheets,
      defaultProperties(),
      context.diagnostics,
      viewportSize = some(size(width, height))
    )
    if context.diagnostics.hasErrors:
      var messages: seq[string]
      for item in context.diagnostics.items:
        if item.severity == dsError:
          messages.add(item.property & ": " & item.message)
      context.setError(messages.join("; "))
      context.computed = false
      return CbssStyleError
    if context.hasViewport and context.resolved.styles.len > 0:
      context.transitions.reconcileTransitions(
        context.tree, context.resolved, target, nowSeconds
      )
    context.keyframes.reconcileAnimations(
      context.tree, target, nowSeconds
    )
    context.dispatchPendingMotionLifecycle()
    context.resolved = target
    context.motionScheduler.clearDeadline()
    discard context.motionScheduler.consumeDirty()
    discard context.transitions.applyTransitions(
      context.tree, context.resolved, context.motionScheduler, nowSeconds
    )
    discard context.keyframes.applyAnimations(
      context.tree, context.resolved, context.motionScheduler, nowSeconds
    )
    context.dispatchPendingMotionLifecycle()
    context.motionDirtyDomains = dirtyDomainBits(
      context.motionScheduler.consumeDirty()
    )
    context.layout = computeLayout(
      context.tree, context.resolved, size(width, height)
    )
    context.scroll.syncScrollState(
      context.tree, context.resolved, context.layout
    )
    context.refreshPresentation()
    context.lastError = ""
    context.computed = true
    context.hasViewport = true
    context.viewportWidth = width
    context.viewportHeight = height
    context.motionNow = nowSeconds
    context.motionTimeInitialized = true
    CbssOk
  except CatchableError as error:
    context.setError(error.msg)
    context.computed = false
    CbssInternalError

proc cbssContextCompute(
    context: CbssContextHandle;
    width, height: cfloat
): int32 {.exportc: "cbss_context_compute", cdecl, dynlib.} =
  computeContextAt(
    context,
    width,
    height,
    if not context.isNil and context.motionTimeInitialized:
      context.motionNow
    else:
      0.0
  )

proc cbssContextComputeAt(
    context: CbssContextHandle;
    width, height: cfloat;
    nowSeconds: cdouble
): int32 {.exportc: "cbss_context_compute_at", cdecl, dynlib.} =
  computeContextAt(context, width, height, nowSeconds)

proc cbssContextNeedsCompute(context: CbssContextHandle): uint8 {.
    exportc: "cbss_context_needs_compute", cdecl, dynlib.} =
  if context.isNil or not context.computed: 1 else: 0

proc cbssContextRecompute(context: CbssContextHandle): int32 {.
    exportc: "cbss_context_recompute", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.hasViewport:
    context.setError("context has no previous viewport")
    return CbssInvalidArgument
  cbssContextCompute(
    context, context.viewportWidth, context.viewportHeight
  )

proc cbssContextRecomputeAt(
    context: CbssContextHandle;
    nowSeconds: cdouble
): int32 {.exportc: "cbss_context_recompute_at", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.hasViewport:
    context.setError("context has no previous viewport")
    return CbssInvalidArgument
  computeContextAt(
    context, context.viewportWidth, context.viewportHeight, nowSeconds
  )

proc cbssContextAdvanceMotion(
    context: CbssContextHandle;
    nowSeconds: cdouble;
    output: ptr CbssMotionStateC
): int32 {.exportc: "cbss_context_advance_motion", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if output.isNil or not context.computed or not context.motionTimeInitialized:
    return CbssInvalidArgument
  if nowSeconds.classify in {fcNan, fcInf, fcNegInf} or
      nowSeconds < context.motionNow:
    context.setError("motion time must be finite and monotonic")
    return CbssInvalidArgument
  try:
    context.motionScheduler.clearDeadline()
    discard context.motionScheduler.consumeDirty()
    let transitionSamples = context.transitions.applyTransitions(
      context.tree, context.resolved, context.motionScheduler, nowSeconds
    )
    let animationSamples = context.keyframes.applyAnimations(
      context.tree, context.resolved, context.motionScheduler, nowSeconds
    )
    context.dispatchPendingMotionLifecycle()
    context.motionDirtyDomains = dirtyDomainBits(
      context.motionScheduler.consumeDirty()
    )
    context.motionNow = nowSeconds
    if transitionSamples > 0 or animationSamples > 0:
      context.refreshPresentation()
    context.fillMotionState(
      output, animationSamples, transitionSamples
    )
    context.lastError = ""
    CbssOk
  except CatchableError as error:
    context.setError(error.msg)
    CbssInternalError

proc cbssContextMotionState(
    context: CbssContextHandle;
    output: ptr CbssMotionStateC
): int32 {.exportc: "cbss_context_motion_state", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if output.isNil:
    return CbssInvalidArgument
  context.fillMotionState(output)
  CbssOk

proc cbssContextSetReducedMotion(
    context: CbssContextHandle;
    enabled: uint8
): int32 {.exportc: "cbss_context_set_reduced_motion", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if enabled > 1:
    return CbssInvalidArgument
  context.reducedMotion = enabled != 0
  context.transitions.reducedMotion = context.reducedMotion
  context.keyframes.setReducedMotion(context.reducedMotion)
  if context.computed and context.motionTimeInitialized:
    var state: CbssMotionStateC
    return cbssContextAdvanceMotion(context, context.motionNow, addr state)
  CbssOk

proc cbssContextLayoutBoxCount(context: CbssContextHandle): uint32 {.
    exportc: "cbss_context_layout_box_count", cdecl, dynlib.} =
  if context.isNil or not context.computed:
    return 0
  uint32(min(context.layout.boxes.len, int(high(uint32))))

proc cbssContextLayoutBox(
    context: CbssContextHandle;
    index: uint32;
    output: ptr CbssLayoutBoxC
): int32 {.exportc: "cbss_context_layout_box", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if output.isNil or not context.computed:
    return CbssInvalidArgument
  if uint64(index) >= uint64(context.layout.boxes.len):
    return CbssOutOfRange
  let item = context.layout.boxes[int(index)]
  output[] = CbssLayoutBoxC(
    node: item.node.nodeRawValue(),
    rect: item.rect.toRect,
    zIndex: int32(item.zIndex)
  )
  CbssOk

proc cbssNodeLayoutRect(
    context: CbssContextHandle;
    node: uint32;
    output: ptr CbssRectC
): int32 {.exportc: "cbss_node_layout_rect", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if output.isNil or not context.computed or not context.validNode(node):
    return CbssInvalidArgument
  let indices = context.layout.layoutBoxIndices(context.tree.nodes.len)
  let index = indices.boxIndexFor(node.nodeId)
  if index < 0:
    return CbssOutOfRange
  output[] = context.layout.boxes[index].rect.toRect
  CbssOk

proc cbssContextPaintCommandCount(context: CbssContextHandle): uint32 {.
    exportc: "cbss_context_paint_command_count", cdecl, dynlib.} =
  if context.isNil or not context.computed:
    return 0
  uint32(min(context.commands.len, int(high(uint32))))

proc cbssContextPaintCommand(
    context: CbssContextHandle;
    index: uint32;
    output: ptr CbssPaintCommandC
): int32 {.exportc: "cbss_context_paint_command", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if output.isNil or not context.computed:
    return CbssInvalidArgument
  if uint64(index) >= uint64(context.commands.len):
    return CbssOutOfRange
  let command = context.commands[int(index)]
  let value = command.commandString()
  output[] = CbssPaintCommandC(
    kind: command.commandKindToC(),
    owner:
      if command.owner.isSome: command.owner.get.nodeRawValue()
      else: CbssNodeNone,
    rect: command.commandRect().toRect,
    color: command.commandColor().toColor,
    radius: command.commandRadius(),
    stringBytes: uint32(min(value.len, int(high(uint32))))
  )
  case command.kind
  of pcBoxShadow:
    output.value0 = command.shadowOffsetX
    output.value1 = command.shadowOffsetY
    output.value2 = command.shadowBlur
    output.value3 = command.shadowSpread
  of pcFillLinearGradient:
    output.value0 = command.gradient.angle
    output.value1 = cfloat(command.gradient.stops.len)
    output.value2 = cfloat(
      command.gradient.interpolationSpace.interpolationSpaceToC
    )
  of pcStrokeRect:
    output.value0 = command.strokeWidth
  of pcStrokePath:
    output.value0 = command.pathWidth
    output.value1 = cfloat(ord(command.pathLineCap))
    output.value2 = cfloat(ord(command.pathLineJoin))
    output.value3 = command.pathMiterLimit
  of pcDrawImage:
    output.value0 = command.imageOpacity
  of pcPushLayer:
    output.value0 = command.layerOpacity
    output.value1 = cfloat(ord(command.layerCompositeMode))
  else:
    discard
  CbssOk

proc cbssPaintCommandString(
    context: CbssContextHandle;
    index: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_paint_command_string", cdecl, dynlib.} =
  if context.isNil or not context.computed or
      uint64(index) >= uint64(context.commands.len):
    return 0
  copyString(context.commands[int(index)].commandString(), buffer, capacity)

proc cbssPaintCommandTransform(
    context: CbssContextHandle;
    index: uint32;
    output: ptr CbssAffineTransformC
): int32 {.exportc: "cbss_paint_command_transform", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if output.isNil or not context.computed:
    return CbssInvalidArgument
  if uint64(index) >= uint64(context.commands.len):
    return CbssOutOfRange
  let command = context.commands[int(index)]
  if command.kind != pcPushTransform:
    return CbssInvalidArgument
  output[] = CbssAffineTransformC(
    m11: command.transform.m11,
    m12: command.transform.m12,
    m21: command.transform.m21,
    m22: command.transform.m22,
    tx: command.transform.tx,
    ty: command.transform.ty
  )
  CbssOk

proc cbssPaintCommandPathSegmentCount(
    context: CbssContextHandle;
    index: uint32
): uint32 {.exportc: "cbss_paint_command_path_segment_count", cdecl, dynlib.} =
  if context.isNil or not context.computed or
      uint64(index) >= uint64(context.commands.len):
    return 0
  let command = context.commands[int(index)]
  if command.kind != pcStrokePath:
    return 0
  uint32(min(command.path.segments.len, int(high(uint32))))

proc cbssPaintCommandPathSegment(
    context: CbssContextHandle;
    commandIndex, segmentIndex: uint32;
    output: ptr CbssPathSegmentC
): int32 {.exportc: "cbss_paint_command_path_segment", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if output.isNil or not context.computed or
      uint64(commandIndex) >= uint64(context.commands.len):
    return CbssInvalidArgument
  let command = context.commands[int(commandIndex)]
  if command.kind != pcStrokePath:
    return CbssInvalidArgument
  if uint64(segmentIndex) >= uint64(command.path.segments.len):
    return CbssOutOfRange
  let segment = command.path.segments[int(segmentIndex)]
  output[] = CbssPathSegmentC(
    kind: uint32(ord(segment.kind)),
    control1X: segment.control1.x,
    control1Y: segment.control1.y,
    control2X: segment.control2.x,
    control2Y: segment.control2.y,
    endpointX: segment.endpoint.x,
    endpointY: segment.endpoint.y
  )
  CbssOk

proc cbssPaintCommandTextStyle(
    context: CbssContextHandle;
    index: uint32;
    output: ptr CbssTextStyleC
): int32 {.exportc: "cbss_paint_command_text_style", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if output.isNil or not context.computed or
      uint64(index) >= uint64(context.commands.len):
    return CbssInvalidArgument
  let command = context.commands[int(index)]
  if command.kind != pcDrawText:
    return CbssInvalidArgument
  let style = command.textStyle
  output[] = CbssTextStyleC()
  if style.fontSize.isSome:
    output.flags = output.flags or 1'u32
    output.fontSize = style.fontSize.get
  if style.lineHeight.isSome:
    output.flags = output.flags or 2'u32
    output.lineHeight = style.lineHeight.get
  if style.fontWeight.isSome:
    output.flags = output.flags or 4'u32
    output.fontWeight = style.fontWeight.get
  if style.letterSpacing.isSome:
    output.flags = output.flags or 8'u32
    output.letterSpacing = style.letterSpacing.get
  if style.fontStyle.isSome:
    output.flags = output.flags or 16'u32
    output.fontStyle = uint32(ord(style.fontStyle.get))
  CbssOk

proc cbssPaintCommandFontFamily(
    context: CbssContextHandle;
    index: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_paint_command_font_family", cdecl, dynlib.} =
  if context.isNil or not context.computed or
      uint64(index) >= uint64(context.commands.len):
    return 0
  let command = context.commands[int(index)]
  if command.kind != pcDrawText or command.textStyle.fontFamily.isNone:
    return 0
  copyString(command.textStyle.fontFamily.get, buffer, capacity)

proc cbssPaintCommandGradientStopCount(
    context: CbssContextHandle;
    index: uint32
): uint32 {.exportc: "cbss_paint_command_gradient_stop_count", cdecl, dynlib.} =
  if context.isNil or not context.computed or
      uint64(index) >= uint64(context.commands.len):
    return 0
  let command = context.commands[int(index)]
  if command.kind != pcFillLinearGradient:
    return 0
  uint32(min(command.gradient.stops.len, int(high(uint32))))

proc cbssPaintCommandGradientStop(
    context: CbssContextHandle;
    commandIndex, stopIndex: uint32;
    output: ptr CbssGradientStopC
): int32 {.exportc: "cbss_paint_command_gradient_stop", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if output.isNil or not context.computed or
      uint64(commandIndex) >= uint64(context.commands.len):
    return CbssInvalidArgument
  let command = context.commands[int(commandIndex)]
  if command.kind != pcFillLinearGradient:
    return CbssInvalidArgument
  if uint64(stopIndex) >= uint64(command.gradient.stops.len):
    return CbssOutOfRange
  let stop = command.gradient.stops[int(stopIndex)]
  output[] = CbssGradientStopC(color: stop.color.toColor, offset: stop.offset)
  CbssOk

proc cbssContextHitTest(
    context: CbssContextHandle;
    x, y: cfloat;
    output: ptr CbssHitResultC
): int32 {.exportc: "cbss_context_hit_test", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if output.isNil or not context.computed:
    return CbssInvalidArgument
  let hit = hitTest(context.hits, vec2(x, y))
  if hit.isNone:
    return CbssOutOfRange
  output[] = CbssHitResultC(
    node: hit.get.node.nodeRawValue(),
    localX: hit.get.local.x,
    localY: hit.get.local.y,
    kind: uint32(ord(hit.get.kind)),
    cursor:
      if hit.get.cursor.isSome: uint32(ord(hit.get.cursor.get))
      else: 0,
    hasCursor: uint8(hit.get.cursor.isSome)
  )
  CbssOk

proc writeDispatchSummary(
    output: ptr CbssDispatchSummaryC;
    target: Option[NodeId];
    dispatchCount: int;
    outcome: EventOutcome;
    needsCompute, paintChanged, focusChanged: bool
) =
  if output.isNil:
    return
  output[] = CbssDispatchSummaryC(
    target:
      if target.isSome: target.get.nodeRawValue()
      else: CbssNodeNone,
    dispatchCount: uint32(min(dispatchCount, int(high(uint32)))),
    handled: uint8(ord(outcome.handled)),
    outcome:
      (if outcome.handled: CbssEventOutcomeHandled else: 0'u8) or
      (if outcome.stopPropagation: CbssEventOutcomeStopPropagation else: 0'u8) or
      (if outcome.preventDefault: CbssEventOutcomePreventDefault else: 0'u8),
    needsCompute: uint8(ord(needsCompute)),
    paintChanged: uint8(ord(paintChanged)),
    focusChanged: uint8(ord(focusChanged))
  )

proc cbssContextDispatchInput(
    context: CbssContextHandle;
    input: ptr CbssInputEventC;
    output: ptr CbssDispatchSummaryC
): int32 {.exportc: "cbss_context_dispatch_input", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if input.isNil or not input[].validInputEvent():
    return CbssInvalidArgument
  if (input.flags and CbssInputHasPosition) != 0 and not context.computed:
    context.setError("positioned input requires a computed context")
    return CbssInvalidArgument

  try:
    let event = input[].inputEvent()
    let oldHovered = context.interaction.hoveredTarget
    let oldPressed = context.interaction.pressedTarget
    let oldFocused = context.interaction.focusedTarget
    let oldScrollRevision = context.scroll.revision
    var dispatches: seq[DispatchResult]

    case event.kind
    of iekPointerMove, iekPointerDown, iekPointerUp, iekPointerCancel,
       iekKeyDown, iekKeyUp, iekTextInput, iekWheel, iekResize,
       iekTouchCancel, iekTouchEnd, iekTouchMove, iekTouchStart:
      dispatches = context.interaction.processInput(
        context.tree, context.hits, event, context.scroll
      )
      if event.position.isNone and
          event.kind in {iekKeyDown, iekKeyUp, iekTextInput} and
          context.interaction.focusedTarget.isSome:
        for dispatch in dispatches.mitems:
          if dispatch.target.isNone:
            dispatch.target = context.interaction.focusedTarget
    else:
      let target =
        if event.position.isSome:
          let hit = hitTest(context.hits, event.position.get)
          if hit.isSome: some(hit.get.node) else: none(NodeId)
        else:
          context.interaction.focusedTarget
      dispatches.add DispatchResult(
        target: target,
        local:
          if event.position.isSome:
            let hit = hitTest(context.hits, event.position.get)
            if hit.isSome: some(hit.get.local) else: none(Vec2)
          else:
            none(Vec2),
        event: event
      )

    let stateChanged =
      oldHovered != context.interaction.hoveredTarget or
      oldPressed != context.interaction.pressedTarget or
      oldFocused != context.interaction.focusedTarget
    if stateChanged:
      context.invalidate()

    let dispatched = context.dispatchAll(dispatches)
    var outcome = dispatched.outcome
    var dispatchCount = dispatched.count

    if event.kind == iekKeyDown and event.key.isSome and
        event.key.get.toLowerAscii() == "tab" and not outcome.handled:
      let targets = context.focusTargets()
      if targets.len > 0:
        var currentIndex = -1
        for index, target in targets:
          if context.interaction.focusedTarget == some(target):
            currentIndex = index
            break
        let direction = if event.shiftKey: -1 else: 1
        let nextIndex =
          if direction > 0:
            if currentIndex < 0: 0
            else: (currentIndex + 1) mod targets.len
          else:
            if currentIndex < 0: targets.high
            else: (currentIndex - 1 + targets.len) mod targets.len
        let focusResult = context.setContextFocus(
          some(targets[nextIndex]), focusVisible = true
        )
        outcome.handled = outcome.handled or
          focusResult.handled or focusResult.changed
        dispatchCount += focusResult.dispatchCount

    let scrollChanged = oldScrollRevision != context.scroll.revision
    if scrollChanged and context.computed:
      context.refreshPresentation()

    var target = none(NodeId)
    for dispatch in dispatches:
      if dispatch.target.isSome:
        target = dispatch.target
        break
    writeDispatchSummary(
      output,
      target,
      dispatchCount,
      outcome,
      not context.computed,
      scrollChanged and context.computed,
      oldFocused != context.interaction.focusedTarget
    )
    CbssOk
  except CatchableError as error:
    context.setError(error.msg)
    CbssInternalError

proc emitAtNode(
    context: CbssContextHandle;
    node: uint32;
    event: InputEvent;
    output: ptr CbssDispatchSummaryC
): int32 =
  try:
    var dispatch = DispatchResult(
      target: some(node.nodeId),
      local: none(Vec2),
      event: event
    )
    if event.position.isSome and context.computed:
      for region in context.hits:
        if region.node == node.nodeId and region.localOrigin.isSome:
          dispatch.local = some(vec2(
            event.position.get.x - region.localOrigin.get.x,
            event.position.get.y - region.localOrigin.get.y
          ))
          break
    let outcome = context.invokeCallbacks(dispatch)
    writeDispatchSummary(
      output,
      some(node.nodeId),
      1,
      outcome,
      not context.computed,
      false,
      false
    )
    CbssOk
  except CatchableError as error:
    context.setError(error.msg)
    CbssInternalError

proc cbssContextEmitEvent(
    context: CbssContextHandle;
    node: uint32;
    input: ptr CbssInputEventC;
    output: ptr CbssDispatchSummaryC
): int32 {.exportc: "cbss_context_emit_event", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node) or input.isNil or
      not input[].validInputEvent():
    return CbssInvalidArgument
  context.emitAtNode(node, input[].inputEvent(), output)

proc cbssContextEmitSubmit(
    context: CbssContextHandle;
    node: uint32;
    formData: CbssFormDataHandle;
    output: ptr CbssDispatchSummaryC
): int32 {.exportc: "cbss_context_emit_submit", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node):
    return CbssInvalidArgument
  if formData.isNil:
    return CbssInvalidHandle
  var snapshot: FormData
  let status = nimFormDataSnapshot(formData, snapshot)
  if status != CbssOk:
    context.setError("C FormData could not be converted for submit")
    return status
  context.emitAtNode(node, submitEvent(snapshot), output)

proc cbssContextFocusedNode(context: CbssContextHandle): uint32 {.
    exportc: "cbss_context_focused_node", cdecl, dynlib.} =
  if context.isNil or context.interaction.focusedTarget.isNone:
    return CbssNodeNone
  context.interaction.focusedTarget.get.nodeRawValue()

proc cbssContextSetFocus(
    context: CbssContextHandle;
    node: uint32;
    focusVisible: uint8
): int32 {.exportc: "cbss_context_set_focus", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if node != CbssNodeNone and not context.validNode(node):
    return CbssInvalidArgument
  let target =
    if node == CbssNodeNone: none(NodeId)
    else: some(node.nodeId)
  if target.isSome and not context.tree.isFocusable(target.get):
    context.setError("focus target is not focusable")
    return CbssInvalidArgument
  discard context.setContextFocus(target, focusVisible != 0)
  CbssOk

proc cbssContextMoveFocus(
    context: CbssContextHandle;
    direction: int32
): int32 {.exportc: "cbss_context_move_focus", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  let targets = context.focusTargets()
  if targets.len == 0:
    context.setError("context has no focusable traversal target")
    return CbssOutOfRange
  var currentIndex = -1
  for index, target in targets:
    if context.interaction.focusedTarget == some(target):
      currentIndex = index
      break
  let nextIndex =
    if direction >= 0:
      if currentIndex < 0: 0 else: (currentIndex + 1) mod targets.len
    else:
      if currentIndex < 0: targets.high
      else: (currentIndex - 1 + targets.len) mod targets.len
  discard context.setContextFocus(
    some(targets[nextIndex]), focusVisible = true
  )
  CbssOk

proc cbssContextSetFocusScope(
    context: CbssContextHandle;
    node: uint32
): int32 {.exportc: "cbss_context_set_focus_scope", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if node != CbssNodeNone and not context.validNode(node):
    return CbssInvalidArgument
  let scope =
    if node == CbssNodeNone: none(NodeId)
    else: some(node.nodeId)
  context.tree.setFocusScope(scope)
  if context.interaction.focusedTarget.isSome and
      not context.tree.isWithinFocusScope(
        context.interaction.focusedTarget.get
      ):
    discard context.setContextFocus(none(NodeId), focusVisible = false)
  CbssOk

proc cbssContextCapturePointer(
    context: CbssContextHandle;
    node: uint32
): int32 {.exportc: "cbss_context_capture_pointer", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.validNode(node):
    return CbssInvalidArgument
  let dispatch = context.interaction.capturePointer(node.nodeId)
  discard context.invokeCallbacks(dispatch)
  CbssOk

proc cbssContextReleasePointer(context: CbssContextHandle): int32 {.
    exportc: "cbss_context_release_pointer", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  let dispatch = context.interaction.releasePointer()
  if dispatch.isSome:
    discard context.invokeCallbacks(dispatch.get)
  CbssOk

proc cbssNodeScrollMetrics(
    context: CbssContextHandle;
    node: uint32;
    output: ptr CbssScrollMetricsC
): int32 {.exportc: "cbss_node_scroll_metrics", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if output.isNil or not context.computed or not context.validNode(node):
    return CbssInvalidArgument
  let metrics = context.scroll.metricsFor(node.nodeId)
  if metrics.isNone:
    return CbssOutOfRange
  let value = metrics.get
  let maximum = value.maxOffset()
  output[] = CbssScrollMetricsC(
    offsetX: value.offset.x,
    offsetY: value.offset.y,
    viewportWidth: value.viewport.w,
    viewportHeight: value.viewport.h,
    contentWidth: value.content.w,
    contentHeight: value.content.h,
    maxOffsetX: maximum.x,
    maxOffsetY: maximum.y,
    enabledX: uint8(ord(value.enabledX)),
    enabledY: uint8(ord(value.enabledY)),
    scrolling: uint8(ord(value.scrolling))
  )
  CbssOk

proc updateScrollPresentation(
    context: CbssContextHandle;
    changed: bool
): int32 =
  if changed:
    context.refreshPresentation()
  CbssOk

proc cbssNodeScrollTo(
    context: CbssContextHandle;
    node: uint32;
    x, y: cfloat
): int32 {.exportc: "cbss_node_scroll_to", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.computed or not context.validNode(node):
    return CbssInvalidArgument
  if context.scroll.metricsFor(node.nodeId).isNone:
    return CbssOutOfRange
  context.updateScrollPresentation(
    context.scroll.setScrollOffset(node.nodeId, vec2(x, y))
  )

proc cbssNodeScrollBy(
    context: CbssContextHandle;
    node: uint32;
    deltaX, deltaY: cfloat
): int32 {.exportc: "cbss_node_scroll_by", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.computed or not context.validNode(node):
    return CbssInvalidArgument
  if context.scroll.metricsFor(node.nodeId).isNone:
    return CbssOutOfRange
  context.updateScrollPresentation(
    context.scroll.scrollBy(node.nodeId, vec2(deltaX, deltaY))
  )

proc cbssNodeSetScrolling(
    context: CbssContextHandle;
    node: uint32;
    scrolling: uint8
): int32 {.exportc: "cbss_node_set_scrolling", cdecl, dynlib.} =
  if context.isNil:
    return CbssInvalidHandle
  if not context.computed or not context.validNode(node):
    return CbssInvalidArgument
  if context.scroll.metricsFor(node.nodeId).isNone:
    return CbssOutOfRange
  context.updateScrollPresentation(
    context.scroll.setScrolling(node.nodeId, scrolling != 0)
  )

proc cbssContextDiagnosticCount(context: CbssContextHandle): uint32 {.
    exportc: "cbss_context_diagnostic_count", cdecl, dynlib.} =
  if context.isNil:
    return 0
  uint32(min(context.diagnostics.items.len, int(high(uint32))))

proc cbssContextDiagnosticSeverity(
    context: CbssContextHandle;
    index: uint32
): uint32 {.exportc: "cbss_context_diagnostic_severity", cdecl, dynlib.} =
  if context.isNil or uint64(index) >= uint64(context.diagnostics.items.len):
    return high(uint32)
  uint32(ord(context.diagnostics.items[int(index)].severity))

proc cbssContextDiagnosticProperty(
    context: CbssContextHandle;
    index: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_context_diagnostic_property", cdecl, dynlib.} =
  if context.isNil or uint64(index) >= uint64(context.diagnostics.items.len):
    return 0
  copyString(
    context.diagnostics.items[int(index)].property, buffer, capacity
  )

proc cbssContextDiagnosticMessage(
    context: CbssContextHandle;
    index: uint32;
    buffer: cstring;
    capacity: uint32
): uint32 {.exportc: "cbss_context_diagnostic_message", cdecl, dynlib.} =
  if context.isNil or uint64(index) >= uint64(context.diagnostics.items.len):
    return 0
  copyString(
    context.diagnostics.items[int(index)].message, buffer, capacity
  )
