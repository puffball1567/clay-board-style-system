import std/[json, options, os, strutils, unittest]

import clay_box_style_system
import clay_box_style_system/testing/test_driver

proc controlStyle(width = 160.0'f32; height = 32.0'f32): UiStyle =
  uiStyle([
    decl("width", px(width)),
    decl("height", px(height)),
    decl("padding", px(8)),
    decl("font-size", px(14)),
    decl("line-height", px(18)),
    decl("background-color", colorValue(rgb(0.12, 0.14, 0.17)))
  ])

proc optionStyle(): UiStyle =
  uiStyle([
    decl("width", px(160)),
    decl("height", px(26)),
    decl("padding", px(6)),
    decl("font-size", px(14))
  ])

proc buildControlsUi(): UiRoot =
  result = initUiRoot()
  let radioSet = initRadioSet("basic")
  result.box("app"):
    discard result.textInput(
      TextInputParams(placeholder: "Type here"),
      style = controlStyle(),
      textStyle = uiStyle([
        decl("width", px(140)),
        decl("white-space", keyword("nowrap"))
      ]),
      id = "name"
    )
    discard result.textArea(
      TextAreaParams(placeholder: "Message", width: some(180.0'f32), height: some(72.0'f32)),
      style = controlStyle(width = 180, height = 72),
      textStyle = uiStyle([
        decl("width", px(156)),
        decl("white-space", keyword("pre-wrap"))
      ]),
      id = "message"
    )
    discard result.selectBox(
      @[
        SelectOption(label: "Small", value: "small"),
        SelectOption(label: "Medium", value: "medium"),
        SelectOption(label: "Large", value: "large")
      ],
      selectedValue = "small",
      style = controlStyle(),
      panelStyle = uiStyle([
        decl("width", px(160)),
        decl("background-color", colorValue(rgb(0.08, 0.09, 0.11)))
      ]),
      optionStyle = optionStyle(),
      id = "size"
    )
    discard result.checkbox("Remember", id = "remember")
    discard result.slider(
      value = 25,
      min = 0,
      max = 100,
      step = 1,
      trackWidth = 120,
      style = controlStyle(width = 180),
      trackStyle = uiStyle([
        decl("width", px(120)),
        decl("height", px(8))
      ]),
      fillStyle = uiStyle([
        decl("height", px(8))
      ]),
      id = "volume"
    )
    discard result.radio(radioSet, "Basic", "basic", id = "radio-basic")
    discard result.radio(radioSet, "Advanced", "advanced", id = "radio-advanced")

