import std/[atomics, locks, options]

import clay_board_style_system/data/stream_bridge

type
  ## Result of a non-blocking producer offer. Producers should pause or retry
  ## only after `smorBackpressure`; other failures are terminal for that offer.
  StreamMailboxOfferResult* = enum
    smorAccepted,
    smorBackpressure,
    smorInvalidState,
    smorDisposed

  ## Signals the host event loop that UI-thread pumping is required. The
  ## callback must only post a wake signal; it must not re-enter or dispose the
  ## mailbox. CBSS waits for an in-flight callback before disposal returns.
  StreamMailboxWakeProc* = proc(context: pointer) {.cdecl, gcsafe, raises: [].}

  StreamMailboxPumpResult* = object
    processed*: int
    rejected*: int
    changed*: bool
    backpressured*: bool
    pending*: bool

  StreamMailboxShared[T] = object
    references: Atomic[int]
    gate: Lock
    channel: Channel[StreamEvent[T]]
    maxQueuedItems: int
    maxQueuedWeight: int64
    queuedItems: int
    queuedWeight: int64
    state: StreamState
    disposed: bool
    wakePending: bool
    wakeCallbacksInFlight: int
    wakeIdle: Cond
    wakeCallback: StreamMailboxWakeProc
    wakeContext: pointer

  StreamMailboxHandle[T] = object
    shared: ptr StreamMailboxShared[T]

  StreamProducer*[T] = object
    handle: StreamMailboxHandle[T]

  StreamMailboxOwner[T] = object
    handle: StreamMailboxHandle[T]

  StreamMailbox*[T] = ref object
    owner: StreamMailboxOwner[T]
    deferred: StreamEvent[T]
    hasDeferred: bool

proc releaseShared[T](shared: ptr StreamMailboxShared[T])
proc disposeShared[T](shared: ptr StreamMailboxShared[T]): bool

proc retainShared[T](shared: ptr StreamMailboxShared[T]) {.inline.} =
  if shared != nil:
    discard shared.references.fetchAdd(1, moRelaxed)

proc `=destroy`[T](handle: var StreamMailboxHandle[T]) =
  let shared = handle.shared
  handle.shared = nil
  if shared != nil:
    releaseShared(shared)

proc `=copy`[T](destination: var StreamMailboxHandle[T];
                source: StreamMailboxHandle[T]) =
  if destination.shared == source.shared:
    return
  retainShared(source.shared)
  `=destroy`(destination)
  destination.shared = source.shared

proc `=sink`[T](destination: var StreamMailboxHandle[T];
                source: StreamMailboxHandle[T]) =
  `=destroy`(destination)
  destination.shared = source.shared

proc `=destroy`[T](owner: var StreamMailboxOwner[T]) =
  if owner.handle.shared != nil:
    discard disposeShared(owner.handle.shared)
  `=destroy`(owner.handle)

proc releaseShared[T](shared: ptr StreamMailboxShared[T]) =
  if shared.references.fetchSub(1, moAcquireRelease) != 1:
    return

  while true:
    let received = shared.channel.tryRecv()
    if not received.dataAvailable:
      break
  shared.channel.close()
  deinitCond(shared.wakeIdle)
  deinitLock(shared.gate)
  deallocShared(shared)

proc initStreamMailbox*[T](
    maxQueuedItems = 64;
    maxQueuedWeight = 4'i64 * 1024'i64 * 1024'i64
): StreamMailbox[T] =
  if maxQueuedItems <= 0:
    raise newException(ValueError, "stream mailbox item limit must be positive")
  if maxQueuedWeight <= 0:
    raise newException(ValueError, "stream mailbox weight limit must be positive")

  let shared = cast[ptr StreamMailboxShared[T]](
    allocShared0(sizeof(StreamMailboxShared[T]))
  )
  shared.references.store(1, moRelaxed)
  initLock(shared.gate)
  initCond(shared.wakeIdle)
  shared.channel.open(maxQueuedItems)
  shared.maxQueuedItems = maxQueuedItems
  shared.maxQueuedWeight = maxQueuedWeight
  shared.state = ssIdle

  result = StreamMailbox[T](
    owner: StreamMailboxOwner[T](
      handle: StreamMailboxHandle[T](shared: shared)
    )
  )

proc producer*[T](mailbox: StreamMailbox[T]): StreamProducer[T] =
  ## Returns a lightweight, atomically retained producer handle. The handle may
  ## cross a thread boundary; the mailbox itself remains UI-thread-owned.
  if mailbox.isNil or mailbox.owner.handle.shared == nil:
    return
  result.handle = mailbox.owner.handle

proc invokeWake(
    callback: StreamMailboxWakeProc;
    context: pointer
) {.inline.} =
  if callback != nil:
    callback(context)

