import std/unittest

import clay_board_style_system
import clay_board_style_system/frontend_runtime

type
  CounterAction = enum
    caIncrement

  TriggerComponent = ref object of CBSSComponent
    source: Signal[int]
    events: ref seq[int]
    runtime: CueRuntime
    trigger: CueTrigger[int]

proc render(self: TriggerComponent) =
  self.runtime = self.cueRuntime()
  let events = self.events
  self.trigger = self.cueOn(
    self.source,
    self.runtime,
    proc(value: int): CueGraph =
      cue(cueAction("record", proc() = events[].add value))
  )
  ui.box(self):
    ui.text("trigger")

suite "typed Cue source adapters":
  test "Signal values build and start typed Cue graphs":
    let source = initSignal[int]()
    let runtime = initCueRuntime()
    var values: seq[int]
    let trigger = initCueTrigger(
      source,
      runtime,
      proc(value: int): CueGraph =
        cue(cueAction("record", proc() = values.add value))
    )
    defer:
      check trigger.dispose()
      check runtime.dispose()

    source.emit(3)
    source.emit(7)
    check values == @[3, 7]
    check trigger.activeCount == 0

  test "fixed graphs can be shared by an occurrence source":
    let source = initSignal[string]()
    let runtime = initCueRuntime()
    var runs = 0
    let graph = cue(cueAction("run", proc() = inc runs))
    let trigger = initCueTrigger(source, runtime, graph)
    defer:
      check trigger.dispose()
      check runtime.dispose()

    source.emit("first")
    source.emit("second")
    check runs == 2

  test "repeated-start policy is preserved by the source adapter":
    let source = initSignal[int]()
    let runtime = initCueRuntime()
    var completions: seq[CueCompletion]
    let graph = cue(cueAction("pending", proc(completion: CueCompletion): CueCancel =
      completions.add completion
      nil
    ))
    let trigger = initCueTrigger(source, runtime, graph, cspQueue)
    defer:
      check trigger.dispose()
      check runtime.dispose()

    source.emit(1)
    source.emit(2)
    source.emit(3)
    check runtime.activeCount == 1
    check trigger.activeCount == 3
    completions[0].succeed()
    check completions.len == 2
    completions[1].succeed()
    check completions.len == 3
    completions[2].succeed()
    check trigger.activeCount == 0

  test "disposing a trigger unsubscribes and cancels its active sessions":
    let source = initSignal[int]()
    let runtime = initCueRuntime()
    var cancellations = 0
    let graph = cue(cueAction("pending", proc(completion: CueCompletion): CueCancel =
      discard completion
      return proc() {.raises: [].} = inc cancellations
    ))
    let trigger = initCueTrigger(source, runtime, graph)
    defer:
      check runtime.dispose()
    source.emit(1)
    check source.listenerCount == 1
    check runtime.activeCount == 1

    check trigger.dispose()
    check source.listenerCount == 0
    check runtime.activeCount == 0
    check cancellations == 1
    source.emit(2)
    check cancellations == 1

  test "component ownership removes the subscription before its runtime":
    let root = initUiRoot()
    let source = initSignal[int]()
    let events = new seq[int]
    let component = root.mount(TriggerComponent(source: source, events: events))
    source.emit(9)
    check events[] == @[9]

    var interaction = initInteractionState()
    check root.disposeSubtree(component.node, interaction)
    check source.listenerCount == 0
    source.emit(10)
    check events[] == @[9]

  test "State changes enter Cue through their typed Signal":
    let root = initUiRoot()
    let source = initState(1)
    let runtime = initCueRuntime()
    var values: seq[int]
    let component = root.mount(TriggerComponent(
      source: initSignal[int](),
      events: new seq[int]
    ))
    discard component.own(runtime)
    discard component.cueOn(
      source,
      runtime,
      proc(value: int): CueGraph =
        cue(cueAction("state", proc() = values.add value))
    )

    discard source.set(2)
    discard source.set(3)
    check values == @[2, 3]
    var interaction = initInteractionState()
    check root.disposeSubtree(component.node, interaction)

  test "Store commits provide one Cue occurrence per committed revision":
    let root = initUiRoot()
    let store = createStore(0, proc(state: var int; action: CounterAction) =
      case action
      of caIncrement:
        inc state
    )
    let runtime = initCueRuntime()
    var revisions: seq[uint64]
    let component = root.mount(TriggerComponent(
      source: initSignal[int](),
      events: new seq[int]
    ))
    discard component.own(runtime)
    discard component.cueOn(
      store,
      runtime,
      proc(revision: uint64): CueGraph =
        cue(cueAction("commit", proc() = revisions.add revision))
    )

    store.transaction:
      store.dispatch(caIncrement)
      store.dispatch(caIncrement)
    check store.state == 2
    check revisions == @[1'u64]
    var interaction = initInteractionState()
    check root.disposeSubtree(component.node, interaction)

  test "selected Store values start Cue only when the projection changes":
    let root = initUiRoot()
    let store = createStore(0, proc(state: var int; action: CounterAction) =
      case action
      of caIncrement:
        inc state
    )
    let parity = store.select(proc(value: int): int = value mod 2)
    let runtime = initCueRuntime()
    var values: seq[int]
    let component = root.mount(TriggerComponent(
      source: initSignal[int](),
      events: new seq[int]
    ))
    discard component.own(runtime)
    discard component.cueOn(
      parity,
      runtime,
      proc(value: int): CueGraph =
        cue(cueAction("selection", proc() = values.add value))
    )

    store.dispatch(caIncrement)
    store.dispatch(caIncrement)
    check values == @[1, 0]
    check parity.dispose()
    var interaction = initInteractionState()
    check root.disposeSubtree(component.node, interaction)

  test "Store and selector fixed graphs preserve the concise trigger form":
    let root = initUiRoot()
    let store = createStore(0, proc(state: var int; action: CounterAction) =
      case action
      of caIncrement:
        inc state
    )
    let parity = store.select(proc(value: int): int = value mod 2)
    let runtime = initCueRuntime()
    var commits = 0
    var selections = 0
    let component = root.mount(TriggerComponent(
      source: initSignal[int](),
      events: new seq[int]
    ))
    discard component.own(runtime)
    discard component.cueOn(
      store,
      runtime,
      cue(cueAction("commit", proc() = inc commits))
    )
    discard component.cueOn(
      parity,
      runtime,
      cue(cueAction("selection", proc() = inc selections))
    )

    store.dispatch(caIncrement)
    store.dispatch(caIncrement)
    check commits == 2
    check selections == 2
    check parity.dispose()
    var interaction = initInteractionState()
    check root.disposeSubtree(component.node, interaction)

  test "invalid source runtime factory and nil graph fail explicitly":
    let source = initSignal[int]()
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    expect ValueError:
      discard initCueTrigger[int](nil, runtime, cue(cueAction("x", proc() = discard)))
    expect ValueError:
      discard initCueTrigger(source, CueRuntime(nil), cue(cueAction("x", proc() = discard)))
    expect ValueError:
      discard initCueTrigger(source, runtime, CueGraphFactory[int](nil))
    let trigger = initCueTrigger(
      source,
      runtime,
      proc(value: int): CueGraph = nil
    )
    defer:
      check trigger.dispose()
    expect ValueError:
      source.emit(1)
    check trigger.activeCount == 0
