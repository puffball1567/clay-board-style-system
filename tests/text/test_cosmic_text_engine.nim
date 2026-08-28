import std/[options, strutils, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties
import clay_board_style_system/text/cosmic_text_engine

suite "cosmic text engine":
  test "reports usable ascent and descent through the bridge":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let metrics = cosmic.textEngine().textBaselineMetrics(TextFontMetricsInput(
      style: ComputedTextStyle(
        fontSize: some(20.0'f32),
        lineHeight: some(28.0'f32),
        fontFamilies: @["sans-serif"]
      ),
      fonts: fonts
    ))

    check metrics.ascent > 0
    check metrics.descent >= 0
    check metrics.ascent + metrics.descent > 0

  test "reports font-relative metrics through the versioned bridge":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let style = ComputedTextStyle(
      fontSize: some(20.0'f32),
      fontFamilies: @["sans-serif"]
    )
    let metrics = engine.fontMetrics(TextFontMetricsInput(
      style: style,
      fonts: fonts
    ))
    let zero = engine.measure(TextMeasureInput(
      text: "0",
      style: style,
      maxWidth: none(float32),
      fonts: fonts
    ))

    check metrics.version == fontUnitMetricsVersion
    check metrics.xHeight > 0
    check metrics.xHeight <= 20
    check metrics.zeroAdvance > 0
    check abs(metrics.zeroAdvance - zero.w) < 0.01

  test "resolves ex and ch with the installed cosmic-text metrics provider":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let style = ComputedTextStyle(
      fontSize: some(20.0'f32),
      fontFamilies: @["sans-serif"]
    )
    let metrics = engine.fontMetrics(TextFontMetricsInput(
      style: style,
      fonts: fonts
    ))
    var tree = initTree()
    let root = tree.addBox(id = "root")
    let sheet = styleSheet([rule(target(root), [
      decl("font-size", px(20)),
      decl("font-family", keyword("sans-serif")),
      decl("width", ex(2)),
      decl("height", ch(3))
    ])])
    var diagnostics: Diagnostics
    let resolved = resolveTreeStyles(
      tree,
      [sheet],
      defaultProperties(),
      diagnostics,
      fontMetricsResolver = engine.fontMetricsResolver(fonts)
    )

    check not diagnostics.hasErrors
    check abs(resolved.styles[root.nodeIndex].layout.width.get -
      metrics.xHeight * 2) < 0.01
    check abs(resolved.styles[root.nodeIndex].layout.height.get -
      metrics.zeroAdvance * 3) < 0.01

  test "measures text through cosmic-text bridge":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let baseStyle = ComputedTextStyle(
      fontSize: some(18.0'f32),
      lineHeight: some(24.0'f32),
      fontWeight: some(700.0'f32),
      fontStyle: some(fsItalic),
      fontStretch: some(100.0'f32),
      fontFamilies: @["sans-serif"],
      fontFeatureSettings: some("kern 1, liga 1")
    )
    let measured = engine.measure(TextMeasureInput(
      text: "Hello cosmic text",
      style: baseStyle,
      maxWidth: none(float32),
      fonts: fonts
    ))

    check measured.w > 0
    check measured.h >= 24

  test "letter-spacing is passed to cosmic-text":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let baseStyle = ComputedTextStyle(
      fontSize: some(18.0'f32),
      lineHeight: some(24.0'f32),
      fontFamilies: @["sans-serif"]
    )
    var spacedStyle = baseStyle
    spacedStyle.letterSpacing = some(4.0'f32)

    let normal = engine.measure(TextMeasureInput(
      text: "Spacing",
      style: baseStyle,
      maxWidth: none(float32),
      fonts: fonts
    ))
    let spaced = engine.measure(TextMeasureInput(
      text: "Spacing",
      style: spacedStyle,
      maxWidth: none(float32),
      fonts: fonts
    ))

    check spaced.w > normal.w

  test "word-spacing drives cosmic measurement caret hit and wrapping":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let baseStyle = ComputedTextStyle(
      fontSize: some(18.0'f32),
      lineHeight: some(24.0'f32),
      fontFamilies: @["sans-serif"]
    )
    var spacedStyle = baseStyle
    spacedStyle.wordSpacing = some(12.0'f32)
    let text = "alpha beta"
    let normal = engine.measure(TextMeasureInput(
      text: text,
      style: baseStyle,
      maxWidth: none(float32),
      fonts: fonts
    ))
    let spaced = engine.measure(TextMeasureInput(
      text: text,
      style: spacedStyle,
      maxWidth: none(float32),
      fonts: fonts
    ))
    let caret = engine.caret(TextCaretInput(
      text: text,
      style: spacedStyle,
      maxWidth: none(float32),
      fonts: fonts,
      byteIndex: 6
    ))
    let hit = engine.hit(TextHitInput(
      text: text,
      style: spacedStyle,
      maxWidth: none(float32),
      fonts: fonts,
      point: caret.position
    ))
    let wrapped = engine.measure(TextMeasureInput(
      text: text,
      style: spacedStyle,
      maxWidth: some(normal.w + 1.0'f32),
      fonts: fonts
    ))

    check spaced.w > normal.w + 8.0'f32
    check caret.position.x > 0.0'f32
    check hit.byteIndex in 5 .. 6
    check wrapped.h >= 48.0'f32

  test "renders text bitmap through cosmic-text bridge":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let bitmap = cosmic.renderCosmicTextBitmap(TextMeasureInput(
      text: "Bitmap",
      style: ComputedTextStyle(
        fontSize: some(20.0'f32),
        lineHeight: some(26.0'f32),
        fontFamilies: @["sans-serif"]
      ),
      maxWidth: none(float32),
      fonts: fonts
    ))

    check bitmap.isSome
    check bitmap.get.width > 0
    check bitmap.get.height > 0
    check bitmap.get.pixels.len == bitmap.get.width * bitmap.get.height * 4
    var alphaPixels = 0
    for index in countup(3, bitmap.get.pixels.high, 4):
      if bitmap.get.pixels[index] > 0:
        inc alphaPixels
    check alphaPixels > 0

  test "renders maximum textarea-sized multiline input without overflow":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let text = repeat("line\n", 3_000)[0 ..< maxPasteEventBytes]
    let bitmap = cosmic.renderCosmicTextBitmap(TextMeasureInput(
      text: text,
      style: ComputedTextStyle(
        fontSize: some(12.0'f32),
        lineHeight: some(16.0'f32),
        fontFamilies: @["sans-serif"],
        whiteSpace: some(wsPreWrap)
      ),
      maxWidth: some(190.0'f32),
      fonts: fonts
    ))

    check bitmap.isSome
    check bitmap.get.width > 0
    check bitmap.get.height > 16_000
    check bitmap.get.pixels.len == bitmap.get.width * bitmap.get.height * 4

    let visible = cosmic.renderCosmicTextBitmapRegion(
      TextMeasureInput(
        text: text,
        style: ComputedTextStyle(
          fontSize: some(12.0'f32),
          lineHeight: some(16.0'f32),
          fontFamilies: @["sans-serif"],
          whiteSpace: some(wsPreWrap)
        ),
        maxWidth: some(190.0'f32),
        fonts: fonts
      ),
      regionTop = 8_000,
      regionHeight = 96
    )
    check visible.isSome
    check visible.get.height <= 128
    check visible.get.offsetY >= 7_980

  test "anywhere wrap breaks long unspaced text":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let style = ComputedTextStyle(
      fontSize: some(16.0'f32),
      lineHeight: some(22.0'f32),
      fontFamilies: @["sans-serif"],
      overflowWrap: some(owAnywhere)
    )
    let measured = engine.measure(TextMeasureInput(
      text: "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz",
      style: style,
      maxWidth: some(90.0'f32),
      fonts: fonts
    ))
    let bitmap = cosmic.renderCosmicTextBitmap(TextMeasureInput(
      text: "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz",
      style: style,
      maxWidth: some(90.0'f32),
      fonts: fonts
    ))

    check measured.w <= 92.0'f32
    check measured.h >= 44.0'f32
    check bitmap.isSome
    check bitmap.get.height >= 30

  test "preformatted text preserves width instead of soft wrapping":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let baseStyle = ComputedTextStyle(
      fontSize: some(16.0'f32),
      lineHeight: some(22.0'f32),
      fontFamilies: @["sans-serif"]
    )
    var preStyle = baseStyle
    preStyle.whiteSpace = some(wsPre)
    let wrapped = engine.measure(TextMeasureInput(
      text: "alpha beta gamma delta",
      style: baseStyle,
      maxWidth: some(40.0'f32),
      fonts: fonts
    ))
    let preserved = engine.measure(TextMeasureInput(
      text: "alpha beta gamma delta",
      style: preStyle,
      maxWidth: some(40.0'f32),
      fonts: fonts
    ))

    check wrapped.h > 22.0'f32
    check preserved.h <= 22.0'f32
    check preserved.w > 40.0'f32

  test "font size adjust affects cosmic-text measurement":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let baseStyle = ComputedTextStyle(
      fontSize: some(20.0'f32),
      lineHeight: some(28.0'f32),
      fontFamilies: @["sans-serif"]
    )
    var adjustedStyle = baseStyle
    adjustedStyle.fontSizeAdjust = some(1.4'f32)

    let normal = engine.measure(TextMeasureInput(
      text: "Adjust",
      style: baseStyle,
      maxWidth: none(float32),
      fonts: fonts
    ))
    let adjusted = engine.measure(TextMeasureInput(
      text: "Adjust",
      style: adjustedStyle,
      maxWidth: none(float32),
      fonts: fonts
    ))

    check adjusted.w > normal.w

  test "caret position and hit test use cosmic-text layout":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let style = ComputedTextStyle(
      fontSize: some(20.0'f32),
      lineHeight: some(28.0'f32),
      fontFamilies: @["sans-serif"]
    )
    let caret = engine.caret(TextCaretInput(
      text: "Hello",
      style: style,
      maxWidth: none(float32),
      fonts: fonts,
      byteIndex: 2
    ))
    let hit = engine.hit(TextHitInput(
      text: "Hello",
      style: style,
      maxWidth: none(float32),
      fonts: fonts,
      point: caret.position
    ))

    check caret.height == 28.0'f32
    check caret.position.x > 0
    check hit.byteIndex <= 2

  test "caret at end of trailing-newline text lands on the empty final line":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let style = ComputedTextStyle(
      fontSize: some(12.0'f32),
      lineHeight: some(16.0'f32),
      fontFamilies: @["sans-serif"],
      whiteSpace: some(wsPreWrap)
    )
    let text = "first line\nsecond line\n"
    let caret = engine.caret(TextCaretInput(
      text: text,
      style: style,
      maxWidth: some(242.0'f32),
      fonts: fonts,
      byteIndex: text.len
    ))

    check caret.position.x == 0.0'f32
    check caret.position.y == 32.0'f32

  test "ellipsis fits the measured Cosmic Text width":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let style = ComputedTextStyle(
      fontSize: some(18.0'f32),
      lineHeight: some(24.0'f32),
      fontFamilies: @["sans-serif"],
      whiteSpace: some(wsNoWrap),
      textOverflow: some(toEllipsis)
    )
    let input = TextMeasureInput(
      text: "Clay Board Style System",
      style: style,
      maxWidth: some(96.0'f32),
      fonts: fonts
    )
    let visible = engine.textWithOverflow(input)
    let measured = engine.measure(TextMeasureInput(
      text: visible,
      style: style,
      maxWidth: none(float32),
      fonts: fonts
    ))

    check visible.len < input.text.len
    check visible.endsWith("…")
    check measured.w <= input.maxWidth.get

  test "text indent shifts only the first explicit line through cosmic-text":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let style = ComputedTextStyle(
      fontSize: some(18.0'f32),
      lineHeight: some(24.0'f32),
      fontFamilies: @["sans-serif"],
      textIndent: some(20.0'f32),
      whiteSpace: some(wsPreWrap)
    )
    let input = TextMeasureInput(
      text: "first\nsecond",
      style: style,
      maxWidth: none(float32),
      fonts: fonts
    )
    let samples = engine.carets(input)
    let first = engine.caret(TextCaretInput(
      text: input.text,
      style: style,
      maxWidth: input.maxWidth,
      fonts: fonts,
      byteIndex: 0
    ))
    let second = engine.caret(TextCaretInput(
      text: input.text,
      style: style,
      maxWidth: input.maxWidth,
      fonts: fonts,
      byteIndex: 6
    ))
    let beforeIndent = engine.hit(TextHitInput(
      text: input.text,
      style: style,
      maxWidth: input.maxWidth,
      fonts: fonts,
      point: vec2(0, 0)
    ))

    check samples.len > 2
    check abs(first.position.x - 20.0'f32) < 0.01
    check first.position.y == 0.0'f32
    check abs(second.position.x) < 0.01
    check abs(second.position.y - 24.0'f32) < 0.01
    check beforeIndent.byteIndex == 0
    check abs(beforeIndent.position.x - 20.0'f32) < 0.01

  test "wrapped text indent reduces only the first visual line":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let style = ComputedTextStyle(
      fontSize: some(18.0'f32),
      lineHeight: some(24.0'f32),
      fontFamilies: @["sans-serif"],
      textIndent: some(24.0'f32),
      overflowWrap: some(owAnywhere)
    )
    let input = TextMeasureInput(
      text: "abcdefghijklmno",
      style: style,
      maxWidth: some(80.0'f32),
      fonts: fonts
    )
    let measured = engine.measure(input)
    let samples = engine.carets(input)
    var firstWrapped = none(TextCaretSample)
    for sample in samples:
      if sample.position.y >= 23.9'f32:
        firstWrapped = some(sample)
        break

    check measured.w <= 80.1'f32
    check measured.h >= 48.0'f32
    check abs(samples[0].position.x - 24.0'f32) < 0.01
    check firstWrapped.isSome
    check abs(firstWrapped.get.position.x) < 0.01

  test "text indent is part of shaping and bitmap cache identity":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let baseStyle = ComputedTextStyle(
      fontSize: some(20.0'f32),
      lineHeight: some(26.0'f32),
      fontFamilies: @["sans-serif"]
    )
    var indentedStyle = baseStyle
    indentedStyle.textIndent = some(18.0'f32)
    let normalInput = TextMeasureInput(
      text: "Cache",
      style: baseStyle,
      maxWidth: none(float32),
      fonts: fonts
    )
    let indentedInput = TextMeasureInput(
      text: "Cache",
      style: indentedStyle,
      maxWidth: none(float32),
      fonts: fonts
    )
    let normal = engine.measure(normalInput)
    let indented = engine.measure(indentedInput)
    let normalBitmap = cosmic.renderCosmicTextBitmap(normalInput)
    let indentedBitmap = cosmic.renderCosmicTextBitmap(indentedInput)

    check abs((indented.w - normal.w) - 18.0'f32) < 0.1
    check normalBitmap.isSome
    check indentedBitmap.isSome
    check indentedBitmap.get.offsetX - normalBitmap.get.offsetX >= 17

  test "negative text indent keeps caret and bitmap left overflow":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let style = ComputedTextStyle(
      fontSize: some(20.0'f32),
      lineHeight: some(26.0'f32),
      fontFamilies: @["sans-serif"],
      textIndent: some(-12.0'f32)
    )
    let input = TextMeasureInput(
      text: "Hanging",
      style: style,
      maxWidth: none(float32),
      fonts: fonts
    )
    let caret = engine.caret(TextCaretInput(
      text: input.text,
      style: style,
      maxWidth: input.maxWidth,
      fonts: fonts,
      byteIndex: 0
    ))
    let bitmap = cosmic.renderCosmicTextBitmap(input)

    check abs(caret.position.x + 12.0'f32) < 0.01
    check bitmap.isSome
    check bitmap.get.offsetX < 0

  test "indented empty lines preserve caret origin and line height":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let style = ComputedTextStyle(
      fontSize: some(18.0'f32),
      lineHeight: some(24.0'f32),
      fontFamilies: @["sans-serif"],
      textIndent: some(20.0'f32),
      whiteSpace: some(wsPreWrap)
    )
    let input = TextMeasureInput(
      text: "\n",
      style: style,
      maxWidth: none(float32),
      fonts: fonts
    )
    let measured = engine.measure(input)
    let samples = engine.carets(input)

    check measured == size(0, 48)
    check samples.len == 2
    check samples[0].byteIndex == 0
    check samples[0].position == vec2(20, 0)
    check samples[1].byteIndex == 1
    check samples[1].position == vec2(0, 24)

  test "text alignment drives Cosmic caret and hit geometry":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let baseStyle = ComputedTextStyle(
      fontSize: some(18.0'f32),
      lineHeight: some(24.0'f32),
      fontFamilies: @["sans-serif"]
    )
    let intrinsic = engine.measure(TextMeasureInput(
      text: "Align",
      style: baseStyle,
      maxWidth: none(float32),
      fonts: fonts
    )).w
    var centeredStyle = baseStyle
    centeredStyle.textAlign = some(taCenter)
    let centeredInput = TextMeasureInput(
      text: "Align",
      style: centeredStyle,
      maxWidth: some(160.0'f32),
      fonts: fonts
    )
    let first = engine.caret(TextCaretInput(
      text: centeredInput.text,
      style: centeredStyle,
      maxWidth: centeredInput.maxWidth,
      fonts: fonts,
      byteIndex: 0
    ))
    let hit = engine.hit(TextHitInput(
      text: centeredInput.text,
      style: centeredStyle,
      maxWidth: centeredInput.maxWidth,
      fonts: fonts,
      point: vec2(first.position.x, 0)
    ))

    check abs(first.position.x - (160.0'f32 - intrinsic) * 0.5'f32) < 0.2
    check hit.byteIndex == 0
    check abs(hit.position.x - first.position.x) < 0.01

  test "right alignment and text indent share the first-line content area":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let engine = cosmic.textEngine()
    let baseStyle = ComputedTextStyle(
      fontSize: some(18.0'f32),
      lineHeight: some(24.0'f32),
      fontFamilies: @["sans-serif"]
    )
    let intrinsic = engine.measure(TextMeasureInput(
      text: "Right",
      style: baseStyle,
      maxWidth: none(float32),
      fonts: fonts
    )).w
    var style = baseStyle
    style.textAlign = some(taRight)
    style.textIndent = some(20.0'f32)
    let caret = engine.caret(TextCaretInput(
      text: "Right",
      style: style,
      maxWidth: some(180.0'f32),
      fonts: fonts,
      byteIndex: 0
    ))

    check abs(caret.position.x - (180.0'f32 - intrinsic)) < 0.2

  test "text alignment participates in shaping and bitmap cache identity":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    let baseStyle = ComputedTextStyle(
      fontSize: some(20.0'f32),
      lineHeight: some(26.0'f32),
      fontFamilies: @["sans-serif"]
    )
    var rightStyle = baseStyle
    rightStyle.textAlign = some(taRight)
    let baseInput = TextMeasureInput(
      text: "Cache",
      style: baseStyle,
      maxWidth: some(160.0'f32),
      fonts: fonts
    )
    let rightInput = TextMeasureInput(
      text: "Cache",
      style: rightStyle,
      maxWidth: some(160.0'f32),
      fonts: fonts
    )
    let baseBitmap = cosmic.renderCosmicTextBitmap(baseInput)
    let rightBitmap = cosmic.renderCosmicTextBitmap(rightInput)

    check baseInput.cosmicTextRasterKey != rightInput.cosmicTextRasterKey
    check baseBitmap.isSome
    check rightBitmap.isSome
    check rightBitmap.get.offsetX > baseBitmap.get.offsetX

  test "alignment without a width keeps Cosmic intrinsic coordinates":
    var fonts = initFontRegistry()
    var cosmic = initCosmicTextEngine(fonts)
    defer:
      cosmic.close()

    var style = ComputedTextStyle(
      fontSize: some(18.0'f32),
      lineHeight: some(24.0'f32),
      fontFamilies: @["sans-serif"],
      textAlign: some(taCenter)
    )
    let caret = cosmic.textEngine().caret(TextCaretInput(
      text: "Intrinsic",
      style: style,
      maxWidth: none(float32),
      fonts: fonts,
      byteIndex: 0
    ))

    check abs(caret.position.x) < 0.01
