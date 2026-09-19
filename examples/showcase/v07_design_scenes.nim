import std/[math, options]

import clay_board_style_system

type
  DesignScene* = enum
    dsHeartParade,
    dsCandyRadio,
    dsStickerStudio,
    dsTinyPlanet,
    dsNeonDream

const
  designSceneCount* = DesignScene.high.ord + 1
  sceneLabels* = [
    "HEART PARADE",
    "CANDY RADIO",
    "STICKER STUDIO",
    "TINY PLANET",
    "NEON DREAM"
  ]
  tau = PI.float32 * 2.0'f32

proc wrap(value, period: float32): float32 =
  result = value mod period
  if result < 0:
    result += period

proc textStyle(
    size: float32;
    weight = 500.0'f32;
    lineHeight = 0.0'f32
): ComputedTextStyle =
  ComputedTextStyle(
    fontSize: some(size),
    fontWeight: some(weight),
    lineHeight: some(if lineHeight > 0: lineHeight else: size + 6)
  )

proc label(
    canvas: Canvas2D;
    value: string;
    x, y, size: float32;
    color: Color;
    weight = 500.0'f32;
    maxWidth = none(float32)
) =
  canvas.drawText(value, vec2(x, y), color, textStyle(size, weight), maxWidth)

proc gradient(
    first, second: Color;
    angle = 90.0'f32
): LinearGradient =
  LinearGradient(
    angle: angle,
    interpolationSpace: cisOklab,
    stops: @[colorStop(first, 0), colorStop(second, 100)]
  )

