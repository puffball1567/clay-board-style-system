import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

suite "line-height-relative unit resolution":
  test "constructors append stable public unit ordinals":
    check ord(ukVmax) == 14
    check ord(ukLh) == 15
    check ord(ukRlh) == 16
    check lh(1.5).length == LengthValue(kind: ukLh, value: 1.5)
    check rlh(2).length == LengthValue(kind: ukRlh, value: 2)

  test "ordinary properties use current and root computed line heights":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [
        decl("font-size", px(20)),
        decl("line-height", px(30)),
        decl("padding", lh(2))
      ]),
      rule(target(child), [
        decl("font-size", lh(1)),
        decl("line-height", number(1.5)),
        decl("width", lh(2)),
        decl("height", rlh(2))
      ])
    ])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree, [sheet], defaultProperties(), diagnostics
    )

    check not diagnostics.hasErrors
    check resolved.styles[root.nodeIndex].text.lineHeight == some(30.0'f32)
    check resolved.styles[root.nodeIndex].box.padding == some(edges(60))
    check resolved.styles[child.nodeIndex].text.fontSize == some(30.0'f32)
    check resolved.styles[child.nodeIndex].text.lineHeight == some(45.0'f32)
    check resolved.styles[child.nodeIndex].layout.width == some(90.0'f32)
    check resolved.styles[child.nodeIndex].layout.height == some(60.0'f32)

  test "root font properties use initial metrics before establishing rlh":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let sheet = styleSheet([rule(target(root), [
      decl("font-size", lh(1)),
      decl("line-height", number(2)),
      decl("width", rlh(1))
    ])])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree, [sheet], defaultProperties(), diagnostics, rootFontSize = 16
    )

    check not diagnostics.hasErrors
    check abs(resolved.styles[root.nodeIndex].text.fontSize.get - 19.2) < 0.001
    check abs(resolved.styles[root.nodeIndex].text.lineHeight.get - 38.4) < 0.001
    check abs(resolved.styles[root.nodeIndex].layout.width.get - 38.4) < 0.001

  test "line-height lh resolves against the parent to avoid a cycle":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [
        decl("font-size", px(20)),
        decl("line-height", px(24))
      ]),
      rule(target(child), [
        decl("font-size", px(10)),
        decl("line-height", lh(2)),
        decl("height", lh(1))
      ])
    ])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree, [sheet], defaultProperties(), diagnostics
    )

    check not diagnostics.hasErrors
    check resolved.styles[child.nodeIndex].text.lineHeight == some(48.0'f32)
    check resolved.styles[child.nodeIndex].layout.height == some(48.0'f32)

  test "normal line-height follows the resolved element font size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [decl("line-height", px(40))]),
      rule(target(child), [
        decl("font-size", px(10)),
        decl("line-height", keyword("normal")),
        decl("height", lh(2))
      ])
    ])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree, [sheet], defaultProperties(), diagnostics
    )

    check not diagnostics.hasErrors
    check abs(resolved.styles[child.nodeIndex].text.lineHeight.get - 12) < 0.001
    check abs(resolved.styles[child.nodeIndex].layout.height.get - 24) < 0.001

  test "implicit normal metrics follow each element font size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [
        decl("font-size", px(20)),
        decl("width", lh(1)),
        decl("height", rlh(1))
      ]),
      rule(target(child), [
        decl("font-size", px(10)),
        decl("width", lh(1)),
        decl("height", rlh(1))
      ])
    ])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree, [sheet], defaultProperties(), diagnostics
    )

    check not diagnostics.hasErrors
    check resolved.styles[root.nodeIndex].text.lineHeight.isNone
    check abs(resolved.styles[root.nodeIndex].layout.width.get - 24) < 0.001
    check abs(resolved.styles[root.nodeIndex].layout.height.get - 24) < 0.001
    check resolved.styles[child.nodeIndex].text.lineHeight.isNone
    check abs(resolved.styles[child.nodeIndex].layout.width.get - 12) < 0.001
    check abs(resolved.styles[child.nodeIndex].layout.height.get - 24) < 0.001

  test "subtree resolution retains the established root line height":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [decl("line-height", px(28))]),
      rule(target(child), [decl("height", rlh(3))])
    ])
    var diagnostics: Diagnostics
    var resolved = resolveTreeStyles(
      tree, [sheet], defaultProperties(), diagnostics
    )

    check resolveSubtreeStyles(
      tree, child, [sheet], defaultProperties(), diagnostics, resolved
    )
    check not diagnostics.hasErrors
    check resolved.styles[child.nodeIndex].layout.height == some(84.0'f32)

  test "standalone resolution diagnoses missing line-height contexts":
    let context = styleContext([
      decl("width", lh(2)),
      decl("height", rlh(2))
    ])
    var diagnostics: Diagnostics
    let style = resolveStyles(
      context, defaultProperties(), ResolveEnv(), diagnostics
    )

    check diagnostics.hasErrors
    check diagnostics.items.len == 2
    check style.layout.width.isNone
    check style.layout.height.isNone
