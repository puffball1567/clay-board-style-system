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
