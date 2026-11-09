## Optional pixel-space crop of a sampled GPU surface.
type GpuSurfaceCrop* = object
  enabled: bool
  x, y, width, height: uint32

proc gpuSurfaceCrop*(
    x, y, width, height: uint32
): GpuSurfaceCrop =
  ## Coordinates are measured from the source's top-left corner.
  if width == 0 or height == 0:
    raise newException(ValueError,
      "GPU surface crop must have positive dimensions")
  GpuSurfaceCrop(enabled: true, x: x, y: y,
    width: width, height: height)

proc isGpuCropActive*(crop: GpuSurfaceCrop): bool =
  crop.enabled

proc sampledGpuCropUv*(
    crop: GpuSurfaceCrop; sourceWidth, sourceHeight: uint32;
    rowsBottomUp: bool
): tuple[uv, clampUv: seq[float32]] =
  ## UV bounds and texel-center clamps keep linear sampling inside an atlas tile.
  if sourceWidth == 0 or sourceHeight == 0:
    raise newException(ValueError, "GPU surface crop requires a nonempty source")
  let x = if crop.enabled: crop.x else: 0'u32
  let y = if crop.enabled: crop.y else: 0'u32
  let width = if crop.enabled: crop.width else: sourceWidth
  let height = if crop.enabled: crop.height else: sourceHeight
  if width == 0 or height == 0 or
      uint64(x) + uint64(width) > uint64(sourceWidth) or
      uint64(y) + uint64(height) > uint64(sourceHeight):
    raise newException(ValueError, "GPU surface crop exceeds source bounds")
  let left = float32(x) / float32(sourceWidth)
  let right = float32(uint64(x) + uint64(width)) / float32(sourceWidth)
  let top = float32(y) / float32(sourceHeight)
  let bottom = float32(uint64(y) + uint64(height)) / float32(sourceHeight)
  result.uv = if rowsBottomUp:
    @[left, 1'f32 - top, right, 1'f32 - bottom]
  else:
    @[left, top, right, bottom]
  let insetX = 0.5'f32 / float32(sourceWidth)
  let insetY = 0.5'f32 / float32(sourceHeight)
  result.clampUv = if rowsBottomUp:
    @[left + insetX, 1'f32 - bottom + insetY,
      right - insetX, 1'f32 - top - insetY]
  else:
    @[left + insetX, top + insetY,
      right - insetX, bottom - insetY]
