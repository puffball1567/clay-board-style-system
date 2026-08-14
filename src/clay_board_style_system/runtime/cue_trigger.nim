import ./[
  component,
  cue,
  retained_state,
  signal,
  state_runtime,
  store_selector
]

type
  CueGraphFactory*[Value] = proc(value: Value): CueGraph {.closure.}

  CueTriggerSourceKind = enum
    ctskSignal,
    ctskState,
    ctskStore,
    ctskSelector

  CueTrigger*[Value] = ref object of ComponentOwnedResource
    source: Signal[Value]
    subscription: SignalSubscription
    runtime: CueRuntime
    graphFactory: CueGraphFactory[Value]
    policyValue: CueStartPolicy
    sessions: seq[CueSession]

proc compactSessions[Value](trigger: CueTrigger[Value]) =
  var retained = newSeqOfCap[CueSession](trigger.sessions.len)
  for session in trigger.sessions:
    if session.status in {cssQueued, cssRunning}:
      retained.add session
  trigger.sessions = move(retained)

proc releaseCueTrigger[Value](resource: ComponentOwnedResource) {.raises: [].} =
  let trigger = CueTrigger[Value](resource)
  if not trigger.source.isNil:
    discard trigger.source.unsubscribe(trigger.subscription)
  if not trigger.runtime.isNil and not trigger.runtime.disposed:
    for session in trigger.sessions:
      try:
        discard trigger.runtime.cancel(session)
      except Exception:
        discard
  trigger.sessions.setLen(0)
  trigger.source = nil
  trigger.runtime = nil
  trigger.graphFactory = nil
  trigger.subscription = SignalSubscription()

proc initCueTriggerWithSource[Value](
    source: Signal[Value];
    runtime: CueRuntime;
    graphFactory: CueGraphFactory[Value];
    policy: CueStartPolicy;
    sourceKind: static[CueTriggerSourceKind]
): CueTrigger[Value] =
  if source.isNil:
    raise newException(ValueError, "Cue trigger source cannot be nil")
  if runtime.isNil or runtime.disposed:
    raise newException(ValueError, "Cue trigger runtime is not active")
  if graphFactory.isNil:
    raise newException(ValueError, "Cue graph factory cannot be nil")

  result = CueTrigger[Value](
    source: source,
    runtime: runtime,
    graphFactory: graphFactory,
    policyValue: policy
  )
  result.setReleaseCallback(releaseCueTrigger[Value])
  let trigger = result
  result.subscription = source.subscribe(proc(value: Value) =
    if trigger.disposed or trigger.runtime.isNil or trigger.runtime.disposed:
      return
    trigger.compactSessions()
    when not defined(release) or defined(cbssFrontendTrace):
      let traceKind = case sourceKind
        of ctskSignal: ftkTriggerSignal
        of ctskState: ftkTriggerState
        of ctskStore: ftkTriggerStore
        of ctskSelector: ftkTriggerSelector
      when Value is uint64:
        if sourceKind == ctskStore:
          trigger.runtime.traceTrigger(traceKind, revision = value)
        else:
          trigger.runtime.traceTrigger(traceKind)
      else:
        trigger.runtime.traceTrigger(traceKind)
    let graph = trigger.graphFactory(value)
    if graph.isNil:
      raise newException(ValueError, "Cue graph factory returned nil")
    trigger.sessions.add trigger.runtime.start(graph, trigger.policyValue)
  )

proc initCueTrigger*[Value](
    source: Signal[Value];
    runtime: CueRuntime;
    graphFactory: CueGraphFactory[Value];
    policy = cspRestart
): CueTrigger[Value] =
  initCueTriggerWithSource(source, runtime, graphFactory, policy, ctskSignal)

proc initCueTrigger*[Value](
    source: Signal[Value];
    runtime: CueRuntime;
    graph: CueGraph;
    policy = cspRestart
): CueTrigger[Value] =
  if graph.isNil:
    raise newException(ValueError, "Cue trigger graph cannot be nil")
  initCueTriggerWithSource(
    source,
    runtime,
    proc(value: Value): CueGraph =
      discard value
      graph,
    policy,
    ctskSignal
  )

