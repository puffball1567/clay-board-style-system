import std/[options, unittest]

import clay_box_style_system
import clay_box_style_system/generated/default_properties

proc rectFor(layout: LayoutResult; node: NodeId): Rect =
  for box in layout.boxes:
    if box.node == node:
      return box.rect
  rect(0, 0, 0, 0)

suite "layout positioning":
  test "relative child moves visually without changing normal flow":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let shifted = tree.addBox(parent = some(root), id = "shifted")
    let sibling = tree.addBox(parent = some(root), id = "sibling")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(100)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(id("shifted"), [
        decl("position", keyword("relative")),
        decl("left", px(12)),
        decl("top", px(4)),
        decl("width", px(20)),
        decl("height", px(10))
      ]),
      rule(id("sibling"), [
        decl("width", px(20)),
        decl("height", px(10))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    check styles.styles[shifted.nodeIndex].layout.position == pkRelative

    let layout = computeLayout(tree, styles, size(100, 30))
    var shiftedRect: Option[Rect]
    var siblingRect: Option[Rect]
    for box in layout.boxes:
      if box.node == shifted:
        shiftedRect = some(box.rect)
      if box.node == sibling:
        siblingRect = some(box.rect)

    check shiftedRect.isSome
    check siblingRect.isSome
    check shiftedRect.get.x == 12
    check shiftedRect.get.y == 4
    check siblingRect.get.x == 20
    check siblingRect.get.y == 0

  test "relative right and bottom offsets move in the opposite direction":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let shifted = tree.addBox(parent = some(root), id = "shifted")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(100)),
        decl("height", px(40))
      ]),
      rule(id("shifted"), [
        decl("position", keyword("relative")),
        decl("right", px(7)),
        decl("bottom", px(3)),
        decl("width", px(20)),
        decl("height", px(10))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(100, 40))
    var shiftedRect: Option[Rect]
    for box in layout.boxes:
      if box.node == shifted:
        shiftedRect = some(box.rect)

    check shiftedRect.isSome
    check shiftedRect.get.x == -7
    check shiftedRect.get.y == -3

  test "relative percentage insets use the parent content box":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let shifted = tree.addBox(parent = some(root), id = "shifted")
    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(220)),
        decl("height", px(120)),
        decl("padding", px(10))
      ]),
      rule(id("shifted"), [
        decl("position", keyword("relative")),
        decl("left", percent(10)),
        decl("top", percent(25)),
        decl("width", px(20)),
        decl("height", px(10))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(220, 120))

    check not diagnostics.hasErrors
    check layout.rectFor(shifted) == rect(30, 35, 20, 10)

  test "negative percentage inset keeps its sign":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let shifted = tree.addBox(parent = some(root), id = "shifted")
    let sheet = styleSheet([
      rule(id("root"), [decl("width", px(200)), decl("height", px(40))]),
      rule(id("shifted"), [
        decl("position", keyword("relative")),
        decl("left", percent(-10)),
        decl("width", px(20)),
        decl("height", px(10))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(200, 40))

    check not diagnostics.hasErrors
    check layout.rectFor(shifted).x == -20

  test "absolute child is positioned from parent padding box":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let normal = tree.addBox(parent = some(root), id = "normal")
    let overlay = tree.addBox(parent = some(root), id = "overlay")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(160)),
        decl("height", px(100)),
        decl("padding", px(10)),
        decl("gap", px(8))
      ]),
      rule(id("normal"), [
        decl("width", px(30)),
        decl("height", px(20))
      ]),
      rule(id("overlay"), [
        decl("position", keyword("absolute")),
        decl("right", px(12)),
        decl("bottom", px(6)),
        decl("width", px(40)),
        decl("height", px(18))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(160, 100))
    var normalRect: Option[Rect]
    var overlayRect: Option[Rect]
    for box in layout.boxes:
      if box.node == normal:
        normalRect = some(box.rect)
      if box.node == overlay:
        overlayRect = some(box.rect)

    check normalRect.isSome
    check overlayRect.isSome
    check normalRect.get.x == 10
    check normalRect.get.y == 10
    check overlayRect.get.x == 98
    check overlayRect.get.y == 66

  test "absolute percentage insets resolve on their physical axes":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let overlay = tree.addBox(parent = some(root), id = "overlay")
    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(220)),
        decl("height", px(120)),
        decl("padding", px(10))
      ]),
      rule(id("overlay"), [
        decl("position", keyword("absolute")),
        decl("right", percent(10)),
        decl("bottom", percent(20)),
        decl("width", px(20)),
        decl("height", px(10))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(220, 120))

    check not diagnostics.hasErrors
    check layout.rectFor(overlay) == rect(170, 80, 20, 10)

  test "explicit inset inheritance preserves percentage semantics":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(id("root"), [
        decl("position", keyword("relative")),
        decl("left", percent(10)),
        decl("width", px(200)),
        decl("height", px(40))
      ]),
      rule(id("child"), [
        decl("position", keyword("relative")),
        decl("left", inherit()),
        decl("width", px(20)),
        decl("height", px(10))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(200, 40))

    check not diagnostics.hasErrors
    check styles.styles[child.nodeIndex].layout.sizing.insetLeft.get.kind == ukPercent
    check layout.rectFor(child).x == 20

  test "subtree relayout updates absolute descendants without moving siblings":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let field = tree.addBox(parent = some(root), id = "field")
    let caret = tree.addBox(parent = some(field), id = "caret")
    let sibling = tree.addBox(parent = some(root), id = "sibling")

    proc sheetFor(caretLeft: float32): StyleSheet =
      styleSheet([
        rule(id("root"), [
          decl("width", px(180)),
          decl("height", px(40)),
          decl("flex-direction", keyword("row")),
          decl("gap", px(8))
        ]),
        rule(id("field"), [
          decl("width", px(100)),
          decl("height", px(30))
        ]),
        rule(id("caret"), [
          decl("position", keyword("absolute")),
          decl("left", px(caretLeft)),
          decl("top", px(4)),
          decl("width", px(1)),
          decl("height", px(16))
        ]),
        rule(id("sibling"), [
          decl("width", px(20)),
          decl("height", px(20))
        ])
      ])

    var diagnostics: Diagnostics
    let stylesBefore = resolveTreeStyles(tree, [sheetFor(4)], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    var layout = computeLayout(tree, stylesBefore, size(180, 40))
    var siblingBefore: Option[Rect]
    for box in layout.boxes:
      if box.node == sibling:
        siblingBefore = some(box.rect)

    diagnostics = Diagnostics()
    let stylesAfter = resolveTreeStyles(tree, [sheetFor(42)], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let fullLayout = computeLayout(tree, stylesAfter, size(180, 40))
    check relayoutSubtree(tree, stylesAfter, field, layout)

    var caretPartial: Option[Rect]
    var caretFull: Option[Rect]
    var siblingAfter: Option[Rect]
    for box in layout.boxes:
      if box.node == caret:
        caretPartial = some(box.rect)
      if box.node == sibling:
        siblingAfter = some(box.rect)
    for box in fullLayout.boxes:
      if box.node == caret:
        caretFull = some(box.rect)

    check caretPartial.isSome
    check caretFull.isSome
    check siblingBefore.isSome
    check siblingAfter.isSome
    check caretPartial.get.x == caretFull.get.x
    check caretPartial.get.y == caretFull.get.y
    check siblingAfter.get == siblingBefore.get

  test "subtree relayout propagates changed flow size to following siblings":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), id = "first")
    let second = tree.addBox(parent = some(root), id = "second")

    proc sheetFor(firstHeight: float32): StyleSheet =
      styleSheet([
        rule(id("root"), [
          decl("width", px(100)),
          decl("height", px(100)),
          decl("flex-direction", keyword("column"))
        ]),
        rule(id("first"), [
          decl("width", px(100)),
          decl("height", px(firstHeight))
        ]),
        rule(id("second"), [
          decl("width", px(100)),
          decl("height", px(20))
        ])
      ])

    var diagnostics: Diagnostics
    var styles = resolveTreeStyles(
      tree, [sheetFor(20)], defaultProperties(), diagnostics
    )
    var layout = computeLayout(tree, styles, size(100, 100))
    diagnostics = Diagnostics()
    check resolveSubtreeStyles(
      tree, first, [sheetFor(40)], defaultProperties(), diagnostics, styles
    )
    check relayoutSubtree(tree, styles, first, layout)

    let indices = layout.layoutBoxIndices(tree.nodes.len)
    check layout.boxes[indices.boxIndexFor(first)].rect == rect(0, 0, 100, 40)
    check layout.boxes[indices.boxIndexFor(second)].rect == rect(0, 40, 100, 20)

  test "absolute child does not affect normal flow size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addBox(parent = some(root), id = "overlay")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("padding", px(10))
      ]),
      rule(id("overlay"), [
        decl("position", keyword("absolute")),
        decl("width", px(80)),
        decl("height", px(40))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(200, 200))
    var rootRect: Option[Rect]
    for box in layout.boxes:
      if box.node == root:
        rootRect = some(box.rect)

    check rootRect.isSome
    check rootRect.get.w == 20
    check rootRect.get.h == 20

  test "inset aliases position absolute child":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let overlay = tree.addBox(parent = some(root), id = "overlay")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(120)),
        decl("height", px(80)),
        decl("padding", px(10))
      ]),
      rule(id("overlay"), [
        decl("position", keyword("absolute")),
        decl("inset", px(4)),
        decl("inset-block-start", px(7)),
        decl("inset-inline-start", px(9)),
        decl("width", px(20)),
        decl("height", px(10))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(120, 80))
    var overlayRect: Option[Rect]
    for box in layout.boxes:
      if box.node == overlay:
        overlayRect = some(box.rect)

    check overlayRect.isSome
    check overlayRect.get.x == 19
    check overlayRect.get.y == 17
    check styles.styles[overlay.nodeIndex].layout.sizing.isNil
