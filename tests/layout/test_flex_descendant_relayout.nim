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

proc measureOnlyEngine(measure: TextMeasureProc): TextEngine =
  TextEngine(
    measureText: measure,
    caretPosition: debugCaretPosition,
    hitTestText: debugHitText
  )

suite "flex item descendant relayout":
  test "row grow updates percentage descendants":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let firstChild = tree.addBox(parent = some(first), groups = ["fill"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let secondChild = tree.addBox(parent = some(second), groups = ["fill"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(50)),
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(40)),
        decl("height", px(30)),
        decl("flex-grow", number(1))
      ]),
      rule(group("fill"), [
        decl("width", percent(100)),
        decl("height", px(10))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect == rect(0, 0, 100, 30)
    check resolved.layout.boxFor(second).rect == rect(100, 0, 100, 30)
    check resolved.layout.boxFor(firstChild).rect == rect(0, 0, 100, 10)
    check resolved.layout.boxFor(secondChild).rect == rect(100, 0, 100, 10)

  test "row shrink updates percentage descendants":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let firstChild = tree.addBox(parent = some(first), groups = ["fill"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let secondChild = tree.addBox(parent = some(second), groups = ["fill"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(50)),
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(80)),
        decl("height", px(30)),
        decl("min-width", px(0)),
        decl("flex-shrink", number(1))
      ]),
      rule(group("fill"), [
        decl("width", percent(100)),
        decl("height", px(10))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect.w == 50
    check resolved.layout.boxFor(second).rect.w == 50
    check resolved.layout.boxFor(firstChild).rect.w == 50
    check resolved.layout.boxFor(secondChild).rect.w == 50

  test "column grow updates percentage descendants":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let firstChild = tree.addBox(parent = some(first), groups = ["fill"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let secondChild = tree.addBox(parent = some(second), groups = ["fill"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(80)),
        decl("height", px(200)),
        decl("flex-direction", keyword("column")),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(30)),
        decl("height", px(40)),
        decl("flex-grow", number(1))
      ]),
      rule(group("fill"), [
        decl("width", px(10)),
        decl("height", percent(100))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect == rect(0, 0, 30, 100)
    check resolved.layout.boxFor(second).rect == rect(0, 100, 30, 100)
    check resolved.layout.boxFor(firstChild).rect == rect(0, 0, 10, 100)
    check resolved.layout.boxFor(secondChild).rect == rect(0, 100, 10, 100)

  test "flex basis updates a nested percentage chain":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let item = tree.addBox(parent = some(root), id = "item")
    let inner = tree.addBox(parent = some(item), id = "inner")
    let leaf = tree.addBox(parent = some(inner), id = "leaf")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(50)),
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("start"))
      ]),
      rule(target(item), [
        decl("width", px(40)),
        decl("height", px(30)),
        decl("flex-basis", px(120)),
        decl("flex-shrink", number(0))
      ]),
      rule(target(inner), [
        decl("width", percent(100)),
        decl("height", px(20))
      ]),
      rule(target(leaf), [
        decl("width", percent(100)),
        decl("height", px(10))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(item).rect.w == 120
    check resolved.layout.boxFor(inner).rect.w == 120
    check resolved.layout.boxFor(leaf).rect.w == 120

  test "absolute descendants use the flexed containing block":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let firstOverlay = tree.addBox(parent = some(first), groups = ["overlay"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let secondOverlay = tree.addBox(parent = some(second), groups = ["overlay"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(50)),
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(40)),
        decl("height", px(30)),
        decl("flex-grow", number(1))
      ]),
      rule(group("overlay"), [
        decl("position", keyword("absolute")),
        decl("right", px(0)),
        decl("top", px(0)),
        decl("width", px(10)),
        decl("height", px(10))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(firstOverlay).rect == rect(90, 0, 10, 10)
    check resolved.layout.boxFor(secondOverlay).rect == rect(190, 0, 10, 10)

  test "row reverse keeps relaid descendants inside physical items":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let firstChild = tree.addBox(parent = some(first), groups = ["fill"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let secondChild = tree.addBox(parent = some(second), groups = ["fill"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(50)),
        decl("flex-direction", keyword("row-reverse")),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(40)),
        decl("height", px(30)),
        decl("flex-grow", number(1))
      ]),
      rule(group("fill"), [
        decl("width", percent(100)),
        decl("height", px(10))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect == rect(100, 0, 100, 30)
    check resolved.layout.boxFor(firstChild).rect == rect(100, 0, 100, 10)
    check resolved.layout.boxFor(second).rect == rect(0, 0, 100, 30)
    check resolved.layout.boxFor(secondChild).rect == rect(0, 0, 100, 10)

  test "overflow metrics are replaced with the flexed viewport":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    discard tree.addBox(parent = some(first), groups = ["fill"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    discard tree.addBox(parent = some(second), groups = ["fill"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(50)),
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(40)),
        decl("height", px(30)),
        decl("flex-grow", number(1)),
        decl("overflow-x", keyword("auto"))
      ]),
      rule(group("fill"), [
        decl("width", percent(100)),
        decl("height", px(10))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    let firstMetrics = resolved.layout.overflowFor(first)
    let secondMetrics = resolved.layout.overflowFor(second)
    check firstMetrics.isSome
    check secondMetrics.isSome
    check firstMetrics.get.viewportSize.w == 100
    check firstMetrics.get.contentSize.w == 100
    check secondMetrics.get.viewportSize.w == 100
    check secondMetrics.get.contentSize.w == 100

  test "grown items arrange centered descendants against their final width":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let item = tree.addBox(parent = some(root), id = "item")
    let child = tree.addBox(parent = some(item), id = "child")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(40)),
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("start"))
      ]),
      rule(target(item), [
        decl("width", px(40)),
        decl("height", px(30)),
        decl("flex-grow", number(1)),
        decl("flex-direction", keyword("row")),
        decl("justify-content", keyword("center"))
      ]),
      rule(target(child), [
        decl("width", px(20)),
        decl("height", px(10))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(item).rect == rect(0, 0, 200, 30)
    check resolved.layout.boxFor(child).rect == rect(90, 0, 20, 10)

  test "stretch arranges descendants against the final cross size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let item = tree.addBox(parent = some(root), id = "item")
    let child = tree.addBox(parent = some(item), id = "child")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(80)),
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("stretch"))
      ]),
      rule(target(item), [
        decl("width", px(100)),
        decl("justify-content", keyword("center"))
      ]),
      rule(target(child), [
        decl("width", px(20)),
        decl("height", px(10))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(item).rect == rect(0, 0, 100, 80)
    check resolved.layout.boxFor(child).rect == rect(0, 35, 20, 10)

  test "text flex items are measured again at the final width":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "wrapped text", id = "label")
    var measuredWidths: seq[float32]
    let textEngine = measureOnlyEngine(proc(input: TextMeasureInput): Size =
      let width = input.maxWidth.get(0)
      measuredWidths.add width
      size(width, if width <= 20: 40 else: 10)
    )
    var resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(120)),
        decl("height", px(50)),
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("start"))
      ]),
      rule(target(label), [
        decl("width", px(20)),
        decl("flex-grow", number(1))
      ])
    ])
    resolved.layout = computeLayout(
      tree, resolved.styles, size(400, 240), textEngine
    )

    check not resolved.diagnostics.hasErrors
    check measuredWidths.len >= 2
    check measuredWidths[^1] == 120
    check resolved.layout.boxFor(label).rect == rect(0, 0, 120, 10)

  test "content-box padding remains inside the final flex width":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let item = tree.addBox(parent = some(root), id = "item")
    let child = tree.addBox(parent = some(item), id = "child")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(50)),
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("start"))
      ]),
      rule(target(item), [
        decl("width", px(40)),
        decl("height", px(30)),
        decl("padding", px(10)),
        decl("box-sizing", keyword("content-box")),
        decl("flex-grow", number(1))
      ]),
      rule(target(child), [
        decl("width", percent(100)),
        decl("height", px(10))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(item).rect == rect(0, 0, 200, 50)
    check resolved.layout.boxFor(child).rect == rect(10, 10, 180, 10)

  test "zoom does not double-scale the final flex size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let item = tree.addBox(parent = some(root), id = "item")
    let child = tree.addBox(parent = some(item), id = "child")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(60)),
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("start"))
      ]),
      rule(target(item), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("zoom", number(2)),
        decl("flex-grow", number(1))
      ]),
      rule(target(child), [
        decl("width", percent(100)),
        decl("height", px(5))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(item).rect == rect(0, 0, 200, 40)
    check resolved.layout.boxFor(child).rect == rect(0, 0, 200, 10)

  test "wrapped lines reflow descendants to each line-local flex width":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let firstChild = tree.addBox(parent = some(first), groups = ["fill"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let secondChild = tree.addBox(parent = some(second), groups = ["fill"])
    let third = tree.addBox(parent = some(root), groups = ["item"])
    let thirdChild = tree.addBox(parent = some(third), groups = ["fill"])
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
      ]),
      rule(group("fill"), [
        decl("width", percent(100)),
        decl("height", px(10))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(firstChild).rect == rect(0, 0, 50, 10)
    check resolved.layout.boxFor(secondChild).rect == rect(50, 0, 50, 10)
    check resolved.layout.boxFor(thirdChild).rect == rect(0, 20, 100, 10)

  test "shrunk overflow viewports retain larger descendant content":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    discard tree.addBox(parent = some(first), groups = ["content"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    discard tree.addBox(parent = some(second), groups = ["content"])
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(40)),
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(80)),
        decl("height", px(30)),
        decl("min-width", px(0)),
        decl("flex-shrink", number(1)),
        decl("overflow-x", keyword("auto"))
      ]),
      rule(group("content"), [
        decl("width", px(80)),
        decl("height", px(10))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    let firstMetrics = resolved.layout.overflowFor(first).get
    let secondMetrics = resolved.layout.overflowFor(second).get
    check firstMetrics.viewportSize.w == 50
    check firstMetrics.contentSize.w == 80
    check secondMetrics.viewportSize.w == 50
    check secondMetrics.contentSize.w == 80

  test "unchanged sibling subtrees are not measured again":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let growing = tree.addBox(parent = some(root), id = "growing")
    discard tree.addText(growing, "growing label")
    let stable = tree.addBox(parent = some(root), id = "stable")
    discard tree.addText(stable, "stable label")
    var growingMeasures = 0
    var stableMeasures = 0
    let textEngine = measureOnlyEngine(proc(input: TextMeasureInput): Size =
      if input.text == "growing label":
        inc growingMeasures
      elif input.text == "stable label":
        inc stableMeasures
      size(20, 10)
    )
    var resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(40)),
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("start"))
      ]),
      rule(target(growing), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("flex-grow", number(1))
      ]),
      rule(target(stable), [
        decl("width", px(40)),
        decl("height", px(20))
      ])
    ])
    resolved.layout = computeLayout(
      tree, resolved.styles, size(400, 240), textEngine
    )

    check not resolved.diagnostics.hasErrors
    check growingMeasures == stableMeasures + 1
    check resolved.layout.boxFor(growing).rect.w == 160
    check resolved.layout.boxFor(stable).rect.w == 40
