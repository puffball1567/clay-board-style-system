import std/[options, strutils, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

suite "text input component":
  proc lengthDecl(rule: StyleRule; property: string): Option[float32] =
    for declaration in rule.declarations:
      if declaration.property == property and declaration.operation.value.isSome:
        let value = declaration.operation.value.get
        if value.kind == svLength and value.length.kind == ukPx:
          return some(value.length.value)
    none(float32)

  proc caretDecl(input: TextInputHandle; property: string): Option[float32] =
    if input.state.caretStyleIndex.isNone:
      return none(float32)
    let index = input.state.caretStyleIndex.get
    if index < 0 or index >= input.root.componentStyles.len:
      return none(float32)
    for rule in input.root.componentStyles[index].rules:
      let value = rule.lengthDecl(property)
      if value.isSome:
        return value
    none(float32)

  proc checkClose(actual, expected: float32; epsilon = 0.01'f32) =
    check abs(actual - expected) <= epsilon

  proc expectedCaretLeft(input: TextInputHandle; text: string; byteIndex: int): float32 =
    let caret = input.root.textEngine.caret(TextCaretInput(
      text: text,
      style: input.state.textStyle,
      maxWidth:
        if input.state.textMaxWidth.isSome:
          some(max(1.0'f32, input.state.textMaxWidth.get - 2.0'f32))
        else:
          none(float32),
      fonts: input.root.fonts,
      byteIndex: byteIndex
    ))
    if input.state.textMaxWidth.isSome:
      min(caret.position.x, max(0.0'f32, input.state.textMaxWidth.get - 2.0'f32))
    else:
      caret.position.x

  proc expectedCaretTop(input: TextInputHandle; text: string; byteIndex: int): float32 =
    let caret = input.root.textEngine.caret(TextCaretInput(
      text: text,
      style: input.state.textStyle,
      maxWidth:
        if input.state.textMaxWidth.isSome:
          some(max(1.0'f32, input.state.textMaxWidth.get - 2.0'f32))
        else:
          none(float32),
      fonts: input.root.fonts,
      byteIndex: byteIndex
    ))
    let metrics = input.state.textStyle.caretVisualMetrics(caret.height)
    input.state.textVerticalOffset + caret.position.y + metrics.offset

  proc naturalCaretLeft(input: TextInputHandle; text: string; byteIndex: int): float32 =
    input.root.textEngine.caret(TextCaretInput(
      text: text,
      style: input.state.textStyle,
      maxWidth: none(float32),
      fonts: input.root.fonts,
      byteIndex: byteIndex
    )).position.x

  proc boxFor(layout: LayoutResult; id: NodeId): Rect =
    for item in layout.boxes:
      if item.node == id:
        return item.rect
    fail()
    rect(0, 0, 0, 0)

  test "text input updates value before onInput and onChange handlers":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "A"))
    var inputValue = ""
    var changedValue = ""

    input.container.onInput = proc(event: DispatchResult): EventOutcome =
      inputValue = input.value()
      false

    input.container.onChange = proc(event: DispatchResult): EventOutcome =
      changedValue = input.value()
      false

    discard input.container.emit(textInputEvent("b"))

    check input.value() == "Ab"
    check inputValue == "Ab"
    check changedValue == "Ab"
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "Ab"

  test "preventing before input suppresses mutation and value events":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "A"))
    var valueEvents = 0

    input.container.onBeforeInput = proc(
        event: DispatchResult
    ): EventOutcome =
      preventedEvent()
    input.container.onInput = proc(event: DispatchResult): EventOutcome =
      inc valueEvents
      ignoredEvent()
    input.container.onChange = proc(event: DispatchResult): EventOutcome =
      inc valueEvents
      ignoredEvent()

    check input.container.emit(textInputEvent("b"))
    check input.value() == "A"
    check valueEvents == 0

  test "backspace updates value and emits value events":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "abc"))
    var seen: seq[string] = @[]

    input.container.onInput = proc(event: DispatchResult): EventOutcome =
      seen.add input.value()
      false

    input.container.onChange = proc(event: DispatchResult): EventOutcome =
      seen.add input.value()
      false

    discard input.container.emit(keyDownEvent("Backspace"))

    check input.value() == "ab"
    check seen == @["ab", "ab"]
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "ab"

  test "printable keydown inserts ascii text as a backend fallback":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "A"))
    var inputEvents = 0
    var changeEvents = 0

    input.container.onInput = proc(event: DispatchResult): EventOutcome =
      inc inputEvents
      false

    input.container.onChange = proc(event: DispatchResult): EventOutcome =
      inc changeEvents
      false

    check input.container.emit(keyDownEvent("b"))
    check input.container.emit(keyDownEvent("c", shiftKey = true))

    check input.value() == "AbC"
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "AbC"
    check inputEvents == 2
    check changeEvents == 0

  test "matching text input after keydown fallback is deduplicated":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: ""))

    discard input.container.emit(keyDownEvent("a"))
    discard input.container.emit(textInputEvent("a"))

    check input.value() == "a"

  test "shifted punctuation waits for layout-aware text input":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: ""))

    discard input.container.emit(keyDownEvent(";", shiftKey = true))
    check input.value() == ""

    discard input.container.emit(textInputEvent("+"))
    check input.value() == "+"

  test "long focused text keeps a bounded render surface and scrolls horizontally":
    let ui = initUiRoot()
    let input = ui.textInput(
      TextInputParams(value: "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"),
      textStyle = uiStyle([
        decl("width", px(72)),
        decl("font-size", px(14))
      ])
    )

    discard input.container.emit(iekFocus)

    let textNode = ui.tree.nodes[input.textNode.nodeId.nodeIndex]
    check textNode.text.len <= 512
    check textNode.renderOffset.x < 0
    check input.naturalCaretLeft(textNode.text, textNode.text.len) + textNode.renderOffset.x <= 70

  test "text input layout width does not change when value changes":
    let ui = initUiRoot()
    let input = ui.textInput(
      TextInputParams(value: "abc"),
      style = uiStyle([
        decl("width", px(180)),
        decl("height", px(32)),
        decl("padding", px(8))
      ]),
      textStyle = uiStyle([
        decl("width", px(144)),
        decl("font-size", px(14)),
        decl("white-space", keyword("nowrap"))
      ])
    )

    var diagnostics: Diagnostics
    var styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let before = computeLayout(ui.tree, styles, size(260, 80))
    let beforeContainer = before.boxFor(input.container.nodeId)
    let beforeText = before.boxFor(input.textNode.nodeId)

    input.setValue("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz")
    diagnostics = Diagnostics()
    styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let after = computeLayout(ui.tree, styles, size(260, 80))
    let afterContainer = after.boxFor(input.container.nodeId)
    let afterText = after.boxFor(input.textNode.nodeId)

    check afterContainer.w == beforeContainer.w
    check afterContainer.h == beforeContainer.h
    check afterText.w == beforeText.w

  test "long text input can jump home without scanning the full value":
    let ui = initUiRoot()
    var value = ""
    for _ in 0 ..< 250:
      value.add "abcdefghijklmnopqrstuvwxyz"
    let input = ui.textInput(
      TextInputParams(value: value),
      textStyle = uiStyle([
        decl("width", px(96)),
        decl("font-size", px(14))
      ])
    )

    discard input.container.emit(iekFocus)
    discard input.container.emit(keyDownEvent("Home"))
    discard input.container.emit(textInputEvent(">"))

    check input.value().startsWith(">")
    check input.state.caret == 1
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text.len <= 512

  test "paste inserts text and emits value events":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "hello"))
    var changed = ""

    input.container.onChange = proc(event: DispatchResult): EventOutcome =
      changed = input.value()
      false

    discard input.container.emit(pasteEvent(" world"))

    check input.value() == "hello world"
    check changed == "hello world"

  test "large paste keeps visible text and undo history bounded":
    let ui = initUiRoot()
    let input = ui.textInput(
      TextInputParams(value: "seed"),
      textStyle = uiStyle([
        decl("width", px(120)),
        decl("font-size", px(14))
      ])
    )
    let payload = repeat("abcdef0123456789", 512)

    discard input.container.emit(iekFocus)
    for _ in 0 ..< 4:
      discard input.container.emit(pasteEvent(payload))

    check input.value().len == 8_192
    check input.state.caret == input.value().len
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text.len <= 512
    var undoBytes = 0
    for item in input.state.undoStack:
      undoBytes += item.len
    check undoBytes <= 262_144

  test "repeated growing paste keeps visible text bounded":
    let ui = initUiRoot()
    let input = ui.textInput(
      TextInputParams(value: ""),
      style = uiStyle([
        decl("width", px(160)),
        decl("padding", px(8))
      ]),
      textStyle = uiStyle([
        decl("font-size", px(14))
      ])
    )
    var payload = repeat("abcdef0123456789", 256)

    discard input.container.emit(iekFocus)
    for _ in 0 ..< 8:
      discard input.container.emit(pasteEvent(payload))
      check input.state.caret == input.value().len
      check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text.len <= 512
      payload = input.value()

    check input.value().len <= 8_192
    check ui.tree.nodes[input.container.nodeId.nodeIndex].attrValue("value").get.len <= 8_192

  test "default text input paste is capped before it can grow without bound":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams())
    let payload = repeat("x", 60_000)

    discard input.container.emit(pasteEvent(payload))
    discard input.container.emit(pasteEvent(payload))

    check input.value().len == 8_192
    check ui.tree.nodes[input.container.nodeId.nodeIndex].attrValue("value").get.len <= 8_192

  test "initial long text input value is clipped before layout":
    let ui = initUiRoot()
    let payload = repeat("x", 600_000)
    let input = ui.textInput(
      TextInputParams(value: payload),
      textStyle = uiStyle([
        decl("width", px(120)),
        decl("font-size", px(14))
      ])
    )

    check input.value().len == 8_192
    check input.state.caret == 8_192
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text.len <= 512
    check ui.tree.nodes[input.container.nodeId.nodeIndex].attrValue("value").get.len <= 8_192

  test "paste at max text input length does not grow undo history":
    let ui = initUiRoot()
    let payload = repeat("x", 8_192)
    let input = ui.textInput(TextInputParams(value: payload))
    let undoCount = input.state.undoStack.len

    discard input.container.emit(pasteEvent("more"))
    discard input.container.emit(pasteEvent("more"))
    discard input.container.emit(pasteEvent("more"))

    check input.value().len == 8_192
    check input.state.undoStack.len == undoCount
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text.len <= 512

  test "oversized repeated text input paste stays capped":
    let ui = initUiRoot()
    let input = ui.textInput(
      TextInputParams(),
      style = uiStyle([
        decl("width", px(160)),
        decl("padding", px(8))
      ])
    )
    let payload = repeat("paste-block-", 10_000)

    for _ in 0 ..< 8:
      discard input.container.emit(pasteEvent(payload))

    check input.value().len == 8_192
    check input.state.caret == 8_192
    check input.state.undoStack.len <= 2
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text.len <= 512

  test "controlled text input survives repeated paste rebuilds":
    var value = ""

    proc build(): tuple[ui: UiRoot; input: TextInputHandle] =
      result.ui = initUiRoot()
      result.input = result.ui.textInput(
        TextInputParams(value: value),
        style = uiStyle([
          decl("width", px(140)),
          decl("padding", px(8))
        ])
      )
      let input = result.input
      input.container.onInput = proc(event: DispatchResult): EventOutcome =
        if event.event.text.isSome:
          value = event.event.text.get
        false

    for index in 0 ..< 5:
      var app = build()
      discard app.input.container.emit(pasteEvent("paste-" & $index & " "))
      check value.endsWith("paste-" & $index & " ")
      check app.input.state.caret == app.input.value().len
      check app.ui.tree.nodes[app.input.textNode.nodeId.nodeIndex].text.len <= 512

  test "selected text is replaced by text input":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "hello world"))

    input.setSelection(6, 11)
    discard input.container.emit(textInputEvent("CBSS"))

    check input.value() == "hello CBSS"
    check input.selectedText() == ""
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "hello CBSS"

  test "replacement input places caret after inserted text":
    let ui = initUiRoot()
    let input = ui.textInput(
      TextInputParams(value: "alpha beta gamma"),
      textStyle = uiStyle([
        decl("width", px(160)),
        decl("font-size", px(14)),
        decl("white-space", keyword("nowrap"))
      ])
    )

    discard input.container.emit(iekFocus)
    input.setSelection(6, 10)
    discard input.container.emit(textInputEvent("B"))

    check input.value() == "alpha B gamma"
    check input.selectedText() == ""
    check input.state.caret == "alpha B".len
    check input.caretDecl("left").isSome
    input.caretDecl("left").get.checkClose(input.expectedCaretLeft(
      ui.tree.nodes[input.textNode.nodeId.nodeIndex].text,
      "alpha B".len
    ))

  test "select all and copy expose selected text to handlers":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "copy me"))
    var copied = ""

    input.container.onCopy = proc(event: DispatchResult): EventOutcome =
      copied = input.selectedText()
      false

    discard input.container.emit(keyDownEvent("a", ctrlKey = true))
    check input.selectedText() == "copy me"

    discard input.container.emit(copyEvent())
    check copied == "copy me"
    check input.takeClipboardText() == "copy me"
    check input.value() == "copy me"

  test "cut removes selected text and emits value events":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "cut this"))
    var clipboard = ""
    var changed = ""

    input.container.onCut = proc(event: DispatchResult): EventOutcome =
      clipboard = input.selectedText()
      false

    input.container.onChange = proc(event: DispatchResult): EventOutcome =
      changed = input.value()
      false

    input.setSelection(4, 8)
    discard input.container.emit(cutEvent())

    check clipboard == "this"
    check input.takeClipboardText() == "this"
    check input.value() == "cut "
    check changed == "cut "
    check input.selectedText() == ""

  test "preventing cut keeps the selection and skips clipboard default":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "keep this"))
    input.setSelection(5, 9)
    input.container.onCut = proc(event: DispatchResult): EventOutcome =
      preventedEvent()

    check input.container.emit(cutEvent())
    check input.value() == "keep this"
    check input.selectedText() == "this"
    check input.takeClipboardText() == ""

  test "cut clears fallback and composition state":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "abc def"))

    discard input.container.emit(keyDownEvent("x"))
    check input.state.pendingFallbackText == "x"
    discard input.container.emit(compositionStartEvent("かな"))
    input.setSelection(0, input.value().len)
    discard input.container.emit(cutEvent())

    check input.value() == ""
    check input.state.pendingFallbackText == ""
    check input.state.composingText == ""
    check not input.state.composingActive

  test "shift arrow extends selection from the caret":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "abc"))
    var selected = false

    input.container.onSelect = proc(event: DispatchResult): EventOutcome =
      selected = true
      false

    discard input.container.emit(keyDownEvent("ArrowLeft", shiftKey = true))

    check input.selectedText() == "c"
    check selected

  test "pointer down moves caret near the clicked column":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "abcdef"))

    discard input.container.emit(pointerDownEvent(vec2(28, 8)), local = some(vec2(28, 8)))
    discard input.container.emit(textInputEvent("X"))

    check input.value() == "abXcdef"

  test "mouse drag extends text input selection":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "abcdef"))

    discard input.container.emit(pointerDownEvent(vec2(12, 8), 1), local = some(vec2(12, 8)))
    discard input.container.emit(pointerMoveEvent(vec2(46, 8)), local = some(vec2(46, 8)))
    discard input.container.emit(pointerUpEvent(vec2(46, 8), 1), local = some(vec2(46, 8)))

    check input.selectedText() == "abcd"

  test "drag selection outside text input clamps to text bounds":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "abcdef"))

    discard input.container.emit(pointerDownEvent(vec2(28, 8), 1), local = some(vec2(28, 8)))
    discard input.container.emit(
      InputEvent(kind: iekDrag, position: some(vec2(-200, 8))),
      local = some(vec2(-200, 8))
    )

    check input.selectedText().len > 0
    check input.state.caret == 0

    discard input.container.emit(
      InputEvent(kind: iekDrag, position: some(vec2(400, 8))),
      local = some(vec2(400, 8))
    )

    check input.selectedText().len > 0
    check input.state.caret == input.value().len

  test "repeated paste around a middle caret always terminates and advances":
    let ui = initUiRoot()
    let input = ui.textInput(
      TextInputParams(value: "0123456789abcdefghijklmnopqrstuvwxyz"),
      style = uiStyle([
        decl("width", px(120))
      ]),
      textStyle = uiStyle([
        decl("font-size", px(14)),
        decl("white-space", keyword("nowrap"))
      ])
    )
    input.setSelection(10, 10)

    for _ in 0 ..< 12:
      let before = input.state.caret
      discard input.container.emit(pasteEvent("日本語paste"))
      check input.state.caret > before
      check input.state.caret <= input.value().len

    check input.value().contains("日本語paste日本語paste")

  test "arrow movement after a long paste keeps the visible window stable":
    let ui = initUiRoot()
    let input = ui.textInput(
      TextInputParams(),
      style = uiStyle([
        decl("width", px(120)),
        decl("padding", px(8))
      ]),
      textStyle = uiStyle([
        decl("font-size", px(14)),
        decl("white-space", keyword("nowrap"))
      ])
    )
    let payload = "alpha-beta-gamma-delta-epsilon-zeta"

    discard input.container.emit(pasteEvent(payload))
    let visibleAfterPaste = ui.tree.nodes[input.textNode.nodeId.nodeIndex].text
    let caretAfterPaste = input.caretDecl("left")
    discard input.container.emit(keyDownEvent("ArrowLeft"))

    check input.state.caret == payload.len - 1
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == visibleAfterPaste
    check caretAfterPaste.isSome
    check input.caretDecl("left").isSome
    check input.caretDecl("left").get < caretAfterPaste.get

  test "arrow movement after a multibyte paste follows UTF-8 rune boundaries":
    let ui = initUiRoot()
    let input = ui.textInput(
      TextInputParams(),
      style = uiStyle([decl("width", px(120))]),
      textStyle = uiStyle([
        decl("font-size", px(14)),
        decl("white-space", keyword("nowrap"))
      ])
    )
    let payload = repeat("日本語", 12)

    discard input.container.emit(pasteEvent(payload))
    let visibleAfterPaste = ui.tree.nodes[input.textNode.nodeId.nodeIndex].text
    let caretAfterPaste = input.state.caret
    discard input.container.emit(keyDownEvent("ArrowLeft"))

    check input.state.caret == caretAfterPaste - "語".len
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == visibleAfterPaste
    discard input.container.emit(keyDownEvent("ArrowRight"))
    check input.state.caret == caretAfterPaste

  test "rapid multibyte input keeps the rendered tail and caret in view":
    let ui = initUiRoot()
    let input = ui.textInput(
      TextInputParams(),
      style = uiStyle([
        decl("width", px(120)),
        decl("padding", px(8))
      ]),
      textStyle = uiStyle([
        decl("font-size", px(14)),
        decl("white-space", keyword("nowrap"))
      ])
    )
    let maxTextWidth = 120.0'f32 - 16.0'f32 - 2.0'f32
    var previousOffset = 0.0'f32

    for _ in 0 ..< 24:
      discard input.container.emit(textInputEvent("語"))
      let visible = ui.tree.nodes[input.textNode.nodeId.nodeIndex].text
      check visible.endsWith("語")
      check input.state.caret == input.value().len
      let renderOffset = ui.tree.nodes[input.textNode.nodeId.nodeIndex].renderOffset.x
      check renderOffset <= previousOffset
      check input.naturalCaretLeft(visible, visible.len) + renderOffset <= maxTextWidth
      previousOffset = renderOffset

  test "home and end update the horizontal text viewport":
    let ui = initUiRoot()
    let input = ui.textInput(
      TextInputParams(value: repeat("abcdefgh", 12)),
      style = uiStyle([
        decl("width", px(120)),
        decl("padding", px(8))
      ]),
      textStyle = uiStyle([
        decl("font-size", px(14)),
        decl("white-space", keyword("nowrap"))
      ])
    )

    check input.state.horizontalScroll > 0
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].renderOffset.x < 0
    discard input.container.emit(keyDownEvent("Home"))
    check input.state.caret == 0
    check input.state.horizontalScroll == 0
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].renderOffset.x == 0

    discard input.container.emit(keyDownEvent("End"))
    check input.state.caret == input.value().len
    check input.state.horizontalScroll > 0
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].renderOffset.x < 0

  test "pointer placement includes the horizontal scroll offset":
    let ui = initUiRoot()
    let input = ui.textInput(
      TextInputParams(value: repeat("a", 40)),
      style = uiStyle([
        decl("width", px(120)),
        decl("padding", px(8))
      ]),
      textStyle = uiStyle([
        decl("font-size", px(14)),
        decl("white-space", keyword("nowrap"))
      ])
    )
    let scrollBeforeClick = input.state.horizontalScroll

    check scrollBeforeClick > 0
    input.moveCaretToPoint(vec2(8, 10))

    check input.state.caret > 0
    check input.state.caret < input.value().len
    check input.state.horizontalScroll <= scrollBeforeClick

  test "drag end outside text input clears selecting state":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "abcdef"))

    discard input.container.emit(pointerDownEvent(vec2(12, 8), 1), local = some(vec2(12, 8)))
    discard input.container.emit(
      InputEvent(kind: iekDrag, position: some(vec2(400, 8))),
      local = some(vec2(400, 8))
    )
    check input.state.selecting

    discard input.container.emit(InputEvent(kind: iekDragEnd, position: some(vec2(400, 8))))

    check not input.state.selecting

  test "control word shortcuts move and delete by word":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "one two three"))

    discard input.container.emit(keyDownEvent("ArrowLeft", ctrlKey = true, shiftKey = true))
    check input.selectedText() == "three"

    discard input.container.emit(keyDownEvent("Backspace", ctrlKey = true))
    check input.value() == "one two "

  test "control home and end move to input boundaries":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "alpha beta"))

    discard input.container.emit(keyDownEvent("Home", ctrlKey = true, shiftKey = true))
    check input.selectedText() == "alpha beta"

    discard input.container.emit(keyDownEvent("End", ctrlKey = true))
    discard input.container.emit(textInputEvent("!"))
    check input.value() == "alpha beta!"

  test "control clipboard and history shortcuts work in text input":
    let ui = initUiRoot()
    var clipboard = " pasted"
    ui.configureClipboardTextProvider(proc(): string = clipboard)
    ui.configureClipboardTextWriter(proc(text: string) =
      clipboard = text
    )
    let input = ui.textInput(TextInputParams(value: "copy me"))

    discard input.container.emit(keyDownEvent("a", ctrlKey = true))
    discard input.container.emit(keyDownEvent("c", ctrlKey = true))
    check clipboard == "copy me"

    discard input.container.emit(keyDownEvent("x", ctrlKey = true))
    check clipboard == "copy me"
    check input.value() == ""

    discard input.container.emit(keyDownEvent("v", ctrlKey = true))
    check input.value() == "copy me"

    discard input.container.emit(keyDownEvent("z", ctrlKey = true))
    check input.value() == ""

    discard input.container.emit(keyDownEvent("y", ctrlKey = true))
    check input.value() == "copy me"

  test "meta clipboard shortcuts work in text input":
    let ui = initUiRoot()
    var clipboard = " pasted"
    ui.configureClipboardTextProvider(proc(): string = clipboard)
    ui.configureClipboardTextWriter(proc(text: string) =
      clipboard = text
    )
    let input = ui.textInput(TextInputParams(value: "copy me"))

    discard input.container.emit(keyDownEvent("a", metaKey = true))
    check input.selectedText() == "copy me"

    discard input.container.emit(keyDownEvent("c", metaKey = true))
    check clipboard == "copy me"

    discard input.container.emit(keyDownEvent("x", metaKey = true))
    check input.value() == ""
    check clipboard == "copy me"

    discard input.container.emit(keyDownEvent("v", metaKey = true))
    check input.value() == "copy me"

  test "shift editing shortcuts work in text input":
    let ui = initUiRoot()
    var clipboard = "paste"
    ui.configureClipboardTextProvider(proc(): string = clipboard)
    ui.configureClipboardTextWriter(proc(text: string) =
      clipboard = text
    )
    let input = ui.textInput(TextInputParams(value: "abc"))

    discard input.container.emit(keyDownEvent("ArrowUp", shiftKey = true))
    check input.selectedText() == "abc"

    discard input.container.emit(keyDownEvent("Delete", shiftKey = true))
    check clipboard == "abc"
    check input.value() == ""

    discard input.container.emit(keyDownEvent("Insert", shiftKey = true))
    check input.value() == "abc"

  test "read only input allows selection and copy but rejects edits":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "locked", readOnly: true))
    var copied = ""
    var changed = false

    input.container.onCopy = proc(event: DispatchResult): EventOutcome =
      copied = input.selectedText()
      false

    input.container.onChange = proc(event: DispatchResult): EventOutcome =
      changed = true
      false

    discard input.container.emit(keyDownEvent("a", ctrlKey = true))
    discard input.container.emit(copyEvent())
    discard input.container.emit(textInputEvent("x"))
    discard input.container.emit(cutEvent())
    discard input.container.emit(keyDownEvent("Backspace"))

    check copied == "locked"
    check input.value() == "locked"
    check not changed

  test "disabled input rejects focus and edits":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "disabled", disabled: true))
    let initialCaret = input.state.caret

    discard input.container.emit(iekFocus)
    discard input.container.emit(pointerDownEvent(vec2(2, 8), 1), local = some(vec2(2, 8)))
    discard input.container.emit(textInputEvent("x"))
    discard input.container.emit(keyDownEvent("Backspace"))

    check input.value() == "disabled"
    check input.state.caret == initialCaret
    check not input.state.selecting
    check esDisabled in ui.tree.nodes[input.container.nodeId.nodeIndex].states
    check esFocus notin ui.tree.nodes[input.container.nodeId.nodeIndex].states

  test "max length limits initial value setValue and inserted text on rune boundaries":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "abcdef", maxLength: some(4)))

    check input.value() == "abcd"

    input.setValue("あいう")
    check input.value() == "あ"

    input.setValue("ab")
    discard input.container.emit(textInputEvent("cd"))
    discard input.container.emit(textInputEvent("e"))
    check input.value() == "abcd"

  test "composition update is visible without committing value":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: ""))

    check input.container.emit(compositionStartEvent("か"))
    check input.value() == ""
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "か"

    check input.container.emit(compositionUpdateEvent("かな"))

    check input.value() == ""
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "かな"

    check input.container.emit(compositionEndEvent("かな"))
    check input.value() == ""
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == ""

  test "IME commit survives an empty preedit transition":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: ""))

    check input.container.emit(compositionStartEvent("かんじ"))
    check input.container.emit(compositionUpdateEvent("かん"))
    check input.container.emit(compositionUpdateEvent(""))
    check input.value() == ""

    check input.container.emit(compositionEndEvent("漢字"))
    check input.container.emit(textInputEvent("漢字"))
    check input.value() == "漢字"
    check not input.state.composingActive
    check input.state.composingText == ""

  test "IME preedit restarts after paste with the same update text":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams())

    discard input.container.emit(iekFocus)
    check input.container.emit(compositionUpdateEvent("かな"))
    discard input.container.emit(pasteEvent("日本語"))

    check input.value() == "日本語"
    check input.container.emit(compositionUpdateEvent("かな"))
    check input.state.composingActive
    check input.state.composingText == "かな"
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "日本語かな"

  test "backspace removes composing text before committed value":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "seed"))

    check input.container.emit(compositionStartEvent("かな"))
    check input.container.emit(keyDownEvent("Backspace"))

    check input.value() == "seed"
    check input.state.composingText == "か"
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "seedか"

    check input.container.emit(keyDownEvent("Backspace"))
    check input.value() == "seed"
    check input.state.composingText == ""
    check not input.state.composingActive
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "seed"

    check input.container.emit(textInputEvent("x"))
    check input.value() == "seedx"
    check not input.state.composingActive

    check input.container.emit(keyDownEvent("Backspace"))
    check input.value() == "seed"

  test "placeholder is visible until value or composition exists":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(placeholder: "Name"))

    check input.value() == ""
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "Name"

    discard input.container.emit(textInputEvent("N"))
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "N"

  test "empty active composition hides placeholder":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(placeholder: "Name"))

    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "Name"
    check input.container.emit(compositionStartEvent(""))
    check input.state.composingActive
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == ""
    check input.container.emit(compositionUpdateEvent(""))
    check input.state.composingActive
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == ""
    check input.container.emit(compositionEndEvent(""))
    check not input.state.composingActive
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "Name"

  test "focus shows a caret and blur restores placeholder":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(placeholder: "Name"))

    discard input.container.emit(iekFocus)
    check esFocus in ui.tree.nodes[input.container.nodeId.nodeIndex].states
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "Name"
    check input.caretDecl("top").isSome
    input.caretDecl("top").get.checkClose(input.expectedCaretTop("", 0))

    discard input.container.emit(keyDownEvent("a"))
    check input.value() == "a"
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "a"

    discard input.container.emit(iekBlur)
    check esFocus notin ui.tree.nodes[input.container.nodeId.nodeIndex].states
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "a"

  test "select all delete clears stale fallback text":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "seed"))

    discard input.container.emit(keyDownEvent("x"))
    check input.value() == "seedx"
    check input.state.pendingFallbackText == "x"

    input.selectAll()
    discard input.container.emit(keyDownEvent("Backspace"))
    check input.value() == ""
    check input.state.pendingFallbackText == ""
    check input.state.composingText == ""
    check not input.state.composingActive

    discard input.container.emit(textInputEvent("x"))
    check input.value() == "x"

  test "select all forward delete clears stale fallback text":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "seed"))

    discard input.container.emit(keyDownEvent("x"))
    check input.state.pendingFallbackText == "x"

    input.selectAll()
    discard input.container.emit(keyDownEvent("Delete"))
    check input.value() == ""
    check input.state.pendingFallbackText == ""
    check input.state.composingText == ""
    check not input.state.composingActive

    discard input.container.emit(textInputEvent("x"))
    check input.value() == "x"

  test "composition after select all delete starts from empty value":
    let ui = initUiRoot()
    let input = ui.textInput(TextInputParams(value: "seed", placeholder: "Name"))

    input.selectAll()
    discard input.container.emit(keyDownEvent("Backspace"))
    check input.value() == ""
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "Name"

    discard input.container.emit(compositionStartEvent("か"))
    check input.value() == ""
    check input.state.composingText == "か"
    check input.state.composingActive
    check ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "か"

  test "caret follows rapid input and reset after select all delete":
    let ui = initUiRoot()
    let input = ui.textInput(
      TextInputParams(value: ""),
      textStyle = uiStyle([
        decl("width", px(120)),
        decl("font-size", px(14)),
        decl("white-space", keyword("nowrap"))
      ])
    )

    discard input.container.emit(iekFocus)
    for key in ["a", "b", "c", "d", "e", "f"]:
      discard input.container.emit(keyDownEvent(key))

    check input.value() == "abcdef"
    check input.state.caret == input.value().len
    check input.caretDecl("left").isSome
    input.caretDecl("left").get.checkClose(input.expectedCaretLeft(
      ui.tree.nodes[input.textNode.nodeId.nodeIndex].text,
      ui.tree.nodes[input.textNode.nodeId.nodeIndex].text.len
    ))

    input.selectAll()
    discard input.container.emit(keyDownEvent("Backspace"))
    check input.value() == ""
    check input.state.caret == 0
    check input.caretDecl("left").isSome
    input.caretDecl("left").get.checkClose(input.expectedCaretLeft("", 0))

    discard input.container.emit(keyDownEvent("z"))
    check input.value() == "z"
    check input.state.caret == 1
    check input.caretDecl("left").isSome
    input.caretDecl("left").get.checkClose(input.expectedCaretLeft("z", 1))

  test "visible text does not intercept pointer focus":
    let ui = initUiRoot()
    let input = ui.textInput(
      TextInputParams(placeholder: "Name"),
      style = uiStyle([
        decl("width", px(120)),
        decl("height", px(32))
      ])
    )

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let layout = computeLayout(ui.tree, styles, size(160, 80))
    let regions = buildHitRegions(ui.tree, layout, styles)
    let hit = hitTest(regions, vec2(8, 8))

    check hit.isSome
    check hit.get.node == input.container.nodeId
