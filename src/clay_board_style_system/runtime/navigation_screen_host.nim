import std/options

import ../core/[declaration, node, style_value]
import ../input/events
import ./[focus, frame_scheduler, navigation, navigation_focus, navigation_transition, ui_root]

const navigationScreenHostStylePriority* = 1_000_000

type
  NavigationScreenBinding*[Destination] = object
    destination*: Destination
    screenRoot*: NodeHandle
    focusFallback*: Option[NodeHandle]
    active*: bool

  ActiveNavigationTransition[Destination] = object
    startedAt: float64
    lastProgress: float32
    outgoingIndex: int
    incomingIndex: int
    previous: NavigationEntry[Destination]
    current: NavigationEntry[Destination]
    kind: NavigationChangeKind

  NavigationScreenHost*[Destination] = ref object
    root* {.cursor.}: UiRoot
    navigator* {.cursor.}: Navigator[Destination]
    screens: seq[NavigationScreenBinding[Destination]]
    activeIndex: int
    activeEntryId: Option[NavigationEntryId]
    pendingEntry: Option[NavigationEntry[Destination]]
    pendingSnapshot: Option[NavigationSnapshot[Destination]]
    pendingKind: Option[NavigationChangeKind]
    pendingChange: bool
    focusMemory: NavigationFocusMemory
    listenerId: Option[NavigationListenerId]
    transitionSpec: Option[NavigationTransitionSpec[Destination]]
    activeTransition: Option[ActiveNavigationTransition[Destination]]

proc setScreenActive[Destination](
    host: NavigationScreenHost[Destination];
    index: int;
    active: bool
) =
  if index < 0 or index >= host.screens.len or
      host.screens[index].active == active:
    return
  let screenRoot = host.screens[index].screenRoot
  screenRoot.setInert(not active)
  host.root.setNodeStyle(
    screenRoot.id,
    uiStyle([decl("display", keyword(if active: "flex" else: "none"))]),
    priority = navigationScreenHostStylePriority
  )
  host.screens[index].active = active

proc findScreenIndex[Destination](
    host: NavigationScreenHost[Destination];
    destination: Destination
): int =
  for index, screen in host.screens:
    if screen.destination == destination:
      return index
  -1

proc initNavigationScreenHost*[Destination](
    root: UiRoot;
    navigator: Navigator[Destination];
    transition = none(NavigationTransitionSpec[Destination])
): NavigationScreenHost[Destination] =
  if root.isNil:
    raise newException(ValueError, "navigation screen host requires a UiRoot")
  if navigator.isNil:
    raise newException(ValueError, "navigation screen host requires a navigator")

  result = NavigationScreenHost[Destination](
    root: root,
    navigator: navigator,
    screens: @[],
    activeIndex: -1,
    activeEntryId: none(NavigationEntryId),
    pendingEntry: navigator.currentEntry(),
    pendingSnapshot: some(navigator.snapshot()),
    pendingKind: none(NavigationChangeKind),
    pendingChange: true,
    focusMemory: initNavigationFocusMemory(),
    listenerId: none(NavigationListenerId),
    transitionSpec: transition,
    activeTransition: none(ActiveNavigationTransition[Destination])
  )
  let host = result
  result.listenerId = some(navigator.addListener(
    proc(change: NavigationChange[Destination]) =
      host.pendingEntry = change.current
      host.pendingSnapshot = some(change.snapshot)
      host.pendingKind = some(change.kind)
      host.pendingChange = true
  ))

proc disconnect*[Destination](host: NavigationScreenHost[Destination]): bool {.discardable.} =
  if host.listenerId.isNone:
    return false
  let listenerId = host.listenerId.get
  host.listenerId = none(NavigationListenerId)
  host.navigator.removeListener(listenerId)

proc connected*[Destination](host: NavigationScreenHost[Destination]): bool =
  host.listenerId.isSome

proc screenCount*[Destination](host: NavigationScreenHost[Destination]): int =
  host.screens.len

proc transitionActive*[Destination](host: NavigationScreenHost[Destination]): bool =
  host.activeTransition.isSome

proc setTransition*[Destination](
    host: NavigationScreenHost[Destination];
    transition: Option[NavigationTransitionSpec[Destination]]
) =
  if host.activeTransition.isSome:
    raise newException(ValueError, "cannot replace an active navigation transition")
  host.transitionSpec = transition

