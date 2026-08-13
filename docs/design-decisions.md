# CBSS Design Decisions

Numbered, ADR-style decisions that resolve contradictions between the stated
design (`architecture.md`, README) and the implementation, as surfaced by the
2026-07-16 audits: the implementation audit
(`docs/audits/2026-07-16-implementation-audit.md`, defects — D1–D15) and the
feature-gap audit (`docs/audits/2026-07-16-feature-gap-audit.md`, absences —
D16–D19).

Status meanings:
- **Adopted** — settled by existing project policy; implementation should
  follow without further discussion.
- **Proposed** — recommended by the audit; needs owner sign-off before large
  diffs land.
- **Owner decision** — a naming/positioning call only the project owner can
  make; a recommendation is given.

---

## D1 — Runtime layering: mechanisms, reference widgets, theme (Proposed)

**Context.** README says CBSS is not a widget toolkit, yet `runtime/` is a
6.7k-line directory of 15 controls + 3 widgets with hardcoded colors, glyphs,
and metrics, all exported from the public umbrella.

**Decision.** Split the runtime into three explicit layers:

1. **Mechanisms (CBSS-core runtime)** — `ui_root` builders, event registry,
   interaction/focus coordination, invalidation + frame scheduler, text edit
   core. No visual opinion. This is the part the "not a widget toolkit"
   promise protects.
2. **Reference widgets** (`runtime/widgets/` — Button, Checkbox, …,
   CommandMenu) — thin, replaceable validation components, exactly as
   architecture.md already describes them. All current `runtime/*.nim`
   controls move conceptually into this layer.
3. **Default theme** — every color, glyph, marker string, metric, and z-index
   currently hardcoded inside controls (selection/caret colors, checkbox "✓",
   radio dot, details "v"/">", select popup `top: 30px`, context-menu styling
   in `ui_root.nim`) moves into a single replaceable theme definition, and
   indicator glyphs/texts become parameters.

README positioning is updated to say CBSS *ships replaceable reference
widgets* rather than denying they exist. The default context menu moves out of
`ui_root.nim` into the widget layer.

## D2 — The frame scheduler is a library component (Adopted)

At audit time, the dirty-domain scheduler (`runtime/invalidation.nim`) was dead
code while the only working incremental pipeline lived in
`examples/sdl3_demo.nim`. The demo's machinery (`buildFrame`, `repaintDirtySubtrees`,
`repaintTextControlFrame`, static/dynamic layering, event coalescing, caret
blink scheduling, focus staleness handling) moves into
`runtime/frame_scheduler.nim` + `runtime/interaction.nim`, driven by
`InvalidationState`. Components mark dirty domains; the backend exposes
`waitEvent(timeoutMs)`; the loop blocks when idle. The demo becomes a consumer.
Rationale and budgets: `docs/performance-model.md`.

**Implementation status.** `runtime/frame_scheduler.nim` now owns dirty-domain
consumption and deadline-to-timeout calculation. SDL3 exposes ordered
`waitEvent`/`waitEventTimeout`, and the demo blocks while idle instead of waking
at 60 Hz. Caret blink and scroll-end behavior are deadline-driven. The demo
still owns frame construction and bridges some component changes through local
booleans, so extracting the full interaction/update pipeline remains open.

## D3 — One text edit core (Adopted)

`text_input.nim` and `textarea.nim` share ~850 near-verbatim lines and have
already diverged behaviorally. A shared `runtime/text_edit_core.nim` owns the
byte buffer, caret/selection (rune-safe, grapheme-aware later), undo stack,
edit commands, composition state, and key command mapping, parameterized over
single/multi-line. The change-event contract is unified: `onInput` per edit,
`onChange` on commit (blur/Enter for single-line), identical across both
controls and both input paths. `maxLength` semantics (bytes) are documented on
the API.

## D4 — ComputedStyle hot/cold split and property-surface trim (Proposed)

`ComputedStyle` is 5,664 bytes; ~150 fields are `Option[string]` passthroughs
with no consumer. Decision:

- Hot struct: numeric/enum fields actually read by layout, paint, hit, text.
- Cold extension: a lazily-allocated `ref` holding long-tail typed fields.
- Unconsumed speculative properties (timeline-trigger, corner-shape variants,
  SVG vector fields with no vector element, `legacyBox*`, most `mask-*`)
  leave the struct entirely and move to one documented passthrough table
  (design-source/metadata interchange only), reintroduced as typed fields
  when a consumer lands. The support matrix keeps them as `Metadata` with a
  pointer to the passthrough mechanism.

