# Product Roadmap

This document records intended product milestones. A planned item describes
project direction, not a compatibility promise, until its public API and tests
are complete.

## Version 0.1 - Linux Developer Preview

Status: `Released 2026-07-28`

Version 0.1 establishes the primitive native UI foundation: style resolution,
layout, text, paint commands, SDL3 rendering, hit testing, input, focus,
reference controls, retained scrolling, accessibility semantics, test tooling,
and the language-neutral C ABI.

## Version 0.2 - Native Navigation

Status: `Released 2026-08-01`

The primary Version 0.2 feature is a state-driven navigation layer for native
applications. CBSS already lets applications change state and render a
different component tree. Version 0.2 turns that capability into a small,
consistent navigation surface without importing browser-only routing behavior.

Released capabilities:

- A semantic `Link` primitive with pointer, keyboard, focus-visible, and
  accessibility behavior.
- A navigator with `push`, `replace`, `back`, and `forward` operations.
- A typed destination model that does not require URL strings for ordinary
  in-process screens.
- Navigation-stack state that can be injected into components and replaced by
  an application-owned implementation.
- Focus transfer and restoration when the active screen changes.
- Dirty-domain integration so navigation updates only affected UI instead of
  rebuilding unrelated state by default.
- Optional transition hooks that request continuous frames only while a
  transition is active.
- Platform adapters for external URLs and application deep links.
- Headless navigation tests plus optional SDL3 integration coverage.

### ARC Ownership And Widget Lifecycle

Version 0.2 must also close the ownership gap between the documented ARC
model and the reference-control implementation. ARC remains CBSS's strict
release-verification baseline. ORC compatibility is tested as a safety net,
but cycle collection must not be used to hide an ownership cycle in the
runtime.

This work is a Version 0.2 release gate:

- Remove owning `UiRoot` back-references from public and internal component
  handles. Handles use `NodeId`, component state, or explicitly non-owning
  `{.cursor.}` access whose lifetime is bounded by the owning `UiRoot`.
- Ensure event-registry closures cannot form
  `UiRoot -> EventRegistry -> closure -> component handle -> UiRoot` cycles.
  Internal handlers capture only the state and stable identifiers they need,
  and receive root-scoped services from dispatch-time context.
- Audit every reference control and widget, including buttons, checkboxes,
  switches, dialogs, details, forms, labels, list boxes, command menus, radio
  sets, select boxes, sliders, tabs, text inputs, and textareas.
- Keep SDL windows, renderers, textures, font systems, native bridge contexts,
  and future GPU resources behind explicit `close`/`destroy` ownership. A
  cycle collector is not a substitute for native-resource lifecycle APIs.
- Document that a component handle is valid only while its owning `UiRoot`
  and node generation remain valid. The C ABI continues to expose opaque
  handles with explicit create/destroy contracts instead of Nim references.

The existing Valgrind checks exercise shared and static C ABI consumers. They
do not by themselves prove that Nim component graphs are cycle-free. Version
0.2 therefore adds a separate ARC widget-lifecycle executable that:

- builds with `--mm:arc -d:release -d:useMalloc` so allocations are visible to
  Valgrind;
- repeatedly creates, mounts, interacts with, closes, rebuilds, and destroys
  `UiRoot` instances containing every reference control and widget;
- exercises registered closures, popup closers, focus changes, clipboard
  callbacks, text composition, and component replacement before destruction;
- runs with full leak reporting and treats definite and indirect leaks,
  invalid reads/writes, double frees, and use-after-free reports as failures;
  and
- runs in CI alongside, but separately from, the C ABI Valgrind consumers and
  the normal discovered ARC test suite.

The lifecycle test must first reproduce the pre-fix ownership cycle and then
pass after the strong back-references are removed. A clean C ABI Valgrind run
alone is not sufficient evidence for this Version 0.2 gate.

**Implementation status (2026-08-01):** Component and node handle root
back-references now use non-owning ARC cursors. The lifecycle probe reproduced
both the general component-handler cycle and a separate direct root capture in
the default context menu before the fixes. Its expanded 16-root workload now
finishes with 23,793 allocations, 23,793 frees, zero bytes in use, and zero
Valgrind errors. Dedicated widget-lifecycle and C ABI Valgrind tasks run as
separate CI steps. Explicit destruction of backend and future GPU resources
remains an ongoing requirement as those resource types are added.

The navigation layer owns UI behavior and history mechanics. Applications still
own route authorization, data loading, persistence, and other business logic.
Screen constructors and destination payloads should remain normal Nim values so
GUI libraries can build higher-level routing conventions without modifying the
CBSS core.

The initial API should remain small and declarative:

```nim
navigator.push(settingsScreen)
navigator.replace(loginScreen)
navigator.back()
```

**Navigation implementation status (2026-08-01):** The typed destination and
history core, stable entry identities, default `push`/`replace`/`back`/`forward`
stack, additive change listeners, dirty-domain metadata, `ViewContext`
injection, replaceable application-owned drivers, and the semantic Link
primitive are implemented with headless tests. Link includes pointer, Enter,
focus, disabled, accessible role, and AT-SPI activation behavior. Focus capture
and restoration are implemented per stable history entry with active-screen
validation and fallback transfer. Retained screen hosting now switches disjoint
prebuilt screen roots without changing NodeIds or growing node/style storage
during repeated history traversal. Inactive screens are excluded from layout,
paint, hit testing, direct events, focus traversal, and accessibility through
`display: none` plus inherited inert state. Generation-checked subtree disposal,
screen unregister/replacement, stale-handle rejection, and bounded node/style
slot reuse are implemented. Transition hooks, platform URL/deep-link adapters,
and optional SDL3 navigation coverage are now implemented. Transition hooks
request deadlines only while active and settle outgoing roots before disposal
or replacement. External URLs use an injected, scheme-restricted platform
adapter. Application deep links validate and decode into typed destinations;
one-shot command-line launch input and a reusable pending-link source contract
cover Linux launch flows and future OS lifecycle bridges. A real-window Wayland
scenario exercises Link activation, transition frames, and deep-link routing.
The Version 0.2 release matrix passed the complete ARC suite, shared and static
C ABI consumers, separate widget and C ABI Valgrind checks, all example link
profiles, both Rust bridges, release benchmarks, real-window Wayland smoke and
large-paste scenarios, and the navigation E2E scenario. The navigation and full
SDL3 demos were also reviewed interactively before release.

### Non-Goals

- SEO, server-side routing, or browser URL compatibility.
- A DOM, browser history clone, or dependency on a WebView.
- Application-specific authorization or data-fetching policy.
- Rebuilding the complete UI tree for every navigation action.
- Forcing one router convention on GUI libraries built above CBSS.

## Version 0.3 - Visual Foundation And Color

Status: `Released in 0.3.0`

Version 0.3 establishes the public visual-surface foundation that independent
libraries can build on. CBSS owns the host contract, placement, composition,
input routing, frame scheduling, and core color model. Charting and other
application-domain libraries remain separate OSS packages. SDL-native game
surfaces that must share CBSS texture, renderer, input, and frame lifecycles
are optional modules shipped within CBSS.

Planned capabilities:

- Add a type-oriented Nim component authoring layer that remains ordinary Nim
  and preserves LSP completion, navigation, rename, and static checking. Public
  examples use `CBSSComponent` subtypes, `render(self)`,
  `ui.mount(Component(...))`, and `ui.box(self, ownedStyle = ...)`; they do not
  depend on an uppercase proc convention, an untyped component macro, an
  implicit `result` variable, or command-call syntax without parentheses.
- Make component Style DI automatic at the component-root boundary. The caller
  supplies the inherited `style` field, the component supplies `ownedStyle`,
  and CBSS applies the documented component-owned conflict precedence without
  requiring authors to write `injected + owned` expressions in every render
  proc.
- Provide an imported `ui` authoring facade backed by a checked, nested render
  context rather than a process-global `UiRoot`. `ui.mount()` establishes and
  restores the active root synchronously, supports nested components and
  separate roots, retains mounted component instances under ARC, and reports
  use outside a render scope as an authoring error.
- Keep `render(self)` as retained initial construction, not virtual-DOM-style
  replay. Later state changes update stable nodes and dirty domains. Mount and
  subtree disposal own deterministic component retention and unmount hooks so
  a discarded `ui.mount(...)` return value cannot prematurely free component
  state.
- Make the color subsystem semantically compatible with the supported CSS
  Color 4 surface described below, including hexadecimal, named, RGB, HSL,
  HWB, Lab/LCH, Oklab/Oklch, alpha, interpolation, gamut handling,
  `currentColor`, and typed color-mix behavior where relevant. CBSS as a whole
  remains CSS-inspired rather than a complete CSS implementation.
