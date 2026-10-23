import std/[options, sequtils, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

suite "drag visual states":
  test "accepted drop style tracks each target decision":
    let ui = initUiRoot()
    let root = ui.box()
    let source = ui.box(parent = some(root))
    let target = ui.box(parent = some(root))
    target.applyStateStyle({esDropAccepted}, uiStyle([
      decl("background-color", colorValue(rgb(0.2, 0.7, 0.3)))
    ]))
    let regions = @[
      HitRegion(node: source.id, rect: rect(0, 0, 40, 30), zIndex: 1),
      HitRegion(node: target.id, rect: rect(70, 0, 40, 30), zIndex: 1)
    ]
    var interaction = initInteractionState()
    var shouldAccept = true
    target.onDragOver = proc(event: DispatchResult): EventOutcome =
      if shouldAccept:
        check interaction.acceptDropOperation(target.id, dgoCopy)
      handledEvent()
    discard ui.consumeInvalidation()

    discard ui.handleEvents(interaction, interaction.processInput(
      ui.tree, regions, pointerDownEvent(vec2(10, 10))
    ))
    check interaction.setDragOperations(source.id, {dgoCopy})
    discard ui.handleEvents(interaction, interaction.processInput(
      ui.tree, regions, pointerMoveEvent(vec2(80, 10))
    ))
    check esDropAccepted in ui.tree.nodes[target.id.nodeIndex].states
    check ddStyle in ui.consumeInvalidation().domains
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      ui.tree, ui.styleSheets(), defaultProperties(), diagnostics
    )
    check not diagnostics.hasErrors
    check styles.styles[target.id.nodeIndex].box.backgroundColor ==
      some(rgb(0.2, 0.7, 0.3))

    discard ui.handleEvents(interaction, interaction.processInput(
      ui.tree, regions, pointerMoveEvent(vec2(81, 10))
    ))
    check esDropAccepted in ui.tree.nodes[target.id.nodeIndex].states
    check ddStyle notin ui.consumeInvalidation().domains

    shouldAccept = false
    discard ui.handleEvents(interaction, interaction.processInput(
      ui.tree, regions, pointerMoveEvent(vec2(82, 10))
    ))
    check esDragOver in ui.tree.nodes[target.id.nodeIndex].states
    check esDropAccepted notin ui.tree.nodes[target.id.nodeIndex].states
    check ddStyle in ui.consumeInvalidation().domains

    shouldAccept = true
    discard ui.handleEvents(interaction, interaction.processInput(
      ui.tree, regions, pointerMoveEvent(vec2(83, 10))
    ))
    check esDropAccepted in ui.tree.nodes[target.id.nodeIndex].states
    discard ui.consumeInvalidation()
    discard ui.handleEvents(interaction, interaction.processInput(
      ui.tree, regions, pointerUpEvent(vec2(83, 10))
    ))
    check esDropAccepted notin ui.tree.nodes[target.id.nodeIndex].states
    check esDragOver notin ui.tree.nodes[target.id.nodeIndex].states
    check ddStyle in ui.consumeInvalidation().domains

  test "pointer drag styles clear after an unaccepted release":
    let ui = initUiRoot()
    let root = ui.box()
    let source = ui.box(parent = some(root))
    let target = ui.box(parent = some(root))
    source.applyStateStyle({esDragging}, uiStyle([
      decl("background-color", colorValue(rgb(0.8, 0.2, 0.1)))
    ]))
    target.applyStateStyle({esDragOver}, uiStyle([
      decl("background-color", colorValue(rgb(0.1, 0.4, 0.8)))
    ]))
    discard ui.consumeInvalidation()
    let regions = @[
      HitRegion(node: source.id, rect: rect(0, 0, 40, 30), zIndex: 1),
      HitRegion(node: target.id, rect: rect(70, 0, 40, 30), zIndex: 1)
    ]
    var interaction = initInteractionState()

    discard ui.handleEvents(interaction.processInput(
      ui.tree, regions, pointerDownEvent(vec2(10, 10))
    ))
    check interaction.setDragOperations(source.id, {dgoCopy})
    discard ui.handleEvents(interaction.processInput(
      ui.tree, regions, pointerMoveEvent(vec2(80, 10))
    ))
    check esDragging in ui.tree.nodes[source.id.nodeIndex].states
    check esDragOver in ui.tree.nodes[target.id.nodeIndex].states
    check ddStyle in ui.consumeInvalidation().domains

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      ui.tree, ui.styleSheets(), defaultProperties(), diagnostics
    )
    check not diagnostics.hasErrors
    check styles.styles[source.id.nodeIndex].box.backgroundColor ==
      some(rgb(0.8, 0.2, 0.1))
    check styles.styles[target.id.nodeIndex].box.backgroundColor ==
      some(rgb(0.1, 0.4, 0.8))

    discard ui.handleEvents(interaction.processInput(
      ui.tree, regions, pointerMoveEvent(vec2(81, 10))
    ))
    check ddStyle notin ui.consumeInvalidation().domains
    discard ui.handleEvents(interaction.processInput(
      ui.tree, regions, pointerMoveEvent(vec2(150, 10))
    ))
    check esDragOver notin ui.tree.nodes[target.id.nodeIndex].states
    discard ui.consumeInvalidation()
    discard ui.handleEvents(interaction.processInput(
      ui.tree, regions, pointerMoveEvent(vec2(80, 10))
    ))
    check esDragOver in ui.tree.nodes[target.id.nodeIndex].states
    discard ui.consumeInvalidation()

    let released = interaction.processInput(
      ui.tree, regions, pointerUpEvent(vec2(80, 10))
    )
    check released.anyIt(it.event.kind == iekDragEnd)
    check released.allIt(it.event.kind != iekDrop)
    discard ui.handleEvents(released)
    check esDragging notin ui.tree.nodes[source.id.nodeIndex].states
    check esDragOver notin ui.tree.nodes[target.id.nodeIndex].states
    check ddStyle in ui.consumeInvalidation().domains
