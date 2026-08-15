import std/[options, os, times]

import clay_board_style_system
import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/frontend_runtime
import clay_board_style_system/generated/default_properties

type DemoFrame = object
  styles: ResolvedTree
  layout: LayoutResult
  commands: seq[PaintCommand]

const
  viewportWidth = 1180
  viewportHeight = 720
  stageBackground = rgb(0.018, 0.022, 0.030)

proc textStyle(
    fontSize: float32;
    color: Color;
    weight = 400.0'f32;
    lineHeight = 0.0'f32;
    letterSpacing = 0.0'f32
): UiStyle =
  var declarations = @[
    decl("font-size", px(fontSize)),
    decl("line-height", px(
      if lineHeight > 0: lineHeight else: fontSize + 6
    )),
    decl("font-weight", number(weight)),
    decl("color", colorValue(color))
  ]
  if letterSpacing != 0:
    declarations.add decl("letter-spacing", px(letterSpacing))
  uiStyle(declarations)

proc transformStyle(
    x, y: float32;
    scaleValue = 1.0'f32;
    angle = 0.0'f32
): StyleValue =
  transformValue(
    translate(px(x), px(y)),
    scale(scaleValue, some(scaleValue)),
    rotate(angle)
  )

proc oneShotAnimation(
    name: string;
    duration: float32;
    timing = "ease-out"
): UiStyle =
  uiStyle([
    animationNames(name),
    animationDurations(duration),
    animationTimingFunctions(timing),
    animationFillMode(afBoth)
  ])

proc registerMotionGraphics(ui: UiRoot) =
  ui.registerStyleKeyframes(styleKeyframes("opening-mark", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(-42, 0, 0.82, -8))
    ]),
    styleKeyframe(0.22, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ]),
    styleKeyframe(0.72, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(34, 0, 0.94, 4))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("color-field", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(-720, 70, 0.72, -14))
    ]),
    styleKeyframe(0.18, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(-120, 18, 0.94, -7))
    ]),
    styleKeyframe(0.72, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(120, -12, 1.08, 3))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(570, -80, 1.22, 10))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("split-clay", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(-520, 0, 0.78, -9))
    ]),
    styleKeyframe(0.28, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ]),
    styleKeyframe(0.72, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(-80, -30, 1.06, -3))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("split-board", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(520, 0, 0.78, 9))
    ]),
    styleKeyframe(0.28, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ]),
    styleKeyframe(0.72, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(80, 30, 1.06, 3))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("kinetic-type", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(0, 96, 0.90, 0))
    ]),
    styleKeyframe(0.24, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ]),
    styleKeyframe(0.74, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(18, 0, 1.0, 0))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(86, -34, 1.06, 0))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("orbit-mark", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(0, 0, 0.18, -160))
    ]),
    styleKeyframe(0.30, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.08, 18))
    ]),
    styleKeyframe(0.70, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 0.94, -8))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(0, 0, 1.34, 42))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("accent-bars", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(-170, 0, 0.32, 0))
    ]),
    styleKeyframe(0.28, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ]),
    styleKeyframe(0.78, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(46, 0, 1.0, 0))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(240, 0, 0.42, 0))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("final-lockup", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(0, 52, 0.94, 0))
    ]),
    styleKeyframe(0.42, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("logo-mark", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(0, 0, 0.18, -135))
    ]),
    styleKeyframe(0.48, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.08, 8))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("underline-reveal", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(-440, 0, 0.10, 0))
    ]),
    styleKeyframe(0.58, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ])
  ]))

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
    raise newException(ValueError, "motion graphics style resolution failed")

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

proc refreshPaint(ui: UiRoot; frame: var DemoFrame) =
  ui.syncRenderSurfaces(frame.styles, frame.layout)
  frame.commands = buildPaintCommands(
    ui.tree, frame.styles, frame.layout, ui.scroll, ui.canvasPaintProvider()
  )

proc saveCapturedFrame(frame: Sdl3CapturedFrame; path: string) =
  var output = "P6\n" & $frame.width & " " & $frame.height & "\n255\n"
  let offset = output.len
  output.setLen(offset + frame.pixels.len)
  for index, value in frame.pixels:
    output[offset + index] = char(value)
  writeFile(path, output)

