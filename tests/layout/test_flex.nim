import std/[options, unittest]

import clay_box_style_system
import clay_box_style_system/generated/default_properties

proc rectFor(layout: LayoutResult; node: NodeId): Option[Rect] =
  for box in layout.boxes:
    if box.node == node:
      return some(box.rect)
  none(Rect)

suite "flex layout":
  test "flex-grow distributes remaining main-axis space":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), id = "first")
    let second = tree.addBox(parent = some(root), id = "second")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(120)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(id("first"), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("flex-grow", number(1))
      ]),
      rule(id("second"), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("flex-grow", number(3))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(120, 30))
    let firstRect = layout.rectFor(first)
    let secondRect = layout.rectFor(second)

    check firstRect.isSome
    check secondRect.isSome
    check firstRect.get.w == 40
    check secondRect.get.w == 80
    check secondRect.get.x == 40

  test "flex-shrink reduces overflowing main-axis size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), id = "first")
    let second = tree.addBox(parent = some(root), id = "second")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(80)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(id("first"), [
        decl("width", px(60)),
        decl("height", px(20)),
        decl("flex-shrink", number(1))
      ]),
      rule(id("second"), [
        decl("width", px(60)),
        decl("height", px(20)),
        decl("flex-shrink", number(1))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(80, 30))
    let firstRect = layout.rectFor(first)
    let secondRect = layout.rectFor(second)

    check firstRect.isSome
    check secondRect.isSome
    check firstRect.get.w == 40
    check secondRect.get.w == 40
    check secondRect.get.x == 40

  test "flex-shrink freezes at min-size and redistributes the deficit":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), id = "first")
    let second = tree.addBox(parent = some(root), id = "second")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(70)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(id("first"), [
        decl("width", px(60)),
        decl("height", px(20)),
        decl("min-width", px(50))
      ]),
      rule(id("second"), [
        decl("width", px(60)),
        decl("height", px(20)),
        decl("min-width", px(10))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(70, 30))

    check not diagnostics.hasErrors
    check layout.rectFor(first).get.w == 50
    check layout.rectFor(second).get.w == 20
    check layout.rectFor(second).get.x == 50

  test "flex-basis overrides initial main-axis size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(100)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(id("child"), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("flex-basis", px(50))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(100, 30))
    let childRect = layout.rectFor(child)

    check childRect.isSome
    check childRect.get.w == 50

  test "percentage flex-basis resolves against the parent content width":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(200)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(id("child"), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("flex-basis", percent(25))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(200, 30))

    check not diagnostics.hasErrors
    check styles.styles[child.nodeIndex].layout.flexBasis.isNone
    check styles.styles[child.nodeIndex].layout.sizing.flexBasis.get.kind == ukPercent
    check layout.rectFor(child).get.w == 50

  test "percentage flex-basis stays content based on an indefinite main axis":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(id("root"), [
        decl("height", px(30)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(id("child"), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("flex-basis", percent(50))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(200, 30))

    check not diagnostics.hasErrors
    check layout.rectFor(root).get.w == 20
    check layout.rectFor(child).get.w == 20

  test "content flex-basis uses measured content instead of explicit width":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addText(root, "hello", id = "child")
    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(200)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(id("child"), [
        decl("width", px(8)),
        decl("height", px(20)),
        decl("flex-basis", content())
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(200, 30))

    check not diagnostics.hasErrors
    check layout.rectFor(child).get.w == 40

  test "column-gap controls row main-axis spacing":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(100)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row")),
        decl("gap", px(2)),
        decl("column-gap", px(12))
      ]),
      rule(group("item"), [
        decl("width", px(20)),
        decl("height", px(20))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(100, 30))
    let firstRect = layout.rectFor(first)
    let secondRect = layout.rectFor(second)

    check firstRect.isSome
    check secondRect.isSome
    check firstRect.get.x == 0
    check secondRect.get.x == 32
    check styles.styles[root.nodeIndex].layout.sizing.isNil

  test "percentage column-gap resolves against the content width":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(200)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row")),
        decl("column-gap", percent(10))
      ]),
      rule(group("item"), [decl("width", px(20)), decl("height", px(20))])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(200, 30))

    check not diagnostics.hasErrors
    check layout.rectFor(first).get.x == 0
    check layout.rectFor(second).get.x == 40

  test "percentage gap does not inflate an auto intrinsic main size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])
    let sheet = styleSheet([
      rule(id("root"), [
        decl("height", px(30)),
        decl("flex-direction", keyword("row")),
        decl("gap", percent(10))
      ]),
      rule(group("item"), [
        decl("width", px(50)),
        decl("height", px(20)),
        decl("flex-shrink", number(0))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(300, 30))

    check not diagnostics.hasErrors
    check layout.rectFor(root).get.w == 100
    check layout.rectFor(first).get.x == 0
    check layout.rectFor(second).get.x == 60

  test "row-gap controls column main-axis spacing":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), groups = ["item"])
    let second = tree.addBox(parent = some(root), groups = ["item"])

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(40)),
        decl("height", px(100)),
        decl("gap", px(2)),
        decl("row-gap", px(14))
      ]),
      rule(group("item"), [
        decl("width", px(20)),
        decl("height", px(20))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(40, 100))
    let firstRect = layout.rectFor(first)
    let secondRect = layout.rectFor(second)

    check firstRect.isSome
    check secondRect.isSome
    check firstRect.get.y == 0
    check secondRect.get.y == 34

  test "inherited percentage gap resolves in the receiving container":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let nested = tree.addBox(parent = some(root), id = "nested")
    let first = tree.addBox(parent = some(nested), groups = ["item"])
    let second = tree.addBox(parent = some(nested), groups = ["item"])
    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(200)),
        decl("height", px(60)),
        decl("gap", percent(10))
      ]),
      rule(id("nested"), [
        decl("width", px(100)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row")),
        decl("gap", inherit())
      ]),
      rule(group("item"), [decl("width", px(20)), decl("height", px(20))])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(200, 60))

    check not diagnostics.hasErrors
    check styles.styles[nested.nodeIndex].layout.sizing.gap.get.kind == ukPercent
    check layout.rectFor(first).get.x == 0
    check layout.rectFor(second).get.x == 30

  test "order controls flex child placement":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), id = "first")
    let second = tree.addBox(parent = some(root), id = "second")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(100)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(id("first"), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("order", number(2))
      ]),
      rule(id("second"), [
        decl("width", px(20)),
        decl("height", px(20)),
        decl("order", number(1))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(100, 30))
    let firstRect = layout.rectFor(first)
    let secondRect = layout.rectFor(second)

    check firstRect.isSome
    check secondRect.isSome
    check secondRect.get.x == 0
    check firstRect.get.x == 20

  test "default order remains node creation order when child storage is reordered":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), id = "first")
    let second = tree.addBox(parent = some(root), id = "second")
    tree.nodes[root.nodeIndex].children = @[second, first]

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(100)),
        decl("height", px(30)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(id("first"), [decl("width", px(20)), decl("height", px(20))]),
      rule(id("second"), [decl("width", px(20)), decl("height", px(20))])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(100, 30))

    check not diagnostics.hasErrors
    check layout.rectFor(first).get.x == 0
    check layout.rectFor(second).get.x == 20

  test "align-self overrides parent align-items":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addBox(parent = some(root), id = "first")
    let second = tree.addBox(parent = some(root), id = "second")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("width", px(80)),
        decl("height", px(40)),
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("start"))
      ]),
      rule(id("first"), [
        decl("width", px(20)),
        decl("height", px(10)),
        decl("align-self", keyword("end"))
      ]),
      rule(id("second"), [
        decl("width", px(20)),
        decl("height", px(10))
      ])
    ])

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    check not diagnostics.hasErrors

    let layout = computeLayout(tree, styles, size(80, 40))
    let firstRect = layout.rectFor(first)
    let secondRect = layout.rectFor(second)

    check firstRect.isSome
    check secondRect.isSome
    check firstRect.get.y == 30
    check secondRect.get.y == 0
