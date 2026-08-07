import std/options

type
  StreamState* = enum
    ssIdle,
    ssOpen,
    ssEnded,
    ssFailed,
    ssCancelled,
    ssClosed

  StreamTerminalKind* = enum
    stkNone,
    stkEnd,
    stkError,
    stkCancel

  StreamEventKind* = enum
    sekOpen,
    sekData,
    sekProgress,
    sekEnd,
    sekError,
    sekCancel,
    sekClose

  StreamOfferResult* = enum
    sorAccepted,
    sorBackpressure,
    sorNotOpen

  StreamEvent*[T] = object
    case kind*: StreamEventKind
    of sekData:
      data*: T
      weight*: int64
    of sekProgress:
      completed*: uint64
      total*: Option[uint64]
    of sekError:
      message*: string
    else:
      discard

  PendingStreamData[T] = object
    value: T
    weight: int64

  StreamBridge*[T] = ref object
    maxQueuedItems: int
    maxQueuedWeight: int64
    queue: seq[PendingStreamData[T]]
    queueHead: int
    queuedWeightValue: int64
    stateValue: StreamState
    terminalValue: StreamTerminalKind
    terminalMessage: string
    openPending: bool
    progressPending: bool
    progressCompleted: uint64
    progressTotal: Option[uint64]
    terminalPending: bool
    closePending: bool
    revisionValue: uint64

proc initStreamBridge*[T](
    maxQueuedItems = 64;
    maxQueuedWeight = 4'i64 * 1024'i64 * 1024'i64
): StreamBridge[T] =
  if maxQueuedItems <= 0:
    raise newException(ValueError, "stream queue item limit must be positive")
  if maxQueuedWeight <= 0:
    raise newException(ValueError, "stream queue weight limit must be positive")
  StreamBridge[T](
    maxQueuedItems: maxQueuedItems,
    maxQueuedWeight: maxQueuedWeight,
    queue: @[],
    stateValue: ssIdle,
    terminalValue: stkNone
  )

proc state*[T](stream: StreamBridge[T]): StreamState {.inline.} =
  if stream.isNil: ssClosed else: stream.stateValue

proc terminalKind*[T](stream: StreamBridge[T]): StreamTerminalKind {.inline.} =
  if stream.isNil: stkNone else: stream.terminalValue

proc revision*[T](stream: StreamBridge[T]): uint64 {.inline.} =
  if stream.isNil: 0'u64 else: stream.revisionValue

proc queuedItems*[T](stream: StreamBridge[T]): int {.inline.} =
  if stream.isNil: 0 else: stream.queue.len - stream.queueHead

proc queuedWeight*[T](stream: StreamBridge[T]): int64 {.inline.} =
  if stream.isNil: 0'i64 else: stream.queuedWeightValue

proc hasPending*[T](stream: StreamBridge[T]): bool {.inline.} =
  not stream.isNil and (
    stream.openPending or stream.queuedItems > 0 or
    stream.progressPending or stream.terminalPending or stream.closePending
  )

proc advanceRevision[T](stream: StreamBridge[T]) {.inline.} =
  if stream.revisionValue < high(uint64):
    inc stream.revisionValue

proc open*[T](stream: StreamBridge[T]): bool =
  if stream.isNil or stream.stateValue != ssIdle:
    return false
  stream.stateValue = ssOpen
  stream.openPending = true
  stream.advanceRevision()
  true

proc pushData*[T](
    stream: StreamBridge[T];
    value: sink T;
    weight: int64
): StreamOfferResult =
  if stream.isNil or stream.stateValue != ssOpen:
    return sorNotOpen
  if weight < 0:
    raise newException(ValueError, "stream data weight cannot be negative")
  if stream.queuedItems >= stream.maxQueuedItems or
      weight > stream.maxQueuedWeight or
      stream.queuedWeightValue > stream.maxQueuedWeight - weight:
    return sorBackpressure
  stream.queue.add PendingStreamData[T](value: move(value), weight: weight)
  stream.queuedWeightValue += weight
  stream.advanceRevision()
  sorAccepted

