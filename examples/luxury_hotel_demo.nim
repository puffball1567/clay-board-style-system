import std/options

import clay_board_style_system

import ./lifestyle_demo_support

const
  viewportWidth = 1200
  viewportHeight = 760
  ink = Color(r: 0.075, g: 0.09, b: 0.105, a: 1)
  midnight = Color(r: 0.07, g: 0.15, b: 0.17, a: 1)
  ivory = Color(r: 0.965, g: 0.955, b: 0.925, a: 1)
  paper = Color(r: 0.995, g: 0.99, b: 0.975, a: 1)
  white = Color(r: 1, g: 1, b: 1, a: 1)
  muted = Color(r: 0.37, g: 0.39, b: 0.39, a: 1)
  brass = Color(r: 0.72, g: 0.57, b: 0.29, a: 1)
  wine = Color(r: 0.38, g: 0.12, b: 0.16, a: 1)
  sea = Color(r: 0.16, g: 0.39, b: 0.44, a: 1)
  suiteImage = "examples/assets/luxury-hotel-suite.png"

type
  HotelLayoutMode = enum
    hlmMobile,
    hlmCompact,
    hlmDesktop

  HotelLayoutNodes* = object
    root, header, identity, identityCopy, headerMeta, headerDate: NodeHandle
    main, primary, hero, heroImage, heroCopy, lower: NodeHandle
    reservation, reservationHeading, reservationTitle, facts, note: NodeHandle
    evening, eveningTitle, itinerary: NodeHandle
    aside, stay, stayHeading, timeline: NodeHandle
    concierge, conciergeHeading, weather, weatherTop, weatherCopy, forecast: NodeHandle
    serviceRows: seq[NodeHandle]

