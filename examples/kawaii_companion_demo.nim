import std/options

import clay_board_style_system

import ./lifestyle_demo_support

const
  viewportWidth = 1200
  viewportHeight = 760
  plum = Color(r: 0.20, g: 0.13, b: 0.28, a: 1)
  muted = Color(r: 0.43, g: 0.39, b: 0.49, a: 1)
  shell = Color(r: 0.985, g: 0.975, b: 0.99, a: 1)
  white = Color(r: 1, g: 1, b: 1, a: 1)
  pink = Color(r: 0.97, g: 0.48, b: 0.61, a: 1)
  mint = Color(r: 0.48, g: 0.84, b: 0.72, a: 1)
  lavender = Color(r: 0.66, g: 0.57, b: 0.91, a: 1)
  sky = Color(r: 0.44, g: 0.74, b: 0.94, a: 1)
  butter = Color(r: 1.0, g: 0.84, b: 0.40, a: 1)

proc textStyle(
    size: float32;
    color = plum;
    weight = 500.0'f32;
    lineHeight = 0.0'f32
): UiStyle =
  let resolvedLineHeight =
    if lineHeight > 0: lineHeight else: size + 6
  uiStyle([
    fontSize(size),
    decl("line-height", px(resolvedLineHeight)),
    fontWeight(weight),
    decl("color", colorValue(color))
  ])

