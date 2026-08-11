import std/[options, strutils]
import ../core/[computed_style, geometry, property]
import ./font_registry

type
  TextFontMetricsInput* = object
    style*: ComputedTextStyle
    fonts*: FontRegistry

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

  TextEngine* = object
    measureText*: TextMeasureProc
    caretPosition*: TextCaretProc
    hitTestText*: TextHitProc
    layoutCarets*: TextCaretLayoutProc
    fontUnitMetrics*: TextFontMetricsProc

proc measure*(engine: TextEngine; input: TextMeasureInput): Size =
  engine.measureText(input)

proc caret*(engine: TextEngine; input: TextCaretInput): TextCaretResult =
  engine.caretPosition(input)

proc hit*(engine: TextEngine; input: TextHitInput): TextCaretResult =
  engine.hitTestText(input)

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

proc nextRuneEnd(text: string; caret: int): int

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
  engine.layoutCarets(input)

proc debugMeasureText*(input: TextMeasureInput): Size =
  let lineHeight =
    if input.style.lineHeight.isSome: input.style.lineHeight.get
    else: 8.0'f32
  let letterSpacing =
    if input.style.letterSpacing.isSome: input.style.letterSpacing.get
    else: 0.0'f32
  var lines = input.text.splitLines()
  if lines.len == 0:
    lines = @[""]
  var maxWidth = 0.0'f32
  for line in lines:
    let extraSpacing =
      if line.len > 1: (line.len - 1).float32 * letterSpacing
      else: 0.0'f32
    maxWidth = max(maxWidth, line.len.float32 * 8.0'f32 + extraSpacing)
  size(maxWidth, max(1, lines.len).float32 * lineHeight)

proc lineHeightOf(style: ComputedTextStyle): float32 =
  if style.lineHeight.isSome: style.lineHeight.get
  elif style.fontSize.isSome: style.fontSize.get * 1.2'f32
  else: 16.0'f32 * 1.2'f32

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
  let lineHeight = input.style.lineHeightOf()
  let stop = min(max(input.byteIndex, 0), input.text.len)
  var line = 0
  var column = 0
  var index = 0
  while index < stop:
    if input.text[index] == '\n':
      inc line
      column = 0
      inc index
    else:
      inc column
      index = input.text.nextRuneEnd(index)
  TextCaretResult(position: vec2(column.float32 * 8.0'f32, line.float32 * lineHeight), height: lineHeight, byteIndex: stop)

proc byteIndexAtDebugPoint(text: string; point: Vec2; lineHeight: float32): int =
  let targetLine = max(0, int(point.y / max(1.0'f32, lineHeight)))
  let targetColumn = max(0, int((point.x + 4.0'f32) / 8.0'f32))
  var line = 0
  var column = 0
  var index = 0
  while index < text.len:
    if line == targetLine and column >= targetColumn:
      return index
    if text[index] == '\n':
      if line == targetLine:
        return index
      inc line
      column = 0
      inc index
    else:
      inc column
      index = text.nextRuneEnd(index)
  text.len

proc debugHitText*(input: TextHitInput): TextCaretResult =
  let lineHeight = input.style.lineHeightOf()
  let byteIndex = input.text.byteIndexAtDebugPoint(input.point, lineHeight)
  debugCaretPosition(TextCaretInput(
    text: input.text,
    style: input.style,
    maxWidth: input.maxWidth,
    fonts: input.fonts,
    byteIndex: byteIndex
  ))

proc debugFontUnitMetrics(input: TextFontMetricsInput): FontUnitMetrics =
  fallbackFontUnitMetrics(input.style.fontSize.get(16.0'f32))

proc debugTextEngine*(): TextEngine =
  TextEngine(
    measureText: debugMeasureText,
    caretPosition: debugCaretPosition,
    hitTestText: debugHitText,
    fontUnitMetrics: debugFontUnitMetrics,
    layoutCarets: proc(input: TextMeasureInput): seq[TextCaretSample] =
      let lineHeight = input.style.lineHeightOf()
      var index = 0
      var line = 0
      var column = 0
      while true:
        result.add TextCaretSample(
          byteIndex: index,
          position: vec2(column.float32 * 8.0'f32, line.float32 * lineHeight),
          height: lineHeight
        )
        if index >= input.text.len:
          break
        if input.text[index] == '\n':
          inc line
          column = 0
          inc index
          continue
        inc column
        let next = input.text.nextRuneEnd(index)
        if next <= index:
          break
        index = next
  )