proc emitTransition[Destination](
    host: NavigationScreenHost[Destination];
    transition: ActiveNavigationTransition[Destination];
    phase: NavigationTransitionPhase;
    progress: float32
) =
  if host.transitionSpec.isNone:
    return
  host.transitionSpec.get.onTransition(NavigationTransitionContext[Destination](
    phase: phase,
    kind: transition.kind,
    previous: transition.previous,
    current: transition.current,
    outgoingRoot: host.screens[transition.outgoingIndex].screenRoot,
    incomingRoot: host.screens[transition.incomingIndex].screenRoot,
    progress: progress
  ))

proc settleTransition[Destination](
    host: NavigationScreenHost[Destination];
    phase: NavigationTransitionPhase
): bool =
  if host.activeTransition.isNone:
    return false
  let transition = host.activeTransition.get
  host.activeTransition = none(ActiveNavigationTransition[Destination])
  if transition.outgoingIndex >= 0 and
      transition.outgoingIndex < host.screens.len and
      transition.outgoingIndex != transition.incomingIndex:
    host.setScreenActive(transition.outgoingIndex, false)
  host.emitTransition(transition, phase, transition.lastProgress)
  true

proc cancelTransition*[Destination](
    host: NavigationScreenHost[Destination]
): bool {.discardable.} =
  host.settleTransition(ntpCancelled)

proc cancelTransition*[Destination](
    host: NavigationScreenHost[Destination];
    scheduler: var FrameScheduler
): bool {.discardable.} =
  result = host.settleTransition(ntpCancelled)
  if result and host.transitionSpec.isSome:
    scheduler.markDirty(host.transitionSpec.get.dirtyDomains)

proc activeScreen*[Destination](
    host: NavigationScreenHost[Destination]
): Option[NavigationScreenBinding[Destination]] =
  if host.activeIndex < 0 or host.activeIndex >= host.screens.len:
    return none(NavigationScreenBinding[Destination])
  some(host.screens[host.activeIndex])

proc pendingDestination*[Destination](
    host: NavigationScreenHost[Destination]
): Option[Destination] =
  if not host.pendingChange or host.pendingEntry.isNone:
    return none(Destination)
  some(host.pendingEntry.get.destination)

proc registerScreen*[Destination](
    host: NavigationScreenHost[Destination];
    destination: Destination;
    screenRoot: NodeHandle;
    focusFallback = none(NodeHandle)
) =
  if screenRoot.root != host.root or not host.root.tree.isValid(screenRoot.id):
    raise newException(ValueError, "navigation screen root belongs to another UiRoot")
  if focusFallback.isSome:
    if focusFallback.get.root != host.root or
        not host.root.tree.isValid(focusFallback.get.id) or
        not host.root.tree.isDescendantOrSelf(
          focusFallback.get.id,
          screenRoot.id
        ):
      raise newException(
        ValueError,
        "navigation focus fallback must belong to the registered screen"
      )
  if host.findScreenIndex(destination) >= 0:
    raise newException(ValueError, "navigation destination is already registered")
  for screen in host.screens:
    if host.root.tree.isDescendantOrSelf(screenRoot.id, screen.screenRoot.id) or
        host.root.tree.isDescendantOrSelf(screen.screenRoot.id, screenRoot.id):
      raise newException(ValueError, "navigation screen roots must not overlap")

  host.screens.add NavigationScreenBinding[Destination](
    destination: destination,
    screenRoot: screenRoot,
    focusFallback: focusFallback,
    active: true
  )
  host.setScreenActive(host.screens.high, false)

proc unregisterScreen*[Destination](
    host: NavigationScreenHost[Destination];
    destination: Destination;
    interaction: var InteractionState
): bool {.discardable.} =
  let index = host.findScreenIndex(destination)
  if index < 0:
    return false

  discard host.cancelTransition()

  let screenRoot = host.screens[index].screenRoot
  let wasActive = index == host.activeIndex
  if wasActive:
    host.activeIndex = -1
    host.activeEntryId = none(NavigationEntryId)
  elif index < host.activeIndex:
    dec host.activeIndex
  host.screens.delete(index)

  discard host.root.disposeSubtree(screenRoot, interaction)
  if wasActive:
    host.queueCurrent()
  true

