import std/options

import clay_board_style_system
import ./lifestyle_demo_support

const
  viewportWidth = 1200
  viewportHeight = 760
  ink = Color(r: 0.105, g: 0.105, b: 0.16, a: 1)
  muted = Color(r: 0.38, g: 0.39, b: 0.48, a: 1)
  paper = Color(r: 0.965, g: 0.962, b: 0.99, a: 1)
  white = Color(r: 1, g: 1, b: 1, a: 1)
  coral = Color(r: 0.98, g: 0.36, b: 0.38, a: 1)
  violet = Color(r: 0.44, g: 0.34, b: 0.92, a: 1)
  aqua = Color(r: 0.12, g: 0.72, b: 0.72, a: 1)
  yellow = Color(r: 1.0, g: 0.78, b: 0.20, a: 1)

proc textStyle(
    size: float32;
    color = ink;
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

proc surfaceStyle(
    widthValue, heightValue: float32;
    background: Color;
    radius = 8.0'f32
): UiStyle =
  uiStyle([
    width(widthValue),
    height(heightValue),
    decl("background-color", colorValue(background)),
    borderRadius(radius)
  ])

proc addMetric(
    ui: UiRoot;
    parent: NodeHandle;
    value, labelText, note: string;
    accent: Color
) =
  let card = ui.box(uiStyle([
    width(216),
    height(126),
    padding(18),
    gap(7),
    flexDirection(fdColumn),
    decl("background-color", colorValue(white)),
    borderWidth(1),
    decl("border-color", colorValue(rgba(0.12, 0.12, 0.18, 0.08))),
    borderRadius(8),
    decl("box-shadow", shadowValue(
      px(0), px(9), some(px(22)), some(px(-12)),
      some(rgba(0.16, 0.14, 0.28, 0.22))
    ))
  ]), parent = some(parent))
  discard ui.box(surfaceStyle(34, 5, accent, 2), parent = some(card))
  discard ui.text(card, value, style = textStyle(27, ink, 760, 32))
  discard ui.text(card, labelText, style = textStyle(13, ink, 650, 18))
  discard ui.text(card, note, style = textStyle(11, muted, 480, 16))

proc drawWeeklyPulse(canvas: Canvas2D) =
  canvas.clear()
  canvas.fillLinearGradient(
    rect(0, 0, 348, 222),
    LinearGradient(
      angle: 128,
      interpolationSpace: cisOklab,
      stops: @[
        colorStop(rgba(0.97, 0.98, 1.0, 1), 0),
        colorStop(rgba(0.92, 0.96, 1.0, 1), 100)
      ]
    ),
    radius = 8
  )

  let values = [0.44'f32, 0.68, 0.54, 0.82, 0.63, 0.91, 0.74]
  let colors = [coral, violet, aqua, yellow, violet, coral, aqua]
  for index, value in values:
    let x = 22 + index.float32 * 45
    canvas.fillRect(
      rect(x, 188 - value * 132, 25, value * 132),
      colors[index],
      radius = 12
    )
    canvas.fillRect(
      rect(x + 5, 193, 15, 4),
      rgba(0.20, 0.20, 0.28, 0.12),
      radius = 2
    )

  var curve = initPath2D()
  curve.moveTo(vec2(34, 91))
  curve.bezierCurveTo(vec2(86, 38), vec2(125, 126), vec2(174, 76))
  curve.bezierCurveTo(vec2(221, 29), vec2(266, 111), vec2(326, 48))
  canvas.strokePath(
    curve,
    rgba(0.12, 0.13, 0.22, 0.72),
    width = 3,
    lineCap = slcRound,
    lineJoin = sljRound
  )
  for point in [vec2(34, 91), vec2(174, 76), vec2(326, 48)]:
    canvas.fillRect(
      rect(point.x - 5, point.y - 5, 10, 10), white, radius = 5
    )
    canvas.strokeRect(
      rect(point.x - 5, point.y - 5, 10, 10), ink, width = 2, radius = 5
    )

proc addInsight(
    ui: UiRoot;
    parent: NodeHandle;
    number, title, detail: string;
    accent: Color
) =
  let row = ui.box(uiStyle([
    width(348),
    height(66),
    gap(13),
    flexDirection(fdRow),
    alignItems(aiCenter),
    borderBottomWidth(1),
    decl("border-bottom-color", colorValue(rgba(0.12, 0.12, 0.18, 0.08)))
  ]), parent = some(parent))
  let marker = ui.box(uiStyle([
    width(38),
    height(38),
    alignItems(aiCenter),
    justifyContent(jcCenter),
    decl("background-color", colorValue(accent)),
    borderRadius(7)
  ]), parent = some(row))
  discard ui.text(marker, number, style = textStyle(13, white, 760, 18))
  let copy = ui.box(uiStyle([
    width(292), gap(2), flexDirection(fdColumn)
  ]), parent = some(row))
  discard ui.text(copy, title, style = textStyle(13, ink, 680, 18))
  discard ui.text(copy, detail, style = textStyle(11, muted, 460, 16))

proc buildDemo(ui: UiRoot) =
  let root = ui.box(uiStyle([
    width(viewportWidth),
    height(viewportHeight),
    padding(28),
    gap(22),
    flexDirection(fdColumn),
    alignItems(aiCenter),
    decl("background-color", colorValue(paper))
  ]), id = "pop-infographic-demo")

  let header = ui.box(uiStyle([
    width(1144),
    height(58),
    flexDirection(fdRow),
    alignItems(aiCenter),
    justifyContent(jcSpaceBetween)
  ]), parent = some(root))
  let brand = ui.box(uiStyle([
    width(360), height(48), gap(11), flexDirection(fdRow), alignItems(aiCenter)
  ]), parent = some(header))
  let mark = ui.box(uiStyle([
    width(38), height(38), alignItems(aiCenter), justifyContent(jcCenter),
    decl("background-color", colorValue(violet)), borderRadius(7)
  ]), parent = some(brand))
  discard ui.text(mark, "W", style = textStyle(16, white, 800, 21))
  discard ui.text(brand, "WEEKLY PULSE", style = textStyle(17, ink, 800, 23))
  discard ui.text(brand, "/ WEEK 24", style = textStyle(11, muted, 650, 16))

  let headerActions = ui.box(uiStyle([
    width(296), height(42), gap(10), flexDirection(fdRow), alignItems(aiCenter),
    justifyContent(jcEnd)
  ]), parent = some(header))
  let live = ui.box(uiStyle([
    width(105), height(34), gap(7), flexDirection(fdRow), alignItems(aiCenter),
    justifyContent(jcCenter), decl("background-color", colorValue(white)),
    borderRadius(6)
  ]), parent = some(headerActions))
  discard ui.box(surfaceStyle(8, 8, aqua, 4), parent = some(live))
  discard ui.text(live, "LIVE DATA", style = textStyle(10, ink, 720, 14))
  let avatar = ui.box(uiStyle([
    width(38), height(38), alignItems(aiCenter), justifyContent(jcCenter),
    decl("background-color", colorValue(coral)), borderRadius(19)
  ]), parent = some(headerActions))
  discard ui.text(avatar, "AK", style = textStyle(11, white, 760, 15))

  let main = ui.box(uiStyle([
    width(1144), height(624), gap(22), flexDirection(fdRow)
  ]), parent = some(root))

  let primary = ui.box(uiStyle([
    width(752), height(624), gap(20), flexDirection(fdColumn)
  ]), parent = some(main))
  let intro = ui.box(uiStyle([
    width(752), height(194), padding(24), gap(20), flexDirection(fdRow),
    alignItems(aiCenter), decl("background-color", colorValue(ink)),
    borderRadius(8)
  ]), parent = some(primary))
  let introCopy = ui.box(uiStyle([
    width(478), height(146), gap(7), flexDirection(fdColumn),
    justifyContent(jcCenter)
  ]), parent = some(intro))
  discard ui.text(
    introCopy, "YOUR WEEK IN COLOR",
    style = textStyle(11, yellow, 760, 16)
  )
  discard ui.text(
    introCopy, "Small moves.\nBright momentum.",
    style = textStyle(31, white, 790, 36)
  )
  discard ui.text(
    introCopy, "Seven days of energy, focus and recovery at a glance.",
    style = textStyle(12, rgba(0.86, 0.87, 0.93, 1), 480, 18)
  )
  let score = ui.box(uiStyle([
    width(202), height(146), alignItems(aiCenter), justifyContent(jcCenter),
    flexDirection(fdColumn), decl("background-color", colorValue(yellow)),
    borderRadius(8)
  ]), parent = some(intro))
  discard ui.text(score, "82%", style = textStyle(39, ink, 820, 44))
  discard ui.text(score, "weekly rhythm", style = textStyle(11, ink, 650, 16))

  let metrics = ui.box(uiStyle([
    width(752), height(126), gap(18), flexDirection(fdRow)
  ]), parent = some(primary))
  ui.addMetric(metrics, "6.4k", "STEPS / DAY", "+12% from last week", coral)
  ui.addMetric(metrics, "7h 18", "DEEP REST", "best on Thursday", violet)
  ui.addMetric(metrics, "4 / 5", "FOCUS BLOCKS", "steady momentum", aqua)

  let story = ui.box(uiStyle([
    width(752), height(264), padding(22), gap(18), flexDirection(fdColumn),
    decl("background-color", colorValue(white)), borderRadius(8),
    borderWidth(1),
    decl("border-color", colorValue(rgba(0.12, 0.12, 0.18, 0.08)))
  ]), parent = some(primary))
  let storyHeading = ui.box(uiStyle([
    width(708), height(38), flexDirection(fdRow), alignItems(aiCenter),
    justifyContent(jcSpaceBetween)
  ]), parent = some(story))
  discard ui.text(storyHeading, "A week that found its pace", style = textStyle(17, ink, 740, 22))
  discard ui.text(storyHeading, "MAY 19 - 25", style = textStyle(10, muted, 680, 14))
  let ribbon = ui.box(uiStyle([
    width(708), height(66), gap(7), flexDirection(fdRow)
  ]), parent = some(story))
  let dayWidths = [72.0'f32, 88, 62, 108, 96, 130, 110]
  let dayColors = [coral, violet, yellow, aqua, violet, coral, aqua]
  for index, dayWidth in dayWidths:
    let segment = ui.box(uiStyle([
      width(dayWidth), height(66), padding(10), justifyContent(jcEnd),
      decl("background-color", colorValue(dayColors[index])), borderRadius(6)
    ]), parent = some(ribbon))
    discard ui.text(segment, $(index + 1), style = textStyle(11, if index == 2: ink else: white, 760, 15))
  discard ui.text(
    story,
    "Consistency rose after Wednesday. Friday carried the strongest mix of movement and recovery.",
    style = textStyle(12, muted, 480, 18)
  )

  let aside = ui.box(uiStyle([
    width(370), height(624), padding(11), gap(13), flexDirection(fdColumn),
    decl("background-color", colorValue(white)), borderRadius(8),
    borderWidth(1),
    decl("border-color", colorValue(rgba(0.12, 0.12, 0.18, 0.08)))
  ]), parent = some(main))
  let asideHeading = ui.box(uiStyle([
    width(348), height(40), flexDirection(fdRow), alignItems(aiCenter),
    justifyContent(jcSpaceBetween)
  ]), parent = some(aside))
  discard ui.text(asideHeading, "ENERGY MAP", style = textStyle(13, ink, 760, 18))
  discard ui.text(asideHeading, "7 DAYS", style = textStyle(10, violet, 700, 14))

  let chart = newCanvas2D()
  chart.drawWeeklyPulse()
  discard ui.canvas(
    chart,
    uiStyle([width(348), height(222)]),
    parent = some(aside),
    code = "weekly-pulse-chart"
  )
  ui.addInsight(aside, "01", "Your strongest window", "10:00 - 12:00, four days running", violet)
  ui.addInsight(aside, "02", "Recovery is working", "Rest quality climbed 8 points", aqua)
  ui.addInsight(aside, "03", "One gentle adjustment", "Move the late block 30 min earlier", coral)
  let footer = ui.box(uiStyle([
    width(348), height(46), padding(10), flexDirection(fdRow),
    alignItems(aiCenter), justifyContent(jcSpaceBetween),
    decl("background-color", colorValue(rgba(1, 0.78, 0.20, 0.22))),
    borderRadius(6)
  ]), parent = some(aside))
  discard ui.text(footer, "NEXT CHECK-IN", style = textStyle(10, ink, 720, 14))
  discard ui.text(footer, "SUNDAY 18:00", style = textStyle(11, ink, 760, 15))

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
    "Clay Board Style System - Pop Infographic",
    viewportWidth,
    viewportHeight,
    paper
  )

when isMainModule:
  main()
