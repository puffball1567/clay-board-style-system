import std/[options, os, times]

import clay_board_style_system
import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/generated/default_properties

type DemoFrame = object
  styles: ResolvedTree
  layout: LayoutResult
  commands: seq[PaintCommand]
  regions: seq[HitRegion]

const
  viewportWidth = 1180
  viewportHeight = 760
  canvasBackground = rgb(0.035, 0.039, 0.052)

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

proc inheritedTextStyle(
    fontSize: float32;
    weight = 400.0'f32;
    lineHeight = 0.0'f32
): UiStyle =
  uiStyle([
    decl("font-size", px(fontSize)),
    decl("line-height", px(
      if lineHeight > 0: lineHeight else: fontSize + 6
    )),
    decl("font-weight", number(weight))
  ])

proc infiniteAnimation(
    name: string;
    duration: float32;
    timing: string;
    direction = adNormal;
    delay = 0.0'f32
): UiStyle =
  uiStyle([
    animationNames(name),
    animationDurations(duration),
    animationDelays(delay),
    animationTimingFunctions(timing),
    decl("animation-iteration-count", keyword("infinite")),
    animationDirection(direction),
    animationFillMode(afBoth)
  ])

proc registerMotion(ui: UiRoot) =
  ui.registerStyleKeyframes(styleKeyframes("ease-shuttle", [
    styleKeyframe(0, [
      decl("transform", transformValue(
        translate(px(0), px(0)), scale(1, some(1.0'f32)), rotate(0)
      ))
    ]),
    styleKeyframe(0.12, [
      decl("transform", transformValue(
        translate(px(0), px(0)), scale(1, some(1.0'f32)), rotate(0)
      ))
    ]),
    styleKeyframe(0.88, [
      decl("transform", transformValue(
        translate(px(350), px(0)), scale(1, some(1.0'f32)), rotate(0)
      ))
    ]),
    styleKeyframe(1, [
      decl("transform", transformValue(
        translate(px(350), px(0)), scale(1, some(1.0'f32)), rotate(0)
      ))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("flip-travel", [
    styleKeyframe(0, [
      decl("transform", transformValue(
        translate(px(0), px(0)), scale(1, some(1.0'f32)), rotate(0)
      ))
    ]),
    styleKeyframe(0.50, [
      decl("transform", transformValue(
        translate(px(0), px(0)), scale(-1, some(1.0'f32)), rotate(0)
      ))
    ]),
    styleKeyframe(1, [
      decl("transform", transformValue(
        translate(px(0), px(0)), scale(1, some(1.0'f32)), rotate(0)
      ))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("palette-cycle", [
    styleKeyframe(0, [
      decl("background-color", colorValue(rgb(0.84, 0.18, 0.32))),
      decl("color", colorValue(rgb(1.0, 0.95, 0.82)))
    ]),
    styleKeyframe(0.34, [
      decl("background-color", colorValue(rgb(0.12, 0.62, 0.72))),
      decl("color", colorValue(rgb(0.96, 1.0, 0.86)))
    ]),
    styleKeyframe(0.67, [
      decl("background-color", colorValue(rgb(0.72, 0.82, 0.16))),
      decl("color", colorValue(rgb(0.08, 0.11, 0.08)))
    ]),
    styleKeyframe(1, [
      decl("background-color", colorValue(rgb(0.42, 0.24, 0.76))),
      decl("color", colorValue(rgb(1.0, 0.91, 0.98)))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("opacity-breathe", [
    styleKeyframe(0, [decl("opacity", number(0.42))]),
    styleKeyframe(0.5, [decl("opacity", number(1.0))]),
    styleKeyframe(1, [decl("opacity", number(0.42))])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("staggered-type", [
    styleKeyframe(0, [
      decl("transform", transformValue(
        translate(px(-14), px(0)), scale(1, some(1.0'f32)), rotate(0)
      )),
      decl("opacity", number(0.24))
    ]),
    styleKeyframe(0.5, [
      decl("transform", transformValue(
        translate(px(0), px(0)), scale(1, some(1.0'f32)), rotate(0)
      )),
      decl("opacity", number(1.0))
    ]),
    styleKeyframe(1, [
      decl("transform", transformValue(
        translate(px(14), px(0)), scale(1, some(1.0'f32)), rotate(0)
      )),
      decl("opacity", number(0.24))
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
    raise newException(ValueError, "declarative motion style resolution failed")

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
    ui.tree, frame.styles, frame.layout, ui.scroll,
    ui.canvasPaintProvider()
  )
  frame.regions = buildHitRegions(
    ui.tree, frame.layout, frame.styles, ui.scroll
  )

proc refreshPaint(ui: UiRoot; frame: var DemoFrame; refreshHit: bool) =
  ui.syncRenderSurfaces(frame.styles, frame.layout)
  frame.commands = buildPaintCommands(
    ui.tree, frame.styles, frame.layout, ui.scroll,
    ui.canvasPaintProvider()
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

proc main() =
  var fonts = initFontRegistry()
  fonts.addFallbackFamily("Noto Sans")
  fonts.addFallbackFamily("Noto Sans CJK JP")
  var cosmic = initCosmicTextEngine(fonts)
  defer:
    cosmic.close()

  let ui = initUiRoot()
  ui.configureTextLayout(cosmic.textEngine(), fonts)
  ui.registerMotion()

  let root = ui.box(uiStyle([
    decl("width", px(viewportWidth)),
    decl("height", px(viewportHeight)),
    decl("padding", px(32)),
    decl("gap", px(20)),
    decl("flex-direction", keyword("column")),
    decl("background-color", colorValue(canvasBackground)),
    decl("color", colorValue(rgb(0.94, 0.95, 0.92)))
  ]), id = "declarative-motion-demo")

  let header = ui.box(uiStyle([
    decl("width", px(1116)),
    decl("height", px(72)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("space-between")),
    decl("border-bottom-width", px(1)),
    decl("border-bottom-color", colorValue(rgb(0.18, 0.19, 0.22)))
  ]), parent = some(root))
  let titleBlock = ui.box(uiStyle([
    decl("gap", px(2)),
    decl("flex-direction", keyword("column"))
  ]), parent = some(header))
  discard ui.text(
    titleBlock, "KINETIC SYSTEMS / 04",
    textStyle(27, rgb(0.96, 0.96, 0.91), 760)
  )
  discard ui.text(
    titleBlock, "DECLARATIVE MOTION STUDY",
    textStyle(11, rgb(0.48, 0.82, 0.85), 620, 15)
  )
  discard ui.text(
    header, "KEYFRAMES  +  TRANSITIONS  /  LIVE",
    textStyle(11, rgb(0.72, 0.75, 0.70), 590, 15)
  )

  let main = ui.box(uiStyle([
    decl("width", px(1116)),
    decl("height", px(604)),
    decl("gap", px(20)),
    decl("flex-direction", keyword("row"))
  ]), parent = some(root))

  let motionColumn = ui.box(uiStyle([
    decl("width", px(720)),
    decl("height", px(604)),
    decl("padding", px(22)),
    decl("gap", px(12)),
    decl("flex-direction", keyword("column")),
    decl("background-color", colorValue(rgb(0.058, 0.064, 0.080))),
    decl("border-width", px(1)),
    decl("border-color", colorValue(rgb(0.16, 0.17, 0.20))),
    decl("border-radius", px(6))
  ]), parent = some(main))

  discard ui.text(
    motionColumn, "01  /  EASE IN-OUT",
    textStyle(11, rgb(0.67, 0.70, 0.66), 620, 16)
  )
  let easeTrack = ui.box(uiStyle([
    decl("width", px(676)),
    decl("height", px(122)),
    decl("padding", px(18)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("flex-start")),
    decl("background-color", colorValue(rgb(0.085, 0.091, 0.107))),
    decl("border-radius", px(4)),
    decl("overflow", keyword("hidden"))
  ]), parent = some(motionColumn), id = "ease-track")
  let shuttle = ui.box(
    uiStyle([
      decl("width", px(160)),
      decl("height", px(72)),
      decl("padding", px(16)),
      decl("justify-content", keyword("space-between")),
      decl("align-items", keyword("center")),
      decl("flex-direction", keyword("row")),
      decl("background-color", colorValue(rgb(0.86, 0.24, 0.32))),
      decl("border-radius", px(3)),
      decl("color", colorValue(rgb(1.0, 0.96, 0.88)))
    ]) + infiniteAnimation(
      "ease-shuttle", 2.6, "cubic-bezier(0.42, 0, 0.58, 1)", adAlternate
    ),
    parent = some(easeTrack),
    id = "ease-shuttle"
  )
  discard ui.text(shuttle, "EASE", inheritedTextStyle(16, 760, 20))
  discard ui.text(shuttle, "01", inheritedTextStyle(11, 640, 15))

  discard ui.text(
    motionColumn, "02  /  FLIP IN PLACE",
    textStyle(11, rgb(0.67, 0.70, 0.66), 620, 16)
  )
  let flipTrack = ui.box(uiStyle([
    decl("width", px(676)),
    decl("height", px(122)),
    decl("padding", px(18)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(rgb(0.085, 0.091, 0.107))),
    decl("border-radius", px(4)),
    decl("overflow", keyword("hidden"))
  ]), parent = some(motionColumn))
  let flipTile = ui.box(
    uiStyle([
      decl("width", px(160)),
      decl("height", px(72)),
      decl("padding", px(13)),
      decl("gap", px(10)),
      decl("align-items", keyword("center")),
      decl("flex-direction", keyword("row")),
      decl("background-color", colorValue(rgb(0.19, 0.74, 0.78))),
      decl("border-left-width", px(9)),
      decl("border-left-color", colorValue(rgb(0.93, 0.92, 0.30))),
      decl("border-radius", px(3)),
      decl("color", colorValue(rgb(0.04, 0.11, 0.12)))
    ]) + infiniteAnimation(
      "flip-travel", 3.4, "ease-in-out", adAlternate, -0.65
    ),
    parent = some(flipTrack),
    id = "flip-tile"
  )
  discard ui.text(flipTile, "FLIP", inheritedTextStyle(16, 820, 20))
  discard ui.text(flipTile, "/ 02", inheritedTextStyle(11, 650, 15))

  let colorPanel = ui.box(uiStyle([
    decl("width", px(676)),
    decl("height", px(170)),
    decl("padding", px(22)),
    decl("gap", px(6)),
    decl("justify-content", keyword("center")),
    decl("flex-direction", keyword("column")),
    decl("border-radius", px(4)),
    animationNames("palette-cycle", "opacity-breathe"),
    animationDurations(6.2'f32, 3.1'f32),
    animationDelays(0.0'f32, -0.9'f32),
    animationTimingFunctions("ease-in-out", "ease-in-out"),
    decl("animation-iteration-count", keyword("infinite, infinite")),
    animationDirections(adAlternate, adNormal),
    animationFillModes(afBoth, afBoth)
  ]), parent = some(motionColumn), id = "color-cycle")
  discard ui.text(
    colorPanel, "COLOR / TYPE / OPACITY",
    inheritedTextStyle(24, 780, 31)
  )
  discard ui.text(
    colorPanel, "Multiple named keyframes share one retained node.",
    inheritedTextStyle(12, 520, 18)
  )

  let interactionColumn = ui.box(uiStyle([
    decl("width", px(376)),
    decl("height", px(604)),
    decl("padding", px(20)),
    decl("gap", px(14)),
    decl("flex-direction", keyword("column")),
    decl("background-color", colorValue(rgb(0.94, 0.93, 0.88))),
    decl("border-radius", px(6)),
    decl("color", colorValue(rgb(0.08, 0.09, 0.10)))
  ]), parent = some(main))
  discard ui.text(
    interactionColumn, "03  /  HOVER TRANSITION",
    textStyle(11, rgb(0.24, 0.25, 0.23), 700, 16)
  )

  let hoverStage = ui.box(uiStyle([
    decl("width", px(336)),
    decl("height", px(260)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(rgb(0.87, 0.86, 0.81))),
    decl("border-radius", px(4)),
    decl("overflow", keyword("hidden"))
  ]), parent = some(interactionColumn))
  ui.pushParent(hoverStage)
  let hoverButton = ui.button(
    "HOVER / REVEAL",
    uiStyle([
      decl("width", px(246)),
      decl("height", px(142)),
      decl("align-items", keyword("center")),
      decl("justify-content", keyword("center")),
      decl("background-color", colorValue(rgb(0.08, 0.10, 0.12))),
      decl("border-width", px(1)),
      decl("border-color", colorValue(rgb(0.22, 0.24, 0.24))),
      decl("border-radius", px(5)),
      decl("cursor", keyword("pointer")),
      decl("opacity", number(0.86)),
      decl("transform", transformValue(
        translate(px(0), px(0)), scale(1, some(1.0'f32)), rotate(0)
      )),
      transitionProperties("background-color", "opacity", "transform"),
      transitionDurations(0.42'f32, 0.24'f32, 0.52'f32),
      transitionDelays(0.0'f32),
      transitionTimingFunctions(
        "ease-out", "ease-out", "cubic-bezier(0.16, 1, 0.3, 1)"
      )
    ]),
    textStyle = textStyle(14, rgb(0.95, 0.94, 0.86), 720, 20),
    id = "hover-transition"
  )
  ui.popParent()
  hoverButton.container.applyHoverStyle(uiStyle([
    decl("background-color", colorValue(rgb(0.88, 0.27, 0.31))),
    decl("opacity", number(1.0)),
    decl("transform", transformValue(
      translate(px(0), px(-7)), scale(1.06, some(1.06'f32)), rotate(-2)
    ))
  ]))

  discard ui.text(
    interactionColumn,
    "State changes are reconciled once. Active tracks update paint and hit data only.",
    textStyle(12, rgb(0.31, 0.32, 0.29), 500, 18)
  )

  discard ui.text(
    interactionColumn, "04  /  STAGGERED TYPE",
    textStyle(11, rgb(0.24, 0.25, 0.23), 700, 16)
  )
  let typeStage = ui.box(uiStyle([
    decl("width", px(336)),
    decl("height", px(142)),
    decl("padding", px(14)),
    decl("gap", px(1)),
    decl("justify-content", keyword("center")),
    decl("flex-direction", keyword("column")),
    decl("background-color", colorValue(rgb(0.12, 0.13, 0.14))),
    decl("border-radius", px(4)),
    decl("overflow", keyword("hidden"))
  ]), parent = some(interactionColumn))
  discard ui.text(
    typeStage, "NATIVE",
    textStyle(23, rgb(0.30, 0.84, 0.86), 790, 28) + infiniteAnimation(
      "staggered-type", 2.7, "ease-in-out", adNormal, 0.0
    )
  )
  discard ui.text(
    typeStage, "MOTION",
    textStyle(23, rgb(0.95, 0.34, 0.38), 790, 28) + infiniteAnimation(
      "staggered-type", 2.7, "ease-in-out", adNormal, -0.45
    )
  )
  discard ui.text(
    typeStage, "SYSTEM",
    textStyle(23, rgb(0.82, 0.82, 0.22), 790, 28) + infiniteAnimation(
      "staggered-type", 2.7, "ease-in-out", adNormal, -0.90
    )
  )
  discard ui.text(
    interactionColumn, "STYLE-DRIVEN  /  NO CANVAS ANIMATION",
    textStyle(11, rgb(0.19, 0.20, 0.18), 760, 16)
  )

  var renderer = initSdl3Renderer(
    "Clay Board Style System - Declarative Motion",
    viewportWidth,
    viewportHeight,
    resizable = true
  )
  defer:
    renderer.close()

  var viewport = renderer.windowSize()
  var frame: DemoFrame
  var interaction = initInteractionState()
  var scheduler = initFrameScheduler({ddStyle, ddLayout, ddPaint, ddHit})
  var running = true
  var queued = none(Sdl3Event)
  let capturePath = getEnv("CBSS_MOTION_DEMO_CAPTURE")
  let captureOnly = getEnv("CBSS_MOTION_DEMO_CAPTURE_ONLY") == "1"
  let captureStartedAt = epochTime()
  var capturePending = capturePath.len > 0

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
    of sekPointerDown, sekPointerUp, sekPointerCancel,
       sekTouchStart, sekTouchMove, sekTouchEnd, sekTouchCancel,
       sekPenProximityIn, sekPenProximityOut,
       sekPenButtonDown, sekPenButtonUp:
      let input = event.pointerInputEvent()
      if input.isSome:
        let dispatches = interaction.processInput(
          ui.tree, frame.regions, input.get, ui.scroll
        )
        discard ui.handleEvents(dispatches)
        scheduler.markDirty({ddStyle, ddPaint, ddHit})
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
      if capturePending and now - captureStartedAt >= 0.85:
        renderer.requestFrameCapture()
      renderer.render(frame.commands, cosmic, fonts, canvasBackground)
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