- Evaluate Pixie as an optional CPU raster and image-effects backend for
  paths, masks, gradients, shadows, blur, blending, SVG rasterization, and
  image processing. Pixie remains behind CBSS color, paint, cache, and C ABI
  contracts and must not redefine their semantics.
- Publish a versioned `CanvasHost` / `RenderSurface` lifecycle contract for
  independent Nim modules: mount, update, resize, input, frame request,
  visibility, device-loss, unmount, and deterministic cleanup. A Nim module
  may privately adapt a foreign library over its C ABI, but the published CBSS
  extension remains a normal Nim package.
- Provide the first standard 2D Canvas host on the SDL3 renderer path, with
  local coordinates, clipping, opacity, stacking, pointer blocking, and
  retained static content consistent with an ordinary CBSS Box.
- Add a time-driven animation clock and declarative keyframe/transition
  primitives for properties CBSS can interpolate and paint deterministically.
  Continuous frames are requested only while a visual surface or animation is
  active; idle UI remains event-driven.
- Establish the single transform, paint, and hit-test coordinate contract
  needed by Canvas and animation. This does not require all future visual
  effects to ship in Version 0.3.
- Make cross-platform compatibility a required CI signal. Linux x86_64,
  Windows x86_64, and macOS arm64 must compile and run the portable ARC suite,
  compile the public API and non-window examples, build the shared and static
  C ABI libraries, and test both native Rust bridges. Linux keeps the separate
  bundled-SDL3, Wayland, and Valgrind lanes. Passing portable CI does not by
  itself promote Windows or macOS to runtime-supported status; real-window,
  input, IME, DPI, and accessibility validation remain explicit platform
  gates.

Independent modules may use the resulting contract to provide capabilities
such as `cbss_charts`. CBSS itself may provide opt-in game modules for sprites,
tile maps, and Tiled integration because they share its SDL renderer, texture
cache, input routing, coordinate conversion, and frame scheduler. CBSS does
not bundle image assets or make a chart/widget catalogue part of its core
release.

Implementation progress:

- Implemented in Version 0.3: typed `CBSSComponent` authoring with ordinary
  Nim `render(self)` procedures, checked nested `ui` contexts, automatic Style
  DI with component-owned conflict precedence, root event properties, ARC
  retention, deterministic lifecycle hooks, and transactional rollback.

- Implemented on the Version 0.3 development line: authored color-space
  values, conversion to the current SDR sRGB paint boundary, explicit gamut
  policy, late `currentColor` resolution, and premultiplied-alpha
  interpolation. The existing 16-byte resolved `Color` remains unchanged.
- Implemented on the Version 0.3 development line: structured serialized color
  parsing with byte-offset diagnostics for hexadecimal and named colors,
  modern and legacy RGB/HSL, HWB, Lab/LCH, Oklab/Oklch, predefined
  `color()` spaces, angle units, alpha, and missing components. Parsing is a
  typed input boundary and does not add a CSS cascade or custom properties.
- Implemented on the Version 0.3 development line: typed and parsed authored
  colors resolve through solid color properties, structured borders and
  shadows, and scrollbar color pairs. Foreground color resolves first so
  `currentColor` is independent of declaration order. Computed and paint data
  retain the existing compact resolved `Color` representation. Direct `decl`
  overloads accept both resolved `Color` and authored `ColorValue` without an
  extra `colorValue(...)` wrapper.
- Implemented on the Version 0.3 development line: a portable test profile and
  required Linux, Windows, and macOS CI lanes for the platform-neutral core,
  C ABI build, and native Rust bridges. Linux-specific SDL3 runtime checks
  remain separate and continue to be release-blocking.
- Implemented on the Version 0.3 development line: typed and serialized
  `color-mix()` with CSS percentage defaulting and normalization, explicit
  sRGB, linear-sRGB, and Oklab interpolation, premultiplied alpha, late
  `currentColor`, strict diagnostics, and direct solid/border/shadow style
  integration. Additional interpolation spaces, hue methods, and nested mixes
  remain explicit follow-up work.
- Implemented on the Version 0.3 development line: CSS missing-component
  interpolation for the currently supported rectangular interpolation spaces,
  including analogous cross-space components, remaining-component sets, and
  alpha carry-forward before premultiplication.
- Implemented on the Version 0.3 development line: explicit sRGB,
  linear-sRGB, and Oklab interpolation for linear gradients through one shared
  premultiplied-alpha sampler used by SDL3 and PPM. The selected space is part
  of computed style, paint commands, and SDL3 baked-texture cache identity.
- Implemented on the Version 0.3 development line: additive C ABI 1.1 opaque
  authored-color handles and constructors for typed spaces, `currentColor`,
  CSS color parsing, and `color-mix()`. The stable 16-byte resolved color ABI
  remains unchanged.
- Implemented on the Version 0.3 development line: mixed resolved and authored
  gradient stops, including wide-gamut values, `currentColor`, and color mixes.
  Stops retain authored intent in declarations and resolve to the existing
  compact paint representation during style computation. The C ABI copies
  opaque authored-color stop handles rather than borrowing them.
- Implemented on the Version 0.3 development line: pinned Chrome 150 fixtures
  for serialized colors, color mixes, alpha composition, wide-gamut Canvas
  conversion, and actual CSS swatches. Portable tests enforce the captured
  RGBA8 boundary without requiring a browser in product builds. A Chrome 150
  Rec.2020 transfer-function difference from current CSS Color 4 is recorded
  explicitly rather than hidden behind a broad tolerance.
- The planned Version 0.3 color units are implemented. Additional
  interpolation spaces, polar hue methods, serialized gradient syntax,
  wide-gamut/HDR output surfaces, and newer browser comparison lanes remain
  follow-up capabilities rather than release blockers for the SDR sRGB path.
- Implemented on the Version 0.3 development line: versioned RenderSurface
  registration and lifecycle, placement, local input conversion, explicit
  frame requests, visibility, device-loss/recovery, deterministic teardown,
  and idle-aware scheduling.
- Implemented on the Version 0.3 development line: a first retained `Canvas2D`
  surface for rectangles, rounded rectangles, linear gradients, strokes,
  text, images, and nested clips. Canvas content uses the Box content area;
  CBSS retains ownership of padding, borders, opacity, clipping, stacking, and
  event routing. Canvas commands enter the existing paint stream, so SDL3 and
  headless rendering do not acquire separate style semantics.
- Implemented on the Version 0.3 development line: a deterministic animation
  clock with delays, finite and infinite iterations, direction, fill,
  pause/resume, reduced-motion policy, CSS timing functions, typed float and
  color keyframes, dirty-domain integration, and no idle frame loop.
- Implemented on the Version 0.3 development line: one presentation-coordinate
  helper for ancestor scroll translation, overflow clipping, inherited
  opacity, paint, hit testing, and RenderSurface placement. Dedicated tests
  assert that these consumers agree.
- Implemented on the Version 0.3 development line: the versioned RenderSurface
  contract is exposed through the C ABI, including Box attachment, placement,
  local input, explicit frame requests, pixel-scale resize, visibility,
  device loss/recovery, and deterministic unmount. Shared and static C
  consumers exercise the complete lifecycle.
- Implemented on the Version 0.3 development line: an interactive Canvas and
  wide-gamut color demo exercises retained drawing, local pointer input,
  explicit 60 Hz frame requests, event-driven idle waiting, clipping, and
  Oklab-interpolated gradients through the bundled SDL3 path.
- Implemented on the Version 0.3 development line: retained open and closed
  paths with adaptive quadratic/cubic curves, configurable butt/round/square
  caps, miter/round/bevel joins, Canvas-local placement, opacity, clipping,
  and shared SDL3/headless rendering.
- Implemented on the Version 0.3 development line: resolved 2D
  `transform`, `translate`, `rotate`, `scale`, transform origin, and transform
  box now share one affine coordinate contract across paint, exact hit tests,
  transformed clips, and RenderSurface-local input. SDL3 composites bounded
  offscreen scopes with reusable high-DPI textures; the PPM reference backend
  inverse-samples transformed gradients and clips. Pixel tests cover normal,
  layered, nested, and rounded-clip composition.
- Implemented on the Version 0.3 development line: retained Canvas `save`,
  `restore`, `transform`, `translate`, `rotate`, and `scale`. Transform and clip
  scopes restore in strict LIFO order, local matrices are placed at the Canvas
  Box origin, malformed scopes are contained, and SDL pixel tests exercise the
  same bounded affine composition path as styled Box transforms.
- Pixie evaluation result: do not make Pixie a core dependency or expose its
  types. A future optional adapter remains appropriate for cached paths,
  masks, SVG, blur, and image effects after the canonical path/mask paint
  vocabulary and cache ownership are stable. SDL3 remains sufficient for the
  mandatory Version 0.3 Canvas path.
