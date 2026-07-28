import std/[options, strutils, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

suite "textarea element":
  proc lengthDecl(rule: StyleRule; property: string): Option[float32] =
    for declaration in rule.declarations:
      if declaration.property == property and declaration.operation.value.isSome:
        let value = declaration.operation.value.get
        if value.kind == svLength and value.length.kind == ukPx:
          return some(value.length.value)
    none(float32)

  proc caretDecl(area: TextAreaHandle; property: string): Option[float32] =
    if area.state.caretStyleIndex.isNone:
      return none(float32)
    let index = area.state.caretStyleIndex.get
    if index < 0 or index >= area.root.componentStyles.len:
      return none(float32)
    for rule in area.root.componentStyles[index].rules:
      let value = rule.lengthDecl(property)
      if value.isSome:
        return value
    none(float32)

  proc checkClose(actual, expected: float32; epsilon = 0.01'f32) =
    check abs(actual - expected) <= epsilon

  proc expectedCaretLeft(area: TextAreaHandle; x: float32): float32 =
    if area.state.textMaxWidth.isSome:
      min(x, max(0.0'f32, area.state.textMaxWidth.get - 2.0'f32))
    else:
      x

  proc expectedCaretTop(area: TextAreaHandle; caret: TextCaretResult): float32 =
    let metrics = area.state.textStyle.caretVisualMetrics(caret.height)
    caret.position.y - area.state.scrollY + metrics.offset

  proc isDescendant(tree: Tree; node, ancestor: NodeId): bool =
    var current = some(node)
    while current.isSome:
      if current.get == ancestor:
        return true
      current = tree.nodes[current.get.nodeIndex].parent
    false

  proc normalizeTextAreaDispatches(
      tree: Tree;
      regions: openArray[HitRegion];
      area: TextAreaHandle;
      dispatches: var seq[DispatchResult]
  ) =
    var areaRect = rect(0, 0, 0, 0)
    for region in regions:
      if region.node == area.container.nodeId:
        areaRect = region.rect
        break
    for dispatch in dispatches.mitems:
      if dispatch.event.kind notin {iekPointerMove, iekPointerDown, iekPointerUp, iekDrag, iekDragOver}:
        continue
      if dispatch.event.position.isNone:
        continue
      if dispatch.target.isSome and tree.isDescendant(dispatch.target.get, area.container.nodeId):
        let point = dispatch.event.position.get
        dispatch.target = some(area.container.nodeId)
        dispatch.local = some(vec2(point.x - areaRect.x, point.y - areaRect.y))

  test "textarea accepts multiline text and enter inserts a newline":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "hello"))
    var seen: seq[string] = @[]

    area.container.onChange = proc(event: DispatchResult): bool =
      seen.add area.value()
      false

    discard area.container.emit(keyDownEvent("Enter"))
    discard area.container.emit(textInputEvent("world"))

    check area.value() == "hello\nworld"
    check seen == @["hello\n", "hello\nworld"]
    check ui.tree.nodes[area.textNode.nodeId.nodeIndex].text == "hello\nworld"

  test "focus shows a caret and blur hides it":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "hello"))

    discard area.container.emit(iekFocus)
    check esFocus in ui.tree.nodes[area.container.nodeId.nodeIndex].states
    check ui.tree.nodes[area.textNode.nodeId.nodeIndex].text == "hello"
    let caret = ui.textEngine.caret(TextCaretInput(
      text: "hello",
      style: area.state.textStyle,
      maxWidth: area.state.textMaxWidth,
      fonts: ui.fonts,
      byteIndex: "hello".len
    ))
    check area.caretDecl("top").isSome
    area.caretDecl("top").get.checkClose(area.expectedCaretTop(caret))

    discard area.container.emit(iekBlur)
    check esFocus notin ui.tree.nodes[area.container.nodeId.nodeIndex].states
    check ui.tree.nodes[area.textNode.nodeId.nodeIndex].text == "hello"

  test "printable keydown inserts ascii text as a backend fallback":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "a"))
    var seen: seq[string] = @[]

    area.container.onInput = proc(event: DispatchResult): bool =
      seen.add area.value()
      false

    check area.container.emit(keyDownEvent("b"))
    check area.value() == "ab"
    check seen == @["ab"]

    discard area.container.emit(textInputEvent("b"))
    check area.value() == "ab"
    check seen == @["ab"]

  test "visible textarea text does not intercept pointer focus":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(value: "hello\nworld"),
      style = uiStyle([
        decl("width", px(160)),
        decl("height", px(72))
      ])
    )

    check ui.tree.nodes[area.textNode.nodeId.nodeIndex].hasGroup("textarea-value")

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let layout = computeLayout(ui.tree, styles, size(220, 120))
    let regions = buildHitRegions(ui.tree, layout, styles)
    let hit = hitTest(regions, vec2(12, 12))

    check hit.isSome
    check hit.get.node == area.container.nodeId

  test "arrow up and down move the caret by line column":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "ab\ncde\nf"))

    area.setSelection(1, 1)
    discard area.container.emit(keyDownEvent("ArrowDown"))
    discard area.container.emit(textInputEvent("X"))

    check area.value() == "ab\ncXde\nf"

    discard area.container.emit(keyDownEvent("ArrowDown"))
    discard area.container.emit(textInputEvent("Y"))

    check area.value() == "ab\ncXde\nfY"

  test "arrow up returns the caret to the previous line":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "ab\ncde\nfgh"))

    area.setSelection(4, 4)
    discard area.container.emit(keyDownEvent("ArrowUp"))
    discard area.container.emit(textInputEvent("X"))

    check area.value() == "aXb\ncde\nfgh"

  test "textarea scrolls to keep the caret visible":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(
        value: "one\ntwo\nthree\nfour\nfive",
        width: some(120.0'f32),
        height: some(40.0'f32)
      ),
      style = uiStyle([
        decl("padding", px(4))
      ]),
      textStyle = uiStyle([
        decl("line-height", px(16))
      ])
    )

    discard area.container.emit(iekFocus)
    area.setSelection(area.value().len, area.value().len)

    check area.state.scrollY > 0.0'f32

  test "textarea does not scroll when the content already fits":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(
        value: "one\ntwo",
        width: some(120.0'f32),
        height: some(80.0'f32)
      ),
      style = uiStyle([
        decl("padding", px(4))
      ]),
      textStyle = uiStyle([
        decl("line-height", px(16))
      ])
    )

    discard area.container.emit(iekFocus)
    area.setSelection(area.value().len, area.value().len)

    check area.state.scrollY == 0.0'f32

  test "textarea paste scrolls predictably and keeps the caret visible":
    let ui = initUiRoot()
    let initial = "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten"
    let area = ui.textArea(
      TextAreaParams(
        value: initial,
        width: some(140.0'f32),
        height: some(44.0'f32)
      ),
      style = uiStyle([
        decl("padding", px(4))
      ]),
      textStyle = uiStyle([
        decl("line-height", px(16))
      ])
    )

    discard area.container.emit(iekFocus)
    area.setSelection(area.value().len, area.value().len)
    let beforePasteScrollY = area.state.scrollY
    discard area.container.emit(pasteEvent("\r\nalpha\r\nbeta\r\ngamma\r\ndelta\r\nepsilon\r\nzeta"))

    check area.value().endsWith("epsilon\nzeta")
    check "\r" notin area.value()
    check area.state.scrollY > beforePasteScrollY
    let firstPasteScrollY = area.state.scrollY
    discard area.container.emit(pasteEvent("\none more\ntwo more\nthree more"))

    check area.value().endsWith("two more\nthree more")
    check area.state.scrollY > firstPasteScrollY

    let repeatedPayload = "\nrepeat repeat repeat repeat repeat repeat repeat"
    for _ in 0 ..< 3:
      let insertionStart = area.value().len
      discard area.container.emit(pasteEvent(repeatedPayload))
      let anchorCaret = ui.textEngine.caret(TextCaretInput(
        text: area.value(),
        style: area.state.textStyle,
        maxWidth: area.state.textMaxWidth,
        fonts: ui.fonts,
        byteIndex: insertionStart + 1
      ))
      let caret = ui.textEngine.caret(TextCaretInput(
        text: area.value(),
        style: area.state.textStyle,
        maxWidth: area.state.textMaxWidth,
        fonts: ui.fonts,
        byteIndex: area.state.caret
      ))
      let anchorScrollY = max(0.0'f32, anchorCaret.position.y - max(1.0'f32, anchorCaret.height))
      let caretTop = caret.position.y - area.state.scrollY

      check area.state.scrollY >= anchorScrollY - max(1.0'f32, caret.height)
      check caretTop >= 0.0'f32
      check caretTop + caret.height <= 44.0'f32

  test "paste at max textarea length does not grow undo history":
    let ui = initUiRoot()
    let payload = repeat("x", 8_192)
    let area = ui.textArea(TextAreaParams(value: payload))
    let undoCount = area.state.undoStack.len

    discard area.container.emit(pasteEvent("more"))
    discard area.container.emit(pasteEvent("more"))
    discard area.container.emit(pasteEvent("more"))

    check area.value().len == 8_192
    check area.state.undoStack.len == undoCount

  test "oversized repeated textarea paste stays capped":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(width: some(180.0'f32), height: some(72.0'f32)),
      textStyle = uiStyle([
        decl("line-height", px(16))
      ])
    )
    let payload = repeat("line\n", 20_000)

    for _ in 0 ..< 8:
      discard area.container.emit(pasteEvent(payload))

    check area.value().len == 8_192
    check area.state.caret == 8_192
    check area.state.undoStack.len <= 2

  test "large multiline selection creates chrome only for visible lines":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(width: some(180.0'f32), height: some(72.0'f32)),
      textStyle = uiStyle([
        decl("width", px(160)),
        decl("line-height", px(16)),
        decl("white-space", keyword("pre-wrap"))
      ])
    )
    discard area.container.emit(iekFocus)
    discard area.container.emit(pasteEvent(repeat("line\n", 3_000)))
    discard area.container.emit(keyDownEvent("a", ctrlKey = true))

    check area.value().len == maxPasteEventBytes
    check area.selectedText() == area.value()
    check area.state.selectionNodes.len <= 32
    check ui.tree.nodes.len <= 40

  test "controlled textarea survives repeated paste rebuilds":
    var value = "Line one"

    proc build(): tuple[ui: UiRoot; area: TextAreaHandle] =
      result.ui = initUiRoot()
      result.area = result.ui.textArea(
        TextAreaParams(
          value: value,
          width: some(180.0'f32),
          height: some(52.0'f32)
        ),
        textStyle = uiStyle([
          decl("line-height", px(16))
        ])
      )
      let area = result.area
      area.container.onInput = proc(event: DispatchResult): bool =
        if event.event.text.isSome:
          value = event.event.text.get
        false

    for index in 0 ..< 5:
      var app = build()
      app.area.setSelection(app.area.value().len, app.area.value().len)
      discard app.area.container.emit(pasteEvent("\nblock-" & $index))
      check value.endsWith("block-" & $index)
      check app.area.state.caret == app.area.value().len
      check app.area.state.selectionStart == app.area.state.caret
      check app.area.state.selectionEnd == app.area.state.caret

  test "textarea text style cache reuses component style slots across text-only updates":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(
        value: "one\ntwo\nthree\nfour\nfive",
        width: some(140.0'f32),
        height: some(44.0'f32)
      ),
      style = uiStyle([
        decl("padding", px(4))
      ]),
      textStyle = uiStyle([
        decl("width", px(120)),
        decl("line-height", px(16)),
        decl("white-space", keyword("pre-wrap"))
      ])
    )

    discard area.container.emit(iekFocus)
    check area.state.textNodeStyleIndex.isSome
    let textStyleIndex = area.state.textNodeStyleIndex.get
    let caretStyleIndex = area.state.caretStyleIndex
    let selectionStyleIndex = area.state.selectionStyleIndex
    let styleCount = ui.componentStyles.len

    discard area.container.emit(textInputEvent("!"))
    check area.state.textNodeStyleIndex == some(textStyleIndex)
    check area.state.caretStyleIndex == caretStyleIndex
    check area.state.selectionStyleIndex == selectionStyleIndex
    check ui.componentStyles.len == styleCount

    area.scrollBy(16)
    check area.state.textNodeStyleIndex == some(textStyleIndex)
    check area.state.caretStyleIndex == caretStyleIndex
    check area.state.selectionStyleIndex == selectionStyleIndex
    check ui.componentStyles.len == styleCount

  test "positive wheel pixels scroll textarea toward later content":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(
        value: "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight",
        width: some(140.0'f32),
        height: some(44.0'f32)
      ),
      style = uiStyle([decl("padding", px(4))]),
      textStyle = uiStyle([
        decl("width", px(120)),
        decl("line-height", px(16)),
        decl("white-space", keyword("pre-wrap"))
      ])
    )

    area.scrollBy(-1000)
    check area.state.scrollY == 0
    discard area.container.emit(iekScrollEnd)
    check not area.state.scrollbarVisible
    discard area.container.emit(wheelEvent(vec2(10, 10), vec2(0, 24)))
    check area.state.scrollY == 24
    check area.state.scrollbarVisible
    discard area.container.emit(iekScrollEnd)
    check not area.state.scrollbarVisible
    discard area.container.emit(wheelEvent(vec2(10, 10), vec2(0, -12)))
    check area.state.scrollY == 12
    check area.state.scrollbarVisible

  test "textarea paste draws caret at inserted text end":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(
        value: "before",
        width: some(160.0'f32),
        height: some(52.0'f32)
      ),
      style = uiStyle([
        decl("padding", px(4))
      ]),
      textStyle = uiStyle([
        decl("width", px(120)),
        decl("line-height", px(16)),
        decl("white-space", keyword("pre-wrap"))
      ])
    )

    discard area.container.emit(iekFocus)
    area.setSelection(area.value().len, area.value().len)
    discard area.container.emit(pasteEvent("\nalpha\nbeta"))

    let caret = ui.textEngine.caret(TextCaretInput(
      text: area.value(),
      style: area.state.textStyle,
      maxWidth: area.state.textMaxWidth,
      fonts: ui.fonts,
      byteIndex: area.state.caret
    ))
    check area.state.caret == area.value().len
    check area.caretDecl("left").isSome
    check area.caretDecl("top").isSome
    area.caretDecl("left").get.checkClose(area.expectedCaretLeft(caret.position.x))
    area.caretDecl("top").get.checkClose(area.expectedCaretTop(caret))

  test "textarea paste keeps appended caret visible with preceding context":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(
        value: "before",
        width: some(170.0'f32),
        height: some(56.0'f32)
      ),
      style = uiStyle([
        decl("padding", px(4))
      ]),
      textStyle = uiStyle([
        decl("width", px(120)),
        decl("line-height", px(16)),
        decl("white-space", keyword("pre-wrap"))
      ])
    )

    discard area.container.emit(iekFocus)
    area.setSelection(area.value().len, area.value().len)
    discard area.container.emit(pasteEvent("\nalpha\nbeta\ngamma\ndelta"))

    let caret = ui.textEngine.caret(TextCaretInput(
      text: area.value(),
      style: area.state.textStyle,
      maxWidth: area.state.textMaxWidth,
      fonts: ui.fonts,
      byteIndex: area.state.caret
    ))
    let caretTop = caret.position.y - area.state.scrollY

    check area.state.caret == area.value().len
    check caretTop >= 0.0'f32
    check caretTop + caret.height <= 56.0'f32
    check area.state.scrollY <= caret.position.y - max(1.0'f32, caret.height)

  test "textarea repeated paste keeps caret at appended end":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(
        value: "seed",
        width: some(170.0'f32),
        height: some(56.0'f32)
      ),
      style = uiStyle([
        decl("padding", px(4))
      ]),
      textStyle = uiStyle([
        decl("width", px(116)),
        decl("line-height", px(16)),
        decl("white-space", keyword("pre-wrap"))
      ])
    )
    let payload = "\nrepeat repeat repeat repeat"

    discard area.container.emit(iekFocus)
    area.setSelection(area.value().len, area.value().len)
    discard area.container.emit(pasteEvent(payload))
    let firstScrollY = area.state.scrollY
    discard area.container.emit(pasteEvent(payload))

    let caret = ui.textEngine.caret(TextCaretInput(
      text: area.value(),
      style: area.state.textStyle,
      maxWidth: area.state.textMaxWidth,
      fonts: ui.fonts,
      byteIndex: area.state.caret
    ))
    check area.state.scrollY >= firstScrollY
    check area.state.caret == area.value().len
    check area.caretDecl("left").isSome
    check area.caretDecl("top").isSome
    area.caretDecl("left").get.checkClose(area.expectedCaretLeft(caret.position.x))
    area.caretDecl("top").get.checkClose(area.expectedCaretTop(caret))

  test "textarea composition update draws caret after composing text":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(
        value: "seed",
        width: some(170.0'f32),
        height: some(56.0'f32)
      ),
      style = uiStyle([
        decl("padding", px(4))
      ]),
      textStyle = uiStyle([
        decl("width", px(120)),
        decl("line-height", px(16)),
        decl("white-space", keyword("pre-wrap"))
      ])
    )

    discard area.container.emit(iekFocus)
    area.setSelection(area.value().len, area.value().len)
    discard area.container.emit(compositionUpdateEvent("かな"))

    let display = "seedかな"
    let caret = ui.textEngine.caret(TextCaretInput(
      text: display,
      style: area.state.textStyle,
      maxWidth: area.state.textMaxWidth,
      fonts: ui.fonts,
      byteIndex: display.len
    ))
    check area.value() == "seed"
    check area.state.caret == "seed".len
    check area.state.composingText == "かな"
    check ui.tree.nodes[area.textNode.nodeId.nodeIndex].text == display
    check area.caretDecl("left").isSome
    check area.caretDecl("top").isSome
    area.caretDecl("left").get.checkClose(area.expectedCaretLeft(caret.position.x))
    area.caretDecl("top").get.checkClose(area.expectedCaretTop(caret))

  test "textarea composition start is visible before commit":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: ""))

    discard area.container.emit(iekFocus)
    check area.container.emit(compositionStartEvent("か"))

    check area.value() == ""
    check area.state.composingText == "か"
    check ui.tree.nodes[area.textNode.nodeId.nodeIndex].text == "か"
    check area.caretDecl("left").isSome

  test "textarea empty active composition hides placeholder":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(placeholder: "Message"))

    check ui.tree.nodes[area.textNode.nodeId.nodeIndex].text == "Message"
    check area.container.emit(compositionStartEvent(""))
    check area.state.composingActive
    check ui.tree.nodes[area.textNode.nodeId.nodeIndex].text == ""
    check area.container.emit(compositionUpdateEvent(""))
    check area.state.composingActive
    check ui.tree.nodes[area.textNode.nodeId.nodeIndex].text == ""
    check area.container.emit(compositionEndEvent(""))
    check not area.state.composingActive
    check ui.tree.nodes[area.textNode.nodeId.nodeIndex].text == "Message"

  test "textarea IME commit survives an empty preedit transition":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: ""))

    check area.container.emit(compositionStartEvent("かんじ"))
    check area.container.emit(compositionUpdateEvent("かん"))
    check area.container.emit(compositionUpdateEvent(""))
    check area.value() == ""

    check area.container.emit(compositionEndEvent("漢字"))
    check area.container.emit(textInputEvent("漢字"))
    check area.value() == "漢字"
    check not area.state.composingActive
    check area.state.composingText == ""

  test "textarea backspace removes composing text before committed value":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "seed"))

    check area.container.emit(compositionStartEvent("かな"))
    check area.container.emit(keyDownEvent("Backspace"))

    check area.value() == "seed"
    check area.state.composingText == "か"
    check ui.tree.nodes[area.textNode.nodeId.nodeIndex].text == "seedか"

    check area.container.emit(keyDownEvent("Backspace"))
    check area.value() == "seed"
    check area.state.composingText == ""
    check not area.state.composingActive
    check ui.tree.nodes[area.textNode.nodeId.nodeIndex].text == "seed"

    check area.container.emit(textInputEvent("x"))
    check area.value() == "seedx"
    check not area.state.composingActive

    check area.container.emit(keyDownEvent("Backspace"))
    check area.value() == "seed"

  test "home and end move within the current line":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "one\ntwo"))

    area.setSelection(5, 5)
    discard area.container.emit(keyDownEvent("Home"))
    discard area.container.emit(textInputEvent(">"))
    check area.value() == "one\n>two"

    discard area.container.emit(keyDownEvent("End"))
    discard area.container.emit(textInputEvent("<"))
    check area.value() == "one\n>two<"

  test "selection copy and cut work across lines":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "first\nsecond\nthird"))
    var copied = ""
    var changed = ""

    area.container.onCopy = proc(event: DispatchResult): bool =
      copied = area.takeClipboardText()
      false

    area.container.onChange = proc(event: DispatchResult): bool =
      changed = area.value()
      false

    area.setSelection(6, 12)
    discard area.container.emit(copyEvent())
    check copied == "second"

    discard area.container.emit(cutEvent())
    check area.value() == "first\n\nthird"
    check changed == "first\n\nthird"

  test "textarea cut clears fallback and composition state":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "first\nsecond"))

    discard area.container.emit(keyDownEvent("x"))
    check area.state.pendingFallbackText == "x"
    discard area.container.emit(compositionStartEvent("かな"))
    area.selectAll()
    discard area.container.emit(cutEvent())

    check area.value() == ""
    check area.state.pendingFallbackText == ""
    check area.state.composingText == ""
    check not area.state.composingActive

  test "shifted punctuation waits for layout-aware text input":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: ""))

    discard area.container.emit(keyDownEvent(";", shiftKey = true))
    check area.value() == ""

    discard area.container.emit(textInputEvent("+"))
    check area.value() == "+"

  test "pointer down moves caret near the clicked line and column":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "abc\ndef"))

    discard area.container.emit(pointerDownEvent(vec2(28, 32)), local = some(vec2(28, 32)))
    discard area.container.emit(textInputEvent("X"))

    check area.value() == "abc\ndeXf"

  test "mouse drag extends textarea selection":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "abcdef"))

    discard area.container.emit(pointerDownEvent(vec2(10, 8), 1), local = some(vec2(10, 8)))
    discard area.container.emit(pointerMoveEvent(vec2(44, 8)), local = some(vec2(44, 8)))
    discard area.container.emit(pointerUpEvent(vec2(44, 8), 1), local = some(vec2(44, 8)))

    check area.selectedText() == "abcd"

  test "interaction state drag extends textarea selection":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(value: "abcdef"),
      style = uiStyle([
        decl("width", px(120)),
        decl("height", px(32)),
        decl("padding", px(0))
      ]),
      textStyle = uiStyle([
        decl("font-size", px(16)),
        decl("line-height", px(18))
      ])
    )
    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let layout = computeLayout(ui.tree, styles, size(180, 80))
    let regions = buildHitRegions(ui.tree, layout, styles)
    var input = initInteractionState()

    var down = input.processInput(ui.tree, regions, pointerDownEvent(vec2(10, 8), 1))
    ui.tree.normalizeTextAreaDispatches(regions, area, down)
    discard ui.events.handle(ui.tree, down)
    input.pressedTarget = some(area.container.nodeId)
    check area.state.selecting

    var move = input.processInput(ui.tree, regions, pointerMoveEvent(vec2(220, 8)))
    ui.tree.normalizeTextAreaDispatches(regions, area, move)
    discard ui.events.handle(ui.tree, move)
    check area.selectedText().len > 0

    var up = input.processInput(ui.tree, regions, pointerUpEvent(vec2(220, 8), 1))
    ui.tree.normalizeTextAreaDispatches(regions, area, up)
    discard ui.events.handle(ui.tree, up)

    check input.pressedTarget.isNone
    check not area.state.selecting
    check area.selectedText().len > 0

  test "textarea selection emits visible background paint":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(value: "abcdef"),
      style = uiStyle([
        decl("width", px(120)),
        decl("height", px(32)),
        decl("padding", px(0))
      ]),
      textStyle = uiStyle([
        decl("font-size", px(16)),
        decl("line-height", px(18))
      ])
    )

    discard area.container.emit(pointerDownEvent(vec2(10, 8), 1), local = some(vec2(10, 8)))
    discard area.container.emit(pointerMoveEvent(vec2(44, 8)), local = some(vec2(44, 8)))
    check area.selectedText().len > 0

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let layout = computeLayout(ui.tree, styles, size(180, 80))
    let commands = buildPaintCommands(ui.tree, styles, layout)
    var selectionPainted = false
    for command in commands:
      if command.kind == pcFillRect and
          command.color.a > 0.35'f32 and command.color.a < 0.5'f32 and
          command.rect.w > 0 and command.rect.h > 0:
        selectionPainted = true

    check selectionPainted

  test "drag selection outside textarea clamps to visible text bounds":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(
        value: "one\ntwo\nthree\nfour",
        width: some(120.0'f32),
        height: some(42.0'f32)
      ),
      textStyle = uiStyle([
        decl("line-height", px(14))
      ])
    )

    discard area.container.emit(pointerDownEvent(vec2(28, 24), 1), local = some(vec2(28, 24)))
    discard area.container.emit(pointerMoveEvent(vec2(-200, -200)), local = some(vec2(-200, -200)))
    discard area.container.emit(pointerUpEvent(vec2(-200, -200), 1), local = some(vec2(-200, -200)))

    check area.selectedText().len > 0
    check area.selectedText() != area.value()

  test "drag selection below textarea scrolls and extends selection":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(
        value: "one\ntwo\nthree\nfour\nfive\nsix\nseven",
        width: some(120.0'f32),
        height: some(42.0'f32)
      ),
      textStyle = uiStyle([
        decl("line-height", px(14))
      ])
    )

    discard area.container.emit(pointerDownEvent(vec2(8, 8), 1), local = some(vec2(8, 8)))
    discard area.container.emit(pointerMoveEvent(vec2(8, 160)), local = some(vec2(8, 160)))

    check area.state.scrollY > 0.0'f32
    check area.selectedText().len > 0
    check "five" in area.selectedText() or "six" in area.selectedText() or "seven" in area.selectedText()

  test "control word shortcuts move and delete by word in textarea":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "one two three"))

    discard area.container.emit(keyDownEvent("ArrowLeft", ctrlKey = true, shiftKey = true))
    check area.selectedText() == "three"

    discard area.container.emit(keyDownEvent("Backspace", ctrlKey = true))
    check area.value() == "one two "

  test "control home and end move to textarea boundaries":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "one\ntwo\nthree"))

    discard area.container.emit(keyDownEvent("Home", ctrlKey = true, shiftKey = true))
    check area.selectedText() == "one\ntwo\nthree"

    discard area.container.emit(keyDownEvent("End", ctrlKey = true))
    discard area.container.emit(textInputEvent("!"))
    check area.value() == "one\ntwo\nthree!"

  test "control clipboard and history shortcuts work in textarea":
    let ui = initUiRoot()
    var clipboard = " pasted"
    ui.configureClipboardTextProvider(proc(): string = clipboard)
    ui.configureClipboardTextWriter(proc(text: string) =
      clipboard = text
    )
    let area = ui.textArea(TextAreaParams(value: "copy\nme"))

    discard area.container.emit(keyDownEvent("a", ctrlKey = true))
    discard area.container.emit(keyDownEvent("c", ctrlKey = true))
    check clipboard == "copy\nme"

    discard area.container.emit(keyDownEvent("x", ctrlKey = true))
    check area.value() == ""

    discard area.container.emit(keyDownEvent("v", ctrlKey = true))
    check area.value() == "copy\nme"

    discard area.container.emit(keyDownEvent("z", ctrlKey = true))
    check area.value() == ""

    discard area.container.emit(keyDownEvent("z", ctrlKey = true, shiftKey = true))
    check area.value() == "copy\nme"

  test "shift editing shortcuts work in textarea":
    let ui = initUiRoot()
    var clipboard = "paste"
    ui.configureClipboardTextProvider(proc(): string = clipboard)
    ui.configureClipboardTextWriter(proc(text: string) =
      clipboard = text
    )
    let area = ui.textArea(TextAreaParams(value: "abc\ndef"))

    discard area.container.emit(keyDownEvent("Home", ctrlKey = true, shiftKey = true))
    check area.selectedText() == "abc\ndef"

    discard area.container.emit(keyDownEvent("Delete", shiftKey = true))
    check clipboard == "abc\ndef"
    check area.value() == ""

    discard area.container.emit(keyDownEvent("Insert", shiftKey = true))
    check area.value() == "abc\ndef"

  test "page up and page down move textarea caret by viewport":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(
        value: "one\ntwo\nthree\nfour\nfive\nsix",
        width: some(120.0'f32),
        height: some(42.0'f32)
      ),
      textStyle = uiStyle([
        decl("line-height", px(14))
      ])
    )

    area.setSelection(0, 0)
    discard area.container.emit(keyDownEvent("PageDown"))
    discard area.container.emit(textInputEvent("X"))
    check area.value().startsWith("one\n")
    check "X" in area.value()

  test "textarea text paints inside its overflow clip":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(
        value: "one\ntwo\nthree\nfour\nfive\nsix",
        width: some(120.0'f32),
        height: some(42.0'f32)
      ),
      style = uiStyle([
        decl("width", px(120)),
        decl("height", px(42)),
        decl("overflow", keyword("hidden"))
      ])
    )

    var diagnostics: Diagnostics
    let styles = resolveTreeStyles(ui.tree, ui.styleSheets(), defaultProperties(), diagnostics)
    check not diagnostics.hasErrors
    let layout = computeLayout(ui.tree, styles, size(180, 120))
    let commands = buildPaintCommands(ui.tree, styles, layout)
    var clipDepth = 0
    var textWasClipped = false
    for command in commands:
      case command.kind
      of pcPushClip:
        inc clipDepth
      of pcPopClip:
        if clipDepth > 0:
          dec clipDepth
      of pcDrawText:
        if command.node == area.textNode.nodeId and clipDepth > 0:
          textWasClipped = true
      else:
        discard

    check textWasClipped

  test "read only textarea allows copy but rejects edits":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "locked\ntext", readOnly: true))
    var copied = ""
    var changed = false

    area.container.onCopy = proc(event: DispatchResult): bool =
      copied = area.takeClipboardText()
      false

    area.container.onChange = proc(event: DispatchResult): bool =
      changed = true
      false

    area.selectAll()
    discard area.container.emit(copyEvent())
    discard area.container.emit(keyDownEvent("Enter"))
    discard area.container.emit(textInputEvent("x"))
    discard area.container.emit(cutEvent())

    check copied == "locked\ntext"
    check area.value() == "locked\ntext"
    check not changed

  test "disabled textarea rejects focus and edits":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "disabled", disabled: true))
    let initialCaret = area.state.caret

    discard area.container.emit(iekFocus)
    discard area.container.emit(pointerDownEvent(vec2(2, 8), 1), local = some(vec2(2, 8)))
    discard area.container.emit(textInputEvent("x"))
    discard area.container.emit(keyDownEvent("Enter"))

    check area.value() == "disabled"
    check area.state.caret == initialCaret
    check not area.state.selecting
    check esDisabled in ui.tree.nodes[area.container.nodeId.nodeIndex].states
    check esFocus notin ui.tree.nodes[area.container.nodeId.nodeIndex].states

  test "max length limits textarea text on rune boundaries":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "abcdef", maxLength: some(4)))

    check area.value() == "abcd"

    area.setValue("あいう")
    check area.value() == "あ"

  test "select all delete clears stale fallback text":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "seed"))

    discard area.container.emit(keyDownEvent("x"))
    check area.value() == "seedx"
    check area.state.pendingFallbackText == "x"

    area.selectAll()
    discard area.container.emit(keyDownEvent("Backspace"))
    check area.value() == ""
    check area.state.pendingFallbackText == ""
    check area.state.composingText == ""
    check not area.state.composingActive

    discard area.container.emit(textInputEvent("x"))
    check area.value() == "x"

  test "textarea select all forward delete clears stale fallback text":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "seed"))

    discard area.container.emit(keyDownEvent("x"))
    check area.state.pendingFallbackText == "x"

    area.selectAll()
    discard area.container.emit(keyDownEvent("Delete"))
    check area.value() == ""
    check area.state.pendingFallbackText == ""
    check area.state.composingText == ""
    check not area.state.composingActive

    discard area.container.emit(textInputEvent("x"))
    check area.value() == "x"

  test "textarea composition after select all delete starts from empty value":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(value: "seed", placeholder: "Message"))

    area.selectAll()
    discard area.container.emit(keyDownEvent("Backspace"))
    check area.value() == ""
    check ui.tree.nodes[area.textNode.nodeId.nodeIndex].text == "Message"

    discard area.container.emit(compositionStartEvent("か"))
    check area.value() == ""
    check area.state.composingText == "か"
    check area.state.composingActive
    check ui.tree.nodes[area.textNode.nodeId.nodeIndex].text == "か"

  test "textarea enter after rapid input keeps caret on new line":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(value: "", width: some(180'f32), height: some(72'f32)),
      textStyle = uiStyle([
        decl("font-size", px(14)),
        decl("line-height", px(18)),
        decl("white-space", keyword("pre-wrap"))
      ])
    )

    discard area.container.emit(iekFocus)
    for key in ["a", "b", "c", "d"]:
      discard area.container.emit(keyDownEvent(key))
    discard area.container.emit(keyDownEvent("Enter"))

    let caret = ui.textEngine.caret(TextCaretInput(
      text: area.value(),
      style: area.state.textStyle,
      maxWidth: area.state.textMaxWidth,
      fonts: ui.fonts,
      byteIndex: area.state.caret
    ))
    check area.value() == "abcd\n"
    check area.state.caret == area.value().len
    check area.caretDecl("left").isSome
    check area.caretDecl("top").isSome
    area.caretDecl("left").get.checkClose(area.expectedCaretLeft(caret.position.x))
    area.caretDecl("top").get.checkClose(area.expectedCaretTop(caret))

  test "textarea caret follows rapid input and reset after select all delete":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(value: "", width: some(180'f32), height: some(72'f32)),
      textStyle = uiStyle([
        decl("font-size", px(14)),
        decl("line-height", px(18)),
        decl("white-space", keyword("pre-wrap"))
      ])
    )

    discard area.container.emit(iekFocus)
    for key in ["a", "b", "c", "d", "e", "f"]:
      discard area.container.emit(keyDownEvent(key))

    var caret = ui.textEngine.caret(TextCaretInput(
      text: area.value(),
      style: area.state.textStyle,
      maxWidth: area.state.textMaxWidth,
      fonts: ui.fonts,
      byteIndex: area.state.caret
    ))
    check area.value() == "abcdef"
    check area.state.caret == area.value().len
    check area.caretDecl("left").isSome
    check area.caretDecl("top").isSome
    area.caretDecl("left").get.checkClose(area.expectedCaretLeft(caret.position.x))
    area.caretDecl("top").get.checkClose(area.expectedCaretTop(caret))

    area.selectAll()
    discard area.container.emit(keyDownEvent("Backspace"))
    caret = ui.textEngine.caret(TextCaretInput(
      text: area.value(),
      style: area.state.textStyle,
      maxWidth: area.state.textMaxWidth,
      fonts: ui.fonts,
      byteIndex: area.state.caret
    ))
    check area.value() == ""
    check area.state.caret == 0
    check area.caretDecl("left").isSome
    check area.caretDecl("top").isSome
    area.caretDecl("left").get.checkClose(area.expectedCaretLeft(caret.position.x))
    area.caretDecl("top").get.checkClose(area.expectedCaretTop(caret))

    discard area.container.emit(keyDownEvent("z"))
    caret = ui.textEngine.caret(TextCaretInput(
      text: area.value(),
      style: area.state.textStyle,
      maxWidth: area.state.textMaxWidth,
      fonts: ui.fonts,
      byteIndex: area.state.caret
    ))
    check area.value() == "z"
    check area.state.caret == 1
    check area.caretDecl("left").isSome
    check area.caretDecl("top").isSome
    area.caretDecl("left").get.checkClose(area.expectedCaretLeft(caret.position.x))
    area.caretDecl("top").get.checkClose(area.expectedCaretTop(caret))

  test "resize handle updates width and height and emits resize":
    let ui = initUiRoot()
    let area = ui.textArea(TextAreaParams(
      value: "body",
      width: some(120'f32),
      height: some(80'f32),
      minWidth: some(100'f32),
      maxWidth: some(160'f32),
      minHeight: some(60'f32),
      maxHeight: some(120'f32)
    ))
    var resized = 0

    area.onResize = proc(event: DispatchResult): bool =
      inc resized
      false

    discard area.resizeHandle.emit(pointerDownEvent(vec2(0, 0)), local = some(vec2(0, 0)))
    discard area.resizeHandle.emit(pointerMoveEvent(vec2(80, 70)), local = some(vec2(80, 70)))
    discard area.resizeHandle.emit(pointerUpEvent(vec2(80, 70)), local = some(vec2(80, 70)))

    check area.effectiveWidth().get == 160'f32
    check area.effectiveHeight().get == 120'f32
    check resized == 1
    check esActive notin ui.tree.nodes[area.resizeHandle.nodeId.nodeIndex].states

  test "resize direction can be limited or disabled":
    let ui = initUiRoot()
    let vertical = ui.textArea(TextAreaParams(
      value: "body",
      resize: some(rkVertical),
      width: some(120'f32),
      height: some(80'f32)
    ))

    discard vertical.resizeHandle.emit(pointerDownEvent(vec2(0, 0)), local = some(vec2(0, 0)))
    discard vertical.resizeHandle.emit(pointerMoveEvent(vec2(50, 30)), local = some(vec2(50, 30)))
    discard vertical.resizeHandle.emit(pointerUpEvent(vec2(50, 30)), local = some(vec2(50, 30)))

    check vertical.effectiveWidth().get == 120'f32
    check vertical.effectiveHeight().get == 110'f32

    let fixed = ui.textArea(TextAreaParams(
      value: "fixed",
      resize: some(rkNone),
      width: some(120'f32),
      height: some(80'f32)
    ))

    discard fixed.resizeHandle.emit(pointerDownEvent(vec2(0, 0)), local = some(vec2(0, 0)))
    discard fixed.resizeHandle.emit(pointerMoveEvent(vec2(50, 30)), local = some(vec2(50, 30)))

    check fixed.effectiveWidth().get == 120'f32
    check fixed.effectiveHeight().get == 80'f32
    check esDisabled in ui.tree.nodes[fixed.resizeHandle.nodeId.nodeIndex].states

  test "textarea reads direct style resize and size declarations":
    let ui = initUiRoot()
    let area = ui.textArea(
      TextAreaParams(value: "styled"),
      style = uiStyle([
        decl("resize", keyword("horizontal")),
        decl("width", px(90)),
        decl("height", px(70))
      ])
    )

    discard area.resizeHandle.emit(pointerDownEvent(vec2(0, 0)), local = some(vec2(0, 0)))
    discard area.resizeHandle.emit(pointerMoveEvent(vec2(20, 30)), local = some(vec2(20, 30)))

    check area.effectiveWidth().get == 110'f32
    check area.effectiveHeight().get == 70'f32
