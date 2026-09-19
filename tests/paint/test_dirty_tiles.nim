import std/[math, unittest]

import clay_board_style_system

suite "retained dirty tile grid":
  test "fractional damage expands conservatively and clips to the surface":
    var grid = initDirtyTileGrid(130, 70, tileSize = 32)
    check grid.totalTileCount == 15
    check grid.markDirty(rect(31.5, 31.5, 1, 1)) == 4
    check grid.dirtyTileCount == 4
    check grid.markDirty(rect(-50, -50, 51, 51)) == 0
    check grid.markDirty(rect(129, 69, 20, 20)) == 1
    check grid.dirtyTileCount == 5

  test "duplicate and invalid damage are bounded no-ops":
    var grid = initDirtyTileGrid(64, 64, tileSize = 16)
    check grid.markDirty(rect(1, 1, 4, 4)) == 1
    check grid.markDirty(rect(1, 1, 4, 4)) == 0
    check grid.markDirty(rect(80, 80, 2, 2)) == 0
    check grid.markDirty(rect(0, 0, 0, 5)) == 0
    check grid.markDirty(rect(NaN.float32, 0, 2, 2)) == 0
    check grid.dirtyTileCount == 1

  test "equal horizontal runs coalesce across rows":
    var grid = initDirtyTileGrid(96, 80, tileSize = 32)
    discard grid.markDirty(rect(0, 0, 64, 64))
    discard grid.markDirty(rect(64, 64, 32, 16))
    check grid.dirtyRegions == @[
      dirtyTileRegion(0, 0, 2, 2),
      dirtyTileRegion(2, 2, 1, 1)
    ]
    check grid.dirtyPixelRegions == @[
      rect(0, 0, 64, 64),
      rect(64, 64, 32, 16)
    ]

  test "full damage includes clipped edge tiles and clear resets in place":
    var grid = initDirtyTileGrid(65, 33, tileSize = 32)
    grid.markAll()
    check grid.dirtyTileCount == 6
    check grid.dirtyPixelRegions == @[rect(0, 0, 65, 33)]
    check grid.tileBounds(2, 1) == rect(64, 32, 1, 1)
    grid.clear()
    check not grid.hasDirtyTiles
    check grid.dirtyRegions.len == 0

  test "invalid dimensions limits and coordinates fail closed":
    expect ValueError:
      discard initDirtyTileGrid(0, 10)
    expect ValueError:
      discard initDirtyTileGrid(10, 10, tileSize = 0)
    expect ValueError:
      discard initDirtyTileGrid(100, 100, tileSize = 1, maxTiles = 9_999)
    let grid = initDirtyTileGrid(10, 10)
    expect ValueError:
      discard grid.tileBounds(1, 0)
    expect ValueError:
      discard grid.pixelBounds(dirtyTileRegion(0, 0, 0, 1))

  test "edge bounds remain valid at the integer coordinate limit":
    let halfLimit = high(int) div 2 + 1
    let grid = initDirtyTileGrid(high(int), 1, tileSize = halfLimit)
    check grid.columns == 2
    check grid.pixelBounds(dirtyTileRegion(0, 0, 2, 1)) ==
      rect(0, 0, high(int).float32, 1)
