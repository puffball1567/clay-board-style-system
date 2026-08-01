import std/[options, unittest]

import clay_board_style_system

type FocusScreen = enum
  fsHome,
  fsSettings,
  fsDetails

suite "navigation focus memory":
  test "empty memory operations are idempotent":
    let memory = initNavigationFocusMemory()
    let ui = initUiRoot()
    let screenRoot = ui.box()
    var interaction = initInteractionState()

    check memory.pendingEntry().isNone
    check memory.rememberedEntryCount() == 0
    memory.forgetFocus(NavigationEntryId(99))
    memory.clear()
    check not memory.restoreFocus(ui, interaction, screenRoot)
    check interaction.focusedTarget.isNone

  test "a later restore request replaces an earlier pending entry":
    let memory = initNavigationFocusMemory()
    memory.requestRestore(NavigationEntryId(1))
    memory.requestRestore(NavigationEntryId(2))
    check memory.pendingEntry() == some(NavigationEntryId(2))

  test "back and forward restore focus for each history entry":
    let memory = initNavigationFocusMemory()
    let navigator = initStackNavigator(fsHome)
    let ui = initUiRoot()
    let appRoot = ui.box()
    let homeRoot = ui.box(parent = some(appRoot))
    ui.pushParent(homeRoot)
    let homeFirst = ui.button("Home first")
    let homeLast = ui.button("Home last")
    ui.popParent()
    let settingsRoot = ui.box(parent = some(appRoot))
    ui.pushParent(settingsRoot)
    let settingsFirst = ui.button("Settings first")
    let settingsLast = ui.button("Settings last")
    ui.popParent()
    settingsRoot.setState(esDisabled, true)
    var interaction = initInteractionState()
    navigator.addListener(proc(change: NavigationChange[FocusScreen]) =
      memory.captureFocus(change, interaction)
    )

    discard ui.setFocus(
      interaction,
      some(homeLast.container.nodeId),
      focusVisible = true
    )
    navigator.push(fsSettings)
    homeRoot.setState(esDisabled, true)
    settingsRoot.setState(esDisabled, false)
    check memory.restoreFocus(
      ui,
      interaction,
      settingsRoot,
      fallback = some(settingsFirst.container)
    )
    check interaction.focusedTarget == some(settingsFirst.container.nodeId)

    discard ui.setFocus(
      interaction,
      some(settingsLast.container.nodeId),
      focusVisible = true
    )
    navigator.back()
    settingsRoot.setState(esDisabled, true)
    homeRoot.setState(esDisabled, false)
    check memory.restoreFocus(ui, interaction, homeRoot)
    check interaction.focusedTarget == some(homeLast.container.nodeId)

    navigator.forward()
    homeRoot.setState(esDisabled, true)
    settingsRoot.setState(esDisabled, false)
    check memory.restoreFocus(ui, interaction, settingsRoot)
    check interaction.focusedTarget == some(settingsLast.container.nodeId)

    check homeFirst.container.nodeId != homeLast.container.nodeId

  test "a new destination uses fallback then the first screen target":
    let memory = initNavigationFocusMemory()
    let navigator = initStackNavigator(fsHome)
    let ui = initUiRoot()
    let appRoot = ui.box()
    let detailsRoot = ui.box(parent = some(appRoot))
    ui.pushParent(detailsRoot)
    let first = ui.button("First")
    let preferred = ui.button("Preferred")
    ui.popParent()
    var interaction = initInteractionState()
    navigator.addListener(proc(change: NavigationChange[FocusScreen]) =
      memory.captureFocus(change, interaction)
    )

    navigator.push(fsDetails)
    check memory.restoreFocus(
      ui,
      interaction,
      detailsRoot,
      fallback = some(preferred.container)
    )
    check interaction.focusedTarget == some(preferred.container.nodeId)

    navigator.push(fsDetails)
    check memory.restoreFocus(ui, interaction, detailsRoot)
    check interaction.focusedTarget == some(first.container.nodeId)

  test "automatic fallback follows positive tab order before tree order":
    let memory = initNavigationFocusMemory()
    let ui = initUiRoot()
    let screenRoot = ui.box()
    ui.pushParent(screenRoot)
    let zero = ui.button("Zero")
    let later = ui.button("Later")
    let first = ui.button("First")
    ui.popParent()
    zero.container.setFocusable(tabIndex = 0)
    later.container.setFocusable(tabIndex = 8)
    first.container.setFocusable(tabIndex = 2)
    var interaction = initInteractionState()

    memory.requestRestore(NavigationEntryId(1))
    check memory.restoreFocus(ui, interaction, screenRoot)
    check interaction.focusedTarget == some(first.container.nodeId)

  test "disabled inert and out-of-screen fallbacks are skipped":
    let memory = initNavigationFocusMemory()
    let ui = initUiRoot()
    let screenRoot = ui.box()
    ui.pushParent(screenRoot)
    let disabled = ui.button("Disabled")
    let inertParent = ui.box()
    ui.pushParent(inertParent)
    let inertChild = ui.button("Inert")
    ui.popParent()
    let valid = ui.button("Valid")
    ui.popParent()
    let outside = ui.button("Outside")
    disabled.container.setState(esDisabled, true)
    inertParent.setInert()
    var interaction = initInteractionState()

    memory.requestRestore(NavigationEntryId(1))
    check memory.restoreFocus(
      ui,
      interaction,
      screenRoot,
      fallback = some(disabled.container)
    )
    check interaction.focusedTarget == some(valid.container.nodeId)

    memory.requestRestore(NavigationEntryId(2))
    discard memory.restoreFocus(
      ui,
      interaction,
      screenRoot,
      fallback = some(outside.container)
    )
    check interaction.focusedTarget == some(valid.container.nodeId)
    check inertChild.container.nodeId != valid.container.nodeId

  test "invalid saved targets fall back within the active screen":
    let memory = initNavigationFocusMemory()
    let navigator = initStackNavigator(fsHome)
    let ui = initUiRoot()
    let appRoot = ui.box()
    let outside = ui.button("Outside")
    let screenRoot = ui.box(parent = some(appRoot))
    ui.pushParent(screenRoot)
    let fallback = ui.button("Fallback")
    ui.popParent()
    var interaction = initInteractionState()
    navigator.addListener(proc(change: NavigationChange[FocusScreen]) =
      memory.captureFocus(change, interaction)
    )

    navigator.push(fsSettings)
    let entry = navigator.currentEntry().get.id
    memory.rememberFocus(entry, outside.container.nodeId)

    check memory.restoreFocus(
      ui,
      interaction,
      screenRoot,
      fallback = some(fallback.container)
    )
    check interaction.focusedTarget == some(fallback.container.nodeId)
    check memory.pendingEntry().isNone
    check not memory.restoreFocus(ui, interaction, screenRoot)

  test "a stale saved target is forgotten after one restore attempt":
    let memory = initNavigationFocusMemory()
    let ui = initUiRoot()
    let screenRoot = ui.box()
    ui.pushParent(screenRoot)
    let fallback = ui.button("Fallback")
    ui.popParent()
    let entryId = NavigationEntryId(7)
    memory.rememberFocus(entryId, NodeId(99_999))
    memory.requestRestore(entryId)
    var interaction = initInteractionState()

    check memory.rememberedEntryCount() == 1
    check memory.restoreFocus(ui, interaction, screenRoot)
    check interaction.focusedTarget == some(fallback.container.nodeId)
    check memory.rememberedEntryCount() == 0

  test "a screen without focus targets clears the previous focus":
    let memory = initNavigationFocusMemory()
    let navigator = initStackNavigator(fsHome)
    let ui = initUiRoot()
    let appRoot = ui.box()
    let previous = ui.button("Previous")
    let emptyRoot = ui.box(parent = some(appRoot))
    var interaction = initInteractionState()
    discard ui.setFocus(
      interaction,
      some(previous.container.nodeId),
      focusVisible = true
    )
    navigator.addListener(proc(change: NavigationChange[FocusScreen]) =
      memory.captureFocus(change, interaction)
    )

    navigator.push(fsSettings)

    check memory.restoreFocus(ui, interaction, emptyRoot)
    check interaction.focusedTarget.isNone

  test "screen roots and fallbacks must belong to the supplied root":
    let memory = initNavigationFocusMemory()
    let navigator = initStackNavigator(fsHome)
    let firstUi = initUiRoot()
    let secondUi = initUiRoot()
    let foreignRoot = secondUi.box()
    var interaction = initInteractionState()
    navigator.addListener(proc(change: NavigationChange[FocusScreen]) =
      memory.captureFocus(change, interaction)
    )
    navigator.push(fsSettings)

    expect ValueError:
      discard memory.restoreFocus(firstUi, interaction, foreignRoot)

  test "focus records are pruned when replace removes a history entry":
    let memory = initNavigationFocusMemory()
    let navigator = initStackNavigator(fsHome)
    let ui = initUiRoot()
    let focusTarget = ui.button("Target")
    var interaction = initInteractionState()
    discard ui.setFocus(
      interaction,
      some(focusTarget.container.nodeId),
      focusVisible = true
    )
    navigator.addListener(proc(change: NavigationChange[FocusScreen]) =
      memory.captureFocus(change, interaction)
    )

    navigator.push(fsSettings)
    check memory.rememberedEntryCount() == 1
    navigator.replace(fsDetails)

    check memory.rememberedEntryCount() == 1

  test "pushing after back prunes focus from the discarded forward branch":
    let memory = initNavigationFocusMemory()
    let navigator = initStackNavigator(fsHome)
    var interaction = initInteractionState()
    navigator.addListener(proc(change: NavigationChange[FocusScreen]) =
      memory.captureFocus(change, interaction)
    )

    let home = navigator.currentEntry().get.id
    navigator.push(fsSettings)
    let settings = navigator.currentEntry().get.id
    navigator.push(fsDetails)
    let details = navigator.currentEntry().get.id
    memory.rememberFocus(home, NodeId(10))
    memory.rememberFocus(settings, NodeId(11))
    memory.rememberFocus(details, NodeId(12))
    check memory.rememberedEntryCount() == 3

    navigator.back()
    navigator.push(fsHome)
    check memory.rememberedEntryCount() == 2

  test "capture without focused nodes still schedules the current entry":
    let memory = initNavigationFocusMemory()
    let navigator = initStackNavigator(fsHome)
    var interaction = initInteractionState()
    navigator.addListener(proc(change: NavigationChange[FocusScreen]) =
      memory.captureFocus(change, interaction)
    )

    navigator.push(fsSettings)
    check memory.rememberedEntryCount() == 0
    check memory.pendingEntry() == some(navigator.currentEntry().get.id)

    memory.clear()
    check memory.rememberedEntryCount() == 0
    check memory.pendingEntry().isNone
