## Verifies that Command and Cue completion use indexed/counted runtime state
## rather than scanning the active set for every result.
import std/[monotimes, strformat, times]

import clay_board_style_system
import clay_board_style_system/frontend_runtime

proc elapsedUs(started: MonoTime): float =
  (getMonoTime() - started).inNanoseconds.float / 1_000.0

proc benchmarkConcurrentCompletion(runCount: int): float =
  let sinks = new seq[CommandSink[int, string]]
  let command = initCommand[int, int, string](
    proc(input: int; sink: CommandSink[int, string]): CommandCancel =
      discard input
      sinks[].add sink
      nil,
    policy = cpConcurrent,
    maxPendingCompletions = runCount
  )
  defer:
    doAssert command.dispose()
  var checksum = 0
  var settled = 0
  command.onSuccess = proc(value: int) = checksum = checksum xor value
  for value in 0 ..< runCount:
    let ticket = command.run(value)
    discard command.observeRun(
      ticket,
      proc(ticket: CommandTicket; status: CommandStatus) {.raises: [].} =
        discard ticket
        if status == csSucceeded:
          inc settled
    )
  for value in countdown(runCount - 1, 0):
    doAssert sinks[][value].succeed(value) == smorAccepted

  let started = getMonoTime()
  doAssert command.pump() == runCount
  result = elapsedUs(started) / runCount.float
  doAssert command.activeCount == 0
  doAssert checksum >= 0
  doAssert settled == runCount

proc benchmarkParallelCueCompletion(branchCount: int): float =
  let completions = new seq[CueCompletion]
  let action = cueAction("parallel", proc(completion: CueCompletion): CueCancel =
    completions[].add completion
    nil
  )
  var branches = newSeq[CueBranch](branchCount)
  for index in 0 ..< branchCount:
    branches[index] = branch(action)
  let graph = cue(cueAction("start", proc() = discard)).thenStage(branches)
  let runtime = initCueRuntime()
  defer:
    doAssert runtime.dispose()
  let session = runtime.start(graph)
  doAssert completions[].len == branchCount

  let started = getMonoTime()
  for completion in completions[]:
    completion.succeed()
  result = elapsedUs(started) / branchCount.float
  doAssert session.status == cssSucceeded
  doAssert runtime.activeCount == 0

proc benchmarkCanvasCueCompletion(branchCount: int): float =
  let ui = initUiRoot()
  let drawing = newCanvas2D()
  let canvas = ui.canvas(drawing)
  ui.surfaces.mountSurface(
    canvas.surface,
    canvas.node.id,
    renderSurfacePlacement(rect(0, 0, 100, 100), rect(0, 0, 100, 100))
  )
  var completed = 0
  let action = cueCanvas(
    "canvas-frame",
    canvas,
    proc(
        value: Canvas2D;
        frame: RenderSurfaceFrame
    ): CueCanvasFrameDecision =
      discard value
      discard frame
      inc completed
      ccfdComplete
  )
  var branches = newSeq[CueBranch](branchCount)
  for index in 0 ..< branchCount:
    branches[index] = branch(action)
  let graph = cue(cueAction("start", proc() = discard)).thenStage(branches)
  let runtime = initCueRuntime()
  defer:
    doAssert runtime.dispose()
  let session = runtime.start(graph)

  let started = getMonoTime()
  doAssert ui.runRenderSurfaceFrames(1) == 1
  result = elapsedUs(started) / branchCount.float
  doAssert completed == branchCount
  doAssert session.status == cssSucceeded
  doAssert runtime.activeCount == 0
  doAssert not drawing.hasFrameObservers(canvas.surface)

proc main() =
  echo "CBSS frontend-runtime concurrent Command benchmark (release, ARC)"
  echo "Reverse-order worker results; mean UI pump cost per completion"
  echo "active runs\tcompletion us"
  let small = benchmarkConcurrentCompletion(1_000)
  let large = benchmarkConcurrentCompletion(10_000)
  echo &"1000\t{small:.3f}"
  echo &"10000\t{large:.3f}"
  doAssert large <= small * 4.0 + 0.5,
    "Command completion lookup scaled superlinearly with active runs"

  echo "Parallel Cue stage; mean completion cost per branch"
  echo "branches\tcompletion us"
  let cueSmall = benchmarkParallelCueCompletion(1_000)
  let cueLarge = benchmarkParallelCueCompletion(10_000)
  echo &"1000\t{cueSmall:.3f}"
  echo &"10000\t{cueLarge:.3f}"
  doAssert cueLarge <= cueSmall * 4.0 + 0.5,
    "Cue completion scaled superlinearly with parallel branches"

  echo "Canvas Cue fan-out; mean frame dispatch and completion cost per branch"
  echo "branches\tcompletion us"
  let canvasSmall = benchmarkCanvasCueCompletion(1_000)
  let canvasLarge = benchmarkCanvasCueCompletion(10_000)
  echo &"1000\t{canvasSmall:.3f}"
  echo &"10000\t{canvasLarge:.3f}"
  doAssert canvasLarge <= canvasSmall * 4.0 + 0.5,
    "Canvas Cue completion scaled superlinearly with parallel branches"

when isMainModule:
  main()
