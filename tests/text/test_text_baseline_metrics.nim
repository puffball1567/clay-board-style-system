import std/[options, unittest]

import clay_board_style_system

suite "text baseline metrics":
  test "fallback metrics use the em box and half leading":
    let engine = TextEngine()
    let baseline = engine.firstLineBaseline(TextFontMetricsInput(
      style: ComputedTextStyle(
        fontSize: some(20.0'f32),
        lineHeight: some(30.0'f32)
      ),
      fonts: initFontRegistry()
    ))

    check baseline == 21.0'f32

  test "a text engine can provide font-specific ascent and descent":
    let engine = TextEngine(
      baselineMetrics: proc(
          input: TextFontMetricsInput
      ): TextBaselineMetrics =
        check input.style.fontSize == some(20.0'f32)
        TextBaselineMetrics(ascent: 15, descent: 5)
    )
    let baseline = engine.firstLineBaseline(TextFontMetricsInput(
      style: ComputedTextStyle(
        fontSize: some(20.0'f32),
        lineHeight: some(24.0'f32)
      ),
      fonts: initFontRegistry()
    ))

    check baseline == 17.0'f32

  test "invalid provider metrics fall back independently":
    let engine = TextEngine(
      baselineMetrics: proc(
          input: TextFontMetricsInput
      ): TextBaselineMetrics =
        TextBaselineMetrics(ascent: -1, descent: -1)
    )
    let metrics = engine.textBaselineMetrics(TextFontMetricsInput(
      style: ComputedTextStyle(fontSize: some(10.0'f32)),
      fonts: initFontRegistry()
    ))

    check metrics.ascent == 8.0'f32
    check metrics.descent == 2.0'f32

  test "font-size-adjust participates in fallback baseline metrics":
    let metrics = fallbackTextBaselineMetrics(ComputedTextStyle(
      fontSize: some(10.0'f32),
      fontSizeAdjust: some(1.5'f32)
    ))

    check metrics.ascent == 12.0'f32
    check metrics.descent == 3.0'f32
