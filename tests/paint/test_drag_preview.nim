import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/backends/ppm/raster

proc pixel(image: RasterImage; x, y: int): tuple[r, g, b: uint8] =
  let index = (y * image.width + x) * 3
  (image.pixels[index], image.pixels[index + 1], image.pixels[index + 2])

suite "paint-only drag preview":
  test "preview follows the pointer without moving layout or hit regions":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let source = tree.addBox(parent = some(root), id = "source")
    let target = tree.addBox(parent = some(root), id = "target")
    let regions = @[
      HitRegion(node: source, rect: rect(2, 2, 4, 4), zIndex: 1),
      HitRegion(node: target, rect: rect(9, 6, 6, 6), zIndex: 1)
    ]
    let preview = initDragPreview(
      source, rect(2, 2, 4, 4), vec2(3, 3), opacity = 0.5
    )
    let sourceCommands = @[fillRect(rect(2, 2, 4, 4), rgb(1, 0, 0))]
    var state = initInteractionState()
    check preview.dragPreviewBounds(state, vec2(11, 7)).isNone
    check preview.dragPreviewCommands(state, vec2(11, 7), sourceCommands).len == 0

    discard state.processInput(tree, regions, pointerDownEvent(vec2(3, 3)))
    discard state.processInput(tree, regions, pointerMoveEvent(vec2(11, 7)))
    check state.dragTarget == some(source)
    check preview.dragPreviewBounds(state, vec2(11, 7)) ==
      some(rect(10, 6, 4, 4))
    check preview.dragPreviewBounds(state, vec2(12, 8)) ==
      some(rect(11, 7, 4, 4))
    let overlay = preview.dragPreviewCommands(
      state, vec2(11, 7), sourceCommands
    )
    check overlay.len == 5
    check overlay[0].kind == pcPushTransform
    check overlay[0].transformBounds == rect(2, 2, 4, 4)
    check sourceCommands[0].rect == rect(2, 2, 4, 4)
    var commands = @[fillRect(rect(0, 0, 20, 16), rgb(0, 0, 1))]
    commands.add overlay
    let image = render(commands, 20, 16)
    check image.pixel(3, 3) == (0'u8, 0'u8, 255'u8)
    check image.pixel(11, 7) == (128'u8, 0'u8, 128'u8)
    check image.pixel(15, 7) == (0'u8, 0'u8, 255'u8)

    discard state.processInput(tree, regions, pointerUpEvent(vec2(11, 7)))
    check preview.dragPreviewBounds(state, vec2(11, 7)).isNone
    check preview.dragPreviewCommands(state, vec2(11, 7), sourceCommands).len == 0

    discard state.processInput(tree, regions, pointerDownEvent(vec2(3, 3)))
    discard state.processInput(tree, regions, pointerMoveEvent(vec2(11, 7)))
    discard state.processInput(tree, regions, InputEvent(
      kind: iekPointerCancel, position: some(vec2(11, 7))
    ))
    check preview.dragPreviewBounds(state, vec2(11, 7)).isNone

  test "invalid preview inputs cannot reach a paint stream":
    var tree = initTree()
    let source = tree.addBox(id = "source")
    expect ValueError:
      discard initDragPreview(source, rect(0, 0, 0, 4), vec2(0, 0))
    expect ValueError:
      discard initDragPreview(
        source, rect(0, 0, 4, 4), vec2(0, 0), opacity = 2
      )
    let preview = initDragPreview(source, rect(0, 0, 4, 4), vec2(0, 0))
    var state = initInteractionState()
    check state.setFocusedTarget(some(source))
    check state.startKeyboardDrag(tree, source, {dgoCopy}).isSome
    check preview.dragPreviewCommands(
      state, vec2(4, 4), [fillRect(rect(0, 0, 4, 4), rgb(1, 0, 0))]
    ).len == 0

  test "nested source transforms remain inside the preview layer":
    var tree = initTree()
    let source = tree.addBox(id = "source")
    let regions = @[
      HitRegion(node: source, rect: rect(0, 0, 8, 8), zIndex: 1)
    ]
    var state = initInteractionState()
    discard state.processInput(tree, regions, pointerDownEvent(vec2(1, 1)))
    discard state.processInput(tree, regions, pointerMoveEvent(vec2(10, 6)))
    let preview = initDragPreview(
      source, rect(0, 0, 8, 8), vec2(1, 1), opacity = 0.5
    )
    let content = @[
      pushTransform(translationAffine2D(1, 0)),
      fillRect(rect(1, 1, 3, 3), rgb(0, 1, 0)),
      popTransform()
    ]
    var commands = @[fillRect(rect(0, 0, 20, 16), rgb(0, 0, 1))]
    commands.add preview.dragPreviewCommands(state, vec2(10, 6), content)
    let image = render(commands, 20, 16)
    check image.pixel(11, 6) == (0'u8, 128'u8, 128'u8)
    check image.pixel(10, 6) == (0'u8, 0'u8, 255'u8)
