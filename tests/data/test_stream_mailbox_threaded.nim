import std/[atomics, os, sequtils, unittest]

import clay_board_style_system/data/[stream_bridge, stream_mailbox]

type WorkerArguments = object
  source: StreamProducer[string]
  count: int

type
  ConcurrentMessage = object
    producer: int
    index: int

  ConcurrentArguments = object
    source: StreamProducer[ConcurrentMessage]
    producer: int
    count: int

  TerminalOperation = enum
    toFinish,
    toFail,
    toCancel

  TerminalArguments = object
    source: StreamProducer[int]
    operation: TerminalOperation

var
  disposalProduced: Atomic[int]
  disposalStopped: Atomic[bool]
  disposalWakes: Atomic[int]
  concurrentWorkers: Atomic[int]
  terminalStart: Atomic[bool]
  terminalAccepted: Atomic[int]
  terminalRejected: Atomic[int]
  blockingWakeEntered: Atomic[bool]
  blockingWakeRelease: Atomic[bool]
  blockingWakeReturned: Atomic[bool]
  replacementWakes: Atomic[int]

proc countDisposalWake(context: pointer) {.cdecl, gcsafe, raises: [].} =
  let counter = cast[ptr Atomic[int]](context)
  discard counter[].fetchAdd(1, moRelaxed)

proc produce(arguments: WorkerArguments) {.thread.} =
  for index in 0 ..< arguments.count:
    let value = "worker:" & $index
    while arguments.source.pushData(value, value.len) == smorBackpressure:
      sleep(1)
  while arguments.source.finish() == smorBackpressure:
    sleep(1)

proc produceUntilDisposed(source: StreamProducer[string]) {.thread.} =
  var index = 0
  while true:
    let value = "dispose-race:" & $index
    case source.pushData(value, value.len)
    of smorAccepted:
      inc index
      disposalProduced.store(index, moRelaxed)
    of smorBackpressure:
      sleep(1)
    of smorInvalidState, smorDisposed:
      disposalStopped.store(true, moRelease)
      break

proc produceConcurrent(arguments: ConcurrentArguments) {.thread.} =
  for index in 0 ..< arguments.count:
    let message = ConcurrentMessage(
      producer: arguments.producer,
      index: index
    )
    while arguments.source.pushData(message, 1) == smorBackpressure:
      sleep(1)
  discard concurrentWorkers.fetchSub(1, moRelease)

proc raceTerminal(arguments: TerminalArguments) {.thread.} =
  while not terminalStart.load(moAcquire):
    sleep(1)
  let offered =
    case arguments.operation
    of toFinish:
      arguments.source.finish()
    of toFail:
      arguments.source.fail("terminal race")
    of toCancel:
      arguments.source.cancel()
  case offered
  of smorAccepted:
    discard terminalAccepted.fetchAdd(1, moRelaxed)
  of smorInvalidState:
    discard terminalRejected.fetchAdd(1, moRelaxed)
  of smorBackpressure, smorDisposed:
    doAssert false, "unexpected terminal race result: " & $offered

proc blockingWake(context: pointer) {.cdecl, gcsafe, raises: [].} =
  discard context
  blockingWakeEntered.store(true, moRelease)
  while not blockingWakeRelease.load(moAcquire):
    sleep(1)
  blockingWakeReturned.store(true, moRelease)

proc releaseBlockingWake(_: bool) {.thread.} =
  sleep(20)
  blockingWakeRelease.store(true, moRelease)

proc openWithBlockingWake(source: StreamProducer[int]) {.thread.} =
  doAssert source.open() == smorAccepted

