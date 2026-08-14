import std/unittest

import clay_board_style_system
import clay_board_style_system/frontend_runtime

type
  TestCommand = Command[int, string, string]
  TestSink = CommandSink[string, string]

  CueCommandComponent = ref object of CBSSComponent
    sinks: ref seq[TestSink]
    cancellations: ref int
    commandValue: TestCommand
    runtimeValue: CueRuntime
    session: CueSession

proc deferredCommand(
    policy: CommandPolicy;
    sinks: ref seq[TestSink];
    cancellations: ref int
): TestCommand =
  initCommand[int, string, string](
    (proc(input: int; sink: TestSink): CommandCancel =
      discard input
      sinks[].add sink
      return proc() {.raises: [].} = inc cancellations[]),
    policy = policy
  )

proc render(self: CueCommandComponent) =
  self.commandValue = command[int, string, string](
    self,
    proc(input: int; sink: TestSink): CommandCancel =
      discard input
      self.sinks[].add sink
      return proc() {.raises: [].} = inc self.cancellations[]
  )
  self.runtimeValue = self.cueRuntime()
  self.session = self.runtimeValue.start(cue(cueCommand(
    "component-work",
    self.commandValue,
    proc(): int = 1
  )))
  ui.box(self):
    ui.text("command")

suite "Cue Command adapter":
  when not defined(release) or defined(cbssFrontendTrace):
    test "Command lifecycle shares the owning Cue trace context":
      let sinks = new seq[TestSink]
      let cancellations = new int
      let command = deferredCommand(cpConcurrent, sinks, cancellations)
      let runtime = initCueRuntime()
      let trace = runtime.enableTrace()
      defer:
        check runtime.dispose()
        check command.dispose()
      let session = runtime.start(cue(cueCommand(
        "load",
        command,
        proc(): int = 42
      )))

      check sinks[][0].succeed("loaded") == smorAccepted
      check command.pump() == 1
      let events = trace.snapshot
      var commandStarted = false
      var commandSucceeded = false
      for event in events:
        if event.kind == ftkCommandStarted and event.name == "load" and
            event.revision == 1:
          commandStarted = true
        elif event.kind == ftkCommandSucceeded and event.name == "load" and
            event.revision == 1:
          commandSucceeded = true
      check session.status == cssSucceeded
      check commandStarted
      check commandSucceeded

  test "successful Commands advance Cue only after the UI pumps":
    let sinks = new seq[TestSink]
    let cancellations = new int
    let command = deferredCommand(cpConcurrent, sinks, cancellations)
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
      check command.dispose()
    var events: seq[string]
    let graph = cue(cueCommand(
      "load",
      command,
      proc(): int = 42
    )).then(cueAction("render", proc() = events.add "render"))

    let session = runtime.start(graph)
    check session.status == cssRunning
    check sinks[].len == 1
    check sinks[][0].succeed("loaded") == smorAccepted
    check session.status == cssRunning
    check events.len == 0
    check command.pump() == 1
    check session.status == cssSucceeded
    check events == @["render"]

  test "Command failure stops the Cue graph with its declared message":
    let sinks = new seq[TestSink]
    let cancellations = new int
    let command = deferredCommand(cpConcurrent, sinks, cancellations)
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
      check command.dispose()
    var reachedNext = false
    let graph = cue(cueCommand(
      "save",
      command,
      proc(): int = 1,
      failureMessage = "Save failed"
    )).then(cueAction("next", proc() = reachedNext = true))

    let session = runtime.start(graph)
    check sinks[][0].fail("disk full") == smorAccepted
    check command.pump() == 1
    check session.status == cssFailed
    check session.failure == "Save failed"
    check not reachedNext

  test "external Command cancellation fails its waiting Cue action":
    let sinks = new seq[TestSink]
    let cancellations = new int
    let command = deferredCommand(cpConcurrent, sinks, cancellations)
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
      check command.dispose()
    let graph = cue(cueCommand(
      "refresh",
      command,
      proc(): int = 1,
      cancelledMessage = "Refresh cancelled"
    ))

    let session = runtime.start(graph)
    check command.cancelAll() == 1
    check session.status == cssFailed
    check session.failure == "Refresh cancelled"
    check cancellations[] == 1

  test "Cue cancellation detaches and cancels the Command run":
    let sinks = new seq[TestSink]
    let cancellations = new int
    let command = deferredCommand(cpConcurrent, sinks, cancellations)
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
      check command.dispose()
    let graph = cue(cueCommand("work", command, proc(): int = 1))

    let session = runtime.start(graph)
    check runtime.cancel(session)
    check session.status == cssCancelled
    check command.activeCount == 0
    check cancellations[] == 1
    check sinks[][0].succeed("late") == smorAccepted
    check command.pump() == 1
    check session.status == cssCancelled

  test "disposing a Command settles its waiting Cue instead of stranding it":
    let sinks = new seq[TestSink]
    let cancellations = new int
    let command = deferredCommand(cpConcurrent, sinks, cancellations)
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
    let graph = cue(cueCommand(
      "work",
      command,
      proc(): int = 1,
      cancelledMessage = "Command disposed"
    ))

    let session = runtime.start(graph)
    check command.dispose()
    check session.status == cssFailed
    check session.failure == "Command disposed"
    check cancellations[] == 1
    check sinks[][0].succeed("late") == smorDisposed

  test "component unmount cancels the adapter before releasing its Command":
    let root = initUiRoot()
    let sinks = new seq[TestSink]
    let cancellations = new int
    let component = root.mount(CueCommandComponent(
      sinks: sinks,
      cancellations: cancellations
    ))
    check component.session.status == cssRunning

    var interaction = initInteractionState()
    check root.disposeSubtree(component.node, interaction)
    check component.session.status == cssCancelled
    check cancellations[] == 1
    check sinks[][0].succeed("late") == smorDisposed

  test "global Command callbacks remain independent from Cue completion":
    let sinks = new seq[TestSink]
    let cancellations = new int
    let command = deferredCommand(cpConcurrent, sinks, cancellations)
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
      check command.dispose()
    var outputs: seq[string]
    command.onSuccess = proc(value: string) = outputs.add value
    let graph = cue(cueCommand("load", command, proc(): int = 7))

    let session = runtime.start(graph)
    check sinks[][0].succeed("payload") == smorAccepted
    check command.pump() == 1
    check outputs == @["payload"]
    check session.status == cssSucceeded

  test "input factories run once for every reusable graph session":
    let sinks = new seq[TestSink]
    let inputs = new seq[int]
    let command = initCommand[int, string, string](
      (proc(input: int; sink: TestSink): CommandCancel =
        inputs[].add input
        sinks[].add sink
        nil),
      policy = cpConcurrent
    )
    let runtime = initCueRuntime()
    defer:
      check runtime.dispose()
      check command.dispose()
    var nextInput = 0
    let graph = cue(cueCommand(
      "repeat",
      command,
      proc(): int =
        inc nextInput
        nextInput
    ))

    let first = runtime.start(graph, cspParallel)
    let second = runtime.start(graph, cspParallel)
    check inputs[] == @[1, 2]
    check sinks[][0].succeed("one") == smorAccepted
    check sinks[][1].succeed("two") == smorAccepted
    check command.pump() == 2
    check first.status == cssSucceeded
    check second.status == cssSucceeded

  test "start failures become Cue failures instead of wedging the session":
    let command = initCommand[int, string, string](
      proc(input: int; sink: TestSink): CommandCancel =
        discard input
        discard sink
        raise newException(ValueError, "executor rejected input")
    )
    let runtime = initCueRuntime()
    when not defined(release) or defined(cbssFrontendTrace):
      let trace = runtime.enableTrace()
    defer:
      check runtime.dispose()
      check command.dispose()
    let graph = cue(cueCommand("reject", command, proc(): int = 1))

    let session = runtime.start(graph)
    check session.status == cssFailed
    check session.failure == "Command could not start: executor rejected input"
    when not defined(release) or defined(cbssFrontendTrace):
      var startFailure = false
      for event in trace.snapshot:
        if event.kind == ftkCommandFailed and event.name == "reject" and
            event.detail == "Command could not start: executor rejected input":
          startFailure = true
      check startFailure

  test "invalid adapter inputs fail before a graph is created":
    let sinks = new seq[TestSink]
    let cancellations = new int
    let command = deferredCommand(cpConcurrent, sinks, cancellations)
    defer:
      check command.dispose()
    expect ValueError:
      discard cueCommand[int, string, string](
        "nil",
        nil,
        proc(): int = 1
      )
    expect ValueError:
      discard cueCommand[int, string, string](
        "factory",
        command,
        CommandInputFactory[int](nil)
      )
    expect ValueError:
      discard cueCommand(
        "failure",
        command,
        proc(): int = 1,
        failureMessage = ""
      )
    expect ValueError:
      discard cueCommand(
        "cancel",
        command,
        proc(): int = 1,
        cancelledMessage = ""
      )
