when not defined(cbssGpuBgfx):
  {.error: "the bgfx adapter requires -d:cbssGpuBgfx and the optional bgfxim package".}

import bgfx

import ../../runtime/gpu_host

type
  BgfxHostOptions* = object
    rendererType*: bgfx_renderer_type_t
    vendorId*, deviceId*: uint16
    capabilities*: uint64
    debug*, profile*, fallback*, videoDecode*: bool
    platformData*: bgfx_platform_data_t
    colorFormat*: bgfx_texture_format_t
    depthStencilFormat*: bgfx_texture_format_t
    numBackBuffers*, maxFrameLatency*, debugTextScale*: uint8

  BgfxAdapterContext = ref object of GpuBackendContext
    options: BgfxHostOptions
    attached: bool
    owned: bool

var activeBgfxContext: BgfxAdapterContext

proc defaultBgfxHostOptions*(): BgfxHostOptions =
  BgfxHostOptions(
    rendererType: BGFX_RENDERER_TYPE_COUNT,
    vendorId: BGFX_PCI_ID_NONE,
    deviceId: 0,
    colorFormat: BGFX_TEXTURE_FORMAT_COUNT,
    depthStencilFormat: BGFX_TEXTURE_FORMAT_COUNT
  )

proc context(value: GpuBackendContext): BgfxAdapterContext {.inline.} =
  BgfxAdapterContext(value)

proc fillBackendInfo(info: var GpuBackendInfo): GpuBackendStatus =
  let caps = BGFX.getCaps()
  if caps.isNil:
    return gbsUnavailable
  let name = BGFX.getRendererName(BGFX.getRendererType())
  info = GpuBackendInfo(
    rendererName: (if name.isNil: "bgfx" else: $name),
    computeSupported: (caps.supported and BGFX_CAPS_COMPUTE) != 0,
    homogeneousDepth: caps.homogeneousDepth,
    originBottomLeft: caps.originBottomLeft,
    maxTextureSize: caps.limits.maxTextureSize
  )
  gbsOk

proc claimContext(value: BgfxAdapterContext; owned: bool): GpuBackendStatus =
  if not activeBgfxContext.isNil or value.attached:
    return gbsFailed
  value.attached = true
  value.owned = owned
  activeBgfxContext = value
  gbsOk

proc releaseContext(value: BgfxAdapterContext) =
  if activeBgfxContext == value:
    activeBgfxContext = nil
  value.attached = false
  value.owned = false

proc openOwned(
    rawContext: GpuBackendContext;
    config: GpuHostConfig;
    info: var GpuBackendInfo
): GpuBackendStatus {.raises: [].} =
  let value = rawContext.context
  if value.claimContext(true) != gbsOk:
    return gbsFailed

  var init: bgfx_init_t
  BGFX.initCtor(addr init)
  init.type = value.options.rendererType
  init.vendorId = value.options.vendorId
  init.deviceId = value.options.deviceId
  init.capabilities = value.options.capabilities
  init.debug = value.options.debug
  init.profile = value.options.profile
  init.fallback = value.options.fallback
  init.videoDecode = value.options.videoDecode
  init.platformData = value.options.platformData
  init.resolution.width = config.width
  init.resolution.height = config.height
  init.resolution.reset = config.resetFlags
  if value.options.colorFormat != BGFX_TEXTURE_FORMAT_COUNT:
    init.resolution.formatColor = value.options.colorFormat
  if value.options.depthStencilFormat != BGFX_TEXTURE_FORMAT_COUNT:
    init.resolution.formatDepthStencil = value.options.depthStencilFormat
  if value.options.numBackBuffers != 0:
    init.resolution.numBackBuffers = value.options.numBackBuffers
  if value.options.maxFrameLatency != 0:
    init.resolution.maxFrameLatency = value.options.maxFrameLatency
  if value.options.debugTextScale != 0:
    init.resolution.debugTextScale = value.options.debugTextScale

  if not BGFX.init(addr init):
    value.releaseContext()
    return gbsUnavailable

  result = fillBackendInfo(info)
  if result != gbsOk:
    BGFX.shutdown()
    value.releaseContext()

proc attachBorrowed(
    rawContext: GpuBackendContext;
    config: GpuHostConfig;
    info: var GpuBackendInfo
): GpuBackendStatus {.raises: [].} =
  discard config
  let value = rawContext.context
  if value.claimContext(false) != gbsOk:
    return gbsFailed
  result = fillBackendInfo(info)
  if result != gbsOk:
    value.releaseContext()

proc beginFrame(
    rawContext: GpuBackendContext;
    frameNumber: uint64
): GpuBackendStatus {.raises: [].} =
  discard frameNumber
  if not rawContext.context.attached:
    return gbsFailed
  gbsOk

