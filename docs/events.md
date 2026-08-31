# Events And Typed Signals

CBSS separates standard UI events from library-specific semantic output.
Controls use the closed `InputEventKind` surface and familiar properties such
as `onClick`. Charts, editors, and independent component packages use typed
`Signal[T]` values when their payload is not a standard UI event.

## Event Outcomes

An event handler returns `EventOutcome`. Its effects are independent:

```nim
saveButton.onClick = proc(event: DispatchResult): EventOutcome =
  saveDocument()
  return handledEvent()
```

- `handledEvent()` reports that the callback acted, without suppressing the
  control's intrinsic behavior or ancestor handlers.
- `stoppedEvent()` stops ancestor propagation but retains the intrinsic default
  action.
- `preventedEvent()` suppresses a cancelable default action but still allows
  ancestor handlers to observe the event.
- `handledEvent(stopPropagation = true, preventDefault = true)` combines the
  effects explicitly.
- `ignoredEvent()` reports no action.

Code written before Version 0.4 may still return `bool` while migrating:
`true` maps to `stoppedEvent()` and `false` maps to `ignoredEvent()`. This is a
source-compatibility bridge, not the current event API. New handlers should
return an explicit outcome so handled state, propagation, and default-action
suppression cannot be confused. CBSS compiles its runtime and public examples
with `-d:cbssStrictEventOutcomes` in CI to prevent first-party code from using
the compatibility conversion. Applications do not need that build flag.

`target` remains the original hit or focus target. `currentTarget` is the node
whose handler is currently running. `phase` distinguishes target, bubble, and
default-action dispatch. Local coordinates are valid only on the original
target unless a future event definition explicitly provides another contract.

CBSS checks `disabled` and `inert` before public handlers. It then runs the one
replaceable public handler, additive observers, and finally the control's
preventable intrinsic action. This lets application code reject navigation or
a toggle without replacing the control implementation.

## Public Slots And Observers

Property assignment replaces only the public slot:

```nim
button.onClick = firstHandler
button.onClick = replacementHandler
```

Libraries that deliberately observe the same event use a removable
subscription. Reassigning the public slot does not remove observers.

```nim
let observation = button.subscribe(
  iekClick,
  proc(event: DispatchResult): EventOutcome =
    recordActivation(event.target)
    return ignoredEvent()
)

discard button.unsubscribe(observation)
```

Subscriptions are detached automatically when their owning node's subtree is
disposed. Explicit removal remains appropriate when an observer has a shorter
lifetime. Removal is safe during dispatch; a removed callback is not invoked
later in the same dispatch.

## Dispatch-Scoped UI Actions

Handlers request UI work through the current event instead of capturing the
owning `UiRoot`. The requests are applied after propagation finishes:

```nim
button.onPointerDown = proc(event: DispatchResult): EventOutcome =
  discard event.requestFocus()
  discard event.capturePointer()
  discard event.invalidate({ddPaint, ddHit})
  discard event.requestFrame()
  return handledEvent()

discard ui.handleEvents(dispatches)
discard ui.reconcilePointerCapture(interaction)
discard ui.reconcileFocus(interaction)
```

The action capability is non-owning and valid only while that event is being
dispatched. Retaining `DispatchResult` does not retain `UiRoot`; later calls on
the stale value return `false`. Pending focus or pointer-capture requests are
also canceled when their target subtree is disposed.

Pointer capture remains active when the pointer leaves the component or native
window. The corresponding pointer-up is routed to the captured node with local
coordinates that may be outside its bounds, then CBSS releases capture and
emits `onLostPointerCapture`. A platform focus loss or capture failure emits
pointer-cancel instead, so drag state cannot remain stuck. Releasing outside the
node does not synthesize a click.

Application hosts should dispatch through `UiRoot.handleEvent`,
`UiRoot.handleEvents`, or `UiRoot.dispatchEvent`. Calling `EventRegistry`
directly remains useful for isolated tests, but deliberately provides no
root-scoped action authority.

Event production, payload shape, bubbling, cancelability, compatibility
aliases, and C ABI numbers are defined by one `EventDefinition` table. This
keeps backend input, synthetic events, component events, and foreign-language
callbacks on the same contract.

Declarative motion uses this same path. Animation lifecycle handlers can read
`motionName`, `motionElapsedSeconds`, and `motionIteration`; transition
lifecycle handlers use the name and elapsed-time fields. The supported event
set is animation start/iteration/end/cancel and transition run/start/end/cancel.
These events are non-cancelable notifications. Disposing a subtree dispatches
its cancellation events before removing its handlers.

The same table owns each public `onX` name. Run
`nimble checkGeneratedEvents` to verify the committed EventRegistry,
NodeHandle, CBSSComponent, and C event-kind surfaces. Contributors changing an
event definition regenerate those files with:

```sh
nim c -r --mm:arc --path:src tools/generate_events.nim
```

Product builds import only the generated Nim fragments. The generator and its
verification code remain development tools and are not linked into CBSS
applications.

## Typed Library Signals

Do not add project-specific names to `InputEventKind` merely to carry a custom
payload. Publish a typed signal instead:

```nim
type ChartSelection = object
  series: int
  point: int

let selectionChanged = initSignal[ChartSelection]()
let subscription = selectionChanged.subscribe(
  proc(selection: ChartSelection) =
    echo selection.series, ":", selection.point
)

selectionChanged.emit(ChartSelection(series: 2, point: 8))
discard selectionChanged.unsubscribe(subscription)
```

Signals preserve listener registration order. Adding a listener during an
emission takes effect on the next emission, while removing or clearing a
listener takes effect immediately. Signals are UI-thread primitives; worker
threads must publish immutable data through the application's UI-thread queue.

## C ABI

The C callback receives the same original target, current target, phase,
bubbling, and cancelability metadata. Replaceable handlers and removable
additive subscriptions both use the same runtime registry as Nim handlers.
Callbacks return a bitwise combination of `CBSS_EVENT_OUTCOME_*`.
`CbssDispatchSummary.outcome` preserves the complete result while `handled`
remains as a compatibility convenience. See [C ABI](c-api.md) for the
fixed-layout contract.
