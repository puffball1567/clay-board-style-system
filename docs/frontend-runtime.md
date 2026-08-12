# Frontend Runtime Design

Status: `Design adopted; implementation is planned after the current motion and
event foundations`

All frontend-runtime API names and examples in this document are proposed
authoring contracts. They do not claim that the corresponding symbols are
already exported.

CBSS already provides retained components, typed events, signals, dependency
injection, lifecycle ownership, dirty domains, transitions, and keyframes.
Those mechanisms are enough to build application state management in Nim, but
they are not yet one coherent authoring model. This document defines that
model.

The goal is not to reproduce React Hooks or Redux. The goal is to preserve the
frontend capabilities that made those tools useful while removing machinery
that exists only because React re-executes function components. CBSS components
are retained objects, so ordinary fields survive naturally and updates can
patch stable nodes directly.

## Product Boundary

The optional frontend runtime owns application-facing coordination:

- local and shared state;
- typed actions and deterministic reducers;
- selected and derived values;
- owned subscriptions and effects;
- asynchronous commands and UI-thread delivery;
- Cue-based temporal orchestration; and
- focused invalidation of the affected retained UI.

The style/layout core does not own application state. It continues to own
style state, interaction state, layout, paint, hit testing, focus, and reusable
control behavior. Business logic, network policy, persistence, and domain
models remain application or service-library responsibilities.

The feature is an optional Nim module. Applications that do not import it do
not link its scheduler, action log, command adapters, or Cue runtime.

```nim
import clay_board_style_system
import clay_board_style_system/frontend_runtime
```

## Current Foundation And Missing Integration

The design extends working CBSS mechanisms rather than replacing them.

| Capability | Current mechanism | Frontend-runtime work |
| --- | --- | --- |
| Retained component state | `CBSSComponent` fields | Concise patch and watch helpers |
| Mount and cleanup | `onMount`, `onUnmount`, `ComponentOwnedResource` | Source-driven owned effects |
| Reducer and dispatch | `StateRuntime[State, Action]` | Transactions and subscriptions |
| Typed occurrences | `Signal[T]` | Component-owned subscription helpers |
| Dependency injection | `ViewContext`, `provide`, `use` | Store/Command convenience only |
| Dirty scheduling | dirty domains and `FrameScheduler` | Automatic bounded invalidation |
| Visual motion | transition and named keyframes | Cue orchestration over motion |
| Worker delivery | bounded streams and UI mailbox | Command completion adapters |

Selectors, effect sources, Commands, and Cue sessions are not implemented yet.

## Familiar Authoring Without React Semantics

Public names should be immediately understandable to JavaScript and
TypeScript developers: `createStore`, `dispatch`, `select`, `subscribe`,
`effect`, `command`, and `cueSequence`. APIs remain ordinary typed Nim
procedures with parentheses. They must preserve compiler diagnostics, LSP
completion, navigation, rename, and static checking.

The authoring surface must not require:

- Hook call-order rules;
- dependency arrays;
- virtual-DOM reconciliation;
- re-executing every component after state changes;
- immutable-update boilerplate merely to detect changes;
- string action types, selector names, or component IDs; or
- command-call syntax, implicit `result`, or untyped macros in primary examples.

The intended flow is:

```text
native input
  -> typed event handler
    -> Action
      -> Store transaction
        -> changed Selector subscriptions
          -> retained node/component patch
            -> bounded dirty domains

Action
  -> Command
    -> UI-thread Result Action

event or Command result
  -> CueSession
    -> transition / keyframes / typed actions
```

## Capability Model

### Retained Local State

Component-local state is normally an ordinary component field. A Hook is not
needed to preserve it between renders because `CBSSComponent` instances are
retained.

```nim
type Counter = ref object of CBSSComponent
  count: int
  countLabel: LabelHandle

proc increment(self: Counter) =
  self.count += 1
  self.countLabel.setText($self.count)
```

The frontend runtime should add concise helpers that pair a retained mutation
with its exact invalidation. It must not make replaying `render(self)` the
default update mechanism. A component may deliberately rebuild or replace a
subtree, but ordinary text, value, selection, Style, and visibility changes
patch stable handles.

