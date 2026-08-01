import std/[hashes, options]

import ./invalidation

type
  NavigationEntryId* = distinct uint64
  NavigationListenerId* = distinct uint64

  NavigationEntry*[Destination] = object
    id*: NavigationEntryId
    destination*: Destination

  NavigationSnapshot*[Destination] = object
    entries*: seq[NavigationEntry[Destination]]
    currentIndex*: int
    revision*: uint64

  NavigationChangeKind* = enum
    nckPush,
    nckReplace,
    nckBack,
    nckForward

  NavigationChange*[Destination] = object
    kind*: NavigationChangeKind
    previous*: Option[NavigationEntry[Destination]]
    current*: Option[NavigationEntry[Destination]]
    snapshot*: NavigationSnapshot[Destination]
    dirtyDomains*: set[DirtyDomain]

  NavigationSnapshotProc*[Destination] =
    proc(): NavigationSnapshot[Destination] {.closure.}
  NavigationDestinationProc*[Destination] =
    proc(destination: Destination): Option[NavigationChange[Destination]] {.closure.}
  NavigationStepProc*[Destination] =
    proc(): Option[NavigationChange[Destination]] {.closure.}
  NavigationChangedProc*[Destination] =
    proc(change: NavigationChange[Destination]) {.closure.}

  NavigationListenerBinding[Destination] = object
    id: NavigationListenerId
    callback: NavigationChangedProc[Destination]

  NavigationDriver*[Destination] = object
    snapshot*: NavigationSnapshotProc[Destination]
    push*: NavigationDestinationProc[Destination]
    replace*: NavigationDestinationProc[Destination]
    back*: NavigationStepProc[Destination]
    forward*: NavigationStepProc[Destination]

  Navigator*[Destination] = ref object
    driver: NavigationDriver[Destination]
    listeners: seq[NavigationListenerBinding[Destination]]
    nextListenerId: uint64

  StackNavigationState[Destination] = ref object
    entries: seq[NavigationEntry[Destination]]
    currentIndex: int
    revision: uint64
    nextEntryId: uint64

const navigationScreenDirtyDomains* = {ddStyle, ddLayout, ddPaint, ddHit}

proc `==`*(left, right: NavigationEntryId): bool =
  uint64(left) == uint64(right)

proc entryIdValue*(id: NavigationEntryId): uint64 =
  uint64(id)

proc hash*(id: NavigationEntryId): Hash =
  hash(id.entryIdValue())

proc `==`*(left, right: NavigationListenerId): bool =
  uint64(left) == uint64(right)

proc listenerIdValue*(id: NavigationListenerId): uint64 =
  uint64(id)

proc currentEntry*[Destination](
    snapshot: NavigationSnapshot[Destination]
): Option[NavigationEntry[Destination]] =
  if snapshot.currentIndex < 0 or snapshot.currentIndex >= snapshot.entries.len:
    return none(NavigationEntry[Destination])
  some(snapshot.entries[snapshot.currentIndex])

proc currentDestination*[Destination](
    snapshot: NavigationSnapshot[Destination]
): Option[Destination] =
  let entry = snapshot.currentEntry()
  if entry.isNone:
    return none(Destination)
  some(entry.get.destination)

proc canGoBack*[Destination](snapshot: NavigationSnapshot[Destination]): bool =
  snapshot.currentIndex > 0 and snapshot.currentIndex < snapshot.entries.len

proc canGoForward*[Destination](snapshot: NavigationSnapshot[Destination]): bool =
  snapshot.currentIndex >= 0 and snapshot.currentIndex < snapshot.entries.high

proc validateDriver[Destination](driver: NavigationDriver[Destination]) =
  if driver.snapshot.isNil or driver.push.isNil or driver.replace.isNil or
      driver.back.isNil or driver.forward.isNil:
    raise newException(ValueError, "navigation driver requires snapshot, push, replace, back, and forward operations")

proc initNavigator*[Destination](
    driver: NavigationDriver[Destination];
    onChanged: NavigationChangedProc[Destination] = nil
): Navigator[Destination] =
  driver.validateDriver()
  result = Navigator[Destination](
    driver: driver,
    listeners: @[],
    nextListenerId: 1
  )
  if not onChanged.isNil:
    discard result.addListener(onChanged)

proc addListener*[Destination](
    navigator: Navigator[Destination];
    listener: NavigationChangedProc[Destination]
): NavigationListenerId {.discardable.} =
  if listener.isNil:
    raise newException(ValueError, "navigation listener must not be nil")
  result = NavigationListenerId(navigator.nextListenerId)
  inc navigator.nextListenerId
  navigator.listeners.add NavigationListenerBinding[Destination](
    id: result,
    callback: listener
  )

proc removeListener*[Destination](
    navigator: Navigator[Destination];
    listenerId: NavigationListenerId
): bool {.discardable.} =
  for index, binding in navigator.listeners:
    if binding.id == listenerId:
      navigator.listeners.delete(index)
      return true
  false

proc clearListeners*[Destination](navigator: Navigator[Destination]) =
  navigator.listeners.setLen(0)

