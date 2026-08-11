import std/[atomics, options, sequtils, unittest]

import clay_board_style_system/data/[stream_bridge, stream_mailbox]

var wakeCount: Atomic[int]

proc countWake(context: pointer) {.cdecl, gcsafe, raises: [].} =
  let counter = cast[ptr Atomic[int]](context)
  discard counter[].fetchAdd(1, moRelaxed)

suite "bounded worker-to-UI stream mailbox":
  setup:
    wakeCount.store(0, moRelaxed)

  test "maps ordered messages into the UI stream state machine":
    let mailbox = initStreamMailbox[string](8, 64)
    let source = mailbox.producer()
    let stream = initStreamBridge[string](8, 64)

    check source.open() == smorAccepted
    check source.pushData("first", 5) == smorAccepted
    check source.reportProgress(1, some(2'u64)) == smorAccepted
    check source.pushData("second", 6) == smorAccepted
    check source.finish() == smorAccepted

    let pumped = mailbox.pumpInto(stream)
    check pumped.processed == 5
    check pumped.rejected == 0
    check pumped.changed
    check not pumped.backpressured
    check not pumped.pending
    check mailbox.queuedItems == 0
    check mailbox.queuedWeight == 0

    let events = stream.drain()
    check events.mapIt(it.kind) ==
      @[sekOpen, sekData, sekData, sekProgress, sekEnd]
    check events[1].data == "first"
    check events[2].data == "second"
    check events[3].completed == 1

  test "enforces source item and weight limits before allocation can grow":
    let mailbox = initStreamMailbox[string](3, 5)
    let source = mailbox.producer()
    check source.open() == smorAccepted
    check source.pushData("aaa", 3) == smorAccepted
    check source.pushData("bb", 2) == smorAccepted
    check source.pushData("queue-full", 0) == smorBackpressure
    check mailbox.queuedItems == 3
    check mailbox.queuedWeight == 5

    let stream = initStreamBridge[string](8, 64)
    check mailbox.pumpInto(stream, 2).pending
    check mailbox.queuedItems == 1
    check mailbox.queuedWeight == 2
    check source.pushData("too-heavy", 6) == smorBackpressure
    check source.pushData("ok", 3) == smorAccepted

  test "retains a moved payload when the UI bridge applies backpressure":
    let mailbox = initStreamMailbox[string](8, 64)
    let source = mailbox.producer()
    let stream = initStreamBridge[string](1, 64)
    check source.open() == smorAccepted
    check source.pushData("first", 5) == smorAccepted
    check source.pushData("preserved", 9) == smorAccepted
    check source.finish() == smorAccepted

    let firstPump = mailbox.pumpInto(stream)
    check firstPump.processed == 2
    check firstPump.backpressured
    check firstPump.pending
    check mailbox.queuedItems == 2
    check mailbox.queuedWeight == 9
    let firstEvents = stream.drain()
    check firstEvents.mapIt(it.kind) == @[sekOpen, sekData]
    check firstEvents[1].data == "first"

    let secondPump = mailbox.pumpInto(stream)
    check secondPump.processed == 2
    check not secondPump.backpressured
    check not secondPump.pending
    let secondEvents = stream.drain()
    check secondEvents.mapIt(it.kind) == @[sekData, sekEnd]
    check secondEvents[0].data == "preserved"

  test "coalesces wake requests until the UI fully drains pending work":
    let mailbox = initStreamMailbox[int](8, 64)
    mailbox.setWakeCallback(countWake, addr wakeCount)
    let source = mailbox.producer()
    let stream = initStreamBridge[int](8, 64)

    check source.open() == smorAccepted
    check source.pushData(1, 1) == smorAccepted
    check source.pushData(2, 1) == smorAccepted
    check wakeCount.load(moRelaxed) == 1
    check mailbox.pumpInto(stream, 1).pending
    check wakeCount.load(moRelaxed) == 1
    check not mailbox.pumpInto(stream).pending

    check source.reportProgress(2) == smorAccepted
    check wakeCount.load(moRelaxed) == 2
    check not mailbox.pumpInto(stream).pending

  test "installing a wake callback after work arrives requests one wake":
    let mailbox = initStreamMailbox[int]()
    let source = mailbox.producer()
    check source.open() == smorAccepted
    check wakeCount.load(moRelaxed) == 0
    mailbox.setWakeCallback(countWake, addr wakeCount)
    check wakeCount.load(moRelaxed) == 1
    mailbox.setWakeCallback(nil)

  test "cancellation removes data already transferred to the UI bridge":
    let mailbox = initStreamMailbox[int]()
    let source = mailbox.producer()
    let stream = initStreamBridge[int]()
    check source.open() == smorAccepted
    check source.pushData(1, 1) == smorAccepted
    check source.pushData(2, 1) == smorAccepted
    check source.cancel() == smorAccepted
    check mailbox.pumpInto(stream).processed == 4
    check stream.drain().mapIt(it.kind) == @[sekCancel]
    check source.pushData(3, 1) == smorInvalidState

  test "close preserves completed data and rejects every later offer":
    let mailbox = initStreamMailbox[string]()
    let source = mailbox.producer()
    let stream = initStreamBridge[string]()
    check source.open() == smorAccepted
    check source.pushData("done", 4) == smorAccepted
    check source.finish() == smorAccepted
    check source.close() == smorAccepted
    check source.state == ssClosed
    check source.close() == smorInvalidState
    check source.pushData("late", 4) == smorInvalidState
    discard mailbox.pumpInto(stream)
    check stream.drain().mapIt(it.kind) ==
      @[sekOpen, sekData, sekEnd, sekClose]

  test "explicit disposal drops queued values and invalidates escaped producers":
    let mailbox = initStreamMailbox[string]()
    let source = mailbox.producer()
    mailbox.setWakeCallback(countWake, addr wakeCount)
    check source.open() == smorAccepted
    check source.pushData("pending", 7) == smorAccepted
    check mailbox.dispose()
    check not mailbox.dispose()
    check mailbox.queuedItems == 0
    check mailbox.queuedWeight == 0
    check source.state == ssClosed
    check source.pushData("late", 4) == smorDisposed

  test "mailbox destruction automatically closes an escaped producer":
    var source: StreamProducer[string]
    block:
      let mailbox = initStreamMailbox[string]()
      source = mailbox.producer()
      check source.open() == smorAccepted
    check source.pushData("late", 4) == smorDisposed

  test "invalid state and value diagnostics are deterministic":
    let mailbox = initStreamMailbox[int]()
    let source = mailbox.producer()
    check source.pushData(1, 1) == smorInvalidState
    check source.finish() == smorInvalidState
    expect ValueError:
      discard source.pushData(1, -1)
    expect ValueError:
      discard source.reportProgress(2, some(1'u64))
    expect ValueError:
      discard source.fail("")
    expect ValueError:
      discard initStreamMailbox[int](0, 1)
    expect ValueError:
      discard initStreamMailbox[int](1, 0)

  test "partial pumping preserves FIFO order across many bounded batches":
    let mailbox = initStreamMailbox[int](128, 128)
    let source = mailbox.producer()
    let stream = initStreamBridge[int](128, 128)
    check source.open() == smorAccepted
    for value in 0 ..< 100:
      check source.pushData(value, 1) == smorAccepted
    check source.finish() == smorAccepted

    while mailbox.hasPending:
      discard mailbox.pumpInto(stream, 7)
    var values: seq[int]
    for event in stream.drain():
      if event.kind == sekData:
        values.add event.data
    check values == toSeq(0 ..< 100)

  test "repeated cancelled and completed lifecycles release managed payloads":
    for iteration in 0 ..< 500:
      let mailbox = initStreamMailbox[string](16, 256)
      let source = mailbox.producer()
      let stream = initStreamBridge[string](16, 256)
      check source.open() == smorAccepted
      for value in 0 ..< 8:
        check source.pushData($iteration & ":" & $value, 8) == smorAccepted
      if iteration mod 2 == 0:
        check source.cancel() == smorAccepted
      else:
        check source.finish() == smorAccepted
      discard mailbox.pumpInto(stream)
      discard stream.drain()
      check mailbox.dispose()
