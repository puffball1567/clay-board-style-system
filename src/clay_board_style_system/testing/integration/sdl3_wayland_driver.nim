import std/[math, options, os, strutils]

import ../../backends/sdl3/renderer
import ../../backends/sdl3/text_event_guard
import ../../core/[color, computed_style, diagnostics, geometry, node, selector, style_resolver, style_value]
import ../../generated/default_properties
import ../../hit/hit_test
import ../../input/events
import ../../layout/layout
import ../../layout/scroll_state
import ../../paint/[paint, paint_command]
import ../../runtime/ui_root
import ../../text/[font_registry, text_engine]
import ../../vendor/sdl3
import ../test_driver

export renderer

## Testing-only SDL3 Wayland driver.
##
## Security boundary:
## - not exported by the production facade;
## - opens windows only when explicitly constructed by tests;
## - writes artifacts only to caller-provided paths;
## - never executes artifact paths or external commands.
##
type
  CbssSdl3Frame* = object
    diagnostics*: Diagnostics
    styles*: ResolvedTree
    layout*: LayoutResult
    commands*: seq[PaintCommand]
    regions*: seq[HitRegion]

  Sdl3WaylandProbe* = object
    sessionType*: string
    waylandDisplay*: string
    sdlVideoDriver*: string
    canUseWayland*: bool
    message*: string

  Sdl3CompositionCandidates* = object
    candidates*: seq[string]
    selectedCandidate*: int
    horizontalCandidates*: bool

  Sdl3IntegrationCapabilities* = object
    backendName*: string
    videoDriver*: string
    realWindow*: bool
    canOpenWindow*: bool
    semanticDriver*: bool
    eventDispatch*: bool
    cursorState*: bool
    textInputArea*: bool
    compositionCandidates*: bool
    clipboard*: bool
    screenshotPpm*: bool
    screenshotDiff*: bool
    scenarioArtifacts*: bool
    debugBundle*: bool

  Sdl3WaylandDriver* = ref object
    headless*: CbssTestDriver
    app*: Sdl3Renderer
    frame*: CbssSdl3Frame
    title*: string
    previousSdlVideoDriver: string
    hadPreviousSdlVideoDriver: bool
    actionLog*: seq[string]
    lastEvents*: seq[Sdl3Event]
    lastCompositionCandidates*: Option[Sdl3CompositionCandidates]
    artifacts*: seq[string]
    clipboardSnapshotValid: bool

  Sdl3WaylandScenario* = object
    name*: string
    driver*: Sdl3WaylandDriver
    summary*: CbssTestRunSummary
    artifactDir*: string
    artifacts*: seq[string]

  CbssPpmImage* = object
    width*: int
    height*: int
    pixels*: seq[uint8]

  CbssScreenshotDiff* = object
    matches*: bool
    width*: int
    height*: int
    comparedPixels*: int
    changedPixels*: int
    changedRatio*: float
    maxChannelDelta*: int
    message*: string

const cbssSdl3ActionLogLimit = 80

proc safeSdl3ArtifactName(name: string): string =
  for ch in name:
    if ch in {'a'..'z'} or ch in {'A'..'Z'} or ch in {'0'..'9'} or ch in {'-', '_'}:
      result.add ch
    elif result.len == 0 or result[^1] != '_':
      result.add '_'
  result = result.strip(chars = {'_'})
  if result.len == 0:
    result = "artifact"

proc waylandProbe*(): Sdl3WaylandProbe =
  result.sessionType = getEnv("XDG_SESSION_TYPE")
  result.waylandDisplay = getEnv("WAYLAND_DISPLAY")
  result.sdlVideoDriver = getEnv("SDL_VIDEODRIVER")
  result.canUseWayland =
    result.sessionType.toLowerAscii() == "wayland" or
    result.waylandDisplay.len > 0 or
    result.sdlVideoDriver.toLowerAscii() == "wayland"
  if result.canUseWayland:
    result.message = "Wayland session appears available"
  else:
    result.message = "Wayland session was not detected; set WAYLAND_DISPLAY or run from a Wayland desktop"

proc requireWayland*(probe: Sdl3WaylandProbe) =
  if not probe.canUseWayland:
    raise newException(CatchableError, probe.message)

proc currentSdlVideoDriver*(): string =
  let raw = SDL3.getCurrentVideoDriver()
  if raw.isNil:
    ""
  else:
    $raw

proc capabilitiesReport*(capabilities: Sdl3IntegrationCapabilities): string =
  @[
    "backend: " & capabilities.backendName,
    "video-driver: " & capabilities.videoDriver,
    "real-window: " & $capabilities.realWindow,
    "can-open-window: " & $capabilities.canOpenWindow,
    "semantic-driver: " & $capabilities.semanticDriver,
    "event-dispatch: " & $capabilities.eventDispatch,
    "cursor-state: " & $capabilities.cursorState,
    "text-input-area: " & $capabilities.textInputArea,
    "composition-candidates: " & $capabilities.compositionCandidates,
    "clipboard: " & $capabilities.clipboard,
    "screenshot-ppm: " & $capabilities.screenshotPpm,
    "screenshot-diff: " & $capabilities.screenshotDiff,
    "scenario-artifacts: " & $capabilities.scenarioArtifacts,
    "debug-bundle: " & $capabilities.debugBundle
  ].join("\n")

