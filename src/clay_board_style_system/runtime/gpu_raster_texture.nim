import ../core/raster_surface
import ./gpu_host

const DefaultGpuRasterTexturePartialRegions* = 8

type
  GpuRasterTextureConfig* = object
    usage*: set[GpuTextureUsage]
    maxPartialRegions*: int
    label*: string

  GpuRasterTextureSyncKind* = enum
    grtskUnchanged,
    grtskPartial,
    grtskFull

  GpuRasterTextureSyncResult* = object
    kind*: GpuRasterTextureSyncKind
    revision*: uint64
    regionCount*: int
    uploadedBytes*: uint64

  GpuRasterTexture* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    generation: uint64
    configValue: GpuRasterTextureConfig
    sourceValue: RasterSurface
    textureValue: GpuResourceHandle
    uploadedRevisionValue: uint64
    closedValue: bool

proc defaultGpuRasterTextureConfig*(): GpuRasterTextureConfig =
  GpuRasterTextureConfig(
    usage: {gtuSampled},
    maxPartialRegions: DefaultGpuRasterTexturePartialRegions,
    label: "gpu-raster-texture"
  )

proc normalized(config: GpuRasterTextureConfig): GpuRasterTextureConfig =
  result = config
  if result.usage == {}:
    result.usage = {gtuSampled}
  if result.maxPartialRegions == 0:
    result.maxPartialRegions = DefaultGpuRasterTexturePartialRegions
  if result.label.len == 0:
    result.label = "gpu-raster-texture"
  if gtuReadback in result.usage:
    raise newException(
      ValueError,
      "GPU raster textures cannot use the readback-only texture lifecycle"
    )
  if result.maxPartialRegions < 1 or
      result.maxPartialRegions > MaxRasterDirtyRegions:
    raise newException(ValueError, "GPU raster texture partial-region limit is invalid")
  if result.label.len > maxGpuResourceLabelBytes:
    raise newException(ValueError, "GPU raster texture label is too long")

proc newGpuRasterTexture*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    source: RasterSurface;
    config = defaultGpuRasterTextureConfig()
): GpuRasterTexture =
  if host.isNil:
    raise newException(ValueError, "GPU raster texture host cannot be nil")
  if source.isNil:
    raise newException(ValueError, "GPU raster texture source cannot be nil")
  if not host.isReady():
    raise newException(GpuHostError, "GPU raster texture host is not ready")
  if not host.hasGpuNamespace(namespace):
    raise newException(GpuHostError, "GPU raster texture namespace is unknown")
  if source.width <= 0 or source.height <= 0 or
      uint64(source.width) > uint64(high(uint32)) or
      uint64(source.height) > uint64(high(uint32)):
    raise newException(ValueError, "GPU raster texture dimensions are invalid")
  if uint64(source.width) > uint64(high(uint32)) div RasterBytesPerPixel.uint64:
    raise newException(ValueError, "GPU raster texture row stride is too large")

  let resolved = config.normalized()
  let texture = host.createGpuTexture(
    namespace,
    GpuTextureDescriptor(
      width: uint32(source.width),
      height: uint32(source.height),
      format: gtfRgba8,
      usage: resolved.usage,
      access: gtaDynamic,
      label: resolved.label
    ),
    source.pixels
  )
  GpuRasterTexture(
    host: host,
    namespace: namespace,
    generation: host.generation(),
    configValue: resolved,
    sourceValue: source,
    textureValue: texture,
    uploadedRevisionValue: source.revision
  )

proc isClosed*(surface: GpuRasterTexture): bool =
  surface.isNil or surface.closedValue

proc isStale*(surface: GpuRasterTexture): bool =
  surface.isNil or surface.closedValue or not surface.host.isReady() or
    surface.generation != surface.host.generation() or
    not surface.host.isGpuResourceLive(surface.textureValue)

proc requireOpen(surface: GpuRasterTexture) =
  if surface.isNil or surface.closedValue:
    raise newException(ValueError, "GPU raster texture is closed")
  if surface.isStale():
    raise newException(
      GpuHostError,
      "GPU raster texture is stale and must be recreated"
    )

proc config*(surface: GpuRasterTexture): GpuRasterTextureConfig =
  surface.requireOpen()
  surface.configValue

proc source*(surface: GpuRasterTexture): RasterSurface =
  surface.requireOpen()
  surface.sourceValue

proc texture*(surface: GpuRasterTexture): GpuResourceHandle =
  surface.requireOpen()
  surface.textureValue

proc uploadedRevision*(surface: GpuRasterTexture): uint64 =
  if surface.isNil: 0'u64 else: surface.uploadedRevisionValue

proc syncGpuRasterTexture*(
    surface: GpuRasterTexture
): GpuRasterTextureSyncResult {.discardable.} =
  surface.requireOpen()
  let revision = surface.sourceValue.revision
  result.revision = revision
  if revision == surface.uploadedRevisionValue:
    return
  if revision < surface.uploadedRevisionValue:
    raise newException(GpuHostError, "GPU raster texture revision moved backwards")

  let consecutive = surface.uploadedRevisionValue < high(uint64) and
    surface.uploadedRevisionValue + 1 == revision
  let dirtyCount = surface.sourceValue.dirtyRegionCount
  if consecutive and dirtyCount > 0 and
      dirtyCount <= surface.configValue.maxPartialRegions:
    let pixels = surface.sourceValue.pixels
    let sourceStride = surface.sourceValue.width * RasterBytesPerPixel
    var uploadBytes = 0'u64
    for region in surface.sourceValue.dirtyRegions:
      let rowBytes = region.width * RasterBytesPerPixel
      let byteLength = (region.height - 1) * sourceStride + rowBytes
      if uint64(byteLength) > high(uint64) - uploadBytes:
        raise newException(GpuHostError, "GPU raster texture upload size overflows")
      uploadBytes += uint64(byteLength)
    surface.host.validateGpuFrameWork(
      surface.namespace,
      transientBytes = uploadBytes,
      workUnits = uint32(dirtyCount)
    )
    for region in surface.sourceValue.dirtyRegions:
      let rowBytes = region.width * RasterBytesPerPixel
      let byteOffset =
        (region.y * surface.sourceValue.width + region.x) * RasterBytesPerPixel
      let byteLength = (region.height - 1) * sourceStride + rowBytes
      surface.host.updateGpuTexture(
        surface.textureValue,
        GpuTextureUpdateRegion(
          x: uint32(region.x),
          y: uint32(region.y),
          width: uint32(region.width),
          height: uint32(region.height)
        ),
        pixels.toOpenArray(byteOffset, byteOffset + byteLength - 1),
        rowStride = uint32(sourceStride)
      )
    result.kind = grtskPartial
    result.regionCount = dirtyCount
    result.uploadedBytes = uploadBytes
  else:
    let pixels = surface.sourceValue.pixels
    surface.host.updateGpuTexture(surface.textureValue, pixels)
    result.kind = grtskFull
    result.regionCount = 1
    result.uploadedBytes = uint64(pixels.len)

  surface.uploadedRevisionValue = revision

proc closeGpuRasterTexture*(surface: GpuRasterTexture): bool {.discardable.} =
  if surface.isNil or surface.closedValue:
    return false
  if surface.host.isReady() and surface.generation == surface.host.generation() and
      surface.host.isGpuResourceLive(surface.textureValue):
    discard surface.host.releaseGpuResource(surface.textureValue)
  surface.closedValue = true
  true
