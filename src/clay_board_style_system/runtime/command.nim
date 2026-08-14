import std/[options, tables]

import ../data/[stream_bridge, stream_mailbox]
import ./component

type
  CommandPolicy* = enum
    cpLatestOnly,
    cpOrdered,
    cpConcurrent

  CommandStatus* = enum
    csQueued,
    csRunning,
    csSucceeded,
    csFailed,
    csCancelled

  CommandMessageKind = enum
    cmkSuccess,
    cmkFailure

  CommandMessage[Output, Failure] = object
    runId: uint64
    case kind: CommandMessageKind
    of cmkSuccess:
      output: Output
    of cmkFailure:
      failure: Failure

  CommandTicketState = ref object
    status: CommandStatus

  CommandTicket* = object
    id*: uint64
    owner: pointer
    state: CommandTicketState

  CommandSink*[Output, Failure] = object
    runId: uint64
    producer: StreamProducer[CommandMessage[Output, Failure]]

  CommandCancel* = proc() {.closure, raises: [].}
  CommandExecutor*[Input, Output, Failure] = proc(
    input: Input;
    sink: CommandSink[Output, Failure]
  ): CommandCancel {.closure.}

  CommandSuccessProc*[Output] = proc(output: Output) {.closure.}
  CommandFailureProc*[Failure] = proc(failure: Failure) {.closure.}
  CommandCancelledProc* = proc(ticket: CommandTicket) {.closure, raises: [].}
  CommandRunSettledProc* = proc(
    ticket: CommandTicket;
    status: CommandStatus
  ) {.closure, raises: [].}

  CommandRunSubscription* = object
    id*: uint64
    runId: uint64
    owner: pointer

  CommandRunBinding = object
    id: uint64
    callback: CommandRunSettledProc

  ActiveCommandRun = object
    ticket: CommandTicket
    cancel: CommandCancel

  QueuedCommandRun[Input] = object
    ticket: CommandTicket
    input: Input

  Command*[Input, Output, Failure] = ref object of ComponentOwnedResource
    policyValue: CommandPolicy
    executor: CommandExecutor[Input, Output, Failure]
    mailbox: StreamMailbox[CommandMessage[Output, Failure]]
    bridge: StreamBridge[CommandMessage[Output, Failure]]
    source: StreamProducer[CommandMessage[Output, Failure]]
    activeRuns: Table[uint64, ActiveCommandRun]
    queuedRuns: seq[QueuedCommandRun[Input]]
    queuedHead: int
    nextRunId: uint64
    onSuccessValue: CommandSuccessProc[Output]
    onFailureValue: CommandFailureProc[Failure]
    onCancelledValue: CommandCancelledProc
    runBindings: Table[uint64, seq[CommandRunBinding]]
    nextRunBindingId: uint64

proc status*(ticket: CommandTicket): CommandStatus {.inline.} =
  if ticket.state.isNil: csCancelled else: ticket.state.status

proc valid*(ticket: CommandTicket): bool {.inline.} =
  ticket.id != 0 and not ticket.state.isNil

proc valid*(subscription: CommandRunSubscription): bool {.inline.} =
  subscription.id != 0 and subscription.runId != 0 and
    subscription.owner != nil

proc notifyRunSettled[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    ticket: CommandTicket
) {.raises: [].} =
  if ticket.id notin command.runBindings:
    return
  let bindings = command.runBindings.getOrDefault(ticket.id)
  command.runBindings.del(ticket.id)
  for binding in bindings:
    if binding.callback != nil:
      binding.callback(ticket, ticket.status)

proc observeRun*[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    ticket: CommandTicket;
    callback: CommandRunSettledProc
): CommandRunSubscription =
  if command.isNil:
    raise newException(ValueError, "command cannot be nil")
  if not ticket.valid or ticket.owner != cast[pointer](command):
    raise newException(ValueError, "command ticket does not belong to this command")
  if callback.isNil:
    raise newException(ValueError, "command run observer cannot be nil")
  if ticket.status notin {csQueued, csRunning}:
    callback(ticket, ticket.status)
    return
  if command.disposed:
    raise newException(ValueError, "command is not active")
  if command.nextRunBindingId == 0:
    raise newException(ValueError, "command run observer identifier space exhausted")
  result = CommandRunSubscription(
    id: command.nextRunBindingId,
    runId: ticket.id,
    owner: cast[pointer](command)
  )
  inc command.nextRunBindingId
  var bindings = command.runBindings.getOrDefault(ticket.id)
  bindings.add CommandRunBinding(id: result.id, callback: callback)
  command.runBindings[ticket.id] = move(bindings)

