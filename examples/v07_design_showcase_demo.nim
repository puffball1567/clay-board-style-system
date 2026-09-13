import std/[options, os, strutils, times]

import clay_board_style_system
import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/generated/default_properties

import ./showcase/v07_design_scenes

type DemoFrame = object
  styles: ResolvedTree
  layout: LayoutResult
  commands: seq[PaintCommand]

const
  viewportWidth = 1280
  viewportHeight = 760
  clearColor = rgb(0.98, 0.97, 0.95)

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
    raise newException(ValueError, "v0.7 design showcase style resolution failed")
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

proc saveCapturedFrame(frame: Sdl3CapturedFrame; path: string) =
  var output = "P6\n" & $frame.width & " " & $frame.height & "\n255\n"
  let offset = output.len
  output.setLen(offset + frame.pixels.len)
  for index, value in frame.pixels:
    output[offset + index] = char(value)
  writeFile(path, output)

proc parseInitialScene(): DesignScene =
  let authored = getEnv("CBSS_DESIGN_SCENE").toLowerAscii()
  case authored
  of "heart", "hearts", "heart-parade": dsHeartParade
  of "radio", "candy-radio": dsCandyRadio
  of "sticker", "studio", "sticker-studio": dsStickerStudio
  of "planet", "tiny-planet": dsTinyPlanet
  of "neon", "neon-dream": dsNeonDream
  else: dsHeartParade

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
    width(viewportWidth),
    height(viewportHeight),
    decl("overflow", keyword("hidden")),
    decl("background-color", colorValue(clearColor))
  ]), id = "v07-design-showcase")

  let drawing = newCanvas2D()
  var selected = parseInitialScene()
  var canvasHost: CanvasHandle
  drawing.onFrame = proc(
      canvas: Canvas2D; frame: RenderSurfaceFrame
  ): RenderSurfaceFrameResult =
    canvas.drawDesignScene(selected, frame.nowSeconds)
    if selected.sceneIsAnimated: rsfRequestNext else: rsfIdle

  canvasHost = ui.canvas(
    drawing,
    uiStyle([width(viewportWidth), height(viewportHeight)]),
    parent = some(root),
    code = "v07-design-stage"
  )

  var renderer = initSdl3Renderer(
    "Clay Board Style System - v0.7 Design Showcase",
    viewportWidth,
    viewportHeight,
    resizable = false
  )
  defer:
    renderer.close()

  var viewport = renderer.windowSize()
  var frame = ui.buildFrame(viewport)
  var scheduler = initFrameScheduler({ddPaint})
  discard canvasHost.requestFrame()
  var running = true
  var queued = none(Sdl3Event)
  var capturePending = getEnv("CBSS_DESIGN_SHOWCASE_CAPTURE").len > 0

  proc selectScene(next: DesignScene) =
    if next == selected:
      return
    selected = next
    discard canvasHost.requestFrame()
    scheduler.markDirty(ddPaint)

  proc handleEvent(event: Sdl3Event) =
    case event.kind
    of sekQuit:
      running = false
    of sekExpose:
      scheduler.markDirty(ddPaint)
    of sekResize:
      viewport = size(event.width.float32, event.height.float32)
      scheduler.markDirty({ddStyle, ddLayout, ddPaint})
    of sekPointerMove:
      let overNavigation = event.y >= 15 and event.y <= 51 and event.x >= 317
      renderer.setCursor(if overNavigation: ckPointer else: ckDefault)
    of sekPointerUp:
      let target = sceneAtNavigationPoint(vec2(event.buttonX, event.buttonY))
      if target.isSome:
        selectScene(target.get)
    of sekKeyDown:
      if event.repeat:
        return
      case event.key.toLowerAscii()
      of "arrowleft": selectScene(selected.nextScene(-1))
      of "arrowright": selectScene(selected.nextScene(1))
      of "1": selectScene(dsHeartParade)
      of "2": selectScene(dsCandyRadio)
      of "3": selectScene(dsStickerStudio)
      of "4": selectScene(dsTinyPlanet)
      of "5": selectScene(dsNeonDream)
      else: discard
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
    discard ui.runRenderSurfaceFrames(scheduler, now, 60)
    scheduler.markDirty(ui.consumeInvalidation().domains)
    let dirty = scheduler.consumeDirty()
    if ddStyle in dirty or ddLayout in dirty:
      frame = ui.buildFrame(viewport)
    elif ddPaint in dirty:
      ui.refreshPaint(frame)
    if dirty != {}:
      if capturePending:
        renderer.requestFrameCapture()
      renderer.render(frame.commands, cosmic, fonts, clearColor)
      if capturePending and renderer.capturedFrame().isSome:
        saveCapturedFrame(
          renderer.capturedFrame().get,
          getEnv("CBSS_DESIGN_SHOWCASE_CAPTURE")
        )
        capturePending = false
        if getEnv("CBSS_DESIGN_SHOWCASE_CAPTURE_ONLY") == "1":
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
