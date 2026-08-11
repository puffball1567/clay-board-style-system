# Native Navigation

Version 0.2 introduces a typed, state-driven navigation layer for native
applications. It models in-process screen history without requiring URL
strings, a DOM, browser history, or a WebView.

## Typed Destinations

A destination is an application-defined Nim value. An enum is sufficient for
simple applications, while an object or variant object can carry typed screen
parameters.

```nim
type
  Screen = enum
    homeScreen,
    settingsScreen,
    accountScreen

let navigator = initStackNavigator(homeScreen)

navigator.push(settingsScreen)
navigator.replace(accountScreen)
navigator.back()
navigator.forward()
```

The default stack stores `NavigationEntry[Destination]` values. Each entry has
a stable `NavigationEntryId`, so two visits to the same destination remain
distinct history entries. `replace` keeps the current history position but
creates a new entry identity, preventing later focus or transition state from
being confused with the replaced screen.

`snapshot()` returns the entries, current index, and monotonically increasing
revision. `currentDestination()`, `canGoBack()`, and `canGoForward()` provide
the common read path. Boundary `back` and `forward` operations are no-ops and
do not notify listeners.

## Link Primitive

`Link` is a style-neutral semantic primitive rather than a predesigned widget.
It owns pointer activation, Enter-key activation, focusability, disabled
suppression, an accessible Link role, and the destination-to-navigator
connection. Space is not treated as Link activation.

```nim
let settingsLink = ui.link(
  navigator,
  settingsScreen,
  "Settings",
  style = settingsLinkStyle,
  textStyle = settingsLinkTextStyle
)

settingsLink.onClick = proc(event: DispatchResult): EventOutcome =
  recordNavigationMetric()
  ignoredEvent()
```

The optional user `onClick` handler runs before navigation. Returning
`preventedEvent()` suppresses navigation without implicitly stopping event
propagation; `stoppedEvent()` stops propagation while retaining navigation.
Disabled links suppress both navigation and the user handler. Visual
appearance, including hover and focus-visible styling, remains injectable
through normal CBSS styles.

The navigator is application-owned and must outlive every mounted Link that
uses it. Link stores a non-owning ARC cursor to the navigator so a navigator
listener may interact with host state without creating
`UiRoot -> event closure -> Link -> Navigator -> listener -> UiRoot` cycles.

## Injection And Custom Drivers

`Navigator[Destination]` is a normal typed Nim value and can be injected with
the existing `ViewContext` provider mechanism:

```nim
let context = initViewContext([provide(navigator)])
let injected = context.use(Navigator[Screen])
```

The default implementation is built by `stackNavigationDriver`. Applications
and higher-level GUI libraries can instead provide a `NavigationDriver` with
their own snapshot, push, replace, back, and forward procedures, then pass it
to `initNavigator`. This keeps persistence, authorization, and business policy
outside CBSS while preserving one component-facing contract.

## Change And Invalidation Contract

Successful operations emit a typed `NavigationChange` containing:

- the operation kind;
- previous and current entries;
- the complete post-operation snapshot;
- the revision; and
- the dirty domains required for a screen change.

Listeners are additive and return an ID that can be passed to
`removeListener`. A host can connect navigation to its scheduler without
making the navigator own the renderer or root:

```nim
navigator.addListener(proc(change: NavigationChange[Screen]) =
  scheduler.markDirty(change.dirtyDomains)
)
```

The initial default domains are style, layout, paint, and hit testing.

## Retained Screen Hosting

`NavigationScreenHost` associates typed destinations with screen roots that
have already been built. Navigation queues a host change; `sync` applies the
latest queued destination once per event batch. It does not reconstruct the UI
tree, change existing `NodeId` values, or append a new style sheet on every
back/forward operation.