- Implemented on the Version 0.3 development line: bounded Canvas offscreen
  layers with explicit opacity and portable source-over, copy, and additive
  composition. Scopes balance in strict LIFO order with transforms and clips;
  SDL3 reuses compact high-DPI textures and the PPM reference backend verifies
  alpha composition pixel by pixel. The append-only C ABI exposes layer paint
  kinds and composition metadata.
- Implemented on the Version 0.3 development line: the C ABI RenderSurface
  Canvas adapter accepts retained transforms, clips, layers, rectangles,
  gradients, paths, text, and images in local coordinates. One explicit commit
  publishes the complete display-list update without style resolution or
  layout, including safe mount-callback reentrancy and revision synchronization.
- Version 0.3 release gates cover SDL3 and headless rendering, performance,
  ARC and C ABI memory checks, portable CI, and real-window Wayland scenarios.
  Three-dimensional transforms, filters, shared GPU targets, CPU pixel-buffer
  surfaces, and full CSS blend/isolation semantics remain later work.

## Version 0.4 - Units, Component Flow, And Open Event Contracts

Status: `Partially implemented`

Version 0.4 completes the typed unit model across supported properties, makes
conditionally materialized components behave like ordinary flow children, and
turns events into a stable connection contract for independently developed Nim
UI libraries. The unit goal is not merely to parse more values: every supported
unit/property pair must have a defined resolution context, a computed-value
result, diagnostics, and tests. The component-flow goal is to let application
code mount a component at its intended location without exposing coordinates,
layout placeholders, or conditional-rendering machinery. The event goal is to
keep intrinsic UI behavior, application callbacks, and library observers
separate without making one component language or widget implementation the
only integration surface.

Planned capabilities:

- Complete percentage resolution for layout, paint, and text properties where
  the relevant containing block, box, or font context exists.
- Complete font-relative units such as `em`, `rem`, and the supported
  font-metric-relative forms, with a diagnostic when the necessary font
  context is unavailable.
- Add viewport-relative units only with an explicit window/viewport reference
  and deterministic resize invalidation.
- Finish property-level numeric shorthand while preserving explicit unit
  constructors and the low-level explicit `decl(...)` path.
- Specify intrinsic and automatic sizing interactions instead of accepting a
  unit syntactically without an executable layout meaning.
- Add cross-property unit-resolution tests, resize tests, and diagnostics for
  unsupported combinations.
- Complete the open event contract described below, including explicit event
  outcomes, correct target identity, deterministic default actions, removable
  subscriptions, typed library signals, ARC-safe dispatch services, and the
  same observable semantics through Nim and the C ABI.

### Viewport-Relative Units

Status: `Implemented on the Version 0.4 development line`

The typed `vw`, `vh`, `vmin`, and `vmax` constructors resolve against an
explicit viewport supplied by the host. Window resize invalidation recomputes
their pixel values deterministically; resolving them without a viewport emits
a diagnostic instead of silently producing a zero or stale value.

The shared resolver is connected to supported dimensions and constraints,
spacing, flex gaps and basis, positioning, transforms, borders and radii,
outlines and shadows, background sizing and positioning, columns, text
metrics and decoration lengths, vector coordinates, and overflow clip margins.
The C ABI appends matching unit tags without changing the ordinals of existing
tags. Percentages remain a separate unit-resolution task because they require
property-specific containing-block or box references rather than the viewport.

### Percentage Box Spacing

Status: `Implemented on the Version 0.4 development line`

`padding`, `margin`, their physical sides, and their current logical aliases
accept typed percentage values. As in CSS horizontal writing mode, percentages
on every side resolve against the containing block's inline width; vertical
padding and margins therefore do not use the containing height. Negative
padding is clamped to zero, while negative margins retain their sign.

Percentage intent remains typed through style resolution and inheritance, then
is resolved during layout when the containing width is known. The resulting
used padding is stored with the layout box and shared by paint clipping,
scrollbar geometry, hit testing, transforms, and embedded render surfaces.
Pixel-only spacing keeps the allocation-free hot path. During intrinsic
measurement, unresolved percentages contribute zero so they do not create a
cyclic content-size dependency.

### Transparent Conditional Component Flow

Status: `Implemented on the Version 0.4 development line`

A component library must be able to occupy a declarative position between
ordinary siblings even when its content becomes available asynchronously. The
application-facing form remains an ordinary mount:

```nim
ui.mount(A())
ui.mount(RemotePanel(source))
ui.mount(C())
```

`RemotePanel` may initially produce no visible content and later materialize B
at the same sibling position. Application code must not need to declare a
slot, select a target by class or ID, calculate coordinates, or manually write
a conditional rendering branch for this lifecycle.

Required behavior:

- `ui.mount(component)` records a stable insertion position internally. The
  public component API does not expose that anchor as required authoring
  syntax.
- An empty or unavailable component contributes no width, height, intrinsic
  size, margin, flex item, or `gap`. It is also absent from paint, hit testing,
  focus order, input dispatch, and the exposed accessibility tree.
- When content becomes available, it enters normal Box/Flex flow at the
  original mount position. Its measured size reserves space and moves later
  siblings without overlap or application-authored coordinates.
- Clearing or hiding the content collapses that space and restores the sibling
  flow. Repeated materialize/clear cycles preserve order and deterministic
  component lifecycle behavior.
- The mounted component or library owns its asynchronous/loading state. The
  application consumes it as a normal component and is not required to know
  that conditional materialization occurs internally.
- Materialization invalidates only the affected style, layout, paint, hit-test,
  focus, and accessibility domains. It must not replay unrelated components or
  rebuild the whole UI tree.
- Existing `display: none` exclusion semantics remain valid, including the
  absence of phantom Flex gaps. A lower-level insertion/slot mechanism may
  exist internally or as an advanced API, but it is not the primary user
  contract.

Release tests cover row and column flow, Flex gaps, intrinsic and constrained
sizes, repeated asynchronous show/hide cycles, sibling order, focus transfer,
event isolation, accessibility exposure, subtree disposal, and bounded dirty
work on large trees.

The retained implementation uses the component root itself as the stable flow
position. `setMaterialized(false)` maps that root to an internal collapsed
state rather than disposing it or replaying `render`. The collapsed subtree is
excluded consistently from computed layout, intrinsic measurement, Flex gap
accounting, paint, hit testing, focus, event dispatch, and accessibility
export. A state change queues style/layout/paint/hit invalidation together with
the nearest containing flow root, allowing hosts with retained frame data to
use subtree style resolution and relayout. Async workers must hand results back
to the UI thread before mutating a component or its `UiRoot`.

### Open Event Contract And Library Isolation

Status: `Implemented on the Version 0.4 development line`

Implemented on this line: independent `EventOutcome` flags; stable `target`,
`currentTarget`, and phase data; precondition/user-observer/default ordering;
propagation-bounded default actions; replaceable public slots; removable,
subtree-owned subscriptions; typed library `Signal[T]`; dispatch-scoped,
non-owning focus, pointer-capture, invalidation, and frame actions;
allocation-free alias iteration; indexed dispatch with a large
unrelated-listener performance gate; one runtime `EventDefinition` table for
producer, payload, alias, propagation, and ABI metadata; and C ABI `0x0001000C`
parity using the same event registry, including additive C subscriptions and
explicit removal. ARC/ORC tests cover stale action capabilities, dispatch-time
removal, repeated listener churn, and subtree disposal. Shared/static C
consumers and Valgrind coverage exercise the foreign-language boundary. A
dedicated 500-root ARC lifecycle gate also covers temporary root captures that
are broken by dispatch-time unsubscription; Valgrind reports no retained
allocations. Public event names now live in that definition source as well.
One development-only generator emits the committed EventRegistry, NodeHandle,
CBSSComponent, and C event-kind surfaces, while CI rejects stale output. All
first-party handlers use explicit outcomes. The Boolean converter remains only
as a documented pre-0.4 source-compatibility bridge; Boolean-returning query and
convenience APIs report only success or handled state and do not encode the
three independent dispatch effects. A strict compile gate disables that bridge
while checking the runtime, public module, examples, and lifecycle probe so new
first-party handlers cannot silently reintroduce ambiguous Boolean outcomes.

CBSS must provide the event equivalent of its shared style and layout model: an
independently maintained component, chart, control, or design-system package
must be able to participate without modifying CBSS core, depending on another
library's internal widget implementation, or taking ownership of the
application's business logic. The ordinary component syntax remains concise:

```nim
saveButton.onClick = onSave
```

Assignment remains replacement-oriented for the component's public event slot.
The runtime contract underneath that syntax must distinguish preconditions,
application handling, default UI behavior, propagation, and observers.

Required behavior:

