import std/[algorithm, math, options, tables]

import ./component

when not defined(release) or defined(cbssFrontendTrace):
  import ../core/dirty_domain
  import ./frontend_trace
  export frontend_trace

type
  CueJoinPolicy* = enum
    cjpAll,
    cjpAny,
    cjpRace

  CueStartPolicy* = enum
    cspRestart,
    cspIgnore,
    cspQueue,
    cspParallel

  CueSessionStatus* = enum
    cssQueued,
    cssRunning,
    cssSucceeded,
    cssFailed,
    cssCancelled

  CueCancel* = proc() {.closure, raises: [].}

  CueSessionState = ref object
    status: CueSessionStatus
    failure: string

  CueSession* = object
    id*: uint64
    owner: pointer
    state: CueSessionState

  CueRuntime* = ref object of ComponentOwnedResource
    nowValue: float64
    hostNowValue: float64
    rateValue: float64
    pausedValue: bool
    nextSessionId: uint64
    sessions: Table[uint64, ActiveCueSession]
    activeByGraph: Table[pointer, seq[uint64]]
    queuedByGraph: Table[pointer, QueuedCueQueue]
    processing: bool
    when not defined(release) or defined(cbssFrontendTrace):
      traceValue: FrontendTrace

  CueCompletionState = ref object
    owner: pointer
    sessionId: uint64
    stageIndex: int
    branchIndex: int
    settled: bool

  CueCompletion* = object
    state: CueCompletionState

  CueActionExecutor* = proc(completion: CueCompletion): CueCancel {.closure.}

  CueAction* = ref object
    nameValue: string
    executor: CueActionExecutor

  CueBranch* = object
    actionValue: CueAction
    delaySecondsValue: float64

  CueStage* = object
    branches: seq[CueBranch]
    joinPolicy: CueJoinPolicy

  CueGraph* = ref object
    stages: seq[CueStage]
    sealed: bool

  ActiveCueBranch = object
    definition: CueBranch
    completion: CueCompletionState
    cancel: CueCancel
    started: bool
    settled: bool
    succeeded: bool

  ActiveCueSession = ref object
    graph: CueGraph
    ticket: CueSession
    stageIndex: int
    stageStartedAt: float64
    branches: seq[ActiveCueBranch]
    stageOpen: bool
    launchingStage: bool
    settledCount: int
    succeededCount: int
    firstFailure: string

  QueuedCueSession = object
    graph: CueGraph
    ticket: CueSession

  QueuedCueQueue = object
    items: seq[QueuedCueSession]
    head: int

proc process(runtime: CueRuntime)
proc succeed*(completion: CueCompletion)
proc cancel*(runtime: CueRuntime; ticket: CueSession): bool {.discardable.}
proc settle(
    runtime: CueRuntime;
    completion: CueCompletionState;
    succeeded: bool;
    failure: string
)

when not defined(release) or defined(cbssFrontendTrace):
  proc recordTrace(
      runtime: CueRuntime;
      kind: FrontendTraceKind;
      sessionId = 0'u64;
      stageIndex = -1;
      branchIndex = -1;
      name = "";
      revision = 0'u64;
      domains: set[DirtyDomain] = {};
      detail = ""
  ) =
    if runtime.isNil or runtime.traceValue.isNil:
      return
    runtime.traceValue.add FrontendTraceEvent(
      atSeconds: runtime.nowValue,
      kind: kind,
      sessionId: sessionId,
      stageIndex: stageIndex,
      branchIndex: branchIndex,
      name: name,
      revision: revision,
      domains: domains,
      detail: detail
    )

  proc enableTrace*(runtime: CueRuntime; capacity = 2048): FrontendTrace =
    if runtime.isNil or runtime.disposed:
      raise newException(ValueError, "Cue runtime is not active")
    runtime.traceValue = initFrontendTrace(capacity)
    runtime.traceValue

  proc trace*(runtime: CueRuntime): FrontendTrace {.inline.} =
    if runtime.isNil: nil else: runtime.traceValue

  proc disableTrace*(runtime: CueRuntime) =
    if not runtime.isNil:
      runtime.traceValue = nil

  proc traceAdapter*(
      completion: CueCompletion;
      kind: FrontendTraceKind;
      name = "";
      revision = 0'u64;
      domains: set[DirtyDomain] = {};
      detail = ""
  ) =
    if completion.state.isNil or completion.state.owner == nil:
      return
    let state = completion.state
    let runtime = cast[CueRuntime](state.owner)
    runtime.recordTrace(
      kind,
      state.sessionId,
      state.stageIndex,
      state.branchIndex,
      name,
      revision,
      domains,
      detail
    )

  proc traceTrigger*(
      runtime: CueRuntime;
      kind: FrontendTraceKind;
      revision = 0'u64;
      name = ""
  ) =
    runtime.recordTrace(kind, revision = revision, name = name)

