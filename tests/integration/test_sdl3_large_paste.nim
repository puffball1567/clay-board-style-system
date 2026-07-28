import std/[options, os, strutils, times, unittest]

import clay_board_style_system
import clay_board_style_system/testing/test_driver
import clay_board_style_system/testing/integration/sdl3_wayland_driver

proc buildLargePasteUi(): UiRoot =
  result = initUiRoot()
  # Wire the real cosmic-text engine with fallback families like the demo does;
  # the built-in debug engine hides the shaping cost this test must observe.
  var fonts = initFontRegistry()
  fonts.addFallbackFamily("Noto Sans")
  fonts.addFallbackFamily("Noto Sans CJK JP")
  var cosmic = initCosmicTextEngine(fonts)
  result.configureTextLayout(cosmic.textEngine(), fonts)
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
    result.textInput(
      TextInputParams(placeholder: "Paste input"),
      style = uiStyle([
        decl("width", px(260)),
        decl("height", px(34)),
        decl("padding", px(8)),
        decl("background-color", colorValue(rgb(0.15, 0.17, 0.21))),
        decl("color", colorValue(rgb(1, 1, 1))),
        decl("cursor", keyword("text"))
      ]),
      id = "large-paste-input"
    )
    result.textArea(
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
        decl("font-size", px(12)),
        decl("line-height", px(16)),
        decl("white-space", keyword("pre-wrap"))
      ]),
      id = "large-paste-area"
    )
  finally:
    result.popParent()

const maxInteractiveMs = 500.0

suite "SDL3 Wayland large paste":
  test "large repeated paste remains responsive through real rendering":
    let probe = waylandProbe()
    if getEnv("CBSS_RUN_WAYLAND_E2E") != "1" or not probe.canUseWayland:
      skip()
    else:
      var driver = initSdl3WaylandDriver(
        buildLargePasteUi,
        size(460, 260),
        title = "CBSS Wayland Large Paste"
      )
      try:
        driver.render()

        check driver.click(byId("large-paste-input"))
        check driver.setClipboardText(repeat("input-", 1_000))
        for index in 0 ..< 4:
          let started = epochTime()
          check driver.pasteFocused()
          driver.render()
          let elapsedMs = (epochTime() - started) * 1_000.0
          echo "large-paste input iteration=", index,
            " valueBytes=", driver.headless.value(byId("large-paste-input")).len,
            " renderMs=", elapsedMs
          check elapsedMs < maxInteractiveMs

        check driver.click(byId("large-paste-area"))
        check driver.setClipboardText(repeat("line\n", 3_000))
        for index in 0 ..< 4:
          let started = epochTime()
          check driver.pasteFocused()
          driver.render()
          let elapsedMs = (epochTime() - started) * 1_000.0
          echo "large-paste textarea iteration=", index,
            " valueBytes=", driver.headless.value(byId("large-paste-area")).len,
            " nodes=", driver.headless.ui.tree.nodes.len,
            " renderMs=", elapsedMs
          check driver.headless.value(byId("large-paste-area")).len <= maxPasteEventBytes
          check elapsedMs < maxInteractiveMs
        # Pasted newline-terminated content must keep the caret visible: the
        # textarea has to scroll to the trailing empty line, not snap to top.
        let scrolled = driver.headless.scrollY(byId("large-paste-area"))
        check scrolled.isSome and scrolled.get > 0.0'f32

        check driver.dispatchSdlEvent(Sdl3Event(kind: sekKeyDown, key: "a", ctrl: true))
        driver.render()
        echo "large-paste selected nodes=", driver.headless.ui.tree.nodes.len
        check driver.headless.ui.tree.nodes.len <= 64
        check driver.copyFocused()
        for index in 0 ..< 4:
          let started = epochTime()
          check driver.pasteFocused()
          driver.render()
          let elapsedMs = (epochTime() - started) * 1_000.0
          echo "large-paste copied iteration=", index,
            " renderMs=", elapsedMs
          check driver.expectRendered().ok
          check elapsedMs < maxInteractiveMs
      finally:
        driver.close()
