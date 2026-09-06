import clay_board_style_system/core/raster_surface
import clay_board_style_system/runtime/gpu_host

const
  DefaultGpuCanvasReadbackSlots* = 3

type
  GpuCanvasAlphaMode* = GpuAlphaMode

  GpuCanvasConfig* = object
    width*, height*: uint32
    format*: GpuTextureFormat
    alphaMode*: GpuCanvasAlphaMode
    readbackSlots*: int
    label*: string
    maxRasterBytes*: int

  GpuCanvasReadbackSlot = object
    texture: GpuResourceHandle
    pending: bool
    readback: GpuReadbackHandle

  GpuCanvasSurface* = ref object
    host: GpuHost
    namespace: GpuNamespaceId
    generation: uint64
    configValue: GpuCanvasConfig
    target: GpuResourceHandle
    slots: seq[GpuCanvasReadbackSlot]
    pendingOrder: seq[int]
    surface: RasterSurface
    queuedFrameNumber, completedFrameNumber: uint64
    closedValue: bool

proc defaultGpuCanvasConfig*(width, height: uint32): GpuCanvasConfig =
  GpuCanvasConfig(
    width: width,
    height: height,
    format: gtfRgba8,
    alphaMode: gcamStraight,
    readbackSlots: DefaultGpuCanvasReadbackSlots,
    label: "gpu-canvas",
    maxRasterBytes: DefaultMaxRasterSurfaceBytes
  )

proc normalized(config: GpuCanvasConfig): GpuCanvasConfig =
  result = config
  if result.readbackSlots == 0:
    result.readbackSlots = DefaultGpuCanvasReadbackSlots
  if result.label.len == 0:
    result.label = "gpu-canvas"
  if result.maxRasterBytes == 0:
    result.maxRasterBytes = DefaultMaxRasterSurfaceBytes

  if result.width == 0 or result.height == 0:
    raise newException(ValueError, "GPU canvas dimensions must be positive")
  if result.format notin {gtfR8, gtfRgba8, gtfBgra8}:
    raise newException(
      ValueError,
      "GPU canvas readback supports only 8-bit raster formats"
    )
  if uint64(result.width) > uint64(high(int)) or
      uint64(result.height) > uint64(high(int)):
    raise newException(ValueError, "GPU canvas dimensions exceed addressable memory")
  if result.readbackSlots < 1 or
      result.readbackSlots > maxGpuPendingReadbacksPerNamespace:
    raise newException(ValueError, "GPU canvas readback slot count is invalid")
  if result.label.len + len("-readback-8") > maxGpuResourceLabelBytes:
    raise newException(ValueError, "GPU canvas label is too long")
  if result.maxRasterBytes <= 0:
    raise newException(ValueError, "GPU canvas raster byte limit must be positive")

proc releaseCreated(
    host: GpuHost;
    target: GpuResourceHandle;
    slots: var seq[GpuCanvasReadbackSlot]
) =
  for index in countdown(slots.high, 0):
    discard host.releaseGpuResource(slots[index].texture)
  if host.isGpuResourceLive(target):
    discard host.releaseGpuResource(target)

proc newGpuCanvasSurface*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    config: GpuCanvasConfig
): GpuCanvasSurface =
  if host.isNil:
    raise newException(ValueError, "GPU canvas host cannot be nil")
  let resolved = config.normalized()
  if not host.isReady():
    raise newException(GpuHostError, "GPU canvas requires a ready GPU host")
  if not host.hasGpuNamespace(namespace):
    raise newException(GpuHostError, "GPU canvas namespace is unknown")
  let info = host.backendInfo()
  if not info.textureCopySupported or not info.textureReadbackSupported:
    raise newException(
      GpuHostError,
      "GPU canvas requires texture-copy and texture-readback support"
    )

  let raster = newRasterSurface(
    int(resolved.width),
    int(resolved.height),
    maxBytes = resolved.maxRasterBytes
  )
  var target = host.createGpuRenderTarget(
    namespace,
    GpuRenderTargetDescriptor(
      width: resolved.width,
      height: resolved.height,
      format: resolved.format,
      usage: {gtuRenderTarget, gtuBlitSource},
      label: resolved.label & "-target"
    )
  )
  var slots: seq[GpuCanvasReadbackSlot]
  try:
    for index in 0 ..< resolved.readbackSlots:
      slots.add GpuCanvasReadbackSlot(
        texture: host.createGpuTexture(
          namespace,
          GpuTextureDescriptor(
            width: resolved.width,
            height: resolved.height,
            format: resolved.format,
            usage: {gtuBlitDestination, gtuReadback},
            label: resolved.label & "-readback-" & $(index + 1)
          )
        )
      )
  except CatchableError:
    host.releaseCreated(target, slots)
    raise

  GpuCanvasSurface(
    host: host,
    namespace: namespace,
    generation: host.generation(),
    configValue: resolved,
    target: target,
    slots: move(slots),
    surface: raster
  )

