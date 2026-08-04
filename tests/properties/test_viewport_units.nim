import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties
import clay_board_style_system/testing/test_driver

suite "viewport-relative unit resolution":
  test "public unit ordinals preserve the existing C ABI":
    check ord(ukPx) == 0
    check ord(ukNone) == 10
    check ord(ukVw) == 11
    check ord(ukVh) == 12
    check ord(ukVmin) == 13
    check ord(ukVmax) == 14

  test "constructors retain typed viewport-relative intent":
    check vw(12.5).length == LengthValue(kind: ukVw, value: 12.5)
    check vh(25).length == LengthValue(kind: ukVh, value: 25)
    check vmin(2).length == LengthValue(kind: ukVmin, value: 2)
    check vmax(3).length == LengthValue(kind: ukVmax, value: 3)

  test "one viewport context resolves layout box text and transform values":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let sheet = styleSheet([rule(target(root), [
      decl("font-size", vmin(2)),
      decl("width", vw(50)),
      decl("height", vh(20)),
      decl("min-width", vmin(10)),
      decl("max-height", vmax(30)),
      decl("padding", em(2)),
      decl("margin-top", rem(1.5)),
      decl("gap", vmax(1)),
      decl("flex-basis", vmin(20)),
      decl("position", keyword("relative")),
      decl("left", vw(5)),
      decl("transform", transformValue(translate(vw(10), vh(10))))
    ])])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree,
      [sheet],
      defaultProperties(),
      diagnostics,
      viewportSize = some(size(1000, 500))
    )
    let style = resolved.styles[root.nodeIndex]

    check not diagnostics.hasErrors
    check style.text.fontSize == some(10.0'f32)
    check style.layout.width == some(500.0'f32)
    check style.layout.height == some(100.0'f32)
    check style.layout.minWidth == some(50.0'f32)
    check style.layout.maxHeight == some(300.0'f32)
    check style.box.padding == some(edges(20))
    check style.box.margin.get.top == 15
    check style.layout.gap == 10
    check style.layout.flexBasis == some(100.0'f32)
    check style.layout.inset.left == some(50.0'f32)
    check style.transform.operations.len == 1
    check style.transform.operations[0].xLength == some(
      ComputedLength(kind: cukPx, value: 100)
    )
    check style.transform.operations[0].yLength == some(
      ComputedLength(kind: cukPx, value: 50)
    )

  test "viewport resize deterministically re-resolves values":
    let ui = initUiRoot()
    let panel = ui.box(style = uiStyle([
      decl("width", vw(50)),
      decl("height", vh(25)),
      decl("padding", vmin(2))
    ]))
    let driver = initCbssTestDriver(ui, size(800, 600))

    check driver.styles.styles[panel.nodeId.nodeIndex].layout.width ==
      some(400.0'f32)
    check driver.styles.styles[panel.nodeId.nodeIndex].layout.height ==
      some(150.0'f32)
    check driver.styles.styles[panel.nodeId.nodeIndex].box.padding ==
      some(edges(12))

    driver.setViewport(size(1200, 400))

    check driver.styles.styles[panel.nodeId.nodeIndex].layout.width ==
      some(600.0'f32)
    check driver.styles.styles[panel.nodeId.nodeIndex].layout.height ==
      some(100.0'f32)
    check driver.styles.styles[panel.nodeId.nodeIndex].box.padding ==
      some(edges(8))

  test "subtree resolution retains the full resolution viewport":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([rule(target(child), [
      decl("width", vw(25)),
      decl("height", vh(10))
    ])])
    var diagnostics: Diagnostics
    var resolved = resolveTreeStyles(
      tree,
      [sheet],
      defaultProperties(),
      diagnostics,
      viewportSize = some(size(800, 600))
    )

    check resolveSubtreeStyles(
      tree, child, [sheet], defaultProperties(), diagnostics, resolved
    )
    check not diagnostics.hasErrors
    check resolved.styles[child.nodeIndex].layout.width == some(200.0'f32)
    check resolved.styles[child.nodeIndex].layout.height == some(60.0'f32)

  test "viewport-relative values require an explicit viewport":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let sheet = styleSheet([rule(target(root), [
      decl("width", vw(50)),
      decl("padding", vh(2)),
      decl("font-size", vmin(3))
    ])])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree, [sheet], defaultProperties(), diagnostics
    )

    check diagnostics.hasErrors
    check diagnostics.items.len == 3
    check resolved.styles[root.nodeIndex].layout.width.isNone
    check resolved.styles[root.nodeIndex].box.padding.isNone
    check resolved.styles[root.nodeIndex].text.fontSize == some(16.0'f32)

  test "font-relative dimensions normalize after font inheritance":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [decl("font-size", px(20))]),
      rule(target(child), [
        decl("width", em(3)),
        decl("height", rem(2)),
        decl("column-gap", em(0.5))
      ])
    ])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree,
      [sheet],
      defaultProperties(),
      diagnostics,
      viewportSize = some(size(800, 600))
    )
    let style = resolved.styles[child.nodeIndex]

    check not diagnostics.hasErrors
    check style.layout.width == some(60.0'f32)
    check style.layout.height == some(40.0'f32)
    check style.layout.columnGap == some(10.0'f32)

  test "viewport units cover absolute-length property families":
    let context = styleContext([
      decl("border-width", vw(1)),
      decl("border-radius", vmin(2)),
      decl("box-shadow", shadowValue(
        offsetX = vw(1),
        offsetY = vh(2),
        blur = some(vmin(1)),
        spread = some(vmax(0.5)),
        shadowColor = some(rgba(0, 0, 0, 0.5))
      )),
      decl("outline-width", vmin(0.5)),
      decl("outline-offset", vmax(1)),
      decl("background-size", vw(25)),
      decl("background-position-x", vh(3)),
      decl("column-width", vw(20)),
      decl("column-height", vh(30)),
      decl("column-rule-width", vmin(1)),
      decl("line-height", vh(4)),
      decl("letter-spacing", vw(0.25)),
      decl("word-spacing", vmin(1)),
      decl("text-decoration-thickness", vmax(0.5)),
      decl("text-indent", vw(4)),
      decl("text-shadow", shadowValue(
        offsetX = vw(0.5),
        offsetY = vh(1),
        blur = some(vmin(0.5)),
        spread = some(vmax(0.25))
      )),
      decl("tab-size", vmin(2)),
      decl("stroke-width", vw(1)),
      decl("x", vh(5)),
      decl("overflow-clip-margin", vmax(1))
    ])
    var diagnostics: Diagnostics
    let style = resolveStyles(
      context,
      defaultProperties(),
      ResolveEnv(viewportSize: some(size(1000, 500))),
      diagnostics
    )

    check not diagnostics.hasErrors
    check style.box.borderWidth == 10
    check style.box.borderRadius == 10
    check style.box.boxShadow.get.offsetX == 10
    check style.box.boxShadow.get.offsetY == 10
    check style.box.boxShadow.get.blur == 5
    check style.box.boxShadow.get.spread == 5
    check style.box.outlineWidth == 2.5
    check style.box.outlineOffset == 10
    check style.box.backgroundSize.get.width == some(250.0'f32)
    check style.box.backgroundPosition.x == 15
    check style.columns.columnWidth == some(200.0'f32)
    check style.columns.columnHeight == some(150.0'f32)
    check style.columns.columnRuleWidth == some(5.0'f32)
    check style.text.lineHeight == some(20.0'f32)
    check style.text.letterSpacing == some(2.5'f32)
    check style.text.wordSpacing == some(5.0'f32)
    check style.text.textDecorationThickness == some(5.0'f32)
    check style.text.textIndent == some(40.0'f32)
    check style.text.textShadow.get.offsetX == 5
    check style.text.textShadow.get.offsetY == 5
    check style.text.textShadow.get.blur == 2.5
    check style.text.textShadow.get.spread == 2.5
    check style.text.tabSize == some(10.0'f32)
    check style.vector.strokeWidth == some(10.0'f32)
    check style.vector.x == some(25.0'f32)
    check style.visual.overflowClipMargin == some(10.0'f32)

  test "absolute-length properties reject percentages without a reference box":
    let context = styleContext([
      decl("border-width", percent(10)),
      decl("box-shadow", shadowValue(
        offsetX = percent(1),
        offsetY = px(2)
      )),
      decl("column-width", percent(20))
    ])
    var diagnostics: Diagnostics
    discard resolveStyles(
      context,
      defaultProperties(),
      ResolveEnv(viewportSize: some(size(1000, 500))),
      diagnostics
    )

    check diagnostics.hasErrors
    check diagnostics.items.len == 3
