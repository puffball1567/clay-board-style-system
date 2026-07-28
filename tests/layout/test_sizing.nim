import std/[options, unittest]

import clay_box_style_system
import clay_box_style_system/generated/default_properties

proc rectFor(layout: LayoutResult; node: NodeId): Rect =
  for box in layout.boxes:
    if box.node == node:
      return box.rect
  rect(0, 0, 0, 0)

proc resolvedLayout(
    tree: Tree;
    declarations: openArray[Declaration];
    viewport: Size
): tuple[styles: ResolvedTree, layout: LayoutResult, diagnostics: Diagnostics] =
  let sheet = styleSheet([rule(target(tree.root.get), declarations)])
  result.styles = resolveTreeStyles(tree, [sheet], defaultProperties(), result.diagnostics)
  result.layout = computeLayout(tree, result.styles, viewport)

suite "percentage auto and intrinsic sizing":
  test "percentage width resolves against the viewport and responds to resize":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.resolvedLayout([decl("width", percent(50)), decl("height", px(20))], size(200, 100))
    let second = tree.resolvedLayout([decl("width", percent(50)), decl("height", px(20))], size(320, 100))

    check not first.diagnostics.hasErrors
    check first.styles.styles[root.nodeIndex].layout.width.isNone
    check not first.styles.styles[root.nodeIndex].layout.sizing.isNil
    check first.styles.styles[root.nodeIndex].layout.sizing.width.get.kind == ukPercent
    check first.layout.rectFor(root).w == 100
    check second.layout.rectFor(root).w == 160

  test "fixed pixel sizing stays on the allocation-free hot path":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let resolved = tree.resolvedLayout([
      decl("width", px(80)),
      decl("height", px(20))
    ], size(200, 100))

    check not resolved.diagnostics.hasErrors
    check resolved.styles.styles[root.nodeIndex].layout.sizing.isNil
    check resolved.layout.rectFor(root) == rect(0, 0, 80, 20)

  test "child percentage uses the parent content box":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(60)),
        decl("padding", px(10))
      ]),
      rule(target(child), [decl("width", percent(100)), decl("height", px(20))])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(400, 200))

    check not diagnostics.hasErrors
    check layout.rectFor(root).w == 200
    check layout.rectFor(child) == rect(10, 10, 180, 20)

  test "percentage min and max constraints use the containing size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let resolved = tree.resolvedLayout([
      decl("width", percent(80)),
      decl("height", px(20)),
      decl("max-width", percent(60))
    ], size(200, 100))

    check not resolved.diagnostics.hasErrors
    check resolved.layout.rectFor(root).w == 120

  test "minimum constraint wins when it exceeds maximum":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let resolved = tree.resolvedLayout([
      decl("width", px(80)),
      decl("height", px(20)),
      decl("min-width", px(120)),
      decl("max-width", px(100))
    ], size(200, 100))

    check not resolved.diagnostics.hasErrors
    check resolved.layout.rectFor(root).w == 120

  test "explicit inheritance preserves percentage semantics":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [decl("width", percent(50)), decl("height", px(40))]),
      rule(target(child), [decl("width", inherit()), decl("height", px(10))])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(200, 100))

    check not diagnostics.hasErrors
    check layout.rectFor(root).w == 100
    check layout.rectFor(child).w == 50

  test "auto keeps content based natural sizing":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [decl("width", autoSize()), decl("padding", px(5))]),
      rule(target(child), [decl("width", px(40)), decl("height", px(12))])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(200, 100))

    check not diagnostics.hasErrors
    check layout.rectFor(root) == rect(0, 0, 50, 22)

  test "min max and fit content select measured text widths":
    proc textWidth(value: StyleValue; viewportWidth: float32): float32 =
      var tree = initTree()
      let root = tree.addBox(id = "root")
      let text = tree.addText(root, "hello world", id = "text")
      let sheet = styleSheet([rule(target(text), [
        decl("width", value),
        decl("line-height", px(8))
      ])])
      var diagnostics: Diagnostics
      let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
      let layout = computeLayout(tree, styles, size(viewportWidth, 40))
      check not diagnostics.hasErrors
      layout.rectFor(text).w

    check textWidth(minContent(), 60) == 40
    check textWidth(maxContent(), 60) == 88
    check textWidth(fitContent(), 60) == 60
    check textWidth(content(), 60) == 88

  test "intrinsic measurement work grows linearly with text nodes":
    const textNodeCount = 128
    var tree = initTree()
    let root = tree.addBox(id = "root")
    for index in 0 ..< textNodeCount:
      discard tree.addText(root, "item " & $index, groups = ["item"])

    let sheet = styleSheet([
      rule(target(root), [
        decl("width", fitContent()),
        decl("flex-direction", keyword("column"))
      ]),
      rule(group("item"), [decl("width", minContent())])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    var measureCalls = 0
    let engine = TextEngine(
      measureText: proc(input: TextMeasureInput): Size =
        inc measureCalls
        debugMeasureText(input),
      caretPosition: debugCaretPosition,
      hitTestText: debugHitText
    )

    discard computeLayout(tree, styles, size(800, 600), engine)

    check not diagnostics.hasErrors
    check measureCalls >= textNodeCount * 2
    check measureCalls <= textNodeCount * 4
