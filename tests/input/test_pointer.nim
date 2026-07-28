import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

suite "pointer state":
  test "updateHover sets hover on the hit node":
    var tree = initTree()
    let root = tree.addBox(id = "toolbar")
    let button = tree.addBox(parent = some(root), id = "button")
    discard tree.addText(button, "Save")

    let sheet = styleSheet([
      rule(id("toolbar"), [
        decl("width", px(300)),
        decl("padding", px(8))
      ]),
      rule(id("button"), [
        decl("padding", px(6)),
        decl("font-size", px(14))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(300, 80))
    let regions = buildHitRegions(layout)
    let hovered = tree.updateHover(regions, vec2(10, 10))

    check hovered == some(button)
    check esHover in tree.nodes[button.nodeIndex].states
    check esHover notin tree.nodes[root.nodeIndex].states
