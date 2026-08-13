import std/unittest

import clay_board_style_system

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

  test "dispatch publishes one committed revision":
    let runtime = createStore(State(count: 0), update)
    var revisions: seq[uint64]
    discard runtime.commitSignal.subscribe(proc(revision: uint64) =
      revisions.add(revision)
    )

    runtime.dispatch(Action(kind: akIncrement))
    runtime.dispatch(Action(kind: akAdd, amount: 2))

    check runtime.state.count == 3
    check runtime.revision == 2
    check revisions == @[1'u64, 2'u64]

  test "transaction publishes several actions as one commit":
    let runtime = createStore(State(count: 0), update)
    var committedCounts: seq[int]
    discard runtime.commitSignal.subscribe(proc(revision: uint64) =
      discard revision
      committedCounts.add(runtime.state.count)
    )

    runtime.transaction:
      runtime.dispatch(Action(kind: akIncrement))
      runtime.dispatch(Action(kind: akAdd, amount: 4))
      check committedCounts.len == 0

    check runtime.state.count == 5
    check runtime.revision == 1
    check committedCounts == @[5]

  test "nested transactions share the outer commit boundary":
    let runtime = createStore(State(count: 0), update)
    var commits = 0
    discard runtime.commitSignal.subscribe(proc(revision: uint64) = inc commits)

    runtime.transaction:
      runtime.dispatch(Action(kind: akIncrement))
      runtime.transaction:
        runtime.dispatch(Action(kind: akAdd, amount: 2))
      check commits == 0

    check runtime.state.count == 3
    check commits == 1

  test "dispatch from a commit listener is queued for a later commit":
    let runtime = createStore(State(count: 0), update)
    var committedCounts: seq[int]
    discard runtime.commitSignal.subscribe(proc(revision: uint64) =
      committedCounts.add(runtime.state.count)
      if revision == 1:
        runtime.dispatch(Action(kind: akAdd, amount: 2))
    )

    runtime.dispatch(Action(kind: akIncrement))

    check runtime.state.count == 3
    check runtime.revision == 2
    check committedCounts == @[1, 3]

  test "silent dispatch does not publish a commit":
    let runtime = createStore(State(count: 0), update)
    var commits = 0
    discard runtime.commitSignal.subscribe(proc(revision: uint64) = inc commits)

    runtime.dispatchSilent(Action(kind: akIncrement))

    check runtime.state.count == 1
    check runtime.revision == 0
    check commits == 0

  test "transaction commits completed actions when its body raises":
    let runtime = createStore(State(count: 0), update)
    var committedCounts: seq[int]
    discard runtime.commitSignal.subscribe(proc(revision: uint64) =
      committedCounts.add(runtime.state.count)
    )

    expect ValueError:
      runtime.transaction:
        runtime.dispatch(Action(kind: akIncrement))
        raise newException(ValueError, "transaction failed")

    check runtime.state.count == 1
    check committedCounts == @[1]

  test "a failed reducer does not wedge later dispatch":
    proc fallibleUpdate(state: var State; action: Action) =
      if action.amount < 0:
        raise newException(ValueError, "invalid amount")
      update(state, action)

    let runtime = createStore(State(count: 0), fallibleUpdate)
    expect ValueError:
      runtime.dispatch(Action(kind: akAdd, amount: -1))

    runtime.dispatch(Action(kind: akAdd, amount: 3))
    check runtime.state.count == 3
    check runtime.revision == 1

  test "nil runtime and nil update fail explicitly":
    var runtime: StateRuntime[State, Action]
    expect ValueError:
      runtime.dispatch(Action(kind: akIncrement))
    expect ValueError:
      discard initStateRuntime[State, Action](State(), nil)
