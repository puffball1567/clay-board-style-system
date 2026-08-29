import std/[strutils, unittest]

import clay_board_style_system/runtime/gpu_host

type MockGpuContext = ref object of GpuBackendContext
  openStatus: GpuBackendStatus
  beginStatus: GpuBackendStatus
  endStatus: GpuBackendStatus
  resizeStatus: GpuBackendStatus
  restoreStatus: GpuBackendStatus
  createTextureStatus: GpuBackendStatus
  createBufferStatus: GpuBackendStatus
  updateBufferStatus: GpuBackendStatus
  ownedOpens: int
  borrowedAttaches: int
  begins: int
  ends: int
  resizes: int
  restores: int
  ownedCloses: int
  borrowedDetaches: int
  textureCreates: int
  bufferCreates: int
  bufferUpdates: int
  resourceDestroys: int
  nextBackendResource: uint64
  lastTexture: GpuTextureDescriptor
  lastTextureDataBytes: int
  lastBuffer: GpuBufferDescriptor
  lastBufferDataBytes: int
  lastBufferUpdateOffset: uint64
  lastBufferUpdateBytes: int
  destroyedResources: seq[uint64]
  width, height: uint32

proc mock(context: GpuBackendContext): MockGpuContext {.inline.} =
  MockGpuContext(context)

proc openOwned(
    context: GpuBackendContext;
    config: GpuHostConfig;
    info: var GpuBackendInfo
): GpuBackendStatus {.raises: [].} =
  let state = context.mock
  inc state.ownedOpens
  state.width = config.width
  state.height = config.height
  info = GpuBackendInfo(
    rendererName: "mock-owned",
    computeSupported: true,
    maxTextureSize: 8192
  )
  state.openStatus

proc attachBorrowed(
    context: GpuBackendContext;
    config: GpuHostConfig;
    info: var GpuBackendInfo
): GpuBackendStatus {.raises: [].} =
  let state = context.mock
  inc state.borrowedAttaches
  state.width = config.width
  state.height = config.height
  info = GpuBackendInfo(rendererName: "mock-borrowed")
  state.openStatus

proc beginFrame(
    context: GpuBackendContext;
    frameNumber: uint64
): GpuBackendStatus {.raises: [].} =
  discard frameNumber
  let state = context.mock
  inc state.begins
  state.beginStatus

proc endFrame(
    context: GpuBackendContext;
    frameNumber: uint64
): GpuBackendStatus {.raises: [].} =
  discard frameNumber
  let state = context.mock
  inc state.ends
  state.endStatus

proc resize(
    context: GpuBackendContext;
    width, height: uint32;
    resetFlags: uint32
): GpuBackendStatus {.raises: [].} =
  discard resetFlags
  let state = context.mock
  inc state.resizes
  state.width = width
  state.height = height
  state.resizeStatus

proc restore(
    context: GpuBackendContext;
    info: var GpuBackendInfo
): GpuBackendStatus {.raises: [].} =
  let state = context.mock
  inc state.restores
  info.rendererName = "mock-restored"
  info.computeSupported = false
  state.restoreStatus

proc closeOwned(context: GpuBackendContext) {.raises: [].} =
  inc context.mock.ownedCloses

proc detachBorrowed(context: GpuBackendContext) {.raises: [].} =
  inc context.mock.borrowedDetaches