proc status*(session: CueSession): CueSessionStatus {.inline.} =
  if session.state.isNil: cssCancelled else: session.state.status

proc failure*(session: CueSession): string {.inline.} =
  if session.state.isNil: "" else: session.state.failure

proc valid*(session: CueSession): bool {.inline.} =
  session.id != 0 and not session.state.isNil

proc name*(action: CueAction): string =
  if action.isNil: "" else: action.nameValue

proc cueAction*(name: string; executor: CueActionExecutor): CueAction =
  if name.len == 0:
    raise newException(ValueError, "Cue action name cannot be empty")
  if executor.isNil:
    raise newException(ValueError, "Cue action executor cannot be nil")
  CueAction(nameValue: name, executor: executor)

proc cueAction*(name: string; run: proc() {.closure.}): CueAction =
  if run.isNil:
    raise newException(ValueError, "Cue action callback cannot be nil")
  cueAction(name, proc(completion: CueCompletion): CueCancel =
    run()
    completion.succeed()
    nil
  )

proc branch*(action: CueAction; delaySeconds = 0.0): CueBranch =
  if action.isNil:
    raise newException(ValueError, "Cue branch action cannot be nil")
  if delaySeconds.classify in {fcNan, fcInf, fcNegInf} or delaySeconds < 0:
    raise newException(ValueError, "Cue branch delay must be finite and non-negative")
  CueBranch(actionValue: action, delaySecondsValue: delaySeconds)

proc cueAfter*(delaySeconds: float64; action: CueAction): CueBranch =
  branch(action, delaySeconds)

proc cue*(first: CueAction): CueGraph =
  CueGraph(stages: @[CueStage(
    branches: @[branch(first)],
    joinPolicy: cjpAll
  )])

proc requireMutable(graph: CueGraph) =
  if graph.isNil:
    raise newException(ValueError, "Cue graph cannot be nil")
  if graph.sealed:
    raise newException(ValueError, "a started Cue graph cannot be modified")

proc then*(graph: CueGraph; action: CueAction): CueGraph {.discardable.} =
  graph.requireMutable()
  graph.stages.add CueStage(branches: @[branch(action)], joinPolicy: cjpAll)
  graph

proc thenStage*(
    graph: CueGraph;
    branches: openArray[CueBranch];
    join = cjpAll
): CueGraph {.discardable.} =
  graph.requireMutable()
  if branches.len == 0:
    raise newException(ValueError, "Cue stage requires at least one branch")
  result = graph
  result.stages.add CueStage(branches: @branches, joinPolicy: join)

proc thenParallel*(
    graph: CueGraph;
    actions: varargs[CueAction]
): CueGraph {.discardable.} =
  var branches = newSeqOfCap[CueBranch](actions.len)
  for action in actions:
    branches.add branch(action)
  graph.thenStage(branches, cjpAll)

proc thenAny*(
    graph: CueGraph;
    actions: varargs[CueAction]
): CueGraph {.discardable.} =
  var branches = newSeqOfCap[CueBranch](actions.len)
  for action in actions:
    branches.add branch(action)
  graph.thenStage(branches, cjpAny)

