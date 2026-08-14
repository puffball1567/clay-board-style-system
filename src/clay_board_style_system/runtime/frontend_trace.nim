import ../core/dirty_domain

type
  FrontendTraceKind* = enum
    ftkSessionQueued,
    ftkSessionStarted,
    ftkStageStarted,
    ftkActionStarted,
    ftkActionSucceeded,
    ftkActionFailed,
    ftkStageSucceeded,
    ftkStageFailed,
    ftkSessionSucceeded,
    ftkSessionFailed,
    ftkSessionCancelled,
    ftkTriggerSignal,
    ftkTriggerState,
    ftkTriggerStore,
    ftkTriggerSelector,
    ftkCommandStarted,
    ftkCommandSucceeded,
    ftkCommandFailed,
    ftkCommandCancelled,
    ftkMotionStarted,
    ftkMotionSucceeded,
    ftkMotionFailed,
    ftkMotionCancelled,
    ftkDirtyDomains

  FrontendTraceEvent* = object
    sequence*: uint64
    atSeconds*: float64
    kind*: FrontendTraceKind
    sessionId*: uint64
    stageIndex*: int
    branchIndex*: int
    name*: string
    revision*: uint64
    domains*: set[DirtyDomain]
    detail*: string

  FrontendTrace* = ref object
    events: seq[FrontendTraceEvent]
    head: int
    countValue: int
    droppedValue: uint64
    nextSequence: uint64

proc initFrontendTrace*(capacity = 2048): FrontendTrace =
  if capacity <= 0:
    raise newException(ValueError, "Frontend trace capacity must be positive")
  FrontendTrace(
    events: newSeq[FrontendTraceEvent](capacity),
    nextSequence: 1
  )

proc capacity*(trace: FrontendTrace): int {.inline.} =
  if trace.isNil: 0 else: trace.events.len

proc len*(trace: FrontendTrace): int {.inline.} =
  if trace.isNil: 0 else: trace.countValue

proc dropped*(trace: FrontendTrace): uint64 {.inline.} =
  if trace.isNil: 0 else: trace.droppedValue

proc add*(trace: FrontendTrace; event: sink FrontendTraceEvent) =
  if trace.isNil:
    return
  var stored = move(event)
  stored.sequence = trace.nextSequence
  inc trace.nextSequence
  let index = (trace.head + trace.countValue) mod trace.events.len
  if trace.countValue == trace.events.len:
    trace.events[trace.head] = move(stored)
    trace.head = (trace.head + 1) mod trace.events.len
    inc trace.droppedValue
  else:
    trace.events[index] = move(stored)
    inc trace.countValue

proc snapshot*(trace: FrontendTrace): seq[FrontendTraceEvent] =
  if trace.isNil:
    return
  result = newSeqOfCap[FrontendTraceEvent](trace.countValue)
  for offset in 0 ..< trace.countValue:
    result.add trace.events[(trace.head + offset) mod trace.events.len]

proc clear*(trace: FrontendTrace) =
  if trace.isNil:
    return
  for event in trace.events.mitems:
    event = FrontendTraceEvent()
  trace.head = 0
  trace.countValue = 0
  trace.droppedValue = 0
