import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc boxFor(layout: LayoutResult; node: NodeId): LayoutBox =
  for item in layout.boxes:
    if item.node == node:
      return item

proc resolveLayout(
    tree: Tree;
    rules: openArray[StyleRule]
): tuple[styles: ResolvedTree, layout: LayoutResult, diagnostics: Diagnostics] =
  result.styles = resolveTreeStyles(
    tree,
    [styleSheet(rules)],
    defaultProperties(),
    result.diagnostics
  )
  result.layout = computeLayout(tree, result.styles, size(200, 200))

suite "place-content runtime":
  test "one keyword applies to both content axes":
    let context = styleContext([
      decl("place-content", keyword("space-between"))
    ])
    var diagnostics: Diagnostics
    let style = resolveStyles(
      context, defaultProperties(), ResolveEnv(), diagnostics
    )

    check not diagnostics.hasErrors
    check style.layout.alignContent == jcSpaceBetween
    check style.layout.justifyContent == jcSpaceBetween

  test "two keywords independently place wrapped lines and their items":
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
        decl("place-content", keyword("center end")),
        decl("align-items", keyword("start"))
      ]),
      rule(group("item"), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("flex-shrink", number(0))
      ])
    ])

    check not resolved.diagnostics.hasErrors
    check resolved.layout.boxFor(first).rect == rect(10, 30, 40, 20)
    check resolved.layout.boxFor(second).rect == rect(10, 50, 40, 20)

  test "an invalid second keyword leaves both axes unchanged":
    let context = styleContext([
      decl("align-content", keyword("end")),
      decl("justify-content", keyword("center")),
      decl("place-content", keyword("start invalid"))
    ])
    var diagnostics: Diagnostics
    let style = resolveStyles(
      context, defaultProperties(), ResolveEnv(), diagnostics
    )

    check diagnostics.hasErrors
    check style.layout.alignContent == jcEnd
    check style.layout.justifyContent == jcCenter

  test "empty and excessive keyword lists are rejected":
    for value in ["", "start center end"]:
      let context = styleContext([
        decl("place-content", keyword(value))
      ])
      var diagnostics: Diagnostics
      discard resolveStyles(
        context, defaultProperties(), ResolveEnv(), diagnostics
      )
      check diagnostics.hasErrors