```nim
let host = initNavigationScreenHost(ui, navigator)
host.registerScreen(homeScreen, homeRoot)
host.registerScreen(
  settingsScreen,
  settingsRoot,
  focusFallback = some(settingsHeading)
)

var interaction = initInteractionState()
host.sync(interaction) # Initial activation.

# After each platform event batch:
discard host.sync(interaction)
```

Only the active screen participates in layout, paint, hit testing, direct UI
event dispatch, focus traversal, or the visible accessibility tree. Inactive
roots use `display: none` and an inherited runtime `inert` state. This state is
not a CSS pseudo-class and does not overwrite an application's disabled state.

If the current destination has not been registered, `sync` returns `false` and
keeps the previous screen active. Registering that destination and calling
`sync` again completes the transition. Screen roots must be disjoint and belong
to the host's `UiRoot`.

The host coalesces multiple navigation changes before one `sync`. Activating a
registered screen mutates only the previous and next screen roots; repeated
history traversal does not grow the retained node or style collections. Call
`disconnect` before intentionally releasing a host while retaining its
navigator. The navigator otherwise retains the host through its listener.

Screens may also be removed or rebuilt without reconstructing the whole UI:

```nim
discard host.unregisterScreen(settingsScreen, interaction)

let replacementRoot = buildSettingsScreen(ui)
discard host.replaceScreen(
  settingsScreen,
  replacementRoot,
  interaction,
  focusFallback = some(replacementHeading)
)
```

`replaceScreen` requires the replacement subtree to be fully built and
disjoint from all registered screens. It installs the replacement before it
disposes the previous subtree, so a construction failure leaves the registered
screen untouched. Disposal removes descendant event handlers, targeted style
rules, scroll state, popup closers, focus and pointer references, pending focus
requests, and semantic cross-references.

`NodeId` is a 32-bit opaque value containing an arena index and generation.
Disposed arena slots are reused, but stale `NodeId` and `NodeHandle` values do
not become valid for the replacement node. The same opaque value is exposed by
the C ABI. Application and GUI-library code must not derive or persist the
internal index. Component handles are valid only while their root node remains
active; stale built-in component setters are safe no-ops.

## Focus Transfer And Restoration

`NavigationFocusMemory` provides a two-phase focus contract that does not force
one screen construction model on GUI libraries. A navigation listener captures
the focused node for the entry being left. After the host activates or rebuilds
the destination screen, it restores focus within that screen root.

```nim
let focusMemory = initNavigationFocusMemory()

navigator.addListener(proc(change: NavigationChange[Screen]) =
  focusMemory.captureFocus(change, interaction)
)

# Activate or rebuild the destination screen, then:
focusMemory.restoreFocus(
  ui,
  interaction,
  activeScreenRoot,
  fallback = some(primaryControl.container)
)
```

Restoration checks, in order:

1. the last valid focus target saved for this exact history entry;
2. the explicit fallback, when it belongs to the active screen; and
3. the first focusable descendant in normal focus order.

If the screen has no valid target, focus is cleared. Saved targets outside the
active subtree, disabled targets, stale node indexes, foreign roots, and
fallbacks from another `UiRoot` are rejected. The listener, interaction state,
and navigator must share an application-controlled lifetime.

## Optional Screen Transitions

`NavigationScreenHost` can expose screen changes to an application-owned visual
hook without making animation policy part of navigation. The hook receives the
operation, stable history entries, outgoing and incoming roots, phase, and a
normalized progress value. It may inject opacity, transform, or other styles
supported by the active renderer.

```nim
let transition = navigationTransition[Screen](
  durationSeconds = 0.18,
  onTransition = proc(context: NavigationTransitionContext[Screen]) =
    case context.phase
    of ntpStarted, ntpAdvanced:
      ui.setNodeStyle(
        context.incomingRoot.id,
        uiStyle([decl("opacity", number(context.progress))])
      )
    of ntpCompleted, ntpCancelled:
      ui.setNodeStyle(
        context.incomingRoot.id,
        uiStyle([decl("opacity", number(1.0))])
      )
)

let host = initNavigationScreenHost(ui, navigator, some(transition))
```

