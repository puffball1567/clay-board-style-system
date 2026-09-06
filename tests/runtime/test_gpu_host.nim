import std/[math, options, sequtils, strutils, unittest]

import clay_board_style_system/core/[computed_style, custom_paint, declaration,
    diagnostics, geometry, node, raster_surface, style_resolver, style_value]
import clay_board_style_system/generated/default_properties
import clay_board_style_system/hit/hit_test
import clay_board_style_system/layout/layout
import clay_board_style_system/paint/[paint, paint_command]
import clay_board_style_system/paint/gpu_direct_compositor
import clay_board_style_system/runtime/button
import clay_board_style_system/runtime/gpu_canvas
import clay_board_style_system/runtime/gpu_canvas_ui
import clay_board_style_system/runtime/gpu_direct_surface
import clay_board_style_system/runtime/gpu_display_surface
import clay_board_style_system/runtime/gpu_display_surface_ui
import clay_board_style_system/runtime/gpu_host
import clay_board_style_system/runtime/[invalidation, ui_root]

proc boxFor(layout: LayoutResult; node: NodeId): LayoutBox =
  for item in layout.boxes:
    if item.node == node:
      return item
  raise newException(ValueError, "layout box was not found")

type MockGpuContext = ref object of GpuBackendContext
  openStatus: GpuBackendStatus
  beginStatus: GpuBackendStatus
  endStatus: GpuBackendStatus
  resizeStatus: GpuBackendStatus
  restoreStatus: GpuBackendStatus
  createTextureStatus: GpuBackendStatus
  createBufferStatus: GpuBackendStatus
  updateBufferStatus: GpuBackendStatus
  createRenderTargetStatus: GpuBackendStatus
  createShaderStatus: GpuBackendStatus
  createUniformStatus: GpuBackendStatus
  createSamplerStatus: GpuBackendStatus
  createGraphicsPipelineStatus: GpuBackendStatus
  createComputePipelineStatus: GpuBackendStatus
  beginGraphicsPassStatus: GpuBackendStatus
  submitDrawStatus: GpuBackendStatus
  dispatchStatus: GpuBackendStatus
  copyTextureStatus: GpuBackendStatus
  requestReadbackStatus: GpuBackendStatus
  pollReadbackStatus: GpuBackendStatus
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
  renderTargetCreates: int
  shaderCreates: int
  uniformCreates: int
  samplerCreates: int
  graphicsPipelineCreates: int
  computePipelineCreates: int
  graphicsPassBegins: int
  drawSubmits: int
  computeDispatches: int
  textureCopies: int
  readbackRequests: int
  readbackPolls: int
  resourceDestroys: int
  nextBackendResource: uint64
  lastTexture: GpuTextureDescriptor
  lastTextureDataBytes: int
  lastBuffer: GpuBufferDescriptor
  lastBufferDataBytes: int
  lastBufferUpdateOffset: uint64
  lastBufferUpdateBytes: int
  lastRenderTarget: GpuRenderTargetDescriptor
  lastShader: GpuShaderDescriptor
  lastUniform: GpuUniformDescriptor
  lastSampler: GpuSamplerDescriptor
  lastShaderBytecodeBytes: int
  lastGraphicsPipeline: GpuGraphicsPipelineDescriptor
  lastComputePipeline: GpuComputePipelineDescriptor
  lastPipelineShaders: seq[uint64]
  lastViewId: uint16
  lastGraphicsPass: GpuGraphicsPassDescriptor
  lastDrawCommand: GpuDrawCommand
  lastComputeCommand: GpuComputeCommand
  lastBindings: GpuBackendBindingSet
  lastCopyRegion: GpuTextureCopyRegion
  lastCopySourceKind: GpuResourceKind
  lastReadbackBytes: uint64
  readbackReady: bool
  nextCompletionToken: uint64
  readbackSeed: int
  copySupported: bool
  readbackSupported: bool
  directTextureSupported: bool
  directRenderTargetSupported: bool
  directComputeOutputSupported: bool
  directFormats: set[GpuTextureFormat]
  maxDirectBuffers: uint8
  lastSubmissionResources: seq[uint64]
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
    textureCopySupported: state.copySupported,
    textureReadbackSupported: state.readbackSupported,
    directTexturePresentationSupported: state.directTextureSupported,
    directRenderTargetPresentationSupported: state.directRenderTargetSupported,
    directComputeOutputPresentationSupported: state.directComputeOutputSupported,
    directPresentationFormats: state.directFormats,
    maxDirectPresentationBuffers: state.maxDirectBuffers,
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
  info = GpuBackendInfo(
    rendererName: "mock-borrowed",
    textureCopySupported: state.copySupported,
    textureReadbackSupported: state.readbackSupported,
    directTexturePresentationSupported: state.directTextureSupported,
    directRenderTargetPresentationSupported: state.directRenderTargetSupported,
    directComputeOutputPresentationSupported: state.directComputeOutputSupported,
    directPresentationFormats: state.directFormats,
    maxDirectPresentationBuffers: state.maxDirectBuffers
  )
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

