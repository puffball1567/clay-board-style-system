import std/[math, options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc indentStyle(
    indent: float32;
    overflowWrap = none(OverflowWrap);
    whiteSpace = none(WhiteSpace)
): ComputedTextStyle =
  ComputedTextStyle(
    fontSize: some(8.0'f32),
    lineHeight: some(10.0'f32),
    textIndent: some(indent),
    overflowWrap: overflowWrap,
    whiteSpace: whiteSpace
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

suite "text indent runtime":
  test "positive indentation shifts only the first authored line":
    let engine = debugTextEngine()
    let style = indentStyle(8)
    let samples = engine.carets(textInput("ab\ncd", style))

    check engine.measure(textInput("ab\ncd", style)) == size(24, 20)
    check samples[0].position == vec2(8, 0)
    check engine.caret(TextCaretInput(
      text: "ab\ncd",
      style: style,
      maxWidth: none(float32),
      fonts: initFontRegistry(),
      byteIndex: 3
    )).position == vec2(0, 10)

  test "indent participates in first-line wrapping and later lines use full width":
    let engine = debugTextEngine()
    let style = indentStyle(8, overflowWrap = some(owAnywhere))
    let input = textInput("abcd", style, some(16.0'f32))
    let samples = engine.carets(input)

    check engine.measure(input) == size(16, 30)
    check samples.len == 5
    check samples[0].position == vec2(8, 0)
    check samples[1].position == vec2(0, 10)
    check samples[2].position == vec2(8, 10)
    check samples[3].position == vec2(0, 20)
    check samples[4].position == vec2(8, 20)

  test "negative indentation exposes a hanging first line without shifting later lines":
    let engine = debugTextEngine()
    let style = indentStyle(-8, overflowWrap = some(owAnywhere))
    let input = textInput("abcd", style, some(16.0'f32))
    let samples = engine.carets(input)

    check engine.measure(input) == size(16, 20)
    check samples[0].position == vec2(-8, 0)
    check samples[3].position == vec2(0, 10)

  test "caret and hit testing share indented coordinates":
    let engine = debugTextEngine()
    let style = indentStyle(8, overflowWrap = some(owAnywhere))
    let caret = engine.caret(TextCaretInput(
      text: "日本語",
      style: style,
      maxWidth: some(16.0'f32),
      fonts: initFontRegistry(),
      byteIndex: 3
    ))
    let firstHit = engine.hit(TextHitInput(
      text: "日本語",
      style: style,
      maxWidth: some(16.0'f32),
      fonts: initFontRegistry(),
      point: vec2(8, 0)
    ))
    let secondHit = engine.hit(TextHitInput(
      text: "日本語",
      style: style,
      maxWidth: some(16.0'f32),
      fonts: initFontRegistry(),
      point: vec2(1, 11)
    ))

    check caret.position == vec2(0, 10)
    check firstHit.byteIndex == 0
    check firstHit.position == vec2(8, 0)
    check secondHit.byteIndex == 3
    check secondHit.position == vec2(0, 10)

  test "empty and non-finite indentation are deterministic":
    let engine = debugTextEngine()
    let emptyInput = textInput("", indentStyle(12))
    let emptySamples = engine.carets(emptyInput)

    check engine.measure(emptyInput) == size(0, 10)
    check emptySamples.len == 1
    check emptySamples[0].position == vec2(12, 0)
    for value in [NaN.float32, Inf.float32, NegInf.float32]:
      check engine.measure(textInput("ab", indentStyle(value))) == size(16, 10)

  test "ellipsis spends first-line width on indent only once":
    let engine = debugTextEngine()
    var style = indentStyle(8, whiteSpace = some(wsNoWrap))
    style.textOverflow = some(toEllipsis)

    check engine.textWithOverflow(textInput(
      "abcdef\nabcdef", style, some(32.0'f32)
    )) == "ab…\nabc…"

  test "resolved text-indent reaches layout and paint without mutating source text":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "abcd", id = "label")
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([rule(target(label), [
        decl("width", px(16)),
        decl("line-height", px(10)),
        decl("text-indent", px(8)),
        decl("overflow-wrap", keyword("anywhere"))
      ])])],
      defaultProperties(),
      diagnostics
    )

    check not diagnostics.hasErrors
    let layout = computeLayout(tree, styles, size(100, 100))
    let boxIndex = layout.layoutBoxIndices(tree.nodes.len).boxIndexFor(label)
    check boxIndex >= 0
    check layout.boxes[boxIndex].rect == rect(0, 0, 16, 30)
    check tree.nodes[label.nodeIndex].text == "abcd"

    let commands = buildPaintCommands(tree, styles, layout)
    var found = false
    for command in commands:
      if command.kind == pcDrawText and command.node == label:
        found = true
        check command.textStyle.textIndent == some(8.0'f32)
        break
    check found

  test "negative indent expands transform bounds to prevent clipping":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "abc", id = "label")
    let style = indentStyle(-8)
    var commands = @[
      pushTransform(identityAffine2D()),
      drawText(
        label, "abc", vec2(10, 20), rgb(1, 1, 1), style,
        maxWidth = some(100.0'f32)
      ),
      popTransform()
    ]

    commands.resolveTransformBounds()
    check commands[0].transformBounds == rect(2, 20, 108, 10)
