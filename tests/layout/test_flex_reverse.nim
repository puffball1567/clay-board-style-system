import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc boxFor(layout: LayoutResult; node: NodeId): LayoutBox =
  for item in layout.boxes:
    if item.node == node:
      return item

proc boxOrder(layout: LayoutResult; nodes: openArray[NodeId]): seq[NodeId] =
  for item in layout.boxes:
    if item.node in nodes:
      result.add item.node

proc resolveLayout(
    tree: Tree;
    rules: openArray[StyleRule];
    viewport = size(400, 240)
): tuple[styles: ResolvedTree, layout: LayoutResult, diagnostics: Diagnostics] =
  result.styles = resolveTreeStyles(
    tree,
    [styleSheet(rules)],
    defaultProperties(),
    result.diagnostics
  )
  result.layout = computeLayout(tree, result.styles, viewport)

suite "reverse main-axis flex layout":
  test "row-reverse places source items from right to left":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let third = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(120)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row-reverse")),
        decl("column-gap", px(10)),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(20)),
        decl("height", px(10)),
        decl("flex-shrink", number(0))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect == rect(100, 0, 20, 10)
    check resolved.layout.boxFor(second).rect == rect(70, 0, 20, 10)
    check resolved.layout.boxFor(third).rect == rect(40, 0, 20, 10)
    let regions = buildHitRegions(tree, resolved.layout, resolved.styles)
    check hitTest(regions, vec2(110, 5)).get.node == first
    check hitTest(regions, vec2(80, 5)).get.node == second

  test "reverse placement shifts a flex item's retained subtree once":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let item = tree.addBox(parent = some(root), id = "item")
    let child = tree.addBox(parent = some(item), id = "child")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row-reverse")),
        decl("align-items", keyword("start"))
      ]),
      rule(target(item), [decl("width", px(20)), decl("height", px(10))]),
      rule(target(child), [decl("width", px(5)), decl("height", px(5))])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(item).rect == rect(80, 0, 20, 10)
    check resolved.layout.boxFor(child).rect == rect(80, 0, 5, 5)

  test "row-reverse maps justify end to the physical left":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row-reverse")),
        decl("justify-content", keyword("end")),
        decl("column-gap", px(10)),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(20)),
        decl("height", px(10)),
        decl("flex-shrink", number(0))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect.x == 30
    check resolved.layout.boxFor(second).rect.x == 0

  test "reverse placement preserves physical margins":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row-reverse")),
        decl("column-gap", px(10)),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(20)),
        decl("height", px(10)),
        decl("margin-left", px(3)),
        decl("margin-right", px(7)),
        decl("flex-shrink", number(0))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect.x == 73
    check resolved.layout.boxFor(second).rect.x == 33

  test "column-reverse places source items from bottom to top":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let third = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(30)),
        decl("height", px(100)),
        decl("flex-direction", keyword("column-reverse")),
        decl("row-gap", px(10)),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(10)),
        decl("height", px(20)),
        decl("flex-shrink", number(0))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect == rect(0, 80, 10, 20)
    check resolved.layout.boxFor(second).rect == rect(0, 50, 10, 20)
    check resolved.layout.boxFor(third).rect == rect(0, 20, 10, 20)

  test "row-reverse wraps the same source items into each line":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let third = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(60)),
        decl("flex-flow", keyword("row-reverse wrap")),
        decl("column-gap", px(10)),
        decl("row-gap", px(6)),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("flex-shrink", number(0))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect == rect(60, 0, 40, 20)
    check resolved.layout.boxFor(second).rect == rect(10, 0, 40, 20)
    check resolved.layout.boxFor(third).rect == rect(60, 26, 40, 20)

  test "main and cross reversal compose independently":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let third = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(100)),
        decl("flex-flow", keyword("row-reverse wrap-reverse")),
        decl("column-gap", px(10)),
        decl("row-gap", px(6)),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("flex-shrink", number(0))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect == rect(60, 80, 40, 20)
    check resolved.layout.boxFor(second).rect == rect(10, 80, 40, 20)
    check resolved.layout.boxFor(third).rect == rect(60, 54, 40, 20)

  test "column-reverse wrapping creates columns without reversing line membership":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let third = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(80)),
        decl("height", px(70)),
        decl("flex-flow", keyword("column-reverse wrap")),
        decl("row-gap", px(10)),
        decl("column-gap", px(7)),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(20)),
        decl("height", px(30)),
        decl("flex-shrink", number(0))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect == rect(0, 40, 20, 30)
    check resolved.layout.boxFor(second).rect == rect(0, 0, 20, 30)
    check resolved.layout.boxFor(third).rect == rect(27, 40, 20, 30)

  test "order changes visual ordering before reverse flow without changing paint sequence again":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), id = "first")
    let second = tree.addBox(parent = some(root), id = "second")
    let third = tree.addBox(parent = some(root), id = "third")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row-reverse")),
        decl("align-items", keyword("start"))
      ]),
      rule(target(first), [
        decl("width", px(20)), decl("height", px(10)), decl("order", number(2))
      ]),
      rule(target(second), [decl("width", px(20)), decl("height", px(10))]),
      rule(target(third), [
        decl("width", px(20)), decl("height", px(10)), decl("order", number(1))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(second).rect.x == 80
    check resolved.layout.boxFor(third).rect.x == 60
    check resolved.layout.boxFor(first).rect.x == 40
    check resolved.layout.boxOrder([first, second, third]) == @[second, third, first]

  test "reverse directions preserve intrinsic axis sizing":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addBox(parent = some(root), groups = ["item"])
    discard tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("flex-direction", keyword("row-reverse")),
        decl("column-gap", px(10))
      ]),
      rule(group("item"), [decl("width", px(20)), decl("height", px(12))])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(root).rect == rect(0, 0, 50, 12)
