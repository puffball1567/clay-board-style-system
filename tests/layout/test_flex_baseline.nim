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

suite "flex baseline alignment":
  test "mixed font sizes share their first text baseline":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let small = tree.addText(root, "small", id = "small")
    let large = tree.addText(root, "large", id = "large")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("baseline"))
      ]),
      rule(target(small), [
        decl("font-size", px(10)),
        decl("line-height", px(12))
      ]),
      rule(target(large), [
        decl("font-size", px(20)),
        decl("line-height", px(24))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(small).rect.y == 9
    check resolved.layout.boxFor(large).rect.y == 0
    check resolved.layout.boxFor(root).rect.h == 24

  test "descent space expands a line below an image baseline":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let image = tree.addImage(root, "icon.png", 30, 20, id = "image")
    let text = tree.addText(root, "Text", id = "text")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("baseline"))
      ]),
      rule(target(text), [
        decl("font-size", px(20)),
        decl("line-height", px(24))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(image).rect.y == 0
    check resolved.layout.boxFor(text).rect.y == 2
    check resolved.layout.boxFor(root).rect.h == 26

  test "align-self baseline overrides the parent alignment":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let small = tree.addText(root, "small", id = "small")
    let large = tree.addText(root, "large", id = "large")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("end"))
      ]),
      rule(target(small), [
        decl("align-self", keyword("baseline")),
        decl("font-size", px(10)),
        decl("line-height", px(12))
      ]),
      rule(target(large), [
        decl("align-self", keyword("baseline")),
        decl("font-size", px(20)),
        decl("line-height", px(24))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(small).rect.y == 9
    check resolved.layout.boxFor(large).rect.y == 0

  test "non-baseline siblings keep their own alignment":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let baselineText = tree.addText(root, "base", id = "base")
    let centered = tree.addBox(parent = some(root), id = "centered")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("height", px(40)),
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("baseline"))
      ]),
      rule(target(baselineText), [
        decl("font-size", px(20)),
        decl("line-height", px(24))
      ]),
      rule(target(centered), [
        decl("width", px(10)),
        decl("height", px(10)),
        decl("align-self", keyword("center"))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(baselineText).rect.y == 0
    check resolved.layout.boxFor(centered).rect.y == 15

  test "row-reverse mirrors only the main axis":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let small = tree.addText(root, "a", id = "small")
    let large = tree.addText(root, "b", id = "large")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("flex-direction", keyword("row-reverse")),
        decl("align-items", keyword("baseline"))
      ]),
      rule(target(small), [
        decl("font-size", px(10)), decl("line-height", px(12))
      ]),
      rule(target(large), [
        decl("font-size", px(20)), decl("line-height", px(24))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(small).rect.x > resolved.layout.boxFor(large).rect.x
    check resolved.layout.boxFor(small).rect.y == 9
    check resolved.layout.boxFor(large).rect.y == 0

  test "wrapped rows aggregate baselines independently":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addText(root, "a", id = "first")
    let second = tree.addText(root, "b", id = "second")
    let third = tree.addText(root, "c", id = "third")
    let fourth = tree.addText(root, "d", id = "fourth")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(40)),
        decl("flex-direction", keyword("row")),
        decl("flex-wrap", keyword("wrap")),
        decl("align-items", keyword("baseline"))
      ]),
      rule(group("item"), [decl("flex-shrink", number(0))]),
      rule(target(first), [
        decl("width", px(20)), decl("font-size", px(10)),
        decl("line-height", px(12)), decl("flex-shrink", number(0))
      ]),
      rule(target(second), [
        decl("width", px(20)), decl("font-size", px(20)),
        decl("line-height", px(24)), decl("flex-shrink", number(0))
      ]),
      rule(target(third), [
        decl("width", px(20)), decl("font-size", px(20)),
        decl("line-height", px(24)), decl("flex-shrink", number(0))
      ]),
      rule(target(fourth), [
        decl("width", px(20)), decl("font-size", px(10)),
        decl("line-height", px(12)), decl("flex-shrink", number(0))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect.y == 9
    check resolved.layout.boxFor(second).rect.y == 0
    check resolved.layout.boxFor(third).rect.y == 24
    check resolved.layout.boxFor(fourth).rect.y == 33

  test "nested row containers propagate their first baseline":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let nested = tree.addBox(parent = some(root), id = "nested")
    let nestedText = tree.addText(nested, "small", id = "nested-text")
    let large = tree.addText(root, "large", id = "large")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("baseline"))
      ]),
      rule(target(nested), [decl("flex-direction", keyword("row"))]),
      rule(target(nestedText), [
        decl("font-size", px(10)), decl("line-height", px(12))
      ]),
      rule(target(large), [
        decl("font-size", px(20)), decl("line-height", px(24))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(nested).rect.y == 9
    check resolved.layout.boxFor(nestedText).rect.y == 9
    check resolved.layout.boxFor(large).rect.y == 0

  test "column baseline falls back to cross-start":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("width", px(100)),
        decl("flex-direction", keyword("column")),
        decl("align-items", keyword("baseline"))
      ]),
      rule(target(child), [decl("width", px(20)), decl("height", px(10))])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(child).rect.x == 0

  test "hit regions follow baseline-shifted boxes":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let small = tree.addText(root, "a", id = "small")
    let large = tree.addText(root, "b", id = "large")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("baseline"))
      ]),
      rule(target(small), [
        decl("font-size", px(10)), decl("line-height", px(12))
      ]),
      rule(target(large), [
        decl("font-size", px(20)), decl("line-height", px(24))
      ])
    ])
    let regions = buildHitRegions(tree, resolved.layout, resolved.styles)

    check hitTest(regions, vec2(4, 10)).get.node == small
    check hitTest(regions, vec2(12, 4)).get.node == large

  test "physical margins participate in baseline line metrics":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let image = tree.addImage(root, "icon.png", 30, 20, id = "image")
    let text = tree.addText(root, "Text", id = "text")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("baseline"))
      ]),
      rule(target(image), [decl("margin-top", px(4))]),
      rule(target(text), [
        decl("font-size", px(20)), decl("line-height", px(24))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(image).rect.y == 4
    check resolved.layout.boxFor(text).rect.y == 6
    check resolved.layout.boxFor(root).rect.h == 30

  test "zoom scales a child baseline with its border box":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let zoomed = tree.addText(root, "a", id = "zoomed")
    let large = tree.addText(root, "b", id = "large")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("baseline"))
      ]),
      rule(target(zoomed), [
        decl("font-size", px(10)), decl("line-height", px(12)),
        decl("zoom", keyword("2"))
      ]),
      rule(target(large), [
        decl("font-size", px(20)), decl("line-height", px(24))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(zoomed).rect.y == 0
    check resolved.layout.boxFor(large).rect.y == 0

  test "display-none children do not contribute a baseline":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let visible = tree.addText(root, "a", id = "visible")
    let hidden = tree.addText(root, "b", id = "hidden")
    let resolved = tree.resolveLayout([
      rule(target(root), [
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("baseline"))
      ]),
      rule(target(visible), [
        decl("font-size", px(10)), decl("line-height", px(12))
      ]),
      rule(target(hidden), [
        decl("display", keyword("none")),
        decl("font-size", px(40)), decl("line-height", px(48))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(visible).rect.y == 0
    check resolved.layout.boxFor(root).rect.h == 12