## D5 — Style application is keyed replacement; rules are indexed (Adopted)

`applyStyle`-family APIs replace a node's component style slot instead of
appending sheets (append is the root cause of the slider/progress/textarea
leak). Sheets/rules are bucketed by target (nodeIndex / group / element kind)
at registration, pre-sorted by (priority, specificity, sheetIndex, ruleIndex,
declIndex). `Declaration.sourceOrder` is removed or given one documented tier
in that ordering — never mixed with a per-node counter.

## D6 — Property modules become declarative; `generated/` becomes generated (Adopted)

The ~130 copies of the merge-mode skeleton, 8 `resolvePx` clones, and triple
set/clear/get string switches are replaced by a small macro/codegen layer:
one line per property declaring name, target field, accepted units/keywords,
merge policy (`overwrite/inherit/initial/unset/relative`), and invalidation
domains. `generated/default_properties.nim` is emitted by a committed
generator (or a registration macro iterating exported `PropertyImpl`s), with a
test asserting module ↔ registry sync and a diagnostic on duplicate
registration. Property inheritance becomes property-owned metadata consumed by
a generic resolver pass — the hardcoded per-field inheritance block in
`style_resolver.nim` is deleted, fixing `initial`-vs-inherit semantics along
the way.

## D7 — Layout moves to measure/arrange two-pass with an axis abstraction (Adopted)

Single-pass layout finalizes children before container sizes are known (wrong
interior alignment after grow/stretch, min/max never re-clamped, text measured
at the wrong width). The layout engine is restructured into:
`measureLeaf → collectFlexLines → resolveFlexibleLengths (freeze/redistribute
loop) → justifyAndAlign → placeAbsolute`, with a main/cross `AxisView` to kill
the ~14 duplicated `fdRow` branches. This creates the seam for `flex-wrap`,
`align-content`, `space-around/evenly`, and both-side absolute insets.
`display:none` children leave flow accounting. `LayoutResult` gains a
`nodeIndex → boxIndex` index.

**Implementation status.** Sizing now has an explicit bottom-up intrinsic
measurement pass followed by arrangement. `%`, `auto`, `content`,
`min-content`, `max-content`, and `fit-content` reach layout without being
collapsed to pixels during style resolution. The intrinsic pass is skipped
when no node requests intrinsic sizing. Percentage gaps, percentage/intrinsic
flex bases, and signed percentage insets also resolve during arrangement. Full flex-line collection,
freeze/redistribute, axis abstraction, wrap/align-content, and the box index
remain open, so D7 is only partially complete.

## D8 — Hit testing follows paint order and clipping (Adopted)

Hit regions record the paint traversal order and an effective stacking layer
propagated down the tree; ties resolve by paint order (topmost wins), not by
smaller area. Region rects are intersected with the accumulated ancestor clip.
`visibility`/`pointer-events` on a container affect the whole subtree, exactly
as paint prunes it. The `layer×100000+index` packing is replaced by two fields.

## D9 — Input synthesis fixes and event-surface honesty (Adopted)

- Drag begins only past a movement threshold; click survives sub-threshold
  jitter; `pointerCancel` resets pressed/drag/capture state.
- `InputEvent` gains a timestamp (backends already have one); double-click
  gates on a time window and position delta.
- Button numbering normalizes to DOM (0/1/2) at the backend boundary; `click`
  fires for the primary button only.
- Enter/leave synthesize along the LCA path, distinct from over/out;
  non-bubbling kinds don't bubble.
- Event slots without any real firing path (media, fullscreen, cue, encrypted,
  …) are removed from the public enum until an implementation exists —
  architecture.md already mandates exactly this.
- The enum→dispatchMode→slot-name→setter surface is generated from one
  declarative table; synthesis moves to `input/synthesis.nim` so `events.nim`
  stops being the file every feature edits.
- Handler registry: per-node index, removal API, user handlers run before
  internal defaults, and cancellation (`beforeinput`) is explicit rather than
  "any handler returning true swallows the expansion".

## D10 — FFI hardening (Adopted)

