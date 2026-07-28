import std/[options, unittest]

import clay_box_style_system
import clay_box_style_system/generated/default_properties

suite "paint clipping":
  test "overflow hidden wraps descendant paint commands":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    discard tree.addText(child, "Child")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(120)),
        decl("height", px(50)),
        decl("overflow", keyword("hidden")),
        decl("background-color", colorValue(rgb(0, 0, 0)))
      ]),
      rule(id("child"), [
        decl("width", px(80)),
        decl("height", px(30)),
        decl("background-color", colorValue(rgb(1, 0, 0)))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(120, 50))
    let commands = buildPaintCommands(tree, styles, layout)

    var pushIndex = -1
    var childIndex = -1
    var textIndex = -1
    var popIndex = -1
    for index, command in commands:
      case command.kind
      of pcPushClip:
        pushIndex = index
      of pcFillRect:
        if command.color == rgb(1, 0, 0):
          childIndex = index
      of pcDrawText:
        textIndex = index
      of pcPopClip:
        popIndex = index
      else:
        discard

    check pushIndex >= 0
    check childIndex > pushIndex
    check textIndex > childIndex
    check popIndex > textIndex

  test "overflow hidden clips descendants inside padding":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let text = tree.addText(root, "overflow hidden clips long text")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(112)),
        decl("height", px(30)),
        decl("padding", px(6)),
        decl("overflow", keyword("hidden")),
        decl("background-color", colorValue(rgb(0, 0, 0)))
      ]),
      rule(target(text), [
        decl("width", px(210)),
        decl("font-size", px(12)),
        decl("white-space", keyword("nowrap"))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(112, 30))
    let commands = buildPaintCommands(tree, styles, layout)

    var clip = none(Rect)
    for command in commands:
      if command.kind == pcPushClip:
        clip = some(command.clipRect)
        break

    check clip == some(rect(6, 6, 100, 18))

  test "overflow-x hidden wraps descendant paint commands":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addBox(parent = some(root), id = "child")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(120)),
        decl("height", px(50)),
        decl("overflow-x", keyword("hidden"))
      ]),
      rule(id("child"), [
        decl("width", px(80)),
        decl("height", px(30)),
        decl("background-color", colorValue(rgb(1, 0, 0)))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(120, 50))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 3
    check commands[0].kind == pcPushClip
    check commands[1].kind == pcFillRect
    check commands[2].kind == pcPopClip

  test "clip-path inset wraps element and descendant paint commands":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addBox(parent = some(root), id = "child")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(120)),
        decl("height", px(60)),
        decl("clip-path", keyword("inset(4px 8px)")),
        decl("background-color", colorValue(rgb(0, 0, 0)))
      ]),
      rule(id("child"), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("background-color", colorValue(rgb(1, 0, 0)))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(120, 60))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 4
    check commands[0].kind == pcPushClip
    check commands[0].clipRect == rect(8, 4, 104, 52)
    check commands[1].kind == pcFillRect
    check commands[1].color == rgb(0, 0, 0)
    check commands[2].kind == pcFillRect
    check commands[2].color == rgb(1, 0, 0)
    check commands[3].kind == pcPopClip

  test "overflow-block clip wraps descendant paint commands":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addBox(parent = some(root), id = "child")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(120)),
        decl("height", px(50)),
        decl("overflow-block", keyword("clip"))
      ]),
      rule(id("child"), [
        decl("width", px(80)),
        decl("height", px(30)),
        decl("background-color", colorValue(rgb(1, 0, 0)))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(120, 50))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 3
    check commands[0].kind == pcPushClip
    check commands[1].kind == pcFillRect
    check commands[2].kind == pcPopClip
