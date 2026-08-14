import std/unittest

import clay_board_style_system/frontend_runtime

when not defined(release) or defined(cbssFrontendTrace):
  proc kinds(events: openArray[FrontendTraceEvent]): seq[FrontendTraceKind] =
    for event in events:
      result.add event.kind

  suite "development frontend trace":
    test "bounded storage preserves chronological order and reports loss":
      let trace = initFrontendTrace(3)
      for index in 0 .. 4:
        trace.add FrontendTraceEvent(
          kind: ftkActionStarted,
          branchIndex: index
        )

      let events = trace.snapshot
      check trace.capacity == 3
      check trace.len == 3
      check trace.dropped == 2
      check events.len == 3
      check events[0].sequence == 3
      check events[0].branchIndex == 2
      check events[2].sequence == 5
      check events[2].branchIndex == 4

      trace.clear()
      check trace.len == 0
      check trace.dropped == 0
      check trace.snapshot.len == 0

    test "invalid capacity fails before allocating storage":
      expect ValueError:
        discard initFrontendTrace(0)
      expect ValueError:
        discard initFrontendTrace(-1)

    test "serial Cue lifecycle has one ordered event per transition":
      let runtime = initCueRuntime(7.0)
      let trace = runtime.enableTrace(32)
      let graph = cue(cueAction("first", proc() = discard))
        .then(cueAction("second", proc() = discard))

      let session = runtime.start(graph)
      let events = trace.snapshot

      check session.status == cssSucceeded
      check events.kinds == @[
        ftkSessionStarted,
        ftkStageStarted,
        ftkActionStarted,
        ftkActionSucceeded,
        ftkStageSucceeded,
        ftkStageStarted,
        ftkActionStarted,
        ftkActionSucceeded,
        ftkStageSucceeded,
        ftkSessionSucceeded
      ]
      check events[0].sessionId == session.id
      check events[0].atSeconds == 7.0
      check events[2].name == "first"
      check events[2].stageIndex == 0
      check events[2].branchIndex == 0
      check events[6].name == "second"
      check events[6].stageIndex == 1

    test "parallel failure records the failing branch and terminal reason":
      let runtime = initCueRuntime()
      let trace = runtime.enableTrace()
      var firstCompletion: CueCompletion
      var secondCancelled = 0
      let first = cueAction("first", proc(completion: CueCompletion): CueCancel =
        firstCompletion = completion
        nil
      )
      let second = cueAction("second", proc(completion: CueCompletion): CueCancel =
        discard completion
        return proc() {.raises: [].} = inc secondCancelled
      )
      let graph = cue(cueAction("prepare", proc() = discard))
        .thenParallel(first, second)

      let session = runtime.start(graph)
      firstCompletion.fail("expected failure")
      let events = trace.snapshot

      check session.status == cssFailed
      check secondCancelled == 1
      check ftkActionFailed in events.kinds
      check ftkStageFailed in events.kinds
      check events[^1].kind == ftkSessionFailed
      check events[^1].detail == "expected failure"

    test "queued activation and cancellation are distinguishable":
      let runtime = initCueRuntime()
      let trace = runtime.enableTrace()
      var completions: seq[CueCompletion]
      let graph = cue(cueAction("pending", proc(completion: CueCompletion): CueCancel =
        completions.add completion
        nil
      ))
      let first = runtime.start(graph)
      let second = runtime.start(graph, cspQueue)

      check trace.snapshot[^1].kind == ftkSessionQueued
      check trace.snapshot[^1].sessionId == second.id
      completions[0].succeed()

      let activated = trace.snapshot
      var secondStarted = false
      for event in activated:
        if event.kind == ftkSessionStarted and event.sessionId == second.id:
          secondStarted = true
      check first.status == cssSucceeded
      check second.status == cssRunning
      check secondStarted

      check runtime.cancel(second)
      check trace.snapshot[^1].kind == ftkSessionCancelled
      check trace.snapshot[^1].sessionId == second.id

    test "restart records every queued session it replaces":
      let runtime = initCueRuntime()
      let trace = runtime.enableTrace()
      var completions: seq[CueCompletion]
      let graph = cue(cueAction("pending", proc(completion: CueCompletion): CueCancel =
        completions.add completion
        nil
      ))
      let first = runtime.start(graph)
      let queued = runtime.start(graph, cspQueue)
      let replacement = runtime.start(graph, cspRestart)

      var queuedCancellation = false
      for event in trace.snapshot:
        if event.kind == ftkSessionCancelled and
            event.sessionId == queued.id and
            event.detail == "Cue session was replaced":
          queuedCancellation = true
      check first.status == cssCancelled
      check queued.status == cssCancelled
      check replacement.status == cssRunning
      check queuedCancellation

    test "tracing can be detached without affecting Cue execution":
      let runtime = initCueRuntime()
      let trace = runtime.enableTrace()
      runtime.disableTrace()
      var ran = false
      let session = runtime.start(cue(cueAction("work", proc() = ran = true)))

      check ran
      check session.status == cssSucceeded
      check runtime.trace.isNil
      check trace.len == 0
