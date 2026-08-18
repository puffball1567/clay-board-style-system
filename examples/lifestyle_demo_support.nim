import std/[options, os, strutils]

import clay_board_style_system
import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/generated/default_properties

type LifestyleDemoFrame* = object
  styles*: ResolvedTree
  layout*: LayoutResult
  commands*: seq[PaintCommand]

type LifestyleViewportLayout* = proc(
  ui: UiRoot;
  viewport: Size
) {.closure.}

proc saveCapturedFrame(frame: Sdl3CapturedFrame; path: string) =
  var output = "P6\n" & $frame.width & " " & $frame.height & "\n255\n"
  let offset = output.len
  output.setLen(offset + frame.pixels.len)
  for index, value in frame.pixels:
    output[offset + index] = char(value)
  writeFile(path, output)

proc demoDimension(name: string; fallback: int): int =
  let authored = getEnv(name)
  if authored.len == 0:
    return fallback
  try:
    result = parseInt(authored)
  except ValueError:
    return fallback
  if result <= 0:
    result = fallback

proc buildLifestyleFrame*(ui: UiRoot; viewport: Size): LifestyleDemoFrame =
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
    raise newException(ValueError, "lifestyle demo style resolution failed")
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

proc runLifestyleDemo*(
    ui: UiRoot;
    cosmic: var CosmicTextEngine;
    fonts: FontRegistry;
    title: string;
    initialWidth, initialHeight: int;
    clearColor: Color;
    viewportLayout: LifestyleViewportLayout = nil
) =
  let windowWidth = demoDimension("CBSS_LIFESTYLE_DEMO_WIDTH", initialWidth)
  let windowHeight = demoDimension("CBSS_LIFESTYLE_DEMO_HEIGHT", initialHeight)
  var renderer = initSdl3Renderer(
    title, windowWidth, windowHeight, resizable = true
  )
  defer:
    renderer.close()

  var viewport = renderer.windowSize()
  if not viewportLayout.isNil:
    viewportLayout(ui, viewport)
  var frame = ui.buildLifestyleFrame(viewport)
  let capturePath = getEnv("CBSS_LIFESTYLE_DEMO_CAPTURE")
  let captureOnly = getEnv("CBSS_LIFESTYLE_DEMO_CAPTURE_ONLY") == "1"
  if capturePath.len > 0:
    renderer.requestFrameCapture()
  renderer.render(frame.commands, cosmic, fonts, clearColor)
  if capturePath.len > 0 and renderer.capturedFrame().isSome:
    saveCapturedFrame(renderer.capturedFrame().get, capturePath)
    if captureOnly:
      return

  var running = true
  while running:
    var event: Sdl3Event
    if not renderer.waitEvent(event):
      continue

    var needsRender = false
    var needsLayout = false
    case event.kind
    of sekQuit:
      running = false
    of sekResize:
      viewport = size(event.width.float32, event.height.float32)
      needsLayout = true
      needsRender = true
    of sekExpose:
      needsRender = true
    else:
      discard

    while running and renderer.pollEvent(event):
      case event.kind
      of sekQuit:
        running = false
      of sekResize:
        viewport = size(event.width.float32, event.height.float32)
        needsLayout = true
        needsRender = true
      of sekExpose:
        needsRender = true
      else:
        discard

    if running and needsLayout:
      if not viewportLayout.isNil:
        viewportLayout(ui, viewport)
      frame = ui.buildLifestyleFrame(viewport)
    if running and needsRender:
      renderer.render(frame.commands, cosmic, fonts, clearColor)
