import std/[options, os, strutils, times]

import clay_board_style_system
import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/backends/sdl3/text_event_guard
import clay_board_style_system/generated/default_properties
import clay_board_style_system/runtime/text_focus

type
  DemoFrame = object
    styles: ResolvedTree
    layout: LayoutResult
    commands: seq[PaintCommand]
    regions: seq[HitRegion]

  ValidationDemo = object
    ui: UiRoot
    form: FormHandle
    username: TextInputHandle
    email: TextInputHandle
    password: TextInputHandle
    confirmation: TextInputHandle
    terms: CheckboxHandle
    usernameMessage: LabelHandle
    emailMessage: LabelHandle
    passwordMessage: LabelHandle
    confirmationMessage: LabelHandle
    termsMessage: LabelHandle
    submitStatus: LabelHandle

const
  viewportWidth = 1040
  viewportHeight = 760

proc buildFrame(ui: UiRoot; viewport: Size): DemoFrame =
  var diagnostics: Diagnostics
  result.styles = resolveTreeStyles(
    ui.tree,
    ui.styleSheets(),
    defaultProperties(),
    diagnostics,
    viewportSize = some(viewport)
  )
  if diagnostics.hasErrors:
    for item in diagnostics.items:
      echo item.property, ": ", item.message
    raise newException(ValueError, "validation demo style resolution failed")
  result.layout = computeLayout(
    ui.tree,
    result.styles,
    viewport,
    ui.textEngine,
    ui.fonts
  )
  ui.scroll.syncScrollState(ui.tree, result.styles, result.layout)
  result.commands = buildPaintCommands(
    ui.tree,
    result.styles,
    result.layout,
    ui.scroll,
    ui.canvasPaintProvider()
  )
  result.regions = buildHitRegions(
    ui.tree,
    result.layout,
    result.styles,
    ui.scroll
  )

proc saveCapturedFrame(frame: Sdl3CapturedFrame; path: string) =
  var output = "P6\n" & $frame.width & " " & $frame.height & "\n255\n"
  let offset = output.len
  output.setLen(offset + frame.pixels.len)
  for index, value in frame.pixels:
    output[offset + index] = char(value)
  writeFile(path, output)

proc traceLayout(ui: UiRoot; frame: DemoFrame) =
  if getEnv("CBSS_VALIDATION_DEMO_TRACE_LAYOUT") != "1":
    return
  for box in frame.layout.boxes:
    let node = ui.tree.nodes[box.node.nodeIndex]
    if node.id.len > 0 or node.kind == nkText:
      echo "[validation-layout] id=", node.id,
        " kind=", node.kind,
        " text=", node.text,
        " rect=", box.rect

proc pageStyle(): UiStyle =
  uiStyle([
    width(viewportWidth),
    height(viewportHeight),
    padding(34),
    gap(24),
    flexDirection(fdColumn),
    alignItems(aiCenter),
    decl("background-color", colorValue(oklch(0.20, 0.025, 258))),
    decl("color", colorValue(oklch(0.94, 0.015, 255)))
  ])

proc headerStyle(): UiStyle =
  uiStyle([
    width(900),
    gap(7),
    flexDirection(fdColumn)
  ])

proc titleStyle(): UiStyle =
  uiStyle([
    fontSize(30),
    decl("line-height", px(38)),
    fontWeight(720),
    decl("color", colorValue(oklch(0.96, 0.015, 255)))
  ])

proc titleRowStyle(): UiStyle =
  uiStyle([
    height(38),
    gap(8),
    flexDirection(fdRow),
    alignItems(aiCenter)
  ])

proc subtitleStyle(): UiStyle =
  uiStyle([
    width(820),
    fontSize(14),
    decl("line-height", px(21)),
    decl("color", colorValue(oklch(0.74, 0.025, 255)))
  ])

proc panelStyle(): UiStyle =
  uiStyle([
    width(900),
    height(540),
    padding(26),
    gap(20),
    flexDirection(fdColumn),
    decl("background-color", colorValue(oklch(0.255, 0.03, 258))),
    borderWidth(1),
    decl("border-color", colorValue(oklch(0.38, 0.035, 258))),
    borderRadius(8),
    decl("box-shadow", shadowValue(
      px(0), px(18), some(px(45)), some(px(0)),
      some(rgba(0, 0, 0, 0.28))
    ))
  ])

proc columnsStyle(): UiStyle =
  uiStyle([
    width(848),
    height(300),
    gap(28),
    flexDirection(fdRow)
  ])