proc thenRace*(
    graph: CueGraph;
    actions: varargs[CueAction]
): CueGraph {.discardable.} =
  var branches = newSeqOfCap[CueBranch](actions.len)
  for action in actions:
    branches.add branch(action)
  graph.thenStage(branches, cjpRace)

proc succeed*(completion: CueCompletion) =
  if completion.state.isNil or completion.state.settled or
      completion.state.owner == nil:
    return
  let runtime = cast[CueRuntime](completion.state.owner)
  runtime.settle(completion.state, true, "")

proc fail*(completion: CueCompletion; message: string) =
  if message.len == 0:
    raise newException(ValueError, "Cue failure message cannot be empty")
  if completion.state.isNil or completion.state.settled or
      completion.state.owner == nil:
    return
  let runtime = cast[CueRuntime](completion.state.owner)
  runtime.settle(completion.state, false, message)

proc invokeCancel(branch: var ActiveCueBranch) {.raises: [].} =
  let cancel = branch.cancel
  branch.cancel = nil
  if not branch.completion.isNil:
    branch.completion.owner = nil
    branch.completion.settled = true
  if cancel != nil:
    cancel()

proc removeActive(runtime: CueRuntime; graphKey: pointer; sessionId: uint64) =
  if graphKey notin runtime.activeByGraph:
    return
  var ids = runtime.activeByGraph[graphKey]
  for index, id in ids:
    if id == sessionId:
      ids.delete(index)
      break
  if ids.len == 0:
    runtime.activeByGraph.del(graphKey)
  else:
    runtime.activeByGraph[graphKey] = move(ids)

proc compact(queue: var QueuedCueQueue) =
  if queue.head >= queue.items.len:
    queue.items.setLen(0)
    queue.head = 0
  elif queue.head >= 64 and queue.head * 2 >= queue.items.len:
    var retained = newSeqOfCap[QueuedCueSession](queue.items.len - queue.head)
    for index in queue.head ..< queue.items.len:
      retained.add move(queue.items[index])
    queue.items = move(retained)
    queue.head = 0

proc activateQueued(runtime: CueRuntime; graphKey: pointer) =
  if graphKey in runtime.activeByGraph or graphKey notin runtime.queuedByGraph:
    return
  var queue = runtime.queuedByGraph[graphKey]
  while queue.head < queue.items.len and
      queue.items[queue.head].ticket.status != cssQueued:
    inc queue.head
  if queue.head >= queue.items.len:
    runtime.queuedByGraph.del(graphKey)
    return
  let next = queue.items[queue.head]
  queue.items[queue.head] = QueuedCueSession()
  inc queue.head
  queue.compact()
  if queue.head >= queue.items.len:
    runtime.queuedByGraph.del(graphKey)
  else:
    runtime.queuedByGraph[graphKey] = move(queue)
  next.ticket.state.status = cssRunning
  runtime.sessions[next.ticket.id] = ActiveCueSession(
    graph: next.graph,
    ticket: next.ticket
  )
  runtime.activeByGraph[graphKey] = @[next.ticket.id]
  when not defined(release) or defined(cbssFrontendTrace):
    runtime.recordTrace(ftkSessionStarted, next.ticket.id)

proc finishSession(
    runtime: CueRuntime;
    sessionId: uint64;
    status: CueSessionStatus;
    failure = ""
) =
  if sessionId notin runtime.sessions:
    return
  var session = runtime.sessions[sessionId]
  for branch in session.branches.mitems:
    if not branch.settled:
      branch.invokeCancel()
  session.ticket.state.status = status
  session.ticket.state.failure = failure
  when not defined(release) or defined(cbssFrontendTrace):
    let kind = case status
      of cssSucceeded: ftkSessionSucceeded
      of cssFailed: ftkSessionFailed
      of cssCancelled: ftkSessionCancelled
      of cssQueued, cssRunning: ftkSessionCancelled
    runtime.recordTrace(
      kind,
      sessionId,
      session.stageIndex,
      detail = failure
    )
  let graphKey = cast[pointer](session.graph)
  runtime.sessions.del(sessionId)
  runtime.removeActive(graphKey, sessionId)
  runtime.activateQueued(graphKey)

