import ./[retained_state, signal, state_runtime]

type
  SelectorProc*[Source, Selected] = proc(state: Source): Selected {.closure.}

  StoreSelector*[Source, Action, Selected] = ref object
    selected: State[Selected]
    source: Signal[uint64]
    subscription: SignalSubscription
    refreshCallback: proc() {.closure.}
    disposedValue: bool

proc requireSelector[Source, Action, Selected](
    selector: StoreSelector[Source, Action, Selected]
) =
  if selector.isNil:
    raise newException(ValueError, "store selector cannot be nil")
  if selector.disposedValue:
    raise newException(ValueError, "store selector is disposed")

proc select*[Source, Action, Selected](
    runtime: StateRuntime[Source, Action];
    projection: SelectorProc[Source, Selected];
    equal: StateEqualProc[Selected] = nil
): StoreSelector[Source, Action, Selected] =
  if runtime.isNil:
    raise newException(ValueError, "selector store cannot be nil")
  if projection.isNil:
    raise newException(ValueError, "selector projection cannot be nil")

  let selected = initState(projection(runtime.state), equal)
  let source = runtime.commitSignal
  let sourceState = addr runtime.state
  let project = projection
  let subscription = source.subscribe(proc(revision: uint64) =
    discard revision
    discard selected.set(project(sourceState[]))
  )

  result = StoreSelector[Source, Action, Selected](
    selected: selected,
    source: source,
    subscription: subscription,
    refreshCallback: proc() =
      discard selected.set(project(runtime.state))
  )

proc refresh*[Source, Action, Selected](
    selector: StoreSelector[Source, Action, Selected]
) =
  selector.requireSelector()
  selector.refreshCallback()

proc value*[Source, Action, Selected](
    selector: StoreSelector[Source, Action, Selected]
): lent Selected =
  selector.requireSelector()
  selector.selected.value

proc signal*[Source, Action, Selected](
    selector: StoreSelector[Source, Action, Selected]
): Signal[Selected] =
  selector.requireSelector()
  selector.selected.signal

proc dispose*[Source, Action, Selected](
    selector: StoreSelector[Source, Action, Selected]
): bool {.discardable.} =
  if selector.isNil or selector.disposedValue:
    return false
  selector.disposedValue = true
  if not selector.source.isNil:
    discard selector.source.unsubscribe(selector.subscription)
  selector.source = nil
  selector.subscription = SignalSubscription()
  selector.refreshCallback = nil
  if not selector.selected.isNil:
    selector.selected.signal.clear()
  selector.selected = nil
  true

proc disposed*[Source, Action, Selected](
    selector: StoreSelector[Source, Action, Selected]
): bool =
  selector.isNil or selector.disposedValue

proc subscriberCount*[Source, Action, Selected](
    selector: StoreSelector[Source, Action, Selected]
): int =
  if not selector.isNil and not selector.disposedValue:
    result = selector.selected.subscriberCount
