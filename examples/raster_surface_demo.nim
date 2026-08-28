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
  viewportWidth = 920
  viewportHeight = 680
  drawingWidth = 720
  drawingHeight = 460
  paper = [246'u8, 248'u8, 252'u8, 255'u8]
  ink = [42'u8, 55'u8, 82'u8, 255'u8]

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
    raise newException(ValueError, "RasterSurface demo style resolution failed")
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

proc paintSegment(
    surface: RasterSurface;
    first, last: Vec2;
    firstRadius, lastRadius: float32;
    color, background: array[4, uint8];
    coverageMask: var seq[uint8]
): tuple[region: RasterRegion, pixels: seq[uint8]] =
  let maxRadius = max(firstRadius, lastRadius)
  let left = max(0, floor(min(first.x, last.x) - maxRadius - 1).int)
  let top = max(0, floor(min(first.y, last.y) - maxRadius - 1).int)
  let right = min(
    surface.width, ceil(max(first.x, last.x) + maxRadius + 1).int
  )
  let bottom = min(
    surface.height, ceil(max(first.y, last.y) + maxRadius + 1).int
  )
  if right <= left or bottom <= top:
    return

  result.region = rasterRegion(left, top, right - left, bottom - top)
  result.pixels = newSeq[uint8](
    result.region.width * result.region.height * RasterBytesPerPixel
  )
  let committed = surface.pixels
  let rowBytes = result.region.width * RasterBytesPerPixel
  for row in 0 ..< result.region.height:
    let sourceOffset =
      ((result.region.y + row) * surface.width + result.region.x) *
        RasterBytesPerPixel
    let destinationOffset = row * rowBytes
    copyMem(
      addr result.pixels[destinationOffset],
      unsafeAddr committed[sourceOffset],
      rowBytes
    )

  let direction = vec2(last.x - first.x, last.y - first.y)
  let lengthSquared =
    direction.x * direction.x + direction.y * direction.y
  for row in 0 ..< result.region.height:
    for column in 0 ..< result.region.width:
      let point = vec2(
        result.region.x.float32 + column.float32 + 0.5'f32,
        result.region.y.float32 + row.float32 + 0.5'f32
      )
      let projection =
        if lengthSquared <= 0.0001'f32:
          0.0'f32
        else:
          max(0.0'f32, min(1.0'f32,
            ((point.x - first.x) * direction.x +
             (point.y - first.y) * direction.y) / lengthSquared
          ))
      let nearest = vec2(
        first.x + direction.x * projection,
        first.y + direction.y * projection
      )
      let dx = point.x - nearest.x
      let dy = point.y - nearest.y
      let radius = firstRadius + (lastRadius - firstRadius) * projection
      let coverage = max(
        0.0'f32, min(1.0'f32, radius + 0.75'f32 - sqrt(dx * dx + dy * dy))
      )
      if coverage <= 0:
        continue
      let offset = (row * result.region.width + column) * RasterBytesPerPixel
      let surfacePixel =
        (result.region.y + row) * surface.width + result.region.x + column
      let priorCoverage = coverageMask[surfacePixel]
      let mergedCoverage = max(priorCoverage, uint8(round(coverage * 255.0'f32)))
      if mergedCoverage == priorCoverage:
        continue
      coverageMask[surfacePixel] = mergedCoverage
      let sourceAlpha = color[3].float32 / 255.0'f32 *
        mergedCoverage.float32 / 255.0'f32
      for channel in 0 .. 2:
        let blended = color[channel].float32 * sourceAlpha +
          background[channel].float32 * (1.0'f32 - sourceAlpha)
        result.pixels[offset + channel] = uint8(round(blended))
      result.pixels[offset + 3] = 255

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
    decl("width", percent(100)),
    decl("height", percent(100)),
    decl("padding", px(34)),
    decl("gap", px(18)),
    decl("flex-direction", keyword("column")),
    decl("align-items", keyword("center")),
    decl("background-color", colorValue(rgb(0.055, 0.064, 0.083))),
    decl("color", colorValue(rgb(0.94, 0.96, 0.99)))
  ]), id = "raster-surface-demo")

  discard ui.text(root, "RasterSurface drawing", uiStyle([
    decl("font-size", px(28)),
    decl("line-height", px(35)),
    decl("font-weight", number(720)),
    decl("color", colorValue(rgb(0.96, 0.97, 1.0)))
  ]))
  discard ui.text(
    root,
    "Drag with a mouse or pen. Only the changed RGBA region is uploaded.",
    uiStyle([
      decl("font-size", px(14)),
      decl("line-height", px(21)),
      decl("color", colorValue(rgb(0.66, 0.71, 0.80)))
    ])
  )

  let surface = newRasterSurface(drawingWidth, drawingHeight, paper)
  var coverageMask = newSeq[uint8](drawingWidth * drawingHeight)
  var host {.cursor.} = ui.rasterSurface(surface, uiStyle([
    decl("width", px(drawingWidth)),
    decl("height", px(drawingHeight)),
    decl("border-width", px(1)),
    decl("border-color", colorValue(rgb(0.18, 0.21, 0.28))),
    decl("border-radius", px(8)),
    decl("overflow", keyword("hidden")),
    decl("box-shadow", shadowValue(
      px(0), px(22), some(px(48)), some(px(-18)),
      some(rgba(0, 0, 0, 0.58))
    )),
    decl("cursor", keyword("crosshair"))
  ]), parent = some(root), code = "drawing-surface")

  var drawing = false
  var previous = vec2(0, 0)
  var previousRadius = 0.0'f32
  host.canvas.canvas.onInput = proc(
      canvas: Canvas2D; event: RenderSurfaceInput
  ): bool =
    discard canvas
    if event.event.kind in {iekPointerUp, iekPointerCancel, iekTouchEnd,
        iekTouchCancel}:
      drawing = false
      return true
    if event.localPosition.isNone:
      return false
    let current = event.localPosition.get
    let pressure =
      if event.event.pointer.isSome and
          paPressure in event.event.pointer.get.axes:
        max(0.2'f32, event.event.pointer.get.pressure)
      else:
        0.58'f32
    let radius = 3.5'f32 + pressure * 7.0'f32
    if event.event.kind in {iekPointerDown, iekTouchStart}:
      drawing = true
      previous = current
      previousRadius = radius
    elif event.event.kind notin {iekPointerMove, iekTouchMove} or not drawing:
      return false
    let patch = surface.paintSegment(
      previous, current, previousRadius, radius, ink, paper, coverageMask
    )
    if patch.pixels.len > 0:
      discard host.updateRegion(patch.region, patch.pixels)
    previous = current
    previousRadius = radius
    true

  var renderer = initSdl3Renderer(
    "Clay Board Style System - RasterSurface",
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
      let input = event.pointerInputEvent()
      if input.isSome:
        discard ui.handleEvents(interaction.processInput(
          ui.tree, frame.regions, input.get, ui.scroll
        ))
    of sekPointerDown, sekPointerUp,
       sekTouchStart, sekTouchMove, sekTouchEnd, sekTouchCancel,
       sekPenProximityIn, sekPenProximityOut,
       sekPenButtonDown, sekPenButtonUp:
      let input = event.pointerInputEvent()
      if input.isSome:
        discard ui.handleEvents(interaction.processInput(
          ui.tree, frame.regions, input.get, ui.scroll
        ))
    else:
      discard
    discard ui.reconcilePointerCapture(interaction)

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

    scheduler.markDirty(ui.consumeInvalidation().domains)
    let dirty = scheduler.consumeDirty()
    if ddStyle in dirty or ddLayout in dirty:
      frame = ui.buildFrame(viewport)
    elif ddPaint in dirty or ddHit in dirty:
      ui.refreshPaint(frame)
    if dirty != {}:
      renderer.render(frame.commands, cosmic, fonts, rgb(0.055, 0.064, 0.083))

    let timeout = scheduler.waitTimeoutMs(epochTime())
    let received =
      if timeout < 0: renderer.waitEvent(event)
      else: renderer.waitEventTimeout(event, timeout)
    if received:
      queued = some(event)

when isMainModule:
  main()