proc columnStyle(): UiStyle =
  uiStyle([
    width(410),
    gap(14),
    flexDirection(fdColumn)
  ])

proc sectionHeadingStyle(): UiStyle =
  uiStyle([
    fontSize(13),
    decl("line-height", px(18)),
    fontWeight(650),
    decl("color", colorValue(oklch(0.78, 0.11, 213)))
  ])

proc fieldStyle(): UiStyle =
  uiStyle([
    width(410),
    height(116),
    gap(5),
    flexDirection(fdColumn)
  ])

proc labelTextStyle(): UiStyle =
  uiStyle([
    fontSize(13),
    decl("line-height", px(18)),
    fontWeight(570),
    decl("color", colorValue(oklch(0.90, 0.015, 255)))
  ])

proc inputStyle(): UiStyle =
  uiStyle([
    width(410),
    height(44),
    padding(11),
    decl("background-color", colorValue(oklch(0.205, 0.025, 258))),
    borderWidth(1),
    decl("border-color", colorValue(oklch(0.42, 0.04, 258))),
    borderRadius(5),
    decl("cursor", keyword("text"))
  ])

proc inputTextStyle(): UiStyle =
  uiStyle([
    width(386),
    fontSize(14),
    decl("line-height", px(20)),
    decl("color", colorValue(oklch(0.95, 0.012, 255)))
  ])

proc messageStyle(): UiStyle =
  uiStyle([
    width(410),
    height(19),
    fontSize(12),
    decl("line-height", px(17)),
    decl("color", colorValue(oklch(0.72, 0.18, 25)))
  ])

proc hintStyle(): UiStyle =
  uiStyle([
    fontSize(11),
    decl("line-height", px(16)),
    decl("color", colorValue(oklch(0.64, 0.025, 255)))
  ])

proc actionRowStyle(): UiStyle =
  uiStyle([
    width(848),
    height(104),
    paddingTop(14),
    gap(16),
    flexDirection(fdRow),
    alignItems(aiCenter),
    justifyContent(jcSpaceBetween),
    borderTopWidth(1),
    decl("border-top-color", colorValue(oklch(0.37, 0.035, 258)))
  ])

proc termsBlockStyle(): UiStyle =
  uiStyle([
    width(560),
    height(76),
    gap(5),
    flexDirection(fdColumn)
  ])

proc checkboxStyle(): UiStyle =
  uiStyle([
    height(30),
    gap(9),
    flexDirection(fdRow),
    alignItems(aiCenter),
    decl("cursor", keyword("pointer"))
  ])

proc checkboxMarkerStyle(): UiStyle =
  uiStyle([
    width(18),
    height(18),
    alignItems(aiCenter),
    justifyContent(jcCenter),
    decl("background-color", colorValue(oklch(0.205, 0.025, 258))),
    borderWidth(1),
    decl("border-color", colorValue(oklch(0.48, 0.045, 258))),
    borderRadius(3)
  ])

proc checkboxLabelStyle(): UiStyle =
  uiStyle([
    fontSize(14),
    decl("line-height", px(20)),
    decl("color", colorValue(oklch(0.91, 0.015, 255)))
  ])

proc submitButtonStyle(): UiStyle =
  uiStyle([
    width(176),
    height(44),
    padding(11),
    alignItems(aiCenter),
    justifyContent(jcCenter),
    decl("background-color", colorValue(oklch(0.68, 0.15, 194))),
    borderWidth(1),
    decl("border-color", colorValue(oklch(0.79, 0.13, 194))),
    borderRadius(5),
    decl("cursor", keyword("pointer"))
  ])

proc submitButtonTextStyle(): UiStyle =
  uiStyle([
    fontSize(14),
    decl("line-height", px(20)),
    fontWeight(700),
    decl("color", colorValue(oklch(0.19, 0.035, 212)))
  ])

proc statusStyle(): UiStyle =
  uiStyle([
    width(848),
    height(26),
    fontSize(13),
    decl("line-height", px(20)),
    decl("color", colorValue(oklch(0.76, 0.045, 255)))
  ])

proc decorateInput(input: TextInputHandle) =
  input.container.applyStateStyle({esFocus}, uiStyle([
    borderWidth(2),
    decl("border-color", colorValue(oklch(0.76, 0.13, 213)))
  ]), priority = 80)
  input.container.applyStateStyle({esInvalid}, uiStyle([
    borderWidth(2),
    decl("border-color", colorValue(oklch(0.68, 0.19, 25))),
    decl("box-shadow", shadowValue(
      px(0),
      px(0),
      some(px(12)),
      some(px(1)),
      some(rgba(0.95, 0.18, 0.22, 0.28))
    ))
  ]), priority = 90)

