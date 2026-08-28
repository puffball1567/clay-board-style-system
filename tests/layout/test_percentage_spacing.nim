import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc rectFor(layout: LayoutResult; node: NodeId): Rect =
  for box in layout.boxes:
    if box.node == node:
      return box.rect
  rect(0, 0, 0, 0)

proc boxFor(layout: LayoutResult; node: NodeId): LayoutBox =
  for box in layout.boxes:
    if box.node == node:
      return box

suite "percentage box spacing":
  test "percentage padding resolves from containing inline size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(100)),
        decl("padding", percent(10)),
        decl("box-sizing", keyword("border-box"))
      ]),
      rule(target(child), [
        decl("width", percent(100)),
        decl("height", px(20)),
        decl("flex-shrink", number(0))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(400, 200))

    check not diagnostics.hasErrors
    check styles.styles[root.nodeIndex].layout.sizing.paddingLeft ==
      some(LengthValue(kind: ukPercent, value: 10))
    check layout.rectFor(root) == rect(0, 0, 200, 100)
    check layout.rectFor(child) == rect(40, 40, 120, 20)
    check layout.boxFor(root).padding == edges(40)

    let resized = computeLayout(tree, styles, size(500, 200))
    check resized.boxFor(root).padding == edges(50)
    check resized.rectFor(child) == rect(50, 50, 100, 20)

  test "percentage margins resolve from parent content inline size":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(100)),
        decl("padding", px(10)),
        decl("box-sizing", keyword("border-box"))
      ]),
      rule(target(child), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("margin-left", percent(10)),
        decl("margin-top", percent(5))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(400, 200))

    check not diagnostics.hasErrors
    check styles.styles[child.nodeIndex].layout.sizing.marginLeft ==
      some(LengthValue(kind: ukPercent, value: 10))
    check layout.rectFor(child) == rect(28, 19, 40, 20)

  test "logical side overrides preserve mixed pixel and percentage values":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(100)),
        decl("padding", percent(10)),
        decl("padding-inline", px(5)),
        decl("box-sizing", keyword("border-box"))
      ]),
      rule(target(child), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("margin", percent(10)),
        decl("margin-block", px(2))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(200, 120))

    check not diagnostics.hasErrors
    check styles.styles[root.nodeIndex].layout.sizing.paddingLeft.isNone
    check styles.styles[root.nodeIndex].layout.sizing.paddingTop.isSome
    check styles.styles[child.nodeIndex].layout.sizing.marginLeft.isSome
    check styles.styles[child.nodeIndex].layout.sizing.marginTop.isNone
    check layout.rectFor(child) == rect(24, 22, 40, 20)

  test "inherited percentage sides retain their late resolution":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(100)),
        decl("padding-left", percent(10)),
        decl("margin-top", percent(5))
      ]),
      rule(target(child), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("padding-left", inherit()),
        decl("margin-top", inherit())
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    discard computeLayout(tree, styles, size(400, 200))

    check not diagnostics.hasErrors
    check styles.styles[child.nodeIndex].layout.sizing.paddingLeft ==
      some(LengthValue(kind: ukPercent, value: 10))
    check styles.styles[child.nodeIndex].layout.sizing.marginTop ==
      some(LengthValue(kind: ukPercent, value: 5))

  test "relative merge rejects an unresolved percentage base":
    let context = styleContext([
      decl("padding", percent(10)),
      decl("padding", relative(px(2)))
    ])
    var diagnostics: Diagnostics
    discard resolveStyles(context, defaultProperties(), ResolveEnv(), diagnostics)

    check diagnostics.hasErrors
    check diagnostics.items.len == 1

  test "resolved padding is shared by clipping and presented content":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let sheet = styleSheet([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(100)),
        decl("padding", percent(10)),
        decl("box-sizing", keyword("border-box")),
        decl("overflow", keyword("hidden"))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(400, 200))
    let item = layout.boxFor(root)
    let presentation = presentationForNode(tree, layout, styles, root)
    let commands = buildPaintCommands(tree, styles, layout)
    var paintedClip = none(Rect)
    for command in commands:
      if command.kind == pcPushClip:
        paintedClip = some(command.clipRect)
        break

    check not diagnostics.hasErrors
    check item.padding == edges(40)
    check overflowClipRect(item.rect, styles.styles[root.nodeIndex], item.padding) ==
      rect(40, 40, 120, 20)
    check paintedClip == some(rect(40, 40, 120, 20))
    check presentation.isSome
    check presentation.get.sourceContentBounds(styles.styles[root.nodeIndex]) ==
      rect(40, 40, 120, 20)

  test "content-box transforms use resolved percentage padding":
    var style = initialComputedStyle()
    style.transform.transformBox = tboxContentBox

    check transformReferenceBounds(
      rect(10, 20, 200, 100), style, edges(10, 20, 30, 40)
    ) == rect(50, 30, 140, 60)

  test "pixel spacing keeps the cold sizing extension unallocated":
    let context = styleContext([
      decl("padding", px(12)),
      decl("margin-left", px(-4))
    ])
    var diagnostics: Diagnostics
    let style = resolveStyles(
      context, defaultProperties(), ResolveEnv(), diagnostics
    )

    check not diagnostics.hasErrors
    check style.layout.sizing.isNil
    check style.box.padding == some(edges(12))
    check style.box.margin.get.left == -4

  test "negative percentage padding clamps but margin remains signed":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [
        decl("width", px(200)),
        decl("height", px(100)),
        decl("padding-left", percent(-10))
      ]),
      rule(target(child), [
        decl("width", px(40)),
        decl("height", px(20)),
        decl("margin-left", percent(-10))
      ])
    ])
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(tree, [sheet], defaultProperties(), diagnostics)
    let layout = computeLayout(tree, styles, size(200, 100))

    check not diagnostics.hasErrors
    check layout.boxFor(root).padding.left == 0
    check layout.rectFor(child).x == -20
