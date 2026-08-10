# Declarative Motion

CBSS uses one monotonic animation clock for imperative component motion,
declarative style transitions, and declaration-bound keyframes. Motion
requests frames only while work is active. A static application returns to the
event-driven wait loop.

## Declarative Transitions

The first runtime slice consumes these existing declarations:

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

Supported runtime properties in this slice are:

- `opacity`;
- `color`; and
- `background-color`.

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
`applyStyleAnimations`, then rebuilds affected paint output. It must not resolve
the full style tree or run layout merely to sample these paint-only tracks.
Sampling cost is proportional to active tracks, not total tree size.

`CbssTestDriver.refresh()` performs the reconciliation automatically.
`advanceTime(seconds)` advances transition and keyframe paint deterministically
without re-resolving style, layout, or hit regions.

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
  decl("animation-name", keyword("pulse")),
  decl("animation-duration", number(1.2)),
  decl("animation-iteration-count", keyword("infinite")),
  animationDirection(adAlternate),
  animationFillMode(afBoth)
]))
```

The first keyframe runtime slice animates `opacity`, `color`, and
`background-color`. It consumes `animation-name`, duration, signed delay,
timing function, iteration count, direction, fill mode, and play state.
Missing zero/one endpoints use the element's underlying computed value.
Completed forwards/both presentations survive unrelated style refreshes,
definition replacement restarts the named animation, and subtree disposal or
definition removal cancels active tracks.

Keyframe sampling, like transition sampling, is paint-only and proportional to
active tracks. It does not resolve style, perform layout, or rebuild unrelated
components on every animation frame.

## Remaining Motion Work

This is not yet the complete declaration-driven motion surface. The following
remain planned:

- transform and other typed interpolable values;
- multiple comma-separated animations and CSS-like list cycling;
- additive and accumulative `animation-composition` modes;
- transition and animation lifecycle event dispatch;
- list-valued keyframe animation longhands with CSS-like cycling;
- discrete-transition policy; and
- platform reduced-motion preference adapters.

These additions must retain the active-track cost model and idle behavior.
