import std/[options, sequtils, unittest]

import clay_board_style_system/data/stream_bridge

suite "bounded UI stream bridge":
  test "delivers open data latest progress and end in deterministic order":
    let stream = initStreamBridge[string](4, 32)
    check stream.state == ssIdle
    check stream.open()
    check stream.pushData("first", 5) == sorAccepted
    check stream.reportProgress(1, some(3'u64))
    check stream.reportProgress(2, some(3'u64))
    check stream.pushData("second", 6) == sorAccepted
    check stream.finish()
    check stream.state == ssEnded
    check stream.terminalKind == stkEnd

    let events = stream.drain()
    check events.len == 5
    check events[0].kind == sekOpen
    check events[1].kind == sekData
    check events[1].data == "first"
    check events[2].kind == sekData
    check events[2].data == "second"
    check events[3].kind == sekProgress
    check events[3].completed == 2
    check events[3].total == some(3'u64)
    check events[4].kind == sekEnd
    check not stream.hasPending
    check stream.drain().len == 0
    check stream.pushData("late", 4) == sorNotOpen
    check not stream.finish()

  test "enforces item and weight backpressure without consuming rejected data":
    let stream = initStreamBridge[string](2, 6)
    check stream.open()
    check stream.pushData("aaa", 3) == sorAccepted
    check stream.pushData("bbb", 3) == sorAccepted
    check stream.queuedItems == 2
    check stream.queuedWeight == 6
    check stream.pushData("rejected", 0) == sorBackpressure
    check stream.canPushData(0) == sorBackpressure

    let first = stream.drain(2)
    check first.len == 2
    check first[0].kind == sekOpen
    check first[1].data == "aaa"
    check stream.queuedItems == 1
    check stream.queuedWeight == 3
    check stream.pushData("too-heavy", 7) == sorBackpressure
    check stream.canPushData(7) == sorBackpressure
    check stream.pushData("accepted", 3) == sorAccepted

  test "cancellation drops queued work and rejects late producer messages":
    let stream = initStreamBridge[int](8, 64)
    check stream.open()
    check stream.pushData(1, 8) == sorAccepted
    check stream.pushData(2, 8) == sorAccepted
    check stream.reportProgress(2)
    check stream.cancel()
    check stream.state == ssCancelled
    check stream.terminalKind == stkCancel
    check stream.queuedItems == 0
    check stream.queuedWeight == 0
    check stream.pushData(3, 8) == sorNotOpen
    check not stream.reportProgress(3)
    check not stream.cancel()
    let events = stream.drain()
    check events.len == 1
    check events[0].kind == sekCancel

  test "close is idempotent and follows an active cancellation":
    let stream = initStreamBridge[int]()
    check stream.open()
    check stream.pushData(1, 1) == sorAccepted
    check stream.close()
    check stream.state == ssClosed
    check not stream.close()
    let events = stream.drain()
    check events.len == 2
    check events[0].kind == sekCancel
    check events[1].kind == sekClose

  test "close after failure preserves the error before close":
    let stream = initStreamBridge[int]()
    check stream.open()
    check stream.pushData(7, 1) == sorAccepted
    check stream.fail("decoder failed")
    check stream.close()
    let events = stream.drain()
    check events.len == 4
    check events[0].kind == sekOpen
    check events[1].kind == sekData
    check events[2].kind == sekError
    check events[2].message == "decoder failed"
    check events[3].kind == sekClose

  test "partial drains preserve accounting and event order":
    let stream = initStreamBridge[int](128, 128)
    check stream.open()
    for value in 0 ..< 100:
      check stream.pushData(value, 1) == sorAccepted
    check stream.finish()
    var received: seq[int]
    while stream.hasPending:
      for event in stream.drain(7):
        if event.kind == sekData:
          received.add event.data
    check received.len == 100
    for index, value in received:
      check value == index
    check stream.queuedItems == 0
    check stream.queuedWeight == 0

  test "invalid limits weights progress and errors fail immediately":
    expect ValueError:
      discard initStreamBridge[int](0, 1)
    expect ValueError:
      discard initStreamBridge[int](1, 0)
    let stream = initStreamBridge[int]()
    check stream.open()
    expect ValueError:
      discard stream.pushData(1, -1)
    expect ValueError:
      discard stream.reportProgress(2, some(1'u64))
    expect ValueError:
      discard stream.fail("")

  test "revision changes only when observable stream state changes":
    let stream = initStreamBridge[int]()
    check stream.revision == 0
    check stream.open()
    let openedRevision = stream.revision
    check openedRevision > 0
    check not stream.open()
    check stream.revision == openedRevision
    check stream.pushData(1, 1) == sorAccepted
    check stream.revision > openedRevision
    let dataRevision = stream.revision
    check stream.pushData(2, high(int64)) == sorBackpressure
    check stream.revision == dataRevision
    check stream.reportProgress(1, some(2'u64))
    let progressRevision = stream.revision
    check stream.reportProgress(1, some(2'u64))
    check stream.revision == progressRevision

  test "idle close and nil handles are safe and deterministic":
    let idle = initStreamBridge[int]()
    check idle.close()
    check idle.state == ssClosed
    check idle.drain().mapIt(it.kind) == @[sekClose]

    let missing: StreamBridge[int] = nil
    check missing.state == ssClosed
    check missing.terminalKind == stkNone
    check missing.revision == 0
    check missing.queuedItems == 0
    check missing.queuedWeight == 0
    check not missing.hasPending
    check not missing.open()
    check missing.pushData(1, 0) == sorNotOpen
    check missing.drain().len == 0

  test "zero-weight items remain bounded by item count":
    let stream = initStreamBridge[int](2, 1)
    check stream.open()
    check stream.pushData(1, 0) == sorAccepted
    check stream.pushData(2, 0) == sorAccepted
    check stream.pushData(3, 0) == sorBackpressure
    check stream.queuedItems == 2
    check stream.queuedWeight == 0

  test "repeated lifecycles release all pending values cleanly":
    for iteration in 0 ..< 1_000:
      let stream = initStreamBridge[string](8, 256)
      check stream.open()
      for value in 0 ..< 8:
        check stream.pushData($iteration & ":" & $value, 16) == sorAccepted
      if iteration mod 2 == 0:
        check stream.cancel()
      else:
        check stream.finish()
      check stream.close()
      discard stream.drain()
      check not stream.hasPending
