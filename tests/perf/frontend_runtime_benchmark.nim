## Verifies that concurrent Command completion uses indexed run lookup rather
## than scanning the active set for every result.
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
  var checksum = 0
  command.onSuccess = proc(value: int) = checksum = checksum xor value
  for value in 0 ..< runCount:
    discard command.run(value)
  for value in countdown(runCount - 1, 0):
    doAssert sinks[][value].succeed(value) == smorAccepted

  let started = getMonoTime()
  doAssert command.pump() == runCount
  result = elapsedUs(started) / runCount.float
  doAssert command.activeCount == 0
  doAssert checksum >= 0

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

when isMainModule:
  main()

