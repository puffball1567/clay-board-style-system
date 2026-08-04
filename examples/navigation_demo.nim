import std/[options, os, strutils, times]

import clay_board_style_system
import clay_board_style_system/backends/sdl3/platform_links
import clay_board_style_system/backends/sdl3/renderer
import clay_board_style_system/generated/default_properties

type
  DemoScreen = enum
    dsOverview,
    dsProjects,
    dsSettings

  DemoFrame = object
    styles: ResolvedTree
    layout: LayoutResult
    commands: seq[PaintCommand]
    regions: seq[HitRegion]

const
  viewportWidth = 1080
  viewportHeight = 700
  transitionStylePriority = navigationScreenHostStylePriority - 1

proc buildFrame(ui: UiRoot; viewport: Size): DemoFrame =
  var diagnostics: Diagnostics
  result.styles = resolveTreeStyles(
    ui.tree,
    ui.styleSheets(),
    defaultProperties(),
    diagnostics
  )
  if diagnostics.hasErrors:
    for item in diagnostics.items:
      echo item.property, ": ", item.message
    raise newException(ValueError, "navigation demo style resolution failed")
  result.layout = computeLayout(
    ui.tree,
    result.styles,
    viewport,
    ui.textEngine,
    ui.fonts
  )
  ui.scroll.syncScrollState(ui.tree, result.styles, result.layout)
  result.commands = buildPaintCommands(
    ui.tree,
    result.styles,
    result.layout,
    ui.scroll
  )
  result.regions = buildHitRegions(
    ui.tree,
    result.layout,
    result.styles,
    ui.scroll
  )

proc saveCapturedFrame(frame: Sdl3CapturedFrame; path: string) =
  var output = "P6\n" & $frame.width & " " & $frame.height & "\n255\n"
  let offset = output.len
  output.setLen(offset + frame.pixels.len)
  for index, value in frame.pixels:
    output[offset + index] = char(value)
  writeFile(path, output)

proc screenName(screen: DemoScreen): string =
  case screen
  of dsOverview: "Overview"
  of dsProjects: "Projects"
  of dsSettings: "Settings"

proc appStyle(): UiStyle =
  uiStyle([
    decl("width", px(viewportWidth)),
    decl("height", px(viewportHeight)),
    decl("flex-direction", keyword("row")),
    decl("background-color", colorValue(rgb(0.035, 0.047, 0.067))),
    decl("color", colorValue(rgb(0.90, 0.93, 0.97)))
  ])

proc sidebarStyle(): UiStyle =
  uiStyle([
    decl("width", px(236)),
    decl("height", px(viewportHeight)),
    decl("padding", px(22)),
    decl("gap", px(12)),
    decl("flex-direction", keyword("column")),
    decl("background-color", colorValue(rgb(0.055, 0.075, 0.105))),
    decl("border-right-width", px(1)),
    decl("border-right-color", colorValue(rgb(0.15, 0.19, 0.25)))
  ])

proc navLinkStyle(): UiStyle =
  uiStyle([
    decl("width", px(192)),
    decl("height", px(42)),
    decl("padding", px(11)),
    decl("align-items", keyword("center")),
    decl("background-color", colorValue(rgb(0.085, 0.115, 0.155))),
    decl("border-width", px(1)),
    decl("border-color", colorValue(rgb(0.16, 0.21, 0.28))),
    decl("border-radius", px(6)),
    decl("cursor", keyword("pointer"))
  ])

proc navLinkTextStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(14)),
    decl("line-height", px(20)),
    decl("color", colorValue(rgb(0.87, 0.91, 0.96)))
  ])

proc toolbarButtonStyle(width = 112.0'f32): UiStyle =
  uiStyle([
    decl("width", px(width)),
    decl("height", px(36)),
    decl("padding", px(9)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(rgb(0.10, 0.14, 0.19))),
    decl("border-width", px(1)),
    decl("border-color", colorValue(rgb(0.21, 0.27, 0.35))),
    decl("border-radius", px(5)),
    decl("cursor", keyword("pointer"))
  ])

proc toolbarButtonTextStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(13)),
    decl("line-height", px(18)),
    decl("color", colorValue(rgb(0.90, 0.93, 0.97)))
  ])