- Dispatch has three explicit stages: CBSS preconditions such as `disabled` and
  `inert`; the public user handler and permitted observers; then the control's
  intrinsic default action such as toggle, selection, expansion, or keyboard
  activation. A default action runs only when it has not been prevented.
- A typed result replaces the overloaded Boolean convention. At minimum it
  distinguishes `handled`, `stopPropagation`, and `preventDefault`; consuming
  one synthesized event must not accidentally suppress unrelated later events.
- Every dispatched event preserves the original hit or focus `target` and
  exposes a separate `currentTarget` while traversing ancestors. Event phase,
  local-coordinate validity, bubbling, and cancelability are explicit metadata.
- Non-bubbling kinds, including enter/leave and other kinds defined as local,
  remain on their intended target. Bubbling and capture behavior are properties
  of the event definition, not incidental consequences of walking every parent.
- Standard JavaScript/TypeScript-style slots remain the primary names for
  standard UI events. Data-rich library output that is not a standard event
  uses a typed Nim signal or callback contract rather than adding an untyped
  string or forcing every library-specific payload into `InputEvent`.
- Public assignment provides one replaceable handler slot. Deliberately
  additive observation returns an `EventSubscription` with explicit removal,
  an owning component or node, and automatic detachment during subtree disposal.
  A library can therefore add and remove behavior without accumulating stale
  callbacks on a stable node.
- Event handlers receive dispatch-scoped, non-owning UI actions for operations
  such as focus requests, pointer capture, invalidation, and frame requests.
  The documented safe path must not require a closure to retain `UiRoot`, and
  ARC tests must detect `UiRoot -> EventRegistry -> closure -> UiRoot` cycles.
- One declarative event-definition table owns event kind, producer class,
  payload shape, aliases, bubbling, cancelability, public setters, and C ABI
  mapping. An event with no producer is either omitted from the supported
  surface or explicitly identified as manually emitted/component-provided.
- Event aliases and traversal use allocation-free iteration on pointer, pen,
  touch, wheel, and keyboard hot paths. Nim and C ABI registries use indexed
  lookup rather than scanning every binding for each ancestor.
- The Nim and C APIs expose equivalent `target`, `currentTarget`, outcome, and
  propagation semantics. A language adapter must not observe a materially
  different event model from a native Nim component.

CBSS owns focus, disabled behavior, activation mechanics, selection, expansion,
and other reusable UI behavior. The callback owns what an activation means to
the application, including persistence, backend calls, navigation policy, and
other business logic. A component may package its own handler internally, but a
parent is not required to receive and forward an event bundle merely to place
that component.

This is an architectural difference from a QML-style integration model, not a
claim that QML lacks signals or extension mechanisms. CBSS deliberately avoids
making its UI declaration syntax the sole object, event, and library ABI.
Independent packages compose through ordinary Nim types and one stable CBSS
runtime contract; style ownership, event ownership, and business logic remain
separable.

Version 0.4 release tests must cover user/default ordering, prevention without
unintended propagation changes, original and current targets, local and
non-bubbling events, nested component isolation, handler replacement, additive
subscription removal, disposal during dispatch, late callbacks, ARC/ORC
lifecycle behavior, C ABI parity, and bounded work with large listener sets.
Tests that currently encode internal-before-user ordering or universal bubbling
must be corrected as part of this work rather than preserved as compatibility.

### UI Data Interchange: Blob, Form Data, And Streams

Status: `Partially implemented on the Version 0.4 development line`

Implemented on this line: immutable in-memory `Blob` snapshots with advisory
MIME metadata, bounded reads, slices, and explicit materialization limits;
ordered immutable `FormData` with repeated names and Blob-backed values;
TextInput, TextArea, Select, Checkbox, and Radio registration through
`form.register(name, control)`; collection diagnostics for disposed or
value-less fields; and C ABI `0x0001000C` Blob handles with retain/release,
bounded reads, and a 64 MiB eager-allocation ceiling. ARC/ORC value and form
tests plus shared/static C consumers and Valgrind cover this slice.

The typed `FileInput` is now implemented as a style-neutral control. It exposes
single/multiple and advisory accept metadata to an application-owned picker,
accepts only host-authorized immutable Blob values, emits standard input/change
events, and contributes ordered Blob entries to immutable FormData snapshots.
It never opens an arbitrary path or exposes a platform file handle.

Submit events on the Nim component surface now carry the already-collected,
immutable FormData snapshot. The common input event stays compact by allocating
its managed payload sidecar only for submit events; an intentionally empty form
remains distinguishable from a synthetic submit event with no snapshot.

C ABI `0x0001000D` now provides a bounded FormData builder plus immutable,
atomically retained snapshots. It preserves order and repeated names, shares
Blob handles by reference, uses caller-owned buffers for string queries, and
releases unfinished builder resources deterministically.

C ABI `0x0001000E` adds payload-aware EventView handlers and
`cbss_context_emit_submit` without changing the existing event struct or
callback signature. Submit payloads preserve ordered text and Blob entries,
empty snapshots remain distinguishable from payload-free synthetic events,
and callbacks may retain a snapshot beyond dispatch through explicit
retain/release ownership.

The bounded stream boundary is now implemented as two transport-neutral
layers. `StreamBridge[T]` is the UI-thread state machine and provides
deterministic open/data/progress/end/error/cancel/close ordering, item and
declared-weight backpressure, progress coalescing, exact terminal delivery,
cancellation that drops queued work, late-offer rejection, partial draining,
and ARC/ORC stress tests. `StreamMailbox[T]` is the bounded worker-to-UI
ownership-transfer layer.
It moves managed values through shared channel storage, uses atomically retained
producer handles, preserves a backpressured value without copying, coalesces
host-loop wake requests, invalidates escaped producers during automatic or
explicit disposal, and has real threaded ARC/ORC transfer tests. UI trees,
components, and `StreamBridge` remain UI-thread-owned rather than becoming
lock-based shared objects.

Remaining: host-authorized file/provider Blob sources, optional transport
adapters, C ABI transport, and broader cancellation/disposal race verification.

CBSS will define transport-neutral data contracts for UI operations that need
binary values, form snapshots, or progressively produced data. These contracts
belong at the UI boundary because images, clipboard content, file drops, file
inputs, progress indicators, and media surfaces need consistent ownership and
lifecycle behavior. CBSS does not become an HTTP client, multipart encoder,
filesystem policy layer, or media decoder by defining them.

#### Blob

A `Blob` represents an immutable binary resource with optional advisory MIME
metadata. Its source may be owned in-memory bytes, a host-authorized file
reference, a mapped resource, or a provider exposed through an adapter. A Blob
must preserve the following rules:

- Managed in-memory bytes use ARC ownership and may be shared without exposing
  mutable `seq[byte]` storage. Mutation requires producing a new Blob or a new
  immutable snapshot.
- Native files, mappings, provider handles, and foreign buffers have explicit
  close/release behavior. Destruction is deterministic and idempotent; an
  external resource is never kept alive solely by an accidental closure cycle.
- A file reference is not an authority grant. Opening it remains subject to the
  host application's sandbox, permission, path, size, and lifetime policy.
- MIME type is optional metadata supplied by the producer. Consumers must not
  trust it for security decisions without validating the content and permitted
  operation.
- Size is known when possible and bounded before eager allocation. Consumers
  may reject oversized data before materializing it in memory.
- The C ABI exposes opaque Blob handles with explicit retain/release and bounded
  read operations; Nim-managed pointers and backend-specific objects never
  cross the ABI.

Images, clipboard payloads, dropped files, form file values, and future media
sources should reuse this contract rather than inventing unrelated byte owners.

#### Form Data

CBSS form controls may produce a stable, ordered `FormData` snapshot containing
text values and Blob-backed file values. Collection is a UI responsibility;
serialization and transport are not. The existing typed controls remain the
input surface instead of being replaced by one stringly typed HTML-style
`input(type = ...)` constructor.

- `TextInput`, `TextArea`, `Select`, `Checkbox`, and `Radio` gain a common
  form-field contract and optional submission `name`. A typed `FileInput`
  provides one or more Blob values without exposing a platform file handle as
  ordinary application data.
- A `Form` registers descendant fields during declarative construction and can
  produce a snapshot through an API such as `form.collectData()`. A submit
  event may carry that already-collected snapshot so the handler does not need
  to walk the UI tree.
- Collection preserves field order and repeated names. It uses form/control
  ownership and explicit field names, not CSS selectors or required test IDs.
- Disabled or otherwise unsuccessful controls follow the documented CBSS form
  rules. Collection diagnostics identify unsupported control values instead of
  silently dropping them.
- A snapshot does not retain live references to mutable controls. Subsequent UI
  edits do not alter data already handed to application logic.
