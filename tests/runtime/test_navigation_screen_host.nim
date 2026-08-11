import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/generated/default_properties

type HostScreen = enum
  hsHome,
  hsSettings,
  hsDetails

proc resolvedStyles(ui: UiRoot): ResolvedTree =
  var diagnostics: Diagnostics
  result = resolveTreeStyles(
    ui.tree,
    ui.styleSheets(),
    defaultProperties(),
    diagnostics
  )
  check not diagnostics.hasErrors

suite "retained navigation screen host":
  test "construction rejects missing runtime dependencies":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    expect ValueError:
      discard initNavigationScreenHost(UiRoot(nil), navigator)
    expect ValueError:
      discard initNavigationScreenHost(ui, Navigator[HostScreen](nil))

  test "an empty custom navigator is a safe no-op":
    proc emptySnapshot(): NavigationSnapshot[HostScreen] =
      NavigationSnapshot[HostScreen](entries: @[], currentIndex: -1)
    proc noDestination(
        destination: HostScreen
    ): Option[NavigationChange[HostScreen]] =
      none(NavigationChange[HostScreen])
    proc noStep(): Option[NavigationChange[HostScreen]] =
      none(NavigationChange[HostScreen])
    let navigator = initNavigator(NavigationDriver[HostScreen](
      snapshot: emptySnapshot,
      push: noDestination,
      replace: noDestination,
      back: noStep,
      forward: noStep
    ))
    let ui = initUiRoot()
    let host = initNavigationScreenHost(ui, navigator)
    var interaction = initInteractionState()

    check host.pendingDestination().isNone
    check not host.sync(interaction)
    check host.activeScreen().isNone
    check not host.sync(interaction)

  test "only the active retained screen participates in UI behavior":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let app = ui.box(uiStyle([
      decl("width", px(320)),
      decl("height", px(200))
    ]))
    let homeRoot = ui.box(
      uiStyle([decl("width", px(120)), decl("height", px(80))]),
      parent = some(app)
    )
    ui.pushParent(homeRoot)
    let homeButton = ui.button("Home")
    ui.popParent()
    let settingsRoot = ui.box(
      uiStyle([decl("width", px(140)), decl("height", px(90))]),
      parent = some(app)
    )
    ui.pushParent(settingsRoot)
    let settingsButton = ui.button("Settings")
    ui.popParent()
    var settingsClicks = 0
    settingsButton.onClick = proc(event: DispatchResult): EventOutcome =
      inc settingsClicks
      true

    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(hsHome, homeRoot)
    host.registerScreen(hsSettings, settingsRoot)
    var interaction = initInteractionState()
    let retainedNodeCount = ui.tree.nodes.len
    let homeId = homeRoot.id
    let settingsId = settingsRoot.id

    check host.sync(interaction)
    check host.activeScreen().get.destination == hsHome
    check not homeRoot.inert()
    check settingsRoot.inert()
    check not settingsButton.container.emit(InputEvent(kind: iekClick))
    check settingsClicks == 0
    check homeButton.container.nodeId in ui.focusTargets()
    check settingsButton.container.nodeId notin ui.focusTargets()

    let initialAccessibility = ui.accessibilityTree()
    var settingsHidden = false
    for node in initialAccessibility:
      if node.node == settingsButton.container.nodeId:
        settingsHidden = node.hidden
    check settingsHidden

    let initialStyles = ui.resolvedStyles()
    check initialStyles.styles[homeId.nodeIndex].layout.display == dkFlex
    check initialStyles.styles[settingsId.nodeIndex].layout.display == dkNone
    let initialLayout = computeLayout(ui.tree, initialStyles, size(320, 200))
    let initialHits = buildHitRegions(initialLayout, initialStyles)
    for region in initialHits:
      check region.node != settingsButton.container.nodeId

    navigator.push(hsSettings)
    check host.pendingDestination() == some(hsSettings)
    check host.sync(interaction)

    check host.activeScreen().get.destination == hsSettings
    check homeRoot.inert()
    check not settingsRoot.inert()
    check settingsButton.container.emit(InputEvent(kind: iekClick))
    check settingsClicks == 1
    check ui.tree.nodes.len == retainedNodeCount
    check homeRoot.id == homeId
    check settingsRoot.id == settingsId

    let settingsStyles = ui.resolvedStyles()
    check settingsStyles.styles[homeId.nodeIndex].layout.display == dkNone
    check settingsStyles.styles[settingsId.nodeIndex].layout.display == dkFlex

  test "back and forward restore focus for each retained history entry":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let app = ui.box()
    let homeRoot = ui.box(parent = some(app))
    ui.pushParent(homeRoot)
    let homeFirst = ui.button("Home first")
    let homeLast = ui.button("Home last")
    ui.popParent()
    let settingsRoot = ui.box(parent = some(app))
    ui.pushParent(settingsRoot)
    let settingsFirst = ui.button("Settings first")
    let settingsLast = ui.button("Settings last")
    ui.popParent()

    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(hsHome, homeRoot, focusFallback = some(homeFirst.container))
    host.registerScreen(
      hsSettings,
      settingsRoot,
      focusFallback = some(settingsFirst.container)
    )
    var interaction = initInteractionState()
    check host.sync(interaction)
    discard ui.setFocus(
      interaction,
      some(homeLast.container.nodeId),
      focusVisible = true
    )

    navigator.push(hsSettings)
    check host.sync(interaction)
    check interaction.focusedTarget == some(settingsFirst.container.nodeId)
    discard ui.setFocus(
      interaction,
      some(settingsLast.container.nodeId),
      focusVisible = true
    )

    navigator.back()
    check host.sync(interaction)
    check interaction.focusedTarget == some(homeLast.container.nodeId)

    navigator.forward()
    check host.sync(interaction)
    check interaction.focusedTarget == some(settingsLast.container.nodeId)

  test "an unregistered destination keeps the current screen until registered":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let app = ui.box()
    let homeRoot = ui.box(parent = some(app))
    let detailsRoot = ui.box(parent = some(app))
    ui.pushParent(detailsRoot)
    let detailsButton = ui.button("Details")
    ui.popParent()
    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(hsHome, homeRoot)
    var interaction = initInteractionState()
    check host.sync(interaction)

    navigator.push(hsDetails)
    check not host.sync(interaction)
    check host.pendingDestination() == some(hsDetails)
    check host.activeScreen().get.destination == hsHome
    check not homeRoot.inert()

    host.registerScreen(
      hsDetails,
      detailsRoot,
      focusFallback = some(detailsButton.container)
    )
    check host.sync(interaction)
    check host.pendingDestination().isNone
    check host.activeScreen().get.destination == hsDetails
    check homeRoot.inert()
    check not detailsRoot.inert()

  test "an initially missing destination activates after registration":
    let navigator = initStackNavigator(hsDetails)
    let ui = initUiRoot()
    let detailsRoot = ui.box()
    let host = initNavigationScreenHost(ui, navigator)
    var interaction = initInteractionState()

    check host.pendingDestination() == some(hsDetails)
    check not host.sync(interaction)
    check host.activeScreen().isNone

    host.registerScreen(hsDetails, detailsRoot)
    check detailsRoot.inert()
    check host.sync(interaction)
    check host.pendingDestination().isNone
    check host.activeScreen().get.destination == hsDetails
    check not detailsRoot.inert()

  test "multiple navigation changes coalesce to the latest destination":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let app = ui.box()
    let homeRoot = ui.box(parent = some(app))
    let settingsRoot = ui.box(parent = some(app))
    let detailsRoot = ui.box(parent = some(app))
    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(hsHome, homeRoot)
    host.registerScreen(hsSettings, settingsRoot)
    host.registerScreen(hsDetails, detailsRoot)
    var interaction = initInteractionState()
    check host.sync(interaction)

    navigator.push(hsSettings)
    navigator.push(hsDetails)
    check host.pendingDestination() == some(hsDetails)
    check host.sync(interaction)
    check host.activeScreen().get.destination == hsDetails
    check homeRoot.inert()
    check settingsRoot.inert()
    check not detailsRoot.inert()
    check not host.sync(interaction)

  test "replacing the active destination does not grow retained state":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let homeRoot = ui.box()
    ui.pushParent(homeRoot)
    let homeButton = ui.button("Home")
    ui.popParent()
    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(hsHome, homeRoot, focusFallback = some(homeButton.container))
    var interaction = initInteractionState()
    check host.sync(interaction)
    discard ui.setFocus(
      interaction,
      some(homeButton.container.nodeId),
      focusVisible = true
    )
    let nodesBefore = ui.tree.nodes.len
    let stylesBefore = ui.componentStyles.len

    navigator.replace(hsHome)
    check host.sync(interaction)
    check host.activeScreen().get.destination == hsHome
    check interaction.focusedTarget == some(homeButton.container.nodeId)
    check ui.tree.nodes.len == nodesBefore
    check ui.componentStyles.len == stylesBefore

  test "screen registration rejects ambiguous ownership and overlap":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let foreignUi = initUiRoot()
    let app = ui.box()
    let homeRoot = ui.box(parent = some(app))
    let nested = ui.box(parent = some(homeRoot))
    let outside = ui.button("Outside")
    let foreign = foreignUi.box()
    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(hsHome, homeRoot)

    expect ValueError:
      host.registerScreen(hsHome, app)
    expect ValueError:
      host.registerScreen(hsSettings, nested)
    expect ValueError:
      host.registerScreen(hsSettings, foreign)
    expect ValueError:
      host.registerScreen(
        hsSettings,
        app,
        focusFallback = some(outside.container)
      )

  test "inactive screens block direct events focus and accessibility actions":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let app = ui.box(uiStyle([
      decl("width", px(240)),
      decl("height", px(120))
    ]))
    let homeRoot = ui.box(parent = some(app))
    let settingsRoot = ui.box(parent = some(app))
    ui.pushParent(settingsRoot)
    let settingsButton = ui.button("Settings")
    ui.popParent()
    var clicks = 0
    settingsButton.onClick = proc(event: DispatchResult): EventOutcome =
      inc clicks
      true
    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(hsHome, homeRoot)
    host.registerScreen(hsSettings, settingsRoot)
    var interaction = initInteractionState()
    check host.sync(interaction)

    check not settingsButton.container.emit(InputEvent(kind: iekClick))
    check clicks == 0
    check not ui.setFocus(
      interaction,
      some(settingsButton.container.nodeId),
      focusVisible = true
    )
    check interaction.focusedTarget.isNone

    let styles = ui.resolvedStyles()
    let layout = computeLayout(ui.tree, styles, size(240, 120))
    let snapshot = ui.buildAtspiSnapshot(layout, "Navigation")
    let path = objectPathFor(settingsButton.container.nodeId)
    check not ui.performAtspiAction(snapshot, path)

    navigator.push(hsSettings)
    check host.sync(interaction)
    check settingsButton.container.emit(InputEvent(kind: iekClick))
    check clicks == 1

  test "inert toggling preserves unrelated screen state":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let app = ui.box()
    let homeRoot = ui.box(parent = some(app))
    let settingsRoot = ui.box(parent = some(app))
    homeRoot.setState(esDisabled, true)
    homeRoot.setAccessibleHidden(true)
    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(hsHome, homeRoot)
    host.registerScreen(hsSettings, settingsRoot)
    var interaction = initInteractionState()
    check host.sync(interaction)

    navigator.push(hsSettings)
    check host.sync(interaction)
    navigator.back()
    check host.sync(interaction)

    check esDisabled in ui.tree.nodes[homeRoot.id.nodeIndex].states
    check ui.tree.semanticInfo(homeRoot.id).hidden
    check not homeRoot.inert()

  test "disconnect stops automatic navigation observation":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let app = ui.box()
    let homeRoot = ui.box(parent = some(app))
    let settingsRoot = ui.box(parent = some(app))
    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(hsHome, homeRoot)
    host.registerScreen(hsSettings, settingsRoot)
    var interaction = initInteractionState()
    check host.sync(interaction)
    check host.connected()
    check host.disconnect()
    check not host.connected()
    check not host.disconnect()

    navigator.push(hsSettings)
    check not host.sync(interaction)
    check host.activeScreen().get.destination == hsHome

    host.queueCurrent()
    check host.sync(interaction)
    check host.activeScreen().get.destination == hsSettings

  test "repeated history traversal does not grow retained nodes or styles":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let app = ui.box()
    let homeRoot = ui.box(parent = some(app))
    let settingsRoot = ui.box(parent = some(app))
    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(hsHome, homeRoot)
    host.registerScreen(hsSettings, settingsRoot)
    var interaction = initInteractionState()
    check host.sync(interaction)
    navigator.push(hsSettings)
    check host.sync(interaction)
    let retainedNodeCount = ui.tree.nodes.len
    let retainedStyleCount = ui.componentStyles.len

    for iteration in 0 ..< 100:
      check navigator.back()
      check host.sync(interaction)
      check navigator.forward()
      check host.sync(interaction)

    check ui.tree.nodes.len == retainedNodeCount
    check ui.componentStyles.len == retainedStyleCount

  test "unregistering an inactive screen disposes only that screen":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let app = ui.box()
    let homeRoot = ui.box(parent = some(app))
    let settingsRoot = ui.box(parent = some(app))
    ui.pushParent(settingsRoot)
    let settingsButton = ui.button("Settings")
    ui.popParent()
    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(hsHome, homeRoot)
    host.registerScreen(hsSettings, settingsRoot)
    var interaction = initInteractionState()
    check host.sync(interaction)

    check host.unregisterScreen(hsSettings, interaction)
    check host.screenCount() == 1
    check host.activeScreen().get.destination == hsHome
    check homeRoot.valid()
    check not settingsRoot.valid()
    check not settingsButton.container.valid()
    check not host.unregisterScreen(hsSettings, interaction)

  test "unregistering the active screen waits for a replacement registration":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let oldRoot = ui.box()
    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(hsHome, oldRoot)
    var interaction = initInteractionState()
    check host.sync(interaction)

    check host.unregisterScreen(hsHome, interaction)
    check not oldRoot.valid()
    check host.activeScreen().isNone
    check host.pendingDestination() == some(hsHome)
    check not host.sync(interaction)

    let replacement = ui.box()
    host.registerScreen(hsHome, replacement)
    check host.sync(interaction)
    check host.activeScreen().get.screenRoot.id == replacement.id
    check not replacement.inert()

  test "replacing an active screen disposes old behavior and restores focus":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let app = ui.box()
    let oldRoot = ui.box(parent = some(app))
    ui.pushParent(oldRoot)
    let oldButton = ui.button("Old")
    ui.popParent()
    var oldClicks = 0
    oldButton.onClick = proc(event: DispatchResult): EventOutcome =
      inc oldClicks
      true
    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(hsHome, oldRoot, focusFallback = some(oldButton.container))
    var interaction = initInteractionState()
    check host.sync(interaction)
    discard ui.setFocus(interaction, some(oldButton.container.id), focusVisible = true)

    let replacement = ui.box(parent = some(app))
    ui.pushParent(replacement)
    let replacementButton = ui.button("Replacement")
    ui.popParent()
    check host.replaceScreen(
      hsHome,
      replacement,
      interaction,
      focusFallback = some(replacementButton.container)
    )

    check not oldRoot.valid()
    check not oldButton.container.valid()
    check replacement.valid()
    check not replacement.inert()
    check host.activeScreen().get.screenRoot.id == replacement.id
    check interaction.focusedTarget == some(replacementButton.container.id)
    check not ui.events.emit(ui.tree, oldButton.container.id, iekClick)
    check oldClicks == 0

  test "replacing an inactive screen keeps it hidden and inert":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let app = ui.box()
    let homeRoot = ui.box(parent = some(app))
    let oldSettings = ui.box(parent = some(app))
    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(hsHome, homeRoot)
    host.registerScreen(hsSettings, oldSettings)
    var interaction = initInteractionState()
    check host.sync(interaction)

    let replacement = ui.box(parent = some(app))
    check host.replaceScreen(hsSettings, replacement, interaction)
    check not oldSettings.valid()
    check replacement.inert()
    check host.activeScreen().get.destination == hsHome
    let styles = ui.resolvedStyles()
    check styles.styles[replacement.id.nodeIndex].layout.display == dkNone

  test "screen replacement rejects missing overlapping and foreign roots":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let foreignUi = initUiRoot()
    let app = ui.box()
    let homeRoot = ui.box(parent = some(app))
    let nested = ui.box(parent = some(homeRoot))
    let outside = ui.box(parent = some(app))
    let foreign = foreignUi.box()
    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(hsHome, homeRoot)
    var interaction = initInteractionState()

    expect ValueError:
      discard host.replaceScreen(hsSettings, outside, interaction)
    expect ValueError:
      discard host.replaceScreen(hsHome, nested, interaction)
    expect ValueError:
      discard host.replaceScreen(hsHome, foreign, interaction)
    expect ValueError:
      discard host.replaceScreen(
        hsHome,
        outside,
        interaction,
        focusFallback = some(homeRoot)
      )
    check homeRoot.valid()

  test "repeated screen replacement reuses nodes styles and event slots":
    let navigator = initStackNavigator(hsHome)
    let ui = initUiRoot()
    let app = ui.box()
    var currentRoot = ui.box(parent = some(app))
    ui.pushParent(currentRoot)
    var currentButton = ui.button("Initial")
    ui.popParent()
    let host = initNavigationScreenHost(ui, navigator)
    host.registerScreen(
      hsHome,
      currentRoot,
      focusFallback = some(currentButton.container)
    )
    var interaction = initInteractionState()
    check host.sync(interaction)

    var boundedNodes = 0
    var boundedStyles = 0
    for iteration in 0 ..< 200:
      let previousRoot = currentRoot
      currentRoot = ui.box(
        uiStyle([decl("width", px(float32(100 + iteration mod 7)))]),
        parent = some(app)
      )
      ui.pushParent(currentRoot)
      currentButton = ui.button("Replacement")
      ui.popParent()
      currentButton.onClick = proc(event: DispatchResult): EventOutcome = stoppedEvent()
      check host.replaceScreen(
        hsHome,
        currentRoot,
        interaction,
        focusFallback = some(currentButton.container)
      )
      check not previousRoot.valid()
      check ui.tree.activeNodeCount() == 4
      if iteration == 1:
        boundedNodes = ui.tree.nodes.len
        boundedStyles = ui.componentStyles.len
      elif iteration > 1:
        check ui.tree.nodes.len == boundedNodes
        check ui.componentStyles.len == boundedStyles

    check host.screenCount() == 1
    check currentRoot.valid()
    check ui.events.bindings.len == 3
