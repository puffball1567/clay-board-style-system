import ./[invalidation, navigation, ui_root]

const defaultNavigationTransitionFrameInterval* = 1.0 / 60.0

type
  NavigationTransitionPhase* = enum
    ntpStarted,
    ntpAdvanced,
    ntpCompleted,
    ntpCancelled

  NavigationTransitionContext*[Destination] = object
    phase*: NavigationTransitionPhase
    kind*: NavigationChangeKind
    previous*: NavigationEntry[Destination]
    current*: NavigationEntry[Destination]
    outgoingRoot*: NodeHandle
    incomingRoot*: NodeHandle
    progress*: float32

  NavigationTransitionHook*[Destination] =
    proc(context: NavigationTransitionContext[Destination]) {.closure.}

  NavigationTransitionSpec*[Destination] = object
    durationSeconds*: float64
    frameIntervalSeconds*: float64
    dirtyDomains*: set[DirtyDomain]
    onTransition*: NavigationTransitionHook[Destination]

proc navigationTransition*[Destination](
    durationSeconds: float64;
    onTransition: NavigationTransitionHook[Destination];
    frameIntervalSeconds = defaultNavigationTransitionFrameInterval;
    dirtyDomains = {ddStyle, ddPaint, ddHit}
): NavigationTransitionSpec[Destination] =
  if durationSeconds <= 0.0:
    raise newException(ValueError, "navigation transition duration must be positive")
  if frameIntervalSeconds <= 0.0:
    raise newException(ValueError, "navigation transition frame interval must be positive")
  if onTransition.isNil:
    raise newException(ValueError, "navigation transition hook must not be nil")
  if dirtyDomains == {}:
    raise newException(ValueError, "navigation transition requires at least one dirty domain")
  NavigationTransitionSpec[Destination](
    durationSeconds: durationSeconds,
    frameIntervalSeconds: frameIntervalSeconds,
    dirtyDomains: dirtyDomains,
    onTransition: onTransition
  )