proc heartPath(center: Vec2; size: float32): Path2D =
  let x = center.x
  let y = center.y
  let s = size
  result = initPath2D()
  result.moveTo(vec2(x, y + s * 0.34'f32))
  result.bezierCurveTo(
    vec2(x - s * 0.62'f32, y - s * 0.05'f32),
    vec2(x - s * 0.50'f32, y - s * 0.66'f32),
    vec2(x, y - s * 0.28'f32)
  )
  result.bezierCurveTo(
    vec2(x + s * 0.50'f32, y - s * 0.66'f32),
    vec2(x + s * 0.62'f32, y - s * 0.05'f32),
    vec2(x, y + s * 0.34'f32)
  )
  result.closePath()

proc starPath(center: Vec2; outerRadius, innerRadius: float32): Path2D =
  result = initPath2D()
  for index in 0 ..< 10:
    let angle = -PI.float32 * 0.5'f32 + index.float32 * PI.float32 / 5'f32
    let radius = if index mod 2 == 0: outerRadius else: innerRadius
    let point = vec2(
      center.x + cos(angle) * radius,
      center.y + sin(angle) * radius
    )
    if index == 0: result.moveTo(point) else: result.lineTo(point)
  result.closePath()

proc pill(
    canvas: Canvas2D;
    bounds: Rect;
    background, foreground: Color;
    value: string
) =
  canvas.fillRect(bounds, background, bounds.h * 0.5'f32)
  canvas.label(
    value,
    bounds.x + 14,
    bounds.y + bounds.h * 0.27'f32,
    11,
    foreground,
    720
  )

proc drawNavigation(canvas: Canvas2D; selected: DesignScene) =
  canvas.fillRect(rect(0, 0, 1280, 66), rgba(1, 1, 1, 0.94))
  canvas.label("CBSS / DESIGN LAB", 34, 22, 13, rgb(0.12, 0.10, 0.18), 820)
  for scene in DesignScene:
    let index = scene.ord
    let x = 330.0'f32 + index.float32 * 178.0'f32
    if scene == selected:
      canvas.fillRect(rect(x - 13, 15, 160, 36), rgb(0.15, 0.12, 0.22), 7)
      canvas.label(sceneLabels[index], x, 27, 10, rgb(1, 1, 1), 760)
    else:
      canvas.label(sceneLabels[index], x, 27, 10, rgb(0.38, 0.35, 0.44), 660)

proc drawHeartParade(canvas: Canvas2D; time: float32) =
  let cream = rgb(1.0, 0.97, 0.91)
  let ink = rgb(0.19, 0.08, 0.18)
  let red = rgb(0.96, 0.19, 0.35)
  let pink = rgb(1.0, 0.48, 0.67)
  let aqua = rgb(0.20, 0.80, 0.78)
  let yellow = rgb(1.0, 0.79, 0.18)
  canvas.fillRect(rect(0, 66, 1280, 694), cream)

  canvas.fillRect(rect(34, 96, 500, 622), rgb(0.19, 0.08, 0.18), 8)
  canvas.label("LOVE", 70, 132, 76, rgb(1, 0.93, 0.95), 860)
  canvas.label("LOOKS GOOD", 70, 216, 46, rgb(1, 0.93, 0.95), 820)
  canvas.label("IN MOTION.", 70, 270, 46, pink, 820)
  canvas.label(
    "A looping collection of tiny reasons to smile.",
    72, 349, 17, rgba(1, 1, 1, 0.72), 520, some(330.0'f32)
  )
  canvas.pill(rect(72, 434, 160, 42), red, rgb(1, 1, 1), "OPEN THE PARADE")
  canvas.fillPath(heartPath(vec2(387, 503), 105), red)
  canvas.fillPath(heartPath(vec2(337, 553), 43), pink)
  canvas.fillPath(starPath(vec2(438, 612), 45, 19), yellow)

  canvas.fillRect(rect(558, 96, 688, 622), rgb(1, 0.56, 0.70), 8)
  canvas.fillRect(rect(590, 128, 624, 240), rgb(1, 0.91, 0.94), 8)
  canvas.label("HEART PARADE", 622, 158, 15, red, 820)
  canvas.label("Every beat", 622, 206, 42, ink, 820)
  canvas.label("finds its color.", 622, 254, 42, ink, 820)
  canvas.pill(rect(622, 313, 102, 34), yellow, ink, "VOL. 07")

  canvas.pushClip(rect(590, 396, 624, 160), 8)
  canvas.fillRect(rect(590, 396, 624, 160), rgb(0.98, 0.25, 0.42))
  let heartColors = [rgb(1, 0.88, 0.22), rgb(1, 0.87, 0.91), aqua, ink]
  for row in 0 .. 1:
    for index in 0 .. 10:
      let x = 570 + wrap(index.float32 * 78 - time * (95 + row * 42).float32, 858)
      let y = 438 + row.float32 * 73
      let size = 30.0'f32 + ((index + row) mod 3).float32 * 7
      canvas.fillPath(heartPath(vec2(x, y), size), heartColors[(index + row) mod 4])
  canvas.popClip()

  let cardColors = [rgb(0.18, 0.77, 0.75), rgb(1, 0.82, 0.16), rgb(0.18, 0.08, 0.22)]
  for index in 0 .. 2:
    let x = 590.0'f32 + index.float32 * 210
    canvas.fillRect(rect(x, 580, 194, 110), cardColors[index], 7)
    canvas.label(
      ["GOOD NEWS", "SUNNY SIDE", "NIGHT NOTE"][index],
      x + 16, 600, 11,
      if index == 2: rgb(1, 0.90, 0.94) else: ink,
      760
    )
    canvas.label(
      ["08 little wins", "Warm / bright", "Saved for later"][index],
      x + 16, 644, 15,
      if index == 2: rgb(1, 1, 1) else: ink,
      670
    )

proc drawCandyRadio(canvas: Canvas2D; time: float32) =
  let ink = rgb(0.11, 0.08, 0.20)
  let violet = rgb(0.48, 0.25, 0.93)
  let lime = rgb(0.76, 0.96, 0.24)
  let coral = rgb(1.0, 0.35, 0.42)
  let sky = rgb(0.31, 0.75, 0.98)
  canvas.fillRect(rect(0, 66, 1280, 694), rgb(0.95, 0.92, 1.0))
  canvas.fillLinearGradient(
    rect(34, 96, 1212, 278), gradient(violet, rgb(0.94, 0.29, 0.70), 18), 8)
  canvas.label("CANDY RADIO", 70, 126, 15, rgb(1, 1, 1), 820)
  canvas.label("Turn the day", 70, 180, 48, rgb(1, 1, 1), 830)
  canvas.label("all the way up.", 70, 234, 48, lime, 830)
  canvas.pill(rect(70, 311, 126, 36), lime, ink, "LIVE / 104.7")

  let center = vec2(1015, 235)
  for ring in countdown(4, 1):
    let radius = 28.0'f32 + ring.float32 * 31
    let pulse = sin(time * 3 + ring.float32) * 4
    var path = initPath2D()
    for pointIndex in 0 .. 80:
      let angle = pointIndex.float32 / 80 * tau
      let r = radius + pulse * sin(angle * (3 + ring).float32 + time * 2)
      let point = vec2(center.x + cos(angle) * r, center.y + sin(angle) * r)
      if pointIndex == 0: path.moveTo(point) else: path.lineTo(point)
    path.closePath()
    canvas.strokePath(path, rgba(1, 1, 1, 0.20 + ring.float32 * 0.12), 3,
        lineJoin = sljRound)
  canvas.fillRect(rect(973, 193, 84, 84), ink, 42)
  canvas.fillPath(starPath(center, 27, 12), lime)

  canvas.fillRect(rect(34, 398, 776, 320), rgb(1, 1, 1), 8)
  canvas.label("NOW PLAYING", 66, 426, 11, violet, 780)
  canvas.fillRect(rect(66, 466, 202, 202), coral, 7)
  canvas.fillPath(heartPath(vec2(167, 568), 95), rgb(1, 0.86, 0.20))
  canvas.label("STRAWBERRY STATIC", 300, 474, 28, ink, 800)
  canvas.label("Mika & the Satellites", 300, 517, 15, rgb(0.40, 0.35, 0.48), 560)
  canvas.fillRect(rect(300, 574, 430, 8), rgb(0.90, 0.87, 0.94), 4)
  canvas.fillRect(rect(300, 574, 266 + sin(time) * 20, 8), violet, 4)
  canvas.fillRect(rect(300, 616, 56, 56), ink, 28)
  canvas.label("II", 321, 631, 14, rgb(1, 1, 1), 800)
  canvas.pill(rect(374, 626, 104, 36), sky, ink, "SKIP +15")

  canvas.fillRect(rect(834, 398, 412, 320), ink, 8)
  canvas.label("COMING UP", 866, 426, 11, lime, 780)
  for index in 0 .. 2:
    let y = 470.0'f32 + index.float32 * 70
    canvas.fillRect(rect(866, y, 48, 48), [sky, coral, lime][index], 7)
    canvas.label(["Bubble Run", "Cherry Beam", "Soft Landing"][index], 932, y +
        2, 14, rgb(1, 1, 1), 680)
    canvas.label(["03:18", "02:44", "04:06"][index], 932, y + 28, 11, rgba(1, 1,
        1, 0.55), 520)

proc drawStickerStudio(canvas: Canvas2D; time: float32) =
  let paper = rgb(0.98, 0.97, 0.91)
  let ink = rgb(0.10, 0.13, 0.16)
  let blue = rgb(0.26, 0.47, 0.96)
  let orange = rgb(1.0, 0.45, 0.17)
  let green = rgb(0.32, 0.73, 0.45)
  canvas.fillRect(rect(0, 66, 1280, 694), paper)
  for row in 0 .. 19:
    for column in 0 .. 34:
      canvas.fillRect(rect(18 + column.float32 * 38, 83 + row.float32 * 38, 2,
          2), rgba(0.12, 0.16, 0.18, 0.11), 1)
  canvas.label("STICKER STUDIO", 40, 100, 14, ink, 840)
  canvas.label("MAKE IT", 40, 151, 42, ink, 880)
  canvas.label("MEMORABLE.", 40, 198, 42, blue, 880)

  canvas.save()
  canvas.translate(34, 278)
  canvas.rotate(-0.045 + sin(time * 0.9) * 0.006)
  canvas.fillRect(rect(0, 0, 355, 326), rgb(1, 0.86, 0.32), 5)
  canvas.label("TODAY", 28, 28, 13, ink, 800)
  canvas.label("Try the weird", 28, 78, 30, ink, 780)
  canvas.label("version first.", 28, 114, 30, ink, 780)
  for index in 0 .. 3:
    let y = 190.0'f32 + index.float32 * 30
    canvas.strokeRect(rect(30, y, 16, 16), ink, 2, 3)
    canvas.label(["name it", "shape it", "ship it", "save scraps"][index], 60,
        y - 1, 13, ink, 570)
  canvas.restore()

  canvas.fillRect(rect(428, 102, 818, 616), rgb(1, 1, 1), 7)
  canvas.label("PINBOARD / 07", 462, 132, 11, rgb(0.43, 0.43, 0.43), 760)
  canvas.strokeLine(vec2(462, 174), vec2(1208, 174), rgba(0.1, 0.13, 0.16,
      0.12), 2)
  let notes = [
    (rect(466, 210, 210, 146), rgb(0.95, 0.45, 0.58), "LOUD IDEA",
        "Color before copy"),
    (rect(702, 206, 254, 180), rgb(0.72, 0.92, 0.31), "GOOD QUESTION",
        "What should move?"),
    (rect(982, 214, 220, 140), rgb(0.35, 0.76, 0.98), "REFERENCE",
        "Edges / rhythm / air"),
    (rect(500, 410, 280, 224), rgb(0.64, 0.48, 0.96), "NEXT PASS",
        "Make it unmistakable"),
    (rect(824, 430, 336, 182), rgb(1.0, 0.62, 0.22), "KEEP", "The small happy accident")
  ]
  for index, note in notes:
    canvas.save()
    canvas.translate(note[0].x, note[0].y)
    canvas.rotate(([0.035, -0.024, 0.018, -0.035, 0.026][index]) + sin(time +
        index.float32) * 0.003)
    canvas.fillRect(rect(0, 0, note[0].w, note[0].h), note[1], 5)
    canvas.label(note[2], 22, 22, 11, ink, 820)
    canvas.label(note[3], 22, 63, 18, ink, 690, some(note[0].w - 40))
    canvas.restore()
  canvas.fillPath(starPath(vec2(1134, 622), 42, 18), blue)
  canvas.fillPath(heartPath(vec2(440, 655), 36), orange)
  canvas.fillRect(rect(943, 371, 112, 26), green, 3)

proc drawTinyPlanet(canvas: Canvas2D; time: float32) =
  let night = rgb(0.055, 0.075, 0.13)
  let white = rgb(0.96, 1.0, 0.98)
  let mint = rgb(0.43, 0.92, 0.67)
  let sky = rgb(0.43, 0.78, 1.0)
  let peach = rgb(1.0, 0.64, 0.47)
  canvas.fillRect(rect(0, 66, 1280, 694), rgb(0.88, 0.97, 0.94))
  canvas.fillRect(rect(34, 96, 1212, 622), night, 8)
  canvas.label("TINY PLANET CONTROL", 70, 130, 13, mint, 820)
  canvas.label("Everything is", 70, 182, 39, white, 780)
  canvas.label("growing nicely.", 70, 226, 39, white, 780)
  canvas.pill(rect(70, 292, 120, 36), mint, night, "ALL SYSTEMS")

  let planet = vec2(712, 367)
  canvas.fillRect(rect(500, 155, 424, 424), rgba(0.45, 0.85, 0.74, 0.08), 212)
  canvas.fillRect(rect(538, 193, 348, 348), rgba(0.45, 0.85, 0.74, 0.10), 174)
  canvas.fillLinearGradient(rect(574, 229, 276, 276), gradient(sky, mint, 140), 138)
  for index in 0 .. 6:
    let angle = time * (0.22 + index.float32 * 0.018) + index.float32 * 0.91
    let radius = 172.0'f32 + (index mod 2).float32 * 20
    let p = vec2(planet.x + cos(angle) * radius, planet.y + sin(angle) * radius)
    canvas.fillRect(rect(p.x - 8, p.y - 8, 16, 16), [mint, peach, sky][
        index mod 3], 8)
  canvas.fillPath(heartPath(vec2(677, 350), 36), white)
  canvas.fillPath(starPath(vec2(754, 390), 30, 13), night)

  let metrics = [
    ("AIR", "98%", mint), ("WATER", "72%", sky),
    ("LIGHT", "GOOD", peach), ("MOOD", "CALM", rgb(0.78, 0.62, 1.0))
  ]
  for index, metric in metrics:
    let x = if index mod 2 == 0: 70.0'f32 else: 1000.0'f32
    let y = 414.0'f32 + (index div 2).float32 * 118
    canvas.fillRect(rect(x, y, 176, 92), rgba(1, 1, 1, 0.07), 7)
    canvas.label(metric[0], x + 18, y + 18, 10, rgba(1, 1, 1, 0.52), 760)
    canvas.label(metric[1], x + 18, y + 47, 23, white, 760)
    canvas.fillRect(rect(x + 145, y + 17, 12, 58), metric[2], 6)
  canvas.fillRect(rect(954, 137, 222, 92), rgba(1, 1, 1, 0.07), 7)
  canvas.label("NEXT SUNRISE", 976, 158, 10, rgba(1, 1, 1, 0.52), 760)
  canvas.label("06:42", 976, 190, 24, white, 760)
  canvas.strokePath(starPath(vec2(1140, 183), 23, 10), peach, 2,
      lineJoin = sljRound)

proc drawNeonDream(canvas: Canvas2D; time: float32) =
  let black = rgb(0.018, 0.014, 0.035)
  let white = rgb(0.96, 0.96, 1.0)
  let cyan = rgb(0.19, 0.91, 0.96)
  let magenta = rgb(1.0, 0.20, 0.68)
  let purple = rgb(0.49, 0.27, 1.0)
  canvas.fillRect(rect(0, 66, 1280, 694), black)
  for index in 0 .. 12:
    let x = 34.0'f32 + index.float32 * 101
    canvas.strokeLine(vec2(x, 96), vec2(x, 718), rgba(0.25, 0.65, 0.92, 0.08), 1)
  for index in 0 .. 6:
    let y = 108.0'f32 + index.float32 * 94
    canvas.strokeLine(vec2(34, y), vec2(1246, y), rgba(0.25, 0.65, 0.92, 0.08), 1)

  canvas.label("NEON DREAM / LIVE", 42, 98, 12, cyan, 820)
  canvas.label("MAKE THE", 42, 146, 58, white, 860)
  canvas.label("NIGHT MOVE", 42, 209, 58, magenta, 860)
  canvas.label("TOKYO  /  22:18  /  120 BPM", 46, 289, 13, rgba(1, 1, 1, 0.55), 620)

  let visual = rect(536, 102, 682, 390)
  canvas.fillLinearGradient(visual, gradient(rgb(0.09, 0.03, 0.22), rgb(0.01,
      0.23, 0.32), 22), 8)
  canvas.pushClip(visual, 8)
  for index in 0 .. 15:
    let phase = time * 1.7 + index.float32 * 0.48
    let x = visual.x + 25 + index.float32 * 42
    let height = 60 + abs(sin(phase)) * 210
    canvas.fillRect(
      rect(x, visual.y + visual.h - height - 24, 18, height),
      if index mod 2 == 0: cyan else: magenta,
      3
    )
  canvas.popClip()
  canvas.label("LIVE FREQUENCY", 564, 126, 11, rgba(1, 1, 1, 0.60), 760)

  let cards = [
    ("ACTIVE LIGHTS", "128", cyan),
    ("CROWD PULSE", "92%", magenta),
    ("NEXT CUE", "00:14", purple)
  ]
  for index, card in cards:
    let x = 42.0'f32 + index.float32 * 300
    canvas.fillRect(rect(x, 548, 274, 138), rgba(1, 1, 1, 0.055), 7)
    canvas.strokeRect(rect(x, 548, 274, 138), rgba(card[2].r, card[2].g, card[
        2].b, 0.48), 1, 7)
    canvas.label(card[0], x + 20, 572, 10, rgba(1, 1, 1, 0.52), 760)
    canvas.label(card[1], x + 20, 610, 30, white, 780)
    canvas.fillRect(rect(x + 20, 659, 234, 5), rgba(card[2].r, card[2].g, card[
        2].b, 0.22), 2)
    canvas.fillRect(rect(x + 20, 659, 70 + index.float32 * 63, 5), card[2], 2)
  canvas.fillRect(rect(956, 548, 262, 138), magenta, 7)
  canvas.label("LAUNCH VISUAL", 982, 578, 12, black, 800)
  canvas.label("CUE 07", 982, 620, 31, black, 850)
  canvas.fillPath(starPath(vec2(1170, 634), 28 + sin(time * 2) * 3, 12), cyan)

proc drawDesignScene*(canvas: Canvas2D; scene: DesignScene;
    nowSeconds: float64) =
  canvas.clear()
  let time = nowSeconds.float32
  canvas.drawNavigation(scene)
  case scene
  of dsHeartParade:
    canvas.drawHeartParade(time)
  of dsCandyRadio:
    canvas.drawCandyRadio(time)
  of dsStickerStudio:
    canvas.drawStickerStudio(time)
  of dsTinyPlanet:
    canvas.drawTinyPlanet(time)
  of dsNeonDream:
    canvas.drawNeonDream(time)

proc sceneAtNavigationPoint*(point: Vec2): Option[DesignScene] =
  if point.y < 15 or point.y > 51:
    return none(DesignScene)
  for scene in DesignScene:
    let x = 330.0'f32 + scene.ord.float32 * 178.0'f32
    if point.x >= x - 13 and point.x <= x + 147:
      return some(scene)
  none(DesignScene)

proc nextScene*(scene: DesignScene; delta: int): DesignScene =
  let count = designSceneCount
  DesignScene((scene.ord + delta mod count + count) mod count)

proc sceneIsAnimated*(scene: DesignScene): bool =
  scene in {dsHeartParade, dsCandyRadio, dsStickerStudio, dsTinyPlanet, dsNeonDream}
