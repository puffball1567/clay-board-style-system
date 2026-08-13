import ./signal

type
  StateEqualProc*[Value] = proc(left, right: Value): bool {.closure.}

  State*[Value] = ref object
    currentValue: Value
    publishedValue: Value
    equal: StateEqualProc[Value]
    changed: Signal[Value]
    publicationQueued: bool

  PendingStatePublication = object
    publish: proc() {.closure.}
    cancel: proc() {.closure.}

var
  stateBatchDepth {.threadvar.}: int
  flushingStatePublications {.threadvar.}: bool
  pendingStatePublications {.threadvar.}: seq[PendingStatePublication]

proc flushStatePublications()

proc defaultStateEqual[Value](left, right: Value): bool =
  left == right

proc initState*[Value](
    initialValue: Value;
    equal: StateEqualProc[Value] = nil
): State[Value] =
  result = State[Value](
    currentValue: initialValue,
    publishedValue: initialValue,
    equal: equal,
    changed: initSignal[Value]()
  )
  if result.equal.isNil:
    result.equal = defaultStateEqual[Value]

proc value*[Value](state: State[Value]): lent Value =
  if state.isNil:
    raise newException(ValueError, "state cannot be nil")
  state.currentValue

proc signal*[Value](state: State[Value]): Signal[Value] =
  if state.isNil:
    raise newException(ValueError, "state cannot be nil")
  state.changed

proc publishPending[Value](state: State[Value]) =
  state.publicationQueued = false
  if state.equal(state.publishedValue, state.currentValue):
    return
  state.publishedValue = state.currentValue
  state.changed.emit(state.currentValue)

proc cancelPending[Value](state: State[Value]) =
  state.publicationQueued = false

proc queuePublication[Value](state: State[Value]) =
  if state.publicationQueued:
    return
  state.publicationQueued = true
  pendingStatePublications.add PendingStatePublication(
    publish: proc() = state.publishPending(),
    cancel: proc() = state.cancelPending()
  )
  if stateBatchDepth == 0 and not flushingStatePublications:
    flushStatePublications()

proc flushStatePublications() =
  if flushingStatePublications or stateBatchDepth > 0:
    return
  flushingStatePublications = true
  var index = 0
  var firstFailure: ref CatchableError
  try:
    while index < pendingStatePublications.len:
      let publication = pendingStatePublications[index]
      inc index
      try:
        publication.publish()
      except CatchableError as error:
        if firstFailure.isNil:
          firstFailure = error
  finally:
    for remaining in index ..< pendingStatePublications.len:
      pendingStatePublications[remaining].cancel()
    pendingStatePublications.setLen(0)
    flushingStatePublications = false
  if not firstFailure.isNil:
    raise firstFailure

proc set*[Value](state: State[Value]; nextValue: Value): bool {.discardable.} =
  if state.isNil:
    raise newException(ValueError, "state cannot be nil")
  if state.equal(state.currentValue, nextValue):
    return false
  state.currentValue = nextValue
  state.queuePublication()
  true

proc update*[Value](
    state: State[Value];
    mutation: proc(value: var Value) {.closure.}
): bool {.discardable.} =
  if state.isNil:
    raise newException(ValueError, "state cannot be nil")
  if mutation.isNil:
    raise newException(ValueError, "state mutation cannot be nil")
  var nextValue = state.currentValue
  mutation(nextValue)
  state.set(nextValue)

template batch*(body: untyped) =
  block:
    inc stateBatchDepth
    try:
      body
    finally:
      dec stateBatchDepth
      if stateBatchDepth == 0:
        flushStatePublications()

proc subscriberCount*[Value](state: State[Value]): int =
  if not state.isNil:
    result = state.changed.listenerCount
