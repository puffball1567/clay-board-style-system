import ../core/raster_surface
import ./[gpu_canvas, gpu_direct_surface, gpu_host]

type
  GpuDisplaySurfaceFallback* = enum
    gdsfRequireDirect,
    gdsfAllowReadback

  GpuDisplaySurfacePath* = enum
    gdspDirect,
    gdspReadback

  GpuDisplaySurfaceConfig* = object
    width*, height*: uint32
    format*: GpuTextureFormat
    bufferCount*: int
    acceptComputeOutput*: bool
    fallback*: GpuDisplaySurfaceFallback
    alphaMode*: GpuAlphaMode
    label*: string
    maxRasterBytes*: int

  GpuDisplaySurfaceCapabilities* = object
    direct*: bool
    readbackFallback*: bool
    computeOutputDirect*: bool
    format*: GpuTextureFormat
    maxDirectBuffers*: int

  GpuDisplaySurface* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    configValue: GpuDisplaySurfaceConfig
    pathValue: GpuDisplaySurfacePath
    directValue: GpuDirectSurface
    readbackValue: GpuCanvasSurface
    closedValue: bool

proc defaultGpuDisplaySurfaceConfig*(
    width, height: uint32;
    format = gtfRgba8
): GpuDisplaySurfaceConfig =
  GpuDisplaySurfaceConfig(
    width: width,
    height: height,
    format: format,
    bufferCount: DefaultGpuDirectSurfaceBuffers,
    fallback: gdsfAllowReadback,
    alphaMode: gcamStraight,
    label: "gpu-display-surface",
    maxRasterBytes: DefaultMaxRasterSurfaceBytes
  )

proc normalized(config: GpuDisplaySurfaceConfig): GpuDisplaySurfaceConfig =
  result = config
  if result.bufferCount == 0:
    result.bufferCount = DefaultGpuDirectSurfaceBuffers
  if result.label.len == 0:
    result.label = "gpu-display-surface"
  if result.maxRasterBytes == 0:
    result.maxRasterBytes = DefaultMaxRasterSurfaceBytes
  if result.width == 0 or result.height == 0:
    raise newException(ValueError, "GPU display surface dimensions must be positive")
  if result.bufferCount < MinGpuDirectSurfaceBuffers or
      result.bufferCount > MaxGpuDirectSurfaceBuffers:
    raise newException(ValueError, "GPU display surface buffer count is invalid")
  if result.label.len > maxGpuResourceLabelBytes:
    raise newException(ValueError, "GPU display surface label is too long")
  if result.maxRasterBytes <= 0:
    raise newException(ValueError, "GPU display surface raster byte limit must be positive")

proc directConfig(config: GpuDisplaySurfaceConfig): GpuDirectSurfaceConfig =
  GpuDirectSurfaceConfig(
    width: config.width,
    height: config.height,
    format: config.format,
    bufferCount: config.bufferCount,
    acceptComputeOutput: config.acceptComputeOutput,
    alphaMode: config.alphaMode,
    label: config.label
  )

proc gpuDisplaySurfaceCapabilities*(
    host: GpuHost;
    config: GpuDisplaySurfaceConfig
): GpuDisplaySurfaceCapabilities =
  if host.isNil or not host.isReady():
    return
  let resolved = config.normalized()
  let info = host.backendInfo()
  let rasterPixels = uint64(resolved.width) * uint64(resolved.height)
  let rasterSizeFits = rasterPixels <= high(uint64) div 4'u64
  let rasterBytes =
    if rasterSizeFits: rasterPixels * 4'u64
    else: high(uint64)
  result.direct = host.supportsGpuDirectSurface(resolved.directConfig())
  result.readbackFallback =
    rasterSizeFits and
    resolved.format in {gtfR8, gtfRgba8, gtfBgra8} and
    info.textureCopySupported and info.textureReadbackSupported and
    rasterBytes <= uint64(resolved.maxRasterBytes) and
    resolved.label.len + len("-readback-8") <= maxGpuResourceLabelBytes
  result.computeOutputDirect =
    result.direct and resolved.acceptComputeOutput and
    info.directComputeOutputPresentationSupported
  result.format = resolved.format
  result.maxDirectBuffers = int(info.maxDirectPresentationBuffers)