proc finishWake[T](shared: ptr StreamMailboxShared[T]) =
  acquire(shared.gate)
  try:
    dec shared.wakeCallbacksInFlight
    if shared.wakeCallbacksInFlight == 0:
      signal(shared.wakeIdle)
  finally:
    release(shared.gate)

proc offerEvent[T](
    producer: StreamProducer[T];
    event: sink StreamEvent[T];
    allowedStates: set[StreamState];
    nextState: StreamState;
    changesState: bool;
    weight: int64
): StreamMailboxOfferResult =
  let shared = producer.handle.shared
  if shared == nil:
    return smorDisposed

  var callback: StreamMailboxWakeProc
  var context: pointer
  acquire(shared.gate)
  try:
    if shared.disposed:
      return smorDisposed
    if shared.state notin allowedStates:
      return smorInvalidState
    if shared.queuedItems >= shared.maxQueuedItems or
        weight > shared.maxQueuedWeight or
        shared.queuedWeight > shared.maxQueuedWeight - weight:
      return smorBackpressure
    if not shared.channel.trySend(move(event)):
      return smorBackpressure

    inc shared.queuedItems
    shared.queuedWeight += weight
    if changesState:
      shared.state = nextState
    if not shared.wakePending and shared.wakeCallback != nil:
      shared.wakePending = true
      inc shared.wakeCallbacksInFlight
      callback = shared.wakeCallback
      context = shared.wakeContext
    result = smorAccepted
  finally:
    release(shared.gate)

  if callback != nil:
    invokeWake(callback, context)
    finishWake(shared)

proc open*[T](producer: StreamProducer[T]): StreamMailboxOfferResult =
  producer.offerEvent(
    StreamEvent[T](kind: sekOpen),
    {ssIdle},
    ssOpen,
    true,
    0
  )

proc pushData*[T](
    producer: StreamProducer[T];
    value: sink T;
    weight: int64
): StreamMailboxOfferResult =
  if weight < 0:
    raise newException(ValueError, "stream data weight cannot be negative")
  producer.offerEvent(
    StreamEvent[T](kind: sekData, data: move(value), weight: weight),
    {ssOpen},
    ssOpen,
    false,
    weight
  )

proc reportProgress*[T](
    producer: StreamProducer[T];
    completed: uint64;
    total = none(uint64)
): StreamMailboxOfferResult =
  if total.isSome and completed > total.get:
    raise newException(ValueError, "stream progress exceeds its total")
  producer.offerEvent(
    StreamEvent[T](kind: sekProgress, completed: completed, total: total),
    {ssOpen},
    ssOpen,
    false,
    0
  )

proc finish*[T](producer: StreamProducer[T]): StreamMailboxOfferResult =
  producer.offerEvent(
    StreamEvent[T](kind: sekEnd),
    {ssOpen},
    ssEnded,
    true,
    0
  )

proc fail*[T](
    producer: StreamProducer[T];
    message: string
): StreamMailboxOfferResult =
  if message.len == 0:
    raise newException(ValueError, "stream error message cannot be empty")
  producer.offerEvent(
    StreamEvent[T](kind: sekError, message: message),
    {ssOpen},
    ssFailed,
    true,
    0
  )

proc cancel*[T](producer: StreamProducer[T]): StreamMailboxOfferResult =
  producer.offerEvent(
    StreamEvent[T](kind: sekCancel),
    {ssIdle, ssOpen},
    ssCancelled,
    true,
    0
  )

proc close*[T](producer: StreamProducer[T]): StreamMailboxOfferResult =
  producer.offerEvent(
    StreamEvent[T](kind: sekClose),
    {ssIdle, ssOpen, ssEnded, ssFailed, ssCancelled},
    ssClosed,
    true,
    0
  )

proc state*[T](producer: StreamProducer[T]): StreamState =
  let shared = producer.handle.shared
  if shared == nil:
    return ssClosed
  acquire(shared.gate)
  try:
    if shared.disposed:
      result = ssClosed
    else:
      result = shared.state
  finally:
    release(shared.gate)

proc queuedItems*[T](mailbox: StreamMailbox[T]): int =
  if mailbox.isNil or mailbox.owner.handle.shared == nil:
    return 0
  let shared = mailbox.owner.handle.shared
  acquire(shared.gate)
  try:
    result = shared.queuedItems
  finally:
    release(shared.gate)

proc queuedWeight*[T](mailbox: StreamMailbox[T]): int64 =
  if mailbox.isNil or mailbox.owner.handle.shared == nil:
    return 0
  let shared = mailbox.owner.handle.shared
  acquire(shared.gate)
  try:
    result = shared.queuedWeight
  finally:
    release(shared.gate)

proc hasPending*[T](mailbox: StreamMailbox[T]): bool =
  mailbox.queuedItems > 0