proc addTextField(
    demo: var ValidationDemo;
    parent: NodeHandle;
    labelText, hint, placeholder, id: string;
    rules: ValidationRules[string];
    reportOn: ValidationReport;
    inputType = TextInputType.text
): tuple[input: TextInputHandle, message: LabelHandle] =
  let field = demo.ui.box(fieldStyle(), parent = some(parent), id = id & "-field")
  demo.ui.pushParent(field)
  try:
    let fieldLabel = demo.ui.label(
      labelText,
      style = uiStyle([height(18)]),
      textStyle = labelTextStyle()
    )
    result.input = demo.ui.textInput(
      "",
      rules,
      reportOn = reportOn,
      placeholder = placeholder,
      inputType = inputType,
      style = inputStyle(),
      textStyle = inputTextStyle(),
      id = id
    )
    result.input.decorateInput()
    fieldLabel.setTarget(result.input.container)
    result.message = demo.ui.label(
      "",
      style = uiStyle([height(19)]),
      textStyle = messageStyle(),
      id = id & "-message"
    )
    discard demo.ui.text(hint, style = hintStyle())
  finally:
    demo.ui.popParent()

proc buildValidationDemo(): ValidationDemo =
  result.ui = initUiRoot()
  let page = result.ui.box(pageStyle(), id = "validation-demo")
  result.ui.pushParent(page)
  try:
    let header = result.ui.box(headerStyle())
    result.ui.pushParent(header)
    let titleRow = result.ui.box(titleRowStyle())
    result.ui.pushParent(titleRow)
    discard result.ui.text("Reactive", style = titleStyle())
    discard result.ui.text("form", style = titleStyle())
    discard result.ui.text("validation", style = titleStyle())
    result.ui.popParent()
    discard result.ui.text(
      "One form demonstrates input, blur, submit, and cross-field validation without a browser or WebView.",
      style = subtitleStyle()
    )
    result.ui.popParent()

    result.form = result.ui.form(style = panelStyle(), id = "account-form")
    result.ui.pushParent(result.form.container)
    try:
      let columns = result.ui.box(columnsStyle())
      result.ui.pushParent(columns)
      try:
        let identityColumn = result.ui.box(columnStyle())
        result.ui.pushParent(identityColumn)
        discard result.ui.text("INPUT + BLUR", style = sectionHeadingStyle())
        result.ui.popParent()

        let usernameField = result.addTextField(
          identityColumn,
          "Username",
          "Checks while typing: 3+ characters, letters/numbers/_",
          "ada_lovelace",
          "validation-username",
          validationRules[string]()
            .required("Enter a username")
            .minLength(3, "Use at least 3 characters")
            .matches(
              compileRegex("^[A-Za-z][A-Za-z0-9_]*$"),
              "Start with a letter; use letters, numbers, or _"
            ),
          ValidationReport.onInput
        )
        result.username = usernameField.input
        result.usernameMessage = usernameField.message

        let emailField = result.addTextField(
          identityColumn,
          "Email",
          "Checks only after focus leaves this field",
          "name@site.dev",
          "validation-email",
          validationRules[string]()
            .required("Enter an email address")
            .email("Enter a valid email address"),
          ValidationReport.onBlur
        )
        result.email = emailField.input
        result.emailMessage = emailField.message

        let credentialColumn = result.ui.box(columnStyle())
        result.ui.pushParent(credentialColumn)
        discard result.ui.text("CROSS-FIELD", style = sectionHeadingStyle())
        result.ui.popParent()

        let passwordField = result.addTextField(
          credentialColumn,
          "Passphrase",
          "Checks while typing: at least 8 characters",
          "Eight or more characters",
          "validation-password",
          validationRules[string]()
            .required("Enter a passphrase")
            .minLength(8, "Use at least 8 characters"),
          ValidationReport.onInput,
          TextInputType.password
        )
        result.password = passwordField.input
        result.passwordMessage = passwordField.message

        let confirmationField = result.addTextField(
          credentialColumn,
          "Confirmation",
          "Rechecks automatically when either field changes",
          "Repeat the passphrase",
          "validation-confirmation",
          validationRules[string]()
            .required("Repeat the passphrase")
            .sameAs(
              result.password.validationValue,
              "Passphrases do not match"
            ),
          ValidationReport.onInput,
          TextInputType.password
        )
        result.confirmation = confirmationField.input
        result.confirmationMessage = confirmationField.message
      finally:
        result.ui.popParent()

      let actions = result.ui.box(actionRowStyle())
      result.ui.pushParent(actions)
      try:
        let termsBlock = result.ui.box(termsBlockStyle())
        result.ui.pushParent(termsBlock)
        result.terms = result.ui.checkbox(
          "I accept the project terms",
          validationRules[bool]().equalTo(
            true,
            "Accept the terms before submitting"
          ),
          reportOn = ValidationReport.onSubmit,
          style = checkboxStyle(),
          markerStyle = checkboxMarkerStyle(),
          labelStyle = checkboxLabelStyle(),
          id = "validation-terms"
        )
        result.termsMessage = result.ui.label(
          "",
          style = uiStyle([height(19)]),
          textStyle = messageStyle(),
          id = "validation-terms-message"
        )
        discard result.ui.text(
          "This rule remains quiet until Submit is pressed.",
          style = hintStyle()
        )
        result.ui.popParent()

        let submit = result.ui.button(
          "Create account",
          style = submitButtonStyle(),
          textStyle = submitButtonTextStyle(),
          id = "validation-submit"
        )
        let form = result.form
        submit.onClick = proc(event: DispatchResult): EventOutcome =
          if form.submit(): handledEvent() else: stoppedEvent()
      finally:
        result.ui.popParent()

      result.submitStatus = result.ui.label(
        "Fill the fields, then submit to exercise the complete form path.",
        style = uiStyle([height(26)]),
        textStyle = statusStyle(),
        id = "validation-status"
      )
    finally:
      result.ui.popParent()
  finally:
    result.ui.popParent()

  result.form.register("username", result.username)
  result.form.register("email", result.email)
  result.form.register("password", result.password)
  result.form.register("confirmation", result.confirmation)
  result.form.register("terms", result.terms)

  let status = result.submitStatus
  result.form.onSubmit = proc(event: DispatchResult): EventOutcome =
    status.setText("Valid form submitted. FormData contains 5 typed fields.")
    handledEvent()
  result.form.onInvalid = proc(event: DispatchResult): EventOutcome =
    status.setText("Submission blocked. Focus moved to the first invalid field.")
    handledEvent()