proc newGpuDisplaySurface*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    config: GpuDisplaySurfaceConfig
): GpuDisplaySurface =
  if host.isNil:
    raise newException(ValueError, "GPU display surface host cannot be nil")
  if not host.isReady():
    raise newException(GpuHostError, "GPU display surface host is not ready")
  if not host.hasGpuNamespace(namespace):
    raise newException(GpuHostError, "GPU display surface namespace is unknown")
  let resolved = config.normalized()
  let capabilities = host.gpuDisplaySurfaceCapabilities(resolved)
  result = GpuDisplaySurface(
    host: host,
    namespace: namespace,
    configValue: resolved
  )
  if capabilities.direct:
    result.pathValue = gdspDirect
    result.directValue = host.newGpuDirectSurface(
      namespace, resolved.directConfig()
    )
  elif resolved.fallback == gdsfAllowReadback and capabilities.readbackFallback:
    result.pathValue = gdspReadback
    var fallbackConfig = defaultGpuCanvasConfig(
      resolved.width, resolved.height
    )
    fallbackConfig.format = resolved.format
    fallbackConfig.alphaMode = resolved.alphaMode
    fallbackConfig.readbackSlots = resolved.bufferCount
    fallbackConfig.label = resolved.label
    fallbackConfig.maxRasterBytes = resolved.maxRasterBytes
    result.readbackValue = host.newGpuCanvasSurface(namespace, fallbackConfig)
  else:
    raise newException(
      GpuHostError,
      "GPU display surface has no compatible direct or readback path"
    )

proc config*(surface: GpuDisplaySurface): GpuDisplaySurfaceConfig =
  if surface.isNil:
    raise newException(ValueError, "GPU display surface cannot be nil")
  surface.configValue

proc path*(surface: GpuDisplaySurface): GpuDisplaySurfacePath =
  if surface.isNil:
    raise newException(ValueError, "GPU display surface cannot be nil")
  surface.pathValue

proc directSurface*(surface: GpuDisplaySurface): GpuDirectSurface =
  if surface.isNil or surface.pathValue != gdspDirect:
    return nil
  surface.directValue

proc readbackSurface*(surface: GpuDisplaySurface): GpuCanvasSurface =
  if surface.isNil or surface.pathValue != gdspReadback:
    return nil
  surface.readbackValue

proc isClosed*(surface: GpuDisplaySurface): bool =
  surface.isNil or surface.closedValue

proc queueGpuDisplayFrame*(
    surface: GpuDisplaySurface;
    resource: GpuResourceHandle;
    completion: GpuFrameToken
): bool {.discardable.} =
  if surface.isNil or surface.closedValue:
    return false
  case surface.pathValue
  of gdspDirect:
    surface.directValue.queueGpuDirectSurfaceFrame(resource, completion)
  of gdspReadback:
    if not surface.host.isGpuFrameActive(completion):
      raise newException(
        GpuHostError,
        "GPU readback fallback must be queued in its active source frame"
      )
    surface.readbackValue.queueGpuCanvasFrameFrom(resource)

proc collectGpuDisplayFrame*(surface: GpuDisplaySurface): bool {.discardable.} =
  if surface.isNil or surface.closedValue:
    return false
  case surface.pathValue
  of gdspDirect:
    surface.directValue.collectGpuDirectSurfaceFrame()
  of gdspReadback:
    surface.readbackValue.collectGpuCanvasFrame()

proc closeGpuDisplaySurface*(surface: GpuDisplaySurface): bool {.discardable.} =
  if surface.isNil or surface.closedValue:
    return false
  result =
    case surface.pathValue
    of gdspDirect:
      surface.directValue.closeGpuDirectSurface()
    of gdspReadback:
      surface.readbackValue.closeGpuCanvasSurface()
  if result:
    surface.closedValue = true