proc capabilities*(probe: Sdl3WaylandProbe): Sdl3IntegrationCapabilities =
  Sdl3IntegrationCapabilities(
    backendName: "sdl3-wayland",
    videoDriver:
      if probe.sdlVideoDriver.len > 0: probe.sdlVideoDriver
      elif probe.canUseWayland: "wayland"
      else: "",
    realWindow: false,
    canOpenWindow: probe.canUseWayland,
    semanticDriver: true,
    eventDispatch: true,
    cursorState: true,
    textInputArea: true,
    compositionCandidates: true,
    clipboard: true,
    screenshotPpm: true,
    screenshotDiff: true,
    scenarioArtifacts: true,
    debugBundle: true
  )

proc capabilitiesReport*(probe: Sdl3WaylandProbe): string =
  capabilitiesReport(probe.capabilities())

proc poll*(driver: Sdl3WaylandDriver; maxEvents = 64): int

proc rememberAction(driver: Sdl3WaylandDriver; action: string) =
  driver.actionLog.add action
  while driver.actionLog.len > cbssSdl3ActionLogLimit:
    driver.actionLog.delete(0)

proc actionSnapshot*(driver: Sdl3WaylandDriver): string =
  if driver.actionLog.len == 0:
    return ""
  var lines: seq[string]
  for index, action in driver.actionLog:
    lines.add $index & ": " & action
  lines.join("\n")

proc eventSnapshot*(driver: Sdl3WaylandDriver): string =
  if driver.lastEvents.len == 0:
    result = ""
  else:
    var lines: seq[string]
    for index, event in driver.lastEvents:
      lines.add $index & ": " & $event.kind & " @" & $event.timestamp
    result = lines.join("\n")
  if driver.lastCompositionCandidates.isSome:
    let candidates = driver.lastCompositionCandidates.get
    let suffix = "composition-candidates: selected=" & $candidates.selectedCandidate &
      " horizontal=" & $candidates.horizontalCandidates &
      " candidates=" & candidates.candidates.join("|")
    if result.len == 0:
      result = suffix
    else:
      result.add "\n" & suffix

proc capabilities*(driver: Sdl3WaylandDriver): Sdl3IntegrationCapabilities =
  let probe = waylandProbe()
  let hasWindow = not driver.app.window.isNil
  let activeDriver = currentSdlVideoDriver()
  Sdl3IntegrationCapabilities(
    backendName: "sdl3-wayland",
    videoDriver:
      if activeDriver.len > 0: activeDriver
      elif hasWindow: "wayland"
      else: "",
    realWindow: hasWindow,
    canOpenWindow: probe.canUseWayland,
    semanticDriver: not driver.headless.isNil,
    eventDispatch: true,
    cursorState: true,
    textInputArea: true,
    compositionCandidates: true,
    clipboard: true,
    screenshotPpm: true,
    screenshotDiff: true,
    scenarioArtifacts: true,
    debugBundle: true
  )

proc capabilitiesReport*(driver: Sdl3WaylandDriver): string =
  capabilitiesReport(driver.capabilities())

proc compositionCandidates*(driver: Sdl3WaylandDriver): Option[Sdl3CompositionCandidates] =
  driver.lastCompositionCandidates

proc clearCompositionCandidates*(driver: Sdl3WaylandDriver) =
  driver.rememberAction("composition candidates clear")
  driver.lastCompositionCandidates = none(Sdl3CompositionCandidates)

proc expectCompositionCandidates*(
    driver: Sdl3WaylandDriver;
    expected: openArray[string];
    selectedCandidate = -1
): tuple[ok: bool, message: string] =
  let actual = driver.lastCompositionCandidates
  if actual.isNone:
    return (false, "composition candidates missing")
  let candidates = actual.get
  if candidates.candidates != @expected:
    return (false, "composition candidates mismatch: expected " &
      (@expected).join("|") & ", got " & candidates.candidates.join("|"))
  if selectedCandidate >= 0 and candidates.selectedCandidate != selectedCandidate:
    return (false, "composition selected candidate mismatch: expected " &
      $selectedCandidate & ", got " & $candidates.selectedCandidate)
  (true, "composition candidates matched")

