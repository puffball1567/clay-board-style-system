import std/options

import ../core/dirty_domain
import ./[component, retained_state, signal, ui_root]

type
  ComponentWatch*[Value] = ref object of ComponentOwnedResource
    source: Signal[Value]
    subscription: SignalSubscription

proc releaseComponentWatch[Value](
    resource: ComponentOwnedResource
) {.raises: [].} =
  let watch = ComponentWatch[Value](resource)
  if not watch.source.isNil:
    discard watch.source.unsubscribe(watch.subscription)
  watch.source = nil
  watch.subscription = SignalSubscription()

proc validateWatchTarget(
    component: CBSSComponent;
    target: Option[NodeHandle]
) =
  if target.isNone:
    return
  let handle = target.get
  if not handle.valid:
    raise newException(ComponentContextError, "watch target is not active")
  if handle.root != component.node.root:
    raise newException(
      ComponentContextError,
      "watch target belongs to another UiRoot"
    )

proc watch*[Value](
    component: CBSSComponent;
    source: Signal[Value];
    listener: SignalListener[Value];
    dirtyDomains: set[DirtyDomain] = {};
    target = none(NodeHandle)
): ComponentWatch[Value] =
  if component.isNil:
    raise newException(ComponentContextError, "component cannot be nil")
  if source.isNil:
    raise newException(ComponentContextError, "watch source cannot be nil")
  if listener.isNil:
    raise newException(ComponentContextError, "watch listener cannot be nil")
  component.validateWatchTarget(target)

  let watchedComponent = component
  let watchedTarget = target
  let watchedDomains = dirtyDomains
  let subscription = source.subscribe(proc(value: Value) =
    listener(value)
    if watchedDomains != {}:
      watchedComponent.invalidate(watchedDomains, watchedTarget)
  )
  result = ComponentWatch[Value](
    source: source,
    subscription: subscription
  )
  result.setReleaseCallback(releaseComponentWatch[Value])
  try:
    discard component.own(result)
  except:
    discard source.unsubscribe(subscription)
    result.source = nil
    result.subscription = SignalSubscription()
    raise

proc watch*[Value](
    component: CBSSComponent;
    state: State[Value];
    listener: SignalListener[Value];
    dirtyDomains: set[DirtyDomain] = {};
    target = none(NodeHandle);
    immediate = true
): ComponentWatch[Value] =
  if state.isNil:
    raise newException(ComponentContextError, "watch state cannot be nil")
  if component.isNil:
    raise newException(ComponentContextError, "component cannot be nil")
  if listener.isNil:
    raise newException(ComponentContextError, "watch listener cannot be nil")
  component.validateWatchTarget(target)
  if immediate:
    listener(state.value)
  component.watch(
    state.signal,
    listener,
    dirtyDomains = dirtyDomains,
    target = target
  )
