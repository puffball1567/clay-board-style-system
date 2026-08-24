import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc boxFor(layout: LayoutResult; node: NodeId): LayoutBox =
  for item in layout.boxes:
    if item.node == node:
      return item

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

proc borderDeclarations(): seq[Declaration] =
  @[
    decl("border-width", px(5)),
    decl("border-style", keyword("solid"))
  ]

suite "box-sizing runtime layout":
  test "content-box adds padding and visible borders around explicit content size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    var rootStyle = @[
      decl("width", px(100)),
      decl("height", px(40)),
      decl("padding", px(10)),
      decl("box-sizing", keyword("content-box"))
    ]
    rootStyle.add borderDeclarations()
    let resolved = tree.resolveLayout([
      rule(target(root), rootStyle),
      rule(target(child), [
        decl("width", percent(100)),
        decl("height", percent(100))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(root).rect == rect(0, 0, 130, 70)
    check resolved.layout.boxFor(root).padding == edges(10)
    check resolved.layout.boxFor(child).rect == rect(15, 15, 100, 40)

  test "border-box keeps the explicit outer size and derives the content box":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    var rootStyle = @[
      decl("width", px(100)),
      decl("height", px(50)),
      decl("padding", px(10)),
      decl("box-sizing", keyword("border-box"))
    ]
    rootStyle.add borderDeclarations()
    let resolved = tree.resolveLayout([
      rule(target(root), rootStyle),
      rule(target(child), [
        decl("width", percent(100)),
        decl("height", percent(100))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(root).rect == rect(0, 0, 100, 50)
    check resolved.layout.boxFor(child).rect == rect(15, 15, 70, 20)

  test "border-box cannot shrink below its padding and visible borders":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    var declarations = @[
      decl("width", px(10)),
      decl("height", px(10)),
      decl("padding", px(10)),
      decl("box-sizing", keyword("border-box"))
    ]
    declarations.add borderDeclarations()
    let resolved = tree.resolveLayout([rule(target(root), declarations)])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(root).rect == rect(0, 0, 30, 30)

  test "min and max constraints use the selected sizing box":
    var tree = initTree()
    let host = tree.addBox(id = "host")
    let contentBox = tree.addBox(parent = some(host), id = "content")
    let borderBox = tree.addBox(parent = some(host), id = "border")
    let common = @[
      decl("width", px(100)),
      decl("height", px(20)),
      decl("max-width", px(60)),
      decl("padding", px(10))
    ]
    let resolved = tree.resolveLayout([
      rule(target(host), [decl("width", px(400)), decl("height", px(240))]),
      rule(target(contentBox), common & @[
        decl("box-sizing", keyword("content-box"))
      ]),
      rule(target(borderBox), common & @[
        decl("box-sizing", keyword("border-box"))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(contentBox).rect.w == 80
    check resolved.layout.boxFor(borderBox).rect.w == 60

  test "auto size is the same outer box under both sizing modes":
    var tree = initTree()
    let host = tree.addBox(id = "host")
    let contentBox = tree.addBox(parent = some(host), id = "content")
    let contentChild = tree.addBox(parent = some(contentBox))
    let borderBox = tree.addBox(parent = some(host), id = "border")
    let borderChild = tree.addBox(parent = some(borderBox))
    let common = @[
      decl("width", autoSize()),
      decl("height", autoSize()),
      decl("padding", px(5))
    ]
    let resolved = tree.resolveLayout([
      rule(target(host), [decl("width", px(400)), decl("height", px(240))]),
      rule(target(contentBox), common & @[
        decl("box-sizing", keyword("content-box"))
      ]),
      rule(target(borderBox), common & @[
        decl("box-sizing", keyword("border-box"))
      ]),
      rule(target(contentChild), [decl("width", px(40)), decl("height", px(12))]),
      rule(target(borderChild), [decl("width", px(40)), decl("height", px(12))])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(contentBox).rect.w == 50
    check resolved.layout.boxFor(contentBox).rect.h == 22
    check resolved.layout.boxFor(borderBox).rect.w == 50
    check resolved.layout.boxFor(borderBox).rect.h == 22

  test "flex basis uses each item's sizing box":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let contentBox = tree.addBox(parent = some(root), id = "content")
    let borderBox = tree.addBox(parent = some(root), id = "border")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(300)),
        decl("height", px(80)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(target(contentBox), [
        decl("flex-basis", px(100)),
        decl("height", px(20)),
        decl("padding", px(10)),
        decl("box-sizing", keyword("content-box")),
        decl("flex-shrink", number(0))
      ]),
      rule(target(borderBox), [
        decl("flex-basis", px(100)),
        decl("height", px(20)),
        decl("padding", px(10)),
        decl("box-sizing", keyword("border-box")),
        decl("flex-shrink", number(0))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(contentBox).rect.w == 120
    check resolved.layout.boxFor(borderBox).rect.w == 100
    check resolved.layout.boxFor(borderBox).rect.x == 120

  test "intrinsic sizing keywords are independent of box-sizing":
    var tree = initTree()
    let host = tree.addBox(id = "host")
    let contentBox = tree.addBox(parent = some(host), id = "content")
    let contentChild = tree.addBox(parent = some(contentBox))
    let borderBox = tree.addBox(parent = some(host), id = "border")
    let borderChild = tree.addBox(parent = some(borderBox))
    let common = @[
      decl("width", minContent()),
      decl("height", maxContent()),
      decl("padding", px(5))
    ]
    let resolved = tree.resolveLayout([
      rule(target(host), [
        decl("width", px(300)),
        decl("height", px(100)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(target(contentBox), common & @[
        decl("box-sizing", keyword("content-box"))
      ]),
      rule(target(borderBox), common & @[
        decl("box-sizing", keyword("border-box"))
      ]),
      rule(target(contentChild), [decl("width", px(40)), decl("height", px(12))]),
      rule(target(borderChild), [decl("width", px(40)), decl("height", px(12))])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(contentBox).rect == rect(0, 0, 50, 22)
    check resolved.layout.boxFor(borderBox).rect == rect(50, 0, 50, 22)

  test "aspect ratio uses the selected sizing box":
    var tree = initTree()
    let host = tree.addBox(id = "host")
    let contentBox = tree.addBox(parent = some(host), id = "content")
    let borderBox = tree.addBox(parent = some(host), id = "border")
    let common = @[
      decl("width", px(100)),
      decl("padding", px(10)),
      decl("aspect-ratio", number(2)),
      decl("flex-shrink", number(0))
    ]
    let resolved = tree.resolveLayout([
      rule(target(host), [
        decl("width", px(300)),
        decl("height", px(120)),
        decl("flex-direction", keyword("row"))
      ]),
      rule(target(contentBox), common & @[
        decl("box-sizing", keyword("content-box"))
      ]),
      rule(target(borderBox), common & @[
        decl("box-sizing", keyword("border-box"))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(contentBox).rect == rect(0, 0, 120, 70)
    check resolved.layout.boxFor(borderBox).rect == rect(120, 0, 100, 50)