Use the scheduler-aware overload to start a configured transition, then advance
it from the central timed-work phase:

```nim
discard host.sync(interaction, scheduler, monotonicNow)

# After the event wait, while timed work is active:
scheduler.clearDeadline()
discard host.advanceTransition(scheduler, monotonicNow)
```

The outgoing root remains paintable during the transition but becomes inert
immediately. Focus and input therefore belong only to the incoming screen. The
outgoing root changes to `display: none` at completion. A second navigation,
screen replacement, or screen disposal cancels and settles the active
transition before continuing. Initial activation and navigation to a new entry
of the same retained screen do not manufacture a visual transition.

The scheduler requests the next deadline only while a transition is active.
The legacy `sync(interaction)` overload remains an immediate switch for event
loops that do not opt into time-driven transitions. Navigation hooks remain
separate from the declarative CSS-inspired transition/keyframe engine; they
coordinate retained screen roots rather than style-property interpolation.

## External URLs And Application Deep Links

External URLs use an injected `ExternalUrlAdapter`. The default policy allows
only HTTP and HTTPS; file URLs, custom schemes, whitespace/control characters,
relative references, and oversized values are rejected before a platform
procedure is called.

```nim
import clay_board_style_system/backends/sdl3/platform_links

let externalLinks = sdl3ExternalUrlAdapter()
let opened = externalLinks.openExternalUrl("https://example.test/docs")
```

Applications may explicitly construct another `PlatformUrlPolicy`, for example
to allow `mailto`. SDL's successful return means that the OS accepted the open
request, not that the destination loaded successfully.

Application deep links use an application-defined codec so CBSS never has to
serialize arbitrary destination objects or own authorization rules:

```nim
let codec = deepLinkCodec[Screen](
  ["my-app"],
  proc(url: string): Option[Screen] =
    case url
    of "my-app://settings": some(settingsScreen)
    of "my-app://account": some(accountScreen)
    else: none(Screen)
)

let result = navigator.navigateDeepLink(codec, "my-app://settings")
```

`navigateDeepLink` validates the URI and allowed scheme, decodes it into a typed
destination, and then performs `push` or `replace`. Unmatched, rejected, and
driver-declined inputs have distinct result statuses. Optional encoding uses
the same validation policy.

Linux desktop launch links commonly arrive in process arguments. The command
line source consumes its initial arguments exactly once:

```nim
let launchLinks = commandLineDeepLinkAdapter()
let results = launchLinks.drainDeepLinks(navigator, codec)
```

Platform lifecycle bridges for Windows, macOS, iOS, and Android can implement
the same `DeepLinkSourceAdapter` contract and deliver pending strings without
changing navigation or codecs. SDL3 does not provide one cross-platform
incoming deep-link event, so package registration and each OS callback bridge
remain platform integration responsibilities. CBSS does not fetch data or
authorize a destination after decoding it.

## Current And Planned Scope

Implemented in Version 0.2:

- typed entries, snapshots, and changes;
- default push/replace/back/forward history;
- forward-branch truncation after a new push;
- additive listeners and dirty-domain metadata;
- replaceable application-owned drivers;
- `ViewContext` injection;
- semantic Link pointer, keyboard, focus, disabled, and AT-SPI behavior;
- history-entry focus capture, fallback transfer, and restoration; and
- retained screen activation with inert inactive subtrees;
- generation-checked subtree disposal and bounded arena reuse;
- active and inactive screen replacement and unregister operations; and
- ARC lifecycle and headless regression coverage;
- optional screen-transition hooks tied to the frame scheduler;
- policy-checked external URL and typed application deep-link adapters; and
- an optional SDL3 Wayland integration scenario covering Link, transition,
  and deep-link rendering through a real window.

Navigation does not own authorization, data loading, persistence, or backend
requests. Those remain application and backend-logic responsibilities.