proc endFrame(
    rawContext: GpuBackendContext;
    frameNumber: uint64
): GpuBackendStatus {.raises: [].} =
  discard frameNumber
  if not rawContext.context.attached:
    return gbsFailed
  discard BGFX.frame(BGFX_FRAME_NONE)
  gbsOk

proc resize(
    rawContext: GpuBackendContext;
    width, height: uint32;
    resetFlags: uint32
): GpuBackendStatus {.raises: [].} =
  if not rawContext.context.attached:
    return gbsFailed
  BGFX.reset(width, height, resetFlags, BGFX_TEXTURE_FORMAT_COUNT)
  gbsOk

proc restore(
    rawContext: GpuBackendContext;
    info: var GpuBackendInfo
): GpuBackendStatus {.raises: [].} =
  discard rawContext
  discard info
  gbsUnsupported

proc bgfxTextureFormat(value: GpuTextureFormat): bgfx_texture_format_t =
  case value
  of gtfR8: BGFX_TEXTURE_FORMAT_R8
  of gtfRgba8: BGFX_TEXTURE_FORMAT_RGBA8
  of gtfBgra8: BGFX_TEXTURE_FORMAT_BGRA8

proc bgfxTextureFlags(usage: set[GpuTextureUsage]): uint64 =
  result = BGFX_TEXTURE_NONE
  if gtuRenderTarget in usage:
    result = result or BGFX_TEXTURE_RT
  if gtuStorage in usage:
    result = result or BGFX_TEXTURE_COMPUTE_WRITE
  if gtuBlitDestination in usage:
    result = result or BGFX_TEXTURE_BLIT_DST
  if gtuReadback in usage:
    result = result or BGFX_TEXTURE_READ_BACK

proc createTexture(
    rawContext: GpuBackendContext;
    descriptor: GpuTextureDescriptor;
    initialData: seq[byte];
    resource: var GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  let value = rawContext.context
  if not value.attached:
    return gbsFailed
  if descriptor.width > uint32(high(uint16)) or
      descriptor.height > uint32(high(uint16)) or
      uint64(initialData.len) > uint64(high(uint32)):
    return gbsInvalidConfiguration
  if gtuReadback in descriptor.usage and
      (gtuRenderTarget in descriptor.usage or
       gtuStorage in descriptor.usage):
    return gbsInvalidConfiguration

  var memory: ptr bgfx_memory_t
  if initialData.len > 0:
    memory = BGFX.copy(unsafeAddr initialData[0], uint32(initialData.len))
    if memory.isNil:
      return gbsFailed

  let handle = BGFX.createTexture2D(
    uint16(descriptor.width),
    uint16(descriptor.height),
    false,
    1,
    descriptor.format.bgfxTextureFormat(),
    descriptor.usage.bgfxTextureFlags(),
    memory,
    0
  )
  if not BGFX_HANDLE_IS_VALID(handle):
    return gbsFailed
  if descriptor.label.len > 0:
    BGFX.setTextureName(
      handle,
      descriptor.label.cstring,
      int32(descriptor.label.len)
    )
  resource = GpuBackendResourceId(uint64(handle.idx) + 1'u64)
  gbsOk

proc destroyResource(
    rawContext: GpuBackendContext;
    resource: GpuBackendResourceId;
    kind: GpuResourceKind
) {.raises: [].} =
  let value = rawContext.context
  let rawId = resource.backendResourceIdValue()
  if not value.attached or rawId == 0 or rawId > uint64(high(uint16)) + 1:
    return
  case kind
  of grkTexture:
    BGFX.destroyTexture(bgfx_texture_handle_t(idx: uint16(rawId - 1)))
  else:
    discard

proc closeOwned(rawContext: GpuBackendContext) {.raises: [].} =
  let value = rawContext.context
  if value.attached and value.owned:
    BGFX.shutdown()
  value.releaseContext()

proc detachBorrowed(rawContext: GpuBackendContext) {.raises: [].} =
  rawContext.context.releaseContext()

proc newBgfxBackend*(
    options = defaultBgfxHostOptions()
): GpuBackendVTable =
  let value = BgfxAdapterContext(options: options)
  GpuBackendVTable(
    apiVersion: gpuHostApiVersion,
    provider: gpkBgfx,
    context: value,
    openOwned: openOwned,
    attachBorrowed: attachBorrowed,
    beginFrame: beginFrame,
    endFrame: endFrame,
    resize: resize,
    restore: restore,
    createTexture: createTexture,
    destroyResource: destroyResource,
    closeOwned: closeOwned,
    detachBorrowed: detachBorrowed
  )