proc evaluateStage(runtime: CueRuntime; sessionId: uint64): bool =
  if sessionId notin runtime.sessions:
    return
  var session = runtime.sessions[sessionId]
  if not session.stageOpen or session.launchingStage:
    return
  let total = session.branches.len
  var advance = false
  var failSession = false
  case session.graph.stages[session.stageIndex].joinPolicy
  of cjpAll:
    failSession = session.settledCount > session.succeededCount
    advance = session.settledCount == total and session.succeededCount == total
  of cjpAny:
    advance = session.succeededCount > 0
    failSession = session.settledCount == total and session.succeededCount == 0
  of cjpRace:
    if session.settledCount > 0:
      advance = session.succeededCount > 0
      failSession = not advance

  if not advance and not failSession:
    return
  result = true
  session.stageOpen = false
  for branch in session.branches.mitems:
    if not branch.settled:
      branch.invokeCancel()
      branch.settled = true
  runtime.sessions[sessionId] = session
  if failSession:
    when not defined(release) or defined(cbssFrontendTrace):
      runtime.recordTrace(
        ftkStageFailed,
        sessionId,
        session.stageIndex,
        detail = session.firstFailure
      )
    runtime.finishSession(sessionId, cssFailed, session.firstFailure)
  else:
    when not defined(release) or defined(cbssFrontendTrace):
      runtime.recordTrace(ftkStageSucceeded, sessionId, session.stageIndex)
    var updated = runtime.sessions[sessionId]
    inc updated.stageIndex
    updated.branches.setLen(0)
    runtime.sessions[sessionId] = updated

proc startBranch(
    runtime: CueRuntime;
    sessionId: uint64;
    expectedStage: int;
    branchIndex: int
) =
  if sessionId notin runtime.sessions:
    return
  var session = runtime.sessions[sessionId]
  if session.stageIndex != expectedStage or not session.stageOpen or
      branchIndex < 0 or branchIndex >= session.branches.len or
      session.branches[branchIndex].started:
    return
  session.branches[branchIndex].started = true
  let completionState = CueCompletionState(
    owner: cast[pointer](runtime),
    sessionId: sessionId,
    stageIndex: session.stageIndex,
    branchIndex: branchIndex
  )
  session.branches[branchIndex].completion = completionState
  let action = session.branches[branchIndex].definition.actionValue
  runtime.sessions[sessionId] = session
  when not defined(release) or defined(cbssFrontendTrace):
    runtime.recordTrace(
      ftkActionStarted,
      sessionId,
      expectedStage,
      branchIndex,
      action.name
    )
  try:
    let cancel = action.executor(CueCompletion(state: completionState))
    if sessionId in runtime.sessions:
      var current = runtime.sessions[sessionId]
      if branchIndex < current.branches.len and
          current.branches[branchIndex].completion == completionState and
          not current.branches[branchIndex].settled:
        current.branches[branchIndex].cancel = cancel
        runtime.sessions[sessionId] = current
  except CatchableError as error:
    runtime.settle(completionState, false, error.msg)

