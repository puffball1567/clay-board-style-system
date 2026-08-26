import std/[math, options, unicode]
import ../core/[computed_style, geometry, property]
import ./display_text
import ./font_registry

type
  TextFontMetricsInput* = object
    style*: ComputedTextStyle
    fonts*: FontRegistry

  TextBaselineMetrics* = object
    ascent*: float32
    descent*: float32

  TextMeasureInput* = object
    text*: string
    style*: ComputedTextStyle
    maxWidth*: Option[float32]
    fonts*: FontRegistry

  TextCaretInput* = object
    text*: string
    style*: ComputedTextStyle
    maxWidth*: Option[float32]
    fonts*: FontRegistry
    byteIndex*: int

  TextHitInput* = object
    text*: string
    style*: ComputedTextStyle
    maxWidth*: Option[float32]
    fonts*: FontRegistry
    point*: Vec2

  TextCaretResult* = object
    position*: Vec2
    height*: float32
    byteIndex*: int

  TextCaretSample* = object
    byteIndex*: int
    position*: Vec2
    height*: float32

  TextMeasureProc* = proc(input: TextMeasureInput): Size {.closure.}
  TextCaretProc* = proc(input: TextCaretInput): TextCaretResult {.closure.}
  TextHitProc* = proc(input: TextHitInput): TextCaretResult {.closure.}
  TextCaretLayoutProc* = proc(input: TextMeasureInput): seq[TextCaretSample] {.closure.}
  TextFontMetricsProc* = proc(input: TextFontMetricsInput): FontUnitMetrics {.closure.}
  TextBaselineMetricsProc* = proc(input: TextFontMetricsInput): TextBaselineMetrics {.closure.}

  TextEngine* = object
    measureText*: TextMeasureProc
    caretPosition*: TextCaretProc
    hitTestText*: TextHitProc
    layoutCarets*: TextCaretLayoutProc
    fontUnitMetrics*: TextFontMetricsProc
    baselineMetrics*: TextBaselineMetricsProc

proc measure*(engine: TextEngine; input: TextMeasureInput): Size =
  let mapping = displayTextTransform(input.text, input.style)
  var displayInput = input
  displayInput.text = mapping.text
  engine.measureText(displayInput)

proc caret*(engine: TextEngine; input: TextCaretInput): TextCaretResult =
  let mapping = displayTextTransform(input.text, input.style)
  var displayInput = input
  displayInput.text = mapping.text
  displayInput.byteIndex = mapping.displayByteIndex(input.byteIndex)
  result = engine.caretPosition(displayInput)
  result.byteIndex = mapping.sourceByteIndex(result.byteIndex)

proc hit*(engine: TextEngine; input: TextHitInput): TextCaretResult =
  let mapping = displayTextTransform(input.text, input.style)
  var displayInput = input
  displayInput.text = mapping.text
  result = engine.hitTestText(displayInput)
  result.byteIndex = mapping.sourceByteIndex(result.byteIndex)

const fontUnitMetricsVersion* = fontUnitMetricsContractVersion