proc unsubscribeRun*[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    subscription: CommandRunSubscription
): bool {.discardable.} =
  if command.isNil or not subscription.valid or
      subscription.owner != cast[pointer](command) or
      subscription.runId notin command.runBindings:
    return false
  var bindings = command.runBindings.getOrDefault(subscription.runId)
  for index, binding in bindings:
    if binding.id == subscription.id:
      bindings.delete(index)
      if bindings.len == 0:
        command.runBindings.del(subscription.runId)
      else:
        command.runBindings[subscription.runId] = move(bindings)
      return true

proc policy*[Input, Output, Failure](
    command: Command[Input, Output, Failure]
): CommandPolicy =
  if command.isNil:
    raise newException(ValueError, "command cannot be nil")
  command.policyValue

proc setOnSuccess*[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    callback: CommandSuccessProc[Output]
) =
  if command.isNil or command.disposed:
    raise newException(ValueError, "command is not active")
  command.onSuccessValue = callback

proc `onSuccess=`*[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    callback: CommandSuccessProc[Output]
) =
  command.setOnSuccess(callback)

proc setOnFailure*[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    callback: CommandFailureProc[Failure]
) =
  if command.isNil or command.disposed:
    raise newException(ValueError, "command is not active")
  command.onFailureValue = callback

proc `onFailure=`*[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    callback: CommandFailureProc[Failure]
) =
  command.setOnFailure(callback)

proc setOnCancelled*[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    callback: CommandCancelledProc
) =
  if command.isNil or command.disposed:
    raise newException(ValueError, "command is not active")
  command.onCancelledValue = callback

proc `onCancelled=`*[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    callback: CommandCancelledProc
) =
  command.setOnCancelled(callback)

proc invokeCancel(active: var ActiveCommandRun) {.raises: [].} =
  let cancel = active.cancel
  active.cancel = nil
  if cancel != nil:
    cancel()

proc cancelActive[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    id: uint64;
    notify: bool
): bool =
  if id notin command.activeRuns:
    return false
  var active = command.activeRuns[id]
  command.activeRuns.del(id)
  active.invokeCancel()
  active.ticket.state.status = csCancelled
  command.notifyRunSettled(active.ticket)
  if notify and command.onCancelledValue != nil:
    command.onCancelledValue(active.ticket)
  true

proc compactQueued[Input, Output, Failure](
    command: Command[Input, Output, Failure]
) =
  if command.queuedHead == command.queuedRuns.len:
    command.queuedRuns.setLen(0)
    command.queuedHead = 0
  elif command.queuedHead >= 64 and
      command.queuedHead * 2 >= command.queuedRuns.len:
    var retained = newSeqOfCap[QueuedCommandRun[Input]](
      command.queuedRuns.len - command.queuedHead
    )
    for index in command.queuedHead ..< command.queuedRuns.len:
      retained.add move(command.queuedRuns[index])
    command.queuedRuns = move(retained)
    command.queuedHead = 0

proc startQueued[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    queued: sink QueuedCommandRun[Input]
)

proc startNextOrdered[Input, Output, Failure](
    command: Command[Input, Output, Failure]
) =
  if command.policyValue != cpOrdered or command.activeRuns.len > 0 or
      command.queuedHead >= command.queuedRuns.len:
    return
  var queued = move(command.queuedRuns[command.queuedHead])
  inc command.queuedHead
  command.compactQueued()
  command.startQueued(move(queued))

proc completeRun[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    message: sink CommandMessage[Output, Failure]
) =
  if message.runId notin command.activeRuns:
    return
  let ticket = command.activeRuns[message.runId].ticket
  command.activeRuns.del(message.runId)
  case message.kind
  of cmkSuccess:
    ticket.state.status = csSucceeded
    let callback = command.onSuccessValue
    command.notifyRunSettled(ticket)
    command.startNextOrdered()
    if callback != nil:
      callback(move(message.output))
  of cmkFailure:
    ticket.state.status = csFailed
    let callback = command.onFailureValue
    command.notifyRunSettled(ticket)
    command.startNextOrdered()
    if callback != nil:
      callback(move(message.failure))

