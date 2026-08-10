import std/[math, options, sequtils, unittest]

import clay_board_style_system
import clay_board_style_system/testing/test_driver

proc animationStyle(
    name: string;
    duration = 1.0'f32;
    delay = 0.0'f32;
    iterations = 1.0'f32;
    direction = adNormal;
    fillMode = afNone;
    playState = apsRunning
): UiStyle =
  uiStyle([
    decl("animation-name", keyword(name)),
    decl("animation-duration", number(duration)),
    decl("animation-delay", number(delay)),
    decl("animation-timing-function", keyword("linear")),
    decl("animation-iteration-count", number(iterations)),
    animationDirection(direction),
    animationFillMode(fillMode),
    animationPlayState(playState)
  ])

proc combined(styles: openArray[UiStyle]): UiStyle =
  var declarations: seq[Declaration]
  for style in styles:
    declarations.add style.declarations
  uiStyle(declarations)

suite "declarative style keyframes":
  test "animation-name binds registered opacity keyframes":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("fade", [
      styleKeyframe(0, [decl("opacity", number(0))]),
      styleKeyframe(1, [decl("opacity", number(1))])
    ]))
    let panel = ui.box(
      combined([
        uiStyle([decl("width", px(120)), decl("height", px(40))]),
        animationStyle("fade", fillMode = afForwards)
      ]),
      id = "panel"
    )
    let driver = initCbssTestDriver(ui, size(320, 180))
    let initialRect = driver.rectFor(panel.id)

    check ui.activeStyleAnimationCount == 1
    check driver.styles.styles[panel.id.nodeIndex].visual.opacity == 0
    driver.advanceTime(0.5)
    check abs(driver.styles.styles[panel.id.nodeIndex].visual.opacity - 0.5) < 0.0001
    check driver.rectFor(panel.id) == initialRect
    check driver.scheduler.consumeDirty() == {ddPaint, ddAnimation}
    driver.advanceTime(0.5)
    check driver.styles.styles[panel.id.nodeIndex].visual.opacity == 1
    check ui.activeStyleAnimationCount == 0

  test "foreground and background colors use prepared interpolation":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("colors", [
      styleKeyframe(0, [
        decl("color", colorValue(rgb(1, 0, 0))),
        decl("background-color", colorValue(rgb(0, 0, 0)))
      ]),
      styleKeyframe(1, [
        decl("color", colorValue(rgb(0, 0, 1))),
        decl("background-color", colorValue(rgb(1, 1, 1)))
      ])
    ]))
    let panel = ui.box(animationStyle("colors", fillMode = afForwards))
    let driver = initCbssTestDriver(ui, size(200, 100))
    driver.advanceTime(0.5)

    let foreground = driver.styles.styles[panel.id.nodeIndex].text.color.get
    let background = driver.styles.styles[panel.id.nodeIndex].box.backgroundColor.get
    check foreground.r > 0.4 and foreground.b > 0.4
    check background.r > 0.3 and background.r < 0.8

  test "multiple animation names run independently on one node":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("fade", [
      styleKeyframe(0, [decl("opacity", number(0))]),
      styleKeyframe(1, [decl("opacity", number(1))])
    ]))
    ui.registerStyleKeyframes(styleKeyframes("tint", [
      styleKeyframe(0, [
        decl("background-color", colorValue(rgb(1, 0, 0)))
      ]),
      styleKeyframe(1, [
        decl("background-color", colorValue(rgb(0, 0, 1)))
      ])
    ]))
    let panel = ui.box(uiStyle([
      animationNames("fade", "tint"),
      animationDurations(1.0'f32, 2.0'f32),
      animationTimingFunctions("linear"),
      animationFillModes(afForwards)
    ]))
    let driver = initCbssTestDriver(ui, size(200, 100))

    check ui.activeStyleAnimationCount == 2
    driver.advanceTime(1)
    check driver.styles.styles[panel.id.nodeIndex].visual.opacity == 1
    let halfway = driver.styles.styles[
      panel.id.nodeIndex
    ].box.backgroundColor.get
    check halfway.r > 0.4 and halfway.b > 0.4
    check ui.activeStyleAnimationCount == 1
    driver.advanceTime(1)
    check ui.activeStyleAnimationCount == 0
    check driver.styles.styles[
      panel.id.nodeIndex
    ].box.backgroundColor.get.b > 0.99

  test "missing definitions preserve animation list positions":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("fade", [
      styleKeyframe(0, [decl("opacity", number(0))]),
      styleKeyframe(1, [decl("opacity", number(1))])
    ]))
    let panel = ui.box(uiStyle([
      animationNames("not-registered", "fade"),
      animationDurations(30.0'f32, 1.0'f32),
      animationTimingFunctions("linear"),
      animationFillModes(afForwards)
    ]))
    let driver = initCbssTestDriver(ui, size(200, 100))

    check ui.activeStyleAnimationCount == 1
    driver.advanceTime(1)
    check driver.styles.styles[panel.id.nodeIndex].visual.opacity == 1
    check ui.activeStyleAnimationCount == 0

  test "per-animation play state does not pause sibling tracks":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("fade", [
      styleKeyframe(0, [decl("opacity", number(0))]),
      styleKeyframe(1, [decl("opacity", number(1))])
    ]))
    ui.registerStyleKeyframes(styleKeyframes("tint", [
      styleKeyframe(0, [
        decl("background-color", colorValue(rgb(1, 0, 0)))
      ]),
      styleKeyframe(1, [
        decl("background-color", colorValue(rgb(0, 0, 1)))
      ])
    ]))
    let panel = ui.box(uiStyle([
      animationNames("fade", "tint"),
      animationDurations(2.0'f32),
      animationTimingFunctions("linear"),
      animationPlayStates(apsPaused, apsRunning),
      animationFillModes(afForwards)
    ]))
    let driver = initCbssTestDriver(ui, size(200, 100))
    driver.advanceTime(1)

    check driver.styles.styles[panel.id.nodeIndex].visual.opacity == 0
    let background = driver.styles.styles[
      panel.id.nodeIndex
    ].box.backgroundColor.get
    check background.r > 0.4 and background.b > 0.4
    check ui.activeStyleAnimationCount == 2

  test "typed transform keyframes update paint and hit domains":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("move", [
      styleKeyframe(0, [
        decl("transform", transformValue(
          translate(px(0), px(0)), rotate(0)
        ))
      ]),
      styleKeyframe(1, [
        decl("transform", transformValue(
          translate(px(100), px(20)), rotate(90)
        ))
      ])
    ]))
    let panel = ui.box(combined([
      uiStyle([decl("width", px(20)), decl("height", px(20))]),
      animationStyle("move", fillMode = afForwards)
    ]))
    let driver = initCbssTestDriver(ui, size(240, 120))
    let initialRect = driver.rectFor(panel.id)
    let initialRegion = driver.hitRegions.filterIt(it.node == panel.id)[0]
    driver.advanceTime(0.5)

    let transform = driver.styles.styles[
      panel.id.nodeIndex
    ].transform.operations
    check transform.len == 2
    check abs(transform[0].xLength.get.value - 50) < 0.0001
    check abs(transform[0].yLength.get.value - 10) < 0.0001
    check abs(transform[1].angle - 45) < 0.0001
    check driver.rectFor(panel.id) == initialRect
    check ddHit in driver.scheduler.invalidation.domains
    let movedRegion = driver.hitRegions.filterIt(it.node == panel.id)[0]
    check movedRegion.shape.isSome
    check initialRegion.shape.isSome
    check movedRegion.shape.get.transform != initialRegion.shape.get.transform
    let movedCenter = movedRegion.shape.get.transform.transformPoint(
      vec2(initialRect.get.w * 0.5, initialRect.get.h * 0.5)
    )
    check driver.hitAt(movedCenter) == some(panel.id)

  test "missing endpoints use the underlying computed value":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("peak", [
      styleKeyframe(0.5, [decl("opacity", number(1))])
    ]))
    let panel = ui.box(combined([
      uiStyle([decl("opacity", number(0.2))]),
      animationStyle("peak")
    ]))
    let driver = initCbssTestDriver(ui, size(200, 100))
    check abs(driver.styles.styles[panel.id.nodeIndex].visual.opacity - 0.2) < 0.0001
    driver.advanceTime(0.5)
    check driver.styles.styles[panel.id.nodeIndex].visual.opacity == 1
    driver.advanceTime(0.5)
    check abs(driver.styles.styles[panel.id.nodeIndex].visual.opacity - 0.2) < 0.0001

  test "alternate direction and iteration count share the animation clock":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("alternate", [
      styleKeyframe(0, [decl("opacity", number(0))]),
      styleKeyframe(1, [decl("opacity", number(1))])
    ]))
    let panel = ui.box(animationStyle(
      "alternate", duration = 1, iterations = 2,
      direction = adAlternate, fillMode = afForwards
    ))
    let driver = initCbssTestDriver(ui, size(200, 100))
    driver.advanceTime(0.25)
    check abs(driver.styles.styles[panel.id.nodeIndex].visual.opacity - 0.25) < 0.0001
    driver.advanceTime(1.0)
    check abs(driver.styles.styles[panel.id.nodeIndex].visual.opacity - 0.75) < 0.0001
    driver.advanceTime(0.75)
    check driver.styles.styles[panel.id.nodeIndex].visual.opacity == 0

  test "backwards fill applies during delay and negative delay starts in progress":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("delayed", [
      styleKeyframe(0, [decl("opacity", number(0.1))]),
      styleKeyframe(1, [decl("opacity", number(1))])
    ]))
    let root = ui.box()
    let delayed = ui.box(combined([
      uiStyle([decl("opacity", number(0.8))]),
      animationStyle("delayed", delay = 2, fillMode = afBackwards)
    ]), parent = some(root))
    let advanced = ui.box(combined([
      uiStyle([decl("opacity", number(0))]),
      animationStyle("delayed", delay = -0.5, fillMode = afForwards)
    ]), parent = some(root))
    let driver = initCbssTestDriver(ui, size(200, 100))
    check abs(driver.styles.styles[delayed.id.nodeIndex].visual.opacity - 0.1) < 0.0001
    check abs(driver.styles.styles[advanced.id.nodeIndex].visual.opacity - 0.55) < 0.0001

  test "paused declarations resume without restarting":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("pause", [
      styleKeyframe(0, [decl("opacity", number(0))]),
      styleKeyframe(1, [decl("opacity", number(1))])
    ]))
    let panel = ui.box(animationStyle(
      "pause", duration = 2, fillMode = afForwards,
      playState = apsPaused
    ))
    let driver = initCbssTestDriver(ui, size(200, 100))
    check driver.styles.styles[panel.id.nodeIndex].visual.opacity == 0
    driver.advanceTime(1)
    check driver.styles.styles[panel.id.nodeIndex].visual.opacity == 0

    driver.refresh()
    check driver.styles.styles[panel.id.nodeIndex].visual.opacity == 0

    panel.applyStyle(uiStyle([animationPlayState(apsRunning)]))
    driver.refresh()
    driver.advanceTime(1)
    check abs(driver.styles.styles[panel.id.nodeIndex].visual.opacity - 0.5) < 0.0001

  test "completed animation does not restart on unrelated refresh":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("once", [
      styleKeyframe(0, [decl("opacity", number(0))]),
      styleKeyframe(1, [decl("opacity", number(1))])
    ]))
    let panel = ui.box(combined([
      uiStyle([decl("opacity", number(0.25))]),
      animationStyle("once", fillMode = afForwards)
    ]))
    let other = ui.box(uiStyle([decl("width", px(10))]))
    let driver = initCbssTestDriver(ui, size(200, 100))
    driver.advanceTime(1)
    check ui.activeStyleAnimationCount == 0
    other.applyStyle(uiStyle([decl("width", px(20))]))
    driver.refresh()
    check ui.activeStyleAnimationCount == 0
    check driver.styles.styles[panel.id.nodeIndex].visual.opacity == 1

  test "reduced motion completes active keyframes without restarting":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("reduced", [
      styleKeyframe(0, [decl("opacity", number(0))]),
      styleKeyframe(1, [decl("opacity", number(1))])
    ]))
    let panel = ui.box(animationStyle(
      "reduced", duration = 30, fillMode = afForwards
    ))
    let driver = initCbssTestDriver(ui, size(200, 100))
    driver.advanceTime(0.5)
    check driver.styles.styles[panel.id.nodeIndex].visual.opacity < 0.1

    ui.setReducedMotion(true)
    driver.advanceTime(0)
    check driver.styles.styles[panel.id.nodeIndex].visual.opacity == 1
    check ui.activeStyleAnimationCount == 0

  test "unregistered definitions cancel tracks during reconciliation":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("temporary", [
      styleKeyframe(0, [decl("opacity", number(0))]),
      styleKeyframe(1, [decl("opacity", number(1))])
    ]))
    discard ui.box(animationStyle("temporary", duration = 30))
    let driver = initCbssTestDriver(ui, size(200, 100))
    check ui.activeStyleAnimationCount == 1
    check ui.unregisterStyleKeyframes("temporary")
    check ui.activeStyleAnimationCount == 0
    driver.refresh()
    check not ui.hasStyleKeyframes("temporary")

  test "infinite iterations remain active until explicitly cancelled":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("forever", [
      styleKeyframe(0, [decl("opacity", number(0))]),
      styleKeyframe(1, [decl("opacity", number(1))])
    ]))
    let panel = ui.box(combined([
      animationStyle("forever", duration = 0.25),
      uiStyle([decl("animation-iteration-count", keyword("infinite"))])
    ]))
    let driver = initCbssTestDriver(ui, size(200, 100))
    driver.advanceTime(10)
    check ui.activeStyleAnimationCount == 1
    check ui.disposeSubtree(panel, driver.input)
    check ui.activeStyleAnimationCount == 0

  test "definition replacement restarts the named animation":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("replaceable", [
      styleKeyframe(0, [decl("opacity", number(0))]),
      styleKeyframe(1, [decl("opacity", number(1))])
    ]))
    let panel = ui.box(animationStyle("replaceable", fillMode = afForwards))
    let driver = initCbssTestDriver(ui, size(200, 100))
    driver.advanceTime(1)
    ui.registerStyleKeyframes(styleKeyframes("replaceable", [
      styleKeyframe(0, [decl("opacity", number(1))]),
      styleKeyframe(1, [decl("opacity", number(0.25))])
    ]))
    driver.refresh()
    check ui.activeStyleAnimationCount == 1
    check driver.styles.styles[panel.id.nodeIndex].visual.opacity == 1
    driver.advanceTime(1)
    check abs(driver.styles.styles[panel.id.nodeIndex].visual.opacity - 0.25) < 0.0001

  test "subtree disposal cancels declarative animation tracks":
    let ui = initUiRoot()
    ui.registerStyleKeyframes(styleKeyframes("long", [
      styleKeyframe(0, [decl("opacity", number(0))]),
      styleKeyframe(1, [decl("opacity", number(1))])
    ]))
    let parent = ui.box(id = "parent")
    let child = ui.box(
      animationStyle("long", duration = 30),
      parent = some(parent)
    )
    let driver = initCbssTestDriver(ui, size(200, 100))
    check ui.activeStyleAnimationCount == 1
    check ui.disposeSubtree(child, driver.input)
    check ui.activeStyleAnimationCount == 0

  test "registration and authoring reject invalid definitions":
    expect ValueError:
      discard styleKeyframe(-0.1, [decl("opacity", number(1))])
    expect ValueError:
      discard styleKeyframe(0, [decl("width", px(10))])
    expect ValueError:
      discard styleKeyframes("", [
        styleKeyframe(0, [decl("opacity", number(1))])
      ])
    expect ValueError:
      discard styleKeyframes("bad", [
        styleKeyframe(1, [decl("opacity", number(1))]),
        styleKeyframe(0, [decl("opacity", number(0))])
      ])
    let ui = initUiRoot()
    expect ValueError:
      ui.registerStyleKeyframes(StyleKeyframes(
        name: "bypassed",
        steps: @[StyleKeyframe(
          offset: 2,
          declarations: @[decl("opacity", number(1))]
        )]
      ))
