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

const
  backendResourceTagShift = 32
  backendResourcePayloadMask = 0xffff_ffff'u64
  brtTexture = 1'u64
  brtStaticVertexBuffer = 2'u64
  brtStaticIndexBuffer = 3'u64
  brtDynamicVertexBuffer = 4'u64
  brtDynamicIndexBuffer = 5'u64
  brtFrameBuffer = 6'u64
  brtShader = 7'u64
  brtProgram = 8'u64

proc packBackendResource(tag: uint64; handleIndex: uint16): GpuBackendResourceId =
  GpuBackendResourceId(
    (tag shl backendResourceTagShift) or (uint64(handleIndex) + 1'u64)
  )

proc unpackBackendResource(
    resource: GpuBackendResourceId
): tuple[tag: uint64, handleIndex: uint16, valid: bool] =
  let raw = resource.backendResourceIdValue()
  let payload = raw and backendResourcePayloadMask
  let tag = raw shr backendResourceTagShift
  if payload == 0 or payload > uint64(high(uint16)) + 1'u64 or tag == 0:
    return (tag, 0'u16, false)
  (tag, uint16(payload - 1'u64), true)

proc bgfxVertexSemantic(value: GpuVertexSemantic): bgfx_attrib_t =
  case value
  of gvsPosition: BGFX_ATTRIB_POSITION
  of gvsNormal: BGFX_ATTRIB_NORMAL
  of gvsTangent: BGFX_ATTRIB_TANGENT
  of gvsBitangent: BGFX_ATTRIB_BITANGENT
  of gvsColor0: BGFX_ATTRIB_COLOR0
  of gvsColor1: BGFX_ATTRIB_COLOR1
  of gvsColor2: BGFX_ATTRIB_COLOR2
  of gvsColor3: BGFX_ATTRIB_COLOR3
  of gvsIndices: BGFX_ATTRIB_INDICES
  of gvsWeight: BGFX_ATTRIB_WEIGHT
  of gvsTexCoord0: BGFX_ATTRIB_TEXCOORD0
  of gvsTexCoord1: BGFX_ATTRIB_TEXCOORD1
  of gvsTexCoord2: BGFX_ATTRIB_TEXCOORD2
  of gvsTexCoord3: BGFX_ATTRIB_TEXCOORD3
  of gvsTexCoord4: BGFX_ATTRIB_TEXCOORD4
  of gvsTexCoord5: BGFX_ATTRIB_TEXCOORD5
  of gvsTexCoord6: BGFX_ATTRIB_TEXCOORD6
  of gvsTexCoord7: BGFX_ATTRIB_TEXCOORD7

proc bgfxVertexComponentType(
    value: GpuVertexComponentType
): bgfx_attrib_type_t =
  case value
  of gvctUint8: BGFX_ATTRIB_TYPE_UINT8
  of gvctInt16: BGFX_ATTRIB_TYPE_INT16
  of gvctHalf: BGFX_ATTRIB_TYPE_HALF
  of gvctFloat: BGFX_ATTRIB_TYPE_FLOAT

proc buildBgfxVertexLayout(
    descriptor: GpuBufferDescriptor;
    layout: var bgfx_vertex_layout_t
) =
  discard BGFX.vertexLayoutBegin(addr layout, BGFX.getRendererType())
  for attribute in descriptor.vertexLayout:
    discard BGFX.vertexLayoutAdd(
      addr layout,
      attribute.semantic.bgfxVertexSemantic(),
      attribute.components,
      attribute.componentType.bgfxVertexComponentType(),
      attribute.normalized,
      attribute.asInteger
    )
  BGFX.vertexLayoutEnd(addr layout)

proc bgfxIndexFlags(descriptor: GpuBufferDescriptor): uint16 =
  if descriptor.indexFormat == gifUint32: BGFX_BUFFER_INDEX32
  else: BGFX_BUFFER_NONE

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
  resource = packBackendResource(brtTexture, handle.idx)
  gbsOk

proc createBuffer(
    rawContext: GpuBackendContext;
    descriptor: GpuBufferDescriptor;
    initialData: seq[byte];
    resource: var GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  let value = rawContext.context
  if not value.attached:
    return gbsFailed
  if descriptor.byteSize == 0 or descriptor.byteSize > uint64(high(uint32)) or
      uint64(initialData.len) > uint64(high(uint32)):
    return gbsInvalidConfiguration

  var layout: bgfx_vertex_layout_t
  case descriptor.role
  of gbrVertex:
    descriptor.buildBgfxVertexLayout(layout)
    if layout.stride == 0 or descriptor.byteSize mod uint64(layout.stride) != 0:
      return gbsInvalidConfiguration
  of gbrIndex:
    let elementBytes = if descriptor.indexFormat == gifUint16: 2'u64 else: 4'u64
    if descriptor.byteSize mod elementBytes != 0:
      return gbsInvalidConfiguration

  var memory: ptr bgfx_memory_t
  if initialData.len > 0:
    memory = BGFX.copy(unsafeAddr initialData[0], uint32(initialData.len))
    if memory.isNil:
      return gbsFailed

  case descriptor.role
  of gbrVertex:
    if descriptor.access == gbaStatic:
      let handle = BGFX.createVertexBuffer(memory, addr layout, BGFX_BUFFER_NONE)
      if not BGFX_HANDLE_IS_VALID(handle):
        return gbsFailed
      if descriptor.label.len > 0:
        BGFX.setVertexBufferName(
          handle,
          descriptor.label.cstring,
          int32(descriptor.label.len)
        )
      resource = packBackendResource(brtStaticVertexBuffer, handle.idx)
    elif initialData.len > 0:
      let handle = BGFX.createDynamicVertexBufferMem(
        memory,
        addr layout,
        BGFX_BUFFER_NONE
      )
      if not BGFX_HANDLE_IS_VALID(handle):
        return gbsFailed
      resource = packBackendResource(brtDynamicVertexBuffer, handle.idx)
    else:
      let handle = BGFX.createDynamicVertexBuffer(
        uint32(descriptor.byteSize div uint64(layout.stride)),
        addr layout,
        BGFX_BUFFER_NONE
      )
      if not BGFX_HANDLE_IS_VALID(handle):
        return gbsFailed
      resource = packBackendResource(brtDynamicVertexBuffer, handle.idx)
  of gbrIndex:
    let flags = descriptor.bgfxIndexFlags()
    let elementBytes = if descriptor.indexFormat == gifUint16: 2'u64 else: 4'u64
    if descriptor.access == gbaStatic:
      let handle = BGFX.createIndexBuffer(memory, flags)
      if not BGFX_HANDLE_IS_VALID(handle):
        return gbsFailed
      if descriptor.label.len > 0:
        BGFX.setIndexBufferName(
          handle,
          descriptor.label.cstring,
          int32(descriptor.label.len)
        )
      resource = packBackendResource(brtStaticIndexBuffer, handle.idx)
    elif initialData.len > 0:
      let handle = BGFX.createDynamicIndexBufferMem(memory, flags)
      if not BGFX_HANDLE_IS_VALID(handle):
        return gbsFailed
      resource = packBackendResource(brtDynamicIndexBuffer, handle.idx)
    else:
      let handle = BGFX.createDynamicIndexBuffer(
        uint32(descriptor.byteSize div elementBytes),
        flags
      )
      if not BGFX_HANDLE_IS_VALID(handle):
        return gbsFailed
      resource = packBackendResource(brtDynamicIndexBuffer, handle.idx)
  gbsOk

proc updateBuffer(
    rawContext: GpuBackendContext;
    resource: GpuBackendResourceId;
    descriptor: GpuBufferDescriptor;
    offsetBytes: uint64;
    data: seq[byte]
): GpuBackendStatus {.raises: [].} =
  let value = rawContext.context
  let decoded = resource.unpackBackendResource()
  if not value.attached or not decoded.valid or data.len == 0 or
      uint64(data.len) > uint64(high(uint32)):
    return gbsInvalidConfiguration
  if decoded.tag != brtDynamicVertexBuffer and
      decoded.tag != brtDynamicIndexBuffer:
    return gbsInvalidConfiguration
  var startElement: uint32
  case decoded.tag
  of brtDynamicVertexBuffer:
    let stride = descriptor.vertexStride()
    if stride == 0 or offsetBytes mod stride != 0:
      return gbsInvalidConfiguration
    startElement = uint32(offsetBytes div stride)
  of brtDynamicIndexBuffer:
    let elementBytes = if descriptor.indexFormat == gifUint16: 2'u64 else: 4'u64
    if offsetBytes mod elementBytes != 0:
      return gbsInvalidConfiguration
    startElement = uint32(offsetBytes div elementBytes)
  else:
    discard
  let memory = BGFX.copy(unsafeAddr data[0], uint32(data.len))
  if memory.isNil:
    return gbsFailed
  case decoded.tag
  of brtDynamicVertexBuffer:
    BGFX.updateDynamicVertexBuffer(
      bgfx_dynamic_vertex_buffer_handle_t(idx: decoded.handleIndex),
      startElement,
      memory
    )
  of brtDynamicIndexBuffer:
    BGFX.updateDynamicIndexBuffer(
      bgfx_dynamic_index_buffer_handle_t(idx: decoded.handleIndex),
      startElement,
      memory
    )
  else:
    discard
  gbsOk

proc createRenderTarget(
    rawContext: GpuBackendContext;
    descriptor: GpuRenderTargetDescriptor;
    resource: var GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  let value = rawContext.context
  if not value.attached:
    return gbsFailed
  if descriptor.width == 0 or descriptor.height == 0 or
      descriptor.width > uint32(high(uint16)) or
      descriptor.height > uint32(high(uint16)) or
      gtuRenderTarget notin descriptor.usage or
      gtuReadback in descriptor.usage:
    return gbsInvalidConfiguration

  let handle = BGFX.createFrameBuffer(
    uint16(descriptor.width),
    uint16(descriptor.height),
    descriptor.format.bgfxTextureFormat(),
    descriptor.usage.bgfxTextureFlags()
  )
  if not BGFX_HANDLE_IS_VALID(handle):
    return gbsFailed
  if descriptor.label.len > 0:
    BGFX.setFrameBufferName(
      handle,
      descriptor.label.cstring,
      int32(descriptor.label.len)
    )
  resource = packBackendResource(brtFrameBuffer, handle.idx)
  gbsOk

proc createShader(
    rawContext: GpuBackendContext;
    descriptor: GpuShaderDescriptor;
    bytecode: seq[byte];
    resource: var GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  let value = rawContext.context
  if not value.attached or bytecode.len == 0 or
      uint64(bytecode.len) > uint64(high(uint32)):
    return gbsInvalidConfiguration
  if descriptor.stage == gssCompute:
    let caps = BGFX.getCaps()
    if caps.isNil or (caps.supported and BGFX_CAPS_COMPUTE) == 0:
      return gbsUnsupported

  let memory = BGFX.copy(unsafeAddr bytecode[0], uint32(bytecode.len))
  if memory.isNil:
    return gbsFailed
  let handle = BGFX.createShader(memory)
  if not BGFX_HANDLE_IS_VALID(handle):
    return gbsFailed
  if descriptor.label.len > 0:
    BGFX.setShaderName(
      handle,
      descriptor.label.cstring,
      int32(descriptor.label.len)
    )
  resource = packBackendResource(brtShader, handle.idx)
  gbsOk

proc createGraphicsPipeline(
    rawContext: GpuBackendContext;
    descriptor: GpuGraphicsPipelineDescriptor;
    vertexShader, fragmentShader: GpuBackendResourceId;
    resource: var GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  discard descriptor
  let value = rawContext.context
  let vertex = vertexShader.unpackBackendResource()
  let fragment = fragmentShader.unpackBackendResource()
  if not value.attached or not vertex.valid or not fragment.valid or
      vertex.tag != brtShader or fragment.tag != brtShader:
    return gbsInvalidConfiguration
  let handle = BGFX.createProgram(
    bgfx_shader_handle_t(idx: vertex.handleIndex),
    bgfx_shader_handle_t(idx: fragment.handleIndex),
    false
  )
  if not BGFX_HANDLE_IS_VALID(handle):
    return gbsFailed
  resource = packBackendResource(brtProgram, handle.idx)
  gbsOk

proc createComputePipeline(
    rawContext: GpuBackendContext;
    descriptor: GpuComputePipelineDescriptor;
    computeShader: GpuBackendResourceId;
    resource: var GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  discard descriptor
  let value = rawContext.context
  let compute = computeShader.unpackBackendResource()
  if not value.attached or not compute.valid or compute.tag != brtShader:
    return gbsInvalidConfiguration
  let caps = BGFX.getCaps()
  if caps.isNil or (caps.supported and BGFX_CAPS_COMPUTE) == 0:
    return gbsUnsupported
  let handle = BGFX.createComputeProgram(
    bgfx_shader_handle_t(idx: compute.handleIndex),
    false
  )
  if not BGFX_HANDLE_IS_VALID(handle):
    return gbsFailed
  resource = packBackendResource(brtProgram, handle.idx)
  gbsOk

proc bgfxBlendFactor(value: GpuBlendFactor): uint64 =
  case value
  of gbfZero: BGFX_STATE_BLEND_ZERO
  of gbfOne: BGFX_STATE_BLEND_ONE
  of gbfSourceColor: BGFX_STATE_BLEND_SRC_COLOR
  of gbfOneMinusSourceColor: BGFX_STATE_BLEND_INV_SRC_COLOR
  of gbfDestinationColor: BGFX_STATE_BLEND_DST_COLOR
  of gbfOneMinusDestinationColor: BGFX_STATE_BLEND_INV_DST_COLOR
  of gbfSourceAlpha: BGFX_STATE_BLEND_SRC_ALPHA
  of gbfOneMinusSourceAlpha: BGFX_STATE_BLEND_INV_SRC_ALPHA
  of gbfDestinationAlpha: BGFX_STATE_BLEND_DST_ALPHA
  of gbfOneMinusDestinationAlpha: BGFX_STATE_BLEND_INV_DST_ALPHA

proc bgfxBlendOperation(value: GpuBlendOperation): uint64 =
  case value
  of gboAdd: BGFX_STATE_BLEND_EQUATION_ADD
  of gboSubtract: BGFX_STATE_BLEND_EQUATION_SUB
  of gboReverseSubtract: BGFX_STATE_BLEND_EQUATION_REVSUB
  of gboMinimum: BGFX_STATE_BLEND_EQUATION_MIN
  of gboMaximum: BGFX_STATE_BLEND_EQUATION_MAX

proc bgfxDrawState(descriptor: GpuGraphicsPipelineDescriptor): uint64 =
  if gccRed in descriptor.blend.writeMask:
    result = result or BGFX_STATE_WRITE_R
  if gccGreen in descriptor.blend.writeMask:
    result = result or BGFX_STATE_WRITE_G
  if gccBlue in descriptor.blend.writeMask:
    result = result or BGFX_STATE_WRITE_B
  if gccAlpha in descriptor.blend.writeMask:
    result = result or BGFX_STATE_WRITE_A

  case descriptor.topology
  of gptTriangleList: discard
  of gptTriangleStrip: result = result or BGFX_STATE_PT_TRISTRIP
  of gptLineList: result = result or BGFX_STATE_PT_LINES
  of gptLineStrip: result = result or BGFX_STATE_PT_LINESTRIP
  of gptPointList: result = result or BGFX_STATE_PT_POINTS

  if descriptor.frontFace == gffCounterClockwise:
    result = result or BGFX_STATE_FRONT_CCW
  case descriptor.cullMode
  of gcmNone: discard
  of gcmFront:
    if descriptor.frontFace == gffCounterClockwise:
      result = result or BGFX_STATE_CULL_CCW
    else:
      result = result or BGFX_STATE_CULL_CW
  of gcmBack:
    if descriptor.frontFace == gffCounterClockwise:
      result = result or BGFX_STATE_CULL_CW
    else:
      result = result or BGFX_STATE_CULL_CCW

  if descriptor.blend.enabled:
    result = result or BGFX_STATE_BLEND_FUNC_SEPARATE(
      descriptor.blend.sourceColor.bgfxBlendFactor(),
      descriptor.blend.destinationColor.bgfxBlendFactor(),
      descriptor.blend.sourceAlpha.bgfxBlendFactor(),
      descriptor.blend.destinationAlpha.bgfxBlendFactor()
    )
    result = result or BGFX_STATE_BLEND_EQUATION_SEPARATE(
      descriptor.blend.colorOperation.bgfxBlendOperation(),
      descriptor.blend.alphaOperation.bgfxBlendOperation()
    )

proc packedClearColor(color: GpuClearColor): uint32 =
  let red = uint32(color.red * 255'f32 + 0.5'f32)
  let green = uint32(color.green * 255'f32 + 0.5'f32)
  let blue = uint32(color.blue * 255'f32 + 0.5'f32)
  let alpha = uint32(color.alpha * 255'f32 + 0.5'f32)
  (red shl 24) or (green shl 16) or (blue shl 8) or alpha

proc beginGraphicsPass(
    rawContext: GpuBackendContext;
    viewId: uint16;
    pass: GpuGraphicsPassDescriptor;
    renderTarget: GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  if not rawContext.context.attached:
    return gbsInvalidConfiguration
  let target = renderTarget.unpackBackendResource()
  if renderTarget.backendResourceIdValue() == 0:
    BGFX.setViewFrameBuffer(
      viewId,
      bgfx_frame_buffer_handle_t(idx: BGFX_INVALID_HANDLE)
    )
  elif not target.valid or target.tag != brtFrameBuffer:
    return gbsInvalidConfiguration
  else:
    BGFX.setViewFrameBuffer(
      viewId,
      bgfx_frame_buffer_handle_t(idx: target.handleIndex)
    )
  BGFX.setViewRect(
    viewId,
    int16(pass.viewport.x),
    int16(pass.viewport.y),
    uint16(pass.viewport.width),
    uint16(pass.viewport.height)
  )
  if pass.scissorEnabled:
    BGFX.setViewScissor(
      viewId,
      uint16(pass.scissor.x),
      uint16(pass.scissor.y),
      uint16(pass.scissor.width),
      uint16(pass.scissor.height)
    )
  else:
    BGFX.setViewScissor(viewId, 0, 0, 0, 0)
  if pass.clearColorEnabled:
    BGFX.setViewClear(
      viewId,
      BGFX_CLEAR_COLOR,
      pass.clearColor.packedClearColor(),
      1'f32,
      0
    )
  else:
    BGFX.setViewClear(viewId, BGFX_CLEAR_NONE, 0, 1'f32, 0)
  gbsOk

proc submitDraw(
    rawContext: GpuBackendContext;
    viewId: uint16;
    pipeline, vertexBuffer, indexBuffer: GpuBackendResourceId;
    pipelineDescriptor: GpuGraphicsPipelineDescriptor;
    vertexDescriptor, indexDescriptor: GpuBufferDescriptor;
    command: GpuDrawCommand
): GpuBackendStatus {.raises: [].} =
  discard vertexDescriptor
  discard indexDescriptor
  let value = rawContext.context
  let program = pipeline.unpackBackendResource()
  let vertex = vertexBuffer.unpackBackendResource()
  let index = indexBuffer.unpackBackendResource()
  if not value.attached or not program.valid or program.tag != brtProgram or
      not vertex.valid or
      (vertex.tag != brtStaticVertexBuffer and
       vertex.tag != brtDynamicVertexBuffer):
    return gbsInvalidConfiguration
  if indexBuffer.backendResourceIdValue() != 0 and
      (not index.valid or
       (index.tag != brtStaticIndexBuffer and
        index.tag != brtDynamicIndexBuffer)):
    return gbsInvalidConfiguration
  case vertex.tag
  of brtStaticVertexBuffer:
    BGFX.setVertexBuffer(
      0,
      bgfx_vertex_buffer_handle_t(idx: vertex.handleIndex),
      command.firstVertex,
      command.vertexCount
    )
  of brtDynamicVertexBuffer:
    BGFX.setDynamicVertexBuffer(
      0,
      bgfx_dynamic_vertex_buffer_handle_t(idx: vertex.handleIndex),
      command.firstVertex,
      command.vertexCount
    )
  else:
    return gbsInvalidConfiguration

  if indexBuffer.backendResourceIdValue() != 0:
    case index.tag
    of brtStaticIndexBuffer:
      BGFX.setIndexBuffer(
        bgfx_index_buffer_handle_t(idx: index.handleIndex),
        command.firstIndex,
        command.indexCount
      )
    of brtDynamicIndexBuffer:
      BGFX.setDynamicIndexBuffer(
        bgfx_dynamic_index_buffer_handle_t(idx: index.handleIndex),
        command.firstIndex,
        command.indexCount
      )
    else:
      return gbsInvalidConfiguration

  BGFX.setState(pipelineDescriptor.bgfxDrawState(), 0)
  BGFX.submit(
    viewId,
    bgfx_program_handle_t(idx: program.handleIndex),
    command.depth,
    BGFX_DISCARD_ALL
  )
  result = gbsOk

proc dispatch(
    rawContext: GpuBackendContext;
    viewId: uint16;
    pipeline: GpuBackendResourceId;
    command: GpuComputeCommand
): GpuBackendStatus {.raises: [].} =
  let value = rawContext.context
  let program = pipeline.unpackBackendResource()
  if not value.attached or not program.valid or program.tag != brtProgram:
    return gbsInvalidConfiguration
  let caps = BGFX.getCaps()
  if caps.isNil or (caps.supported and BGFX_CAPS_COMPUTE) == 0:
    return gbsUnsupported
  BGFX.dispatch(
    viewId,
    bgfx_program_handle_t(idx: program.handleIndex),
    command.groupsX,
    command.groupsY,
    command.groupsZ,
    BGFX_DISCARD_ALL
  )
  gbsOk

proc destroyResource(
    rawContext: GpuBackendContext;
    resource: GpuBackendResourceId;
    kind: GpuResourceKind
) {.raises: [].} =
  let value = rawContext.context
  let decoded = resource.unpackBackendResource()
  if not value.attached or not decoded.valid:
    return
  discard kind
  case decoded.tag
  of brtTexture:
    BGFX.destroyTexture(bgfx_texture_handle_t(idx: decoded.handleIndex))
  of brtStaticVertexBuffer:
    BGFX.destroyVertexBuffer(
      bgfx_vertex_buffer_handle_t(idx: decoded.handleIndex)
    )
  of brtStaticIndexBuffer:
    BGFX.destroyIndexBuffer(bgfx_index_buffer_handle_t(idx: decoded.handleIndex))
  of brtDynamicVertexBuffer:
    BGFX.destroyDynamicVertexBuffer(
      bgfx_dynamic_vertex_buffer_handle_t(idx: decoded.handleIndex)
    )
  of brtDynamicIndexBuffer:
    BGFX.destroyDynamicIndexBuffer(
      bgfx_dynamic_index_buffer_handle_t(idx: decoded.handleIndex)
    )
  of brtFrameBuffer:
    BGFX.destroyFrameBuffer(
      bgfx_frame_buffer_handle_t(idx: decoded.handleIndex)
    )
  of brtShader:
    BGFX.destroyShader(bgfx_shader_handle_t(idx: decoded.handleIndex))
  of brtProgram:
    BGFX.destroyProgram(bgfx_program_handle_t(idx: decoded.handleIndex))
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
    createBuffer: createBuffer,
    updateBuffer: updateBuffer,
    createRenderTarget: createRenderTarget,
    createShader: createShader,
    createGraphicsPipeline: createGraphicsPipeline,
    createComputePipeline: createComputePipeline,
    beginGraphicsPass: beginGraphicsPass,
    submitDraw: submitDraw,
    dispatch: dispatch,
    destroyResource: destroyResource,
    closeOwned: closeOwned,
    detachBorrowed: detachBorrowed
  )