proc releaseCommand[Input, Output, Failure](
    resource: ComponentOwnedResource
) {.raises: [].} =
  let command = Command[Input, Output, Failure](resource)
  for _, active in command.activeRuns.mpairs:
    active.invokeCancel()
    active.ticket.state.status = csCancelled
    command.notifyRunSettled(active.ticket)
  for index in command.queuedHead ..< command.queuedRuns.len:
    command.queuedRuns[index].ticket.state.status = csCancelled
    command.notifyRunSettled(command.queuedRuns[index].ticket)
  command.activeRuns.clear()
  command.queuedRuns.setLen(0)
  command.queuedHead = 0
  if not command.mailbox.isNil:
    discard command.mailbox.dispose()
  if not command.bridge.isNil:
    discard command.bridge.close()
    discard command.bridge.drain()
  command.source = default(StreamProducer[CommandMessage[Output, Failure]])
  command.mailbox = nil
  command.bridge = nil
  command.executor = nil
  command.onSuccessValue = nil
  command.onFailureValue = nil
  command.onCancelledValue = nil
  command.runBindings.clear()

proc initCommand*[Input, Output, Failure](
    executor: CommandExecutor[Input, Output, Failure];
    policy = cpLatestOnly;
    maxPendingCompletions = 256;
    maxPendingWeight = 4'i64 * 1024'i64 * 1024'i64
): Command[Input, Output, Failure] =
  if executor.isNil:
    raise newException(ValueError, "command executor cannot be nil")
  if maxPendingCompletions <= 0 or maxPendingCompletions == high(int):
    raise newException(
      ValueError,
      "command pending completion limit must be positive and finite"
    )
  let mailbox = initStreamMailbox[CommandMessage[Output, Failure]](
    maxPendingCompletions,
    maxPendingWeight
  )
  let bridge = initStreamBridge[CommandMessage[Output, Failure]](
    maxPendingCompletions,
    maxPendingWeight
  )
  let source = mailbox.producer()
  if source.open() != smorAccepted:
    discard mailbox.dispose()
    raise newException(ValueError, "command completion mailbox could not open")
  # Consume the mailbox lifecycle marker during construction. Every later
  # pumped event is one completion, so maxCompletions is an exact bound.
  discard mailbox.pumpInto(bridge)
  discard bridge.drain()
  result = Command[Input, Output, Failure](
    policyValue: policy,
    executor: executor,
    mailbox: mailbox,
    bridge: bridge,
    source: source,
    activeRuns: initTable[uint64, ActiveCommandRun](),
    runBindings: initTable[uint64, seq[CommandRunBinding]](),
    nextRunBindingId: 1,
    nextRunId: 1
  )
  result.setReleaseCallback(releaseCommand[Input, Output, Failure])

proc command*[Input, Output, Failure](
    component: CBSSComponent;
    executor: CommandExecutor[Input, Output, Failure];
    policy = cpLatestOnly;
    maxPendingCompletions = 256;
    maxPendingWeight = 4'i64 * 1024'i64 * 1024'i64
): Command[Input, Output, Failure] =
  if component.isNil:
    raise newException(ComponentContextError, "component cannot be nil")
  result = initCommand(
    executor,
    policy,
    maxPendingCompletions,
    maxPendingWeight
  )
  try:
    discard component.own(result)
  except:
    discard result.dispose()
    raise

proc makeTicket[Input, Output, Failure](
    command: Command[Input, Output, Failure]
): CommandTicket =
  let id = command.nextRunId
  inc command.nextRunId
  if command.nextRunId == 0:
    command.nextRunId = 1
  CommandTicket(
    id: id,
    owner: cast[pointer](command),
    state: CommandTicketState(status: csQueued)
  )

proc startQueued[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    queued: sink QueuedCommandRun[Input]
) =
  queued.ticket.state.status = csRunning
  command.activeRuns[queued.ticket.id] = ActiveCommandRun(ticket: queued.ticket)
  let sink = CommandSink[Output, Failure](
    runId: queued.ticket.id,
    producer: command.source
  )
  try:
    let cancel = command.executor(move(queued.input), sink)
    if queued.ticket.id in command.activeRuns:
      command.activeRuns[queued.ticket.id].cancel = cancel
    elif cancel != nil:
      cancel()
  except:
    if queued.ticket.id in command.activeRuns:
      command.activeRuns.del(queued.ticket.id)
    queued.ticket.state.status = csCancelled
    command.notifyRunSettled(queued.ticket)
    command.startNextOrdered()
    raise