proc openStage(runtime: CueRuntime; sessionId: uint64) =
  if sessionId notin runtime.sessions:
    return
  var session = runtime.sessions[sessionId]
  if session.stageIndex >= session.graph.stages.len:
    runtime.finishSession(sessionId, cssSucceeded)
    return
  let stage = session.graph.stages[session.stageIndex]
  session.stageStartedAt = runtime.nowValue
  session.stageOpen = true
  session.launchingStage = true
  session.settledCount = 0
  session.succeededCount = 0
  session.firstFailure = ""
  session.branches = newSeqOfCap[ActiveCueBranch](stage.branches.len)
  for definition in stage.branches:
    session.branches.add ActiveCueBranch(definition: definition)
  runtime.sessions[sessionId] = session
  when not defined(release) or defined(cbssFrontendTrace):
    runtime.recordTrace(ftkStageStarted, sessionId, session.stageIndex)
  for index, definition in stage.branches:
    if sessionId notin runtime.sessions or
        runtime.sessions[sessionId].stageIndex != session.stageIndex or
        not runtime.sessions[sessionId].stageOpen:
      break
    if definition.delaySecondsValue == 0:
      runtime.startBranch(sessionId, session.stageIndex, index)
  if sessionId in runtime.sessions and
      runtime.sessions[sessionId].stageIndex == session.stageIndex:
    var opened = runtime.sessions[sessionId]
    opened.launchingStage = false
    runtime.sessions[sessionId] = opened
    discard runtime.evaluateStage(sessionId)

proc process(runtime: CueRuntime) =
  if runtime.isNil or runtime.disposed or runtime.processing:
    return
  runtime.processing = true
  try:
    var changed = true
    while changed:
      changed = false
      var ids: seq[uint64]
      for id in runtime.sessions.keys:
        ids.add id
      ids.sort()
      for id in ids:
        if id notin runtime.sessions:
          continue
        let beforeStage = runtime.sessions[id].stageIndex
        if not runtime.sessions[id].stageOpen:
          runtime.openStage(id)
          changed = true
        if id notin runtime.sessions:
          continue
        let session = runtime.sessions[id]
        let expectedStage = session.stageIndex
        var dueBranches: seq[int]
        for index, active in session.branches:
          if not active.started and
              runtime.nowValue >= session.stageStartedAt +
                active.definition.delaySecondsValue:
            dueBranches.add index
        for index in dueBranches:
          if id in runtime.sessions and
              runtime.sessions[id].stageIndex == expectedStage:
            runtime.sessions[id].launchingStage = true
          runtime.startBranch(id, expectedStage, index)
          changed = true
        if dueBranches.len > 0 and id in runtime.sessions and
            runtime.sessions[id].stageIndex == expectedStage:
          runtime.sessions[id].launchingStage = false
          discard runtime.evaluateStage(id)
        if id in runtime.sessions:
          discard runtime.evaluateStage(id)
          if id notin runtime.sessions or
              runtime.sessions[id].stageIndex != beforeStage:
            changed = true
  finally:
    runtime.processing = false

proc settle(
    runtime: CueRuntime;
    completion: CueCompletionState;
    succeeded: bool;
    failure: string
) =
  if runtime.isNil or runtime.disposed or completion.isNil or
      completion.settled or completion.owner != cast[pointer](runtime) or
      completion.sessionId notin runtime.sessions:
    return
  var session = runtime.sessions[completion.sessionId]
  if session.stageIndex != completion.stageIndex or
      completion.branchIndex < 0 or completion.branchIndex >= session.branches.len or
      session.branches[completion.branchIndex].completion != completion:
    completion.owner = nil
    completion.settled = true
    return
  completion.settled = true
  completion.owner = nil
  session.branches[completion.branchIndex].settled = true
  session.branches[completion.branchIndex].succeeded = succeeded
  session.branches[completion.branchIndex].cancel = nil
  when not defined(release) or defined(cbssFrontendTrace):
    runtime.recordTrace(
      if succeeded: ftkActionSucceeded else: ftkActionFailed,
      completion.sessionId,
      completion.stageIndex,
      completion.branchIndex,
      session.branches[completion.branchIndex].definition.actionValue.name,
      detail = failure
    )
  inc session.settledCount
  if succeeded:
    inc session.succeededCount
  elif session.firstFailure.len == 0:
    if failure.len > 0:
      session.firstFailure = failure
    else:
      session.firstFailure = "Cue action failed: " &
        session.branches[completion.branchIndex].definition.actionValue.name
  runtime.sessions[completion.sessionId] = session
  if runtime.evaluateStage(completion.sessionId):
    runtime.process()

