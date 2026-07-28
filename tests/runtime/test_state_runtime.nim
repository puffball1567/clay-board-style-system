import std/unittest

import clay_box_style_system

suite "state runtime":
  type
    ActionKind = enum
      akIncrement
      akAdd

    Action = object
      kind: ActionKind
      amount: int

    State = object
      count: int

  proc update(state: var State; action: Action) =
    case action.kind
    of akIncrement:
      inc state.count
    of akAdd:
      state.count += action.amount

  test "dispatch updates state and marks runtime dirty":
    var runtime = initStateRuntime(State(count: 0), update)
    runtime.markClean()

    runtime.dispatch(Action(kind: akIncrement))

    check runtime.state.count == 1
    check runtime.dirty

  test "dispatcher closure updates the runtime":
    var runtime = initStateRuntime(State(count: 1), update)
    runtime.markClean()
    let dispatch = runtime.dispatcher()

    dispatch(Action(kind: akAdd, amount: 4))

    check runtime.state.count == 5
    check runtime.consumeDirty()
    check not runtime.dirty

  test "silent dispatch updates state without marking dirty":
    var runtime = initStateRuntime(State(count: 1), update)
    runtime.markClean()

    runtime.dispatchSilent(Action(kind: akAdd, amount: 4))

    check runtime.state.count == 5
    check not runtime.dirty
    check not runtime.consumeDirty()

  test "silent dispatcher closure preserves clean state":
    var runtime = initStateRuntime(State(count: 2), update)
    runtime.markClean()
    let dispatch = runtime.silentDispatcher()

    dispatch(Action(kind: akIncrement))

    check runtime.state.count == 3
    check not runtime.dirty

  test "consumeDirty is edge-triggered until another update marks dirty":
    var runtime = initStateRuntime(State(count: 0), update)

    check runtime.consumeDirty()
    check not runtime.consumeDirty()

    runtime.markDirty()
    check runtime.consumeDirty()
    check not runtime.consumeDirty()

    runtime.dispatch(Action(kind: akAdd, amount: 3))
    check runtime.state.count == 3
    check runtime.consumeDirty()
    check not runtime.consumeDirty()
