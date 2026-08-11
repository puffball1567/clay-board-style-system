import std/[math, options, os, strutils, times, unittest]

import clay_board_style_system
import clay_board_style_system/testing/test_driver
import clay_board_style_system/testing/integration/sdl3_wayland_driver
import ../../examples/sdl3_demo

proc buildSmokeUi(): UiRoot =
  result = initUiRoot()
  let app = result.box(
    uiStyle([
      decl("width", px(320)),
      decl("height", px(180)),
      decl("padding", px(16)),
      decl("background-color", colorValue(rgb(0.08, 0.10, 0.13)))
    ]),
    id = "app"
  )
  result.pushParent(app)
  try:
    discard result.text(
      "CBSS Wayland smoke",
      style = uiStyle([
        decl("font-size", px(18)),
        decl("color", colorValue(rgb(0.95, 0.96, 0.98)))
      ])
    )
    discard result.textInput(
      TextInputParams(placeholder: "Type here"),
      style = uiStyle([
        decl("width", px(220)),
        decl("height", px(34)),
        decl("padding", px(8)),
        decl("background-color", colorValue(rgb(0.15, 0.17, 0.21))),
        decl("color", colorValue(rgb(1, 1, 1))),
        decl("cursor", keyword("text"))
      ]),
      id = "input"
    )
  finally:
    result.popParent()