Every `extern "C"` entry point in the cosmic-text bridge is wrapped in
`catch_unwind` (or the crate sets `panic = "abort"` explicitly and documents
process-fatal semantics). Single-thread ownership is documented on the ABI.
`useSystemFonts` is honored; the full font-family fallback chain and
registered family/weight/style metadata cross the ABI or are documented as
advisory. The stale duplicate SDL3 binding under `bindings/c/sdl3/` is deleted
or reduced to the documented generator input — one binding copy only
(`src/clay_board_style_system/vendor/sdl3.nim`).

## D11 — Memory-model enforcement under ARC (Adopted)

- No reference cycles: handles and closure contexts hold `{.cursor.}`
  (non-owning) references to `UiRoot`; internal handlers key off `NodeId` plus
  dispatch-time context. (An `--mm:orc` CI job is a safety net, not the fix.)
- The node arena gains tombstoning + a free list, and `NodeId` becomes
  (index, generation) before external code bakes in raw-index assumptions.
- Sort/comparator closures on hot paths are banned per
  `docs/performance-model.md` rule 1.

## D12 — Build, test, and repo hygiene (Adopted)

- A discovery-based test runner replaces the hand-maintained exec list. It
  runs every portable `tests/**/*.nim` file under ARC and writes compiler
  caches and executables to a process-unique temporary directory. Native
  Wayland tests, performance benchmarks, and the cosmic-text integration test
  remain explicit opt-in tasks because they require a display, release-mode
  timing, or a prebuilt native bridge.
- CI runs `nimble check`, the discovered ARC suite, the same suite and public
  examples under ORC, ARC example checks for all three SDL3 link modes, and
  locked Cargo bridge tests/builds. Release hygiene checks verify required
  notices, SDL3 symlinks, and the absence of unrelated native binaries.
- A root `LICENSE` (Apache-2.0) is added, plus SDL3/cosmic-text third-party
  notices alongside the existing image-rs notice. The explicit contributor
  patent grant is appropriate for a shared native UI foundation intended for
  commercial and cross-language use.
- Unexplained native binaries are removed; maintained bridges have source,
  locked dependencies, and license notices. The three full copies of
  `libSDL3.so*` become symlinks or a fetch step.
- Runtime dependency selection is setup-time configuration. The CBSS Nimble
  package does not include native runtime binaries. Bundled and custom setup
  both consume the same application-supplied runtime-root layout and write
  `.cbss/link-mode` plus `.cbss/runtime-root` through `cbss_configure`, without
  changing application imports or API calls.

**Implementation status.** Implemented. The portable runner currently
discovers 47 test files. The development checkout keeps one versioned SDL3
shared binary plus SONAME/link-name symlinks; release packages do not include
these native binaries. The image bridge is built from CBSS-owned Rust source,
and the unused font binary was removed. See
`docs/runtime-linking.md` for distribution layouts and advanced overrides.

## D13 — Naming: Clay Board Style System (Adopted)

The product, repository, Nimble package, Nim import path, and internal source
tree use the same Clay **Board** Style System name. This removes the previous
Board-versus-Box distinction before external adoption.

- Product and repository name: **Clay Board Style System**. The board is the
  primitive foundation on which component libraries are built.
- Nimble package name: `clay_board_style_system`, matching the public product
  and repository name.
- Nim import name and internal source tree: `clay_board_style_system`.

The README must state the public package and import name near its first use.

## D14 — Documentation restructure (Adopted)

`architecture.md` returns to being a stable design-intent document:

- Per-component behavior notes (currently ~230 lines inside the *Selectors*
  section) live in `docs/runtime-components.md`.
- The event model (slot list, firing paths, synthesis policy) becomes its own
  `docs/event-model.md` extract in a follow-up.
- The "Suggested Directory Structure" section is rewritten to describe the
  actual tree (`core/`, `properties/` grouped modules, `runtime/`, `layout/`,
  `paint/`, `hit/`, `input/`, `text/`, `backends/`, `testing/`,
  `design_source/`, `generated/`, `vendor/`), marking aspirational parts
  (`elements/`, `selectors/`) explicitly.
- Performance policy lives in `docs/performance-model.md` (added 2026-07-16).
- `CONTRIBUTING.md` carries the promised "files to touch" map.

## D15 — Runtime component conventions (Adopted)

One written convention applied mechanically to every control:

- State flags: `esOpen` for open/closed (dialog and command_menu stop mapping
  *closed* to `esDisabled`); `esDisabled` means disabled only; `esActive` is
  pressed/engaged, with the progress-indeterminate exception documented.