proc createTexture(
    context: GpuBackendContext;
    descriptor: GpuTextureDescriptor;
    initialData: seq[byte];
    resource: var GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  let state = context.mock
  inc state.textureCreates
  state.lastTexture = descriptor
  state.lastTextureDataBytes = initialData.len
  if state.createTextureStatus == gbsOk:
    resource = GpuBackendResourceId(state.nextBackendResource)
    inc state.nextBackendResource
  state.createTextureStatus

proc createBuffer(
    context: GpuBackendContext;
    descriptor: GpuBufferDescriptor;
    initialData: seq[byte];
    resource: var GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  let state = context.mock
  inc state.bufferCreates
  state.lastBuffer = descriptor
  state.lastBufferDataBytes = initialData.len
  if state.createBufferStatus == gbsOk:
    resource = GpuBackendResourceId(state.nextBackendResource)
    inc state.nextBackendResource
  state.createBufferStatus

proc updateBuffer(
    context: GpuBackendContext;
    resource: GpuBackendResourceId;
    descriptor: GpuBufferDescriptor;
    offsetBytes: uint64;
    data: seq[byte]
): GpuBackendStatus {.raises: [].} =
  discard resource
  let state = context.mock
  inc state.bufferUpdates
  state.lastBuffer = descriptor
  state.lastBufferUpdateOffset = offsetBytes
  state.lastBufferUpdateBytes = data.len
  state.updateBufferStatus

proc destroyResource(
    context: GpuBackendContext;
    resource: GpuBackendResourceId;
    kind: GpuResourceKind
) {.raises: [].} =
  discard kind
  let state = context.mock
  inc state.resourceDestroys
  state.destroyedResources.add resource.backendResourceIdValue()

proc backend(state: MockGpuContext): GpuBackendVTable =
  GpuBackendVTable(
    apiVersion: gpuHostApiVersion,
    provider: gpkCustom,
    context: state,
    openOwned: openOwned,
    attachBorrowed: attachBorrowed,
    beginFrame: beginFrame,
    endFrame: endFrame,
    resize: resize,
    restore: restore,
    createTexture: createTexture,
    createBuffer: createBuffer,
    updateBuffer: updateBuffer,
    destroyResource: destroyResource,
    closeOwned: closeOwned,
    detachBorrowed: detachBorrowed
  )

proc newContext(): MockGpuContext =
  MockGpuContext(
    openStatus: gbsOk,
    beginStatus: gbsOk,
    endStatus: gbsOk,
    resizeStatus: gbsOk,
    restoreStatus: gbsOk,
    createTextureStatus: gbsOk,
    createBufferStatus: gbsOk,
    updateBufferStatus: gbsOk,
    nextBackendResource: 1
  )

proc presentationConfig(): GpuHostConfig =
  GpuHostConfig(width: 1280, height: 720, resetFlags: 7, presentation: true)

proc standardBudget(): GpuResourceBudget =
  GpuResourceBudget(
    persistentBytes: 1024,
    transientBytesPerFrame: 256,
    readbackBytesPerFrame: 128,
    workUnitsPerFrame: 10,
    maxResources: 2
  )

proc textureDescriptor(
    width = 8'u32;
    height = 8'u32;
    format = gtfRgba8;
    usage = {gtuSampled};
    label = "texture"
): GpuTextureDescriptor =
  GpuTextureDescriptor(
    width: width,
    height: height,
    format: format,
    usage: usage,
    label: label
  )

proc positionColorLayout(): seq[GpuVertexAttribute] =
  @[
    GpuVertexAttribute(
      semantic: gvsPosition,
      components: 2,
      componentType: gvctFloat
    ),
    GpuVertexAttribute(
      semantic: gvsColor0,
      components: 4,
      componentType: gvctUint8,
      normalized: true
    )
  ]

proc vertexBufferDescriptor(
    byteSize = 24'u64;
    access = gbaStatic;
    label = "vertices"
): GpuBufferDescriptor =
  GpuBufferDescriptor(
    byteSize: byteSize,
    role: gbrVertex,
    access: access,
    vertexLayout: positionColorLayout(),
    label: label
  )

proc indexBufferDescriptor(
    byteSize = 12'u64;
    access = gbaStatic;
    indexFormat = gifUint16;
    label = "indices"
): GpuBufferDescriptor =
  GpuBufferDescriptor(
    byteSize: byteSize,
    role: gbrIndex,
    access: access,
    indexFormat: indexFormat,
    label: label
  )

suite "GPU host lifecycle":
  test "owned host opens once and closes the owned backend idempotently":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned, presentationConfig())
    check host.provider == gpkCustom
    check host.ownership == ghoOwned
    check host.state == ghsReady
    check host.generation == 1
    check host.backendInfo.rendererName == "mock-owned"
    check host.backendInfo.computeSupported
    check context.ownedOpens == 1

    host.close()
    host.close()
    check host.state == ghsClosed
    check context.ownedCloses == 1
    check context.borrowedDetaches == 0

  test "borrowed host detaches without destroying the backend":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoBorrowed, presentationConfig())
    check host.backendInfo.rendererName == "mock-borrowed"
    check context.borrowedAttaches == 1
    host.close()
    check context.borrowedDetaches == 1
    check context.ownedCloses == 0

  test "invalid presentation configuration and unsupported ownership fail closed":
    let context = newContext()
    expect GpuHostError:
      discard openGpuHost(
        context.backend,
        ghoOwned,
        GpuHostConfig(presentation: true)
      )

    var value = context.backend
    value.attachBorrowed = nil
    expect GpuHostError:
      discard openGpuHost(value, ghoBorrowed)

    value = context.backend
    value.apiVersion = gpuHostApiVersion + 1
    expect GpuHostError:
      discard openGpuHost(value, ghoOwned)

  test "backend initialization failure is reported":
    let context = newContext()
    context.openStatus = gbsUnavailable
    expect GpuHostError:
      discard openGpuHost(context.backend, ghoOwned)
    check context.ownedOpens == 1
    check context.ownedCloses == 1

  test "failed restoration preserves device-lost state and backend information":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let originalInfo = host.backendInfo
    check host.markGpuDeviceLost()
    context.restoreStatus = gbsFailed
    expect GpuHostError:
      host.restoreGpuHost()
    check host.state == ghsDeviceLost
    check host.backendInfo == originalInfo
    host.close()

  test "frames are ordered and nested or stale tokens are rejected":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let first = host.beginGpuFrame()
    check first.number == 1
    expect GpuHostError:
      discard host.beginGpuFrame()
    expect GpuHostError:
      host.endGpuFrame(GpuFrameToken(number: first.number + 1, generation: 1))
    host.endGpuFrame(first)
    expect GpuHostError:
      host.endGpuFrame(first)
    check context.begins == 1
    check context.ends == 1
    host.close()

  test "backend frame device loss changes state and generation":
    let context = newContext()
    context.endStatus = gbsDeviceLost
    let host = openGpuHost(context.backend, ghoOwned)
    let token = host.beginGpuFrame()
    expect GpuHostError:
      host.endGpuFrame(token)
    check host.state == ghsDeviceLost
    check host.generation == 2
    expect GpuHostError:
      discard host.beginGpuFrame()
    host.close()

  test "begin-frame device loss invalidates every retained resource":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("scene", standardBudget())
    let resource = host.reserveGpuResource(namespace, grkBuffer, 128)
    context.beginStatus = gbsDeviceLost
    expect GpuHostError:
      discard host.beginGpuFrame()
    check host.state == ghsDeviceLost
    check not host.isGpuResourceLive(resource)
    check host.gpuNamespaceUsage(namespace).resourceCount == 0
    host.close()

  test "resize updates retained viewport only after backend success":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned, presentationConfig())
    host.resizeGpuHost(1920, 1080)
    check host.config.width == 1920
    check host.config.height == 1080
    check context.width == 1920
    check context.height == 1080

    context.resizeStatus = gbsFailed
    expect GpuHostError:
      host.resizeGpuHost(800, 600)
    check host.config.width == 1920
    check host.config.height == 1080
    host.close()

  test "compute-only hosts reject presentation resize":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    expect GpuHostError:
      host.resizeGpuHost(640, 480)
    host.close()