proc setWakeCallback*[T](
    mailbox: StreamMailbox[T];
    callback: StreamMailboxWakeProc;
    context: pointer = nil
) =
  if mailbox.isNil or mailbox.owner.handle.shared == nil:
    return
  let shared = mailbox.owner.handle.shared
  var callbackNow: StreamMailboxWakeProc
  var contextNow: pointer
  acquire(shared.gate)
  try:
    if shared.disposed:
      return
    # Replacing or clearing the callback transfers ownership of the old raw
    # context back to the caller. Do not return while that context is still in
    # use by a worker callback.
    while shared.wakeCallbacksInFlight > 0:
      wait(shared.wakeIdle, shared.gate)
      if shared.disposed:
        return
    shared.wakeCallback = callback
    shared.wakeContext = context
    shared.wakePending = false
    if callback != nil and (shared.queuedItems > 0 or mailbox.hasDeferred):
      shared.wakePending = true
      inc shared.wakeCallbacksInFlight
      callbackNow = callback
      contextNow = context
  finally:
    release(shared.gate)
  if callbackNow != nil:
    invokeWake(callbackNow, contextNow)
    finishWake(shared)

proc disposeShared[T](shared: ptr StreamMailboxShared[T]): bool =
  if shared == nil:
    return false
  acquire(shared.gate)
  try:
    if shared.disposed:
      return false
    shared.disposed = true
    shared.state = ssClosed
    shared.wakeCallback = nil
    shared.wakeContext = nil
    shared.wakePending = false
    while shared.wakeCallbacksInFlight > 0:
      wait(shared.wakeIdle, shared.gate)
    result = true
  finally:
    release(shared.gate)

  if result:
    while true:
      let received = shared.channel.tryRecv()
      if not received.dataAvailable:
        break
    acquire(shared.gate)
    try:
      shared.queuedItems = 0
      shared.queuedWeight = 0
    finally:
      release(shared.gate)

proc dispose*[T](mailbox: StreamMailbox[T]): bool =
  if mailbox.isNil or mailbox.owner.handle.shared == nil:
    return false
  result = disposeShared(mailbox.owner.handle.shared)
  mailbox.hasDeferred = false
  reset(mailbox.deferred)

proc releaseProcessed[T](
    shared: ptr StreamMailboxShared[T];
    event: StreamEvent[T]
) =
  acquire(shared.gate)
  try:
    dec shared.queuedItems
    if event.kind == sekData:
      shared.queuedWeight -= event.weight
  finally:
    release(shared.gate)

proc applyEvent[T](
    stream: StreamBridge[T];
    event: var StreamEvent[T]
): tuple[accepted: bool, backpressured: bool] =
  case event.kind
  of sekOpen:
    result.accepted = stream.open()
  of sekData:
    case stream.canPushData(event.weight)
    of sorAccepted:
      result.accepted =
        stream.pushData(move(event.data), event.weight) == sorAccepted
    of sorBackpressure:
      result.backpressured = true
    of sorNotOpen:
      discard
  of sekProgress:
    result.accepted = stream.reportProgress(event.completed, event.total)
  of sekEnd:
    result.accepted = stream.finish()
  of sekError:
    result.accepted = stream.fail(event.message)
  of sekCancel:
    result.accepted = stream.cancel()
  of sekClose:
    result.accepted = stream.close()

proc pumpInto*[T](
    mailbox: StreamMailbox[T];
    stream: StreamBridge[T];
    maxMessages = high(int)
): StreamMailboxPumpResult =
  ## Transfers at most `maxMessages` into the UI-thread StreamBridge. A data
  ## value rejected by bridge backpressure stays owned by the mailbox and is
  ## retried without copying or loss on the next call.
  if mailbox.isNil or stream.isNil or maxMessages <= 0 or
      mailbox.owner.handle.shared == nil:
    return
  let shared = mailbox.owner.handle.shared
  let initialRevision = stream.revision

  while result.processed < maxMessages:
    var event: StreamEvent[T]
    if mailbox.hasDeferred:
      event = move(mailbox.deferred)
      mailbox.hasDeferred = false
    else:
      var received = shared.channel.tryRecv()
      if not received.dataAvailable:
        break
      event = move(received.msg)

    let applied = stream.applyEvent(event)
    if applied.backpressured:
      mailbox.deferred = move(event)
      mailbox.hasDeferred = true
      result.backpressured = true
      break
    releaseProcessed(shared, event)
    inc result.processed
    if not applied.accepted:
      inc result.rejected

  acquire(shared.gate)
  try:
    result.pending = mailbox.hasDeferred or shared.queuedItems > 0
    if not result.pending:
      shared.wakePending = false
  finally:
    release(shared.gate)
  result.changed = stream.revision != initialRevision
