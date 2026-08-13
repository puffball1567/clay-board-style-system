import std/[options, unittest]

import clay_board_style_system
import clay_board_style_system/frontend_runtime

type
  DeferredAction = object
    action: CueAction
    completions: ref seq[CueCompletion]
    cancellations: ref int

  CueComponent = ref object of CBSSComponent
    runtime: CueRuntime
    deferred: DeferredAction

proc deferredAction(name: string): DeferredAction =
  result.completions = new seq[CueCompletion]
  result.cancellations = new int
  let completions = result.completions
  let cancellations = result.cancellations
  result.action = cueAction(name, proc(completion: CueCompletion): CueCancel =
    completions[].add completion
    return proc() {.raises: [].} = inc cancellations[]
  )

proc render(self: CueComponent) =
  self.runtime = self.cueRuntime()
  self.deferred = deferredAction("component work")
  ui.box(self):
    ui.text("cue")

suite "Cue orchestration runtime":
  test "serial actions advance automatically in declaration order":
    let runtime = initCueRuntime()
    var events: seq[string]
    let graph = cue(cueAction("A", proc() = events.add "A"))
      .then(cueAction("B", proc() = events.add "B"))
      .then(cueAction("C", proc() = events.add "C"))

    let session = runtime.start(graph)

    check events == @["A", "B", "C"]
    check session.status == cssSucceeded
    check runtime.activeCount == 0
    check runtime.nextDeadline.isNone

  test "all join starts branches together and waits for every completion":
    let runtime = initCueRuntime()
    let first = deferredAction("first")
    let second = deferredAction("second")
    var tailRuns = 0
    let graph = cue(cueAction("start", proc() = discard))
      .thenParallel(first.action, second.action)
      .then(cueAction("tail", proc() = inc tailRuns))

    let session = runtime.start(graph)
    check first.completions[].len == 1
    check second.completions[].len == 1
    check tailRuns == 0
    check session.status == cssRunning

    first.completions[][0].succeed()
    check tailRuns == 0
    second.completions[][0].succeed()
    check tailRuns == 1
    check session.status == cssSucceeded

  test "delayed branches expose a monotonic next deadline":
    let runtime = initCueRuntime(10.0)
    var events: seq[string]
    let graph = cue(cueAction("start", proc() = events.add "start"))
      .thenStage([
        cueAfter(0.5, cueAction("half", proc() = events.add "half")),
        cueAfter(2.0, cueAction("two", proc() = events.add "two"))
      ])

    let session = runtime.start(graph)
    check events == @["start"]
    check runtime.nextDeadline == some(10.5)
    runtime.tick(10.49)
    check events == @["start"]
    runtime.tick(10.5)
    check events == @["start", "half"]
    check runtime.nextDeadline == some(12.0)
    runtime.tick(12.0)
    check events == @["start", "half", "two"]
    check session.status == cssSucceeded
    expect ValueError:
      runtime.tick(11.0)

  test "pause and rate map host time onto an independent Cue clock":
    let runtime = initCueRuntime()
    var runs = 0
    let graph = cue(cueAction("start", proc() = discard))
      .thenStage([cueAfter(10.0, cueAction("delayed", proc() = inc runs))])
    let session = runtime.start(graph)
    check runtime.nextDeadline == some(10.0)

    runtime.tick(2.0)
    runtime.pause()
    runtime.tick(20.0)
    check runtime.paused
    check runtime.now == 2.0
    check runtime.nextDeadline.isNone
    check runs == 0

    runtime.resume()
    check runtime.nextDeadline == some(28.0)
    runtime.setRate(2.0)
    check runtime.rate == 2.0
    check runtime.nextDeadline == some(24.0)
    runtime.tick(23.9)
    check runs == 0
    runtime.tick(24.0)
    check runs == 1
    check session.status == cssSucceeded
    expect ValueError:
      runtime.setRate(0.0)

  test "any join advances on first success and cancels unfinished work":
    let runtime = initCueRuntime()
    let failed = deferredAction("failed")
    let winner = deferredAction("winner")
    let pending = deferredAction("pending")
    var tailRuns = 0
    let graph = cue(cueAction("start", proc() = discard))
      .thenAny(failed.action, winner.action, pending.action)
      .then(cueAction("tail", proc() = inc tailRuns))

    let session = runtime.start(graph)
    failed.completions[][0].fail("not this one")
    check session.status == cssRunning
    winner.completions[][0].succeed()
    check session.status == cssSucceeded
    check tailRuns == 1
    check pending.cancellations[] == 1
    pending.completions[][0].succeed()
    check tailRuns == 1

  test "race uses the first terminal branch and reports its failure":
    let runtime = initCueRuntime()
    let loser = deferredAction("loser")
    let pending = deferredAction("pending")
    let graph = cue(cueAction("start", proc() = discard))
      .thenRace(loser.action, pending.action)

    let session = runtime.start(graph)
    loser.completions[][0].fail("network unavailable")
    check session.status == cssFailed
    check session.failure == "network unavailable"
    check pending.cancellations[] == 1

  test "branches sharing one delayed deadline all start before a join settles":
    let runtime = initCueRuntime()
    var events: seq[string]
    let graph = cue(cueAction("start", proc() = discard))
      .thenStage([
        cueAfter(1.0, cueAction("first", proc() = events.add "first")),
        cueAfter(1.0, cueAction("second", proc() = events.add "second"))
      ], cjpRace)
    let session = runtime.start(graph)

    runtime.tick(1.0)
    check events == @["first", "second"]
    check session.status == cssSucceeded

  test "all join fails fast and executor exceptions cannot wedge runtime":
    let runtime = initCueRuntime()
    let pending = deferredAction("pending")
    let throwing = cueAction("throwing", proc(completion: CueCompletion): CueCancel =
      discard completion
      raise newException(ValueError, "action crashed")
    )
    let graph = cue(cueAction("start", proc() = discard))
      .thenParallel(throwing, pending.action)

    let session = runtime.start(graph)
    check session.status == cssFailed
    check session.failure == "action crashed"
    check pending.cancellations[] == 1

  test "completion and cancellation are idempotent":
    let runtime = initCueRuntime()
    let pending = deferredAction("pending")
    let session = runtime.start(cue(pending.action))
    check runtime.cancel(session)
    check session.status == cssCancelled
    check pending.cancellations[] == 1

    check not runtime.cancel(session)
    pending.completions[][0].succeed()
    pending.completions[][0].fail("late")
    check session.status == cssCancelled
    check pending.cancellations[] == 1

  test "restart cancels active and queued sessions before starting anew":
    let runtime = initCueRuntime()
    let pending = deferredAction("pending")
    let graph = cue(pending.action)
    let first = runtime.start(graph, cspParallel)
    let queued = runtime.start(graph, cspQueue)
    let replacement = runtime.start(graph, cspRestart)

    check first.status == cssCancelled
    check queued.status == cssCancelled
    check replacement.status == cssRunning
    check pending.cancellations[] == 1
    check pending.completions[].len == 2

  test "ignore returns the active session while parallel creates another":
    let runtime = initCueRuntime()
    let pending = deferredAction("pending")
    let graph = cue(pending.action)
    let first = runtime.start(graph)
    let ignored = runtime.start(graph, cspIgnore)
    let parallel = runtime.start(graph, cspParallel)

    check ignored.id == first.id
    check parallel.id != first.id
    check runtime.activeCount == 2
    check pending.completions[].len == 2

  test "queued sessions activate in FIFO order and cancelled entries are skipped":
    let runtime = initCueRuntime()
    let pending = deferredAction("pending")
    let graph = cue(pending.action)
    let first = runtime.start(graph)
    let second = runtime.start(graph, cspQueue)
    let third = runtime.start(graph, cspQueue)
    check second.status == cssQueued
    check third.status == cssQueued
    check runtime.cancel(second)

    pending.completions[][0].succeed()
    check first.status == cssSucceeded
    check second.status == cssCancelled
    check third.status == cssRunning
    check pending.completions[].len == 2
    pending.completions[][1].succeed()
    check third.status == cssSucceeded

  test "component unmount cancels owned sessions and ignores late completion":
    let root = initUiRoot()
    let component = root.mount(CueComponent())
    let session = component.runtime.start(cue(component.deferred.action))
    check session.status == cssRunning

    var interaction = initInteractionState()
    check root.disposeSubtree(component.node, interaction)
    check session.status == cssCancelled
    check component.deferred.cancellations[] == 1
    component.deferred.completions[][0].succeed()
    check session.status == cssCancelled

  test "started graphs are immutable and invalid inputs fail explicitly":
    let runtime = initCueRuntime()
    let graph = cue(cueAction("start", proc() = discard))
    discard runtime.start(graph)
    expect ValueError:
      discard graph.then(cueAction("late", proc() = discard))
    expect ValueError:
      discard cueAction("", proc() = discard)
    expect ValueError:
      discard cueAction("nil", CueActionExecutor(nil))
    expect ValueError:
      discard branch(nil)
    expect ValueError:
      discard branch(cueAction("delay", proc() = discard), -1.0)
    expect ValueError:
      discard initCueRuntime(Inf)
    expect ValueError:
      discard runtime.start(nil)

  test "large synchronous chains do not recurse through the call stack":
    const actionCount = 5_000
    let runtime = initCueRuntime()
    var runs = 0
    let action = cueAction("increment", proc() = inc runs)
    let graph = cue(action)
    for _ in 1 ..< actionCount:
      discard graph.then(action)

    let session = runtime.start(graph)
    check runs == actionCount
    check session.status == cssSucceeded

  test "large parallel stages settle without repeated whole-stage scans":
    const actionCount = 5_000
    let runtime = initCueRuntime()
    let pending = deferredAction("parallel")
    var branches = newSeq[CueBranch](actionCount)
    for index in 0 ..< actionCount:
      branches[index] = branch(pending.action)
    let graph = cue(cueAction("start", proc() = discard))
      .thenStage(branches)
    let session = runtime.start(graph)

    check pending.completions[].len == actionCount
    for completion in pending.completions[]:
      completion.succeed()
    check session.status == cssSucceeded
    check runtime.activeCount == 0