proc createRenderTarget(
    context: GpuBackendContext;
    descriptor: GpuRenderTargetDescriptor;
    resource: var GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  let state = context.mock
  inc state.renderTargetCreates
  state.lastRenderTarget = descriptor
  if state.createRenderTargetStatus == gbsOk:
    resource = GpuBackendResourceId(state.nextBackendResource)
    inc state.nextBackendResource
  state.createRenderTargetStatus

proc createShader(
    context: GpuBackendContext;
    descriptor: GpuShaderDescriptor;
    bytecode: seq[byte];
    resource: var GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  let state = context.mock
  inc state.shaderCreates
  state.lastShader = descriptor
  state.lastShaderBytecodeBytes = bytecode.len
  if state.createShaderStatus == gbsOk:
    resource = GpuBackendResourceId(state.nextBackendResource)
    inc state.nextBackendResource
  state.createShaderStatus

proc createUniform(
    context: GpuBackendContext;
    descriptor: GpuUniformDescriptor;
    resource: var GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  let state = context.mock
  inc state.uniformCreates
  state.lastUniform = descriptor
  if state.createUniformStatus == gbsOk:
    resource = GpuBackendResourceId(state.nextBackendResource)
    inc state.nextBackendResource
  state.createUniformStatus

proc createSampler(
    context: GpuBackendContext;
    descriptor: GpuSamplerDescriptor;
    resource: var GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  let state = context.mock
  inc state.samplerCreates
  state.lastSampler = descriptor
  if state.createSamplerStatus == gbsOk:
    resource = GpuBackendResourceId(state.nextBackendResource)
    inc state.nextBackendResource
  state.createSamplerStatus

proc createGraphicsPipeline(
    context: GpuBackendContext;
    descriptor: GpuGraphicsPipelineDescriptor;
    vertexShader, fragmentShader: GpuBackendResourceId;
    resource: var GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  let state = context.mock
  inc state.graphicsPipelineCreates
  state.lastGraphicsPipeline = descriptor
  state.lastPipelineShaders = @[
    vertexShader.backendResourceIdValue(),
    fragmentShader.backendResourceIdValue()
  ]
  if state.createGraphicsPipelineStatus == gbsOk:
    resource = GpuBackendResourceId(state.nextBackendResource)
    inc state.nextBackendResource
  state.createGraphicsPipelineStatus

proc createComputePipeline(
    context: GpuBackendContext;
    descriptor: GpuComputePipelineDescriptor;
    computeShader: GpuBackendResourceId;
    resource: var GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  let state = context.mock
  inc state.computePipelineCreates
  state.lastComputePipeline = descriptor
  state.lastPipelineShaders = @[computeShader.backendResourceIdValue()]
  if state.createComputePipelineStatus == gbsOk:
    resource = GpuBackendResourceId(state.nextBackendResource)
    inc state.nextBackendResource
  state.createComputePipelineStatus

proc beginGraphicsPass(
    context: GpuBackendContext;
    viewId: uint16;
    pass: GpuGraphicsPassDescriptor;
    renderTarget: GpuBackendResourceId
): GpuBackendStatus {.raises: [].} =
  let state = context.mock
  inc state.graphicsPassBegins
  state.lastViewId = viewId
  state.lastGraphicsPass = pass
  state.lastSubmissionResources = @[renderTarget.backendResourceIdValue()]
  state.beginGraphicsPassStatus

proc submitDraw(
    context: GpuBackendContext;
    viewId: uint16;
    pipeline, vertexBuffer, indexBuffer: GpuBackendResourceId;
    pipelineDescriptor: GpuGraphicsPipelineDescriptor;
    vertexDescriptor, indexDescriptor: GpuBufferDescriptor;
    bindings: GpuBackendBindingSet;
    command: GpuDrawCommand
): GpuBackendStatus {.raises: [].} =
  discard pipelineDescriptor
  discard vertexDescriptor
  discard indexDescriptor
  let state = context.mock
  inc state.drawSubmits
  state.lastViewId = viewId
  state.lastDrawCommand = command
  state.lastBindings = bindings
  state.lastSubmissionResources = @[
    pipeline.backendResourceIdValue(),
    vertexBuffer.backendResourceIdValue(),
    indexBuffer.backendResourceIdValue()
  ]
  state.submitDrawStatus

proc dispatch(
    context: GpuBackendContext;
    viewId: uint16;
    pipeline: GpuBackendResourceId;
    bindings: GpuBackendBindingSet;
    command: GpuComputeCommand
): GpuBackendStatus {.raises: [].} =
  let state = context.mock
  inc state.computeDispatches
  state.lastViewId = viewId
  state.lastComputeCommand = command
  state.lastBindings = bindings
  state.lastSubmissionResources = @[pipeline.backendResourceIdValue()]
  state.dispatchStatus

proc copyTexture(
    context: GpuBackendContext;
    viewId: uint16;
    source: GpuBackendResourceId;
    sourceKind: GpuResourceKind;
    destination: GpuBackendResourceId;
    region: GpuTextureCopyRegion
): GpuBackendStatus {.raises: [].} =
  let state = context.mock
  inc state.textureCopies
  state.lastViewId = viewId
  state.lastCopySourceKind = sourceKind
  state.lastCopyRegion = region
  state.lastSubmissionResources = @[
    source.backendResourceIdValue(),
    destination.backendResourceIdValue()
  ]
  state.copyTextureStatus

proc requestReadback(
    context: GpuBackendContext;
    texture: GpuBackendResourceId;
    descriptor: GpuTextureDescriptor;
    destination: pointer;
    destinationBytes: uint64;
    completionToken: var uint64
): GpuBackendStatus {.raises: [].} =
  discard descriptor
  let state = context.mock
  inc state.readbackRequests
  state.lastSubmissionResources = @[texture.backendResourceIdValue()]
  state.lastReadbackBytes = destinationBytes
  if state.requestReadbackStatus == gbsOk:
    let bytes = cast[ptr UncheckedArray[byte]](destination)
    for index in 0 ..< int(destinationBytes):
      bytes[index] = byte((index + state.readbackSeed) mod 251)
    inc state.readbackSeed
    completionToken = state.nextCompletionToken
    inc state.nextCompletionToken
  state.requestReadbackStatus

proc pollReadback(
    context: GpuBackendContext;
    completionToken: uint64;
    ready: var bool
): GpuBackendStatus {.raises: [].} =
  discard completionToken
  let state = context.mock
  inc state.readbackPolls
  ready = state.readbackReady
  state.pollReadbackStatus

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
    createRenderTarget: createRenderTarget,
    createShader: createShader,
    createUniform: createUniform,
    createSampler: createSampler,
    createGraphicsPipeline: createGraphicsPipeline,
    createComputePipeline: createComputePipeline,
    beginGraphicsPass: beginGraphicsPass,
    submitDraw: submitDraw,
    dispatch: dispatch,
    copyTexture: copyTexture,
    requestReadback: requestReadback,
    pollReadback: pollReadback,
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
    createRenderTargetStatus: gbsOk,
    createShaderStatus: gbsOk,
    createUniformStatus: gbsOk,
    createSamplerStatus: gbsOk,
    createGraphicsPipelineStatus: gbsOk,
    createComputePipelineStatus: gbsOk,
    beginGraphicsPassStatus: gbsOk,
    submitDrawStatus: gbsOk,
    dispatchStatus: gbsOk,
    copyTextureStatus: gbsOk,
    requestReadbackStatus: gbsOk,
    pollReadbackStatus: gbsOk,
    nextCompletionToken: 1,
    copySupported: true,
    readbackSupported: true,
    nextBackendResource: 1
  )

proc presentationConfig(): GpuHostConfig =
  GpuHostConfig(width: 1280, height: 720, resetFlags: 7, presentation: true)

proc enableDirectPresentation(
    context: MockGpuContext;
    formats: set[GpuTextureFormat] = {gtfRgba8};
    maxBuffers = 3'u8;
    textures = true;
    renderTargets = true;
    computeOutput = true
) =
  context.directTextureSupported = textures
  context.directRenderTargetSupported = renderTargets
  context.directComputeOutputSupported = computeOutput
  context.directFormats = formats
  context.maxDirectBuffers = maxBuffers

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

proc storageBufferDescriptor(
    byteSize = 64'u64;
    access = gbaDynamic;
    storageFormat = gsbfFloat32x4;
    storageAccess = gsaReadWrite;
    label = "storage"
): GpuBufferDescriptor =
  GpuBufferDescriptor(
    byteSize: byteSize,
    role: gbrStorage,
    access: access,
    storageFormat: storageFormat,
    storageAccess: storageAccess,
    label: label
  )

proc renderTargetDescriptor(
    width = 8'u32;
    height = 8'u32;
    format = gtfRgba8;
    usage = {gtuRenderTarget, gtuSampled};
    label = "render-target"
): GpuRenderTargetDescriptor =
  GpuRenderTargetDescriptor(
    width: width,
    height: height,
    format: format,
    usage: usage,
    label: label
  )

proc shaderDescriptor(
    stage = gssVertex;
    label = "shader"
): GpuShaderDescriptor =
  GpuShaderDescriptor(stage: stage, label: label)

proc graphicsPipelineDescriptor(
    vertexShader, fragmentShader: GpuResourceHandle;
    label = "graphics-pipeline"
): GpuGraphicsPipelineDescriptor =
  GpuGraphicsPipelineDescriptor(
    vertexShader: vertexShader,
    fragmentShader: fragmentShader,
    vertexLayout: positionColorLayout(),
    colorFormat: gtfRgba8,
    topology: gptTriangleList,
    cullMode: gcmBack,
    frontFace: gffCounterClockwise,
    blend: alphaGpuBlendState(),
    label: label
  )

proc computePipelineDescriptor(
    computeShader: GpuResourceHandle;
    label = "compute-pipeline"
): GpuComputePipelineDescriptor =
  GpuComputePipelineDescriptor(
    computeShader: computeShader,
    label: label
  )

proc graphicsPass(
    width = 640'u32;
    height = 480'u32;
    renderTarget = GpuResourceHandle()
): GpuGraphicsPassDescriptor =
  GpuGraphicsPassDescriptor(
    viewport: GpuViewport(width: width, height: height),
    renderTarget: renderTarget
  )

proc createDrawingResources(
    host: GpuHost;
    namespace: GpuNamespaceId
): tuple[
    pipeline, vertexBuffer, indexBuffer: GpuResourceHandle
  ] =
  let vertexShader = host.createGpuShader(
    namespace,
    shaderDescriptor(gssVertex, "draw-vertex"),
    @[1'u8]
  )
  let fragmentShader = host.createGpuShader(
    namespace,
    shaderDescriptor(gssFragment, "draw-fragment"),
    @[2'u8]
  )
  result.pipeline = host.createGpuGraphicsPipeline(
    namespace,
    graphicsPipelineDescriptor(vertexShader, fragmentShader)
  )
  result.vertexBuffer = host.createGpuBuffer(
    namespace,
    vertexBufferDescriptor(),
    newSeq[byte](24)
  )
  result.indexBuffer = host.createGpuBuffer(
    namespace,
    indexBufferDescriptor(),
    newSeq[byte](12)
  )

proc uniformDescriptor(
    name = "u_cbssValue";
    uniformType = gutVec4;
    arrayLength = 1'u16;
    label = "uniform"
): GpuUniformDescriptor =
  GpuUniformDescriptor(
    name: name,
    uniformType: uniformType,
    arrayLength: arrayLength,
    label: label
  )

proc samplerDescriptor(
    name = "s_cbssTexture";
    label = "sampler"
): GpuSamplerDescriptor =
  GpuSamplerDescriptor(
    name: name,
    addressU: gsamClamp,
    addressV: gsamClamp,
    addressW: gsamClamp,
    minFilter: gsfLinear,
    magFilter: gsfLinear,
    mipFilter: gsfLinear,
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

  test "inconsistent direct presentation capabilities close the opened backend":
    let owned = newContext()
    owned.directFormats = {gtfRgba8}
    owned.maxDirectBuffers = 2
    expect GpuHostError:
      discard openGpuHost(owned.backend, ghoOwned)
    check owned.ownedOpens == 1
    check owned.ownedCloses == 1

    let borrowed = newContext()
    borrowed.directTextureSupported = true
    borrowed.directFormats = {gtfRgba8}
    borrowed.maxDirectBuffers = 1
    expect GpuHostError:
      discard openGpuHost(borrowed.backend, ghoBorrowed)
    check borrowed.borrowedAttaches == 1
    check borrowed.borrowedDetaches == 1

  test "failed restoration preserves device-lost state and backend information":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("not-restored", standardBudget())
    var handlerCalls = 0
    host.setGpuNamespaceRestoreHandler(namespace,
      proc(
          restoringHost: GpuHost;
          restoringNamespace: GpuNamespaceId;
          previousGeneration, generation: uint64
      ): GpuNamespaceRestoreStatus {.raises: [].} =
        discard restoringHost
        discard restoringNamespace
        discard previousGeneration
        discard generation
        inc handlerCalls
        gnrsRestored
    )
    let originalInfo = host.backendInfo
    check host.markGpuDeviceLost()
    context.restoreStatus = gbsFailed
    expect GpuHostError:
      host.restoreGpuHost()
    check host.state == ghsDeviceLost
    check host.backendInfo == originalInfo
    check handlerCalls == 0
    host.close()

  test "namespace restoration runs in deterministic order and replaces stale resources":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let first = host.createGpuNamespace("first", standardBudget())
    let second = host.createGpuNamespace("second", standardBudget())
    let stale = host.reserveGpuResource(first, grkTexture, 128)
    var restoreOrder: seq[uint64]
    var firstReplacement, secondReplacement: GpuResourceHandle
    var observedPrevious, observedCurrent: uint64
    var crossNamespaceRejected = false

    host.setGpuNamespaceRestoreHandler(first,
      proc(
          restoringHost: GpuHost;
          namespace: GpuNamespaceId;
          previousGeneration, generation: uint64
      ): GpuNamespaceRestoreStatus {.raises: [].} =
        restoreOrder.add namespace.namespaceIdValue()
        observedPrevious = previousGeneration
        observedCurrent = generation
        try:
          firstReplacement = restoringHost.reserveGpuResource(
            namespace,
            grkTexture,
            128
          )
          gnrsRestored
        except CatchableError:
          gnrsFailed
    )
    host.setGpuNamespaceRestoreHandler(second,
      proc(
          restoringHost: GpuHost;
          namespace: GpuNamespaceId;
          previousGeneration, generation: uint64
      ): GpuNamespaceRestoreStatus {.raises: [].} =
        discard previousGeneration
        discard generation
        restoreOrder.add namespace.namespaceIdValue()
        try:
          discard restoringHost.reserveGpuResource(first, grkBuffer, 1)
        except CatchableError:
          crossNamespaceRejected = true
        try:
          secondReplacement = restoringHost.reserveGpuResource(
            namespace,
            grkBuffer,
            64
          )
          gnrsRestored
        except CatchableError:
          gnrsFailed
    )

    check host.markGpuDeviceLost()
    let report = host.restoreGpuHostWithReport()

    check report.previousGeneration == 1
    check report.generation == 2
    check observedPrevious == report.previousGeneration
    check observedCurrent == report.generation
    check restoreOrder == @[
      first.namespaceIdValue(),
      second.namespaceIdValue()
    ]
    check report.namespaces.len == 2
    check report.namespaces[0].namespace == first
    check report.namespaces[0].status == gnrsRestored
    check report.namespaces[1].namespace == second
    check report.namespaces[1].status == gnrsRestored
    check not host.isGpuResourceLive(stale)
    check host.isGpuResourceLive(firstReplacement)
    check host.isGpuResourceLive(secondReplacement)
    check crossNamespaceRejected
    check host.gpuNamespaceUsage(first).persistentBytes == 128
    check host.gpuNamespaceUsage(second).persistentBytes == 64
    host.close()

  test "failed namespace restoration rolls back only its partial resources":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let skipped = host.createGpuNamespace("skipped", standardBudget())
    let failed = host.createGpuNamespace("failed", standardBudget())
    let successful = host.createGpuNamespace("successful", standardBudget())
    var failedPartial, successfulReplacement: GpuResourceHandle

    host.setGpuNamespaceRestoreHandler(failed,
      proc(
          restoringHost: GpuHost;
          namespace: GpuNamespaceId;
          previousGeneration, generation: uint64
      ): GpuNamespaceRestoreStatus {.raises: [].} =
        discard previousGeneration
        discard generation
        try:
          failedPartial = restoringHost.createGpuTexture(
            namespace,
            textureDescriptor(width = 4, height = 4, label = "partial")
          )
        except CatchableError:
          return gnrsFailed
        gnrsFailed
    )
    host.setGpuNamespaceRestoreHandler(successful,
      proc(
          restoringHost: GpuHost;
          namespace: GpuNamespaceId;
          previousGeneration, generation: uint64
      ): GpuNamespaceRestoreStatus {.raises: [].} =
        discard previousGeneration
        discard generation
        try:
          successfulReplacement = restoringHost.createGpuTexture(
            namespace,
            textureDescriptor(width = 4, height = 4, label = "restored")
          )
          gnrsRestored
        except CatchableError:
          gnrsFailed
    )

    check host.markGpuDeviceLost()
    let report = host.restoreGpuHostWithReport()

    check report.namespaces.len == 3
    check report.namespaces[0].namespace == skipped
    check report.namespaces[0].status == gnrsSkipped
    check report.namespaces[1].namespace == failed
    check report.namespaces[1].status == gnrsFailed
    check report.namespaces[2].namespace == successful
    check report.namespaces[2].status == gnrsRestored
    check not host.isGpuResourceLive(failedPartial)
    check host.gpuNamespaceUsage(failed).resourceCount == 0
    check host.gpuNamespaceUsage(failed).persistentBytes == 0
    check host.isGpuResourceLive(successfulReplacement)
    check context.textureCreates == 2
    check context.resourceDestroys == 1
    host.close()

  test "restoration callbacks cannot mutate host structure or start work":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned, presentationConfig())
    let namespace = host.createGpuNamespace("guarded", standardBudget())
    var rejectedOperations = 0

    host.setGpuNamespaceRestoreHandler(namespace,
      proc(
          restoringHost: GpuHost;
          restoringNamespace: GpuNamespaceId;
          previousGeneration, generation: uint64
      ): GpuNamespaceRestoreStatus {.raises: [].} =
        discard previousGeneration
        discard generation
        try:
          discard restoringHost.createGpuNamespace("nested", standardBudget())
        except CatchableError:
          inc rejectedOperations
        try:
          discard restoringHost.closeGpuNamespace(restoringNamespace)
        except CatchableError:
          inc rejectedOperations
        try:
          restoringHost.setGpuNamespaceRestoreHandler(restoringNamespace, nil)
        except CatchableError:
          inc rejectedOperations
        try:
          discard restoringHost.beginGpuFrame()
        except CatchableError:
          inc rejectedOperations
        try:
          restoringHost.resizeGpuHost(640, 480)
        except CatchableError:
          inc rejectedOperations
        try:
          discard restoringHost.markGpuDeviceLost()
        except CatchableError:
          inc rejectedOperations
        try:
          restoringHost.close()
        except CatchableError:
          inc rejectedOperations
        gnrsRestored
    )

    check host.markGpuDeviceLost()
    let report = host.restoreGpuHostWithReport()
    check report.namespaces.len == 1
    check report.namespaces[0].status == gnrsRestored
    check rejectedOperations == 7
    check host.state == ghsReady
    check context.resizes == 0
    check context.begins == 0
    host.close()

  test "device loss during a restoration callback can be retried cleanly":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("retry", standardBudget())
    var replacement: GpuResourceHandle

    host.setGpuNamespaceRestoreHandler(namespace,
      proc(
          restoringHost: GpuHost;
          restoringNamespace: GpuNamespaceId;
          previousGeneration, generation: uint64
      ): GpuNamespaceRestoreStatus {.raises: [].} =
        discard previousGeneration
        discard generation
        try:
          replacement = restoringHost.createGpuTexture(
            restoringNamespace,
            textureDescriptor(width = 4, height = 4, label = "retry")
          )
          gnrsRestored
        except CatchableError:
          gnrsFailed
    )

    check host.markGpuDeviceLost()
    context.createTextureStatus = gbsDeviceLost
    expect GpuHostError:
      discard host.restoreGpuHostWithReport()
    check host.state == ghsDeviceLost
    check host.generation == 3
    check not host.isGpuResourceLive(replacement)

    context.createTextureStatus = gbsOk
    let report = host.restoreGpuHostWithReport()
    check report.previousGeneration == 2
    check report.generation == 3
    check report.namespaces.len == 1
    check report.namespaces[0].status == gnrsRestored
    check host.isGpuResourceLive(replacement)
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
      let bytesPerPixel =
        case format
        of gtfR8: 1'u64
        of gtfR16F: 2'u64
        of gtfRgba8, gtfBgra8, gtfR32F, gtfRg16F: 4'u64
        of gtfRg32F, gtfRgba16F: 8'u64
        of gtfRgba32F: 16'u64
      let expectedBytes = 64'u64 * bytesPerPixel
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
      discard host.reserveGpuResource(namespace, grkBuffer, 0)
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

  test "storage buffers retain typed element and shader access metadata":
    for format in GpuStorageBufferFormat:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace("storage-" & $format, standardBudget())
      let elementBytes = format.storageBufferElementBytes()
      let descriptor = storageBufferDescriptor(
        byteSize = elementBytes * 4,
        storageFormat = format
      )
      let buffer = host.createGpuBuffer(namespace, descriptor)
      check buffer.kind == grkBuffer
      check context.lastBuffer == descriptor
      check host.gpuNamespaceUsage(namespace).persistentBytes == elementBytes * 4
      host.close()
      check context.resourceDestroys == 1

  test "CPU updates are limited to compute-read storage buffers":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("storage-updates", standardBudget())
    let readable = host.createGpuBuffer(
      namespace,
      storageBufferDescriptor(
        byteSize = 32,
        storageFormat = gsbfFloat32x2,
        storageAccess = gsaRead
      )
    )
    host.updateGpuBuffer(readable, 8, newSeq[byte](16))
    check context.bufferUpdates == 1

    check host.releaseGpuResource(readable)
    let writable = host.createGpuBuffer(
      namespace,
      storageBufferDescriptor(storageAccess = gsaReadWrite)
    )
    expect GpuHostError:
      host.updateGpuBuffer(writable, 0, newSeq[byte](16))
    check context.bufferUpdates == 1
    host.close()

  test "storage descriptors reject layout misalignment and unsupported compute":
    block invalidDescriptors:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace("invalid-storage", standardBudget())
      var withLayout = storageBufferDescriptor()
      withLayout.vertexLayout = positionColorLayout()
      for descriptor in [
        storageBufferDescriptor(byteSize = 12, storageFormat = gsbfFloat32x4),
        withLayout
      ]:
        expect GpuHostError:
          discard host.createGpuBuffer(namespace, descriptor)
      check context.bufferCreates == 0
      host.close()

    block unsupportedCompute:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoBorrowed)
      let namespace = host.createGpuNamespace("no-compute-storage", standardBudget())
      expect GpuHostError:
        discard host.createGpuBuffer(namespace, storageBufferDescriptor())
      check context.bufferCreates == 0
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

suite "GPU render target mapping":
  test "offscreen color targets are accounted and destroyed":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("render-target", standardBudget())
    let descriptor = renderTargetDescriptor(
      width = 8,
      height = 4,
      format = gtfBgra8,
      usage = {gtuRenderTarget, gtuSampled, gtuBlitSource},
      label = "panel-layer"
    )
    let target = host.createGpuRenderTarget(namespace, descriptor)

    check target.kind == grkRenderTarget
    check host.isGpuResourceLive(target)
    check context.renderTargetCreates == 1
    check context.lastRenderTarget == descriptor
    check host.gpuNamespaceUsage(namespace).persistentBytes == 8'u64 * 4 * 4
    check host.gpuNamespaceUsage(namespace).resourceCount == 1

    check host.releaseGpuResource(target)
    check context.resourceDestroys == 1
    check context.destroyedResources == @[1'u64]
    check host.gpuNamespaceUsage(namespace) == GpuResourceUsage()
    host.close()

  test "render target validation happens before backend allocation":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("invalid-targets", standardBudget())

    for descriptor in [
      renderTargetDescriptor(width = 0),
      renderTargetDescriptor(height = 0),
      renderTargetDescriptor(width = 8193),
      renderTargetDescriptor(usage = {gtuSampled}),
      renderTargetDescriptor(usage = {gtuRenderTarget, gtuReadback}),
      renderTargetDescriptor(label = repeat('x', maxGpuResourceLabelBytes + 1))
    ]:
      expect GpuHostError:
        discard host.createGpuRenderTarget(namespace, descriptor)

    check context.renderTargetCreates == 0
    check host.gpuNamespaceUsage(namespace) == GpuResourceUsage()
    host.close()

  test "render target budget callback and backend failures preserve accounting":
    block budgetFailure:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "target-budget",
        GpuResourceBudget(persistentBytes: 255, maxResources: 1)
      )
      expect GpuHostError:
        discard host.createGpuRenderTarget(namespace, renderTargetDescriptor())
      check context.renderTargetCreates == 0
      host.close()

    block missingCallback:
      let context = newContext()
      var value = context.backend
      value.createRenderTarget = nil
      let host = openGpuHost(value, ghoOwned)
      let namespace = host.createGpuNamespace("missing-target", standardBudget())
      expect GpuHostError:
        discard host.createGpuRenderTarget(namespace, renderTargetDescriptor())
      check context.renderTargetCreates == 0
      host.close()

    block backendFailure:
      let context = newContext()
      context.createRenderTargetStatus = gbsFailed
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace("failed-target", standardBudget())
      expect GpuHostError:
        discard host.createGpuRenderTarget(namespace, renderTargetDescriptor())
      check context.renderTargetCreates == 1
      check context.resourceDestroys == 0
      check host.gpuNamespaceUsage(namespace) == GpuResourceUsage()
      host.close()

  test "render target device loss and frame boundaries invalidate safely":
    block deviceLoss:
      let context = newContext()
      context.createRenderTargetStatus = gbsDeviceLost
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace("target-loss", standardBudget())
      expect GpuHostError:
        discard host.createGpuRenderTarget(namespace, renderTargetDescriptor())
      check host.state == ghsDeviceLost
      check context.resourceDestroys == 0
      host.close()

    block activeFrame:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace("target-frame", standardBudget())
      let token = host.beginGpuFrame()
      expect GpuHostError:
        discard host.createGpuRenderTarget(namespace, renderTargetDescriptor())
      check context.renderTargetCreates == 0
      host.endGpuFrame(token)
      let target = host.createGpuRenderTarget(namespace, renderTargetDescriptor())
      check host.isGpuResourceLive(target)
      host.close()
      check context.resourceDestroys == 1

suite "GPU shader mapping":
  test "compiled shader bytecode is accounted and destroyed":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("shader", standardBudget())
    let descriptor = shaderDescriptor(gssFragment, "panel-fragment")
    let bytecode = @[0x43'u8, 0x42'u8, 0x53'u8, 0x53'u8]
    let shader = host.createGpuShader(namespace, descriptor, bytecode)

    check shader.kind == grkShader
    check host.isGpuResourceLive(shader)
    check context.shaderCreates == 1
    check context.lastShader == descriptor
    check context.lastShaderBytecodeBytes == bytecode.len
    check host.gpuNamespaceUsage(namespace).persistentBytes == 4
    check host.gpuNamespaceUsage(namespace).resourceCount == 1

    check host.releaseGpuResource(shader)
    check context.resourceDestroys == 1
    check context.destroyedResources == @[1'u64]
    check host.gpuNamespaceUsage(namespace) == GpuResourceUsage()
    host.close()

  test "shader validation happens before backend allocation":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("invalid-shaders", standardBudget())

    expect GpuHostError:
      discard host.createGpuShader(namespace, shaderDescriptor(), @[])
    expect GpuHostError:
      discard host.createGpuShader(
        namespace,
        shaderDescriptor(label = repeat('x', maxGpuResourceLabelBytes + 1)),
        @[1'u8]
      )
    check context.shaderCreates == 0
    check host.gpuNamespaceUsage(namespace) == GpuResourceUsage()
    host.close()

    let noComputeContext = newContext()
    var noComputeBackend = noComputeContext.backend
    noComputeBackend.openOwned = proc(
        context: GpuBackendContext;
        config: GpuHostConfig;
        info: var GpuBackendInfo
    ): GpuBackendStatus {.nimcall, raises: [].} =
      discard context
      discard config
      info = GpuBackendInfo(rendererName: "no-compute", computeSupported: false)
      gbsOk
    let noComputeHost = openGpuHost(noComputeBackend, ghoOwned)
    let noComputeNamespace = noComputeHost.createGpuNamespace(
      "no-compute-shader",
      standardBudget()
    )
    expect GpuHostError:
      discard noComputeHost.createGpuShader(
        noComputeNamespace,
        shaderDescriptor(gssCompute),
        @[1'u8]
      )
    check noComputeContext.shaderCreates == 0
    noComputeHost.close()

  test "shader budget callback and backend failures preserve accounting":
    block budgetFailure:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "shader-budget",
        GpuResourceBudget(persistentBytes: 3, maxResources: 1)
      )
      expect GpuHostError:
        discard host.createGpuShader(
          namespace,
          shaderDescriptor(),
          @[1'u8, 2'u8, 3'u8, 4'u8]
        )
      check context.shaderCreates == 0
      host.close()

    block missingCallback:
      let context = newContext()
      var value = context.backend
      value.createShader = nil
      let host = openGpuHost(value, ghoOwned)
      let namespace = host.createGpuNamespace("missing-shader", standardBudget())
      expect GpuHostError:
        discard host.createGpuShader(namespace, shaderDescriptor(), @[1'u8])
      check context.shaderCreates == 0
      host.close()

    block backendFailure:
      let context = newContext()
      context.createShaderStatus = gbsFailed
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace("failed-shader", standardBudget())
      expect GpuHostError:
        discard host.createGpuShader(namespace, shaderDescriptor(), @[1'u8])
      check context.shaderCreates == 1
      check context.resourceDestroys == 0
      check host.gpuNamespaceUsage(namespace) == GpuResourceUsage()
      host.close()

  test "shader device loss and frame boundaries invalidate safely":
    block deviceLoss:
      let context = newContext()
      context.createShaderStatus = gbsDeviceLost
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace("shader-loss", standardBudget())
      expect GpuHostError:
        discard host.createGpuShader(namespace, shaderDescriptor(), @[1'u8])
      check host.state == ghsDeviceLost
      check context.resourceDestroys == 0
      host.close()

    block activeFrame:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace("shader-frame", standardBudget())
      let token = host.beginGpuFrame()
      expect GpuHostError:
        discard host.createGpuShader(namespace, shaderDescriptor(), @[1'u8])
      check context.shaderCreates == 0
      host.endGpuFrame(token)
      let shader = host.createGpuShader(namespace, shaderDescriptor(), @[1'u8])
      check host.isGpuResourceLive(shader)
      host.close()
      check context.resourceDestroys == 1

suite "GPU pipeline mapping":
  test "graphics and compute pipelines retain typed shader dependencies":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "pipelines",
      GpuResourceBudget(persistentBytes: 32, maxResources: 5)
    )
    let vertex = host.createGpuShader(
      namespace,
      shaderDescriptor(gssVertex, "vertex"),
      @[1'u8]
    )
    let fragment = host.createGpuShader(
      namespace,
      shaderDescriptor(gssFragment, "fragment"),
      @[2'u8]
    )
    let graphicsDescriptor = graphicsPipelineDescriptor(vertex, fragment)
    let graphics = host.createGpuGraphicsPipeline(namespace, graphicsDescriptor)

    check graphics.kind == grkPipeline
    check host.isGpuResourceLive(graphics)
    check context.graphicsPipelineCreates == 1
    check context.lastGraphicsPipeline == graphicsDescriptor
    check context.lastPipelineShaders == @[1'u64, 2'u64]
    check host.gpuNamespaceUsage(namespace).persistentBytes == 2
    check host.gpuNamespaceUsage(namespace).resourceCount == 3
    expect GpuHostError:
      discard host.releaseGpuResource(vertex)

    check host.releaseGpuResource(graphics)
    check host.releaseGpuResource(vertex)
    check host.releaseGpuResource(fragment)

    let compute = host.createGpuShader(
      namespace,
      shaderDescriptor(gssCompute, "compute"),
      @[3'u8]
    )
    let computeDescriptor = computePipelineDescriptor(compute)
    let computePipeline = host.createGpuComputePipeline(
      namespace,
      computeDescriptor
    )
    check context.computePipelineCreates == 1
    check context.lastComputePipeline == computeDescriptor
    check context.lastPipelineShaders == @[4'u64]
    expect GpuHostError:
      discard host.releaseGpuResource(compute)
    check host.releaseGpuResource(computePipeline)
    check host.releaseGpuResource(compute)
    check host.gpuNamespaceUsage(namespace) == GpuResourceUsage()
    host.close()

  test "pipeline validation rejects unsafe shader relationships before backend work":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let budget = GpuResourceBudget(persistentBytes: 64, maxResources: 12)
    let first = host.createGpuNamespace("first-pipelines", budget)
    let second = host.createGpuNamespace("second-pipelines", budget)
    let vertex = host.createGpuShader(first, shaderDescriptor(gssVertex), @[1'u8])
    let fragment = host.createGpuShader(
      first,
      shaderDescriptor(gssFragment),
      @[2'u8]
    )
    let foreignFragment = host.createGpuShader(
      second,
      shaderDescriptor(gssFragment),
      @[3'u8]
    )

    expect GpuHostError:
      discard host.createGpuGraphicsPipeline(
        first,
        graphicsPipelineDescriptor(vertex, foreignFragment)
      )
    expect GpuHostError:
      discard host.createGpuGraphicsPipeline(
        first,
        graphicsPipelineDescriptor(fragment, vertex)
      )
    var noWrites = graphicsPipelineDescriptor(vertex, fragment)
    noWrites.blend.writeMask = {}
    expect GpuHostError:
      discard host.createGpuGraphicsPipeline(first, noWrites)
    var noLayout = graphicsPipelineDescriptor(vertex, fragment)
    noLayout.vertexLayout = @[]
    expect GpuHostError:
      discard host.createGpuGraphicsPipeline(first, noLayout)
    expect GpuHostError:
      discard host.createGpuGraphicsPipeline(
        first,
        graphicsPipelineDescriptor(
          vertex,
          fragment,
          repeat('p', maxGpuResourceLabelBytes + 1)
        )
      )
    expect GpuHostError:
      discard host.createGpuComputePipeline(
        first,
        computePipelineDescriptor(vertex)
      )
    check context.graphicsPipelineCreates == 0
    check context.computePipelineCreates == 0
    host.close()

  test "pipeline callback budget and backend failures preserve accounting":
    block missingCallback:
      let context = newContext()
      var value = context.backend
      value.createGraphicsPipeline = nil
      let host = openGpuHost(value, ghoOwned)
      let namespace = host.createGpuNamespace(
        "missing-pipeline",
        GpuResourceBudget(persistentBytes: 8, maxResources: 3)
      )
      let vertex = host.createGpuShader(
        namespace,
        shaderDescriptor(gssVertex),
        @[1'u8]
      )
      let fragment = host.createGpuShader(
        namespace,
        shaderDescriptor(gssFragment),
        @[2'u8]
      )
      expect GpuHostError:
        discard host.createGpuGraphicsPipeline(
          namespace,
          graphicsPipelineDescriptor(vertex, fragment)
        )
      check context.graphicsPipelineCreates == 0
      host.close()

    block resourceBudget:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "pipeline-budget",
        GpuResourceBudget(persistentBytes: 8, maxResources: 2)
      )
      let vertex = host.createGpuShader(
        namespace,
        shaderDescriptor(gssVertex),
        @[1'u8]
      )
      let fragment = host.createGpuShader(
        namespace,
        shaderDescriptor(gssFragment),
        @[2'u8]
      )
      expect GpuHostError:
        discard host.createGpuGraphicsPipeline(
          namespace,
          graphicsPipelineDescriptor(vertex, fragment)
        )
      check context.graphicsPipelineCreates == 0
      host.close()

    block backendFailure:
      let context = newContext()
      context.createGraphicsPipelineStatus = gbsFailed
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "failed-pipeline",
        GpuResourceBudget(persistentBytes: 8, maxResources: 3)
      )
      let vertex = host.createGpuShader(
        namespace,
        shaderDescriptor(gssVertex),
        @[1'u8]
      )
      let fragment = host.createGpuShader(
        namespace,
        shaderDescriptor(gssFragment),
        @[2'u8]
      )
      expect GpuHostError:
        discard host.createGpuGraphicsPipeline(
          namespace,
          graphicsPipelineDescriptor(vertex, fragment)
        )
      check context.graphicsPipelineCreates == 1
      check host.gpuNamespaceUsage(namespace).resourceCount == 2
      check context.resourceDestroys == 0
      host.close()

  test "pipeline device loss frame boundaries and teardown order are safe":
    block deviceLoss:
      let context = newContext()
      context.createComputePipelineStatus = gbsDeviceLost
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "pipeline-loss",
        GpuResourceBudget(persistentBytes: 8, maxResources: 2)
      )
      let compute = host.createGpuShader(
        namespace,
        shaderDescriptor(gssCompute),
        @[1'u8]
      )
      expect GpuHostError:
        discard host.createGpuComputePipeline(
          namespace,
          computePipelineDescriptor(compute)
        )
      check host.state == ghsDeviceLost
      check not host.isGpuResourceLive(compute)
      host.close()

    block activeFrame:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "pipeline-frame",
        GpuResourceBudget(persistentBytes: 8, maxResources: 3)
      )
      let vertex = host.createGpuShader(
        namespace,
        shaderDescriptor(gssVertex),
        @[1'u8]
      )
      let fragment = host.createGpuShader(
        namespace,
        shaderDescriptor(gssFragment),
        @[2'u8]
      )
      let token = host.beginGpuFrame()
      expect GpuHostError:
        discard host.createGpuGraphicsPipeline(
          namespace,
          graphicsPipelineDescriptor(vertex, fragment)
        )
      host.endGpuFrame(token)
      discard host.createGpuGraphicsPipeline(
        namespace,
        graphicsPipelineDescriptor(vertex, fragment)
      )
      host.close()
      check context.destroyedResources == @[3'u64, 2'u64, 1'u64]

suite "GPU binding resources":
  test "uniforms and samplers map typed descriptors and accounting":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "binding-resources",
      GpuResourceBudget(persistentBytes: 128, maxResources: 4)
    )
    let uniform = host.createGpuUniform(
      namespace,
      uniformDescriptor(
        name = "u_cbssPalette",
        uniformType = gutMat4,
        arrayLength = 2,
        label = "palette"
      )
    )
    let sampler = host.createGpuSampler(
      namespace,
      GpuSamplerDescriptor(
        name: "s_cbssSurface",
        addressU: gsamMirror,
        addressV: gsamClamp,
        addressW: gsamBorder,
        minFilter: gsfNearest,
        magFilter: gsfAnisotropic,
        mipFilter: gsfNearest,
        borderColorIndex: 15,
        label: "surface"
      )
    )

    check host.isGpuResourceLive(uniform)
    check host.isGpuResourceLive(sampler)
    check context.uniformCreates == 1
    check context.samplerCreates == 1
    check context.lastUniform.name == "u_cbssPalette"
    check context.lastUniform.uniformType == gutMat4
    check context.lastUniform.arrayLength == 2
    check context.lastSampler.addressW == gsamBorder
    check context.lastSampler.borderColorIndex == 15
    check host.gpuNamespaceUsage(namespace).persistentBytes == 128
    check host.gpuNamespaceUsage(namespace).resourceCount == 2

    check host.releaseGpuResource(sampler)
    check host.releaseGpuResource(uniform)
    check context.destroyedResources == @[2'u64, 1'u64]
    host.close()

  test "binding descriptors fail before backend allocation":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "invalid-bindings",
      GpuResourceBudget(persistentBytes: 256, maxResources: 8)
    )

    for name in ["", "1value", "bad-value", "bad value"]:
      expect GpuHostError:
        discard host.createGpuUniform(namespace, uniformDescriptor(name = name))
    expect GpuHostError:
      discard host.createGpuUniform(
        namespace,
        uniformDescriptor(arrayLength = 0)
      )
    expect GpuHostError:
      discard host.createGpuUniform(
        namespace,
        uniformDescriptor(label = repeat('u', maxGpuResourceLabelBytes + 1))
      )
    check context.uniformCreates == 0

    for name in ["", "2sampler", "bad-sampler", "bad sampler"]:
      expect GpuHostError:
        discard host.createGpuSampler(namespace, samplerDescriptor(name = name))
    var invalidBorder = samplerDescriptor()
    invalidBorder.borderColorIndex = 16
    expect GpuHostError:
      discard host.createGpuSampler(namespace, invalidBorder)
    var invalidMip = samplerDescriptor()
    invalidMip.mipFilter = gsfAnisotropic
    expect GpuHostError:
      discard host.createGpuSampler(namespace, invalidMip)
    check context.samplerCreates == 0

    let token = host.beginGpuFrame()
    expect GpuHostError:
      discard host.createGpuUniform(namespace, uniformDescriptor())
    expect GpuHostError:
      discard host.createGpuSampler(namespace, samplerDescriptor())
    host.endGpuFrame(token)
    host.close()

  test "binding callback budget failure and device loss preserve invariants":
    block missingCallbacks:
      let context = newContext()
      var backend = context.backend
      backend.createUniform = nil
      backend.createSampler = nil
      let host = openGpuHost(backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "missing-binding-callbacks",
        GpuResourceBudget(persistentBytes: 64, maxResources: 2)
      )
      expect GpuHostError:
        discard host.createGpuUniform(namespace, uniformDescriptor())
      expect GpuHostError:
        discard host.createGpuSampler(namespace, samplerDescriptor())
      check host.gpuNamespaceUsage(namespace).resourceCount == 0
      host.close()

    block budgetFailure:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "binding-budget",
        GpuResourceBudget(persistentBytes: 15, maxResources: 1)
      )
      expect GpuHostError:
        discard host.createGpuUniform(namespace, uniformDescriptor())
      check context.uniformCreates == 0
      check host.gpuNamespaceUsage(namespace).resourceCount == 0
      host.close()

    block backendFailure:
      let context = newContext()
      context.createSamplerStatus = gbsFailed
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "binding-failure",
        GpuResourceBudget(persistentBytes: 64, maxResources: 1)
      )
      expect GpuHostError:
        discard host.createGpuSampler(namespace, samplerDescriptor())
      check context.samplerCreates == 1
      check host.gpuNamespaceUsage(namespace).resourceCount == 0
      host.close()

    block deviceLoss:
      let context = newContext()
      context.createUniformStatus = gbsDeviceLost
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "binding-loss",
        GpuResourceBudget(persistentBytes: 64, maxResources: 1)
      )
      expect GpuHostError:
        discard host.createGpuUniform(namespace, uniformDescriptor())
      check host.state == ghsDeviceLost
      check host.gpuNamespaceUsage(namespace).resourceCount == 0
      host.close()

suite "GPU command bindings":
  test "draw and compute bindings resolve before backend submission":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned, presentationConfig())
    let namespace = host.createGpuNamespace(
      "command-bindings",
      GpuResourceBudget(
        persistentBytes: 4096,
        workUnitsPerFrame: 4,
        maxResources: 16
      )
    )
    let drawing = host.createDrawingResources(namespace)
    let sampledTexture = host.createGpuTexture(
      namespace,
      textureDescriptor(usage = {gtuSampled})
    )
    let storageTexture = host.createGpuTexture(
      namespace,
      textureDescriptor(usage = {gtuSampled, gtuStorage})
    )
    let storageBuffer = host.createGpuBuffer(
      namespace,
      storageBufferDescriptor(storageFormat = gsbfFloat32x4)
    )
    let uniform = host.createGpuUniform(namespace, uniformDescriptor())
    let sampler = host.createGpuSampler(namespace, samplerDescriptor())
    let computeShader = host.createGpuShader(
      namespace,
      shaderDescriptor(gssCompute),
      @[3'u8]
    )
    let computePipeline = host.createGpuComputePipeline(
      namespace,
      computePipelineDescriptor(computeShader)
    )

    let token = host.beginGpuFrame()
    host.submitGpuDraw(
      namespace,
      graphicsPass(),
      GpuDrawCommand(
        pipeline: drawing.pipeline,
        vertexBuffer: drawing.vertexBuffer,
        vertexCount: 2,
        bindings: GpuBindingSet(
          uniforms: @[
            GpuUniformBinding(
              uniform: uniform,
              values: @[0.25'f32, 0.5'f32, 0.75'f32, 1'f32]
            )
          ],
          textures: @[
            GpuTextureBinding(
              stage: 3,
              sampler: sampler,
              texture: sampledTexture
            )
          ]
        )
      )
    )
    check context.lastBindings.uniforms.len == 1
    check context.lastBindings.uniforms[0].descriptor.name == "u_cbssValue"
    check context.lastBindings.uniforms[0].values[2] == 0.75'f32
    check context.lastBindings.textures.len == 1
    check context.lastBindings.textures[0].stage == 3
    check context.lastBindings.textures[0].samplerDescriptor.addressU == gsamClamp

    host.dispatchGpuCompute(
      namespace,
      GpuComputeCommand(
        pipeline: computePipeline,
        groupsX: 2,
        groupsY: 1,
        groupsZ: 1,
        bindings: GpuBindingSet(
          uniforms: @[
            GpuUniformBinding(
              uniform: uniform,
              values: @[1'f32, 2'f32, 3'f32, 4'f32]
            )
          ],
          storageImages: @[
            GpuStorageImageBinding(
              stage: 4,
              texture: storageTexture,
              access: gsaReadWrite
            )
          ],
          storageBuffers: @[
            GpuStorageBufferBinding(
              stage: 5,
              buffer: storageBuffer,
              access: gsaRead
            )
          ]
        )
      )
    )
    check context.lastBindings.storageImages.len == 1
    check context.lastBindings.storageImages[0].stage == 4
    check context.lastBindings.storageImages[0].format == gtfRgba8
    check context.lastBindings.storageImages[0].access == gsaReadWrite
    check context.lastBindings.storageBuffers.len == 1
    check context.lastBindings.storageBuffers[0].stage == 5
    check context.lastBindings.storageBuffers[0].descriptor.storageFormat ==
      gsbfFloat32x4
    check context.lastBindings.storageBuffers[0].access == gsaRead
    host.endGpuFrame(token)
    host.close()

  test "invalid command bindings never reach a graphics pass or dispatch":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned, presentationConfig())
    let budget = GpuResourceBudget(
      persistentBytes: 8192,
      workUnitsPerFrame: 64,
      maxResources: 32
    )
    let namespace = host.createGpuNamespace("invalid-command-bindings", budget)
    let foreign = host.createGpuNamespace("foreign-command-bindings", budget)
    let drawing = host.createDrawingResources(namespace)
    let sampled = host.createGpuTexture(
      namespace,
      textureDescriptor(usage = {gtuSampled})
    )
    let notSampled = host.createGpuTexture(
      namespace,
      textureDescriptor(usage = {gtuBlitDestination})
    )
    let storage = host.createGpuTexture(
      namespace,
      textureDescriptor(usage = {gtuStorage})
    )
    let storageBuffer = host.createGpuBuffer(
      namespace,
      storageBufferDescriptor()
    )
    let readOnlyStorageBuffer = host.createGpuBuffer(
      namespace,
      storageBufferDescriptor(storageAccess = gsaRead)
    )
    let writeOnlyStorageBuffer = host.createGpuBuffer(
      namespace,
      storageBufferDescriptor(storageAccess = gsaWrite)
    )
    let uniform = host.createGpuUniform(namespace, uniformDescriptor())
    let sampler = host.createGpuSampler(namespace, samplerDescriptor())
    let foreignSampler = host.createGpuSampler(foreign, samplerDescriptor())
    let computeShader = host.createGpuShader(
      namespace,
      shaderDescriptor(gssCompute),
      @[3'u8]
    )
    let computePipeline = host.createGpuComputePipeline(
      namespace,
      computePipelineDescriptor(computeShader)
    )
    let base = GpuDrawCommand(
      pipeline: drawing.pipeline,
      vertexBuffer: drawing.vertexBuffer,
      vertexCount: 2
    )
    let token = host.beginGpuFrame()

    for values in [
      @[1'f32, 2'f32, 3'f32],
      @[1'f32, 2'f32, 3'f32, Inf.float32]
    ]:
      var command = base
      command.bindings.uniforms = @[
        GpuUniformBinding(uniform: uniform, values: values)
      ]
      expect GpuHostError:
        host.submitGpuDraw(namespace, graphicsPass(), command)

    var duplicateUniform = base
    duplicateUniform.bindings.uniforms = @[
      GpuUniformBinding(uniform: uniform, values: @[1'f32, 2, 3, 4]),
      GpuUniformBinding(uniform: uniform, values: @[4'f32, 3, 2, 1])
    ]
    expect GpuHostError:
      host.submitGpuDraw(namespace, graphicsPass(), duplicateUniform)

    for textureBinding in [
      GpuTextureBinding(stage: 0, sampler: foreignSampler, texture: sampled),
      GpuTextureBinding(stage: 0, sampler: sampler, texture: notSampled),
      GpuTextureBinding(stage: uint8(maxGpuTextureBindings), sampler: sampler,
        texture: sampled)
    ]:
      var command = base
      command.bindings.textures = @[textureBinding]
      expect GpuHostError:
        host.submitGpuDraw(namespace, graphicsPass(), command)

    var duplicateStage = base
    duplicateStage.bindings.textures = @[
      GpuTextureBinding(stage: 1, sampler: sampler, texture: sampled),
      GpuTextureBinding(stage: 1, sampler: sampler, texture: sampled)
    ]
    expect GpuHostError:
      host.submitGpuDraw(namespace, graphicsPass(), duplicateStage)

    var storageOnDraw = base
    storageOnDraw.bindings.storageImages = @[
      GpuStorageImageBinding(stage: 0, texture: storage, access: gsaRead)
    ]
    expect GpuHostError:
      host.submitGpuDraw(namespace, graphicsPass(), storageOnDraw)
    storageOnDraw.bindings.storageImages = @[]
    storageOnDraw.bindings.storageBuffers = @[
      GpuStorageBufferBinding(
        stage: 0,
        buffer: storageBuffer,
        access: gsaReadWrite
      )
    ]
    expect GpuHostError:
      host.submitGpuDraw(namespace, graphicsPass(), storageOnDraw)

    let computeBase = GpuComputeCommand(
      pipeline: computePipeline,
      groupsX: 1,
      groupsY: 1,
      groupsZ: 1
    )
    for imageBinding in [
      GpuStorageImageBinding(stage: 0, texture: sampled, access: gsaRead),
      GpuStorageImageBinding(stage: 0, texture: storage, access: gsaWrite, mip: 1),
      GpuStorageImageBinding(stage: uint8(maxGpuStorageImageBindings),
        texture: storage, access: gsaReadWrite)
    ]:
      var command = computeBase
      command.bindings.storageImages = @[imageBinding]
      expect GpuHostError:
        host.dispatchGpuCompute(namespace, command)

    for bufferBinding in [
      GpuStorageBufferBinding(
        stage: 0,
        buffer: drawing.vertexBuffer,
        access: gsaRead
      ),
      GpuStorageBufferBinding(
        stage: 0,
        buffer: readOnlyStorageBuffer,
        access: gsaWrite
      ),
      GpuStorageBufferBinding(
        stage: 0,
        buffer: writeOnlyStorageBuffer,
        access: gsaRead
      ),
      GpuStorageBufferBinding(
        stage: uint8(maxGpuStorageBufferBindings),
        buffer: storageBuffer,
        access: gsaReadWrite
      )
    ]:
      var command = computeBase
      command.bindings.storageBuffers = @[bufferBinding]
      expect GpuHostError:
        host.dispatchGpuCompute(namespace, command)

    var duplicateStorageBuffer = computeBase
    duplicateStorageBuffer.bindings.storageBuffers = @[
      GpuStorageBufferBinding(stage: 0, buffer: storageBuffer, access: gsaRead),
      GpuStorageBufferBinding(stage: 1, buffer: storageBuffer, access: gsaWrite)
    ]
    expect GpuHostError:
      host.dispatchGpuCompute(namespace, duplicateStorageBuffer)

    var crossStage = computeBase
    crossStage.bindings.textures = @[
      GpuTextureBinding(stage: 2, sampler: sampler, texture: sampled)
    ]
    crossStage.bindings.storageImages = @[
      GpuStorageImageBinding(stage: 2, texture: storage, access: gsaReadWrite)
    ]
    expect GpuHostError:
      host.dispatchGpuCompute(namespace, crossStage)

    crossStage.bindings.storageImages = @[]
    crossStage.bindings.storageBuffers = @[
      GpuStorageBufferBinding(stage: 2, buffer: storageBuffer, access: gsaRead)
    ]
    expect GpuHostError:
      host.dispatchGpuCompute(namespace, crossStage)

    var tooManyUniforms = base
    for index in 0 .. maxGpuUniformBindings:
      discard index
      tooManyUniforms.bindings.uniforms.add GpuUniformBinding(
        uniform: uniform,
        values: @[1'f32, 2, 3, 4]
      )
    expect GpuHostError:
      host.submitGpuDraw(namespace, graphicsPass(), tooManyUniforms)

    var tooManyStorageBuffers = computeBase
    for stage in 0 .. maxGpuStorageBufferBindings:
      tooManyStorageBuffers.bindings.storageBuffers.add GpuStorageBufferBinding(
        stage: uint8(stage mod maxGpuStorageBufferBindings),
        buffer: storageBuffer,
        access: gsaRead
      )
    expect GpuHostError:
      host.dispatchGpuCompute(namespace, tooManyStorageBuffers)

    check context.graphicsPassBegins == 0
    check context.drawSubmits == 0
    check context.computeDispatches == 0
    check host.gpuNamespaceUsage(namespace).workUnits == 0
    host.endGpuFrame(token)
    host.close()

suite "GPU bounded submission":
  test "draw and compute commands map resources onto reserved view identifiers":
    let context = newContext()
    var config = presentationConfig()
    config.viewIdBase = 20
    config.viewIdCount = 3
    let host = openGpuHost(context.backend, ghoOwned, config)
    let namespace = host.createGpuNamespace(
      "submission",
      GpuResourceBudget(
        persistentBytes: 1024,
        workUnitsPerFrame: 4,
        maxResources: 8
      )
    )
    let drawing = host.createDrawingResources(namespace)
    let target = host.createGpuRenderTarget(
      namespace,
      renderTargetDescriptor(width = 8, height = 8)
    )
    let computeShader = host.createGpuShader(
      namespace,
      shaderDescriptor(gssCompute, "dispatch"),
      @[3'u8]
    )
    let computePipeline = host.createGpuComputePipeline(
      namespace,
      computePipelineDescriptor(computeShader)
    )
    var pass = graphicsPass(8, 8, target)
    pass.scissorEnabled = true
    pass.scissor = GpuViewport(x: 1, y: 1, width: 6, height: 6)
    pass.clearColorEnabled = true
    pass.clearColor = GpuClearColor(
      red: 0.1,
      green: 0.2,
      blue: 0.3,
      alpha: 1
    )
    let indexed = GpuDrawCommand(
      pipeline: drawing.pipeline,
      vertexBuffer: drawing.vertexBuffer,
      firstVertex: 0,
      vertexCount: 2,
      indexBuffer: drawing.indexBuffer,
      firstIndex: 1,
      indexCount: 5,
      depth: 7
    )
    let plain = GpuDrawCommand(
      pipeline: drawing.pipeline,
      vertexBuffer: drawing.vertexBuffer,
      vertexCount: 2
    )

    let token = host.beginGpuFrame()
    host.submitGpuDraws(namespace, pass, [indexed, plain])
    check context.graphicsPassBegins == 1
    check context.drawSubmits == 2
    check context.lastViewId == 20
    check context.lastGraphicsPass == pass
    check context.lastDrawCommand == plain
    check context.lastSubmissionResources == @[3'u64, 4'u64, 0'u64]
    check host.gpuNamespaceUsage(namespace).workUnits == 2

    let compute = GpuComputeCommand(
      pipeline: computePipeline,
      groupsX: 2,
      groupsY: 3,
      groupsZ: 4
    )
    host.dispatchGpuCompute(namespace, compute)
    check context.computeDispatches == 1
    check context.lastViewId == 21
    check context.lastComputeCommand == compute
    check context.lastSubmissionResources == @[8'u64]
    check host.gpuNamespaceUsage(namespace).workUnits == 3
    host.endGpuFrame(token)

    let next = host.beginGpuFrame()
    host.submitGpuDraw(namespace, graphicsPass(), plain)
    check context.graphicsPassBegins == 2
    check context.lastViewId == 20
    host.endGpuFrame(next)
    host.close()

  test "draw validation rejects unsafe passes buffers pipelines and ranges":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned, presentationConfig())
    let budget = GpuResourceBudget(
      persistentBytes: 2048,
      workUnitsPerFrame: 20,
      maxResources: 12
    )
    let namespace = host.createGpuNamespace("draw-validation", budget)
    let foreign = host.createGpuNamespace("foreign-draw", budget)
    let drawing = host.createDrawingResources(namespace)
    let foreignDrawing = host.createDrawingResources(foreign)
    let target = host.createGpuRenderTarget(
      namespace,
      renderTargetDescriptor(width = 8, height = 8)
    )
    let wrongTarget = host.createGpuRenderTarget(
      namespace,
      renderTargetDescriptor(width = 8, height = 8, format = gtfBgra8)
    )
    let unmappedPipeline = host.reserveGpuResource(
      namespace,
      grkPipeline,
      0
    )
    let unmappedBuffer = host.reserveGpuResource(namespace, grkBuffer, 0)
    let command = GpuDrawCommand(
      pipeline: drawing.pipeline,
      vertexBuffer: drawing.vertexBuffer,
      vertexCount: 2
    )

    expect GpuHostError:
      host.submitGpuDraw(namespace, graphicsPass(), command)
    let token = host.beginGpuFrame()

    for pass in [
      graphicsPass(width = 0),
      graphicsPass(width = 1281),
      graphicsPass(8, 8, wrongTarget)
    ]:
      expect GpuHostError:
        host.submitGpuDraw(namespace, pass, command)

    var badScissor = graphicsPass()
    badScissor.scissorEnabled = true
    badScissor.scissor = GpuViewport(x: 1279, width: 2, height: 1)
    expect GpuHostError:
      host.submitGpuDraw(namespace, badScissor, command)

    var badClear = graphicsPass()
    badClear.clearColorEnabled = true
    badClear.clearColor = GpuClearColor(red: -0.1, alpha: 1)
    expect GpuHostError:
      host.submitGpuDraw(namespace, badClear, command)

    for badCommand in [
      GpuDrawCommand(
        pipeline: foreignDrawing.pipeline,
        vertexBuffer: drawing.vertexBuffer,
        vertexCount: 2
      ),
      GpuDrawCommand(
        pipeline: unmappedPipeline,
        vertexBuffer: drawing.vertexBuffer,
        vertexCount: 2
      ),
      GpuDrawCommand(
        pipeline: drawing.pipeline,
        vertexBuffer: unmappedBuffer,
        vertexCount: 1
      ),
      GpuDrawCommand(
        pipeline: drawing.pipeline,
        vertexBuffer: drawing.indexBuffer,
        vertexCount: 2
      ),
      GpuDrawCommand(
        pipeline: drawing.pipeline,
        vertexBuffer: drawing.vertexBuffer,
        firstVertex: 1,
        vertexCount: 2
      ),
      GpuDrawCommand(
        pipeline: drawing.pipeline,
        vertexBuffer: drawing.vertexBuffer,
        vertexCount: 2,
        firstIndex: 1,
        indexCount: 1
      ),
      GpuDrawCommand(
        pipeline: drawing.pipeline,
        vertexBuffer: drawing.vertexBuffer,
        vertexCount: 2,
        indexBuffer: drawing.indexBuffer,
        firstIndex: 5,
        indexCount: 2
      )
    ]:
      expect GpuHostError:
        host.submitGpuDraw(namespace, graphicsPass(), badCommand)

    expect GpuHostError:
      host.submitGpuDraws(namespace, graphicsPass(), newSeq[GpuDrawCommand]())
    check context.drawSubmits == 0
    check host.gpuNamespaceUsage(namespace).workUnits == 0
    host.endGpuFrame(token)
    discard target
    host.close()

  test "submission callbacks budgets view ranges and device loss fail closed":
    block missingCallback:
      let context = newContext()
      var backend = context.backend
      backend.beginGraphicsPass = nil
      let host = openGpuHost(backend, ghoOwned, presentationConfig())
      let namespace = host.createGpuNamespace(
        "missing-submit",
        GpuResourceBudget(
          persistentBytes: 128,
          workUnitsPerFrame: 2,
          maxResources: 5
        )
      )
      let drawing = host.createDrawingResources(namespace)
      let token = host.beginGpuFrame()
      expect GpuHostError:
        host.submitGpuDraw(
          namespace,
          graphicsPass(),
          GpuDrawCommand(
            pipeline: drawing.pipeline,
            vertexBuffer: drawing.vertexBuffer,
            vertexCount: 2
          )
        )
      host.endGpuFrame(token)
      host.close()

    block missingDrawCallback:
      let context = newContext()
      var backend = context.backend
      backend.submitDraw = nil
      let host = openGpuHost(backend, ghoOwned, presentationConfig())
      let namespace = host.createGpuNamespace(
        "missing-draw",
        GpuResourceBudget(
          persistentBytes: 128,
          workUnitsPerFrame: 1,
          maxResources: 5
        )
      )
      let drawing = host.createDrawingResources(namespace)
      let token = host.beginGpuFrame()
      expect GpuHostError:
        host.submitGpuDraw(
          namespace,
          graphicsPass(),
          GpuDrawCommand(
            pipeline: drawing.pipeline,
            vertexBuffer: drawing.vertexBuffer,
            vertexCount: 2
          )
        )
      check context.graphicsPassBegins == 0
      host.endGpuFrame(token)
      host.close()

    block failedPassDoesNotConsumeViewOrWork:
      let context = newContext()
      context.beginGraphicsPassStatus = gbsInvalidConfiguration
      var config = presentationConfig()
      config.viewIdBase = 42
      config.viewIdCount = 1
      let host = openGpuHost(context.backend, ghoOwned, config)
      let namespace = host.createGpuNamespace(
        "failed-pass",
        GpuResourceBudget(
          persistentBytes: 128,
          workUnitsPerFrame: 1,
          maxResources: 5
        )
      )
      let drawing = host.createDrawingResources(namespace)
      let command = GpuDrawCommand(
        pipeline: drawing.pipeline,
        vertexBuffer: drawing.vertexBuffer,
        vertexCount: 2
      )
      let token = host.beginGpuFrame()
      expect GpuHostError:
        host.submitGpuDraw(namespace, graphicsPass(), command)
      check context.graphicsPassBegins == 1
      check context.drawSubmits == 0
      check host.gpuNamespaceUsage(namespace).workUnits == 0

      context.beginGraphicsPassStatus = gbsOk
      host.submitGpuDraw(namespace, graphicsPass(), command)
      check context.graphicsPassBegins == 2
      check context.drawSubmits == 1
      check context.lastViewId == 42
      check host.gpuNamespaceUsage(namespace).workUnits == 1
      host.endGpuFrame(token)
      host.close()

    block boundedViewsAndWork:
      let context = newContext()
      var config = presentationConfig()
      config.viewIdBase = 255
      config.viewIdCount = 1
      let host = openGpuHost(context.backend, ghoOwned, config)
      let namespace = host.createGpuNamespace(
        "bounded-submit",
        GpuResourceBudget(
          persistentBytes: 128,
          workUnitsPerFrame: 2,
          maxResources: 5
        )
      )
      let drawing = host.createDrawingResources(namespace)
      let command = GpuDrawCommand(
        pipeline: drawing.pipeline,
        vertexBuffer: drawing.vertexBuffer,
        vertexCount: 2
      )
      let token = host.beginGpuFrame()
      host.submitGpuDraw(namespace, graphicsPass(), command)
      check context.lastViewId == 255
      expect GpuHostError:
        host.submitGpuDraw(namespace, graphicsPass(), command)
      check host.gpuNamespaceUsage(namespace).workUnits == 1
      host.endGpuFrame(token)
      host.close()

    block deviceLoss:
      let context = newContext()
      context.submitDrawStatus = gbsDeviceLost
      let host = openGpuHost(context.backend, ghoOwned, presentationConfig())
      let namespace = host.createGpuNamespace(
        "lost-submit",
        GpuResourceBudget(
          persistentBytes: 128,
          workUnitsPerFrame: 1,
          maxResources: 5
        )
      )
      let drawing = host.createDrawingResources(namespace)
      discard host.beginGpuFrame()
      expect GpuHostError:
        host.submitGpuDraw(
          namespace,
          graphicsPass(),
          GpuDrawCommand(
            pipeline: drawing.pipeline,
            vertexBuffer: drawing.vertexBuffer,
            vertexCount: 2
          )
        )
      check host.state == ghsDeviceLost
      check not host.isGpuResourceLive(drawing.pipeline)
      host.close()

  test "compute dispatch validates pipeline groups capability and namespace":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let budget = GpuResourceBudget(
      persistentBytes: 128,
      workUnitsPerFrame: 4,
      maxResources: 5
    )
    let namespace = host.createGpuNamespace("compute-submit", budget)
    let foreign = host.createGpuNamespace("foreign-compute", budget)
    let shader = host.createGpuShader(
      namespace,
      shaderDescriptor(gssCompute),
      @[1'u8]
    )
    let pipeline = host.createGpuComputePipeline(
      namespace,
      computePipelineDescriptor(shader)
    )
    let foreignShader = host.createGpuShader(
      foreign,
      shaderDescriptor(gssCompute),
      @[2'u8]
    )
    let foreignPipeline = host.createGpuComputePipeline(
      foreign,
      computePipelineDescriptor(foreignShader)
    )
    let token = host.beginGpuFrame()
    for command in [
      GpuComputeCommand(pipeline: pipeline),
      GpuComputeCommand(pipeline: pipeline, groupsX: 65536, groupsY: 1, groupsZ: 1),
      GpuComputeCommand(
        pipeline: foreignPipeline,
        groupsX: 1,
        groupsY: 1,
        groupsZ: 1
      )
    ]:
      expect GpuHostError:
        host.dispatchGpuCompute(namespace, command)
    check context.computeDispatches == 0
    host.endGpuFrame(token)
    host.close()

  test "invalid view ranges are rejected and zero count normalizes to all views":
    let context = newContext()
    var config = presentationConfig()
    config.viewIdBase = 1
    config.viewIdCount = maxGpuViewCount
    expect GpuHostError:
      discard openGpuHost(context.backend, ghoOwned, config)

    config = presentationConfig()
    let host = openGpuHost(context.backend, ghoOwned, config)
    check host.config.viewIdCount == maxGpuViewCount
    host.close()

suite "GPU texture transfer and readback":

  test "readback byte accounting follows every texture format":
    for format in GpuTextureFormat:
      let bytesPerPixel =
        case format
        of gtfR8: 1'u64
        of gtfR16F: 2'u64
        of gtfRgba8, gtfBgra8, gtfR32F, gtfRg16F: 4'u64
        of gtfRg32F, gtfRgba16F: 8'u64
        of gtfRgba32F: 16'u64
      let expectedBytes = 4'u64 * bytesPerPixel
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "readback-format-" & $format,
        GpuResourceBudget(
          persistentBytes: expectedBytes,
          readbackBytesPerFrame: expectedBytes,
          workUnitsPerFrame: 1,
          maxResources: 1
        )
      )
      let texture = host.createGpuTexture(
        namespace,
        textureDescriptor(
          width = 2,
          height = 2,
          format = format,
          usage = {gtuBlitDestination, gtuReadback}
        )
      )
      let frame = host.beginGpuFrame()
      let readback = host.requestGpuReadback(namespace, texture)
      check context.lastReadbackBytes == expectedBytes
      check host.gpuNamespaceUsage(namespace).readbackBytes == expectedBytes
      host.endGpuFrame(frame)
      context.readbackReady = true
      var data: GpuReadbackData
      check host.tryTakeGpuReadback(readback, data)
      check data.format == format
      check data.rowStride == uint32(2'u64 * bytesPerPixel)
      check uint64(data.pixels.len) == expectedBytes
      host.close()

  test "render target copies complete into retained readback data":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "canvas-transfer",
      GpuResourceBudget(
        persistentBytes: 64,
        readbackBytesPerFrame: 32,
        workUnitsPerFrame: 2,
        maxResources: 2
      )
    )
    let target = host.createGpuRenderTarget(
      namespace,
      GpuRenderTargetDescriptor(
        width: 4,
        height: 2,
        format: gtfRgba8,
        usage: {gtuRenderTarget, gtuBlitSource}
      )
    )
    let readbackTexture = host.createGpuTexture(
      namespace,
      textureDescriptor(
        width = 4,
        height = 2,
        usage = {gtuBlitDestination, gtuReadback}
      )
    )

    let frame = host.beginGpuFrame()
    host.copyGpuTexture(namespace, target, readbackTexture)
    let readback = host.requestGpuReadback(namespace, readbackTexture)
    check context.textureCopies == 1
    check context.readbackRequests == 1
    check context.lastCopySourceKind == grkRenderTarget
    check context.lastCopyRegion == GpuTextureCopyRegion(width: 4, height: 2)
    check context.lastReadbackBytes == 32
    check host.gpuNamespaceUsage(namespace).readbackBytes == 32
    check host.gpuNamespaceUsage(namespace).workUnits == 2
    check host.pendingGpuReadbackCount(namespace) == 1
    check host.gpuReadbackState(readback) == grsPending
    expect GpuHostError:
      discard host.releaseGpuResource(readbackTexture)
    host.endGpuFrame(frame)

    context.readbackReady = true
    check host.gpuReadbackState(readback) == grsReady
    var data: GpuReadbackData
    check host.tryTakeGpuReadback(readback, data)
    check data.width == 4
    check data.height == 2
    check data.format == gtfRgba8
    check data.rowStride == 16
    check data.pixels.len == 32
    check data.pixels[0] == 0
    check data.pixels[31] == 31
    check host.gpuReadbackState(readback) == grsInvalid
    check host.pendingGpuReadbackCount(namespace) == 0
    check host.releaseGpuResource(readbackTexture)
    check host.releaseGpuResource(target)
    host.close()

  test "partial texture copies preserve the typed region":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "partial-transfer",
      GpuResourceBudget(
        persistentBytes: 512,
        workUnitsPerFrame: 1,
        maxResources: 2
      )
    )
    let source = host.createGpuTexture(
      namespace,
      textureDescriptor(usage = {gtuBlitSource})
    )
    let destination = host.createGpuTexture(
      namespace,
      textureDescriptor(usage = {gtuBlitDestination})
    )
    let region = GpuTextureCopyRegion(
      sourceX: 1,
      sourceY: 2,
      destinationX: 3,
      destinationY: 4,
      width: 2,
      height: 3
    )
    let frame = host.beginGpuFrame()
    host.copyGpuTexture(namespace, source, destination, region)
    check context.lastCopySourceKind == grkTexture
    check context.lastCopyRegion == region
    host.endGpuFrame(frame)
    host.close()

  test "copy validation finishes before backend work or budget consumption":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let budget = GpuResourceBudget(
      persistentBytes: 2048,
      workUnitsPerFrame: 4,
      maxResources: 8
    )
    let namespace = host.createGpuNamespace("invalid-transfer", budget)
    let foreign = host.createGpuNamespace("foreign-transfer", budget)
    let source = host.createGpuTexture(
      namespace, textureDescriptor(usage = {gtuBlitSource})
    )
    let destination = host.createGpuTexture(
      namespace, textureDescriptor(usage = {gtuBlitDestination})
    )
    let ordinary = host.createGpuTexture(namespace, textureDescriptor())
    let mismatched = host.createGpuTexture(
      namespace,
      textureDescriptor(format = gtfBgra8, usage = {gtuBlitDestination})
    )
    let foreignSource = host.createGpuTexture(
      foreign, textureDescriptor(usage = {gtuBlitSource})
    )
    let target = host.createGpuRenderTarget(
      namespace,
      GpuRenderTargetDescriptor(
        width: 8,
        height: 8,
        format: gtfRgba8,
        usage: {gtuRenderTarget, gtuBlitSource}
      )
    )
    let frame = host.beginGpuFrame()
    for invalid in [
      GpuTextureCopyRegion(),
      GpuTextureCopyRegion(sourceX: 8, width: 1, height: 1),
      GpuTextureCopyRegion(destinationY: 7, width: 2, height: 2)
    ]:
      expect GpuHostError:
        host.copyGpuTexture(namespace, source, destination, invalid)
    expect GpuHostError:
      host.copyGpuTexture(namespace, ordinary, destination)
    expect GpuHostError:
      host.copyGpuTexture(namespace, source, ordinary)
    expect GpuHostError:
      host.copyGpuTexture(namespace, source, mismatched)
    expect GpuHostError:
      host.copyGpuTexture(namespace, foreignSource, destination)
    expect GpuHostError:
      host.copyGpuTexture(namespace, source, target)
    check context.textureCopies == 0
    check host.gpuNamespaceUsage(namespace).workUnits == 0
    host.endGpuFrame(frame)
    host.close()

  test "readback textures enforce CPU-only usage and frame budgets":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "readback-validation",
      GpuResourceBudget(
        persistentBytes: 512,
        readbackBytesPerFrame: 31,
        workUnitsPerFrame: 1,
        maxResources: 4
      )
    )
    expect GpuHostError:
      discard host.createGpuTexture(
        namespace,
        textureDescriptor(
          width = 4,
          height = 2,
          usage = {gtuSampled, gtuBlitDestination, gtuReadback}
        )
      )
    expect GpuHostError:
      discard host.createGpuTexture(
        namespace,
        textureDescriptor(
          width = 4,
          height = 2,
          usage = {gtuBlitDestination, gtuReadback}
        ),
        newSeq[byte](32)
      )
    let ordinary = host.createGpuTexture(namespace, textureDescriptor())
    let readbackTexture = host.createGpuTexture(
      namespace,
      textureDescriptor(
        width = 4,
        height = 2,
        usage = {gtuBlitDestination, gtuReadback}
      )
    )
    let frame = host.beginGpuFrame()
    expect GpuHostError:
      discard host.requestGpuReadback(namespace, ordinary)
    expect GpuHostError:
      discard host.requestGpuReadback(namespace, readbackTexture)
    check context.readbackRequests == 0
    check host.gpuNamespaceUsage(namespace).readbackBytes == 0
    check host.gpuNamespaceUsage(namespace).workUnits == 0
    host.endGpuFrame(frame)
    host.close()

  test "pending readbacks are bounded and retain namespace lifetime":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "bounded-readbacks",
      GpuResourceBudget(
        persistentBytes: 4,
        readbackBytesPerFrame: 4 * maxGpuPendingReadbacksPerNamespace,
        workUnitsPerFrame: maxGpuPendingReadbacksPerNamespace,
        maxResources: 1
      )
    )
    let texture = host.createGpuTexture(
      namespace,
      textureDescriptor(
        width = 1,
        height = 1,
        usage = {gtuBlitDestination, gtuReadback}
      )
    )
    let frame = host.beginGpuFrame()
    var readbacks: seq[GpuReadbackHandle]
    for index in 0 ..< maxGpuPendingReadbacksPerNamespace:
      discard index
      readbacks.add host.requestGpuReadback(namespace, texture)
    expect GpuHostError:
      discard host.requestGpuReadback(namespace, texture)
    check context.readbackRequests == maxGpuPendingReadbacksPerNamespace
    host.endGpuFrame(frame)
    expect GpuHostError:
      discard host.closeGpuNamespace(namespace)
    context.readbackReady = true
    for readback in readbacks:
      var data: GpuReadbackData
      check host.tryTakeGpuReadback(readback, data)
    check host.closeGpuNamespace(namespace)
    host.close()

  test "backend failures and capability gaps remain atomic":
    block missingCapability:
      let context = newContext()
      context.readbackSupported = false
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "unsupported-readback",
        GpuResourceBudget(persistentBytes: 4, maxResources: 1)
      )
      expect GpuHostError:
        discard host.createGpuTexture(
          namespace,
          textureDescriptor(
            width = 1,
            height = 1,
            usage = {gtuBlitDestination, gtuReadback}
          )
        )
      host.close()

    block backendFailure:
      let context = newContext()
      context.requestReadbackStatus = gbsFailed
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "failed-readback",
        GpuResourceBudget(
          persistentBytes: 4,
          readbackBytesPerFrame: 4,
          workUnitsPerFrame: 1,
          maxResources: 1
        )
      )
      let texture = host.createGpuTexture(
        namespace,
        textureDescriptor(
          width = 1,
          height = 1,
          usage = {gtuBlitDestination, gtuReadback}
        )
      )
      let frame = host.beginGpuFrame()
      expect GpuHostError:
        discard host.requestGpuReadback(namespace, texture)
      check host.pendingGpuReadbackCount(namespace) == 0
      check host.gpuNamespaceUsage(namespace).readbackBytes == 0
      host.endGpuFrame(frame)
      check host.releaseGpuResource(texture)
      host.close()

  test "device loss invalidates pending readback handles":
    let context = newContext()
    context.pollReadbackStatus = gbsDeviceLost
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "lost-readback",
      GpuResourceBudget(
        persistentBytes: 4,
        readbackBytesPerFrame: 4,
        workUnitsPerFrame: 1,
        maxResources: 1
      )
    )
    let texture = host.createGpuTexture(
      namespace,
      textureDescriptor(
        width = 1,
        height = 1,
        usage = {gtuBlitDestination, gtuReadback}
      )
    )
    let frame = host.beginGpuFrame()
    let readback = host.requestGpuReadback(namespace, texture)
    host.endGpuFrame(frame)
    expect GpuHostError:
      discard host.gpuReadbackState(readback)
    check host.state == ghsDeviceLost
    check host.gpuReadbackState(readback) == grsInvalid
    host.close()

  test "borrowed hosts must drain readbacks before detaching":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoBorrowed)
    let namespace = host.createGpuNamespace(
      "borrowed-readback",
      GpuResourceBudget(
        persistentBytes: 4,
        readbackBytesPerFrame: 4,
        workUnitsPerFrame: 1,
        maxResources: 1
      )
    )
    let texture = host.createGpuTexture(
      namespace,
      textureDescriptor(
        width = 1,
        height = 1,
        usage = {gtuBlitDestination, gtuReadback}
      )
    )
    let frame = host.beginGpuFrame()
    let readback = host.requestGpuReadback(namespace, texture)
    host.endGpuFrame(frame)
    expect GpuHostError:
      host.close()
    check context.borrowedDetaches == 0
    context.readbackReady = true
    var data: GpuReadbackData
    check host.tryTakeGpuReadback(readback, data)
    host.close()
    check context.borrowedDetaches == 1

suite "GPU canvas composition bridge":

  test "UI attachment publishes only the completed GPU canvas surface":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "gpu-canvas-ui",
      GpuResourceBudget(
        persistentBytes: 8,
        readbackBytesPerFrame: 4,
        workUnitsPerFrame: 2,
        maxResources: 2
      )
    )
    var config = defaultGpuCanvasConfig(1, 1)
    config.readbackSlots = 1
    let canvas = host.newGpuCanvasSurface(namespace, config)
    let ui = initUiRoot()
    let handle = ui.gpuCanvas(
      canvas,
      uiStyle([
        decl("width", px(24)),
        decl("height", px(12)),
        decl("border-radius", px(6)),
        decl("overflow", keyword("hidden"))
      ]),
      code = "gpu-accent"
    )

    check handle.valid
    check handle.nodeHandle.valid
    check ui.tree.nodes[handle.nodeHandle.id.nodeIndex].kind == nkBox
    check ui.tree.nodes[handle.nodeHandle.id.nodeIndex].code == "gpu-accent"
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      ui.tree, ui.styleSheets(), defaultProperties(), diagnostics
    )
    let layout = computeLayout(ui.tree, styles, size(80, 60))
    check not diagnostics.hasErrors
    check layout.boxes[handle.nodeHandle.id.nodeIndex].rect.w == 24
    check layout.boxes[handle.nodeHandle.id.nodeIndex].rect.h == 12
    discard ui.consumeInvalidation()

    let frame = host.beginGpuFrame()
    check handle.queueGpuFrame()
    check not handle.queueGpuFrame()
    host.endGpuFrame(frame)
    check not handle.collectGpuFrame()
    check not ui.hasPendingInvalidation

    context.readbackReady = true
    check handle.collectGpuFrame()
    check canvas.rasterSurface.revision == 2
    let invalidation = ui.consumeInvalidation()
    check invalidation.domains == {ddPaint}
    check invalidation.roots == @[handle.nodeHandle.id]
    check not handle.collectGpuFrame()
    check not ui.hasPendingInvalidation

    check canvas.closeGpuCanvasSurface()
    check not handle.valid
    check not handle.queueGpuFrame()
    check not handle.collectGpuFrame()
    host.close()

  test "GPU paint material composes through Style without an attachment node":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "gpu-style-material",
      GpuResourceBudget(
        persistentBytes: 8,
        readbackBytesPerFrame: 4,
        workUnitsPerFrame: 2,
        maxResources: 2
      )
    )
    var config = defaultGpuCanvasConfig(1, 1)
    config.readbackSlots = 1
    let canvas = host.newGpuCanvasSurface(namespace, config)
    let ui = initUiRoot()
    let button = ui.button(
      "Render",
      style = uiStyle([
        decl("width", px(96)),
        decl("height", px(36)),
        decl("overflow", keyword("hidden")),
        customPaint("gpu-accent", cpsUnderlay)
      ])
    )
    let nodeCount = ui.tree.nodes.len
    var material = ui.registerGpuPaintMaterial("gpu-accent", canvas)

    check material.valid
    check material.material == "gpu-accent"
    check ui.tree.nodes.len == nodeCount

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      ui.tree, ui.styleSheets(), defaultProperties(), diagnostics
    )
    let layout = computeLayout(ui.tree, styles, size(160, 80))
    let commands = ui.buildPaintCommands(styles, layout)
    var rasterIndex = -1
    var textIndex = -1
    for index, command in commands:
      if command.kind == pcDrawRasterSurface:
        rasterIndex = index
        check command.owner == some(button.container.id)
      elif command.kind == pcDrawText and command.node == button.labelNode.id:
        textIndex = index

    check not diagnostics.hasErrors
    check rasterIndex >= 0
    check textIndex >= 0
    check rasterIndex < textIndex
    check ui.takeCustomPaintDiagnostics().len == 0

    discard ui.consumeInvalidation()
    let frame = host.beginGpuFrame()
    check material.queueGpuFrame()
    check not material.queueGpuFrame()
    host.endGpuFrame(frame)
    check not material.collectGpuFrame()
    check not ui.hasPendingInvalidation

    context.readbackReady = true
    check material.collectGpuFrame()
    let invalidation = ui.consumeInvalidation()
    check invalidation.domains == {ddPaint}
    check invalidation.roots == @[button.container.id]

    check material.unregister()
    check not material.valid
    check not material.unregister()
    check canvas.closeGpuCanvasSurface()
    host.close()

  test "GPU paint material rejects duplicate names and unsupported stages":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "gpu-style-material-invalid",
      GpuResourceBudget(persistentBytes: 8, maxResources: 2)
    )
    var config = defaultGpuCanvasConfig(1, 1)
    config.readbackSlots = 1
    let canvas = host.newGpuCanvasSurface(namespace, config)
    let ui = initUiRoot()
    var material = ui.registerGpuPaintMaterial("gpu-accent", canvas)

    expect ValueError:
      discard ui.registerGpuPaintMaterial("gpu-accent", canvas)
    expect ValueError:
      discard ui.registerGpuPaintMaterial(
        "gpu-mask", canvas, {cpsMask}
      )

    check material.unregister()
    check canvas.closeGpuCanvasSurface()
    host.close()

  test "UI attachment rejects nil and closed GPU canvases":
    let ui = initUiRoot()
    expect ValueError:
      discard ui.gpuCanvas(nil)

    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "gpu-canvas-ui-closed",
      GpuResourceBudget(persistentBytes: 8, maxResources: 2)
    )
    var config = defaultGpuCanvasConfig(1, 1)
    config.readbackSlots = 1
    let canvas = host.newGpuCanvasSurface(namespace, config)
    check canvas.closeGpuCanvasSurface()
    expect ValueError:
      discard ui.gpuCanvas(canvas)
    host.close()

  test "GPU visual underlay fills a button without owning pointer semantics":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "gpu-button-underlay",
      GpuResourceBudget(
        persistentBytes: 8,
        readbackBytesPerFrame: 4,
        workUnitsPerFrame: 2,
        maxResources: 2
      )
    )
    var config = defaultGpuCanvasConfig(1, 1)
    config.readbackSlots = 1
    let canvas = host.newGpuCanvasSurface(namespace, config)
    let ui = initUiRoot()
    let button = ui.button(
      "Render",
      style = uiStyle([
        decl("width", px(96)),
        decl("height", px(36)),
        decl("overflow", keyword("hidden"))
      ])
    )
    let layer = ui.gpuVisualLayer(
      button.container,
      canvas,
      code = "render-button-gpu"
    )

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      ui.tree, ui.styleSheets(), defaultProperties(), diagnostics
    )
    let layout = computeLayout(ui.tree, styles, size(160, 80))
    let layerStyle = styles.styles[layer.nodeHandle.id.nodeIndex]
    let ownerBox = layout.boxFor(button.container.id).rect
    let layerBox = layout.boxFor(layer.nodeHandle.id).rect
    let hit = hitTest(
      buildHitRegions(ui.tree, layout, styles),
      vec2(ownerBox.x + ownerBox.w * 0.5, ownerBox.y + ownerBox.h * 0.5)
    )

    check not diagnostics.hasErrors
    check layer.valid
    check layer.placement == gvlUnderlay
    check ui.tree.nodes[layer.nodeHandle.id.nodeIndex].parent == some(button.container.id)
    check layerStyle.layout.position == pkAbsolute
    check layerStyle.layout.zIndex == -1
    check layerStyle.visual.pointerEvents == peNone
    check ui.tree.semanticInfo(layer.nodeHandle.id).hidden
    check layerBox == ownerBox
    check hit.isSome
    check hit.get.node == button.container.id

    ui.syncRenderSurfaces(styles, layout)
    let commands = buildPaintCommands(
      ui.tree, styles, layout, ui.scroll, ui.canvasPaintProvider()
    )
    var rasterIndex = -1
    var textIndex = -1
    for index, command in commands:
      if command.kind == pcDrawRasterSurface:
        rasterIndex = index
      elif command.kind == pcDrawText and command.node == button.labelNode.id:
        textIndex = index
    check rasterIndex >= 0
    check textIndex >= 0
    check rasterIndex < textIndex

    discard ui.consumeInvalidation()
    let frame = host.beginGpuFrame()
    check layer.queueGpuFrame()
    host.endGpuFrame(frame)
    context.readbackReady = true
    check layer.collectGpuFrame()
    let invalidation = ui.consumeInvalidation()
    check invalidation.domains == {ddPaint}
    check invalidation.roots == @[layer.nodeHandle.id]

    check canvas.closeGpuCanvasSurface()
    host.close()

  test "GPU visual layer invariants override conflicting caller geometry and input":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "gpu-button-overlay",
      GpuResourceBudget(
        persistentBytes: 8,
        readbackBytesPerFrame: 4,
        workUnitsPerFrame: 2,
        maxResources: 2
      )
    )
    var config = defaultGpuCanvasConfig(1, 1)
    config.readbackSlots = 1
    let canvas = host.newGpuCanvasSurface(namespace, config)
    let ui = initUiRoot()
    let owner = ui.box(uiStyle([
      decl("width", px(72)),
      decl("height", px(28))
    ]))
    let label = ui.text(owner, "Status")
    let layer = ui.gpuVisualLayer(
      owner,
      canvas,
      placement = gvlOverlay,
      style = uiStyle([
        decl("position", keyword("relative")),
        decl("width", px(5)),
        decl("height", px(6)),
        decl("z-index", number(99)),
        decl("pointer-events", keyword("auto")),
        decl("opacity", number(0.6))
      ])
    )

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      ui.tree, ui.styleSheets(), defaultProperties(), diagnostics
    )
    let layout = computeLayout(ui.tree, styles, size(120, 60))
    let layerStyle = styles.styles[layer.nodeHandle.id.nodeIndex]

    check not diagnostics.hasErrors
    check layer.placement == gvlOverlay
    check layerStyle.layout.position == pkAbsolute
    check layerStyle.layout.zIndex == 1
    check layerStyle.visual.pointerEvents == peNone
    check abs(layerStyle.visual.opacity - 0.6) < 0.001
    check layout.boxFor(layer.nodeHandle.id).rect == layout.boxFor(owner.id).rect

    ui.syncRenderSurfaces(styles, layout)
    let commands = buildPaintCommands(
      ui.tree, styles, layout, ui.scroll, ui.canvasPaintProvider()
    )
    var rasterIndex = -1
    var textIndex = -1
    for index, command in commands:
      if command.kind == pcDrawRasterSurface:
        rasterIndex = index
      elif command.kind == pcDrawText and command.node == label.id:
        textIndex = index
    check rasterIndex >= 0
    check textIndex >= 0
    check rasterIndex > textIndex

    check canvas.closeGpuCanvasSurface()
    host.close()

  test "GPU visual layer rejects invalid and foreign owners":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "gpu-layer-owner-validation",
      GpuResourceBudget(persistentBytes: 8, maxResources: 2)
    )
    var config = defaultGpuCanvasConfig(1, 1)
    config.readbackSlots = 1
    let canvas = host.newGpuCanvasSurface(namespace, config)
    let ui = initUiRoot()
    let other = initUiRoot()
    let foreignOwner = other.box()

    expect ValueError:
      discard ui.gpuVisualLayer(foreignOwner, canvas)
    expect ValueError:
      discard ui.gpuVisualLayer(NodeHandle(), canvas)

    check canvas.closeGpuCanvasSurface()
    host.close()

  test "canvas owns a render target and bounded readback ring":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "gpu-canvas-lifecycle",
      GpuResourceBudget(
        persistentBytes: 32,
        readbackBytesPerFrame: 24,
        workUnitsPerFrame: 6,
        maxResources: 4
      )
    )
    let canvas = host.newGpuCanvasSurface(namespace, 2, 1)
    check canvas.width == 2
    check canvas.height == 1
    check canvas.pendingFrameCount == 0
    check canvas.queuedFrameNumber == 0
    check canvas.completedFrameNumber == 0
    check canvas.renderTarget.kind == grkRenderTarget
    check canvas.rasterSurface.width == 2
    check canvas.rasterSurface.height == 1
    check context.renderTargetCreates == 1
    check context.textureCreates == DefaultGpuCanvasReadbackSlots
    check host.gpuNamespaceUsage(namespace).resourceCount == 4
    check canvas.closeGpuCanvasSurface()
    check canvas.isClosed
    check context.resourceDestroys == 4
    check host.gpuNamespaceUsage(namespace).resourceCount == 0
    check not canvas.closeGpuCanvasSurface()
    host.close()

  test "queued frames use backpressure and publish only the latest ready frame":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "gpu-canvas-frames",
      GpuResourceBudget(
        persistentBytes: 24,
        readbackBytesPerFrame: 16,
        workUnitsPerFrame: 4,
        maxResources: 3
      )
    )
    var config = defaultGpuCanvasConfig(2, 1)
    config.readbackSlots = 2
    let canvas = host.newGpuCanvasSurface(namespace, config)
    let frame = host.beginGpuFrame()
    check canvas.queueGpuCanvasFrame()
    check canvas.queueGpuCanvasFrame()
    check not canvas.queueGpuCanvasFrame()
    check canvas.pendingFrameCount == 2
    check canvas.queuedFrameNumber == 2
    check context.textureCopies == 2
    check context.readbackRequests == 2
    host.endGpuFrame(frame)

    check not canvas.collectGpuCanvasFrame()
    check canvas.rasterSurface.pendingUpdateCount == 0
    context.readbackReady = true
    check canvas.collectGpuCanvasFrame()
    check canvas.pendingFrameCount == 0
    check canvas.completedFrameNumber == 2
    check canvas.rasterSurface.pendingUpdateCount == 1
    check canvas.rasterSurface.revision == 1
    check canvas.rasterSurface.publish()
    check canvas.rasterSurface.revision == 2
    check canvas.rasterSurface.pixels == @[1'u8, 2, 3, 4, 5, 6, 7, 8]
    check canvas.closeGpuCanvasSurface()
    host.close()

  test "readback formats and alpha modes normalize to straight RGBA":
    for format in [gtfRgba8, gtfBgra8, gtfR8]:
      for alphaMode in [gcamStraight, gcamPremultiplied, gcamOpaque]:
        let context = newContext()
        let host = openGpuHost(context.backend, ghoOwned)
        let bytesPerTexture = if format == gtfR8: 1'u64 else: 4'u64
        let namespace = host.createGpuNamespace(
          "gpu-canvas-conversion-" & $format & "-" & $alphaMode,
          GpuResourceBudget(
            persistentBytes: bytesPerTexture * 2,
            readbackBytesPerFrame: bytesPerTexture,
            workUnitsPerFrame: 2,
            maxResources: 2
          )
        )
        var config = defaultGpuCanvasConfig(1, 1)
        config.format = format
        config.alphaMode = alphaMode
        config.readbackSlots = 1
        let canvas = host.newGpuCanvasSurface(namespace, config)
        let frame = host.beginGpuFrame()
        check canvas.queueGpuCanvasFrame()
        host.endGpuFrame(frame)
        context.readbackReady = true
        check canvas.collectGpuCanvasFrame()
        check canvas.rasterSurface.publish()
        case format
        of gtfR8:
          check canvas.rasterSurface.pixels == @[0'u8, 0, 0, 255]
        of gtfBgra8:
          case alphaMode
          of gcamStraight:
            check canvas.rasterSurface.pixels == @[2'u8, 1, 0, 3]
          of gcamPremultiplied:
            check canvas.rasterSurface.pixels == @[170'u8, 85, 0, 3]
          of gcamOpaque:
            check canvas.rasterSurface.pixels == @[2'u8, 1, 0, 255]
        of gtfRgba8:
          case alphaMode
          of gcamStraight:
            check canvas.rasterSurface.pixels == @[0'u8, 1, 2, 3]
          of gcamPremultiplied:
            check canvas.rasterSurface.pixels == @[0'u8, 85, 170, 3]
          of gcamOpaque:
            check canvas.rasterSurface.pixels == @[0'u8, 1, 2, 255]
        else:
          check false
        check canvas.closeGpuCanvasSurface()
        host.close()

  test "construction validates capabilities configuration and resource budgets":
    block invalidConfiguration:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "gpu-canvas-invalid-config",
        GpuResourceBudget(persistentBytes: 64, maxResources: 4)
      )
      var config = defaultGpuCanvasConfig(1, 1)
      config.readbackSlots = maxGpuPendingReadbacksPerNamespace + 1
      expect ValueError:
        discard host.newGpuCanvasSurface(namespace, config)
      config = defaultGpuCanvasConfig(1, 1)
      config.label = repeat('x', maxGpuResourceLabelBytes)
      expect ValueError:
        discard host.newGpuCanvasSurface(namespace, config)
      for format in [
          gtfR16F, gtfR32F, gtfRg16F, gtfRg32F, gtfRgba16F, gtfRgba32F
      ]:
        config = defaultGpuCanvasConfig(1, 1)
        config.format = format
        expect ValueError:
          discard host.newGpuCanvasSurface(namespace, config)
      check context.renderTargetCreates == 0
      host.close()

    block missingCapability:
      let context = newContext()
      context.copySupported = false
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "gpu-canvas-no-copy",
        GpuResourceBudget(persistentBytes: 8, maxResources: 2)
      )
      expect GpuHostError:
        discard host.newGpuCanvasSurface(namespace, 1, 1)
      check context.renderTargetCreates == 0
      host.close()

    block rollback:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "gpu-canvas-rollback",
        GpuResourceBudget(persistentBytes: 16, maxResources: 4)
      )
      var config = defaultGpuCanvasConfig(2, 1)
      config.readbackSlots = 3
      expect GpuHostError:
        discard host.newGpuCanvasSurface(namespace, config)
      check context.renderTargetCreates == 1
      check context.textureCreates == 1
      check context.resourceDestroys == 2
      check host.gpuNamespaceUsage(namespace).persistentBytes == 0
      check host.gpuNamespaceUsage(namespace).resourceCount == 0
      host.close()

  test "pending frames retain resources and device loss makes the canvas stale":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "gpu-canvas-stale",
      GpuResourceBudget(
        persistentBytes: 8,
        readbackBytesPerFrame: 4,
        workUnitsPerFrame: 2,
        maxResources: 2
      )
    )
    var config = defaultGpuCanvasConfig(1, 1)
    config.readbackSlots = 1
    let canvas = host.newGpuCanvasSurface(namespace, config)
    let frame = host.beginGpuFrame()
    check canvas.queueGpuCanvasFrame()
    host.endGpuFrame(frame)
    check not canvas.closeGpuCanvasSurface()
    check host.markGpuDeviceLost()
    expect GpuHostError:
      discard canvas.collectGpuCanvasFrame()
    expect GpuHostError:
      discard canvas.renderTarget
    check canvas.closeGpuCanvasSurface()
    check canvas.isClosed
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

suite "GPU direct surface lifecycle":

  test "capability negotiation rejects unsupported formats and buffer counts":
    let context = newContext()
    context.enableDirectPresentation(
      formats = {gtfRgba8, gtfRgba16F},
      maxBuffers = 3
    )
    let host = openGpuHost(context.backend, ghoOwned)
    var config = defaultGpuDirectSurfaceConfig(64, 32)
    check host.supportsGpuDirectSurface(config)
    config.format = gtfRgba16F
    check host.supportsGpuDirectSurface(config)
    config.format = gtfBgra8
    check not host.supportsGpuDirectSurface(config)
    config = defaultGpuDirectSurfaceConfig(64, 32)
    config.bufferCount = 4
    check not host.supportsGpuDirectSurface(config)
    config.bufferCount = 1
    expect ValueError:
      discard host.supportsGpuDirectSurface(config)
    config = defaultGpuDirectSurfaceConfig(8193, 32)
    check not host.supportsGpuDirectSurface(config)
    host.close()

  test "unsupported hosts fail before retaining resources":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "direct-unsupported",
      GpuResourceBudget(persistentBytes: 64, maxResources: 2)
    )
    let config = defaultGpuDirectSurfaceConfig(2, 2)
    check not host.supportsGpuDirectSurface(config)
    expect GpuHostError:
      discard host.newGpuDirectSurface(namespace, config)
    check host.gpuNamespaceUsage(namespace).resourceCount == 0
    host.close()

  test "a completed frame is published and protected until retired":
    let context = newContext()
    context.enableDirectPresentation(maxBuffers = 2)
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "direct-double-buffer",
      GpuResourceBudget(persistentBytes: 32, workUnitsPerFrame: 4, maxResources: 2)
    )
    var config = defaultGpuDirectSurfaceConfig(2, 2)
    config.bufferCount = 2
    let surface = host.newGpuDirectSurface(namespace, config)
    let first = host.createGpuRenderTarget(
      namespace, renderTargetDescriptor(2, 2, label = "direct-first")
    )
    let second = host.createGpuRenderTarget(
      namespace, renderTargetDescriptor(2, 2, label = "direct-second")
    )

    let firstToken = host.beginGpuFrame()
    check surface.queueGpuDirectSurfaceFrame(first, firstToken)
    check not surface.collectGpuDirectSurfaceFrame()
    check surface.presentedRevision == 0
    host.endGpuFrame(firstToken)
    check host.isGpuFrameComplete(firstToken)
    let nextToken = host.beginGpuFrame()
    check host.isGpuFrameComplete(firstToken)
    host.endGpuFrame(nextToken)
    check surface.collectGpuDirectSurfaceFrame()
    check surface.presentedRevision == 1
    var firstLease = surface.acquireGpuDirectSurfaceFrame().get
    check firstLease.resource == first
    check firstLease.provider == gpkCustom
    check firstLease.backendResource.backendResourceIdValue() != 0
    expect GpuHostError:
      discard host.releaseGpuResource(first)
    expect GpuHostError:
      discard host.closeGpuNamespace(namespace)

    let secondToken = host.beginGpuFrame()
    check surface.queueGpuDirectSurfaceFrame(second, secondToken)
    host.endGpuFrame(secondToken)
    check surface.collectGpuDirectSurfaceFrame()
    check surface.presentedRevision == 2
    check host.isGpuResourcePresentationRetained(first)
    check firstLease.release()
    check not host.isGpuResourcePresentationRetained(first)
    check host.releaseGpuResource(first)

    var secondLease = surface.acquireGpuDirectSurfaceFrame().get
    check secondLease.resource == second
    check not surface.closeGpuDirectSurface()
    check secondLease.release()
    check surface.closeGpuDirectSurface()
    check not host.isGpuResourcePresentationRetained(second)
    check host.releaseGpuResource(second)
    host.close()

  test "triple buffering applies backpressure and coalesces completed frames":
    let context = newContext()
    context.enableDirectPresentation(maxBuffers = 3)
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "direct-triple-buffer",
      GpuResourceBudget(persistentBytes: 64, maxResources: 4)
    )
    let surface = host.newGpuDirectSurface(
      namespace, defaultGpuDirectSurfaceConfig(1, 1)
    )
    var resources: seq[GpuResourceHandle]
    for index in 0 .. 3:
      resources.add host.createGpuRenderTarget(
        namespace,
        renderTargetDescriptor(1, 1, label = "direct-" & $index)
      )
    let token = host.beginGpuFrame()
    check surface.queueGpuDirectSurfaceFrame(resources[0], token)
    check surface.queueGpuDirectSurfaceFrame(resources[1], token)
    check surface.queueGpuDirectSurfaceFrame(resources[2], token)
    check not surface.queueGpuDirectSurfaceFrame(resources[3], token)
    check surface.pendingFrameCount == 3
    host.endGpuFrame(token)
    check surface.collectGpuDirectSurfaceFrame()
    check surface.pendingFrameCount == 0
    check surface.retainedFrameCount == 1
    let current = surface.acquireGpuDirectSurfaceFrame().get
    check current.resource == resources[2]
    var mutableCurrent = current
    check mutableCurrent.release()
    for index in 0 .. 1:
      check not host.isGpuResourcePresentationRetained(resources[index])
      check host.releaseGpuResource(resources[index])
    check surface.closeGpuDirectSurface()
    for index in 2 .. 3:
      check host.releaseGpuResource(resources[index])
    host.close()

  test "invalid resources and completion tokens fail atomically":
    let context = newContext()
    context.enableDirectPresentation(formats = {gtfRgba8}, maxBuffers = 2)
    let host = openGpuHost(context.backend, ghoOwned)
    let firstNamespace = host.createGpuNamespace(
      "direct-validation",
      GpuResourceBudget(persistentBytes: 128, maxResources: 4)
    )
    let secondNamespace = host.createGpuNamespace(
      "direct-foreign",
      GpuResourceBudget(persistentBytes: 64, maxResources: 2)
    )
    var config = defaultGpuDirectSurfaceConfig(2, 2)
    config.bufferCount = 2
    let surface = host.newGpuDirectSurface(firstNamespace, config)
    let wrongSize = host.createGpuRenderTarget(
      firstNamespace, renderTargetDescriptor(1, 2, label = "wrong-size")
    )
    let wrongFormat = host.createGpuRenderTarget(
      firstNamespace,
      renderTargetDescriptor(2, 2, gtfBgra8, label = "wrong-format")
    )
    let foreign = host.createGpuRenderTarget(
      secondNamespace, renderTargetDescriptor(2, 2, label = "foreign")
    )
    let valid = host.createGpuRenderTarget(
      firstNamespace, renderTargetDescriptor(2, 2, label = "valid")
    )
    let unsampled = host.createGpuRenderTarget(
      firstNamespace,
      renderTargetDescriptor(
        2, 2, usage = {gtuRenderTarget}, label = "unsampled"
      )
    )
    let token = host.beginGpuFrame()
    expect GpuHostError:
      discard surface.queueGpuDirectSurfaceFrame(wrongSize, token)
    expect GpuHostError:
      discard surface.queueGpuDirectSurfaceFrame(wrongFormat, token)
    expect GpuHostError:
      discard surface.queueGpuDirectSurfaceFrame(foreign, token)
    expect GpuHostError:
      discard surface.queueGpuDirectSurfaceFrame(unsampled, token)
    expect GpuHostError:
      discard surface.queueGpuDirectSurfaceFrame(
        valid,
        GpuFrameToken(number: token.number + 1, generation: token.generation)
      )
    check surface.retainedFrameCount == 0
    host.endGpuFrame(token)
    check surface.closeGpuDirectSurface()
    for resource in [wrongSize, wrongFormat, valid, unsampled]:
      check host.releaseGpuResource(resource)
    check host.releaseGpuResource(foreign)
    host.close()

  test "compute output requires an explicit direct capability":
    let context = newContext()
    context.enableDirectPresentation(
      maxBuffers = 2,
      computeOutput = false
    )
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "direct-compute",
      GpuResourceBudget(persistentBytes: 32, maxResources: 2)
    )
    var config = defaultGpuDirectSurfaceConfig(2, 2)
    config.bufferCount = 2
    config.acceptComputeOutput = false
    let surface = host.newGpuDirectSurface(namespace, config)
    let texture = host.createGpuTexture(
      namespace,
      textureDescriptor(
        2, 2, usage = {gtuSampled, gtuStorage}, label = "compute-output"
      )
    )
    let token = host.beginGpuFrame()
    expect GpuHostError:
      discard surface.queueGpuDirectSurfaceFrame(texture, token)
    host.endGpuFrame(token)
    check surface.closeGpuDirectSurface()
    check host.releaseGpuResource(texture)
    host.close()

  test "presentation retention rejects writes and device loss clears stale frames":
    let context = newContext()
    context.enableDirectPresentation(maxBuffers = 2)
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "direct-write-protection",
      GpuResourceBudget(
        persistentBytes: 64,
        workUnitsPerFrame: 4,
        maxResources: 3
      )
    )
    var config = defaultGpuDirectSurfaceConfig(2, 2)
    config.bufferCount = 2
    let surface = host.newGpuDirectSurface(namespace, config)
    let source = host.createGpuTexture(
      namespace,
      textureDescriptor(2, 2, usage = {gtuBlitSource}, label = "copy-source")
    )
    let destination = host.createGpuTexture(
      namespace,
      textureDescriptor(
        2, 2,
        usage = {gtuSampled, gtuBlitDestination},
        label = "presented-destination"
      )
    )
    let token = host.beginGpuFrame()
    check surface.queueGpuDirectSurfaceFrame(destination, token)
    expect GpuHostError:
      host.copyGpuTexture(namespace, source, destination)
    host.endGpuFrame(token)
    check surface.collectGpuDirectSurfaceFrame()
    check host.markGpuDeviceLost()
    check surface.isStale
    check not surface.acquireGpuDirectSurfaceFrame().isSome
    check surface.closeGpuDirectSurface()
    check not host.isGpuResourceLive(source)
    check not host.isGpuResourceLive(destination)
    host.close()

suite "GPU display surface negotiation and UI":

  test "direct surfaces participate in normal layout paint and component semantics":
    let context = newContext()
    context.enableDirectPresentation(maxBuffers = 2)
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "display-direct",
      GpuResourceBudget(persistentBytes: 64, maxResources: 2)
    )
    var config = defaultGpuDisplaySurfaceConfig(4, 2)
    config.bufferCount = 2
    config.alphaMode = gcamPremultiplied
    let display = host.newGpuDisplaySurface(namespace, config)
    check display.path == gdspDirect
    check display.directSurface() != nil
    check display.readbackSurface().isNil

    let target = host.createGpuRenderTarget(
      namespace, renderTargetDescriptor(4, 2, label = "display-target")
    )
    let ui = initUiRoot()
    let owner = ui.box(uiStyle([
      decl("width", px(120)),
      decl("height", px(48)),
      decl("overflow", keyword("hidden")),
      decl("border-radius", px(8))
    ]))
    let label = ui.text(owner, "GPU")
    let layer = ui.gpuDisplayVisualLayer(
      owner,
      display,
      placement = gdsvOverlay,
      style = uiStyle([decl("opacity", number(0.6))])
    )
    check layer.valid
    discard ui.consumeInvalidation()

    let token = host.beginGpuFrame()
    check layer.queueGpuFrame(target, token)
    check not layer.collectGpuFrame()
    check ui.consumeInvalidation().domains == {}
    host.endGpuFrame(token)
    check layer.collectGpuFrame()
    let invalidation = ui.consumeInvalidation()
    check ddPaint in invalidation.domains
    check layer.nodeHandle.id in invalidation.roots

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      ui.tree, ui.styleSheets(), defaultProperties(), diagnostics
    )
    let layout = computeLayout(ui.tree, styles, size(180, 80))
    let ownerBox = layout.boxFor(owner.id).rect
    let layerBox = layout.boxFor(layer.nodeHandle.id).rect
    check not diagnostics.hasErrors
    check layerBox == ownerBox
    let layerStyle = styles.styles[layer.nodeHandle.id.nodeIndex]
    check layerStyle.layout.position == pkAbsolute
    check layerStyle.layout.zIndex == 1
    check layerStyle.visual.pointerEvents == peNone
    check ui.tree.semanticInfo(layer.nodeHandle.id).hidden
    let hit = hitTest(
      buildHitRegions(ui.tree, layout, styles),
      vec2(ownerBox.x + 4, ownerBox.y + 4)
    )
    check hit.isSome
    check hit.get.node != layer.nodeHandle.id

    ui.syncRenderSurfaces(styles, layout)
    let commands = ui.buildPaintCommands(styles, layout)
    var gpuIndex = -1
    var textIndex = -1
    for index, command in commands:
      if command.kind == pcDrawGpuDirectSurface:
        gpuIndex = index
        check command.gpuSurfaceRect == ownerBox
        check abs(command.gpuSurfaceOpacity - 0.6) < 0.001
      elif command.kind == pcDrawText and command.node == label.id:
        textIndex = index
    check gpuIndex >= 0
    check textIndex >= 0
    check gpuIndex > textIndex

    var callbackCount = 0
    let status = commands[gpuIndex].compositeGpuDirectSurface(
      proc(
          request: GpuDirectCompositeRequest
      ): GpuDirectCompositeStatus {.closure.} =
        inc callbackCount
        check request.frame.resource == target
        check request.frame.backendResource.backendResourceIdValue() != 0
        check request.frame.alphaMode == gcamPremultiplied
        check request.frame.revision == 1
        check request.destination == ownerBox
        check abs(request.opacity - 0.6) < 0.001
        check not display.closeGpuDisplaySurface()
        gdcsPresented
    )
    check status == gdcsPresented
    check callbackCount == 1
    check display.closeGpuDisplaySurface()
    check host.releaseGpuResource(target)
    host.close()

  test "direct compositor releases its lease on retry and exceptions":
    let context = newContext()
    context.enableDirectPresentation(maxBuffers = 2)
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "display-compositor-cleanup",
      GpuResourceBudget(persistentBytes: 16, maxResources: 1)
    )
    var config = defaultGpuDisplaySurfaceConfig(2, 2)
    config.bufferCount = 2
    let display = host.newGpuDisplaySurface(namespace, config)
    let target = host.createGpuRenderTarget(
      namespace, renderTargetDescriptor(2, 2, label = "cleanup-target")
    )
    let token = host.beginGpuFrame()
    check display.queueGpuDisplayFrame(target, token)
    host.endGpuFrame(token)
    check display.collectGpuDisplayFrame()
    let command = drawGpuDirectSurface(
      NodeId(0), display.directSurface(), rect(0, 0, 2, 2)
    )

    check command.compositeGpuDirectSurface(
      proc(request: GpuDirectCompositeRequest): GpuDirectCompositeStatus =
        check request.frame.backendResource.backendResourceIdValue() != 0
        gdcsRetry
    ) == gdcsRetry
    expect GpuHostError:
      host.close()
    expect ValueError:
      discard command.compositeGpuDirectSurface(
        proc(request: GpuDirectCompositeRequest): GpuDirectCompositeStatus =
          discard request
          raise newException(ValueError, "compositor failed")
      )

    check display.closeGpuDisplaySurface()
    check host.releaseGpuResource(target)
    host.close()

  test "readback fallback keeps the same queue collect and UI contract":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "display-fallback",
      GpuResourceBudget(
        persistentBytes: 64,
        readbackBytesPerFrame: 8,
        workUnitsPerFrame: 2,
        maxResources: 4
      )
    )
    var config = defaultGpuDisplaySurfaceConfig(2, 1)
    config.bufferCount = 2
    let capabilities = host.gpuDisplaySurfaceCapabilities(config)
    check not capabilities.direct
    check capabilities.readbackFallback
    let display = host.newGpuDisplaySurface(namespace, config)
    check display.path == gdspReadback
    check display.directSurface().isNil
    check display.readbackSurface() != nil
    let source = host.createGpuTexture(
      namespace,
      textureDescriptor(
        2, 1, usage = {gtuBlitSource}, label = "fallback-source"
      )
    )
    let ui = initUiRoot()
    let handle = ui.gpuDisplaySurface(
      display,
      uiStyle([decl("width", px(80)), decl("height", px(40))])
    )
    discard ui.consumeInvalidation()

    let token = host.beginGpuFrame()
    check handle.queueGpuFrame(source, token)
    host.endGpuFrame(token)
    expect GpuHostError:
      discard display.queueGpuDisplayFrame(source, token)
    check not handle.collectGpuFrame()
    check ui.consumeInvalidation().domains == {}
    context.readbackReady = true
    check handle.collectGpuFrame()
    let invalidation = ui.consumeInvalidation()
    check ddPaint in invalidation.domains
    check handle.nodeHandle.id in invalidation.roots

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      ui.tree, ui.styleSheets(), defaultProperties(), diagnostics
    )
    let layout = computeLayout(ui.tree, styles, size(100, 60))
    ui.syncRenderSurfaces(styles, layout)
    let commands = ui.buildPaintCommands(styles, layout)
    check commands.anyIt(it.kind == pcDrawRasterSurface)
    check commands.allIt(it.kind != pcDrawGpuDirectSurface)
    check display.readbackSurface().rasterSurface().revision == 2

    check display.closeGpuDisplaySurface()
    check host.releaseGpuResource(source)
    host.close()

  test "required direct mode and unsupported fallback formats fail closed":
    let context = newContext()
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "display-no-path",
      GpuResourceBudget(persistentBytes: 64, maxResources: 4)
    )
    var config = defaultGpuDisplaySurfaceConfig(2, 2)
    config.fallback = gdsfRequireDirect
    expect GpuHostError:
      discard host.newGpuDisplaySurface(namespace, config)
    config.fallback = gdsfAllowReadback
    config.format = gtfRgba32F
    let capabilities = host.gpuDisplaySurfaceCapabilities(config)
    check not capabilities.direct
    check not capabilities.readbackFallback
    expect GpuHostError:
      discard host.newGpuDisplaySurface(namespace, config)

    config = defaultGpuDisplaySurfaceConfig(2, 2)
    config.maxRasterBytes = 15
    check not host.gpuDisplaySurfaceCapabilities(config).readbackFallback
    config.maxRasterBytes = 16
    config.label = repeat(
      'x', maxGpuResourceLabelBytes - len("-readback-8") + 1
    )
    check not host.gpuDisplaySurfaceCapabilities(config).readbackFallback
    host.close()

suite "GPU display surface quality matrix":

  test "configuration boundaries normalize valid defaults and reject invalid input":
    let context = newContext()
    context.enableDirectPresentation(maxBuffers = uint8(MaxGpuDirectSurfaceBuffers))
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("matrix-config", standardBudget())

    var config = defaultGpuDirectSurfaceConfig(1, 1)
    config.bufferCount = 0
    config.label = ""
    let defaults = host.newGpuDirectSurface(namespace, config)
    check defaults.config().bufferCount == DefaultGpuDirectSurfaceBuffers
    check defaults.config().label == "gpu-direct-surface"
    check defaults.closeGpuDirectSurface()

    for bufferCount in [MinGpuDirectSurfaceBuffers, MaxGpuDirectSurfaceBuffers]:
      config = defaultGpuDirectSurfaceConfig(1, 1)
      config.bufferCount = bufferCount
      check host.supportsGpuDirectSurface(config)

    config = defaultGpuDirectSurfaceConfig(8192, 8192)
    config.bufferCount = 2
    check host.supportsGpuDirectSurface(config)
    config.width = 8193
    check not host.supportsGpuDirectSurface(config)
    config = defaultGpuDirectSurfaceConfig(1, 1)
    config.label = repeat('x', maxGpuResourceLabelBytes)
    check host.supportsGpuDirectSurface(config)

    for bufferCount in [MinGpuDirectSurfaceBuffers - 1,
                        MaxGpuDirectSurfaceBuffers + 1]:
      config = defaultGpuDirectSurfaceConfig(1, 1)
      config.bufferCount = bufferCount
      expect ValueError:
        discard host.supportsGpuDirectSurface(config)
    for dimensions in [(0'u32, 1'u32), (1'u32, 0'u32), (0'u32, 0'u32)]:
      config = defaultGpuDirectSurfaceConfig(dimensions[0], dimensions[1])
      expect ValueError:
        discard host.supportsGpuDirectSurface(config)
    config = defaultGpuDirectSurfaceConfig(1, 1)
    config.label = repeat('x', maxGpuResourceLabelBytes + 1)
    expect ValueError:
      discard host.supportsGpuDirectSurface(config)

    host.close()

  test "texture render-target and compute capabilities are enforced independently":
    block textureOnly:
      let context = newContext()
      context.enableDirectPresentation(
        maxBuffers = 2, textures = true, renderTargets = false,
        computeOutput = true
      )
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "matrix-texture", GpuResourceBudget(persistentBytes: 64,
            maxResources: 2)
      )
      var config = defaultGpuDirectSurfaceConfig(2, 2)
      config.bufferCount = 2
      config.acceptComputeOutput = true
      let surface = host.newGpuDirectSurface(namespace, config)
      let texture = host.createGpuTexture(
        namespace,
        textureDescriptor(2, 2, usage = {gtuSampled, gtuStorage})
      )
      let target = host.createGpuRenderTarget(
        namespace, renderTargetDescriptor(2, 2)
      )
      let token = host.beginGpuFrame()
      check surface.queueGpuDirectSurfaceFrame(texture, token)
      expect GpuHostError:
        discard surface.queueGpuDirectSurfaceFrame(target, token)
      host.endGpuFrame(token)
      check surface.collectGpuDirectSurfaceFrame()
      check surface.closeGpuDirectSurface()
      check host.releaseGpuResource(texture)
      check host.releaseGpuResource(target)
      host.close()

    block computeNegotiation:
      let context = newContext()
      context.enableDirectPresentation(maxBuffers = 2, computeOutput = true)
      let host = openGpuHost(context.backend, ghoOwned)
      var config = defaultGpuDisplaySurfaceConfig(2, 2)
      config.bufferCount = 2
      check host.gpuDisplaySurfaceCapabilities(config).direct
      check not host.gpuDisplaySurfaceCapabilities(config).computeOutputDirect
      config.acceptComputeOutput = true
      check host.gpuDisplaySurfaceCapabilities(config).direct
      check host.gpuDisplaySurfaceCapabilities(config).computeOutputDirect
      host.close()

    block renderTargetOnly:
      let context = newContext()
      context.enableDirectPresentation(
        maxBuffers = 2, textures = false, renderTargets = true,
        computeOutput = false
      )
      let host = openGpuHost(context.backend, ghoOwned)
      let namespace = host.createGpuNamespace(
        "matrix-target", GpuResourceBudget(persistentBytes: 64, maxResources: 2)
      )
      var config = defaultGpuDirectSurfaceConfig(2, 2)
      config.bufferCount = 2
      let surface = host.newGpuDirectSurface(namespace, config)
      let texture = host.createGpuTexture(
        namespace, textureDescriptor(2, 2)
      )
      let target = host.createGpuRenderTarget(
        namespace, renderTargetDescriptor(2, 2)
      )
      let token = host.beginGpuFrame()
      check surface.queueGpuDirectSurfaceFrame(target, token)
      expect GpuHostError:
        discard surface.queueGpuDirectSurfaceFrame(texture, token)
      host.endGpuFrame(token)
      check surface.collectGpuDirectSurfaceFrame()
      check surface.closeGpuDirectSurface()
      check host.releaseGpuResource(texture)
      check host.releaseGpuResource(target)
      host.close()

  test "duplicate queue and backpressure failures are atomic and recoverable":
    let context = newContext()
    context.enableDirectPresentation(maxBuffers = 2)
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "matrix-backpressure",
      GpuResourceBudget(persistentBytes: 64, maxResources: 3)
    )
    var config = defaultGpuDirectSurfaceConfig(1, 1)
    config.bufferCount = 2
    let surface = host.newGpuDirectSurface(namespace, config)
    var resources: seq[GpuResourceHandle]
    for index in 0 .. 2:
      resources.add host.createGpuRenderTarget(
        namespace, renderTargetDescriptor(1, 1, label = "matrix-" & $index)
      )

    let token = host.beginGpuFrame()
    check surface.queueGpuDirectSurfaceFrame(resources[0], token)
    expect GpuHostError:
      discard surface.queueGpuDirectSurfaceFrame(resources[0], token)
    check surface.pendingFrameCount == 1
    check surface.retainedFrameCount == 1
    check surface.queueGpuDirectSurfaceFrame(resources[1], token)
    check not surface.queueGpuDirectSurfaceFrame(resources[2], token)
    check surface.pendingFrameCount == 2
    check not host.isGpuResourcePresentationRetained(resources[2])
    host.endGpuFrame(token)

    check surface.collectGpuDirectSurfaceFrame()
    check surface.pendingFrameCount == 0
    check surface.retainedFrameCount == 1
    let next = host.beginGpuFrame()
    check surface.queueGpuDirectSurfaceFrame(resources[2], next)
    host.endGpuFrame(next)
    check surface.collectGpuDirectSurfaceFrame()
    check surface.closeGpuDirectSurface()
    for resource in resources:
      check host.releaseGpuResource(resource)
    host.close()

  test "close waits for incomplete work and succeeds without an explicit collect":
    let context = newContext()
    context.enableDirectPresentation(maxBuffers = 2)
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "matrix-close", GpuResourceBudget(persistentBytes: 16, maxResources: 1)
    )
    var config = defaultGpuDirectSurfaceConfig(2, 2)
    config.bufferCount = 2
    let surface = host.newGpuDirectSurface(namespace, config)
    let target = host.createGpuRenderTarget(
      namespace, renderTargetDescriptor(2, 2)
    )
    let token = host.beginGpuFrame()
    check surface.queueGpuDirectSurfaceFrame(target, token)
    check not surface.closeGpuDirectSurface()
    check host.isGpuResourcePresentationRetained(target)
    host.endGpuFrame(token)
    check surface.closeGpuDirectSurface()
    check not host.isGpuResourcePresentationRetained(target)
    check not surface.closeGpuDirectSurface()
    check host.releaseGpuResource(target)
    host.close()

  test "multiple leases keep retired frames alive until the last release":
    let context = newContext()
    context.enableDirectPresentation(maxBuffers = 3)
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "matrix-leases", GpuResourceBudget(persistentBytes: 32, maxResources: 2)
    )
    let surface = host.newGpuDirectSurface(
      namespace, defaultGpuDirectSurfaceConfig(2, 2)
    )
    let first = host.createGpuRenderTarget(
      namespace, renderTargetDescriptor(2, 2, label = "lease-first")
    )
    let second = host.createGpuRenderTarget(
      namespace, renderTargetDescriptor(2, 2, label = "lease-second")
    )
    var token = host.beginGpuFrame()
    check surface.queueGpuDirectSurfaceFrame(first, token)
    host.endGpuFrame(token)
    check surface.collectGpuDirectSurfaceFrame()
    var firstLease = surface.acquireGpuDirectSurfaceFrame().get
    var secondLease = surface.acquireGpuDirectSurfaceFrame().get

    token = host.beginGpuFrame()
    check surface.queueGpuDirectSurfaceFrame(second, token)
    host.endGpuFrame(token)
    check surface.collectGpuDirectSurfaceFrame()
    check host.isGpuResourcePresentationRetained(first)
    check firstLease.release()
    check host.isGpuResourcePresentationRetained(first)
    check secondLease.release()
    check not host.isGpuResourcePresentationRetained(first)
    check not secondLease.release()
    check host.releaseGpuResource(first)

    check surface.closeGpuDirectSurface()
    check host.releaseGpuResource(second)
    host.close()

  test "device loss invalidates pending frames and outstanding leases safely":
    let context = newContext()
    context.enableDirectPresentation(maxBuffers = 2)
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "matrix-device-loss",
      GpuResourceBudget(persistentBytes: 32, maxResources: 2)
    )
    var config = defaultGpuDirectSurfaceConfig(2, 2)
    config.bufferCount = 2
    let surface = host.newGpuDirectSurface(namespace, config)
    let presented = host.createGpuRenderTarget(
      namespace, renderTargetDescriptor(2, 2, label = "loss-presented")
    )
    let pending = host.createGpuRenderTarget(
      namespace, renderTargetDescriptor(2, 2, label = "loss-pending")
    )
    var token = host.beginGpuFrame()
    check surface.queueGpuDirectSurfaceFrame(presented, token)
    host.endGpuFrame(token)
    check surface.collectGpuDirectSurfaceFrame()
    var lease = surface.acquireGpuDirectSurfaceFrame().get
    token = host.beginGpuFrame()
    check surface.queueGpuDirectSurfaceFrame(pending, token)
    host.endGpuFrame(token)

    check host.markGpuDeviceLost()
    check surface.isStale
    check not surface.collectGpuDirectSurfaceFrame()
    check not surface.acquireGpuDirectSurfaceFrame().isSome
    check not lease.release()
    check surface.pendingFrameCount == 0
    check surface.retainedFrameCount == 0
    check surface.closeGpuDirectSurface()
    host.close()

  test "bounded frame cycling remains stable across thousands of revisions":
    const FrameCount = 4096
    let context = newContext()
    context.enableDirectPresentation(maxBuffers = 3)
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "matrix-soak", GpuResourceBudget(persistentBytes: 48, maxResources: 3)
    )
    let surface = host.newGpuDirectSurface(
      namespace, defaultGpuDirectSurfaceConfig(2, 2)
    )
    var resources: seq[GpuResourceHandle]
    for index in 0 .. 2:
      resources.add host.createGpuRenderTarget(
        namespace, renderTargetDescriptor(2, 2, label = "soak-" & $index)
      )

    for frameNumber in 1 .. FrameCount:
      let token = host.beginGpuFrame()
      check surface.queueGpuDirectSurfaceFrame(
        resources[(frameNumber - 1) mod resources.len], token
      )
      host.endGpuFrame(token)
      check surface.collectGpuDirectSurfaceFrame()
      check surface.presentedRevision == uint64(frameNumber)
      check surface.pendingFrameCount == 0
      check surface.retainedFrameCount == 1
      var lease = surface.acquireGpuDirectSurfaceFrame().get
      check lease.revision == uint64(frameNumber)
      check lease.release()

    check surface.closeGpuDirectSurface()
    for resource in resources:
      check host.releaseGpuResource(resource)
    check host.gpuNamespaceUsage(namespace).resourceCount == 0
    host.close()

  test "compositor result matrix never leaks a presentation lease":
    let context = newContext()
    context.enableDirectPresentation(maxBuffers = 2)
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "matrix-compositor", GpuResourceBudget(persistentBytes: 16,
          maxResources: 1)
    )
    var config = defaultGpuDirectSurfaceConfig(2, 2)
    config.bufferCount = 2
    let surface = host.newGpuDirectSurface(namespace, config)
    let target = host.createGpuRenderTarget(
      namespace, renderTargetDescriptor(2, 2)
    )
    let emptyCommand = drawGpuDirectSurface(
      NodeId(0), surface, rect(0, 0, 2, 2)
    )
    check emptyCommand.compositeGpuDirectSurface(
      proc(request: GpuDirectCompositeRequest): GpuDirectCompositeStatus =
      discard request
      gdcsPresented
    ) == gdcsNoFrame
    check PaintCommand().compositeGpuDirectSurface(nil) == gdcsUnsupported

    let token = host.beginGpuFrame()
    check surface.queueGpuDirectSurfaceFrame(target, token)
    host.endGpuFrame(token)
    check surface.collectGpuDirectSurfaceFrame()
    for expected in [gdcsPresented, gdcsRetry, gdcsUnsupported, gdcsFailed]:
      check emptyCommand.compositeGpuDirectSurface(
        proc(request: GpuDirectCompositeRequest): GpuDirectCompositeStatus =
        check request.frame.resource == target
        expected
      ) == expected
      check surface.retainedFrameCount == 1
    check surface.closeGpuDirectSurface()
    check host.releaseGpuResource(target)
    host.close()

  test "fallback capability matrix rejects arithmetic overflow and missing backend features":
    block formats:
      let context = newContext()
      let host = openGpuHost(context.backend, ghoOwned)
      for format in GpuTextureFormat:
        let config = defaultGpuDisplaySurfaceConfig(2, 2, format)
        check host.gpuDisplaySurfaceCapabilities(config).readbackFallback ==
          (format in {gtfR8, gtfRgba8, gtfBgra8})

      var overflow = defaultGpuDisplaySurfaceConfig(
        0x80000000'u32, 0x80000000'u32
      )
      overflow.maxRasterBytes = high(int)
      check not host.gpuDisplaySurfaceCapabilities(overflow).readbackFallback
      host.close()

    for missingCopy in [false, true]:
      let context = newContext()
      context.copySupported = not missingCopy
      context.readbackSupported = missingCopy
      let host = openGpuHost(context.backend, ghoOwned)
      let config = defaultGpuDisplaySurfaceConfig(2, 2)
      check not host.gpuDisplaySurfaceCapabilities(config).readbackFallback
      host.close()

  test "closed display surfaces and handles reject further work without mutation":
    let context = newContext()
    context.enableDirectPresentation(maxBuffers = 2)
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace(
      "matrix-closed", GpuResourceBudget(persistentBytes: 16, maxResources: 1)
    )
    var config = defaultGpuDisplaySurfaceConfig(2, 2)
    config.bufferCount = 2
    let display = host.newGpuDisplaySurface(namespace, config)
    let target = host.createGpuRenderTarget(
      namespace, renderTargetDescriptor(2, 2)
    )
    let ui = initUiRoot()
    let handle = ui.gpuDisplaySurface(display)
    check handle.valid
    check display.closeGpuDisplaySurface()
    check display.isClosed
    check not handle.valid
    check not display.closeGpuDisplaySurface()
    check not display.collectGpuDisplayFrame()
    let token = host.beginGpuFrame()
    check not display.queueGpuDisplayFrame(target, token)
    host.endGpuFrame(token)
    check not host.isGpuResourcePresentationRetained(target)
    check host.releaseGpuResource(target)
    host.close()

  test "UI safety styles and ownership validation hold for both layer placements":
    let context = newContext()
    context.enableDirectPresentation(maxBuffers = 2)
    let host = openGpuHost(context.backend, ghoOwned)
    let namespace = host.createGpuNamespace("matrix-ui", standardBudget())
    var config = defaultGpuDisplaySurfaceConfig(2, 2)
    config.bufferCount = 2
    let display = host.newGpuDisplaySurface(namespace, config)
    let ui = initUiRoot()
    let foreignUi = initUiRoot()
    let owner = ui.box(uiStyle([
      decl("width", px(40)), decl("height", px(20))
    ]))
    let foreignOwner = foreignUi.box()
    expect ValueError:
      discard ui.gpuDisplayVisualLayer(foreignOwner, display)
    expect ValueError:
      discard ui.gpuDisplayVisualLayer(NodeHandle(), display)

    for placement in [gdsvUnderlay, gdsvOverlay]:
      let layer = ui.gpuDisplayVisualLayer(
        owner,
        display,
        placement = placement,
        style = uiStyle([
          decl("z-index", number(99)),
          decl("pointer-events", keyword("auto"))
        ])
      )
      var diagnostics: Diagnostics
      let styles = resolveTreeStyles(
        ui.tree, ui.styleSheets(), defaultProperties(), diagnostics
      )
      check not diagnostics.hasErrors
      let style = styles.styles[layer.nodeHandle.id.nodeIndex]
      check style.visual.pointerEvents == peNone
      check style.layout.position == pkAbsolute
      check style.layout.zIndex == (if placement == gdsvUnderlay: -1 else: 1)
      check ui.tree.semanticInfo(layer.nodeHandle.id).hidden

    check display.closeGpuDisplaySurface()
    expect ValueError:
      discard ui.gpuDisplaySurface(display)
    host.close()
