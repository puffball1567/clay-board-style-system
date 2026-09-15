import std/options

import ../core/[geometry, raster_surface]
import ../runtime/gpu_direct_surface
import ./[dirty_tiles, paint_command]

type
  RetainedDamagePlan* = object
    ## Backend-neutral result for one retained paint comparison.
    dirtyTiles*, totalTiles*: int
    regions*: seq[Rect]
    fullRepaint*: bool

  RetainedDamageTracker* = object
    ## Retains the previous paint snapshot and maps bounded changes to tiles.
    ## Backend adapters consume the plan; this object owns no render resource.
    grid: DirtyTileGrid
    previousCommands: seq[PaintCommand]
    previousBounds: seq[Option[Rect]]
    previousResourceRevisions: seq[uint64]
    initialized: bool

proc initRetainedDamageTracker*(
    width, height: int;
    tileSize = DefaultDirtyTileSize
): RetainedDamageTracker =
  ## Creates a bounded tracker for one fixed-size retained target.
  RetainedDamageTracker(grid: initDirtyTileGrid(width, height, tileSize))

proc width*(tracker: RetainedDamageTracker): int {.inline.} =
  tracker.grid.width

proc height*(tracker: RetainedDamageTracker): int {.inline.} =
  tracker.grid.height

proc tileSize*(tracker: RetainedDamageTracker): int {.inline.} =
  tracker.grid.tileSize

proc isInitialized*(tracker: RetainedDamageTracker): bool {.inline.} =
  tracker.initialized

proc reset*(
    tracker: var RetainedDamageTracker;
    width, height: int;
    tileSize = DefaultDirtyTileSize
) =
  ## Drops the retained snapshot after a target size or tile-policy change.
  tracker = initRetainedDamageTracker(width, height, tileSize)

proc resourceRevision(command: PaintCommand): uint64 =
  case command.kind
  of pcDrawRasterSurface:
    if command.rasterSurface.isNil: 0'u64
    else: command.rasterSurface.revision
  of pcDrawGpuDirectSurface:
    command.gpuDirectSurface.presentedRevision
  else:
    0'u64

proc resourceRevisions(commands: openArray[PaintCommand]): seq[uint64] =
  result = newSeq[uint64](commands.len)
  for index, command in commands:
    result[index] = command.resourceRevision

proc markCommandDamage(
    grid: var DirtyTileGrid;
    command: PaintCommand;
    bounds: Option[Rect]
): bool =
  if command.isPaintScopeCommand or not command.hasConservativeDamageBounds or
      bounds.isNone:
    return false
  discard grid.markDirty(bounds.get)
  true

proc markRasterResourceDamage(
    grid: var DirtyTileGrid;
    commands: openArray[PaintCommand];
    commandIndex: int
): bool =
  let command = commands[commandIndex]
  if command.kind != pcDrawRasterSurface or command.rasterSurface.isNil or
      command.rasterRect.isEmpty:
    return false
  let sourceWidth = command.rasterSurface.width
  let sourceHeight = command.rasterSurface.height
  if sourceWidth <= 0 or sourceHeight <= 0:
    return false
  for dirty in command.rasterSurface.dirtyRegions:
    let local = rect(
      command.rasterRect.x +
        dirty.x.float32 / sourceWidth.float32 * command.rasterRect.w,
      command.rasterRect.y +
        dirty.y.float32 / sourceHeight.float32 * command.rasterRect.h,
      dirty.width.float32 / sourceWidth.float32 * command.rasterRect.w,
      dirty.height.float32 / sourceHeight.float32 * command.rasterRect.h
    )
    let resolved = commands.resolvedVisualBoundsFor(commandIndex, local)
    if resolved.isSome:
      discard grid.markDirty(resolved.get)
  true

proc plan*(
    tracker: var RetainedDamageTracker;
    commands: openArray[PaintCommand];
    forceFullRepaint = false
): RetainedDamagePlan =
  ## Compares and retains `commands`, returning regions that must be replayed.
  ## Unbounded changes conservatively mark the complete target.
  if tracker.grid.width <= 0 or tracker.grid.height <= 0:
    raise newException(ValueError, "retained damage tracker is not initialized")
  tracker.grid.clear()
  var currentResourceRevisions = resourceRevisions(commands)
  var currentBounds = resolvedVisualBounds(commands)
  var fullRepaint = forceFullRepaint or not tracker.initialized

  if not fullRepaint:
    let commonLength = min(tracker.previousCommands.len, commands.len)
    for index in 0 ..< commonLength:
      let commandChanged = not samePaintCommand(
        tracker.previousCommands[index], commands[index]
      )
      let resourceChanged =
        tracker.previousResourceRevisions[index] != currentResourceRevisions[index]
      if not commandChanged and not resourceChanged:
        continue
      if not commandChanged and resourceChanged and
          commands[index].kind == pcDrawRasterSurface:
        if not tracker.grid.markRasterResourceDamage(commands, index):
          fullRepaint = true
          break
        continue
      if not tracker.grid.markCommandDamage(
          tracker.previousCommands[index], tracker.previousBounds[index]
        ) or not tracker.grid.markCommandDamage(commands[index], currentBounds[index]):
        fullRepaint = true
        break

    if not fullRepaint and tracker.previousCommands.len > commonLength:
      for index in commonLength ..< tracker.previousCommands.len:
        if not tracker.grid.markCommandDamage(
            tracker.previousCommands[index], tracker.previousBounds[index]
        ):
          fullRepaint = true
          break
    if not fullRepaint and commands.len > commonLength:
      for index in commonLength ..< commands.len:
        if not tracker.grid.markCommandDamage(commands[index], currentBounds[index]):
          fullRepaint = true
          break

  if fullRepaint:
    tracker.grid.clear()
    tracker.grid.markAll()

  result = RetainedDamagePlan(
    dirtyTiles: tracker.grid.dirtyTileCount,
    totalTiles: tracker.grid.totalTileCount,
    fullRepaint: fullRepaint,
    regions: tracker.grid.dirtyPixelRegions()
  )
  tracker.previousCommands = @commands
  tracker.previousBounds = move(currentBounds)
  tracker.previousResourceRevisions = move(currentResourceRevisions)
  tracker.initialized = true