proc main() =
  var fonts = initFontRegistry()
  fonts.addFallbackFamily("Noto Sans")
  fonts.addFallbackFamily("Noto Sans CJK JP")
  var cosmic = initCosmicTextEngine(fonts)
  defer:
    cosmic.close()

  let ui = initUiRoot()
  ui.configureTextLayout(cosmic.textEngine(), fonts)
  ui.registerMotionGraphics()

  let root = ui.box(uiStyle([
    decl("width", px(viewportWidth)),
    decl("height", px(viewportHeight)),
    decl("position", keyword("relative")),
    decl("overflow", keyword("hidden")),
    decl("background-color", colorValue(stageBackground))
  ]), id = "cue-motion-graphics-demo")

  for index in 0 .. 7:
    discard ui.box(uiStyle([
      decl("position", keyword("absolute")),
      decl("left", px(70 + index.float32 * 148)),
      decl("top", px(0)),
      decl("width", px(1)),
      decl("height", px(viewportHeight)),
      decl("opacity", number(0.18)),
      decl("background-color", colorValue(rgb(0.20, 0.24, 0.31)))
    ]), parent = some(root))

  let field = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(210)),
    decl("top", px(112)),
    decl("width", px(770)),
    decl("height", px(470)),
    decl("opacity", number(0)),
    decl("background-color", colorValue(oklch(0.68, 0.19, 28).resolveColor())),
    decl("border-radius", px(18)),
    decl("transform", transformStyle(-720, 70, 0.72, -14))
  ]), parent = some(root), id = "motion-color-field")

  let orbit = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(805)),
    decl("top", px(205)),
    decl("width", px(246)),
    decl("height", px(246)),
    decl("opacity", number(0)),
    decl("background-color", colorValue(rgba(0, 0, 0, 0))),
    decl("border-width", px(20)),
    decl("border-color", colorValue(oklch(0.82, 0.17, 195).resolveColor())),
    decl("border-radius", px(123)),
    decl("transform", transformStyle(0, 0, 0.18, -160))
  ]), parent = some(root), id = "motion-orbit")

  let opening = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(76)),
    decl("top", px(260)),
    decl("width", px(1028)),
    decl("height", px(155)),
    decl("opacity", number(0)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("transform", transformStyle(-42, 0, 0.82, -8))
  ]), parent = some(root), id = "opening-mark")
  discard ui.text(
    opening, "BUILD THE INTERFACE",
    textStyle(66, rgb(0.96, 0.97, 0.99), 820, 76)
  )

  let splitClay = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(74)),
    decl("top", px(184)),
    decl("width", px(690)),
    decl("height", px(150)),
    decl("opacity", number(0)),
    decl("transform", transformStyle(-520, 0, 0.78, -9))
  ]), parent = some(root), id = "split-clay")
  discard ui.text(
    splitClay, "CLAY",
    textStyle(126, oklch(0.82, 0.17, 195).resolveColor(), 870, 136, 6.5)
  )

  let splitBoard = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(390)),
    decl("top", px(334)),
    decl("width", px(720)),
    decl("height", px(150)),
    decl("opacity", number(0)),
    decl("justify-content", keyword("flex-end")),
    decl("transform", transformStyle(520, 0, 0.78, 9))
  ]), parent = some(root), id = "split-board")
  discard ui.text(
    splitBoard, "BOARD",
    textStyle(126, oklch(0.72, 0.19, 30).resolveColor(), 870, 136, 6.5)
  )

  let kineticType = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(78)),
    decl("top", px(168)),
    decl("width", px(880)),
    decl("height", px(350)),
    decl("gap", px(0)),
    decl("opacity", number(0)),
    decl("flex-direction", keyword("column")),
    decl("transform", transformStyle(0, 96, 0.90, 0))
  ]), parent = some(root), id = "kinetic-type")
  discard ui.text(
    kineticType, "NATIVE",
    textStyle(96, rgb(0.985, 0.985, 0.97), 860, 102)
  )
  discard ui.text(
    kineticType, "UI / IN",
    textStyle(96, rgb(0.985, 0.985, 0.97), 860, 102)
  )
  discard ui.text(
    kineticType, "MOTION",
    textStyle(96, rgb(0.985, 0.985, 0.97), 860, 102)
  )

  let bars = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(80)),
    decl("top", px(555)),
    decl("width", px(710)),
    decl("height", px(66)),
    decl("gap", px(10)),
    decl("opacity", number(0)),
    decl("flex-direction", keyword("row")),
    decl("transform", transformStyle(-170, 0, 0.32, 0))
  ]), parent = some(root), id = "accent-bars")
  for item in [
    (180.0'f32, oklch(0.78, 0.16, 195).resolveColor()),
    (112.0'f32, oklch(0.85, 0.17, 112).resolveColor()),
    (254.0'f32, oklch(0.68, 0.19, 28).resolveColor())
  ]:
    discard ui.box(uiStyle([
      decl("width", px(item[0])),
      decl("height", px(12)),
      decl("background-color", colorValue(item[1])),
      decl("border-radius", px(2))
    ]), parent = some(bars))

  let logoMark = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(78)),
    decl("top", px(278)),
    decl("width", px(102)),
    decl("height", px(102)),
    decl("opacity", number(0)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(oklch(0.80, 0.15, 195).resolveColor())),
    decl("border-radius", px(8)),
    decl("transform", transformStyle(0, 0, 0.18, -135))
  ]), parent = some(root), id = "final-logo-mark")
  discard ui.box(uiStyle([
    decl("width", px(48)),
    decl("height", px(48)),
    decl("background-color", colorValue(stageBackground)),
    decl("border-radius", px(24))
  ]), parent = some(logoMark))

  let finalLockup = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(214)),
    decl("top", px(208)),
    decl("width", px(894)),
    decl("height", px(310)),
    decl("gap", px(14)),
    decl("opacity", number(0)),
    decl("flex-direction", keyword("column")),
    decl("justify-content", keyword("center")),
    decl("transform", transformStyle(0, 52, 0.94, 0))
  ]), parent = some(root), id = "final-lockup")
  discard ui.text(
    finalLockup, "CLAY BOARD",
    textStyle(88, rgb(0.97, 0.98, 0.99), 850, 96, 6.5)
  )
  discard ui.text(
    finalLockup, "STYLE SYSTEM",
    textStyle(
      88, oklch(0.80, 0.15, 195).resolveColor(), 850, 96, 6.5
    )
  )
  discard ui.text(
    finalLockup,
    "CSS-LIKE AUTHORING  /  NATIVE RUNTIME  /  SDL3",
    textStyle(13, rgb(0.69, 0.74, 0.81), 650, 19)
  )

  let underline = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(214)),
    decl("top", px(535)),
    decl("width", px(640)),
    decl("height", px(8)),
    decl("opacity", number(0)),
    decl("background-color", colorValue(oklch(0.72, 0.19, 30).resolveColor())),
    decl("border-radius", px(2)),
    decl("transform", transformStyle(-440, 0, 0.10, 0))
  ]), parent = some(root), id = "final-underline")

  let caption = ui.text(
    root,
    "CLAY BOARD STYLE SYSTEM  /  MOTION STUDY 05",
    textStyle(10, rgb(0.46, 0.53, 0.63), 650, 15),
    id = "motion-caption"
  )
  caption.applyStyle(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(76)),
    decl("top", px(42))
  ]))

  let runtime = initCueRuntime(epochTime())
  defer:
    discard runtime.dispose()
  when not defined(release) or defined(cbssFrontendTrace):
    let trace = runtime.enableTrace(128)

  proc animationAction(
      actionName: string;
      target: NodeHandle;
      animationName: string;
      duration: float32;
      timing: string
  ): CueAction =
    cueAnimation(
      actionName,
      target,
      animationName,
      proc() = target.applyStyle(oneShotAnimation(
        animationName, duration, timing
      ))
    )

  let graph = cue(animationAction(
    "opening", opening, "opening-mark", 1.80,
    "cubic-bezier(0.16, 1, 0.3, 1)"
  )).thenStage([
    branch(animationAction(
      "split-clay", splitClay, "split-clay", 1.90,
      "cubic-bezier(0.16, 1, 0.3, 1)"
    )),
    cueAfter(0.08, animationAction(
      "split-board", splitBoard, "split-board", 1.82,
      "cubic-bezier(0.16, 1, 0.3, 1)"
    ))
  ]).thenStage([
    branch(animationAction(
      "field", field, "color-field", 3.20,
      "cubic-bezier(0.22, 1, 0.36, 1)"
    )),
    cueAfter(0.10, animationAction(
      "type", kineticType, "kinetic-type", 3.00,
      "cubic-bezier(0.16, 1, 0.3, 1)"
    )),
    cueAfter(0.20, animationAction(
      "orbit", orbit, "orbit-mark", 2.80,
      "cubic-bezier(0.34, 1.56, 0.64, 1)"
    )),
    cueAfter(0.26, animationAction(
      "bars", bars, "accent-bars", 2.60, "ease-in-out"
    ))
  ]).thenStage([
    branch(animationAction(
      "lockup", finalLockup, "final-lockup", 2.00,
      "cubic-bezier(0.16, 1, 0.3, 1)"
    )),
    cueAfter(0.12, animationAction(
      "logo-mark", logoMark, "logo-mark", 1.72,
      "cubic-bezier(0.34, 1.56, 0.64, 1)"
    )),
    cueAfter(0.24, animationAction(
      "underline", underline, "underline-reveal", 1.56,
      "cubic-bezier(0.16, 1, 0.3, 1)"
    ))
  ])

  var renderer = initSdl3Renderer(
    "Clay Board Style System - Cue Motion Graphics",
    viewportWidth,
    viewportHeight,
    resizable = true
  )
  defer:
    renderer.close()

  var viewport = renderer.windowSize()
  var frame: DemoFrame
  var scheduler = initFrameScheduler({ddStyle, ddLayout, ddPaint})
  var running = true
  var queued = none(Sdl3Event)
  var started = false
  let capturePath = getEnv("CBSS_CUE_MOTION_CAPTURE")
  let captureOnly = getEnv("CBSS_CUE_MOTION_CAPTURE_ONLY") == "1"
  var capturePending = capturePath.len > 0
  var captureAt = 0.0

  proc handleEvent(event: Sdl3Event) =
    case event.kind
    of sekQuit:
      running = false
    of sekExpose:
      scheduler.markDirty(ddPaint)
    of sekResize:
      viewport = size(event.width.float32, event.height.float32)
      scheduler.markDirty({ddStyle, ddLayout, ddPaint})
    else:
      discard

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
    if capturePending and started and now >= captureAt:
      renderer.requestFrameCapture()
      scheduler.markDirty(ddPaint)

    scheduler.markDirty(ui.consumeInvalidation().domains)
    let deadlineDue = scheduler.deadlineDue(now)
    if deadlineDue:
      scheduler.clearDeadline()
    var dirty = scheduler.consumeDirty()

    if ddStyle in dirty or ddLayout in dirty or frame.styles.styles.len == 0:
      ui.rebuildFrame(frame, viewport, scheduler, now)
      dirty = dirty + scheduler.consumeDirty() + {ddPaint}
    elif deadlineDue:
      let transitionSamples = ui.applyStyleTransitions(
        frame.styles, scheduler, now
      )
      let animationSamples = ui.applyStyleAnimations(
        frame.styles, scheduler, now
      )
      # Motion lifecycle handlers may start the next Cue stage while samples
      # are being applied. Pull those new Style mutations into this frame.
      scheduler.markDirty(ui.consumeInvalidation().domains)
      dirty = dirty + scheduler.consumeDirty()
      if ddStyle in dirty or ddLayout in dirty:
        ui.rebuildFrame(frame, viewport, scheduler, now)
        dirty = dirty + scheduler.consumeDirty() + {ddPaint}
      elif transitionSamples > 0 or animationSamples > 0:
        ui.refreshPaint(frame)
        dirty.incl ddPaint
    elif ddPaint in dirty:
      ui.refreshPaint(frame)

    if dirty != {}:
      renderer.render(frame.commands, cosmic, fonts, stageBackground)
      if not started:
        started = true
        discard runtime.start(graph)
        captureAt = now + 2.75
        scheduler.markDirty({ddStyle, ddPaint})
      if capturePending and renderer.capturedFrame().isSome:
        when not defined(release) or defined(cbssFrontendTrace):
          if getEnv("CBSS_CUE_MOTION_TRACE") == "1":
            for item in trace.snapshot():
              echo item.sequence, " ", item.kind, " ", item.name
        saveCapturedFrame(renderer.capturedFrame().get, capturePath)
        capturePending = false
        if captureOnly:
          running = false

    if not running:
      break

    let cueDeadline = runtime.nextDeadline()
    if cueDeadline.isSome:
      scheduler.requestDeadline(cueDeadline.get)
    if capturePending and started:
      scheduler.requestDeadline(captureAt)

    let timeout = scheduler.waitTimeoutMs(epochTime())
    let received =
      if timeout < 0: renderer.waitEvent(event)
      else: renderer.waitEventTimeout(event, timeout)
    if received:
      queued = some(event)

when isMainModule:
  main()
