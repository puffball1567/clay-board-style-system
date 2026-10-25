import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/backends/ppm/raster

proc pixel(image: RasterImage; x, y: int): tuple[r, g, b: uint8] =
  let index = (y * image.width + x) * 3
  (image.pixels[index], image.pixels[index + 1], image.pixels[index + 2])

suite "paint-only drop insertion indicator":
  test "accepted pointer target shows a marker on the selected edge":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let source = tree.addBox(parent = some(root), id = "source")
    let target = tree.addBox(parent = some(root), id = "target")
    let regions = @[
      HitRegion(node: source, rect: rect(0, 0, 3, 3), zIndex: 1),
      HitRegion(node: target, rect: rect(4, 4, 10, 10), zIndex: 1)
    ]
    let indicator = initDropInsertionIndicator(
      target, rect(4, 4, 10, 10), rgb(0, 0, 1), inset = 2
    )
    var state = initInteractionState()
    discard state.processInput(tree, regions, pointerDownEvent(vec2(1, 1)))
    check state.setDragOperations(source, {dgoMove})
    discard state.processInput(tree, regions, pointerMoveEvent(vec2(8, 6)))
    check indicator.dropInsertionSide(vec2(8, 6)) == some(disBefore)
    check indicator.dropInsertionSide(vec2(8, 12)) == some(disAfter)
    check indicator.dropInsertionCommands(state, disBefore).len == 0
    check state.acceptDropOperation(target, dgoMove)

    let before = indicator.dropInsertionCommands(state, disBefore)
    check before.len == 1
    check before[0].kind == pcFillRect
    check before[0].rect == rect(6, 3, 6, 2)
    check before[0].owner == some(target)
    var commands = @[fillRect(rect(0, 0, 18, 18), rgb(1, 1, 1))]
    commands.add before
    let firstImage = render(commands, 18, 18)
    check firstImage.pixel(8, 4) == (0'u8, 0'u8, 255'u8)
    check firstImage.pixel(4, 4) == (255'u8, 255'u8, 255'u8)

    let after = indicator.dropInsertionCommands(state, disAfter)
    check after[0].rect == rect(6, 13, 6, 2)
    let lastImage = render(after, 18, 18, rgb(1, 1, 1))
    check lastImage.pixel(8, 14) == (0'u8, 0'u8, 255'u8)
    check state.declineDropOperation(target)
    check indicator.dropInsertionCommands(state, disBefore).len == 0
    check state.acceptDropOperation(target, dgoMove)
    discard state.processInput(tree, regions, pointerUpEvent(vec2(8, 6)))
    check indicator.dropInsertionCommands(state, disBefore).len == 0
    check indicator.dropInsertionSide(vec2(8, 12)) == some(disAfter)

  test "horizontal marker supports accepted keyboard drag":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let source = tree.addBox(parent = some(root), id = "source")
    let target = tree.addBox(parent = some(root), id = "target")
    let indicator = initDropInsertionIndicator(
      target, rect(2, 2, 10, 8), rgb(1, 0, 0),
      axis = diaHorizontal, inset = 1
    )
    var state = initInteractionState()
    check state.setFocusedTarget(some(source))
    check state.startKeyboardDrag(tree, source, {dgoCopy}).isSome
    check state.setFocusedTarget(some(target))
    discard state.advanceKeyboardDrag(tree)
    check indicator.dropInsertionCommands(state, disAfter).len == 0
    check state.acceptDropOperation(target, dgoCopy)
    check indicator.dropInsertionSide(vec2(3, 6)) == some(disBefore)
    check indicator.dropInsertionSide(vec2(7, 6)) == some(disAfter)
    let marker = indicator.dropInsertionCommands(state, disAfter)
    check marker.len == 1
    check marker[0].rect == rect(11, 3, 2, 6)
    let reversed = initDropInsertionIndicator(
      target, rect(2, 2, 10, 8), rgb(1, 0, 0),
      axis = diaHorizontal, reversed = true, inset = 1
    )
    check reversed.dropInsertionSide(vec2(3, 6)) == some(disAfter)
    check reversed.dropInsertionSide(vec2(9, 6)) == some(disBefore)
    check reversed.dropInsertionCommands(state, disBefore)[0].rect ==
      rect(11, 3, 2, 6)
    discard state.cancelKeyboardDrag()
    check indicator.dropInsertionCommands(state, disAfter).len == 0

  test "invalid indicator geometry is rejected":
    var tree = initTree()
    let target = tree.addBox(id = "target")
    expect ValueError:
      discard initDropInsertionIndicator(
        target, rect(0, 0, 8, 8), rgb(1, 0, 0), inset = 4
      )
    expect ValueError:
      discard initDropInsertionIndicator(
        target, rect(0, 0, 8, 8), rgb(1, 0, 0), thickness = 0
      )