proc notify[Destination](
    navigator: Navigator[Destination];
    change: NavigationChange[Destination]
) =
  var callbacks = newSeqOfCap[NavigationChangedProc[Destination]](
    navigator.listeners.len
  )
  for binding in navigator.listeners:
    callbacks.add binding.callback
  for callback in callbacks:
    callback(change)

proc snapshot*[Destination](navigator: Navigator[Destination]): NavigationSnapshot[Destination] =
  navigator.driver.snapshot()

proc currentEntry*[Destination](
    navigator: Navigator[Destination]
): Option[NavigationEntry[Destination]] =
  navigator.snapshot().currentEntry()

proc currentDestination*[Destination](navigator: Navigator[Destination]): Option[Destination] =
  navigator.snapshot().currentDestination()

proc canGoBack*[Destination](navigator: Navigator[Destination]): bool =
  navigator.snapshot().canGoBack()

proc canGoForward*[Destination](navigator: Navigator[Destination]): bool =
  navigator.snapshot().canGoForward()

proc applyChange[Destination](
    navigator: Navigator[Destination];
    change: Option[NavigationChange[Destination]]
): bool =
  if change.isNone:
    return false
  navigator.notify(change.get)
  true

proc push*[Destination](navigator: Navigator[Destination]; destination: Destination): bool {.discardable.} =
  navigator.applyChange(navigator.driver.push(destination))

proc replace*[Destination](navigator: Navigator[Destination]; destination: Destination): bool {.discardable.} =
  navigator.applyChange(navigator.driver.replace(destination))

proc back*[Destination](navigator: Navigator[Destination]): bool {.discardable.} =
  navigator.applyChange(navigator.driver.back())

proc forward*[Destination](navigator: Navigator[Destination]): bool {.discardable.} =
  navigator.applyChange(navigator.driver.forward())

proc nextEntry[Destination](
    state: StackNavigationState[Destination];
    destination: Destination
): NavigationEntry[Destination] =
  result = NavigationEntry[Destination](
    id: NavigationEntryId(state.nextEntryId),
    destination: destination
  )
  inc state.nextEntryId

proc snapshot[Destination](
    state: StackNavigationState[Destination]
): NavigationSnapshot[Destination] =
  var entries = newSeqOfCap[NavigationEntry[Destination]](state.entries.len)
  for entry in state.entries:
    entries.add entry
  NavigationSnapshot[Destination](
    entries: entries,
    currentIndex: state.currentIndex,
    revision: state.revision
  )

proc change[Destination](
    state: StackNavigationState[Destination];
    kind: NavigationChangeKind;
    previous: Option[NavigationEntry[Destination]]
): NavigationChange[Destination] =
  let currentSnapshot = state.snapshot()
  NavigationChange[Destination](
    kind: kind,
    previous: previous,
    current: currentSnapshot.currentEntry(),
    snapshot: currentSnapshot,
    dirtyDomains: navigationScreenDirtyDomains
  )

proc stackNavigationDriver*[Destination](
    initialDestination: Destination
): NavigationDriver[Destination] =
  let state = StackNavigationState[Destination](
    entries: @[],
    currentIndex: -1,
    revision: 0,
    nextEntryId: 1
  )
  state.entries.add state.nextEntry(initialDestination)
  state.currentIndex = 0

  result.snapshot = proc(): NavigationSnapshot[Destination] =
    state.snapshot()

  result.push = proc(destination: Destination): Option[NavigationChange[Destination]] =
    let previous = state.snapshot().currentEntry()
    if state.currentIndex < state.entries.high:
      state.entries.setLen(state.currentIndex + 1)
    state.entries.add state.nextEntry(destination)
    state.currentIndex = state.entries.high
    inc state.revision
    some(state.change(nckPush, previous))

  result.replace = proc(destination: Destination): Option[NavigationChange[Destination]] =
    let previous = state.snapshot().currentEntry()
    if state.currentIndex < 0 or state.currentIndex >= state.entries.len:
      state.entries.add state.nextEntry(destination)
      state.currentIndex = state.entries.high
    else:
      state.entries[state.currentIndex] = state.nextEntry(destination)
    inc state.revision
    some(state.change(nckReplace, previous))

  result.back = proc(): Option[NavigationChange[Destination]] =
    if state.currentIndex <= 0 or state.currentIndex >= state.entries.len:
      return none(NavigationChange[Destination])
    let previous = state.snapshot().currentEntry()
    dec state.currentIndex
    inc state.revision
    some(state.change(nckBack, previous))

  result.forward = proc(): Option[NavigationChange[Destination]] =
    if state.currentIndex < 0 or state.currentIndex >= state.entries.high:
      return none(NavigationChange[Destination])
    let previous = state.snapshot().currentEntry()
    inc state.currentIndex
    inc state.revision
    some(state.change(nckForward, previous))

proc initStackNavigator*[Destination](
    initialDestination: Destination;
    onChanged: NavigationChangedProc[Destination] = nil
): Navigator[Destination] =
  initNavigator(stackNavigationDriver(initialDestination), onChanged)