- Application logic may consume the snapshot directly. `joubako` may adapt it
  to JSON, NIF, multipart data, or another supported request representation.
- Multipart boundaries, content encoding, HTTP requests, authentication,
  retries, and backend policy remain outside CBSS and belong to `joubako` or
  the backend application. The `joubako` adapter remains optional and does not
  become a CBSS dependency.

This division allows `onSubmit` and other UI events to hand application logic a
complete value snapshot while keeping network and business behavior replaceable.

#### Streams

CBSS will define a consumer-side stream bridge for progressively delivered
immutable chunks and typed status updates. Producers may perform file reads,
downloads, backend event delivery, image decoding, or audio/video preparation,
but they do not mutate the UI tree from a worker thread.

The bridge contract includes:

- explicit open, data, progress, end-of-stream, error, cancellation, and close
  states with exactly-once terminal behavior;
- bounded queues and backpressure so a producer cannot grow UI memory without
  limit when rendering or decoding is slower than input;
- immutable chunks or ownership-transferred buffers across thread boundaries;
- marshaling onto the owning UI thread before changing component state,
  invalidation domains, textures, or render surfaces;
- coalesced progress and latest-result-wins updates where intermediate states
  have no semantic value, while ordered data streams preserve chunk order;
- cancellation and component-disposal integration so an unmounted consumer
  cannot receive late callbacks; and
- deterministic fake producers for unit, integration, and E2E tests.

CBSS owns attachment to components, lifecycle cancellation, UI-thread delivery,
and the resulting invalidation. It does not own sockets, HTTP semantics, retry
policy, general-purpose worker pools, codecs, or storage. `joubako` supplies
network-facing producers and FormData request encoding. Media and image
features may build adapters on this bridge while retaining their own resource
and scheduling policies.

The implemented stream boundary establishes both the bounded UI-side state
machine and an explicit worker-to-UI ownership-transfer mailbox. The mailbox
uses a coalesced host wake callback instead of requesting continuous frames;
the UI drains it and performs invalidation only when transferred events change
observable state. `ComponentStreamBinding[T]` now connects that pump to selected
dirty domains and is retained through the general component-owned resource
lifecycle. Subtree disposal closes the mailbox, drains retained payloads, and
rejects escaped producer handles exactly once under ARC and ORC. Release
completion remains gated on broader cancellation races and C ABI transport.
The SDL3 adapter now posts a coalesced, integer-token-only user event from the
worker callback. A real worker test proves that an SDL event loop blocked in
`SDL_WaitEventTimeout` wakes, routes only the matching binding, preserves stream
order, marks only configured dirty domains, and returns to an empty event queue.

## Authoring Value Model And Ergonomics

Status: `Partially implemented on the Version 0.4 development line`

CBSS should keep its typed, CSS-inspired value model while making common
authoring forms concise. This work is separate from CSS compatibility: a value
is exposed only when CBSS can resolve it for the relevant property, or when it
is explicitly documented as interchange metadata with a diagnostic boundary.

### Units

Lengths must remain unit-bearing values in the underlying value model. A bare
number cannot in general distinguish pixels from font-relative, percentage,
viewport-relative, or intrinsic-sizing intent. CBSS will therefore retain
explicit constructors such as `px(16)`, `percent(50)`, `em(1.25)`, and
`rem(1)` as the canonical and fully portable representation.

The authoring API may add property-specific shorthand where the property
grammar makes a pixel length unambiguous. This is a convenience overload, not
a change to the stored value model or a global rule that every number is a
pixel. For example, a high-level API may support:

```nim
width(320)              # shorthand for width(px(320))
width(percent(100))     # explicitly percentage-based
padding(12)             # shorthand for padding(px(12))
fontSize(14.5)          # shorthand for fontSize(px(14.5))
lineHeight(1.4)         # unitless line-height multiplier
lineHeight(px(24))      # explicitly length-based line height
opacity(0.8)            # unitless opacity
flexGrow(1)             # unitless flex factor
zIndex(10)              # integer stacking order
```

The low-level generic declaration path, including `decl(...)`, must remain
explicit for dimensional values. It lacks enough property-specific type context
to infer that an arbitrary number means pixels safely. This preserves a clear
escape hatch for generated styles, extension properties, and contributors who
need exact value intent.

Zero-length shorthand may be accepted where a property expects a length, but
it must resolve to an explicit zero length internally. It must not establish a
broader rule that all unitless values are lengths.

CBSS will follow CSS-like property semantics for unitless values only where
they are meaningful for that property. It must not reinterpret a number across
property categories: `1` may be an opacity, flex factor, font-weight,
line-height multiplier, z-index, or pixel length depending on the typed
property API. Ambiguous generic input must be rejected or require an explicit
constructor.

Planned work:

- Add typed property-level overloads for common dimensional properties where
  bare integers and floats have an unambiguous `px` meaning. The initial set
  should cover dimensions, offsets, margin, padding, gaps, border widths,
  border radii, and font size, subject to each property's final value grammar.
- Keep explicit-unit overloads alongside shorthand overloads for every
  supported dimension property. Shorthand must never make `percent`, `em`,
  `rem`, viewport units, or future units inaccessible.
- Define and test the unitless grammar per property. At minimum this includes
  opacity, flex factors, order, z-index, font weight, and both multiplier and
  length forms of line height where CBSS supports them.
- Reject a bare numeric shorthand for properties whose grammar is genuinely
  ambiguous, including multi-domain properties that accept a number, length,
  percentage, keyword, or other distinct value forms without a safe default.
- Document shorthand expansion in generated property documentation and API
  references so users can tell whether `12` means `px(12)`, a unitless number,
  or is invalid for a particular property.
- Complete property-specific resolution for the currently represented units,
  including percentage and font-relative values where their layout or font
  context exists.
- Add viewport-relative and font-metric-relative units only with defined
  resolution contexts and test coverage.
- Preserve the specified unit until the appropriate layout or text-resolution
  phase; renderer boundaries receive resolved floating-point coordinates.
- Reject or diagnose a unit/property combination that CBSS cannot resolve.
  Constructing a value must not silently produce a no-op.

The initial typed declaration API is implemented for dimensions and
constraints, positioned offsets, margin and padding, Flex gaps and basis,
border widths and radii, and font size. Bare numeric values in those APIs are
stored as explicit pixel lengths; every API also accepts an explicit
`StyleValue`, preserving `%`, `em`, `rem`, viewport, and intrinsic units.
Property-specific unitless overloads cover line-height multipliers, opacity,
Flex grow/shrink factors, font weight, order, and z-index. Integer-only APIs
for order and z-index reject fractional shorthand at compile time. The generic
`decl(...)` path remains unchanged and never infers units.

The Version 0.4 development line also implements `lh`, `rlh`, `ex`, `ch`,
`rex`, and `rch`. Resolution is
ordered as font size, line height, then dependent properties. In `font-*` and
`line-height` declarations these units use the parent metrics to avoid a
cycle; other properties use the current element and root computed line
heights. Standalone resolution without those contexts emits a diagnostic.
Font-glyph units use a versioned, injectable text-engine metrics contract.
The cosmic-text adapter reports the selected font's x-height and the shaped
advance of the `0` glyph, with results cached by resolved font configuration.
When no metrics provider is installed, or a provider cannot return a valid
metric, CBSS applies the CSS Values fallback of `0.5em`. This keeps the core
independent from cosmic-text while preserving deterministic headless and C ABI
behavior.

The design-source viewport-condition conveniences are named
`minViewportWidth(...)` and `maxViewportWidth(...)`. This keeps their return
type and purpose explicit while reserving `minWidth(...)` and `maxWidth(...)`
for style declarations in the umbrella authoring API.

### Colors

`Color` is distinct from a general `StyleValue`: styles may represent a solid
color, a color pair, gradient stops, border colors, shadow colors, and other
typed visual values. That distinction remains part of the runtime model.

The target is semantic compatibility with the supported CSS Color 4 authoring
surface, while retaining a typed Nim API rather than requiring CSS text for
ordinary Nim code. A serialized CSS color parser is provided for design
tokens, generated assets, external styles, and web-to-native migration. A
syntax is not considered supported merely because CBSS can store its source
text: it must have a specified conversion, interpolation, paint result, and
diagnostic behavior.

Capability plan and progress:

- Keep explicit `rgb(...)` and `rgba(...)` constructors for numeric color
  values and alpha.
- Parse hexadecimal forms, named colors, `transparent`, `currentColor`, modern
  and legacy RGB/HSL, HWB, Lab/LCH, Oklab/Oklch, and predefined `color()`
  spaces with strict diagnostics. This parser foundation is implemented in
  Version 0.3; consuming properties must still define their resolution
  contexts.
- Keep the implemented predefined `color(...)` spaces and typed/serialized
  `color-mix(...)` behavior where it is meaningful for CBSS declarations.
