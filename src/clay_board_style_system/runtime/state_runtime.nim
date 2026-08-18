import ./signal

type
  DispatchProc*[Action] = proc(action: Action) {.closure.}
  UpdateProc*[State, Action] = proc(state: var State; action: Action) {.closure.}

  StateRuntime*[State, Action] = ref object
    state*: State
    update*: UpdateProc[State, Action]
    dirty*: bool
    revisionValue: uint64
    committed: Signal[uint64]
    pendingActions: seq[Action]
    pendingCommit: bool
    processing: bool
    transactionDepth: int

proc drain[State, Action](runtime: StateRuntime[State, Action])

proc requireRuntime[State, Action](runtime: StateRuntime[State, Action]) =
  if runtime.isNil:
    raise newException(ValueError, "state runtime cannot be nil")
  if runtime.update.isNil:
    raise newException(ValueError, "state runtime update cannot be nil")

proc initStateRuntime*[State, Action](
    initialState: State;
    update: UpdateProc[State, Action]
): StateRuntime[State, Action] =
  if update.isNil:
    raise newException(ValueError, "state runtime update cannot be nil")
  StateRuntime[State, Action](
    state: initialState,
    update: update,
    dirty: true,
    committed: initSignal[uint64]()
  )

proc createStore*[State, Action](
    initialState: State;
    update: UpdateProc[State, Action]
): StateRuntime[State, Action] =
  initStateRuntime(initialState, update)

proc revision*[State, Action](runtime: StateRuntime[State, Action]): uint64 =
  runtime.requireRuntime()
  runtime.revisionValue

proc commitSignal*[State, Action](
    runtime: StateRuntime[State, Action]
): Signal[uint64] =
  runtime.requireRuntime()
  runtime.committed

proc publishCommit[State, Action](runtime: StateRuntime[State, Action]) =
  if not runtime.pendingCommit:
    return
  runtime.pendingCommit = false
  inc runtime.revisionValue
  runtime.committed.emit(runtime.revisionValue)

proc drain[State, Action](runtime: StateRuntime[State, Action]) =
  if runtime.processing:
    return
  runtime.processing = true
  var index = 0
  var firstFailure: ref CatchableError
  try:
    while index < runtime.pendingActions.len:
      let action = runtime.pendingActions[index]
      inc index
      try:
        runtime.update(runtime.state, action)
        runtime.dirty = true
        runtime.pendingCommit = true
        if runtime.transactionDepth == 0:
          runtime.publishCommit()
      except CatchableError as error:
        if firstFailure.isNil:
          firstFailure = error
    if runtime.transactionDepth == 0 and runtime.pendingCommit:
      try:
        runtime.publishCommit()
      except CatchableError as error:
        if firstFailure.isNil:
          firstFailure = error
  finally:
    runtime.pendingActions.setLen(0)
    runtime.processing = false
  if not firstFailure.isNil:
    raise firstFailure

proc dispatch*[State, Action](runtime: StateRuntime[State, Action]; action: Action) =
  runtime.requireRuntime()
  runtime.pendingActions.add action
  runtime.drain()

proc dispatchSilent*[State, Action](runtime: StateRuntime[State, Action]; action: Action) =
  runtime.requireRuntime()
  runtime.update(runtime.state, action)

template transaction*[State, Action](
    runtime: StateRuntime[State, Action];
    body: untyped
) =
  block:
    runtime.requireRuntime()
    inc runtime.transactionDepth
    try:
      body
    finally:
      dec runtime.transactionDepth
      if runtime.transactionDepth == 0:
        runtime.drain()

proc dispatcher*[State, Action](runtime: StateRuntime[State, Action]): DispatchProc[Action] =
  proc(action: Action) =
    runtime.dispatch(action)

proc silentDispatcher*[State, Action](runtime: StateRuntime[State, Action]): DispatchProc[Action] =
  proc(action: Action) =
    runtime.dispatchSilent(action)

proc markDirty*[State, Action](runtime: StateRuntime[State, Action]) =
  runtime.requireRuntime()
  runtime.dirty = true

proc markClean*[State, Action](runtime: StateRuntime[State, Action]) =
  runtime.requireRuntime()
  runtime.dirty = false

proc consumeDirty*[State, Action](runtime: StateRuntime[State, Action]): bool =
  runtime.requireRuntime()
  result = runtime.dirty
  runtime.dirty = false
