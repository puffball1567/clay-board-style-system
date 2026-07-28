import std/[options, sequtils, unittest]

import clay_box_style_system
import clay_box_style_system/generated/default_properties

suite "hit testing":
  test "returns the topmost node containing the point":
    var tree = initTree()
    let root = tree.addBox(id = "toolbar")
    let save = tree.addBox(parent = some(root), id = "button")
    discard tree.addText(save, "Save")

    let sheet = styleSheet([
      rule(id("toolbar"), [
        decl("width", px(300)),
        decl("padding", px(8)),
        decl("background-color", colorValue(rgb(0.12, 0.14, 0.16)))
      ]),
      rule(id("button"), [
        decl("padding", px(6)),
        decl("background-color", colorValue(rgb(0.22, 0.25, 0.29))),
        decl("font-size", px(14))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(300, 80))
    let regions = buildHitRegions(layout)
    let hit = hitTest(regions, vec2(10, 10))

    check not diagnostics.hasErrors
    check hit.isSome
    check hit.get.node == save

  test "z-index is preferred over layout order":
    var layout: LayoutResult
    let back = NodeId(0)
    let front = NodeId(1)
    layout.boxes = @[
      LayoutBox(node: front, rect: rect(0, 0, 20, 20), zIndex: 0),
      LayoutBox(node: back, rect: rect(0, 0, 20, 20), zIndex: 5)
    ]

    let regions = buildHitRegions(layout)
    let hit = hitTest(regions, vec2(10, 10))

    check hit.isSome
    check hit.get.node == back

  test "explicit z-index overlay is preferred over smaller underlying regions":
    var layout: LayoutResult
    let under = NodeId(0)
    let overlay = NodeId(1)
    layout.boxes = @[
      LayoutBox(node: under, rect: rect(8, 8, 20, 20), zIndex: 0),
      LayoutBox(node: overlay, rect: rect(0, 0, 80, 80), zIndex: 10)
    ]

    let regions = buildHitRegions(layout)
    let hit = hitTest(regions, vec2(10, 10))

    check hit.isSome
    check hit.get.node == overlay

  test "visibility hidden removes styled hit regions":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addBox(parent = some(root), id = "hidden")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(100)),
        decl("height", px(40))
      ]),
      rule(id("hidden"), [
        decl("width", px(80)),
        decl("height", px(30)),
        decl("visibility", keyword("hidden"))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(100, 40))
    let regions = buildHitRegions(layout, styles)
    let hit = hitTest(regions, vec2(10, 10))

    check hit.isSome
    check hit.get.node == root

  test "pointer-events none removes styled hit regions":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addBox(parent = some(root), id = "overlay")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(100)),
        decl("height", px(40))
      ]),
      rule(id("overlay"), [
        decl("width", px(100)),
        decl("height", px(40)),
        decl("pointer-events", keyword("none"))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(100, 40))
    let regions = buildHitRegions(layout, styles)
    let hit = hitTest(regions, vec2(10, 10))

    check hit.isSome
    check hit.get.node == root

  test "content-visibility hidden removes descendant hit regions":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let hiddenParent = tree.addBox(parent = some(root), id = "hidden-parent")
    discard tree.addBox(parent = some(hiddenParent), id = "child")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(100)),
        decl("height", px(40))
      ]),
      rule(id("hidden-parent"), [
        decl("width", px(80)),
        decl("height", px(30)),
        decl("content-visibility", keyword("hidden"))
      ]),
      rule(id("child"), [
        decl("width", px(60)),
        decl("height", px(20))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(100, 40))
    let regions = buildHitRegions(tree, layout, styles)
    let hit = hitTest(regions, vec2(10, 10))

    check hit.isSome
    check hit.get.node == hiddenParent

  test "cursorAt reads inherited cursor from styled hit regions":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let button = tree.addBox(parent = some(root), id = "button")
    discard tree.addText(button, "Run", id = "label")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(100)),
        decl("height", px(40))
      ]),
      rule(id("button"), [
        decl("width", px(80)),
        decl("height", px(30)),
        decl("cursor", keyword("pointer"))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(100, 40))
    let regions = buildHitRegions(tree, layout, styles)

    check cursorAt(regions, vec2(10, 10)) == ckPointer
    check cursorAt(regions, vec2(95, 35)) == ckDefault

  test "subtree hit rebuild matches its span in a full scrolled build":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let scrollBox = tree.addBox(parent = some(root), id = "scroll")
    let first = tree.addBox(parent = some(scrollBox), id = "first")
    let second = tree.addBox(parent = some(scrollBox), id = "second")
    discard tree.addBox(parent = some(root), id = "sibling")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(160)),
        decl("height", px(100)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(id("scroll"), [
        decl("width", px(80)),
        decl("height", px(40)),
        decl("overflow-y", keyword("auto"))
      ]),
      rule(id("first"), [
        decl("height", px(30)),
        decl("min-height", px(30)),
        decl("cursor", keyword("pointer"))
      ]),
      rule(id("second"), [
        decl("height", px(30)),
        decl("min-height", px(30))
      ]),
      rule(id("sibling"), [
        decl("width", px(60)),
        decl("height", px(40))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree, [sheet], defaultProperties(), diagnostics
    )
    check not diagnostics.hasErrors
    let layout = computeLayout(tree, styles, size(160, 100))
    var scroll = initScrollState()
    scroll.syncScrollState(tree, styles, layout)
    check scroll.scrollBy(scrollBox, vec2(0, 12))

    let full = buildHitRegions(tree, layout, styles, scroll)
    let subtree = buildHitRegionsForSubtree(
      tree, layout, styles, scrollBox, scroll
    )
    let subtreeIds = [scrollBox, first, second]
    let expected = full.filterIt(it.node in subtreeIds)

    check subtree == expected