proc buildFrame(
    ui: UiRoot;
    viewport: Size;
    textEngine: TextEngine;
    fonts: FontRegistry
): CbssSdl3Frame =
  result.diagnostics = Diagnostics()
  result.styles = resolveTreeStyles(
    ui.tree,
    ui.styleSheets(),
    defaultProperties(),
    result.diagnostics,
    viewportSize = some(viewport)
  )
  result.layout = computeLayout(ui.tree, result.styles, viewport, textEngine, fonts)
  ui.scroll.syncScrollState(ui.tree, result.styles, result.layout)
  result.commands = buildPaintCommands(ui.tree, result.styles, result.layout, ui.scroll)
  result.regions = buildHitRegions(ui.tree, result.layout, result.styles, ui.scroll)

proc refresh*(driver: Sdl3WaylandDriver) =
  driver.headless.refresh()
  driver.frame = buildFrame(
    driver.headless.ui,
    driver.headless.viewport,
    driver.headless.ui.textEngine,
    driver.headless.ui.fonts
  )

proc render*(driver: Sdl3WaylandDriver; clearColor = rgb(1, 1, 1)) =
  driver.rememberAction("render")
  driver.refresh()
  driver.app.render(driver.frame.commands, clearColor)

proc cursorAt*(driver: Sdl3WaylandDriver; point: Vec2): CursorKind =
  cursorAt(driver.frame.regions, point)

proc currentCursor*(driver: Sdl3WaylandDriver): CursorKind =
  driver.app.activeCursor()

proc updateCursor*(driver: Sdl3WaylandDriver; point: Vec2): CursorKind =
  result = driver.cursorAt(point)
  driver.app.setCursor(result)
  driver.rememberAction("cursor @" & $point.x & "," & $point.y & " -> " & $result)

proc descendantWithGroup(driver: Sdl3WaylandDriver; root: NodeId; group: string): Option[NodeId] =
  if not driver.headless.ui.tree.isValid(root):
    return none(NodeId)
  for child in driver.headless.ui.tree.nodes[root.nodeIndex].children:
    if driver.headless.ui.tree.nodes[child.nodeIndex].hasGroup(group):
      return some(child)
    let nested = driver.descendantWithGroup(child, group)
    if nested.isSome:
      return nested
  none(NodeId)

proc componentLengthForNode(driver: Sdl3WaylandDriver; nodeId: NodeId; property: string): Option[float32] =
  if not driver.headless.ui.tree.isValid(nodeId):
    return none(float32)
  let node = driver.headless.ui.tree.nodes[nodeId.nodeIndex]
  for sheet in driver.headless.ui.componentStyles:
    for rule in sheet.rules:
      if not rule.selector.matches(node, some(nodeId)):
        continue
      for declaration in rule.declarations:
        if declaration.property != property or declaration.operation.value.isNone:
          continue
        let value = declaration.operation.value.get
        if value.kind == svLength and value.length.kind == ukPx:
          result = some(value.length.value)

proc focusedTextInputCaretArea(driver: Sdl3WaylandDriver; focused: NodeId): Option[Rect] =
  let parentRect = driver.headless.rectFor(focused)
  if parentRect.isNone:
    return none(Rect)
  for group in ["text-input-caret", "textarea-caret"]:
    let caretNode = driver.descendantWithGroup(focused, group)
    if caretNode.isSome:
      let style = driver.headless.styles.styles[caretNode.get.nodeIndex]
      let width =
        if driver.componentLengthForNode(caretNode.get, "width").isSome:
          driver.componentLengthForNode(caretNode.get, "width").get
        elif style.layout.width.isSome: style.layout.width.get
        else:
          let caretRect = driver.headless.rectFor(caretNode.get)
          if caretRect.isSome: caretRect.get.w else: 1.0'f32
      let height =
        if driver.componentLengthForNode(caretNode.get, "height").isSome:
          driver.componentLengthForNode(caretNode.get, "height").get
        elif style.layout.height.isSome: style.layout.height.get
        else:
          let caretRect = driver.headless.rectFor(caretNode.get)
          if caretRect.isSome: caretRect.get.h else: 1.0'f32
      if width > 0 and height > 0:
        let left = driver.componentLengthForNode(caretNode.get, "left")
        let top = driver.componentLengthForNode(caretNode.get, "top")
        return some(rect(
          parentRect.get.x + (
            if left.isSome: left.get
            elif style.layout.inset.left.isSome: style.layout.inset.left.get
            else: 0.0'f32
          ),
          parentRect.get.y + (
            if top.isSome: top.get
            elif style.layout.inset.top.isSome: style.layout.inset.top.get
            else: 0.0'f32
          ),
          width,
          height
        ))
  none(Rect)

proc syncTextInputArea*(driver: Sdl3WaylandDriver): bool =
  driver.headless.refresh()
  let focused = driver.headless.focusedTarget()
  if focused.isNone:
    driver.rememberAction("textInputArea clear")
    return driver.app.setTextInputArea(none(Rect))
  let caretArea = driver.focusedTextInputCaretArea(focused.get)
  if caretArea.isSome:
    driver.rememberAction("textInputArea caret " & $caretArea.get.x & "," & $caretArea.get.y &
      " " & $caretArea.get.w & "x" & $caretArea.get.h)
    return driver.app.setTextInputArea(caretArea, 0)
  let area = driver.headless.rectFor(focused.get)
  if area.isNone:
    driver.rememberAction("textInputArea clear missing rect")
    return driver.app.setTextInputArea(none(Rect))
  driver.rememberAction("textInputArea " & $area.get.x & "," & $area.get.y &
    " " & $area.get.w & "x" & $area.get.h)
  driver.app.setTextInputArea(area, 0)