proc syncMessages(demo: var ValidationDemo): bool =
  let messages = [
    (demo.usernameMessage, demo.username.validationMessage),
    (demo.emailMessage, demo.email.validationMessage),
    (demo.passwordMessage, demo.password.validationMessage),
    (demo.confirmationMessage, demo.confirmation.validationMessage),
    (demo.termsMessage, demo.terms.validationMessage)
  ]
  for item in messages:
    if item[0].text != item[1]:
      item[0].setText(item[1])
      result = true

proc focusedEvent(
    demo: ValidationDemo;
    interaction: InteractionState;
    event: InputEvent
): bool =
  if interaction.focusedTarget.isNone:
    return false
  demo.ui.events.emit(demo.ui.tree, interaction.focusedTarget.get, event)

proc syncTextInputArea(
    renderer: var Sdl3Renderer;
    demo: ValidationDemo;
    frame: DemoFrame;
    interaction: InteractionState
) =
  if interaction.focusedTarget.isNone or
      not demo.ui.isTextInputTarget(interaction.focusedTarget.get):
    discard renderer.setTextInputArea(none(Rect))
    return
  for box in frame.layout.boxes:
    if box.node == interaction.focusedTarget.get:
      discard renderer.setTextInputArea(some(box.rect), 0)
      return
  discard renderer.setTextInputArea(none(Rect))

