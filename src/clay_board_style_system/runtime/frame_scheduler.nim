import std/[math, options]

import ./invalidation

type
  FrameScheduler* = object
    invalidation*: InvalidationState
    nextDeadline*: Option[float64]

proc initFrameScheduler*(
    initialDomains: set[DirtyDomain] = {}
): FrameScheduler =
  FrameScheduler(
    invalidation: initInvalidationState(initialDomains),
    nextDeadline: none(float64)
  )

proc markDirty*(scheduler: var FrameScheduler; domain: DirtyDomain) =
  scheduler.invalidation.markDirty(domain)

proc markDirty*(scheduler: var FrameScheduler; domains: set[DirtyDomain]) =
  scheduler.invalidation.markDirty(domains)

proc consumeDirty*(scheduler: var FrameScheduler): set[DirtyDomain] =
  scheduler.invalidation.consumeDirty()

proc clearDeadline*(scheduler: var FrameScheduler) =
  scheduler.nextDeadline = none(float64)

proc requestDeadline*(scheduler: var FrameScheduler; deadline: float64) =
  ## Multiple runtime features may request a wake-up. The event loop only
  ## needs the earliest monotonic deadline.
  if scheduler.nextDeadline.isNone or deadline < scheduler.nextDeadline.get:
    scheduler.nextDeadline = some(deadline)

proc waitTimeoutMs*(scheduler: FrameScheduler; now: float64): int =
  ## Returns -1 for an indefinite event wait, 0 for immediately runnable work,
  ## or a positive timeout rounded up so a deadline is not fired early.
  if scheduler.invalidation.needsFrame():
    return 0
  if scheduler.nextDeadline.isNone:
    return -1
  max(0, int(ceil((scheduler.nextDeadline.get - now) * 1000.0)))

proc deadlineDue*(scheduler: FrameScheduler; now: float64): bool =
  scheduler.nextDeadline.isSome and now >= scheduler.nextDeadline.get
