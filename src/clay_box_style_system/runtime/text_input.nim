import std/[options, strutils]

import ../core/[color, computed_style, declaration, geometry, node, rule, selector, style_value]
import ../input/events
import ../text/text_engine
import ./ui_root

const textEdgeSlack = 2.0'f32
const maxVisibleInputBytes = 512
const maxVisibleCompositionInputBytes = 72
const maxUndoEntries = 64
const maxUndoBytes = 262_144
const defaultMaxTextInputBytes = 8_192
const maxValueAttributeBytes = 8_192

type
  TextInputParams* = object
    value*: string
    placeholder*: string
    disabled*: bool
    readOnly*: bool
    maxLength*: Option[int]

  TextInputState* = ref object
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
    pendingFallbackText*: string
    selecting*: bool
    undoStack*: seq[string]
    redoStack*: seq[string]
    textStyle*: ComputedTextStyle
    textMaxWidth*: Option[float32]
    textLeftInset*: float32
    textTopInset*: float32
    textVerticalOffset*: float32
    visibleStart*: int
    horizontalScroll*: float32
    caretStyleIndex*: Option[int]
    selectionStyleIndex*: Option[int]

  TextInputVisibleInfo = tuple[text: string, start: int, caret: int]

  TextInputHandle* = object
    root*: UiRoot
    container*: NodeHandle
    selectionNode*: NodeHandle
    textNode*: NodeHandle
    caretNode*: NodeHandle
    state*: TextInputState

proc clampCaret(state: TextInputState) =
  if state.caret < 0:
    state.caret = 0
  if state.caret > state.value.len:
    state.caret = state.value.len

proc clampSelection(state: TextInputState) =
  if state.selectionStart < 0:
    state.selectionStart = 0
  if state.selectionStart > state.value.len:
    state.selectionStart = state.value.len
  if state.selectionEnd < 0:
    state.selectionEnd = 0
  if state.selectionEnd > state.value.len:
    state.selectionEnd = state.value.len

proc selectionBounds(state: TextInputState): tuple[first, last: int] =
  state.clampSelection()
  if state.selectionStart <= state.selectionEnd:
    (state.selectionStart, state.selectionEnd)
  else:
    (state.selectionEnd, state.selectionStart)

proc hasSelection(state: TextInputState): bool =
  let bounds = state.selectionBounds()
  bounds.first != bounds.last

proc collapseSelection(state: TextInputState) =
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

proc effectiveMaxLength(state: TextInputState): int =
  if state.maxLength.isSome:
    min(state.maxLength.get, defaultMaxTextInputBytes)
  else:
    defaultMaxTextInputBytes

proc setValueAttribute(input: TextInputHandle) =
  let value =
    if input.state.value.len <= maxValueAttributeBytes:
      input.state.value
    else:
      input.state.value.truncateAtRuneBoundary(maxValueAttributeBytes)
  input.root.tree.setAttribute(input.container.id, "value", value)
  input.container.setAccessibleValue(input.state.value)

proc runeStartAtOrAfter(text: string; index: int): int =
  result = max(0, min(index, text.len))
  while result < text.len and (ord(text[result]) and 0b1100_0000) == 0b1000_0000:
    inc result

proc displayCaretIndex(state: TextInputState): int =
  result = state.caret
  if state.composingText.len > 0:
    result += state.composingText.len

proc displayValueIndex(state: TextInputState; displayIndex: int): int =
  if displayIndex <= state.caret:
    displayIndex
  elif displayIndex <= state.caret + state.composingText.len:
    state.caret
  else:
    displayIndex - state.composingText.len

