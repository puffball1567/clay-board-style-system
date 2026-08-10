# Declarative Motion

CBSS uses one monotonic animation clock for imperative component motion,
declarative style transitions, and declaration-bound keyframes. Motion
requests frames only while work is active. A static application returns to the
event-driven wait loop.

## Declarative Transitions

The runtime consumes these existing declarations:

```nim
let resting = uiStyle([
  decl("opacity", number(0.65)),
  decl("background-color", colorValue(hexColor("#334155"))),
  decl("transition-property", keyword("opacity, background-color")),
  decl("transition-duration", number(0.18)),
  decl("transition-delay", number(0)),
  decl("transition-timing-function", keyword("ease-out"))
])

let active = uiStyle([
  decl("opacity", number(1)),
  decl("background-color", colorValue(hexColor("#0ea5e9")))
])
```

Supported runtime properties are:

- `opacity`;
- `color`;
- `background-color`;
- typed 2D `transform` operation lists; and
- individual `translate`, `scale`, and `rotate` values.

Named timing functions, `step-start`, `step-end`, and valid
`cubic-bezier(...)` values are supported. Negative delays begin partway through
the active interval. Comma-separated property, duration, delay, timing, and
behavior lists use CSS-like index cycling. Unknown property names retain their
position, and the last `transition-property` entry matching a property supplies
its parameters. Color transitions use prepared Oklab interpolation.

Typed list helpers avoid constructing the comma-separated representation by
hand:

```nim
let motion = uiStyle([
  transitionProperties("opacity", "background-color"),
  transitionDurations(0.12'f32, 0.3'f32),
  transitionDelays(0.0'f32),
  transitionTimingFunctions("ease-out", "cubic-bezier(0.2, 0.8, 0.4, 1)"),
  transitionBehaviors(tbNormal)
])
```

The runtime is keyed by stable `NodeId` and property. Reversing a transition
starts from the currently displayed value, reconciling an unchanged target
does not restart it, and disposing a subtree removes its tracks. Reduced-motion
mode applies the target without retaining nonessential motion.

## Host Contract

Style resolution happens once when authored or state-derived style changes.
The host then reconciles the previously displayed and newly resolved trees:

```nim
var targetStyles = resolveTreeStyles(...)
ui.reconcileStyleTransitions(displayedStyles, targetStyles, nowSeconds)
ui.reconcileStyleAnimations(targetStyles, nowSeconds)
displayedStyles = targetStyles
discard ui.applyStyleTransitions(displayedStyles, scheduler, nowSeconds)
discard ui.applyStyleAnimations(displayedStyles, scheduler, nowSeconds)
```

On later animation deadlines, the host calls only `applyStyleTransitions` and
`applyStyleAnimations`, then rebuilds affected paint output. Transform tracks
also request a hit-region rebuild. The host must not resolve the full style
tree or run layout merely to sample these tracks. Sampling cost is proportional
to active tracks, not total tree size.

`CbssTestDriver.refresh()` performs the reconciliation automatically.
`advanceTime(seconds)` advances transition and keyframe presentation
deterministically without re-resolving style or layout; it rebuilds hit regions
only when active transform motion requests `ddHit`.

## Declarative Keyframes

Named keyframes are registered as typed Nim values and selected through the
existing `animation-*` declarations:

```nim
ui.registerStyleKeyframes(styleKeyframes("pulse", [
  styleKeyframe(0, [decl("opacity", number(0.4))]),
  styleKeyframe(0.5, [
    decl("opacity", number(1)),
    decl("background-color", colorValue(hexColor("#38bdf8")))
  ]),
  styleKeyframe(1, [decl("opacity", number(0.4))])
]))

let indicator = ui.box(uiStyle([
  animationNames("pulse"),
  animationDurations(1.2'f32),
  decl("animation-iteration-count", keyword("infinite")),
  animationDirection(adAlternate),
  animationFillMode(afBoth)
]))
```

The current keyframe runtime animates `opacity`, `color`, `background-color`,
and typed 2D `transform`, `translate`, `scale`, and `rotate` values. It consumes
list-valued `animation-name`, duration, signed
delay, timing function, iteration count, direction, fill mode, play state, and
composition. All longhand lists cycle by animation index. Unknown animation
names retain their positions, so a missing registration does not shift the
duration or timing assigned to later names. Multiple tracks on one node pause,
complete, and retain fill presentation independently; later declared tracks
have paint precedence when they target the same property.
Missing zero/one endpoints use the element's underlying computed value.
Completed forwards/both presentations survive unrelated style refreshes,
definition replacement restarts the named animation, and subtree disposal or
definition removal cancels active tracks.

## Lifecycle Events

Declarative motion emits standard lifecycle events through the same target,
bubble, observer, and replaceable-handler path as other CBSS events:

```nim
panel.onAnimationIteration = proc(event: DispatchResult): EventOutcome =
  echo event.motionName, " iteration ", event.motionIteration
  return handledEvent()

panel.onTransitionEnd = proc(event: DispatchResult): EventOutcome =
  echo event.motionName, " completed in ", event.motionElapsedSeconds
  return handledEvent()
```

Animations emit start, iteration, end, and cancel. Transitions emit run, start,
end, and cancel. Cancellation caused by subtree disposal is dispatched before
the subtree's handlers are detached. Lifecycle events are synthetic UI events;
they do not cause style resolution or layout by themselves.

Keyframe sampling, like transition sampling, is paint-only and proportional to
active tracks. It does not resolve style, perform layout, or rebuild unrelated
components on every animation frame. Transform tracks additionally invalidate
hit geometry so pointer targeting follows the displayed transform. Compatible
typed length units interpolate directly; incompatible units or transform-list
shapes use the defined discrete fallback instead of producing invalid geometry.

## Remaining Motion Work

This is not yet the complete declaration-driven motion surface. The following
remain planned:

- additional typed interpolable values beyond the current paint and transform
  set;
- additive and accumulative `animation-composition` modes;
- discrete-transition policy; and
- platform reduced-motion preference adapters.

These additions must retain the active-track cost model and idle behavior.