proc contentStyle(): UiStyle =
  uiStyle([
    decl("width", px(844)),
    decl("height", px(viewportHeight)),
    decl("position", keyword("relative")),
    decl("overflow", keyword("hidden"))
  ])

proc screenStyle(): UiStyle =
  uiStyle([
    decl("position", keyword("absolute")),
    decl("left", px(0)),
    decl("top", px(0)),
    decl("width", px(844)),
    decl("height", px(viewportHeight)),
    decl("padding", px(30)),
    decl("gap", px(18)),
    decl("flex-direction", keyword("column")),
    decl("background-color", colorValue(rgb(0.035, 0.047, 0.067)))
  ])

proc headingStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(30)),
    decl("line-height", px(38)),
    decl("font-weight", number(700)),
    decl("color", colorValue(rgb(0.96, 0.98, 1.0)))
  ])

proc bodyStyle(): UiStyle =
  uiStyle([
    decl("font-size", px(14)),
    decl("line-height", px(22)),
    decl("color", colorValue(rgb(0.66, 0.73, 0.82)))
  ])

proc cardStyle(width = 242.0'f32; height = 146.0'f32): UiStyle =
  uiStyle([
    decl("width", px(width)),
    decl("height", px(height)),
    decl("padding", px(18)),
    decl("gap", px(10)),
    decl("flex-direction", keyword("column")),
    decl("background-color", colorValue(rgb(0.075, 0.10, 0.135))),
    decl("border-width", px(1)),
    decl("border-color", colorValue(rgb(0.16, 0.21, 0.28))),
    decl("border-radius", px(7)),
    decl("box-shadow", shadowValue(
      px(0),
      px(9),
      some(px(24)),
      some(px(0)),
      some(rgba(0, 0, 0, 0.24))
    ))
  ])

proc buildOverview(
    ui: UiRoot;
    content: NodeHandle;
    navigator: Navigator[DemoScreen]
): tuple[root: NodeHandle, deepLinkButton: ButtonHandle, rebuildButton: ButtonHandle] =
  result.root = ui.box(screenStyle(), parent = some(content), id = "overview-screen")
  ui.pushParent(result.root)
  try:
    discard ui.text("Native navigation", style = headingStyle())
    discard ui.text(
      "Typed destinations, retained screens, focus restore, and event-driven transitions.",
      style = bodyStyle()
    )
    let cards = ui.box(uiStyle([
      decl("height", px(166)),
      decl("gap", px(16)),
      decl("flex-direction", keyword("row"))
    ]))
    ui.pushParent(cards)
    try:
      for item in [
        ("3", "Typed screens", "No URL strings for\nin-process navigation."),
        ("0", "Idle frames", "Event loop sleeps until\nUI work is requested."),
        ("1", "Retained tree", "History changes preserve\nunrelated node state.")
      ]:
        let card = ui.box(cardStyle())
        ui.pushParent(card)
        discard ui.text(item[0], style = uiStyle([
          decl("font-size", px(28)),
          decl("line-height", px(34)),
          decl("font-weight", number(700)),
          decl("color", colorValue(rgb(0.35, 0.78, 0.98)))
        ]))
        discard ui.text(item[1], style = uiStyle([
          decl("font-size", px(15)),
          decl("line-height", px(20)),
          decl("font-weight", number(600)),
          decl("color", colorValue(rgb(0.92, 0.95, 0.98)))
        ]))
        discard ui.text(item[2], style = uiStyle([
          decl("width", px(206)),
          decl("height", px(46)),
          decl("font-size", px(13)),
          decl("line-height", px(20)),
          decl("white-space", keyword("pre-wrap")),
          decl("color", colorValue(rgb(0.66, 0.73, 0.82)))
        ]))
        ui.popParent()
    finally:
      ui.popParent()

    let actions = ui.box(uiStyle([
      decl("height", px(44)),
      decl("gap", px(10)),
      decl("flex-direction", keyword("row"))
    ]))
    ui.pushParent(actions)
    result.deepLinkButton = ui.button(
      "Open project deep link",
      style = toolbarButtonStyle(198),
      textStyle = toolbarButtonTextStyle(),
      id = "deep-link-button"
    )
    result.rebuildButton = ui.button(
      "Rebuild settings",
      style = toolbarButtonStyle(150),
      textStyle = toolbarButtonTextStyle(),
      id = "rebuild-button"
    )
    ui.popParent()

    let focusLink = ui.link(
      navigator,
      dsSettings,
      "Focus this link, leave Settings, then use Back to see focus restoration.",
      style = uiStyle([
        decl("width", px(640)),
        decl("height", px(42)),
        decl("padding", px(10)),
        decl("background-color", colorValue(rgb(0.07, 0.16, 0.20))),
        decl("border-width", px(1)),
        decl("border-color", colorValue(rgb(0.16, 0.40, 0.46))),
        decl("border-radius", px(5)),
        decl("cursor", keyword("pointer"))
      ]),
      textStyle = bodyStyle(),
      id = "focus-restore-link"
    )
    discard focusLink
  finally:
    ui.popParent()

