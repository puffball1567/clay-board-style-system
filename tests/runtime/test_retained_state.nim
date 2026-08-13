import std/[options, strutils, unittest]

import clay_board_style_system
import clay_board_style_system/frontend_runtime

type
  WatchedComponent = ref object of CBSSComponent
    source: State[int]
    values: ref seq[int]
    child: NodeHandle

  FailingWatchComponent = ref object of CBSSComponent
    source: State[int]

proc render(self: WatchedComponent) =
  ui.box(self):
    self.child = ui.box()
    ui.text(self.child, "watched")

method onMount(self: WatchedComponent) =
  discard self.watch(
    self.source,
    proc(value: int) = self.values[].add(value),
    dirtyDomains = {ddText, ddPaint},
    target = some(self.child)
  )

proc render(self: FailingWatchComponent) =
  ui.box(self):
    ui.text("failing watch")

method onMount(self: FailingWatchComponent) =
  discard self.watch(self.source, proc(value: int) = discard)
  raise newException(ValueError, "mount failed")

suite "retained frontend state":
  test "state publishes changed values and suppresses equal writes":
    let state = initState(1)
    var values: seq[int]
    discard state.signal.subscribe(proc(value: int) = values.add(value))

    check not state.set(1)
    check state.set(2)
    check state.value == 2
    check values == @[2]

  test "custom equality controls publication":
    let state = initState(
      "ready",
      proc(left, right: string): bool = left.toLowerAscii == right.toLowerAscii
    )
    var values: seq[string]
    discard state.signal.subscribe(proc(value: string) = values.add(value))

    check not state.set("READY")
    check state.set("done")
    check values == @["done"]

  test "batch publishes the final value once":
    let state = initState(0)
    var values: seq[int]
    discard state.signal.subscribe(proc(value: int) = values.add(value))

    batch:
      discard state.set(1)
      discard state.set(2)
      discard state.set(3)

    check state.value == 3
    check values == @[3]

  test "batch suppresses a round trip to the published value":
    let state = initState(0)
    var calls = 0
    discard state.signal.subscribe(proc(value: int) = inc calls)

    batch:
      discard state.set(1)
      discard state.set(0)

    check calls == 0

  test "nested batches share the outer commit boundary":
    let first = initState(0)
    let second = initState("idle")
    var order: seq[string]
    discard first.signal.subscribe(proc(value: int) = order.add("first:" & $value))
    discard second.signal.subscribe(proc(value: string) = order.add("second:" & value))

    batch:
      discard first.set(1)
      batch:
        discard second.set("ready")
        discard first.set(2)
      check order.len == 0

    check order == @["first:2", "second:ready"]

  test "reentrant writes run in a later publication turn":
    let state = initState(0)
    var values: seq[int]
    discard state.signal.subscribe(proc(value: int) =
      values.add(value)
      if value == 1:
        discard state.set(2)
    )

    discard state.set(1)

    check values == @[1, 2]

  test "publication failure does not leave state permanently queued":
    let state = initState(0)
    var shouldRaise = true
    discard state.signal.subscribe(proc(value: int) =
      if shouldRaise:
        shouldRaise = false
        raise newException(ValueError, "listener failed")
    )

    expect ValueError:
      discard state.set(1)
    check state.set(2)
    check state.value == 2

  test "a reentrant write is committed even when its listener raises":
    let state = initState(0)
    var values: seq[int]
    var shouldRaise = true
    discard state.signal.subscribe(proc(value: int) =
      values.add(value)
      if value == 1:
        discard state.set(2)
      if shouldRaise:
        shouldRaise = false
        raise newException(ValueError, "listener failed")
    )

    expect ValueError:
      discard state.set(1)
    check state.value == 2
    check values == @[1, 2]
    check state.set(3)
    check values == @[1, 2, 3]

  test "batch commits completed writes when its body raises":
    let state = initState(0)
    var values: seq[int]
    discard state.signal.subscribe(proc(value: int) = values.add(value))

    expect ValueError:
      batch:
        discard state.set(1)
        raise newException(ValueError, "batch failed")

    check state.value == 1
    check values == @[1]

  test "update publishes a changed object and rejects nil mutations":
    type Model = object
      count: int
    let state = initState(Model(count: 1))
    var observed = 0
    discard state.signal.subscribe(proc(value: Model) = observed = value.count)

    check state.update(proc(value: var Model) = value.count += 2)
    check observed == 3
    expect ValueError:
      discard state.update(nil)

  test "a failed update leaves the previous value intact":
    let state = initState(4)
    expect ValueError:
      discard state.update(proc(value: var int) =
        value = 9
        raise newException(ValueError, "mutation failed")
      )
    check state.value == 4

  test "component watch applies the current value and exact invalidation":
    let root = initUiRoot()
    let values = new seq[int]
    let state = initState(4)
    let component = root.mount(WatchedComponent(source: state, values: values))

    check values[] == @[4]
    discard root.consumeInvalidation()
    discard state.set(5)

    check values[] == @[4, 5]
    let invalidation = root.consumeInvalidation()
    check invalidation.domains == {ddText, ddPaint}
    check invalidation.roots == @[component.child.id]

  test "component watch is detached on unmount":
    let root = initUiRoot()
    let values = new seq[int]
    let state = initState(1)
    let component = root.mount(WatchedComponent(source: state, values: values))
    check state.subscriberCount == 1

    var interaction = initInteractionState()
    check root.disposeSubtree(component.node, interaction)
    check state.subscriberCount == 0
    discard state.set(2)
    check values[] == @[1]

  test "component watch is detached when mounting fails":
    let root = initUiRoot()
    let state = initState(1)

    expect ValueError:
      discard root.mount(FailingWatchComponent(source: state))

    check state.subscriberCount == 0
    check state.set(2)

  test "component watch can be disposed before unmount":
    let root = initUiRoot()
    let values = new seq[int]
    let state = initState(1)
    let component = root.mount(WatchedComponent(source: state, values: values))
    let watch = component.watch(state, proc(value: int) = values[].add(value))
    check state.subscriberCount == 2

    check watch.dispose()
    check not watch.dispose()
    check state.subscriberCount == 1
    discard state.set(2)
    check values[] == @[1, 1, 2]

  test "signal watch does not synthesize an initial occurrence":
    let root = initUiRoot()
    let values = new seq[int]
    let state = initState(1)
    let component = root.mount(WatchedComponent(source: state, values: values))
    let occurrence = initSignal[string]()
    var received: seq[string]
    discard component.watch(occurrence, proc(value: string) = received.add(value))

    check received.len == 0
    occurrence.emit("ready")
    check received == @["ready"]

  test "watch rejects a target owned by another root":
    let root = initUiRoot()
    let otherRoot = initUiRoot()
    let values = new seq[int]
    let state = initState(1)
    let component = root.mount(WatchedComponent(source: state, values: values))
    let foreign = otherRoot.box()

    expect ComponentContextError:
      discard component.watch(
        state,
        proc(value: int) = discard,
        target = some(foreign)
      )
    check state.subscriberCount == 1

  test "nil state operations fail explicitly":
    var state: State[int]
    expect ValueError:
      discard state.value
    expect ValueError:
      discard state.set(1)
    expect ValueError:
      discard state.signal

  test "nil component watch fails before invoking the listener":
    var component: CBSSComponent
    let state = initState(1)
    var calls = 0
    expect ComponentContextError:
      discard component.watch(state, proc(value: int) = inc calls)
    check calls == 0
