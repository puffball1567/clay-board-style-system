import std/[math, options, times]

import clay_board_style_system
import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/generated/default_properties

type
  DemoFrame = object
    styles: ResolvedTree
    layout: LayoutResult
    commands: seq[PaintCommand]
    regions: seq[HitRegion]

  DoorButtonState = ref object
    progress: float64
    animation: Option[AnimationId]
    hovered: bool
    keyboardFocused: bool
    lightColor: Color
    deepColor: Color

  DoorButton = object
    button: ButtonHandle
    overlay: CanvasHandle
    state: DoorButtonState

const
  viewportWidth = 760
  viewportHeight = 460
  transitionSeconds = 0.42

proc buildFrame(ui: UiRoot; viewport: Size): DemoFrame =
  var diagnostics: Diagnostics
  result.styles = resolveTreeStyles(
    ui.tree,
    ui.styleSheets(),
    defaultProperties(),
    diagnostics,
    viewportSize = some(viewport),
    fontMetricsResolver = ui.textEngine.fontMetricsResolver(ui.fonts)
  )
  if diagnostics.hasErrors:
    for item in diagnostics.items:
      echo item.property, ": ", item.message
    raise newException(ValueError, "door button style resolution failed")
  result.layout = computeLayout(
    ui.tree, result.styles, viewport, ui.textEngine, ui.fonts
  )
  ui.scroll.syncScrollState(ui.tree, result.styles, result.layout)
  ui.syncRenderSurfaces(result.styles, result.layout)
  result.commands = buildPaintCommands(
    ui.tree,
    result.styles,
    result.layout,
    ui.scroll,
    ui.canvasPaintProvider()
  )
  result.regions = buildHitRegions(
    ui.tree, result.layout, result.styles, ui.scroll
  )

proc refreshPaint(ui: UiRoot; frame: var DemoFrame) =
  ui.syncRenderSurfaces(frame.styles, frame.layout)
  frame.commands = buildPaintCommands(
    ui.tree,
    frame.styles,
    frame.layout,
    ui.scroll,
    ui.canvasPaintProvider()
  )
  frame.regions = buildHitRegions(
    ui.tree, frame.layout, frame.styles, ui.scroll
  )

