# Declarative Motion

CBSS uses one monotonic animation clock for imperative component motion,
declarative style transitions, and future declaration-bound keyframes. Motion
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
the active interval. Color transitions use prepared Oklab interpolation.

The runtime is keyed by stable `NodeId` and property. Reversing a transition
starts from the currently displayed value, reconciling an unchanged target
does not restart it, and disposing a subtree removes its tracks. Reduced-motion
mode applies the target without retaining nonessential motion.

## Host Contract

Style resolution happens once when authored or state-derived style changes.
The host then reconciles the previously displayed and newly resolved trees:

```nim
ui.reconcileStyleTransitions(displayedStyles, targetStyles, nowSeconds)
displayedStyles = targetStyles
discard ui.applyStyleTransitions(displayedStyles, scheduler, nowSeconds)
```

On later animation deadlines, the host calls only `applyStyleTransitions` and
rebuilds affected paint output. It must not resolve the full style tree or run
layout merely to sample these paint-only tracks. Sampling cost is proportional
to active tracks, not total tree size.

`CbssTestDriver.refresh()` performs the reconciliation automatically.
`advanceTime(seconds)` advances transition paint deterministically without
re-resolving style, layout, or hit regions.

## Remaining Motion Work

This is not yet the complete declaration-driven motion surface. The following
remain planned:

- declaration-bound named keyframes through `animation-*` properties;
- transform and other typed interpolable values;
- transition and animation lifecycle event dispatch;
- list-valued durations, delays, and timing functions with CSS-like cycling;
- discrete-transition policy; and
- platform reduced-motion preference adapters.

These additions must retain the active-track cost model and idle behavior.