proc textInputArea*(driver: Sdl3WaylandDriver): Option[Rect] =
  driver.app.textInputArea()

proc textInputActive*(driver: Sdl3WaylandDriver): bool =
  driver.app.textInputActive()

proc textInputCursor*(driver: Sdl3WaylandDriver): int =
  driver.app.textInputCursor()

proc setClipboardText*(driver: Sdl3WaylandDriver; text: string): bool =
  driver.rememberAction("clipboard set len=" & $text.len)
  driver.headless.clipboard = text
  if driver.app.window.isNil:
    driver.clipboardSnapshotValid = true
    result = true
  else:
    result = setClipboardText(text)
    driver.clipboardSnapshotValid = result

proc clipboardText*(driver: Sdl3WaylandDriver): string =
  driver.rememberAction("clipboard get")
  let platformText =
    if driver.app.window.isNil:
      driver.headless.clipboard
    else:
      clipboardText()
  # A synthetic Wayland test window is not guaranteed to receive an input-seat
  # focus serial. Keep a successful local write usable when the compositor
  # consequently exposes an empty clipboard to the unfocused test process.
  result =
    if platformText.len > 0 or not driver.clipboardSnapshotValid:
      platformText
    else:
      driver.headless.clipboard
  driver.headless.clipboard = result

proc copyFocused*(driver: Sdl3WaylandDriver): bool =
  driver.rememberAction("copyFocused")
  result = driver.headless.copy()
  if result:
    discard driver.setClipboardText(driver.headless.clipboard)
  discard driver.syncTextInputArea()

proc cutFocused*(driver: Sdl3WaylandDriver): bool =
  driver.rememberAction("cutFocused")
  result = driver.headless.cut()
  if result:
    discard driver.setClipboardText(driver.headless.clipboard)
  discard driver.syncTextInputArea()
  if not driver.app.renderer.isNil:
    driver.render()

proc pasteFocused*(driver: Sdl3WaylandDriver): bool =
  driver.rememberAction("pasteFocused")
  let text = driver.clipboardText()
  result = driver.headless.paste(text)
  discard driver.syncTextInputArea()
  if not driver.app.renderer.isNil:
    driver.render()

proc finishSdlDispatch(driver: Sdl3WaylandDriver; renderAfter: bool) =
  discard driver.syncTextInputArea()
  if renderAfter and not driver.app.renderer.isNil:
    driver.render()
  else:
    driver.refresh()

proc dispatchSdlEvent*(
    driver: Sdl3WaylandDriver;
    event: Sdl3Event;
    renderAfter = true
): bool =
  driver.rememberAction("dispatch " & $event.kind)
  case event.kind
  of sekQuit:
    result = true
  of sekExpose:
    result = true
  of sekResize:
    driver.headless.setViewport(size(event.width.float32, event.height.float32))
    result = true
  of sekFocus, sekBlur:
    result = true
  of sekPointerMove:
    let point = vec2(event.x, event.y)
    discard driver.updateCursor(point)
    let hit = driver.headless.hitAt(point).isSome
    let input = event.pointerInputEvent()
    result = (input.isSome and driver.headless.sendPointer(input.get)) or hit
  of sekPointerDown:
    let point = vec2(event.buttonX, event.buttonY)
    let hit = driver.headless.hitAt(point).isSome
    let input = event.pointerInputEvent()
    result = (input.isSome and driver.headless.sendPointer(input.get)) or hit
  of sekPointerUp:
    let point = vec2(event.buttonX, event.buttonY)
    let hit = driver.headless.hitAt(point).isSome
    let input = event.pointerInputEvent()
    result = (input.isSome and driver.headless.sendPointer(input.get)) or hit
  of sekKeyDown:
    if event.isPrintableTextKey:
      # SDL_TEXT_INPUT is authoritative for layout-dependent printable text.
      result = driver.headless.focusedTarget().isSome
    else:
      result = driver.headless.press(
        event.key,
        ctrlKey = event.ctrl,
        altKey = event.alt,
        shiftKey = event.shift,
        metaKey = event.meta
      )
  of sekKeyUp:
    result = driver.headless.sendFocused(
      keyUpEvent(
        event.key,
        ctrlKey = event.ctrl,
        altKey = event.alt,
        shiftKey = event.shift,
        metaKey = event.meta
      )
    )
  of sekTextInput:
    result = driver.headless.sendFocused(textInputEvent(event.text))
  of sekCompositionStart:
    result = driver.headless.sendFocused(compositionStartEvent(event.text))
  of sekCompositionUpdate:
    result = driver.headless.sendFocused(compositionUpdateEvent(event.text))
  of sekCompositionEnd:
    result = driver.headless.sendFocused(compositionEndEvent(event.text))
  of sekCompositionCandidates:
    driver.lastCompositionCandidates = some(Sdl3CompositionCandidates(
      candidates: event.candidates,
      selectedCandidate: event.selectedCandidate,
      horizontalCandidates: event.horizontalCandidates
    ))
    result = true
  of sekWheel:
    let point = vec2(event.wheelMouseX, event.wheelMouseY)
    let hit = driver.headless.hitAt(point).isSome
    result = driver.headless.sendPointer(
      wheelEvent(
        point,
        event.scrollDelta()
      )
    ) or hit
  of sekTouchStart:
    let input = event.pointerInputEvent()
    result = input.isSome and driver.headless.sendPointer(input.get)
  of sekTouchMove:
    let input = event.pointerInputEvent()
    result = input.isSome and driver.headless.sendPointer(input.get)
  of sekTouchEnd:
    let input = event.pointerInputEvent()
    result = input.isSome and driver.headless.sendPointer(input.get)
  of sekTouchCancel:
    let input = event.pointerInputEvent()
    result = input.isSome and driver.headless.sendPointer(input.get)
  of sekPenProximityIn, sekPenProximityOut,
     sekPenButtonDown, sekPenButtonUp:
    let input = event.pointerInputEvent()
    result = input.isSome and driver.headless.sendPointer(input.get)
  of sekStreamWake:
    # Stream ownership is application-specific. The integration driver keeps
    # the wake observable without guessing which typed binding should pump.
    result = false
  driver.finishSdlDispatch(renderAfter)

