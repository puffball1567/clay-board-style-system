import std/options

import ../../core/[color, geometry, raster_surface]
import ../../paint/[dirty_tiles, paint_command]
import ./raster

type
  RetainedRasterUpdate* = object
    dirtyTiles*, totalTiles*: int
    regions*: seq[Rect]
    fullRepaint*: bool

  RetainedRasterCanvas* = ref object
    target: RasterImage
    grid: DirtyTileGrid
    previousCommands: seq[PaintCommand]
    previousResourceRevisions: seq[uint64]
    background: Color
    initialized: bool

proc newRetainedRasterCanvas*(
    width, height: int;
    background = rgb(1, 1, 1);
    tileSize = DefaultDirtyTileSize
): RetainedRasterCanvas =
  result = RetainedRasterCanvas(
    target: initRasterImage(width, height, background),
    grid: initDirtyTileGrid(width, height, tileSize),
    background: background
  )

proc image*(canvas: RetainedRasterCanvas): lent RasterImage =
  if canvas.isNil:
    raise newException(ValueError, "retained raster canvas cannot be nil")
  canvas.target

proc width*(canvas: RetainedRasterCanvas): int =
  if canvas.isNil: 0 else: canvas.target.width

proc height*(canvas: RetainedRasterCanvas): int =
  if canvas.isNil: 0 else: canvas.target.height

proc resourceRevision(command: PaintCommand): uint64 =
  case command.kind
  of pcDrawRasterSurface:
    command.rasterSurface.revision
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

proc update*(
    canvas: RetainedRasterCanvas;
    commands: openArray[PaintCommand];
    background: Color
): RetainedRasterUpdate =
  if canvas.isNil:
    raise newException(ValueError, "retained raster canvas cannot be nil")

  canvas.grid.clear()
  var currentResourceRevisions = resourceRevisions(commands)
  var fullRepaint = not canvas.initialized or canvas.background != background

  if not fullRepaint:
    let previousBounds = resolvedVisualBounds(canvas.previousCommands)
    let currentBounds = resolvedVisualBounds(commands)
    let commonLength = min(canvas.previousCommands.len, commands.len)
    for index in 0 ..< commonLength:
      let commandChanged = not samePaintCommand(
        canvas.previousCommands[index], commands[index]
      )
      let resourceChanged =
        canvas.previousResourceRevisions[index] != currentResourceRevisions[index]
      if not commandChanged and not resourceChanged:
        continue
      if not commandChanged and resourceChanged and
          commands[index].kind == pcDrawRasterSurface:
        if not canvas.grid.markRasterResourceDamage(commands, index):
          fullRepaint = true
          break
        continue
      if not canvas.grid.markCommandDamage(
          canvas.previousCommands[index], previousBounds[index]
        ) or not canvas.grid.markCommandDamage(commands[index], currentBounds[index]):
        fullRepaint = true
        break

    if not fullRepaint and canvas.previousCommands.len > commonLength:
      for index in commonLength ..< canvas.previousCommands.len:
        if not canvas.grid.markCommandDamage(
            canvas.previousCommands[index], previousBounds[index]
        ):
          fullRepaint = true
          break
    if not fullRepaint and commands.len > commonLength:
      for index in commonLength ..< commands.len:
        if not canvas.grid.markCommandDamage(commands[index], currentBounds[index]):
          fullRepaint = true
          break

  if fullRepaint:
    canvas.grid.clear()
    canvas.grid.markAll()

  result = RetainedRasterUpdate(
    dirtyTiles: canvas.grid.dirtyTileCount,
    totalTiles: canvas.grid.totalTileCount,
    fullRepaint: fullRepaint
  )
  result.regions = canvas.grid.dirtyPixelRegions()
  for region in result.regions:
    canvas.target.renderInto(commands, region, background)

  canvas.previousCommands = @commands
  canvas.previousResourceRevisions = move(currentResourceRevisions)
  canvas.background = background
  canvas.initialized = true

proc update*(
    canvas: RetainedRasterCanvas;
    commands: openArray[PaintCommand]
): RetainedRasterUpdate =
  if canvas.isNil:
    raise newException(ValueError, "retained raster canvas cannot be nil")
  canvas.update(commands, canvas.background)
