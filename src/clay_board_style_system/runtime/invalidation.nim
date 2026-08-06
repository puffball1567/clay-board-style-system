import ../core/dirty_domain

export dirty_domain

type
  InvalidationState* = object
    domains*: set[DirtyDomain]

proc initInvalidationState*(domains: set[DirtyDomain] = {}): InvalidationState =
  InvalidationState(domains: domains)

proc dirty*(state: InvalidationState): bool =
  state.domains != {}

proc markDirty*(state: var InvalidationState; domain: DirtyDomain) =
  state.domains.incl domain

proc markDirty*(state: var InvalidationState; domains: set[DirtyDomain]) =
  state.domains = state.domains + domains

proc clearDirty*(state: var InvalidationState; domain: DirtyDomain) =
  state.domains.excl domain

proc clearDirty*(state: var InvalidationState) =
  state.domains = {}

proc consumeDirty*(state: var InvalidationState): set[DirtyDomain] =
  result = state.domains
  state.clearDirty()

proc consumeDirty*(state: var InvalidationState; domain: DirtyDomain): bool =
  result = domain in state.domains
  state.domains.excl domain

proc needsFrame*(state: InvalidationState): bool =
  state.dirty()

proc needsFullFrameData*(state: InvalidationState): bool =
  ({ddStyle, ddLayout, ddHit, ddResource} * state.domains) != {}

proc needsPaintOnly*(state: InvalidationState): bool =
  state.domains != {} and not state.needsFullFrameData()