- Activation: click activates; pointer-down is for focus/press visuals only.
- Disabled behavior: guards consume the event uniformly; programmatic setters
  behave the same across controls; every interactive control registers with
  fieldset auto-disable.
- Events: `onInput` then `onChange`, emitted only on actual value change,
  after the component's own state is updated.
- Attributes mirrored to nodes (value/checked/label/…) follow one table.

---

The decisions below resolve findings from the feature-gap audit
(`docs/audits/2026-07-16-feature-gap-audit.md`).

## D16 — Style vocabulary parity is a release gate (Adopted)

**Context.** 193 of 665 properties are `Metadata`: accepted by the resolver and
read by nothing. `flex-wrap`, `align-content`, `box-sizing`, `direction`,
`writing-mode`, `transform`, `filter`, and `mix-blend-mode` all parse, store,
and are discarded. Worse than the properties are the value constructors: `pct()`
and `content()` are public (`core/style_value.nim:91,103`), so `width: pct(50)`
compiles and type-checks against an engine that is px-only
(`properties/sizing.nim:4-13`). `docs/css-property-support.md` documents all of
this accurately — but a doc the author must consult to learn that a compiling
call does nothing is not a substitute for a type system that refuses it.

**Decision.** Parity is enforced, not tracked. For every registered property,
exactly one of:

1. a consumer exists in layout, paint, hit testing, or the text engine;
2. the registration is removed until a consumer lands; or
3. the property emits a "not implemented" diagnostic naming its tracking issue.

Silent acceptance is not an option. A test asserts that every property marked
`Runtime` in the support matrix has a consumer, and that the matrix status of
every registered property matches reality.

