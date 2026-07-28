import std/[options, os, strutils, unittest]

import clay_box_style_system
import clay_box_style_system/testing/test_driver
import clay_box_style_system/testing/integration/sdl3_wayland_driver

proc buildMinimalUi(): UiRoot =
  result = initUiRoot()
  result.box("app"):
    discard result.text("Wayland unit")

proc buildTextInputUi(input: var TextInputHandle): UiRoot =
  result = initUiRoot()
  result.box("app"):
    input = result.textInput(
      TextInputParams(placeholder: "Name"),
      style = uiStyle([
        decl("width", px(160)),
        decl("height", px(32)),
        decl("cursor", keyword("text"))
      ]),
      id = "name"
    )

proc buildTwoTextControlsUi(input: var TextInputHandle; area: var TextAreaHandle): UiRoot =
  result = initUiRoot()
  result.box("app"):
    input = result.textInput(
      TextInputParams(placeholder: "Name"),
      style = uiStyle([
        decl("width", px(160)),
        decl("height", px(32)),
        decl("cursor", keyword("text"))
      ]),
      id = "name"
    )
    area = result.textArea(
      TextAreaParams(placeholder: "Message", width: some(180.0'f32), height: some(72.0'f32)),
      style = uiStyle([
        decl("width", px(180)),
        decl("height", px(72)),
        decl("cursor", keyword("text"))
      ]),
      id = "message"
    )

