when defined(cbssFrontendTrace):
  import std/[monotimes, strformat, times]

  import clay_board_style_system/frontend_runtime

  proc elapsedUs(started: MonoTime): float =
    (getMonoTime() - started).inNanoseconds.float / 1_000.0

  proc benchmarkTraceWrites(writeCount: int): float =
    let trace = initFrontendTrace(2048)
    let started = getMonoTime()
    for index in 0 ..< writeCount:
      trace.add FrontendTraceEvent(
        kind: ftkActionStarted,
        sessionId: uint64(index),
        name: "work"
      )
    result = elapsedUs(started) / writeCount.float
    doAssert trace.len == 2048
    doAssert trace.dropped == uint64(writeCount - 2048)

  proc main() =
    echo "CBSS bounded frontend trace benchmark (release, ARC)"
    echo "writes\tappend us"
    let small = benchmarkTraceWrites(10_000)
    let large = benchmarkTraceWrites(1_000_000)
    echo &"10000\t{small:.3f}"
    echo &"1000000\t{large:.3f}"
    doAssert large <= small * 4.0 + 0.5,
      "bounded trace append scaled with trace history"

  when isMainModule:
    main()
