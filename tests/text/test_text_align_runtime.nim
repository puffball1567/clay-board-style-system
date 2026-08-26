import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc alignStyle(
    alignment: TextAlign;
    indent = 0.0'f32;
    overflowWrap = none(OverflowWrap)
): ComputedTextStyle =
  ComputedTextStyle(
    fontSize: some(8.0'f32),
    lineHeight: some(10.0'f32),
    textAlign: some(alignment),
    textIndent: some(indent),
    overflowWrap: overflowWrap
  )

proc textInput(
    text: string;
    style: ComputedTextStyle;
    width = none(float32)
): TextMeasureInput =
  TextMeasureInput(
    text: text,
    style: style,
    maxWidth: width,
    fonts: initFontRegistry()
  )

suite "text align runtime":
  test "center and right align caret geometry inside the supplied width":
    let engine = debugTextEngine()
    let centered = textInput("ab", alignStyle(taCenter), some(40.0'f32))
    let right = textInput("ab", alignStyle(taRight), some(40.0'f32))

    check engine.measure(centered) == size(16, 10)
    check engine.carets(centered)[0].position == vec2(12, 0)
    check engine.carets(centered)[^1].position == vec2(28, 0)
    check engine.carets(right)[0].position == vec2(24, 0)
    check engine.carets(right)[^1].position == vec2(40, 0)

  test "start and end use the current horizontal LTR contract":
    let engine = debugTextEngine()
    let start = textInput("ab", alignStyle(taStart), some(40.0'f32))
    let finish = textInput("ab", alignStyle(taEnd), some(40.0'f32))

    check engine.carets(start)[0].position.x == 0
    check engine.carets(finish)[0].position.x == 24

  test "alignment without a supplied line width preserves intrinsic coordinates":
    let engine = debugTextEngine()
    for alignment in [taCenter, taRight, taEnd]:
      let samples = engine.carets(textInput("ab", alignStyle(alignment)))
      check samples[0].position == vec2(0, 0)
      check samples[^1].position == vec2(16, 0)

  test "each explicit and wrapped visual line aligns independently":
    let engine = debugTextEngine()
    let explicit = engine.carets(textInput(
      "a\nabc", alignStyle(taCenter), some(40.0'f32)
    ))
    let wrapped = engine.carets(textInput(
      "abcd",
      alignStyle(taCenter, overflowWrap = some(owAnywhere)),
      some(24.0'f32)
    ))

    check explicit[0].position == vec2(16, 0)
    check explicit[2].position == vec2(8, 10)
    check wrapped[0].position == vec2(0, 0)
    check wrapped[3].position == vec2(8, 10)
    check wrapped[^1].position == vec2(16, 10)

  test "text indent reduces the first-line alignment area":
    let engine = debugTextEngine()
    let centered = engine.carets(textInput(
      "ab", alignStyle(taCenter, indent = 8), some(40.0'f32)
    ))
    let right = engine.carets(textInput(
      "ab", alignStyle(taRight, indent = 8), some(40.0'f32)
    ))

    check centered[0].position == vec2(16, 0)
    check centered[^1].position == vec2(32, 0)
    check right[0].position == vec2(24, 0)
    check right[^1].position == vec2(40, 0)

  test "UTF-8 caret and hit testing share aligned coordinates":
    let engine = debugTextEngine()
    let style = alignStyle(taCenter)
    let caret = engine.caret(TextCaretInput(
      text: "日本",
      style: style,
      maxWidth: some(40.0'f32),
      fonts: initFontRegistry(),
      byteIndex: 3
    ))
    let hit = engine.hit(TextHitInput(
      text: "日本",
      style: style,
      maxWidth: some(40.0'f32),
      fonts: initFontRegistry(),
      point: vec2(21, 0)
    ))

    check caret.position == vec2(20, 0)
    check hit.byteIndex == 3
    check hit.position == vec2(20, 0)

  test "resolved text-align reaches layout and paint":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "ab", id = "label")
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([rule(target(label), [
        decl("width", px(40)),
        decl("line-height", px(10)),
        decl("text-align", keyword("right"))
      ])])],
      defaultProperties(),
      diagnostics
    )

    check not diagnostics.hasErrors
    check styles.styles[label.nodeIndex].text.textAlign == some(taRight)
    let layout = computeLayout(tree, styles, size(100, 100))
    let commands = buildPaintCommands(tree, styles, layout)
    var found = false
    for command in commands:
      if command.kind == pcDrawText and command.node == label:
        found = true
        check command.textMaxWidth == some(40.0'f32)
        check command.textStyle.textAlign == some(taRight)
    check found

  test "text-align-last remains separate from the executable alignment contract":
    let engine = debugTextEngine()
    var style = alignStyle(taLeft)
    style.textAlignLast = some(taRight)
    let samples = engine.carets(textInput("a\nb", style, some(40.0'f32)))

    check samples[0].position.x == 0
    check samples[2].position.x == 0
