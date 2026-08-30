import std/[algorithm, hashes, math, tables]

const
  gpuHostApiVersion* = 9'u32
  maxGpuNamespaceNameBytes* = 128
  maxGpuResourceLabelBytes* = 128
  maxGpuViewCount* = 256'u16
  maxGpuUniformBindings* = 32
  maxGpuTextureBindings* = 16
  maxGpuStorageImageBindings* = 16
  maxGpuPendingReadbacksPerNamespace* = 8

type
  GpuHostError* = object of CatchableError

  GpuProviderKind* = enum
    gpkCustom,
    gpkBgfx

  GpuHostOwnership* = enum
    ghoOwned,
    ghoBorrowed

  GpuHostState* = enum
    ghsOpening,
    ghsReady,
    ghsDeviceLost,
    ghsClosed

  GpuBackendStatus* = enum
    gbsOk,
    gbsUnavailable,
    gbsUnsupported,
    gbsInvalidConfiguration,
    gbsDeviceLost,
    gbsFailed

  GpuResourceKind* = enum
    grkBuffer,
    grkTexture,
    grkRenderTarget,
    grkSampler,
    grkUniform,
    grkShader,
    grkPipeline

  GpuTextureFormat* = enum
    gtfR8,
    gtfRgba8,
    gtfBgra8

  GpuTextureUsage* = enum
    gtuSampled,
    gtuRenderTarget,
    gtuStorage,
    gtuBlitSource,
    gtuBlitDestination,
    gtuReadback

  GpuBufferRole* = enum
    gbrVertex,
    gbrIndex

  GpuBufferAccess* = enum
    gbaStatic,
    gbaDynamic

  GpuIndexFormat* = enum
    gifUint16,
    gifUint32

  GpuVertexSemantic* = enum
    gvsPosition,
    gvsNormal,
    gvsTangent,
    gvsBitangent,
    gvsColor0,
    gvsColor1,
    gvsColor2,
    gvsColor3,
    gvsIndices,
    gvsWeight,
    gvsTexCoord0,
    gvsTexCoord1,
    gvsTexCoord2,
    gvsTexCoord3,
    gvsTexCoord4,
    gvsTexCoord5,
    gvsTexCoord6,
    gvsTexCoord7

  GpuVertexComponentType* = enum
    gvctUint8,
    gvctInt16,
    gvctHalf,
    gvctFloat

  GpuShaderStage* = enum
    gssVertex,
    gssFragment,
    gssCompute

  GpuUniformType* = enum
    gutVec4,
    gutMat3,
    gutMat4

  GpuSamplerAddressMode* = enum
    gsamRepeat,
    gsamMirror,
    gsamClamp,
    gsamBorder

  GpuSamplerFilter* = enum
    gsfLinear,
    gsfNearest,
    gsfAnisotropic

  GpuStorageAccess* = enum
    gsaRead,
    gsaWrite,
    gsaReadWrite

  GpuPipelineKind* = enum
    gplkGraphics,
    gplkCompute

  GpuPrimitiveTopology* = enum
    gptTriangleList,
    gptTriangleStrip,
    gptLineList,
    gptLineStrip,
    gptPointList

  GpuCullMode* = enum
    gcmNone,
    gcmFront,
    gcmBack

  GpuFrontFace* = enum
    gffClockwise,
    gffCounterClockwise

  GpuBlendFactor* = enum
    gbfZero,
    gbfOne,
    gbfSourceColor,
    gbfOneMinusSourceColor,
    gbfDestinationColor,
    gbfOneMinusDestinationColor,
    gbfSourceAlpha,
    gbfOneMinusSourceAlpha,
    gbfDestinationAlpha,
    gbfOneMinusDestinationAlpha

  GpuBlendOperation* = enum
    gboAdd,
    gboSubtract,
    gboReverseSubtract,
    gboMinimum,
    gboMaximum

  GpuColorChannel* = enum
    gccRed,
    gccGreen,
    gccBlue,
    gccAlpha

  GpuVertexAttribute* = object
    semantic*: GpuVertexSemantic
    components*: uint8
    componentType*: GpuVertexComponentType
    normalized*: bool
    asInteger*: bool

  GpuNamespaceId* = distinct uint64
  GpuResourceId* = distinct uint64
  GpuReadbackId* = distinct uint64
  GpuBackendResourceId* = distinct uint64

  GpuTextureDescriptor* = object
    width*, height*: uint32
    format*: GpuTextureFormat
    usage*: set[GpuTextureUsage]
    label*: string

  GpuBufferDescriptor* = object
    byteSize*: uint64
    role*: GpuBufferRole
    access*: GpuBufferAccess
    indexFormat*: GpuIndexFormat
    vertexLayout*: seq[GpuVertexAttribute]
    label*: string

  GpuRenderTargetDescriptor* = object
    width*, height*: uint32
    format*: GpuTextureFormat
    usage*: set[GpuTextureUsage]
    label*: string

  GpuShaderDescriptor* = object
    stage*: GpuShaderStage
    label*: string

  GpuUniformDescriptor* = object
    name*: string
    uniformType*: GpuUniformType
    arrayLength*: uint16
    label*: string

  GpuSamplerDescriptor* = object
    name*: string
    addressU*, addressV*, addressW*: GpuSamplerAddressMode
    minFilter*, magFilter*, mipFilter*: GpuSamplerFilter
    borderColorIndex*: uint8
    label*: string

  GpuBlendState* = object
    enabled*: bool
    sourceColor*, destinationColor*: GpuBlendFactor
    colorOperation*: GpuBlendOperation
    sourceAlpha*, destinationAlpha*: GpuBlendFactor
    alphaOperation*: GpuBlendOperation
    writeMask*: set[GpuColorChannel]

  GpuGraphicsPipelineDescriptor* = object
    vertexShader*, fragmentShader*: GpuResourceHandle
    vertexLayout*: seq[GpuVertexAttribute]
    colorFormat*: GpuTextureFormat
    topology*: GpuPrimitiveTopology
    cullMode*: GpuCullMode
    frontFace*: GpuFrontFace
    blend*: GpuBlendState
    label*: string

  GpuComputePipelineDescriptor* = object
    computeShader*: GpuResourceHandle
    label*: string

  GpuViewport* = object
    x*, y*: uint32
    width*, height*: uint32

  GpuClearColor* = object
    red*, green*, blue*, alpha*: float32

  GpuGraphicsPassDescriptor* = object
    viewport*: GpuViewport
    scissorEnabled*: bool
    scissor*: GpuViewport
    clearColorEnabled*: bool
    clearColor*: GpuClearColor
    renderTarget*: GpuResourceHandle

  GpuUniformBinding* = object
    uniform*: GpuResourceHandle
    values*: seq[float32]

  GpuTextureBinding* = object
    stage*: uint8
    sampler*: GpuResourceHandle
    texture*: GpuResourceHandle

  GpuStorageImageBinding* = object
    stage*: uint8
    texture*: GpuResourceHandle
    access*: GpuStorageAccess
    mip*: uint8

  GpuBindingSet* = object
    uniforms*: seq[GpuUniformBinding]
    textures*: seq[GpuTextureBinding]
    storageImages*: seq[GpuStorageImageBinding]

  GpuDrawCommand* = object
    pipeline*: GpuResourceHandle
    vertexBuffer*: GpuResourceHandle
    firstVertex*, vertexCount*: uint32
    indexBuffer*: GpuResourceHandle
    firstIndex*, indexCount*: uint32
    depth*: uint32
    bindings*: GpuBindingSet

  GpuComputeCommand* = object
    pipeline*: GpuResourceHandle
    groupsX*, groupsY*, groupsZ*: uint32
    bindings*: GpuBindingSet

  GpuTextureCopyRegion* = object
    sourceX*, sourceY*: uint32
    destinationX*, destinationY*: uint32
    width*, height*: uint32

  GpuReadbackState* = enum
    grsInvalid,
    grsPending,
    grsReady

  GpuReadbackHandle* = object
    namespace*: GpuNamespaceId
    readback*: GpuReadbackId
    generation*: uint64

  GpuReadbackData* = object
    width*, height*: uint32
    format*: GpuTextureFormat
    rowStride*: uint32
    pixels*: seq[byte]

  GpuBackendUniformBinding* = object
    resource*: GpuBackendResourceId
    descriptor*: GpuUniformDescriptor
    values*: seq[float32]

  GpuBackendTextureBinding* = object
    stage*: uint8
    sampler*, texture*: GpuBackendResourceId
    samplerDescriptor*: GpuSamplerDescriptor

  GpuBackendStorageImageBinding* = object
    stage*: uint8
    texture*: GpuBackendResourceId
    format*: GpuTextureFormat
    access*: GpuStorageAccess
    mip*: uint8

  GpuBackendBindingSet* = object
    uniforms*: seq[GpuBackendUniformBinding]
    textures*: seq[GpuBackendTextureBinding]
    storageImages*: seq[GpuBackendStorageImageBinding]

  GpuHostConfig* = object
    width*, height*: uint32
    resetFlags*: uint32
    presentation*: bool
    viewIdBase*, viewIdCount*: uint16

  GpuBackendInfo* = object
    rendererName*: string
    computeSupported*: bool
    textureCopySupported*: bool
    textureReadbackSupported*: bool
    homogeneousDepth*: bool
    originBottomLeft*: bool
    maxTextureSize*: uint32

  GpuResourceBudget* = object
    persistentBytes*: uint64
    transientBytesPerFrame*: uint64
    readbackBytesPerFrame*: uint64
    workUnitsPerFrame*: uint32
    maxResources*: uint32

  GpuResourceUsage* = object
    persistentBytes*: uint64
    transientBytes*: uint64
    readbackBytes*: uint64
    workUnits*: uint32
    resourceCount*: uint32

  GpuResourceHandle* = object
    namespace*: GpuNamespaceId
    resource*: GpuResourceId
    generation*: uint64
    kind*: GpuResourceKind

  GpuFrameToken* = object
    number*: uint64
    generation*: uint64

  GpuBackendContext* = ref object of RootObj

  GpuBackendOpenProc* = proc(
    context: GpuBackendContext;
    config: GpuHostConfig;
    info: var GpuBackendInfo
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendFrameProc* = proc(
    context: GpuBackendContext;
    frameNumber: uint64
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendResizeProc* = proc(
    context: GpuBackendContext;
    width, height: uint32;
    resetFlags: uint32
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendRestoreProc* = proc(
    context: GpuBackendContext;
    info: var GpuBackendInfo
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendCloseProc* = proc(
    context: GpuBackendContext
  ) {.nimcall, raises: [].}

  GpuBackendCreateTextureProc* = proc(
    context: GpuBackendContext;
    descriptor: GpuTextureDescriptor;
    initialData: seq[byte];
    resource: var GpuBackendResourceId
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendCreateBufferProc* = proc(
    context: GpuBackendContext;
    descriptor: GpuBufferDescriptor;
    initialData: seq[byte];
    resource: var GpuBackendResourceId
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendUpdateBufferProc* = proc(
    context: GpuBackendContext;
    resource: GpuBackendResourceId;
    descriptor: GpuBufferDescriptor;
    offsetBytes: uint64;
    data: seq[byte]
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendCreateRenderTargetProc* = proc(
    context: GpuBackendContext;
    descriptor: GpuRenderTargetDescriptor;
    resource: var GpuBackendResourceId
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendCreateShaderProc* = proc(
    context: GpuBackendContext;
    descriptor: GpuShaderDescriptor;
    bytecode: seq[byte];
    resource: var GpuBackendResourceId
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendCreateUniformProc* = proc(
    context: GpuBackendContext;
    descriptor: GpuUniformDescriptor;
    resource: var GpuBackendResourceId
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendCreateSamplerProc* = proc(
    context: GpuBackendContext;
    descriptor: GpuSamplerDescriptor;
    resource: var GpuBackendResourceId
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendCreateGraphicsPipelineProc* = proc(
    context: GpuBackendContext;
    descriptor: GpuGraphicsPipelineDescriptor;
    vertexShader, fragmentShader: GpuBackendResourceId;
    resource: var GpuBackendResourceId
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendCreateComputePipelineProc* = proc(
    context: GpuBackendContext;
    descriptor: GpuComputePipelineDescriptor;
    computeShader: GpuBackendResourceId;
    resource: var GpuBackendResourceId
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendBeginGraphicsPassProc* = proc(
    context: GpuBackendContext;
    viewId: uint16;
    pass: GpuGraphicsPassDescriptor;
    renderTarget: GpuBackendResourceId
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendSubmitDrawProc* = proc(
    context: GpuBackendContext;
    viewId: uint16;
    pipeline, vertexBuffer, indexBuffer: GpuBackendResourceId;
    pipelineDescriptor: GpuGraphicsPipelineDescriptor;
    vertexDescriptor, indexDescriptor: GpuBufferDescriptor;
    bindings: GpuBackendBindingSet;
    command: GpuDrawCommand
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendDispatchProc* = proc(
    context: GpuBackendContext;
    viewId: uint16;
    pipeline: GpuBackendResourceId;
    bindings: GpuBackendBindingSet;
    command: GpuComputeCommand
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendCopyTextureProc* = proc(
    context: GpuBackendContext;
    viewId: uint16;
    source: GpuBackendResourceId;
    sourceKind: GpuResourceKind;
    destination: GpuBackendResourceId;
    region: GpuTextureCopyRegion
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendRequestReadbackProc* = proc(
    context: GpuBackendContext;
    texture: GpuBackendResourceId;
    descriptor: GpuTextureDescriptor;
    destination: pointer;
    destinationBytes: uint64;
    completionToken: var uint64
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendPollReadbackProc* = proc(
    context: GpuBackendContext;
    completionToken: uint64;
    ready: var bool
  ): GpuBackendStatus {.nimcall, raises: [].}

  GpuBackendDestroyResourceProc* = proc(
    context: GpuBackendContext;
    resource: GpuBackendResourceId;
    kind: GpuResourceKind
  ) {.nimcall, raises: [].}

  GpuBackendVTable* = object
    apiVersion*: uint32
    provider*: GpuProviderKind
    context*: GpuBackendContext
    openOwned*: GpuBackendOpenProc
    attachBorrowed*: GpuBackendOpenProc
    beginFrame*: GpuBackendFrameProc
    endFrame*: GpuBackendFrameProc
    resize*: GpuBackendResizeProc
    restore*: GpuBackendRestoreProc
    createTexture*: GpuBackendCreateTextureProc
    createBuffer*: GpuBackendCreateBufferProc
    updateBuffer*: GpuBackendUpdateBufferProc
    createRenderTarget*: GpuBackendCreateRenderTargetProc
    createShader*: GpuBackendCreateShaderProc
    createUniform*: GpuBackendCreateUniformProc
    createSampler*: GpuBackendCreateSamplerProc
    createGraphicsPipeline*: GpuBackendCreateGraphicsPipelineProc
    createComputePipeline*: GpuBackendCreateComputePipelineProc
    beginGraphicsPass*: GpuBackendBeginGraphicsPassProc
    submitDraw*: GpuBackendSubmitDrawProc
    dispatch*: GpuBackendDispatchProc
    copyTexture*: GpuBackendCopyTextureProc
    requestReadback*: GpuBackendRequestReadbackProc
    pollReadback*: GpuBackendPollReadbackProc
    destroyResource*: GpuBackendDestroyResourceProc
    closeOwned*: GpuBackendCloseProc
    detachBorrowed*: GpuBackendCloseProc

  GpuResourceEntry = object
    kind: GpuResourceKind
    bytes: uint64
    generation: uint64
    backendResource: GpuBackendResourceId
    bufferDescriptor: GpuBufferDescriptor
    textureDescriptor: GpuTextureDescriptor
    renderTargetDescriptor: GpuRenderTargetDescriptor
    shaderDescriptor: GpuShaderDescriptor
    uniformDescriptor: GpuUniformDescriptor
    samplerDescriptor: GpuSamplerDescriptor
    graphicsPipelineDescriptor: GpuGraphicsPipelineDescriptor
    computePipelineDescriptor: GpuComputePipelineDescriptor
    pipelineKind: GpuPipelineKind
    dependencies: seq[GpuResourceId]
    dependentCount: uint32

  GpuResolvedDrawCommand = object
    pipeline, vertexBuffer, indexBuffer: GpuBackendResourceId
    pipelineDescriptor: GpuGraphicsPipelineDescriptor
    vertexDescriptor, indexDescriptor: GpuBufferDescriptor
    bindings: GpuBackendBindingSet

  GpuReadbackEntry = object
    generation: uint64
    texture: GpuResourceId
    descriptor: GpuTextureDescriptor
    completionToken: uint64
    pixels: seq[byte]
    ready: bool

  GpuNamespaceEntry = object
    name: string
    budget: GpuResourceBudget
    usage: GpuResourceUsage
    nextResourceId: uint64
    nextReadbackId: uint64
    resources: Table[GpuResourceId, GpuResourceEntry]
    readbacks: Table[GpuReadbackId, GpuReadbackEntry]

  GpuHost* = ref object
    backend: GpuBackendVTable
    ownershipValue: GpuHostOwnership
    stateValue: GpuHostState
    configValue: GpuHostConfig
    infoValue: GpuBackendInfo
    generationValue: uint64
    frameNumber: uint64
    activeFrame: bool
    nextViewOffset: uint16
    nextNamespaceId: uint64
    namespaces: Table[GpuNamespaceId, GpuNamespaceEntry]

proc `==`*(a, b: GpuNamespaceId): bool {.borrow.}
proc hash*(id: GpuNamespaceId): Hash {.borrow.}
proc `==`*(a, b: GpuResourceId): bool {.borrow.}
proc hash*(id: GpuResourceId): Hash {.borrow.}
proc `==`*(a, b: GpuReadbackId): bool {.borrow.}
proc hash*(id: GpuReadbackId): Hash {.borrow.}

proc namespaceIdValue*(id: GpuNamespaceId): uint64 {.inline.} = uint64(id)
proc resourceIdValue*(id: GpuResourceId): uint64 {.inline.} = uint64(id)
proc readbackIdValue*(id: GpuReadbackId): uint64 {.inline.} = uint64(id)
proc backendResourceIdValue*(id: GpuBackendResourceId): uint64 {.inline.} =
  uint64(id)

proc opaqueGpuBlendState*(): GpuBlendState =
  GpuBlendState(writeMask: {gccRed, gccGreen, gccBlue, gccAlpha})

proc alphaGpuBlendState*(): GpuBlendState =
  GpuBlendState(
    enabled: true,
    sourceColor: gbfSourceAlpha,
    destinationColor: gbfOneMinusSourceAlpha,
    colorOperation: gboAdd,
    sourceAlpha: gbfOne,
    destinationAlpha: gbfOneMinusSourceAlpha,
    alphaOperation: gboAdd,
    writeMask: {gccRed, gccGreen, gccBlue, gccAlpha}
  )

proc statusMessage(status: GpuBackendStatus): string =
  case status
  of gbsOk: "ok"
  of gbsUnavailable: "GPU backend is unavailable"
  of gbsUnsupported: "GPU operation is unsupported"
  of gbsInvalidConfiguration: "GPU configuration is invalid"
  of gbsDeviceLost: "GPU device is lost"
  of gbsFailed: "GPU backend operation failed"

proc requireHost(host: GpuHost) =
  if host.isNil:
    raise newException(GpuHostError, "GPU host cannot be nil")

proc raiseForStatus(status: GpuBackendStatus) =
  if status != gbsOk:
    raise newException(GpuHostError, status.statusMessage)

proc validateConfig(config: GpuHostConfig) =
  if config.presentation and (config.width == 0 or config.height == 0):
    raise newException(
      GpuHostError,
      "a presentation GPU host requires a non-zero viewport"
    )
  let viewCount =
    if config.viewIdCount == 0: maxGpuViewCount
    else: config.viewIdCount
  if uint32(config.viewIdBase) + uint32(viewCount) > uint32(maxGpuViewCount):
    raise newException(GpuHostError, "GPU view identifier range is invalid")

proc openGpuHost*(
    backend: GpuBackendVTable;
    ownership: GpuHostOwnership;
    config = GpuHostConfig()
): GpuHost =
  var normalizedConfig = config
  if normalizedConfig.viewIdCount == 0:
    normalizedConfig.viewIdCount = maxGpuViewCount
  normalizedConfig.validateConfig()
  if backend.apiVersion != gpuHostApiVersion:
    raise newException(GpuHostError, "GPU backend API version is incompatible")
  if backend.context.isNil:
    raise newException(GpuHostError, "GPU backend context cannot be nil")

  let openProc =
    if ownership == ghoOwned: backend.openOwned
    else: backend.attachBorrowed
  if openProc.isNil:
    raise newException(GpuHostError, "GPU backend does not support this ownership mode")

  result = GpuHost(
    backend: backend,
    ownershipValue: ownership,
    stateValue: ghsOpening,
    configValue: normalizedConfig,
    generationValue: 1'u64,
    nextNamespaceId: 1'u64,
    namespaces: initTable[GpuNamespaceId, GpuNamespaceEntry]()
  )

  var info: GpuBackendInfo
  let status = openProc(backend.context, normalizedConfig, info)
  if status != gbsOk:
    result.stateValue = ghsClosed
    case ownership
    of ghoOwned:
      if not backend.closeOwned.isNil:
        backend.closeOwned(backend.context)
    of ghoBorrowed:
      if not backend.detachBorrowed.isNil:
        backend.detachBorrowed(backend.context)
    raiseForStatus(status)
  result.infoValue = info
  result.stateValue = ghsReady

proc provider*(host: GpuHost): GpuProviderKind =
  host.requireHost()
  host.backend.provider

proc ownership*(host: GpuHost): GpuHostOwnership =
  host.requireHost()
  host.ownershipValue

proc state*(host: GpuHost): GpuHostState =
  host.requireHost()
  host.stateValue

proc config*(host: GpuHost): GpuHostConfig =
  host.requireHost()
  host.configValue

proc backendInfo*(host: GpuHost): GpuBackendInfo =
  host.requireHost()
  host.infoValue

proc generation*(host: GpuHost): uint64 =
  host.requireHost()
  host.generationValue

proc isReady*(host: GpuHost): bool =
  not host.isNil and host.stateValue == ghsReady

proc destroyNamespaceResources(host: GpuHost; id: GpuNamespaceId) =
  if id notin host.namespaces:
    return
  var resourceIds: seq[GpuResourceId]
  for resourceId in host.namespaces[id].resources.keys:
    resourceIds.add resourceId
  resourceIds.sort(proc(a, b: GpuResourceId): int =
    cmp(resourceIdValue(b), resourceIdValue(a)))
  if not host.backend.destroyResource.isNil:
    for resourceId in resourceIds:
      let entry = host.namespaces[id].resources[resourceId]
      if entry.backendResource.backendResourceIdValue != 0:
        host.backend.destroyResource(
          host.backend.context,
          entry.backendResource,
          entry.kind
        )

proc close*(host: GpuHost) =
  if host.isNil or host.stateValue == ghsClosed:
    return
  if host.ownershipValue == ghoBorrowed:
    for id, entry in host.namespaces.pairs:
      discard id
      if entry.readbacks.len != 0:
        raise newException(
          GpuHostError,
          "a borrowed GPU host cannot detach with retained readbacks"
        )

  host.activeFrame = false
  var namespaceIds: seq[GpuNamespaceId]
  for id in host.namespaces.keys:
    namespaceIds.add id
  namespaceIds.sort(proc(a, b: GpuNamespaceId): int =
    cmp(namespaceIdValue(b), namespaceIdValue(a)))
  for id in namespaceIds:
    host.destroyNamespaceResources(id)
  case host.ownershipValue
  of ghoOwned:
    if not host.backend.closeOwned.isNil:
      host.backend.closeOwned(host.backend.context)
  of ghoBorrowed:
    if not host.backend.detachBorrowed.isNil:
      host.backend.detachBorrowed(host.backend.context)
  # Readback destinations must remain alive until the backend has drained its
  # queued work during shutdown or detach.
  host.namespaces.clear()
  host.stateValue = ghsClosed

proc invalidateResources(host: GpuHost) =
  for id, entry in host.namespaces.mpairs:
    discard id
    entry.resources.clear()
    entry.readbacks.clear()
    entry.usage = GpuResourceUsage()

proc enterDeviceLost(host: GpuHost) =
  host.activeFrame = false
  host.stateValue = ghsDeviceLost
  inc host.generationValue
  if host.generationValue == 0:
    raise newException(GpuHostError, "GPU generation space exhausted")
  host.invalidateResources()

proc beginGpuFrame*(host: GpuHost): GpuFrameToken =
  host.requireHost()
  if host.stateValue != ghsReady:
    raise newException(GpuHostError, "GPU host is not ready")
  if host.activeFrame:
    raise newException(GpuHostError, "a GPU frame is already active")

  inc host.frameNumber
  if host.frameNumber == 0:
    raise newException(GpuHostError, "GPU frame number space exhausted")
  if not host.backend.beginFrame.isNil:
    let status = host.backend.beginFrame(host.backend.context, host.frameNumber)
    if status == gbsDeviceLost:
      host.enterDeviceLost()
    raiseForStatus(status)

  for id, entry in host.namespaces.mpairs:
    discard id
    entry.usage.transientBytes = 0
    entry.usage.readbackBytes = 0
    entry.usage.workUnits = 0

  host.nextViewOffset = 0
  host.activeFrame = true
  GpuFrameToken(number: host.frameNumber, generation: host.generationValue)

proc endGpuFrame*(host: GpuHost; token: GpuFrameToken) =
  host.requireHost()
  if not host.activeFrame:
    raise newException(GpuHostError, "no GPU frame is active")
  if token.number != host.frameNumber or token.generation != host.generationValue:
    raise newException(GpuHostError, "GPU frame token is stale")

  if not host.backend.endFrame.isNil:
    let status = host.backend.endFrame(host.backend.context, host.frameNumber)
    host.activeFrame = false
    if status == gbsDeviceLost:
      host.enterDeviceLost()
    raiseForStatus(status)
  host.activeFrame = false

proc resizeGpuHost*(host: GpuHost; width, height: uint32) =
  host.requireHost()
  if host.stateValue != ghsReady:
    raise newException(GpuHostError, "GPU host is not ready")
  if not host.configValue.presentation:
    raise newException(GpuHostError, "compute-only GPU hosts cannot be resized")
  if width == 0 or height == 0:
    raise newException(GpuHostError, "GPU viewport must be non-zero")
  if host.activeFrame:
    raise newException(GpuHostError, "GPU host cannot resize during a frame")
  if host.backend.resize.isNil:
    raise newException(GpuHostError, "GPU backend does not support resize")

  let status = host.backend.resize(
    host.backend.context,
    width,
    height,
    host.configValue.resetFlags
  )
  if status == gbsDeviceLost:
    host.enterDeviceLost()
  raiseForStatus(status)
  host.configValue.width = width
  host.configValue.height = height

proc markGpuDeviceLost*(host: GpuHost): bool =
  host.requireHost()
  if host.stateValue != ghsReady:
    return false
  host.enterDeviceLost()
  true

proc restoreGpuHost*(host: GpuHost) =
  host.requireHost()
  if host.stateValue != ghsDeviceLost:
    raise newException(GpuHostError, "GPU host is not device-lost")
  if host.backend.restore.isNil:
    raise newException(GpuHostError, "GPU backend cannot restore the device")

  var restoredInfo = host.infoValue
  let status = host.backend.restore(host.backend.context, restoredInfo)
  raiseForStatus(status)
  host.infoValue = restoredInfo
  host.stateValue = ghsReady

proc createGpuNamespace*(
    host: GpuHost;
    name: string;
    budget: GpuResourceBudget
): GpuNamespaceId =
  host.requireHost()
  if host.stateValue == ghsClosed:
    raise newException(GpuHostError, "GPU host is closed")
  if host.stateValue != ghsReady:
    raise newException(GpuHostError, "GPU host is not ready")
  if name.len == 0 or name.len > maxGpuNamespaceNameBytes:
    raise newException(GpuHostError, "GPU namespace name length is invalid")
  for id, entry in host.namespaces.pairs:
    discard id
    if entry.name == name:
      raise newException(GpuHostError, "GPU namespace name is already registered")
  if budget.maxResources == 0:
    raise newException(GpuHostError, "GPU namespace must allow at least one resource")
  if host.nextNamespaceId == 0:
    raise newException(GpuHostError, "GPU namespace identifier space exhausted")

  result = GpuNamespaceId(host.nextNamespaceId)
  inc host.nextNamespaceId
  host.namespaces[result] = GpuNamespaceEntry(
    name: name,
    budget: budget,
    nextResourceId: 1'u64,
    nextReadbackId: 1'u64,
    resources: initTable[GpuResourceId, GpuResourceEntry](),
    readbacks: initTable[GpuReadbackId, GpuReadbackEntry]()
  )

proc hasGpuNamespace*(host: GpuHost; id: GpuNamespaceId): bool =
  not host.isNil and id in host.namespaces

proc gpuNamespaceName*(host: GpuHost; id: GpuNamespaceId): string =
  host.requireHost()
  if id notin host.namespaces:
    return ""
  host.namespaces[id].name

proc gpuNamespaceUsage*(host: GpuHost; id: GpuNamespaceId): GpuResourceUsage =
  host.requireHost()
  if id notin host.namespaces:
    raise newException(GpuHostError, "unknown GPU namespace")
  host.namespaces[id].usage

proc closeGpuNamespace*(host: GpuHost; id: GpuNamespaceId): bool =
  host.requireHost()
  if id notin host.namespaces:
    return false
  if host.activeFrame:
    raise newException(
      GpuHostError,
      "GPU namespace cannot close during an active frame"
    )
  if host.namespaces[id].readbacks.len != 0:
    raise newException(
      GpuHostError,
      "GPU namespace cannot close with retained readbacks"
    )
  host.destroyNamespaceResources(id)
  host.namespaces.del(id)
  true

proc fits(current, addition, limit: uint64): bool {.inline.} =
  current <= limit and addition <= limit - current

proc ensureResourceCapacity(
    entry: GpuNamespaceEntry;
    bytes: uint64
) =
  if entry.usage.resourceCount >= entry.budget.maxResources:
    raise newException(GpuHostError, "GPU namespace resource count exceeded")
  if not fits(entry.usage.persistentBytes, bytes, entry.budget.persistentBytes):
    raise newException(GpuHostError, "GPU namespace persistent budget exceeded")
  if entry.nextResourceId == 0:
    raise newException(GpuHostError, "GPU resource identifier space exhausted")

proc insertGpuResource(
    host: GpuHost;
    namespace: GpuNamespaceId;
    kind: GpuResourceKind;
    bytes: uint64;
    backendResource = GpuBackendResourceId(0);
    bufferDescriptor = GpuBufferDescriptor();
    textureDescriptor = GpuTextureDescriptor();
    renderTargetDescriptor = GpuRenderTargetDescriptor();
    shaderDescriptor = GpuShaderDescriptor();
    uniformDescriptor = GpuUniformDescriptor();
    samplerDescriptor = GpuSamplerDescriptor();
    graphicsPipelineDescriptor = GpuGraphicsPipelineDescriptor();
    computePipelineDescriptor = GpuComputePipelineDescriptor();
    pipelineKind = gplkGraphics;
    dependencies: seq[GpuResourceId] = @[]
): GpuResourceHandle =
  var entry = host.namespaces[namespace]
  entry.ensureResourceCapacity(bytes)
  let resource = GpuResourceId(entry.nextResourceId)
  inc entry.nextResourceId
  entry.resources[resource] = GpuResourceEntry(
    kind: kind,
    bytes: bytes,
    generation: host.generationValue,
    backendResource: backendResource,
    bufferDescriptor: bufferDescriptor,
    textureDescriptor: textureDescriptor,
    renderTargetDescriptor: renderTargetDescriptor,
    shaderDescriptor: shaderDescriptor,
    uniformDescriptor: uniformDescriptor,
    samplerDescriptor: samplerDescriptor,
    graphicsPipelineDescriptor: graphicsPipelineDescriptor,
    computePipelineDescriptor: computePipelineDescriptor,
    pipelineKind: pipelineKind,
    dependencies: dependencies
  )
  entry.usage.persistentBytes += bytes
  inc entry.usage.resourceCount
  host.namespaces[namespace] = entry
  GpuResourceHandle(
    namespace: namespace,
    resource: resource,
    generation: host.generationValue,
    kind: kind
  )

proc reserveGpuResource*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    kind: GpuResourceKind;
    bytes: uint64
): GpuResourceHandle =
  host.requireHost()
  if host.stateValue != ghsReady:
    raise newException(GpuHostError, "GPU host is not ready")
  if host.activeFrame:
    raise newException(
      GpuHostError,
      "retained GPU resources cannot be reserved during an active frame"
    )
  if namespace notin host.namespaces:
    raise newException(GpuHostError, "unknown GPU namespace")

  host.insertGpuResource(namespace, kind, bytes)

proc textureBytes(descriptor: GpuTextureDescriptor): uint64 =
  let bytesPerPixel =
    case descriptor.format
    of gtfR8: 1'u64
    of gtfRgba8, gtfBgra8: 4'u64
  let width = uint64(descriptor.width)
  let height = uint64(descriptor.height)
  if width != 0 and height > high(uint64) div width:
    raise newException(GpuHostError, "GPU texture dimensions overflow")
  let pixels = width * height
  if pixels != 0 and bytesPerPixel > high(uint64) div pixels:
    raise newException(GpuHostError, "GPU texture byte size overflow")
  pixels * bytesPerPixel

proc renderTargetBytes(descriptor: GpuRenderTargetDescriptor): uint64 =
  GpuTextureDescriptor(
    width: descriptor.width,
    height: descriptor.height,
    format: descriptor.format
  ).textureBytes()

proc vertexComponentBytes(value: GpuVertexComponentType): uint64 =
  case value
  of gvctUint8: 1'u64
  of gvctInt16, gvctHalf: 2'u64
  of gvctFloat: 4'u64

proc vertexStride*(descriptor: GpuBufferDescriptor): uint64 =
  if descriptor.role != gbrVertex:
    return 0
  for attribute in descriptor.vertexLayout:
    result += uint64(attribute.components) *
      attribute.componentType.vertexComponentBytes()

proc validateVertexLayout(layout: seq[GpuVertexAttribute]): uint64 =
  if layout.len == 0:
    raise newException(GpuHostError, "GPU vertex layout cannot be empty")
  var semantics: set[GpuVertexSemantic]
  for attribute in layout:
    if attribute.components < 1 or attribute.components > 4:
      raise newException(GpuHostError, "GPU vertex component count is invalid")
    if (attribute.normalized or attribute.asInteger) and
        attribute.componentType notin {gvctUint8, gvctInt16}:
      raise newException(
        GpuHostError,
        "GPU vertex fixed-point flags require an integer component type"
      )
    if attribute.semantic in semantics:
      raise newException(GpuHostError, "GPU vertex semantic is duplicated")
    semantics.incl attribute.semantic
    result += uint64(attribute.components) *
      attribute.componentType.vertexComponentBytes()
  if result == 0 or result > uint64(high(uint16)):
    raise newException(GpuHostError, "GPU vertex layout stride is invalid")

proc bufferElementBytes(descriptor: GpuBufferDescriptor): uint64 =
  case descriptor.role
  of gbrVertex:
    descriptor.vertexStride()
  of gbrIndex:
    if descriptor.indexFormat == gifUint16: 2'u64
    else: 4'u64

proc validateBufferDescriptor(
    descriptor: GpuBufferDescriptor;
    initialData: seq[byte]
) =
  if descriptor.byteSize == 0:
    raise newException(GpuHostError, "GPU buffer size must be non-zero")
  if descriptor.byteSize > uint64(high(uint32)):
    raise newException(GpuHostError, "GPU buffer exceeds backend-neutral limits")
  if descriptor.label.len > maxGpuResourceLabelBytes:
    raise newException(GpuHostError, "GPU resource label is too long")
  if uint64(initialData.len) > descriptor.byteSize:
    raise newException(GpuHostError, "GPU buffer initial data exceeds its capacity")
  if descriptor.access == gbaStatic and uint64(initialData.len) != descriptor.byteSize:
    raise newException(GpuHostError, "static GPU buffers require complete initial data")
  if initialData.len != 0 and uint64(initialData.len) != descriptor.byteSize:
    raise newException(GpuHostError, "GPU buffer initial data must fill its capacity")

  case descriptor.role
  of gbrVertex:
    let stride = descriptor.vertexLayout.validateVertexLayout()
    if descriptor.byteSize mod stride != 0:
      raise newException(GpuHostError, "GPU vertex buffer size does not match its layout")
  of gbrIndex:
    if descriptor.vertexLayout.len != 0:
      raise newException(GpuHostError, "index GPU buffers cannot declare a vertex layout")
    if descriptor.byteSize mod descriptor.bufferElementBytes() != 0:
      raise newException(GpuHostError, "GPU index buffer size is not aligned")

proc validateBufferUpdate(
    descriptor: GpuBufferDescriptor;
    offsetBytes: uint64;
    data: seq[byte]
) =
  if descriptor.access != gbaDynamic:
    raise newException(GpuHostError, "static GPU buffers cannot be updated")
  if data.len == 0:
    raise newException(GpuHostError, "GPU buffer update cannot be empty")
  let elementBytes = descriptor.bufferElementBytes()
  if offsetBytes mod elementBytes != 0 or uint64(data.len) mod elementBytes != 0:
    raise newException(GpuHostError, "GPU buffer update is not element-aligned")
  if offsetBytes > descriptor.byteSize or
      uint64(data.len) > descriptor.byteSize - offsetBytes:
    raise newException(GpuHostError, "GPU buffer update exceeds its capacity")

proc createGpuTexture*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    descriptor: GpuTextureDescriptor;
    initialData: seq[byte] = @[]
): GpuResourceHandle =
  host.requireHost()
  if host.stateValue != ghsReady:
    raise newException(GpuHostError, "GPU host is not ready")
  if host.activeFrame:
    raise newException(
      GpuHostError,
      "GPU texture creation is not allowed during an active frame"
    )
  if namespace notin host.namespaces:
    raise newException(GpuHostError, "unknown GPU namespace")
  if descriptor.width == 0 or descriptor.height == 0:
    raise newException(GpuHostError, "GPU texture dimensions must be non-zero")
  if host.infoValue.maxTextureSize != 0 and
      (descriptor.width > host.infoValue.maxTextureSize or
       descriptor.height > host.infoValue.maxTextureSize):
    raise newException(GpuHostError, "GPU texture exceeds backend limits")
  if descriptor.usage == {}:
    raise newException(GpuHostError, "GPU texture usage cannot be empty")
  if gtuReadback in descriptor.usage:
    if not host.infoValue.textureReadbackSupported:
      raise newException(GpuHostError, "GPU texture readback is not supported")
    if descriptor.usage != {gtuBlitDestination, gtuReadback}:
      raise newException(
        GpuHostError,
        "GPU readback textures only support blit-destination and readback usage"
      )
    if initialData.len != 0:
      raise newException(
        GpuHostError,
        "GPU readback textures cannot have initial data"
      )
  if descriptor.label.len > maxGpuResourceLabelBytes:
    raise newException(GpuHostError, "GPU resource label is too long")
  let bytes = descriptor.textureBytes()
  if initialData.len != 0 and uint64(initialData.len) != bytes:
    raise newException(GpuHostError, "GPU texture initial data size is invalid")
  host.namespaces[namespace].ensureResourceCapacity(bytes)
  if host.backend.createTexture.isNil or host.backend.destroyResource.isNil:
    raise newException(GpuHostError, "GPU backend does not support textures")

  var backendResource: GpuBackendResourceId
  let status = host.backend.createTexture(
    host.backend.context,
    descriptor,
    initialData,
    backendResource
  )
  if status == gbsDeviceLost:
    host.enterDeviceLost()
  raiseForStatus(status)
  if backendResource.backendResourceIdValue == 0:
    raise newException(GpuHostError, "GPU backend returned an invalid resource")
  host.insertGpuResource(
    namespace,
    grkTexture,
    bytes,
    backendResource,
    textureDescriptor = descriptor
  )

proc createGpuBuffer*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    descriptor: GpuBufferDescriptor;
    initialData: seq[byte] = @[]
): GpuResourceHandle =
  host.requireHost()
  if host.stateValue != ghsReady:
    raise newException(GpuHostError, "GPU host is not ready")
  if host.activeFrame:
    raise newException(
      GpuHostError,
      "GPU buffer creation is not allowed during an active frame"
    )
  if namespace notin host.namespaces:
    raise newException(GpuHostError, "unknown GPU namespace")
  descriptor.validateBufferDescriptor(initialData)
  host.namespaces[namespace].ensureResourceCapacity(descriptor.byteSize)
  if host.backend.createBuffer.isNil or host.backend.destroyResource.isNil:
    raise newException(GpuHostError, "GPU backend does not support buffers")

  var backendResource: GpuBackendResourceId
  let status = host.backend.createBuffer(
    host.backend.context,
    descriptor,
    initialData,
    backendResource
  )
  if status == gbsDeviceLost:
    host.enterDeviceLost()
  raiseForStatus(status)
  if backendResource.backendResourceIdValue == 0:
    raise newException(GpuHostError, "GPU backend returned an invalid resource")
  host.insertGpuResource(
    namespace,
    grkBuffer,
    descriptor.byteSize,
    backendResource,
    descriptor
  )

proc createGpuRenderTarget*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    descriptor: GpuRenderTargetDescriptor
): GpuResourceHandle =
  host.requireHost()
  if host.stateValue != ghsReady:
    raise newException(GpuHostError, "GPU host is not ready")
  if host.activeFrame:
    raise newException(
      GpuHostError,
      "GPU render target creation is not allowed during an active frame"
    )
  if namespace notin host.namespaces:
    raise newException(GpuHostError, "unknown GPU namespace")
  if descriptor.width == 0 or descriptor.height == 0:
    raise newException(GpuHostError, "GPU render target dimensions must be non-zero")
  if host.infoValue.maxTextureSize != 0 and
      (descriptor.width > host.infoValue.maxTextureSize or
       descriptor.height > host.infoValue.maxTextureSize):
    raise newException(GpuHostError, "GPU render target exceeds backend limits")
  if gtuRenderTarget notin descriptor.usage:
    raise newException(GpuHostError, "GPU render target usage is required")
  if gtuReadback in descriptor.usage:
    raise newException(
      GpuHostError,
      "GPU render targets cannot be direct readback resources"
    )
  if descriptor.label.len > maxGpuResourceLabelBytes:
    raise newException(GpuHostError, "GPU resource label is too long")
  let bytes = descriptor.renderTargetBytes()
  host.namespaces[namespace].ensureResourceCapacity(bytes)
  if host.backend.createRenderTarget.isNil or
      host.backend.destroyResource.isNil:
    raise newException(GpuHostError, "GPU backend does not support render targets")

  var backendResource: GpuBackendResourceId
  let status = host.backend.createRenderTarget(
    host.backend.context,
    descriptor,
    backendResource
  )
  if status == gbsDeviceLost:
    host.enterDeviceLost()
  raiseForStatus(status)
  if backendResource.backendResourceIdValue == 0:
    raise newException(GpuHostError, "GPU backend returned an invalid resource")
  host.insertGpuResource(
    namespace,
    grkRenderTarget,
    bytes,
    backendResource,
    renderTargetDescriptor = descriptor
  )

proc createGpuShader*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    descriptor: GpuShaderDescriptor;
    bytecode: seq[byte]
): GpuResourceHandle =
  host.requireHost()
  if host.stateValue != ghsReady:
    raise newException(GpuHostError, "GPU host is not ready")
  if host.activeFrame:
    raise newException(
      GpuHostError,
      "GPU shader creation is not allowed during an active frame"
    )
  if namespace notin host.namespaces:
    raise newException(GpuHostError, "unknown GPU namespace")
  if bytecode.len == 0:
    raise newException(GpuHostError, "GPU shader bytecode cannot be empty")
  if uint64(bytecode.len) > uint64(high(uint32)):
    raise newException(GpuHostError, "GPU shader bytecode is too large")
  if descriptor.label.len > maxGpuResourceLabelBytes:
    raise newException(GpuHostError, "GPU resource label is too long")
  if descriptor.stage == gssCompute and not host.infoValue.computeSupported:
    raise newException(GpuHostError, "GPU compute shaders are not supported")
  let bytes = uint64(bytecode.len)
  host.namespaces[namespace].ensureResourceCapacity(bytes)
  if host.backend.createShader.isNil or host.backend.destroyResource.isNil:
    raise newException(GpuHostError, "GPU backend does not support shaders")

  var backendResource: GpuBackendResourceId
  let status = host.backend.createShader(
    host.backend.context,
    descriptor,
    bytecode,
    backendResource
  )
  if status == gbsDeviceLost:
    host.enterDeviceLost()
  raiseForStatus(status)
  if backendResource.backendResourceIdValue == 0:
    raise newException(GpuHostError, "GPU backend returned an invalid resource")
  host.insertGpuResource(
    namespace,
    grkShader,
    bytes,
    backendResource,
    shaderDescriptor = descriptor
  )

proc validateGpuBindingName(name: string) =
  if name.len == 0 or name.len > maxGpuResourceLabelBytes:
    raise newException(GpuHostError, "GPU binding name length is invalid")
  for index, character in name:
    let valid = character == '_' or
      character in {'a' .. 'z'} or
      character in {'A' .. 'Z'} or
      (index > 0 and character in {'0' .. '9'})
    if not valid:
      raise newException(GpuHostError, "GPU binding name is not a portable identifier")

proc uniformFloatCount(uniformType: GpuUniformType): uint64 =
  case uniformType
  of gutVec4: 4'u64
  of gutMat3: 9'u64
  of gutMat4: 16'u64

proc createGpuUniform*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    descriptor: GpuUniformDescriptor
): GpuResourceHandle =
  host.requireHost()
  if host.stateValue != ghsReady:
    raise newException(GpuHostError, "GPU host is not ready")
  if host.activeFrame:
    raise newException(
      GpuHostError,
      "GPU uniform creation is not allowed during an active frame"
    )
  if namespace notin host.namespaces:
    raise newException(GpuHostError, "unknown GPU namespace")
  descriptor.name.validateGpuBindingName()
  if descriptor.label.len > maxGpuResourceLabelBytes:
    raise newException(GpuHostError, "GPU resource label is too long")
  if descriptor.arrayLength == 0:
    raise newException(GpuHostError, "GPU uniform array length must be non-zero")
  let bytes = descriptor.uniformType.uniformFloatCount() *
    uint64(descriptor.arrayLength) * uint64(sizeof(float32))
  host.namespaces[namespace].ensureResourceCapacity(bytes)
  if host.backend.createUniform.isNil or host.backend.destroyResource.isNil:
    raise newException(GpuHostError, "GPU backend does not support uniforms")

  var backendResource: GpuBackendResourceId
  let status = host.backend.createUniform(
    host.backend.context,
    descriptor,
    backendResource
  )
  if status == gbsDeviceLost:
    host.enterDeviceLost()
  raiseForStatus(status)
  if backendResource.backendResourceIdValue == 0:
    raise newException(GpuHostError, "GPU backend returned an invalid resource")
  host.insertGpuResource(
    namespace,
    grkUniform,
    bytes,
    backendResource,
    uniformDescriptor = descriptor
  )

proc createGpuSampler*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    descriptor: GpuSamplerDescriptor
): GpuResourceHandle =
  host.requireHost()
  if host.stateValue != ghsReady:
    raise newException(GpuHostError, "GPU host is not ready")
  if host.activeFrame:
    raise newException(
      GpuHostError,
      "GPU sampler creation is not allowed during an active frame"
    )
  if namespace notin host.namespaces:
    raise newException(GpuHostError, "unknown GPU namespace")
  descriptor.name.validateGpuBindingName()
  if descriptor.label.len > maxGpuResourceLabelBytes:
    raise newException(GpuHostError, "GPU resource label is too long")
  if descriptor.borderColorIndex > 15:
    raise newException(GpuHostError, "GPU sampler border color index is invalid")
  if descriptor.mipFilter == gsfAnisotropic:
    raise newException(
      GpuHostError,
      "GPU sampler mip filtering cannot be anisotropic"
    )
  host.namespaces[namespace].ensureResourceCapacity(0)
  if host.backend.createSampler.isNil or host.backend.destroyResource.isNil:
    raise newException(GpuHostError, "GPU backend does not support samplers")

  var backendResource: GpuBackendResourceId
  let status = host.backend.createSampler(
    host.backend.context,
    descriptor,
    backendResource
  )
  if status == gbsDeviceLost:
    host.enterDeviceLost()
  raiseForStatus(status)
  if backendResource.backendResourceIdValue == 0:
    raise newException(GpuHostError, "GPU backend returned an invalid resource")
  host.insertGpuResource(
    namespace,
    grkSampler,
    0,
    backendResource,
    samplerDescriptor = descriptor
  )

proc isGpuResourceLive*(host: GpuHost; handle: GpuResourceHandle): bool

proc pipelineShader(
    host: GpuHost;
    namespace: GpuNamespaceId;
    handle: GpuResourceHandle;
    stage: GpuShaderStage
): GpuResourceEntry =
  if handle.namespace != namespace or not host.isGpuResourceLive(handle) or
      handle.kind != grkShader:
    raise newException(
      GpuHostError,
      "GPU pipeline shaders must be live resources in the same namespace"
    )
  result = host.namespaces[namespace].resources[handle.resource]
  if result.shaderDescriptor.stage != stage:
    raise newException(GpuHostError, "GPU pipeline shader stage is invalid")

proc validatePipelineCreation(
    host: GpuHost;
    namespace: GpuNamespaceId;
    label: string
) =
  host.requireHost()
  if host.stateValue != ghsReady:
    raise newException(GpuHostError, "GPU host is not ready")
  if host.activeFrame:
    raise newException(
      GpuHostError,
      "GPU pipeline creation is not allowed during an active frame"
    )
  if namespace notin host.namespaces:
    raise newException(GpuHostError, "unknown GPU namespace")
  if label.len > maxGpuResourceLabelBytes:
    raise newException(GpuHostError, "GPU resource label is too long")
  host.namespaces[namespace].ensureResourceCapacity(0)

proc retainPipelineDependencies(
    host: GpuHost;
    namespace: GpuNamespaceId;
    dependencies: openArray[GpuResourceId]
) =
  var entry = host.namespaces[namespace]
  for resource in dependencies:
    inc entry.resources[resource].dependentCount
  host.namespaces[namespace] = entry

proc createGpuGraphicsPipeline*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    descriptor: GpuGraphicsPipelineDescriptor
): GpuResourceHandle =
  host.validatePipelineCreation(namespace, descriptor.label)
  if descriptor.blend.writeMask == {}:
    raise newException(GpuHostError, "GPU graphics pipeline writes no color channels")
  discard descriptor.vertexLayout.validateVertexLayout()
  let vertex = host.pipelineShader(
    namespace,
    descriptor.vertexShader,
    gssVertex
  )
  let fragment = host.pipelineShader(
    namespace,
    descriptor.fragmentShader,
    gssFragment
  )
  if host.backend.createGraphicsPipeline.isNil or
      host.backend.destroyResource.isNil:
    raise newException(
      GpuHostError,
      "GPU backend does not support graphics pipelines"
    )

  var backendResource: GpuBackendResourceId
  let status = host.backend.createGraphicsPipeline(
    host.backend.context,
    descriptor,
    vertex.backendResource,
    fragment.backendResource,
    backendResource
  )
  if status == gbsDeviceLost:
    host.enterDeviceLost()
  raiseForStatus(status)
  if backendResource.backendResourceIdValue == 0:
    raise newException(GpuHostError, "GPU backend returned an invalid resource")
  let dependencies = @[
    descriptor.vertexShader.resource,
    descriptor.fragmentShader.resource
  ]
  result = host.insertGpuResource(
    namespace,
    grkPipeline,
    0,
    backendResource,
    graphicsPipelineDescriptor = descriptor,
    pipelineKind = gplkGraphics,
    dependencies = dependencies
  )
  host.retainPipelineDependencies(namespace, dependencies)

proc createGpuComputePipeline*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    descriptor: GpuComputePipelineDescriptor
): GpuResourceHandle =
  host.validatePipelineCreation(namespace, descriptor.label)
  if not host.infoValue.computeSupported:
    raise newException(GpuHostError, "GPU compute pipelines are not supported")
  let compute = host.pipelineShader(
    namespace,
    descriptor.computeShader,
    gssCompute
  )
  if host.backend.createComputePipeline.isNil or
      host.backend.destroyResource.isNil:
    raise newException(
      GpuHostError,
      "GPU backend does not support compute pipelines"
    )

  var backendResource: GpuBackendResourceId
  let status = host.backend.createComputePipeline(
    host.backend.context,
    descriptor,
    compute.backendResource,
    backendResource
  )
  if status == gbsDeviceLost:
    host.enterDeviceLost()
  raiseForStatus(status)
  if backendResource.backendResourceIdValue == 0:
    raise newException(GpuHostError, "GPU backend returned an invalid resource")
  let dependencies = @[descriptor.computeShader.resource]
  result = host.insertGpuResource(
    namespace,
    grkPipeline,
    0,
    backendResource,
    computePipelineDescriptor = descriptor,
    pipelineKind = gplkCompute,
    dependencies = dependencies
  )
  host.retainPipelineDependencies(namespace, dependencies)

proc updateGpuBuffer*(
    host: GpuHost;
    handle: GpuResourceHandle;
    offsetBytes: uint64;
    data: seq[byte]
) =
  host.requireHost()
  if host.stateValue != ghsReady:
    raise newException(GpuHostError, "GPU host is not ready")
  if host.activeFrame:
    raise newException(
      GpuHostError,
      "GPU buffer updates are not allowed during an active frame"
    )
  if not host.isGpuResourceLive(handle) or handle.kind != grkBuffer:
    raise newException(GpuHostError, "GPU buffer handle is stale or invalid")
  let resource = host.namespaces[handle.namespace].resources[handle.resource]
  resource.bufferDescriptor.validateBufferUpdate(offsetBytes, data)
  if host.backend.updateBuffer.isNil:
    raise newException(GpuHostError, "GPU backend does not support buffer updates")
  let status = host.backend.updateBuffer(
    host.backend.context,
    resource.backendResource,
    resource.bufferDescriptor,
    offsetBytes,
    data
  )
  if status == gbsDeviceLost:
    host.enterDeviceLost()
  raiseForStatus(status)

proc isGpuResourceLive*(host: GpuHost; handle: GpuResourceHandle): bool =
  if host.isNil or host.stateValue == ghsClosed or
      handle.generation != host.generationValue or
      handle.namespace notin host.namespaces:
    return false
  let namespace = host.namespaces[handle.namespace]
  if handle.resource notin namespace.resources:
    return false
  let resource = namespace.resources[handle.resource]
  resource.generation == handle.generation and resource.kind == handle.kind

proc releaseGpuResource*(host: GpuHost; handle: GpuResourceHandle): bool =
  host.requireHost()
  if not host.isGpuResourceLive(handle):
    return false
  if host.activeFrame:
    raise newException(
      GpuHostError,
      "GPU resource cannot be released during an active frame"
    )
  var namespace = host.namespaces[handle.namespace]
  let resource = namespace.resources[handle.resource]
  if resource.dependentCount != 0:
    raise newException(
      GpuHostError,
      "GPU resource cannot be released while another resource depends on it"
    )
  if resource.backendResource.backendResourceIdValue != 0 and
      not host.backend.destroyResource.isNil:
    host.backend.destroyResource(
      host.backend.context,
      resource.backendResource,
      resource.kind
    )
  namespace.usage.persistentBytes -= resource.bytes
  dec namespace.usage.resourceCount
  for dependency in resource.dependencies:
    if dependency in namespace.resources and
        namespace.resources[dependency].dependentCount != 0:
      dec namespace.resources[dependency].dependentCount
  namespace.resources.del(handle.resource)
  host.namespaces[handle.namespace] = namespace
  true

proc validateGpuFrameWork(
    host: GpuHost;
    namespace: GpuNamespaceId;
    transientBytes = 0'u64;
    readbackBytes = 0'u64;
    workUnits = 0'u32
) =
  host.requireHost()
  if not host.activeFrame:
    raise newException(GpuHostError, "GPU frame work requires an active frame")
  if namespace notin host.namespaces:
    raise newException(GpuHostError, "unknown GPU namespace")

  let entry = host.namespaces[namespace]
  if not fits(
      entry.usage.transientBytes,
      transientBytes,
      entry.budget.transientBytesPerFrame
  ):
    raise newException(GpuHostError, "GPU namespace transient budget exceeded")
  if not fits(
      entry.usage.readbackBytes,
      readbackBytes,
      entry.budget.readbackBytesPerFrame
  ):
    raise newException(GpuHostError, "GPU namespace readback budget exceeded")
  if uint64(entry.usage.workUnits) + uint64(workUnits) >
      uint64(entry.budget.workUnitsPerFrame):
    raise newException(GpuHostError, "GPU namespace frame work budget exceeded")

proc reserveGpuFrameWork*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    transientBytes = 0'u64;
    readbackBytes = 0'u64;
    workUnits = 0'u32
) =
  host.validateGpuFrameWork(
    namespace,
    transientBytes,
    readbackBytes,
    workUnits
  )

  var entry = host.namespaces[namespace]
  entry.usage.transientBytes += transientBytes
  entry.usage.readbackBytes += readbackBytes
  entry.usage.workUnits += workUnits
  host.namespaces[namespace] = entry

proc isEmptyGpuHandle(handle: GpuResourceHandle): bool {.inline.} =
  handle.resource.resourceIdValue() == 0

proc requireGpuResource(
    host: GpuHost;
    namespace: GpuNamespaceId;
    handle: GpuResourceHandle;
    kind: GpuResourceKind;
    message: string
): GpuResourceEntry =
  if handle.namespace != namespace or handle.kind != kind or
      not host.isGpuResourceLive(handle):
    raise newException(GpuHostError, message)
  host.namespaces[namespace].resources[handle.resource]

proc validateViewport(viewport: GpuViewport; limitWidth, limitHeight: uint32) =
  if viewport.width == 0 or viewport.height == 0:
    raise newException(GpuHostError, "GPU viewport dimensions must be non-zero")
  if viewport.x > uint32(high(int16)) or viewport.y > uint32(high(int16)) or
      viewport.width > uint32(high(uint16)) or
      viewport.height > uint32(high(uint16)):
    raise newException(GpuHostError, "GPU viewport exceeds backend-neutral limits")
  if viewport.x > limitWidth or viewport.width > limitWidth - viewport.x or
      viewport.y > limitHeight or viewport.height > limitHeight - viewport.y:
    raise newException(GpuHostError, "GPU viewport exceeds its render target")

proc validateClearColor(color: GpuClearColor) =
  for component in [color.red, color.green, color.blue, color.alpha]:
    if not (component >= 0'f32 and component <= 1'f32):
      raise newException(GpuHostError, "GPU clear color must be finite and normalized")

proc nextGpuViewId(host: GpuHost): uint16 =
  if host.nextViewOffset >= host.configValue.viewIdCount:
    raise newException(GpuHostError, "GPU frame view identifier range exhausted")
  result = host.configValue.viewIdBase + host.nextViewOffset
  inc host.nextViewOffset

proc ensureGpuViewAvailable(host: GpuHost) =
  if host.nextViewOffset >= host.configValue.viewIdCount:
    raise newException(GpuHostError, "GPU frame view identifier range exhausted")

proc validateGraphicsPass(
    host: GpuHost;
    namespace: GpuNamespaceId;
    pass: GpuGraphicsPassDescriptor
): GpuBackendResourceId =
  var limitWidth, limitHeight: uint32
  if pass.renderTarget.isEmptyGpuHandle():
    if not host.configValue.presentation:
      raise newException(
        GpuHostError,
        "a compute-only GPU host has no presentation render target"
      )
    limitWidth = host.configValue.width
    limitHeight = host.configValue.height
  else:
    let target = host.requireGpuResource(
      namespace,
      pass.renderTarget,
      grkRenderTarget,
      "GPU draw render target is stale invalid or belongs to another namespace"
    )
    limitWidth = target.renderTargetDescriptor.width
    limitHeight = target.renderTargetDescriptor.height
    if target.backendResource.backendResourceIdValue() == 0:
      raise newException(GpuHostError, "GPU render target is not backend-mapped")
    result = target.backendResource

  pass.viewport.validateViewport(limitWidth, limitHeight)
  if pass.scissorEnabled:
    pass.scissor.validateViewport(limitWidth, limitHeight)
  if pass.clearColorEnabled:
    pass.clearColor.validateClearColor()

proc validateGpuBindings(
    host: GpuHost;
    namespace: GpuNamespaceId;
    bindings: GpuBindingSet;
    allowStorageImages: bool
): GpuBackendBindingSet =
  if bindings.uniforms.len > maxGpuUniformBindings:
    raise newException(GpuHostError, "GPU uniform binding count exceeded")
  if bindings.textures.len > maxGpuTextureBindings:
    raise newException(GpuHostError, "GPU texture binding count exceeded")
  if bindings.storageImages.len > maxGpuStorageImageBindings:
    raise newException(GpuHostError, "GPU storage image binding count exceeded")
  if not allowStorageImages and bindings.storageImages.len != 0:
    raise newException(
      GpuHostError,
      "GPU storage image bindings require a compute dispatch"
    )

  var resolved: GpuBackendBindingSet
  var uniformIds: seq[GpuResourceId]
  resolved.uniforms = newSeqOfCap[GpuBackendUniformBinding](bindings.uniforms.len)
  for binding in bindings.uniforms:
    let entry = host.requireGpuResource(
      namespace,
      binding.uniform,
      grkUniform,
      "GPU uniform binding is stale invalid or belongs to another namespace"
    )
    if binding.uniform.resource in uniformIds:
      raise newException(GpuHostError, "GPU uniform is bound more than once")
    uniformIds.add binding.uniform.resource
    if entry.backendResource.backendResourceIdValue() == 0:
      raise newException(GpuHostError, "GPU uniform is not backend-mapped")
    let expectedValues = entry.uniformDescriptor.uniformType.uniformFloatCount() *
      uint64(entry.uniformDescriptor.arrayLength)
    if uint64(binding.values.len) != expectedValues:
      raise newException(GpuHostError, "GPU uniform value count is invalid")
    for value in binding.values:
      if value.classify notin {fcNormal, fcSubnormal, fcZero, fcNegZero}:
        raise newException(GpuHostError, "GPU uniform values must be finite")
    resolved.uniforms.add GpuBackendUniformBinding(
      resource: entry.backendResource,
      descriptor: entry.uniformDescriptor,
      values: binding.values
    )

  var occupiedStages: set[uint8]
  resolved.textures = newSeqOfCap[GpuBackendTextureBinding](bindings.textures.len)
  for binding in bindings.textures:
    if binding.stage >= uint8(maxGpuTextureBindings) or
        binding.stage in occupiedStages:
      raise newException(GpuHostError, "GPU texture binding stage is invalid or duplicated")
    occupiedStages.incl binding.stage
    let sampler = host.requireGpuResource(
      namespace,
      binding.sampler,
      grkSampler,
      "GPU sampler binding is stale invalid or belongs to another namespace"
    )
    let texture = host.requireGpuResource(
      namespace,
      binding.texture,
      grkTexture,
      "GPU texture binding is stale invalid or belongs to another namespace"
    )
    if sampler.backendResource.backendResourceIdValue() == 0 or
        texture.backendResource.backendResourceIdValue() == 0:
      raise newException(GpuHostError, "GPU texture binding is not backend-mapped")
    if gtuSampled notin texture.textureDescriptor.usage:
      raise newException(GpuHostError, "GPU texture binding requires sampled usage")
    resolved.textures.add GpuBackendTextureBinding(
      stage: binding.stage,
      sampler: sampler.backendResource,
      texture: texture.backendResource,
      samplerDescriptor: sampler.samplerDescriptor
    )

  resolved.storageImages = newSeqOfCap[GpuBackendStorageImageBinding](
    bindings.storageImages.len
  )
  for binding in bindings.storageImages:
    if binding.stage >= uint8(maxGpuStorageImageBindings) or
        binding.stage in occupiedStages:
      raise newException(
        GpuHostError,
        "GPU storage image binding stage is invalid or duplicated"
      )
    occupiedStages.incl binding.stage
    if binding.mip != 0:
      raise newException(
        GpuHostError,
        "GPU storage image mip levels are not yet supported"
      )
    let texture = host.requireGpuResource(
      namespace,
      binding.texture,
      grkTexture,
      "GPU storage image is stale invalid or belongs to another namespace"
    )
    if texture.backendResource.backendResourceIdValue() == 0:
      raise newException(GpuHostError, "GPU storage image is not backend-mapped")
    if gtuStorage notin texture.textureDescriptor.usage:
      raise newException(GpuHostError, "GPU storage image requires storage usage")
    resolved.storageImages.add GpuBackendStorageImageBinding(
      stage: binding.stage,
      texture: texture.backendResource,
      format: texture.textureDescriptor.format,
      access: binding.access,
      mip: binding.mip
    )
  result = move(resolved)

proc validateDrawCommand(
    host: GpuHost;
    namespace: GpuNamespaceId;
    pass: GpuGraphicsPassDescriptor;
    command: GpuDrawCommand
): GpuResolvedDrawCommand =
  let pipeline = host.requireGpuResource(
    namespace,
    command.pipeline,
    grkPipeline,
    "GPU draw pipeline is stale invalid or belongs to another namespace"
  )
  if pipeline.pipelineKind != gplkGraphics or
      pipeline.backendResource.backendResourceIdValue() == 0:
    raise newException(GpuHostError, "GPU draw requires a graphics pipeline")
  let vertex = host.requireGpuResource(
    namespace,
    command.vertexBuffer,
    grkBuffer,
    "GPU vertex buffer is stale invalid or belongs to another namespace"
  )
  if vertex.bufferDescriptor.role != gbrVertex:
    raise newException(GpuHostError, "GPU draw requires a vertex buffer")
  if vertex.backendResource.backendResourceIdValue() == 0:
    raise newException(GpuHostError, "GPU vertex buffer is not backend-mapped")
  if vertex.bufferDescriptor.vertexLayout !=
      pipeline.graphicsPipelineDescriptor.vertexLayout:
    raise newException(GpuHostError, "GPU vertex layout does not match the pipeline")
  if command.vertexCount == 0:
    raise newException(GpuHostError, "GPU draw vertex count must be non-zero")
  let availableVertices =
    vertex.bufferDescriptor.byteSize div vertex.bufferDescriptor.vertexStride()
  if uint64(command.firstVertex) > availableVertices or
      uint64(command.vertexCount) > availableVertices - uint64(command.firstVertex):
    raise newException(GpuHostError, "GPU draw vertex range exceeds its buffer")

  if pass.renderTarget.isEmptyGpuHandle():
    discard
  else:
    let target = host.namespaces[namespace].resources[pass.renderTarget.resource]
    if target.renderTargetDescriptor.format !=
        pipeline.graphicsPipelineDescriptor.colorFormat:
      raise newException(
        GpuHostError,
        "GPU graphics pipeline color format does not match the render target"
      )

  var indexBackend: GpuBackendResourceId
  var indexDescriptor: GpuBufferDescriptor
  if command.indexBuffer.isEmptyGpuHandle():
    if command.firstIndex != 0 or command.indexCount != 0:
      raise newException(GpuHostError, "GPU draw index range has no index buffer")
  else:
    let index = host.requireGpuResource(
      namespace,
      command.indexBuffer,
      grkBuffer,
      "GPU index buffer is stale invalid or belongs to another namespace"
    )
    if index.bufferDescriptor.role != gbrIndex:
      raise newException(GpuHostError, "GPU draw requires an index buffer")
    if index.backendResource.backendResourceIdValue() == 0:
      raise newException(GpuHostError, "GPU index buffer is not backend-mapped")
    if command.indexCount == 0:
      raise newException(GpuHostError, "indexed GPU draw count must be non-zero")
    let availableIndices = index.bufferDescriptor.byteSize div
      index.bufferDescriptor.bufferElementBytes()
    if uint64(command.firstIndex) > availableIndices or
        uint64(command.indexCount) > availableIndices - uint64(command.firstIndex):
      raise newException(GpuHostError, "GPU draw index range exceeds its buffer")
    indexBackend = index.backendResource
    indexDescriptor = index.bufferDescriptor

  var resolvedBindings = host.validateGpuBindings(
    namespace,
    command.bindings,
    allowStorageImages = false
  )
  result = GpuResolvedDrawCommand(
    pipeline: pipeline.backendResource,
    vertexBuffer: vertex.backendResource,
    indexBuffer: indexBackend,
    pipelineDescriptor: pipeline.graphicsPipelineDescriptor,
    vertexDescriptor: vertex.bufferDescriptor,
    indexDescriptor: move(indexDescriptor),
    bindings: move(resolvedBindings)
  )

proc submitGpuDraws*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    pass: GpuGraphicsPassDescriptor;
    commands: openArray[GpuDrawCommand]
) =
  host.requireHost()
  if host.stateValue != ghsReady or not host.activeFrame:
    raise newException(GpuHostError, "GPU draw submission requires an active frame")
  if namespace notin host.namespaces:
    raise newException(GpuHostError, "unknown GPU namespace")
  if commands.len == 0:
    raise newException(GpuHostError, "GPU draw pass cannot be empty")
  if uint64(commands.len) > uint64(high(uint32)):
    raise newException(GpuHostError, "GPU draw pass has too many commands")
  if host.backend.beginGraphicsPass.isNil or host.backend.submitDraw.isNil:
    raise newException(GpuHostError, "GPU backend does not support draw submission")

  let target = host.validateGraphicsPass(namespace, pass)
  var resolvedCommands = newSeqOfCap[GpuResolvedDrawCommand](commands.len)
  for command in commands:
    resolvedCommands.add host.validateDrawCommand(namespace, pass, command)
  host.ensureGpuViewAvailable()
  host.validateGpuFrameWork(namespace, workUnits = uint32(commands.len))
  let viewId = host.configValue.viewIdBase + host.nextViewOffset
  let passStatus = host.backend.beginGraphicsPass(
    host.backend.context,
    viewId,
    pass,
    target
  )
  if passStatus == gbsDeviceLost:
    host.enterDeviceLost()
  raiseForStatus(passStatus)
  inc host.nextViewOffset
  host.reserveGpuFrameWork(namespace, workUnits = uint32(commands.len))

  for index, command in commands:
    let resolved = resolvedCommands[index]
    let status = host.backend.submitDraw(
      host.backend.context,
      viewId,
      resolved.pipeline,
      resolved.vertexBuffer,
      resolved.indexBuffer,
      resolved.pipelineDescriptor,
      resolved.vertexDescriptor,
      resolved.indexDescriptor,
      resolved.bindings,
      command
    )
    if status == gbsDeviceLost:
      host.enterDeviceLost()
    raiseForStatus(status)

proc submitGpuDraw*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    pass: GpuGraphicsPassDescriptor;
    command: GpuDrawCommand
) =
  host.submitGpuDraws(namespace, pass, [command])

proc dispatchGpuCompute*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    command: GpuComputeCommand
) =
  host.requireHost()
  if host.stateValue != ghsReady or not host.activeFrame:
    raise newException(GpuHostError, "GPU compute dispatch requires an active frame")
  if namespace notin host.namespaces:
    raise newException(GpuHostError, "unknown GPU namespace")
  if not host.infoValue.computeSupported:
    raise newException(GpuHostError, "GPU compute dispatch is not supported")
  if host.backend.dispatch.isNil:
    raise newException(GpuHostError, "GPU backend does not support compute dispatch")
  if command.groupsX == 0 or command.groupsY == 0 or command.groupsZ == 0 or
      command.groupsX > uint32(high(uint16)) or
      command.groupsY > uint32(high(uint16)) or
      command.groupsZ > uint32(high(uint16)):
    raise newException(GpuHostError, "GPU compute work group dimensions are invalid")
  let pipeline = host.requireGpuResource(
    namespace,
    command.pipeline,
    grkPipeline,
    "GPU compute pipeline is stale invalid or belongs to another namespace"
  )
  if pipeline.pipelineKind != gplkCompute or
      pipeline.backendResource.backendResourceIdValue() == 0:
    raise newException(GpuHostError, "GPU compute dispatch requires a compute pipeline")
  let bindings = host.validateGpuBindings(
    namespace,
    command.bindings,
    allowStorageImages = true
  )

  host.ensureGpuViewAvailable()
  host.reserveGpuFrameWork(namespace, workUnits = 1)
  let status = host.backend.dispatch(
    host.backend.context,
    host.nextGpuViewId(),
    pipeline.backendResource,
    bindings,
    command
  )
  if status == gbsDeviceLost:
    host.enterDeviceLost()
  raiseForStatus(status)

proc textureShape(
    entry: GpuResourceEntry
): tuple[width, height: uint32, format: GpuTextureFormat, usage: set[GpuTextureUsage]] =
  case entry.kind
  of grkTexture:
    (
      entry.textureDescriptor.width,
      entry.textureDescriptor.height,
      entry.textureDescriptor.format,
      entry.textureDescriptor.usage
    )
  of grkRenderTarget:
    (
      entry.renderTargetDescriptor.width,
      entry.renderTargetDescriptor.height,
      entry.renderTargetDescriptor.format,
      entry.renderTargetDescriptor.usage
    )
  else:
    (0'u32, 0'u32, gtfR8, {})

proc requireCopyResource(
    host: GpuHost;
    namespace: GpuNamespaceId;
    handle: GpuResourceHandle;
    source: bool
): GpuResourceEntry =
  if handle.namespace != namespace or
      handle.kind notin {grkTexture, grkRenderTarget} or
      not host.isGpuResourceLive(handle):
    raise newException(
      GpuHostError,
      if source:
        "GPU copy source is stale invalid or belongs to another namespace"
      else:
        "GPU copy destination is stale invalid or belongs to another namespace"
    )
  result = host.namespaces[namespace].resources[handle.resource]
  if result.backendResource.backendResourceIdValue() == 0:
    raise newException(GpuHostError, "GPU copy resource is not backend-mapped")

proc validateCopyBounds(
    region: GpuTextureCopyRegion;
    sourceWidth, sourceHeight, destinationWidth, destinationHeight: uint32
) =
  if region.width == 0 or region.height == 0:
    raise newException(GpuHostError, "GPU copy dimensions must be non-zero")
  if region.width > uint32(high(uint16)) or region.height > uint32(high(uint16)) or
      region.sourceX > uint32(high(uint16)) or
      region.sourceY > uint32(high(uint16)) or
      region.destinationX > uint32(high(uint16)) or
      region.destinationY > uint32(high(uint16)):
    raise newException(GpuHostError, "GPU copy region exceeds backend-neutral limits")
  if region.sourceX > sourceWidth or region.width > sourceWidth - region.sourceX or
      region.sourceY > sourceHeight or region.height > sourceHeight - region.sourceY:
    raise newException(GpuHostError, "GPU copy source region is out of bounds")
  if region.destinationX > destinationWidth or
      region.width > destinationWidth - region.destinationX or
      region.destinationY > destinationHeight or
      region.height > destinationHeight - region.destinationY:
    raise newException(GpuHostError, "GPU copy destination region is out of bounds")

proc copyGpuTexture*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    source, destination: GpuResourceHandle;
    region: GpuTextureCopyRegion
) =
  host.requireHost()
  if host.stateValue != ghsReady or not host.activeFrame:
    raise newException(GpuHostError, "GPU texture copy requires an active frame")
  if namespace notin host.namespaces:
    raise newException(GpuHostError, "unknown GPU namespace")
  if host.backend.copyTexture.isNil:
    raise newException(GpuHostError, "GPU backend does not support texture copies")
  if not host.infoValue.textureCopySupported:
    raise newException(GpuHostError, "GPU texture copies are not supported")
  if source.resource == destination.resource and source.kind == destination.kind:
    raise newException(GpuHostError, "GPU texture copy resources must be distinct")

  let sourceEntry = host.requireCopyResource(namespace, source, source = true)
  let destinationEntry = host.requireCopyResource(
    namespace, destination, source = false
  )
  if destinationEntry.kind != grkTexture:
    raise newException(GpuHostError, "GPU copy destination must be a texture")
  let sourceShape = sourceEntry.textureShape()
  let destinationShape = destinationEntry.textureShape()
  if gtuBlitSource notin sourceShape.usage:
    raise newException(GpuHostError, "GPU copy source requires blit-source usage")
  if gtuBlitDestination notin destinationShape.usage:
    raise newException(
      GpuHostError, "GPU copy destination requires blit-destination usage"
    )
  if sourceShape.format != destinationShape.format:
    raise newException(GpuHostError, "GPU copy formats must match")
  region.validateCopyBounds(
    sourceShape.width,
    sourceShape.height,
    destinationShape.width,
    destinationShape.height
  )

  host.ensureGpuViewAvailable()
  host.validateGpuFrameWork(namespace, workUnits = 1)
  let viewId = host.configValue.viewIdBase + host.nextViewOffset
  let status = host.backend.copyTexture(
    host.backend.context,
    viewId,
    sourceEntry.backendResource,
    sourceEntry.kind,
    destinationEntry.backendResource,
    region
  )
  if status == gbsDeviceLost:
    host.enterDeviceLost()
  raiseForStatus(status)
  inc host.nextViewOffset
  host.reserveGpuFrameWork(namespace, workUnits = 1)

proc copyGpuTexture*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    source, destination: GpuResourceHandle
) =
  let sourceEntry = host.requireCopyResource(namespace, source, source = true)
  let shape = sourceEntry.textureShape()
  host.copyGpuTexture(
    namespace,
    source,
    destination,
    GpuTextureCopyRegion(width: shape.width, height: shape.height)
  )

proc isGpuReadbackLive(host: GpuHost; handle: GpuReadbackHandle): bool =
  not host.isNil and host.stateValue != ghsClosed and
    handle.generation == host.generationValue and
    handle.namespace in host.namespaces and
    handle.readback in host.namespaces[handle.namespace].readbacks and
    host.namespaces[handle.namespace].readbacks[handle.readback].generation ==
      handle.generation

proc requestGpuReadback*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    texture: GpuResourceHandle
): GpuReadbackHandle =
  host.requireHost()
  if host.stateValue != ghsReady or not host.activeFrame:
    raise newException(GpuHostError, "GPU readback requires an active frame")
  if namespace notin host.namespaces:
    raise newException(GpuHostError, "unknown GPU namespace")
  if host.backend.requestReadback.isNil or host.backend.pollReadback.isNil:
    raise newException(GpuHostError, "GPU backend does not support readback")
  if not host.infoValue.textureReadbackSupported:
    raise newException(GpuHostError, "GPU texture readback is not supported")
  let entry = host.requireGpuResource(
    namespace,
    texture,
    grkTexture,
    "GPU readback texture is stale invalid or belongs to another namespace"
  )
  if entry.backendResource.backendResourceIdValue() == 0:
    raise newException(GpuHostError, "GPU readback texture is not backend-mapped")
  if entry.textureDescriptor.usage != {gtuBlitDestination, gtuReadback}:
    raise newException(GpuHostError, "GPU readback requires a readback texture")
  if host.namespaces[namespace].readbacks.len >= maxGpuPendingReadbacksPerNamespace:
    raise newException(GpuHostError, "GPU pending readback count exceeded")
  let bytes = entry.textureDescriptor.textureBytes()
  if bytes > uint64(high(int)):
    raise newException(GpuHostError, "GPU readback exceeds addressable memory")
  host.validateGpuFrameWork(namespace, readbackBytes = bytes, workUnits = 1)

  if host.namespaces[namespace].nextReadbackId == 0:
    raise newException(GpuHostError, "GPU readback identifier space exhausted")

  var pixels = newSeq[byte](int(bytes))
  var completionToken: uint64
  let status = host.backend.requestReadback(
    host.backend.context,
    entry.backendResource,
    entry.textureDescriptor,
    addr pixels[0],
    bytes,
    completionToken
  )
  if status == gbsDeviceLost:
    host.enterDeviceLost()
  raiseForStatus(status)

  var namespaceEntry = host.namespaces[namespace]
  let id = GpuReadbackId(namespaceEntry.nextReadbackId)
  inc namespaceEntry.nextReadbackId
  namespaceEntry.readbacks[id] = GpuReadbackEntry(
    generation: host.generationValue,
    texture: texture.resource,
    descriptor: entry.textureDescriptor,
    completionToken: completionToken,
    pixels: move(pixels)
  )
  inc namespaceEntry.resources[texture.resource].dependentCount
  host.namespaces[namespace] = namespaceEntry
  host.reserveGpuFrameWork(namespace, readbackBytes = bytes, workUnits = 1)
  GpuReadbackHandle(
    namespace: namespace,
    readback: id,
    generation: host.generationValue
  )

proc refreshGpuReadback(host: GpuHost; handle: GpuReadbackHandle) =
  if not host.isGpuReadbackLive(handle):
    return
  var namespaceEntry = host.namespaces[handle.namespace]
  if namespaceEntry.readbacks[handle.readback].ready:
    return
  var ready = false
  let status = host.backend.pollReadback(
    host.backend.context,
    namespaceEntry.readbacks[handle.readback].completionToken,
    ready
  )
  if status == gbsDeviceLost:
    host.enterDeviceLost()
  raiseForStatus(status)
  if ready:
    namespaceEntry.readbacks[handle.readback].ready = true
    host.namespaces[handle.namespace] = namespaceEntry

proc gpuReadbackState*(host: GpuHost; handle: GpuReadbackHandle): GpuReadbackState =
  if not host.isGpuReadbackLive(handle):
    return grsInvalid
  host.refreshGpuReadback(handle)
  if not host.isGpuReadbackLive(handle):
    return grsInvalid
  if host.namespaces[handle.namespace].readbacks[handle.readback].ready:
    grsReady
  else:
    grsPending

proc tryTakeGpuReadback*(
    host: GpuHost;
    handle: GpuReadbackHandle;
    data: var GpuReadbackData
): bool =
  if host.gpuReadbackState(handle) != grsReady:
    return false
  var namespaceEntry = host.namespaces[handle.namespace]
  var readback = namespaceEntry.readbacks[handle.readback]
  data = GpuReadbackData(
    width: readback.descriptor.width,
    height: readback.descriptor.height,
    format: readback.descriptor.format,
    rowStride: uint32(
      readback.descriptor.textureBytes() div uint64(readback.descriptor.height)
    ),
    pixels: move(readback.pixels)
  )
  if readback.texture in namespaceEntry.resources and
      namespaceEntry.resources[readback.texture].dependentCount != 0:
    dec namespaceEntry.resources[readback.texture].dependentCount
  namespaceEntry.readbacks.del(handle.readback)
  host.namespaces[handle.namespace] = namespaceEntry
  true

proc pendingGpuReadbackCount*(host: GpuHost; namespace: GpuNamespaceId): int =
  host.requireHost()
  if namespace notin host.namespaces:
    return 0
  host.namespaces[namespace].readbacks.len
