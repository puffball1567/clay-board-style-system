## Optional pixel-space placement of a sampled surface within a GPU target.
type GpuSurfacePlacement* = object
  enabled: bool
  x, y: int32
  width, height: uint32

proc gpuSurfacePlacement*(
    x, y: int32; width, height: uint32
): GpuSurfacePlacement =
  ## Bounds are measured from the destination's top-left corner.
  if width == 0 or height == 0:
    raise newException(ValueError,
      "GPU surface placement must have positive dimensions")
  GpuSurfacePlacement(enabled: true, x: x, y: y,
    width: width, height: height)

proc isGpuPlacementActive*(placement: GpuSurfacePlacement): bool =
  placement.enabled

proc normalizedGpuPlacement*(
    placement: GpuSurfacePlacement; targetWidth, targetHeight: uint32
): seq[float32] =
  ## The default value covers the whole destination.
  if not placement.enabled:
    return @[0'f32, 0'f32, 1'f32, 1'f32]
  @[
    float32(placement.x) / float32(targetWidth),
    float32(placement.y) / float32(targetHeight),
    float32(placement.width) / float32(targetWidth),
    float32(placement.height) / float32(targetHeight)
  ]
