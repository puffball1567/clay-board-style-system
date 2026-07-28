import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

suite "style resolver invalidation":
  test "subtree resolution updates descendants and preserves inherited parent style":
    let ui = initUiRoot()
    let parent = ui.box()
    let child = ui.box(parent = some(parent))
    var sheets = @[
      styleSheet([
        rule(target(parent.nodeId), [
          decl("color", colorValue(rgb(0.2, 0.4, 0.6)))
        ]),
        rule(target(child.nodeId), [
          decl("width", px(40))
        ])
      ])
    ]
    var diagnostics: Diagnostics
    var resolved = resolveTreeStyles(
      ui.tree,
      sheets,
      defaultProperties(),
      diagnostics
    )
    check not diagnostics.hasErrors

    sheets[0] = styleSheet([
      rule(target(parent.nodeId), [
        decl("color", colorValue(rgb(0.2, 0.4, 0.6)))
      ]),
      rule(target(child.nodeId), [
        decl("width", px(96))
      ])
    ])
    diagnostics = Diagnostics()

    check resolveSubtreeStyles(
      ui.tree,
      child.nodeId,
      sheets,
      defaultProperties(),
      diagnostics,
      resolved
    )
    check not diagnostics.hasErrors
    check resolved.styles[child.nodeId.nodeIndex].layout.width == some(96.0'f32)
    check resolved.styles[child.nodeId.nodeIndex].text.color ==
      resolved.styles[parent.nodeId.nodeIndex].text.color

  test "tree resolution supplies resolved font bases to em and rem values":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")

    let sheet = styleSheet([
      rule(id("root"), [
        decl("font-size", px(20)),
        decl("padding", em(1)),
        decl("margin-top", rem(1))
      ]),
      rule(id("child"), [
        decl("font-size", em(1.5)),
        decl("padding", em(1)),
        decl("margin-top", rem(1))
      ])
    ])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let rootStyle = resolved.styles[root.nodeIndex]
    let childStyle = resolved.styles[child.nodeIndex]

    check not diagnostics.hasErrors
    check rootStyle.text.fontSize == some(20.0'f32)
    check rootStyle.box.padding == some(edges(20))
    check rootStyle.box.margin.get.top == 20
    check childStyle.text.fontSize == some(30.0'f32)
    check childStyle.box.padding == some(edges(30))
    check childStyle.box.margin.get.top == 20

  test "tree resolution accepts a configurable root font baseline":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(id("child"), [
        decl("font-size", rem(1.5)),
        decl("padding", em(1))
      ])
    ])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree,
      [sheet],
      defaultProperties(),
      diagnostics,
      rootFontSize = 18
    )

    check not diagnostics.hasErrors
    check resolved.styles[root.nodeIndex].text.fontSize == some(18.0'f32)
    check resolved.styles[child.nodeIndex].text.fontSize == some(27.0'f32)
    check resolved.styles[child.nodeIndex].box.padding == some(edges(27))