proc releaseCueRuntime(resource: ComponentOwnedResource) {.raises: [].} =
  let runtime = CueRuntime(resource)
  for _, session in runtime.sessions.mpairs:
    when not defined(release) or defined(cbssFrontendTrace):
      runtime.recordTrace(
        ftkSessionCancelled,
        session.ticket.id,
        session.stageIndex,
        detail = "Cue runtime was disposed"
      )
    for branch in session.branches.mitems:
      if not branch.settled:
        branch.invokeCancel()
    session.ticket.state.status = cssCancelled
  for _, queue in runtime.queuedByGraph.mpairs:
    for index in queue.head ..< queue.items.len:
      when not defined(release) or defined(cbssFrontendTrace):
        runtime.recordTrace(
          ftkSessionCancelled,
          queue.items[index].ticket.id,
          detail = "Cue runtime was disposed"
        )
      queue.items[index].ticket.state.status = cssCancelled
  runtime.sessions.clear()
  runtime.activeByGraph.clear()
  runtime.queuedByGraph.clear()

proc initCueRuntime*(initialTime = 0.0): CueRuntime =
  if initialTime.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "Cue runtime time must be finite")
  result = CueRuntime(
    nowValue: initialTime,
    hostNowValue: initialTime,
    rateValue: 1.0,
    nextSessionId: 1,
    sessions: initTable[uint64, ActiveCueSession](),
    activeByGraph: initTable[pointer, seq[uint64]](),
    queuedByGraph: initTable[pointer, QueuedCueQueue]()
  )
  result.setReleaseCallback(releaseCueRuntime)

proc cueRuntime*(component: CBSSComponent; initialTime = 0.0): CueRuntime =
  if component.isNil:
    raise newException(ComponentContextError, "component cannot be nil")
  result = initCueRuntime(initialTime)
  try:
    discard component.own(result)
  except:
    discard result.dispose()
    raise

proc makeSession(runtime: CueRuntime; status: CueSessionStatus): CueSession =
  if runtime.nextSessionId == 0:
    raise newException(ValueError, "Cue session identifier space exhausted")
  result = CueSession(
    id: runtime.nextSessionId,
    owner: cast[pointer](runtime),
    state: CueSessionState(status: status)
  )
  inc runtime.nextSessionId

proc start*(
    runtime: CueRuntime;
    graph: CueGraph;
    policy = cspRestart
): CueSession =
  if runtime.isNil or runtime.disposed:
    raise newException(ValueError, "Cue runtime is not active")
  if graph.isNil or graph.stages.len == 0:
    raise newException(ValueError, "Cue graph cannot be empty")
  graph.sealed = true
  let graphKey = cast[pointer](graph)
  let active = runtime.activeByGraph.getOrDefault(graphKey)
  case policy
  of cspIgnore:
    if active.len > 0 and active[0] in runtime.sessions:
      return runtime.sessions[active[0]].ticket
  of cspRestart:
    if graphKey in runtime.queuedByGraph:
      var queue = runtime.queuedByGraph[graphKey]
      for index in queue.head ..< queue.items.len:
        queue.items[index].ticket.state.status = cssCancelled
        when not defined(release) or defined(cbssFrontendTrace):
          runtime.recordTrace(
            ftkSessionCancelled,
            queue.items[index].ticket.id,
            detail = "Cue session was replaced"
          )
      runtime.queuedByGraph.del(graphKey)
    for id in active:
      discard runtime.cancel(CueSession(
        id: id,
        owner: cast[pointer](runtime),
        state: if id in runtime.sessions: runtime.sessions[id].ticket.state else: nil
      ))
  of cspQueue:
    if active.len > 0:
      result = runtime.makeSession(cssQueued)
      var queue = runtime.queuedByGraph.getOrDefault(graphKey)
      queue.items.add QueuedCueSession(graph: graph, ticket: result)
      runtime.queuedByGraph[graphKey] = move(queue)
      when not defined(release) or defined(cbssFrontendTrace):
        runtime.recordTrace(ftkSessionQueued, result.id)
      return
  of cspParallel:
    discard

  result = runtime.makeSession(cssRunning)
  runtime.sessions[result.id] = ActiveCueSession(graph: graph, ticket: result)
  var ids = runtime.activeByGraph.getOrDefault(graphKey)
  ids.add result.id
  runtime.activeByGraph[graphKey] = move(ids)
  when not defined(release) or defined(cbssFrontendTrace):
    runtime.recordTrace(ftkSessionStarted, result.id)
  runtime.process()