A later `StateCell[T]` convenience may combine a current value with typed
subscriptions. It is not a mandatory wrapper around every component field.

### Shared Store

The shared store is a typed state container with a deterministic update
function. The current `StateRuntime[State, Action]` is the starting mechanism;
the frontend API adds transaction batching and selected subscriptions rather
than replacing it with a stringly typed Redux clone.

```nim
type
  AppState = object
    count: int
    saving: bool

  AppActionKind = enum
    akIncrement,
    akSaveStarted,
    akSaveFinished

  AppAction = object
    kind: AppActionKind

proc reduce(state: var AppState; action: AppAction) =
  case action.kind
  of akIncrement:
    state.count += 1
  of akSaveStarted:
    state.saving = true
  of akSaveFinished:
    state.saving = false

let appStore = createStore(AppState(), reduce)
appStore.dispatch(AppAction(kind: akIncrement))
```

Required behavior:

- one dispatch is one transaction;
- nested dispatch is queued or rejected by an explicit policy, never applied
  recursively by accident;
- listeners observe the committed state, not intermediate reducer writes;
- multiple writes in one transaction produce at most one notification per
  changed selection;
- subscription order and removal during notification are deterministic; and
- Stores are application-owned values that can be supplied through the
  existing typed Provider boundary.

The strict reducer contract is non-raising. I/O and business failures are
typed Command results and later Actions, not exceptions escaping a partially
applied reducer. Reducers may mutate Store state inside an unpublished
transaction; CBSS does not require persistent immutable data structures or a
full State copy merely to detect a change.

### Selectors And Derived Values

`select` converts shared state into the smallest value a component needs.

```nim
let countValue = appStore.select(
  proc(state: AppState): int = state.count
)

self.watch(countValue, proc(count: int) =
  self.countLabel.setText($count)
)
```

A Selector:

- evaluates once per committed transaction of its Store at most;
- notifies only when its selected value changes under its equality policy;
- may cache a pure derived value;
- records no implicit dependency on component render order;
- does not retain the owning component strongly; and
- is detached automatically when owned by an unmounted component.

The default equality is typed `==`. Callers may provide a comparator for large
or identity-bearing values. Expensive derived computation uses explicit input
Selectors and caching; CBSS does not add a general `useMemo` equivalent.

A generic reducer does not expose which object field it mutated. The initial
correct implementation therefore evaluates active Selectors of the changed
Store once, then publishes only changed results. It does not scan unrelated
Stores or components. Applications with large shared models may partition
them into typed Store slices; an Action can then declare the affected slices
without exposing string paths or requiring runtime reflection.

### Signals

`Signal[T]` remains the open typed contract for semantic output that is not a
standard UI event. It is not automatically a Store and does not acquire a
current value.

- Events describe standard UI occurrences such as click and change.
- Signals publish library-specific typed occurrences such as chart selection.
- Stores retain application state and reduce Actions.
- Cues coordinate work over time.

The frontend runtime adds component-owned Signal subscriptions without
changing the existing low-level `subscribe`/`unsubscribe` API.

### Effects And Lifecycle

Effects are explicit owned subscriptions or resources. They do not execute
because a render procedure happened to run again.

```nim
self.effect(selectedDocument, proc(document: Document): EffectCleanup =
  let observation = document.observeChanges(onDocumentChanged)
  return cleanup(proc() = observation.close())
)
```

`effect(source, run)` subscribes once while the component is mounted, runs
when the typed source changes, cleans the previous resource before rerunning,
and cleans the final resource during unmount. There is no dependency array:
the source is the dependency.

Simple mount-only work continues to use `onMount`; deterministic release uses
`onUnmount` or `ComponentOwnedResource`. Timer choreography belongs to Cue,
and network/storage work belongs to Command. A generic Effect must not become
the default place for every unrelated side effect.

### Commands And Asynchronous Work

Commands connect application Actions to asynchronous or external work without
putting business logic in Style calculation or event propagation.