- Keep the implemented declaration overloads where `Color` or `ColorValue`
  unambiguously means a solid style color, so ordinary declarations do not
  require a `colorValue(...)` wrapper.
- Define interpolation-space behavior for gradients, transitions, and animated
  colors instead of relying on backend-specific blending.
- Treat device-dependent, wide-gamut, and system-color behavior as explicit
  capability work. Unsupported output profiles must diagnose or use a
  documented conversion; they must not silently render unpredictably.

#### Local CSS Color Parity

Color compatibility is intended to remove duplicate web and native color work
for designers. The same supported color value should be reusable by a web
design and a CBSS application without creating a separate native palette.

The conformance target is local rather than cross-device physical identity:

> On the same OS session, display, and output color space, a supported CBSS
> color value should produce a colorimetrically or perceptually equivalent
> result to the same value rendered by a reference browser.

This target does not promise that unrelated displays, ICC profiles, ambient
conditions, HDR modes, or hardware gamuts look identical. It does require CBSS
to preserve the specified color space and channels until the output conversion
stage, apply defined interpolation and gamut mapping, and avoid accidental
double color management.

Validation should include:

- normative conversion and parsing vectors derived from the CSS Color
  specification;
- comparative swatch, alpha-composition, and gradient rendering against a
  pinned reference browser on the same machine;
- exact channel checks where integer sRGB output permits them and documented
  Oklab/Delta-E tolerances where rasterization or conversion introduces
  rounding;
- SDR sRGB as the required baseline, followed by capability-gated wide-gamut
  and HDR output; and
- platform coverage that records the browser engine, compositor, output color
  space, ICC profile availability, and renderer backend used by each run.

Rendering backends receive resolved paint colors. SDL3, Pixie, a future GPU
Canvas, or another backend may implement the final raster operation, but none
may assign a different meaning to a public CBSS color value.

### Optional CPU Raster And Effects Backend

Status: `Planned evaluation`

Pixie is a candidate optional implementation backend for CPU-side raster and
image-processing work. Its useful scope includes paths, anti-aliased masks,
gradients, shadows, blur, blend modes, SVG rasterization, image transforms, and
other operations that would otherwise require a substantial independent
raster implementation.

Pixie is not the CBSS color specification, layout engine, public paint model,
or canonical type system. In particular:

- CBSS parses and resolves supported CSS Color 4 values before backend use.
- A Pixie adapter converts resolved CBSS paint data into Pixie operations.
- Backend-specific color, image, path, and allocation types do not enter the
  public Nim component contract or the C ABI.
- A Pixie-free build path remains supported for applications that do not need
  these effects.
- Cached Pixie output is uploaded or composed through the active SDL3 path;
  static output is not rasterized again every frame.

Effect execution policy must be selectable without changing the authored
visual value. Provisional policy concepts are:

- `auto`: CBSS chooses from invalidation state and active animation.
- `on-change`: regenerate only when source data, style, size, scale, or output
  color context changes.
- `every-frame`: explicitly allow continuous regeneration for an active
  effect.
- `manual`: retain output until the application explicitly invalidates it.

The exact public names remain subject to API design. The behavior must also
support application-level quality, memory-budget, and dynamic-effect limits.
Disallowed or unavailable effects produce a diagnostic rather than silently
changing appearance.

Deployment profiles should make capability and footprint intentional:

- an embedded profile for SDL3-capable Linux SBCs and comparable devices,
  with bounded caches and optional effects;
- a standard profile for ordinary native applications; and
- a full visual profile with CPU effects and later GPU capabilities.

Microcontroller, RTOS, and bare-metal support is not an initial requirement.
The embedded target begins with SDL3-capable Linux systems. Before Pixie can
become a recommended dependency, release builds on amd64 and arm64 must measure
binary size, startup time, idle and active RSS, first-generation cost, cached
frame cost, and temporary-buffer peaks at embedded-relevant resolutions.

#### C ABI Boundary

The existing 16-byte `CbssColor` remains the stable resolved RGBA interchange
value and must not be enlarged in place. Extended CSS Color 4 input should use
new versioned constructors or opaque CBSS-owned color-value handles, with
corresponding style setters. Existing RGBA callers remain source- and
binary-compatible.

Pixie handles and Nim-managed Pixie objects never cross `include/cbss.h`.
Backend selection, effect policy, and capability queries are represented by
CBSS-owned enums, options, opaque handles, and status codes. Static or shared
CBSS artifacts may contain the selected implementation internally, but foreign
callers depend only on the versioned CBSS ABI.

### Keywords And Closed Value Sets

Status: `Partially implemented on the Version 0.4 development line`

`keyword(...)` remains the extensible lower-level representation for
property-specific values that are not yet closed or may expand over time. It
should not be the preferred surface for common, closed sets such as flex
direction, alignment, overflow, or cursor kinds.

Planned work:

- Add typed helpers or enum-backed APIs for common closed value sets.
- Keep a documented lower-level keyword path for extension and explicitly
  supported metadata use cases.
- Validate keywords against the property that consumes them and report
  unsupported values instead of accepting and ignoring them.

The initial typed surface accepts existing CBSS enums for display, Flex
direction and wrapping, alignment, positioning, box sizing, overflow, pointer
events, cursor, selection, resize, font style, and text alignment. These
helpers serialize to the same validated property operations as the lower-level
keyword path, so they add LSP completion and compile-time type checking without
creating a second runtime representation.

## GPU Canvas Capability

Status: `Planned`

CBSS will support optional GPU-backed drawing inside the standard Canvas
element. This is a capability for game scenes, charts, visualizations, image
processing, and other custom drawing workloads; it is not a second renderer
for normal CBSS buttons, text, or style properties. Normal UI retains one
canonical visual contract.

The related ordinary-UI WGSL goal keeps that canonical contract: CBSS performs
CPU-owned Style resolution, layout, text shaping, and normal paint first, then
lets a typed GPU Style effect paint under, over, mask, or filter a bounded
retained element/layer texture. It does not require a GPU-specific Button or a
second interpretation of Flex, text, events, or accessibility. Static CPU
content remains baked while an animated WGSL overlay runs, so shader-only
frames do not repeat layout, shaping, or unrelated paint work.

The initial implementation target is the SDL3 GPU API, with explicit resource,
swapchain, shader, synchronization, resize, and device-loss ownership rules.
`wgpu-native` is also a planned optional CBSS GPU Canvas backend for workloads
that benefit from a WebGPU/WGSL contract, such as custom visualizations,
camera-frame effects, tile maps, and game scenes. It remains behind the same
Canvas contract and must not create a second renderer-specific interpretation
of ordinary CBSS UI properties.

CBSS will not claim exclusive ownership of the machine's GPU. A separate
backend process may own an independent compute device and return bounded Blob,
Stream, or immutable snapshot results. An in-process backend using the selected
GPU API may register compute work through a host-owned submission capability,
with one present owner and explicit queue, resource, fence, memory-budget,
device-loss, and shutdown rules. Different GPU APIs use bounded CPU staging by
default; platform-specific external-memory sharing is optional and never an
implicit requirement.

The wgpu profile additionally requires one canonical low-level Nim binding and
one exact `wgpu-native` runtime version per process. A versioned `GpuHost`
supports either a CBSS-owned Device/Queue or a compatible application-owned
Device/Queue borrowed by CBSS; ownership is never inferred. CBSS remains the
single Surface/Present owner for its window in both modes. Independent Nim GPU
packages retain cross-frame pipelines, buffers, textures, and shaders through
budgeted owner-specific resource namespaces and submit work through the shared
frame scheduler rather than creating another swapchain or hidden queue policy.
Release qualification includes a same-process real-GPU fixture combining CBSS
Motion/WGSL rendering and an independent compute package on one Device, Queue,
and Swapchain, including device loss, cancellation, teardown order, version
mismatch, and GPU-memory limits.

The complete staged plan, including GPU Canvas composition, visualization APIs,
application compute coexistence, game UI, external engine integration, and
WGSL-backed Custom Styles, is maintained in
[render-surface-roadmap.md](render-surface-roadmap.md). The Custom Style target
ends at declaratively attaching packaged WGSL paint to a CPU-defined CBSS
element and composing it through the existing Style, layout, clip, state, and
invalidation model. Shader-derived event geometry is a separate exploratory
track, not a default cost or a Version 0.4 release gate; ordinary elements and
Custom Styles retain their logical Box/transform hit path.

## Motion, Transform, And Native Visual Surfaces

Status: `Planned`

CBSS should support the CSS-inspired motion and geometric vocabulary needed by
modern application UI without adopting a browser or a virtual-DOM redraw
model. A change that animates paint-only state must not force unrelated nodes
to resolve style or relayout on every frame.

