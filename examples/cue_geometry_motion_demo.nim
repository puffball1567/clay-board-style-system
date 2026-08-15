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
  background = rgb(0.012, 0.016, 0.022)
  cyan = oklch(0.81, 0.16, 195).resolveColor()
  coral = oklch(0.70, 0.20, 28).resolveColor()
  acid = oklch(0.87, 0.18, 112).resolveColor()
  white = rgb(0.96, 0.97, 0.99)

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

proc transformXYStyle(
    x, y, scaleX, scaleY: float32;
    angle = 0.0'f32
): StyleValue =
  transformValue(
    translate(px(x), px(y)),
    scale(scaleX, some(scaleY)),
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

proc registerGeometryKeyframes(ui: UiRoot) =
  ui.registerStyleKeyframes(styleKeyframes("ball-bounce", [
    styleKeyframe(0, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(-440, -320, 1.0, 1.0, -18))
    ]),
    styleKeyframe(0.10, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(-362, -142, 1.0, 1.0, -7))
    ]),
    styleKeyframe(0.17, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(-307, -16, 0.96, 1.04, 1))
    ]),
    styleKeyframe(0.18, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(-300, 0, 1.28, 0.70, 3))
    ]),
    styleKeyframe(0.205, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(-280, -8, 0.91, 1.12, 7))
    ]),
    styleKeyframe(0.25, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(-245, -112, 0.98, 1.02, 12))
    ]),
    styleKeyframe(0.30, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(-206, -190, 1.0, 1.0, 17))
    ]),
    styleKeyframe(0.34, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(-175, -220, 1.0, 1.0, 21))
    ]),
    styleKeyframe(0.38, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(-144, -198, 1.0, 1.0, 25))
    ]),
    styleKeyframe(0.42, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(-113, -132, 1.0, 1.0, 29))
    ]),
    styleKeyframe(0.48, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(-66, -10, 0.96, 1.04, 35))
    ]),
    styleKeyframe(0.49, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(-58, 0, 1.22, 0.76, 36))
    ]),
    styleKeyframe(0.515, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(-38, -6, 0.93, 1.09, 39))
    ]),
    styleKeyframe(0.56, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(-3, -92, 0.99, 1.01, 43))
    ]),
    styleKeyframe(0.61, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(36, -142, 1.0, 1.0, 48))
    ]),
    styleKeyframe(0.64, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(59, -152, 1.0, 1.0, 51))
    ]),
    styleKeyframe(0.68, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(90, -132, 1.0, 1.0, 55))
    ]),
    styleKeyframe(0.73, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(129, -72, 1.0, 1.0, 60))
    ]),
    styleKeyframe(0.755, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(149, -8, 0.97, 1.03, 62))
    ]),
    styleKeyframe(0.765, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(157, 0, 1.16, 0.82, 63))
    ]),
    styleKeyframe(0.79, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(176, -4, 0.95, 1.06, 66))
    ]),
    styleKeyframe(0.83, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(207, -46, 1.0, 1.0, 70))
    ]),
    styleKeyframe(0.87, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(239, -63, 1.0, 1.0, 74))
    ]),
    styleKeyframe(0.90, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(262, -52, 1.0, 1.0, 77))
    ]),
    styleKeyframe(0.935, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(290, -12, 0.98, 1.02, 81))
    ]),
    styleKeyframe(0.95, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(301, 0, 1.10, 0.86, 83))
    ]),
    styleKeyframe(0.975, [
      decl("opacity", number(1)),
      decl("transform", transformXYStyle(320, 0, 1.0, 1.0, 86))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(0)),
      decl("transform", transformXYStyle(340, 0, 0.42, 0.42, 90))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("ball-shadow", [
    styleKeyframe(0, [
      decl("opacity", number(0.08)),
      decl("transform", transformXYStyle(-440, 0, 0.28, 1.0))
    ]),
    styleKeyframe(0.10, [
      decl("opacity", number(0.18)),
      decl("transform", transformXYStyle(-362, 0, 0.54, 1.0))
    ]),
    styleKeyframe(0.18, [
      decl("opacity", number(0.42)),
      decl("transform", transformXYStyle(-300, 0, 1.28, 1.0))
    ]),
    styleKeyframe(0.25, [
      decl("opacity", number(0.20)),
      decl("transform", transformXYStyle(-245, 0, 0.62, 1.0))
    ]),
    styleKeyframe(0.34, [
      decl("opacity", number(0.10)),
      decl("transform", transformXYStyle(-175, 0, 0.36, 1.0))
    ]),
    styleKeyframe(0.42, [
      decl("opacity", number(0.18)),
      decl("transform", transformXYStyle(-113, 0, 0.56, 1.0))
    ]),
    styleKeyframe(0.49, [
      decl("opacity", number(0.40)),
      decl("transform", transformXYStyle(-58, 0, 1.22, 1.0))
    ]),
    styleKeyframe(0.56, [
      decl("opacity", number(0.22)),
      decl("transform", transformXYStyle(-3, 0, 0.68, 1.0))
    ]),
    styleKeyframe(0.64, [
      decl("opacity", number(0.14)),
      decl("transform", transformXYStyle(59, 0, 0.46, 1.0))
    ]),
    styleKeyframe(0.73, [
      decl("opacity", number(0.24)),
      decl("transform", transformXYStyle(129, 0, 0.76, 1.0))
    ]),
    styleKeyframe(0.765, [
      decl("opacity", number(0.38)),
      decl("transform", transformXYStyle(157, 0, 1.16, 1.0))
    ]),
    styleKeyframe(0.83, [
      decl("opacity", number(0.26)),
      decl("transform", transformXYStyle(207, 0, 0.82, 1.0))
    ]),
    styleKeyframe(0.87, [
      decl("opacity", number(0.22)),
      decl("transform", transformXYStyle(239, 0, 0.70, 1.0))
    ]),
    styleKeyframe(0.935, [
      decl("opacity", number(0.30)),
      decl("transform", transformXYStyle(290, 0, 0.92, 1.0))
    ]),
    styleKeyframe(0.95, [
      decl("opacity", number(0.36)),
      decl("transform", transformXYStyle(301, 0, 1.08, 1.0))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(0)),
      decl("transform", transformXYStyle(340, 0, 0.32, 1.0))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("seed-pulse", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(0, 0, 0.08, -90))
    ]),
    styleKeyframe(0.30, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ]),
    styleKeyframe(0.72, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 0.92, 18))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(0, 0, 1.65, 44))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("ring-expand", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(0, 0, 0.12, -60))
    ]),
    styleKeyframe(0.36, [
      decl("opacity", number(0.92)),
      decl("transform", transformStyle(0, 0, 1.0, 8))
    ]),
    styleKeyframe(0.76, [
      decl("opacity", number(0.72)),
      decl("transform", transformStyle(0, 0, 1.10, 22))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(0, 0, 1.42, 48))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("axis-sweep", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(-210, 0, 0.10, 0))
    ]),
    styleKeyframe(0.32, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ]),
    styleKeyframe(0.76, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(210, 0, 0.18, 0))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("tile-rise", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(0, 116, 0.12, -28))
    ]),
    styleKeyframe(0.24, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.06, 3))
    ]),
    styleKeyframe(0.54, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ]),
    styleKeyframe(0.78, [
      decl("opacity", number(0.95)),
      decl("transform", transformStyle(0, -8, 0.92, -4))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(0, -126, 0.18, 24))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("poster-circle", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(-240, 90, 0.16, -80))
    ]),
    styleKeyframe(0.55, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.08, 6))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("poster-square", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(250, -100, 0.18, 110))
    ]),
    styleKeyframe(0.58, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.06, -5))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, 0))
    ])
  ]))

  ui.registerStyleKeyframes(styleKeyframes("poster-bar", [
    styleKeyframe(0, [
      decl("opacity", number(0)),
      decl("transform", transformStyle(-520, 0, 0.08, -12))
    ]),
    styleKeyframe(0.64, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.03, -6))
    ]),
    styleKeyframe(1, [
      decl("opacity", number(1)),
      decl("transform", transformStyle(0, 0, 1.0, -6))
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
    raise newException(ValueError, "geometry demo style resolution failed")

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
  var cosmic = initCosmicTextEngine(fonts)
  defer:
    cosmic.close()

  let ui = initUiRoot()
  ui.configureTextLayout(cosmic.textEngine(), fonts)
  ui.registerGeometryKeyframes()

  let root = ui.box(uiStyle([
    decl("width", px(viewportWidth)),
    decl("height", px(viewportHeight)),
    decl("position", keyword("relative")),
    decl("overflow", keyword("hidden")),
    decl("background-color", colorValue(background))
  ]), id = "cue-geometry-motion-demo")

  for index in 0 .. 9:
    discard ui.box(uiStyle([
      decl("position", keyword("absolute")),
      decl("left", px(52 + index.float32 * 120)),
      decl("top", px(0)),
      decl("width", px(1)),
      decl("height", px(viewportHeight)),
      decl("opacity", number(0.14)),
      decl("background-color", colorValue(rgb(0.20, 0.25, 0.32)))
    ]), parent = some(root))

  for index in 0 .. 5:
    discard ui.box(uiStyle([
      decl("position", keyword("absolute")),
      decl("left", px(0)),
      decl("top", px(58 + index.float32 * 120)),
      decl("width", px(viewportWidth)),
      decl("height", px(1)),
      decl("opacity", number(0.14)),
      decl("background-color", colorValue(rgb(0.20, 0.25, 0.32)))
    ]), parent = some(root))

  discard ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(74)),
    decl("top", px(590)),
    decl("width", px(1032)),
    decl("height", px(2)),
    decl("opacity", number(0.34)),
    decl("background-color", colorValue(rgb(0.42, 0.50, 0.60)))
  ]), parent = some(root), id = "geometry-bounce-ground")

  let ballShadow = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(545)),
    decl("top", px(585)),
    decl("width", px(90)),
    decl("height", px(14)),
    decl("opacity", number(0)),
    decl("background-color", colorValue(cyan)),
    decl("border-radius", px(7)),
    decl("transform", transformXYStyle(-440, 0, 0.28, 1.0))
  ]), parent = some(root), id = "geometry-ball-shadow")

  let ball = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(545)),
    decl("top", px(500)),
    decl("width", px(90)),
    decl("height", px(90)),
    decl("opacity", number(0)),
    decl("background-color", colorValue(acid)),
    decl("border-radius", px(45)),
    decl("transform", transformXYStyle(-440, -360, 1.0, 1.0, -18))
  ]), parent = some(root), id = "geometry-ball")

  let outerRing = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(390)),
    decl("top", px(160)),
    decl("width", px(400)),
    decl("height", px(400)),
    decl("opacity", number(0)),
    decl("border-width", px(7)),
    decl("border-color", colorValue(cyan)),
    decl("border-radius", px(200)),
    decl("transform", transformStyle(0, 0, 0.12, -60))
  ]), parent = some(root), id = "geometry-outer-ring")

  let innerRing = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(465)),
    decl("top", px(235)),
    decl("width", px(250)),
    decl("height", px(250)),
    decl("opacity", number(0)),
    decl("border-width", px(18)),
    decl("border-color", colorValue(coral)),
    decl("border-radius", px(125)),
    decl("transform", transformStyle(0, 0, 0.12, -60))
  ]), parent = some(root), id = "geometry-inner-ring")

  let seed = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(525)),
    decl("top", px(295)),
    decl("width", px(130)),
    decl("height", px(130)),
    decl("opacity", number(0)),
    decl("background-color", colorValue(acid)),
    decl("border-radius", px(65)),
    decl("transform", transformStyle(0, 0, 0.08, -90))
  ]), parent = some(root), id = "geometry-seed")

  let horizontalAxis = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(270)),
    decl("top", px(356)),
    decl("width", px(640)),
    decl("height", px(8)),
    decl("opacity", number(0)),
    decl("background-color", colorValue(white)),
    decl("border-radius", px(4)),
    decl("transform", transformStyle(-210, 0, 0.10, 0))
  ]), parent = some(root), id = "geometry-horizontal-axis")

  let verticalAxis = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(586)),
    decl("top", px(72)),
    decl("width", px(8)),
    decl("height", px(576)),
    decl("opacity", number(0)),
    decl("background-color", colorValue(white)),
    decl("border-radius", px(4)),
    decl("transform", transformStyle(0, -210, 0.10, 90))
  ]), parent = some(root), id = "geometry-vertical-axis")

  var tiles: seq[NodeHandle]
  let tileColors = [cyan, coral, acid, white]
  for row in 0 .. 2:
    for column in 0 .. 4:
      let index = row * 5 + column
      let radius =
        if index mod 5 == 0: 48.0'f32
        elif index mod 3 == 0: 22.0'f32
        else: 5.0'f32
      tiles.add ui.box(uiStyle([
        decl("position", keyword("absolute")),
        decl("left", px(250 + column.float32 * 138)),
        decl("top", px(176 + row.float32 * 122)),
        decl("width", px(112)),
        decl("height", px(94)),
        decl("opacity", number(0)),
        decl("background-color", colorValue(tileColors[index mod tileColors.len])),
        decl("border-radius", px(radius)),
        decl("transform", transformStyle(0, 116, 0.12, -28))
      ]), parent = some(root), id = "geometry-tile-" & $index)

  let posterCircle = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(150)),
    decl("top", px(132)),
    decl("width", px(330)),
    decl("height", px(330)),
    decl("opacity", number(0)),
    decl("background-color", colorValue(cyan)),
    decl("border-radius", px(165)),
    decl("transform", transformStyle(-240, 90, 0.16, -80))
  ]), parent = some(root), id = "geometry-poster-circle")

  let posterSquare = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(590)),
    decl("top", px(180)),
    decl("width", px(300)),
    decl("height", px(300)),
    decl("opacity", number(0)),
    decl("background-color", colorValue(coral)),
    decl("border-radius", px(18)),
    decl("transform", transformStyle(250, -100, 0.18, 110))
  ]), parent = some(root), id = "geometry-poster-square")

  discard ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(90)),
    decl("top", px(90)),
    decl("width", px(120)),
    decl("height", px(120)),
    decl("background-color", colorValue(background)),
    decl("border-radius", px(60))
  ]), parent = some(posterSquare))

  let posterBar = ui.box(uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(245)),
    decl("top", px(526)),
    decl("width", px(690)),
    decl("height", px(42)),
    decl("opacity", number(0)),
    decl("background-color", colorValue(acid)),
    decl("border-radius", px(5)),
    decl("transform", transformStyle(-520, 0, 0.08, -12))
  ]), parent = some(root), id = "geometry-poster-bar")

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

  var tileBranches: seq[CueBranch]
  for index, tile in tiles:
    tileBranches.add cueAfter(
      index.float64 * 0.045,
      animationAction(
        "tile-" & $index,
        tile,
        "tile-rise",
        2.35,
        "cubic-bezier(0.22, 1, 0.36, 1)"
      )
    )

  let bounceAction = cueAnimation(
    "bounce-ball",
    ball,
    "ball-bounce",
    proc() =
      ball.applyStyle(oneShotAnimation("ball-bounce", 3.0, "linear"))
      ballShadow.applyStyle(oneShotAnimation("ball-shadow", 3.0, "linear"))
  )

  let graph = cue(bounceAction).then(animationAction(
    "seed", seed, "seed-pulse", 1.90,
    "cubic-bezier(0.16, 1, 0.3, 1)"
  )).thenStage([
    cueAfter(0.08, animationAction(
      "inner-ring", innerRing, "ring-expand", 1.82,
      "cubic-bezier(0.22, 1, 0.36, 1)"
    )),
    cueAfter(0.16, animationAction(
      "outer-ring", outerRing, "ring-expand", 1.74,
      "cubic-bezier(0.22, 1, 0.36, 1)"
    )),
    cueAfter(0.20, animationAction(
      "horizontal-axis", horizontalAxis, "axis-sweep", 1.68,
      "cubic-bezier(0.16, 1, 0.3, 1)"
    )),
    cueAfter(0.26, animationAction(
      "vertical-axis", verticalAxis, "axis-sweep", 1.62,
      "cubic-bezier(0.16, 1, 0.3, 1)"
    ))
  ]).thenStage(tileBranches).thenStage([
    branch(animationAction(
      "poster-circle", posterCircle, "poster-circle", 2.10,
      "cubic-bezier(0.34, 1.56, 0.64, 1)"
    )),
    cueAfter(0.14, animationAction(
      "poster-square", posterSquare, "poster-square", 2.00,
      "cubic-bezier(0.34, 1.56, 0.64, 1)"
    )),
    cueAfter(0.24, animationAction(
      "poster-bar", posterBar, "poster-bar", 1.86,
      "cubic-bezier(0.16, 1, 0.3, 1)"
    ))
  ])

  let runtime = initCueRuntime(epochTime())
  defer:
    discard runtime.dispose()

  var renderer = initSdl3Renderer(
    "Clay Board Style System - Cue Geometry Motion",
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
  let capturePath = getEnv("CBSS_CUE_GEOMETRY_CAPTURE")
  let captureOnly = getEnv("CBSS_CUE_GEOMETRY_CAPTURE_ONLY") == "1"
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
      renderer.render(frame.commands, cosmic, fonts, background)
      if not started:
        started = true
        discard runtime.start(graph)
        captureAt = now + 1.55
        scheduler.markDirty({ddStyle, ddPaint})
      if capturePending and renderer.capturedFrame().isSome:
        saveCapturedFrame(renderer.capturedFrame().get, capturePath)
        capturePending = false
        if captureOnly:
          running = false

    if not running:
      break

    if capturePending and started:
      scheduler.requestDeadline(captureAt)
    let cueDeadline = runtime.nextDeadline()
    if cueDeadline.isSome:
      scheduler.requestDeadline(cueDeadline.get)

    let timeout = scheduler.waitTimeoutMs(epochTime())
    let received =
      if timeout < 0: renderer.waitEvent(event)
      else: renderer.waitEventTimeout(event, timeout)
    if received:
      queued = some(event)

when isMainModule:
  main()