proc reportProgress*[T](
    stream: StreamBridge[T];
    completed: uint64;
    total = none(uint64)
): bool =
  if stream.isNil or stream.stateValue != ssOpen:
    return false
  if total.isSome and completed > total.get:
    raise newException(ValueError, "stream progress exceeds its total")
  if stream.progressPending and stream.progressCompleted == completed and
      stream.progressTotal == total:
    return true
  stream.progressPending = true
  stream.progressCompleted = completed
  stream.progressTotal = total
  stream.advanceRevision()
  true

proc setTerminal[T](
    stream: StreamBridge[T];
    state: StreamState;
    kind: StreamTerminalKind;
    message = ""
): bool =
  if stream.isNil or stream.stateValue != ssOpen:
    return false
  stream.stateValue = state
  stream.terminalValue = kind
  stream.terminalMessage = message
  stream.terminalPending = true
  stream.advanceRevision()
  true

proc finish*[T](stream: StreamBridge[T]): bool =
  stream.setTerminal(ssEnded, stkEnd)

proc fail*[T](stream: StreamBridge[T]; message: string): bool =
  if message.len == 0:
    raise newException(ValueError, "stream error message cannot be empty")
  stream.setTerminal(ssFailed, stkError, message)

proc clearQueuedData[T](stream: StreamBridge[T]) =
  stream.queue.setLen(0)
  stream.queueHead = 0
  stream.queuedWeightValue = 0

proc cancel*[T](stream: StreamBridge[T]): bool =
  if stream.isNil or stream.stateValue notin {ssIdle, ssOpen}:
    return false
  stream.clearQueuedData()
  stream.openPending = false
  stream.progressPending = false
  stream.stateValue = ssCancelled
  stream.terminalValue = stkCancel
  stream.terminalMessage.setLen(0)
  stream.terminalPending = true
  stream.advanceRevision()
  true

proc close*[T](stream: StreamBridge[T]): bool =
  if stream.isNil or stream.stateValue == ssClosed:
    return false
  if stream.stateValue == ssOpen:
    discard stream.cancel()
  elif stream.stateValue == ssIdle:
    stream.openPending = false
  stream.stateValue = ssClosed
  stream.closePending = true
  stream.advanceRevision()
  true

proc compactQueue[T](stream: StreamBridge[T]) =
  if stream.queueHead == stream.queue.len:
    stream.queue.setLen(0)
    stream.queueHead = 0
  elif stream.queueHead >= 64 and stream.queueHead * 2 >= stream.queue.len:
    var compacted = newSeqOfCap[PendingStreamData[T]](
      stream.queue.len - stream.queueHead
    )
    for index in stream.queueHead ..< stream.queue.len:
      compacted.add move(stream.queue[index])
    stream.queue = move(compacted)
    stream.queueHead = 0

proc drain*[T](
    stream: StreamBridge[T];
    maxEvents = high(int)
): seq[StreamEvent[T]] =
  if stream.isNil or maxEvents <= 0:
    return @[]
  result = newSeqOfCap[StreamEvent[T]](
    min(maxEvents, stream.queuedItems + 4)
  )
  while result.len < maxEvents:
    if stream.openPending:
      stream.openPending = false
      result.add StreamEvent[T](kind: sekOpen)
    elif stream.queueHead < stream.queue.len:
      var pending = move(stream.queue[stream.queueHead])
      inc stream.queueHead
      stream.queuedWeightValue -= pending.weight
      result.add StreamEvent[T](
        kind: sekData,
        data: move(pending.value),
        weight: pending.weight
      )
      stream.compactQueue()
    elif stream.progressPending:
      stream.progressPending = false
      result.add StreamEvent[T](
        kind: sekProgress,
        completed: stream.progressCompleted,
        total: stream.progressTotal
      )
    elif stream.terminalPending:
      stream.terminalPending = false
      case stream.terminalValue
      of stkEnd:
        result.add StreamEvent[T](kind: sekEnd)
      of stkError:
        result.add StreamEvent[T](
          kind: sekError,
          message: stream.terminalMessage
        )
      of stkCancel:
        result.add StreamEvent[T](kind: sekCancel)
      of stkNone:
        discard
    elif stream.closePending:
      stream.closePending = false
      result.add StreamEvent[T](kind: sekClose)
    else:
      break
