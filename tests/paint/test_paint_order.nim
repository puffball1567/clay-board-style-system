import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

suite "paint ordering":
  test "z-index affects paint command order":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addBox(parent = some(root), id = "high")
    discard tree.addBox(parent = some(root), id = "low")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(100)),
        decl("height", px(60))
      ]),
      rule(id("high"), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("z-index", number(10)),
        decl("background-color", colorValue(rgb(1, 0, 0)))
      ]),
      rule(id("low"), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("background-color", colorValue(rgb(0, 0, 1)))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(100, 60))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 2
    check commands[0].kind == pcFillRect
    check commands[0].color == rgb(0, 0, 1)
    check commands[1].kind == pcFillRect
    check commands[1].color == rgb(1, 0, 0)

  test "default paint order remains node creation order when child storage is reordered":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), id = "first")
    let second = tree.addBox(parent = some(root), id = "second")
    tree.nodes[root.nodeIndex].children = @[second, first]

    let sheet = styleSheet([
      rule(id("root"), [decl("width", px(100)), decl("height", px(60))]),
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
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(100, 60))
    let commands = buildPaintCommands(tree, styles, layout)

    check not diagnostics.hasErrors
    check commands.len == 2
    check commands[0].color == rgb(1, 0, 0)
    check commands[1].color == rgb(0, 0, 1)

  test "z-index subtree paints above later sibling content":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let layer = tree.addBox(parent = some(root), id = "layer")
    discard tree.addBox(parent = some(layer), id = "popup")
    discard tree.addBox(parent = some(root), id = "later")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(120)),
        decl("height", px(80))
      ]),
      rule(id("layer"), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("z-index", number(10))
      ]),
      rule(id("popup"), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("background-color", colorValue(rgb(1, 0, 0)))
      ]),
      rule(id("later"), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("background-color", colorValue(rgb(0, 0, 1)))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(120, 80))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 2
    check commands[0].kind == pcFillRect
    check commands[0].color == rgb(0, 0, 1)
    check commands[1].kind == pcFillRect
    check commands[1].color == rgb(1, 0, 0)

  test "retained subtree paint includes positive z-index descendants":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let control = tree.addBox(parent = some(root), id = "control")
    let content = tree.addBox(parent = some(control), id = "content")
    let overlay = tree.addBox(parent = some(control), id = "overlay")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(100)),
        decl("height", px(60))
      ]),
      rule(id("control"), [
        decl("width", px(80)),
        decl("height", px(40))
      ]),
      rule(id("content"), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("background-color", colorValue(rgb(0, 0, 1)))
      ]),
      rule(id("overlay"), [
        decl("position", keyword("absolute")),
        decl("width", px(8)),
        decl("height", px(24)),
        decl("z-index", number(10)),
        decl("background-color", colorValue(rgb(1, 0, 0)))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree, [sheet], defaultProperties(), diagnostics
    )
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(100, 60))
    let commands = buildPaintCommandsForSubtree(
      tree, styles, layout, control
    )

    check commands.len == 2
    check commands[0].owner == some(content)
    check commands[0].color == rgb(0, 0, 1)
    check commands[1].owner == some(overlay)
    check commands[1].color == rgb(1, 0, 0)

  test "opacity is applied to descendants":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addBox(parent = some(root), id = "child")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("opacity", number(0.5))
      ]),
      rule(id("child"), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("background-color", colorValue(rgb(1, 0, 0)))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(100, 60))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 1
    check commands[0].kind == pcFillRect
    check commands[0].color == rgba(1, 0, 0, 0.5)

  test "visibility hidden suppresses paint":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addBox(parent = some(root), id = "child")

    let sheet = styleSheet([
      rule(id("child"), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("visibility", keyword("hidden")),
        decl("background-color", colorValue(rgb(1, 0, 0)))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(100, 60))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 0

  test "content-visibility hidden suppresses descendants but keeps box paint":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addBox(parent = some(root), id = "child")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(40)),
        decl("height", px(30)),
        decl("content-visibility", keyword("hidden")),
        decl("background-color", colorValue(rgb(0, 0, 1)))
      ]),
      rule(id("child"), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("background-color", colorValue(rgb(1, 0, 0)))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(100, 60))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 1
    check commands[0].kind == pcFillRect
    check commands[0].color == rgb(0, 0, 1)

  test "border-style none suppresses border paint":
    var tree = initTree()
    discard tree.addBox(id = "root")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("border-width", px(1)),
        decl("border-color", colorValue(rgb(1, 0, 0))),
        decl("border-style", keyword("none"))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(20, 20))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 0

  test "side-specific border paints only configured sides":
    var tree = initTree()
    discard tree.addBox(id = "root")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(20)),
        decl("height", px(12)),
        decl("border-right-width", px(3)),
        decl("border-right-color", colorValue(rgb(0, 1, 0)))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(20, 12))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 1
    check commands[0].kind == pcFillRect
    check commands[0].rect.x == 17
    check commands[0].rect.y == 0
    check commands[0].rect.w == 3
    check commands[0].rect.h == 12
    check commands[0].color == rgb(0, 1, 0)

  test "side-specific border style suppresses one configured side":
    var tree = initTree()
    discard tree.addBox(id = "root")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(20)),
        decl("height", px(12)),
        decl("border-width", px(2)),
        decl("border-color", colorValue(rgb(1, 0, 0))),
        decl("border-right-style", keyword("none"))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(20, 12))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 3
    check commands[0].kind == pcFillRect
    check commands[0].rect.y == 0
    check commands[1].kind == pcFillRect
    check commands[1].rect.y == 10
    check commands[2].kind == pcFillRect
    check commands[2].rect.x == 0

  test "outline emits a stroke command with offset":
    var tree = initTree()
    discard tree.addBox(id = "root")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(20)),
        decl("height", px(12)),
        decl("outline", borderValue(lineWeight = px(2), lineStyle = "solid", lineColor = rgb(1, 0, 0))),
        decl("outline-offset", px(3))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(20, 12))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 1
    check commands[0].kind == pcStrokeRect
    check commands[0].strokeRect.x == -3
    check commands[0].strokeRect.y == -3
    check commands[0].strokeRect.w == 26
    check commands[0].strokeRect.h == 18
    check commands[0].strokeWidth == 2
    check commands[0].strokeColor == rgb(1, 0, 0)

  test "box-shadow paints before background":
    var tree = initTree()
    discard tree.addBox(id = "root")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(20)),
        decl("height", px(12)),
        decl("background-color", colorValue(rgb(1, 1, 1))),
        decl("border-radius", px(4)),
        decl("box-shadow", shadowValue(
          offsetX = px(3),
          offsetY = px(5),
          blur = some(px(8)),
          spread = some(px(2)),
          shadowColor = some(rgba(0, 0, 0, 0.4))
        ))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(40, 30))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 2
    check commands[0].kind == pcBoxShadow
    check commands[0].shadowRect == rect(0, 0, 20, 12)
    check commands[0].shadowOffsetX == 3
    check commands[0].shadowOffsetY == 5
    check commands[0].shadowBlur == 8
    check commands[0].shadowSpread == 2
    check commands[0].shadowRadius == 4
    check commands[0].shadowColor == rgba(0, 0, 0, 0.4)
    check commands[1].kind == pcFillRect

  test "linear gradient background paints over background color":
    var tree = initTree()
    discard tree.addBox(id = "root")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(20)),
        decl("height", px(12)),
        decl("background-color", colorValue(rgb(0, 0, 0))),
        decl("background-image", linearGradient(
          90,
          colorStop(rgb(1, 0, 0), 0),
          colorStop(rgb(0, 0, 1), 100)
        ))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(40, 30))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 2
    check commands[0].kind == pcFillRect
    check commands[1].kind == pcFillLinearGradient
    check commands[1].gradientRect == rect(0, 0, 20, 12)
    check commands[1].gradient.angle == 90
    check commands[1].gradient.interpolationSpace == cisSrgb
    check commands[1].gradient.stops.len == 2

  test "gradient interpolation space reaches the paint command":
    var tree = initTree()
    discard tree.addBox(id = "root")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(20)),
        decl("height", px(12)),
        decl("background-image", linearGradientIn(
          cisOklab,
          90,
          colorStop(rgb(1, 0, 0), 0),
          colorStop(rgb(0, 0, 1), 100)
        ))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(40, 30))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 1
    check commands[0].kind == pcFillLinearGradient
    check commands[0].gradient.interpolationSpace == cisOklab

  test "authored and resolved gradient stops share one declaration":
    var tree = initTree()
    discard tree.addBox(id = "root")

    let foreground = rgb(0.18, 0.42, 0.76)
    let wideGamut = displayP3(0.92, 0.18, 0.08)
    let mixed = colorMix(
      oklch(0.72, 0.16, 42),
      35,
      rec2020(0.12, 0.66, 0.32),
      65,
      cisOklab
    )
    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(20)),
        decl("height", px(12)),
        decl("color", foreground),
        decl("background-image", linearGradientIn(
          cisSrgbLinear,
          90,
          colorStop(rgb(0.05, 0.08, 0.12), 0),
          colorStop(wideGamut, 33),
          colorStop(currentColor(), 66),
          colorStop(mixed, 100)
        ))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(40, 30))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 1
    check commands[0].kind == pcFillLinearGradient
    check commands[0].gradient.stops.len == 4
    check commands[0].gradient.stops[0].color == rgb(0.05, 0.08, 0.12)
    check commands[0].gradient.stops[1].color == wideGamut.resolveColor()
    check commands[0].gradient.stops[2].color == foreground
    check commands[0].gradient.stops[3].color == mixed.resolveColor(foreground)

  test "max-lines limits drawn text command":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addText(root, "One\nTwo\nThree", id = "label")

    let sheet = styleSheet([
      rule(id("label"), [
        decl("max-lines", keyword("2"))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(100, 80))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 1
    check commands[0].kind == pcDrawText
    check commands[0].text == "One\nTwo"

  test "text decoration emits a visible line":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addText(root, "Decorated", id = "label")

    let sheet = styleSheet([
      rule(id("label"), [
        decl("font-size", px(16)),
        decl("line-height", px(20)),
        decl("color", colorValue(rgb(0, 0, 0))),
        decl("text-decoration", keyword("underline")),
        decl("text-decoration-color", colorValue(rgb(1, 0, 0))),
        decl("text-decoration-thickness", px(2))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(120, 40))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 2
    check commands[0].kind == pcDrawText
    check commands[1].kind == pcFillRect
    check commands[1].color == rgb(1, 0, 0)
    check commands[1].rect.h == 2

  test "text shadow emits shadow text before foreground text":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addText(root, "Shadow", id = "label")

    let sheet = styleSheet([
      rule(id("label"), [
        decl("text-shadow", shadowValue(
          offsetX = px(2),
          offsetY = px(3),
          shadowColor = some(rgba(0, 0, 0, 0.5))
        )),
        decl("color", colorValue(rgb(1, 1, 1)))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(120, 40))
    let commands = buildPaintCommands(tree, styles, layout)

    check commands.len == 2
    check commands[0].kind == pcDrawText
    check commands[1].kind == pcDrawText
    check commands[0].position.x == commands[1].position.x + 2
    check commands[0].position.y == commands[1].position.y + 3
    check commands[0].textColor == rgba(0, 0, 0, 0.5)
    check commands[1].textColor == rgb(1, 1, 1)

  test "text render offset moves the raster without changing layout":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "horizontally scrolled text", id = "label")
    tree.nodes[label.nodeIndex].renderOffset = vec2(-24, 0)
    tree.nodes[label.nodeIndex].textRenderWidth = some(200.0'f32)

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(100)),
        decl("height", px(30)),
        decl("overflow", keyword("hidden"))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(100, 30))
    let commands = buildPaintCommands(tree, styles, layout)
    var textCommand = none(PaintCommand)
    for command in commands:
      if command.kind == pcDrawText:
        textCommand = some(command)
        break

    check textCommand.isSome
    check textCommand.get.position.x == -24
    check textCommand.get.textMaxWidth == some(200.0'f32)
