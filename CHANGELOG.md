# Changelog

All notable user-facing changes will be documented in this file.

The project follows Semantic Versioning after the initial developer-preview
release. Before 1.0, minor releases may contain public API changes.

## [Unreleased]

### Added

- `place-content` now executes as a Flex layout shorthand. One keyword applies
  to both content axes, while two keywords independently set cross-axis
  `align-content` and main-axis `justify-content`; invalid compound values are
  rejected without partially changing either axis.

- `image-rendering` now selects SDL3 texture sampling at draw time: `auto` and
  `smooth` use linear filtering, `crisp-edges` uses nearest-neighbor filtering,
  and `pixelated` uses SDL's pixel-art scaling. Rounded-image cache entries are
  partitioned by sampling mode so differently styled uses cannot alias.

- `accent-color` now inherits through the computed-style tree and colors the
  generated active parts of Checkbox, Radio, Switch, and Slider controls.
  Explicit `auto` preserves each component's fallback Style, and typed
  generated-part metadata prevents the color from leaking into ordinary
  application boxes or text.

- `caret-color` now reaches generated TextInput and TextArea insertion carets.
  Generated parts are identified by a typed node marker rather than public IDs
  or Style group names, `auto` preserves the component fallback color, and the
  computed value now follows inherited-property semantics.

- Background geometry now reaches the shared paint runtime for the
  linear-gradient image path. `background-position`, axis-specific position,
  `background-size`, `background-repeat`, `background-clip`, and
  `background-origin` resolve against border, padding, and content boxes in
  both SDL3 and the deterministic PPM backend. Repetition remains one bounded
  paint command and uses tiled SDL rendering, with a visible-pixel-bounded
  allocation-failure fallback for subpixel tiles. The supported value subset
  and remaining multi-layer, two-value, and `space`/`round` work are recorded
  in the property matrix.

- `text-align` now controls executable per-line text geometry instead of only
  resolving into computed style. `start`/`left`, `center`, and `end`/`right`
  share placement across Cosmic Text rasterization, the deterministic text
  engine, caret layout, hit testing, SDL3 debug text, shaping caches, explicit
  lines, soft-wrapped lines, and first-line `text-indent`. Alignment requires a
  finite line width; unconstrained intrinsic measurement remains unshifted.
  Logical `start`/`end` currently follow the documented horizontal-LTR contract,
  while `text-align-last` remains computed-only pending per-visual-line control.

- `text-indent` now executes as first-line text geometry instead of stopping at
  computed style. Positive and negative lengths participate in shaping,
  wrapping, measurement, caret placement, hit testing, UTF-8-safe ellipsis,
  Cosmic Text bitmap caching and raster offsets, SDL3 debug rendering, and
  transform-layer bounds. Authored newlines and wrapped continuation lines
  return to the normal inline start; percentage indentation remains future
  work.

- The CSS runtime support audit now recognizes five previously conservative
  entries as executable behavior: `aspect-ratio`, `order`, `letter-spacing`,
  `font-size-adjust`, and textarea `resize`. Each promotion is backed by an
  existing layout, text-engine, or widget consumer and focused behavior tests;
  properties that are only partially connected, including `word-spacing` in
  the Cosmic Text path, remain `Computed`.

- `text-overflow: ellipsis` now executes for no-wrap text through the shared
  layout and paint contract. The active text engine measures each explicit
  line, truncates only at UTF-8 rune boundaries, and stores the resulting
  paint string without mutating Node text. SDL3, headless, C ABI, and future
  GPU renderers therefore consume the same overflow result; Cosmic Text and
  deterministic reference-engine behavior are covered separately.

- Text measurement, caret geometry, hit testing, and layout now share one
  UTF-8-safe wrapping result. Normal wrapping preserves words, while
  `overflow-wrap: anywhere`, legacy `word-wrap`, and `word-break: break-all`
  can wrap long runs at rune boundaries. `white-space: nowrap`/`pre` and
  `text-wrap: nowrap` disable soft wrapping without suppressing authored line
  breaks. Cosmic Text and the deterministic reference engine use the same
  wrapping contract, and measurement does not allocate unused caret samples.

- `text-transform` now executes through the shared text pipeline. `uppercase`,
  `lowercase`, and `capitalize` use Unicode simple case mapping for layout and
  paint, while source/display byte-boundary mapping keeps caret placement, hit
  testing, selection, and editable control values coherent when UTF-8 widths
  differ. Source Node text and submitted values remain unchanged.

