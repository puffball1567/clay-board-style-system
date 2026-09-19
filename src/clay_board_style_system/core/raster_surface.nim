import std/atomics

const
  RasterBytesPerPixel* = 4
  DefaultMaxRasterSurfaceBytes* = 256 * 1024 * 1024
  MaxRasterDirtyRegions* = 32

type
  RasterPixelFormat* = enum
    rpfRgba8

  RasterColorSpace* = enum
    rcsSrgb

  RasterAlphaMode* = enum
    ramStraight

  RasterRegion* = object
    x*, y*, width*, height*: int

  RasterPatch = object
    region: RasterRegion
    pixels: seq[uint8]

  RasterSurface* = ref object
    surfaceId: uint64
    pixelWidth, pixelHeight: int
    pixelFormat: RasterPixelFormat
    colorSpace: RasterColorSpace
    alphaMode: RasterAlphaMode
    committedPixels: seq[uint8]
    pendingPatches: seq[RasterPatch]
    pendingBytes, maxPendingBytes: int
    publishedDirty: seq[RasterRegion]
    publishedRevision: uint64

var nextRasterSurfaceId: Atomic[uint64]

proc checkedByteLength(width, height: int; limit: int): int =
  if width <= 0 or height <= 0:
    raise newException(ValueError, "raster surface dimensions must be positive")
  if limit <= 0:
    raise newException(ValueError, "raster surface byte limit must be positive")
  if width > limit div RasterBytesPerPixel div height:
    raise newException(ValueError, "raster surface exceeds the configured byte limit")
  width * height * RasterBytesPerPixel

proc validateRegion(surface: RasterSurface; region: RasterRegion) =
  if surface.isNil:
    raise newException(ValueError, "raster surface cannot be nil")
  if region.x < 0 or region.y < 0 or region.width <= 0 or region.height <= 0:
    raise newException(ValueError, "raster update region must be positive and in bounds")
  if region.x > surface.pixelWidth - region.width or
      region.y > surface.pixelHeight - region.height:
    raise newException(ValueError, "raster update region is outside the surface")

proc rasterRegion*(x, y, width, height: int): RasterRegion =
  RasterRegion(x: x, y: y, width: width, height: height)

proc fullRegion(surface: RasterSurface): RasterRegion =
  RasterRegion(
    x: 0,
    y: 0,
    width: surface.pixelWidth,
    height: surface.pixelHeight
  )

proc right(region: RasterRegion): int {.inline.} = region.x + region.width
proc bottom(region: RasterRegion): int {.inline.} = region.y + region.height

proc touchesOrOverlaps(first, second: RasterRegion): bool {.inline.} =
  first.x <= second.right and second.x <= first.right and
    first.y <= second.bottom and second.y <= first.bottom

proc united(first, second: RasterRegion): RasterRegion =
  let x0 = min(first.x, second.x)
  let y0 = min(first.y, second.y)
  let x1 = max(first.right, second.right)
  let y1 = max(first.bottom, second.bottom)
  RasterRegion(x: x0, y: y0, width: x1 - x0, height: y1 - y0)

proc mergeDirty(regions: var seq[RasterRegion]; added: RasterRegion) =
  var merged = added
  var index = 0
  while index < regions.len:
    if regions[index].touchesOrOverlaps(merged):
      merged = regions[index].united(merged)
      regions.delete(index)
      index = 0
    else:
      inc index
  regions.add merged
  if regions.len > MaxRasterDirtyRegions:
    merged = regions[0]
    for current in regions.toOpenArray(1, regions.high):
      merged = merged.united(current)
    regions = @[merged]