proc buildRepeatedPasteUi(): UiRoot =
  result = initUiRoot()
  let app = result.box(
    uiStyle([
      decl("width", px(420)),
      decl("height", px(220)),
      decl("padding", px(16)),
      decl("gap", px(10)),
      decl("flex-direction", keyword("column")),
      decl("background-color", colorValue(rgb(0.08, 0.10, 0.13)))
    ]),
    id = "app"
  )
  result.pushParent(app)
  try:
    discard result.textInput(
      TextInputParams(placeholder: "Paste input"),
      style = uiStyle([
        decl("width", px(260)),
        decl("height", px(34)),
        decl("padding", px(8)),
        decl("background-color", colorValue(rgb(0.15, 0.17, 0.21))),
        decl("color", colorValue(rgb(1, 1, 1))),
        decl("cursor", keyword("text"))
      ]),
      id = "paste-input"
    )
    discard result.textArea(
      TextAreaParams(
        placeholder: "Paste textarea",
        width: some(260.0'f32),
        height: some(82.0'f32)
      ),
      style = uiStyle([
        decl("padding", px(8)),
        decl("background-color", colorValue(rgb(0.15, 0.17, 0.21))),
        decl("color", colorValue(rgb(1, 1, 1))),
        decl("cursor", keyword("text"))
      ]),
      textStyle = uiStyle([
        decl("line-height", px(18))
      ]),
      id = "paste-area"
    )
  finally:
    result.popParent()

proc buildControlledRepeatedPasteUi(
    inputValue, areaValue: string;
    onInputValue, onAreaValue: proc(value: string) {.closure.}
): UiRoot =
  result = initUiRoot()
  let app = result.box(
    uiStyle([
      decl("width", px(420)),
      decl("height", px(220)),
      decl("padding", px(16)),
      decl("gap", px(10)),
      decl("flex-direction", keyword("column")),
      decl("background-color", colorValue(rgb(0.08, 0.10, 0.13)))
    ]),
    id = "app"
  )
  result.pushParent(app)
  try:
    let input = result.textInput(
      TextInputParams(value: inputValue, placeholder: "Controlled paste input"),
      style = uiStyle([
        decl("width", px(260)),
        decl("height", px(34)),
        decl("padding", px(8)),
        decl("background-color", colorValue(rgb(0.15, 0.17, 0.21))),
        decl("color", colorValue(rgb(1, 1, 1))),
        decl("cursor", keyword("text"))
      ]),
      id = "controlled-paste-input"
    )
    input.container.onInput = proc(event: DispatchResult): EventOutcome =
      if event.event.text.isSome:
        onInputValue(event.event.text.get)
      false

    let area = result.textArea(
      TextAreaParams(
        value: areaValue,
        placeholder: "Controlled paste textarea",
        width: some(260.0'f32),
        height: some(82.0'f32)
      ),
      style = uiStyle([
        decl("padding", px(8)),
        decl("background-color", colorValue(rgb(0.15, 0.17, 0.21))),
        decl("color", colorValue(rgb(1, 1, 1))),
        decl("cursor", keyword("text"))
      ]),
      textStyle = uiStyle([
        decl("line-height", px(18))
      ]),
      id = "controlled-paste-area"
    )
    area.container.onInput = proc(event: DispatchResult): EventOutcome =
      if event.event.text.isSome:
        onAreaValue(event.event.text.get)
      false
  finally:
    result.popParent()

proc buildPaddedLabelUi(): UiRoot =
  result = initUiRoot()
  let app = result.box(
    uiStyle([
      decl("width", px(180)),
      decl("height", px(70)),
      decl("padding", px(12)),
      decl("background-color", colorValue(rgb(0.02, 0.02, 0.03)))
    ]),
    id = "app"
  )
  result.pushParent(app)
  try:
    let label = result.box(
      uiStyle([
        decl("width", px(112)),
        decl("height", px(28)),
        decl("padding-left", px(6)),
        decl("padding-right", px(6)),
        decl("align-items", keyword("center")),
        decl("justify-content", keyword("center")),
        decl("background-color", colorValue(rgb(0.12, 0.13, 0.15))),
        decl("border-color", colorValue(rgb(0.28, 0.30, 0.35))),
        decl("border-width", px(1)),
        decl("border-radius", px(4))
      ]),
      code = "property-label-decoration"
    )
    result.pushParent(label)
    try:
      discard result.text(
        "decoration",
        style = uiStyle([
          decl("width", px(96)),
          decl("font-size", px(10)),
          decl("line-height", px(16)),
          decl("text-align", keyword("center")),
          decl("white-space", keyword("nowrap")),
          decl("color", colorValue(rgb(0.95, 0.96, 0.98)))
        ]),
        groups = ["property-label-text"]
      )
    finally:
      result.popParent()
  finally:
    result.popParent()

proc panelStyle(): UiStyle =
  uiStyle([
    decl("height", px(148)),
    decl("padding", px(9)),
    decl("gap", px(6)),
    decl("flex-direction", keyword("column")),
    decl("align-items", keyword("stretch")),
    decl("background-color", colorValue(rgb(0.13, 0.13, 0.15))),
    decl("border-color", colorValue(rgb(0.28, 0.30, 0.35))),
    decl("border-width", px(1)),
    decl("border-radius", px(5))
  ])

proc panelRowStyle(): UiStyle =
  uiStyle([
    decl("height", px(34)),
    decl("gap", px(8)),
    decl("flex-direction", keyword("row")),
    decl("align-items", keyword("center"))
  ])

proc panelLabelStyle(): UiStyle =
  uiStyle([
    decl("width", px(112)),
    decl("height", px(28)),
    decl("padding-left", px(6)),
    decl("padding-right", px(6)),
    decl("align-items", keyword("center")),
    decl("justify-content", keyword("center")),
    decl("background-color", colorValue(rgb(0.13, 0.13, 0.15))),
    decl("border-color", colorValue(rgb(0.28, 0.30, 0.35))),
    decl("border-width", px(1)),
    decl("border-radius", px(4)),
    decl("font-size", px(10)),
    decl("color", colorValue(rgb(0.68, 0.74, 0.82)))
  ])

proc panelLabelTextStyle(): UiStyle =
  uiStyle([
    decl("width", px(96)),
    decl("font-size", px(10)),
    decl("line-height", px(16)),
    decl("text-align", keyword("center")),
    decl("white-space", keyword("nowrap")),
    decl("color", colorValue(rgb(0.68, 0.74, 0.82)))
  ])

proc panelDecorationTextStyle(decorationStyle = "solid"; width = 86'f32): UiStyle =
  uiStyle([
    decl("width", px(width)),
    decl("height", px(30)),
    decl("font-size", px(13)),
    decl("line-height", px(24)),
    decl("letter-spacing", px(0.4)),
    decl("text-decoration", keyword("underline")),
    decl("text-decoration-style", keyword(decorationStyle)),
    decl("text-decoration-color", colorValue(rgb(0.45, 0.86, 0.98))),
    decl("text-decoration-thickness", px(2)),
    decl("text-underline-offset", px(2)),
    decl("color", colorValue(rgb(0.92, 0.97, 1.00)))
  ])

proc buildPropertyPanelLabelUi(): UiRoot =
  result = initUiRoot()
  let app = result.box(
    uiStyle([
      decl("width", px(520)),
      decl("height", px(190)),
      decl("padding", px(12)),
      decl("background-color", colorValue(rgb(0.02, 0.02, 0.03)))
    ]),
    id = "app"
  )
  result.pushParent(app)
  try:
    let panel = result.box(panelStyle(), code = "property-panel")
    result.pushParent(panel)
    try:
      let row = result.box(panelRowStyle(), code = "decoration-row")
      result.pushParent(row)
      try:
        let label = result.box(panelLabelStyle(), code = "property-label-decoration")
        result.pushParent(label)
        try:
          discard result.text(
            "decoration",
            style = panelLabelTextStyle(),
            groups = ["property-label-text"]
          )
        finally:
          result.popParent()
        discard result.text("solid", style = panelDecorationTextStyle("solid", 72))
        discard result.text("dashed", style = panelDecorationTextStyle("dashed", 82))
        discard result.text("dotted", style = panelDecorationTextStyle("dotted", 80))
        discard result.text("double", style = panelDecorationTextStyle("double", 82))
      finally:
        result.popParent()
    finally:
      result.popParent()
  finally:
    result.popParent()

proc overflowClipSampleStyle(): UiStyle =
  uiStyle([
    decl("width", px(128)),
    decl("height", px(30)),
    decl("padding", px(6)),
    decl("align-items", keyword("center")),
    decl("background-color", colorValue(rgb(0.11, 0.16, 0.21))),
    decl("border-color", colorValue(rgb(0.34, 0.62, 0.84))),
    decl("border-width", px(1)),
    decl("border-radius", px(4)),
    decl("overflow", keyword("hidden"))
  ])

proc overflowClipTextStyle(): UiStyle =
  uiStyle([
    decl("width", px(210)),
    decl("font-size", px(12)),
    decl("line-height", px(18)),
    decl("white-space", keyword("nowrap")),
    decl("color", colorValue(rgb(0.82, 0.94, 1.00)))
  ])

proc buildOverflowPaddingUi(): UiRoot =
  result = initUiRoot()
  let app = result.box(
    uiStyle([
      decl("width", px(180)),
      decl("height", px(70)),
      decl("padding", px(12)),
      decl("background-color", colorValue(rgb(0.02, 0.02, 0.03)))
    ]),
    id = "app"
  )
  result.pushParent(app)
  try:
    let sample = result.box(overflowClipSampleStyle(), code = "overflow-sample")
    result.pushParent(sample)
    try:
      discard result.text(
        "overflow hidden clips long text",
        style = overflowClipTextStyle(),
        groups = ["overflow-sample-text"]
      )
    finally:
      result.popParent()
  finally:
    result.popParent()

proc buildScrollbarUi(): UiRoot =
  result = initUiRoot()
  let app = result.box(
    uiStyle([
      decl("width", px(140)),
      decl("height", px(80)),
      decl("padding", px(12)),
      decl("background-color", colorValue(rgb(0.02, 0.02, 0.03)))
    ]),
    id = "app"
  )
  result.pushParent(app)
  try:
    let viewport = result.box(
      uiStyle([
        decl("width", px(100)),
        decl("height", px(40)),
        decl("flex-direction", keyword("column")),
        decl("overflow-y", keyword("scroll")),
        decl("scrollbar-width", keyword("thin")),
        decl("scrollbar-gutter", keyword("stable")),
        decl("scrollbar-color", colorPairValue(rgb(0, 1, 1), rgb(1, 0, 1))),
        decl("background-color", colorValue(rgb(0.08, 0.10, 0.12)))
      ]),
      code = "scroll-viewport"
    )
    result.pushParent(viewport)
    try:
      for index in 0 ..< 3:
        discard result.text(
          "row " & $(index + 1),
          uiStyle([
            decl("height", px(24)),
            decl("flex-shrink", number(0)),
            decl("font-size", px(10)),
            decl("line-height", px(20)),
            decl("color", colorValue(rgb(0.85, 0.88, 0.92)))
          ])
        )
    finally:
      result.popParent()
  finally:
    result.popParent()

proc brightPixelCount(image: CbssPpmImage; area: Rect; threshold = 180'u8): int =
  let x1 = max(0, int(floor(area.x)))
  let y1 = max(0, int(floor(area.y)))
  let x2 = min(image.width, int(ceil(area.x + area.w)))
  let y2 = min(image.height, int(ceil(area.y + area.h)))
  if x2 <= x1 or y2 <= y1:
    return 0
  for y in y1 ..< y2:
    for x in x1 ..< x2:
      let offset = (y * image.width + x) * 3
      if image.pixels[offset] >= threshold or
          image.pixels[offset + 1] >= threshold or
          image.pixels[offset + 2] >= threshold:
        inc result

proc visiblePixelCount(image: CbssPpmImage; area: Rect; threshold = 20'u8): int =
  brightPixelCount(image, area, threshold)

proc coloredPixelCount(
    image: CbssPpmImage;
    area: Rect;
    red, green, blue: uint8;
    tolerance = 12
): int =
  let x1 = max(0, int(floor(area.x)))
  let y1 = max(0, int(floor(area.y)))
  let x2 = min(image.width, int(ceil(area.x + area.w)))
  let y2 = min(image.height, int(ceil(area.y + area.h)))
  for y in y1 ..< y2:
    for x in x1 ..< x2:
      let offset = (y * image.width + x) * 3
      if abs(image.pixels[offset].int - red.int) <= tolerance and
          abs(image.pixels[offset + 1].int - green.int) <= tolerance and
          abs(image.pixels[offset + 2].int - blue.int) <= tolerance:
        inc result

proc rightPaddingRect(labelRect, textRect: Rect): Rect =
  rect(
    textRect.x + textRect.w,
    labelRect.y + 2,
    labelRect.x + labelRect.w - 1 - (textRect.x + textRect.w),
    max(0.0'f32, labelRect.h - 4)
  )

proc containsRect(outerRect, innerRect: Rect; tolerance = 0.5'f32): bool =
  innerRect.x >= outerRect.x - tolerance and
    innerRect.y >= outerRect.y - tolerance and
    innerRect.x + innerRect.w <= outerRect.x + outerRect.w + tolerance and
    innerRect.y + innerRect.h <= outerRect.y + outerRect.h + tolerance

suite "SDL3 Wayland smoke":
  test "SDL wheel direction is normalized before UI scrolling":
    check normalizedWheelAxis(-1, directionFlipped = false) == -1
    check normalizedWheelAxis(1, directionFlipped = true) == -1
    let towardUser = Sdl3Event(kind: sekWheel, wheelX: 0, wheelY: -1)
    check towardUser.scrollDelta() == vec2(0, DefaultWheelStepPixels)

  test "opens a Wayland SDL3 window when explicitly enabled":
    let probe = waylandProbe()
    if getEnv("CBSS_RUN_WAYLAND_E2E") != "1" or not probe.canUseWayland:
      skip()
    else:
      var driver = initSdl3WaylandDriver(
        buildSmokeUi,
        size(360, 220),
        title = "CBSS Wayland Smoke"
      )
      try:
        var scenario = initSdl3WaylandScenario(
          "wayland smoke",
          driver,
          artifactDir = getTempDir() / "cbss_wayland_smoke_artifacts"
        )
        check scenario.step("initial render", proc(): bool =
          driver.render()
          true
        )
        check scenario.expect("rendered frame", driver.expectRendered())
        check currentSdlVideoDriver() == "wayland"
        check driver.poll(maxEvents = 16) >= 0
        let inputCenter = driver.headless.centerFor(byId("input"))
        check scenario.expect("input cursor", driver.expectCursorAt(inputCenter, ckText))
        check driver.updateCursor(inputCenter) == ckText
        check driver.currentCursor() == ckText
        check scenario.step("focus input", proc(): bool = driver.click(byId("input")))
        let inputBounds = driver.headless.rectFor(byId("input"))
        check inputBounds.isSome
        check scenario.expect("text input area", driver.expectTextInputAreaInside(inputBounds.get))
        check driver.textInputActive()
        check scenario.step("type input", proc(): bool = driver.typeText("abc"))
        check scenario.expect("input value", driver.headless.expectValue(byId("input"), "abc"))
        check driver.dispatchSdlEvent(
          Sdl3Event(
            kind: sekCompositionCandidates,
            timestamp: 1,
            candidates: @["abc", "ABC"],
            selectedCandidate: 0,
            horizontalCandidates: true
          )
        )
        check scenario.expect("composition candidates", driver.expectCompositionCandidates(["abc", "ABC"], selectedCandidate = 0))
        check driver.setClipboardText("cbss-wayland-clipboard")
        check driver.clipboardText() == "cbss-wayland-clipboard"
        let screenshotPath = getTempDir() / "cbss_wayland_smoke.ppm"
        let screenshotBaselinePath = getTempDir() / "cbss_wayland_smoke_baseline.ppm"
        let screenshotDiffPath = getTempDir() / "cbss_wayland_smoke_diff.ppm"
        let debugPath = getTempDir() / "cbss_wayland_smoke_debug.txt"
        let manifestPath = getTempDir() / "cbss_wayland_smoke_manifest.txt"
        check driver.saveScreenshotPpm(screenshotPath)
        check driver.expectScreenshotPpm(screenshotPath).ok
        copyFile(screenshotPath, screenshotBaselinePath)
        check driver.expectScreenshotMatches(
          screenshotBaselinePath,
          screenshotPath,
          diffPath = screenshotDiffPath
        ).ok
        driver.saveDebugBundle(debugPath)
        check fileExists(debugPath)
        check readFile(debugPath).contains("sdl3-wayland:")
        driver.saveArtifactManifest(manifestPath)
        check fileExists(manifestPath)
        check readFile(manifestPath).contains("real-window: true")
        check driver.artifacts.contains(screenshotPath)
        check driver.artifacts.contains(debugPath)
        check driver.artifacts.contains(manifestPath)
        check scenario.ok
        check driver.actionSnapshot().contains("screenshot")
        driver.holdFromEnv()
      finally:
        driver.close()

  test "repeated focused paste stays ordered in a real Wayland SDL3 window":
    let probe = waylandProbe()
    if getEnv("CBSS_RUN_WAYLAND_E2E") != "1" or not probe.canUseWayland:
      skip()
    else:
      var driver = initSdl3WaylandDriver(
        buildRepeatedPasteUi,
        size(460, 260),
        title = "CBSS Wayland Repeated Paste"
      )
      try:
        driver.render()

        check driver.click(byId("paste-input"))
        check driver.setClipboardText("input-")
        for _ in 0 ..< 5:
          check driver.pasteFocused()
        check driver.headless.value(byId("paste-input")) == "input-input-input-input-input-"
        check driver.expectRendered().ok

        check driver.click(byId("paste-area"))
        check driver.setClipboardText("line\n")
        for _ in 0 ..< 5:
          check driver.pasteFocused()
        check driver.headless.value(byId("paste-area")) == "line\nline\nline\nline\nline\n"
        check driver.headless.wheel(byId("paste-area"), vec2(0, -1000))
        check driver.headless.scrollY(byId("paste-area")) == some(0.0'f32)
        let areaCenter = driver.headless.centerFor(byId("paste-area"))
        check driver.dispatchSdlEvent(Sdl3Event(
          kind: sekWheel,
          wheelX: 0,
          wheelY: -1,
          wheelMouseX: areaCenter.x,
          wheelMouseY: areaCenter.y
        ))
        check driver.headless.scrollY(byId("paste-area")).get > 0
        let scrollbarTrack = driver.headless.rectFor(byGroup("textarea-scrollbar-track"))
        let scrollbarThumb = driver.headless.rectFor(byGroup("textarea-scrollbar-thumb"))
        check scrollbarTrack.isSome
        check scrollbarThumb.isSome
        check scrollbarTrack.get.containsRect(scrollbarThumb.get)
        check driver.expectRendered().ok

        let screenshotPath = getTempDir() / "cbss_wayland_repeated_paste.ppm"
        check driver.saveScreenshotPpm(screenshotPath)
        check driver.expectScreenshotPpm(screenshotPath).ok
        let areaRect = driver.headless.rectFor(byId("paste-area"))
        check areaRect.isSome
        let image = loadPpm(screenshotPath)
        check brightPixelCount(image, areaRect.get) > 30

        # A later frame must retain the textarea scrollbar. This guards the
        # static/dynamic layer handoff used by the interactive demo.
        driver.render()
        let retainedTrack = driver.headless.rectFor(byGroup("textarea-scrollbar-track"))
        let retainedThumb = driver.headless.rectFor(byGroup("textarea-scrollbar-thumb"))
        check retainedTrack.isSome
        check retainedThumb.isSome
        check retainedTrack.get.containsRect(retainedThumb.get)
        let retainedScreenshotPath = getTempDir() / "cbss_wayland_scrollbar_retained.ppm"
        check driver.saveScreenshotPpm(retainedScreenshotPath)
        check driver.expectScreenshotPpm(retainedScreenshotPath).ok
        let retainedImage = loadPpm(retainedScreenshotPath)
        check brightPixelCount(retainedImage, areaRect.get) > 30

        check driver.setClipboardText(repeat("line\n", 3_000))
        for _ in 0 ..< 4:
          check driver.pasteFocused()
          driver.render()
          check driver.headless.value(byId("paste-area")).len <= maxPasteEventBytes
          check driver.expectRendered().ok
        check driver.dispatchSdlEvent(Sdl3Event(
          kind: sekKeyDown, key: "a", ctrl: true
        ))
        check driver.copyFocused()
        for _ in 0 ..< 4:
          check driver.pasteFocused()
          check driver.expectRendered().ok
      finally:
        driver.close()

  test "controlled repeated paste survives full UiRoot rebuilds in a real Wayland SDL3 window":
    let probe = waylandProbe()
    if getEnv("CBSS_RUN_WAYLAND_E2E") != "1" or not probe.canUseWayland:
      skip()
    else:
      var inputValue = ""
      var areaValue = ""

      proc build(): UiRoot =
        buildControlledRepeatedPasteUi(
          inputValue,
          areaValue,
          proc(value: string) =
            inputValue = value,
          proc(value: string) =
            areaValue = value
        )

      var driver = initSdl3WaylandDriver(
        build,
        size(460, 260),
        title = "CBSS Wayland Controlled Repeated Paste"
      )

      proc rebuildAndRender() =
        driver.headless.ui = build()
        driver.refresh()
        discard driver.syncTextInputArea()
        driver.render()

      try:
        driver.render()

        check driver.click(byId("controlled-paste-input"))
        check driver.setClipboardText("input-")
        for _ in 0 ..< 5:
          check driver.pasteFocused()
          rebuildAndRender()
        check inputValue == "input-input-input-input-input-"
        check driver.headless.value(byId("controlled-paste-input")) == inputValue
        check driver.expectRendered().ok

        check driver.click(byId("controlled-paste-area"))
        check driver.setClipboardText("line\n")
        for _ in 0 ..< 5:
          check driver.pasteFocused()
          rebuildAndRender()
        check areaValue == "line\nline\nline\nline\nline\n"
        check driver.headless.value(byId("controlled-paste-area")) == areaValue
        check driver.expectRendered().ok

        let screenshotPath = getTempDir() / "cbss_wayland_controlled_repeated_paste.ppm"
        check driver.saveScreenshotPpm(screenshotPath)
        check driver.expectScreenshotPpm(screenshotPath).ok
      finally:
        driver.close()

  test "actual SDL3 demo hero input survives repeated paste rebuilds":
    let probe = waylandProbe()
    if getEnv("CBSS_RUN_WAYLAND_E2E") != "1" or not probe.canUseWayland:
      skip()
    else:
      let harness = initDemoHarness()

      proc build(): UiRoot =
        buildDemoHarnessUi(harness)

      var driver = initSdl3WaylandDriver(
        build,
        size(1200, 980),
        title = "CBSS Actual Demo Repeated Paste"
      )

      proc renderCurrent() =
        driver.refresh()
        discard driver.syncTextInputArea()
        driver.app.render(driver.frame.commands, rgb(1, 1, 1))

      proc rebuildIfDirty() =
        if consumeDemoHarnessDirty(harness):
          driver.headless.ui = buildDemoHarnessUi(harness)
          renderCurrent()

      try:
        driver.render()
        check driver.click(byId("hero-input"))
        check driver.setClipboardText("demo-")
        setDemoHarnessClipboard(harness, "demo-")
        let pasteStart = epochTime()
        for _ in 0 ..< 5:
          check driver.headless.paste(driver.clipboardText())
          rebuildIfDirty()
        let pasteMs = (epochTime() - pasteStart) * 1000.0
        echo "actual-demo repeated paste: totalMs=", pasteMs, " avgMs=", pasteMs / 5.0

        check driver.headless.value(byId("hero-input")) == "demo-demo-demo-demo-demo-"
        check driver.headless.selectAll()
        check driver.headless.copy()
        check demoHarnessClipboard(harness) == "demo-demo-demo-demo-demo-"
        # Copy and the immediately following shortcut paste share the UiRoot
        # snapshot. This must not issue a second platform clipboard read.
        check driver.headless.press("End")
        check driver.headless.press("v", ctrlKey = true)
        rebuildIfDirty()
        check driver.headless.value(byId("hero-input")) ==
          "demo-demo-demo-demo-demo-demo-demo-demo-demo-demo-"
        check driver.expectRendered().ok
        let screenshotPath = getTempDir() / "cbss_actual_demo_repeated_paste.ppm"
        check driver.saveScreenshotPpm(screenshotPath)
        check driver.expectScreenshotPpm(screenshotPath).ok
      finally:
        driver.close()

  test "actual SDL3 demo hero input survives repeated control-v rebuilds":
    let probe = waylandProbe()
    if getEnv("CBSS_RUN_WAYLAND_E2E") != "1" or not probe.canUseWayland:
      skip()
    else:
      let harness = initDemoHarness()

      proc build(): UiRoot =
        buildDemoHarnessUi(harness)

      var driver = initSdl3WaylandDriver(
        build,
        size(1200, 980),
        title = "CBSS Actual Demo Repeated Control V"
      )

      proc renderCurrent() =
        driver.refresh()
        discard driver.syncTextInputArea()
        driver.app.render(driver.frame.commands, rgb(1, 1, 1))

      proc rebuildIfDirty() =
        if consumeDemoHarnessDirty(harness):
          driver.headless.ui = buildDemoHarnessUi(harness)
          renderCurrent()

      try:
        driver.render()
        check driver.click(byId("hero-input"))
        check driver.setClipboardText("key-")
        setDemoHarnessClipboard(harness, "key-")
        let shortcutStart = epochTime()
        for _ in 0 ..< 5:
          check driver.headless.press("v", ctrlKey = true)
          rebuildIfDirty()
        let shortcutMs = (epochTime() - shortcutStart) * 1000.0
        echo "actual-demo repeated control-v: totalMs=", shortcutMs, " avgMs=", shortcutMs / 5.0

        check driver.headless.value(byId("hero-input")) == "key-key-key-key-key-"
        check driver.expectRendered().ok
        let screenshotPath = getTempDir() / "cbss_actual_demo_repeated_control_v.ppm"
        check driver.saveScreenshotPpm(screenshotPath)
        check driver.expectScreenshotPpm(screenshotPath).ok
      finally:
        driver.close()

  test "actual SDL3 demo keeps fixed catalog content inside its panels":
    let probe = waylandProbe()
    if getEnv("CBSS_RUN_WAYLAND_E2E") != "1" or not probe.canUseWayland:
      skip()
    else:
      let harness = initDemoHarness()

      proc build(): UiRoot =
        buildDemoHarnessUi(harness)

      var driver = initSdl3WaylandDriver(
        build,
        size(1200, 980),
        title = "CBSS Actual Demo Layout"
      )
      try:
        driver.render()
        let propertyPanel = driver.headless.rectFor(byCode("property-panel"))
        let dialogPanel = driver.headless.rectFor(byGroup("dialog"))
        let dialogBody = driver.headless.rectFor(byGroup("dialog-body"))
        let detailsPanel = driver.headless.rectFor(byGroup("details"))
        let detailsBody = driver.headless.rectFor(byGroup("details-body"))
        let menuRow = driver.headless.rectFor(byGroup("command-menu-row"))
        let listBox = driver.headless.rectFor(byId("catalog-list-box"))
        let commandMenu = driver.headless.rectFor(byId("catalog-command-menu"))
        let commandMenuLabel =
          driver.headless.rectFor(byId("catalog-command-menu-label"))
        let demoBody = driver.headless.rectFor(byGroup("demo-body"))
        let badge = driver.headless.rectFor(byGroup("absolute-badge"))

        check propertyPanel.isSome
        check propertyPanel.get.w == 500
        check dialogPanel.isSome
        check dialogBody.isSome
        check dialogPanel.get.containsRect(dialogBody.get)
        check detailsPanel.isSome
        check detailsBody.isSome
        check detailsPanel.get.containsRect(detailsBody.get)
        check menuRow.isSome
        check listBox.isSome
        check commandMenu.isSome
        check commandMenuLabel.isSome
        check commandMenuLabel.get.h <= 14.5'f32
        check menuRow.get.containsRect(listBox.get)
        check menuRow.get.containsRect(commandMenu.get)
        check menuRow.get.containsRect(commandMenuLabel.get)
        check demoBody.isSome
        check badge.isSome
        check demoBody.get.containsRect(badge.get)

        let screenshotPath = getTempDir() / "cbss_actual_demo_layout.ppm"
        check driver.saveScreenshotPpm(screenshotPath)
        check driver.expectScreenshotPpm(screenshotPath).ok
        let image = loadPpm(screenshotPath)
        check visiblePixelCount(image, propertyPanel.get) > 1000
        check visiblePixelCount(image, dialogPanel.get) > 100
        check visiblePixelCount(image, detailsPanel.get) > 100
        let detailsLeakArea = rect(
          detailsPanel.get.x + detailsPanel.get.w + 2,
          detailsBody.get.y,
          88,
          detailsBody.get.h
        )
        check brightPixelCount(image, detailsLeakArea, threshold = 120) == 0
      finally:
        driver.close()

  test "text max width keeps glyphs out of right padding in a real SDL3 screenshot":
    let probe = waylandProbe()
    if getEnv("CBSS_RUN_WAYLAND_E2E") != "1" or not probe.canUseWayland:
      skip()
    else:
      var driver = initSdl3WaylandDriver(
        buildPaddedLabelUi,
        size(180, 70),
        title = "CBSS Text Clip Smoke"
      )
      try:
        driver.render()
        let labelRect = driver.headless.rectFor(byCode("property-label-decoration"))
        let textRect = driver.headless.rectFor(byGroup("property-label-text"))
        check labelRect.isSome
        check textRect.isSome
        let screenshotPath = getTempDir() / "cbss_text_clip_padding.ppm"
        check driver.saveScreenshotPpm(screenshotPath)
        let image = loadPpm(screenshotPath)
        check visiblePixelCount(image, labelRect.get) > 100

        let rightPadding = rightPaddingRect(labelRect.get, textRect.get)
        check rightPadding.w > 0
        check brightPixelCount(image, rightPadding) == 0
      finally:
        driver.close()

  test "property panel decoration label keeps right padding clear in a real SDL3 screenshot":
    let probe = waylandProbe()
    if getEnv("CBSS_RUN_WAYLAND_E2E") != "1" or not probe.canUseWayland:
      skip()
    else:
      var driver = initSdl3WaylandDriver(
        buildPropertyPanelLabelUi,
        size(520, 190),
        title = "CBSS Property Panel Text Clip Smoke"
      )
      try:
        driver.render()
        let labelRect = driver.headless.rectFor(byCode("property-label-decoration"))
        let textRect = driver.headless.rectFor(byGroup("property-label-text"))
        check labelRect.isSome
        check textRect.isSome
        let screenshotPath = getTempDir() / "cbss_property_panel_text_clip_padding.ppm"
        check driver.saveScreenshotPpm(screenshotPath)
        let image = loadPpm(screenshotPath)
        check visiblePixelCount(image, labelRect.get) > 100

        let rightPadding = rightPaddingRect(labelRect.get, textRect.get)
        check rightPadding.w > 0
        check brightPixelCount(image, rightPadding) == 0
      finally:
        driver.close()

  test "overflow hidden preserves right padding in a real SDL3 screenshot":
    let probe = waylandProbe()
    if getEnv("CBSS_RUN_WAYLAND_E2E") != "1" or not probe.canUseWayland:
      skip()
    else:
      var driver = initSdl3WaylandDriver(
        buildOverflowPaddingUi,
        size(180, 70),
        title = "CBSS Overflow Padding Smoke"
      )
      try:
        driver.render()
        let sampleRect = driver.headless.rectFor(byCode("overflow-sample"))
        check sampleRect.isSome
        let screenshotPath = getTempDir() / "cbss_overflow_padding.ppm"
        check driver.saveScreenshotPpm(screenshotPath)
        let image = loadPpm(screenshotPath)
        check visiblePixelCount(image, sampleRect.get) > 100

        let rightPadding = rect(
          sampleRect.get.x + sampleRect.get.w - 6,
          sampleRect.get.y + 2,
          4,
          max(0.0'f32, sampleRect.get.h - 4)
        )
        check brightPixelCount(image, rightPadding) == 0
      finally:
        driver.close()

  test "scrollbar track and thumb render inside the stable gutter":
    let probe = waylandProbe()
    if getEnv("CBSS_RUN_WAYLAND_E2E") != "1" or not probe.canUseWayland:
      skip()
    else:
      var driver = initSdl3WaylandDriver(
        buildScrollbarUi,
        size(140, 80),
        title = "CBSS Scrollbar Smoke"
      )
      try:
        driver.render()
        let viewport = driver.headless.rectFor(byCode("scroll-viewport"))
        check viewport.isSome
        let gutter = rect(
          viewport.get.x + viewport.get.w - 6,
          viewport.get.y,
          6,
          viewport.get.h
        )
        let screenshotPath = getTempDir() / "cbss_scrollbar_smoke.ppm"
        check driver.saveScreenshotPpm(screenshotPath)
        let image = loadPpm(screenshotPath)
        check coloredPixelCount(image, gutter, 255, 0, 255) > 0
        check coloredPixelCount(image, gutter, 0, 255, 255) > 0
      finally:
        driver.close()