### Transforms And Transitions

Current and planned work:

- Implemented: `translate`, `scale`, `rotate`, transform origin, and 2D
  composition order use a single layout, paint, hit-test, clip, and
  RenderSurface coordinate contract. Canvas uses the same affine paint scopes.
- Complete the 2D vocabulary with typed skew and matrix operations while
  preserving the same inverse hit-test and transformed-clip contract.
- Add perspective, perspective origin, `transform-style: preserve-3d`, and
  `backface-visibility` only as a coherent 3D scene/composition contract;
  storing these values as transform metadata is not runtime completion.
- Add declarative transition property, duration, delay, timing-function, and
  interpolation behavior for supported style values.
- Implemented foundation: typed float/color keyframes and the animation clock
  resolve and interpolate deterministically; declaration-driven keyframe
  binding remains planned.
- Implemented: frames are scheduled only while timed work, caret blink,
  scrolling motion, or Canvas requests one; idle UI remains event-driven.
- Implemented foundation: the animation clock accepts reduced-motion policy;
  platform preference adapters remain planned.

### CSS-Like Motion Scene

Status: `Planned after declarative transition binding`

CBSS will provide a retained Motion Scene inside Canvas for motion graphics,
generative design, high-density charts, particles, sprites, and other visuals
whose animated object count should not become an equal number of ordinary UI
layout nodes. This is more than accepting a completed frame from an external
renderer: CBSS owns how visual objects are drawn, composed, clipped, layered,
hit-tested, scheduled, and presented inside the resolved Canvas box.

Application code and independent Nim libraries may own simulation, media
decoding, physics, effect calculations, procedural data, and business logic.
They publish typed object data or immutable scene snapshots. CBSS consumes
those results through its Motion Scene and executes the visible composition.

The intended authoring model combines CSS-inspired visual properties with
typed native extensions:

- shared properties such as transform, opacity, clip, mask, blend mode,
  filter, z-order, animation, and keyframes;
- stable visual-object identities for selection, pointer hit testing,
  dragging, handles, context menus, and inspection;
- native motion capabilities such as shaders, uniforms, particles, sprites,
  cameras, render layers, and compute workloads without pretending that they
  are standard CSS properties; and
- ordinary CBSS Boxes, text, controls, and overlays composed around and above
  the Motion Scene without a second window or WebView.

Dependency order is deliberate:

1. Complete declarative transition and declaration-bound keyframe behavior for
   ordinary UI. This establishes one clock, interpolation registry, reversal
   behavior, reduced-motion policy, and dirty-domain contract.
2. Add a deterministic CPU Motion Scene reference path. It must support
   batched object storage, stable IDs, snapshot replacement, cancellation, and
   headless tests without requiring a GPU.
3. Add an SDL3 GPU execution path using instancing, storage buffers, render
   passes, compute passes, and offscreen Canvas composition where appropriate.
4. Add `wgpu-native` as an optional backend behind the same Motion Scene and
   GPU Canvas contract for applications that require WebGPU/WGSL-oriented
   shaders and compute.
5. Add higher-level generative-design and motion-graphics libraries as normal
   Nim packages rather than hard-coding an After Effects, chart, or game
   product into CBSS core.

Implementation starts after declarative transitions, but these constraints
apply immediately so transition work does not close the path:

- UI transitions and Motion Scene tracks use one monotonic time model and
  compatible typed interpolation rules.
- GPU handles and backend-specific shader objects do not enter `Node`,
  `ComputedStyle`, or the public ordinary-UI paint contract.
- A Canvas remains one layout participant even when its Motion Scene contains
  many thousands of visual objects.
- Worker-produced data crosses into the UI as bounded immutable snapshots or
  buffers; application code does not manage a thread per object.
- Preview updates may use latest-result-wins replacement, while deterministic
  export and test paths preserve requested frame order.
- Continuous frames are requested only while motion or rendering work is
  active; a static Motion Scene returns to event-driven idle behavior.

Motion, GPU, Pixie, media, and shader packages remain opt-in imports. They are
not re-exported by the standard umbrella module and are not linked or deployed
for applications that do not select them. A CPU/SDL 2D profile remains a
supported build target for 64-bit Raspberry Pi-class Linux systems. GPU
capability is detected explicitly and has a deterministic CPU fallback or a
clear diagnostic; installing CBSS source does not imply shipping every native
backend in the application artifact.

Compile-time capability profiles enforce this boundary rather than relying
only on linker dead-code elimination. A selected profile controls Nim imports,
native bridge builds, linker inputs, staged runtime libraries, shaders, codecs,
and generated assets. Unselected capabilities must be absent from the final
dependency closure. The configuration tool may generate a project-local
`cbss_app` entry module so application code retains one stable import while the
generated module imports and re-exports only the selected capabilities.

The supported profile families are:

- `standard`: ordinary UI, text, SDL 2D, CPU Canvas, events, accessibility
  semantics, transitions, and the default controls;
- `motion-cpu`: `standard` plus the deterministic CPU Motion Scene;
- `motion-sdl-gpu`: Motion Scene and GPU Canvas through the SDL3 GPU backend;
- `motion-wgpu`: the optional `wgpu-native` implementation of the same public
  Motion Scene and GPU Canvas contract;
- separate opt-ins for Pixie effects and media codecs; and
- `full`: a convenience development/distribution profile that selects every
  capability supported on the target without changing their public contracts.

CI records stripped release artifact size and native dependency closure for
representative `standard` and `full` builds. A feature may not silently enter
`standard`, and unexpected artifact growth is treated as a release regression.
Runtime memory budgets remain separate because textures, decoded frames, font
caches, and scene buffers can dominate executable size on small systems.

This track extends the browser CSS-plus-Canvas/WebGPU authoring model instead
of reproducing JavaScript's main-thread limitations. Its product value depends
on hiding scheduling, batching, synchronization, and backend details behind a
Web-like import-and-mount experience for Nim authors.