proc pollAndDispatch*(driver: Sdl3WaylandDriver; maxEvents = 64; renderAfter = true): int =
  discard driver.poll(maxEvents)
  for event in driver.lastEvents:
    discard driver.dispatchSdlEvent(event, renderAfter = false)
    inc result
  if renderAfter and not driver.app.renderer.isNil:
    driver.render()

proc initSdl3WaylandDriver*(
    ui: UiRoot;
    viewport: Size;
    title = "CBSS SDL3 Wayland Test";
    requireWaylandSession = true;
    resizable = false
): Sdl3WaylandDriver =
  let probe = waylandProbe()
  if requireWaylandSession:
    probe.requireWayland()
  let previousVideoDriver = getEnv("SDL_VIDEODRIVER")
  let hadPreviousVideoDriver = existsEnv("SDL_VIDEODRIVER")
  putEnv("SDL_VIDEODRIVER", "wayland")
  result = Sdl3WaylandDriver(
    headless: initCbssTestDriver(ui, viewport),
    title: title,
    previousSdlVideoDriver: previousVideoDriver,
    hadPreviousSdlVideoDriver: hadPreviousVideoDriver,
    actionLog: @[],
    lastEvents: @[],
    lastCompositionCandidates: none(Sdl3CompositionCandidates),
    artifacts: @[],
    clipboardSnapshotValid: false
  )
  result.app = initSdl3Renderer(title, int(viewport.w), int(viewport.h), resizable = resizable)
  result.refresh()
  result.rememberAction("init wayland title=" & title & " viewport=" & $viewport.w & "x" & $viewport.h)

proc initSdl3WaylandDriver*(
    builder: proc(): UiRoot {.closure.};
    viewport: Size;
    title = "CBSS SDL3 Wayland Test";
    requireWaylandSession = true;
    resizable = false
): Sdl3WaylandDriver =
  initSdl3WaylandDriver(builder(), viewport, title, requireWaylandSession, resizable)

proc close*(driver: var Sdl3WaylandDriver) =
  if driver.isNil:
    return
  driver.rememberAction("close")
  driver.app.close()
  if driver.hadPreviousSdlVideoDriver:
    putEnv("SDL_VIDEODRIVER", driver.previousSdlVideoDriver)
  else:
    delEnv("SDL_VIDEODRIVER")

proc poll*(driver: Sdl3WaylandDriver; maxEvents = 64): int =
  driver.rememberAction("poll max=" & $maxEvents)
  driver.lastEvents.setLen(0)
  var event: Sdl3Event
  while result < maxEvents and driver.app.pollEvent(event):
    driver.lastEvents.add event
    if event.kind == sekCompositionCandidates:
      driver.lastCompositionCandidates = some(Sdl3CompositionCandidates(
        candidates: event.candidates,
        selectedCandidate: event.selectedCandidate,
        horizontalCandidates: event.horizontalCandidates
      ))
    inc result

proc hold*(driver: Sdl3WaylandDriver; ms: int) =
  let duration = max(0, ms)
  if duration <= 0:
    return
  driver.rememberAction("hold " & $duration & "ms")
  var elapsed = 0
  while elapsed < duration:
    discard driver.poll(maxEvents = 32)
    delay(min(16, duration - elapsed))
    elapsed += min(16, duration - elapsed)

