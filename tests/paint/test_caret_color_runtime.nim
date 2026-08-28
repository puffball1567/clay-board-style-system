import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc caretFill(
    commands: openArray[PaintCommand];
    caret: NodeId
): Option[PaintCommand] =
  for command in commands:
    if command.kind == pcFillRect and command.owner == some(caret):
      return some(command)
  none(PaintCommand)

suite "caret color runtime":
  test "text controls mark generated caret nodes without public identifiers":
    let ui = initUiRoot()
    let input = ui.textInput()
    let area = ui.textArea()

    check ui.tree.nodes[input.caretNode.id.nodeIndex].generatedPart == gpkCaret
    check ui.tree.nodes[area.caretNode.id.nodeIndex].generatedPart == gpkCaret
    check input.caretNode.id != area.caretNode.id

  test "owner caret-color overrides the generated caret fallback at paint time":
    var tree = initTree()
    let owner = tree.addBox(id = "owner")
    let caret = tree.addBox(parent = some(owner), id = "internal-caret")
    tree.setGeneratedPart(caret, gpkCaret)

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([
        rule(id("owner"), [
          decl("width", px(80)),
          decl("height", px(30)),
          decl("caret-color", colorValue(rgb(0.9, 0.1, 0.2)))
        ]),
        rule(id("internal-caret"), [
          decl("width", px(2)),
          decl("height", px(16)),
          decl("background-color", colorValue(rgb(0.1, 0.2, 0.9)))
        ])
      ])],
      defaultProperties(),
      diagnostics
    )
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(80, 30))
    let command = buildPaintCommands(tree, styles, layout).caretFill(caret)

    check command.isSome
    check command.get.color == rgb(0.9, 0.1, 0.2)

  test "auto and ordinary boxes preserve their authored background colors":
    var tree = initTree()
    let owner = tree.addBox(id = "owner")
    let caret = tree.addBox(parent = some(owner), id = "caret")
    let ordinary = tree.addBox(parent = some(owner), id = "ordinary")
    tree.setGeneratedPart(caret, gpkCaret)

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([
        rule(id("owner"), [
          decl("width", px(80)),
          decl("height", px(40)),
          decl("caret-color", keyword("auto"))
        ]),
        rule(id("caret"), [
          decl("width", px(2)),
          decl("height", px(16)),
          decl("background-color", colorValue(rgb(0.2, 0.8, 0.4)))
        ]),
        rule(id("ordinary"), [
          decl("width", px(10)),
          decl("height", px(10)),
          decl("background-color", colorValue(rgb(0.8, 0.4, 0.2)))
        ])
      ])],
      defaultProperties(),
      diagnostics
    )
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(80, 40))
    let commands = buildPaintCommands(tree, styles, layout)
    let caretCommand = commands.caretFill(caret)
    let ordinaryCommand = commands.caretFill(ordinary)

    check caretCommand.isSome
    check caretCommand.get.color == rgb(0.2, 0.8, 0.4)
    check ordinaryCommand.isSome
    check ordinaryCommand.get.color == rgb(0.8, 0.4, 0.2)

  test "invalid generated-part writes are inert":
    var tree = initTree()
    let node = tree.addBox()
    let stale = node
    let removed = tree.disposeSubtree(node)

    tree.setGeneratedPart(stale, gpkCaret)

    check removed == @[node]
    check not tree.isValid(stale)

  test "caret color inherits through the control owner":
    var tree = initTree()
    let ancestor = tree.addBox(id = "ancestor")
    let owner = tree.addBox(parent = some(ancestor), id = "owner")
    let caret = tree.addBox(parent = some(owner), id = "caret")
    tree.setGeneratedPart(caret, gpkCaret)

    let inherited = rgb(0.18, 0.72, 0.91)
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([
        rule(id("ancestor"), [
          decl("width", px(80)),
          decl("height", px(30)),
          decl("caret-color", colorValue(inherited))
        ]),
        rule(id("owner"), [
          decl("width", px(80)),
          decl("height", px(30))
        ]),
        rule(id("caret"), [
          decl("width", px(2)),
          decl("height", px(16)),
          decl("background-color", colorValue(rgb(0.1, 0.2, 0.3)))
        ])
      ])],
      defaultProperties(),
      diagnostics
    )
    check not diagnostics.hasErrors
    check styles.styles[owner.nodeIndex].visual.caretColor == some(inherited)

    let layout = computeLayout(tree, styles, size(80, 30))
    let command = buildPaintCommands(tree, styles, layout).caretFill(caret)

    check command.isSome
    check command.get.color == inherited
