import std/[monotimes, options, times]

import clay_board_style_system

const dispatchIterations = 100_000

proc benchmark(listenerCount: int): float =
  var registry = initEventRegistry()
  let listener: EventHandler = proc(event: DispatchResult): EventOutcome =
    handledEvent()
  for index in 0 ..< listenerCount:
    registry.onClick(NodeId(index), listener)

  let dispatch = DispatchResult(
    target: some(NodeId(listenerCount - 1)),
    event: clickEvent(vec2(0, 0))
  )
  var handledCount = 0
  for index in 0 ..< 1_000:
    if registry.handle(dispatch):
      inc handledCount

  let started = getMonoTime()
  for index in 0 ..< dispatchIterations:
    if registry.handle(dispatch):
      inc handledCount
  let elapsed = (getMonoTime() - started).inNanoseconds
  doAssert handledCount == dispatchIterations + 1_000
  float(elapsed) / float(dispatchIterations)

when isMainModule:
  let small = benchmark(500)
  let large = benchmark(50_000)

  echo "CBSS indexed event dispatch benchmark (release, ARC)"
  echo "  500 listeners:   ", small, " ns/dispatch"
  echo "  50,000 listeners: ", large, " ns/dispatch"

  # Dispatch cost follows the target route and matching listeners, not the
  # total number of unrelated bindings in the registry.
  doAssert large <= small * 4.0 + 250.0
