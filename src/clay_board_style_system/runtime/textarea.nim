import std/[algorithm, options, strutils]

import ../core/[color, computed_style, declaration, geometry, node, rule, selector, style_value]
import ../input/events
import ../text/text_engine
import ./form
import ./ui_root

const textEdgeSlack = 2.0'f32
const initialSelectionFragmentCount = 24
const traceTextareaSelection = false
const maxUndoEntries = 64
const maxUndoBytes = 262_144
const defaultMaxTextAreaBytes = 8_192
const maxValueAttributeBytes = 8_192

type
  TextAreaCaretSample = tuple[index: int; x, y, height: float32]
  TextAreaVisualLine = tuple[samples: seq[TextAreaCaretSample]; y, height: float32]

  TextAreaScrollbarGeometry = object
    trackHeight: float32
    thumbTop: float32
    thumbHeight: float32
    maxScroll: float32

  TextAreaParams* = object
    value*: string
    placeholder*: string
    disabled*: bool
    readOnly*: bool
    maxLength*: Option[int]
    resize*: Option[ResizeKind]
    width*: Option[float32]
    height*: Option[float32]
    minWidth*: Option[float32]
    maxWidth*: Option[float32]
    minHeight*: Option[float32]
    maxHeight*: Option[float32]

  TextAreaState* = ref object
    value*: string
    caret*: int
    selectionStart*: int
    selectionEnd*: int
    composingText*: string
    composingActive*: bool
    compositionUpdateSeen*: bool
    lastCompositionUpdateText*: string
    placeholder*: string
    disabled*: bool
    readOnly*: bool
    maxLength*: Option[int]
    clipboardText*: string
    clipboardWriteRequested*: bool
    focused*: bool
    textNodeStyleDirty*: bool
    syncedTextScrollY*: float32
    pendingFallbackText*: string
    selecting*: bool
    undoStack*: seq[string]
    redoStack*: seq[string]
    resize*: ResizeKind
    width*: Option[float32]
    height*: Option[float32]
    minWidth*: Option[float32]
    maxWidth*: Option[float32]
    minHeight*: Option[float32]
    maxHeight*: Option[float32]
    resizing*: bool
    resizeStartPointer*: Vec2
    resizeStartWidth*: float32
    resizeStartHeight*: float32
    scrollbarVisible*: bool
    scrollbarDragging*: bool
    scrollbarDragStartY*: float32
    scrollbarDragStartScrollY*: float32
    textStyle*: ComputedTextStyle
    textMaxWidth*: Option[float32]
    textMaxWidthExplicit*: bool
    textHorizontalInset*: float32
    textVerticalInset*: float32
    textLeftInset*: float32
    textTopInset*: float32
    scrollY*: float32
    caretStyleIndex*: Option[int]
    textNodeStyleIndex*: Option[int]
    selectionStyleIndex*: Option[int]
    selectionVisible*: bool
    caretLinesDirty*: bool
    cachedCaretLines*: seq[TextAreaVisualLine]
    selectionNodes*: seq[NodeHandle]

  TextAreaHandle* = object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    selectionNode*: NodeHandle
    selectionNodes*: seq[NodeHandle]
    textNode*: NodeHandle
    caretNode*: NodeHandle
    scrollbarTrack*: NodeHandle
    scrollbarThumb*: NodeHandle
    resizeHandle*: NodeHandle
    state*: TextAreaState

proc register*(form: FormHandle; name: string; area: TextAreaHandle) =
  form.registerField(area.container, name, ffText)

proc displayText(state: TextAreaState): string =
  if state.value.len == 0 and
      state.composingText.len == 0 and
      not state.composingActive and
      state.placeholder.len > 0:
    return state.placeholder
  if state.composingText.len == 0:
    return state.value
  state.value[0 ..< state.caret] & state.composingText & state.value[state.caret .. ^1]

proc displayCaretIndex(state: TextAreaState): int =
  result = state.caret
  if state.composingText.len > 0:
    result += state.composingText.len

proc clampCaret(state: TextAreaState) =
  if state.caret < 0:
    state.caret = 0
  if state.caret > state.value.len:
    state.caret = state.value.len

proc clampSelection(state: TextAreaState) =
  if state.selectionStart < 0:
    state.selectionStart = 0
  if state.selectionStart > state.value.len:
    state.selectionStart = state.value.len
  if state.selectionEnd < 0:
    state.selectionEnd = 0
  if state.selectionEnd > state.value.len:
    state.selectionEnd = state.value.len

proc selectionBounds(state: TextAreaState): tuple[first, last: int] =
  state.clampSelection()
  if state.selectionStart <= state.selectionEnd:
    (state.selectionStart, state.selectionEnd)
  else:
    (state.selectionEnd, state.selectionStart)

proc hasSelection(state: TextAreaState): bool =
  let bounds = state.selectionBounds()
  bounds.first != bounds.last

proc collapseSelection(state: TextAreaState) =
  state.selectionStart = state.caret
  state.selectionEnd = state.caret

proc previousRuneStart(text: string; caret: int): int =
  result = caret - 1
  while result > 0 and (ord(text[result]) and 0b1100_0000) == 0b1000_0000:
    dec result
  if result < 0:
    result = 0

proc nextRuneEnd(text: string; caret: int): int =
  result = caret + 1
  while result < text.len and (ord(text[result]) and 0b1100_0000) == 0b1000_0000:
    inc result
  if result > text.len:
    result = text.len

proc wordByte(ch: char): bool =
  ch in {'a'..'z', 'A'..'Z', '0'..'9', '_'}

proc previousWordStart(text: string; caret: int): int =
  result = max(0, min(caret, text.len))
  while result > 0 and not text[result - 1].wordByte:
    dec result
  while result > 0 and text[result - 1].wordByte:
    dec result

proc nextWordEnd(text: string; caret: int): int =
  result = max(0, min(caret, text.len))
  while result < text.len and not text[result].wordByte:
    inc result
  while result < text.len and text[result].wordByte:
    inc result

proc truncateAtRuneBoundary(text: string; maxBytes: int): string =
  if maxBytes <= 0:
    return ""
  if text.len <= maxBytes:
    return text
  var stop = maxBytes
  while stop > 0 and (ord(text[stop]) and 0b1100_0000) == 0b1000_0000:
    dec stop
  text[0 ..< stop]

proc effectiveMaxLength(state: TextAreaState): int =
  if state.maxLength.isSome:
    min(state.maxLength.get, defaultMaxTextAreaBytes)
  else:
    defaultMaxTextAreaBytes

proc setValueAttribute(area: TextAreaHandle) =
  let value =
    if area.state.value.len <= maxValueAttributeBytes:
      area.state.value
    else:
      area.state.value.truncateAtRuneBoundary(maxValueAttributeBytes)
  area.root.tree.setAttribute(area.container.id, "value", value)
  area.container.setAccessibleValue(area.state.value)

proc syncCaretStyle(area: TextAreaHandle; lines: seq[TextAreaVisualLine])
proc syncCaretStyle(area: TextAreaHandle; caret: TextCaretResult)
proc syncSelectionStyle(area: TextAreaHandle; lines: seq[TextAreaVisualLine])
proc syncTextNodeStyle(area: TextAreaHandle)
proc syncScrollbarStyle(area: TextAreaHandle; lines: seq[TextAreaVisualLine])
proc ensureCaretVisible(area: TextAreaHandle; lines: seq[TextAreaVisualLine])
proc ensureCaretVisible(area: TextAreaHandle; caret: TextCaretResult)
proc hideSelectionStyle(area: TextAreaHandle)
proc setVisibleText(area: TextAreaHandle)
proc moveCaretTo(area: TextAreaHandle; caret: int; extendSelection = false; emitSelection = false)

proc traceSelection(message: string) =
  if traceTextareaSelection:
    echo "[textarea-select] ", message

proc markTextLayoutDirty(area: TextAreaHandle) =
  area.state.caretLinesDirty = true
  area.state.cachedCaretLines.setLen(0)

