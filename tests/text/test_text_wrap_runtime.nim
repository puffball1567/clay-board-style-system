import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

proc textStyle(
    whiteSpace = none(WhiteSpace);
    textWrap = none(TextWrap);
    overflowWrap = none(OverflowWrap);
    wordBreak = none(WordBreak)
): ComputedTextStyle =
  ComputedTextStyle(
    lineHeight: some(10.0'f32),
    whiteSpace: whiteSpace,
    textWrap: textWrap,
    overflowWrap: overflowWrap,
    wordBreak: wordBreak
  )

proc measure(
    engine: TextEngine;
    text: string;
    style: ComputedTextStyle;
    width: Option[float32]
): Size =
  engine.measure(TextMeasureInput(
    text: text,
    style: style,
    maxWidth: width,
    fonts: initFontRegistry()
  ))

suite "text wrapping runtime":
  test "normal wrapping moves a complete word to the next line":
    let measured = debugTextEngine().measure(
      "alpha beta", textStyle(), some(40.0'f32)
    )

    check measured == size(40, 20)

  test "nowrap and pre preserve an overflowing line":
    let engine = debugTextEngine()
    let noWrap = engine.measure(
      "abcdef", textStyle(textWrap = some(twNoWrap)), some(16.0'f32)
    )
    let pre = engine.measure(
      "abcdef", textStyle(whiteSpace = some(wsPre)), some(16.0'f32)
    )

    check noWrap == size(48, 10)
    check pre == size(48, 10)

  test "nowrap still preserves explicit line breaks":
    let measured = debugTextEngine().measure(
      "ab\ncd", textStyle(textWrap = some(twNoWrap)), some(8.0'f32)
    )

    check measured == size(16, 20)

  test "empty text and a non-positive width retain one empty line":
    let engine = debugTextEngine()
    let style = textStyle(overflowWrap = some(owAnywhere))

    check engine.measure("", style, some(8.0'f32)) == size(0, 10)
    check engine.measure("abc", style, some(0.0'f32)) == size(24, 10)
    check engine.measure("abc", style, some(-1.0'f32)) == size(24, 10)

    let samples = engine.carets(TextMeasureInput(
      text: "",
      style: style,
      maxWidth: some(8.0'f32),
      fonts: initFontRegistry()
    ))
    check samples.len == 1
    check samples[0].byteIndex == 0
    check samples[0].position == vec2(0, 0)

  test "overflow anywhere and break-all wrap at rune boundaries":
    let engine = debugTextEngine()
    let anywhere = engine.measure(
      "abcdef",
      textStyle(overflowWrap = some(owAnywhere)),
      some(16.0'f32)
    )
    let breakAll = engine.measure(
      "abcdef",
      textStyle(wordBreak = some(wbBreakAll)),
      some(16.0'f32)
    )

    check anywhere == size(16, 30)
    check breakAll == anywhere

  test "multibyte text wraps by Unicode rune instead of UTF-8 byte":
    let engine = debugTextEngine()
    let style = textStyle(overflowWrap = some(owAnywhere))
    let measured = engine.measure("日本語", style, some(8.0'f32))
    let samples = engine.carets(TextMeasureInput(
      text: "日本語",
      style: style,
      maxWidth: some(8.0'f32),
      fonts: initFontRegistry()
    ))

    check measured == size(8, 30)
    check samples.len == 4
    check samples[0].byteIndex == 0
    check samples[1].byteIndex == 3
    check samples[1].position == vec2(0, 10)
    check samples[2].byteIndex == 6
    check samples[2].position == vec2(0, 20)
    check samples[3].byteIndex == 9
    check samples[3].position == vec2(8, 20)

  test "caret and hit testing use the same wrapped lines":
    let engine = debugTextEngine()
    let style = textStyle(overflowWrap = some(owAnywhere))
    let caret = engine.caret(TextCaretInput(
      text: "日本語",
      style: style,
      maxWidth: some(8.0'f32),
      fonts: initFontRegistry(),
      byteIndex: 6
    ))
    let hit = engine.hit(TextHitInput(
      text: "日本語",
      style: style,
      maxWidth: some(8.0'f32),
      fonts: initFontRegistry(),
      point: vec2(1, 11)
    ))

    check caret.byteIndex == 6
    check caret.position == vec2(0, 20)
    check hit.byteIndex == 3
    check hit.position == vec2(0, 10)

  test "hit testing clamps points outside wrapped text":
    let engine = debugTextEngine()
    let style = textStyle(overflowWrap = some(owAnywhere))
    let before = engine.hit(TextHitInput(
      text: "abcd",
      style: style,
      maxWidth: some(16.0'f32),
      fonts: initFontRegistry(),
      point: vec2(-100, -100)
    ))
    let after = engine.hit(TextHitInput(
      text: "abcd",
      style: style,
      maxWidth: some(16.0'f32),
      fonts: initFontRegistry(),
      point: vec2(100, 100)
    ))

    check before.byteIndex == 0
    check before.position == vec2(0, 0)
    check after.byteIndex == 4
    check after.position == vec2(16, 10)

  test "letter and word spacing participate in reference measurement":
    var style = textStyle()
    style.letterSpacing = some(1.0'f32)
    style.wordSpacing = some(4.0'f32)

    check debugTextEngine().measure("a b", style, none(float32)) ==
      size(30, 10)

  test "word spacing also applies to non-breaking spaces":
    var style = textStyle()
    style.wordSpacing = some(4.0'f32)

    check debugTextEngine().measure("a\u00a0b", style, none(float32)) ==
      size(28, 10)

  test "display transformations retain rune based wrapping":
    var style = textStyle(overflowWrap = some(owAnywhere))
    style.textTransform = some(ttUppercase)

    check debugTextEngine().measure("aıx", style, some(8.0'f32)) ==
      size(8, 30)

  test "layout height executes overflow-wrap without changing source text":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "abcdef", id = "label")
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([
        rule(target(label), [
          decl("width", px(16)),
          decl("line-height", px(10)),
          decl("overflow-wrap", keyword("anywhere"))
        ])
      ])],
      defaultProperties(),
      diagnostics
    )

    check not diagnostics.hasErrors
    let layout = computeLayout(tree, styles, size(100, 100))
    let indices = layout.layoutBoxIndices(tree.nodes.len)
    let boxIndex = indices.boxIndexFor(label)
    check boxIndex >= 0
    check layout.boxes[boxIndex].rect == rect(0, 0, 16, 30)
    check tree.nodes[label.nodeIndex].text == "abcdef"

  test "word-wrap alias and word-break execute through resolved styles":
    for propertyName in ["word-wrap", "word-break"]:
      var tree = initTree()
      let root = tree.addBox(id = "root")
      let label = tree.addText(root, "abcdef", id = "label")
      var diagnostics: Diagnostics
      let styles = resolveTreeStyles(
        tree,
        [styleSheet([
          rule(target(label), [
            decl("width", px(16)),
            decl("line-height", px(10)),
            decl(propertyName,
              keyword(if propertyName == "word-wrap": "anywhere" else: "break-all"))
          ])
        ])],
        defaultProperties(),
        diagnostics
      )

      check not diagnostics.hasErrors
      let layout = computeLayout(tree, styles, size(100, 100))
      let boxIndex = layout.layoutBoxIndices(tree.nodes.len).boxIndexFor(label)
      check layout.boxes[boxIndex].rect == rect(0, 0, 16, 30)

  test "text-wrap nowrap executes through resolved styles":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "abcdef", id = "label")
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([
        rule(target(label), [
          decl("width", px(16)),
          decl("line-height", px(10)),
          decl("text-wrap", keyword("nowrap"))
        ])
      ])],
      defaultProperties(),
      diagnostics
    )

    check not diagnostics.hasErrors
    let layout = computeLayout(tree, styles, size(100, 100))
    let boxIndex = layout.layoutBoxIndices(tree.nodes.len).boxIndexFor(label)
    check layout.boxes[boxIndex].rect == rect(0, 0, 16, 10)
