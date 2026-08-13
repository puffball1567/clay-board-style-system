import std/unittest

import clay_board_style_system

suite "typed library signals":
  test "signals deliver typed values in registration order":
    let signal = initSignal[int]()
    var received: seq[int]
    discard signal.subscribe(proc(value: int) = received.add value)
    discard signal.subscribe(proc(value: int) = received.add value * 10)

    signal.emit(3)

    check received == @[3, 30]
    check signal.listenerCount == 2

  test "subscriptions are owned by one signal and removable once":
    let first = initSignal[string]()
    let second = initSignal[string]()
    var calls = 0
    let subscription = first.subscribe(proc(value: string) = inc calls)

    check not second.unsubscribe(subscription)
    check first.unsubscribe(subscription)
    check not first.unsubscribe(subscription)
    first.emit("ignored")
    check calls == 0

  test "removing and adding listeners during emission is deterministic":
    let signal = initSignal[int]()
    var calls: seq[string]
    var removed: SignalSubscription
    var firstEmission = true
    discard signal.subscribe(proc(value: int) =
      calls.add "first"
      if firstEmission:
        check signal.unsubscribe(removed)
        discard signal.subscribe(proc(value: int) = calls.add "late")
        firstEmission = false
    )
    removed = signal.subscribe(proc(value: int) = calls.add "removed")
    discard signal.subscribe(proc(value: int) = calls.add "last")

    signal.emit(1)
    check calls == @["first", "last"]
    check signal.listenerCount == 3

    calls.setLen(0)
    signal.emit(2)
    check calls == @["first", "last", "late"]

  test "clearing during emission suppresses remaining listeners":
    let signal = initSignal[int]()
    var calls: seq[string]
    discard signal.subscribe(proc(value: int) =
      calls.add "first"
      signal.clear()
    )
    discard signal.subscribe(proc(value: int) = calls.add "second")

    signal.emit(1)

    check calls == @["first"]
    check signal.listenerCount == 0

  test "nil signals are inert and reject subscriptions":
    var signal: Signal[int]
    signal.emit(1)
    signal.clear()
    check signal.listenerCount == 0
    expect ValueError:
      discard signal.subscribe(proc(value: int) = discard)

  test "one failing listener does not leave later listeners stale":
    let signal = initSignal[int]()
    var values: seq[int]
    discard signal.subscribe(proc(value: int) =
      raise newException(ValueError, "listener failed")
    )
    discard signal.subscribe(proc(value: int) = values.add(value))

    expect ValueError:
      signal.emit(4)

    check values == @[4]