proc holdFromEnv*(driver: Sdl3WaylandDriver; envName = "CBSS_WAYLAND_HOLD_MS") =
  let value = getEnv(envName)
  if value.len == 0:
    return
  try:
    driver.hold(parseInt(value))
  except ValueError:
    driver.rememberAction("hold skipped invalid " & envName & "=" & value)

proc debugBundle*(driver: Sdl3WaylandDriver): string =
  var lines = @[
    "sdl3-wayland:",
    "title: " & driver.title,
    "probe: " & waylandProbe().message,
    "capabilities:",
    driver.capabilitiesReport(),
    "viewport: " & $driver.headless.viewport.w & "x" & $driver.headless.viewport.h,
    "headless:",
    driver.headless.debugBundle(),
    "sdl-actions:"
  ]
  let actions = driver.actionSnapshot()
  if actions.len == 0:
    lines.add "<none>"
  else:
    lines.add actions
  lines.add "sdl-events:"
  let events = driver.eventSnapshot()
  if events.len == 0:
    lines.add "<none>"
  else:
    lines.add events
  lines.join("\n")

proc saveScreenshotPpm*(driver: Sdl3WaylandDriver; path: string): bool

proc saveDebugBundle*(driver: Sdl3WaylandDriver; path: string) =
  let directory = parentDir(path)
  if directory.len > 0:
    createDir(directory)
  writeFile(path, driver.debugBundle())
  driver.artifacts.add path

proc saveArtifactManifest*(driver: Sdl3WaylandDriver; path: string) =
  let directory = parentDir(path)
  if directory.len > 0:
    createDir(directory)
  var lines = @[
    "cbss-integration-artifacts:",
    "title: " & driver.title,
    "capabilities:",
    driver.capabilitiesReport(),
    "artifacts:"
  ]
  if driver.artifacts.len == 0:
    lines.add "- <none>"
  else:
    for artifact in driver.artifacts:
      lines.add "- " & artifact
  lines.add "actions:"
  let actions = driver.actionSnapshot()
  if actions.len == 0:
    lines.add "<none>"
  else:
    lines.add actions
  lines.add "events:"
  let events = driver.eventSnapshot()
  if events.len == 0:
    lines.add "<none>"
  else:
    lines.add events
  writeFile(path, lines.join("\n") & "\n")
  driver.artifacts.add path

proc initSdl3WaylandScenario*(
    name: string;
    driver: Sdl3WaylandDriver;
    artifactDir = ""
): Sdl3WaylandScenario =
  Sdl3WaylandScenario(
    name: name,
    driver: driver,
    summary: initCbssTestRunSummary(),
    artifactDir: artifactDir,
    artifacts: @[]
  )

proc scenarioArtifactBase(scenario: Sdl3WaylandScenario; stepName: string): string =
  let index = scenario.summary.checks.len + 1
  scenario.artifactDir / ($index & "_" & safeSdl3ArtifactName(stepName))

proc saveScenarioArtifact(
    scenario: var Sdl3WaylandScenario;
    stepName: string;
    message: string
) =
  if scenario.artifactDir.len == 0:
    return
  let base = scenario.scenarioArtifactBase(stepName)
  let debugPath = base & ".txt"
  let screenshotPath = base & ".ppm"
  let directory = parentDir(debugPath)
  if directory.len > 0:
    createDir(directory)
  writeFile(debugPath, "scenario: " & scenario.name & "\nstep: " & stepName &
    "\nmessage: " & message & "\n\n" & scenario.driver.debugBundle())
  scenario.artifacts.add debugPath
  scenario.driver.artifacts.add debugPath
  if not scenario.driver.app.renderer.isNil and scenario.driver.saveScreenshotPpm(screenshotPath):
    scenario.artifacts.add screenshotPath

proc step*(
    scenario: var Sdl3WaylandScenario;
    name: string;
    action: proc(): bool {.closure.}
): bool =
  scenario.driver.rememberAction("scenario step " & name)
  var message = "step passed"
  try:
    result = action()
    if not scenario.driver.app.renderer.isNil:
      scenario.driver.render()
    if not result:
      message = "step returned false"
  except CatchableError as error:
    result = false
    message = error.msg
  discard scenario.summary.record(name, result, message)
  if not result:
    scenario.saveScenarioArtifact(name, message)

proc expect*(
    scenario: var Sdl3WaylandScenario;
    name: string;
    check: tuple[ok: bool, message: string]
): bool =
  result = scenario.summary.record(name, check)
  if not result:
    scenario.saveScenarioArtifact(name, check.message)

proc ok*(scenario: Sdl3WaylandScenario): bool =
  scenario.summary.ok