```nim
let saveDocument = command(
  proc(input: Document): Future[SaveResult] = repository.save(input)
)

saveDocument.onSuccess = proc(result: SaveResult) =
  appStore.dispatch(AppAction(kind: akSaveFinished))
```

The initial runtime does not choose one networking, storage, or async library.
A Command adapter must provide:

- a completion handle;
- cancellation;
- success and typed failure delivery;
- an ownership-transfer boundary for worker results;
- marshaling to the owning UI thread; and
- latest-only, ordered, or concurrent policy chosen explicitly by the caller.

The existing bounded stream/mailbox boundary remains the mechanism for
progressive results. `joubako` may provide HTTP-facing Commands, but CBSS owns
only their UI attachment, cancellation, and invalidation behavior.

### Cue Orchestration

Cue is the temporal orchestration layer. It is JavaScript-side behavior, not a
CSS property and not another input event. A standard event starts a
`CueSession`; the session coordinates multiple retained targets and calls the
existing motion runtime.

```nim
let saveCue = cueSequence("save", [
  atStart([
    animate(dialog, dialogEnterKeyframes),
    animate(backdrop, backdropFadeKeyframes),
    animate(spinner, spinnerStartKeyframes)
  ]),
  after(300.ms, [
    animate(title, titleRevealKeyframes)
  ]),
  after(600.ms, [
    animate(description, descriptionRevealKeyframes)
  ]),
  atEnd([
    animate(spinner, spinnerExitKeyframes),
    animate(resultPanel, resultRevealKeyframes)
  ])
])

saveButton.onClick = withCue(saveCue, onSave)
```

Semantics:

- `atStart` actions begin in parallel with the wrapped root operation;
- `after` uses a monotonic deadline relative to the sequence start or an
  explicitly named preceding step;
- actions in one step begin in parallel;
- `atEnd` waits for the wrapped root operation's completion contract;
- synchronous handlers complete on return;
- asynchronous Commands, Futures, streams, and animations expose explicit
  completion handles;
- cancellation and failure are separate from successful completion; and
- repeated start policy is one of `restart`, `ignore`, `queue`, or `parallel`.

Cue does not execute from Style resolution. Style recalculation may happen
more than once and must remain free of one-shot side effects. Cue actions may
start named keyframes, change an applied Style slot, dispatch an Action, emit a
Signal, or invoke a registered typed adapter for audio, video, or another
subsystem.

One process-wide or `UiRoot`-owned monotonic scheduler services all Cue
deadlines. It must not allocate an OS timer or thread per Cue. When no Command,
stream, animation, caret, or Cue deadline requires work, the SDL3 host remains
blocked in its event wait.

### Dependency Injection

The existing `ViewContext`, `provide`, and `use` APIs remain the type-oriented
DI boundary. Stores, Commands, service clients, clocks, and Cue registries may
be provided like any other application-owned value.

Provider lookup does not itself subscribe a component. A component explicitly
selects or watches mutable values. This avoids hidden whole-context invalidation
and keeps service replacement separate from state observation.

Component construction keeps the existing responsibility boundaries:

- `params` carries only additional values required to construct that component;
- caller-supplied Style remains separate Style DI;
- a component owns its own standard event handlers unless its public contract
  deliberately accepts a callback;
- shared Stores, Commands, and services arrive through typed Provider DI; and
- placing a child component does not require its parent to forward a generic
  event or state bundle.

This remains close to familiar frontend component composition without turning
every value into React-style props or context.

## Update And Scheduling Contract

The frontend runtime is retained and transactional.

1. Dispatch the standard UI event through the existing event contract.
2. Run the public handler once.
3. Queue Actions, Commands, and Cue starts requested by that handler.
4. Commit Store transactions after event propagation reaches a stable point.
5. Evaluate affected Selectors once.
6. Run owned watchers and patch stable handles.
7. Merge requested dirty domains and rebuild only affected runtime stages.
8. Request another frame only for an active deadline or newly dirty output.

