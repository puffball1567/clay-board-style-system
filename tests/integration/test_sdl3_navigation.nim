import std/[options, os, unittest]

import clay_board_style_system
import clay_board_style_system/testing/test_driver
import clay_board_style_system/testing/integration/sdl3_wayland_driver

type NavigationScreen = enum
  nsHome,
  nsSettings,
  nsDetails

const transitionStylePriority = navigationScreenHostStylePriority - 1

proc expectDisplay(
    driver: Sdl3WaylandDriver;
    node: NodeHandle;
    expected: DisplayKind
): tuple[ok: bool, message: string] =
  driver.refresh()
  let actual = driver.headless.styles.styles[node.id.nodeIndex].layout.display
  (
    actual == expected,
    "expected display " & $expected & ", got " & $actual
  )

suite "SDL3 Wayland navigation":
  test "link transition and deep link render through a real window":
    let probe = waylandProbe()
    if getEnv("CBSS_RUN_WAYLAND_E2E") != "1" or not probe.canUseWayland:
      skip()
    else:
      let navigator = initStackNavigator(nsHome)
      let ui = initUiRoot()
      let app = ui.box(
        uiStyle([
          decl("width", px(420)),
          decl("height", px(240)),
          decl("padding", px(16)),
          decl("background-color", colorValue(rgb(0.06, 0.08, 0.11)))
        ]),
        id = "navigation-app"
      )
      let screenStyle = uiStyle([
        decl("width", px(388)),
        decl("height", px(208)),
        decl("padding", px(18)),
        decl("gap", px(12)),
        decl("flex-direction", keyword("column"))
      ])
      let home = ui.box(screenStyle, parent = some(app), id = "home-screen")
      ui.pushParent(home)
      discard ui.text("Home", id = "home-heading")
      discard ui.link(
        navigator,
        nsSettings,
        "Open settings",
        style = uiStyle([
          decl("width", px(160)),
          decl("height", px(36)),
          decl("padding", px(8)),
          decl("background-color", colorValue(rgb(0.18, 0.48, 0.82)))
        ]),
        id = "settings-link"
      )
      ui.popParent()

      let settings = ui.box(screenStyle, parent = some(app), id = "settings-screen")
      ui.pushParent(settings)
      discard ui.text("Settings", id = "settings-heading")
      ui.popParent()

      let details = ui.box(screenStyle, parent = some(app), id = "details-screen")
      ui.pushParent(details)
      discard ui.text("Details", id = "details-heading")
      ui.popParent()

      let transition = navigationTransition[NavigationScreen](
        0.1,
        proc(context: NavigationTransitionContext[NavigationScreen]) =
          case context.phase
          of ntpStarted:
            ui.setNodeStyle(
              context.outgoingRoot.id,
              uiStyle([decl("opacity", number(1.0))]),
              priority = transitionStylePriority
            )
            ui.setNodeStyle(
              context.incomingRoot.id,
              uiStyle([decl("opacity", number(0.0))]),
              priority = transitionStylePriority
            )
          of ntpAdvanced:
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
      )
      let host = initNavigationScreenHost(ui, navigator, some(transition))
      host.registerScreen(nsHome, home)
      host.registerScreen(nsSettings, settings)
      host.registerScreen(nsDetails, details)
      var interaction = initInteractionState()
      var scheduler = initFrameScheduler()
      check host.sync(interaction, scheduler, 0.0)

      let codec = deepLinkCodec[NavigationScreen](
        ["cbss-nav"],
        proc(url: string): Option[NavigationScreen] =
          if url == "cbss-nav://details": some(nsDetails)
          else: none(NavigationScreen)
      )

      var driver = initSdl3WaylandDriver(
        ui,
        size(420, 240),
        title = "CBSS Wayland Navigation"
      )
      var scenario = initSdl3WaylandScenario(
        "native-navigation",
        driver,
        getEnv("CBSS_WAYLAND_ARTIFACT_DIR")
      )
      try:
        driver.render()
        var exposed = false
        for attempt in 0 ..< 50:
          discard driver.pollAndDispatch()
          for event in driver.lastEvents:
            if event.kind == sekExpose:
              exposed = true
          if exposed:
            break
          delay(5)
        check exposed
        check scenario.expect("home is initially visible", driver.expectDisplay(home, dkFlex))
        check scenario.expect("settings is initially hidden", driver.expectDisplay(settings, dkNone))

        check scenario.step("activate settings link", proc(): bool =
          driver.click(byId("settings-link")) and
            host.sync(interaction, scheduler, 1.0)
        )
        check host.transitionActive()
        check scenario.expect("outgoing home remains paintable", driver.expectDisplay(home, dkFlex))
        check scenario.expect("incoming settings is paintable", driver.expectDisplay(settings, dkFlex))

        check scenario.step("complete settings transition", proc(): bool =
          host.advanceTransition(scheduler, 1.1)
        )
        check not host.transitionActive()
        check scenario.expect("home is hidden after completion", driver.expectDisplay(home, dkNone))
        check scenario.expect("settings remains visible", driver.expectDisplay(settings, dkFlex))

        check scenario.step("navigate typed deep link", proc(): bool =
          let routed = navigator.navigateDeepLink(codec, "cbss-nav://details")
          routed.status == dlsNavigated and
            host.sync(interaction, scheduler, 2.0)
        )
        check scenario.step("complete deep-link transition", proc(): bool =
          host.advanceTransition(scheduler, 2.1)
        )
        check scenario.expect("details is visible", driver.expectDisplay(details, dkFlex))
        check scenario.expect("settings is hidden", driver.expectDisplay(settings, dkNone))
        check scenario.ok()
      finally:
        driver.close()