suite "CBSS headless test driver":
  test "driver can test handle-first ui without ids":
    var nameInput: TextInputHandle
    var rememberBox: CheckboxHandle
    var volumeSlider: SliderHandle

    proc buildHandleOnlyUi(): UiRoot =
      result = initUiRoot()
      result.box("app"):
        nameInput = result.textInput(
          TextInputParams(placeholder: "Handle only"),
          style = controlStyle()
        )
        rememberBox = result.checkbox("Remember handle")
        volumeSlider = result.slider(
          value = 10,
          min = 0,
          max = 100,
          step = 10,
          trackWidth = 120,
          style = controlStyle(width = 180)
        )

    let driver = initCbssTestDriver(buildHandleOnlyUi, size(360, 240))

    check driver.click(node(nameInput.container))
    check driver.typeText("without-id")
    check driver.value(node(nameInput.container)) == "without-id"

    check not driver.isChecked(node(rememberBox.container))
    check driver.click(node(rememberBox.container))
    check driver.isChecked(node(rememberBox.container))

    check driver.focus(node(volumeSlider.container))
    check driver.press("End")
    check parseFloat(driver.value(node(volumeSlider.container))) == 100.0

  test "driver can use optional cbss codes without requiring ids":
    var generatedCodeBox: NodeHandle
    var laterCodeBox: NodeHandle
    var codedInput: TextInputHandle

    proc buildCodeUi(): UiRoot =
      result = initUiRoot()
      result.box("app"):
        generatedCodeBox = result.box(code = "generated-code")
        result.text(generatedCodeBox, "Generated")
        laterCodeBox = result.box()
        laterCodeBox.setCode("later-code")
        result.text(laterCodeBox, "Later")
        codedInput = result.textInput(TextInputParams(placeholder: "Code input"), style = controlStyle())
        codedInput.container.setCode("field:code-input")

    let driver = initCbssTestDriver(buildCodeUi, size(320, 160))

    check driver.exists(byCode("generated-code"))
    check driver.exists(byCode("later-code"))
    check driver.expectUnique(byCode("generated-code")).ok
    check driver.textContent(byCode("later-code")) == "Later"
    check driver.queryReport(byCode("later-code")).contains("code=later-code")
    check driver.fill(byCode("field:code-input"), "coded")
    check driver.valueByCode("field:code-input") == some("coded")
    check driver.formSnapshot().contains("code:field:code-input=coded")

  test "driver distinguishes duplicated controls by handle without ids":
    var firstName: TextInputHandle
    var secondName: TextInputHandle

    proc buildDuplicatedUi(): UiRoot =
      result = initUiRoot()
      result.box("app"):
        firstName = result.textInput(
          TextInputParams(placeholder: "Name"),
          style = controlStyle()
        )
        secondName = result.textInput(
          TextInputParams(placeholder: "Name"),
          style = controlStyle()
        )

    let driver = initCbssTestDriver(buildDuplicatedUi, size(360, 180))

    check driver.count(byPlaceholder("Name")) == 2
    check not driver.expectUnique(byPlaceholder("Name")).ok
    check driver.expectUnique(node(firstName.container)).ok

    check driver.fill(node(firstName.container), "Alice")
    check driver.fill(node(secondName.container), "Bob")

    check driver.value(node(firstName.container)) == "Alice"
    check driver.value(node(secondName.container)) == "Bob"

  test "driver scopes repeated component queries with within":
    proc buildRepeatedFormsUi(): UiRoot =
      result = initUiRoot()
      result.box("app"):
        let billingBox = result.box(code = "billing-form")
        result.pushParent(billingBox)
        try:
          discard result.textInput(TextInputParams(placeholder: "Name"), style = controlStyle())
          discard result.checkbox("Default")
        finally:
          result.popParent()

        let shippingBox = result.box(code = "shipping-form")
        result.pushParent(shippingBox)
        try:
          discard result.textInput(TextInputParams(placeholder: "Name"), style = controlStyle())
          discard result.checkbox("Default")
        finally:
          result.popParent()

    let driver = initCbssTestDriver(buildRepeatedFormsUi, size(420, 260))
    let billing = driver.within(byCode("billing-form"))
    let shipping = driver.within(byCode("shipping-form"))

    check driver.count(byPlaceholder("Name")) == 2
    check not driver.expectUnique(byPlaceholder("Name")).ok
    check billing.expectUnique(byPlaceholder("Name")).ok
    check shipping.expectUnique(byPlaceholder("Name")).ok

    check billing.fill(byPlaceholder("Name"), "Billing")
    check shipping.fill(byPlaceholder("Name"), "Shipping")

    check billing.expectValue(byPlaceholder("Name"), "Billing").ok
    check shipping.expectValue(byPlaceholder("Name"), "Shipping").ok
    check billing.expectVisible(byPlaceholder("Name")).ok

    check billing.toggle(byGroup("checkbox"))
    check billing.expectChecked(byGroup("checkbox")).ok
    check not shipping.isChecked(byGroup("checkbox"))
    check billing.queryReport(byText("Missing")).contains("within: byCode(billing-form)")

  test "driver supports nested scopes and direct-child queries":
    proc buildNestedUi(): UiRoot =
      result = initUiRoot()
      result.box("app"):
        let shell = result.box(code = "settings-shell")
        result.pushParent(shell)
        try:
          discard result.text("Settings", groups = ["title"])
          let section = result.box(code = "profile-section")
          result.pushParent(section)
          try:
            discard result.textInput(TextInputParams(placeholder: "Name"), style = controlStyle())
          finally:
            result.popParent()
        finally:
          result.popParent()

    let driver = initCbssTestDriver(buildNestedUi, size(360, 180))
    let shell = driver.within(byCode("settings-shell"))
    let profile = shell.within(byCode("profile-section"))

    check shell.children(byGroup("title")).len == 1
    check shell.firstChild(byCode("profile-section")).isSome
    check shell.requireChild(byCode("profile-section")).nodeIndex >= 0
    check driver.childrenOf(byCode("settings-shell"), byGroup("title")).len == 1
    check driver.firstChildOf(byCode("settings-shell"), byCode("profile-section")).isSome
    check driver.requireChildOf(byCode("settings-shell"), byCode("profile-section")).nodeIndex >= 0

    check profile.fill(byPlaceholder("Name"), "Nested")
    check profile.expectValue(byPlaceholder("Name"), "Nested").ok

  test "driver can assert padded label text remains inside label bounds":
    proc labelBoxStyle(): UiStyle =
      uiStyle([
        decl("width", px(112)),
        decl("height", px(28)),
        decl("padding-left", px(6)),
        decl("padding-right", px(6)),
        decl("align-items", keyword("center")),
        decl("justify-content", keyword("center")),
        decl("background-color", colorValue(rgb(0.13, 0.13, 0.15)))
      ])

    proc labelTextStyle(): UiStyle =
      uiStyle([
        decl("width", px(96)),
        decl("font-size", px(10)),
        decl("line-height", px(16)),
        decl("text-align", keyword("center")),
        decl("white-space", keyword("nowrap"))
      ])

    proc buildPaddedLabelUi(): UiRoot =
      result = initUiRoot()
      result.box("app"):
        for labelText in ["paint", "decoration", "visibility"]:
          let label = result.box(labelBoxStyle(), code = "property-label-" & labelText)
          result.pushParent(label)
          try:
            discard result.text(labelText, labelTextStyle(), groups = ["property-label-text", "property-label-text-" & labelText])
          finally:
            result.popParent()

    let driver = initCbssTestDriver(buildPaddedLabelUi, size(180, 80))
    for labelText in ["paint", "decoration", "visibility"]:
      let labelRect = driver.rectFor(byCode("property-label-" & labelText))
      let textRect = driver.rectFor(byGroup("property-label-text-" & labelText))
      check labelRect.isSome
      check textRect.isSome

      let leftPadding = 6.0'f32
      let rightPadding = 6.0'f32
      check textRect.get.x >= labelRect.get.x + leftPadding
      check textRect.get.x + textRect.get.w <= labelRect.get.x + labelRect.get.w - rightPadding
      check textRect.get.y >= labelRect.get.y
      check textRect.get.y + textRect.get.h <= labelRect.get.y + labelRect.get.h

      var labelTextCommand: Option[PaintCommand]
      for command in driver.paintCommands:
        if command.kind == pcDrawText and command.text == labelText:
          labelTextCommand = some(command)
          break
      check labelTextCommand.isSome
      check labelTextCommand.get.position.x == textRect.get.x
      check labelTextCommand.get.textMaxWidth == some(textRect.get.w)

  test "driver can type into text controls and move focus with tab":
    let driver = initCbssTestDriver(buildControlsUi, size(320, 240))

    check driver.diagnosticsOk()
    check driver.exists(byId("name"))
    check driver.count(byGroup("checkbox")) == 1

    check driver.click(byPlaceholder("Type here"))
    check driver.isFocused(byPlaceholder("Type here"))

    check driver.typeText("abcdef")
    check driver.value(byPlaceholder("Type here")) == "abcdef"

    check driver.press("Tab")
    check driver.isFocused(byPlaceholder("Message"))
    check driver.typeText("hello")
    check driver.value(byPlaceholder("Message")) == "hello"
    check driver.value(byPlaceholder("Type here")) == "abcdef"

  test "driver rejects stale focus-owned text after focus moves":
    let driver = initCbssTestDriver(buildControlsUi, size(320, 240))

    check driver.click(byId("name"))
    let oldFocus = driver.focusedTarget()
    check oldFocus.isSome
    let staleText = textInputEvent("late").markFocusOwned(driver.input)
    let stalePaste = pasteEvent(" paste").markFocusOwned(driver.input)

    check driver.click(byId("message"))
    check driver.focusedTarget().isSome
    check driver.focusedTarget().get != oldFocus.get
    check not driver.input.acceptsFocusOwnedEvent(staleText)
    check not driver.input.acceptsFocusOwnedEvent(stalePaste)

    if driver.input.acceptsFocusOwnedEvent(staleText):
      discard driver.ui.events.handle(
        driver.ui.tree,
        DispatchResult(target: oldFocus, local: none(Vec2), event: staleText)
      )
    if driver.input.acceptsFocusOwnedEvent(stalePaste):
      discard driver.ui.events.handle(
        driver.ui.tree,
        DispatchResult(target: oldFocus, local: none(Vec2), event: stalePaste)
      )
    driver.refresh()

    check driver.value(byId("name")) == ""
    check driver.value(byId("message")) == ""

  test "driver keeps fixed text input bounds stable during rapid input":
    let driver = initCbssTestDriver(buildControlsUi, size(320, 240))

    check driver.click(byId("name"))
    let before = driver.rectFor(byId("name"))
    check before.isSome
    check driver.typeText("abcdefghijklmnopqrstuvwxyz0123456789")
    let after = driver.rectFor(byId("name"))

    check after.isSome
    check after.get.x == before.get.x
    check after.get.y == before.get.y
    check after.get.w == before.get.w
    check after.get.h == before.get.h
    check driver.value(byId("name")) == "abcdefghijklmnopqrstuvwxyz0123456789"
    check driver.expectCaret(byId("name"), driver.value(byId("name")).len).ok

  test "driver can open select choose an option and close outside":
    let driver = initCbssTestDriver(buildControlsUi, size(320, 260))

    check driver.value(byId("size")) == "small"
    check driver.click(byId("size"))
    check driver.isOpen(byId("size"))

    check driver.click(byText("Medium"))
    check driver.value(byId("size")) == "medium"
    check not driver.isOpen(byId("size"))

    check driver.click(byId("size"))
    check driver.isOpen(byId("size"))
    check driver.clickOutside()
    check not driver.isOpen(byId("size"))
    check driver.expectClosed(byId("size")).ok

  test "driver closes open popup without clicking through outside target":
    let driver = initCbssTestDriver(buildControlsUi, size(360, 320))

    check not driver.isChecked(byId("remember"))
    check driver.click(byId("size"))
    check driver.isOpen(byId("size"))

    check driver.click(byId("remember"))
    check not driver.isOpen(byId("size"))
    check not driver.isChecked(byId("remember"))

    check driver.click(byId("remember"))
    check driver.isChecked(byId("remember"))

  test "driver provides popup workflow helpers":
    let driver = initCbssTestDriver(buildControlsUi, size(320, 260))

    check driver.openPopup(byId("size"))
    check driver.isOpen(byId("size"))
    check driver.chooseOpenOption("Large")
    check driver.value(byId("size")) == "large"
    check driver.expectClosed(byId("size")).ok

    check driver.choosePopupOption(byId("size"), "Medium")
    check driver.value(byId("size")) == "medium"

    check driver.openPopup(byId("size"))
    check driver.closePopups()
    check driver.expectClosed(byId("size")).ok

  test "driver can read and toggle checkbox and radio state":
    let driver = initCbssTestDriver(buildControlsUi, size(360, 320))

    check not driver.isChecked(byId("remember"))
    check driver.attribute(byId("remember"), "label") == some("Remember")
    check driver.click(byId("remember"))
    check driver.isChecked(byId("remember"))
    check driver.value(byId("remember")) == "true"

    check driver.isChecked(byId("radio-basic"))
    check not driver.isChecked(byId("radio-advanced"))
    check driver.click(byId("radio-advanced"))
    check not driver.isChecked(byId("radio-basic"))
    check driver.isChecked(byId("radio-advanced"))
    check driver.value(byId("radio-advanced")) == "advanced"

  test "driver can drag slider and inspect synchronized value":
    let driver = initCbssTestDriver(buildControlsUi, size(360, 320))

    let before = parseFloat(driver.value(byId("volume")))
    check driver.hover(byId("volume"))
    check driver.drag(byId("volume"), vec2(70, 0), steps = 6)
    let after = parseFloat(driver.value(byId("volume")))

    check after > before
    check driver.attribute(byId("volume"), "percent").isSome

  test "driver can drive focused keyboard controls":
    let driver = initCbssTestDriver(buildControlsUi, size(360, 320))

    check driver.focus(byId("volume"))
    check driver.press("End")
    check parseFloat(driver.value(byId("volume"))) == 100.0
    check driver.press("Home")
    check parseFloat(driver.value(byId("volume"))) == 0.0

  test "driver reconciles modal escape focus restoration":
    let ui = initUiRoot()
    let opener = ui.button("Open", style = controlStyle(), id = "open-dialog")
    let confirm = ui.dialog(
      title = "Confirm",
      body = "Continue?",
      modal = true,
      style = controlStyle(width = 220, height = 100),
      id = "confirm-dialog"
    )
    ui.pushParent(confirm.container)
    let accept = ui.button("Accept", style = controlStyle(), id = "accept")
    ui.popParent()
    let driver = initCbssTestDriver(ui, size(360, 240))

    check driver.focus(opener.container.nodeId)
    check confirm.show(driver.input)
    driver.refresh()
    check driver.focusedTarget() == some(accept.container.nodeId)

    check driver.press("Escape")
    check not confirm.isOpen()
    check driver.focusedTarget() == some(opener.container.nodeId)

  test "tab traversal reaches standard controls and intrinsic keyboard behavior":
    var saveButton: ButtonHandle
    var rememberBox: CheckboxHandle
    var disclosure: DetailsHandle
    var saves = 0

    proc buildKeyboardUi(): UiRoot =
      result = initUiRoot()
      result.box("app"):
        saveButton = result.button("Save")
        saveButton.onClick = proc(event: DispatchResult): bool =
          inc saves
          false
        rememberBox = result.checkbox("Remember")
        disclosure = result.details("Advanced", "Settings")

    let driver = initCbssTestDriver(buildKeyboardUi, size(320, 180))

    check driver.press("Tab")
    check driver.focusedTarget() == some(saveButton.container.nodeId)
    check driver.press("Enter")
    check saves == 1

    check driver.press("Tab")
    check driver.focusedTarget() == some(rememberBox.container.nodeId)
    check driver.press(" ")
    check rememberBox.checked()

    check driver.press("Tab")
    check driver.focusedTarget() == some(disclosure.summaryNode.nodeId)
    check driver.press("ArrowRight")
    check disclosure.isOpen()
    check driver.press("ArrowLeft")
    check not disclosure.isOpen()

  test "driver can inspect selection and clipboard workflows":
    let driver = initCbssTestDriver(buildControlsUi, size(360, 320))

    check driver.click(byId("name"))
    check driver.typeText("abcdef")
    check driver.selectAll()
    check driver.selectedText(byId("name")) == "abcdef"
    check driver.expectSelectedText(byId("name"), "abcdef").ok
    check driver.selectionRange(byId("name")).isSome

    check driver.copy()
    check driver.clipboard == "abcdef"

    check driver.cut()
    check driver.value(byId("name")) == ""
    check driver.clipboard == "abcdef"

    check driver.paste()
    check driver.value(byId("name")) == "abcdef"
    check driver.caret(byId("name")) == some(6)
    check driver.expectCaret(byId("name"), 6).ok

  test "driver exercises text input clipboard keyboard shortcuts":
    let driver = initCbssTestDriver(buildControlsUi, size(360, 320))

    check driver.click(byId("name"))
    check driver.typeText("abcdef")
    check driver.selectAllShortcut()
    check driver.selectedText(byId("name")) == "abcdef"

    check driver.copyShortcut()
    check driver.clipboard == "abcdef"

    check driver.cutShortcut()
    check driver.value(byId("name")) == ""
    check driver.clipboard == "abcdef"

    check driver.pasteShortcut()
    check driver.value(byId("name")) == "abcdef"
    check driver.caret(byId("name")) == some(6)

    check driver.selectAllShortcut(metaKey = true)
    check driver.copyShortcut(metaKey = true)
    check driver.clipboard == "abcdef"

  test "driver can inspect textarea scroll state and form values":
    let driver = initCbssTestDriver(buildControlsUi, size(360, 320))

    check driver.click(byId("message"))
    check driver.paste("one\ntwo\nthree\nfour\nfive\nsix\nseven\neight")
    check driver.value(byId("message")).contains("eight")
    check driver.scrollY(byId("message")).isSome
    check driver.scrollY(byId("message")).get >= 0.0
    check driver.expectScrollYAtLeast(byId("message"), 0.0).ok

    let values = driver.values()
    check values.contains(("message", driver.value(byId("message"))))
    check values.contains(("size", "small"))
    check values.contains(("remember", "false"))

  test "driver keeps textarea paste caret visible without resizing the control":
    let driver = initCbssTestDriver(buildControlsUi, size(360, 320))

    check driver.click(byId("message"))
    let beforeRect = driver.rectFor(byId("message"))
    check beforeRect.isSome

    let payload = "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten"
    check driver.paste(payload)
    let afterFirstPaste = driver.value(byId("message"))
    check afterFirstPaste == payload
    check driver.expectCaret(byId("message"), afterFirstPaste.len).ok
    check driver.expectScrollYAtLeast(byId("message"), 0.0).ok

    check driver.paste("\neleven\ntwelve\nthirteen")
    let afterSecondPaste = driver.value(byId("message"))
    check afterSecondPaste.endsWith("eleven\ntwelve\nthirteen")
    check driver.expectCaret(byId("message"), afterSecondPaste.len).ok
    check driver.scrollY(byId("message")).isSome

    let afterRect = driver.rectFor(byId("message"))
    check afterRect.isSome
    check afterRect.get.w == beforeRect.get.w
    check afterRect.get.h == beforeRect.get.h

  test "overflowing textarea exposes and drags a retained scrollbar thumb":
    let driver = initCbssTestDriver(buildControlsUi, size(360, 320))

    check driver.click(byId("message"))
    check driver.paste("one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten")
    check driver.ui.events.emit(
      driver.ui.tree, driver.requireOne(byId("message")), iekScrollEnd
    )
    driver.refresh()
    check driver.styles.styles[
      driver.requireOne(byGroup("textarea-scrollbar-track")).nodeIndex
    ].layout.display == dkNone

    check driver.wheel(byId("message"), vec2(0, -1000))
    check driver.scrollY(byId("message")) == some(0.0'f32)
    check driver.styles.styles[
      driver.requireOne(byGroup("textarea-scrollbar-track")).nodeIndex
    ].layout.display == dkFlex
    check driver.isVisible(byGroup("textarea-scrollbar-track"))
    check driver.isVisible(byGroup("textarea-scrollbar-thumb"))
    let thumbBefore = driver.rectFor(byGroup("textarea-scrollbar-thumb"))
    check thumbBefore.isSome
    let start = driver.centerFor(byGroup("textarea-scrollbar-thumb"))
    check driver.drag(start, vec2(start.x, start.y + 24), steps = 4)
    check driver.scrollY(byId("message")).get > 0
    let thumbAfter = driver.rectFor(byGroup("textarea-scrollbar-thumb"))
    check thumbAfter.isSome
    check thumbAfter.get.y > thumbBefore.get.y
    for _ in 0 ..< 4:
      driver.refresh()
      check driver.isVisible(byGroup("textarea-scrollbar-track"))
      check driver.isVisible(byGroup("textarea-scrollbar-thumb"))
      check driver.rectFor(byGroup("textarea-scrollbar-thumb")).get.y == thumbAfter.get.y

  test "driver can target direct node handles and wheel events":
    let ui = initUiRoot()
    var wheelCount = 0
    var panel: NodeHandle
    ui.box(panel, uiStyle([
        decl("width", px(120)),
        decl("height", px(80)),
        decl("flex-direction", keyword("column")),
        decl("overflow-y", keyword("auto")),
        decl("scrollbar-width", keyword("thin")),
        decl("scrollbar-visibility", keyword("scrolling"))
      ])):
      discard ui.box(uiStyle([
        decl("width", px(120)),
        decl("height", px(60)),
        decl("flex-shrink", number(0))
      ]))
      discard ui.box(uiStyle([
        decl("width", px(120)),
        decl("height", px(60)),
        decl("flex-shrink", number(0))
      ]))
    panel.onWheel = proc(event: DispatchResult): bool =
      inc wheelCount
      true

    let driver = initCbssTestDriver(ui, size(200, 140))

    proc scrollbarFillCount(): int =
      for command in driver.paintCommands:
        if command.kind == pcFillRect and command.owner == some(panel.nodeId):
          inc result

    check driver.exists(node(panel.nodeId))
    check driver.rectFor(node(panel.nodeId)).isSome
    check driver.scrollOffset(node(panel.nodeId)) == some(vec2(0, 0))
    check scrollbarFillCount() == 0
    check driver.wheel(node(panel.nodeId), vec2(0, 24))
    check wheelCount == 1
    check driver.scrollOffset(node(panel.nodeId)) == some(vec2(0, 24))
    check scrollbarFillCount() == 2
    discard driver.input.finishScroll(driver.ui.scroll)
    driver.refresh()
    check scrollbarFillCount() == 0

  test "driver uses popup hit order so option clicks do not click underlying controls":
    let ui = initUiRoot()
    ui.box("app"):
      discard ui.selectBox(
        @[
          SelectOption(label: "Alpha", value: "alpha"),
          SelectOption(label: "Beta", value: "beta")
        ],
        selectedValue = "alpha",
        style = controlStyle(),
        panelStyle = uiStyle([
          decl("width", px(160)),
          decl("background-color", colorValue(rgb(0.08, 0.09, 0.11)))
        ]),
        optionStyle = optionStyle(),
        id = "select"
      )
      discard ui.checkbox("Under")

    let driver = initCbssTestDriver(ui, size(320, 180))

    check driver.click(byId("select"))
    check driver.isOpen(byId("select"))
    check driver.click(byText("Beta"))

    check driver.value(byId("select")) == "beta"
    check not driver.hasState(byGroup("checkbox"), esChecked)

  test "driver exposes structural paint command snapshots":
    let driver = initCbssTestDriver(buildControlsUi, size(320, 240))

    check driver.paintCommandCount(pcDrawText) > 0
    check driver.paintCommandsOf(pcDrawText).len == driver.paintCommandCount(pcDrawText)
    check driver.layoutSnapshot().contains("#name")
    check driver.paintSnapshot().contains("draw-text")
    check driver.snapshot().contains("layout:\n")
    check driver.snapshot().contains("\npaint:\n")

  test "driver exposes debug reports and snapshot diffs":
    let driver = initCbssTestDriver(buildControlsUi, size(320, 240))

    check describe(byId("name")) == "byId(name)"
    check describe(byCode("field:name")) == "byCode(field:name)"
    check describe(byTextContains("Lar")) == "byTextContains(Lar)"
    check describe(byValue("small")) == "byValue(small)"
    check driver.queryReport(byId("name")).contains("matches: 1")
    check driver.queryReport(byId("missing")).contains("tree:")
    check driver.expectNotExists(byId("missing")).ok
    check not driver.expectNotExists(byId("name")).ok
    check driver.expectUnique(byId("name")).ok
    check driver.treeSnapshot().contains("#name")
    check driver.exists(byValue("small"))
    check driver.exists(byTextContains("Sma"))
    check driver.expectCount(byGroup("checkbox"), 1).ok
    check not driver.expectCount(byGroup("checkbox"), 2).ok
    check driver.expectAttribute(byId("size"), "value", "small").ok
    check not driver.expectAttribute(byId("size"), "value", "large").ok
    check driver.countWithin(byGroup("app"), byId("name")) == 1
    check driver.firstWithin(byGroup("app"), byId("name")).isSome
    check driver.isVisible(byId("name"))
    check driver.hitAt(driver.centerFor(byId("name"))).isSome
    check driver.expectHit(driver.centerFor(byId("name")), byId("name")).ok
    check driver.hits(byId("name"), byId("name"))

    let valueCheck = driver.expectValue(byId("size"), "small")
    check valueCheck.ok
    let missingCheck = driver.expectExists(byId("missing"))
    check not missingCheck.ok
    check missingCheck.message.contains("query: byId(missing)")

    let noDiagnostics = driver.expectNoDiagnostics()
    check noDiagnostics.ok

    let snapshot = driver.snapshot()
    check diffSnapshot(snapshot, snapshot).matches
    let diff = diffSnapshot("layout:\nwrong", snapshot)
    check not diff.matches
    check diff.line > 0
    check diff.message.contains("snapshot mismatch")

    check driver.valueById("size") == some("small")
    check driver.valueById("missing").isNone
    check driver.formSnapshot().contains("size=small")
    check driver.layoutSnapshot(byId("name")).contains("#name")
    check driver.paintSnapshot(byText("Small")).contains("draw-text")
    check driver.debugReport().contains("viewport:")
    check driver.debugReport().contains("values:")
    check driver.debugBundle().contains("layout:")
    check driver.debugBundle(some(byId("name"))).contains("query-report:")
    check driver.debugBundle(some(byId("name"))).contains("query: byId(name)")
    check driver.expectVisible(byId("name")).ok
    check driver.structuredSnapshot().contains("\"nodes\"")
    check driver.structuredSnapshot().contains("\"layout\"")
    check driver.structuredSnapshotJson()["viewport"]["w"].getFloat() == 320.0
    check driver.approvedSnapshot().contains("\"paint\"")

    check driver.click(byId("remember"))
    check driver.dispatchSnapshot().contains("iekClick")
    check driver.dispatchSnapshot().contains("checkbox")
    check driver.dispatched(iekClick)
    check driver.dispatchCount(iekClick) >= 1
    check driver.expectDispatched(iekClick).ok
    check driver.actionSnapshot().contains("click byId(remember)")
    check driver.debugReport().contains("actions:")
    check driver.debugBundle().contains("actions:")
    check driver.structuredSnapshotJson()["actions"].len > 0
    check driver.waitFor(proc(): bool =
      driver.exists(byId("name"))
    ).ok
    check driver.waitForExists(byId("name")).ok
    check driver.waitForValue(byId("size"), "small").ok
    check not driver.waitForExists(byId("missing"), ticks = 1).ok
    check driver.waitForValue(byId("missing"), "x", ticks = 1).message.contains("<missing>")

    driver.setViewport(size(480, 320))
    check driver.debugReport().contains("480.0x320.0")

  test "driver can save and compare approved snapshot baselines":
    let driver = initCbssTestDriver(buildControlsUi, size(320, 240))
    let path = getTempDir() / "cbss_test_driver_approved_snapshot.json"
    let textPath = getTempDir() / "cbss_test_driver_approved_snapshot.txt"

    check driver.expectApprovedSnapshot(path).ok == false
    check driver.expectApprovedSnapshot(path, update = true).ok
    check fileExists(path)
    check driver.expectApprovedSnapshot(path).ok

    let before = readFile(path)
    check before.contains("\"nodes\"")
    writeFile(path, before & "\nchanged")
    let mismatch = driver.expectApprovedSnapshot(path)
    check not mismatch.ok
    check mismatch.message.contains("snapshot mismatch")

    driver.saveApprovedSnapshot(textPath, structured = false)
    check readFile(textPath).contains("layout:")
    check driver.expectApprovedSnapshot(textPath, structured = false).ok

  test "driver supports named baseline paths env updates and actual output":
    let driver = initCbssTestDriver(buildControlsUi, size(320, 240))
    let directory = getTempDir() / "cbss_test_driver_baselines"
    let path = approvedSnapshotPath(directory, "controls")
    let actualPath = actualSnapshotPath(path)
    let previousEnv = getEnv(cbssUpdateSnapshotsEnv)

    if fileExists(path):
      removeFile(path)
    if fileExists(actualPath):
      removeFile(actualPath)

    check path.endsWith("controls.json")
    check driver.expectApprovedSnapshot(directory, "controls", update = true).ok
    check fileExists(path)

    writeFile(path, "{}")
    let mismatch = driver.expectApprovedSnapshot(directory, "controls")
    check not mismatch.ok
    check fileExists(actualPath)
    check readFile(actualPath).contains("\"nodes\"")

    putEnv(cbssUpdateSnapshotsEnv, "1")
    check shouldUpdateApprovedSnapshots()
    check driver.expectApprovedSnapshot(directory, "controls").ok
    check readFile(path).contains("\"nodes\"")

    if previousEnv.len == 0:
      delEnv(cbssUpdateSnapshotsEnv)
    else:
      putEnv(cbssUpdateSnapshotsEnv, previousEnv)

  test "driver can aggregate large suite check summaries":
    let driver = initCbssTestDriver(buildControlsUi, size(320, 240))
    var summary = initCbssTestRunSummary()
    let path = getTempDir() / "cbss_test_driver_summary.txt"

    check summary.record("name exists", driver.expectExists(byId("name")))
    check summary.record("size value", driver.expectValue(byId("size"), "small"))
    check not summary.record("missing exists", driver.expectExists(byId("missing")))

    check summary.checks.len == 3
    check summary.passed == 2
    check summary.failed == 1
    check not summary.ok
    check summary.report().contains("checks: 3")
    check summary.report().contains("failed: 1")
    check summary.report().contains("missing exists")
    summary.save(path)
    check fileExists(path)
    check readFile(path).contains("missing exists")

  test "driver can save debug bundles and clear action logs":
    let driver = initCbssTestDriver(buildControlsUi, size(320, 240))
    let path = getTempDir() / "cbss_test_driver_debug_bundle.txt"

    check driver.click(byId("name"))
    check driver.typeText("trace")
    check driver.actionSnapshot().contains("typeText len=5")
    driver.saveDebugBundle(path, some(byId("name")))
    check fileExists(path)
    check readFile(path).contains("query: byId(name)")
    check readFile(path).contains("actions:")

    driver.clearActionLog()
    check driver.actionSnapshot() == ""

  test "driver can run scenario-style e2e checks with artifacts":
    let driver = initCbssTestDriver(buildControlsUi, size(360, 320))
    let directory = getTempDir() / "cbss_test_driver_scenario"
    var scenario = initCbssScenario("controls workflow", driver, directory)

    check scenario.step("fill name", proc(): bool =
      driver.fill(byId("name"), "Ada")
    , some(byId("name")))
    check scenario.expect("name persisted", driver.expectValue(byId("name"), "Ada"), some(byId("name")))

    check scenario.step("choose medium", proc(): bool =
      driver.chooseOption(byId("size"), "Medium")
    , some(byId("size")))
    check scenario.expect("size changed", driver.expectValue(byId("size"), "medium"), some(byId("size")))

    check not scenario.step("missing click", proc(): bool =
      driver.click(byId("missing"))
    , some(byId("missing")))

    check not scenario.ok
    check scenario.summary.checks.len == 5
    check scenario.summary.failed == 1
    check scenario.artifacts.len == 1
    check fileExists(scenario.artifacts[0])
    check readFile(scenario.artifacts[0]).contains("scenario: controls workflow")
    check readFile(scenario.artifacts[0]).contains("query: byId(missing)")
    check scenario.report().contains("artifacts:")
    check driver.actionSnapshot().contains("scenario step fill name")

  test "driver provides concise form workflow helpers":
    let driver = initCbssTestDriver(buildControlsUi, size(360, 320))

    check driver.fill(byId("name"), "Ada")
    check driver.value(byId("name")) == "Ada"
    check driver.clear(byId("name"))
    check driver.value(byId("name")) == ""

    check driver.chooseOption(byId("size"), "Large")
    check driver.value(byId("size")) == "large"

    check driver.toggle(byId("remember"))
    check driver.isChecked(byId("remember"))
    check driver.waitForDispatched(iekClick).ok

    let textCheck = driver.expectTextContains(byText("Large"), "Large")
    check textCheck.ok
    let snapshotCheck = driver.expectSnapshot(driver.snapshot())
    check snapshotCheck.ok

  test "driver exposes semantic state assertions":
    let driver = initCbssTestDriver(buildControlsUi, size(360, 320))

    check driver.expectFocused(byId("name"), expected = false).ok
    check driver.click(byId("name"))
    check driver.expectFocused(byId("name")).ok

    check driver.expectChecked(byId("remember"), expected = false).ok
    check driver.click(byId("remember"))
    check driver.expectChecked(byId("remember")).ok

    check driver.expectOpen(byId("size"), expected = false).ok
    check driver.click(byId("size"))
    check driver.expectOpen(byId("size")).ok
    check driver.expectState(byId("size"), esOpen).ok

  test "driver can assert stable layout and paint snapshots":
    let driver = initCbssTestDriver(buildControlsUi, size(360, 320))

    check driver.expectLayoutStable(proc(): bool =
      driver.exists(byId("remember"))
    ).ok
    check driver.expectPaintStable(proc(): bool =
      driver.exists(byId("remember"))
    ).ok

    check driver.exists(byId("remember"))

  test "scoped wait helpers report nested component state":
    proc buildScopedWaitUi(): UiRoot =
      result = initUiRoot()
      result.box("app"):
        let panel = result.box(code = "panel")
        result.pushParent(panel)
        try:
          discard result.textInput(TextInputParams(placeholder: "Name"), style = controlStyle())
        finally:
          result.popParent()

    let driver = initCbssTestDriver(buildScopedWaitUi, size(240, 120))
    let panel = driver.within(byCode("panel"))

    check panel.waitForExists(byPlaceholder("Name")).ok
    check panel.fill(byPlaceholder("Name"), "Scoped")
    check panel.waitForValue(byPlaceholder("Name"), "Scoped").ok
    let missing = panel.waitForExists(byText("Missing"), ticks = 1)
    check not missing.ok
    check missing.message.contains("within: byCode(panel)")
