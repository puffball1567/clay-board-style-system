import std/[math, options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc testMetrics(style: ComputedTextStyle): FontUnitMetrics =
  let fontSize = style.fontSize.get(16.0'f32)
  let familyFactor =
    if style.fontFamily == some("Wide"): 0.75'f32
    else: 0.6'f32
  FontUnitMetrics(
    version: fontUnitMetricsContractVersion,
    xHeight: fontSize * familyFactor,
    zeroAdvance: fontSize * 0.8'f32
  )

suite "font-metric-relative unit resolution":
  test "constructors append stable public unit ordinals":
    check ord(ukRlh) == 16
    check ord(ukEx) == 17
    check ord(ukCh) == 18
    check ord(ukRex) == 19
    check ord(ukRch) == 20
    check ex(2).length == LengthValue(kind: ukEx, value: 2)
    check ch(3).length == LengthValue(kind: ukCh, value: 3)
    check rex(4).length == LengthValue(kind: ukRex, value: 4)
    check rch(5).length == LengthValue(kind: ukRch, value: 5)

  test "default resolver follows CSS half-em fallback":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [
        decl("font-size", px(20)),
        decl("width", ex(2)),
        decl("height", ch(3))
      ]),
      rule(target(child), [
        decl("font-size", px(10)),
        decl("width", rex(2)),
        decl("height", rch(3))
      ])
    ])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree, [sheet], defaultProperties(), diagnostics
    )

    check not diagnostics.hasErrors
    check resolved.styles[root.nodeIndex].layout.width == some(20.0'f32)
    check resolved.styles[root.nodeIndex].layout.height == some(30.0'f32)
    check resolved.styles[child.nodeIndex].layout.width == some(20.0'f32)
    check resolved.styles[child.nodeIndex].layout.height == some(30.0'f32)

  test "provider receives current font selection and roots remain stable":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [
        decl("font-size", px(20)),
        decl("font-family", keyword("Wide")),
        decl("width", ex(2))
      ]),
      rule(target(child), [
        decl("font-size", ex(2)),
        decl("font-family", keyword("Narrow")),
        decl("width", ex(2)),
        decl("height", rex(1)),
        decl("min-width", rch(1))
      ])
    ])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree,
      [sheet],
      defaultProperties(),
      diagnostics,
      fontMetricsResolver = testMetrics
    )

    check not diagnostics.hasErrors
    check abs(resolved.styles[root.nodeIndex].layout.width.get - 30) < 0.001
    check abs(resolved.styles[child.nodeIndex].text.fontSize.get - 30) < 0.001
    check abs(resolved.styles[child.nodeIndex].layout.width.get - 36) < 0.001
    check abs(resolved.styles[child.nodeIndex].layout.height.get - 15) < 0.001
    check abs(resolved.styles[child.nodeIndex].layout.minWidth.get - 16) < 0.001

  test "ex and ch in line-height use current element metrics":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [decl("font-size", px(20))]),
      rule(target(child), [
        decl("font-size", px(10)),
        decl("line-height", ch(2)),
        decl("height", lh(1))
      ])
    ])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree,
      [sheet],
      defaultProperties(),
      diagnostics,
      fontMetricsResolver = testMetrics
    )

    check not diagnostics.hasErrors
    check resolved.styles[child.nodeIndex].text.lineHeight == some(16.0'f32)
    check resolved.styles[child.nodeIndex].layout.height == some(16.0'f32)

  test "invalid provider results fall back independently":
    let invalid = proc(style: ComputedTextStyle): FontUnitMetrics =
      FontUnitMetrics(
        version: fontUnitMetricsContractVersion,
        xHeight: NaN.float32,
        zeroAdvance: Inf.float32
      )
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let sheet = styleSheet([rule(target(root), [
      decl("font-size", px(18)),
      decl("width", ex(2)),
      decl("height", ch(2))
    ])])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree,
      [sheet],
      defaultProperties(),
      diagnostics,
      fontMetricsResolver = invalid
    )

    check not diagnostics.hasErrors
    check resolved.styles[root.nodeIndex].layout.width == some(18.0'f32)
    check resolved.styles[root.nodeIndex].layout.height == some(18.0'f32)

  test "standalone resolution diagnoses missing font metric contexts":
    let context = styleContext([
      decl("width", ex(1)),
      decl("height", ch(1)),
      decl("min-width", rex(1)),
      decl("min-height", rch(1))
    ])
    var diagnostics: Diagnostics
    let style = resolveStyles(
      context, defaultProperties(), ResolveEnv(), diagnostics
    )

    check diagnostics.hasErrors
    check diagnostics.items.len == 4
    check style.layout.width.isNone
    check style.layout.height.isNone
    check style.layout.minWidth.isNone
    check style.layout.minHeight.isNone

  test "subtree resolution reuses root and parent font metrics":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let child = tree.addBox(parent = some(root), id = "child")
    let sheet = styleSheet([
      rule(target(root), [
        decl("font-size", px(20)),
        decl("font-family", keyword("Wide"))
      ]),
      rule(target(child), [
        decl("font-size", px(10)),
        decl("width", ex(1)),
        decl("height", rex(1))
      ])
    ])
    var diagnostics: Diagnostics
    var resolved = resolveTreeStyles(
      tree,
      [sheet],
      defaultProperties(),
      diagnostics,
      fontMetricsResolver = testMetrics
    )

    check resolveSubtreeStyles(
      tree,
      child,
      [sheet],
      defaultProperties(),
      diagnostics,
      resolved,
      fontMetricsResolver = testMetrics
    )
    check not diagnostics.hasErrors
    check abs(resolved.styles[child.nodeIndex].layout.width.get - 7.5) < 0.001
    check abs(resolved.styles[child.nodeIndex].layout.height.get - 15) < 0.001

  test "subtree resolution rejects a tree without an attached root":
    var tree = initTree()
    let detached = NodeId(0)
    tree.nodes.add Node(kind: nkBox)
    var diagnostics: Diagnostics
    var resolved = ResolvedTree(styles: newSeq[ComputedStyle](1))

    check not resolveSubtreeStyles(
      tree,
      detached,
      [],
      defaultProperties(),
      diagnostics,
      resolved,
      fontMetricsResolver = testMetrics
    )