proc effectiveTextMaxWidth(input: TextInputHandle): Option[float32] =
  if input.state.textMaxWidth.isSome:
    some(max(1.0'f32, input.state.textMaxWidth.get - textEdgeSlack))
  else:
    none(float32)

proc virtualDisplayLen(state: TextInputState): int =
  if state.value.len == 0 and
      state.composingText.len == 0 and
      not state.composingActive and
      state.placeholder.len > 0:
    state.placeholder.len
  else:
    state.value.len + state.composingText.len

proc virtualBoundaryAtOrAfter(state: TextInputState; index: int): int =
  let displayLen = state.virtualDisplayLen()
  result = max(0, min(index, displayLen))
  if state.value.len == 0 and
      state.composingText.len == 0 and
      not state.composingActive and
      state.placeholder.len > 0:
    return runeStartAtOrAfter(state.placeholder, result)

  let caret = max(0, min(state.caret, state.value.len))
  let compLen = state.composingText.len
  if result < caret:
    return runeStartAtOrAfter(state.value, result)
  if result < caret + compLen:
    return caret + runeStartAtOrAfter(state.composingText, result - caret)
  return compLen + runeStartAtOrAfter(state.value, result - compLen)

proc virtualPreviousRuneStart(state: TextInputState; index: int): int =
  let displayLen = state.virtualDisplayLen()
  let position = max(0, min(index, displayLen))
  if position <= 0:
    return 0
  if state.value.len == 0 and
      state.composingText.len == 0 and
      not state.composingActive and
      state.placeholder.len > 0:
    return previousRuneStart(state.placeholder, position)

  let caret = max(0, min(state.caret, state.value.len))
  let compLen = state.composingText.len
  if position <= caret:
    return previousRuneStart(state.value, position)
  if position <= caret + compLen:
    return caret + previousRuneStart(state.composingText, position - caret)
  compLen + previousRuneStart(state.value, position - compLen)

proc virtualDisplaySlice(state: TextInputState; first, last: int): string =
  let displayLen = state.virtualDisplayLen()
  let start = max(0, min(first, displayLen))
  let stop = max(start, min(last, displayLen))
  if start >= stop:
    return ""
  if state.value.len == 0 and
      state.composingText.len == 0 and
      not state.composingActive and
      state.placeholder.len > 0:
    return state.placeholder[start ..< stop]

  let caret = max(0, min(state.caret, state.value.len))
  let compLen = state.composingText.len
  let compStart = caret
  let compStop = caret + compLen

  if start < compStart:
    let valueStop = min(stop, compStart)
    result.add state.value[start ..< valueStop]
  if start < compStop and stop > compStart:
    let localStart = max(start, compStart) - compStart
    let localStop = min(stop, compStop) - compStart
    if localStart < localStop:
      result.add state.composingText[localStart ..< localStop]
  if stop > compStop:
    let valueStart = max(start, compStop) - compLen
    let valueStop = stop - compLen
    if valueStart < valueStop:
      result.add state.value[valueStart ..< valueStop]

proc visibleInputInfo(input: TextInputHandle): TextInputVisibleInfo =
  let displayLen = input.state.virtualDisplayLen()
  let caretDisplay = input.state.virtualBoundaryAtOrAfter(input.state.displayCaretIndex())
  proc windowStop(first: int): int =
    result = input.state.virtualBoundaryAtOrAfter(
      min(displayLen, first + maxVisibleInputBytes)
    )
    if result - first > maxVisibleInputBytes:
      result = input.state.virtualPreviousRuneStart(result)

  var start =
    if displayLen <= maxVisibleInputBytes:
      0
    else:
      input.state.virtualBoundaryAtOrAfter(
        max(0, min(input.state.visibleStart, displayLen))
      )
  var stop = windowStop(start)
  if caretDisplay < start or caretDisplay > stop or
      (caretDisplay == stop and caretDisplay < displayLen):
    let bytesBeforeCaret = maxVisibleInputBytes * 3 div 4
    start = input.state.virtualBoundaryAtOrAfter(
      max(0, caretDisplay - bytesBeforeCaret)
    )
    if start > caretDisplay:
      start = input.state.virtualPreviousRuneStart(caretDisplay)
    stop = windowStop(start)
  if stop < caretDisplay:
    stop = caretDisplay

  if input.state.composingText.len > 0 and caretDisplay - start > maxVisibleCompositionInputBytes:
    start = input.state.virtualBoundaryAtOrAfter(max(0, caretDisplay - maxVisibleCompositionInputBytes))
    stop = windowStop(start)

  input.state.visibleStart = start

  result.text =
    if start < stop: input.state.virtualDisplaySlice(start, stop)
    else: ""
  result.start = start
  result.caret = caretDisplay - result.start
  if result.caret < 0:
    result.caret = 0
  if result.caret > result.text.len:
    result.caret = result.text.len

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
    else:
      discard

proc widthFrom(style: UiStyle): Option[float32] =
  for declaration in style.declarations:
    if declaration.property == "width" and declaration.operation.value.isSome:
      let value = declaration.operation.value.get
      if value.kind == svLength and value.length.kind == ukPx:
        return some(value.length.value)
  none(float32)

proc lengthFromStyle(style: UiStyle; property: string): Option[float32] =
  for declaration in style.declarations:
    if declaration.property == property and declaration.operation.value.isSome:
      let value = declaration.operation.value.get
      if value.kind == svLength and value.length.kind == ukPx:
        return some(value.length.value)
  none(float32)

proc paddingLeftFromStyle(style: UiStyle; fallback: float32): float32 =
  if style.lengthFromStyle("padding-left").isSome:
    return style.lengthFromStyle("padding-left").get
  if style.lengthFromStyle("padding-inline").isSome:
    return style.lengthFromStyle("padding-inline").get
  if style.lengthFromStyle("padding").isSome:
    return style.lengthFromStyle("padding").get
  fallback

proc paddingRightFromStyle(style: UiStyle; fallback: float32): float32 =
  if style.lengthFromStyle("padding-right").isSome:
    return style.lengthFromStyle("padding-right").get
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

proc paddingBottomFromStyle(style: UiStyle; fallback: float32): float32 =
  if style.lengthFromStyle("padding-bottom").isSome:
    return style.lengthFromStyle("padding-bottom").get
  if style.lengthFromStyle("padding-block").isSome:
    return style.lengthFromStyle("padding-block").get
  if style.lengthFromStyle("padding").isSome:
    return style.lengthFromStyle("padding").get
  fallback

proc alignsItemsCenter(style: UiStyle): bool =
  for declaration in style.declarations:
    if declaration.property == "align-items" and declaration.operation.value.isSome:
      let value = declaration.operation.value.get
      return value.kind == svKeyword and value.keyword == "center"
  false

proc verticalTextOffset(style: UiStyle; textStyle: ComputedTextStyle): float32 =
  if not style.alignsItemsCenter:
    return 0.0'f32
  let height = style.lengthFromStyle("height")
  if height.isNone:
    return 0.0'f32
  let lineHeight =
    if textStyle.lineHeight.isSome: textStyle.lineHeight.get
    elif textStyle.fontSize.isSome: textStyle.fontSize.get * 1.2'f32
    else: 16.0'f32 * 1.2'f32
  let contentHeight = max(0.0'f32,
    height.get - style.paddingTopFromStyle(9.0'f32) - style.paddingBottomFromStyle(9.0'f32))
  max(0.0'f32, (contentHeight - lineHeight) * 0.5'f32)

proc textWidthForInput(width: Option[float32]; leftInset, rightInset: float32): Option[float32] =
  if width.isNone:
    return none(float32)
  some(max(1.0'f32, width.get - leftInset - rightInset))

proc syncHorizontalViewport(
    input: TextInputHandle;
    visible: TextInputVisibleInfo
): TextCaretResult =
  result = input.root.textEngine.caret(TextCaretInput(
    text: visible.text,
    style: input.state.textStyle,
    maxWidth: none(float32),
    fonts: input.root.fonts,
    byteIndex: visible.caret
  ))
  let textEnd = input.root.textEngine.caret(TextCaretInput(
    text: visible.text,
    style: input.state.textStyle,
    maxWidth: none(float32),
    fonts: input.root.fonts,
    byteIndex: visible.text.len
  ))
  if input.effectiveTextMaxWidth().isSome:
    let viewportWidth = input.effectiveTextMaxWidth().get
    let maxScroll = max(0.0'f32, textEnd.position.x - viewportWidth)
    input.state.horizontalScroll = min(max(0.0'f32, input.state.horizontalScroll), maxScroll)
    let viewportCaretX = result.position.x - input.state.horizontalScroll
    if viewportCaretX < 0.0'f32:
      input.state.horizontalScroll = result.position.x
    elif viewportCaretX > viewportWidth:
      input.state.horizontalScroll = result.position.x - viewportWidth
    input.state.horizontalScroll = min(max(0.0'f32, input.state.horizontalScroll), maxScroll)
  else:
    input.state.horizontalScroll = 0.0'f32

  let textNodeIndex = input.textNode.id.nodeIndex
  input.root.tree.nodes[textNodeIndex].renderOffset = vec2(-input.state.horizontalScroll, 0)
  input.root.tree.nodes[textNodeIndex].textRenderWidth = some(max(1.0'f32, textEnd.position.x + textEdgeSlack))

proc syncCaretStyle(
    input: TextInputHandle;
    caret: TextCaretResult
) =
  let caretLeft =
    if input.effectiveTextMaxWidth().isSome:
      min(
        max(0.0'f32, caret.position.x - input.state.horizontalScroll),
        input.effectiveTextMaxWidth().get
      )
    else:
      caret.position.x
  let metrics = input.state.textStyle.caretVisualMetrics(caret.height)
  let sheet = styleSheet([
    rule(
      target(input.caretNode.id),
      [
        decl("display", keyword(if input.state.focused: "flex" else: "none")),
        decl("left", px(caretLeft)),
        decl("top", px(input.state.textVerticalOffset + caret.position.y + metrics.offset)),
        decl("height", px(metrics.height))
      ],
      priority = 900
    )
  ])
  if input.state.caretStyleIndex.isSome and input.state.caretStyleIndex.get < input.root.componentStyles.len:
    input.root.componentStyles[input.state.caretStyleIndex.get] = sheet
  else:
    input.root.componentStyles.add sheet
    input.state.caretStyleIndex = some(input.root.componentStyles.len - 1)

proc syncSelectionStyle(input: TextInputHandle; visible: TextInputVisibleInfo) =
  let bounds = input.state.selectionBounds()
  let visibleStart = visible.start
  let visibleEnd = visible.start + visible.text.len
  let first = max(bounds.first, visibleStart) - visibleStart
  let last = min(bounds.last, visibleEnd) - visibleStart
  var left = 0.0'f32
  var width = 0.0'f32
  var top = 0.0'f32
  var height = 0.0'f32
  var show = input.state.focused and bounds.first != bounds.last and first < last
  if show:
    let startCaret = input.root.textEngine.caret(TextCaretInput(
      text: visible.text,
      style: input.state.textStyle,
      maxWidth: none(float32),
      fonts: input.root.fonts,
      byteIndex: first
    ))
    let endCaret = input.root.textEngine.caret(TextCaretInput(
      text: visible.text,
      style: input.state.textStyle,
      maxWidth: none(float32),
      fonts: input.root.fonts,
      byteIndex: last
    ))
    let rawLeft = min(startCaret.position.x, endCaret.position.x) - input.state.horizontalScroll
    let rawRight = max(startCaret.position.x, endCaret.position.x) - input.state.horizontalScroll
    left = max(0.0'f32, rawLeft)
    let right =
      if input.effectiveTextMaxWidth().isSome:
        min(input.effectiveTextMaxWidth().get, rawRight)
      else:
        rawRight
    width = max(0.0'f32, right - left)
    show = width > 0.0'f32
    top = min(startCaret.position.y, endCaret.position.y)
    height = max(1.0'f32, max(startCaret.height, endCaret.height))
  let sheet = styleSheet([
    rule(
      target(input.selectionNode.id),
      [
        decl("display", keyword(if show: "flex" else: "none")),
        decl("left", px(left)),
        decl("top", px(top)),
        decl("width", px(width)),
        decl("height", px(height))
      ],
      priority = 895
    )
  ])
  if input.state.selectionStyleIndex.isSome and input.state.selectionStyleIndex.get < input.root.componentStyles.len:
    input.root.componentStyles[input.state.selectionStyleIndex.get] = sheet
  else:
    input.root.componentStyles.add sheet
    input.state.selectionStyleIndex = some(input.root.componentStyles.len - 1)

proc setVisibleText(input: TextInputHandle) =
  when defined(cbssTracePerf):
    echo "[text-input-detail] visible begin value=", input.state.value.len,
      " caret=", input.state.caret
    flushFile(stdout)
  let visible = input.visibleInputInfo()
  when defined(cbssTracePerf):
    echo "[text-input-detail] visible range end bytes=", visible.text.len,
      " start=", visible.start, " localCaret=", visible.caret
    flushFile(stdout)
  input.setValueAttribute()
  input.root.tree.setAttribute(input.container.id, "caret", $input.state.caret)
  input.root.tree.setAttribute(input.container.id, "selection-start", $input.state.selectionStart)
  input.root.tree.setAttribute(input.container.id, "selection-end", $input.state.selectionEnd)
  input.root.tree.nodes[input.textNode.id.nodeIndex].text = visible.text
  let caret = input.syncHorizontalViewport(visible)
  when defined(cbssTracePerf):
    echo "[text-input-detail] selection begin"
    flushFile(stdout)
  input.syncSelectionStyle(visible)
  when defined(cbssTracePerf):
    echo "[text-input-detail] caret begin"
    flushFile(stdout)
  input.syncCaretStyle(caret)
  when defined(cbssTracePerf):
    echo "[text-input-detail] visible end"
    flushFile(stdout)

proc syncTextChrome(input: TextInputHandle) =
  let visible = input.visibleInputInfo()
  input.root.tree.setAttribute(input.container.id, "caret", $input.state.caret)
  input.root.tree.setAttribute(input.container.id, "selection-start", $input.state.selectionStart)
  input.root.tree.setAttribute(input.container.id, "selection-end", $input.state.selectionEnd)
  input.root.tree.nodes[input.textNode.id.nodeIndex].text = visible.text
  let caret = input.syncHorizontalViewport(visible)
  input.syncSelectionStyle(visible)
  input.syncCaretStyle(caret)

proc emitValueEvents(input: TextInputHandle) =
  discard input.container.emit(inputEvent(input.state.value))
  discard input.container.emit(changeEvent(input.state.value))

proc emitInputEvent(input: TextInputHandle) =
  discard input.container.emit(inputEvent(input.state.value))

proc emitSelect(input: TextInputHandle) =
  discard input.container.emit(iekSelect)

proc trimUndoStack(stack: var seq[string]) =
  while stack.len > maxUndoEntries:
    stack.delete(0)
  var total = 0
  for item in stack:
    total += item.len
  while stack.len > 0 and total > maxUndoBytes:
    total -= stack[0].len
    stack.delete(0)

proc rememberUndo(input: TextInputHandle) =
  if input.state.undoStack.len == 0 or input.state.undoStack[^1] != input.state.value:
    input.state.undoStack.add input.state.value
    input.state.undoStack.trimUndoStack()
  input.state.redoStack.setLen(0)

proc rememberUndoValue(input: TextInputHandle; value: string) =
  if input.state.undoStack.len == 0 or input.state.undoStack[^1] != value:
    input.state.undoStack.add value
    input.state.undoStack.trimUndoStack()
  input.state.redoStack.setLen(0)

proc restoreValue(input: TextInputHandle; value: string) =
  input.state.value = value
  input.state.caret = input.state.value.len
  input.state.collapseSelection()
  input.state.composingText = ""
  input.state.composingActive = false
  input.state.pendingFallbackText = ""
  input.setVisibleText()

proc undo(input: TextInputHandle): bool =
  if input.state.readOnly or input.state.undoStack.len == 0:
    return false
  let previous = input.state.undoStack.pop()
  input.state.redoStack.add input.state.value
  input.state.redoStack.trimUndoStack()
  input.restoreValue(previous)
  true

proc redo(input: TextInputHandle): bool =
  if input.state.readOnly or input.state.redoStack.len == 0:
    return false
  let next = input.state.redoStack.pop()
  input.state.undoStack.add input.state.value
  input.state.undoStack.trimUndoStack()
  input.restoreValue(next)
  true

proc deleteSelection(input: TextInputHandle; recordUndo = true; refresh = true): bool =
  if input.state.disabled or input.state.readOnly or not input.state.hasSelection():
    return false
  if recordUndo:
    input.rememberUndo()
  let bounds = input.state.selectionBounds()
  input.state.value.delete(bounds.first .. bounds.last - 1)
  input.state.caret = bounds.first
  input.state.collapseSelection()
  input.state.composingText = ""
  input.state.composingActive = false
  input.state.pendingFallbackText = ""
  if refresh:
    input.setVisibleText()
  true

proc insertText(input: TextInputHandle; text: string; emitValue = false) =
  if input.state.disabled or input.state.readOnly or text.len == 0:
    return
  input.state.clampCaret()
  when defined(cbssTracePerf):
    echo "[text-input-detail] insert begin value=", input.state.value.len,
      " bytes=", text.len, " caret=", input.state.caret
    flushFile(stdout)
  let oldValue = input.state.value
  discard input.deleteSelection(recordUndo = false, refresh = false)
  when defined(cbssTracePerf):
    echo "[text-input-detail] selection deleted value=", input.state.value.len,
      " caret=", input.state.caret
    flushFile(stdout)
  var inserted = text
  let remaining = input.state.effectiveMaxLength() - input.state.value.len
  if remaining <= 0:
    if input.state.value != oldValue:
      input.rememberUndoValue(oldValue)
      input.setVisibleText()
      if emitValue:
        input.emitValueEvents()
    return
  inserted = inserted.truncateAtRuneBoundary(remaining)
  if inserted.len == 0:
    if input.state.value != oldValue:
      input.rememberUndoValue(oldValue)
      input.setVisibleText()
      if emitValue:
        input.emitValueEvents()
    return
  input.rememberUndoValue(oldValue)
  when defined(cbssTracePerf):
    echo "[text-input-detail] undo stored entries=", input.state.undoStack.len
    flushFile(stdout)
  input.state.value.insert(inserted, input.state.caret)
  input.state.caret += inserted.len
  input.state.collapseSelection()
  input.state.composingText = ""
  input.state.composingActive = false
  when defined(cbssTracePerf):
    echo "[text-input-detail] string inserted value=", input.state.value.len,
      " caret=", input.state.caret
    flushFile(stdout)
  input.setVisibleText()
  if emitValue:
    when defined(cbssTracePerf):
      echo "[text-input-detail] value events begin"
      flushFile(stdout)
    input.emitValueEvents()
    when defined(cbssTracePerf):
      echo "[text-input-detail] value events end"
      flushFile(stdout)

proc deleteBackward(input: TextInputHandle): bool =
  if input.state.readOnly:
    return false
  if input.deleteSelection():
    return true
  if input.state.disabled or input.state.caret <= 0 or input.state.value.len == 0:
    return false
  input.state.clampCaret()
  let start = previousRuneStart(input.state.value, input.state.caret)
  input.rememberUndo()
  input.state.value.delete(start .. input.state.caret - 1)
  input.state.caret = start
  input.state.collapseSelection()
  input.setVisibleText()
  true

proc deleteComposingBackward(input: TextInputHandle): bool =
  if input.state.readOnly or input.state.disabled or input.state.composingText.len == 0:
    return false
  let start = previousRuneStart(input.state.composingText, input.state.composingText.len)
  input.state.composingText.delete(start .. input.state.composingText.len - 1)
  if input.state.composingText.len == 0:
    input.state.composingActive = false
  input.setVisibleText()
  true

proc deleteForward(input: TextInputHandle): bool =
  if input.state.readOnly:
    return false
  if input.deleteSelection():
    return true
  if input.state.disabled or input.state.caret >= input.state.value.len:
    return false
  input.state.clampCaret()
  let stop = nextRuneEnd(input.state.value, input.state.caret)
  input.rememberUndo()
  input.state.value.delete(input.state.caret .. stop - 1)
  input.state.collapseSelection()
  input.setVisibleText()
  true

proc deleteWordBackward(input: TextInputHandle): bool =
  if input.state.readOnly:
    return false
  if input.deleteSelection():
    return true
  if input.state.disabled or input.state.caret <= 0 or input.state.value.len == 0:
    return false
  input.state.clampCaret()
  let start = previousWordStart(input.state.value, input.state.caret)
  if start == input.state.caret:
    return false
  input.rememberUndo()
  input.state.value.delete(start .. input.state.caret - 1)
  input.state.caret = start
  input.state.collapseSelection()
  input.setVisibleText()
  true

proc deleteWordForward(input: TextInputHandle): bool =
  if input.state.readOnly:
    return false
  if input.deleteSelection():
    return true
  if input.state.disabled or input.state.caret >= input.state.value.len:
    return false
  input.state.clampCaret()
  let stop = nextWordEnd(input.state.value, input.state.caret)
  if stop == input.state.caret:
    return false
  input.rememberUndo()
  input.state.value.delete(input.state.caret .. stop - 1)
  input.state.collapseSelection()
  input.setVisibleText()
  true

proc moveCaretLeft(input: TextInputHandle; extendSelection = false) =
  let hadSelection = input.state.hasSelection()
  input.state.clampCaret()
  if input.state.caret > 0:
    input.state.caret = previousRuneStart(input.state.value, input.state.caret)
  if extendSelection:
    input.state.selectionEnd = input.state.caret
  else:
    input.state.collapseSelection()
  if extendSelection or hadSelection:
    input.emitSelect()
  input.syncTextChrome()

proc moveCaretRight(input: TextInputHandle; extendSelection = false) =
  let hadSelection = input.state.hasSelection()
  input.state.clampCaret()
  if input.state.caret < input.state.value.len:
    input.state.caret = nextRuneEnd(input.state.value, input.state.caret)
  if extendSelection:
    input.state.selectionEnd = input.state.caret
  else:
    input.state.collapseSelection()
  if extendSelection or hadSelection:
    input.emitSelect()
  input.syncTextChrome()

proc moveCaretTo(input: TextInputHandle; caret: int; extendSelection = false) =
  let hadSelection = input.state.hasSelection()
  input.state.caret = caret
  input.state.clampCaret()
  if extendSelection:
    input.state.selectionEnd = input.state.caret
  else:
    input.state.collapseSelection()
  if extendSelection or hadSelection:
    input.emitSelect()
  input.setVisibleText()

proc moveCaretWordLeft(input: TextInputHandle; extendSelection = false) =
  let hadSelection = input.state.hasSelection()
  input.state.clampCaret()
  input.state.caret = previousWordStart(input.state.value, input.state.caret)
  if extendSelection:
    input.state.selectionEnd = input.state.caret
  else:
    input.state.collapseSelection()
  if extendSelection or hadSelection:
    input.emitSelect()
  input.setVisibleText()

proc moveCaretWordRight(input: TextInputHandle; extendSelection = false) =
  let hadSelection = input.state.hasSelection()
  input.state.clampCaret()
  input.state.caret = nextWordEnd(input.state.value, input.state.caret)
  if extendSelection:
    input.state.selectionEnd = input.state.caret
  else:
    input.state.collapseSelection()
  if extendSelection or hadSelection:
    input.emitSelect()
  input.setVisibleText()

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
    case ch
    of 'a'..'z':
      result = ($ch).toUpperAscii()
    of '1':
      result = "!"
    of '2':
      result = "@"
    of '3':
      result = "#"
    of '4':
      result = "$"
    of '5':
      result = "%"
    of '6':
      result = "^"
    of '7':
      result = "&"
    of '8':
      result = "*"
    of '9':
      result = "("
    of '0':
      result = ")"
    of '-':
      result = "_"
    of '=':
      result = "+"
    of '[':
      result = "{"
    of ']':
      result = "}"
    of '\\':
      result = "|"
    of ';':
      result = ":"
    of '\'':
      result = "\""
    of ',':
      result = "<"
    of '.':
      result = ">"
    of '/':
      result = "?"
    of '`':
      result = "~"
    else:
      result = $ch
  else:
    result = $ch

proc requestClipboardWrite(input: TextInputHandle; text: string) =
  input.state.clipboardText = text
  input.state.clipboardWriteRequested = text.len > 0
  if text.len > 0:
    input.root.writeClipboardText(text)

proc value*(input: TextInputHandle): string =
  input.state.value

proc selectedText*(input: TextInputHandle): string =
  if not input.state.hasSelection():
    return ""
  let bounds = input.state.selectionBounds()
  input.state.value[bounds.first ..< bounds.last]

proc takeClipboardText*(input: TextInputHandle): string =
  result = input.state.clipboardText
  input.state.clipboardText = ""
  input.state.clipboardWriteRequested = false

proc setValue*(input: TextInputHandle; value: string) =
  let maxLength = input.state.effectiveMaxLength()
  if value.len > maxLength:
    input.state.value = value.truncateAtRuneBoundary(maxLength)
  else:
    input.state.value = value
  input.state.caret = input.state.value.len
  input.state.collapseSelection()
  input.state.composingText = ""
  input.state.composingActive = false
  input.setVisibleText()

proc setSelection*(input: TextInputHandle; first, last: int) =
  input.state.selectionStart = first
  input.state.selectionEnd = last
  input.state.clampSelection()
  input.state.caret = input.state.selectionEnd
  input.emitSelect()
  input.syncTextChrome()

proc moveCaretToPoint*(input: TextInputHandle; local: Vec2; extendSelection = false) =
  let visible = input.visibleInputInfo()
  let viewportX =
    if input.effectiveTextMaxWidth().isSome:
      min(
        max(0.0'f32, local.x - input.state.textLeftInset),
        input.effectiveTextMaxWidth().get
      )
    else:
      max(0.0'f32, local.x - input.state.textLeftInset)
  let textX = viewportX + input.state.horizontalScroll
  let hit = input.root.textEngine.hit(TextHitInput(
    text: visible.text,
    style: input.state.textStyle,
    maxWidth: none(float32),
    fonts: input.root.fonts,
    point: vec2(textX, 0.0'f32)
  ))
  input.state.caret = input.state.displayValueIndex(visible.start + hit.byteIndex)
  input.state.clampCaret()
  if extendSelection:
    input.state.selectionEnd = input.state.caret
    input.emitSelect()
  else:
    input.state.collapseSelection()
  input.setVisibleText()

proc selectAll*(input: TextInputHandle) =
  input.state.selectionStart = 0
  input.state.selectionEnd = input.state.value.len
  input.state.caret = input.state.selectionEnd
  input.emitSelect()
  input.setVisibleText()

proc focus*(input: TextInputHandle) =
  if input.state.disabled:
    return
  input.state.focused = true
  input.container.addState(esFocus)
  input.setVisibleText()

proc blur*(input: TextInputHandle) =
  input.state.focused = false
  input.container.removeState(esFocus)
  input.state.collapseSelection()
  input.state.composingText = ""
  input.state.composingActive = false
  input.state.pendingFallbackText = ""
  input.setVisibleText()

proc setDisabled*(input: TextInputHandle; disabled: bool) =
  input.state.disabled = disabled
  input.container.setState(esDisabled, disabled)
  if disabled:
    input.blur()

proc textInput*(
    root: UiRoot;
    params = TextInputParams();
    style = UiStyle();
    textStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["text-input"]
): TextInputHandle {.discardable.} =
  let textStyleWidth = textStyle.widthFrom()
  let styleWidth = style.lengthFromStyle("width")
  let leftInset = style.paddingLeftFromStyle(12.0'f32)
  let rightInset = style.paddingRightFromStyle(12.0'f32)
  result.root = root
  let resolvedTextStyle = textStyle.textStyleFrom()
  result.state = TextInputState(
    value: params.value,
    caret: params.value.len,
    selectionStart: params.value.len,
    selectionEnd: params.value.len,
    placeholder: params.placeholder,
    disabled: params.disabled,
    readOnly: params.readOnly,
    maxLength: params.maxLength,
    textStyle: resolvedTextStyle,
    textMaxWidth:
      if textStyleWidth.isSome: textStyleWidth
      else: textWidthForInput(styleWidth, leftInset, rightInset),
    textLeftInset: leftInset,
    textTopInset: style.paddingTopFromStyle(9.0'f32),
    textVerticalOffset: style.verticalTextOffset(resolvedTextStyle)
  )
  let maxLength = result.state.effectiveMaxLength()
  if result.state.value.len > maxLength:
    result.state.value = result.state.value.truncateAtRuneBoundary(maxLength)
    result.state.caret = result.state.value.len
    result.state.collapseSelection()
  result.container = root.box(style, id = id, groups = groups)
  result.container.setFocusable()
  result.container.setAccessibleRole(arTextBox)
  result.container.applyStyle(uiStyle([
    decl("overflow", keyword("hidden"))
  ]))
  result.setValueAttribute()
  root.tree.setAttribute(result.container.id, "placeholder", result.state.placeholder)
  if params.disabled:
    result.container.addState(esDisabled)
  result.selectionNode = root.box(parent = some(result.container), groups = ["text-input-selection"])
  result.selectionNode.applyStyle(uiStyle([
    decl("display", keyword("none")),
    decl("position", keyword("absolute")),
    decl("left", px(0)),
    decl("top", px(0)),
    decl("width", px(0)),
    decl("height", px(0)),
    decl("background-color", colorValue(rgba(0.18, 0.48, 0.78, 0.46))),
    decl("border-radius", px(2)),
    decl("pointer-events", keyword("none"))
  ]))
  result.textNode = root.text(result.container, "", textStyle, groups = ["text-input-value"])
  result.textNode.applyStyle(uiStyle([
    decl("pointer-events", keyword("none"))
  ]))
  result.caretNode = root.box(parent = some(result.container), groups = ["text-input-caret"])
  result.caretNode.applyStyle(uiStyle([
    decl("display", keyword("none")),
    decl("position", keyword("absolute")),
    decl("left", px(12)),
    decl("top", px(9)),
    decl("width", px(1)),
    decl("height", px(18)),
    decl("background-color", colorValue(rgb(0.92, 0.96, 1.0))),
    decl("pointer-events", keyword("none"))
  ]))
  result.setVisibleText()

  let input = result
  let ownDisabled = params.disabled
  root.registerFieldsetTarget(proc(disabled: bool) =
    input.setDisabled(ownDisabled or disabled)
  )

  root.events.addInternalEventHandler(input.container.id, iekFocus, proc(event: DispatchResult): bool =
    input.focus()
    false
  )
  root.events.addInternalEventHandler(input.container.id, iekPointerDown, proc(event: DispatchResult): bool =
    if input.state.disabled:
      input.state.selecting = false
      return true
    let button = if event.event.button.isSome: event.event.button.get else: 0
    if button in [0, 1] and event.local.isSome:
      input.focus()
      input.state.selecting = true
      input.moveCaretToPoint(event.local.get, extendSelection = event.event.shiftKey)
    false
  )
  root.events.addInternalEventHandler(input.container.id, iekPointerMove, proc(event: DispatchResult): bool =
    if input.state.disabled:
      input.state.selecting = false
      return true
    if input.state.selecting and event.local.isSome:
      input.moveCaretToPoint(event.local.get, extendSelection = true)
    false
  )
  root.events.addInternalEventHandler(input.container.id, iekDrag, proc(event: DispatchResult): bool =
    if input.state.disabled:
      input.state.selecting = false
      return true
    if input.state.selecting and event.local.isSome:
      input.moveCaretToPoint(event.local.get, extendSelection = true)
    false
  )
  root.events.addInternalEventHandler(input.container.id, iekPointerUp, proc(event: DispatchResult): bool =
    input.state.selecting = false
    false
  )
  root.events.addInternalEventHandler(input.container.id, iekDragEnd, proc(event: DispatchResult): bool =
    input.state.selecting = false
    false
  )
  root.events.addInternalEventHandler(input.container.id, iekBlur, proc(event: DispatchResult): bool =
    input.blur()
    false
  )
  root.events.addInternalEventHandler(input.container.id, iekTextInput, proc(event: DispatchResult): bool =
    if input.state.disabled or input.state.readOnly:
      return true
    if event.event.text.isSome:
      let text = event.event.text.get
      if input.state.pendingFallbackText == text:
        input.state.pendingFallbackText = ""
        return true
      else:
        input.insertText(text, emitValue = true)
        return true
    false
  )
  root.events.addInternalEventHandler(input.container.id, iekPaste, proc(event: DispatchResult): bool =
    if input.state.disabled or input.state.readOnly:
      return true
    if event.event.text.isSome:
      input.insertText(event.event.text.get, emitValue = true)
    false
  )
  root.events.addInternalEventHandler(input.container.id, iekCopy, proc(event: DispatchResult): bool =
    input.requestClipboardWrite(input.selectedText())
    false
  )
  root.events.addInternalEventHandler(input.container.id, iekCut, proc(event: DispatchResult): bool =
    input.requestClipboardWrite(input.selectedText())
    if not input.state.readOnly and input.deleteSelection():
      input.emitValueEvents()
    false
  )
  root.events.addInternalEventHandler(input.container.id, iekCompositionStart, proc(event: DispatchResult): bool =
    let text =
      if event.event.text.isSome: event.event.text.get
      else: ""
    if input.state.composingActive and input.state.composingText == text:
      return false
    input.state.pendingFallbackText = ""
    input.state.composingActive = true
    input.state.composingText = text
    input.state.compositionUpdateSeen = false
    input.state.lastCompositionUpdateText = ""
    input.setVisibleText()
    true
  )
  root.events.addInternalEventHandler(input.container.id, iekCompositionUpdate, proc(event: DispatchResult): bool =
    let text =
      if event.event.text.isSome: event.event.text.get
      else: ""
    if input.state.compositionUpdateSeen and input.state.lastCompositionUpdateText == text:
      return false
    input.state.pendingFallbackText = ""
    input.state.composingActive = true
    input.state.composingText = text
    input.state.compositionUpdateSeen = true
    input.state.lastCompositionUpdateText = text
    input.setVisibleText()
    true
  )
  root.events.addInternalEventHandler(input.container.id, iekCompositionEnd, proc(event: DispatchResult): bool =
    if not input.state.composingActive and input.state.composingText.len == 0:
      return false
    input.state.pendingFallbackText = ""
    input.state.composingActive = false
    input.state.composingText = ""
    input.state.compositionUpdateSeen = false
    input.state.lastCompositionUpdateText = ""
    input.setVisibleText()
    true
  )
  root.events.addInternalEventHandler(input.container.id, iekKeyDown, proc(event: DispatchResult): bool =
    if input.state.disabled:
      return false
    if event.event.key.isNone:
      return false
    if event.event.ctrlKey or event.event.metaKey:
      case event.event.key.get.toLowerAscii()
      of "a":
        input.selectAll()
        return true
      of "c":
        discard input.container.emit(copyEvent())
        return true
      of "insert":
        discard input.container.emit(copyEvent())
        return true
      of "x":
        discard input.container.emit(cutEvent())
        return true
      of "v":
        discard input.container.emit(pasteEvent(input.root.clipboardText()))
        return true
      of "z":
        let changed =
          if event.event.shiftKey: input.redo()
          else: input.undo()
        if changed:
          input.emitValueEvents()
          return true
      of "y":
        if input.redo():
          input.emitValueEvents()
          return true
      of "arrowleft":
        input.moveCaretWordLeft(extendSelection = event.event.shiftKey)
        return true
      of "arrowright":
        input.moveCaretWordRight(extendSelection = event.event.shiftKey)
        return true
      of "home":
        input.moveCaretTo(0, extendSelection = event.event.shiftKey)
        return true
      of "end":
        input.moveCaretTo(input.state.value.len, extendSelection = event.event.shiftKey)
        return true
      of "backspace":
        if input.deleteWordBackward():
          input.emitValueEvents()
          return true
      of "delete":
        if input.deleteWordForward():
          input.emitValueEvents()
          return true
      else:
        discard
      return false
    case event.event.key.get
    of "Backspace":
      if input.deleteComposingBackward():
        return true
      if input.deleteBackward():
        input.emitValueEvents()
        return true
    of "Delete":
      if event.event.shiftKey:
        discard input.container.emit(cutEvent())
        return true
      else:
        if input.deleteForward():
          input.emitValueEvents()
          return true
    of "Insert":
      if event.event.shiftKey:
        discard input.container.emit(pasteEvent(input.root.clipboardText()))
        return true
    of "ArrowLeft":
      input.moveCaretLeft(extendSelection = event.event.shiftKey)
      return true
    of "ArrowRight":
      input.moveCaretRight(extendSelection = event.event.shiftKey)
      return true
    of "ArrowUp", "PageUp":
      input.moveCaretTo(0, extendSelection = event.event.shiftKey)
      return true
    of "ArrowDown", "PageDown":
      input.moveCaretTo(input.state.value.len, extendSelection = event.event.shiftKey)
      return true
    of "Home":
      input.moveCaretTo(0, extendSelection = event.event.shiftKey)
      return true
    of "End":
      input.moveCaretTo(input.state.value.len, extendSelection = event.event.shiftKey)
      return true
    else:
      let typed = textFromPrintableKey(event.event)
      if typed.len > 0:
        input.insertText(typed)
        input.emitInputEvent()
        input.state.pendingFallbackText = typed
        return true
    false
  )
