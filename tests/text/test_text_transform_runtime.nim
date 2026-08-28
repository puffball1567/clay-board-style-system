import std/unittest

import clay_board_style_system
import clay_board_style_system/generated/default_properties
import clay_board_style_system/text/display_text

proc resolvedTextStyle(transform: string): ComputedTextStyle =
  var tree = initTree()
  let root = tree.addBox(id = "root")
  let label = tree.addText(root, "source", id = "label")
  var diagnostics: Diagnostics
  let styles = resolveTreeStyles(
    tree,
    [styleSheet([
      rule(target(label), [decl("text-transform", keyword(transform))])
    ])],
    defaultProperties(),
    diagnostics
  )
  check not diagnostics.hasErrors
  styles.styles[label.nodeIndex].text

suite "text-transform runtime":
  test "uppercase and lowercase use Unicode simple case mapping":
    let uppercase = displayTextTransform(
      "héllo привет",
      resolvedTextStyle("uppercase")
    )
    let lowercase = displayTextTransform(
      "HÉLLO ПРИВЕТ",
      resolvedTextStyle("lowercase")
    )

    check uppercase.text == "HÉLLO ПРИВЕТ"
    check lowercase.text == "héllo привет"

  test "capitalize preserves apostrophes and combining marks inside words":
    let mapping = displayTextTransform(
      "hello-world don't e\u0301clair",
      resolvedTextStyle("capitalize")
    )

    check mapping.text == "Hello-World Don't E\u0301clair"

  test "none preserves the source without allocating an index map":
    let source = "Already Mixed"
    let mapping = displayTextTransform(source, ComputedTextStyle())

    check mapping.text == source
    check mapping.displayByteIndex(4) == 4
    check mapping.sourceByteIndex(4) == 4

  test "caret input and output map across changed UTF-8 byte widths":
    var receivedText = ""
    var receivedIndex = -1
    let engine = TextEngine(
      caretPosition: proc(input: TextCaretInput): TextCaretResult =
        receivedText = input.text
        receivedIndex = input.byteIndex
        TextCaretResult(
          position: vec2(input.byteIndex.float32, 0),
          height: 10,
          byteIndex: input.byteIndex
        )
    )
    let result = engine.caret(TextCaretInput(
      text: "aıx",
      style: resolvedTextStyle("uppercase"),
      fonts: initFontRegistry(),
      byteIndex: 3
    ))

    check receivedText == "AIX"
    check receivedIndex == 2
    check result.position.x == 2
    check result.byteIndex == 3

  test "hit results map from display bytes back to source bytes":
    let engine = TextEngine(
      hitTestText: proc(input: TextHitInput): TextCaretResult =
        check input.text == "AIX"
        TextCaretResult(position: vec2(2, 0), height: 10, byteIndex: 2)
    )
    let result = engine.hit(TextHitInput(
      text: "aıx",
      style: resolvedTextStyle("uppercase"),
      fonts: initFontRegistry(),
      point: vec2(2, 0)
    ))

    check result.byteIndex == 3

  test "custom caret layouts retain source byte boundaries":
    let engine = TextEngine(
      layoutCarets: proc(input: TextMeasureInput): seq[TextCaretSample] =
        check input.text == "AIX"
        @[
          TextCaretSample(byteIndex: 0, position: vec2(0, 0), height: 10),
          TextCaretSample(byteIndex: 1, position: vec2(1, 0), height: 10),
          TextCaretSample(byteIndex: 2, position: vec2(2, 0), height: 10),
          TextCaretSample(byteIndex: 3, position: vec2(3, 0), height: 10)
        ]
    )
    let samples = engine.carets(TextMeasureInput(
      text: "aıx",
      style: resolvedTextStyle("uppercase"),
      fonts: initFontRegistry()
    ))

    check samples.len == 4
    check samples[0].byteIndex == 0
    check samples[1].byteIndex == 1
    check samples[2].byteIndex == 3
    check samples[3].byteIndex == 4

  test "layout measures and paint draws the same transformed text":
    var measuredTexts: seq[string]
    let engine = TextEngine(
      measureText: proc(input: TextMeasureInput): Size =
        measuredTexts.add input.text
        size(input.text.len.float32 * 10, 12)
    )
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let label = tree.addText(root, "mixed case", id = "label")
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([
        rule(target(root), [decl("align-items", keyword("start"))]),
        rule(target(label), [decl("text-transform", keyword("uppercase"))])
      ])],
      defaultProperties(),
      diagnostics
    )

    check not diagnostics.hasErrors
    let layout = computeLayout(tree, styles, size(300, 80), engine)
    let commands = buildPaintCommands(tree, styles, layout)
    check measuredTexts.len > 0
    for text in measuredTexts:
      check text == "MIXED CASE"
    check tree.nodes[label.nodeIndex].text == "mixed case"
    check commands.len == 1
    check commands[0].kind == pcDrawText
    check commands[0].text == "MIXED CASE"

  test "max-lines is applied before the display transformation":
    var tree = initTree()
    let root = tree.addBox(id = "root")
    discard tree.addText(root, "one\ntwo\nthree", id = "label")
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(
      tree,
      [styleSheet([
        rule(id("label"), [
          decl("max-lines", keyword("2")),
          decl("text-transform", keyword("uppercase"))
        ])
      ])],
      defaultProperties(),
      diagnostics
    )

    check not diagnostics.hasErrors
    let layout = computeLayout(tree, styles, size(120, 60))
    let commands = buildPaintCommands(tree, styles, layout)
    check commands.len == 1
    check commands[0].text == "ONE\nTWO"
