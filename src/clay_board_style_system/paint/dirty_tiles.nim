import std/math

import ../core/geometry

const
  DefaultDirtyTileSize* = 64
  MaxDirtyTileCount* = 1_048_576

type
  DirtyTileRegion* = object
    x*, y*, width*, height*: int

  DirtyTileGrid* = object
    width*, height*, tileSize*: int
    columns*, rows*: int
    dirtyCount: int
    bits: seq[uint64]

proc dirtyTileRegion*(x, y, width, height: int): DirtyTileRegion =
  DirtyTileRegion(x: x, y: y, width: width, height: height)

proc initDirtyTileGrid*(
    width, height: int;
    tileSize = DefaultDirtyTileSize;
    maxTiles = MaxDirtyTileCount
): DirtyTileGrid =
  if width <= 0 or height <= 0:
    raise newException(ValueError, "dirty tile dimensions must be positive")
  if tileSize <= 0:
    raise newException(ValueError, "dirty tile size must be positive")
  if maxTiles <= 0:
    raise newException(ValueError, "dirty tile limit must be positive")
  let columns = 1 + (width - 1) div tileSize
  let rows = 1 + (height - 1) div tileSize
  if columns > maxTiles div rows:
    raise newException(ValueError, "dirty tile grid exceeds the configured limit")
  let count = columns * rows
  let wordCount = count div 64 + ord(count mod 64 != 0)
  DirtyTileGrid(
    width: width,
    height: height,
    tileSize: tileSize,
    columns: columns,
    rows: rows,
    bits: newSeq[uint64](wordCount)
  )

proc totalTileCount*(grid: DirtyTileGrid): int {.inline.} =
  grid.columns * grid.rows

proc dirtyTileCount*(grid: DirtyTileGrid): int {.inline.} =
  grid.dirtyCount

proc hasDirtyTiles*(grid: DirtyTileGrid): bool {.inline.} =
  grid.dirtyCount > 0

proc tileIsDirty(grid: DirtyTileGrid; index: int): bool {.inline.} =
  (grid.bits[index shr 6] and (1'u64 shl (index and 63))) != 0

proc markTile(grid: var DirtyTileGrid; index: int) {.inline.} =
  let word = index shr 6
  let mask = 1'u64 shl (index and 63)
  if (grid.bits[word] and mask) == 0:
    grid.bits[word] = grid.bits[word] or mask
    inc grid.dirtyCount

proc clear*(grid: var DirtyTileGrid) =
  for index in 0 ..< grid.bits.len:
    grid.bits[index] = 0
  grid.dirtyCount = 0

proc markAll*(grid: var DirtyTileGrid) =
  let count = grid.totalTileCount
  for index in 0 ..< count:
    grid.markTile(index)

proc markDirty*(grid: var DirtyTileGrid; bounds: Rect): int {.discardable.} =
  ## Marks every tile touched by a finite pixel-space rectangle. The rectangle
  ## is clipped to the grid, and fractional edges conservatively expand.
  if bounds.isEmpty or
      bounds.x.classify in {fcNan, fcInf, fcNegInf} or
      bounds.y.classify in {fcNan, fcInf, fcNegInf} or
      bounds.w.classify in {fcNan, fcInf, fcNegInf} or
      bounds.h.classify in {fcNan, fcInf, fcNegInf}:
    return 0
  let clipped = bounds.intersection(rect(
    0, 0, grid.width.float32, grid.height.float32
  ))
  if clipped.isEmpty:
    return 0
  let firstColumn = clamp(floor(clipped.x).int div grid.tileSize, 0, grid.columns - 1)
  let firstRow = clamp(floor(clipped.y).int div grid.tileSize, 0, grid.rows - 1)
  let lastColumn = clamp(
    (ceil(clipped.x + clipped.w).int - 1) div grid.tileSize,
    0,
    grid.columns - 1
  )
  let lastRow = clamp(
    (ceil(clipped.y + clipped.h).int - 1) div grid.tileSize,
    0,
    grid.rows - 1
  )
  let before = grid.dirtyCount
  for row in firstRow .. lastRow:
    for column in firstColumn .. lastColumn:
      grid.markTile(row * grid.columns + column)
  grid.dirtyCount - before

proc tileBounds*(grid: DirtyTileGrid; column, row: int): Rect =
  if column < 0 or column >= grid.columns or row < 0 or row >= grid.rows:
    raise newException(ValueError, "dirty tile coordinate is out of range")
  let x = column * grid.tileSize
  let y = row * grid.tileSize
  rect(
    x.float32,
    y.float32,
    min(grid.tileSize, grid.width - x).float32,
    min(grid.tileSize, grid.height - y).float32
  )

proc dirtyRegions*(grid: DirtyTileGrid): seq[DirtyTileRegion] =
  ## Coalesces equal horizontal runs across adjacent rows. Output regions do
  ## not overlap and are deterministic, making them suitable for clip/upload
  ## plans and stable tests.
  var openRuns: seq[DirtyTileRegion]
  for row in 0 ..< grid.rows:
    var rowRuns: seq[DirtyTileRegion]
    var column = 0
    while column < grid.columns:
      if not grid.tileIsDirty(row * grid.columns + column):
        inc column
        continue
      let first = column
      while column < grid.columns and
          grid.tileIsDirty(row * grid.columns + column):
        inc column
      rowRuns.add dirtyTileRegion(first, row, column - first, 1)

    var nextOpen = newSeqOfCap[DirtyTileRegion](max(openRuns.len, rowRuns.len))
    var openIndex = 0
    var rowIndex = 0
    while openIndex < openRuns.len and rowIndex < rowRuns.len:
      let current = openRuns[openIndex]
      let run = rowRuns[rowIndex]
      if current.x == run.x and current.width == run.width:
        var extended = current
        inc extended.height
        nextOpen.add extended
        inc openIndex
        inc rowIndex
      elif current.x < run.x or
          (current.x == run.x and current.width < run.width):
        result.add current
        inc openIndex
      else:
        nextOpen.add run
        inc rowIndex
    while openIndex < openRuns.len:
      result.add openRuns[openIndex]
      inc openIndex
    while rowIndex < rowRuns.len:
      nextOpen.add rowRuns[rowIndex]
      inc rowIndex
    openRuns = move(nextOpen)
  result.add openRuns

proc pixelBounds*(grid: DirtyTileGrid; region: DirtyTileRegion): Rect =
  if region.x < 0 or region.y < 0 or region.width <= 0 or region.height <= 0 or
      region.x > grid.columns - region.width or
      region.y > grid.rows - region.height:
    raise newException(ValueError, "dirty tile region is out of range")
  let x = region.x * grid.tileSize
  let y = region.y * grid.tileSize
  let right =
    if region.x + region.width == grid.columns: grid.width
    else: (region.x + region.width) * grid.tileSize
  let bottom =
    if region.y + region.height == grid.rows: grid.height
    else: (region.y + region.height) * grid.tileSize
  rect(x.float32, y.float32, (right - x).float32, (bottom - y).float32)

proc dirtyPixelRegions*(grid: DirtyTileGrid): seq[Rect] =
  for region in grid.dirtyRegions:
    result.add grid.pixelBounds(region)
