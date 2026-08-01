import std/[options, random, unittest]

import clay_board_style_system

type
  TestScreen = enum
    tsHome,
    tsSettings,
    tsDetails,
    tsLogin

suite "native navigation":
  test "snapshot helpers reject empty and out-of-range positions":
    let empty = NavigationSnapshot[TestScreen](
      entries: @[],
      currentIndex: -1,
      revision: 7
    )
    check empty.currentEntry().isNone
    check empty.currentDestination().isNone
    check not empty.canGoBack()
    check not empty.canGoForward()

    let invalid = NavigationSnapshot[TestScreen](
      entries: @[
        NavigationEntry[TestScreen](
          id: NavigationEntryId(1),
          destination: tsHome
        )
      ],
      currentIndex: 9,
      revision: 8
    )
    check invalid.currentEntry().isNone
    check invalid.currentDestination().isNone
    check not invalid.canGoBack()
    check not invalid.canGoForward()

  test "stack navigator exposes a typed initial destination":
    let navigator = initStackNavigator(tsHome)

    let snapshot = navigator.snapshot()
    check snapshot.entries.len == 1
    check snapshot.currentIndex == 0
    check snapshot.revision == 0
    check snapshot.currentDestination() == some(tsHome)
    check navigator.currentDestination() == some(tsHome)
    check not navigator.canGoBack()
    check not navigator.canGoForward()

  test "push back and forward preserve history entry identity":
    let navigator = initStackNavigator(tsHome)
    var changes: seq[NavigationChangeKind] = @[]
    navigator.addListener(proc(change: NavigationChange[TestScreen]) =
      changes.add change.kind
      check change.dirtyDomains == navigationScreenDirtyDomains
    )

    let homeId = navigator.currentEntry().get.id
    check navigator.push(tsSettings)
    let settingsId = navigator.currentEntry().get.id
    check settingsId != homeId
    check navigator.push(tsDetails)
    let detailsId = navigator.currentEntry().get.id

    check navigator.back()
    check navigator.currentEntry().get.id == settingsId
    check navigator.back()
    check navigator.currentEntry().get.id == homeId
    check navigator.forward()
    check navigator.currentEntry().get.id == settingsId
    check navigator.forward()
    check navigator.currentEntry().get.id == detailsId
    check changes == @[nckPush, nckPush, nckBack, nckBack, nckForward, nckForward]
    check navigator.snapshot().revision == 6

  test "push after back truncates the forward branch":
    let navigator = initStackNavigator(tsHome)
    discard navigator.push(tsSettings)
    discard navigator.push(tsDetails)
    discard navigator.back()

    check navigator.canGoForward()
    check navigator.push(tsLogin)

    let snapshot = navigator.snapshot()
    check snapshot.entries.len == 3
    check snapshot.currentDestination() == some(tsLogin)
    check snapshot.entries[0].destination == tsHome
    check snapshot.entries[1].destination == tsSettings
    check snapshot.entries[2].destination == tsLogin
    check not navigator.canGoForward()

  test "replace keeps the history position but creates a new screen entry":
    let navigator = initStackNavigator(tsHome)
    discard navigator.push(tsSettings)
    let previous = navigator.currentEntry().get

    check navigator.replace(tsLogin)

    let snapshot = navigator.snapshot()
    check snapshot.entries.len == 2
    check snapshot.currentIndex == 1
    check snapshot.currentDestination() == some(tsLogin)
    check snapshot.currentEntry().get.id != previous.id
    check navigator.canGoBack()

  test "change metadata describes the transition before notifying listeners":
    var observed: seq[NavigationChange[TestScreen]] = @[]
    let navigator = initStackNavigator(
      tsHome,
      proc(change: NavigationChange[TestScreen]) =
        observed.add change
    )
    let home = navigator.currentEntry().get

    check navigator.push(tsSettings)
    let settings = navigator.currentEntry().get
    check navigator.replace(tsDetails)
    let details = navigator.currentEntry().get
    check navigator.back()
    check navigator.forward()

    check observed.len == 4
    check observed[0].kind == nckPush
    check observed[0].previous == some(home)
    check observed[0].current == some(settings)
    check observed[0].snapshot.revision == 1
    check observed[1].kind == nckReplace
    check observed[1].previous == some(settings)
    check observed[1].current == some(details)
    check observed[1].snapshot.revision == 2
    check observed[2].kind == nckBack
    check observed[2].previous == some(details)
    check observed[2].current == some(home)
    check observed[3].kind == nckForward
    check observed[3].previous == some(home)
    check observed[3].current == some(details)
    for change in observed:
      check change.dirtyDomains == navigationScreenDirtyDomains

  test "entry IDs remain unique after replacement and branch truncation":
    let navigator = initStackNavigator(tsHome)
    let homeId = navigator.currentEntry().get.id
    discard navigator.push(tsSettings)
    let discardedId = navigator.currentEntry().get.id
    discard navigator.push(tsDetails)
    let detailsId = navigator.currentEntry().get.id
    discard navigator.back()
    discard navigator.back()
    discard navigator.push(tsLogin)
    let loginId = navigator.currentEntry().get.id
    discard navigator.replace(tsSettings)
    let replacementId = navigator.currentEntry().get.id

    check homeId.entryIdValue() == 1
    check discardedId.entryIdValue() == 2
    check detailsId.entryIdValue() == 3
    check loginId.entryIdValue() == 4
    check replacementId.entryIdValue() == 5

  test "returned snapshots cannot mutate the stack structure":
    let navigator = initStackNavigator(tsHome)
    discard navigator.push(tsSettings)
    var external = navigator.snapshot()
    external.entries[0].destination = tsLogin
    external.entries.setLen(1)
    external.currentIndex = -1
    external.revision = 999

    let current = navigator.snapshot()
    check current.entries.len == 2
    check current.entries[0].destination == tsHome
    check current.entries[1].destination == tsSettings
    check current.currentIndex == 1
    check current.revision == 1

  test "history boundaries are no-ops and do not notify listeners":
    let navigator = initStackNavigator(tsHome)
    var notifications = 0
    navigator.addListener(proc(change: NavigationChange[TestScreen]) =
      inc notifications
    )

    check not navigator.back()
    check not navigator.forward()
    check notifications == 0
    check navigator.snapshot().revision == 0

  test "application-owned drivers can replace the default stack":
    var current = tsHome
    var revision = 0'u64
    var pushed: seq[TestScreen] = @[]

    proc customSnapshot(): NavigationSnapshot[TestScreen] =
      NavigationSnapshot[TestScreen](
        entries: @[NavigationEntry[TestScreen](id: NavigationEntryId(99), destination: current)],
        currentIndex: 0,
        revision: revision
      )

    proc customPush(destination: TestScreen): Option[NavigationChange[TestScreen]] =
      let previous = customSnapshot().currentEntry()
      current = destination
      pushed.add destination
      inc revision
      let snapshot = customSnapshot()
      some(NavigationChange[TestScreen](
        kind: nckPush,
        previous: previous,
        current: snapshot.currentEntry(),
        snapshot: snapshot,
        dirtyDomains: {ddPaint}
      ))

    proc customReplace(destination: TestScreen): Option[NavigationChange[TestScreen]] =
      customPush(destination)

    proc noStep(): Option[NavigationChange[TestScreen]] =
      none(NavigationChange[TestScreen])

    let navigator = initNavigator(NavigationDriver[TestScreen](
      snapshot: customSnapshot,
      push: customPush,
      replace: customReplace,
      back: noStep,
      forward: noStep
    ))

    check navigator.push(tsDetails)
    check pushed == @[tsDetails]
    check navigator.currentDestination() == some(tsDetails)
    check not navigator.back()

  test "navigators can be injected through a view context":
    let navigator = initStackNavigator(tsHome)
    let context = initViewContext([provide(navigator)])

    check context.has(Navigator[TestScreen])
    check context.use(Navigator[TestScreen]) == navigator

  test "incomplete custom drivers are rejected":
    expect ValueError:
      discard initNavigator(NavigationDriver[TestScreen]())

  test "nil listeners are rejected and listener IDs are monotonic":
    let navigator = initStackNavigator(tsHome)
    expect ValueError:
      discard navigator.addListener(NavigationChangedProc[TestScreen](nil))

    let first = navigator.addListener(proc(change: NavigationChange[TestScreen]) =
      discard
    )
    let second = navigator.addListener(proc(change: NavigationChange[TestScreen]) =
      discard
    )
    check first.listenerIdValue() > 0
    check second.listenerIdValue() == first.listenerIdValue() + 1
    navigator.clearListeners()
    let third = navigator.addListener(proc(change: NavigationChange[TestScreen]) =
      discard
    )
    check third.listenerIdValue() == second.listenerIdValue() + 1

  test "listeners run in registration order and can all be cleared":
    let navigator = initStackNavigator(tsHome)
    var order: seq[int] = @[]
    discard navigator.addListener(proc(change: NavigationChange[TestScreen]) =
      order.add 1
    )
    discard navigator.addListener(proc(change: NavigationChange[TestScreen]) =
      order.add 2
    )
    navigator.push(tsSettings)
    check order == @[1, 2]

    navigator.clearListeners()
    navigator.push(tsDetails)
    check order == @[1, 2]

  test "listeners can be removed without changing other subscriptions":
    let navigator = initStackNavigator(tsHome)
    var firstCalls = 0
    var secondCalls = 0
    let first = navigator.addListener(proc(change: NavigationChange[TestScreen]) =
      inc firstCalls
    )
    discard navigator.addListener(proc(change: NavigationChange[TestScreen]) =
      inc secondCalls
    )

    check navigator.removeListener(first)
    check not navigator.removeListener(first)
    navigator.push(tsSettings)

    check firstCalls == 0
    check secondCalls == 1

  test "listener changes made during notification apply on the next change":
    let navigator = initStackNavigator(tsHome)
    var firstCalls = 0
    var lateCalls = 0
    var firstId: NavigationListenerId
    firstId = navigator.addListener(proc(change: NavigationChange[TestScreen]) =
      inc firstCalls
      discard navigator.removeListener(firstId)
      discard navigator.addListener(proc(change: NavigationChange[TestScreen]) =
        inc lateCalls
      )
    )

    navigator.push(tsSettings)
    check firstCalls == 1
    check lateCalls == 0

    navigator.push(tsDetails)
    check firstCalls == 1
    check lateCalls == 1

  test "clearing listeners during notification does not corrupt the current pass":
    let navigator = initStackNavigator(tsHome)
    var calls: seq[string] = @[]
    discard navigator.addListener(proc(change: NavigationChange[TestScreen]) =
      calls.add "first"
      navigator.clearListeners()
    )
    discard navigator.addListener(proc(change: NavigationChange[TestScreen]) =
      calls.add "second"
    )

    navigator.push(tsSettings)
    check calls == @["first", "second"]
    navigator.push(tsDetails)
    check calls == @["first", "second"]

  test "generic destinations retain structured values":
    type Route = object
      path: string
      page: int

    let navigator = initStackNavigator(Route(path: "/", page: 1))
    check navigator.push(Route(path: "/items", page: 42))
    let current = navigator.currentDestination().get
    check current.path == "/items"
    check current.page == 42

  test "mixed history operations match an independent state model":
    type ModelEntry = tuple[id: uint64, destination: TestScreen]

    var notifications = 0
    let navigator = initStackNavigator(
      tsHome,
      proc(change: NavigationChange[TestScreen]) =
        inc notifications
    )
    var model: seq[ModelEntry] = @[(id: 1'u64, destination: tsHome)]
    var modelIndex = 0
    var nextId = 2'u64
    var revision = 0'u64
    var rng = initRand(0xCB55)

    for iteration in 0 ..< 2_000:
      let operation = rng.rand(3)
      let destination = TestScreen(rng.rand(ord(TestScreen.high)))
      var changed = false
      case operation
      of 0:
        if modelIndex < model.high:
          model.setLen(modelIndex + 1)
        model.add (id: nextId, destination: destination)
        inc nextId
        modelIndex = model.high
        changed = true
        check navigator.push(destination)
      of 1:
        model[modelIndex] = (id: nextId, destination: destination)
        inc nextId
        changed = true
        check navigator.replace(destination)
      of 2:
        if modelIndex > 0:
          dec modelIndex
          changed = true
        check navigator.back() == changed
      else:
        if modelIndex < model.high:
          inc modelIndex
          changed = true
        check navigator.forward() == changed

      if changed:
        inc revision
      let actual = navigator.snapshot()
      check actual.currentIndex == modelIndex
      check actual.revision == revision
      check actual.entries.len == model.len
      check notifications == int(revision)
      for index, expected in model:
        check actual.entries[index].id.entryIdValue() == expected.id
        check actual.entries[index].destination == expected.destination