proc newGpuCanvasSurface*(
    host: GpuHost;
    namespace: GpuNamespaceId;
    width, height: uint32
): GpuCanvasSurface =
  host.newGpuCanvasSurface(namespace, defaultGpuCanvasConfig(width, height))

proc requireOpen(canvas: GpuCanvasSurface) =
  if canvas.isNil or canvas.closedValue:
    raise newException(ValueError, "GPU canvas is closed")
  if not canvas.host.isReady():
    raise newException(
      GpuHostError,
      "GPU canvas resources are stale and the canvas must be recreated"
    )
  if canvas.generation != canvas.host.generation() or
      not canvas.host.isGpuResourceLive(canvas.target):
    raise newException(
      GpuHostError,
      "GPU canvas resources are stale and the canvas must be recreated"
    )

proc config*(canvas: GpuCanvasSurface): GpuCanvasConfig =
  canvas.requireOpen()
  canvas.configValue

proc rasterSurface*(canvas: GpuCanvasSurface): RasterSurface =
  canvas.requireOpen()
  canvas.surface

proc renderTarget*(canvas: GpuCanvasSurface): GpuResourceHandle =
  canvas.requireOpen()
  canvas.target

proc width*(canvas: GpuCanvasSurface): int =
  if canvas.isNil: 0 else: int(canvas.configValue.width)

proc height*(canvas: GpuCanvasSurface): int =
  if canvas.isNil: 0 else: int(canvas.configValue.height)

proc pendingFrameCount*(canvas: GpuCanvasSurface): int =
  if canvas.isNil: 0 else: canvas.pendingOrder.len

proc queuedFrameNumber*(canvas: GpuCanvasSurface): uint64 =
  if canvas.isNil: 0'u64 else: canvas.queuedFrameNumber

proc completedFrameNumber*(canvas: GpuCanvasSurface): uint64 =
  if canvas.isNil: 0'u64 else: canvas.completedFrameNumber

proc isClosed*(canvas: GpuCanvasSurface): bool =
  canvas.isNil or canvas.closedValue

proc queueGpuCanvasFrameFrom*(
    canvas: GpuCanvasSurface;
    source: GpuResourceHandle
): bool {.discardable.} =
  canvas.requireOpen()
  if canvas.queuedFrameNumber == high(uint64):
    raise newException(ValueError, "GPU canvas frame number space exhausted")
  var slotIndex = -1
  for index in 0 ..< canvas.slots.len:
    if not canvas.slots[index].pending:
      slotIndex = index
      break
  if slotIndex < 0:
    return false

  let texture = canvas.slots[slotIndex].texture
  canvas.host.copyGpuTexture(canvas.namespace, source, texture)
  let readback = canvas.host.requestGpuReadback(canvas.namespace, texture)
  canvas.slots[slotIndex].readback = readback
  canvas.slots[slotIndex].pending = true
  canvas.pendingOrder.add slotIndex
  inc canvas.queuedFrameNumber
  true

proc queueGpuCanvasFrame*(canvas: GpuCanvasSurface): bool {.discardable.} =
  canvas.queueGpuCanvasFrameFrom(canvas.target)

proc unpremultiply(channel, alpha: uint8): uint8 {.inline.} =
  if alpha == 0:
    return 0
  uint8(min(255, (int(channel) * 255 + int(alpha) div 2) div int(alpha)))

