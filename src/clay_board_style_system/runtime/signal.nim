import std/tables

type
  SignalSubscription* = object
    id*: uint64
    owner: pointer

  SignalListener*[Value] = proc(value: Value) {.closure.}

  SignalBinding[Value] = object
    id: uint64
    listener: SignalListener[Value]
    active: bool

  Signal*[Value] = ref object
    bindings: seq[SignalBinding[Value]]
    bindingIndex: Table[uint64, int]
    nextBindingId: uint64
    emitDepth: int
    inactiveBindingCount: int

proc initSignal*[Value](): Signal[Value] =
  Signal[Value](
    bindings: @[],
    bindingIndex: initTable[uint64, int](),
    nextBindingId: 1,
    emitDepth: 0,
    inactiveBindingCount: 0
  )

proc rebuildIndex[Value](signal: Signal[Value]) =
  signal.bindingIndex.clear()
  for index, binding in signal.bindings:
    if binding.active:
      signal.bindingIndex[binding.id] = index

proc compact[Value](signal: Signal[Value]) =
  if signal.inactiveBindingCount == 0:
    return
  var retained = newSeqOfCap[SignalBinding[Value]](
    signal.bindings.len - signal.inactiveBindingCount
  )
  for binding in signal.bindings:
    if binding.active:
      retained.add binding
  signal.bindings = retained
  signal.inactiveBindingCount = 0
  signal.rebuildIndex()

proc subscribe*[Value](
    signal: Signal[Value];
    listener: SignalListener[Value]
): SignalSubscription =
  if signal.isNil:
    raise newException(ValueError, "cannot subscribe to a nil signal")
  if listener.isNil:
    raise newException(ValueError, "signal listener cannot be nil")
  let id = signal.nextBindingId
  inc signal.nextBindingId
  if signal.nextBindingId == 0:
    signal.nextBindingId = 1
  signal.bindings.add SignalBinding[Value](
    id: id,
    listener: listener,
    active: true
  )
  signal.bindingIndex[id] = signal.bindings.high
  SignalSubscription(id: id, owner: cast[pointer](signal))

proc unsubscribe*[Value](
    signal: Signal[Value];
    subscription: SignalSubscription
): bool {.discardable.} =
  if signal.isNil or subscription.id == 0 or
      subscription.owner != cast[pointer](signal) or
      subscription.id notin signal.bindingIndex:
    return false
  let index = signal.bindingIndex[subscription.id]
  signal.bindingIndex.del(subscription.id)
  if signal.emitDepth > 0:
    signal.bindings[index].active = false
    signal.bindings[index].listener = nil
    inc signal.inactiveBindingCount
  else:
    signal.bindings.delete(index)
    signal.rebuildIndex()
  true

proc clear*[Value](signal: Signal[Value]) =
  if signal.isNil:
    return
  signal.bindingIndex.clear()
  if signal.emitDepth > 0:
    for binding in signal.bindings.mitems:
      if binding.active:
        binding.active = false
        binding.listener = nil
        inc signal.inactiveBindingCount
  else:
    signal.bindings.setLen(0)

proc emit*[Value](signal: Signal[Value]; value: Value) =
  if signal.isNil:
    return
  inc signal.emitDepth
  defer:
    dec signal.emitDepth
    if signal.emitDepth == 0:
      signal.compact()

  # A listener added by a callback observes the next emission, not the current
  # one. This keeps one emission deterministic under reentrant mutation.
  let bindingCount = signal.bindings.len
  for index in 0 ..< bindingCount:
    if signal.bindings[index].active:
      signal.bindings[index].listener(value)

proc listenerCount*[Value](signal: Signal[Value]): int =
  if not signal.isNil:
    result = signal.bindingIndex.len