proc report*(scenario: Sdl3WaylandScenario): string =
  var text = "sdl3-wayland scenario: " & scenario.name & "\n" & scenario.summary.report()
  if scenario.artifacts.len > 0:
    text.add "\nartifacts:"
    for path in scenario.artifacts:
      text.add "\n- " & path
  text

proc saveScreenshotPpm*(driver: Sdl3WaylandDriver; path: string): bool =
  driver.rememberAction("screenshot " & path)
  driver.app.requestFrameCapture()
  driver.render()
  let captured = driver.app.capturedFrame()
  if captured.isNone:
    return false
  let frame = captured.get
  let directory = parentDir(path)
  if directory.len > 0:
    createDir(directory)

  var data = "P3\n" & $frame.width & " " & $frame.height & "\n255\n"
  for y in 0 ..< frame.height:
    for x in 0 ..< frame.width:
      let offset = (y * frame.width + x) * 3
      data.add $frame.pixels[offset] & " " & $frame.pixels[offset + 1] & " " & $frame.pixels[offset + 2]
      if x + 1 < frame.width:
        data.add " "
    data.add "\n"
  writeFile(path, data)
  driver.artifacts.add path
  true

proc loadPpm*(path: string): CbssPpmImage =
  if not fileExists(path):
    raise newException(ValueError, "PPM file does not exist: " & path)
  let tokens = readFile(path).splitWhitespace()
  if tokens.len < 4 or tokens[0] != "P3":
    raise newException(ValueError, "Unsupported PPM file; expected ASCII P3: " & path)
  result.width = parseInt(tokens[1])
  result.height = parseInt(tokens[2])
  let maxValue = parseInt(tokens[3])
  if result.width <= 0 or result.height <= 0:
    raise newException(ValueError, "Invalid PPM dimensions: " & path)
  if maxValue <= 0 or maxValue > 255:
    raise newException(ValueError, "Unsupported PPM max value: " & $maxValue)
  let expectedValues = result.width * result.height * 3
  if tokens.len < 4 + expectedValues:
    raise newException(ValueError, "PPM pixel data is shorter than expected: " & path)
  result.pixels = newSeq[uint8](expectedValues)
  for index in 0 ..< expectedValues:
    let value = parseInt(tokens[4 + index])
    if value < 0 or value > maxValue:
      raise newException(ValueError, "PPM pixel value out of range: " & path)
    result.pixels[index] = uint8(int(round(value.float * 255.0 / maxValue.float)))

proc savePpm*(image: CbssPpmImage; path: string) =
  if image.width <= 0 or image.height <= 0:
    raise newException(ValueError, "Invalid PPM dimensions")
  if image.pixels.len != image.width * image.height * 3:
    raise newException(ValueError, "PPM pixel data length does not match dimensions")
  let directory = parentDir(path)
  if directory.len > 0:
    createDir(directory)
  var data = "P3\n" & $image.width & " " & $image.height & "\n255\n"
  for y in 0 ..< image.height:
    for x in 0 ..< image.width:
      let offset = (y * image.width + x) * 3
      data.add $image.pixels[offset] & " " & $image.pixels[offset + 1] & " " & $image.pixels[offset + 2]
      if x + 1 < image.width:
        data.add " "
    data.add "\n"
  writeFile(path, data)

proc diffScreenshotPpm*(
    expectedPath, actualPath: string;
    maxChangedRatio = 0.0;
    maxChannelDelta = 0;
    diffPath = ""
): CbssScreenshotDiff =
  let expected = loadPpm(expectedPath)
  let actual = loadPpm(actualPath)
  if expected.width != actual.width or expected.height != actual.height:
    return CbssScreenshotDiff(
      matches: false,
      width: actual.width,
      height: actual.height,
      message: "screenshot size mismatch: expected " & $expected.width & "x" & $expected.height &
        ", got " & $actual.width & "x" & $actual.height
    )

  result.width = actual.width
  result.height = actual.height
  result.comparedPixels = actual.width * actual.height
  var diffImage = CbssPpmImage(width: actual.width, height: actual.height, pixels: newSeq[uint8](actual.pixels.len))
  for pixel in 0 ..< result.comparedPixels:
    let offset = pixel * 3
    let dr = abs(int(expected.pixels[offset]) - int(actual.pixels[offset]))
    let dg = abs(int(expected.pixels[offset + 1]) - int(actual.pixels[offset + 1]))
    let db = abs(int(expected.pixels[offset + 2]) - int(actual.pixels[offset + 2]))
    let delta = max(dr, max(dg, db))
    result.maxChannelDelta = max(result.maxChannelDelta, delta)
    if delta > maxChannelDelta:
      inc result.changedPixels
      diffImage.pixels[offset] = 255
      diffImage.pixels[offset + 1] = 0
      diffImage.pixels[offset + 2] = 0
    else:
      diffImage.pixels[offset] = uint8(int(actual.pixels[offset]) div 4)
      diffImage.pixels[offset + 1] = uint8(int(actual.pixels[offset + 1]) div 4)
      diffImage.pixels[offset + 2] = uint8(int(actual.pixels[offset + 2]) div 4)
  if result.comparedPixels > 0:
    result.changedRatio = result.changedPixels.float / result.comparedPixels.float
  result.matches = result.changedRatio <= maxChangedRatio
  result.message =
    if result.matches:
      "screenshot matched; changedPixels=" & $result.changedPixels &
        " ratio=" & $result.changedRatio & " maxDelta=" & $result.maxChannelDelta
    else:
      "screenshot mismatch; changedPixels=" & $result.changedPixels &
        " ratio=" & $result.changedRatio & " maxDelta=" & $result.maxChannelDelta
  if diffPath.len > 0 and not result.matches:
    diffImage.savePpm(diffPath)

