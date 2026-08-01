import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

type TransitionScreen = enum
  tsHome,
  tsSettings,
  tsDetails

proc displayFor(ui: UiRoot; node: NodeHandle): DisplayKind =
  var diagnostics: Diagnostics
  let styles = resolveTreeStyles(
    ui.tree,
    ui.styleSheets(),
    defaultProperties(),
    diagnostics
  )
  check not diagnostics.hasErrors
  styles.styles[node.id.nodeIndex].layout.display

suite "navigation transition hooks":
  test "transition construction rejects unusable timing and hooks":
    proc hook(context: NavigationTransitionContext[TransitionScreen]) =
      discard

    expect ValueError:
      discard navigationTransition[TransitionScreen](0.0, hook)
    expect ValueError:
      discard navigationTransition[TransitionScreen](-1.0, hook)
    expect ValueError:
      discard navigationTransition[TransitionScreen](0.2, hook, 0.0)
    expect ValueError:
      discard navigationTransition[TransitionScreen](0.2, nil)
    expect ValueError:
      discard navigationTransition[TransitionScreen](
        0.2,
        hook,
        dirtyDomains = {}
      )

  test "initial activation does not manufacture a transition":
    var phases: seq[NavigationTransitionPhase]
    let spec = navigationTransition[TransitionScreen](
      0.2,
      proc(context: NavigationTransitionContext[TransitionScreen]) =
        phases.add context.phase
    )
    let navigator = initStackNavigator(tsHome)
    let ui = initUiRoot()
    let home = ui.box()
    let host = initNavigationScreenHost(ui, navigator, some(spec))
    host.registerScreen(tsHome, home)
    var interaction = initInteractionState()
    var scheduler = initFrameScheduler()

    check host.sync(interaction, scheduler, 10.0)
    check not host.transitionActive()
    check phases.len == 0
    check scheduler.waitTimeoutMs(10.0) == -1
    check not home.inert()

  test "a scheduled transition keeps only its outgoing paint visible":
    var contexts: seq[NavigationTransitionContext[TransitionScreen]]
    let spec = navigationTransition[TransitionScreen](
      0.2,
      (proc(context: NavigationTransitionContext[TransitionScreen]) =
        contexts.add context),
      frameIntervalSeconds = 0.05
    )
    let navigator = initStackNavigator(tsHome)
    let ui = initUiRoot()
    let app = ui.box()
    let home = ui.box(parent = some(app))
    let settings = ui.box(parent = some(app))
    let host = initNavigationScreenHost(ui, navigator, some(spec))
    host.registerScreen(tsHome, home)
    host.registerScreen(tsSettings, settings)
    var interaction = initInteractionState()
    var scheduler = initFrameScheduler()
    check host.sync(interaction, scheduler, 1.0)

    check navigator.push(tsSettings)
    check host.sync(interaction, scheduler, 2.0)
    check host.transitionActive()
    check contexts.len == 1
    check contexts[0].phase == ntpStarted
    check contexts[0].kind == nckPush
    check contexts[0].previous.destination == tsHome
    check contexts[0].current.destination == tsSettings
    check contexts[0].outgoingRoot.id == home.id
    check contexts[0].incomingRoot.id == settings.id
    check contexts[0].progress == 0.0
    check home.inert()
    check not settings.inert()
    check ui.displayFor(home) == dkFlex
    check ui.displayFor(settings) == dkFlex
    check scheduler.consumeDirty() == {ddStyle, ddPaint, ddHit}
    check scheduler.nextDeadline == some(2.05)

    scheduler.clearDeadline()
    check host.advanceTransition(scheduler, 2.1)
    check host.transitionActive()
    check contexts[^1].phase == ntpAdvanced
    check abs(contexts[^1].progress - 0.5) < 0.0001
    check scheduler.nextDeadline == some(2.15)

    scheduler.clearDeadline()
    discard scheduler.consumeDirty()
    check host.advanceTransition(scheduler, 2.2)
    check not host.transitionActive()
    check contexts[^1].phase == ntpCompleted
    check contexts[^1].progress == 1.0
    check ui.displayFor(home) == dkNone
    check ui.displayFor(settings) == dkFlex
    check scheduler.nextDeadline.isNone
    check scheduler.consumeDirty() == {ddStyle, ddPaint, ddHit}

  test "legacy sync remains an immediate switch even when a hook is configured":
    var calls = 0
    let spec = navigationTransition[TransitionScreen](
      0.2,
      proc(context: NavigationTransitionContext[TransitionScreen]) =
        inc calls
    )
    let navigator = initStackNavigator(tsHome)
    let ui = initUiRoot()
    let home = ui.box()
    let settings = ui.box()
    let host = initNavigationScreenHost(ui, navigator, some(spec))
    host.registerScreen(tsHome, home)
    host.registerScreen(tsSettings, settings)
    var interaction = initInteractionState()
    check host.sync(interaction)

    check navigator.push(tsSettings)
    check host.sync(interaction)
    check calls == 0
    check not host.transitionActive()
    check ui.displayFor(home) == dkNone
    check ui.displayFor(settings) == dkFlex

  test "same-screen history entries do not start a visual transition":
    var calls = 0
    let spec = navigationTransition[TransitionScreen](
      0.2,
      proc(context: NavigationTransitionContext[TransitionScreen]) =
        inc calls
    )
    let navigator = initStackNavigator(tsHome)
    let ui = initUiRoot()
    let home = ui.box()
    let host = initNavigationScreenHost(ui, navigator, some(spec))
    host.registerScreen(tsHome, home)
    var interaction = initInteractionState()
    var scheduler = initFrameScheduler()
    check host.sync(interaction, scheduler, 0.0)

    check navigator.push(tsHome)
    check host.sync(interaction, scheduler, 1.0)
    check calls == 0
    check not host.transitionActive()
    check ui.displayFor(home) == dkFlex

  test "a second navigation cancels the old transition before starting the next":
    var phases: seq[NavigationTransitionPhase]
    var destinations: seq[TransitionScreen]
    let spec = navigationTransition[TransitionScreen](
      1.0,
      proc(context: NavigationTransitionContext[TransitionScreen]) =
        phases.add context.phase
        destinations.add context.current.destination
    )
    let navigator = initStackNavigator(tsHome)
    let ui = initUiRoot()
    let home = ui.box()
    let settings = ui.box()
    let details = ui.box()
    let host = initNavigationScreenHost(ui, navigator, some(spec))
    host.registerScreen(tsHome, home)
    host.registerScreen(tsSettings, settings)
    host.registerScreen(tsDetails, details)
    var interaction = initInteractionState()
    var scheduler = initFrameScheduler()
    check host.sync(interaction, scheduler, 0.0)

    check navigator.push(tsSettings)
    check host.sync(interaction, scheduler, 1.0)
    scheduler.clearDeadline()
    discard scheduler.consumeDirty()
    check host.advanceTransition(scheduler, 1.25)
    check navigator.push(tsDetails)
    check host.sync(interaction, scheduler, 1.3)

    check phases == @[ntpStarted, ntpAdvanced, ntpCancelled, ntpStarted]
    check destinations == @[tsSettings, tsSettings, tsSettings, tsDetails]
    check ui.displayFor(home) == dkNone
    check ui.displayFor(settings) == dkFlex
    check ui.displayFor(details) == dkFlex
    check settings.inert()
    check not details.inert()

  test "manual cancellation settles the outgoing screen and permits reconfiguration":
    var phases: seq[NavigationTransitionPhase]
    let spec = navigationTransition[TransitionScreen](
      0.5,
      proc(context: NavigationTransitionContext[TransitionScreen]) =
        phases.add context.phase
    )
    let navigator = initStackNavigator(tsHome)
    let ui = initUiRoot()
    let home = ui.box()
    let settings = ui.box()
    let host = initNavigationScreenHost(ui, navigator, some(spec))
    host.registerScreen(tsHome, home)
    host.registerScreen(tsSettings, settings)
    var interaction = initInteractionState()
    var scheduler = initFrameScheduler()
    check host.sync(interaction, scheduler, 0.0)
    check navigator.push(tsSettings)
    check host.sync(interaction, scheduler, 1.0)

    expect ValueError:
      host.setTransition(none(NavigationTransitionSpec[TransitionScreen]))
    check host.cancelTransition(scheduler)
    check not host.cancelTransition(scheduler)
    check phases == @[ntpStarted, ntpCancelled]
    check not host.transitionActive()
    check ui.displayFor(home) == dkNone
    host.setTransition(none(NavigationTransitionSpec[TransitionScreen]))

  test "screen disposal cancels transitions before invalidating hook handles":
    var phases: seq[NavigationTransitionPhase]
    let spec = navigationTransition[TransitionScreen](
      0.5,
      proc(context: NavigationTransitionContext[TransitionScreen]) =
        check context.outgoingRoot.valid()
        check context.incomingRoot.valid()
        phases.add context.phase
    )
    let navigator = initStackNavigator(tsHome)
    let ui = initUiRoot()
    let home = ui.box()
    let settings = ui.box()
    let host = initNavigationScreenHost(ui, navigator, some(spec))
    host.registerScreen(tsHome, home)
    host.registerScreen(tsSettings, settings)
    var interaction = initInteractionState()
    var scheduler = initFrameScheduler()
    check host.sync(interaction, scheduler, 0.0)
    check navigator.push(tsSettings)
    check host.sync(interaction, scheduler, 1.0)

    check host.unregisterScreen(tsHome, interaction)
    check phases == @[ntpStarted, ntpCancelled]
    check not home.valid()
    check settings.valid()
    check not host.transitionActive()
