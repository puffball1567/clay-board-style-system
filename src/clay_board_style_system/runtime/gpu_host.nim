import std/[algorithm, hashes, tables]

const
  gpuHostApiVersion* = 6'u32
  maxGpuNamespaceNameBytes* = 128
  maxGpuResourceLabelBytes* = 128

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

  GpuHostConfig* = object
    width*, height*: uint32
    resetFlags*: uint32
    presentation*: bool

  GpuBackendInfo* = object
    rendererName*: string
    computeSupported*: bool
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
    createGraphicsPipeline*: GpuBackendCreateGraphicsPipelineProc
    createComputePipeline*: GpuBackendCreateComputePipelineProc
    destroyResource*: GpuBackendDestroyResourceProc
    closeOwned*: GpuBackendCloseProc
    detachBorrowed*: GpuBackendCloseProc

  GpuResourceEntry = object
    kind: GpuResourceKind
    bytes: uint64
    generation: uint64
    backendResource: GpuBackendResourceId
    bufferDescriptor: GpuBufferDescriptor
    renderTargetDescriptor: GpuRenderTargetDescriptor
    shaderDescriptor: GpuShaderDescriptor
    graphicsPipelineDescriptor: GpuGraphicsPipelineDescriptor
    computePipelineDescriptor: GpuComputePipelineDescriptor
    dependencies: seq[GpuResourceId]
    dependentCount: uint32

  GpuNamespaceEntry = object
    name: string
    budget: GpuResourceBudget
    usage: GpuResourceUsage
    nextResourceId: uint64
    resources: Table[GpuResourceId, GpuResourceEntry]

  GpuHost* = ref object
    backend: GpuBackendVTable
    ownershipValue: GpuHostOwnership
    stateValue: GpuHostState
    configValue: GpuHostConfig
    infoValue: GpuBackendInfo
    generationValue: uint64
    frameNumber: uint64
    activeFrame: bool
    nextNamespaceId: uint64
    namespaces: Table[GpuNamespaceId, GpuNamespaceEntry]

proc `==`*(a, b: GpuNamespaceId): bool {.borrow.}
proc hash*(id: GpuNamespaceId): Hash {.borrow.}
proc `==`*(a, b: GpuResourceId): bool {.borrow.}
proc hash*(id: GpuResourceId): Hash {.borrow.}

proc namespaceIdValue*(id: GpuNamespaceId): uint64 {.inline.} = uint64(id)
proc resourceIdValue*(id: GpuResourceId): uint64 {.inline.} = uint64(id)
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

proc openGpuHost*(
    backend: GpuBackendVTable;
    ownership: GpuHostOwnership;
    config = GpuHostConfig()
): GpuHost =
  config.validateConfig()
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
    configValue: config,
    generationValue: 1'u64,
    nextNamespaceId: 1'u64,
    namespaces: initTable[GpuNamespaceId, GpuNamespaceEntry]()
  )

  var info: GpuBackendInfo
  let status = openProc(backend.context, config, info)
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

  host.activeFrame = false
  var namespaceIds: seq[GpuNamespaceId]
  for id in host.namespaces.keys:
    namespaceIds.add id
  namespaceIds.sort(proc(a, b: GpuNamespaceId): int =
    cmp(namespaceIdValue(b), namespaceIdValue(a)))
  for id in namespaceIds:
    host.destroyNamespaceResources(id)
  host.namespaces.clear()
  case host.ownershipValue
  of ghoOwned:
    if not host.backend.closeOwned.isNil:
      host.backend.closeOwned(host.backend.context)
  of ghoBorrowed:
    if not host.backend.detachBorrowed.isNil:
      host.backend.detachBorrowed(host.backend.context)
  host.stateValue = ghsClosed

proc invalidateResources(host: GpuHost) =
  for id, entry in host.namespaces.mpairs:
    discard id
    entry.resources.clear()
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
    resources: initTable[GpuResourceId, GpuResourceEntry]()
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
    renderTargetDescriptor = GpuRenderTargetDescriptor();
    shaderDescriptor = GpuShaderDescriptor();
    graphicsPipelineDescriptor = GpuGraphicsPipelineDescriptor();
    computePipelineDescriptor = GpuComputePipelineDescriptor();
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
    renderTargetDescriptor: renderTargetDescriptor,
    shaderDescriptor: shaderDescriptor,
    graphicsPipelineDescriptor: graphicsPipelineDescriptor,
    computePipelineDescriptor: computePipelineDescriptor,
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
    backendResource
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

proc reserveGpuFrameWork*(
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

  var entry = host.namespaces[namespace]
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

  entry.usage.transientBytes += transientBytes
  entry.usage.readbackBytes += readbackBytes
  entry.usage.workUnits += workUnits
  host.namespaces[namespace] = entry
