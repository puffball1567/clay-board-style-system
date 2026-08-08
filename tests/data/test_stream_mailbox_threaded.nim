import std/[atomics, os, sequtils, unittest]

import clay_board_style_system/data/[stream_bridge, stream_mailbox]

type WorkerArguments = object
  source: StreamProducer[string]
  count: int

var
  disposalProduced: Atomic[int]
  disposalStopped: Atomic[bool]
  disposalWakes: Atomic[int]

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