proc newRasterSurface*(
    width, height: int;
    initialRgba: array[RasterBytesPerPixel, uint8] = [0'u8, 0'u8, 0'u8, 0'u8];
  maxBytes = DefaultMaxRasterSurfaceBytes
): RasterSurface =
  let byteLength = checkedByteLength(width, height, maxBytes)
  let surfaceId = nextRasterSurfaceId.fetchAdd(1'u64, moRelaxed) + 1'u64
  if surfaceId == 0:
    raise newException(ValueError, "raster surface identifier space exhausted")
  result = RasterSurface(
    surfaceId: surfaceId,
    pixelWidth: width,
    pixelHeight: height,
    pixelFormat: rpfRgba8,
    colorSpace: rcsSrgb,
    alphaMode: ramStraight,
    committedPixels: newSeq[uint8](byteLength),
    maxPendingBytes: maxBytes,
    publishedRevision: 1
  )
  if initialRgba != [0'u8, 0'u8, 0'u8, 0'u8]:
    for channel in 0 ..< RasterBytesPerPixel:
      result.committedPixels[channel] = initialRgba[channel]
    var filled = RasterBytesPerPixel
    while filled < byteLength:
      let copyLength = min(filled, byteLength - filled)
      copyMem(
        addr result.committedPixels[filled],
        unsafeAddr result.committedPixels[0],
        copyLength
      )
      filled += copyLength
  result.publishedDirty = @[result.fullRegion]

proc id*(surface: RasterSurface): uint64 =
  if surface.isNil: 0'u64 else: surface.surfaceId

proc width*(surface: RasterSurface): int =
  if surface.isNil: 0 else: surface.pixelWidth

proc height*(surface: RasterSurface): int =
  if surface.isNil: 0 else: surface.pixelHeight

proc format*(surface: RasterSurface): RasterPixelFormat =
  if surface.isNil: rpfRgba8 else: surface.pixelFormat

proc colorSpace*(surface: RasterSurface): RasterColorSpace =
  if surface.isNil: rcsSrgb else: surface.colorSpace

proc alphaMode*(surface: RasterSurface): RasterAlphaMode =
  if surface.isNil: ramStraight else: surface.alphaMode

proc revision*(surface: RasterSurface): uint64 =
  if surface.isNil: 0'u64 else: surface.publishedRevision

proc pixels*(surface: RasterSurface): lent seq[uint8] =
  if surface.isNil:
    raise newException(ValueError, "raster surface cannot be nil")
  surface.committedPixels

proc dirtyRegions*(surface: RasterSurface): lent seq[RasterRegion] =
  if surface.isNil:
    raise newException(ValueError, "raster surface cannot be nil")
  surface.publishedDirty

proc dirtyRegionCount*(surface: RasterSurface): int {.raises: [].} =
  if surface.isNil: 0 else: surface.publishedDirty.len

proc dirtyRegionAt*(surface: RasterSurface; index: int): RasterRegion =
  if surface.isNil:
    raise newException(ValueError, "raster surface cannot be nil")
  if index < 0 or index >= surface.publishedDirty.len:
    raise newException(ValueError, "raster dirty region index is out of range")
  surface.publishedDirty[index]

proc pendingUpdateCount*(surface: RasterSurface): int =
  if surface.isNil: 0 else: surface.pendingPatches.len

proc updateRegion*(
    surface: RasterSurface;
    region: RasterRegion;
    source: openArray[uint8];
    sourceStride = 0
) =
  surface.validateRegion(region)
  let rowBytes = region.width * RasterBytesPerPixel
  let stride = if sourceStride == 0: rowBytes else: sourceStride
  if stride < rowBytes:
    raise newException(ValueError, "raster source stride is smaller than one row")
  if region.height > 1 and stride > (high(int) - rowBytes) div (region.height - 1):
    raise newException(ValueError, "raster source byte range overflows")
  let required = (region.height - 1) * stride + rowBytes
  if source.len < required:
    raise newException(ValueError, "raster source does not contain the update region")
  let patchBytes = rowBytes * region.height
  if patchBytes > surface.maxPendingBytes - surface.pendingBytes:
    raise newException(ValueError, "raster pending updates exceed the byte limit")

  var patch = RasterPatch(
    region: region,
    pixels: newSeq[uint8](patchBytes)
  )
  for row in 0 ..< region.height:
    let sourceOffset = row * stride
    let patchOffset = row * rowBytes
    copyMem(
      addr patch.pixels[patchOffset], unsafeAddr source[sourceOffset], rowBytes
    )
  surface.pendingPatches.add move(patch)
  surface.pendingBytes += patchBytes

proc replacePixels*(
    surface: RasterSurface;
    source: openArray[uint8];
    sourceStride = 0
) =
  if surface.isNil:
    raise newException(ValueError, "raster surface cannot be nil")
  var previousPatches = move(surface.pendingPatches)
  let previousBytes = surface.pendingBytes
  surface.pendingPatches = @[]
  surface.pendingBytes = 0
  try:
    surface.updateRegion(surface.fullRegion, source, sourceStride)
  except CatchableError:
    surface.pendingPatches = move(previousPatches)
    surface.pendingBytes = previousBytes
    raise

proc publish*(surface: RasterSurface): bool {.discardable.} =
  if surface.isNil:
    raise newException(ValueError, "raster surface cannot be nil")
  if surface.pendingPatches.len == 0:
    return false
  if surface.publishedRevision == high(uint64):
    raise newException(ValueError, "raster surface revision space exhausted")

  var dirty: seq[RasterRegion]
  for patch in surface.pendingPatches:
    dirty.mergeDirty(patch.region)

  for patch in surface.pendingPatches:
    let rowBytes = patch.region.width * RasterBytesPerPixel
    for row in 0 ..< patch.region.height:
      let sourceOffset = row * rowBytes
      let destinationOffset =
        ((patch.region.y + row) * surface.pixelWidth + patch.region.x) *
          RasterBytesPerPixel
      copyMem(
        addr surface.committedPixels[destinationOffset],
        unsafeAddr patch.pixels[sourceOffset],
        rowBytes
      )

  surface.pendingPatches.setLen(0)
  surface.pendingBytes = 0
  surface.publishedDirty = move(dirty)
  inc surface.publishedRevision
  true