Value constructors follow the same rule: a unit the resolver cannot resolve must
not be constructible from typed code. Either gate the constructors behind the
accepted unit set or give `LengthValue` a compile-time unit tag. `Metadata`
remains a legitimate tier for design-source interchange
(`architecture.md`'s passthrough model, D4) — but the passthrough must
be reachable only through an explicitly-named metadata API, never through the
same `decl()` call an author uses for working properties.

This decision governs the other three: none of D17–D19 may land a property
surface ahead of its consumer.

## D17 — CBSS owns UI semantics and accessibility mechanisms (Adopted)

**Context.** At audit time there was no accessibility anywhere: a word-boundary search of
`src/` for `a11y|accessibilit|accessible|aria-|at-spi|UIAutomation|NSAccessibility`
returns zero matches. `Node` carries nothing semantic — `NodeKind` is
`nkBox/nkText/nkImage`. The only mention in the repo is `README.md:221`, under
"Possible later features," alongside text input, IME, and scroll containers —
all of which have since been built or scheduled.

The salient fact is that CBSS *already computes* the semantic state an
accessibility tree needs. `ElementState` (`core/node.nim:12-19`) —
`esChecked`, `esSelected`, `esOpen`, `esDisabled` — is exactly it, and it exits
only into selector matching.

This is the one capability that cannot be added downstream. SDL3 exposes no
accessibility surface, so CBSS is the only layer positioned to own
AT-SPI/UIA/NSAccessibility. A GUI library building a parallel semantic tree
would duplicate the element tree, re-derive geometry for AT hit testing, and
re-derive state CBSS already has — routing around the foundation rather than
building on it. Note also that Blink's headline non-rendering deliverable is the
accessibility tree, and `README.md:14-18` claims that role.

**Decision.** CBSS owns the reusable UI mechanism, including:

- role, accessible name, description, value, and state on the retained UI tree;
- focus, keyboard traversal, activation semantics, selection, expansion,
  disclosure, and other behavior intrinsic to an element;
- geometry and hit information needed by assistive technology; and
- replaceable platform adapters (`backends/atspi/`, later UIA and
  NSAccessibility).

CBSS does **not** own application business logic. A Button owns focus,
keyboard activation, disabled behavior, and click dispatch. What the click
does — saving a document, printing, calling a backend, or changing application
data — remains a user callback and belongs to the application's logic layer.
Likewise, arrow-key expansion of a disclosure or Select is UI behavior and is
owned by CBSS; the business operation triggered by a selected value is not.

The capability target is the practical UI surface available to React
applications through HTML and JavaScript, translated to a retained native
element model. It does not require reproducing the browser DOM or browser-only
behavior. The semantic model lands before platform bridges so component
libraries can build against one stable contract while OS support is added
independently.

**Implementation status.** The retained tree now carries a cold, `NodeId`-keyed
semantic table with typed role, accessible name, description, string and
numeric range values, labelling/describing relations, and the existing semantic
state set. Keeping it parallel avoids enlarging the render-hot `Node` record.
`runtime/accessibility.nim` exports a platform-neutral semantic tree, and
standard controls populate it. Layout bounds can be joined into that tree
without enlarging render-hot nodes. `backends/atspi/adapter.nim` now maps the
neutral tree to the official AT-SPI root/object model, roles, states, component
geometry, actions, and atomic snapshot diffs. Its `activate` action routes into
the existing CBSS event registry and rejects disabled controls.

The Linux accessibility D-Bus provider is still pending. Until that transport
exists and passes real Wayland assistive-technology validation, CBSS must not
claim complete Linux screen-reader support. Text, EditableText, and Value
interfaces are also deliberately unadvertised until their complete operation
surfaces have consumers. See `accessibility.md`.

## D18 — Focus is a general mechanism, not a text-control feature (Adopted)

**Context.** At audit time every control already implemented keyboard semantics —
`button.nim:56-62`, `checkbox.nim:151-157`, `radio.nim:184-190`,
`select_box.nim:253-273`, `slider.nim:185-200`, `details.nim:146-151` — and none
can be reached. Key events dispatch only to `state.focusedTarget`
(`input/events.nim:696-702`); focusability is hardcoded to two group names in
`isTextInputTarget` (`runtime/text_focus.nim:8-11`). **A Button accepts Space
only after it has been clicked with a mouse.**

It is not workable around from above: `normalizeTextControlFocus`
(`runtime/text_focus.nim:243-247`) clears `focusedTarget` on any pointer hit
that is not a text input or label, so focus a library places on a Button is
destroyed by the next pointer event. Tab is wired to traversal only in
`testing/test_driver.nim:667-668`; in a shipped app, Tab does nothing.

**Decision.** Focus becomes a general capability owned by the runtime/root
interaction layer, exactly as `architecture.md:216-220` already mandates for
text controls:

- Focusability is a node property, not a group-name string match.
- A documented traversal order with a `tabindex` analogue; Tab/Shift-Tab wired
  in the library, not only in the test driver.
- Focus assignment on pointer-down checks focusability — focus may not land on a
  decorative Box (`events.nim:878-883`).
- `:focus-visible` is distinguished from `:focus` by last input modality.
- `text_focus.nim` becomes a consumer of the general mechanism, not the
  definition of it, and stops clearing focus it does not own.
- Focus containment follows: `Dialog.modal` (`runtime/dialog.nim:12,18,85-86`)
  is currently a field whose only reader is its own getter — it gains a focus
  trap, initial focus, restoration on close, and background inertness.

This is a precondition for D17. It also completes
D15's control conventions: keyboard activation is currently written into
every control and reachable from none.

**Implementation status.** `runtime/focus.nim` now owns focus assignment,
ordered Tab/Shift-Tab traversal, pointer normalization, and `:focus-visible`.
Standard controls opt in explicitly, decorative Boxes remain unfocusable, and
labels delegate pointer focus to their associated control. The SDL3 demo and
headless E2E driver use this same path. Modal Dialogs install a focus scope,
trap forward and reverse traversal, make the background inert, select an
initial focus target, and restore the opening focus after close or Escape.
Event-triggered restoration uses one root-level focus request reconciled after
the current event batch rather than giving components ownership of global input
state.

## D19 — CSS custom properties are not part of the CBSS value model (Adopted)

**Context.** `docs/css-property-support.md:141` marks `--*` as **"No plan —
CSS custom properties are browser cascade features, not an initial CBSS goal."**
The feature-gap audit argues against that line specifically, so it needs an
explicit decision rather than a silent reversal.

The case: `StyleContext` is `declarations: seq[Declaration]` and nothing else
(`core/style_context.nim:13-14`). `StyleRule` has no condition
(`core/rule.nim:4-8`) and no viewport reaches `ResolveEnv`. There is no theming
signal. Together this means **every value in every rule is a literal fixed at
construction time, and a theme switch requires rebuilding every `colorValue(...)`
in every rule and re-resolving the tree.** There is no indirection layer to
re-point.

`computedValue` closures (`core/style_value.nim:133-137`) are not a substitute:
they require `resolveTrustedStyles`, take no arguments, cannot read an
ancestor's value, and do not participate in the cascade. A thunk is not a
variable, because nothing flows down the tree.

The counter-argument in the current text is real: variables *are* a browser
cascade feature, and CBSS deliberately refuses browser cascade features
elsewhere (descendant selectors, structural pseudo-classes). The distinction
proposed here is that those refusals are about **matching** — they make style
resolution walk the tree — whereas variables are about **value indirection**,
which the explicit style-context/merge model (`architecture.md`'s
"Style Composition And Merge") is already reaching for and failing to complete.

**Decision.** Do not add CSS custom-property syntax or untyped `--name`
storage. CBSS authoring runs in Nim, where `var`, `let`, `const`, typed values,
style composition, and dependency injection already provide value
indirection without recreating a browser-specific substitute for variables.

Theming is expressed by injecting typed Theme values or complete `UiStyle` /
`StyleSheet` values and replacing the affected style slots. Scoped component
overrides remain explicit constructor/style injection. Responsive conditions
remain a separate rule-environment capability and do not require custom
properties.

External design and MCP adapters resolve their source token references into
typed CBSS values at the adapter boundary. If runtime token enumeration or
late-bound external themes later require a registry, it must be a typed
`StyleToken[T]`-style API with explicit invalidation, not CSS custom-property
strings and not an implicit ancestor cascade. This preserves external-tool
interchange without introducing a second variable system alongside Nim.

## D20 — The C ABI is the language-neutral runtime boundary (Adopted)

**Context.** CBSS aims to be a native UI foundation for ecosystems beyond Nim.
Exporting Nim object layouts would couple every consumer to ARC details,
compiler versions, and internal refactors.

**Decision.** Maintain a versioned C ABI under
`src/clay_board_style_system/c_api.nim` with its canonical declaration in
`include/cbss.h`. The ABI uses opaque owning handles, fixed-width scalar
values, caller-owned output buffers, explicit status codes, and copied string
inputs. Nim-managed strings, sequences, references, closures, exceptions, and
object layouts never cross this boundary.

Shared and static libraries are both supported and exercised by a real C
consumer in CI. Nim remains the ergonomic first-party API; other language
bindings are thin adapters over the C ABI rather than separate engine
implementations.

The C ABI is an operational UI boundary, not a read-only export format. It
owns interaction state, event derivation and bubbling, focus traversal,
pointer capture, retained scrolling, and recomputation signals. Foreign
callbacks use C function pointers plus host-owned `user_data`; Nim closures
remain internal.

## D21 — The extension ecosystem uses Nim packages (Adopted)

**Context.** CBSS needs the low-friction composition that made Web libraries
successful: an application imports an independently maintained library and
mounts its component without copying the UI runtime or learning the library's
internal renderer. A language-neutral plugin SDK would make Rust, C, and C++
equal authoring targets, but it would also create a second package model,
duplicate lifecycle and tooling work, and weaken the goal of making Nim the
natural language for native GUI development.

**Decision.** Public CBSS components, design systems, charts, widgets, themes,
and render-surface extensions are distributed as ordinary Nim modules and
Nimble packages. Their consumer-facing entry point is Nim and participates in
Nim's type system, ARC ownership, documentation, compiler checks, and LSP
tooling. Application code imports the extension package, not a foreign binary
or a language-specific CBSS SDK.

A Nim package may privately call an existing C, C++, or Rust library through a
stable C ABI. The adapter owns all linking, conversion, panic/exception
containment, thread rules, and cleanup, and exposes a normal Nim component or
`RenderSurface` API. CBSS will not define a generic foreign plugin descriptor,
dynamic Rust/C++ extension loader, or parallel non-Nim plugin registry.

D20 remains unchanged: CBSS's versioned C ABI is the boundary through which an
application written in another language may consume the CBSS runtime. It is
not the authoring and distribution model for the CBSS extension ecosystem.

## D22 — Events are an open runtime contract, not a widget-private protocol (Adopted)

**Context.** D17 assigns reusable UI mechanics to CBSS and application meaning
to callbacks. D21 allows independent Nim packages to provide components,
charts, controls, and design systems. Those decisions do not hold if an
internal widget handler can silently suppress the public handler, bubbling
replaces the original target, a Boolean conflates default prevention with
propagation, or additive listeners cannot be removed independently.

The relevant distinction from a QML-style system is architectural rather than
syntactic. QML has signals and extension mechanisms; CBSS's decision is that its
declaration syntax will not also become the sole component object model, event
protocol, and extension ABI. Ordinary Nim types and packages remain first-class
on both sides of the runtime boundary.

**Decision.** Version 0.4 completes D9 and exposes one stable event contract to
Nim components and C ABI consumers:

- dispatch separates invariant preconditions, public handlers and observers,
  and preventable intrinsic default actions;
- event outcomes distinguish handling, propagation stopping, and default
  prevention;
- original `target`, traversal `currentTarget`, phase, bubbling, cancelability,
  and local-coordinate validity are represented explicitly;
- public property assignment remains replacement-oriented, while additive
  listeners use owned, removable subscriptions with automatic disposal;
- standard event names remain closed and predictable, while library-specific
  semantic output uses typed Nim signals or callbacks rather than string event
  names or core-enum growth;
- dispatch-time UI services avoid strong `UiRoot` captures in the documented
  ARC-safe path; and
- event metadata, generated API surfaces, hot-path lookup, and observable
  semantics remain aligned across Nim and the C ABI.

CBSS controls may implement focus, disabled behavior, keyboard activation,
selection, expansion, and similar UI mechanics. They do not own the business
operation invoked by a public handler. Independent libraries can therefore
compose behavior without replacing CBSS internals or requiring parents to wire
their children's event bundles.

## D23 — One wgpu provider and explicit shared-device ownership (Adopted)

**Context.** A WGSL Custom Style renderer and an independent in-process Nim
compute or visualization package may need the same physical GPU, Device, Queue,
and frame dependency graph. Allowing each package to vendor its own generated
wgpu binding or native runtime risks ABI mismatch and duplicate initialization.
Frame-only callbacks also cannot express persistent pipelines, buffers, or
textures safely.

**Decision.** A wgpu-enabled process resolves one canonical low-level Nim
binding package and one exact compatible `wgpu-native` runtime. Every
in-process package uses that provider; duplicate private bindings or runtime
instances are unsupported in the shared-device path.

A versioned `GpuHost` explicitly operates in CBSS-owned or application-borrowed
mode. Owned mode gives CBSS deterministic Instance/Adapter/Device/Queue
destruction. Borrowed mode requires the application-owned objects to outlive all
CBSS attachments and prohibits CBSS from destroying them. CBSS remains the sole
Surface acquisition and Present owner for each CBSS window in both modes.

Independent packages receive owner-specific, budgeted persistent resource
namespaces plus frame-scoped submission capabilities. Persistent resources may
survive frames; encoders, passes, swapchain textures, and temporary mappings may
not. Device generation, loss, restoration, cancellation, dependency order, and
teardown are part of the contract rather than application convention.

The release gate includes one same-process fixture combining CBSS Motion/WGSL
rendering and an independent Nim compute package on a single runtime, Device,
Queue, and Swapchain. Mock coverage alone is insufficient; the supported Linux
wgpu profile also runs on a real GPU and verifies device loss, shutdown order,
in-flight cancellation, duplicate/version rejection, and enforced GPU-memory
budgets.

## D24 — Public API migration is staged before removal (Adopted)

**Context.** CBSS is pre-1.0 and still needs room to correct public design, but
unannounced churn makes component packages and foreign-language bindings
unnecessarily expensive to maintain. The C ABI has an additional risk: a
header/runtime mismatch can compile successfully and then misread memory.

**Decision.** A product minor release before Version 1.0 may make a necessary
breaking Nim API change; patch releases do not intentionally do so. When a
coherent additive replacement is practical, CBSS introduces it first, migrates
first-party documentation and examples, marks the superseded API with Nim's
standard `deprecated` pragma, and normally retains it for at least two
subsequent minor release lines. A narrower API is not deprecated when it still
has a valid purpose.

The C ABI remains independently versioned. `CBSS_DEPRECATED(message)` can warn
about a superseded function, but its exported symbol and established ownership
remain available throughout the current C ABI major. Struct layout, enum value,
function signature, symbol removal, and ownership changes require a new C ABI
major regardless of the pre-1.0 product version.

Security, memory-safety, or correctness failures may justify an accelerated
removal, but the exception and migration must be explicit in release and
security documentation. The operational checklist and syntax live in
[API Stability And Deprecation](api-stability.md).

## D25 — Frontend capabilities, not React or Redux mechanics (Adopted)

**Context.** React Hooks and Redux collect capabilities frontend engineers
need: local and shared state, deterministic updates, derived values,
subscriptions, lifecycle cleanup, asynchronous work, and testable data flow.
Their exact APIs also carry constraints from React's function-component replay
and reconciliation model. CBSS components are retained objects and should not
inherit Hook ordering, dependency arrays, referential-equality workarounds, or
whole-tree replay merely to provide the same outcomes.

**Decision.** CBSS includes a first-party frontend runtime as an opt-in Nim
module above the style/layout core. It provides typed Stores, Actions,
Selectors, owned effects, Commands, and Cue orchestration while treating
ordinary component fields as the default local-state mechanism. Public
authoring uses Web-familiar names and flow, remains normal Nim with parentheses
and LSP support, and updates stable nodes through bounded invalidation.
The accepted authoring contract uses retained fields for local state, typed
`createStore` / `dispatch`, focused `select` / component-owned `watch`, explicit
source-driven `effect`, typed `command`, standard event properties such as
`onClick`, and readable Cue graph construction. Exact type details may be
refined during implementation, but the interaction model must not regress to
Hook call ordering, dependency arrays, manual forwarding between every Cue
step, or broad component replay.

Standard UI events remain one input boundary, but Cue orchestration is not
limited to UI input. Cue is a separate behavior-side graph that accepts typed
Events, `Signal[T]` occurrences, clock or media markers, lifecycle, Store
changes, Command completion, and independent-library adapters. Only the first
occurrence enters externally; Cue advances serial edges, parallel fan-out,
joins, relative deadlines, completion, failure, and cancellation. Continuous
media or sensor values remain Streams or parameter sources and emit typed Cue
triggers only for meaningful markers or threshold crossings.

Cue is not a CSS property, FIFO queue, media analyzer, or replacement for
event dispatch. Style and motion continue to own visual values and
interpolation; Cue owns ordering, parallelism, joins, deadlines, scoped
ownership, completion, and cancellation. This same contract is intended for
ordinary GUI behavior, game and media UI, motion graphics, animation/video
editing, music-synchronized visual changes, and generative design.

CBSS exposes independent clocks and scoped pause/resume/cancellation mechanics,
but does not define application policies such as game pause, cut-scene rules,
or autosave timing. Applications compose those policies from the primitives.

Importing the frontend runtime is optional. CBSS core continues to accept
external Stores, signals, reducers, or other state systems through ordinary Nim
and Provider boundaries. The complete contract is
[Frontend Runtime Design](frontend-runtime.md).

## D26 — Integration and presentation substrate, not application mechanics (Adopted)

**Context.** Input, media, game, and visualization features can be classified
incorrectly by product category. A touch contact, audio marker, camera frame,
sprite sequence, or tile-map layer may be used by a game, editor, dashboard, or
ordinary application. Whether it belongs in CBSS depends on its technical
responsibility rather than that application category.

**Decision.** CBSS owns the reusable substrate that connects external devices,
libraries, timelines, data streams, and visual assets to retained UI. That
includes typed Events, Signals, Streams, Command completion, Cue triggers,
thread handoff, lifecycle, scheduling, invalidation, coordinate conversion,
layout participation, clipping, hit testing, composition, and accessibility
semantics where applicable.

Sprite animation and tile-map rendering belong to this substrate as visual
asset and image-sequence presentation. CBSS may own frame selection, timing,
texture regions, map-layer traversal, viewport transforms, clipping, culling,
paint caching, and input-coordinate conversion. It does not own gameplay rules,
map meaning, collisions, movement, combat, quests, save formats, or simulation.

Three-dimensional output follows the same rule. CBSS may accept a compatible
texture, render target, or GPU pass; place and clip it inside a Canvas box;
route bounded input; manage synchronization and lifetime at the integration
boundary; and compose normal UI above it. Meshes, materials, lights, cameras,
scene graphs, skeletal animation, visibility, physics, and 3D asset pipelines
belong to an independent Three.nim-like library or application engine.

Similarly, independent clocks and Cue pause/resume/cancellation are reusable
mechanisms. Game-pause policy, autosave conditions, cut-scene decisions, and
other application-specific orchestration remain application code. A feature is
not excluded merely because games use it, and it is not included merely because
one application could automate it.