proc replaceScreen*[Destination](
    host: NavigationScreenHost[Destination];
    destination: Destination;
    screenRoot: NodeHandle;
    interaction: var InteractionState;
    focusFallback = none(NodeHandle)
): bool {.discardable.} =
  let index = host.findScreenIndex(destination)
  if index < 0:
    raise newException(ValueError, "navigation destination is not registered")
  if screenRoot.root != host.root or not host.root.tree.isValid(screenRoot.id):
    raise newException(ValueError, "navigation screen root belongs to another UiRoot")
  if focusFallback.isSome and
      (focusFallback.get.root != host.root or
        not host.root.tree.isValid(focusFallback.get.id) or
        not host.root.tree.isDescendantOrSelf(
          focusFallback.get.id,
          screenRoot.id
        )):
    raise newException(
      ValueError,
      "navigation focus fallback must belong to the replacement screen"
    )

  let previous = host.screens[index]
  if previous.screenRoot.id == screenRoot.id:
    host.screens[index].focusFallback = focusFallback
    return false
  if host.root.tree.isDescendantOrSelf(screenRoot.id, previous.screenRoot.id) or
      host.root.tree.isDescendantOrSelf(previous.screenRoot.id, screenRoot.id):
    raise newException(ValueError, "replacement screen must be disjoint from the previous screen")
  for otherIndex, other in host.screens:
    if otherIndex == index:
      continue
    if host.root.tree.isDescendantOrSelf(screenRoot.id, other.screenRoot.id) or
        host.root.tree.isDescendantOrSelf(other.screenRoot.id, screenRoot.id):
      raise newException(ValueError, "navigation screen roots must not overlap")

  discard host.cancelTransition()

  let wasActive = index == host.activeIndex
  host.screens[index] = NavigationScreenBinding[Destination](
    destination: destination,
    screenRoot: screenRoot,
    focusFallback: focusFallback,
    active: not wasActive
  )
  host.setScreenActive(index, wasActive)
  discard host.root.disposeSubtree(previous.screenRoot, interaction)

  if wasActive and host.activeEntryId.isSome:
    host.focusMemory.requestRestore(host.activeEntryId.get)
    discard host.focusMemory.restoreFocus(
      host.root,
      interaction,
      screenRoot,
      fallback = focusFallback
    )
  true

proc queueCurrent*[Destination](host: NavigationScreenHost[Destination]) =
  host.pendingEntry = host.navigator.currentEntry()
  host.pendingSnapshot = some(host.navigator.snapshot())
  host.pendingKind = none(NavigationChangeKind)
  host.pendingChange = true

proc finishPending[Destination](host: NavigationScreenHost[Destination]) =
  host.pendingChange = false
  host.pendingSnapshot = none(NavigationSnapshot[Destination])
  host.pendingKind = none(NavigationChangeKind)

proc startTransition[Destination](
    host: NavigationScreenHost[Destination];
    scheduler: var FrameScheduler;
    now: float64;
    outgoingIndex: int;
    incomingIndex: int;
    previous: NavigationEntry[Destination];
    current: NavigationEntry[Destination];
    kind: NavigationChangeKind
) =
  let spec = host.transitionSpec.get
  let transition = ActiveNavigationTransition[Destination](
    startedAt: now,
    lastProgress: 0.0,
    outgoingIndex: outgoingIndex,
    incomingIndex: incomingIndex,
    previous: previous,
    current: current,
    kind: kind
  )
  host.screens[outgoingIndex].screenRoot.setInert(true)
  host.activeTransition = some(transition)
  host.emitTransition(transition, ntpStarted, 0.0)
  scheduler.markDirty(spec.dirtyDomains)
  scheduler.requestDeadline(min(
    now + spec.frameIntervalSeconds,
    now + spec.durationSeconds
  ))

