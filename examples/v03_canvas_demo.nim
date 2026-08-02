import std/[math, options, times]

import clay_board_style_system
import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/generated/default_properties

type DemoFrame = object
  styles: ResolvedTree
  layout: LayoutResult
  commands: seq[PaintCommand]
  regions: seq[HitRegion]

const
  viewportWidth = 1040
  viewportHeight = 680
  canvasWidth = 606.0'f32
  canvasHeight = 366.0'f32

proc textStyle(size: float32; color: Color; weight = 400.0'f32): UiStyle =
  uiStyle([
    decl("font-size", px(size)),
    decl("line-height", px(size + 7)),
    decl("font-weight", number(weight)),
    decl("color", colorValue(color))
  ])

proc buildFrame(ui: UiRoot; viewport: Size): DemoFrame =
  var diagnostics: Diagnostics
  result.styles = resolveTreeStyles(
    ui.tree, ui.styleSheets(), defaultProperties(), diagnostics
  )
  if diagnostics.hasErrors:
    for item in diagnostics.items:
      echo item.property, ": ", item.message
    raise newException(ValueError, "Version 0.3 demo style resolution failed")
  result.layout = computeLayout(
    ui.tree, result.styles, viewport, ui.textEngine, ui.fonts
  )
  ui.scroll.syncScrollState(ui.tree, result.styles, result.layout)
  ui.syncRenderSurfaces(result.styles, result.layout)
  result.commands = buildPaintCommands(
    ui.tree, result.styles, result.layout, ui.scroll,
    ui.canvasPaintProvider()
  )
  result.regions = buildHitRegions(
    ui.tree, result.layout, result.styles, ui.scroll
  )

proc refreshPaint(ui: UiRoot; frame: var DemoFrame) =
  ui.syncRenderSurfaces(frame.styles, frame.layout)
  frame.commands = buildPaintCommands(
    ui.tree, frame.styles, frame.layout, ui.scroll,
    ui.canvasPaintProvider()
  )
  frame.regions = buildHitRegions(
    ui.tree, frame.layout, frame.styles, ui.scroll
  )

proc drawSignal(canvas: Canvas2D; now: float64; pointer: Vec2) =
  canvas.clear()
  canvas.fillLinearGradient(
    rect(0, 0, canvasWidth, canvasHeight),
    LinearGradient(
      angle: 118,
      interpolationSpace: cisOklab,
      stops: @[
        colorStop(oklch(0.24, 0.055, 255).resolveColor(), 0),
        colorStop(oklch(0.18, 0.035, 285).resolveColor(), 100)
      ]
    ),
    radius = 10
  )

  let grid = rgba(0.72, 0.80, 0.90, 0.10)
  for column in 1 .. 9:
    canvas.fillRect(rect(column.float32 * 60, 24, 1, 304), grid)
  for row in 1 .. 5:
    canvas.fillRect(rect(24, row.float32 * 58, 558, 1), grid)

  let phase = now.float32 * 1.8'f32
  let barColors = [
    oklch(0.74, 0.17, 195).resolveColor(),
    oklch(0.76, 0.16, 235).resolveColor(),
    oklch(0.72, 0.19, 285).resolveColor(),
    oklch(0.76, 0.18, 335).resolveColor()
  ]
  for index in 0 .. 7:
    let wave = (sin(phase + index.float32 * 0.72'f32) + 1) * 0.5'f32
    let height = 74 + wave * 188
    let x = 42 + index.float32 * 67
    canvas.fillRect(
      rect(x, 316 - height, 38, height),
      barColors[index mod barColors.len],
      radius = 6
    )

  var signalPath = newSeqOfCap[Vec2](25)
  for index in 0 .. 24:
    let x = 24 + index.float32 * 23
    let y = 72 + sin(phase * 1.3'f32 + index.float32 * 0.46'f32) * 24
    signalPath.add vec2(x, y)
  canvas.strokePath(
    signalPath,
    oklch(0.86, 0.13, 175).resolveColor(),
    width = 3,
    lineCap = slcRound,
    lineJoin = sljRound
  )

  var curve = initPath2D()
  curve.moveTo(vec2(34, 122))
  curve.bezierCurveTo(
    vec2(158, 42), vec2(256, 192), vec2(360, 112)
  )
  curve.quadraticCurveTo(vec2(478, 38), vec2(570, 116))
  canvas.strokePath(
    curve,
    rgba(0.95, 0.72, 0.98, 0.72),
    width = 2,
    lineCap = slcRound,
    lineJoin = sljRound
  )

  let markerX = max(12.0'f32, min(canvasWidth - 28, pointer.x - 8))
  let markerY = max(12.0'f32, min(canvasHeight - 28, pointer.y - 8))
  canvas.fillRect(
    rect(markerX, markerY, 16, 16), rgba(1, 1, 1, 0.92), radius = 8
  )
  canvas.strokeRect(
    rect(1, 1, canvasWidth - 2, canvasHeight - 2),
    rgba(0.78, 0.84, 0.96, 0.22),
    width = 1,
    radius = 10
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
    decl("padding", px(32)),
    decl("gap", px(24)),
    decl("flex-direction", keyword("column")),
    decl("background-color", colorValue(rgb(0.025, 0.032, 0.048))),
    decl("color", colorValue(rgb(0.93, 0.95, 0.98)))
  ]), id = "v03-demo")

  discard ui.text(
    root,
    "Realtime signal",
    style = textStyle(30, rgb(0.96, 0.98, 1), 720)
  )

  let content = ui.box(uiStyle([
    decl("width", px(976)),
    decl("height", px(520)),
    decl("gap", px(24)),
    decl("flex-direction", keyword("row"))
  ]), parent = some(root))

  let drawing = newCanvas2D()
  var pointer = vec2(canvasWidth * 0.5, canvasHeight * 0.5)
  var animating = true
  var canvasHost: CanvasHandle
  drawing.onInput = proc(
      canvas: Canvas2D; event: RenderSurfaceInput
  ): bool =
    if event.localPosition.isSome:
      pointer = event.localPosition.get
    if event.event.kind == iekPointerDown:
      animating = not animating
    discard canvasHost.requestFrame()
    true
  drawing.onFrame = proc(
      canvas: Canvas2D; frame: RenderSurfaceFrame
  ): RenderSurfaceFrameResult =
    canvas.drawSignal(frame.nowSeconds, pointer)
    if animating: rsfRequestNext else: rsfIdle

  canvasHost = ui.canvas(
    drawing,
    uiStyle([
      decl("width", px(640)),
      decl("height", px(400)),
      decl("padding", px(16)),
      decl("border-width", px(1)),
      decl("border-color", colorValue(rgb(0.18, 0.23, 0.32))),
      decl("border-radius", px(12)),
      decl("background-color", colorValue(rgb(0.045, 0.058, 0.083))),
      decl("box-shadow", shadowValue(
        px(0), px(18), some(px(38)), some(px(-12)),
        some(rgba(0, 0, 0, 0.48))
      )),
      decl("cursor", keyword("pointer"))
    ]),
    parent = some(content),
    code = "realtime-signal"
  )

  let side = ui.box(uiStyle([
    decl("width", px(312)),
    decl("height", px(400)),
    decl("padding", px(18)),
    decl("gap", px(14)),
    decl("flex-direction", keyword("column")),
    decl("background-color", colorValue(rgb(0.055, 0.068, 0.095))),
    decl("border-width", px(1)),
    decl("border-color", colorValue(rgb(0.16, 0.20, 0.28))),
    decl("border-radius", px(8))
  ]), parent = some(content))
  discard ui.text(
    side, "Color channels",
    style = textStyle(17, rgb(0.92, 0.95, 0.99), 650)
  )
  for item in [
    ("Oklch / cyan", oklch(0.74, 0.17, 195).resolveColor()),
    ("Display P3", displayP3(0.78, 0.28, 0.91).resolveColor()),
    ("Oklab / rose", oklch(0.76, 0.18, 335).resolveColor())
  ]:
    let row = ui.box(uiStyle([
      decl("width", px(276)),
      decl("height", px(54)),
      decl("padding", px(9)),
      decl("gap", px(12)),
      decl("align-items", keyword("center")),
      decl("flex-direction", keyword("row")),
      decl("background-color", colorValue(rgb(0.075, 0.09, 0.12))),
      decl("border-radius", px(5))
    ]), parent = some(side))
    discard ui.box(uiStyle([
      decl("width", px(34)), decl("height", px(34)),
      decl("background-color", colorValue(item[1])),
      decl("border-radius", px(5))
    ]), parent = some(row))
    discard ui.text(
      row, item[0],
      style = textStyle(13, rgb(0.76, 0.81, 0.89), 520)
    )

  var renderer = initSdl3Renderer(
    "Clay Board Style System - Version 0.3 Canvas",
    viewportWidth,
    viewportHeight,
    resizable = true
  )
  defer:
    renderer.close()

  var viewport = renderer.windowSize()
  var frame = ui.buildFrame(viewport)
  var interaction = initInteractionState()
  var scheduler = initFrameScheduler({ddPaint})
  discard canvasHost.requestFrame()
  var running = true

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
      let dispatches = interaction.processInput(
        ui.tree, frame.regions,
        pointerDownEvent(point, event.button), ui.scroll
      )
      discard ui.events.handle(ui.tree, dispatches)
      scheduler.markDirty({ddStyle, ddPaint, ddHit})
    of sekPointerUp:
      let point = vec2(event.buttonX, event.buttonY)
      let dispatches = interaction.processInput(
        ui.tree, frame.regions,
        pointerUpEvent(point, event.button), ui.scroll
      )
      discard ui.events.handle(ui.tree, dispatches)
      scheduler.markDirty({ddStyle, ddPaint, ddHit})
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
    discard ui.runRenderSurfaceFrames(scheduler, now, 60)
    let dirty = scheduler.consumeDirty()
    if ddStyle in dirty or ddLayout in dirty:
      frame = ui.buildFrame(viewport)
    elif ddPaint in dirty or ddHit in dirty:
      ui.refreshPaint(frame)
    if dirty != {}:
      renderer.render(
        frame.commands, cosmic, fonts, rgb(0.025, 0.032, 0.048)
      )

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