- Flex items whose final main or cross size changes now re-arrange their
  retained descendants against that final size. Grow, shrink, `flex-basis`,
  and stretch therefore update percentage sizing, nested alignment, text
  measurement, absolute descendants, and overflow metrics instead of changing
  only the item's outer box. Re-arrangement is limited to changed item
  subtrees and reuses its temporary storage.

- Added executable first-baseline alignment for horizontal Flex rows.
  `align-items: baseline` and `align-self: baseline` now align mixed font
  sizes, images, and nested row components using line ascent/descent metrics.
  Baselines are aggregated independently per wrapped line and compose with
  `row-reverse`; column-axis baseline currently falls back to cross-start
  until vertical writing-mode baseline sets are implemented. Cosmic Text
  exposes font baseline metrics through a new additive C ABI function without
  changing the existing font-unit metrics result.

- Completed the physical main-axis direction surface for Flex layout.
  `row-reverse` and `column-reverse` now work through `flex-direction`,
  `flex-flow`, and typed authoring, including wrapping, gaps, margins,
  justification, intrinsic sizing, and composition with `wrap-reverse`.
  Reversal changes visual coordinates only; order-modified paint/hit order,
  source-based focus traversal, and accessibility semantics are not reversed.

- Connected multi-line Flex layout to the runtime. `flex-wrap` and `flex-flow`
  now form independent row or column lines, `wrap-reverse` mirrors the cross
  axis, `align-content` distributes lines, and row/column gaps participate in
  both layout and overflow geometry. Grow and shrink redistribution freeze at
  item min/max constraints on each line; `space-around`, `space-evenly`, and
  `stretch` content distribution are available through typed authoring.

- Connected `box-sizing` to the layout runtime. `content-box` remains the CSS
  default, while `border-box` now keeps quantitative width, height, min/max,
  and flex-basis values as outer dimensions. Padding, visible borders, percentage
  child sizing, intrinsic sizing, aspect ratios, scrolling gutters, clipping,
  and absolute positioning share the resulting content-box geometry.

- Added logical accessibility range semantics for virtualized collections.
  Materialized item roots expose one-based `positionInSet` and total `setSize`
  values through the neutral accessibility tree, AT-SPI snapshots and diffs,
  and append-only C ABI accessors without retaining one node per logical item.

- Added stable-key focus retention for virtualized items. `VirtualFocusMemory`
  restores a focusable descendant after its logical item is rematerialized,
  prefers explicit node `code` over structural paths, preserves focus-visible
  state, rejects ambiguous code matches, and cancels restoration after any
  intervening user or application focus operation.

- Added stable-key virtual node materialization on top of the bounded range
  planner. `VirtualNodePool` retains Node IDs and mounted component lifecycle
  for keys that remain visible, mounts and disposes only entering/leaving keys,
  restores child order during reverse scrolling or data reordering, rejects
  shared hosts and duplicate keys, and rolls back partial mount failures.
  A release benchmark keeps 30 materialized nodes and a 36-slot node arena for
  both 100,000 and 10,000,000 logical items.

- Added the first production data-virtualization primitive: a typed virtual
  range planner with sparse measured-extent correction, asymmetric overscan,
  bounded materialization, clamped scroll offsets, and anchor correction. It
  plans 100,000 and 10,000,000 logical rows without retaining or scanning one
  entry per row. Stable-key node reuse, focus retention, and accessibility
  range integration are layered over that bounded plan.