suite "real worker-to-UI stream transfer":
  test "moves managed strings across a bounded ARC-safe mailbox":
    const messageCount = 1_000
    let mailbox = initStreamMailbox[string](8, 128)
    let source = mailbox.producer()
    let stream = initStreamBridge[string](16, 256)
    check source.open() == smorAccepted

    var worker: Thread[WorkerArguments]
    createThread(worker, produce, WorkerArguments(
      source: source,
      count: messageCount
    ))

    var received: seq[string]
    var ended = false
    while not ended:
      discard mailbox.pumpInto(stream, 16)
      for event in stream.drain(16):
        case event.kind
        of sekData:
          received.add event.data
        of sekEnd:
          ended = true
        else:
          discard
      if not ended:
        sleep(1)
    joinThread(worker)

    check received.len == messageCount
    check received == (0 ..< messageCount).toSeq.mapIt("worker:" & $it)
    check not mailbox.hasPending
    check mailbox.queuedWeight == 0

  test "disposal races reject the worker and wait for wake completion":
    disposalProduced.store(0, moRelaxed)
    disposalStopped.store(false, moRelaxed)
    disposalWakes.store(0, moRelaxed)

    let mailbox = initStreamMailbox[string](8, 256)
    mailbox.setWakeCallback(countDisposalWake, addr disposalWakes)
    let source = mailbox.producer()
    check source.open() == smorAccepted

    var worker: Thread[StreamProducer[string]]
    createThread(worker, produceUntilDisposed, source)
    var attempts = 0
    while disposalProduced.load(moAcquire) == 0 and attempts < 1_000:
      sleep(1)
      inc attempts
    check disposalProduced.load(moAcquire) > 0

    check mailbox.dispose()
    joinThread(worker)
    check disposalStopped.load(moAcquire)
    check disposalWakes.load(moAcquire) == 1
    check mailbox.queuedItems == 0
    check mailbox.queuedWeight == 0
    check source.pushData("late", 4) == smorDisposed

  test "many producers preserve every message and per-producer order":
    const
      workerCount = 4
      messagesPerWorker = 250
    concurrentWorkers.store(workerCount, moRelaxed)
    let mailbox = initStreamMailbox[ConcurrentMessage](16, 16)
    let source = mailbox.producer()
    let stream = initStreamBridge[ConcurrentMessage](32, 32)
    check source.open() == smorAccepted

    var workers: array[workerCount, Thread[ConcurrentArguments]]
    for producer in 0 ..< workerCount:
      createThread(workers[producer], produceConcurrent, ConcurrentArguments(
        source: source,
        producer: producer,
        count: messagesPerWorker
      ))

    var received = newSeq[seq[int]](workerCount)
    while concurrentWorkers.load(moAcquire) > 0 or mailbox.hasPending:
      discard mailbox.pumpInto(stream, 32)
      for event in stream.drain(32):
        if event.kind == sekData:
          received[event.data.producer].add event.data.index
      if concurrentWorkers.load(moAcquire) > 0:
        sleep(1)
    for worker in workers.mitems:
      joinThread(worker)

    check source.finish() == smorAccepted
    discard mailbox.pumpInto(stream)
    discard stream.drain()
    for producer in 0 ..< workerCount:
      check received[producer] == toSeq(0 ..< messagesPerWorker)
    check mailbox.queuedItems == 0
    check mailbox.queuedWeight == 0

  test "competing terminal offers choose exactly one outcome":
    const contenderCount = 12
    terminalStart.store(false, moRelaxed)
    terminalAccepted.store(0, moRelaxed)
    terminalRejected.store(0, moRelaxed)
    let mailbox = initStreamMailbox[int](32, 32)
    let source = mailbox.producer()
    check source.open() == smorAccepted

    var contenders: array[contenderCount, Thread[TerminalArguments]]
    for index in 0 ..< contenderCount:
      createThread(contenders[index], raceTerminal, TerminalArguments(
        source: source,
        operation: TerminalOperation(index mod 3)
      ))
    terminalStart.store(true, moRelease)
    for contender in contenders.mitems:
      joinThread(contender)

    check terminalAccepted.load(moAcquire) == 1
    check terminalRejected.load(moAcquire) == contenderCount - 1
    check source.state in {ssEnded, ssFailed, ssCancelled}
    check source.close() == smorAccepted
    check source.state == ssClosed

  test "callback replacement waits until the old raw context is idle":
    blockingWakeEntered.store(false, moRelaxed)
    blockingWakeRelease.store(false, moRelaxed)
    blockingWakeReturned.store(false, moRelaxed)
    replacementWakes.store(0, moRelaxed)
    let mailbox = initStreamMailbox[int](8, 8)
    mailbox.setWakeCallback(blockingWake)
    let source = mailbox.producer()

    var opener: Thread[StreamProducer[int]]
    createThread(opener, openWithBlockingWake, source)
    var attempts = 0
    while not blockingWakeEntered.load(moAcquire) and attempts < 1_000:
      sleep(1)
      inc attempts
    check blockingWakeEntered.load(moAcquire)

    var releaser: Thread[bool]
    createThread(releaser, releaseBlockingWake, true)
    mailbox.setWakeCallback(countDisposalWake, addr replacementWakes)
    check blockingWakeReturned.load(moAcquire)
    check replacementWakes.load(moAcquire) == 1
    joinThread(opener)
    joinThread(releaser)

    let stream = initStreamBridge[int](8, 8)
    check not mailbox.pumpInto(stream).pending
    discard stream.drain()
    check source.pushData(1, 1) == smorAccepted
    check replacementWakes.load(moAcquire) == 2
    check mailbox.dispose()