proc expectScreenshotMatches*(
    driver: Sdl3WaylandDriver;
    expectedPath, actualPath: string;
    maxChangedRatio = 0.0;
    maxChannelDelta = 0;
    diffPath = ""
): tuple[ok: bool, message: string] =
  let diff = diffScreenshotPpm(
    expectedPath,
    actualPath,
    maxChangedRatio = maxChangedRatio,
    maxChannelDelta = maxChannelDelta,
    diffPath = diffPath
  )
  if diffPath.len > 0 and fileExists(diffPath):
    driver.artifacts.add diffPath
  (diff.matches, diff.message)

proc expectScreenshotPpm*(driver: Sdl3WaylandDriver; path: string): tuple[ok: bool, message: string] =
  if not fileExists(path):
    return (false, "screenshot file does not exist: " & path)
  let content = readFile(path)
  if not content.startsWith("P3\n"):
    return (false, "screenshot file is not an ASCII PPM: " & path)
  if content.len < 32:
    return (false, "screenshot file is too small: " & path)
  (true, "screenshot PPM exists: " & path)

proc click*(driver: Sdl3WaylandDriver; query: CbssQuery): bool =
  driver.rememberAction("click " & query.describe())
  result = driver.headless.click(query)
  discard driver.syncTextInputArea()
  driver.render()

proc typeText*(driver: Sdl3WaylandDriver; text: string): bool =
  driver.rememberAction("typeText len=" & $text.len)
  result = driver.headless.typeText(text)
  discard driver.syncTextInputArea()
  driver.render()

proc press*(driver: Sdl3WaylandDriver; key: string; ctrlKey = false; altKey = false; shiftKey = false; metaKey = false): bool =
  driver.rememberAction("press " & key)
  result = driver.headless.press(key, ctrlKey = ctrlKey, altKey = altKey, shiftKey = shiftKey, metaKey = metaKey)
  discard driver.syncTextInputArea()
  driver.render()

proc expectRendered*(driver: Sdl3WaylandDriver): tuple[ok: bool, message: string] =
  if driver.frame.commands.len == 0:
    (false, "frame produced no paint commands")
  elif driver.frame.diagnostics.hasErrors():
    (false, "frame contained diagnostics errors")
  else:
    (true, "frame rendered with " & $driver.frame.commands.len & " paint commands")

proc expectCursorAt*(driver: Sdl3WaylandDriver; point: Vec2; expected: CursorKind): tuple[ok: bool, message: string] =
  let actual = driver.cursorAt(point)
  if actual == expected:
    (true, "cursor matched " & $expected)
  else:
    (false, "cursor mismatch: expected " & $expected & ", got " & $actual)

proc expectTextInputArea*(driver: Sdl3WaylandDriver; expected: Option[Rect]): tuple[ok: bool, message: string] =
  let actual = driver.textInputArea()
  if actual == expected:
    (true, "text input area matched")
  elif actual.isSome and expected.isSome:
    (false, "text input area mismatch: expected " & $expected.get.x & "," & $expected.get.y &
      " " & $expected.get.w & "x" & $expected.get.h & ", got " &
      $actual.get.x & "," & $actual.get.y & " " & $actual.get.w & "x" & $actual.get.h)
  elif actual.isSome:
    (false, "text input area mismatch: expected none, got some")
  else:
    (false, "text input area mismatch: expected some, got none")

proc expectTextInputAreaInside*(driver: Sdl3WaylandDriver; bounds: Rect): tuple[ok: bool, message: string] =
  let actual = driver.textInputArea()
  if actual.isNone:
    return (false, "text input area missing")
  let area = actual.get
  let inside =
    area.x >= bounds.x and
    area.y >= bounds.y and
    area.x + area.w <= bounds.x + bounds.w and
    area.y + area.h <= bounds.y + bounds.h
  if inside:
    (true, "text input area is inside focused control")
  else:
    (false, "text input area outside focused control: area=" &
      $area.x & "," & $area.y & " " & $area.w & "x" & $area.h &
      " bounds=" & $bounds.x & "," & $bounds.y & " " & $bounds.w & "x" & $bounds.h)
