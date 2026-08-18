import std/unittest

import clay_board_style_system
import clay_board_style_system/frontend_runtime

type DeferredAction = object
  action: CueAction
  completions: ref seq[CueCompletion]

proc deferredAction(name: string; starts: ref seq[string]): DeferredAction =
  result.completions = new seq[CueCompletion]
  let completions = result.completions
  result.action = cueAction(name, proc(completion: CueCompletion): CueCancel =
    starts[].add name
    completions[].add completion
    nil
  )

suite "orchestration demo contract":
  test "one Signal drives delayed parallel branches through an all join":
    let starts = new seq[string]
    let actionA = deferredAction("A / intake", starts)
    let actionB = deferredAction("B / layout", starts)
    let actionC = deferredAction("C / paint", starts)
    let actionD = deferredAction("D / signal", starts)
    let actionE = deferredAction("E / commit", starts)

    let sequence = cue(actionA.action)
      .thenStage([
        branch(actionB.action),
        cueAfter(0.15, actionC.action),
        cueAfter(0.30, actionD.action)
      ])
      .then(actionE.action)

    let launch = initSignal[int]()
    let runtime = initCueRuntime()
    when not defined(release) or defined(cbssFrontendTrace):
      let trace = runtime.enableTrace(128)
    let trigger = initCueTrigger(launch, runtime, sequence)
    defer:
      check trigger.dispose()
      check runtime.dispose()

    launch.emit(1)
    check starts[] == @["A / intake"]
    check runtime.activeCount == 1

    actionA.completions[][0].succeed()
    check starts[] == @["A / intake", "B / layout"]

    runtime.tick(0.149)
    check starts[].len == 2
    runtime.tick(0.150)
    check starts[] == @["A / intake", "B / layout", "C / paint"]
    runtime.tick(0.299)
    check starts[].len == 3
    runtime.tick(0.300)
    check starts[] == @[
      "A / intake", "B / layout", "C / paint", "D / signal"
    ]

    actionB.completions[][0].succeed()
    actionC.completions[][0].succeed()
    check actionE.completions[].len == 0
    actionD.completions[][0].succeed()
    check starts[^1] == "E / commit"

    actionE.completions[][0].succeed()
    check runtime.activeCount == 0

    when not defined(release) or defined(cbssFrontendTrace):
      let events = trace.snapshot()
      check events[0].kind == ftkTriggerSignal
      check events[1].kind == ftkSessionStarted
      check events[^2].kind == ftkStageSucceeded
      check events[^1].kind == ftkSessionSucceeded