proc textStyle(
    size: float32;
    color = ink;
    weight = 500.0'f32;
    lineHeight = 0.0'f32;
    serif = false
): UiStyle =
  let resolvedSize = max(size, 10.0'f32)
  let resolvedLineHeight =
    if lineHeight > 0: max(lineHeight, resolvedSize + 3) else: resolvedSize + 6
  let families =
    if serif:
      fontFamilyValue("Liberation Serif", "Noto Serif CJK JP", genericSerif())
    else:
      fontFamilyValue("Lato", "DejaVu Sans", genericSansSerif())
  uiStyle([
    fontSize(resolvedSize),
    decl("line-height", px(resolvedLineHeight)),
    fontWeight(weight),
    decl("font-family", families),
    decl("font-feature-settings", keyword("kern 1, liga 1")),
    decl("letter-spacing", px(0)),
    decl("word-spacing", px(0)),
    decl("text-align", keyword("start")),
    decl("color", colorValue(color))
  ])

proc panelStyle(
    widthValue, heightValue: float32;
    paddingValue = 0.0'f32;
    gapValue = 0.0'f32;
    background = paper
): UiStyle =
  uiStyle([
    width(widthValue),
    height(heightValue),
    padding(paddingValue),
    gap(gapValue),
    flexDirection(fdColumn),
    decl("background-color", colorValue(background)),
    borderWidth(1),
    decl("border-color", colorValue(rgba(0.11, 0.12, 0.12, 0.09))),
    borderRadius(6)
  ])

proc addStayFact(
    ui: UiRoot;
    parent: NodeHandle;
    labelText, valueText: string;
    widthValue: float32
) =
  let item = ui.box(uiStyle([
    width(widthValue), height(54), gap(3), flexDirection(fdColumn)
  ]), parent = some(parent))
  discard ui.text(item, labelText, style = textStyle(9, brass, 720, 13))
  discard ui.text(item, valueText, style = textStyle(13, ink, 620, 18))

proc addService(
    ui: UiRoot;
    parent: NodeHandle;
    symbol, title, detail, action: string;
    accent: Color
) : NodeHandle =
  result = ui.box(uiStyle([
    width(percent(100)), height(62), gap(12), flexDirection(fdRow), alignItems(aiCenter),
    borderBottomWidth(1),
    decl("border-bottom-color", colorValue(rgba(0.11, 0.12, 0.12, 0.08)))
  ]), parent = some(parent))
  let icon = ui.box(uiStyle([
    width(36), height(36), alignItems(aiCenter), justifyContent(jcCenter),
    decl("background-color", colorValue(accent)), borderRadius(18)
  ]), parent = some(result))
  discard ui.text(icon, symbol, style = textStyle(10, white, 760, 14))
  let copy = ui.box(uiStyle([
    width(204), gap(2), flexGrow(1), flexShrink(1), flexDirection(fdColumn)
  ]), parent = some(result))
  discard ui.text(copy, title, style = textStyle(12, ink, 680, 17))
  discard ui.text(copy, detail, style = textStyle(10, muted, 460, 14))
  discard ui.text(result, action, style = textStyle(9, brass, 760, 13))

proc addTimelineItem(
    ui: UiRoot;
    parent: NodeHandle;
    timeText, title, detail: string;
    accent: Color
) =
  let item = ui.box(uiStyle([
    width(percent(50)), height(68), gap(8), flexDirection(fdRow), alignItems(aiCenter)
  ]), parent = some(parent))
  let marker = ui.box(uiStyle([
    width(6), height(44), decl("background-color", colorValue(accent)),
    borderRadius(3)
  ]), parent = some(item))
  let copy = ui.box(uiStyle([
    width(144), gap(1), flexGrow(1), flexShrink(1), flexDirection(fdColumn)
  ]), parent = some(item))
  discard ui.text(copy, timeText, style = textStyle(9, accent, 740, 13))
  discard ui.text(copy, title, style = textStyle(12, ink, 680, 16))
  discard ui.text(copy, detail, style = textStyle(9, muted, 450, 13))
  discard marker

proc buildLuxuryHotelDemo*(ui: UiRoot): HotelLayoutNodes =
  result.root = ui.box(uiStyle([
    width(viewportWidth), height(viewportHeight), padding(24), gap(16),
    flexDirection(fdColumn), alignItems(aiCenter),
    decl("background-color", colorValue(ivory))
  ]), id = "luxury-hotel-demo")

  result.header = ui.box(uiStyle([
    width(1152), height(56), flexDirection(fdRow), alignItems(aiCenter),
    justifyContent(jcSpaceBetween)
  ]), parent = some(result.root), id = "hotel-header")
  result.identity = ui.box(uiStyle([
    width(400), height(44), gap(13), flexDirection(fdRow), alignItems(aiCenter)
  ]), parent = some(result.header))
  let monogram = ui.box(uiStyle([
    width(38), height(38), alignItems(aiCenter), justifyContent(jcCenter),
    decl("background-color", colorValue(midnight)), borderRadius(19)
  ]), parent = some(result.identity))
  discard ui.text(monogram, "18", style = textStyle(10, ivory, 720, 14))
  result.identityCopy = ui.box(uiStyle([
    width(320), gap(1), flexDirection(fdColumn)
  ]), parent = some(result.identity))
  discard ui.text(result.identityCopy, "PRIVATE STAY", style = textStyle(14, ink, 700, 19, serif = true))
  discard ui.text(result.identityCopy, "GRAND SUITE · LEVEL 18", style = textStyle(9, muted, 650, 13))

  result.headerMeta = ui.box(uiStyle([
    width(350), height(40), gap(16), flexDirection(fdRow),
    alignItems(aiCenter), justifyContent(jcEnd)
  ]), parent = some(result.header))
  result.headerDate = ui.text(result.headerMeta, "TUESDAY · 18 AUGUST", style = textStyle(9, muted, 650, 13))
  let guest = ui.box(uiStyle([
    width(108), height(34), gap(8), flexDirection(fdRow), alignItems(aiCenter),
    justifyContent(jcCenter), decl("background-color", colorValue(paper)),
    borderRadius(17)
  ]), parent = some(result.headerMeta))
  discard ui.box(uiStyle([
    width(8), height(8), decl("background-color", colorValue(brass)), borderRadius(4)
  ]), parent = some(guest))
  discard ui.text(guest, "SUITE 1808", style = textStyle(9, ink, 700, 13))

  result.main = ui.box(uiStyle([
    width(1152), height(640), gap(18), flexDirection(fdRow)
  ]), parent = some(result.root), id = "hotel-main")

  result.primary = ui.box(uiStyle([
    width(760), height(640), gap(16), flexDirection(fdColumn)
  ]), parent = some(result.main), id = "hotel-primary")
  result.hero = ui.box(uiStyle([
    width(760), height(394), position(pkRelative),
    decl("overflow", keyword("hidden")), borderRadius(7),
    decl("background-color", colorValue(midnight))
  ]), parent = some(result.primary), id = "hotel-hero")
  let heroImage = ui.image(
    result.hero,
    suiteImage,
    style = uiStyle([
      width(760), height(394), decl("object-fit", keyword("cover")),
      decl("object-position", keyword("center"))
    ]),
    width = 760,
    height = 394,
    id = "suite-photograph"
  )
  result.heroImage = heroImage.container
  result.heroCopy = ui.box(uiStyle([
    width(376), height(124), padding(18), gap(5), flexDirection(fdColumn),
    position(pkAbsolute), left(24), top(246),
    decl("background-color", colorValue(rgba(0.035, 0.075, 0.085, 0.88))),
    borderLeftWidth(3), decl("border-left-color", colorValue(brass)),
    borderRadius(4)
  ]), parent = some(result.hero))
  discard ui.text(result.heroCopy, "WELCOME BACK", style = textStyle(9, brass, 760, 13))
  discard ui.text(result.heroCopy, "Blue hour, above the coast", style = textStyle(23, white, 560, 29, serif = true))
  discard ui.text(result.heroCopy, "Your suite is prepared for a quiet evening.", style = textStyle(10, rgba(0.91, 0.92, 0.90, 1), 470, 14))

  result.lower = ui.box(uiStyle([
    width(760), height(230), gap(16), flexDirection(fdRow)
  ]), parent = some(result.primary), id = "hotel-lower")
  result.reservation = ui.box(
    panelStyle(476, 230, paddingValue = 20, gapValue = 14),
    parent = some(result.lower),
    id = "hotel-reservation"
  )
  result.reservationHeading = ui.box(uiStyle([
    width(percent(100)), height(42), flexDirection(fdRow), alignItems(aiCenter),
    justifyContent(jcSpaceBetween)
  ]), parent = some(result.reservation))
  result.reservationTitle = ui.box(uiStyle([
    width(280), gap(2), flexDirection(fdColumn)
  ]), parent = some(result.reservationHeading))
  discard ui.text(result.reservationTitle, "YOUR RESERVATION", style = textStyle(9, brass, 750, 13))
  discard ui.text(result.reservationTitle, "Three nights of stillness", style = textStyle(17, ink, 600, 22, serif = true))
  discard ui.text(result.reservationHeading, "CONFIRMED", style = textStyle(9, sea, 760, 13))
  result.facts = ui.box(uiStyle([
    width(percent(100)), height(54), gap(16), flexDirection(fdRow)
  ]), parent = some(result.reservation))
  ui.addStayFact(result.facts, "ARRIVAL", "18 AUG · 15:00", 126)
  ui.addStayFact(result.facts, "DEPARTURE", "21 AUG · 12:00", 138)
  ui.addStayFact(result.facts, "GUESTS", "2 ADULTS", 112)
  result.note = ui.box(uiStyle([
    width(percent(100)), height(58), padding(12), gap(10), flexDirection(fdRow),
    alignItems(aiCenter), decl("background-color", colorValue(rgba(0.16, 0.39, 0.44, 0.09))),
    borderRadius(4)
  ]), parent = some(result.reservation))
  discard ui.box(uiStyle([
    width(7), height(34), decl("background-color", colorValue(sea)), borderRadius(3)
  ]), parent = some(result.note))
  discard ui.text(result.note, "Evening turndown is scheduled for 19:30.", style = textStyle(10, ink, 540, 14))

  result.evening = ui.box(
    panelStyle(268, 230, paddingValue = 18, gapValue = 11, background = wine),
    parent = some(result.lower),
    id = "hotel-evening"
  )
  discard ui.text(result.evening, "THIS EVENING", style = textStyle(9, brass, 760, 13))
  result.eveningTitle = ui.box(uiStyle([
    width(percent(100)), height(54), gap(0), flexDirection(fdColumn)
  ]), parent = some(result.evening))
  discard ui.text(result.eveningTitle, "A table by", style = textStyle(22, white, 560, 27, serif = true))
  discard ui.text(result.eveningTitle, "the water", style = textStyle(22, white, 560, 27, serif = true))
  discard ui.text(result.evening, "19:45 · TERRACE", style = textStyle(9, rgba(0.93, 0.85, 0.72, 1), 680, 13))
  discard ui.text(result.evening, "Your car departs the lobby at 19:25.", style = textStyle(10, rgba(0.95, 0.91, 0.89, 1), 460, 15))
  result.itinerary = ui.box(uiStyle([
    width(percent(100)), height(32), alignItems(aiCenter), justifyContent(jcCenter),
    decl("background-color", colorValue(rgba(1, 1, 1, 0.12))),
    borderWidth(1), decl("border-color", colorValue(rgba(1, 1, 1, 0.20))),
    borderRadius(4)
  ]), parent = some(result.evening))
  discard ui.text(result.itinerary, "VIEW ITINERARY", style = textStyle(9, white, 740, 13))

  result.aside = ui.box(uiStyle([
    width(374), height(640), gap(16), flexDirection(fdColumn)
  ]), parent = some(result.main), id = "hotel-aside")
  result.stay = ui.box(
    panelStyle(374, 160, paddingValue = 19, gapValue = 11),
    parent = some(result.aside),
    id = "hotel-stay"
  )
  result.stayHeading = ui.box(uiStyle([
    width(percent(100)), height(24), flexDirection(fdRow), alignItems(aiCenter),
    justifyContent(jcSpaceBetween)
  ]), parent = some(result.stay))
  discard ui.text(result.stayHeading, "TODAY", style = textStyle(9, brass, 760, 13))
  discard ui.text(result.stayHeading, "2 PLANS", style = textStyle(9, muted, 650, 13))
  result.timeline = ui.box(uiStyle([
    width(percent(100)), height(86), gap(12), flexDirection(fdRow)
  ]), parent = some(result.stay))
  ui.addTimelineItem(result.timeline, "17:30", "Private spa", "Wellness level", sea)
  ui.addTimelineItem(result.timeline, "19:45", "Terrace dinner", "Car at 19:25", wine)

  result.concierge = ui.box(
    panelStyle(374, 280, paddingValue = 19, gapValue = 5),
    parent = some(result.aside),
    id = "hotel-concierge"
  )
  result.conciergeHeading = ui.box(uiStyle([
    width(percent(100)), height(40), flexDirection(fdRow), alignItems(aiCenter),
    justifyContent(jcSpaceBetween)
  ]), parent = some(result.concierge))
  discard ui.text(result.conciergeHeading, "CONCIERGE", style = textStyle(15, ink, 650, 20, serif = true))
  discard ui.text(result.conciergeHeading, "AVAILABLE", style = textStyle(9, sea, 750, 13))
  result.serviceRows.add ui.addService(result.concierge, "D", "Private dining", "Reserve or amend a table", "OPEN", wine)
  result.serviceRows.add ui.addService(result.concierge, "S", "Spa and wellness", "Treatments until 22:00", "OPEN", sea)
  result.serviceRows.add ui.addService(result.concierge, "C", "Private car", "Ready within 15 minutes", "CALL", brass)

  result.weather = ui.box(uiStyle([
    width(374), height(168), padding(20), gap(10), flexDirection(fdColumn),
    decl("background-color", colorValue(midnight)), borderRadius(6)
  ]), parent = some(result.aside), id = "hotel-weather")
  result.weatherTop = ui.box(uiStyle([
    width(percent(100)), height(46), flexDirection(fdRow), alignItems(aiCenter),
    justifyContent(jcSpaceBetween)
  ]), parent = some(result.weather))
  result.weatherCopy = ui.box(uiStyle([
    width(240), gap(1), flexDirection(fdColumn)
  ]), parent = some(result.weatherTop))
  discard ui.text(result.weatherCopy, "COAST AT BLUE HOUR", style = textStyle(9, brass, 740, 13))
  discard ui.text(result.weatherCopy, "Clear and still", style = textStyle(16, white, 570, 21, serif = true))
  discard ui.text(result.weatherTop, "21°", style = textStyle(27, white, 540, 32, serif = true))
  result.forecast = ui.box(uiStyle([
    width(percent(100)), height(62), padding(12), gap(13), flexDirection(fdRow),
    alignItems(aiCenter), decl("background-color", colorValue(rgba(1, 1, 1, 0.08))),
    borderRadius(4)
  ]), parent = some(result.weather))
  discard ui.text(result.forecast, "SUNSET 19:12", style = textStyle(9, rgba(0.90, 0.90, 0.86, 1), 650, 13))
  discard ui.box(uiStyle([
    width(1), height(28), decl("background-color", colorValue(rgba(1, 1, 1, 0.18)))
  ]), parent = some(result.forecast))
  discard ui.text(result.forecast, "SEA BREEZE 6 KM/H", style = textStyle(9, rgba(0.90, 0.90, 0.86, 1), 650, 13))

proc bounded(value, minimum, maximum: float32): float32 =
  max(minimum, min(maximum, value))

proc layoutMode(viewport: Size): HotelLayoutMode =
  if viewport.w < 700:
    hlmMobile
  elif viewport.w < 1040:
    hlmCompact
  else:
    hlmDesktop

proc applyLuxuryHotelLayout*(ui: UiRoot; nodes: HotelLayoutNodes; viewport: Size) =
  let mode = viewport.layoutMode()
  let viewportWidth = max(viewport.w, 320.0'f32)
  let viewportHeight = max(viewport.h, 480.0'f32)
  let paddingValue =
    case mode
    of hlmDesktop: 24.0'f32
    of hlmCompact: 20.0'f32
    of hlmMobile: 14.0'f32
  let rootGap =
    case mode
    of hlmDesktop: 16.0'f32
    of hlmCompact: 14.0'f32
    of hlmMobile: 10.0'f32
  let headerHeight =
    case mode
    of hlmDesktop: 56.0'f32
    of hlmCompact: 52.0'f32
    of hlmMobile: 48.0'f32
  let contentWidth = max(292.0'f32, viewportWidth - paddingValue * 2)
  let mainHeight = max(
    390.0'f32,
    viewportHeight - paddingValue * 2 - headerHeight - rootGap
  )

  ui.applyStyle(nodes.root, uiStyle([
    width(viewportWidth), height(viewportHeight), padding(paddingValue), gap(rootGap),
    decl("overflow", keyword("hidden"))
  ]))
  ui.applyStyle(nodes.header, uiStyle([
    width(contentWidth), height(headerHeight)
  ]))
  ui.applyStyle(nodes.main, uiStyle([
    width(contentWidth), height(mainHeight)
  ]))

  case mode
  of hlmDesktop:
    let mainGap = 18.0'f32
    let asideWidth = bounded(contentWidth * 0.325'f32, 340, 374)
    let primaryWidth = contentWidth - mainGap - asideWidth
    let lowerHeight = bounded(mainHeight * 0.36'f32, 210, 230)
    let heroHeight = mainHeight - rootGap - lowerHeight
    let eveningWidth = bounded(primaryWidth * 0.353'f32, 236, 268)
    let reservationWidth = primaryWidth - rootGap - eveningWidth
    let weatherHeight = max(132.0'f32, mainHeight - 160 - 280 - rootGap * 2)

    ui.applyStyle(nodes.identity, uiStyle([width(400), height(44)]))
    ui.applyStyle(nodes.identityCopy, uiStyle([width(320)]))
    ui.applyStyle(nodes.headerMeta, uiStyle([display(dkFlex), width(350), height(40)]))
    ui.applyStyle(nodes.headerDate, uiStyle([display(dkFlex)]))
    ui.applyStyle(nodes.main, uiStyle([gap(mainGap), flexDirection(fdRow)]))
    ui.applyStyle(nodes.primary, uiStyle([
      display(dkFlex), width(primaryWidth), height(mainHeight), gap(rootGap)
    ]))
    ui.applyStyle(nodes.hero, uiStyle([width(primaryWidth), height(heroHeight)]))
    ui.applyStyle(nodes.heroImage, uiStyle([width(primaryWidth), height(heroHeight)]))
    ui.applyStyle(nodes.heroCopy, uiStyle([
      width(min(376.0'f32, primaryWidth - 48)), height(124), padding(18),
      left(24), top(max(18.0'f32, heroHeight - 148))
    ]))
    ui.applyStyle(nodes.lower, uiStyle([
      width(primaryWidth), height(lowerHeight), gap(rootGap), flexDirection(fdRow)
    ]))
    ui.applyStyle(nodes.reservation, uiStyle([
      display(dkFlex), width(reservationWidth), height(lowerHeight), padding(20), gap(14)
    ]))
    ui.applyStyle(nodes.reservationTitle, uiStyle([width(280)]))
    ui.applyStyle(nodes.facts, uiStyle([gap(16)]))
    ui.applyStyle(nodes.note, uiStyle([display(dkFlex)]))
    ui.applyStyle(nodes.evening, uiStyle([
      display(dkFlex), width(eveningWidth), height(lowerHeight), padding(18), gap(11)
    ]))
    ui.applyStyle(nodes.aside, uiStyle([
      display(dkFlex), width(asideWidth), height(mainHeight), gap(rootGap)
    ]))
    ui.applyStyle(nodes.stay, uiStyle([
      display(dkFlex), width(asideWidth), height(160), padding(19), gap(11)
    ]))
    ui.applyStyle(nodes.concierge, uiStyle([
      display(dkFlex), width(asideWidth), height(280), padding(19), gap(5)
    ]))
    ui.applyStyle(nodes.conciergeHeading, uiStyle([height(40)]))
    ui.applyStyle(nodes.weather, uiStyle([
      display(dkFlex), width(asideWidth), height(weatherHeight), padding(20), gap(10)
    ]))
    for row in nodes.serviceRows:
      ui.applyStyle(row, uiStyle([display(dkFlex), height(62), gap(12)]))

  of hlmCompact:
    let mainGap = 14.0'f32
    let asideWidth = bounded(contentWidth * 0.36'f32, 292, 340)
    let primaryWidth = contentWidth - mainGap - asideWidth
    let lowerHeight = bounded(mainHeight * 0.38'f32, 205, 250)
    let heroHeight = mainHeight - mainGap - lowerHeight
    let weatherVisible = mainHeight >= 570
    let weatherHeight =
      if weatherVisible: max(126.0'f32, mainHeight - 150 - 280 - mainGap * 2)
      else: 0.0'f32
    let conciergeHeight =
      if weatherVisible: 280.0'f32
      else: mainHeight - 150 - mainGap

    ui.applyStyle(nodes.identity, uiStyle([width(contentWidth - 188), height(42)]))
    ui.applyStyle(nodes.identityCopy, uiStyle([width(contentWidth - 245)]))
    ui.applyStyle(nodes.headerMeta, uiStyle([display(dkFlex), width(170), height(40)]))
    ui.applyStyle(nodes.headerDate, uiStyle([display(dkNone)]))
    ui.applyStyle(nodes.main, uiStyle([gap(mainGap), flexDirection(fdRow)]))
    ui.applyStyle(nodes.primary, uiStyle([
      display(dkFlex), width(primaryWidth), height(mainHeight), gap(mainGap)
    ]))
    ui.applyStyle(nodes.hero, uiStyle([width(primaryWidth), height(heroHeight)]))
    ui.applyStyle(nodes.heroImage, uiStyle([width(primaryWidth), height(heroHeight)]))
    ui.applyStyle(nodes.heroCopy, uiStyle([
      width(max(286.0'f32, primaryWidth - 32)), height(126), padding(16),
      left(16), top(max(16.0'f32, heroHeight - 142))
    ]))
    ui.applyStyle(nodes.lower, uiStyle([
      width(primaryWidth), height(lowerHeight), gap(0), flexDirection(fdRow)
    ]))
    ui.applyStyle(nodes.reservation, uiStyle([
      display(dkFlex), width(primaryWidth), height(lowerHeight), padding(18), gap(12)
    ]))
    ui.applyStyle(nodes.reservationTitle, uiStyle([width(max(206.0'f32, primaryWidth - 170))]))
    ui.applyStyle(nodes.facts, uiStyle([gap(10)]))
    ui.applyStyle(nodes.note, uiStyle([display(dkFlex)]))
    ui.applyStyle(nodes.evening, uiStyle([display(dkNone)]))
    ui.applyStyle(nodes.aside, uiStyle([
      display(dkFlex), width(asideWidth), height(mainHeight), gap(mainGap)
    ]))
    ui.applyStyle(nodes.stay, uiStyle([
      display(dkFlex), width(asideWidth), height(150), padding(16), gap(9)
    ]))
    ui.applyStyle(nodes.concierge, uiStyle([
      display(dkFlex), width(asideWidth), height(conciergeHeight), padding(16), gap(5)
    ]))
    ui.applyStyle(nodes.conciergeHeading, uiStyle([height(38)]))
    ui.applyStyle(nodes.weather, uiStyle([
      display(if weatherVisible: dkFlex else: dkNone),
      width(asideWidth), height(weatherHeight), padding(16), gap(8)
    ]))
    for row in nodes.serviceRows:
      ui.applyStyle(row, uiStyle([display(dkFlex), height(62), gap(10)]))

  of hlmMobile:
    let mainGap = 10.0'f32
    let conciergeHeight = bounded(mainHeight * 0.31'f32, 170, 220)
    let reservationHeight = bounded(mainHeight * 0.27'f32, 145, 190)
    let heroHeight = max(
      150.0'f32,
      mainHeight - conciergeHeight - reservationHeight - mainGap * 2
    )
    let primaryHeight = heroHeight + mainGap + reservationHeight
    let showGuest = contentWidth >= 430
    let serviceHeight = max(50.0'f32, (conciergeHeight - 68) / 2)

    ui.applyStyle(nodes.identity, uiStyle([
      width(if showGuest: contentWidth - 122 else: contentWidth), height(40), gap(10)
    ]))
    ui.applyStyle(nodes.identityCopy, uiStyle([
      width(if showGuest: contentWidth - 172 else: contentWidth - 50)
    ]))
    ui.applyStyle(nodes.headerMeta, uiStyle([
      display(if showGuest: dkFlex else: dkNone), width(108), height(38)
    ]))
    ui.applyStyle(nodes.headerDate, uiStyle([display(dkNone)]))
    ui.applyStyle(nodes.main, uiStyle([gap(mainGap), flexDirection(fdColumn)]))
    ui.applyStyle(nodes.primary, uiStyle([
      display(dkFlex), width(contentWidth), height(primaryHeight), gap(mainGap)
    ]))
    ui.applyStyle(nodes.hero, uiStyle([width(contentWidth), height(heroHeight)]))
    ui.applyStyle(nodes.heroImage, uiStyle([width(contentWidth), height(heroHeight)]))
    ui.applyStyle(nodes.heroCopy, uiStyle([
      width(max(260.0'f32, contentWidth - 32)), height(124), padding(14),
      left(16), top(max(12.0'f32, heroHeight - 136))
    ]))
    ui.applyStyle(nodes.lower, uiStyle([
      width(contentWidth), height(reservationHeight), gap(0), flexDirection(fdRow)
    ]))
    ui.applyStyle(nodes.reservation, uiStyle([
      display(dkFlex), width(contentWidth), height(reservationHeight), padding(14), gap(10)
    ]))
    ui.applyStyle(nodes.reservationTitle, uiStyle([width(max(190.0'f32, contentWidth - 142))]))
    ui.applyStyle(nodes.facts, uiStyle([gap(8)]))
    ui.applyStyle(nodes.note, uiStyle([display(dkNone)]))
    ui.applyStyle(nodes.evening, uiStyle([display(dkNone)]))
    ui.applyStyle(nodes.aside, uiStyle([
      display(dkFlex), width(contentWidth), height(conciergeHeight), gap(0)
    ]))
    ui.applyStyle(nodes.stay, uiStyle([display(dkNone)]))
    ui.applyStyle(nodes.concierge, uiStyle([
      display(dkFlex), width(contentWidth), height(conciergeHeight), padding(12), gap(4)
    ]))
    ui.applyStyle(nodes.conciergeHeading, uiStyle([height(32)]))
    ui.applyStyle(nodes.weather, uiStyle([display(dkNone)]))
    for index, row in nodes.serviceRows:
      ui.applyStyle(row, uiStyle([
        display(if index < 2: dkFlex else: dkNone),
        height(serviceHeight), gap(10)
      ]))

proc main() =
  var fonts = initFontRegistry()
  fonts.addFallbackFamily("Lato")
  fonts.addFallbackFamily("Liberation Serif")
  fonts.addFallbackFamily("Noto Sans")
  fonts.addFallbackFamily("Noto Sans CJK JP")
  fonts.addFallbackFamily("Noto Serif CJK JP")
  var cosmic = initCosmicTextEngine(fonts)
  defer:
    cosmic.close()

  let ui = initUiRoot()
  ui.configureTextLayout(cosmic.textEngine(), fonts)
  let layoutNodes = ui.buildLuxuryHotelDemo()
  let responsiveLayout: LifestyleViewportLayout = proc(
      target: UiRoot;
      viewport: Size
  ) =
    target.applyLuxuryHotelLayout(layoutNodes, viewport)
  ui.runLifestyleDemo(
    cosmic,
    fonts,
    "Clay Board Style System - Luxury Hotel",
    viewportWidth,
    viewportHeight,
    ivory,
    viewportLayout = responsiveLayout
  )

when isMainModule:
  main()
