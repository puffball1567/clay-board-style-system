import std/[hashes, tables]

const
  gpuHostApiVersion* = 1'u32
  maxGpuNamespaceNameBytes* = 128

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

  GpuNamespaceId* = distinct uint64
  GpuResourceId* = distinct uint64

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
    closeOwned*: GpuBackendCloseProc
    detachBorrowed*: GpuBackendCloseProc

  GpuResourceEntry = object
    kind: GpuResourceKind
    bytes: uint64
    generation: uint64

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

proc close*(host: GpuHost) =
  if host.isNil or host.stateValue == ghsClosed:
    return

  host.activeFrame = false
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
  host.namespaces.del(id)
  true

proc fits(current, addition, limit: uint64): bool {.inline.} =
  current <= limit and addition <= limit - current

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

  var entry = host.namespaces[namespace]
  if entry.usage.resourceCount >= entry.budget.maxResources:
    raise newException(GpuHostError, "GPU namespace resource count exceeded")
  if not fits(entry.usage.persistentBytes, bytes, entry.budget.persistentBytes):
    raise newException(GpuHostError, "GPU namespace persistent budget exceeded")
  if entry.nextResourceId == 0:
    raise newException(GpuHostError, "GPU resource identifier space exhausted")

  let resource = GpuResourceId(entry.nextResourceId)
  inc entry.nextResourceId
  entry.resources[resource] = GpuResourceEntry(
    kind: kind,
    bytes: bytes,
    generation: host.generationValue
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
  var namespace = host.namespaces[handle.namespace]
  let resource = namespace.resources[handle.resource]
  namespace.usage.persistentBytes -= resource.bytes
  dec namespace.usage.resourceCount
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
