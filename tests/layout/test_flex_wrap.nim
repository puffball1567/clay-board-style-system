import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc boxFor(layout: LayoutResult; node: NodeId): LayoutBox =
  for item in layout.boxes:
    if item.node == node:
      return item

proc overflowFor(
    layout: LayoutResult;
    node: NodeId
): Option[LayoutOverflowMetrics] =
  for item in layout.overflowMetrics:
    if item.node == node:
      return some(item)
  none(LayoutOverflowMetrics)

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

suite "multi-line flex layout":
  test "row wrap forms lines with independent main and cross gaps":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let third = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(100)),
        decl("flex-direction", keyword("row")),
        decl("flex-wrap", keyword("wrap")),
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
    check resolved.layout.boxFor(first).rect == rect(0, 0, 40, 20)
    check resolved.layout.boxFor(second).rect == rect(50, 0, 40, 20)
    check resolved.layout.boxFor(third).rect == rect(0, 26, 40, 20)

  test "nowrap keeps overflowing items on one line":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let third = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row")),
        decl("flex-wrap", keyword("nowrap")),
        decl("column-gap", px(10))
      ]),
      rule(group("item"), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("flex-shrink", number(0))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect.x == 0
    check resolved.layout.boxFor(second).rect.x == 50
    check resolved.layout.boxFor(third).rect.x == 100

  test "a maximum main size constrains wrapping and grows an auto cross size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let third = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("max-width", px(100)),
        decl("flex-direction", keyword("row")),
        decl("flex-wrap", keyword("wrap")),
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
    check resolved.layout.boxFor(root).rect == rect(0, 0, 90, 46)
    check resolved.layout.boxFor(first).rect == rect(0, 0, 40, 20)
    check resolved.layout.boxFor(second).rect == rect(50, 0, 40, 20)
    check resolved.layout.boxFor(third).rect == rect(0, 26, 40, 20)

  test "column wrap creates new columns":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let third = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(70)),
        decl("flex-flow", keyword("column wrap")),
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
    check resolved.layout.boxFor(first).rect == rect(0, 0, 20, 30)
    check resolved.layout.boxFor(second).rect == rect(0, 40, 20, 30)
    check resolved.layout.boxFor(third).rect == rect(27, 0, 20, 30)

  test "wrap-reverse mirrors flex lines across the cross axis":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let third = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(100)),
        decl("flex-direction", keyword("row")),
        decl("flex-wrap", keyword("wrap-reverse")),
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
    check resolved.layout.boxFor(first).rect.y == 80
    check resolved.layout.boxFor(second).rect.y == 80
    check resolved.layout.boxFor(third).rect.y == 54

  test "align-content centers multiple lines but does not move a single line":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let third = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(80)),
        decl("height", px(100)),
        decl("flex-direction", keyword("row")),
        decl("flex-wrap", keyword("wrap")),
        decl("align-content", keyword("center")),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("flex-shrink", number(0))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect.y == 30
    check resolved.layout.boxFor(second).rect.y == 30
    check resolved.layout.boxFor(third).rect.y == 50

    var singleTree = initTree()
    let singleRoot = singleTree.addBox(id = "root")
    let single = singleTree.addBox(parent = some(singleRoot), id = "single")
    let singleResolved = singleTree.resolveLayout([
      rule(target(singleRoot), [
        decl("width", px(80)),
        decl("height", px(100)),
        decl("flex-direction", keyword("row")),
        decl("flex-wrap", keyword("wrap")),
        decl("align-content", keyword("center")),
        decl("align-items", keyword("start"))
      ]),
      rule(target(single), [decl("width", px(40)), decl("height", px(20))])
    ])
    check singleResolved.layout.boxFor(single).rect.y == 0

  test "align-content space-between distributes free cross space":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(50)),
        decl("height", px(100)),
        decl("flex-direction", keyword("row")),
        decl("flex-wrap", keyword("wrap")),
        decl("align-content", keyword("space-between")),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("flex-shrink", number(0))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect.y == 0
    check resolved.layout.boxFor(second).rect.y == 80

  test "align-content supports space-around space-evenly and stretch":
    for (alignment, expectedFirst, expectedSecond) in [
      ("space-around", 15.0'f32, 65.0'f32),
      ("space-evenly", 20.0'f32, 60.0'f32),
      ("stretch", 0.0'f32, 50.0'f32)
    ]:
      var tree = initTree()
      let root = tree.addBox(id = "root")
      let first = tree.addBox(parent = some(root), groups = ["item"])
      let second = tree.addBox(parent = some(root), groups = ["item"])
      let resolved = tree.resolveLayout([
        rule(target(root), [
          decl("width", px(50)),
          decl("height", px(100)),
          decl("flex-direction", keyword("row")),
          decl("flex-wrap", keyword("wrap")),
          decl("align-content", keyword(alignment)),
          decl("align-items", keyword("start"))
        ]),
        rule(group("item"), [
          decl("width", px(40)),
          decl("height", px(20)),
          decl("flex-shrink", number(0))
        ])
      ])

      check not resolved.diagnostics.hasErrors
      check resolved.layout.boxFor(first).rect.y == expectedFirst
      check resolved.layout.boxFor(second).rect.y == expectedSecond

  test "justify-content distributes items with space-around and space-evenly":
    for (alignment, expectedFirst, expectedSecond) in [
      ("space-around", 15.0'f32, 65.0'f32),
      ("space-evenly", 20.0'f32, 60.0'f32)
    ]:
      var tree = initTree()
      let root = tree.addBox(id = "root")
      let first = tree.addBox(parent = some(root), groups = ["item"])
      let second = tree.addBox(parent = some(root), groups = ["item"])
      let resolved = tree.resolveLayout([
        rule(target(root), [
          decl("width", px(100)),
          decl("height", px(30)),
          decl("flex-direction", keyword("row")),
          decl("justify-content", keyword(alignment))
        ]),
        rule(group("item"), [decl("width", px(20)), decl("height", px(20))])
      ])

      check not resolved.diagnostics.hasErrors
      check resolved.layout.boxFor(first).rect.x == expectedFirst
      check resolved.layout.boxFor(second).rect.x == expectedSecond

  test "flex-grow is resolved independently for each line":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let third = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(60)),
        decl("flex-direction", keyword("row")),
        decl("flex-wrap", keyword("wrap")),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("flex-grow", number(1)),
        decl("flex-shrink", number(0))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect == rect(0, 0, 50, 20)
    check resolved.layout.boxFor(second).rect == rect(50, 0, 50, 20)
    check resolved.layout.boxFor(third).rect == rect(0, 20, 100, 20)

  test "flex-grow freezes at max-size and redistributes remaining space":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), id = "first")
    let second = tree.addBox(parent = some(root), id = "second")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(target(first), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("max-width", px(45)),
        decl("flex-grow", number(1))
      ]),
      rule(target(second), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("flex-grow", number(1))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect.w == 45
    check resolved.layout.boxFor(second).rect == rect(45, 0, 55, 20)

  test "nested flex-basis uses the flex item padding rather than a descendant":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let item = tree.addBox(parent = some(root), id = "item")
    let descendant = tree.addBox(parent = some(item), id = "descendant")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(300)),
        decl("height", px(100)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(target(item), [
        decl("flex-basis", px(100)),
        decl("padding", px(10)),
        decl("box-sizing", keyword("content-box")),
        decl("flex-shrink", number(0))
      ]),
      rule(target(descendant), [
        decl("width", px(10)),
        decl("height", px(10)),
        decl("padding", px(30))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(item).rect.w == 120

  test "wrapped overflow metrics include all line cross sizes and gaps":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    for _ in 0 ..< 3:
      discard tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row")),
        decl("flex-wrap", keyword("wrap")),
        decl("row-gap", px(6)),
        decl("overflow-y", keyword("auto")),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("flex-shrink", number(0))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    let metrics = resolved.layout.overflowFor(root)
    check metrics.isSome
    check metrics.get.viewportSize == size(100, 30)
    check metrics.get.contentSize == size(80, 46)

  test "display-none and absolute children do not create flex lines":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let hidden = tree.addBox(parent = some(root), id = "hidden")
    let overlay = tree.addBox(parent = some(root), id = "overlay")
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(60)),
        decl("flex-direction", keyword("row")),
        decl("flex-wrap", keyword("wrap")),
        decl("column-gap", px(10))
      ]),
      rule(group("item"), [decl("width", px(40)), decl("height", px(20))]),
      rule(target(hidden), [decl("display", keyword("none"))]),
      rule(target(overlay), [
        decl("position", keyword("absolute")),
        decl("width", px(100)),
        decl("height", px(40))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect.x == 0
    check resolved.layout.boxFor(second).rect.x == 50
    check resolved.layout.boxFor(second).rect.y == 0
