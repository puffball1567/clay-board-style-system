type
  DispatchProc*[Action] = proc(action: Action) {.closure.}
  UpdateProc*[State, Action] = proc(state: var State; action: Action) {.closure.}

  StateRuntime*[State, Action] = ref object
    state*: State
    update*: UpdateProc[State, Action]
    dirty*: bool

proc initStateRuntime*[State, Action](
    initialState: State;
    update: UpdateProc[State, Action]
): StateRuntime[State, Action] =
  StateRuntime[State, Action](state: initialState, update: update, dirty: true)

proc dispatch*[State, Action](runtime: StateRuntime[State, Action]; action: Action) =
  runtime.update(runtime.state, action)
  runtime.dirty = true

proc dispatchSilent*[State, Action](runtime: StateRuntime[State, Action]; action: Action) =
  runtime.update(runtime.state, action)

proc dispatcher*[State, Action](runtime: StateRuntime[State, Action]): DispatchProc[Action] =
  proc(action: Action) =
    runtime.dispatch(action)

proc silentDispatcher*[State, Action](runtime: StateRuntime[State, Action]): DispatchProc[Action] =
  proc(action: Action) =
    runtime.dispatchSilent(action)

proc markDirty*[State, Action](runtime: StateRuntime[State, Action]) =
  runtime.dirty = true

proc markClean*[State, Action](runtime: StateRuntime[State, Action]) =
  runtime.dirty = false

proc consumeDirty*[State, Action](runtime: StateRuntime[State, Action]): bool =
  result = runtime.dirty
  runtime.dirty = false
