## Style-owned visual material backed by a filtered retained RasterSurface.
## The application owns the raster filter display and its filter materials.
import std/options

import ../core/[custom_paint, raster_surface]
import ../paint/[custom_paint_registry, paint_command]
import ./[gpu_canvas, gpu_display_surface, gpu_host,
  gpu_raster_filter_display, ui_root]

type
  GpuRasterFilterMaterialState = ref object
    filtered: GpuRasterFilterDisplay
    active: bool

  GpuRasterFilterMaterialHandle* = object
    root {.cursor.}: UiRoot
    registration: CustomPaintRegistration
    state: GpuRasterFilterMaterialState

proc valid*(handle: GpuRasterFilterMaterialHandle): bool =
  not handle.root.isNil and not handle.state.isNil and
    handle.state.active and not handle.state.filtered.isStale and
    handle.root.hasCustomPaintRegistration(handle.registration)

proc material*(handle: GpuRasterFilterMaterialHandle): string =
  handle.registration.material

proc queueGpuFrame*(
    handle: GpuRasterFilterMaterialHandle; frame: GpuFrameToken
): bool {.discardable.} =
  ## Queue a published raster revision inside its owning GPU host frame.
  if not handle.valid:
    return false
  handle.state.filtered.queueUpdatedGpuRasterFrame(frame)

proc collectGpuFrame*(
    handle: GpuRasterFilterMaterialHandle
): bool {.discardable.} =
  ## Publish completed readback pixels and invalidate only consumers.
  if not handle.valid:
    return false
  let display = handle.state.filtered.displaySurface()
  if not display.collectGpuDisplayFrame():
    return false
  if display.path in {gdspReadback, gdspHybrid}:
    discard display.readbackSurface().rasterSurface().publish()
  discard handle.root.invalidateCustomPaintMaterial(
    handle.registration.material)
  true

proc unregister*(
    handle: var GpuRasterFilterMaterialHandle
): bool {.discardable.} =
  if handle.root.isNil or handle.state.isNil or not handle.state.active:
    return false
  result = handle.root.unregisterCustomPaintMaterial(handle.registration)
  handle.state.active = false

proc registerGpuRasterFilterMaterial*(
    root: UiRoot;
    material: string;
    filtered: GpuRasterFilterDisplay;
    stages: set[CustomPaintStage] = {cpsUnderlay, cpsOverlay}
): GpuRasterFilterMaterialHandle =
  ## Makes filtered raster pixels available through ordinary Style without
  ## adding a layout, input, focus, or accessibility node.
  if root.isNil:
    raise newException(ValueError,
      "GPU raster filter material UiRoot cannot be nil")
  if filtered.isStale:
    raise newException(ValueError,
      "GPU raster filter material display must be open")
  if stages == {} or stages - {cpsUnderlay, cpsOverlay} != {}:
    raise newException(ValueError,
      "GPU raster filter material supports underlay and overlay only")
  let state = GpuRasterFilterMaterialState(filtered: filtered, active: true)
  let callback: CustomPaintMaterialProc = proc(
      request: CustomPaintRequest
  ): seq[PaintCommand] =
    if not state.active:
      return
    try:
      let display = state.filtered.displaySurface()
      case display.path
      of gdspDirect:
        result = @[drawGpuDirectSurface(request.owner,
          display.directSurface(), request.bounds, request.opacity)]
      of gdspReadback:
        result = @[drawRasterSurface(request.owner,
          display.readbackSurface().rasterSurface(),
          request.bounds, request.opacity)]
      of gdspHybrid:
        result = @[drawGpuDirectSurface(request.owner,
          display.directSurface(), request.bounds, request.opacity,
          fallback = display.readbackSurface().rasterSurface())]
    except ValueError, GpuHostError:
      result = @[]
  let registration = root.registerCustomPaintMaterialTracked(
    material, callback, stages)
  if registration.isNone:
    state.active = false
    raise newException(ValueError,
      "GPU raster filter material name is already registered")
  GpuRasterFilterMaterialHandle(
    root: root, registration: registration.get, state: state)