suite "GPU resource namespaces":
  test "persistent resources retain typed generation-checked handles":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("chart", standardBudget())
    let texture = host.reserveGpuResource(namespace, grkTexture, 700)
    let pipeline = host.reserveGpuResource(namespace, grkPipeline, 0)

    check host.hasGpuNamespace(namespace)
    check host.gpuNamespaceName(namespace) == "chart"
    check host.isGpuResourceLive(texture)
    check host.isGpuResourceLive(pipeline)
    check host.gpuNamespaceUsage(namespace).persistentBytes == 700
    check host.gpuNamespaceUsage(namespace).resourceCount == 2
    check host.releaseGpuResource(texture)
    check not host.releaseGpuResource(texture)
    check host.gpuNamespaceUsage(namespace).persistentBytes == 0
    check host.gpuNamespaceUsage(namespace).resourceCount == 1
    host.close()

suite "GPU texture resources":
  test "texture creation maps backend ownership and exact byte accounting":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("textures", standardBudget())
    let pixels = newSeq[byte](8 * 8 * 4)
    let descriptor = textureDescriptor(
      usage = {gtuSampled, gtuBlitSource},
      label = "surface-color"
    )

    let texture = host.createGpuTexture(namespace, descriptor, pixels)
    check texture.kind == grkTexture
    check host.isGpuResourceLive(texture)
    check context.textureCreates == 1
    check context.lastTexture == descriptor
    check context.lastTextureDataBytes == pixels.len
    check host.gpuNamespaceUsage(namespace).persistentBytes == 256
    check host.gpuNamespaceUsage(namespace).resourceCount == 1

    check host.releaseGpuResource(texture)
    check context.resourceDestroys == 1
    check context.destroyedResources == @[1'u64]
    check host.gpuNamespaceUsage(namespace).persistentBytes == 0
    check host.gpuNamespaceUsage(namespace).resourceCount == 0
    host.close()
    check context.resourceDestroys == 1

  test "texture formats use their declared storage size":
    for format in GpuTextureFormat:
      let expectedBytes =
        if format == gtfR8: 64'u64
        else: 256'u64
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace("format", standardBudget())
      discard host.createGpuTexture(
        namespace,
        textureDescriptor(format = format)
      )
      check host.gpuNamespaceUsage(namespace).persistentBytes == expectedBytes
      host.close()
      check context.resourceDestroys == 1

  test "invalid descriptors fail before calling the backend":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("validation", standardBudget())

    for descriptor in [
      textureDescriptor(width = 0),
      textureDescriptor(height = 0),
      textureDescriptor(usage = {}),
      textureDescriptor(width = 8193),
      textureDescriptor(label = repeat('x', maxGpuResourceLabelBytes + 1))
    ]:
      expect GpuHostError:
        discard host.createGpuTexture(namespace, descriptor)

    expect GpuHostError:
      discard host.createGpuTexture(
        namespace,
        textureDescriptor(width = 2, height = 2),
        newSeq[byte](15)
      )
    check context.textureCreates == 0
    check host.gpuNamespaceUsage(namespace) == GpuResourceUsage()
    host.close()

  test "budget failure does not allocate a backend texture":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "small",
      GpuResourceBudget(persistentBytes: 255, maxResources: 1)
    )
    expect GpuHostError:
      discard host.createGpuTexture(namespace, textureDescriptor())
    check context.textureCreates == 0
    check context.resourceDestroys == 0
    host.close()

  test "backend failure leaves namespace accounting unchanged":
    let context = newContext()
    context.createTextureStatus = gbsFailed
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("failed", standardBudget())
    expect GpuHostError:
      discard host.createGpuTexture(namespace, textureDescriptor())
    check context.textureCreates == 1
    check context.resourceDestroys == 0
    check host.gpuNamespaceUsage(namespace) == GpuResourceUsage()
    host.close()

  test "backends must expose both texture lifecycle callbacks":
    let context = newContext()
    var value = context.backend
    value.destroyResource = nil
    let host = openGpuHost(value, ghoOwned)
    let namespace = host.createGpuNamespace("unsupported", standardBudget())
    expect GpuHostError:
      discard host.createGpuTexture(namespace, textureDescriptor())
    check context.textureCreates == 0
    host.close()

  test "active frames reject retained resource mutation":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("frame-locked", standardBudget())
    let texture = host.createGpuTexture(namespace, textureDescriptor())
    let frame = host.beginGpuFrame()
    expect GpuHostError:
      discard host.createGpuTexture(namespace, textureDescriptor())
    expect GpuHostError:
      discard host.releaseGpuResource(texture)
    expect GpuHostError:
      discard host.closeGpuNamespace(namespace)
    check host.isGpuResourceLive(texture)
    host.endGpuFrame(frame)
    check host.releaseGpuResource(texture)
    host.close()

  test "namespace and host closure destroy mapped resources newest first":
    block closeNamespace:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace("temporary", standardBudget())
      discard host.createGpuTexture(namespace, textureDescriptor(format = gtfR8))
      discard host.createGpuTexture(namespace, textureDescriptor(format = gtfR8))
      check host.closeGpuNamespace(namespace)
      check context.destroyedResources == @[2'u64, 1'u64]
      host.close()

    block closeHost:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace("owned", standardBudget())
      discard host.createGpuTexture(namespace, textureDescriptor(format = gtfR8))
      discard host.createGpuTexture(namespace, textureDescriptor(format = gtfR8))
      host.close()
      check context.destroyedResources == @[2'u64, 1'u64]
      check context.ownedCloses == 1

  test "device loss invalidates mapped resources without destroying stale handles":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("lost", standardBudget())
    let texture = host.createGpuTexture(namespace, textureDescriptor())
    check host.markGpuDeviceLost()
    check not host.isGpuResourceLive(texture)
    check host.gpuNamespaceUsage(namespace) == GpuResourceUsage()
    check context.resourceDestroys == 0
    host.close()
    check context.resourceDestroys == 0