proc fontMetrics*(
    engine: TextEngine;
    input: TextFontMetricsInput
): FontUnitMetrics =
  let fontSize = input.style.fontSize.get(16.0'f32)
  if engine.fontUnitMetrics.isNil:
    return fallbackFontUnitMetrics(fontSize)
  result = resolveFontUnitMetrics(
    proc(style: ComputedTextStyle): FontUnitMetrics =
      engine.fontUnitMetrics(TextFontMetricsInput(
        style: style,
        fonts: input.fonts
      )),
    input.style
  )

proc fontMetricsResolver*(
    engine: TextEngine;
    fonts: FontRegistry
): FontUnitMetricsResolver =
  proc(style: ComputedTextStyle): FontUnitMetrics =
    engine.fontMetrics(TextFontMetricsInput(style: style, fonts: fonts))

proc effectiveFontSize(style: ComputedTextStyle): float32 =
  let fontSize = style.fontSize.get(16.0'f32)
  if style.fontSizeAdjust.isSome:
    fontSize * max(0.1'f32, style.fontSizeAdjust.get)
  else:
    fontSize

proc fallbackTextBaselineMetrics*(style: ComputedTextStyle): TextBaselineMetrics =
  let fontSize = max(0.0'f32, style.effectiveFontSize())
  TextBaselineMetrics(
    ascent: fontSize * 0.8'f32,
    descent: fontSize * 0.2'f32
  )

proc textBaselineMetrics*(
    engine: TextEngine;
    input: TextFontMetricsInput
): TextBaselineMetrics =
  let fallback = fallbackTextBaselineMetrics(input.style)
  if engine.baselineMetrics.isNil:
    return fallback
  result = engine.baselineMetrics(input)
  if result.ascent.classify in {fcNan, fcInf, fcNegInf} or result.ascent < 0:
    result.ascent = fallback.ascent
  if result.descent.classify in {fcNan, fcInf, fcNegInf} or result.descent < 0:
    result.descent = fallback.descent
  if result.ascent + result.descent <= 0:
    result = fallback

proc firstLineBaseline*(
    engine: TextEngine;
    input: TextFontMetricsInput
): float32 =
  let metrics = engine.textBaselineMetrics(input)
  let lineHeight =
    if input.style.lineHeight.isSome: input.style.lineHeight.get
    else: input.style.effectiveFontSize() * 1.2'f32
  let halfLeading = (lineHeight - metrics.ascent - metrics.descent) * 0.5'f32
  halfLeading + metrics.ascent

proc nextRuneEnd(text: string; caret: int): int

proc suppressesSoftWrap(style: ComputedTextStyle): bool =
  (style.whiteSpace.isSome and style.whiteSpace.get in {wsNoWrap, wsPre}) or
    (style.textWrap.isSome and style.textWrap.get == twNoWrap)

proc measuredLineWidth(
    engine: TextEngine;
    text: string;
    input: TextMeasureInput
): float32 =
  engine.measure(TextMeasureInput(
    text: text,
    style: input.style,
    maxWidth: none(float32),
    fonts: input.fonts
  )).w

proc ellipsizeLine(
    engine: TextEngine;
    line: string;
    input: TextMeasureInput;
    maximumWidth: float32
): string =
  if line.len == 0 or engine.measuredLineWidth(line, input) <= maximumWidth:
    return line

  const marker = "…"
  if maximumWidth <= 0.0'f32 or
      engine.measuredLineWidth(marker, input) > maximumWidth:
    return ""

  var boundaries = @[0]
  var index = 0
  while index < line.len:
    index = line.nextRuneEnd(index)
    boundaries.add index

  var low = 0
  var high = boundaries.high
  while low < high:
    let middle = (low + high + 1) div 2
    let stop = boundaries[middle]
    let prefix = if stop > 0: line[0 ..< stop] else: ""
    if engine.measuredLineWidth(prefix & marker, input) <= maximumWidth:
      low = middle
    else:
      high = middle - 1

  let stop = boundaries[low]
  (if stop > 0: line[0 ..< stop] else: "") & marker

proc textWithOverflow*(engine: TextEngine; input: TextMeasureInput): string =
  ## Resolve the source string used by every paint backend. Ellipsis is a
  ## single-line overflow behavior; explicit newlines remain independent lines.
  if input.style.textOverflow.isNone or
      input.style.textOverflow.get != toEllipsis or
      not input.style.suppressesSoftWrap() or
      input.maxWidth.isNone:
    return input.text

  let maximumWidth = input.maxWidth.get
  case maximumWidth.classify
  of fcNan, fcNegInf:
    return ""
  of fcInf:
    return input.text
  else:
    discard
  var lineStart = 0
  while lineStart <= input.text.len:
    var lineEnd = lineStart
    while lineEnd < input.text.len and input.text[lineEnd] != '\n':
      inc lineEnd
    let line =
      if lineEnd > lineStart: input.text[lineStart ..< lineEnd]
      else: ""
    result.add engine.ellipsizeLine(line, input, maximumWidth)
    if lineEnd >= input.text.len:
      break
    result.add '\n'
    lineStart = lineEnd + 1

proc carets*(engine: TextEngine; input: TextMeasureInput): seq[TextCaretSample] =
  if engine.layoutCarets.isNil:
    var index = 0
    while true:
      let caret = engine.caret(TextCaretInput(
        text: input.text,
        style: input.style,
        maxWidth: input.maxWidth,
        fonts: input.fonts,
        byteIndex: index
      ))
      result.add TextCaretSample(byteIndex: index, position: caret.position, height: caret.height)
      if index >= input.text.len:
        break
      let next = input.text.nextRuneEnd(index)
      if next <= index:
        break
      index = next
    return
  let mapping = displayTextTransform(input.text, input.style)
  var displayInput = input
  displayInput.text = mapping.text
  result = engine.layoutCarets(displayInput)
  for sample in result.mitems:
    sample.byteIndex = mapping.sourceByteIndex(sample.byteIndex)

proc lineHeightOf(style: ComputedTextStyle): float32 =
  if style.lineHeight.isSome: style.lineHeight.get
  else: 8.0'f32

type
  DebugWrapKind = enum
    dwNone,
    dwWords,
    dwAnywhere

  DebugTextLayout = object
    samples: seq[TextCaretSample]
    measured: Size

proc debugWrapKind(style: ComputedTextStyle): DebugWrapKind =
  if style.whiteSpace.isSome and style.whiteSpace.get in {wsNoWrap, wsPre}:
    return dwNone
  if style.textWrap.isSome and style.textWrap.get == twNoWrap:
    return dwNone
  if style.whiteSpace.isSome and style.whiteSpace.get == wsBreakSpaces:
    return dwAnywhere
  if style.overflowWrap.isSome and
      style.overflowWrap.get in {owAnywhere, owBreakWord}:
    return dwAnywhere
  if style.wordBreak.isSome and
      style.wordBreak.get in {wbBreakAll, wbBreakWord}:
    return dwAnywhere
  dwWords

proc debugRuneAdvance(rune: Rune; style: ComputedTextStyle): float32 =
  result = 8.0'f32
  if rune.int32 in [9'i32, 32'i32]:
    result += style.wordSpacing.get(0.0'f32)
  result = max(0.0'f32, result)

proc isDebugWhitespace(rune: Rune): bool =
  rune.int32 in [9'i32, 13'i32, 32'i32]

proc debugWordWidth(
    text: string;
    start: int;
    style: ComputedTextStyle
): float32 =
  var index = start
  var glyphs = 0
  while index < text.len:
    let rune = text.runeAt(index)
    if rune.int32 == 10 or rune.isDebugWhitespace:
      break
    result += rune.debugRuneAdvance(style)
    inc glyphs
    index = text.nextRuneEnd(index)
  if glyphs > 1:
    result += (glyphs - 1).float32 * style.letterSpacing.get(0.0'f32)
  result = max(0.0'f32, result)

proc debugTextLayout(
    input: TextMeasureInput;
    collectSamples = true
): DebugTextLayout =
  let lineHeight = input.style.lineHeightOf()
  let wrapKind = input.style.debugWrapKind()
  let availableWidth = input.maxWidth.get(0.0'f32)
  let canWrap = wrapKind != dwNone and input.maxWidth.isSome and
    availableWidth > 0.0'f32
  var index = 0
  var x = 0.0'f32
  var y = 0.0'f32
  var line = 0
  var maximumWidth = 0.0'f32
  var startsWord = true
  var lineGlyphs = 0

  template visualLineWidth(): float32 =
    max(0.0'f32, x -
      (if lineGlyphs > 0: input.style.letterSpacing.get(0.0'f32)
       else: 0.0'f32))

  while index < input.text.len:
    let rune = input.text.runeAt(index)
    let next = input.text.nextRuneEnd(index)
    if rune.int32 == 10:
      x = visualLineWidth()
      if collectSamples:
        result.samples.add TextCaretSample(
          byteIndex: index,
          position: vec2(x, y),
          height: lineHeight
        )
      maximumWidth = max(maximumWidth, x)
      inc line
      x = 0.0'f32
      y = line.float32 * lineHeight
      startsWord = true
      lineGlyphs = 0
      index = next
      continue

    let whitespace = rune.isDebugWhitespace
    let advance = rune.debugRuneAdvance(input.style) +
      input.style.letterSpacing.get(0.0'f32)
    let prospectiveWidth = max(
      0.0'f32,
      x + advance - input.style.letterSpacing.get(0.0'f32)
    )
    var shouldWrap = false
    if canWrap and x > 0.0'f32:
      case wrapKind
      of dwNone:
        discard
      of dwAnywhere:
        shouldWrap = prospectiveWidth > availableWidth
      of dwWords:
        if not whitespace and startsWord:
          shouldWrap = x + debugWordWidth(
            input.text, index, input.style
          ) > availableWidth
        elif whitespace:
          shouldWrap = prospectiveWidth > availableWidth
    if shouldWrap:
      maximumWidth = max(maximumWidth, visualLineWidth())
      inc line
      x = 0.0'f32
      y = line.float32 * lineHeight
      lineGlyphs = 0

    if collectSamples:
      result.samples.add TextCaretSample(
        byteIndex: index,
        position: vec2(x, y),
        height: lineHeight
      )
    x += advance
    inc lineGlyphs
    startsWord = whitespace
    index = next

  x = visualLineWidth()
  if collectSamples:
    result.samples.add TextCaretSample(
      byteIndex: input.text.len,
      position: vec2(x, y),
      height: lineHeight
    )
  maximumWidth = max(maximumWidth, x)
  result.measured = size(maximumWidth, max(1, line + 1).float32 * lineHeight)

proc debugMeasureText*(input: TextMeasureInput): Size =
  debugTextLayout(input, collectSamples = false).measured

proc caretVisualMetrics*(style: ComputedTextStyle; lineHeight: float32): tuple[offset, height: float32] =
  ## Align a caret to the font em-box within its line box.
  let resolvedLineHeight = max(1.0'f32, lineHeight)
  let fontHeight =
    if style.fontSize.isSome:
      max(1.0'f32, min(resolvedLineHeight, style.fontSize.get))
    else:
      resolvedLineHeight
  (offset: max(0.0'f32, (resolvedLineHeight - fontHeight) * 0.5'f32), height: fontHeight)

proc nextRuneEnd(text: string; caret: int): int =
  result = caret + 1
  while result < text.len and (ord(text[result]) and 0b1100_0000) == 0b1000_0000:
    inc result
  if result > text.len:
    result = text.len

proc debugCaretPosition*(input: TextCaretInput): TextCaretResult =
  let stop = min(max(input.byteIndex, 0), input.text.len)
  let layout = debugTextLayout(TextMeasureInput(
    text: input.text,
    style: input.style,
    maxWidth: input.maxWidth,
    fonts: input.fonts
  ))
  var sample = layout.samples[0]
  for candidate in layout.samples:
    if candidate.byteIndex > stop:
      break
    sample = candidate
  TextCaretResult(
    position: sample.position,
    height: sample.height,
    byteIndex: sample.byteIndex
  )

proc debugHitText*(input: TextHitInput): TextCaretResult =
  let layout = debugTextLayout(TextMeasureInput(
    text: input.text,
    style: input.style,
    maxWidth: input.maxWidth,
    fonts: input.fonts
  ))
  let lineHeight = input.style.lineHeightOf()
  let lastLine = max(0, int(layout.measured.h / max(1.0'f32, lineHeight)) - 1)
  let targetLine = min(
    lastLine,
    max(0, int(input.point.y / max(1.0'f32, lineHeight)))
  )
  var first = 0
  var last = layout.samples.high
  for index, sample in layout.samples:
    let line = int(sample.position.y / max(1.0'f32, lineHeight))
    if line == targetLine:
      first = index
      break
  for index in countdown(layout.samples.high, first):
    let line = int(
      layout.samples[index].position.y / max(1.0'f32, lineHeight)
    )
    if line == targetLine:
      last = index
      break
  var chosen = layout.samples[first]
  for index in first .. last:
    chosen = layout.samples[index]
    if index == last:
      break
    let midpoint = (layout.samples[index].position.x +
      layout.samples[index + 1].position.x) * 0.5'f32
    if input.point.x < midpoint:
      break
  TextCaretResult(
    position: chosen.position,
    height: chosen.height,
    byteIndex: chosen.byteIndex
  )

proc debugFontUnitMetrics(input: TextFontMetricsInput): FontUnitMetrics =
  fallbackFontUnitMetrics(input.style.fontSize.get(16.0'f32))

proc debugBaselineMetrics(input: TextFontMetricsInput): TextBaselineMetrics =
  fallbackTextBaselineMetrics(input.style)

proc debugTextEngine*(): TextEngine =
  TextEngine(
    measureText: proc(input: TextMeasureInput): Size =
      debugTextLayout(input, collectSamples = false).measured,
    caretPosition: debugCaretPosition,
    hitTestText: debugHitText,
    fontUnitMetrics: debugFontUnitMetrics,
    baselineMetrics: debugBaselineMetrics,
    layoutCarets: proc(input: TextMeasureInput): seq[TextCaretSample] =
      debugTextLayout(input).samples
  )