proc convertReadback(
    data: GpuReadbackData;
    alphaMode: GpuCanvasAlphaMode
): seq[uint8] =
  let sourceChannels = if data.format == gtfR8: 1 else: 4
  let rowBytes = int(data.width) * sourceChannels
  if data.width == 0 or data.height == 0 or int(data.rowStride) < rowBytes:
    raise newException(GpuHostError, "GPU canvas readback shape is invalid")
  let required = (int(data.height) - 1) * int(data.rowStride) + rowBytes
  if data.pixels.len < required:
    raise newException(GpuHostError, "GPU canvas readback data is truncated")

  result = newSeq[uint8](int(data.width) * int(data.height) * RasterBytesPerPixel)
  for y in 0 ..< int(data.height):
    let sourceRow = y * int(data.rowStride)
    let destinationRow = y * int(data.width) * RasterBytesPerPixel
    for x in 0 ..< int(data.width):
      let source = sourceRow + x * sourceChannels
      let destination = destinationRow + x * RasterBytesPerPixel
      if data.format == gtfR8:
        let value = data.pixels[source]
        result[destination] = value
        result[destination + 1] = value
        result[destination + 2] = value
        result[destination + 3] = 255
      else:
        var red, green, blue: uint8
        if data.format == gtfBgra8:
          blue = data.pixels[source]
          green = data.pixels[source + 1]
          red = data.pixels[source + 2]
        else:
          red = data.pixels[source]
          green = data.pixels[source + 1]
          blue = data.pixels[source + 2]
        var alpha = data.pixels[source + 3]
        case alphaMode
        of gcamStraight:
          discard
        of gcamPremultiplied:
          red = unpremultiply(red, alpha)
          green = unpremultiply(green, alpha)
          blue = unpremultiply(blue, alpha)
        of gcamOpaque:
          alpha = 255
        result[destination] = red
        result[destination + 1] = green
        result[destination + 2] = blue
        result[destination + 3] = alpha

proc collectGpuCanvasFrame*(canvas: GpuCanvasSurface): bool {.discardable.} =
  canvas.requireOpen()
  if canvas.completedFrameNumber >
      high(uint64) - uint64(canvas.pendingOrder.len):
    raise newException(ValueError, "GPU canvas frame number space exhausted")
  var latest: GpuReadbackData
  var completed = 0
  while canvas.pendingOrder.len > 0:
    let slotIndex = canvas.pendingOrder[0]
    let state = canvas.host.gpuReadbackState(canvas.slots[slotIndex].readback)
    case state
    of grsPending:
      break
    of grsInvalid:
      for index in canvas.pendingOrder:
        canvas.slots[index].pending = false
      canvas.pendingOrder.setLen(0)
      raise newException(
        GpuHostError,
        "GPU canvas readback became invalid and the canvas must be recreated"
      )
    of grsReady:
      var data: GpuReadbackData
      if not canvas.host.tryTakeGpuReadback(
          canvas.slots[slotIndex].readback, data
      ):
        break
      canvas.slots[slotIndex].pending = false
      canvas.pendingOrder.delete(0)
      latest = move(data)
      inc completed

  if completed == 0:
    return false
  if latest.width != canvas.configValue.width or
      latest.height != canvas.configValue.height or
      latest.format != canvas.configValue.format:
    raise newException(GpuHostError, "GPU canvas readback does not match its surface")
  if latest.format == gtfRgba8 and
      canvas.configValue.alphaMode == gcamStraight:
    canvas.surface.replacePixels(latest.pixels, int(latest.rowStride))
  else:
    let rgba = convertReadback(latest, canvas.configValue.alphaMode)
    canvas.surface.replacePixels(rgba)
  canvas.completedFrameNumber += uint64(completed)
  true

proc closeGpuCanvasSurface*(canvas: GpuCanvasSurface): bool {.discardable.} =
  if canvas.isNil or canvas.closedValue:
    return false

  let resourcesAreCurrent =
    canvas.host.isReady() and canvas.generation == canvas.host.generation()
  if canvas.pendingOrder.len != 0 and resourcesAreCurrent:
    return false

  if resourcesAreCurrent:
    for index in countdown(canvas.slots.high, 0):
      discard canvas.host.releaseGpuResource(canvas.slots[index].texture)
    discard canvas.host.releaseGpuResource(canvas.target)
  canvas.pendingOrder.setLen(0)
  canvas.slots.setLen(0)
  canvas.closedValue = true
  true