suite "GPU buffer resources":
  test "static vertex buffers map layout data accounting and destruction":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("vertex-buffers", standardBudget())
    let descriptor = vertexBufferDescriptor()
    let vertices = newSeq[byte](int(descriptor.byteSize))

    let buffer = host.createGpuBuffer(namespace, descriptor, vertices)
    check buffer.kind == grkBuffer
    check host.isGpuResourceLive(buffer)
    check descriptor.vertexStride() == 12
    check context.bufferCreates == 1
    check context.lastBuffer == descriptor
    check context.lastBufferDataBytes == vertices.len
    check host.gpuNamespaceUsage(namespace).persistentBytes == descriptor.byteSize

    check host.releaseGpuResource(buffer)
    check context.destroyedResources == @[1'u64]
    host.close()

  test "dynamic index buffers accept aligned bounded updates":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("dynamic-indices", standardBudget())
    let descriptor = indexBufferDescriptor(
      byteSize = 16,
      access = gbaDynamic,
      indexFormat = gifUint32
    )
    let buffer = host.createGpuBuffer(namespace, descriptor)

    host.updateGpuBuffer(buffer, 4, newSeq[byte](8))
    check context.bufferUpdates == 1
    check context.lastBufferUpdateOffset == 4
    check context.lastBufferUpdateBytes == 8
    check host.gpuNamespaceUsage(namespace).persistentBytes == 16
    host.close()
    check context.resourceDestroys == 1

  test "dynamic vertex updates use whole layout strides":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("dynamic-vertices", standardBudget())
    let descriptor = vertexBufferDescriptor(byteSize = 36, access = gbaDynamic)
    let buffer = host.createGpuBuffer(
      namespace,
      descriptor,
      newSeq[byte](36)
    )
    host.updateGpuBuffer(buffer, 12, newSeq[byte](24))
    check context.lastBufferUpdateOffset == 12
    check context.lastBufferUpdateBytes == 24
    expect GpuHostError:
      host.updateGpuBuffer(buffer, 4, newSeq[byte](12))
    expect GpuHostError:
      host.updateGpuBuffer(buffer, 12, newSeq[byte](8))
    check context.bufferUpdates == 1
    host.close()

  test "buffer descriptors reject malformed layouts and storage":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("invalid-buffers", standardBudget())

    var missingLayout = vertexBufferDescriptor()
    missingLayout.vertexLayout = @[]
    var duplicateSemantic = vertexBufferDescriptor()
    duplicateSemantic.vertexLayout.add duplicateSemantic.vertexLayout[0]
    var invalidComponents = vertexBufferDescriptor()
    invalidComponents.vertexLayout[0].components = 0
    var invalidNormalizedFloat = vertexBufferDescriptor()
    invalidNormalizedFloat.vertexLayout[0].normalized = true
    var invalidIntegerHalf = vertexBufferDescriptor()
    invalidIntegerHalf.vertexLayout[0].componentType = gvctHalf
    invalidIntegerHalf.vertexLayout[0].asInteger = true
    var indexWithLayout = indexBufferDescriptor()
    indexWithLayout.vertexLayout = positionColorLayout()

    for descriptor in [
      vertexBufferDescriptor(byteSize = 0),
      vertexBufferDescriptor(byteSize = 25),
      vertexBufferDescriptor(label = repeat('x', maxGpuResourceLabelBytes + 1)),
      missingLayout,
      duplicateSemantic,
      invalidComponents,
      invalidNormalizedFloat,
      invalidIntegerHalf,
      indexBufferDescriptor(byteSize = 3),
      indexWithLayout
    ]:
      expect GpuHostError:
        discard host.createGpuBuffer(namespace, descriptor, newSeq[byte](int(descriptor.byteSize)))

    expect GpuHostError:
      discard host.createGpuBuffer(
        namespace,
        vertexBufferDescriptor(),
        newSeq[byte](12)
      )
    expect GpuHostError:
      discard host.createGpuBuffer(namespace, vertexBufferDescriptor())
    check context.bufferCreates == 0
    host.close()

  test "buffer updates reject static stale empty unaligned and overflowing writes":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("update-validation", standardBudget())
    let staticBuffer = host.createGpuBuffer(
      namespace,
      indexBufferDescriptor(),
      newSeq[byte](12)
    )
    let dynamicBuffer = host.createGpuBuffer(
      namespace,
      indexBufferDescriptor(byteSize = 16, access = gbaDynamic)
    )

    expect GpuHostError:
      host.updateGpuBuffer(staticBuffer, 0, @[0'u8, 0'u8])
    expect GpuHostError:
      host.updateGpuBuffer(dynamicBuffer, 0, @[])
    expect GpuHostError:
      host.updateGpuBuffer(dynamicBuffer, 1, @[0'u8, 0'u8])
    expect GpuHostError:
      host.updateGpuBuffer(dynamicBuffer, 14, newSeq[byte](4))
    check context.bufferUpdates == 0

    check host.releaseGpuResource(dynamicBuffer)
    expect GpuHostError:
      host.updateGpuBuffer(dynamicBuffer, 0, @[0'u8, 0'u8])
    host.close()

  test "buffer backend failures and device loss preserve host invariants":
    block createFailure:
      let context = newContext()
      context.createBufferStatus = gbsFailed
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace("create-failure", standardBudget())
      expect GpuHostError:
        discard host.createGpuBuffer(
          namespace,
          indexBufferDescriptor(),
          newSeq[byte](12)
        )
      check host.gpuNamespaceUsage(namespace) == GpuResourceUsage()
      check context.resourceDestroys == 0
      host.close()

  test "buffer budget and callback failures occur before backend allocation":
    block budgetFailure:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "buffer-budget",
        GpuResourceBudget(persistentBytes: 11, maxResources: 1)
      )
      expect GpuHostError:
        discard host.createGpuBuffer(
          namespace,
          indexBufferDescriptor(),
          newSeq[byte](12)
        )
      check context.bufferCreates == 0
      host.close()

    for missingCallback in 0 .. 2:
      let context = newContext()
      var value = context.backend
      case missingCallback
      of 0: value.createBuffer = nil
      of 1: value.updateBuffer = nil
      else: value.destroyResource = nil
      let host = openGpuHost(value, ghoOwned)
      let namespace = host.createGpuNamespace(
        "missing-" & $missingCallback,
        standardBudget()
      )
      if missingCallback == 1:
        let buffer = host.createGpuBuffer(
          namespace,
          indexBufferDescriptor(byteSize = 16, access = gbaDynamic)
        )
        expect GpuHostError:
          host.updateGpuBuffer(buffer, 0, @[0'u8, 0'u8])
        check context.bufferUpdates == 0
      else:
        expect GpuHostError:
          discard host.createGpuBuffer(
            namespace,
            indexBufferDescriptor(),
            newSeq[byte](12)
          )
        check context.bufferCreates == 0
      host.close()

  test "buffer update device loss invalidates mapped handles safely":
    let context = newContext()
    context.updateBufferStatus = gbsDeviceLost
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("update-loss", standardBudget())
    let buffer = host.createGpuBuffer(
      namespace,
      indexBufferDescriptor(byteSize = 16, access = gbaDynamic)
    )
    expect GpuHostError:
      host.updateGpuBuffer(buffer, 0, @[0'u8, 0'u8])
    check host.state == ghsDeviceLost
    check not host.isGpuResourceLive(buffer)
    check context.resourceDestroys == 0
    host.close()

  test "active frames reject buffer creation update and release":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("buffer-frame-lock", standardBudget())
    let buffer = host.createGpuBuffer(
      namespace,
      indexBufferDescriptor(byteSize = 16, access = gbaDynamic)
    )
    let frame = host.beginGpuFrame()
    expect GpuHostError:
      discard host.createGpuBuffer(
        namespace,
        indexBufferDescriptor(),
        newSeq[byte](12)
      )
    expect GpuHostError:
      host.updateGpuBuffer(buffer, 0, @[0'u8, 0'u8])
    expect GpuHostError:
      discard host.releaseGpuResource(buffer)
    host.endGpuFrame(frame)
    host.updateGpuBuffer(buffer, 0, @[0'u8, 0'u8])
    host.close()