proc cancel*(runtime: CueRuntime; ticket: CueSession): bool {.discardable.} =
  if runtime.isNil or runtime.disposed or not ticket.valid or
      ticket.owner != cast[pointer](runtime):
    return false
  if ticket.id in runtime.sessions:
    runtime.finishSession(ticket.id, cssCancelled)
    runtime.process()
    return true
  var queuedGraphKey: pointer = nil
  for graphKey, queue in runtime.queuedByGraph.mpairs:
    for index in queue.head ..< queue.items.len:
      if queue.items[index].ticket.id == ticket.id and
          queue.items[index].ticket.status == cssQueued:
        queuedGraphKey = graphKey
        ticket.state.status = cssCancelled
        when not defined(release) or defined(cbssFrontendTrace):
          runtime.recordTrace(ftkSessionCancelled, ticket.id)
        queue.items[index] = QueuedCueSession()
        break
    if queuedGraphKey != nil:
      break
  if queuedGraphKey != nil:
    return true

proc tick*(runtime: CueRuntime; nowSeconds: float64) =
  if runtime.isNil or runtime.disposed:
    return
  if nowSeconds.classify in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "Cue runtime time must be finite")
  if nowSeconds < runtime.hostNowValue:
    raise newException(ValueError, "Cue runtime time must be monotonic")
  let elapsed = nowSeconds - runtime.hostNowValue
  runtime.hostNowValue = nowSeconds
  if not runtime.pausedValue:
    runtime.nowValue += elapsed * runtime.rateValue
    runtime.process()

proc now*(runtime: CueRuntime): float64 =
  if runtime.isNil: 0.0 else: runtime.nowValue

proc paused*(runtime: CueRuntime): bool {.inline.} =
  not runtime.isNil and runtime.pausedValue

proc pause*(runtime: CueRuntime) =
  if not runtime.isNil and not runtime.disposed:
    runtime.pausedValue = true

proc resume*(runtime: CueRuntime) =
  if not runtime.isNil and not runtime.disposed:
    runtime.pausedValue = false

proc rate*(runtime: CueRuntime): float64 {.inline.} =
  if runtime.isNil: 1.0 else: runtime.rateValue

proc setRate*(runtime: CueRuntime; value: float64) =
  if runtime.isNil or runtime.disposed:
    raise newException(ValueError, "Cue runtime is not active")
  if value.classify in {fcNan, fcInf, fcNegInf} or value <= 0:
    raise newException(ValueError, "Cue runtime rate must be finite and positive")
  runtime.rateValue = value

proc nextDeadline*(runtime: CueRuntime): Option[float64] =
  if runtime.isNil or runtime.disposed or runtime.pausedValue:
    return none(float64)
  var logicalDeadline = none(float64)
  for session in runtime.sessions.values:
    if session.stageOpen:
      for branch in session.branches:
        if not branch.started:
          let deadline = session.stageStartedAt + branch.definition.delaySecondsValue
          if logicalDeadline.isNone or deadline < logicalDeadline.get:
            logicalDeadline = some(deadline)
  if logicalDeadline.isSome:
    let remaining = max(0.0, logicalDeadline.get - runtime.nowValue)
    result = some(runtime.hostNowValue + remaining / runtime.rateValue)

proc activeCount*(runtime: CueRuntime): int =
  if not runtime.isNil and not runtime.disposed:
    result = runtime.sessions.len