proc buildProjects(
    ui: UiRoot;
    content: NodeHandle;
    revision: int
): NodeHandle =
  result = ui.box(screenStyle(), parent = some(content), id = "projects-screen")
  ui.pushParent(result)
  try:
    discard ui.text("Projects", style = headingStyle())
    discard ui.text(
      "Reached through the typed URI cbss-demo://projects. Project view revision " & $revision & ".",
      style = bodyStyle()
    )
    for item in [
      ("Desktop console", "Active", 0.82'f32),
      ("Design review", "Ready", 0.64'f32),
      ("Release validation", "Running", 0.43'f32)
    ]:
      let row = ui.box(uiStyle([
        decl("width", px(720)),
        decl("height", px(76)),
        decl("padding", px(16)),
        decl("gap", px(16)),
        decl("flex-direction", keyword("row")),
        decl("align-items", keyword("center")),
        decl("background-color", colorValue(rgb(0.075, 0.10, 0.135))),
        decl("border-width", px(1)),
        decl("border-color", colorValue(rgb(0.16, 0.21, 0.28))),
        decl("border-radius", px(6))
      ]))
      ui.pushParent(row)
      discard ui.text(item[0], style = uiStyle([
        decl("width", px(210)),
        decl("font-size", px(15)),
        decl("font-weight", number(600)),
        decl("color", colorValue(rgb(0.91, 0.94, 0.98)))
      ]))
      discard ui.text(item[1], style = uiStyle([
        decl("width", px(90)),
        decl("font-size", px(13)),
        decl("color", colorValue(rgb(0.40, 0.84, 0.68)))
      ]))
      let track = ui.box(uiStyle([
        decl("width", px(330)),
        decl("height", px(8)),
        decl("background-color", colorValue(rgb(0.12, 0.16, 0.21))),
        decl("border-radius", px(4))
      ]))
      discard ui.box(uiStyle([
        decl("width", px(330 * item[2])),
        decl("height", px(8)),
        decl("background-color", colorValue(rgb(0.25, 0.67, 0.93))),
        decl("border-radius", px(4))
      ]), parent = some(track))
      ui.popParent()
  finally:
    ui.popParent()

proc buildSettings(ui: UiRoot; content: NodeHandle; revision: int): NodeHandle =
  result = ui.box(screenStyle(), parent = some(content), id = "settings-screen")
  ui.pushParent(result)
  try:
    discard ui.text("Settings", style = headingStyle())
    discard ui.text(
      "This retained subtree can be replaced independently. Revision " & $revision & ".",
      style = bodyStyle()
    )
    let panel = ui.box(cardStyle(590, 232))
    ui.pushParent(panel)
    discard ui.text("Navigation behavior", style = uiStyle([
      decl("font-size", px(17)),
      decl("line-height", px(24)),
      decl("font-weight", number(650)),
      decl("color", colorValue(rgb(0.94, 0.96, 0.99)))
    ]))
    discard ui.checkbox("Restore focus for each history entry", checked = true)
    discard ui.checkbox("Keep inactive screens inert", checked = true)
    discard ui.checkbox("Request frames only during transitions", checked = true)
    ui.popParent()
  finally:
    ui.popParent()

proc main() =
  var fonts = initFontRegistry()
  fonts.addFallbackFamily("Noto Sans")
  fonts.addFallbackFamily("Noto Sans CJK JP")
  var cosmic = initCosmicTextEngine(fonts)
  defer:
    cosmic.close()

  let ui = initUiRoot()
  ui.configureTextLayout(cosmic.textEngine(), fonts)
  let navigator = initStackNavigator(dsOverview)
  let appRoot = ui.box(appStyle(), id = "navigation-demo")
  let sidebar = ui.box(sidebarStyle(), parent = some(appRoot))
  ui.pushParent(sidebar)
  discard ui.text("CBSS", style = uiStyle([
    decl("font-size", px(22)),
    decl("line-height", px(30)),
    decl("font-weight", number(750)),
    decl("color", colorValue(rgb(0.96, 0.98, 1.0)))
  ]))
  discard ui.text("v0.2 navigation", style = bodyStyle())
  for destination in [dsOverview, dsProjects, dsSettings]:
    discard ui.link(
      navigator,
      destination,
      destination.screenName(),
      style = navLinkStyle(),
      textStyle = navLinkTextStyle(),
      id = "nav-" & destination.screenName().toLowerAscii()
    )
  let navActions = ui.box(uiStyle([
    decl("height", px(44)),
    decl("gap", px(8)),
    decl("flex-direction", keyword("row"))
  ]))
  ui.pushParent(navActions)
  let backButton = ui.button(
    "Back",
    style = toolbarButtonStyle(88),
    textStyle = toolbarButtonTextStyle(),
    id = "back-button"
  )
  let forwardButton = ui.button(
    "Forward",
    style = toolbarButtonStyle(96),
    textStyle = toolbarButtonTextStyle(),
    id = "forward-button"
  )
  ui.popParent()
  let docsButton = ui.button(
      "Open documentation",
    style = toolbarButtonStyle(192),
    textStyle = toolbarButtonTextStyle(),
    id = "external-url-button"
  )
  let statusLabel = ui.label(
    "Idle.\nWaiting for events.",
    style = uiStyle([
      decl("width", px(192)),
      decl("height", px(82)),
      decl("padding", px(10)),
      decl("background-color", colorValue(rgb(0.045, 0.06, 0.085))),
      decl("border-radius", px(5))
    ]),
    textStyle = uiStyle([
      decl("width", px(172)),
      decl("font-size", px(12)),
      decl("line-height", px(18)),
      decl("white-space", keyword("pre-wrap")),
      decl("color", colorValue(rgb(0.56, 0.68, 0.80)))
    ])
  )
  ui.popParent()

  let content = ui.box(contentStyle(), parent = some(appRoot))
  let overview = buildOverview(ui, content, navigator)
  var projectRevision = 1
  var projectsRoot = buildProjects(ui, content, projectRevision)
  var settingsRevision = 1
  var settingsRoot = buildSettings(ui, content, settingsRevision)

  let transition = navigationTransition[DemoScreen](
    0.18,
    proc(context: NavigationTransitionContext[DemoScreen]) =
      case context.phase
      of ntpStarted, ntpAdvanced:
        ui.setNodeStyle(
          context.outgoingRoot.id,
          uiStyle([decl("opacity", number(1.0 - context.progress))]),
          priority = transitionStylePriority
        )
        ui.setNodeStyle(
          context.incomingRoot.id,
          uiStyle([decl("opacity", number(context.progress))]),
          priority = transitionStylePriority
        )
      of ntpCompleted, ntpCancelled:
        ui.setNodeStyle(
          context.outgoingRoot.id,
          uiStyle([decl("opacity", number(1.0))]),
          priority = transitionStylePriority
        )
        ui.setNodeStyle(
          context.incomingRoot.id,
          uiStyle([decl("opacity", number(1.0))]),
          priority = transitionStylePriority
        )
      statusLabel.setText(
        context.previous.destination.screenName() & " -> " &
          context.current.destination.screenName() & "\n" &
          $int(context.progress * 100) & "%"
      )
  )
  let host = initNavigationScreenHost(ui, navigator, some(transition))
  host.registerScreen(dsOverview, overview.root)
  host.registerScreen(dsProjects, projectsRoot)
  host.registerScreen(dsSettings, settingsRoot)

  let deepLinks = deepLinkCodec[DemoScreen](
    ["cbss-demo"],
    proc(url: string): Option[DemoScreen] =
      case url
      of "cbss-demo://overview": some(dsOverview)
      of "cbss-demo://projects": some(dsProjects)
      of "cbss-demo://settings": some(dsSettings)
      else: none(DemoScreen)
  )
  let externalUrls = sdl3ExternalUrlAdapter()
  var interaction = initInteractionState()
  var scheduler = initFrameScheduler()

  backButton.onClick = proc(event: DispatchResult): bool =
    if not navigator.back():
      statusLabel.setText("History boundary.\nCannot go back.")
    true
  forwardButton.onClick = proc(event: DispatchResult): bool =
    if not navigator.forward():
      statusLabel.setText("History boundary.\nCannot go forward.")
    true
  docsButton.onClick = proc(event: DispatchResult): bool =
    let opened = externalUrls.openExternalUrl(
      "https://github.com/puffball1567/clay-board-style-system"
    )
    statusLabel.setText("External URL:\n" & $opened.status)
    true
  overview.deepLinkButton.onClick = proc(event: DispatchResult): bool =
    let routed = navigator.navigateDeepLink(deepLinks, "cbss-demo://projects")
    statusLabel.setText("Deep link:\n" & $routed.status)
    true
  overview.rebuildButton.onClick = proc(event: DispatchResult): bool =
    inc settingsRevision
    let replacement = buildSettings(ui, content, settingsRevision)
    if host.replaceScreen(dsSettings, replacement, interaction):
      settingsRoot = replacement
      statusLabel.setText("Settings rebuilt.\nRevision " & $settingsRevision & ".")
    true

  navigator.addListener(proc(change: NavigationChange[DemoScreen]) =
    scheduler.markDirty(change.dirtyDomains)
  )

  doAssert host.sync(interaction)
  let launchResults = commandLineDeepLinkAdapter().drainDeepLinks(navigator, deepLinks)
  if launchResults.len > 0:
    discard host.sync(interaction)
    statusLabel.setText("Launch links:\n" & $launchResults.len & " argument(s).")

  var renderer = initSdl3Renderer(
    "Clay Board Style System - Native Navigation",
    viewportWidth,
    viewportHeight,
    resizable = true
  )
  defer:
    renderer.close()

  var viewport = renderer.windowSize()
  var frame = ui.buildFrame(viewport)
  var running = true
  let traceInput = getEnv("CBSS_NAVIGATION_DEMO_TRACE") == "1"
  let capturePath = getEnv("CBSS_NAVIGATION_DEMO_CAPTURE")
  let captureOnly = getEnv("CBSS_NAVIGATION_DEMO_CAPTURE_ONLY") == "1"
  var capturePending = capturePath.len > 0
  scheduler.markDirty({ddStyle, ddLayout, ddPaint, ddHit})

  proc dispatchFocused(event: InputEvent): bool =
    if interaction.focusedTarget.isNone:
      return false
    result = ui.events.handle(
      ui.tree,
      DispatchResult(
        target: interaction.focusedTarget,
        local: none(Vec2),
        event: event
      )
    )
    discard ui.reconcileFocus(interaction)

  proc handleEvent(event: Sdl3Event) =
    if traceInput:
      echo "[navigation-demo] event=", event.kind
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
      let nextCursor = cursorAt(frame.regions, point)
      if traceInput and nextCursor != renderer.activeCursor:
        echo "[navigation-demo] cursor=", nextCursor,
          " x=", point.x,
          " y=", point.y
      renderer.setCursor(nextCursor)
      var dispatches = interaction.processInput(
        ui.tree,
        frame.regions,
        pointerMoveEvent(point),
        ui.scroll
      )
      discard ui.events.handle(ui.tree, dispatches)
      scheduler.markDirty({ddStyle, ddPaint, ddHit})
    of sekPointerDown:
      let point = vec2(event.buttonX, event.buttonY)
      let hit = hitTest(frame.regions, point)
      let target = if hit.isSome: some(hit.get.node) else: none(NodeId)
      if traceInput:
        echo "[navigation-demo] pointer-down x=", point.x,
          " y=", point.y,
          " button=", event.button,
          " hit=", (if target.isSome: ui.tree.nodes[target.get.nodeIndex].id else: "<none>")
      if ui.closeOpenPopups(target):
        scheduler.markDirty({ddStyle, ddLayout, ddPaint, ddHit})
        return
      discard ui.normalizeFocus(interaction, target)
      var dispatches = interaction.processInput(
        ui.tree,
        frame.regions,
        pointerDownEvent(point, event.button),
        ui.scroll
      )
      let handled = ui.events.handle(ui.tree, dispatches)
      if traceInput:
        echo "[navigation-demo] pointer-down dispatches=", dispatches.len,
          " handled=", handled
      scheduler.markDirty({ddStyle, ddPaint, ddHit})
    of sekPointerUp:
      let point = vec2(event.buttonX, event.buttonY)
      var dispatches = interaction.processInput(
        ui.tree,
        frame.regions,
        pointerUpEvent(point, event.button),
        ui.scroll
      )
      let handled = ui.events.handle(ui.tree, dispatches)
      if traceInput:
        let hit = hitTest(frame.regions, point)
        echo "[navigation-demo] pointer-up x=", point.x,
          " y=", point.y,
          " button=", event.button,
          " hit=", (if hit.isSome: ui.tree.nodes[hit.get.node.nodeIndex].id else: "<none>"),
          " dispatches=", dispatches.len,
          " handled=", handled,
          " current=", navigator.currentDestination().get(dsOverview).screenName()
      discard ui.reconcileFocus(interaction)
      scheduler.markDirty({ddStyle, ddPaint, ddHit})
    of sekKeyDown:
      if event.key == "Tab" and not event.ctrl and not event.alt and not event.meta:
        discard ui.moveFocus(interaction, if event.shift: -1 else: 1)
      else:
        discard dispatchFocused(keyDownEvent(
          event.key,
          ctrlKey = event.ctrl,
          altKey = event.alt,
          shiftKey = event.shift,
          metaKey = event.meta
        ))
      scheduler.markDirty({ddStyle, ddPaint, ddHit})
    of sekKeyUp:
      discard dispatchFocused(keyUpEvent(
        event.key,
        ctrlKey = event.ctrl,
        altKey = event.alt,
        shiftKey = event.shift,
        metaKey = event.meta
      ))
    of sekWheel:
      let point = vec2(event.wheelMouseX, event.wheelMouseY)
      var dispatches = interaction.processInput(
        ui.tree,
        frame.regions,
        wheelEvent(point, event.scrollDelta()),
        ui.scroll
      )
      discard ui.events.handle(ui.tree, dispatches)
      scheduler.markDirty({ddPaint, ddHit})
    else:
      discard

  var queuedEvent = none(Sdl3Event)
  while running:
    var event: Sdl3Event
    if queuedEvent.isSome:
      handleEvent(queuedEvent.get)
      queuedEvent = none(Sdl3Event)
    while running and renderer.pollEvent(event):
      handleEvent(event)
    if not running:
      break

    let now = epochTime()
    if scheduler.deadlineDue(now):
      scheduler.clearDeadline()
      discard host.advanceTransition(scheduler, now)
    discard host.sync(interaction, scheduler, now)
    scheduler.markDirty(ui.consumeInvalidation().domains)

    let dirty = scheduler.consumeDirty()
    if dirty != {}:
      frame = ui.buildFrame(viewport)
      if capturePending:
        renderer.requestFrameCapture()
      renderer.render(
        frame.commands,
        cosmic,
        fonts,
        rgb(0.035, 0.047, 0.067)
      )
      if capturePending and renderer.capturedFrame().isSome:
        saveCapturedFrame(renderer.capturedFrame().get, capturePath)
        capturePending = false
        if captureOnly:
          running = false

    if not running:
      break

    let timeoutMs = scheduler.waitTimeoutMs(epochTime())
    let received =
      if timeoutMs < 0:
        renderer.waitEvent(event)
      else:
        renderer.waitEventTimeout(event, timeoutMs)
    if received:
      queuedEvent = some(event)

when isMainModule:
  main()