suite "GPU resource namespace budgets":

  test "persistent byte and resource count budgets reject overflow":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("bounded", standardBudget())
    discard host.reserveGpuResource(namespace, grkBuffer, 1024)
    expect GpuHostError:
      discard host.reserveGpuResource(namespace, grkTexture, 1)
    discard host.reserveGpuResource(namespace, grkSampler, 0)
    expect GpuHostError:
      discard host.reserveGpuResource(namespace, grkPipeline, 0)
    host.close()

  test "frame budgets reset at the next frame and preserve persistent usage":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("motion", standardBudget())
    discard host.reserveGpuResource(namespace, grkBuffer, 100)

    let first = host.beginGpuFrame()
    host.reserveGpuFrameWork(namespace, 200, 100, 8)
    expect GpuHostError:
      host.reserveGpuFrameWork(namespace, 57, 0, 0)
    expect GpuHostError:
      host.reserveGpuFrameWork(namespace, 0, 29, 0)
    expect GpuHostError:
      host.reserveGpuFrameWork(namespace, 0, 0, 3)
    host.endGpuFrame(first)

    let second = host.beginGpuFrame()
    check host.gpuNamespaceUsage(namespace).persistentBytes == 100
    check host.gpuNamespaceUsage(namespace).transientBytes == 0
    check host.gpuNamespaceUsage(namespace).readbackBytes == 0
    check host.gpuNamespaceUsage(namespace).workUnits == 0
    host.reserveGpuFrameWork(namespace, 256, 128, 10)
    host.endGpuFrame(second)
    host.close()

  test "device loss invalidates handles while preserving namespaces":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("recoverable", standardBudget())
    let oldTexture = host.reserveGpuResource(namespace, grkTexture, 512)
    check host.markGpuDeviceLost()
    check not host.markGpuDeviceLost()
    check host.state == ghsDeviceLost
    check not host.isGpuResourceLive(oldTexture)
    check host.hasGpuNamespace(namespace)
    check host.gpuNamespaceUsage(namespace).persistentBytes == 0

    host.restoreGpuHost()
    check host.state == ghsReady
    check context.restores == 1
    check host.backendInfo.rendererName == "mock-restored"
    check not host.backendInfo.computeSupported
    let replacement = host.reserveGpuResource(namespace, grkTexture, 512)
    check replacement.generation != oldTexture.generation
    check host.isGpuResourceLive(replacement)
    host.close()

  test "namespace close releases accounting and rejects future use":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("temporary", standardBudget())
    let resource = host.reserveGpuResource(namespace, grkTexture, 100)
    check host.closeGpuNamespace(namespace)
    check not host.closeGpuNamespace(namespace)
    check not host.isGpuResourceLive(resource)
    expect GpuHostError:
      discard host.reserveGpuResource(namespace, grkTexture, 1)
    host.close()

  test "invalid namespace definitions are rejected":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    expect GpuHostError:
      discard host.createGpuNamespace("", standardBudget())
    expect GpuHostError:
      discard host.createGpuNamespace(
        "empty",
        GpuResourceBudget(persistentBytes: 10)
      )
    discard host.createGpuNamespace("duplicate", standardBudget())
    expect GpuHostError:
      discard host.createGpuNamespace("duplicate", standardBudget())
    expect GpuHostError:
      discard host.createGpuNamespace(
        repeat('x', maxGpuNamespaceNameBytes + 1),
        standardBudget()
      )
    host.close()