proc dotStyle(size: float32; color: Color): UiStyle =
  uiStyle([
    width(size), height(size),
    decl("background-color", colorValue(color)),
    borderRadius(size * 0.5'f32)
  ])

proc drawMascot(canvas: Canvas2D) =
  canvas.clear()
  canvas.fillLinearGradient(
    rect(0, 0, 380, 378),
    LinearGradient(
      angle: 142,
      interpolationSpace: cisOklab,
      stops: @[
        colorStop(rgba(0.93, 0.88, 1.0, 1), 0),
        colorStop(rgba(0.76, 0.94, 0.91, 1), 100)
      ]
    ),
    radius = 8
  )

  # Soft scene decorations make the retained 2D drawing read like a toy set.
  canvas.fillRect(rect(24, 38, 34, 34), rgba(1, 0.84, 0.40, 0.76), 17)
  canvas.fillRect(rect(312, 58, 22, 22), rgba(0.97, 0.48, 0.61, 0.66), 11)
  canvas.fillRect(rect(42, 260, 19, 19), rgba(0.44, 0.74, 0.94, 0.70), 9)
  canvas.fillRect(rect(322, 265, 30, 30), rgba(1, 1, 1, 0.58), 15)
  canvas.strokeLine(
    vec2(304, 34), vec2(330, 34), rgba(0.20, 0.13, 0.28, 0.24),
    width = 3, lineCap = slcRound
  )
  canvas.strokeLine(
    vec2(317, 21), vec2(317, 47), rgba(0.20, 0.13, 0.28, 0.24),
    width = 3, lineCap = slcRound
  )

  canvas.fillRect(rect(91, 329, 198, 22), rgba(0.26, 0.17, 0.34, 0.15), 11)

  # Shoes, legs, and the dress are layered back-to-front for soft depth.
  canvas.fillRect(rect(139, 296, 38, 33), rgba(0.72, 0.43, 0.35, 1), 17)
  canvas.fillRect(rect(207, 296, 38, 33), rgba(0.72, 0.43, 0.35, 1), 17)
  canvas.fillRect(rect(130, 315, 52, 21), plum, 10)
  canvas.fillRect(rect(202, 315, 52, 21), plum, 10)

  canvas.fillRect(rect(112, 204, 160, 116), rgba(0.63, 0.38, 0.84, 0.25), 54)
  canvas.fillRect(rect(108, 198, 160, 116), pink, 54)
  canvas.fillLinearGradient(
    rect(108, 198, 160, 116),
    LinearGradient(
      angle: 104,
      interpolationSpace: cisOklab,
      stops: @[
        colorStop(rgba(1.0, 0.63, 0.72, 1), 0),
        colorStop(rgba(0.90, 0.36, 0.55, 1), 100)
      ]
    ),
    radius = 54
  )
  canvas.fillRect(rect(128, 215, 120, 9), rgba(1, 1, 1, 0.42), 4)
  canvas.fillRect(rect(95, 217, 39, 74), rgba(0.75, 0.45, 0.35, 1), 19)
  canvas.fillRect(rect(250, 217, 39, 74), rgba(0.75, 0.45, 0.35, 1), 19)
  canvas.fillRect(rect(99, 211, 39, 74), rgba(1.0, 0.77, 0.65, 1), 19)
  canvas.fillRect(rect(246, 211, 39, 74), rgba(1.0, 0.77, 0.65, 1), 19)
  canvas.fillRect(rect(115, 265, 23, 23), rgba(1.0, 0.77, 0.65, 1), 11)
  canvas.fillRect(rect(246, 265, 23, 23), rgba(1.0, 0.77, 0.65, 1), 11)

  # Hair mass and buns sit behind the oversized face.
  let hairShadow = Color(r: 0.20, g: 0.10, b: 0.24, a: 1)
  let hair = Color(r: 0.30, g: 0.17, b: 0.34, a: 1)
  canvas.fillRect(rect(86, 55, 212, 196), hairShadow, 100)
  canvas.fillRect(rect(63, 65, 72, 72), hairShadow, 36)
  canvas.fillRect(rect(249, 65, 72, 72), hairShadow, 36)
  canvas.fillRect(rect(68, 58, 72, 72), hair, 36)
  canvas.fillRect(rect(244, 58, 72, 72), hair, 36)
  canvas.fillRect(rect(91, 48, 202, 194), hair, 96)
  canvas.fillRect(rect(97, 57, 186, 62), rgba(0.43, 0.24, 0.47, 1), 31)

  # Face and its inset highlight create a small pseudo-3D character without 3D assets.
  canvas.fillRect(rect(103, 77, 178, 160), rgba(0.72, 0.42, 0.34, 0.38), 82)
  canvas.fillRect(rect(99, 71, 178, 160), rgba(1.0, 0.77, 0.65, 1), 82)
  canvas.fillLinearGradient(
    rect(99, 71, 178, 160),
    LinearGradient(
      angle: 128,
      interpolationSpace: cisOklab,
      stops: @[
        colorStop(rgba(1.0, 0.86, 0.77, 1), 0),
        colorStop(rgba(1.0, 0.69, 0.59, 1), 100)
      ]
    ),
    radius = 82
  )
  canvas.fillRect(rect(119, 84, 81, 23), rgba(1, 1, 1, 0.26), 11)

  # Rounded fringe, eyes, blush, and mouth.
  canvas.fillRect(rect(98, 65, 78, 64), hair, 29)
  canvas.fillRect(rect(150, 58, 86, 68), hair, 31)
  canvas.fillRect(rect(217, 68, 64, 61), hair, 28)
  canvas.fillRect(rect(137, 145, 20, 30), plum, 10)
  canvas.fillRect(rect(219, 145, 20, 30), plum, 10)
  canvas.fillRect(rect(142, 149, 7, 10), white, 4)
  canvas.fillRect(rect(224, 149, 7, 10), white, 4)
  canvas.fillRect(rect(116, 181, 32, 14), rgba(0.96, 0.35, 0.50, 0.34), 7)
  canvas.fillRect(rect(229, 181, 32, 14), rgba(0.96, 0.35, 0.50, 0.34), 7)
  var smile = initPath2D()
  smile.moveTo(vec2(174, 185))
  smile.quadraticCurveTo(vec2(188, 198), vec2(202, 185))
  canvas.strokePath(
    smile, rgba(0.42, 0.18, 0.27, 0.82), width = 3,
    lineCap = slcRound, lineJoin = sljRound
  )

  # A simple bow and dress badge finish the character silhouette.
  canvas.fillRect(rect(79, 103, 39, 30), lavender, 14)
  canvas.fillRect(rect(112, 103, 39, 30), lavender, 14)
  canvas.fillRect(rect(109, 108, 17, 20), butter, 8)
  canvas.fillRect(rect(174, 239, 32, 32), butter, 16)
  canvas.fillRect(rect(182, 247, 16, 16), white, 8)

proc addTask(
    ui: UiRoot;
    parent: NodeHandle;
    timeText, title, detail: string;
    accent: Color;
    completed = false
) =
  let row = ui.box(uiStyle([
    width(652), height(54), gap(12), flexDirection(fdRow), alignItems(aiCenter)
  ]), parent = some(parent))
  discard ui.text(row, timeText, style = textStyle(11, muted, 650, 16))
  let check = ui.box(uiStyle([
    width(22), height(22), alignItems(aiCenter), justifyContent(jcCenter),
    decl("background-color", colorValue(if completed: accent else: white)),
    borderWidth(2), decl("border-color", colorValue(accent)), borderRadius(11)
  ]), parent = some(row))
  if completed:
    discard ui.text(check, "+", style = textStyle(13, white, 800, 15))
  let copy = ui.box(uiStyle([
    width(455), gap(1), flexDirection(fdColumn)
  ]), parent = some(row))
  discard ui.text(copy, title, style = textStyle(13, plum, 680, 18))
  discard ui.text(copy, detail, style = textStyle(10, muted, 460, 14))
  discard ui.box(dotStyle(9, accent), parent = some(row))

proc addSoftGoal(
    ui: UiRoot;
    parent: NodeHandle;
    symbol, title, note: string;
    accent, tint: Color
) =
  let card = ui.box(uiStyle([
    width(208), height(132), padding(15), gap(8), flexDirection(fdColumn),
    decl("background-color", colorValue(tint)), borderRadius(8)
  ]), parent = some(parent))
  let icon = ui.box(uiStyle([
    width(32), height(32), alignItems(aiCenter), justifyContent(jcCenter),
    decl("background-color", colorValue(accent)), borderRadius(7)
  ]), parent = some(card))
  discard ui.text(icon, symbol, style = textStyle(13, white, 800, 16))
  discard ui.text(card, title, style = textStyle(13, plum, 720, 18))
  discard ui.text(card, note, style = textStyle(10, muted, 470, 14))

proc buildDemo(ui: UiRoot) =
  let root = ui.box(uiStyle([
    width(viewportWidth), height(viewportHeight), padding(26), gap(18),
    flexDirection(fdColumn), alignItems(aiCenter),
    decl("background-color", colorValue(shell))
  ]), id = "kawaii-companion-demo")

  let header = ui.box(uiStyle([
    width(1148), height(58), flexDirection(fdRow), alignItems(aiCenter),
    justifyContent(jcSpaceBetween)
  ]), parent = some(root))
  let brand = ui.box(uiStyle([
    width(420), height(44), gap(10), flexDirection(fdRow), alignItems(aiCenter)
  ]), parent = some(header))
  let brandMark = ui.box(uiStyle([
    width(38), height(38), alignItems(aiCenter), justifyContent(jcCenter),
    decl("background-color", colorValue(pink)), borderRadius(8)
  ]), parent = some(brand))
  discard ui.text(brandMark, "+", style = textStyle(19, white, 820, 23))
  discard ui.text(brand, "MY LITTLE DAY", style = textStyle(18, plum, 800, 24))
  discard ui.text(brand, "DAILY COMPANION", style = textStyle(10, muted, 700, 14))

  let date = ui.box(uiStyle([
    width(270), height(40), gap(12), flexDirection(fdRow), alignItems(aiCenter),
    justifyContent(jcEnd)
  ]), parent = some(header))
  discard ui.text(date, "TUE, AUG 18", style = textStyle(11, muted, 680, 15))
  let avatar = ui.box(uiStyle([
    width(36), height(36), alignItems(aiCenter), justifyContent(jcCenter),
    decl("background-color", colorValue(mint)), borderRadius(18)
  ]), parent = some(date))
  discard ui.text(avatar, "A", style = textStyle(12, plum, 800, 16))

  let main = ui.box(uiStyle([
    width(1148), height(632), gap(20), flexDirection(fdRow)
  ]), parent = some(root))

  let companion = ui.box(uiStyle([
    width(426), height(632), padding(23), gap(11), flexDirection(fdColumn),
    decl("background-color", colorValue(white)), borderRadius(8),
    borderWidth(1),
    decl("border-color", colorValue(rgba(0.31, 0.20, 0.38, 0.08))),
    decl("box-shadow", shadowValue(
      px(0), px(16), some(px(34)), some(px(-18)),
      some(rgba(0.30, 0.18, 0.40, 0.24))
    ))
  ]), parent = some(main))
  let mascot = newCanvas2D()
  mascot.drawMascot()
  discard ui.canvas(
    mascot,
    uiStyle([width(380), height(378)]),
    parent = some(companion),
    code = "daily-companion-character"
  )
  discard ui.text(companion, "TODAY'S FRIEND", style = textStyle(10, pink, 780, 14))
  discard ui.text(
    companion, "きょうも、いい日。", style = textStyle(23, plum, 780, 30)
  )
  discard ui.text(
    companion,
    "You have room for focus and softness today. I saved a little space for both.",
    style = textStyle(12, muted, 480, 18)
  )
  let cheer = ui.box(uiStyle([
    width(380), height(48), padding(11), gap(9), flexDirection(fdRow),
    alignItems(aiCenter), decl("background-color", colorValue(rgba(0.48, 0.84, 0.72, 0.20))),
    borderRadius(7)
  ]), parent = some(companion))
  discard ui.box(dotStyle(10, mint), parent = some(cheer))
  discard ui.text(cheer, "3 gentle wins are waiting", style = textStyle(11, plum, 680, 15))

  let content = ui.box(uiStyle([
    width(702), height(632), gap(16), flexDirection(fdColumn)
  ]), parent = some(main))
  let welcome = ui.box(uiStyle([
    width(702), height(130), padding(21), gap(13), flexDirection(fdRow),
    alignItems(aiCenter), justifyContent(jcSpaceBetween),
    decl("background-color", colorValue(plum)), borderRadius(8)
  ]), parent = some(content))
  let welcomeCopy = ui.box(uiStyle([
    width(390), height(88), gap(5), flexDirection(fdColumn),
    justifyContent(jcCenter)
  ]), parent = some(welcome))
  discard ui.text(welcomeCopy, "GOOD MORNING", style = textStyle(10, mint, 760, 14))
  discard ui.text(welcomeCopy, "How do you want today to feel?", style = textStyle(22, white, 760, 28))
  discard ui.text(welcomeCopy, "Pick a mood, not a productivity score.", style = textStyle(11, rgba(0.91, 0.88, 0.94, 1), 470, 16))
  let moods = ui.box(uiStyle([
    width(230), height(54), gap(9), flexDirection(fdRow), alignItems(aiCenter),
    justifyContent(jcEnd)
  ]), parent = some(welcome))
  for index, item in [("CALM", mint), ("BRIGHT", butter), ("BOLD", pink)]:
    let mood = ui.box(uiStyle([
      width(if index == 1: 80 else: 62), height(34), alignItems(aiCenter),
      justifyContent(jcCenter), decl("background-color", colorValue(item[1])),
      borderRadius(7)
    ]), parent = some(moods))
    discard ui.text(mood, item[0], style = textStyle(9, plum, 760, 13))

  let today = ui.box(uiStyle([
    width(702), height(246), padding(20), gap(4), flexDirection(fdColumn),
    decl("background-color", colorValue(white)), borderRadius(8),
    borderWidth(1),
    decl("border-color", colorValue(rgba(0.31, 0.20, 0.38, 0.08)))
  ]), parent = some(content))
  let todayTitle = ui.box(uiStyle([
    width(662), height(34), flexDirection(fdRow), alignItems(aiCenter),
    justifyContent(jcSpaceBetween)
  ]), parent = some(today))
  discard ui.text(todayTitle, "Today's little plan", style = textStyle(16, plum, 760, 21))
  discard ui.text(todayTitle, "2 OF 4", style = textStyle(10, pink, 750, 14))
  ui.addTask(today, "09:30", "Studio check-in", "Bring the lavender notes", lavender, true)
  ui.addTask(today, "12:10", "Lunch outside", "Ten quiet minutes are enough", mint, true)
  ui.addTask(today, "15:00", "Sketch the new cover", "One rough idea, no polishing", pink)

  let goals = ui.box(uiStyle([
    width(702), height(224), gap(13), flexDirection(fdColumn)
  ]), parent = some(content))
  let goalsTitle = ui.box(uiStyle([
    width(702), height(32), flexDirection(fdRow), alignItems(aiCenter),
    justifyContent(jcSpaceBetween)
  ]), parent = some(goals))
  discard ui.text(goalsTitle, "Soft goals", style = textStyle(16, plum, 760, 21))
  discard ui.text(goalsTitle, "EDIT", style = textStyle(10, sky, 760, 14))
  let goalRow = ui.box(uiStyle([
    width(702), height(132), gap(13), flexDirection(fdRow)
  ]), parent = some(goals))
  ui.addSoftGoal(goalRow, "01", "Drink water", "4 of 6 cups", sky, rgba(0.44, 0.74, 0.94, 0.15))
  ui.addSoftGoal(goalRow, "02", "Make something", "12 min is enough", pink, rgba(0.97, 0.48, 0.61, 0.14))
  ui.addSoftGoal(goalRow, "03", "Close the day", "Write one good thing", lavender, rgba(0.66, 0.57, 0.91, 0.15))
  let progress = ui.box(uiStyle([
    width(702), height(38), padding(10), gap(9), flexDirection(fdRow),
    alignItems(aiCenter), decl("background-color", colorValue(rgba(1, 0.84, 0.40, 0.18))),
    borderRadius(7)
  ]), parent = some(goals))
  discard ui.text(progress, "THIS WEEK", style = textStyle(9, plum, 760, 13))
  let progressTrack = ui.box(uiStyle([
    width(442), height(8), decl("background-color", colorValue(rgba(0.20, 0.13, 0.28, 0.10))),
    borderRadius(4)
  ]), parent = some(progress))
  discard ui.box(uiStyle([
    width(148), height(8), decl("background-color", colorValue(pink)),
    borderRadius(4)
  ]), parent = some(progressTrack))
  discard ui.text(progress, "68%", style = textStyle(10, plum, 760, 14))

proc main() =
  var fonts = initFontRegistry()
  fonts.addFallbackFamily("Noto Sans")
  fonts.addFallbackFamily("Noto Sans CJK JP")
  var cosmic = initCosmicTextEngine(fonts)
  defer:
    cosmic.close()

  let ui = initUiRoot()
  ui.configureTextLayout(cosmic.textEngine(), fonts)
  ui.buildDemo()
  ui.runLifestyleDemo(
    cosmic,
    fonts,
    "Clay Board Style System - Kawaii Companion",
    viewportWidth,
    viewportHeight,
    shell
  )

when isMainModule:
  main()
