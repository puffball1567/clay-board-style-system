import std/unittest

import clay_board_style_system/core/[color, geometry]
import clay_board_style_system/paint/[paint_command, retained_damage]

suite "retained damage planning":
  test "changes inside a blur invalidate the whole enclosing layer":
    var tracker = initRetainedDamageTracker(64, 16, tileSize = 16)
    var commands = @[
      pushBlurLayer(rect(0, 0, 48, 16), 2),
      fillRect(rect(15, 4, 1, 1), rgb(1, 0, 0)), popLayer()]
    discard tracker.plan(commands)
    commands[1] = fillRect(rect(15, 4, 1, 1), rgb(0, 1, 0))
    let change = tracker.plan(commands)
    check not change.fullRepaint
    check change.regions == @[rect(0, 0, 48, 16)]
    check tracker.plan(commands).dirtyTiles == 0

  test "bounded changes and explicit full invalidation are distinct":
    var tracker = initRetainedDamageTracker(128, 64, tileSize = 32)
    let initial = @[fillRect(rect(4, 4, 12, 12), rgb(1, 0, 0))]
    let first = tracker.plan(initial)
    check first.fullRepaint
    check first.dirtyTiles == 8

    let unchanged = tracker.plan(initial)
    check not unchanged.fullRepaint
    check unchanged.dirtyTiles == 0

    let changed = tracker.plan(@[
      fillRect(rect(4, 4, 12, 12), rgb(0, 1, 0))
    ])
    check not changed.fullRepaint
    check changed.dirtyTiles == 1
    check changed.regions == @[rect(0, 0, 32, 32)]

    let forced = tracker.plan(initial, forceFullRepaint = true)
    check forced.fullRepaint
    check forced.dirtyTiles == forced.totalTiles

  test "reset changes dimensions and invalidates the next frame":
    var tracker = initRetainedDamageTracker(32, 32, tileSize = 16)
    discard tracker.plan(newSeq[PaintCommand]())
    tracker.reset(96, 64, tileSize = 32)
    check tracker.width == 96
    check tracker.height == 64
    check tracker.tileSize == 32
    check not tracker.isInitialized
    let plan = tracker.plan(newSeq[PaintCommand]())
    check plan.fullRepaint
    check plan.totalTiles == 6

  test "default and invalid dimensions fail before mutation":
    var tracker: RetainedDamageTracker
    expect ValueError:
      discard tracker.plan(newSeq[PaintCommand]())
    expect ValueError:
      tracker.reset(0, 1)
