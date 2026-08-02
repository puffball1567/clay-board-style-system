import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

suite "shared presentation coordinates":
  test "scroll clip opacity paint and hit testing agree":
    var tree = initTree()
    let viewport = tree.addBox(id = "viewport")
    let child = tree.addBox(parent = some(viewport), id = "child")
    let sheet = styleSheet([
      rule(id("viewport"), [
        decl("width", px(100)),
        decl("height", px(50)),
        decl("padding", px(10)),
        decl("flex-direction", keyword("column")),
        decl("overflow-y", keyword("auto")),
        decl("opacity", number(0.5))
      ]),
      rule(id("child"), [
        decl("width", px(80)),
        decl("height", px(80)),
        decl("min-height", px(80)),
        decl("background-color", rgb(1, 0, 0))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree, [sheet], defaultProperties(), diagnostics
    )
    let layout = computeLayout(tree, styles, size(100, 50))
    var scroll = initScrollState()
    scroll.syncScrollState(tree, styles, layout)
    check not diagnostics.hasErrors
    check scroll.setScrollOffset(viewport, vec2(0, 15))

    let presentation = presentationForNode(
      tree, layout, styles, child, scroll
    ).get
    check presentation.bounds == rect(10, -5, 80, 80)
    check presentation.clip == rect(10, 10, 80, 30)
    check presentation.opacity == 0.5

    let commands = buildPaintCommands(tree, styles, layout, scroll)
    var childFill = none(PaintCommand)
    for command in commands:
      if command.kind == pcFillRect and command.owner == some(child):
        childFill = some(command)
    check childFill.isSome
    check childFill.get.rect == presentation.bounds
    check childFill.get.color.a == presentation.opacity

    let regions = buildHitRegions(tree, layout, styles, scroll)
    let hit = hitTest(regions, vec2(15, 15))
    check hit.isSome
    check hit.get.node == child
    check hit.get.local == vec2(5, 20)
    let clippedHit = hitTest(regions, vec2(15, 5))
    check clippedHit.isSome
    check clippedHit.get.node == viewport
