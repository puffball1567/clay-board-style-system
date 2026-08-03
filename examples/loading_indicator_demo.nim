import std/[math, options, times]

import clay_board_style_system
import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/generated/default_properties

type DemoFrame = object
  styles: ResolvedTree
  layout: LayoutResult
  commands: seq[PaintCommand]

const
  viewportWidth = 480
  viewportHeight = 320
  indicatorSize = 72.0'f32
  tau = PI.float32 * 2.0'f32

proc buildFrame(ui: UiRoot; viewport: Size): DemoFrame =
  var diagnostics: Diagnostics
  result.styles = resolveTreeStyles(
    ui.tree, ui.styleSheets(), defaultProperties(), diagnostics
  )
  if diagnostics.hasErrors:
    for item in diagnostics.items:
      echo item.property, ": ", item.message
    raise newException(ValueError, "loading indicator style resolution failed")
  result.layout = computeLayout(
    ui.tree, result.styles, viewport, ui.textEngine, ui.fonts
  )
  ui.syncRenderSurfaces(result.styles, result.layout)
  result.commands = buildPaintCommands(
    ui.tree,
    result.styles,
    result.layout,
    ui.scroll,
    ui.canvasPaintProvider()
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

proc arcPath(
    center: Vec2;
    radius, startAngle, sweep: float32;
    segments: int
): Path2D =
  result = initPath2D()
  let count = max(1, segments)
  for index in 0 .. count:
    let angle = startAngle + sweep * index.float32 / count.float32
    let point = vec2(
      center.x + cos(angle) * radius,
      center.y + sin(angle) * radius
    )
    if index == 0:
      result.moveTo(point)
    else:
      result.lineTo(point)

proc drawIndicator(canvas: Canvas2D; nowSeconds: float64) =
  canvas.clear()
  let center = vec2(indicatorSize * 0.5'f32, indicatorSize * 0.5'f32)
  let radius = 25.0'f32
  let rotation = ((nowSeconds mod 0.92) / 0.92).float32 * tau

  canvas.strokePath(
    center.arcPath(radius, 0, tau, 64),
    rgba(0.64, 0.70, 0.80, 0.16),
    width = 5,
    lineCap = slcRound,
    lineJoin = sljRound
  )
  canvas.strokePath(
    center.arcPath(radius, rotation, tau * 0.72'f32, 48),
    oklch(0.76, 0.16, 190).resolveColor(),
    width = 5,
    lineCap = slcRound,
    lineJoin = sljRound
  )
  canvas.strokePath(
    center.arcPath(radius, rotation, tau * 0.11'f32, 10),
    rgba(0.88, 1.0, 0.98, 0.92),
    width = 2,
    lineCap = slcRound,
    lineJoin = sljRound
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
    decl("gap", px(16)),
    decl("flex-direction", keyword("column")),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(rgb(0.035, 0.045, 0.062)))
  ]), id = "loading-indicator-demo")

  let drawing = newCanvas2D()
  drawing.onFrame = proc(
      canvas: Canvas2D; frame: RenderSurfaceFrame
  ): RenderSurfaceFrameResult =
    canvas.drawIndicator(frame.nowSeconds)
    rsfRequestNext

  let indicator = ui.canvas(
    drawing,
    uiStyle([
      decl("width", px(indicatorSize)),
      decl("height", px(indicatorSize))
    ]),
    parent = some(root),
    code = "loading-indicator"
  )
  discard ui.text(
    root,
    "Loading",
    uiStyle([
      decl("font-size", px(15)),
      decl("line-height", px(21)),
      decl("font-weight", number(560)),
      decl("color", colorValue(rgb(0.88, 0.91, 0.95)))
    ])
  )

  var renderer = initSdl3Renderer(
    "Clay Board Style System - Loading Indicator",
    viewportWidth,
    viewportHeight,
    resizable = true
  )
  defer:
    renderer.close()

  var viewport = renderer.windowSize()
  var frame = ui.buildFrame(viewport)
  var scheduler = initFrameScheduler({ddPaint})
  discard indicator.requestFrame()
  var running = true
  var queued = none(Sdl3Event)

  while running:
    var event: Sdl3Event
    if queued.isSome:
      event = queued.get
      queued = none(Sdl3Event)
      case event.kind
      of sekQuit:
        running = false
      of sekResize:
        viewport = size(event.width.float32, event.height.float32)
        scheduler.markDirty({ddStyle, ddLayout, ddPaint})
      of sekExpose:
        scheduler.markDirty(ddPaint)
      else:
        discard
    while running and renderer.pollEvent(event):
      case event.kind
      of sekQuit:
        running = false
      of sekResize:
        viewport = size(event.width.float32, event.height.float32)
        scheduler.markDirty({ddStyle, ddLayout, ddPaint})
      of sekExpose:
        scheduler.markDirty(ddPaint)
      else:
        discard
    if not running:
      break

    let now = epochTime()
    discard ui.runRenderSurfaceFrames(scheduler, now, 60)
    let dirty = scheduler.consumeDirty()
    if ddStyle in dirty or ddLayout in dirty:
      frame = ui.buildFrame(viewport)
    elif ddPaint in dirty:
      ui.refreshPaint(frame)
    if dirty != {}:
      renderer.render(
        frame.commands,
        cosmic,
        fonts,
        rgb(0.035, 0.045, 0.062)
      )

    let timeout = scheduler.waitTimeoutMs(epochTime())
    let received =
      if timeout < 0: renderer.waitEvent(event)
      else: renderer.waitEventTimeout(event, timeout)
    if received:
      queued = some(event)

when isMainModule:
  main()