proc ownTrigger[Value](
    component: CBSSComponent;
    trigger: CueTrigger[Value]
): CueTrigger[Value] =
  if component.isNil:
    raise newException(ComponentContextError, "component cannot be nil")
  try:
    result = component.own(trigger)
  except:
    discard trigger.dispose()
    raise

proc cueOn*[Value](
    component: CBSSComponent;
    source: Signal[Value];
    runtime: CueRuntime;
    graphFactory: CueGraphFactory[Value];
    policy = cspRestart
): CueTrigger[Value] =
  component.ownTrigger(initCueTrigger(source, runtime, graphFactory, policy))

proc cueOn*[Value](
    component: CBSSComponent;
    source: Signal[Value];
    runtime: CueRuntime;
    graph: CueGraph;
    policy = cspRestart
): CueTrigger[Value] =
  component.ownTrigger(initCueTrigger(source, runtime, graph, policy))

proc cueOn*[Value](
    component: CBSSComponent;
    state: State[Value];
    runtime: CueRuntime;
    graphFactory: CueGraphFactory[Value];
    policy = cspRestart
): CueTrigger[Value] =
  if state.isNil:
    raise newException(ComponentContextError, "Cue trigger state cannot be nil")
  component.ownTrigger(initCueTriggerWithSource(
    state.signal,
    runtime,
    graphFactory,
    policy,
    ctskState
  ))

proc cueOn*[Value](
    component: CBSSComponent;
    state: State[Value];
    runtime: CueRuntime;
    graph: CueGraph;
    policy = cspRestart
): CueTrigger[Value] =
  if state.isNil:
    raise newException(ComponentContextError, "Cue trigger state cannot be nil")
  component.ownTrigger(initCueTriggerWithSource(
    state.signal,
    runtime,
    proc(value: Value): CueGraph =
      discard value
      graph,
    policy,
    ctskState
  ))

proc cueOn*[Source, Action, Value](
    component: CBSSComponent;
    selector: StoreSelector[Source, Action, Value];
    runtime: CueRuntime;
    graphFactory: CueGraphFactory[Value];
    policy = cspRestart
): CueTrigger[Value] =
  if selector.isNil or selector.disposed:
    raise newException(ComponentContextError, "Cue trigger selector is not active")
  component.ownTrigger(initCueTriggerWithSource(
    selector.signal,
    runtime,
    graphFactory,
    policy,
    ctskSelector
  ))

proc cueOn*[Source, Action, Value](
    component: CBSSComponent;
    selector: StoreSelector[Source, Action, Value];
    runtime: CueRuntime;
    graph: CueGraph;
    policy = cspRestart
): CueTrigger[Value] =
  if selector.isNil or selector.disposed:
    raise newException(ComponentContextError, "Cue trigger selector is not active")
  component.ownTrigger(initCueTriggerWithSource(
    selector.signal,
    runtime,
    proc(value: Value): CueGraph =
      discard value
      graph,
    policy,
    ctskSelector
  ))

proc cueOn*[Source, Action](
    component: CBSSComponent;
    store: StateRuntime[Source, Action];
    runtime: CueRuntime;
    graphFactory: CueGraphFactory[uint64];
    policy = cspRestart
): CueTrigger[uint64] =
  if store.isNil:
    raise newException(ComponentContextError, "Cue trigger Store cannot be nil")
  component.ownTrigger(initCueTriggerWithSource(
    store.commitSignal,
    runtime,
    graphFactory,
    policy,
    ctskStore
  ))

proc cueOn*[Source, Action](
    component: CBSSComponent;
    store: StateRuntime[Source, Action];
    runtime: CueRuntime;
    graph: CueGraph;
    policy = cspRestart
): CueTrigger[uint64] =
  if store.isNil:
    raise newException(ComponentContextError, "Cue trigger Store cannot be nil")
  component.ownTrigger(initCueTriggerWithSource(
    store.commitSignal,
    runtime,
    proc(value: uint64): CueGraph =
      discard value
      graph,
    policy,
    ctskStore
  ))

proc activeCount*[Value](trigger: CueTrigger[Value]): int =
  if trigger.isNil or trigger.disposed:
    return 0
  trigger.compactSessions()
  trigger.sessions.len
