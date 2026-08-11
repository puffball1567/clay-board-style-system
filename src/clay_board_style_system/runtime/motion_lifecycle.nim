import ../core/node

type
  MotionLifecycleKind* = enum
    mlkAnimationStart,
    mlkAnimationIteration,
    mlkAnimationEnd,
    mlkAnimationCancel,
    mlkTransitionRun,
    mlkTransitionStart,
    mlkTransitionEnd,
    mlkTransitionCancel

  MotionLifecycleEvent* = object
    kind*: MotionLifecycleKind
    node*: NodeId
    name*: string
    elapsedSeconds*: float64
    iteration*: uint64

  MotionLifecycleQueue* = ref object
    events: seq[MotionLifecycleEvent]

proc initMotionLifecycleQueue*(): MotionLifecycleQueue =
  MotionLifecycleQueue()

proc add*(queue: MotionLifecycleQueue; event: MotionLifecycleEvent) =
  if not queue.isNil:
    queue.events.add event

proc take*(queue: MotionLifecycleQueue): seq[MotionLifecycleEvent] =
  if queue.isNil:
    return
  result = move(queue.events)
  queue.events = @[]
