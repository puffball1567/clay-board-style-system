import std/unittest

import clay_board_style_system
import clay_board_style_system/frontend_runtime

type
  IntCommand = Command[int, string, string]
  IntSink = CommandSink[string, string]

  CommandComponent = ref object of CBSSComponent
    sinks: ref seq[IntSink]
    cancellations: ref int
    commandValue: IntCommand

proc finishOnWorker(sink: CommandSink[int, string]) {.thread.} =
  var value = 42
  doAssert succeed[int, string](sink, move(value)) == smorAccepted

proc deferredCommand(
    policy: CommandPolicy;
    sinks: ref seq[IntSink];
    cancellations: ref int
): IntCommand =
  initCommand[int, string, string](
    (proc(input: int; sink: IntSink): CommandCancel =
      discard input
      sinks[].add sink
      return proc() = inc cancellations[]),
    policy = policy
  )

proc render(self: CommandComponent) =
  self.commandValue = command[int, string, string](
    self,
    proc(input: int; sink: IntSink): CommandCancel =
      discard input
      self.sinks[].add sink
      return proc() = inc self.cancellations[]
  )
  ui.box(self):
    ui.text("command")

suite "typed commands":
  test "latest-only cancels the previous run and ignores its late result":
    let sinks = new seq[IntSink]
    let cancellations = new int
    let command = deferredCommand(cpLatestOnly, sinks, cancellations)
    var successes: seq[string]
    command.onSuccess = proc(value: string) = successes.add value

    let first = command.run(1)
    let second = command.run(2)
    check first.status == csCancelled
    check second.status == csRunning
    check cancellations[] == 1
    check sinks[].len == 2
    check sinks[][0].succeed("stale") == smorAccepted
    check sinks[][1].succeed("current") == smorAccepted
    check command.pump() == 2
    check successes == @["current"]
    check second.status == csSucceeded
    check command.activeCount == 0

  test "ordered commands start exactly one executor at a time":
    let sinks = new seq[IntSink]
    let cancellations = new int
    let command = deferredCommand(cpOrdered, sinks, cancellations)
    var successes: seq[string]
    var failures: seq[string]
    command.onSuccess = proc(value: string) = successes.add value
    command.onFailure = proc(value: string) = failures.add value

    let first = command.run(1)
    let second = command.run(2)
    let third = command.run(3)
    check first.status == csRunning
    check second.status == csQueued
    check third.status == csQueued
    check sinks[].len == 1
    check command.queuedCount == 2

    check sinks[][0].succeed("one") == smorAccepted
    check command.pump() == 1
    check second.status == csRunning
    check sinks[].len == 2
    check sinks[][1].fail("two failed") == smorAccepted
    check command.pump() == 1
    check second.status == csFailed
    check failures == @["two failed"]
    check third.status == csRunning
    check sinks[].len == 3
    check sinks[][2].succeed("three") == smorAccepted
    check command.pump() == 1
    check successes == @["one", "three"]
    check third.status == csSucceeded
    check not command.pending

  test "concurrent commands complete independently and out of order":
    let sinks = new seq[IntSink]
    let cancellations = new int
    let command = deferredCommand(cpConcurrent, sinks, cancellations)
    var successes: seq[string]
    command.onSuccess = proc(value: string) = successes.add value

    let first = command.run(1)
    let second = command.run(2)
    check command.activeCount == 2
    check sinks[][1].succeed("second") == smorAccepted
    check sinks[][0].succeed("first") == smorAccepted
    check command.pump() == 2
    check successes == @["second", "first"]
    check first.status == csSucceeded
    check second.status == csSucceeded

  test "explicit cancellation handles active and queued runs":
    let sinks = new seq[IntSink]
    let cancellations = new int
    let command = deferredCommand(cpOrdered, sinks, cancellations)
    var cancelled: seq[uint64]
    command.onCancelled = proc(ticket: CommandTicket) {.raises: [].} =
      cancelled.add ticket.id

    let first = command.run(1)
    let second = command.run(2)
    check command.cancel(second)
    check second.status == csCancelled
    check command.cancel(first)
    check first.status == csCancelled
    check cancellations[] == 1
    check cancelled == @[second.id, first.id]
    check not command.cancel(first)

  test "executor exceptions do not wedge ordered dispatch":
    var attempts = 0
    let command = initCommand[int, int, string](
      (proc(input: int; sink: CommandSink[int, string]): CommandCancel =
        discard sink
        inc attempts
        if input == 1:
          raise newException(ValueError, "executor failed")
        nil),
      policy = cpOrdered
    )
    expect ValueError:
      discard command.run(1)
    let next = command.run(2)
    check next.status == csRunning
    check attempts == 2

  test "callback failures do not prevent later completions from settling":
    let sinks = new seq[IntSink]
    let cancellations = new int
    let command = deferredCommand(cpConcurrent, sinks, cancellations)
    var calls = 0
    command.onSuccess = proc(value: string) =
      inc calls
      if value == "first":
        raise newException(ValueError, "callback failed")
    let first = command.run(1)
    let second = command.run(2)
    check sinks[][0].succeed("first") == smorAccepted
    check sinks[][1].succeed("second") == smorAccepted
    expect ValueError:
      discard command.pump()
    check calls == 2
    check first.status == csSucceeded
    check second.status == csSucceeded
    check command.activeCount == 0

  test "component unmount cancels work and rejects late completions":
    let root = initUiRoot()
    let sinks = new seq[IntSink]
    let cancellations = new int
    let component = root.mount(CommandComponent(
      sinks: sinks,
      cancellations: cancellations
    ))
    let ticket = component.commandValue.run(1)
    var interaction = initInteractionState()
    check root.disposeSubtree(component.node, interaction)
    check ticket.status == csCancelled
    check cancellations[] == 1
    check sinks[][0].succeed("late") == smorDisposed
    check component.commandValue.pump() == 0

  test "invalid construction and foreign tickets are rejected":
    expect ValueError:
      discard initCommand[int, int, string](nil)
    expect ValueError:
      discard initCommand[int, int, string](
        proc(input: int; sink: CommandSink[int, string]): CommandCancel = nil,
        maxPendingCompletions = 0
      )
    let firstSinks = new seq[IntSink]
    let secondSinks = new seq[IntSink]
    let cancellations = new int
    let first = deferredCommand(cpConcurrent, firstSinks, cancellations)
    let second = deferredCommand(cpConcurrent, secondSinks, cancellations)
    let ticket = first.run(1)
    check not second.cancel(ticket)
    check ticket.status == csRunning

  test "worker completion is applied only when the UI pumps":
    var worker: Thread[CommandSink[int, string]]
    var sinkValue: CommandSink[int, string]
    let command = initCommand[int, int, string](
      proc(input: int; sink: CommandSink[int, string]): CommandCancel =
        discard input
        sinkValue = sink
        nil
    )
    var resultValue = 0
    command.onSuccess = proc(value: int) = resultValue = value
    let ticket = command.run(1)
    createThread(worker, finishOnWorker, sinkValue)
    joinThread(worker)
    check ticket.status == csRunning
    check resultValue == 0
    check command.pump() == 1
    check ticket.status == csSucceeded
    check resultValue == 42

  test "bounded pumping never drops an extra completion":
    let sinks = new seq[IntSink]
    let cancellations = new int
    let command = deferredCommand(cpConcurrent, sinks, cancellations)
    var successes: seq[string]
    command.onSuccess = proc(value: string) = successes.add value
    discard command.run(1)
    discard command.run(2)
    check sinks[][0].succeed("one") == smorAccepted
    check sinks[][1].succeed("two") == smorAccepted
    check command.pump(1) == 1
    check successes == @["one"]
    check command.pump(1) == 1
    check successes == @["one", "two"]

  test "completion mailbox applies an explicit bounded capacity":
    let sinks = new seq[IntSink]
    let cancellations = new int
    let command = initCommand[int, string, string](
      (proc(input: int; sink: IntSink): CommandCancel =
        discard input
        sinks[].add sink
        return proc() = inc cancellations[]),
      policy = cpConcurrent,
      maxPendingCompletions = 1
    )
    discard command.run(1)
    discard command.run(2)
    check sinks[][0].succeed("one") == smorAccepted
    check sinks[][1].succeed("two") == smorBackpressure
    check command.pump() == 1
    check sinks[][1].succeed("two") == smorAccepted
    check command.pump() == 1

  test "large concurrent sets complete in reverse order without lookup drift":
    const runCount = 2_000
    let sinks = new seq[CommandSink[int, string]]
    let command = initCommand[int, int, string](
      proc(input: int; sink: CommandSink[int, string]): CommandCancel =
        discard input
        sinks[].add sink
        nil,
      policy = cpConcurrent,
      maxPendingCompletions = runCount
    )
    var completed: seq[int]
    command.onSuccess = proc(value: int) = completed.add value
    for value in 0 ..< runCount:
      discard command.run(value)
    check command.activeCount == runCount
    for value in countdown(runCount - 1, 0):
      check sinks[][value].succeed(value) == smorAccepted
    check command.pump() == runCount
    check command.activeCount == 0
    check completed.len == runCount
    check completed[0] == runCount - 1
    check completed[^1] == 0

  test "large ordered queues advance without shifting the remaining queue":
    const runCount = 2_000
    let sinks = new seq[CommandSink[int, string]]
    let command = initCommand[int, int, string](
      proc(input: int; sink: CommandSink[int, string]): CommandCancel =
        discard input
        sinks[].add sink
        nil,
      policy = cpOrdered
    )
    for value in 0 ..< runCount:
      discard command.run(value)
    check command.queuedCount == runCount - 1
    for value in 0 ..< runCount:
      check sinks[].len == value + 1
      check sinks[][value].succeed(value) == smorAccepted
      check command.pump(1) == 1
    check not command.pending
    check command.queuedCount == 0
