import std/[options, os, strformat, strutils, times]

import clay_board_style_system
import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/frontend_runtime
import clay_board_style_system/generated/default_properties

type
  DemoFrame = object
    styles: ResolvedTree
    layout: LayoutResult
    commands: seq[PaintCommand]
    regions: seq[HitRegion]

  StageStatus = enum
    ssIdle,
    ssRunning,
    ssComplete

  StageVisual = object
    container: NodeHandle
    status: LabelHandle

  PendingAction = ref object
    completion: CueCompletion
    visual: StageVisual
    dueAt: float64
    settled: bool

const
  viewportWidth = 1180
  viewportHeight = 720
  demoBackground = rgb(0.025, 0.031, 0.043)

proc textStyle(
    fontSize: float32;
    color: Color;
    weight = 400.0'f32;
    lineHeight = 0.0'f32
): UiStyle =
  uiStyle([
    decl("font-size", px(fontSize)),
    decl("line-height", px(
      if lineHeight > 0: lineHeight else: fontSize + 6
    )),
    decl("font-weight", number(weight)),
    decl("color", colorValue(color))
  ])

proc stageStyle(): UiStyle =
  uiStyle([
    decl("width", px(196)),
    decl("height", px(86)),
    decl("padding", px(14)),
    decl("gap", px(5)),
    decl("flex-direction", keyword("column")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(rgb(0.075, 0.087, 0.115))),
    decl("border-width", px(1)),
    decl("border-color", colorValue(rgb(0.17, 0.20, 0.27))),
    decl("border-radius", px(6)),
    decl("transform", transformValue(
      translate(px(0), px(0)), scale(1, some(1.0'f32)), rotate(0)
    )),
    transitionProperties("background-color", "border-color", "transform"),
    transitionDurations(0.24'f32, 0.24'f32, 0.28'f32),
    transitionTimingFunctions(
      "ease-out", "ease-out", "cubic-bezier(0.16, 1, 0.3, 1)"
    )
  ])

proc statusStyle(status: StageStatus): UiStyle =
  case status
  of ssIdle:
    uiStyle([
      decl("background-color", colorValue(rgb(0.075, 0.087, 0.115))),
      decl("border-color", colorValue(rgb(0.17, 0.20, 0.27))),
      decl("transform", transformValue(
        translate(px(0), px(0)), scale(1, some(1.0'f32)), rotate(0)
      ))
    ])
  of ssRunning:
    uiStyle([
      decl("background-color", colorValue(oklch(0.31, 0.085, 225).resolveColor())),
      decl("border-color", colorValue(oklch(0.78, 0.14, 205).resolveColor())),
      decl("transform", transformValue(
        translate(px(0), px(-3)), scale(1.025, some(1.025'f32)), rotate(0)
      ))
    ])
  of ssComplete:
    uiStyle([
      decl("background-color", colorValue(oklch(0.27, 0.075, 150).resolveColor())),
      decl("border-color", colorValue(oklch(0.75, 0.13, 150).resolveColor())),
      decl("transform", transformValue(
        translate(px(0), px(0)), scale(1, some(1.0'f32)), rotate(0)
      ))
    ])

proc stageStatusText(status: StageStatus): string =
  case status
  of ssIdle: "WAITING"
  of ssRunning: "RUNNING"
  of ssComplete: "COMPLETE"

proc setStatus(visual: StageVisual; status: StageStatus) =
  visual.container.applyStyle(statusStyle(status))
  visual.status.setText(status.stageStatusText)

proc addStage(
    ui: UiRoot;
    parent: NodeHandle;
    code, title, description: string
): StageVisual =
  result.container = ui.box(
    stageStyle(), parent = some(parent), id = "cue-stage-" & code.toLowerAscii()
  )
  ui.pushParent(result.container)
  try:
    let heading = ui.box(uiStyle([
      decl("width", px(168)),
      decl("height", px(21)),
      decl("flex-direction", keyword("row")),
      decl("justify-content", keyword("space-between")),
      decl("align-items", keyword("center"))
    ]))
    discard ui.text(
      heading, code, textStyle(12, rgb(0.50, 0.86, 0.95), 760, 17)
    )
    result.status = ui.label(
      "WAITING",
      style = uiStyle([
        decl("width", px(72)),
        decl("height", px(17)),
        decl("justify-content", keyword("flex-end"))
      ]),
      textStyle = textStyle(9, rgb(0.54, 0.60, 0.70), 700, 13)
    )
    discard ui.text(
      result.container,
      title,
      textStyle(15, rgb(0.94, 0.96, 0.98), 680, 19)
    )
    discard ui.text(
      result.container,
      description,
      textStyle(10, rgb(0.55, 0.62, 0.72), 480, 14)
    )
  finally:
    ui.popParent()

proc connectorStyle(width: float32): UiStyle =
  uiStyle([
    decl("width", px(width)),
    decl("height", px(1)),
    decl("background-color", colorValue(rgb(0.23, 0.29, 0.38)))
  ])

proc rebuildFrame(
    ui: UiRoot;
    frame: var DemoFrame;
    viewport: Size;
    scheduler: var FrameScheduler;
    nowSeconds: float64
) =
  var diagnostics: Diagnostics
  var target = resolveTreeStyles(
    ui.tree,
    ui.styleSheets(),
    defaultProperties(),
    diagnostics,
    viewportSize = some(viewport)
  )
  if diagnostics.hasErrors:
    for item in diagnostics.items:
      echo item.property, ": ", item.message
    raise newException(ValueError, "orchestration demo style resolution failed")

  if frame.styles.styles.len > 0:
    ui.reconcileStyleTransitions(frame.styles, target, nowSeconds)
  ui.reconcileStyleAnimations(target, nowSeconds)
  frame.styles = target
  discard ui.applyStyleTransitions(frame.styles, scheduler, nowSeconds)
  discard ui.applyStyleAnimations(frame.styles, scheduler, nowSeconds)
  frame.layout = computeLayout(
    ui.tree, frame.styles, viewport, ui.textEngine, ui.fonts
  )
  ui.scroll.syncScrollState(ui.tree, frame.styles, frame.layout)
  ui.syncRenderSurfaces(frame.styles, frame.layout)
  frame.commands = buildPaintCommands(
    ui.tree, frame.styles, frame.layout, ui.scroll, ui.canvasPaintProvider()
  )
  frame.regions = buildHitRegions(
    ui.tree, frame.layout, frame.styles, ui.scroll
  )

proc refreshPaint(ui: UiRoot; frame: var DemoFrame; refreshHit: bool) =
  ui.syncRenderSurfaces(frame.styles, frame.layout)
  frame.commands = buildPaintCommands(
    ui.tree, frame.styles, frame.layout, ui.scroll, ui.canvasPaintProvider()
  )
  if refreshHit:
    frame.regions = buildHitRegions(
      ui.tree, frame.layout, frame.styles, ui.scroll
    )

proc saveCapturedFrame(frame: Sdl3CapturedFrame; path: string) =
  var output = "P6\n" & $frame.width & " " & $frame.height & "\n255\n"
  let offset = output.len
  output.setLen(offset + frame.pixels.len)
  for index, value in frame.pixels:
    output[offset + index] = char(value)
  writeFile(path, output)

when not defined(release) or defined(cbssFrontendTrace):
  proc traceLine(event: FrontendTraceEvent): string =
    var label = $event.kind
    if label.startsWith("ftk"):
      label = label[3 .. ^1]
    result = &"{event.sequence:>3}  {label}"
    if event.name.len > 0:
      result.add "  /  " & event.name

proc main() =
  var fonts = initFontRegistry()
  fonts.addFallbackFamily("Noto Sans")
  fonts.addFallbackFamily("Noto Sans CJK JP")
  var cosmic = initCosmicTextEngine(fonts)
  defer:
    cosmic.close()

  let ui = initUiRoot()
  ui.configureTextLayout(cosmic.textEngine(), fonts)

  let root = ui.box(uiStyle([
    decl("width", px(viewportWidth)),
    decl("height", px(viewportHeight)),
    decl("padding", px(30)),
    decl("gap", px(20)),
    decl("flex-direction", keyword("column")),
    decl("background-color", colorValue(demoBackground)),
    decl("color", colorValue(rgb(0.94, 0.96, 0.98)))
  ]), id = "orchestration-demo")

  let header = ui.box(uiStyle([
    decl("width", px(1120)),
    decl("height", px(70)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("space-between")),
    decl("border-bottom-width", px(1)),
    decl("border-bottom-color", colorValue(rgb(0.17, 0.20, 0.26)))
  ]), parent = some(root))
  let titleBlock = ui.box(uiStyle([
    decl("gap", px(2)),
    decl("flex-direction", keyword("column"))
  ]), parent = some(header))
  discard ui.text(
    titleBlock, "CUE / ORCHESTRATION",
    textStyle(27, rgb(0.96, 0.97, 0.99), 760, 34)
  )
  discard ui.text(
    titleBlock, "ONE TRIGGER. PARALLEL STAGES. DETERMINISTIC JOIN.",
    textStyle(10, rgb(0.41, 0.78, 0.87), 650, 15)
  )

  ui.pushParent(header)
  let launchButton = ui.button(
      "RUN SEQUENCE",
      style = uiStyle([
        decl("width", px(166)),
        decl("height", px(42)),
        decl("align-items", keyword("center")),
        decl("justify-content", keyword("center")),
        decl("background-color", colorValue(oklch(0.66, 0.18, 30).resolveColor())),
        decl("border-width", px(1)),
        decl("border-color", colorValue(oklch(0.80, 0.12, 38).resolveColor())),
        decl("border-radius", px(5)),
        decl("cursor", keyword("pointer"))
      ]),
      textStyle = textStyle(11, rgb(1.0, 0.97, 0.92), 760, 16),
      id = "run-sequence"
    )
  ui.popParent()
  launchButton.container.applyHoverStyle(uiStyle([
    decl("background-color", colorValue(oklch(0.72, 0.19, 33).resolveColor()))
  ]))

  let workspace = ui.box(uiStyle([
    decl("width", px(1120)),
    decl("height", px(570)),
    decl("gap", px(20)),
    decl("flex-direction", keyword("row"))
  ]), parent = some(root))

  let sequencePanel = ui.box(uiStyle([
    decl("width", px(780)),
    decl("height", px(570)),
    decl("padding", px(24)),
    decl("gap", px(18)),
    decl("flex-direction", keyword("column")),
    decl("background-color", colorValue(rgb(0.045, 0.054, 0.073))),
    decl("border-width", px(1)),
    decl("border-color", colorValue(rgb(0.13, 0.16, 0.22))),
    decl("border-radius", px(7))
  ]), parent = some(workspace))
  discard ui.text(
    sequencePanel,
    "A  ->  ( B + C + D )  ->  E",
    textStyle(16, rgb(0.86, 0.90, 0.95), 680, 22)
  )
  discard ui.text(
    sequencePanel,
    "B, C, and D share one logical stage. C and D use stage-relative delays.",
    textStyle(11, rgb(0.50, 0.58, 0.68), 480, 17)
  )

  let flow = ui.box(uiStyle([
    decl("width", px(732)),
    decl("height", px(320)),
    decl("gap", px(14)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center"))
  ]), parent = some(sequencePanel))
  let stageA = ui.addStage(flow, "A", "INTAKE", "Event entry / 0.45 s")
  discard ui.box(connectorStyle(28), parent = some(flow))

  let parallelColumn = ui.box(uiStyle([
    decl("width", px(196)),
    decl("height", px(286)),
    decl("gap", px(14)),
    decl("flex-direction", keyword("column")),
    decl("justify-content", keyword("center"))
  ]), parent = some(flow))
  let stageB = ui.addStage(parallelColumn, "B", "LAYOUT", "Immediate / 0.75 s")
  let stageC = ui.addStage(parallelColumn, "C", "PAINT", "+ 0.15 s / 0.60 s")
  let stageD = ui.addStage(parallelColumn, "D", "SIGNAL", "+ 0.30 s / 0.45 s")

  discard ui.box(connectorStyle(28), parent = some(flow))
  let stageE = ui.addStage(flow, "E", "COMMIT", "All-join / 0.50 s")

  ui.pushParent(sequencePanel)
  let summary = ui.label(
    "IDLE / WAITING FOR A TYPED SIGNAL",
    style = uiStyle([
      decl("width", px(732)),
      decl("height", px(52)),
      decl("padding", px(14)),
      decl("align-items", keyword("center")),
      decl("background-color", colorValue(rgb(0.065, 0.076, 0.099))),
      decl("border-left-width", px(3)),
      decl("border-left-color", colorValue(rgb(0.25, 0.69, 0.80))),
      decl("border-radius", px(4))
    ]),
    textStyle = textStyle(11, rgb(0.68, 0.76, 0.85), 680, 16),
    id = "sequence-summary"
  )
  ui.popParent()

  let tracePanel = ui.box(uiStyle([
    decl("width", px(320)),
    decl("height", px(570)),
    decl("padding", px(20)),
    decl("gap", px(12)),
    decl("flex-direction", keyword("column")),
    decl("background-color", colorValue(rgb(0.92, 0.91, 0.86))),
    decl("border-radius", px(7))
  ]), parent = some(workspace))
  discard ui.text(
    tracePanel, "RUNTIME TRACE",
    textStyle(13, rgb(0.10, 0.12, 0.14), 780, 18)
  )
  discard ui.text(
    tracePanel,
    "Bounded development diagnostics. Excluded from ordinary release builds.",
    textStyle(10, rgb(0.34, 0.37, 0.39), 500, 15)
  )
  ui.pushParent(tracePanel)
  let traceLabel = ui.label(
    "No events yet.",
    style = uiStyle([
      decl("width", px(280)),
      decl("height", px(430)),
      decl("padding", px(14)),
      decl("background-color", colorValue(rgb(0.075, 0.083, 0.092))),
      decl("border-radius", px(4)),
      decl("overflow", keyword("hidden"))
    ]),
    textStyle = uiStyle([
      decl("width", px(252)),
      decl("font-size", px(10)),
      decl("line-height", px(17)),
      decl("font-family", keyword("monospace")),
      decl("white-space", keyword("pre-wrap")),
      decl("color", colorValue(rgb(0.73, 0.82, 0.80)))
    ]),
    id = "runtime-trace"
  )
  ui.popParent()

  var scheduler = initFrameScheduler({ddStyle, ddLayout, ddPaint, ddHit})
  let runtime = initCueRuntime(epochTime())
  defer:
    discard runtime.dispose()
  when not defined(release) or defined(cbssFrontendTrace):
    let trace = runtime.enableTrace(128)
  var pending: seq[PendingAction]

  proc makeAction(
      name: string;
      visual: StageVisual;
      durationSeconds: float64
  ): CueAction =
    cueAction(name, proc(completion: CueCompletion): CueCancel =
      visual.setStatus(ssRunning)
      scheduler.markDirty({ddStyle, ddPaint, ddHit})
      let item = PendingAction(
        completion: completion,
        visual: visual,
        dueAt: runtime.now + durationSeconds
      )
      pending.add item
      return proc() {.raises: [].} =
        if not item.settled:
          item.settled = true
          try:
            item.visual.setStatus(ssIdle)
          except Exception:
            discard
    )

  let actionA = makeAction("A / intake", stageA, 0.45)
  let actionB = makeAction("B / layout", stageB, 0.75)
  let actionC = makeAction("C / paint", stageC, 0.60)
  let actionD = makeAction("D / signal", stageD, 0.45)
  let actionE = makeAction("E / commit", stageE, 0.50)
  let sequence = cue(actionA)
    .thenStage([
      branch(actionB),
      cueAfter(0.15, actionC),
      cueAfter(0.30, actionD)
    ])
    .then(actionE)

  let launchSignal = initSignal[int]()
  let trigger = initCueTrigger(launchSignal, runtime, sequence, cspRestart)
  defer:
    discard trigger.dispose()

  var runNumber = 0
  var sequenceWasActive = false

  proc launch() =
    inc runNumber
    for visual in [stageA, stageB, stageC, stageD, stageE]:
      visual.setStatus(ssIdle)
    summary.setText(&"RUN {runNumber:02} / SIGNAL RECEIVED")
    launchSignal.emit(runNumber)
    sequenceWasActive = true
    scheduler.markDirty({ddStyle, ddLayout, ddPaint, ddHit})

  launchButton.onClick = proc(event: DispatchResult): EventOutcome =
    launch()
    stoppedEvent()

  var renderer = initSdl3Renderer(
    "Clay Board Style System - Cue Orchestration",
    viewportWidth,
    viewportHeight,
    resizable = true
  )
  defer:
    renderer.close()

  var viewport = renderer.windowSize()
  var frame: DemoFrame
  var interaction = initInteractionState()
  var running = true
  var queued = none(Sdl3Event)
  let capturePath = getEnv("CBSS_ORCHESTRATION_DEMO_CAPTURE")
  let captureOnly = getEnv("CBSS_ORCHESTRATION_DEMO_CAPTURE_ONLY") == "1"
  var capturePending = capturePath.len > 0
  var captureStartedAt = 0.0
  var autoLaunchPending = capturePending
  var lastTraceCount = -1

  proc dispatchFocused(event: InputEvent): bool =
    if interaction.focusedTarget.isNone:
      return false
    result = ui.events.handle(
      ui.tree,
      DispatchResult(
        target: interaction.focusedTarget,
        local: none(Vec2),
        event: event
      )
    )
    discard ui.reconcileFocus(interaction)

  proc handleEvent(event: Sdl3Event) =
    case event.kind
    of sekQuit:
      running = false
    of sekExpose:
      scheduler.markDirty(ddPaint)
    of sekResize:
      viewport = size(event.width.float32, event.height.float32)
      scheduler.markDirty({ddStyle, ddLayout, ddPaint, ddHit})
    of sekPointerMove:
      let point = vec2(event.x, event.y)
      renderer.setCursor(cursorAt(frame.regions, point))
      let previousHover = interaction.hoveredTarget
      let input = event.pointerInputEvent()
      if input.isSome:
        let dispatches = interaction.processInput(
          ui.tree, frame.regions, input.get, ui.scroll
        )
        discard ui.handleEvents(dispatches)
        if previousHover != interaction.hoveredTarget:
          scheduler.markDirty({ddStyle, ddPaint, ddHit})
    of sekPointerDown, sekPointerUp,
       sekTouchStart, sekTouchMove, sekTouchEnd, sekTouchCancel,
       sekPenProximityIn, sekPenProximityOut,
       sekPenButtonDown, sekPenButtonUp:
      let input = event.pointerInputEvent()
      if input.isSome:
        if event.kind == sekPointerDown:
          let point = vec2(event.buttonX, event.buttonY)
          let hit = hitTest(frame.regions, point)
          discard ui.normalizeFocus(
            interaction,
            if hit.isSome: some(hit.get.node) else: none(NodeId)
          )
        let dispatches = interaction.processInput(
          ui.tree, frame.regions, input.get, ui.scroll
        )
        discard ui.handleEvents(dispatches)
        discard ui.reconcileFocus(interaction)
        scheduler.markDirty({ddStyle, ddPaint, ddHit})
    of sekKeyDown:
      if event.key == "Tab" and not event.ctrl and not event.alt and not event.meta:
        discard ui.moveFocus(interaction, if event.shift: -1 else: 1)
      else:
        discard dispatchFocused(keyDownEvent(
          event.key,
          ctrlKey = event.ctrl,
          altKey = event.alt,
          shiftKey = event.shift,
          metaKey = event.meta
        ))
      scheduler.markDirty({ddStyle, ddPaint, ddHit})
    of sekKeyUp:
      discard dispatchFocused(keyUpEvent(
        event.key,
        ctrlKey = event.ctrl,
        altKey = event.alt,
        shiftKey = event.shift,
        metaKey = event.meta
      ))
    else:
      discard
    discard ui.reconcilePointerCapture(interaction)

  while running:
    var event: Sdl3Event
    if queued.isSome:
      handleEvent(queued.get)
      queued = none(Sdl3Event)
    while running and renderer.pollEvent(event):
      handleEvent(event)
    if not running:
      break

    let now = epochTime()
    runtime.tick(now)

    if capturePending and not autoLaunchPending and
        now - captureStartedAt >= 1.45:
      renderer.requestFrameCapture()
      scheduler.markDirty(ddPaint)

    let pendingCount = pending.len
    for index in 0 ..< pendingCount:
      let item = pending[index]
      if not item.settled and runtime.now >= item.dueAt:
        item.settled = true
        item.visual.setStatus(ssComplete)
        scheduler.markDirty({ddStyle, ddPaint, ddHit})
        item.completion.succeed()
    var activePending = newSeqOfCap[PendingAction](pending.len)
    for item in pending:
      if not item.settled:
        activePending.add item
    pending = move(activePending)

    if sequenceWasActive and runtime.activeCount == 0:
      sequenceWasActive = false
      summary.setText(&"RUN {runNumber:02} / ALL BRANCHES JOINED")
      scheduler.markDirty({ddLayout, ddPaint})

    when not defined(release) or defined(cbssFrontendTrace):
      if trace.len != lastTraceCount:
        lastTraceCount = trace.len
        let events = trace.snapshot()
        var lines: seq[string]
        let first = max(0, events.len - 22)
        for index in first ..< events.len:
          lines.add events[index].traceLine
        traceLabel.setText(lines.join("\n"))
        scheduler.markDirty({ddLayout, ddPaint})
    else:
      if lastTraceCount < 0:
        lastTraceCount = 0
        traceLabel.setText("Trace is disabled in ordinary release builds.")
        scheduler.markDirty({ddLayout, ddPaint})

    scheduler.markDirty(ui.consumeInvalidation().domains)
    let deadlineDue = scheduler.deadlineDue(now)
    if deadlineDue:
      scheduler.clearDeadline()
    var dirty = scheduler.consumeDirty()

    if ddStyle in dirty or ddLayout in dirty or frame.styles.styles.len == 0:
      ui.rebuildFrame(frame, viewport, scheduler, now)
      dirty = dirty + scheduler.consumeDirty() + {ddPaint, ddHit}
    elif deadlineDue:
      let transitionSamples = ui.applyStyleTransitions(
        frame.styles, scheduler, now
      )
      let animationSamples = ui.applyStyleAnimations(
        frame.styles, scheduler, now
      )
      dirty = dirty + scheduler.consumeDirty()
      if transitionSamples > 0 or animationSamples > 0:
        ui.refreshPaint(frame, ddHit in dirty)
        dirty.incl ddPaint
    elif ddPaint in dirty or ddHit in dirty:
      ui.refreshPaint(frame, ddHit in dirty)

    if dirty != {}:
      renderer.render(frame.commands, cosmic, fonts, demoBackground)
      if autoLaunchPending:
        autoLaunchPending = false
        captureStartedAt = now
        launch()
      if capturePending and renderer.capturedFrame().isSome:
        saveCapturedFrame(renderer.capturedFrame().get, capturePath)
        capturePending = false
        if captureOnly:
          running = false

    if not running:
      break

    let cueDeadline = runtime.nextDeadline()
    if cueDeadline.isSome:
      scheduler.requestDeadline(cueDeadline.get)
    for item in pending:
      scheduler.requestDeadline(item.dueAt)
    if capturePending and not autoLaunchPending:
      scheduler.requestDeadline(captureStartedAt + 1.45)

    let timeout = scheduler.waitTimeoutMs(epochTime())
    let received =
      if timeout < 0: renderer.waitEvent(event)
      else: renderer.waitEventTimeout(event, timeout)
    if received:
      queued = some(event)

when isMainModule:
  main()