proc main() =
  var demo = buildValidationDemo()
  demo.ui.configureClipboardTextProvider(proc(): string = clipboardText(1_048_576))
  demo.ui.configureClipboardTextWriter(proc(text: string) =
    discard setClipboardText(text)
  )

  var fonts = initFontRegistry()
  fonts.addFallbackFamily("Noto Sans")
  fonts.addFallbackFamily("Noto Sans CJK JP")
  var cosmic = initCosmicTextEngine(fonts)
  defer:
    cosmic.close()
  demo.ui.configureTextLayout(cosmic.textEngine(), fonts)

  var renderer = initSdl3Renderer(
    "Clay Board Style System - Reactive Validation",
    viewportWidth,
    viewportHeight,
    resizable = true
  )
  defer:
    renderer.close()

  var viewport = renderer.windowSize()
  var frame = demo.ui.buildFrame(viewport)
  demo.ui.traceLayout(frame)
  var interaction = initInteractionState()
  var scheduler = initFrameScheduler({ddStyle, ddLayout, ddPaint, ddHit})
  var running = true
  var queued = none(Sdl3Event)
  var compositionTarget = none(NodeId)
  let capturePath = getEnv("CBSS_VALIDATION_DEMO_CAPTURE")
  let captureOnly = getEnv("CBSS_VALIDATION_DEMO_CAPTURE_ONLY") == "1"
  var capturePending = capturePath.len > 0
  let traceEvents = getEnv("CBSS_VALIDATION_DEMO_TRACE_EVENTS") == "1"

  proc markInteractiveDirty() =
    scheduler.markDirty({ddStyle, ddLayout, ddPaint, ddHit})

  proc resetCompositionForFocusChange() =
    compositionTarget = none(NodeId)
    discard renderer.clearTextComposition()
    renderer.discardPendingTextInputEvents()

  proc handleEvent(event: Sdl3Event) =
    if traceEvents:
      echo "[validation-event] ", event.kind
    case event.kind
    of sekQuit:
      running = false
    of sekExpose:
      scheduler.markDirty(ddPaint)
    of sekResize:
      viewport = size(event.width.float32, event.height.float32)
      scheduler.markDirty({ddStyle, ddLayout, ddPaint, ddHit})
    of sekFocus:
      demo.ui.invalidateClipboardText()
      markInteractiveDirty()
    of sekBlur:
      discard demo.focusedEvent(interaction, InputEvent(kind: iekBlur))
      resetCompositionForFocusChange()
      markInteractiveDirty()
    of sekPointerMove:
      let point = vec2(event.x, event.y)
      renderer.setCursor(cursorAt(frame.regions, point))
      var dispatches = interaction.processInput(
        demo.ui.tree,
        frame.regions,
        pointerMoveEvent(point, event.pointer, event.timestamp),
        demo.ui.scroll
      )
      demo.ui.normalizeTextControlDispatches(frame.regions, dispatches)
      discard demo.ui.handleEvents(dispatches)
      markInteractiveDirty()
    of sekPointerDown:
      let point = vec2(event.buttonX, event.buttonY)
      let previousFocus = interaction.focusedTarget
      let hit = hitTest(frame.regions, point)
      let target = if hit.isSome: some(hit.get.node) else: none(NodeId)
      if demo.ui.closeOpenPopups(target):
        markInteractiveDirty()
        return
      var dispatches = interaction.processInput(
        demo.ui.tree,
        frame.regions,
        pointerDownEvent(point, event.button, event.pointer, event.timestamp),
        demo.ui.scroll
      )
      demo.ui.normalizeTextControlDispatches(frame.regions, dispatches)
      discard demo.ui.handleEvents(dispatches)
      let textHit = demo.ui.textControlHitAtPoint(frame.regions, point)
      let focusTarget = if textHit.isSome: some(textHit.get.node) else: target
      demo.ui.normalizeTextControlFocus(interaction, focusTarget)
      discard demo.ui.reconcileFocus(interaction)
      if previousFocus != interaction.focusedTarget:
        resetCompositionForFocusChange()
      markInteractiveDirty()
    of sekPointerUp:
      let point = vec2(event.buttonX, event.buttonY)
      var dispatches = interaction.processInput(
        demo.ui.tree,
        frame.regions,
        pointerUpEvent(point, event.button, event.pointer, event.timestamp),
        demo.ui.scroll
      )
      demo.ui.normalizeTextControlDispatches(frame.regions, dispatches)
      discard demo.ui.handleEvents(dispatches)
      discard demo.ui.reconcileFocus(interaction)
      markInteractiveDirty()
    of sekPointerCancel:
      let input = event.pointerInputEvent()
      if input.isSome:
        var dispatches = interaction.processInput(
          demo.ui.tree, frame.regions, input.get, demo.ui.scroll
        )
        demo.ui.normalizeTextControlDispatches(frame.regions, dispatches)
        discard demo.ui.handleEvents(dispatches)
      markInteractiveDirty()
    of sekKeyDown:
      if event.key == "Tab" and not event.ctrl and not event.alt and not event.meta:
        let previousFocus = interaction.focusedTarget
        discard demo.ui.moveTextControlFocus(
          interaction,
          if event.shift: -1 else: 1
        )
        if previousFocus != interaction.focusedTarget:
          resetCompositionForFocusChange()
      elif interaction.focusedTarget.isSome:
        let focused = interaction.focusedTarget.get
        let textFocused = demo.ui.isTextInputTarget(focused)
        if textFocused and (event.ctrl or event.meta):
          let changed =
            case event.key.toLowerAscii()
            of "c": demo.ui.events.emit(demo.ui.tree, focused, copyEvent())
            of "x": demo.ui.events.emit(demo.ui.tree, focused, cutEvent())
            of "v": demo.ui.events.emit(
              demo.ui.tree,
              focused,
              pasteEvent(demo.ui.clipboardText())
            )
            else: demo.ui.events.emit(
              demo.ui.tree,
              focused,
              keyDownEvent(
                event.key,
                ctrlKey = event.ctrl,
                altKey = event.alt,
                shiftKey = event.shift,
                metaKey = event.meta
              )
            )
          if changed:
            discard
        elif not textFocused or not event.isPrintableTextKey:
          discard demo.ui.events.emit(
            demo.ui.tree,
            focused,
            keyDownEvent(
              event.key,
              ctrlKey = event.ctrl,
              altKey = event.alt,
              shiftKey = event.shift,
              metaKey = event.meta
            )
          )
      discard demo.ui.reconcileFocus(interaction)
      markInteractiveDirty()
    of sekKeyUp:
      discard demo.focusedEvent(interaction, keyUpEvent(
        event.key,
        ctrlKey = event.ctrl,
        altKey = event.alt,
        shiftKey = event.shift,
        metaKey = event.meta
      ))
    of sekTextInput:
      if interaction.focusedTarget.isSome and
          demo.ui.isValidTextInputTarget(interaction.focusedTarget.get) and
          (compositionTarget.isNone or
            compositionTarget == interaction.focusedTarget):
        discard demo.ui.events.emit(
          demo.ui.tree,
          interaction.focusedTarget.get,
          textInputEvent(event.text)
        )
        compositionTarget = none(NodeId)
        markInteractiveDirty()
    of sekCompositionStart:
      if interaction.focusedTarget.isSome and
          demo.ui.isValidTextInputTarget(interaction.focusedTarget.get):
        compositionTarget = interaction.focusedTarget
        discard demo.focusedEvent(interaction, compositionStartEvent(event.text))
      markInteractiveDirty()
    of sekCompositionUpdate:
      if compositionTarget.isSome and
          compositionTarget == interaction.focusedTarget:
        discard demo.focusedEvent(interaction, compositionUpdateEvent(event.text))
      markInteractiveDirty()
    of sekCompositionEnd:
      if compositionTarget.isSome and
          compositionTarget == interaction.focusedTarget:
        discard demo.focusedEvent(interaction, compositionEndEvent(event.text))
      compositionTarget = none(NodeId)
      markInteractiveDirty()
    of sekWheel:
      let point = vec2(event.wheelMouseX, event.wheelMouseY)
      let dispatches = interaction.processInput(
        demo.ui.tree,
        frame.regions,
        wheelEvent(point, event.scrollDelta()),
        demo.ui.scroll
      )
      discard demo.ui.handleEvents(dispatches)
      markInteractiveDirty()
    else:
      discard
    discard demo.ui.reconcilePointerCapture(interaction)
    discard demo.ui.reconcileFocus(interaction)
    if demo.syncMessages():
      markInteractiveDirty()

  while running:
    var event: Sdl3Event
    if queued.isSome:
      handleEvent(queued.get)
      queued = none(Sdl3Event)
    while running and renderer.pollEvent(event):
      handleEvent(event)
    if not running:
      break

    scheduler.markDirty(demo.ui.consumeInvalidation().domains)
    let dirty = scheduler.consumeDirty()
    if dirty != {}:
      frame = demo.ui.buildFrame(viewport)
      if capturePending:
        renderer.requestFrameCapture()
      renderer.render(
        frame.commands,
        cosmic,
        fonts,
        oklch(0.20, 0.025, 258).resolveColor()
      )
      renderer.syncTextInputArea(demo, frame, interaction)
      if capturePending and renderer.capturedFrame().isSome:
        saveCapturedFrame(renderer.capturedFrame().get, capturePath)
        capturePending = false
        if captureOnly:
          running = false

    if not running:
      break

    let timeout = scheduler.waitTimeoutMs(epochTime())
    let received =
      if timeout < 0: renderer.waitEvent(event)
      else: renderer.waitEventTimeout(event, timeout)
    if received:
      queued = some(event)

when isMainModule:
  main()