proc run*[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    input: sink Input
): CommandTicket =
  if command.isNil or command.disposed:
    raise newException(ValueError, "command is not active")
  result = command.makeTicket()
  var queued = QueuedCommandRun[Input](ticket: result, input: move(input))

  try:
    case command.policyValue
    of cpLatestOnly:
      var activeIds: seq[uint64]
      for id in command.activeRuns.keys:
        activeIds.add id
      for id in activeIds:
        discard command.cancelActive(id, true)
      for index in command.queuedHead ..< command.queuedRuns.len:
        let pending = command.queuedRuns[index].ticket
        pending.state.status = csCancelled
        command.notifyRunSettled(pending)
        if command.onCancelledValue != nil:
          command.onCancelledValue(pending)
      command.queuedRuns.setLen(0)
      command.queuedHead = 0
      command.startQueued(move(queued))
    of cpOrdered:
      if command.activeRuns.len == 0:
        command.startQueued(move(queued))
      else:
        command.queuedRuns.add move(queued)
    of cpConcurrent:
      command.startQueued(move(queued))
  except:
    result = CommandTicket()
    raise

proc succeed*[Output, Failure](
    target: CommandSink[Output, Failure];
    output: sink Output;
    weight = 1'i64
): StreamMailboxOfferResult =
  target.producer.pushData(
    CommandMessage[Output, Failure](
      kind: cmkSuccess,
      runId: target.runId,
      output: move(output)
    ),
    weight
  )

proc fail*[Output, Failure](
    target: CommandSink[Output, Failure];
    failure: sink Failure;
    weight = 1'i64
): StreamMailboxOfferResult =
  target.producer.pushData(
    CommandMessage[Output, Failure](
      kind: cmkFailure,
      runId: target.runId,
      failure: move(failure)
    ),
    weight
  )

proc cancel*[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    ticket: CommandTicket
): bool {.discardable.} =
  if command.isNil or command.disposed or not ticket.valid or
      ticket.owner != cast[pointer](command):
    return false
  if ticket.id in command.activeRuns:
    discard command.cancelActive(ticket.id, true)
    command.startNextOrdered()
    return true
  for index in command.queuedHead ..< command.queuedRuns.len:
    if command.queuedRuns[index].ticket.id == ticket.id:
      let cancelled = command.queuedRuns[index].ticket
      command.queuedRuns.delete(index)
      cancelled.state.status = csCancelled
      command.notifyRunSettled(cancelled)
      if command.onCancelledValue != nil:
        command.onCancelledValue(cancelled)
      return true

proc cancelAll*[Input, Output, Failure](
    command: Command[Input, Output, Failure]
): int =
  if command.isNil or command.disposed:
    return 0
  while command.activeRuns.len > 0:
    var id: uint64
    for activeId in command.activeRuns.keys:
      id = activeId
      break
    discard command.cancelActive(id, true)
    inc result
  while command.queuedHead < command.queuedRuns.len:
    let ticket = command.queuedRuns[^1].ticket
    command.queuedRuns.setLen(command.queuedRuns.len - 1)
    ticket.state.status = csCancelled
    command.notifyRunSettled(ticket)
    if command.onCancelledValue != nil:
      command.onCancelledValue(ticket)
    inc result
  command.queuedRuns.setLen(0)
  command.queuedHead = 0

proc setWakeCallback*[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    callback: StreamMailboxWakeProc;
    context: pointer = nil
) =
  if command.isNil or command.disposed:
    return
  command.mailbox.setWakeCallback(callback, context)

proc pending*[Input, Output, Failure](
    command: Command[Input, Output, Failure]
): bool =
  not command.isNil and not command.disposed and (
    command.activeRuns.len > 0 or command.queuedRuns.len > 0 or
    command.mailbox.hasPending or command.bridge.hasPending
  )

proc activeCount*[Input, Output, Failure](
  command: Command[Input, Output, Failure]
): int =
  if not command.isNil and not command.disposed:
    result = command.activeRuns.len

proc queuedCount*[Input, Output, Failure](
    command: Command[Input, Output, Failure]
): int =
  if not command.isNil and not command.disposed:
    result = command.queuedRuns.len - command.queuedHead

proc pump*[Input, Output, Failure](
    command: Command[Input, Output, Failure];
    maxCompletions = high(int)
): int =
  if command.isNil or command.disposed or maxCompletions <= 0:
    return 0
  discard command.mailbox.pumpInto(command.bridge, maxCompletions)
  var firstFailure: ref CatchableError
  for event in command.bridge.drain(maxCompletions):
    if event.kind == sekData:
      inc result
      try:
        command.completeRun(event.data)
      except CatchableError as error:
        if firstFailure.isNil:
          firstFailure = error
  if not firstFailure.isNil:
    raise firstFailure