suite "SDL3 Wayland integration driver":
  test "Wayland probe is safe without opening a window":
    let probe = waylandProbe()
    check probe.message.len > 0
    check probe.canUseWayland == (
      probe.sessionType.toLowerAscii() == "wayland" or
      probe.waylandDisplay.len > 0 or
      probe.sdlVideoDriver.toLowerAscii() == "wayland"
    )

  test "requireWayland reports a useful error when unavailable":
    let probe = Sdl3WaylandProbe(
      sessionType: "",
      waylandDisplay: "",
      sdlVideoDriver: "",
      canUseWayland: false,
      message: "not available"
    )
    expect CatchableError:
      probe.requireWayland()

  test "integration capabilities report is stable without a window":
    let probe = Sdl3WaylandProbe(
      sessionType: "wayland",
      waylandDisplay: "wayland-0",
      sdlVideoDriver: "",
      canUseWayland: true,
      message: "available"
    )
    let probeReport = probe.capabilitiesReport()
    check probeReport.contains("backend: sdl3-wayland")
    check probeReport.contains("can-open-window: true")
    check probeReport.contains("composition-candidates: true")
    check probeReport.contains("screenshot-diff: true")

    let driver = Sdl3WaylandDriver(
      headless: initCbssTestDriver(buildMinimalUi, size(120, 80)),
      title: "Capabilities",
      artifacts: @[]
    )
    let driverReport = driver.capabilitiesReport()
    check driverReport.contains("backend: sdl3-wayland")
    check driverReport.contains("real-window: false")
    check driverReport.contains("semantic-driver: true")

  test "artifact manifest records capabilities actions events and artifacts":
    let artifactDir = getTempDir() / "cbss-wayland-manifest"
    createDir(artifactDir)
    let debugPath = artifactDir / "debug.txt"
    let manifestPath = artifactDir / "manifest.txt"
    removeFile(debugPath)
    removeFile(manifestPath)
    let driver = Sdl3WaylandDriver(
      headless: initCbssTestDriver(buildMinimalUi, size(120, 80)),
      title: "Manifest",
      artifacts: @[]
    )
    driver.saveDebugBundle(debugPath)
    driver.saveArtifactManifest(manifestPath)

    check fileExists(manifestPath)
    let manifest = readFile(manifestPath)
    check manifest.contains("cbss-integration-artifacts:")
    check manifest.contains("title: Manifest")
    check manifest.contains("capabilities:")
    check manifest.contains("backend: sdl3-wayland")
    check manifest.contains("artifacts:")
    check manifest.contains(debugPath)
    check manifest.contains("actions:")
    check manifest.contains("events:")
    check manifestPath in driver.artifacts
    removeFile(debugPath)
    removeFile(manifestPath)

  test "PPM screenshots can be saved and loaded":
    let path = getTempDir() / "cbss-wayland-ppm-load.ppm"
    removeFile(path)
    let image = CbssPpmImage(
      width: 2,
      height: 1,
      pixels: @[uint8(255), 0, 0, 0, 128, 255]
    )
    image.savePpm(path)
    let loaded = loadPpm(path)
    check loaded.width == 2
    check loaded.height == 1
    check loaded.pixels == image.pixels
    removeFile(path)

  test "PPM screenshot diff accepts identical images":
    let expectedPath = getTempDir() / "cbss-wayland-expected-identical.ppm"
    let actualPath = getTempDir() / "cbss-wayland-actual-identical.ppm"
    let image = CbssPpmImage(
      width: 2,
      height: 1,
      pixels: @[uint8(10), 20, 30, 40, 50, 60]
    )
    image.savePpm(expectedPath)
    image.savePpm(actualPath)
    let diff = diffScreenshotPpm(expectedPath, actualPath)
    check diff.matches
    check diff.changedPixels == 0
    check diff.maxChannelDelta == 0
    removeFile(expectedPath)
    removeFile(actualPath)

  test "PPM screenshot diff reports changed pixels and writes a diff artifact":
    let expectedPath = getTempDir() / "cbss-wayland-expected-changed.ppm"
    let actualPath = getTempDir() / "cbss-wayland-actual-changed.ppm"
    let diffPath = getTempDir() / "cbss-wayland-diff-changed.ppm"
    removeFile(diffPath)
    CbssPpmImage(
      width: 2,
      height: 1,
      pixels: @[uint8(10), 20, 30, 40, 50, 60]
    ).savePpm(expectedPath)
    CbssPpmImage(
      width: 2,
      height: 1,
      pixels: @[uint8(10), 20, 30, 90, 50, 60]
    ).savePpm(actualPath)
    let diff = diffScreenshotPpm(expectedPath, actualPath, diffPath = diffPath)
    check not diff.matches
    check diff.changedPixels == 1
    check diff.maxChannelDelta == 50
    check fileExists(diffPath)
    let diffImage = loadPpm(diffPath)
    check diffImage.pixels[3] == 255
    check diffImage.pixels[4] == 0
    check diffImage.pixels[5] == 0
    removeFile(expectedPath)
    removeFile(actualPath)
    removeFile(diffPath)

  test "PPM screenshot diff supports channel tolerance":
    let expectedPath = getTempDir() / "cbss-wayland-expected-tolerance.ppm"
    let actualPath = getTempDir() / "cbss-wayland-actual-tolerance.ppm"
    CbssPpmImage(
      width: 1,
      height: 1,
      pixels: @[uint8(100), 100, 100]
    ).savePpm(expectedPath)
    CbssPpmImage(
      width: 1,
      height: 1,
      pixels: @[uint8(103), 101, 99]
    ).savePpm(actualPath)
    let diff = diffScreenshotPpm(expectedPath, actualPath, maxChannelDelta = 3)
    check diff.matches
    check diff.changedPixels == 0
    check diff.maxChannelDelta == 3
    removeFile(expectedPath)
    removeFile(actualPath)

  test "PPM screenshot diff rejects size mismatch":
    let expectedPath = getTempDir() / "cbss-wayland-expected-size.ppm"
    let actualPath = getTempDir() / "cbss-wayland-actual-size.ppm"
    CbssPpmImage(
      width: 1,
      height: 1,
      pixels: @[uint8(0), 0, 0]
    ).savePpm(expectedPath)
    CbssPpmImage(
      width: 2,
      height: 1,
      pixels: @[uint8(0), 0, 0, 0, 0, 0]
    ).savePpm(actualPath)
    let diff = diffScreenshotPpm(expectedPath, actualPath)
    check not diff.matches
    check diff.message.contains("size mismatch")
    removeFile(expectedPath)
    removeFile(actualPath)

  test "screenshot expectation records generated diff artifacts":
    let expectedPath = getTempDir() / "cbss-wayland-expected-record.ppm"
    let actualPath = getTempDir() / "cbss-wayland-actual-record.ppm"
    let diffPath = getTempDir() / "cbss-wayland-diff-record.ppm"
    removeFile(diffPath)
    CbssPpmImage(
      width: 1,
      height: 1,
      pixels: @[uint8(0), 0, 0]
    ).savePpm(expectedPath)
    CbssPpmImage(
      width: 1,
      height: 1,
      pixels: @[uint8(255), 0, 0]
    ).savePpm(actualPath)
    let driver = Sdl3WaylandDriver(artifacts: @[])
    let expectation = driver.expectScreenshotMatches(expectedPath, actualPath, diffPath = diffPath)
    check not expectation.ok
    check diffPath in driver.artifacts
    removeFile(expectedPath)
    removeFile(actualPath)
    removeFile(diffPath)

  test "Wayland scenarios record steps and failure artifacts without a window":
    let artifactDir = getTempDir() / "cbss-wayland-scenario-artifacts"
    createDir(artifactDir)
    let driver = Sdl3WaylandDriver(
      headless: initCbssTestDriver(buildMinimalUi, size(120, 80)),
      title: "Unit scenario",
      artifacts: @[]
    )
    var scenario = initSdl3WaylandScenario("unit scenario", driver, artifactDir = artifactDir)

    check scenario.step("passing step", proc(): bool = true)
    check not scenario.step("failing step", proc(): bool = false)
    check not scenario.ok
    check scenario.summary.checks.len == 2
    check scenario.artifacts.len == 1
    check fileExists(scenario.artifacts[0])
    check readFile(scenario.artifacts[0]).contains("failing step")
    check scenario.report().contains("unit scenario")
    removeFile(scenario.artifacts[0])

  test "SDL event dispatch drives composition and committed text":
    var input: TextInputHandle
    let driver = Sdl3WaylandDriver(
      headless: initCbssTestDriver(proc(): UiRoot = buildTextInputUi(input), size(220, 100)),
      title: "Event dispatch",
      artifacts: @[]
    )
    check driver.headless.click(byId("name"))
    check driver.dispatchSdlEvent(
      Sdl3Event(kind: sekCompositionStart, timestamp: 1, text: "か"),
      renderAfter = false
    )
    check driver.headless.value(byId("name")) == ""
    check driver.headless.ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "か"

    check driver.dispatchSdlEvent(
      Sdl3Event(kind: sekCompositionUpdate, timestamp: 2, text: "かな"),
      renderAfter = false
    )
    check driver.headless.value(byId("name")) == ""
    check driver.headless.ui.tree.nodes[input.textNode.nodeId.nodeIndex].text == "かな"

    check driver.dispatchSdlEvent(
      Sdl3Event(kind: sekCompositionEnd, timestamp: 3, text: "かな"),
      renderAfter = false
    )
    check driver.headless.value(byId("name")) == ""

    check driver.dispatchSdlEvent(
      Sdl3Event(kind: sekTextInput, timestamp: 4, text: "仮名"),
      renderAfter = false
    )
    check driver.headless.value(byId("name")) == "仮名"

  test "SDL event dispatch commits converted text after an empty preedit":
    var input: TextInputHandle
    let driver = Sdl3WaylandDriver(
      headless: initCbssTestDriver(proc(): UiRoot = buildTextInputUi(input), size(220, 100)),
      title: "IME empty preedit",
      artifacts: @[]
    )
    check driver.headless.click(byId("name"))
    for event in [
      Sdl3Event(kind: sekCompositionStart, timestamp: 1, text: "かんじ"),
      Sdl3Event(kind: sekCompositionUpdate, timestamp: 2, text: "かん"),
      Sdl3Event(kind: sekCompositionUpdate, timestamp: 3, text: ""),
      Sdl3Event(kind: sekCompositionEnd, timestamp: 4, text: "漢字")
    ]:
      check driver.dispatchSdlEvent(event, renderAfter = false)
    check driver.headless.value(byId("name")) == ""

    check driver.dispatchSdlEvent(
      Sdl3Event(kind: sekTextInput, timestamp: 5, text: "漢字"),
      renderAfter = false
    )
    check driver.headless.value(byId("name")) == "漢字"

  test "SDL composition candidate events are recorded for diagnostics":
    var input: TextInputHandle
    let driver = Sdl3WaylandDriver(
      headless: initCbssTestDriver(proc(): UiRoot = buildTextInputUi(input), size(220, 100)),
      title: "Candidates",
      artifacts: @[]
    )
    check driver.compositionCandidates().isNone
    check driver.dispatchSdlEvent(
      Sdl3Event(
        kind: sekCompositionCandidates,
        timestamp: 5,
        candidates: @["仮名", "かな", "カナ"],
        selectedCandidate: 1,
        horizontalCandidates: true
      ),
      renderAfter = false
    )
    let candidates = driver.compositionCandidates()
    check candidates.isSome
    check candidates.get.candidates == @["仮名", "かな", "カナ"]
    check candidates.get.selectedCandidate == 1
    check candidates.get.horizontalCandidates
    check driver.expectCompositionCandidates(["仮名", "かな", "カナ"], selectedCandidate = 1).ok
    check driver.eventSnapshot().contains("composition-candidates")
    check driver.debugBundle().contains("仮名|かな|カナ")

    driver.clearCompositionCandidates()
    check driver.compositionCandidates().isNone

  test "SDL event dispatch updates viewport and text input focus area":
    var input: TextInputHandle
    let driver = Sdl3WaylandDriver(
      headless: initCbssTestDriver(proc(): UiRoot = buildTextInputUi(input), size(220, 100)),
      title: "Resize dispatch",
      artifacts: @[]
    )
    check driver.dispatchSdlEvent(
      Sdl3Event(kind: sekResize, timestamp: 1, width: 320, height: 180),
      renderAfter = false
    )
    check driver.headless.viewport == size(320, 180)
    let center = driver.headless.centerFor(byId("name"))
    check driver.dispatchSdlEvent(
      Sdl3Event(kind: sekPointerDown, timestamp: 2, button: 0, buttonX: center.x, buttonY: center.y),
      renderAfter = false
    )
    check driver.headless.focusedTarget().isSome

  test "text input area follows the caret node when focused text changes":
    var input: TextInputHandle
    let driver = Sdl3WaylandDriver(
      headless: initCbssTestDriver(proc(): UiRoot = buildTextInputUi(input), size(220, 100)),
      title: "Caret area",
      artifacts: @[]
    )
    check driver.click(byId("name"))
    let initialArea = driver.textInputArea()
    check initialArea.isSome
    check initialArea.get.w <= 2.0'f32

    check driver.typeText("abcd")
    let movedArea = driver.textInputArea()
    check movedArea.isSome
    check movedArea.get.x > initialArea.get.x
    check movedArea.get.h == initialArea.get.h

  test "Wayland clipboard helpers keep SDL and headless clipboard in sync":
    var input: TextInputHandle
    let driver = Sdl3WaylandDriver(
      headless: initCbssTestDriver(proc(): UiRoot = buildTextInputUi(input), size(220, 100)),
      title: "Clipboard sync",
      artifacts: @[]
    )
    check driver.setClipboardText("paste-me")
    check driver.headless.clipboard == "paste-me"
    check driver.headless.click(byId("name"))
    check driver.headless.paste()
    check driver.headless.value(byId("name")) == "paste-me"

  test "focused clipboard helpers copy cut and paste selected text":
    var input: TextInputHandle
    let driver = Sdl3WaylandDriver(
      headless: initCbssTestDriver(proc(): UiRoot = buildTextInputUi(input), size(220, 100)),
      title: "Clipboard focused",
      artifacts: @[]
    )
    check driver.headless.click(byId("name"))
    check driver.headless.paste("copy me")
    check driver.headless.selectAll()
    check driver.copyFocused()
    check driver.clipboardText() == "copy me"
    check driver.headless.value(byId("name")) == "copy me"

    check driver.cutFocused()
    check driver.clipboardText() == "copy me"
    check driver.headless.value(byId("name")) == ""

    check driver.pasteFocused()
    check driver.headless.value(byId("name")) == "copy me"

  test "SDL dispatch routes committed text only to the current focused control":
    var input: TextInputHandle
    var area: TextAreaHandle
    let driver = Sdl3WaylandDriver(
      headless: initCbssTestDriver(proc(): UiRoot = buildTwoTextControlsUi(input, area), size(260, 160)),
      title: "Focus routing",
      artifacts: @[]
    )

    let inputCenter = driver.headless.centerFor(byId("name"))
    check driver.dispatchSdlEvent(
      Sdl3Event(kind: sekPointerDown, timestamp: 1, button: 0, buttonX: inputCenter.x, buttonY: inputCenter.y),
      renderAfter = false
    )
    check driver.headless.focusedTarget().isSome
    check driver.dispatchSdlEvent(
      Sdl3Event(kind: sekTextInput, timestamp: 2, text: "a"),
      renderAfter = false
    )
    check driver.headless.value(byId("name")) == "a"
    check driver.headless.value(byId("message")) == ""

    check driver.dispatchSdlEvent(
      Sdl3Event(kind: sekKeyDown, timestamp: 3, key: "Tab"),
      renderAfter = false
    )
    check driver.headless.focusedTarget().isSome
    check driver.headless.focusedTarget().get == area.container.nodeId

    check driver.dispatchSdlEvent(
      Sdl3Event(kind: sekTextInput, timestamp: 4, text: "b"),
      renderAfter = false
    )
    check driver.headless.value(byId("name")) == "a"
    check driver.headless.value(byId("message")) == "b"
    check driver.textInputArea().isSome