Updates must be proportional to changed subscriptions and dirty subtrees, not
the total component tree. One Action may evaluate active Selectors of its
changed Store or declared slices once, but it must not invoke Selectors from
unrelated Stores, rerun Effects without a changed source, or replay components.

An explicit batch groups several dispatches into one notification boundary.
It does not conceal intermediate business-state mutations from the reducer;
it only delays subscriber publication and UI invalidation until commit.

## Ownership And Threads

The first implementation is UI-thread confined. Store mutation, Signal
emission, component patching, Effect replacement, and Cue graph mutation occur
on the owning UI thread.

Workers transfer immutable values or unique ownership through the existing
bounded mailbox/stream contract. They never retain `UiRoot`, mutate a Store,
or invoke a component callback directly.

Under ARC and ORC:

- a Component owns its subscription/effect/resource handles;
- a Store does not strongly own subscribed Components;
- unmount detaches all owned observations before releasing component fields;
- Command and Cue callbacks use generation-checked session handles;
- completion after cancellation or unmount is ignored deterministically; and
- cleanup is idempotent.

ARC remains the strict cycle-detection baseline. ORC compatibility remains a
supported application choice, not a substitute for correct ownership.

## Error, Cancellation, And Reentrancy

The runtime distinguishes:

- normal completion;
- explicit cancellation;
- component disposal;
- command failure;
- Cue action failure; and
- programmer errors such as a cyclic Cue graph.

Cue graphs are validated before first execution. Cycles, negative or
non-finite delays, missing motion names, and incompatible completion adapters
produce diagnostics rather than partial execution.

An event handler may dispatch an Action, but subscriber callbacks do not
re-enter the same Store transaction. Follow-up Actions are queued for the next
transaction turn. This provides deterministic ordering and prevents recursive
notification growth.

## Testing And Diagnostics

The existing headless driver becomes the primary frontend-runtime verifier.
Tests use a virtual monotonic clock and explicitly flush Actions, Commands,
Selectors, dirty domains, and Cue deadlines.

Required coverage includes:

- local and shared state changes without component replay;
- Selector equality, batching, and bounded evaluation counts;
- subscription removal during notification;
- mount/unmount cleanup and failed mount rollback;
- late Command completion after cancellation or disposal;
- worker-to-UI result ownership;
- Cue start, relative steps, completion barriers, cancellation, restart,
  queueing, parallel sessions, and reduced motion;
- no idle frame requests after all work settles;
- ARC/ORC lifecycle and sanitizer coverage; and
- large unrelated component and Store populations proving local work remains
  local.

Development builds may expose an action/session trace containing typed Action
names, Store revisions, Selector changes, Command lifecycle, Cue steps, and
dirty domains. The trace is development-only and is not linked into release
artifacts unless explicitly enabled.

## Intentional Non-Goals

The frontend runtime does not reproduce:

- React reconciliation, Fiber, concurrent rendering, Suspense internals, or
  Hook ordering;
- `useCallback`, dependency arrays, or referential-equality workarounds;
- Redux's exact middleware, enhancer, action-creator, or `combineReducers`
  APIs;
- automatic serialization of arbitrary Nim state or closures;
- business-specific retry, authorization, persistence, or networking policy;
- a global mandatory Store; or
- Style-driven side effects.

Applications and independent GUI libraries may use only retained component
fields, only a Store, an external state package, or the complete frontend
runtime. CBSS provides one coherent default without making it a prerequisite
for the style/layout engine.

## Delivery Order

1. Extend `StateRuntime` with transaction boundaries and owned typed
   subscriptions while preserving its current API.
2. Add `select` and component-owned `watch` with precise invalidation tests.
3. Add source-driven `effect` and deterministic cleanup using
   `ComponentOwnedResource`.
4. Define the Command completion/cancellation adapter over the existing
   stream and UI-thread mailbox.
5. Implement Cue definitions, sessions, virtual-clock tests, and the bridge to
   transition/keyframes.
6. Add optional development traces and higher-level authoring conveniences.
7. Consider C ABI exposure only after the Nim ownership and completion
   contracts are stable; generic Nim Store state does not cross the C ABI.