proc drawDoors(canvas: Canvas2D; bounds: Rect; state: DoorButtonState) =
  canvas.clear()
  let progress = clamp(state.progress.float32, 0.0'f32, 1.0'f32)
  if progress <= 0.0001'f32:
    return

  let inset = 1.0'f32
  let width = max(0.0'f32, bounds.w - inset * 2)
  let height = max(0.0'f32, bounds.h - inset * 2)
  let revealedWidth = width * progress
  let left = inset + (width - revealedWidth) * 0.5'f32
  let panelBounds = rect(left, inset, revealedWidth, height)

  canvas.fillLinearGradient(
    panelBounds,
    LinearGradient(
      angle: 90,
      interpolationSpace: cisOklab,
      stops: @[
        colorStop(state.deepColor, 0),
        colorStop(state.lightColor, 48),
        colorStop(state.deepColor, 100)
      ]
    )
  )

  let leadingAlpha = sin(progress.float32 * PI.float32) * 0.30'f32
  if leadingAlpha > 0.001'f32:
    canvas.fillRect(
      rect(left, inset + 5, 1, max(0.0'f32, height - 10)),
      rgba(0.86, 0.98, 1.0, leadingAlpha)
    )
    canvas.fillRect(
      rect(left + revealedWidth - 1, inset + 5, 1, max(0.0'f32, height - 10)),
      rgba(0.86, 0.98, 1.0, leadingAlpha)
    )

proc applyProgress(button: DoorButton; value: float64) =
  button.state.progress = clamp(value, 0.0, 1.0)
  discard button.overlay.requestFrame()

proc animateTo(button: DoorButton; focused: bool; nowSeconds: float64) =
  if button.state.animation.isSome:
    discard button.button.root.cancelOwnedAnimation(button.state.animation.get)
    button.state.animation = none(AnimationId)

  let target = if focused: 1.0 else: 0.0
  let start = button.state.progress
  let distance = abs(target - start)
  if distance <= 0.000001:
    button.applyProgress(target)
    return

  let animation = button.button.root.startOwnedAnimation(
    button.button.container,
    animationSpec(
      durationSeconds = transitionSeconds * distance,
      timing = cubicBezierTiming(0.22, 1.0, 0.36, 1.0),
      dirtyDomains = {ddPaint},
      onSample = proc(sample: AnimationSample) =
        button.applyProgress(start + (target - start) * sample.progress),
      onEnd = proc(id: AnimationId) =
        button.applyProgress(target)
        if button.state.animation == some(id):
          button.state.animation = none(AnimationId)
    ),
    nowSeconds
  )
  button.state.animation = some(animation)

proc updateVisualTarget(button: DoorButton) =
  button.animateTo(
    button.state.hovered or button.state.keyboardFocused,
    epochTime()
  )

proc doorButton(
    ui: UiRoot;
    label: string;
    lightColor, deepColor: Color;
    id: string
): DoorButton =
  result.state = DoorButtonState(
    progress: 0,
    animation: none(AnimationId),
    hovered: false,
    keyboardFocused: false,
    lightColor: lightColor,
    deepColor: deepColor
  )
  result.button = ui.button(
    label,
    style = uiStyle([
      decl("width", ch(21)),
      decl("height", ex(4.8)),
      decl("min-width", ch(21)),
      decl("min-height", ex(4.8)),
      decl("max-width", ch(21)),
      decl("max-height", ex(4.8)),
      decl("position", keyword("relative")),
      decl("align-items", keyword("center")),
      decl("justify-content", keyword("center")),
      decl("overflow", keyword("hidden")),
      decl("background-color", colorValue(rgb(0.055, 0.07, 0.095))),
      decl("border-width", px(1)),
      decl("border-color", colorValue(rgba(0.50, 0.61, 0.74, 0.42))),
      decl("border-radius", ex(0.72)),
      decl("box-shadow", shadowValue(
        px(0), px(10), some(px(26)), some(px(-8)),
        some(rgba(0, 0, 0, 0.48))
      )),
      decl("cursor", keyword("pointer"))
    ]),
    textStyle = uiStyle([
      decl("position", keyword("relative")),
      decl("z-index", number(2)),
      decl("font-size", px(16)),
      decl("line-height", number(1.0)),
      decl("font-weight", number(680)),
      decl("letter-spacing", px(1.2)),
      decl("color", colorValue(rgb(0.95, 0.975, 1.0)))
    ]),
    id = id
  )

  let state = result.state
  let drawing = newCanvas2D()
  drawing.onFrame = proc(
      canvas: Canvas2D; frame: RenderSurfaceFrame
  ): RenderSurfaceFrameResult =
    canvas.drawDoors(frame.placement.localBounds(), state)
    rsfIdle

  result.overlay = ui.canvas(
    drawing,
    uiStyle([
      decl("position", keyword("absolute")),
      decl("left", px(0)),
      decl("top", px(0)),
      decl("width", percent(100)),
      decl("height", percent(100)),
      decl("z-index", number(1)),
      decl("pointer-events", keyword("none"))
    ]),
    parent = some(result.button.container),
    code = id & "-doors"
  )

  result.button.container.applyStateStyle({esFocus}, uiStyle([
    decl("border-color", colorValue(rgba(0.72, 0.91, 1.0, 0.92))),
    decl("box-shadow", shadowValue(
      px(0), px(12), some(px(30)), some(px(-7)),
      some(rgba(0.12, 0.56, 0.86, 0.38))
    ))
  ]), priority = 110)
  result.button.container.applyStateStyle({esFocusVisible}, uiStyle([
    decl("outline-style", keyword("solid")),
    decl("outline-width", px(2)),
    decl("outline-offset", ex(0.42)),
    decl("outline-color", colorValue(rgba(0.54, 0.86, 1.0, 0.90)))
  ]), priority = 120)
  result.button.container.applyActiveStyle(uiStyle([
    decl("scale", scale(0.985))
  ]), priority = 130)

  let button = result
  ui.events.addInternalEventHandler(
    button.button.container.id,
    iekPointerEnter,
    proc(event: DispatchResult): bool =
      button.state.hovered = true
      button.updateVisualTarget()
      false
  )
  ui.events.addInternalEventHandler(
    button.button.container.id,
    iekPointerLeave,
    proc(event: DispatchResult): bool =
      button.state.hovered = false
      button.updateVisualTarget()
      false
  )
  ui.events.addInternalEventHandler(
    button.button.container.id,
    iekPointerDown,
    proc(event: DispatchResult): bool =
      button.state.keyboardFocused = false
      button.updateVisualTarget()
      false
  )
  ui.events.addInternalEventHandler(
    button.button.container.id,
    iekFocus,
    proc(event: DispatchResult): bool =
      button.state.keyboardFocused =
        esFocusVisible in button.button.root.tree.nodes[
          button.button.container.id.nodeIndex
        ].states
      button.updateVisualTarget()
      false
  )
  ui.events.addInternalEventHandler(
    button.button.container.id,
    iekBlur,
    proc(event: DispatchResult): bool =
      button.state.keyboardFocused = false
      button.updateVisualTarget()
      false
  )

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
    decl("padding", ch(4)),
    decl("gap", ex(3.2)),
    decl("flex-direction", keyword("column")),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(rgb(0.018, 0.026, 0.041))),
    decl("color", colorValue(rgb(0.92, 0.95, 0.98))),
    decl("font-size", px(16))
  ]), id = "door-button-demo")

  discard ui.text(
    root,
    "THRESHOLD",
    style = uiStyle([
      decl("font-size", px(12)),
      decl("line-height", number(1.0)),
      decl("font-weight", number(720)),
      decl("letter-spacing", px(3.6)),
      decl("color", colorValue(rgba(0.57, 0.70, 0.83, 0.78)))
    ])
  )
  discard ui.text(
    root,
    "Choose an entry point",
    style = uiStyle([
      decl("font-size", px(30)),
      decl("line-height", number(1.1)),
      decl("font-weight", number(690)),
      decl("color", colorValue(rgb(0.96, 0.98, 1.0)))
    ])
  )

  let actions = ui.box(uiStyle([
    decl("gap", ch(2.25)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center"))
  ]), parent = some(root), id = "door-actions")
  ui.pushParent(actions)
  let studio = ui.doorButton(
    "ENTER STUDIO",
    oklch(0.77, 0.15, 205).resolveColor(),
    oklch(0.46, 0.14, 235).resolveColor(),
    "enter-studio"
  )
  let archive = ui.doorButton(
    "OPEN ARCHIVE",
    oklch(0.78, 0.16, 72).resolveColor(),
    oklch(0.50, 0.16, 42).resolveColor(),
    "open-archive"
  )
  ui.popParent()

  var renderer = initSdl3Renderer(
    "Clay Board Style System - Door Button",
    viewportWidth,
    viewportHeight,
    resizable = true
  )
  defer:
    renderer.close()

  var viewport = renderer.windowSize()
  var frame = ui.buildFrame(viewport)
  var interaction = initInteractionState()
  var scheduler = initFrameScheduler({ddPaint, ddHit})
  discard studio.overlay.requestFrame()
  discard archive.overlay.requestFrame()
  var running = true

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
      let dispatches = interaction.processInput(
        ui.tree, frame.regions, pointerMoveEvent(point), ui.scroll
      )
      discard ui.events.handle(ui.tree, dispatches)
      scheduler.markDirty({ddStyle, ddPaint, ddHit})
    of sekPointerDown:
      let point = vec2(event.buttonX, event.buttonY)
      let hit = hitTest(frame.regions, point)
      let target = if hit.isSome: some(hit.get.node) else: none(NodeId)
      discard ui.normalizeFocus(interaction, target)
      let dispatches = interaction.processInput(
        ui.tree,
        frame.regions,
        pointerDownEvent(point, event.button),
        ui.scroll
      )
      discard ui.events.handle(ui.tree, dispatches)
      scheduler.markDirty({ddStyle, ddPaint, ddHit})
    of sekPointerUp:
      let point = vec2(event.buttonX, event.buttonY)
      let dispatches = interaction.processInput(
        ui.tree,
        frame.regions,
        pointerUpEvent(point, event.button),
        ui.scroll
      )
      discard ui.events.handle(ui.tree, dispatches)
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

  var queued = none(Sdl3Event)
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
    discard ui.tickOwnedAnimations(scheduler, now)
    discard ui.runRenderSurfaceFrames(scheduler, now, 60)
    scheduler.markDirty(ui.consumeInvalidation().domains)
    let dirty = scheduler.consumeDirty()
    if ddStyle in dirty or ddLayout in dirty:
      frame = ui.buildFrame(viewport)
    elif ddPaint in dirty or ddHit in dirty:
      ui.refreshPaint(frame)
    if dirty != {}:
      renderer.render(
        frame.commands, cosmic, fonts, rgb(0.018, 0.026, 0.041)
      )

    let timeout = scheduler.waitTimeoutMs(epochTime())
    let received =
      if timeout < 0: renderer.waitEvent(event)
      else: renderer.waitEventTimeout(event, timeout)
    if received:
      queued = some(event)

when isMainModule:
  main()
