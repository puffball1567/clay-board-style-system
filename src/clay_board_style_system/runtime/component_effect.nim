import ./[component, retained_state, signal, store_selector]

type
  EffectCleanup* = proc() {.closure, raises: [].}
  EffectRun*[Value] = proc(value: Value): EffectCleanup {.closure.}

  ComponentEffect*[Value] = ref object of ComponentOwnedResource
    source: Signal[Value]
    subscription: SignalSubscription
    cleanupValue: EffectCleanup
    running: bool
    pendingValues: seq[Value]

proc cleanup*(release: EffectCleanup): EffectCleanup {.inline.} =
  ## Makes cleanup-producing effects read naturally without introducing a
  ## second resource abstraction.
  release

proc clearCurrent[Value](effect: ComponentEffect[Value]) {.raises: [].} =
  let release = effect.cleanupValue
  effect.cleanupValue = nil
  if release != nil:
    release()

proc releaseComponentEffect[Value](
    resource: ComponentOwnedResource
) {.raises: [].} =
  let effect = ComponentEffect[Value](resource)
  if not effect.source.isNil:
    discard effect.source.unsubscribe(effect.subscription)
  effect.source = nil
  effect.subscription = SignalSubscription()
  effect.pendingValues.setLen(0)
  effect.clearCurrent()

proc execute[Value](
    effect: ComponentEffect[Value];
    run: EffectRun[Value];
    value: sink Value
) =
  if effect.disposed:
    return
  effect.pendingValues.add move(value)
  if effect.running:
    return

  effect.running = true
  var index = 0
  try:
    while index < effect.pendingValues.len and not effect.disposed:
      var current = move(effect.pendingValues[index])
      inc index
      effect.clearCurrent()
      let nextCleanup = run(move(current))
      if effect.disposed:
        if nextCleanup != nil:
          nextCleanup()
        break
      effect.cleanupValue = nextCleanup
  finally:
    effect.pendingValues.setLen(0)
    effect.running = false

proc initComponentEffect[Value](
    component: CBSSComponent;
    source: Signal[Value];
    run: EffectRun[Value]
): ComponentEffect[Value] =
  if component.isNil:
    raise newException(ComponentContextError, "component cannot be nil")
  if source.isNil:
    raise newException(ComponentContextError, "effect source cannot be nil")
  if run.isNil:
    raise newException(ComponentContextError, "effect callback cannot be nil")

  result = ComponentEffect[Value](source: source)
  result.setReleaseCallback(releaseComponentEffect[Value])
  let ownedEffect = result
  result.subscription = source.subscribe(proc(value: Value) =
    ownedEffect.execute(run, value)
  )
  try:
    discard component.own(result)
  except:
    discard source.unsubscribe(result.subscription)
    result.source = nil
    result.subscription = SignalSubscription()
    raise

proc effect*[Value](
    component: CBSSComponent;
    source: Signal[Value];
    run: EffectRun[Value]
): ComponentEffect[Value] =
  initComponentEffect(component, source, run)

proc effect*[Value](
    component: CBSSComponent;
    state: State[Value];
    run: EffectRun[Value];
    immediate = true
): ComponentEffect[Value] =
  if state.isNil:
    raise newException(ComponentContextError, "effect state cannot be nil")
  result = initComponentEffect(component, state.signal, run)
  if immediate:
    try:
      result.execute(run, state.value)
    except:
      discard result.dispose()
      raise

proc effect*[Source, Action, Value](
    component: CBSSComponent;
    selector: StoreSelector[Source, Action, Value];
    run: EffectRun[Value];
    immediate = true
): ComponentEffect[Value] =
  if selector.isNil or selector.disposed:
    raise newException(ComponentContextError, "effect selector is not active")
  selector.refresh()
  result = initComponentEffect(component, selector.signal, run)
  if immediate:
    try:
      result.execute(run, selector.value)
    except:
      discard result.dispose()
      raise
