import ../../core/color
import ../../paint/[dirty_tiles, paint_command, retained_damage]
import ./raster

type
  RetainedRasterUpdate* = RetainedDamagePlan

  RetainedRasterCanvas* = ref object
    target: RasterImage
    damage: RetainedDamageTracker
    background: Color

proc newRetainedRasterCanvas*(
    width, height: int;
    background = rgb(1, 1, 1);
    tileSize = DefaultDirtyTileSize
): RetainedRasterCanvas =
  result = RetainedRasterCanvas(
    target: initRasterImage(width, height, background),
    damage: initRetainedDamageTracker(width, height, tileSize),
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

proc update*(
    canvas: RetainedRasterCanvas;
    commands: openArray[PaintCommand];
    background: Color
): RetainedRasterUpdate =
  if canvas.isNil:
    raise newException(ValueError, "retained raster canvas cannot be nil")

  result = canvas.damage.plan(
    commands,
    forceFullRepaint = canvas.background != background
  )
  for region in result.regions:
    canvas.target.renderInto(commands, region, background)

  canvas.background = background

proc update*(
    canvas: RetainedRasterCanvas;
    commands: openArray[PaintCommand]
): RetainedRasterUpdate =
  if canvas.isNil:
    raise newException(ValueError, "retained raster canvas cannot be nil")
  canvas.update(commands, canvas.background)
