import std/[os, sequtils, unittest]

import clay_board_style_system
import clay_board_style_system/backends/sdl3/[renderer, stream_wake]
import clay_board_style_system/vendor/sdl3

const sdlInitEvents = SDL_InitFlags(0x00004000'u32)

type WorkerArgs = object
  producer: StreamProducer[string]

proc produce(args: WorkerArgs) {.thread.} =
  sleep(10)
  doAssert args.producer.open() == smorAccepted
  doAssert args.producer.pushData("worker payload", 14) == smorAccepted
  doAssert args.producer.finish() == smorAccepted

suite "SDL3 stream wake adapter":
  setup:
    check SDL3.init(sdlInitEvents)

  teardown:
    SDL3.quit()

  test "worker offers wake a blocked SDL event loop":
    let binding = initComponentStreamBinding[string](
      maxQueuedItems = 4,
      maxQueuedWeight = 64,
      dirtyDomains = {ddResource, ddPaint}
    )
    let wake = binding.attachSdl3Wake()
    let producer = binding.producer()
    var worker: Thread[WorkerArgs]
    createThread(worker, produce, WorkerArgs(producer: producer))

    var backend: Sdl3Renderer
    var event: Sdl3Event
    check backend.waitEventTimeout(event, 2_000)
    check wake.matches(event)

    var scheduler = initFrameScheduler()
    let pumped = binding.pumpSdl3Wake(wake, event, scheduler)
    check pumped.processed == 3
    check pumped.changed
    check not pumped.pending
    check scheduler.consumeDirty() == {ddResource, ddPaint}
    let events = binding.drain()
    check events.mapIt(it.kind) == @[sekOpen, sekData, sekEnd]
    check events[1].data == "worker payload"
    check not backend.pollEvent(event)

    joinThread(worker)
    check binding.dispose()

  test "unrelated and stale wake tokens do not pump a binding":
    let first = initComponentStreamBinding[int]()
    let second = initComponentStreamBinding[int]()
    let firstWake = first.attachSdl3Wake()
    let secondWake = second.attachSdl3Wake()
    let producer = first.producer()
    check producer.open() == smorAccepted

    var backend: Sdl3Renderer
    var event: Sdl3Event
    check backend.waitEventTimeout(event, 100)
    check firstWake.matches(event)
    check not secondWake.matches(event)

    var scheduler = initFrameScheduler()
    check not second.pumpSdl3Wake(secondWake, event, scheduler).changed
    check first.pending
    let pumped = first.pumpSdl3Wake(firstWake, event, scheduler)
    check pumped.processed == 1
    check not pumped.pending
    check first.drain().mapIt(it.kind) == @[sekOpen]
    check not first.pending

    check first.dispose()
    check second.dispose()

  test "detaching stops wake events without discarding stream data":
    let binding = initComponentStreamBinding[int]()
    let wake = binding.attachSdl3Wake()
    check wake.valid
    binding.detachSdl3Wake()

    let producer = binding.producer()
    check producer.open() == smorAccepted
    check producer.pushData(42, 1) == smorAccepted

    var backend: Sdl3Renderer
    var event: Sdl3Event
    check not backend.waitEventTimeout(event, 20)
    check binding.pending

    var scheduler = initFrameScheduler()
    check binding.pump(scheduler).processed == 2
    let events = binding.drain()
    check events.mapIt(it.kind) == @[sekOpen, sekData]
    check events[1].data == 42
    check binding.dispose()

  test "disposed and nil bindings reject attachment":
    let missing: ComponentStreamBinding[int] = nil
    expect Sdl3StreamWakeError:
      discard missing.attachSdl3Wake()

    let disposed = initComponentStreamBinding[int]()
    check disposed.dispose()
    expect Sdl3StreamWakeError:
      discard disposed.attachSdl3Wake()
