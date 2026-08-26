import std/[math, options, unicode, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc overflowStyle(
    overflow = some(toEllipsis);
    whiteSpace = some(wsNoWrap)
): ComputedTextStyle =
  ComputedTextStyle(
    lineHeight: some(10.0'f32),
    textOverflow: overflow,
    whiteSpace: whiteSpace
  )

proc visibleText(
    engine: TextEngine;
    text: string;
    style: ComputedTextStyle;
    width: Option[float32]
): string =
  engine.textWithOverflow(TextMeasureInput(
    text: text,
    style: style,
    maxWidth: width,
    fonts: initFontRegistry()
  ))

suite "text overflow runtime":
  test "ellipsis replaces the overflowing suffix":
    check debugTextEngine().visibleText(
      "abcdef", overflowStyle(), some(32.0'f32)
    ) == "abc…"

  test "text that fits is not rewritten":
    check debugTextEngine().visibleText(
      "abcd", overflowStyle(), some(32.0'f32)
    ) == "abcd"

  test "clip and missing width preserve the source text":
    let engine = debugTextEngine()
    check engine.visibleText(
      "abcdef", overflowStyle(overflow = some(toClip)), some(16.0'f32)
    ) == "abcdef"
    check engine.visibleText(
      "abcdef", overflowStyle(), none(float32)
    ) == "abcdef"

  test "soft wrapping does not collapse a paragraph into one ellipsized line":
    check debugTextEngine().visibleText(
      "alpha beta", overflowStyle(whiteSpace = some(wsNormal)), some(32.0'f32)
    ) == "alpha beta"

  test "text-wrap nowrap enables ellipsis without white-space nowrap":
    var style = overflowStyle(whiteSpace = none(WhiteSpace))
    style.textWrap = some(twNoWrap)

    check debugTextEngine().visibleText(
      "abcdef", style, some(32.0'f32)
    ) == "abc…"

  test "a marker that cannot fit produces no visible text":
    let engine = debugTextEngine()
    check engine.visibleText("abcdef", overflowStyle(), some(0.0'f32)) == ""
    check engine.visibleText("abcdef", overflowStyle(), some(7.0'f32)) == ""

  test "non-finite widths have deterministic overflow behavior":
    let engine = debugTextEngine()
    check engine.visibleText(
      "abcdef", overflowStyle(), some(NaN.float32)
    ) == ""
    check engine.visibleText(
      "abcdef", overflowStyle(), some(Inf.float32)
    ) == "abcdef"

  test "ellipsis never splits a UTF-8 rune":
    let visible = debugTextEngine().visibleText(
      "日本語", overflowStyle(), some(16.0'f32)
    )

    check visible == "日…"
    check visible.runeLen == 2

  test "explicit lines are ellipsized independently":
    check debugTextEngine().visibleText(
      "abcd\nef", overflowStyle(), some(24.0'f32)
    ) == "ab…\nef"

  test "letter spacing participates in the fit decision":
    var style = overflowStyle()
    style.letterSpacing = some(2.0'f32)

    check debugTextEngine().visibleText(
      "abcdef", style, some(38.0'f32)
    ) == "abc…"

  test "layout retains an ellipsized paint string without mutating the node":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "abcdef", id = "label")
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([
        rule(target(label), [
          decl("width", px(32)),
          decl("line-height", px(10)),
          decl("white-space", keyword("nowrap")),
          decl("text-overflow", keyword("ellipsis"))
        ])
      ])],
      defaultProperties(),
      diagnostics
    )

    check not diagnostics.hasErrors
    let layout = computeLayout(tree, styles, size(100, 100))
    let boxIndex = layout.layoutBoxIndices(tree.nodes.len).boxIndexFor(label)
    check boxIndex >= 0
    check layout.paintTextFor(layout.boxes[boxIndex]) == some("abc…")
    check tree.nodes[label.nodeIndex].text == "abcdef"

    let commands = buildPaintCommands(tree, styles, layout)
    var painted = ""
    for command in commands:
      if command.kind == pcDrawText and command.node == label:
        painted = command.text
        break
    check painted == "abc…"

  test "layout avoids retained paint text when no truncation is needed":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "abc", id = "label")
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([
        rule(target(label), [
          decl("width", px(32)),
          decl("white-space", keyword("nowrap")),
          decl("text-overflow", keyword("ellipsis"))
        ])
      ])],
      defaultProperties(),
      diagnostics
    )

    check not diagnostics.hasErrors
    let layout = computeLayout(tree, styles, size(100, 100))
    let boxIndex = layout.layoutBoxIndices(tree.nodes.len).boxIndexFor(label)
    check layout.paintTextFor(layout.boxes[boxIndex]).isNone

  test "subtree relayout replaces sparse paint text without corrupting siblings":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let first = tree.addText(root, "abcdef", id = "first")
    let second = tree.addText(root, "uvwxyz", id = "second")
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([
        rule(target(first), [
          decl("width", px(32)),
          decl("white-space", keyword("nowrap")),
          decl("text-overflow", keyword("ellipsis"))
        ]),
        rule(target(second), [
          decl("width", px(32)),
          decl("white-space", keyword("nowrap")),
          decl("text-overflow", keyword("ellipsis"))
        ])
      ])],
      defaultProperties(),
      diagnostics
    )
    var layout = computeLayout(tree, styles, size(100, 100))

    tree.nodes[first.nodeIndex].text = "a"
    check relayoutSubtree(tree, styles, first, layout)
    let indices = layout.layoutBoxIndices(tree.nodes.len)
    check layout.paintTextFor(layout.boxes[indices.boxIndexFor(first)]).isNone
    check layout.paintTextFor(layout.boxes[indices.boxIndexFor(second)]) ==
      some("uvw…")

    tree.nodes[first.nodeIndex].text = "123456"
    check relayoutSubtree(tree, styles, first, layout)
    let updated = layout.layoutBoxIndices(tree.nodes.len)
    check layout.paintTextFor(layout.boxes[updated.boxIndexFor(first)]) ==
      some("123…")
    check layout.paintTextFor(layout.boxes[updated.boxIndexFor(second)]) ==
      some("uvw…")

  test "flex descendant reflow preserves the sparse overflow result":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "abcdef", id = "label")
    let spacer = tree.addBox(some(root), id = "spacer")
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([
        rule(target(root), [
          decl("width", px(64)),
          decl("flex-direction", keyword("row"))
        ]),
        rule(target(label), [
          decl("flex-grow", number(1)),
          decl("flex-shrink", number(1)),
          decl("flex-basis", px(0)),
          decl("min-width", px(0)),
          decl("white-space", keyword("nowrap")),
          decl("text-overflow", keyword("ellipsis"))
        ]),
        rule(target(spacer), [decl("width", px(32))])
      ])],
      defaultProperties(),
      diagnostics
    )

    check not diagnostics.hasErrors
    let layout = computeLayout(tree, styles, size(100, 100))
    let boxIndex = layout.layoutBoxIndices(tree.nodes.len).boxIndexFor(label)
    check layout.boxes[boxIndex].rect.w == 32
    check layout.paintTextFor(layout.boxes[boxIndex]) == some("abc…")