The corresponding complex-game design treats CBSS as the frontend and
presentation owner rather than the gameplay engine. Fixed-step Nim simulation,
ECS, physics, AI, persistence, and networking publish bounded immutable scene
snapshots; a data-oriented Visual Scene batches tiles, sprites, particles,
chart-like marks, and other repeated objects without creating one CBSS Node per
item. CBSS composes that CPU/WGSL-rendered scene with its HUD, controls, dialogs,
accessibility UI, and one final presentation owner. The detailed 2D target,
thread/snapshot boundary, interaction model, batching rules, and separate 3D
integration boundary are specified in
[render-surface-roadmap.md](render-surface-roadmap.md#complex-game-frontend-architecture).

### Sprites And Tile Maps

Sprite animation and tile-map drawing are opt-in CBSS game modules, not
general-purpose application widgets. They use the same SDL renderer, texture
cache, input routing, coordinate conversion, and frame scheduler as Canvas,
which avoids requiring a second lifecycle and resource-management layer in an
external package. Applications still supply their own sprites, textures, map
files, and game data. CBSS does not bundle Tiled itself: its game module reads
the needed subset of a Tiled-exported JSON map, operates on that map data, and
draws it through the shared SDL/Canvas path.

Planned work:

- An opt-in CBSS sprite-animation module with texture regions, frame timing,
  loop policy, playback state, and optional frame events.
- An opt-in CBSS Tiled-output importer/renderer that reads the required subset
  of Tiled JSON and renders application-owned tilesets and map data inside a
  normal CBSS box. It includes clipping, viewport transforms, layer
  visibility, tile flip flags, and Tiled tile animation, but does not ship the
  Tiled editor or a copy of its implementation. TMX/XML and less common map
  orientations can follow after the JSON/orthogonal path is stable.
- Cached static layers and dirty-region updates so a changing sprite or tile
  region does not repaint unrelated UI.
- Pointer, keyboard, focus, and coordinate conversion behavior consistent with
  Canvas and surrounding controls.
- Examples for animated application decoration, data-dense tiled views, game
  HUDs, and a UI panel using a tile map as a normal visual surface.

The user-facing API should remain declarative where possible. CSS-inspired
styles describe how a surface is placed and composed; typed Nim data and
callbacks describe sprite frames, tile data, and application-specific behavior.

## Camera And Audio Media Capability

Status: `Planned`

CBSS should make camera previews, media visualization, and sound usable in the
same native application without treating them as browser-only features. Media
behavior remains an explicit typed API; CSS-inspired declarations describe the
layout and visual composition of the associated surfaces, not device access or
business policy.

### Camera And Video Input

Planned work:

- A camera/video-input surface whose preview is a normal CBSS layout
  participant, with sizing, clipping, opacity, transform, stacking, and input
  behavior consistent with Canvas and image surfaces.
- Explicit device enumeration, selection, permissions, lifecycle, format,
  frame-rate, resize, and error reporting through platform adapters.
- Frame delivery to Canvas or GPU Canvas for effects, overlays, computer
  vision, recording integrations, and visualization without copying unrelated
  UI layers.
- Clear consent boundaries: CBSS never opens a camera implicitly, and the
  application owns user intent, persistence, upload, and recording policy.

### Audio

Planned work:

- A project-owned audio abstraction for sound effects, music, streaming,
  capture, volume groups, pan, playback state, and optional spatial audio.
- `miniaudio` is the preferred initial backend candidate because it offers
  low-level device access and a higher-level mixing/resource layer in C, with
  a permissive public-domain or MIT-0 license. The adapter must pin a version
  and expose a stable CBSS-owned contract rather than leaking miniaudio's ABI.
- Audio callbacks must remain real-time safe: no UI-tree mutation, blocking
  I/O, allocation, or device start/stop work on the audio callback thread.
- Explicit scheduling and shared clock interfaces for synchronizing sprite
  animation, video, Canvas effects, and audio when an application needs it.
- Device-loss, permission, interruption, and fallback behavior covered by
  headless tests and native integration tests where devices are available.

Audio is not a CSS property system. Styles can control the visual presentation
of an audio player, waveform, meter, or media control; typed APIs control what
is played, captured, mixed, or recorded.

## Pen, Touch, And Expressive Input

Status: `In progress`

CBSS should support pen input as more than mouse emulation. A stylus can still
participate in ordinary pointer interaction, while Canvas, drawing controls,
and applications that need it can receive the richer pen data without losing
the common event model.

Planned work:

- Implemented on the Version 0.3 development line: one typed pointer metadata
  contract shared by mouse, touch, and pen; source timestamps;
  stable-in-process device identity;
  optional pressure, tangential pressure, x/y tilt, rotation, distance, and
  slider axes; contact, buttons, eraser, and proximity state; SDL3 event
  conversion; Canvas/RenderSurface-local routing; C ABI transport; and
  deterministic injected-event tests. Axis availability is explicit and no
  unsupported value is fabricated.

- A typed `PenEvent` carrying stable-in-session device identity, local and
  window coordinates, contact state, buttons, eraser-tip state, and timestamp.
- Normalized pressure, tangential pressure, x/y tilt, barrel rotation,
  distance/proximity, and slider data when the operating system and device
  provide each axis.
- Down, up, motion, axis, button, proximity-in, and proximity-out handling,
  with pointer capture and Canvas-local coordinate conversion that agree with
  mouse and touch behavior.
- High-rate motion coalescing and stroke interpolation that preserve drawing
  quality without triggering a layout or full UI repaint for every sample.
- Declarative drawing surfaces where CSS-inspired styles control box placement,
  clipping, compositing, opacity, transform, and stacking; typed brush and
  application data control pressure-to-width, opacity, texture, and eraser
  behavior.
- Capability reporting and graceful fallback to ordinary pointer input. Not
  every OS, driver, or pen reports every axis, so unavailable data must be
  distinguishable from a meaningful zero value.
- Native device tests where contributors have compatible hardware, alongside
  deterministic injected-event tests for routing, pressure curves, and stroke
  generation.

## Version 0.5+ - Ownership Contract And Release Verification

Status: `Planned`

CBSS will guarantee its own ARC ownership and native-resource lifecycle when an
application uses the documented safe public API and follows its explicit
lifecycle rules. This guarantee covers references and resources owned by CBSS;
it does not claim to validate arbitrary user-created reference graphs, global
state, raw pointers, or foreign libraries.

ARC is the required release-verification baseline. ORC remains a supported
compatibility option, but cycle collection must not hide a cycle created by the
CBSS runtime, an official control, or a documented example. Static analysis can
reject known unsafe ownership shapes, but it cannot prove the absence of every
runtime leak. The release gate therefore combines static contract checks with
generated lifecycle probes.

The static verifier should:

- detect strong `UiRoot` back-references in handles or state captured by event,
  animation, render-surface, and scheduler callbacks;
- distinguish owning references from explicitly non-owning `{.cursor.}` handles
  and report a reference whose lifetime is not bounded by an owner;
- require native resources and foreign-provider handles to declare deterministic,
  idempotent `close`/`destroy` behavior and reject unsafe implicit copying of
  unique owners;
- validate C ABI create/retain/release/destroy contracts against the exported
  ownership manifest; and
- inspect CBSS core, official controls, generated bindings, and documented
  examples under the same rules.

The dynamic verifier should generate or accept lifecycle scenarios that mount,
interact with, replace, unmount, cancel, close, and destroy components under
`--mm:arc`. CI executes those probes with Valgrind and supported sanitizers,
including late callbacks, cancellation races, Blob/provider release, stream
shutdown, and C ABI consumers. A static pass is not reported as proof of leak
freedom without the matching runtime lifecycle pass.

This verification is development-only. Ownership tracing, generated probes,
sanitizer hooks, and verifier implementation code are not imported, linked, or
packaged into normal application artifacts. CBSS release branches and official
examples use the strict gate in CI. An optional checker may help advanced API
and adapter authors, but correctness of arbitrary application memory management
is outside the CBSS guarantee.

### CSS Property Runtime Completion

Status: `Version 0.5+ candidate; priority order not yet decided`

The canonical property target remains in
[css-property-support.md](css-property-support.md), and every targeted property
has a provisional rank in
[css-property-implementation-order.md](css-property-implementation-order.md).
Those ranks are planning input rather than a fixed Version 0.5 execution order.
The owner may reorder the following work packages after evaluating user
feedback, subsystem dependencies, and release goals.

A property is not complete merely because the registry accepts its name or
ComputedStyle preserves its value. Promotion to `Runtime` requires a consumer
in layout, paint, text, hit testing, input, accessibility, or another visible
runtime subsystem, together with focused behavior and boundary tests.

Before publishing a new completion percentage, audit every current `Computed`
entry against the implementation. Existing consumers for `aspect-ratio`,
`letter-spacing`, `word-spacing`, `order`, `align-self`, and textarea `resize`
show that the support matrix can conservatively lag the code. The matrix,
implementation order, default registry, and generated summary remain
machine-checked, while semantic promotion requires code-and-test review.

Candidate work packages:

- **Box and Flex layout fidelity.** Complete executable `box-sizing`,
  multi-line `flex-wrap` and `flex-flow`, line distribution through
  `align-content`, and the remaining item/container alignment properties.
  Preserve stable intrinsic sizing, min/max constraints, gaps, ordering,
  percentage resolution, scrolling overflow, and dirty-subtree behavior in
  both row and column layouts.
- **Background geometry and composition.** Connect `background-position`,
  `background-position-x`, `background-position-y`, `background-size`,
  `background-repeat`, `background-clip`, and `background-origin` to the
  shared SDL3 and headless paint contract. Then connect attachment and blend
  behavior without introducing an idle redraw loop or backend-specific style
  semantics. Linear-gradient support remains the reference image path.
- **Everyday text behavior.** Finish visible `text-overflow` and ellipsis,
  `text-transform`, `text-indent`, supported `text-wrap` forms, word breaking,
  overflow wrapping, and hyphenation behavior. Letter and word spacing remain
  consistent across measurement, shaping, caret geometry, selection, input,
  textarea scrolling, and both text backends.
- **Writing direction and logical geometry.** Replace the current
  horizontal-LTR physical aliases with explicit `direction`, `unicode-bidi`,
  and `writing-mode` behavior before claiming general logical-property
  compatibility. Layout, text shaping, focus traversal, scrolling, and hit
  geometry must agree on the resulting axes.
- **Visual effects and advanced text.** Connect `filter`, `backdrop-filter`,
  masks, blend/isolation behavior, and the remaining decoration and typography
  properties only through shared paint/text contracts with deterministic
  headless references. Optional Pixie or GPU implementations must not change
  authored semantics or make the standard profile depend on them.

Every selected work package includes negative and unsupported-value
diagnostics, cross-backend reference tests where pixels are affected, and
performance tests proving that a local property change does not resolve or
relayout unrelated subtrees. `No plan` properties remain outside these
candidates unless a later design decision explicitly moves them into the
target.

## Later Milestones

Later milestones remain intentionally unversioned until Version 0.2 APIs and
runtime behavior are stable. Tooling plans for galleries, plugins, MCP
integration, and design-source adapters are tracked separately in
[tooling-roadmap.md](tooling-roadmap.md). Native Canvas, visualization, game
UI, and external-renderer integration are tracked in
[render-surface-roadmap.md](render-surface-roadmap.md). The broader capability
mapping against the roles commonly supplied by HTML, CSS, and JavaScript is in
[web-platform-capability-roadmap.md](web-platform-capability-roadmap.md).