proc caretLines(area: TextAreaHandle): seq[TextAreaVisualLine] =
  if not area.state.caretLinesDirty:
    return area.state.cachedCaretLines
  area.state.cachedCaretLines.setLen(0)
  let samples = area.root.textEngine.carets(TextMeasureInput(
      text: area.state.value,
      style: area.state.textStyle,
      maxWidth: area.state.textMaxWidth,
      fonts: area.root.fonts
    ))
  for caret in samples:
    let sample: TextAreaCaretSample = (
      index: caret.byteIndex,
      x: caret.position.x,
      y: caret.position.y,
      height: max(1.0'f32, caret.height)
    )
    if area.state.cachedCaretLines.len == 0 or
        abs(area.state.cachedCaretLines[^1].y - sample.y) >
          max(1.0'f32, area.state.cachedCaretLines[^1].height * 0.25'f32):
      area.state.cachedCaretLines.add((samples: @[sample], y: sample.y, height: sample.height))
    else:
      area.state.cachedCaretLines[^1].samples.add sample
      area.state.cachedCaretLines[^1].height = max(area.state.cachedCaretLines[^1].height, sample.height)
  for line in area.state.cachedCaretLines.mitems:
    line.samples.sort(proc(a, b: TextAreaCaretSample): int =
      cmp(a.index, b.index)
    )
  area.state.caretLinesDirty = false
  area.state.cachedCaretLines

proc caretXAtOrAfter(samples: openArray[TextAreaCaretSample]; target: int): float32 =
  if samples.len == 0:
    return 0.0'f32
  for sample in samples:
    if sample.index >= target:
      return sample.x
  samples[^1].x

proc caretSampleAt(lines: openArray[TextAreaVisualLine]; target: int): TextAreaCaretSample =
  var fallback: Option[TextAreaCaretSample]
  for line in lines:
    for sample in line.samples:
      if fallback.isNone:
        fallback = some(sample)
      if sample.index >= target:
        return sample
      fallback = some(sample)
  if fallback.isSome:
    fallback.get
  else:
    (index: 0, x: 0.0'f32, y: 0.0'f32, height: 16.0'f32)

proc spaceAdvance(area: TextAreaHandle): float32 =
  let before = area.root.textEngine.caret(TextCaretInput(
    text: " ",
    style: area.state.textStyle,
    maxWidth: none(float32),
    fonts: area.root.fonts,
    byteIndex: 0
  ))
  let after = area.root.textEngine.caret(TextCaretInput(
    text: " ",
    style: area.state.textStyle,
    maxWidth: none(float32),
    fonts: area.root.fonts,
    byteIndex: 1
  ))
  max(3.0'f32, after.position.x - before.position.x)

proc selectedTrailingBlankWidth(
    area: TextAreaHandle;
    samples: openArray[TextAreaCaretSample];
    first, last: int;
    right: float32
): float32 =
  if last <= first:
    return 0.0'f32
  var cursor = last
  var blanks = 0.0'f32
  while cursor > first:
    let previous = previousRuneStart(area.state.value, cursor)
    if previous < 0 or previous >= cursor:
      break
    let glyph = area.state.value[previous ..< cursor]
    if glyph == " ":
      blanks += 1.0'f32
    elif glyph == "\t":
      blanks += 4.0'f32
    else:
      break
    cursor = previous
  if blanks <= 0.0'f32:
    return 0.0'f32

  let beforeBlanksX = caretXAtOrAfter(samples, cursor)
  if right - beforeBlanksX > 0.5'f32:
    return 0.0'f32
  blanks * area.spaceAdvance()

proc addSelectionNode(area: TextAreaHandle): NodeHandle =
  result = area.root.box(parent = some(area.container), groups = ["textarea-selection"])
  result.applyStyle(uiStyle([
    decl("display", keyword("none")),
    decl("position", keyword("absolute")),
    decl("left", px(0)),
    decl("top", px(0)),
    decl("width", px(0)),
    decl("height", px(0)),
    decl("background-color", colorValue(rgba(0.18, 0.48, 0.78, 0.42))),
    decl("border-radius", px(2)),
    decl("pointer-events", keyword("none"))
  ]))
  area.state.selectionNodes.add result

proc ensureSelectionNodes(area: TextAreaHandle; count: int) =
  while area.state.selectionNodes.len < count:
    discard area.addSelectionNode()

proc emitValueEvents(area: TextAreaHandle) =
  discard area.container.emit(inputEvent(area.state.value))
  discard area.container.emit(changeEvent(area.state.value))

proc emitSelect(area: TextAreaHandle) =
  discard area.container.emit(iekSelect)

proc trimUndoStack(stack: var seq[string]) =
  while stack.len > maxUndoEntries:
    stack.delete(0)
  var total = 0
  for item in stack:
    total += item.len
  while stack.len > 0 and total > maxUndoBytes:
    total -= stack[0].len
    stack.delete(0)

proc rememberUndo(area: TextAreaHandle) =
  if area.state.undoStack.len == 0 or area.state.undoStack[^1] != area.state.value:
    area.state.undoStack.add area.state.value
    area.state.undoStack.trimUndoStack()
  area.state.redoStack.setLen(0)

proc rememberUndoValue(area: TextAreaHandle; value: string) =
  if area.state.undoStack.len == 0 or area.state.undoStack[^1] != value:
    area.state.undoStack.add value
    area.state.undoStack.trimUndoStack()
  area.state.redoStack.setLen(0)

proc restoreValue(area: TextAreaHandle; value: string) =
  area.state.value = value
  area.state.caret = area.state.value.len
  area.state.collapseSelection()
  area.state.composingText = ""
  area.state.composingActive = false
  area.state.pendingFallbackText = ""
  area.setVisibleText()

proc undo(area: TextAreaHandle): bool =
  if area.state.readOnly or area.state.undoStack.len == 0:
    return false
  let previous = area.state.undoStack.pop()
  area.state.redoStack.add area.state.value
  area.state.redoStack.trimUndoStack()
  area.restoreValue(previous)
  true

proc redo(area: TextAreaHandle): bool =
  if area.state.readOnly or area.state.redoStack.len == 0:
    return false
  let next = area.state.redoStack.pop()
  area.state.undoStack.add area.state.value
  area.state.undoStack.trimUndoStack()
  area.restoreValue(next)
  true

proc clampDimension(value: float32; minValue, maxValue: Option[float32]): float32 =
  result = value
  if minValue.isSome and result < minValue.get:
    result = minValue.get
  if maxValue.isSome and result > maxValue.get:
    result = maxValue.get
  if result < 0:
    result = 0

proc effectiveWidth*(area: TextAreaHandle): Option[float32] =
  area.state.width

proc effectiveHeight*(area: TextAreaHandle): Option[float32] =
  area.state.height

proc resizable*(area: TextAreaHandle): bool =
  area.state.resize != rkNone and not area.state.disabled

proc syncResizeStyle(area: TextAreaHandle) =
  var declarations: seq[Declaration] = @[]
  if area.state.width.isSome:
    declarations.add decl("width", px(area.state.width.get))
  if area.state.height.isSome:
    declarations.add decl("height", px(area.state.height.get))
  if declarations.len > 0:
    area.root.applyStyle(area.container, uiStyle(declarations))
  area.resizeHandle.setState(esDisabled, not area.resizable())
  area.resizeHandle.setState(esActive, area.state.resizing)

proc emitResize(area: TextAreaHandle) =
  discard area.container.emit(iekResize)

proc resizeFromStyle(style: UiStyle): Option[ResizeKind] =
  for declaration in style.declarations:
    if declaration.property != "resize":
      continue
    if declaration.operation.mode in {mmInitial, mmUnset}:
      result = some(rkNone)
    elif declaration.operation.mode == mmOverwrite and
        declaration.operation.value.isSome and
        declaration.operation.value.get.kind == svKeyword:
      case declaration.operation.value.get.keyword
      of "none":
        result = some(rkNone)
      of "both":
        result = some(rkBoth)
      of "horizontal":
        result = some(rkHorizontal)
      of "vertical":
        result = some(rkVertical)
      else:
        discard

proc lengthFromStyle(style: UiStyle; property: string): Option[float32] =
  for declaration in style.declarations:
    if declaration.property != property:
      continue
    if declaration.operation.mode in {mmInitial, mmUnset}:
      result = none(float32)
    elif declaration.operation.mode == mmOverwrite and
        declaration.operation.value.isSome and
        declaration.operation.value.get.kind == svLength and
        declaration.operation.value.get.length.kind == ukPx:
      result = some(declaration.operation.value.get.length.value)

proc horizontalPaddingFromStyle(style: UiStyle): float32 =
  let all = style.lengthFromStyle("padding")
  let left = style.lengthFromStyle("padding-left")
  let right = style.lengthFromStyle("padding-right")
  let resolvedLeft =
    if left.isSome: left.get
    elif all.isSome: all.get
    else: 0.0'f32
  let resolvedRight =
    if right.isSome: right.get
    elif all.isSome: all.get
    else: 0.0'f32
  resolvedLeft + resolvedRight

proc verticalPaddingFromStyle(style: UiStyle): float32 =
  let all = style.lengthFromStyle("padding")
  let top = style.lengthFromStyle("padding-top")
  let bottom = style.lengthFromStyle("padding-bottom")
  let resolvedTop =
    if top.isSome: top.get
    elif all.isSome: all.get
    else: 0.0'f32
  let resolvedBottom =
    if bottom.isSome: bottom.get
    elif all.isSome: all.get
    else: 0.0'f32
  resolvedTop + resolvedBottom

proc paddingLeftFromStyle(style: UiStyle; fallback: float32): float32 =
  if style.lengthFromStyle("padding-left").isSome:
    return style.lengthFromStyle("padding-left").get
  if style.lengthFromStyle("padding-inline").isSome:
    return style.lengthFromStyle("padding-inline").get
  if style.lengthFromStyle("padding").isSome:
    return style.lengthFromStyle("padding").get
  fallback

proc paddingTopFromStyle(style: UiStyle; fallback: float32): float32 =
  if style.lengthFromStyle("padding-top").isSome:
    return style.lengthFromStyle("padding-top").get
  if style.lengthFromStyle("padding-block").isSome:
    return style.lengthFromStyle("padding-block").get
  if style.lengthFromStyle("padding").isSome:
    return style.lengthFromStyle("padding").get
  fallback

proc textWidthForArea(width: Option[float32]; horizontalInset: float32): Option[float32] =
  if width.isNone:
    return none(float32)
  some(max(1.0'f32, width.get - horizontalInset - textEdgeSlack))

proc effectiveTextMaxWidth(area: TextAreaHandle): Option[float32] =
  area.state.textMaxWidth

proc normalizePastedText(text: string): string =
  text.replace("\r\n", "\n").replace("\r", "\n")

proc deleteSelection(area: TextAreaHandle; recordUndo = true; refresh = true): bool =
  if area.state.disabled or area.state.readOnly or not area.state.hasSelection():
    return false
  if recordUndo:
    area.rememberUndo()
  let bounds = area.state.selectionBounds()
  area.state.value.delete(bounds.first .. bounds.last - 1)
  area.state.caret = bounds.first
  area.state.collapseSelection()
  area.state.composingText = ""
  area.state.composingActive = false
  area.state.pendingFallbackText = ""
  if refresh:
    area.setVisibleText()
  true

proc insertText(area: TextAreaHandle; text: string; emitValue = false) =
  if area.state.disabled or area.state.readOnly or text.len == 0:
    return
  # A committed insertion or paste ends the previous preedit transaction.
  # Reset the deduplication fields as well so an update-only IME stream can
  # start again with the same preedit text.
  area.state.composingText = ""
  area.state.composingActive = false
  area.state.compositionUpdateSeen = false
  area.state.lastCompositionUpdateText = ""
  area.state.pendingFallbackText = ""
  area.state.clampCaret()
  let oldValue = area.state.value
  discard area.deleteSelection(recordUndo = false, refresh = false)
  var inserted = text
  let remaining = area.state.effectiveMaxLength() - area.state.value.len
  if remaining <= 0:
    if area.state.value != oldValue:
      area.rememberUndoValue(oldValue)
      area.setVisibleText()
      if emitValue:
        area.emitValueEvents()
    return
  inserted = inserted.truncateAtRuneBoundary(remaining)
  if inserted.len == 0:
    if area.state.value != oldValue:
      area.rememberUndoValue(oldValue)
      area.setVisibleText()
      if emitValue:
        area.emitValueEvents()
    return
  area.rememberUndoValue(oldValue)
  area.state.value.insert(inserted, area.state.caret)
  area.state.caret += inserted.len
  area.state.collapseSelection()
  area.setVisibleText()
  if emitValue:
    area.emitValueEvents()

proc deleteBackward(area: TextAreaHandle): bool =
  if area.state.readOnly:
    return false
  if area.deleteSelection():
    return true
  if area.state.disabled or area.state.caret <= 0 or area.state.value.len == 0:
    return false
  area.state.clampCaret()
  let start = previousRuneStart(area.state.value, area.state.caret)
  area.rememberUndo()
  area.state.value.delete(start .. area.state.caret - 1)
  area.state.caret = start
  area.state.collapseSelection()
  area.setVisibleText()
  true

proc deleteComposingBackward(area: TextAreaHandle): bool =
  if area.state.readOnly or area.state.disabled or area.state.composingText.len == 0:
    return false
  let start = previousRuneStart(area.state.composingText, area.state.composingText.len)
  area.state.composingText.delete(start .. area.state.composingText.len - 1)
  if area.state.composingText.len == 0:
    area.state.composingActive = false
  area.setVisibleText()
  true

proc deleteForward(area: TextAreaHandle): bool =
  if area.state.readOnly:
    return false
  if area.deleteSelection():
    return true
  if area.state.disabled or area.state.caret >= area.state.value.len:
    return false
  area.state.clampCaret()
  let stop = nextRuneEnd(area.state.value, area.state.caret)
  area.rememberUndo()
  area.state.value.delete(area.state.caret .. stop - 1)
  area.state.collapseSelection()
  area.setVisibleText()
  true

proc deleteWordBackward(area: TextAreaHandle): bool =
  if area.state.readOnly:
    return false
  if area.deleteSelection():
    return true
  if area.state.disabled or area.state.caret <= 0 or area.state.value.len == 0:
    return false
  area.state.clampCaret()
  let start = previousWordStart(area.state.value, area.state.caret)
  if start == area.state.caret:
    return false
  area.rememberUndo()
  area.state.value.delete(start .. area.state.caret - 1)
  area.state.caret = start
  area.state.collapseSelection()
  area.setVisibleText()
  true

proc deleteWordForward(area: TextAreaHandle): bool =
  if area.state.readOnly:
    return false
  if area.deleteSelection():
    return true
  if area.state.disabled or area.state.caret >= area.state.value.len:
    return false
  area.state.clampCaret()
  let stop = nextWordEnd(area.state.value, area.state.caret)
  if stop == area.state.caret:
    return false
  area.rememberUndo()
  area.state.value.delete(area.state.caret .. stop - 1)
  area.state.collapseSelection()
  area.setVisibleText()
  true

proc moveCaretLeft(area: TextAreaHandle; extendSelection = false) =
  let hadSelection = area.state.hasSelection()
  area.state.clampCaret()
  if area.state.caret > 0:
    area.state.caret = previousRuneStart(area.state.value, area.state.caret)
  if extendSelection:
    area.state.selectionEnd = area.state.caret
  else:
    area.state.collapseSelection()
  if extendSelection or hadSelection:
    area.emitSelect()
  let lines = area.caretLines()
  area.ensureCaretVisible(lines)
  area.syncTextNodeStyle()
  area.syncSelectionStyle(lines)
  area.syncCaretStyle(lines)

proc moveCaretRight(area: TextAreaHandle; extendSelection = false) =
  let hadSelection = area.state.hasSelection()
  area.state.clampCaret()
  if area.state.caret < area.state.value.len:
    area.state.caret = nextRuneEnd(area.state.value, area.state.caret)
  if extendSelection:
    area.state.selectionEnd = area.state.caret
  else:
    area.state.collapseSelection()
  if extendSelection or hadSelection:
    area.emitSelect()
  let lines = area.caretLines()
  area.ensureCaretVisible(lines)
  area.syncTextNodeStyle()
  area.syncSelectionStyle(lines)
  area.syncCaretStyle(lines)

proc moveCaretWordLeft(area: TextAreaHandle; extendSelection = false) =
  let hadSelection = area.state.hasSelection()
  area.state.clampCaret()
  area.moveCaretTo(previousWordStart(area.state.value, area.state.caret), extendSelection, hadSelection)

proc moveCaretWordRight(area: TextAreaHandle; extendSelection = false) =
  let hadSelection = area.state.hasSelection()
  area.state.clampCaret()
  area.moveCaretTo(nextWordEnd(area.state.value, area.state.caret), extendSelection, hadSelection)

proc lineStart(text: string; caret: int): int =
  result = min(caret, text.len)
  while result > 0 and text[result - 1] != '\n':
    dec result

proc lineEnd(text: string; caret: int): int =
  result = min(caret, text.len)
  while result < text.len and text[result] != '\n':
    inc result

proc textStyleFrom(style: UiStyle): ComputedTextStyle =
  for declaration in style.declarations:
    if declaration.operation.value.isNone or declaration.operation.mode != mmOverwrite:
      continue
    let value = declaration.operation.value.get
    case declaration.property
    of "font-size":
      if value.kind == svLength and value.length.kind == ukPx:
        result.fontSize = some(value.length.value)
    of "line-height":
      if value.kind == svLength and value.length.kind == ukPx:
        result.lineHeight = some(value.length.value)
      elif value.kind == svNumber:
        let fontSize = if result.fontSize.isSome: result.fontSize.get else: 16.0'f32
        result.lineHeight = some(fontSize * value.number)
    of "letter-spacing":
      if value.kind == svLength and value.length.kind == ukPx:
        result.letterSpacing = some(value.length.value)
    of "font-family":
      if value.kind == svKeyword:
        result.fontFamilies = value.keyword.split(",")
    of "white-space":
      if value.kind == svKeyword and value.keyword == "nowrap":
        result.whiteSpace = some(wsNoWrap)
      elif value.kind == svKeyword and value.keyword == "pre-wrap":
        result.whiteSpace = some(wsPreWrap)
      elif value.kind == svKeyword and value.keyword == "pre":
        result.whiteSpace = some(wsPre)
      elif value.kind == svKeyword and value.keyword == "normal":
        result.whiteSpace = some(wsNormal)
    of "overflow-wrap":
      if value.kind == svKeyword:
        case value.keyword
        of "anywhere":
          result.overflowWrap = some(owAnywhere)
        of "break-word":
          result.overflowWrap = some(owBreakWord)
        of "normal":
          result.overflowWrap = some(owNormal)
        else:
          discard
    of "word-break":
      if value.kind == svKeyword:
        case value.keyword
        of "break-all":
          result.wordBreak = some(wbBreakAll)
        of "break-word":
          result.wordBreak = some(wbBreakWord)
        of "keep-all":
          result.wordBreak = some(wbKeepAll)
        of "normal":
          result.wordBreak = some(wbNormal)
        else:
          discard
    else:
      discard
  if result.whiteSpace.isNone:
    result.whiteSpace = some(wsPreWrap)
  if result.overflowWrap.isNone and result.whiteSpace.get != wsNoWrap:
    result.overflowWrap = some(owAnywhere)

proc widthFrom(style: UiStyle): Option[float32] =
  for declaration in style.declarations:
    if declaration.property == "width" and declaration.operation.value.isSome:
      let value = declaration.operation.value.get
      if value.kind == svLength and value.length.kind == ukPx:
        return some(value.length.value)
  none(float32)

proc visibleTextHeight(area: TextAreaHandle): Option[float32] =
  if area.state.height.isNone:
    return none(float32)
  some(max(1.0'f32, area.state.height.get - area.state.textVerticalInset))

proc measuredDisplayHeight(area: TextAreaHandle; lines: seq[TextAreaVisualLine]): float32 =
  if lines.len == 0:
    return 0.0'f32
  lines[^1].y + lines[^1].height

proc scrollbarGeometry(
    area: TextAreaHandle;
    lines: seq[TextAreaVisualLine]
): Option[TextAreaScrollbarGeometry] =
  if area.state.height.isNone:
    return none(TextAreaScrollbarGeometry)
  let visibleHeight = area.visibleTextHeight()
  if visibleHeight.isNone:
    return none(TextAreaScrollbarGeometry)
  let contentHeight = area.measuredDisplayHeight(lines)
  let maxScroll = max(0.0'f32, contentHeight - visibleHeight.get)
  if maxScroll <= 0.5'f32:
    return none(TextAreaScrollbarGeometry)
  let resizeReserve = if area.resizable(): 14.0'f32 else: 0.0'f32
  let trackHeight = max(16.0'f32, area.state.height.get - 8.0'f32 - resizeReserve)
  let thumbHeight = min(
    trackHeight,
    max(14.0'f32, trackHeight * min(1.0'f32, visibleHeight.get / contentHeight))
  )
  let travel = max(0.0'f32, trackHeight - thumbHeight)
  let progress = min(1.0'f32, max(0.0'f32, area.state.scrollY / maxScroll))
  some(TextAreaScrollbarGeometry(
    trackHeight: trackHeight,
    thumbTop: travel * progress,
    thumbHeight: thumbHeight,
    maxScroll: maxScroll
  ))

proc syncScrollbarStyle(area: TextAreaHandle; lines: seq[TextAreaVisualLine]) =
  if area.scrollbarTrack.root.isNil or area.scrollbarThumb.root.isNil:
    return
  let geometry = area.scrollbarGeometry(lines)
  if geometry.isNone or not area.state.scrollbarVisible:
    area.scrollbarTrack.applyStyle(uiStyle([
      decl("display", keyword("none"))
    ]))
    area.scrollbarThumb.applyStyle(uiStyle([
      decl("display", keyword("none"))
    ]))
    return
  let bar = geometry.get
  area.scrollbarTrack.applyStyle(uiStyle([
    decl("display", keyword("flex")),
    decl("position", keyword("absolute")),
    decl("right", px(3)),
    decl("top", px(4)),
    decl("width", px(7)),
    decl("height", px(bar.trackHeight)),
    decl("background-color", colorValue(rgba(0.14, 0.17, 0.21, 0.92))),
    decl("border-radius", px(4)),
    decl("z-index", number(980))
  ]))
  area.scrollbarThumb.applyStyle(uiStyle([
    decl("display", keyword("flex")),
    decl("position", keyword("absolute")),
    decl("left", px(0)),
    decl("top", px(bar.thumbTop)),
    decl("width", px(7)),
    decl("height", px(bar.thumbHeight)),
    decl("background-color", colorValue(rgb(0.46, 0.62, 0.74))),
    decl("border-radius", px(4)),
    decl("cursor", keyword("pointer")),
    decl("z-index", number(981))
  ]))

proc clampScrollY(area: TextAreaHandle; lines: seq[TextAreaVisualLine]) =
  let visibleHeight = area.visibleTextHeight()
  if visibleHeight.isNone:
    area.state.scrollY = 0.0'f32
    return
  let maxScroll = max(0.0'f32, area.measuredDisplayHeight(lines) - visibleHeight.get)
  area.state.scrollY = max(0.0'f32, min(area.state.scrollY, maxScroll))

proc ensureCaretVisible(area: TextAreaHandle; lines: seq[TextAreaVisualLine]) =
  let visibleHeight = area.visibleTextHeight()
  if visibleHeight.isNone:
    area.state.scrollY = 0.0'f32
    return
  let caret = lines.caretSampleAt(area.state.caret)
  let top = caret.y
  let bottom = caret.y + max(1.0'f32, caret.height)
  if top < area.state.scrollY:
    area.state.scrollY = top
  elif bottom > area.state.scrollY + visibleHeight.get:
    area.state.scrollY = bottom - visibleHeight.get
  area.clampScrollY(lines)

proc ensureCaretVisible(area: TextAreaHandle; caret: TextCaretResult) =
  let visibleHeight = area.visibleTextHeight()
  if visibleHeight.isNone:
    area.state.scrollY = 0.0'f32
    return
  let top = caret.position.y
  let bottom = caret.position.y + max(1.0'f32, caret.height)
  if top < area.state.scrollY:
    area.state.scrollY = top
  elif bottom > area.state.scrollY + visibleHeight.get:
    area.state.scrollY = bottom - visibleHeight.get
  if area.state.caret >= area.state.value.len:
    let maxScroll = max(0.0'f32, bottom - visibleHeight.get)
    area.state.scrollY = max(0.0'f32, min(area.state.scrollY, maxScroll))
  else:
    area.state.scrollY = max(0.0'f32, area.state.scrollY)

proc scrollBy*(area: TextAreaHandle; deltaY: float32) =
  if not area.container.valid():
    return
  let previousScrollY = area.state.scrollY
  area.state.scrollY += deltaY
  let lines = area.caretLines()
  area.clampScrollY(lines)
  if abs(area.state.scrollY - previousScrollY) > 0.001'f32:
    area.state.scrollbarVisible = true
  area.syncTextNodeStyle()
  area.syncSelectionStyle(lines)
  area.syncCaretStyle(lines)
  area.root.tree.setAttribute(area.container.id, "scroll-y", $area.state.scrollY)

proc finishScroll*(area: TextAreaHandle) =
  if not area.container.valid():
    return
  if not area.state.scrollbarVisible or area.state.scrollbarDragging:
    return
  area.state.scrollbarVisible = false
  area.syncScrollbarStyle(area.caretLines())

proc syncCaretStyle(area: TextAreaHandle; lines: seq[TextAreaVisualLine]) =
  if area.state.composingText.len > 0:
    let display = area.state.displayText()
    let caret = area.root.textEngine.caret(TextCaretInput(
      text: display,
      style: area.state.textStyle,
      maxWidth: area.state.textMaxWidth,
      fonts: area.root.fonts,
      byteIndex: area.state.displayCaretIndex()
    ))
    area.syncCaretStyle(caret)
    return
  let caret = lines.caretSampleAt(area.state.caret)
  let caretLeft =
    if area.state.textMaxWidth.isSome:
      min(caret.x, max(0.0'f32, area.state.textMaxWidth.get - textEdgeSlack))
    else:
      caret.x
  let metrics = area.state.textStyle.caretVisualMetrics(caret.height)
  let sheet = styleSheet([
    rule(
      target(area.caretNode.id),
      [
        decl("display", keyword(if area.state.focused: "flex" else: "none")),
        decl("left", px(caretLeft)),
        decl("top", px(caret.y - area.state.scrollY + metrics.offset)),
        decl("height", px(metrics.height))
      ],
      priority = 900
    )
  ])
  if area.state.caretStyleIndex.isSome and area.state.caretStyleIndex.get < area.root.componentStyles.len:
    area.root.componentStyles[area.state.caretStyleIndex.get] = sheet
  else:
    area.root.componentStyles.add sheet
    area.state.caretStyleIndex = some(area.root.componentStyles.len - 1)

proc syncCaretStyle(area: TextAreaHandle; caret: TextCaretResult) =
  let caretLeft =
    if area.state.textMaxWidth.isSome:
      min(caret.position.x, max(0.0'f32, area.state.textMaxWidth.get - textEdgeSlack))
    else:
      caret.position.x
  let metrics = area.state.textStyle.caretVisualMetrics(caret.height)
  let sheet = styleSheet([
    rule(
      target(area.caretNode.id),
      [
        decl("display", keyword(if area.state.focused: "flex" else: "none")),
        decl("left", px(caretLeft)),
        decl("top", px(caret.position.y - area.state.scrollY + metrics.offset)),
        decl("height", px(metrics.height))
      ],
      priority = 900
    )
  ])
  if area.state.caretStyleIndex.isSome and area.state.caretStyleIndex.get < area.root.componentStyles.len:
    area.root.componentStyles[area.state.caretStyleIndex.get] = sheet
  else:
    area.root.componentStyles.add sheet
    area.state.caretStyleIndex = some(area.root.componentStyles.len - 1)

proc hideSelectionStyle(area: TextAreaHandle) =
  if not area.state.selectionVisible:
    return
  area.state.selectionVisible = false
  var rules: seq[StyleRule] = @[]
  for node in area.state.selectionNodes:
    rules.add rule(
      target(node.id),
      [
        decl("display", keyword("none")),
        decl("left", px(0)),
        decl("top", px(0)),
        decl("width", px(0)),
        decl("height", px(0))
      ],
      priority = 845
    )
  let sheet = styleSheet(rules)
  if area.state.selectionStyleIndex.isSome and area.state.selectionStyleIndex.get < area.root.componentStyles.len:
    area.root.componentStyles[area.state.selectionStyleIndex.get] = sheet
  else:
    area.root.componentStyles.add sheet
    area.state.selectionStyleIndex = some(area.root.componentStyles.len - 1)

proc syncSelectionStyle(area: TextAreaHandle; lines: seq[TextAreaVisualLine]) =
  let bounds = area.state.selectionBounds()
  let show = area.state.focused and bounds.first != bounds.last
  let visibleHeight = area.visibleTextHeight()
  var fragments: seq[tuple[left, right, top, height: float32]] = @[]
  if show:
    traceSelection(
      "sync bounds=" & $bounds.first & ".." & $bounds.last &
      " caret=" & $area.state.caret &
      " scrollY=" & $area.state.scrollY
    )
    for line in lines:
      if line.samples.len == 0:
        continue
      let visibleTop = line.y - area.state.scrollY
      if visibleHeight.isSome and
          (visibleTop + line.height <= 0 or visibleTop >= visibleHeight.get):
        continue
      let lineStart = line.samples[0]
      let lineEnd = line.samples[^1]
      if bounds.last <= lineStart.index or bounds.first >= lineEnd.index:
        continue
      let selectedFirst = max(bounds.first, lineStart.index)
      let selectedLast = min(bounds.last, lineEnd.index)
      let left =
        if bounds.first <= lineStart.index:
          lineStart.x
        else:
          caretXAtOrAfter(line.samples, bounds.first)
      var right =
        if bounds.last >= lineEnd.index:
          lineEnd.x
        else:
          caretXAtOrAfter(line.samples, bounds.last)
      right += area.selectedTrailingBlankWidth(line.samples, selectedFirst, selectedLast, right)
      var fragmentLeft = left
      var fragmentRight = right
      if fragmentRight < fragmentLeft:
        swap(fragmentLeft, fragmentRight)
      fragments.add((
        left: fragmentLeft,
        right: fragmentRight,
        top: visibleTop,
        height: line.height
      ))
      traceSelection(
        "line y=" & $line.y &
        " samples=" & $line.samples.len &
        " lineStart=" & $lineStart.index & "@x" & $lineStart.x &
        " lineEnd=" & $lineEnd.index & "@x" & $lineEnd.x &
        " fragment left=" & $fragmentLeft &
        " right=" & $fragmentRight &
        " top=" & $visibleTop &
        " h=" & $line.height
      )

  area.ensureSelectionNodes(fragments.len)
  if not show and not area.state.selectionVisible:
    return
  area.state.selectionVisible = show
  var rules: seq[StyleRule] = @[]
  for index, node in area.state.selectionNodes:
    if show and index < fragments.len:
      let fragment = fragments[index]
      rules.add rule(
        target(node.id),
        [
          decl("display", keyword("flex")),
          decl("left", px(fragment.left)),
          decl("top", px(fragment.top)),
          decl("width", px(max(1.0'f32, fragment.right - fragment.left))),
          decl("height", px(fragment.height)),
          decl("background-color", colorValue(rgba(0.18, 0.48, 0.78, 0.42))),
          decl("border-radius", px(2)),
          decl("pointer-events", keyword("none"))
        ],
        priority = 845
      )
    else:
      rules.add rule(
        target(node.id),
        [
          decl("display", keyword("none")),
          decl("left", px(0)),
          decl("top", px(0)),
          decl("width", px(0)),
          decl("height", px(0))
        ],
        priority = 845
      )

  let sheet = styleSheet(rules)
  if area.state.selectionStyleIndex.isSome and area.state.selectionStyleIndex.get < area.root.componentStyles.len:
    area.root.componentStyles[area.state.selectionStyleIndex.get] = sheet
  else:
    area.root.componentStyles.add sheet
    area.state.selectionStyleIndex = some(area.root.componentStyles.len - 1)

proc syncTextNodeStyle(area: TextAreaHandle) =
  if not area.state.textNodeStyleDirty and
      area.state.textNodeStyleIndex.isSome and
      abs(area.state.syncedTextScrollY - area.state.scrollY) <= 0.001'f32:
    return
  var declarations = @[
    decl("pointer-events", keyword("none")),
    decl("position", keyword("absolute")),
    decl("left", px(0)),
    decl("top", px(-area.state.scrollY))
  ]
  if area.state.textMaxWidth.isSome:
    declarations.add decl("width", px(area.effectiveTextMaxWidth().get))
  if area.state.textStyle.whiteSpace.isSome:
    case area.state.textStyle.whiteSpace.get
    of wsNoWrap:
      declarations.add decl("white-space", keyword("nowrap"))
    of wsPre:
      declarations.add decl("white-space", keyword("pre"))
    of wsNormal:
      declarations.add decl("white-space", keyword("normal"))
    else:
      declarations.add decl("white-space", keyword("pre-wrap"))
  else:
    declarations.add decl("white-space", keyword("pre-wrap"))
  if area.state.textStyle.overflowWrap.isSome:
    case area.state.textStyle.overflowWrap.get
    of owAnywhere:
      declarations.add decl("overflow-wrap", keyword("anywhere"))
    of owBreakWord:
      declarations.add decl("overflow-wrap", keyword("break-word"))
    else:
      declarations.add decl("overflow-wrap", keyword("normal"))
  elif area.state.textStyle.whiteSpace.isNone or area.state.textStyle.whiteSpace.get != wsNoWrap:
    declarations.add decl("overflow-wrap", keyword("anywhere"))

  let sheet = styleSheet([
    rule(target(area.textNode.id), declarations, priority = 850)
  ])
  if area.state.textNodeStyleIndex.isSome and area.state.textNodeStyleIndex.get < area.root.componentStyles.len:
    area.root.componentStyles[area.state.textNodeStyleIndex.get] = sheet
  else:
    area.root.componentStyles.add sheet
    area.state.textNodeStyleIndex = some(area.root.componentStyles.len - 1)
  area.state.textNodeStyleDirty = false
  area.state.syncedTextScrollY = area.state.scrollY
  area.syncScrollbarStyle(area.caretLines())

proc setVisibleText(area: TextAreaHandle) =
  area.setValueAttribute()
  area.root.tree.setAttribute(area.container.id, "caret", $area.state.caret)
  area.root.tree.setAttribute(area.container.id, "selection-start", $area.state.selectionStart)
  area.root.tree.setAttribute(area.container.id, "selection-end", $area.state.selectionEnd)
  let display = area.state.displayText()
  area.root.tree.nodes[area.textNode.id.nodeIndex].text = display
  area.markTextLayoutDirty()
  if area.state.hasSelection():
    let lines = area.caretLines()
    area.ensureCaretVisible(lines)
    area.syncTextNodeStyle()
    area.syncSelectionStyle(lines)
    area.syncCaretStyle(lines)
  else:
    let caret = area.root.textEngine.caret(TextCaretInput(
      text: display,
      style: area.state.textStyle,
      maxWidth: area.state.textMaxWidth,
      fonts: area.root.fonts,
      byteIndex: area.state.displayCaretIndex()
    ))
    area.ensureCaretVisible(caret)
    area.syncTextNodeStyle()
    area.hideSelectionStyle()
    area.syncCaretStyle(caret)
  area.root.tree.setAttribute(area.container.id, "scroll-y", $area.state.scrollY)

proc moveCaretTo(area: TextAreaHandle; caret: int; extendSelection = false; emitSelection = false) =
  area.state.caret = caret
  area.state.clampCaret()
  if extendSelection:
    area.state.selectionEnd = area.state.caret
  else:
    area.state.collapseSelection()
  if extendSelection or emitSelection:
    area.emitSelect()
  let lines = area.caretLines()
  area.ensureCaretVisible(lines)
  area.syncTextNodeStyle()
  area.syncSelectionStyle(lines)
  area.syncCaretStyle(lines)
  area.root.tree.setAttribute(area.container.id, "caret", $area.state.caret)
  area.root.tree.setAttribute(area.container.id, "selection-start", $area.state.selectionStart)
  area.root.tree.setAttribute(area.container.id, "selection-end", $area.state.selectionEnd)
  area.root.tree.setAttribute(area.container.id, "scroll-y", $area.state.scrollY)

proc moveCaretLineStart(area: TextAreaHandle; extendSelection = false) =
  let hadSelection = area.state.hasSelection()
  area.moveCaretTo(area.state.value.lineStart(area.state.caret), extendSelection, hadSelection)

proc moveCaretLineEnd(area: TextAreaHandle; extendSelection = false) =
  let hadSelection = area.state.hasSelection()
  area.moveCaretTo(area.state.value.lineEnd(area.state.caret), extendSelection, hadSelection)

proc moveCaretVertical(area: TextAreaHandle; direction: int; extendSelection = false) =
  let hadSelection = area.state.hasSelection()
  let caret = area.root.textEngine.caret(TextCaretInput(
    text: area.state.value,
    style: area.state.textStyle,
    maxWidth: area.state.textMaxWidth,
    fonts: area.root.fonts,
    byteIndex: area.state.caret
  ))
  let lineHeight = max(1.0'f32, caret.height)
  let targetY =
    if direction < 0:
      max(0.0'f32, caret.position.y - lineHeight * 0.5'f32)
    else:
      caret.position.y + lineHeight * 1.5'f32
  let hit = area.root.textEngine.hit(TextHitInput(
    text: area.state.value,
    style: area.state.textStyle,
    maxWidth: area.state.textMaxWidth,
    fonts: area.root.fonts,
    point: vec2(max(0.0'f32, caret.position.x), targetY)
  ))
  area.moveCaretTo(hit.byteIndex, extendSelection, hadSelection)

proc moveCaretUp(area: TextAreaHandle; extendSelection = false) =
  area.moveCaretVertical(-1, extendSelection)

proc moveCaretDown(area: TextAreaHandle; extendSelection = false) =
  area.moveCaretVertical(1, extendSelection)

proc moveCaretPage(area: TextAreaHandle; direction: int; extendSelection = false) =
  let hadSelection = area.state.hasSelection()
  let caret = area.root.textEngine.caret(TextCaretInput(
    text: area.state.value,
    style: area.state.textStyle,
    maxWidth: area.state.textMaxWidth,
    fonts: area.root.fonts,
    byteIndex: area.state.caret
  ))
  let visibleHeight =
    if area.visibleTextHeight().isSome: area.visibleTextHeight().get
    else: max(1.0'f32, caret.height * 5.0'f32)
  let targetY =
    if direction < 0:
      max(0.0'f32, caret.position.y - visibleHeight)
    else:
      caret.position.y + visibleHeight
  let hit = area.root.textEngine.hit(TextHitInput(
    text: area.state.value,
    style: area.state.textStyle,
    maxWidth: area.state.textMaxWidth,
    fonts: area.root.fonts,
    point: vec2(max(0.0'f32, caret.position.x), targetY)
  ))
  area.moveCaretTo(hit.byteIndex, extendSelection, hadSelection)

proc caretIndexAtPoint(area: TextAreaHandle; lines: seq[TextAreaVisualLine]; point: Vec2): int =
  if lines.len == 0:
    return 0

  var bestLine = lines[0]
  var bestDistance = abs(point.y - lines[0].y)
  for line in lines:
    let top = line.y
    let bottom = line.y + line.height
    let distance =
      if point.y < top: top - point.y
      elif point.y > bottom: point.y - bottom
      else: 0.0'f32
    if distance < bestDistance:
      bestDistance = distance
      bestLine = line

  let lineSamples = bestLine.samples
  if lineSamples.len == 0:
    traceSelection(
      "hit point=(" & $point.x & "," & $point.y & ") no-line -> 0"
    )
    return 0

  result = lineSamples[^1].index
  if point.x <= lineSamples[0].x:
    result = lineSamples[0].index
  else:
    for index in 0 ..< lineSamples.high:
      let left = lineSamples[index]
      let right = lineSamples[index + 1]
      let midpoint = (left.x + right.x) / 2.0'f32
      if point.x < midpoint:
        result = left.index
        break
      if point.x < right.x:
        result = right.index
        break
  traceSelection(
    "hit point=(" & $point.x & "," & $point.y & ")" &
    " chosenLineY=" & $bestLine.y &
    " lineSamples=" & $lineSamples.len &
    " first=" & $lineSamples[0].index & "@x" & $lineSamples[0].x &
    " last=" & $lineSamples[^1].index & "@x" & $lineSamples[^1].x &
    " result=" & $result
  )

proc textFromPrintableKey(event: InputEvent): string =
  if event.ctrlKey or event.metaKey or event.altKey or event.key.isNone:
    return ""
  let key = event.key.get
  if key.len != 1:
    return ""
  let ch = key[0]
  if ch < ' ' or ch > '~':
    return ""
  if event.shiftKey:
    if ch in {'a'..'z'}:
      result = ($ch).toUpperAscii()
  else:
    result = $ch

proc requestClipboardWrite(area: TextAreaHandle; text: string) =
  area.state.clipboardText = text
  area.state.clipboardWriteRequested = text.len > 0
  if text.len > 0:
    area.root.writeClipboardText(text)

proc value*(area: TextAreaHandle): string =
  area.state.value

proc selectedText*(area: TextAreaHandle): string =
  if not area.state.hasSelection():
    return ""
  let bounds = area.state.selectionBounds()
  area.state.value[bounds.first ..< bounds.last]

proc takeClipboardText*(area: TextAreaHandle): string =
  result = area.state.clipboardText
  area.state.clipboardText = ""
  area.state.clipboardWriteRequested = false

proc setValue*(area: TextAreaHandle; value: string) =
  if not area.container.valid():
    return
  let maxLength = area.state.effectiveMaxLength()
  if value.len > maxLength:
    area.state.value = value.truncateAtRuneBoundary(maxLength)
  else:
    area.state.value = value
  area.state.caret = area.state.value.len
  area.state.collapseSelection()
  area.state.composingText = ""
  area.state.composingActive = false
  area.state.pendingFallbackText = ""
  area.setVisibleText()

proc setSelection*(area: TextAreaHandle; first, last: int) =
  if not area.container.valid():
    return
  area.state.selectionStart = first
  area.state.selectionEnd = last
  area.state.clampSelection()
  area.state.caret = area.state.selectionEnd
  area.emitSelect()
  let lines = area.caretLines()
  area.ensureCaretVisible(lines)
  area.syncTextNodeStyle()
  area.syncSelectionStyle(lines)
  area.syncCaretStyle(lines)
  area.root.tree.setAttribute(area.container.id, "caret", $area.state.caret)
  area.root.tree.setAttribute(area.container.id, "selection-start", $area.state.selectionStart)
  area.root.tree.setAttribute(area.container.id, "selection-end", $area.state.selectionEnd)
  area.root.tree.setAttribute(area.container.id, "scroll-y", $area.state.scrollY)

proc moveCaretToPoint*(area: TextAreaHandle; local: Vec2; extendSelection = false) =
  if not area.container.valid():
    return
  let textX =
    if area.state.textMaxWidth.isSome:
      min(max(0.0'f32, local.x - area.state.textLeftInset), area.state.textMaxWidth.get)
    else:
      max(0.0'f32, local.x - area.state.textLeftInset)
  let visibleHeight = area.visibleTextHeight()
  let lines = area.caretLines()
  if visibleHeight.isSome and extendSelection:
    let top = area.state.textTopInset
    let bottom = area.state.textTopInset + visibleHeight.get
    let scrollDelta =
      if local.y < top:
        local.y - top
      elif local.y > bottom:
        local.y - bottom
      else:
        0.0'f32
    if scrollDelta != 0.0'f32:
      area.state.scrollY += scrollDelta
      area.clampScrollY(lines)
  let viewportY =
    if visibleHeight.isSome:
      min(max(0.0'f32, local.y - area.state.textTopInset), max(0.0'f32, visibleHeight.get - 1.0'f32))
    else:
      max(0.0'f32, local.y - area.state.textTopInset)
  let previousCaret = area.state.caret
  let previousStart = area.state.selectionStart
  let previousEnd = area.state.selectionEnd
  area.state.caret = area.caretIndexAtPoint(lines, vec2(textX, viewportY + area.state.scrollY))
  area.state.clampCaret()
  if extendSelection:
    area.state.selectionEnd = area.state.caret
    area.emitSelect()
  else:
    area.state.collapseSelection()
  traceSelection(
    "move local=(" & $local.x & "," & $local.y & ")" &
    " text=(" & $textX & "," & $(viewportY + area.state.scrollY) & ")" &
    " extend=" & $extendSelection &
    " caret " & $previousCaret & "->" & $area.state.caret &
    " selection " & $previousStart & ".." & $previousEnd &
    " -> " & $area.state.selectionStart & ".." & $area.state.selectionEnd
  )
  area.ensureCaretVisible(lines)
  area.syncTextNodeStyle()
  area.syncSelectionStyle(lines)
  area.syncCaretStyle(lines)
  area.root.tree.setAttribute(area.container.id, "caret", $area.state.caret)
  area.root.tree.setAttribute(area.container.id, "selection-start", $area.state.selectionStart)
  area.root.tree.setAttribute(area.container.id, "selection-end", $area.state.selectionEnd)
  area.root.tree.setAttribute(area.container.id, "scroll-y", $area.state.scrollY)

proc selectAll*(area: TextAreaHandle) =
  if not area.container.valid():
    return
  area.state.selectionStart = 0
  area.state.selectionEnd = area.state.value.len
  area.state.caret = area.state.selectionEnd
  area.emitSelect()
  let lines = area.caretLines()
  area.ensureCaretVisible(lines)
  area.syncTextNodeStyle()
  area.syncSelectionStyle(lines)
  area.syncCaretStyle(lines)
  area.root.tree.setAttribute(area.container.id, "caret", $area.state.caret)
  area.root.tree.setAttribute(area.container.id, "selection-start", $area.state.selectionStart)
  area.root.tree.setAttribute(area.container.id, "selection-end", $area.state.selectionEnd)
  area.root.tree.setAttribute(area.container.id, "scroll-y", $area.state.scrollY)

proc focus*(area: TextAreaHandle) =
  if not area.container.valid() or area.state.disabled:
    return
  area.state.focused = true
  area.container.addState(esFocus)
  area.setVisibleText()

proc blur*(area: TextAreaHandle) =
  if not area.container.valid():
    return
  area.state.focused = false
  area.container.removeState(esFocus)
  area.state.collapseSelection()
  area.state.composingText = ""
  area.state.composingActive = false
  area.state.pendingFallbackText = ""
  area.setVisibleText()

proc setDisabled*(area: TextAreaHandle; disabled: bool) =
  if not area.container.valid():
    return
  area.state.disabled = disabled
  area.container.setState(esDisabled, disabled)
  if disabled:
    area.state.resizing = false
    area.blur()
  area.syncResizeStyle()

proc setSize*(area: TextAreaHandle; width, height: Option[float32]; emitEvent = false) =
  if not area.container.valid():
    return
  if width.isSome:
    area.state.width = some(clampDimension(width.get, area.state.minWidth, area.state.maxWidth))
  if height.isSome:
    area.state.height = some(clampDimension(height.get, area.state.minHeight, area.state.maxHeight))
  if not area.state.textMaxWidthExplicit:
    area.state.textMaxWidth = textWidthForArea(area.state.width, area.state.textHorizontalInset)
  area.markTextLayoutDirty()
  area.state.textNodeStyleDirty = true
  area.setVisibleText()
  area.syncResizeStyle()
  if emitEvent:
    area.emitResize()

proc setResize*(area: TextAreaHandle; resize: ResizeKind) =
  if not area.container.valid():
    return
  area.state.resize = resize
  if resize == rkNone:
    area.state.resizing = false
  area.syncResizeStyle()

proc `onResize=`*(area: TextAreaHandle; handler: EventHandler) =
  area.container.onResize = handler

proc textArea*(
    root: UiRoot;
    params = TextAreaParams();
    style = UiStyle();
    textStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["textarea"]
): TextAreaHandle {.discardable.} =
  let styleResize = style.resizeFromStyle()
  let styleWidth = style.lengthFromStyle("width")
  let styleHeight = style.lengthFromStyle("height")
  let styleMinWidth = style.lengthFromStyle("min-width")
  let styleMaxWidth = style.lengthFromStyle("max-width")
  let styleMinHeight = style.lengthFromStyle("min-height")
  let styleMaxHeight = style.lengthFromStyle("max-height")
  let textStyleWidth = textStyle.widthFrom()
  let horizontalInset = style.horizontalPaddingFromStyle()
  let verticalInset = style.verticalPaddingFromStyle()
  let leftInset = style.paddingLeftFromStyle(10.0'f32)
  let topInset = style.paddingTopFromStyle(8.0'f32)
  let initialWidth =
    if params.width.isSome: params.width
    else: styleWidth

  result.root = root
  result.state = TextAreaState(
    value: params.value,
    caret: params.value.len,
    selectionStart: params.value.len,
    selectionEnd: params.value.len,
    placeholder: params.placeholder,
    disabled: params.disabled,
    readOnly: params.readOnly,
    maxLength: params.maxLength,
    resize:
      if params.resize.isSome: params.resize.get
      elif styleResize.isSome: styleResize.get
      else: rkBoth,
    width:
      if params.width.isSome: params.width
      else: styleWidth,
    height:
      if params.height.isSome: params.height
      else: styleHeight,
    minWidth:
      if params.minWidth.isSome: params.minWidth
      else: styleMinWidth,
    maxWidth:
      if params.maxWidth.isSome: params.maxWidth
      else: styleMaxWidth,
    minHeight:
      if params.minHeight.isSome: params.minHeight
      else: styleMinHeight,
    maxHeight:
      if params.maxHeight.isSome: params.maxHeight
      else: styleMaxHeight,
    textStyle: textStyle.textStyleFrom(),
    textMaxWidth:
      if textStyleWidth.isSome: textStyleWidth
      else: textWidthForArea(initialWidth, horizontalInset),
    textMaxWidthExplicit: textStyleWidth.isSome,
    textHorizontalInset: horizontalInset,
    textVerticalInset: verticalInset,
    textLeftInset: leftInset,
    textTopInset: topInset,
    textNodeStyleDirty: true,
    caretLinesDirty: true
  )
  let maxLength = result.state.effectiveMaxLength()
  if result.state.value.len > maxLength:
    result.state.value = result.state.value.truncateAtRuneBoundary(maxLength)
    result.state.caret = result.state.value.len
    result.state.collapseSelection()
  result.container = root.box(style, id = id, groups = groups)
  result.container.setFocusable()
  result.container.setAccessibleRole(arTextArea)
  result.setValueAttribute()
  root.tree.setAttribute(result.container.id, "placeholder", result.state.placeholder)
  result.container.applyStyle(uiStyle([
    decl("overflow", keyword("hidden"))
  ]))
  if params.disabled:
    result.container.addState(esDisabled)
  for index in 0 ..< initialSelectionFragmentCount:
    let node = result.addSelectionNode()
    if index == 0:
      result.selectionNode = node
    result.selectionNodes.add node
  result.textNode = root.text(result.container, result.state.displayText(), textStyle, groups = ["textarea-value"])
  result.syncTextNodeStyle()
  result.caretNode = root.box(parent = some(result.container), groups = ["textarea-caret"])
  result.caretNode.applyStyle(uiStyle([
    decl("display", keyword("none")),
    decl("position", keyword("absolute")),
    decl("left", px(10)),
    decl("top", px(8)),
    decl("width", px(1)),
    decl("height", px(16)),
    decl("background-color", colorValue(rgb(0.92, 0.96, 1.0))),
    decl("pointer-events", keyword("none"))
  ]))
  result.scrollbarTrack = root.box(
    parent = some(result.container), groups = ["textarea-scrollbar-track"]
  )
  result.scrollbarThumb = root.box(
    parent = some(result.scrollbarTrack), groups = ["textarea-scrollbar-thumb"]
  )
  result.resizeHandle = root.box(parent = some(result.container), groups = ["textarea-resize-handle"])
  result.resizeHandle.applyStyle(uiStyle([
    decl("position", keyword("absolute")),
    decl("right", px(2)),
    decl("bottom", px(2)),
    decl("width", px(14)),
    decl("height", px(14)),
    decl("cursor", keyword("pointer"))
  ]))
  result.setSize(result.state.width, result.state.height)
  result.syncScrollbarStyle(result.caretLines())

  let area = result
  let ownDisabled = params.disabled
  root.registerFieldsetTarget(proc(disabled: bool) =
    area.setDisabled(ownDisabled or disabled)
  )

  root.events.addInternalEventHandler(area.container.id, iekFocus, proc(event: DispatchResult): EventOutcome =
    area.focus()
    false
  )
  root.events.addInternalEventHandler(area.container.id, iekPointerDown, proc(event: DispatchResult): EventOutcome =
    if area.state.disabled:
      area.state.selecting = false
      return true
    let button = if event.event.button.isSome: event.event.button.get else: 0
    if button in [0, 1] and event.local.isSome:
      area.focus()
      area.state.selecting = true
      area.moveCaretToPoint(event.local.get, extendSelection = event.event.shiftKey)
    false
  )
  root.events.addInternalEventHandler(area.container.id, iekPointerMove, proc(event: DispatchResult): EventOutcome =
    if area.state.disabled:
      area.state.selecting = false
      return true
    if area.state.selecting and event.local.isSome:
      area.moveCaretToPoint(event.local.get, extendSelection = true)
    false
  )
  root.events.addInternalEventHandler(area.container.id, iekDrag, proc(event: DispatchResult): EventOutcome =
    if area.state.disabled:
      area.state.selecting = false
      return true
    if area.state.selecting and event.local.isSome:
      area.moveCaretToPoint(event.local.get, extendSelection = true)
    false
  )
  root.events.addInternalEventHandler(area.container.id, iekPointerUp, proc(event: DispatchResult): EventOutcome =
    area.state.selecting = false
    false
  )
  root.events.addInternalEventHandler(area.container.id, iekDragEnd, proc(event: DispatchResult): EventOutcome =
    area.state.selecting = false
    false
  )
  root.events.addInternalEventHandler(area.container.id, iekWheel, proc(event: DispatchResult): EventOutcome =
    if event.event.delta.isNone:
      return false
    area.scrollBy(event.event.delta.get.y)
    true
  )
  root.events.addInternalEventHandler(area.container.id, iekScrollEnd, proc(event: DispatchResult): EventOutcome =
    area.finishScroll()
    true
  )
  root.events.addInternalEventHandler(area.scrollbarThumb.id, iekPointerDown, proc(event: DispatchResult): EventOutcome =
    if event.event.position.isNone:
      return true
    area.state.scrollbarDragging = true
    area.state.scrollbarDragStartY = event.event.position.get.y
    area.state.scrollbarDragStartScrollY = area.state.scrollY
    true
  )
  root.events.addInternalEventHandler(area.scrollbarThumb.id, iekPointerMove, proc(event: DispatchResult): EventOutcome =
    if not area.state.scrollbarDragging or event.event.position.isNone:
      return false
    let lines = area.caretLines()
    let geometry = area.scrollbarGeometry(lines)
    if geometry.isNone:
      area.state.scrollbarDragging = false
      return true
    let bar = geometry.get
    let travel = max(0.0'f32, bar.trackHeight - bar.thumbHeight)
    if travel <= 0:
      return true
    let deltaY = event.event.position.get.y - area.state.scrollbarDragStartY
    let nextScroll = area.state.scrollbarDragStartScrollY + deltaY / travel * bar.maxScroll
    area.scrollBy(nextScroll - area.state.scrollY)
    true
  )
  root.events.addInternalEventHandler(area.scrollbarThumb.id, iekPointerUp, proc(event: DispatchResult): EventOutcome =
    let wasDragging = area.state.scrollbarDragging
    area.state.scrollbarDragging = false
    wasDragging
  )
  root.events.addInternalEventHandler(area.scrollbarTrack.id, iekPointerDown, proc(event: DispatchResult): EventOutcome =
    if event.target.isSome and event.target.get == area.scrollbarThumb.nodeId:
      return false
    if event.local.isNone:
      return true
    let lines = area.caretLines()
    let geometry = area.scrollbarGeometry(lines)
    if geometry.isNone:
      return true
    let bar = geometry.get
    if event.local.get.y < bar.thumbTop:
      area.scrollBy(-area.visibleTextHeight().get)
    elif event.local.get.y > bar.thumbTop + bar.thumbHeight:
      area.scrollBy(area.visibleTextHeight().get)
    true
  )
  root.events.addInternalEventHandler(area.container.id, iekBlur, proc(event: DispatchResult): EventOutcome =
    area.blur()
    false
  )
  root.events.addInternalEventHandler(area.container.id, iekTextInput, proc(event: DispatchResult): EventOutcome =
    if area.state.disabled or area.state.readOnly:
      return true
    if event.event.text.isSome:
      let text = event.event.text.get
      if area.state.pendingFallbackText == text:
        area.state.pendingFallbackText = ""
        return true
      else:
        area.insertText(text, emitValue = true)
        return true
    false
  )
  root.events.addInternalEventHandler(area.container.id, iekPaste, proc(event: DispatchResult): EventOutcome =
    if area.state.disabled or area.state.readOnly:
      return true
    if event.event.text.isSome:
      area.insertText(event.event.text.get.normalizePastedText(), emitValue = true)
    false
  )
  root.events.addInternalEventHandler(area.container.id, iekCopy, proc(event: DispatchResult): EventOutcome =
    area.requestClipboardWrite(area.selectedText())
    false
  )
  root.events.addInternalEventHandler(area.container.id, iekCut, proc(event: DispatchResult): EventOutcome =
    area.requestClipboardWrite(area.selectedText())
    if not area.state.readOnly and area.deleteSelection():
      area.emitValueEvents()
    false
  )
  root.events.addInternalEventHandler(area.container.id, iekCompositionStart, proc(event: DispatchResult): EventOutcome =
    let text =
      if event.event.text.isSome: event.event.text.get
      else: ""
    if area.state.composingActive and area.state.composingText == text:
      return false
    area.state.pendingFallbackText = ""
    area.state.composingActive = true
    area.state.composingText = text
    area.state.compositionUpdateSeen = false
    area.state.lastCompositionUpdateText = ""
    area.setVisibleText()
    true
  )
  root.events.addInternalEventHandler(area.container.id, iekCompositionUpdate, proc(event: DispatchResult): EventOutcome =
    let text =
      if event.event.text.isSome: event.event.text.get
      else: ""
    if area.state.compositionUpdateSeen and area.state.lastCompositionUpdateText == text:
      return false
    area.state.pendingFallbackText = ""
    area.state.composingActive = true
    area.state.composingText = text
    area.state.compositionUpdateSeen = true
    area.state.lastCompositionUpdateText = text
    area.setVisibleText()
    true
  )
  root.events.addInternalEventHandler(area.container.id, iekCompositionEnd, proc(event: DispatchResult): EventOutcome =
    if not area.state.composingActive and area.state.composingText.len == 0:
      return false
    area.state.pendingFallbackText = ""
    area.state.composingActive = false
    area.state.composingText = ""
    area.state.compositionUpdateSeen = false
    area.state.lastCompositionUpdateText = ""
    area.setVisibleText()
    true
  )
  root.events.addInternalEventHandler(area.container.id, iekKeyDown, proc(event: DispatchResult): EventOutcome =
    if area.state.disabled:
      return false
    if event.event.key.isNone:
      return false
    if event.event.ctrlKey or event.event.metaKey:
      case event.event.key.get.toLowerAscii()
      of "a":
        area.selectAll()
        return true
      of "c":
        discard area.container.emit(copyEvent())
        return true
      of "insert":
        discard area.container.emit(copyEvent())
        return true
      of "x":
        discard area.container.emit(cutEvent())
        return true
      of "v":
        discard area.container.emit(pasteEvent(area.root.clipboardText()))
        return true
      of "z":
        let changed =
          if event.event.shiftKey: area.redo()
          else: area.undo()
        if changed:
          area.emitValueEvents()
          return true
      of "y":
        if area.redo():
          area.emitValueEvents()
          return true
      of "arrowleft":
        area.moveCaretWordLeft(extendSelection = event.event.shiftKey)
        return true
      of "arrowright":
        area.moveCaretWordRight(extendSelection = event.event.shiftKey)
        return true
      of "home":
        area.moveCaretTo(0, extendSelection = event.event.shiftKey)
        return true
      of "end":
        area.moveCaretTo(area.state.value.len, extendSelection = event.event.shiftKey)
        return true
      of "pageup":
        area.moveCaretPage(-1, extendSelection = event.event.shiftKey)
        return true
      of "pagedown":
        area.moveCaretPage(1, extendSelection = event.event.shiftKey)
        return true
      of "backspace":
        if area.deleteWordBackward():
          area.emitValueEvents()
          return true
      of "delete":
        if area.deleteWordForward():
          area.emitValueEvents()
          return true
      else:
        discard
      return false
    case event.event.key.get
    of "Enter":
      area.insertText("\n", emitValue = true)
      return true
    of "Backspace":
      if area.deleteComposingBackward():
        return true
      if area.deleteBackward():
        area.emitValueEvents()
        return true
    of "Delete":
      if event.event.shiftKey:
        discard area.container.emit(cutEvent())
        return true
      else:
        if area.deleteForward():
          area.emitValueEvents()
          return true
    of "Insert":
      if event.event.shiftKey:
        discard area.container.emit(pasteEvent(area.root.clipboardText()))
        return true
    of "ArrowLeft":
      area.moveCaretLeft(extendSelection = event.event.shiftKey)
      return true
    of "ArrowRight":
      area.moveCaretRight(extendSelection = event.event.shiftKey)
      return true
    of "ArrowUp":
      area.moveCaretUp(extendSelection = event.event.shiftKey)
      return true
    of "ArrowDown":
      area.moveCaretDown(extendSelection = event.event.shiftKey)
      return true
    of "PageUp":
      area.moveCaretPage(-1, extendSelection = event.event.shiftKey)
      return true
    of "PageDown":
      area.moveCaretPage(1, extendSelection = event.event.shiftKey)
      return true
    of "Home":
      area.moveCaretLineStart(extendSelection = event.event.shiftKey)
      return true
    of "End":
      area.moveCaretLineEnd(extendSelection = event.event.shiftKey)
      return true
    else:
      let typed = textFromPrintableKey(event.event)
      if typed.len > 0:
        area.insertText(typed)
        area.emitValueEvents()
        area.state.pendingFallbackText = typed
        return true
    false
  )
  root.events.addInternalEventHandler(area.resizeHandle.id, iekPointerDown, proc(event: DispatchResult): EventOutcome =
    if area.state.disabled:
      area.state.resizing = false
      return true
    if not area.resizable() or event.local.isNone:
      return true
    area.state.resizing = true
    area.state.resizeStartPointer = event.local.get
    area.state.resizeStartWidth =
      if area.state.width.isSome: area.state.width.get
      else: 0
    area.state.resizeStartHeight =
      if area.state.height.isSome: area.state.height.get
      else: 0
    area.syncResizeStyle()
    true
  )
  root.events.addInternalEventHandler(area.resizeHandle.id, iekPointerMove, proc(event: DispatchResult): EventOutcome =
    if not area.state.resizing or event.local.isNone:
      return false
    let delta = vec2(
      event.local.get.x - area.state.resizeStartPointer.x,
      event.local.get.y - area.state.resizeStartPointer.y
    )
    let nextWidth =
      if area.state.resize in {rkBoth, rkHorizontal}:
        some(area.state.resizeStartWidth + delta.x)
      else:
        none(float32)
    let nextHeight =
      if area.state.resize in {rkBoth, rkVertical}:
        some(area.state.resizeStartHeight + delta.y)
      else:
        none(float32)
    area.setSize(nextWidth, nextHeight, emitEvent = true)
    true
  )
  root.events.addInternalEventHandler(area.resizeHandle.id, iekPointerUp, proc(event: DispatchResult): EventOutcome =
    if area.state.resizing:
      area.state.resizing = false
      area.syncResizeStyle()
      return true
    false
  )