proc advanceTransition*[Destination](
    host: NavigationScreenHost[Destination];
    scheduler: var FrameScheduler;
    now: float64
): bool {.discardable.} =
  if host.activeTransition.isNone or host.transitionSpec.isNone:
    return false

  let spec = host.transitionSpec.get
  var transition = host.activeTransition.get
  let elapsed = max(0.0, now - transition.startedAt)
  let progress = float32(min(1.0, elapsed / spec.durationSeconds))
  transition.lastProgress = progress
  host.activeTransition = some(transition)
  scheduler.markDirty(spec.dirtyDomains)

  if progress >= 1.0:
    host.activeTransition = none(ActiveNavigationTransition[Destination])
    if transition.outgoingIndex != transition.incomingIndex:
      host.setScreenActive(transition.outgoingIndex, false)
    host.emitTransition(transition, ntpCompleted, 1.0)
    return true

  host.emitTransition(transition, ntpAdvanced, progress)
  scheduler.requestDeadline(min(
    now + spec.frameIntervalSeconds,
    transition.startedAt + spec.durationSeconds
  ))
  true

proc syncImpl[Destination](
    host: NavigationScreenHost[Destination];
    interaction: var InteractionState;
    scheduler: ptr FrameScheduler;
    now: float64
): bool

proc sync*[Destination](
    host: NavigationScreenHost[Destination];
    interaction: var InteractionState
): bool {.discardable.} =
  host.syncImpl(interaction, nil, 0.0)

proc sync*[Destination](
    host: NavigationScreenHost[Destination];
    interaction: var InteractionState;
    scheduler: var FrameScheduler;
    now: float64
): bool {.discardable.} =
  host.syncImpl(interaction, addr scheduler, now)

proc syncImpl[Destination](
    host: NavigationScreenHost[Destination];
    interaction: var InteractionState;
    scheduler: ptr FrameScheduler;
    now: float64
): bool =
  if not host.pendingChange:
    return false

  if host.activeTransition.isSome:
    if scheduler.isNil:
      discard host.cancelTransition()
    else:
      discard host.cancelTransition(scheduler[])

  if host.pendingEntry.isNone:
    if host.activeIndex >= 0:
      let previousIndex = host.activeIndex
      discard host.root.setFocus(interaction, none(NodeId))
      host.setScreenActive(previousIndex, false)
      host.activeIndex = -1
      host.activeEntryId = none(NavigationEntryId)
      host.finishPending()
      return true
    host.finishPending()
    return false

  let targetEntry = host.pendingEntry.get
  let changeKind = host.pendingKind
  let targetIndex = host.findScreenIndex(targetEntry.destination)
  if targetIndex < 0:
    return false
  if host.activeEntryId == some(targetEntry.id):
    host.finishPending()
    return false

  let previousIndex = host.activeIndex
  let previousEntryId = host.activeEntryId
  if previousIndex >= 0 and previousEntryId.isSome and
      interaction.focusedTarget.isSome and
      host.root.tree.isDescendantOrSelf(
        interaction.focusedTarget.get,
        host.screens[previousIndex].screenRoot.id
      ):
    host.focusMemory.rememberFocus(
      previousEntryId.get,
      interaction.focusedTarget.get
    )
  if host.pendingKind == some(nckReplace) and previousEntryId.isSome:
    host.focusMemory.forgetFocus(previousEntryId.get)
  elif host.pendingKind == some(nckPush) and host.pendingSnapshot.isSome:
    host.focusMemory.retainEntries(host.pendingSnapshot.get)
  elif host.pendingKind.isNone and host.pendingSnapshot.isSome:
    host.focusMemory.retainEntries(host.pendingSnapshot.get)

  if targetIndex != previousIndex:
    host.setScreenActive(targetIndex, true)

  host.activeIndex = targetIndex
  host.activeEntryId = some(targetEntry.id)
  host.finishPending()

  if previousEntryId.isSome:
    host.focusMemory.requestRestore(targetEntry.id)
    host.focusMemory.restoreFocus(
      host.root,
      interaction,
      host.screens[targetIndex].screenRoot,
      fallback = host.screens[targetIndex].focusFallback
    )

  if previousIndex >= 0 and previousIndex != targetIndex:
    if not scheduler.isNil and host.transitionSpec.isSome and
        changeKind.isSome and previousEntryId.isSome:
      host.startTransition(
        scheduler[],
        now,
        previousIndex,
        targetIndex,
        NavigationEntry[Destination](
          id: previousEntryId.get,
          destination: host.screens[previousIndex].destination
        ),
        targetEntry,
        changeKind.get
      )
    else:
      host.setScreenActive(previousIndex, false)
  true
