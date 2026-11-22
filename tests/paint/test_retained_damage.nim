import std/unittest

import clay_board_style_system/core/[color, custom_paint_parameter, geometry]
import clay_board_style_system/paint/[paint_command, retained_damage]

suite "retained damage planning":
  test "shader parameter snapshots compare by value and source damage covers the layer":
    proc layer(gain: float32): PaintCommand =
      pushShaderFilterLayer(rect(0, 0, 48, 16), LayerShaderFilter(material: "tint",
        parameters: customPaintParameters([customPaintFloat("u_gain", gain)])))
    check samePaintCommand(layer(1), layer(1))
    check not samePaintCommand(layer(1), layer(0.5))
    var tracker = initRetainedDamageTracker(64, 16, tileSize = 16)
    var commands = @[layer(1), fillRect(rect(15, 4, 1, 1), rgb(1, 0, 0)), popLayer()]
    discard tracker.plan(commands)
    commands[0] = layer(1)
    check tracker.plan(commands).dirtyTiles == 0
    commands[1] = fillRect(rect(15, 4, 1, 1), rgb(0, 1, 0))
    check tracker.plan(commands).regions == @[rect(0, 0, 48, 16)]

  test "shader source damage covers its transformed outset within an ancestor clip":
    var tracker = initRetainedDamageTracker(96, 64, tileSize = 8)
    var commands = @[
      pushClip(rect(0, 0, 48, 64)),
      pushTransform(translationAffine2D(32, 8)),
      pushShaderFilterLayer(rect(8, 16, 8, 8), LayerShaderFilter(material: "halo"),
        effectOutset = 8),
      pushClip(rect(8, 16, 8, 8)),
      fillRect(rect(10, 18, 1, 1), rgb(1, 0, 0)),
      popClip(), popLayer(), popTransform(), popClip()]
    commands.resolveTransformBounds()
    check commands[1].transformBounds == rect(0, 8, 24, 24)
    discard tracker.plan(commands)
    commands[4].color = rgb(0, 1, 0)
    let change = tracker.plan(commands)
    check not change.fullRepaint
    check change.regions == @[rect(32, 16, 16, 24)]

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