- Named the independently released
  [`bgfxim`](https://github.com/puffball1567/bgfxim) package as the low-level
  Nim C99 binding for the planned optional bgfx GPU adapter. The binding is
  available separately; CBSS ownership integration and real-GPU qualification
  remain Version 0.7 work.

- Added a test-only cross-Driver reference application. C++14 and Rust now run
  the same Craft Style, layout, event ordering, invalidation, FormData submit,
  Store transaction, Navigation, Command/Cue cancellation, late-completion
  containment, diagnostic, and teardown scenario and must produce the same
  versioned trace and checked-in expected result. The same applications now
  also produce byte-identical deterministic PPM reference images covering
  layout, border, shadow, rounded background, and `oklab` linear-gradient
  paint. The reference raster entry point is compiled only for this test and
  is absent from normal C ABI artifacts.

- Added RAII/owned Blob and immutable FormData APIs to the C++14 and Rust Craft
  Drivers. Ordered repeated text and Blob values, bounded reads, payload-aware
  handlers/subscriptions, callback-lifetime-safe snapshots, and
  validation-first submit now share the canonical C ABI semantics. Driver
  Validation Forms can register serializable controls, collect their current
  values in field order, skip disabled fields, and emit the collected snapshot
  without rebuilding or walking the UI tree. FormData remains transport-neutral
  and does not pull multipart or network behavior into CBSS.

- Added typed validation cores to the C++14 and Rust Craft Drivers with the
  same 40 synchronous operations, first-failure ordering, optional/required
  precedence, current peer references, custom rules, and retained reporting
  policies as the canonical Nim API.
- Added retained `ValidationControl<T>` attachment and heterogeneous
  `ValidationForm` coordination to both reference Drivers. Additive input/blur
  observation now synchronizes invalid state and messages, skips disabled
  controls, preserves application handlers, and focuses the first invalid
  registered control without replaying the form tree. Weak peer-dependency
  edges revalidate only declared cross-field dependants.
- Extended C ABI `0x00010019` with bounded compiled validation-pattern and
  canonical string-format checks. Foreign Drivers share Nim's linear-time
  regex and email/URL/UUID/IP/date/time semantics instead of depending on
  host-specific regex or parser behavior.
- Added typed asynchronous Commands to the C++14 and Rust Craft Drivers with
  latest-only, ordered, and concurrent policies, bounded worker-to-UI
  completion queues, stable tickets, cancellation, settlement observers,
  wake coalescing, backpressure, and deterministic late-result rejection.
- Added typed Cue graphs to the C++14 and Rust Craft Drivers with iterative
  serial progression, delayed parallel branches, all/any/race joins,
  restart/ignore/queue/parallel start policies, independent monotonic clocks,
  cancellation and late-result containment, and component-owned teardown.
- Added typed screen-transition hooks to the C++14 and Rust Craft Drivers.
  Retained outgoing and incoming roots, deterministic phase/progress context,
  monotonic next-frame deadlines, immediate legacy sync, navigation reentry,
  cancellation, and teardown now match the canonical Nim screen host without
  requiring a continuous frame loop.

- Added the bounded Craft Pack Version 1 manifest and JSON Schema for declaring
  distributable Craft Components, public Style Slots, Craft Styles, assets,
  feature profiles, platforms, and ABI/capability compatibility requirements.
- Added atomic Craft Pack and Craft Style replacement through Nim, C, C++, and
  Rust APIs, with stable typed diagnostics, copied input boundaries, explicit
  source limits, and active-resource queries.
- Added Craft Driver capabilities for Craft Style and Craft Pack loading. Both
  ARC and ORC now exercise the new APIs through shared and static C ABI builds.
- Added C ABI subtree lifecycle capability and atomic subtree removal. Removal
  invalidates generation-checked Node IDs after synchronously releasing owned
  focus, pointer, event, Style, motion, scroll, Craft Slot, and Render Surface
  state.
- Added high-level C++ and Rust subtree removal with generation-safe stale
  handles, deterministic Driver callback release, and subscription tokens that
  reflect lifecycle-driven detachment.
- Added atomic high-level `CraftComponent` construction to the C++14 and Rust
  reference Drivers, including automatic root Style Slots, scoped public child
  Slots, failed-construction rollback, and explicit subtree unmount.
- Added retained Text, Image, group, attribute, and node-state mutation APIs to
  both reference Drivers. Cross-language fixtures verify that updates preserve
  Node identity and event handlers instead of rebuilding the component tree.
- Added typed retained `Store<State, Action>` and selected subscriptions to the
  C++14 and Rust reference Drivers. Both surfaces provide queued reentrant
  dispatch, nested transactions, silent updates with explicit selector refresh,
  custom selector equality, deterministic subscription disposal, and recovery
  after listener or transaction failures without replaying the UI tree or
  copying the complete Store state on each commit.
- Added component-owned selected watches and weak `UiHandle` retained-mutation
  handles to both reference Drivers. Watches can apply the current selected
  value immediately, update existing Text/Image/group/attribute/state targets
  without rebuilding a component, and detach on explicit close, component drop,
  or successful unmount.
- Added typed navigation to the C++14 and Rust reference Drivers with
  application-defined destinations, stable entry identities, stack revisions,
  push/replace/back/forward history, forward-branch truncation, dirty-domain
  metadata, pluggable drivers, deterministic listener snapshots, failure
  recovery, and lifecycle-bound RAII/`Drop` subscriptions.
- Added retained `NavigationScreenHost` and semantic typed `Link` authoring to
  both reference Drivers. History entries preserve focus independently,
  inactive screens remain mounted but inert and `display: none`, and Link
  activation consistently supports click, Enter, disabled state, public click
  handlers, prevent-default, and accessible link semantics.
- Extended C ABI `0x00010018` with inherited inert-state mutation/query and a
  subtree-scoped first-focusable query so foreign Drivers do not approximate
  hidden-screen interaction or duplicate focus-order rules.
- Exposed a replaceable C ABI default-action slot so foreign widgets preserve
  public bubbling and prevent-default ordering instead of folding intrinsic
  behavior into application handlers.

### Changed

- Paint, hit testing, and node presentation now borrow the retained layout-box
  index instead of copying one entry per retained node on every update. A fixed
  seven-node dirty subtree remains constant-time through 10,000 unrelated nodes.

### Security

- Reject duplicate JSON keys, unsafe or non-normalized asset paths, duplicate
  identities and paths, malformed digest metadata, unknown fields, excessive
  nesting, oversized collections, and incompatible runtime requirements before
  mutating an active Craft Pack.
- Keep asset I/O outside manifest registration. Pack loading does not access the
  filesystem or network, follow symlinks, load native code, or claim digest
  verification without a host-authorized resolver.

## [0.5.0] - 2026-08-18

### Added

- Added the first opt-in Version 0.5 frontend-runtime unit: retained typed
  `State[T]`, deterministic nested `batch` publication, component-owned
  `watch`, and target-scoped dirty-domain invalidation without component replay.
- Added transactional `StateRuntime` commits, queued reentrant dispatch,
  `createStore`, typed `StoreSelector` projections, and component-owned
  selected subscriptions that notify only when their selected value changes.
- Added component-owned source Effects with immediate retained-value runs,
  ordered reentrant updates, cleanup-before-rerun, failed-mount rollback, and
  idempotent manual or unmount disposal.
- Added typed asynchronous Commands with latest-only, ordered, and concurrent
  policies; stable run tickets; cancellation; bounded worker-to-UI completion
  delivery; exact bounded pumping; late-result rejection; and component-owned
  lifecycle cleanup.
- Added an indexed concurrent-Command performance gate; 10,000 reverse-order
  completions remain constant-cost per result instead of linearly searching
  the active run set.
- Added the typed Cue graph core with automatic serial progression, parallel
  `all` / `any` / `race` joins, relative deadlines, restart / ignore / queue /
  parallel start policies, explicit failure and cancellation, component-owned
  sessions, and independent pausable/rate-adjustable monotonic clocks.
- Added virtual-clock and lifecycle coverage plus a parallel-Cue performance
  gate; 10,000 branch completions remain constant-cost instead of rescanning
  the complete stage for every result.
- Added component-owned typed Cue source adapters for `Signal[T]`, retained
  `State[T]`, Store commits, and selected Store values. Payload-aware graph
  factories preserve source types, repeated-start policy, automatic
  unsubscribe, active-session cancellation, and late-emission rejection.
- Added ticket-scoped Command settlement subscriptions and `cueCommand`.
  Cue graphs can now await typed asynchronous Commands without replacing
  application `onSuccess` / `onFailure` callbacks or copying result payloads;
  failure, cancellation, graph cancellation, and late completion remain
  deterministic.
- Added `cueTransition` and `cueAnimation` motion actions. They subscribe before
  starting motion, wait for the matching lifecycle end, preserve public event
  handlers, and detach deterministically on completion, cancellation, startup
  failure, or node disposal.
- Added `cueCanvas`, an additive frame adapter that lets retained Canvas work
  participate in serial and parallel Cue graphs without replacing the public
  `onFrame` callback. Frame subscriptions are scoped by RenderSurface, support
  shared display lists, and detach on completion, cancellation, failure, or
  surface disposal.
- Added an opt-in bounded frontend trace that records Cue sessions, stages and
  actions together with Signal / State / Store / Selector triggers, Command
  run identifiers, motion lifecycle, and requested dirty domains. Ordinary
  release builds compile the trace types and storage out; diagnostic release
  builds can restore them with `-d:cbssFrontendTrace`.
- Added a standalone Cue orchestration demo and matching headless contract
  test for typed Signal entry, serial stages, stage-relative delayed parallel
  branches, an all-join barrier, retained visual updates, and bounded tracing.
- Added typography and geometry motion-graphics demos built entirely from the
  public Style, keyframe, and Cue APIs. They demonstrate real-time serial and
  parallel visual orchestration without pre-rendered media or demo-specific
  runtime behavior.
- Added pop-infographic, kawaii-companion, and luxury-hotel application demos
  that exercise the same public Box, Text, Image, Canvas, Style, layout, and
  retained-rendering APIs across distinct visual systems. The hotel demo also
  includes deterministic desktop, compact, and mobile responsive-layout gates.
- Added typed synchronous form validation with 40 composable rules, reactive
  validation for six form-control families, cross-field dependency tracking,
  form submission gating, invalid events and accessibility state, plus the
  corresponding C ABI invalid-state flag. Prepared patterns use a linear-time
  pure Nim regex engine without adding a native PCRE runtime dependency.

### Fixed

- Invalidating a dynamically replaced node style now schedules style
  reconciliation, allowing completed Cue motion to start its following stage
  without an unrelated redraw.
- The cosmic-text bridge now source-over composites overlapping glyph pixels
  instead of allowing later antialiased pixels to erase earlier glyph edges.

## [0.4.2] - 2026-08-13

### Added

- Added C ABI `0x00010012` with copied named-keyframe builders,
  context-scoped registration and removal, time-aware style reconciliation,
  paint-only transition/keyframe advancement, active-track and dirty-domain
  state, next deadlines, reduced-motion control, and explicit lifecycle event
  payloads.
- Added shared/static ARC and ORC C consumers for deterministic keyframe and
  transition sampling, lifecycle/cancellation behavior, ownership, reduced
  motion, deadlines, invalid offsets and values, and monotonic-time rejection.

### Fixed

- Kept borrowed C motion-event names alive for the complete callback scope;
  Valgrind now reports zero invalid accesses and zero leaks for shared and
  static motion consumers.
- Made C context reset and destruction dispatch active animation/transition
  cancellation before handlers and runtime state are released.

### Documentation

- Defined the opt-in first-party frontend runtime architecture for retained
  local state, typed Stores and Actions, selected subscriptions, owned effects,
  asynchronous Commands, and typed Cue graphs with serial progression,
  parallel fan-out, joins, relative timing, lifecycle ownership, and triggers
  from UI events, Signals, Commands, clocks, media markers, and independent
  libraries. The authoring model keeps Web-familiar names without adopting
  Hook ordering, dependency arrays, Redux-specific APIs, or virtual-DOM replay.
- Recorded the adopted frontend authoring contract for retained local fields,
  typed Stores and Actions, focused `select` / owned `watch`, source-driven
  effects, typed Commands, standard event properties, and fluent serial or
  parallel Cue graphs.
- Defined Version 0.5 frontend-runtime work and Version 0.6 production-
  foundation work as separate scopes developed in parallel, with shared
  integration scenarios and independently reviewable feature branches.
- Combined CPU Canvas, Pixie, color, SDL3 GPU Canvas, optional `wgpu-native`,
  WGSL Custom Style, Motion Scene, shared-device ownership, persistent
  resources, capability profiles, and real-GPU gates into the Version 0.7
  visual-expression milestone.
- Added a Version 0.9 touch and expressive-input scope covering multi-contact
  tracking, gesture recognition and arbitration, kinetic scrolling, pen/touch
  coexistence, virtual-keyboard behavior, and native device verification.
- Clarified that Cue supplies clocks, pause/resume, graph, and cancellation
  primitives while application policies such as game pause and autosave remain
  outside CBSS.
- Adopted a responsibility-based boundary: CBSS connects external inputs,
  timelines, libraries, streams, and visual assets to retained UI, while
  application-specific meaning and gameplay policy remain outside it. Sprite
  animation and tile maps are classified as visual-asset presentation rather
  than gameplay mechanics.
- Applied the same boundary to 3D: CBSS may compose compatible textures,
  render targets, and GPU passes inside UI, while complete 3D scene and engine
  responsibilities remain in independent libraries.

## [0.4.1] - 2026-08-12

### Added

- Added a polished declarative-motion SDL3 demo with automatic eased travel,
  2D flip motion, simultaneous color/text/opacity keyframes, and a reversible
  hover transition. Its host loop samples active tracks through paint and hit
  updates without resolving styles or running layout on every animation frame.
- Added GIF and MP4 recordings of the declarative-motion demo.

### Documentation

- Defined the planned Version 0.5+ C ABI for foreign-language keyframe
  registration, transition reconciliation, active motion, frame deadlines,
  reduced motion, ownership, and conformance testing.

## [0.4.0] - 2026-08-11

### Added

- Added LLVM UBSan gates for numeric, layout, transform, transition, and
  keyframe paths on Linux and macOS; a standalone LSan lifecycle gate on Linux;
  and TSan worker-to-UI ownership gates on Linux and macOS. Every sanitizer task
  covers both ARC and ORC and remains test-only. Windows retains portable and
  ASan coverage rather than requiring an unverified UBSan runtime.
- Added C ABI `0x00010011` and declaration-driven animation/transition
  lifecycle events. `animationstart`, `animationiteration`, `animationend`,
  `animationcancel`, `transitionrun`, `transitionstart`, `transitionend`, and
  `transitioncancel` use normal CBSS dispatch with motion name, elapsed time,
  and iteration payloads where applicable. Subtree disposal emits cancellation
  before handlers are detached.
- Expanded the motion AddressSanitizer gate to ARC and ORC on Linux, Windows,
  and macOS. Linux additionally retains Valgrind lifecycle and leak gates;
  unsupported LeakSanitizer options are not passed to macOS or Windows.
- Added declarative transition and keyframe interpolation for typed 2D
  `transform`, `translate`, `scale`, and `rotate` values. Motion reuses the
  existing affine paint/hit contract, does not relayout each frame, and marks
  hit data dirty only while geometry changes.
- Added multiple declaration-bound animations per node with typed list
  authoring and CSS-like cycling across name, duration, delay, timing,
  iteration count, direction, fill, play state, and composition. Missing
  definitions retain their list positions, tracks pause and complete
  independently, and declaration order determines paint precedence.
- Added an AddressSanitizer motion gate for declarative transitions and
  keyframes under both ARC and ORC. Valgrind remains the separate Linux leak
  gate.
- Added typed and lower-level list authoring for transition property, duration,
  delay, timing, and behavior values, with CSS-like index cycling, preserved
  unknown-property positions, nested-function comma parsing, and last-match
  parameter selection.
- Added the first declaration-bound named-keyframe runtime for `opacity`,
  `color`, and `background-color`, including typed registration, duration,
  signed delay, timing, finite/infinite iterations, direction, fill, pause and
  resume, retained forwards presentation, reduced motion, definition revision,
  subtree cancellation, and deterministic paint-only test-driver advancement.
- Added the first declarative style-transition runtime for `opacity`, `color`,
  and `background-color`, including timing functions, signed delay, reversal,
  Oklab color interpolation, reduced motion, subtree cancellation, active-only
  frame scheduling, and deterministic headless-driver time advancement without
  per-frame style resolution or layout.
- Expanded enum-backed property authoring across existing closed text, image,
  background, blending, input, scrolling, transform, transition, and animation
  value sets. These helpers retain the validated keyword runtime path while
  adding LSP completion and compile-time rejection of unrelated values.
- Added C ABI `0x00010010` and Nim host-authorized Blob providers with lazy
  bounded reads, serialized access per Blob, success-only context ownership,
  exactly-once release, and ARC/ORC plus pthread/Valgrind coverage.
- Added C ABI `0x0001000F` bounded Blob streams with UI-owned consumers,
  atomically retained cross-thread producers, item/byte backpressure,
  coalesced wake callbacks, ordered pump/drain, explicit Blob ownership,
  progress and terminal events, foreign-thread attach/detach, and shared/static
  ARC/ORC pthread consumer coverage.

## [0.3.2] - 2026-08-04

### Changed

- Defined the public extension ecosystem as Nim-first: independent component,
  chart, theme, widget, and design-system packages expose ordinary Nim APIs,
  while foreign implementations remain encapsulated behind Nim adapters.
- Expanded the Version 0.4 roadmap with transparent conditional component
  flow. Ordinary `ui.mount(component)` placement will retain an internal flow
  position, consume no layout space while empty, and materialize into normal
  Box/Flex flow without exposing slots, selectors, or coordinates to
  application code.

## [0.3.1] - 2026-08-04

### Added

- Added a semantic, style-injectable `Switch` reference control with pointer,
  Space/Enter, disabled, fieldset, input/change, accessibility, AT-SPI,
  headless-driver, and ARC lifecycle coverage. Its transform-positioned thumb
  and checked-track overlay use an idle-aware, reversible 180ms `ease`
  transition with reduced-motion support.
- Added interactive dark and light Switch examples to the full SDL3 demo with
  headless layout and activation regression tests.
- Added a standalone Canvas loading-indicator demo that continuously animates
  only its retained drawing surface while the surrounding UI remains static.
- Extended the append-only C ABI accessibility role vocabulary with Switch in
  ABI version `0x00010006`.

### Changed

- Reworked the README around the user-facing value, current typed component
  API, demo media, measured performance, installation paths, release scope,
  and documentation map.

## [0.3.0] - 2026-08-03

### Added

- Added typed `CBSSComponent` authoring with ordinary Nim `render(self)`
  procedures, checked scoped `ui` composition, automatic Style DI,
  component-owned event slots, ARC retention, lifecycle hooks, and
  transactional mount rollback.
- Added typed CSS Color 4-inspired authored values and strict serialized
  parsing for hexadecimal, named, RGB/HSL, HWB, Lab/LCH, Oklab/Oklch, and
  predefined `color()` spaces with byte-offset diagnostics.
- Added typed mouse, touch, and pen metadata across SDL3 input, normal event
  dispatch, Canvas/RenderSurface-local callbacks, and C ABI version
  `0x00010005`, including source timestamps and capability-masked pressure,
  tilt, rotation, distance,
  slider, eraser, button, proximity, and stable-in-process device data.
- Added typed and serialized `color-mix()` values with CSS percentage
  normalization, delayed `currentColor` resolution, strict diagnostics, and
  direct integration with solid color, border, and shadow declarations.
- Implemented CSS missing-component carry-forward for sRGB, linear-sRGB, and
  Oklab interpolation, including analogous component sets and alpha handling.
- Added explicit sRGB, linear-sRGB, and Oklab linear-gradient interpolation
  through a shared SDL3/PPM sampler with premultiplied alpha and cache-safe
  interpolation-space identity.
- Moved raster gradient hot loops to prepared, resolution-bounded lookup
  tables, avoiding repeated color-space conversion and gamut mapping for every
  output pixel.
- Added C ABI 1.1 opaque authored-color handles for typed spaces,
  `currentColor`, CSS color parsing, `color-mix()`, explicit resolution, and
  copied style application while retaining the existing `CbssColor` layout.
- Added mixed resolved/authored linear-gradient stops, including wide-gamut
  colors, `currentColor`, and color mixes resolved at style-computation time.
  The C ABI exposes the same behavior through copied opaque color-value stops.
- Added pinned Chrome 150 browser comparison fixtures for CSS Color 4 inputs,
  color mixes, alpha composition, wide-gamut conversion, and actual CSS
  swatches, with strict RGBA8 checks and an explicit Rec.2020 divergence record.
- Added the versioned RenderSurface lifecycle with retained placement,
  local-coordinate input, explicit frame requests, visibility and device
  lifecycle callbacks, and deterministic cleanup.
- Added the first retained `Canvas2D` host integrated with normal `UiRoot`
  construction and the canonical paint stream. Canvas content is constrained
  to the Box content area and supports rectangles, gradients, strokes, text,
  images, and nested clips without rebuilding the UI tree.
- Added a deterministic animation clock with CSS timing functions, direction,
  fill, iteration, reduced-motion handling, dirty-domain scheduling, and typed
  float and color keyframes.
- Added a shared presentation-coordinate contract for scroll translation,
  overflow clipping, inherited opacity, paint, hit testing, and surface
  placement, with cross-subsystem regression coverage.
- Exposed the RenderSurface lifecycle through the C ABI with Box attachment,
  local input, DPI-aware resize, requested frames, visibility, device recovery,
  and deterministic unmount coverage in shared and static C consumers.
- Added an interactive Version 0.3 SDL3 demo for retained Canvas animation,
  local pointer input, Oklab gradients, and authored wide-gamut colors.
- Added retained open and closed Canvas paths with adaptive quadratic/cubic
  curves, configurable cap/join styles, shared SDL3/headless rendering,
  clipping, opacity, and Canvas-local coordinates.
- Added one affine coordinate contract for resolved Box transforms and
  retained Canvas transforms across paint, exact hit testing, transformed
  clips, RenderSurface input, SDL3 composition, and headless rendering.
- Added bounded Canvas offscreen layers with explicit opacity, source-over,
  copy, and additive composition across SDL3 and the alpha-aware PPM reference
  backend, including append-only C ABI paint kinds and performance gates.
- Added a retained C ABI Canvas adapter for registered RenderSurfaces. Foreign
  libraries can submit local transforms, clips, layers, rectangles, gradients,
  paths, text, and images, then publish one paint-only display-list update
  without recomputing style or layout.
- Added required Linux x86_64, Windows x86_64, and macOS arm64 portable CI
  lanes covering ARC tests, public modules, non-window examples, C ABI builds,
  and both native Rust bridges.
- Extended the release-mode ARC lifecycle Valgrind gate to cover typed
  component retention, events, mount, subtree disposal, and unmount hooks.

### Fixed

- Corrected `step-start` to jump at the zero endpoint and rejected non-finite
  Canvas target frame rates before they can enter the scheduler.
- Prevented transformed PPM rectangles from alpha-compositing shared triangle
  edges twice.

## [0.2.0] - 2026-08-01

### Added

- Added typed native navigation with stable history entries, `push`,
  `replace`, `back`, and `forward`, additive listeners, dirty-domain metadata,
  dependency injection, and application-owned navigator drivers.
- Added the semantic `Link` primitive with pointer, keyboard, focus-visible,
  disabled, accessibility, external-URL, and typed deep-link behavior.
- Added retained navigation screen hosting with per-entry focus restoration,
  inactive-screen inertness, replaceable and disposable screen subtrees, and
  optional frame-scheduled transition hooks.
- Added the Version 0.2 navigation demo, headless navigation coverage, release
  benchmarks, and real-window Wayland navigation tests.
- Added a dedicated ARC widget-lifecycle Valgrind gate covering every
  reference control and widget independently from the shared and static C ABI
  memory checks.

### Changed

- Made component handles non-owning ARC views and generation-checked node IDs,
  preventing stale handles from mutating reused tree slots and removing event
  closure ownership cycles.
- Extended inactive-state handling across layout, paint, hit testing, direct
  events, focus traversal, and accessibility output.
- Added `link` to the accessibility role vocabulary and propagated
  generation-checked node handles through the existing C ABI.
- Updated the SDL3 test integration driver to retain a deterministic local
  clipboard snapshot when an unfocused synthetic Wayland window cannot read
  back its compositor selection.

### Fixed

- Fixed initial input routing under SDL3, Wayland, and libdecor by repainting
  after window expose events and restoring the application cursor when the
  pointer returns from client-side decorations.
- Fixed focus changes that previously cleared state across unrelated nodes and
  hardened focus, accessibility, and event paths against stale node handles.
- Preserved retained scroll bounds and minimum sizes while avoiding unrelated
  layout work during scroll-only updates.

## [0.1.8] - 2026-07-31

### Added

- Made ARC ownership cleanup a Version 0.2 release gate, including removal of
  owning `UiRoot` back-references from component handles and event closures.
- Planned a dedicated ARC Widget lifecycle executable and Valgrind CI path
  covering reference controls, registered handlers, popup lifecycles, focus,
  clipboard callbacks, text composition, rebuilds, and deterministic cleanup.
- Defined leak, invalid-access, double-free, and use-after-free failures
  separately from the existing shared and static C ABI Valgrind checks.

## [0.1.7] - 2026-07-30

### Added

- Defined local CSS Color 4 parity as the color-system target so supported
  color values can be shared between a web design and CBSS on the same OS,
  display, and output color space.
- Added the planned optional Pixie CPU raster and effects path for cached
  paths, masks, gradients, shadows, blur, SVG, image processing, and generated
  game-interface assets.
- Documented embedded, standard, and full visual deployment profiles together
  with effect cache policy, resource budgets, and required amd64/arm64
  measurements.
- Preserved the stable C ABI boundary by keeping Pixie internal and planning
  versioned or opaque extended-color inputs alongside the existing RGBA value.

### Changed

- Required release pull requests from `devel` to `main` to use merge commits
  rather than squash or rebase merges.

## [0.1.6] - 2026-07-30

### Fixed

- Restored Japanese IME preedit rendering after pasting text without changing
  the active input mode.
- Reset stale composition deduplication state consistently in text inputs and
  textareas when committed text or clipboard content is inserted.

## [0.1.5] - 2026-07-30

### Added

- Published the native web-platform capability roadmap, defining the intended
  CBSS, Nim, independent-package, and deliberate non-browser boundaries across
  HTML-like structure, CSS-like presentation, and JavaScript-like behavior.
- Expanded the Canvas roadmap with a renderer-neutral `ExternalSurface`
  contract, capability diagnostics, lifecycle ownership, and host-driven UI
  composition requirements.

### Changed

- Replaced renderer-specific integration examples with a generic external
  surface contract so future integrations are not coupled to one engine or
  rendering library.

## [0.1.4] - 2026-07-29

### Added

- Published the Native Canvas, visualization, game UI, SDL3 GPU capability,
  external-renderer integration, and design-source/NIF-BIF roadmap.

## [0.1.2] - 2026-07-29

### Changed

- Refined the public project description to "A CSS-inspired primitive engine
  for native GUI toolkits."
- Clarified that Clay Board Style System is independent from Clay, the C UI
  layout library.

## [0.1.1] - 2026-07-29

### Changed

- Unified the public package name, Nim import path, source tree, documentation,
  demo title, and sample asset names under `clay_board_style_system`.

## [0.1.0] - 2026-07-28

### Added

- Initial Linux x86_64 developer preview.
- Bundled static-SDL3, system dynamic-link, and custom-prefix setup profiles.
- Versioned CBSS C ABI with shared/static builds, typed compound styles,
  event callbacks, focus traversal, retained scrolling, accessibility output,
  and an interactive C consumer test.
- Automatic ARC test discovery and release-oriented example checks.
- Apache License 2.0 project licensing and third-party dependency notices.
