import std/[options, sequtils, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

suite "drop child reordering":
  test "a committed drop changes layout and paint order":
    let ui = initUiRoot()
    let host = ui.box(id = "host")
    let first = ui.box(parent = some(host), id = "first")
    let second = ui.box(parent = some(host), id = "second")
    check ui.moveChildForDrop(host.id, first.id, second.id, disAfter)

    let sheet = styleSheet([
      rule(id("host"), [
        decl("width", px(100)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(id("first"), [
        decl("width", px(20)), decl("height", px(20)),
        decl("background-color", colorValue(rgb(1, 0, 0)))
      ]),
      rule(id("second"), [
        decl("width", px(20)), decl("height", px(20)),
        decl("background-color", colorValue(rgb(0, 0, 1)))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      ui.tree, [sheet], defaultProperties(), diagnostics
    )
    let layout = computeLayout(ui.tree, styles, size(100, 30))
    let commands = buildPaintCommands(ui.tree, styles, layout)

    check not diagnostics.hasErrors
    check layout.boxes.filterIt(it.node == second.id)[0].rect.x == 0
    check layout.boxes.filterIt(it.node == first.id)[0].rect.x == 20
    check commands.len == 2
    check commands[0].color == rgb(0, 0, 1)
    check commands[1].color == rgb(1, 0, 0)

  test "moving a sibling preserves handles and invalidates its parent":
    let ui = initUiRoot()
    let host = ui.box()
    let first = ui.box(parent = some(host))
    let second = ui.box(parent = some(host))
    let third = ui.box(parent = some(host))
    let otherHost = ui.box()
    let outsider = ui.box(parent = some(otherHost))
    first.setFocusable()
    second.setFocusable()
    third.setFocusable()
    discard ui.consumeInvalidation()

    check ui.moveChildForDrop(host.id, first.id, third.id, disAfter)
    check ui.tree.nodes[host.id.nodeIndex].children ==
      @[second.id, third.id, first.id]
    check ui.focusTargets(host.id) == @[second.id, third.id, first.id]
    check ui.tree.isValid(first.id)
    let changed = ui.consumeInvalidation()
    check changed.domains == {ddLayout, ddPaint, ddHit}
    check changed.roots == @[host.id]

    check not ui.moveChildForDrop(host.id, first.id, third.id, disAfter)
    check ui.consumeInvalidation().domains == {}
    check not ui.moveChildForDrop(host.id, first.id, outsider.id, disBefore)
    check not ui.moveChildForDrop(host.id, first.id, first.id, disBefore)
    check ui.consumeInvalidation().domains == {}

    check ui.moveChildForDrop(host.id, first.id, second.id, disBefore)
    check ui.tree.nodes[host.id.nodeIndex].children ==
      @[first.id, second.id, third.id]

  test "a negotiated pointer drop can commit the indicated position":
    let ui = initUiRoot()
    let host = ui.box()
    let source = ui.box(parent = some(host))
    let target = ui.box(parent = some(host))
    source.setFocusable()
    target.setFocusable()
    let indicator = initDropInsertionIndicator(
      target.id, rect(70, 0, 40, 30), rgb(0, 0, 1)
    )
    let regions = @[
      HitRegion(node: source.id, rect: rect(0, 0, 40, 30), zIndex: 1),
      HitRegion(node: target.id, rect: rect(70, 0, 40, 30), zIndex: 1)
    ]
    var interaction = initInteractionState()
    discard interaction.processInput(
      ui.tree, regions, pointerDownEvent(vec2(10, 10))
    )
    check interaction.setDragOperations(source.id, {dgoMove})
    discard interaction.processInput(
      ui.tree, regions, pointerMoveEvent(vec2(80, 20))
    )
    check interaction.acceptDropOperation(target.id, dgoMove)
    check indicator.dropInsertionSide(vec2(80, 20)) == some(disAfter)

    let released = interaction.processInput(
      ui.tree, regions, pointerUpEvent(vec2(80, 20))
    )
    check released.anyIt(it.event.kind == iekDrop and
      it.dropOperation == some(dgoMove))
    check interaction.dropOperation.isNone
    let side = indicator.dropInsertionSide(vec2(80, 20))
    check side.isSome
    check ui.moveChildForDrop(host.id, source.id, target.id, side.get)
    check ui.tree.nodes[host.id.nodeIndex].children ==
      @[target.id, source.id]
    check ui.focusTargets(host.id) == @[target.id, source.id]

  test "keyboard steps keep the same focused node and stop at list edges":
    let ui = initUiRoot()
    let host = ui.box()
    let first = ui.box(parent = some(host))
    let middle = ui.box(parent = some(host))
    let last = ui.box(parent = some(host))
    let otherHost = ui.box()
    let outsider = ui.box(parent = some(otherHost))
    first.setFocusable()
    middle.setFocusable()
    last.setFocusable()
    var interaction = initInteractionState()
    check ui.setFocus(interaction, some(middle.id))
    discard ui.consumeInvalidation()

    check ui.moveChildByStep(host.id, middle.id, -1)
    check ui.tree.nodes[host.id.nodeIndex].children ==
      @[middle.id, first.id, last.id]
    check ui.focusTargets(host.id) == @[middle.id, first.id, last.id]
    check interaction.focusedTarget == some(middle.id)
    check ui.consumeInvalidation().roots == @[host.id]

    check not ui.moveChildByStep(host.id, middle.id, -1)
    check not ui.moveChildByStep(host.id, middle.id, 0)
    check not ui.moveChildByStep(host.id, middle.id, 2)
    check not ui.moveChildByStep(host.id, outsider.id, 1)
    check ui.consumeInvalidation().domains == {}

    check ui.moveChildByStep(host.id, middle.id, 1)
    check ui.moveChildByStep(host.id, middle.id, 1)
    check ui.tree.nodes[host.id.nodeIndex].children ==
      @[first.id, last.id, middle.id]
    check not ui.moveChildByStep(host.id, middle.id, 1)
    check interaction.focusedTarget == some(middle.id)
