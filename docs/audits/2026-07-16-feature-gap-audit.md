# CBSS Feature-Gap Audit — 2026-07-16

Companion to [`2026-07-16-implementation-audit.md`](2026-07-16-implementation-audit.md).
That audit covers **defects**: bugs, performance, memory, and code structure in
what exists. This audit covers **absences**: capabilities a GUI library author
needs from the foundation and cannot obtain today, at any quality level.

Audited at commit `6759560` (branch `main`, clean tree), after the runtime
performance and safety fixes landed. Five parallel investigations covered
layout/scrolling, text/i18n, the style system, accessibility/focus, and
platform/windowing. Every finding below was verified against the code at that
commit; line references were re-checked after the audit fixes landed.

Findings are scored against the project's own positioning — *"CBSS is the
primitive layer that GUI libraries can build on"* (`README.md:14-18`), playing
the role Blink's style/layout engine plays for React and Vue.

Severity scale: **CRITICAL** (a GUI library cannot be built on this today) /
**HIGH** (blocks a mainstream, everyday UI) / **MEDIUM** (real friction, or
wrong-by-default behavior) / LOW (bounded impact).

Section 7 lists confirmed **intentional non-goals**. Do not "fix" those.

## Remediation note

This document remains the historical audit of commit `6759560`; its evidence is
not rewritten after fixes. In the subsequent working tree:

- G4 is partially remediated: typed retained semantics, inherited hidden state,
  layout bounds, and a platform-neutral AT-SPI snapshot/action adapter exist.
  The Linux accessibility D-Bus transport and real assistive-technology
  validation remain open.
- G5 is remediated at the runtime level: general focusability, ordered
  Tab/Shift-Tab traversal, focus-visible, label delegation, and modal Dialog
  containment/restoration are implemented and covered by unit and headless E2E
  tests.
- G6 and G12 have focused remediations for relative positioning and cosmic-text
  fallback/system-font handling.
- G9's CSS custom-property proposal was declined in D19. Nim `var`/`let`/`const`
  and typed style/theme injection remain the authoring mechanism.
- G8's scheduler prerequisite is partially remediated: SDL3 can block on
  ordered event waits, the demo no longer polls every 16 ms while idle, and
  caret/scroll-end wakeups use scheduler deadlines. The animation timeline,
  interpolation, and component-owned `ddAnimation` producers remain open.
- G2's audited px-only gates are remediated. Width/height and min/max constraints
  consume percentage, auto, and intrinsic sizing values; gap consumes percentage;
  flex-basis consumes percentage and intrinsic sizing; and physical/logical
  insets consume signed percentage values. Values remain typed until layout and
  explicit inheritance preserves their unresolved semantics. `em`/`rem` and
  multi-value shorthand expansion remain separate unit and authoring work.

Current decisions and implementation status live in
[`design-decisions.md`](../design-decisions.md), not in the historical finding
text below.

---

## 0. The through-line

Five independent investigations converged on one structural finding, and it is
more useful than any individual gap:

```text
CBSS computes the information. It has one pipe out of it: the style cascade.
Everything that is not the cascade is unwired.
```

Concretely, the same shape five times:

| Area | Produced | Consumed |
| --- | --- | --- |
| Text | ~85 fields in `ComputedTextStyle` (`core/computed_style.nim:483-568`), cascaded and inherited | **14 fields** reach the shaper (`text/cosmic_text_engine.nim:19-33`) |
| Style | `transform`, `filter`, `backdrop-filter`, `mix-blend-mode`, `isolation` parsed into `ComputedStyle` | **zero** reads in `paint/`, `hit/`, `layout/` |
| Layout | `flex-wrap`, `align-content`, `box-sizing`, `direction`, `writing-mode` parsed and stored | **zero** reads in `layout/layout.nim` |
| Semantics | `esChecked`, `esSelected`, `esOpen`, `esDisabled` (`core/node.nim:12-19`) — genuinely semantic state | selector input only; no accessibility, no export |
| Keyboard | Correct Enter/Space/arrow handlers in **every** control | unreachable — key events go only to `state.focusedTarget` (`input/events.nim:696-702`), which only text controls can hold |

`docs/css-property-support.md` names this honestly: 193 of 665 properties are
`Metadata`, and the legend (`:18-20`) states that *"`Runtime` is the only status
that means the property currently changes rendered or interactive behavior."*

**The documentation is accurate. The API is not.** `pct()` and `content()` are
public constructors (`core/style_value.nim:91,103`), so `width: pct(50)`
compiles, type-checks, and fails at resolve time. A doc the author must consult
to learn that a compiling call does nothing is not a substitute for a type
system that refuses it.

The one-line summary of this audit: **`font-variant-east-asian` works and
`width: 50%` does not.** The exotic surface is present; the basics are not.

---

## 1. Top findings (ranked)

### G1 — CRITICAL: the style vocabulary accepts what the engine cannot consume
The meta-finding above, stated as an actionable item. Properties and value
constructors are reachable from typed Nim code, are accepted silently, and are
then discarded. The author has no local signal — the failure surfaces as a
diagnostic at resolve time (best case) or as nothing at all (worst case, see
G6).

**Fix**: parity is a release gate, not a milestone. For every registered
property, exactly one of: (a) a consumer exists, (b) the registration is
removed, or (c) the property errors loudly with a "not implemented" diagnostic
that names the tracking issue. Value constructors that layout cannot resolve
(`pct`, `content`) must not compile — gate them behind the units the resolver
actually accepts, or make `LengthValue` carry a compile-time unit tag. A test
asserting `Runtime`-marked properties in `css-property-support.md` have a
consumer, and `Metadata`-marked ones do not silently claim otherwise, keeps this
from re-accreting. See [D16](../design-decisions.md).

### G2 — CRITICAL: all layout lengths are px-only
`properties/sizing.nim:4-13` — `resolvePx` rejects every unit except `ukPx` with
*"only px is supported for initial sizing implementation"*. This gates `width`,
`height`, `min/max-*`. `properties/positioning.nim:4-13` has the identical gate
for every inset. `gap` (`layout_basic.nim:146-148`) and `flex-basis`
(`layout_basic.nim:245-247`) are px-only too.

There is no `%`, no `auto`, and no intrinsic sizing — `min-content`,
`max-content`, and `fit-content` appear nowhere in `src/`. Boxes size from
children bottom-up (`layout/layout.nim:299-310`), which yields one implicit
max-content-ish behavior with no way to select, override, or invert it.

"Half the parent" and "as tall as its content" are both inexpressible. Every
responsive layout is blocked. This and G3 together mean a resizable window
containing a scrollable list — the most common widget in existence — cannot be
built.

**Fix**: percentage resolution against the containing block, `auto`, and a
min-content/max-content intrinsic pass. The intrinsic pass wants the
measure/arrange split that [D7](../design-decisions.md) already adopts —
land them together.

### G3 — CRITICAL: scroll containers do not exist in any form
`layout/layout.nim`, `paint/paint.nim`, and `hit/hit_test.nim` contain **zero**
occurrences of `scroll`. There is no scroll offset, no content size, no
scrollable region concept.

`overflow: scroll` and `overflow: auto` **do not parse** —
`properties/layout_basic.nim:601-609` accepts `visible`, `hidden`, `clip` and
errors on anything else. The whole overflow model is one bool
(`layout.overflowHidden`); `overflow`, `overflow-x`, and `overflow-y` all
register to the same `applyOverflow` writing that same bool
(`layout_basic.nim:611-613`), so per-axis overflow is inexpressible in
principle. Its only consumer is paint-side clipping (`paint.nim:256-263`).

`scrollbar-width`, `scrollbar-color`, `scrollbar-gutter`, `scroll-behavior`, and
`overscroll-behavior-*` all parse into `ComputedVisualStyle`
(`properties/visual.nim:164-320`) with zero consumers. Wheel input mutates
nothing: the `iekWheel` handler (`input/events.nim:958-960`) records
`state.scrollTarget` for a later `onScrollEnd` and returns.

What exists instead are two private widget hacks, both leaky. `textarea.nim`
carries its own `scrollY` (`:74`) and "scrolls" by **rewriting a style
declaration every frame** — `decl("top", px(-area.state.scrollY))`
(`textarea.nim:1003`) — forcing a restyle and relayout. `text_input.nim` uses a
different mechanism entirely, `node.renderOffset` (`:433`), whose only reader is
the `nkText` branch of paint (`paint.nim:357-359`) and which hit testing ignores
(`text_input.nim:939` manually re-adds it to compensate).

**Fix**: a real scroll offset on the layout box, applied in paint and in hit
testing, with `overflow: scroll/auto` parsed and per-axis overflow separated.
Hit testing needs a clip/transform stack to do this correctly — the same stack
G10 and G11 need. Build it once (see §9).

**Core remediation (2026-07-17)**: `overflow`, `overflow-x`, and `overflow-y`
now preserve independent `visible`/`hidden`/`clip`/`auto`/`scroll` modes.
`LayoutResult` reports sparse viewport and content metrics for scroll-capable
boxes, while a retained `ScrollState` owns clamped offsets by stable `NodeId`.
Wheel input walks from the hit node to the nearest scrollable ancestor. Paint
and hit testing consume the same
ancestor translation and clipping model, including z-index overlay and subtree
paint paths. A scroll offset update does not mutate styles or `LayoutResult`.
Sparse scroll metrics keep synchronization proportional to scroll-capable
boxes, while a per-stage `NodeId -> LayoutBox` index keeps paint and hit
traversal O(n) instead of introducing a nested linear scan.

The shared metrics now also drive overlay scrollbar track/thumb paint.
`scrollbar-width` supports normal, thin, and hidden output;
`scrollbar-color` controls both colors; and the thumb position follows the
retained offset. `overscroll-behavior-x/y` and their shorthand suppress nested
wheel chaining at a boundary for `contain` and `none`. Paint and hit testing
share the same scrollbar geometry, so the thumb can be dragged, track clicks
page the viewport, and neither interaction passes through to child content.
Wheel and scrollbar offset changes emit `onScroll`.

This closes the missing core scroll-container mechanism, not every scrolling
feature. Reserved scrollbar gutters, smooth or kinetic scrolling, and
migration of the textarea's private text viewport onto the shared mechanism
remain separate work. Tests in
`tests/layout/test_scroll_state.nim` lock axis resolution, retained clamping,
paint/hit agreement, clipping, and nested wheel chaining.

### G4 — CRITICAL: no accessibility layer, and semantic state cannot leave the cascade
Word-boundary search across `src/` (excluding `vendor/`) for
`a11y|accessibilit|accessible|aria-|at-spi|atspi|ATK|UIAutomation|NSAccessibility`
returns **zero matches**. The only mention in the repo is `README.md:221`,
listing "Accessibility tree" under *"Possible later features"* — alongside text
input, IME support, and scroll containers, all of which have since been built or
scheduled. Accessibility is the one neighbor left behind.

`Node` (`core/node.nim:25-39`) carries nothing semantic: `NodeKind` is
`nkBox/nkText/nkImage`, purely presentational. No role, no accessible name, no
description, no relations, no live region.

The sharp part: `ElementState` (`core/node.nim:12-19`) —
`esChecked`, `esSelected`, `esOpen`, `esDisabled` — **is** semantic state. CBSS
already computes exactly what an accessibility tree needs, and routes it
exclusively into selector matching. `dialog.nim:114-115` tags title/body nodes
with `groups = ["dialog-title"]`/`["dialog-body"]` — a style hook, not a name
relation; nothing can resolve "this dialog's accessible name is that node's
text."

This is the one capability that **cannot be added downstream**. SDL3 exposes no
accessibility surface of its own, so CBSS is the only layer positioned to own
AT-SPI/UIA/NSAccessibility. A GUI library building its own parallel semantic
tree would have to duplicate the element tree, re-derive geometry for AT hit
testing, and re-derive state CBSS already computes — at which point it is
routing around the foundation, not building on it.

Note also that Blink's headline non-rendering deliverable *is* the accessibility
tree. The positioning claim in `README.md:14-18` is not currently true.

**Fix**: scope decision required — see [D17](../design-decisions.md). The
minimum shape is a role/name/description/value surface on `Node` (or a parallel
`SemanticNode` keyed by `NodeId`), `ElementState` exported as accessible state
rather than only matched, and one platform bridge behind an adapter
(`backends/atspi/`) on the same boundary discipline as the renderer.

### G5 — HIGH: no general focus traversal; keyboard-only operation is impossible
Every control already implements correct keyboard semantics —
`button.nim:56-62` (Enter/Space→click), `checkbox.nim:151-157`,
`radio.nim:184-190`, `select_box.nim:253-273` (arrows/Enter/Space/Escape),
`slider.nim:185-200` (arrows, Home/End), `details.nim:146-151`. **None of them
can be reached.**

Key events dispatch only to `state.focusedTarget` (`input/events.nim:696-702`),
and `focusedTarget` is set only by (a) pointerDown (`events.nim:878-883`) or (b)
text-control traversal. Focusability is hardcoded to two group names:
`isTextInputTarget` (`runtime/text_focus.nim:8-11`) matches
`hasGroup("text-input")` or `hasGroup("textarea")` and nothing else.

**A Button accepts Space only after it has been clicked with a mouse.** A
keyboard-only user can never activate one.

Worse, this cannot be worked around from above. `setFocusedTarget` is public
(`events.nim:374`), but `normalizeTextControlFocus`
(`runtime/text_focus.nim:243-247`) unconditionally blurs and clears
`focusedTarget` to `none` on any pointer hit that is not a text input or label.
Custom focus placed on a Button is destroyed by the next pointer event. The
foundation does not merely omit general focus — it assumes focus means text
focus.

Also absent: any `tabindex` analogue, any `focusNext`/`nextFocusable`
computation, and `:focus-visible` (only `:focus` exists). Tab is wired to
traversal in exactly one place — `testing/test_driver.nim:667-668`. In a shipped
app, Tab does nothing. And `events.nim:878-883` assigns focus to whatever node
was hit with no focusability check, so focus can land on a decorative Box.

**Fix**: generalize focus at the runtime/root interaction layer, as
`architecture.md:216-220` already mandates for text controls. Focusability
becomes a node property, not a group-name string match. Add a documented
traversal order, `:focus-visible` driven by the last input modality, and
`removeEventHandlers`-style focus release. `text_focus.nim` becomes a consumer
of the general mechanism rather than the definition of it.
See [D18](../design-decisions.md).

### G6 — HIGH: `position: relative` is a silent no-op; there is no containing-block chain
`properties/positioning.nim:31-32`:

```nim
of "static", "relative":
  style.layout.position = pkStatic
```

`position: relative` + `top: 10px` produces **no diagnostic and no movement**.
`PositionKind` has two values, `pkStatic` and `pkAbsolute`
(`core/computed_style.nim:369-371`); `fixed` and `sticky` error out as
unsupported keywords.

The silence is the danger. It is also load-bearing: `relative` is what
establishes a containing block in CSS, so the standard "relative parent,
absolute child" overlay idiom is unavailable. And there is no containing-block
model at all — `layout/layout.nim:237` routes every `pkAbsolute` child against
its **immediate parent's** padding box (`:440-463`), unconditionally. There is no
positioned-ancestor concept, no containing-block chain, and no viewport
containing block. An absolute child can never escape to a further ancestor.

`docs/css-property-support.md:128,641` marks `position` as `Runtime` — an
over-claim that hides the silent aliasing.

**Fix**: implement `relative` (offset without removal from flow) and the
positioned-ancestor containing-block chain; error loudly on `fixed`/`sticky`
until they exist; correct the support matrix. This is the highest
value-per-line fix in the audit.

### G7 — HIGH: no inline layout; one Text node is permanently one uniform style
`Node.text` is a flat `string` (`core/node.nim:25-39`); `addText`
(`core/node.nim:69-75`) takes one string; `PaintCommand.pcDrawText` carries one
`text: string` plus one `ComputedTextStyle`. There is no run, span, or attribute
list. Bolding one word in a sentence requires N sibling nodes.

Those siblings cannot form a line. `layout/layout.nim` contains **zero**
occurrences of `inline`, `lineBox`, or `baseline`. Text is measured as an opaque
rectangle (`layout.nim:183-200`) and laid out as a flex box. Sibling Text nodes
do not wrap as one continuous paragraph, and text cannot flow alongside an
inline image. `DisplayKind` is a two-value enum — `dkFlex`, `dkNone`
(`core/computed_style.nim:5-7`) — so there is no inline flow and no block flow
either. Flex is the only layout mode that exists.

The Rust side already supports runs (cosmic-text `AttrsList`); the bridge passes
a single `Attrs` and `None` for the list (`native/cosmic_text_bridge/src/lib.rs:334`).

Blocked: paragraphs, links in text, syntax highlighting, mixed emoji/text runs,
markdown rendering, ruby, and document-level text selection (§3).

**Fix**: this is a data-model change plus real inline layout — the largest item
in this audit and correctly deferred until G2/G3 land. Sequence it after the
measure/arrange split ([D7](../design-decisions.md)), which is the seam line
boxes need.

### G8 — HIGH: there is no time; no animation or transition subsystem exists
`properties/animation.nim` is ~530 lines of pure parse-into-fields: all 31 of its
`PropertyImpl`s write to `style.animation.*` and stop. There is no timeline, no
driver, no keyframe model, no interpolation, and no clock. `keyframe` returns
**zero hits** across `src/` — `animation-name` stores a string that resolves to
nothing, because there is no `@keyframes` registry for it to point at.

**Nothing in the pipeline takes a time parameter.** No property is interpolable
and no tick exists to interpolate on.

`animationDirty` returns **zero hits repo-wide** — the invalidation domain
`docs/architecture.md:252-254` documents does not exist in code. `ddResource`
(`runtime/invalidation.nim:8`) exists but has no producer.

A GUI library cannot implement a fade or a slide today. It must build the entire
animation subsystem itself and drive CBSS by re-resolving styles every frame.

**Fix**: a frame clock owned by the frame scheduler
([D2](../design-decisions.md) already adopts the scheduler — this is its
missing input), an interpolable-value trait on `PropertyImpl`, a `@keyframes`
registry, and a transition driver keyed on computed-style deltas. `animationDirty`
becomes a real domain with a producer. Hover-delay/tooltips and kinetic
scrolling fall out of the same clock.

### G9 — HIGH: the style system has no indirection and no conditional rules
`StyleContext` is `declarations: seq[Declaration]` and nothing else
(`core/style_context.nim:13-14`). There are no CSS variables — the concept is
absent, not stubbed. `docs/css-property-support.md:141` marks `--*` as *"No
plan"*.

`StyleRule` is `selector` + `declarations` + `priority` + `sourceOrder`
(`core/rule.nim:4-8`). There is no condition, no at-rule concept, and no
viewport anywhere in `ResolveEnv` — `resolveTreeStyles` never sees viewport
dimensions. Core does not import `design_source`, so the `ViewportCondition`
that exists at `design_source/model.nim:91-93` is unreachable from core and
gates whole sheets in the importer only.

No theming signal exists either: `prefers-color-scheme|darkMode|theme` returns
zero non-vendor hits. `color-scheme` parses to an `Option[string]`
(`properties/visual.nim:55-79`) that nothing reads.

These compound. Every value in every rule is a literal fixed at construction
time, so **a theme switch means rebuilding every `colorValue(...)` in every rule
and re-resolving the tree.** There is no indirection layer to re-point.

This is the gap most in tension with the positioning. The leverage CSS gives
React and Vue is not its property count — it is variables, queries, and the
cascade, i.e. indirection. A design system *is* variables. Without them CBSS is
a styling API, not a style system.

**Fix**: variables are a policy reversal — see
[D19](../design-decisions.md). `computedValue` closures
(`style_value.nim:133-137`) are not a substitute: they require
`resolveTrustedStyles`, take no arguments, cannot read an ancestor's value, and
do not participate in the cascade. A thunk is not a variable, because nothing
flows down the tree.

### G10 — HIGH: no layer primitive; transforms are a write-only subsystem
`PaintCommandKind` is eight commands (`paint/paint_command.nim:5-13`):
`pcPushClip`, `pcPopClip`, `pcBoxShadow`, `pcFillRect`, `pcFillLinearGradient`,
`pcStrokeRect`, `pcDrawText`, `pcDrawImage`. There is no `pushLayer`/`popLayer`
and no command carrying a matrix.

Consequences:
- **Transforms never reach paint or hit testing.** `properties/transform.nim`
  parses 10 properties into `ComputedTransformStyle`
  (`core/computed_style.nim:317-323`) including `transform-origin`,
  `perspective`, and `preserve-3d`. The only reader in the entire repo is the
  default initializer. `hit/hit_test.nim` tests axis-aligned
  `region.rect.contains(point)` with no inverse mapping. A transformed button
  would paint unmoved and hit-test at its untransformed rect — the two agree
  only because both ignore the transform.
- **Group opacity is impossible.** `paint.nim:302` multiplies
  `inheritedOpacity * style.visual.opacity` into each color individually
  (`withOpacity`, `:60-67`). Overlapping children of an `opacity: 0.5` parent
  composite independently instead of flattening as one layer.
- **`mix-blend-mode` and `isolation` are unimplementable** without exactly this
  primitive. Both parse to real enums (`properties/effects.nim:97-161`) with
  zero consumers.
- `filter` and `backdrop-filter` are stored as **opaque uninterpreted strings**
  (`effects.nim:62-95`) — never tokenized into filter functions. No blur exists
  in any standalone form.
- Gradients are linear only (`core/style_value.nim:19-30` — no radial, no conic).

**Fix**: add `pcPushLayer`/`pcPopLayer` to the command vocabulary and a
transform matrix on the layer. That one primitive unlocks group opacity, blend
modes, isolation, and transforms, and it is the same clip/transform stack G3 and
G11 need.

### G11 — HIGH: popups cannot escape the window; multi-window is structurally blocked
**Popups.** Every overlay is an ordinary in-tree node positioned in window
coordinates. `vendor/sdl3.nim:14425` declares `createPopupWindow`; it has zero
call sites. The Select dropdown (`runtime/select_box.nim:198-206`) is a child
node styled `position: absolute; left: 0; top: px(30); z-index: 101` — the `30`
is a hardcoded literal, not a measurement of the trigger. There is no flip-up,
no collision detection, and no viewport clamping, so a Select near the bottom
edge renders its list clipped. The context menu (`runtime/ui_root.nim:241-262`)
has the same shape at `z-index: 5000` with an unclamped position. Tooltips do
not exist. This is structural: escaping the window needs a second surface with
its own paint and hit passes.

**Multi-window.** There is no window abstraction anywhere in `src/` — no
`Window`, no `Application`. `backends/` is not exported from the public umbrella
(`src/clay_board_style_system.nim`), so a library author consuming CBSS gets no
window at all and must vendor the SDL3 backend. Two hard couplings:
`initSdl3Renderer` owns global SDL lifetime (`SDL3.init` at
`backends/sdl3/renderer.nim:289`, `SDL3.quit()` at `:330` inside `close`), so
closing renderer A tears down SDL for renderer B; and `pollEvent`
(`renderer.nim:587-736`) **never references `windowID`** — it drains the global
SDL queue and attributes every event to `self`, discarding
`raw.window.windowID` while handling `SDL_EVENT_WINDOW_RESIZED` (`:609-612`).
Two renderers would steal each other's events and cross-apply resizes.

One piece of good news: `UiRoot` holds no window handle or viewport
(`runtime/ui_root.nim:34-54`) — it is a pure tree. Multi-window is blocked at
the backend only, not at the runtime layer.

**Fix**: a window-keyed event demux in `pollEvent`, refcounted SDL init, a
`Window` abstraction exported from the public API, and an OS-level popup surface
for overlays that must escape (dropdowns, context menus, tooltips) with viewport
collision handling.

### G12 — MEDIUM: font fallback chain truncated at the first entry; `useSystemFonts` ignored
`effectiveFontFamilies` (`text/font_registry.nim:82-88`) correctly builds the
full chain and joins it to CSV (`text/cosmic_text_engine.nim:288`). Then
`first_family` (`native/cosmic_text_bridge/src/lib.rs:111-127`) iterates the CSV
and **`return`s on the first non-empty entry** — the loop can never reach entry
two. `font-family: Inter, "Noto Sans JP", sans-serif` sends only `Inter`.

Consequence for CJK: Japanese text does not vanish — cosmic-text's internal
script fallback still finds *a* CJK face — but the author's declared Japanese
font is unreachable. **Font choice is not expressible for exactly the text that
needs it most.** For a Japanese-authored project this is the cheapest high-value
fix in the audit.

Separately, `use_system_fonts` is discarded at `lib.rs:224` (`let _ =
use_system_fonts;`). `FontSystem::new()` always loads system fonts, so discovery
works — the missing capability is the inverse: `initFontRegistry(useSystemFonts
= false)` (`font_registry.nim:26-28`) is a lie, and hermetic, reproducible font
rendering (embedded-fonts-only, deterministic screenshot tests) is impossible.

**Fix**: pass the family list across the ABI and build a real cosmic-text
fallback chain; honor `useSystemFonts`. Both are localized.

### G13 — MEDIUM: resources load synchronously inside paint; there is no async pipeline
`drawImageTexture` (`backends/sdl3/renderer.nim:1720-1721`) calls
`loadImageTexture` mid-render, which blocks on FFI file I/O
(`backends/sdl3/image_loader.nim:35`) on the UI thread. First paint of any image
stalls the frame. There is no async pipeline anywhere — no `asyncdispatch`, no
`threadpool`, no `createThread` in `src/` or `examples/`.

The load events are theatre: `renderer.nim:1720-1727` queues `sieLoadStart`,
loads, then queues `sieLoad` and `sieLoadEnd` — **all three in the same call, in
the same frame.** A loading state is never observable, so a spinner can never
render. Unsurprisingly, `ddResource` has no producer (G8).

**Fix**: an async resource pipeline producing `ddResource`, with load state
observable across at least one frame boundary. Gated on the frame scheduler
([D2](../design-decisions.md)).

### G14 — MEDIUM: truncated value sets across working properties
Individually small, collectively constant friction. All verified as parse-errors
or dead fields, not bugs:

- `flex-direction`: no `row-reverse`/`column-reverse` — `FlexDirection` is
  `fdRow`/`fdColumn` only (`computed_style.nim:9-11`).
- `justify-content`: 4 of 6 — no `space-around`, no `space-evenly`
  (`computed_style.nim:24-28`).
- `align-items`: no `baseline` (`layout_basic.nim:327-339`) — and no baseline
  exists to align to (§3).
- `flex-basis`: no `auto`, no `%`, no `content` — `auto` maps to `none`
  (`layout_basic.nim:239-240`).
- `flex-wrap` and `align-content`: fully parsed (`layout_basic.nim:60-70`,
  `:446-463`), stored, never read. Layout is single-line only.
- `box-sizing`: parsed into `bsContentBox`/`bsBorderBox`
  (`properties/sizing.nim:139-160`), defaulted, **never read by layout**.
  Selecting a box model is a no-op.
- `aspect-ratio`: works, but only when exactly one of width/height is set, and
  only accepts `svNumber` (`sizing.nim:117-121`) — the CSS `16 / 9` syntax is
  unsupported.

> Resolution note (2026-08-25): `row-reverse` and `column-reverse` are now
> executable values for `flex-direction` and `flex-flow`. They reverse only
> main-axis coordinates and preserve logical focus and accessibility order.
> Multi-line Flex, content distribution, flexible sizing, and executable
> `box-sizing` have also landed; baseline alignment remains open.

**Fix**: mechanical, once G1's parity gate is in place — each is either
implemented or made to error.

---

## 2. Layout and scrolling

Beyond G2/G3/G6/G7/G14:

- **`display` is flex-or-none** (`computed_style.nim:5-7`). Grid is a stated
  non-goal (§7), but **block flow's absence appears unintentional** and there is
  no substitute — flex is the only tool in the box.
- **`z-index` is a flat global sort**, not real stacking contexts
  (`hit_test.nim:19` packs `zIndex * 100000 + index`; paint uses an `overlayPass`
  at `paint.nim:294`). Interacts badly with the missing containing-block chain
  (G6) and the missing layer primitive (G10). [D8](../design-decisions.md)
  already replaces the packing; stacking contexts proper are a separate item.
- **Hit testing has no clip awareness at all** — `buildHitRegions`
  (`hit_test.nim:54-65`) tests raw `rect.contains` and never consults
  `overflowHidden` or any ancestor clip, so content clipped away by
  `overflow: hidden` remains fully hittable. Already tracked as P7/D8; noted
  here because it is also the blocker for G3.

## 3. Text and internationalization

Beyond G7/G12:

- **Document-level text selection does not exist.** Selection is widget-local
  integer state (`runtime/text_input.nim:27-28`), painted by synthesizing a
  component stylesheet aimed at a private `selectionNode` (`:507,518-522`).
  There is no selection state on `Tree` or `Node`, no anchor/focus API, and
  nothing exported. **You cannot select a sentence spanning two Text nodes —
  i.e. you cannot copy text out of a CBSS document.** `::selection` cannot
  exist: `SelectorCondition` (`core/selector.nim:5-16`) has no pseudo-element
  slot. `user-select` is registered (`generated/default_properties.nim:449`)
  with no consumer.
- **Vertical writing (縦書き) is absent through the entire engine**, not merely
  unimplemented. `writing-mode` parses `vertical-rl` (`properties/text.nim:960-973`),
  inherits (`core/style_resolver.nim:236-237`), and is read by nobody. Beneath
  it: cosmic-text 0.19 is horizontal-only (no vertical metrics, no `vert`/`vrt2`
  GSUB), `layout/layout.nim` is width/height literal throughout with no
  block-flow axis, and the glyph pipeline rasterizes one horizontal bitmap.
  Same for `text-orientation` and `text-combine-upright` (縦中横).
- **Bidi: partial.** cosmic-text runs the UBA internally and CBSS consumes
  `glyph.level.is_rtl()` for caret placement (`lib.rs:547-559`) — the only
  bidi-aware line in the codebase, and RTL carets roughly work. But `direction`
  and `unicode-bidi` parse, inherit, and reach no FFI field, so **the RTL base
  direction cannot be set** — a pure-Arabic paragraph is laid out with an LTR
  base level and misaligns. No RTL mirroring anywhere in layout. No RTL test.
- **Logical properties are physical aliases hardcoded to LTR horizontal-tb.**
  `inline-size`→`applyWidth`, `block-size`→`applyHeight` (`sizing.nim:164-165`);
  `inset-inline-start`→`inset.left` (`positioning.nim:51-58`). These never
  consult `direction` or `writingMode`, so in RTL they resolve to the **wrong
  physical side** — actively wrong rather than merely absent. Disclosed in the
  matrix (`css-property-support.md:295,511,801`), which is to its credit.
- **`line-break` does not exist** — not parsed, not in `ComputedTextStyle`, no
  property impl. So `line-break: strict|normal|loose` is unreachable: whether
  小書きカナ (ゃゅょっ) and 長音符 (ー) may start a line cannot be controlled.
  This is the single knob Japanese typography most needs. Baseline kinsoku does
  come free from UAX #14 via cosmic-text's `unicode-linebreak`, and CJK breaks
  without spaces correctly.
- **`word-break`/`overflow-wrap` are lossy** — both collapse into one 3-value
  `wrapCode` (`cosmic_text_engine.nim:147-156`); `owAnywhere`, `owBreakWord`,
  `wbBreakAll`, `wbBreakWord` all map to `Wrap::Glyph`. `hyphens` parses fully
  and reaches no FFI field — no hyphenation exists. `hanging-punctuation`
  (burasagari) is a parsed `Option[string]` with no consumer.
- **No baseline crosses the FFI.** `CbssCosmicTextMeasureResult`
  (`lib.rs:41-45`) is `{width, height, ok}`; the ascent is discarded at
  `lib.rs:340-343` despite `run.line_y` being right there. So 12px and 24px text
  on one row cannot share a baseline, `vertical-align` is inert
  (`computed_style.nim:562`), and `align-items: baseline` has nothing to align
  to. **Widening the result struct by one field is the enabler** — small, and it
  unblocks G14's baseline item.
- **The default (non-cosmic) engine does not wrap.** `debugMeasureText`
  (`text/text_engine.nim:79-95`) ignores `input.maxWidth` entirely and measures
  `line.len * 8.0` — where `line.len` is **bytes**, so every CJK character
  measures 3 cells wide. This is the fallback whenever the `.so` is missing
  (`cosmic_text_engine.nim:285-286,320`), so **a failed bridge load silently
  degrades to unwrapped, CJK-mismeasured text** rather than failing loudly.
  "Works without Rust" is currently untrue and should be documented as such.
- **Ruby (ルビ) is absent** and correctly gated on G7 — it is inline layout plus
  a second text track. The two existing traces are inert: `ruby-merge` parses to
  an unread `Option[string]`, and `font-variant-east-asian: ruby` selects
  ruby-sized glyph variants, not annotation.

## 4. Style system

Beyond G1/G8/G9/G10:

- **Pseudo-elements are entirely absent.** `pseudo|::before|::after` returns
  nothing across `core/` and `properties/`. `SelectorCondition`
  (`core/selector.nim:9-16`) has no slot for them and `content` has no
  generated-box machinery. Note the contrast: pseudo-*classes* work well as
  state selectors (`requiredStates: set[ElementState]`, matched at `:66-68`), so
  `:hover` is fine. Since a paint command's `owner` is an `Option[NodeId]` tied
  to a real node, pseudo-element boxes need either synthetic nodes or a new
  owner concept — a design call, not a small addition.
- **Effects: what actually reaches paint** is box-shadow (`paint.nim:312-326`),
  linear gradient (`:329-330`), outline (`:343-351`), and `clip-path: inset(...)`
  only (`:118-146`, px-only string parsing). Everything else in
  `properties/effects.nim` is stored and dropped.

## 5. Accessibility and focus

Beyond G4/G5:

- **Focus containment does not exist.** `runtime/dialog.nim` declares `modal`
  (`:12,18`), a setter (`:85-86`), and a getter (`:39-40`). A repo-wide grep for
  reads of `.modal` returns **exactly one hit: its own getter at `dialog.nim:40`.**
  The flag influences nothing. Absent: focus trap, initial focus on open, focus
  restoration on close, background inertness, backdrop click-blocking. Ordered
  behind G5 — a trap has nothing to trap until general focus exists.
- **Cursor works** (not a gap): `properties/input.nim:170` →
  `computed_style.nim:576` → hit regions carry it (`hit/hit_test.nim:10`) →
  `backends/sdl3/renderer.nim:433-460` maps to `SDL_SystemCursor` with a cache.
  Two caveats: only **5 of SDL's 20** system cursors are mapped (no resize
  cursors, no crosshair, no wait/progress — so a resizable split-pane or a busy
  state cannot be built), and the last-mile `setCursor` call site lives in
  `testing/integration/sdl3_wayland_driver.nim:291`, so driving it per frame is
  left to the embedder rather than being turnkey.
- **No tooltip mechanism**, and no hover-delay/dwell primitive to build one on.
  Genuinely downstream-addable once a clock exists (G8) — lowest priority here.

## 6. Platform and windowing

Beyond G11/G13:

Framing note: `src/clay_board_style_system/vendor/sdl3.nim` is a complete
translation of the SDL3 headers. `showFileDialogWithProperties` (`:16487`),
`showSimpleMessageBox` (`:23843`), `getSystemTheme` (`:13925`),
`getDisplayContentScale` (`:14067`), `createTray` (`:27328`), and
`SDL_EVENT_DROP_FILE` (`:2345`) are all **already declared and callable** and
have zero call sites. Most items below are therefore "declared but unwrapped,"
which is cheap. The structurally blocked ones are marked.

- **Native dialogs: nothing wrapped** — no file open/save, no message box.
  Unwrapped only. (SDL3 has no color picker; that needs a portal binding or an
  in-tree widget.)
- **Window chrome/state: nothing wrapped.** The only window properties that
  exist are frozen into `initSdl3Renderer`'s signature
  (`renderer.nim:276-281`): title, width, height, resizable. Title is set once
  at creation (`:297`) and is never mutable; flags are hardcoded to
  `resizable | highPixelDensity` (`:295-296`). Not exposed despite all 28
  `setWindow*` procs existing: icon, min/max size, fullscreen, always-on-top,
  opacity, decorations, position, maximize/minimize/restore. `pollEvent`
  (`:606-618`) handles only QUIT, CLOSE_REQUESTED, RESIZED, PIXEL_SIZE_CHANGED,
  and FOCUS_GAINED/LOST — **an app cannot know it was minimized.**
- **OS file drop — STRUCTURAL.** `SDL_EVENT_DROP_FILE/DROP_TEXT/DROP_BEGIN` are
  declared and fall into `else: discard` (`renderer.nim:734-735`). The blocker
  is not the backend: `InputEvent` (`input/events.nim:104-117`) has **no payload
  field able to carry file paths** — only position, button, key, text, delta,
  focusOwner, modifiers. `text` is capped at 8 KB and semantically overloaded.
  A real file drop needs a new event kind plus a `files: seq[string]` field —
  a core event-model change.
- **DPI never reaches style or layout.** `pixelScale`
  (`renderer.nim:506-512`) exists and its only five consumers are texture
  rasterization inside the renderer. Nothing in `core/`, `layout/`,
  `properties/`, or `runtime/` references it. `rem` resolves against a root
  font-size, not a device ratio — there is no px-ratio concept at all.
  **On a monitor change, nothing happens**: no `SDL_EVENT_DISPLAY_*` is handled
  (including `DISPLAY_CONTENT_SCALE_CHANGED`), and there is no display
  enumeration, no per-monitor bounds, no "which screen am I on."
- **System integration: entirely absent.** `systemTheme|prefers-color-scheme|
  reduced-motion|trayIcon|notification` returns zero hits across `src/` and
  `examples/`. No system dark/light theme, no system font settings, no
  reduced-motion, no tray. Compounds G9 — even with a theme signal there is no
  indirection layer to re-point.
- **Clipboard genuinely works** (least-bad): the OS path is real
  (`renderer.nim:741-769`, reaching Wayland/X11), wired through injectable
  closures on `UiRoot` (`ui_root.nim:10-11,48-49,89-95`) that the text controls
  call. Real gaps: **CBSS never wires the closures — the demo does**
  (defaults are `proc(): string = ""` and `proc(text: string) = discard`,
  `ui_root.nim:76-77`; the only production wiring is
  `examples/sdl3_demo.nim:2831-2850`), so a library author must reimplement the
  glue. Text only — no images, no MIME negotiation. Pastes over 8 KB are
  silently truncated (`events.nim:148,330`). `SDL_EVENT_CLIPBOARD_UPDATE` is
  unhandled; the demo compensates with a focus-gained heuristic that misses
  same-focus external changes.

## 7. Confirmed intentional non-goals — do not "fix" these

Verified against project docs and owner statements. Listed so a future
contributor does not mistake a deliberate boundary for an oversight.

- **CSS Grid / Masonry** — `docs/css-property-support.md:482-491`: *"Full CSS
  Grid/Masonry is not an initial CBSS layout goal."* Zero grid properties
  registered. Note the interaction: this is fine on its own, but combined with
  the unintentional absence of block flow (§2) it leaves flex as the only layout
  mode.
- **Descendant and child selectors** — `docs/architecture.md`. Contextual
  styling goes through explicit style injection and merged contexts instead.
- **Structural pseudo-classes** (`:first-child`, `:nth-child`, …) — deferred to
  generation-time metadata by design; the generating code already knows.
- **Deprecated and duplicated CSS properties** — omitted deliberately.
- **Serialized style import/export** — CBSS has no serialization
  (`readFile`/`writeFile`/JSON hits in `src/` are limited to
  `backends/ppm/raster.nim:149`, a PPM writer). External styles are Nim modules
  imported at compile time. This is consistent with the compile-time authoring
  model and is not a gap under current positioning.

**Not on this list**: CSS custom properties. `css-property-support.md:141` marks
`--*` as "No plan," which G9 argues against — see
[D19](../design-decisions.md). That is a decision to revisit, not a boundary
to respect silently.

## 8. What is notably good (calibration)

- **Every control already implements correct keyboard semantics.** The work is
  done; only the focus wire is missing (G5). This is a much better position than
  it appears.
- **`ElementState` is already the accessibility state model.** `esChecked`,
  `esSelected`, `esOpen`, `esDisabled` are exactly what an AT tree needs — they
  just have no exit (G4). The information is being produced.
- **Clipboard is genuinely wired to the OS** and correctly abstracted behind
  injectable providers.
- **Flex core is correct where it exists.** `flex-grow`, `flex-shrink` weighted
  by basis, `order`, `align-self`, `gap` all work — and the scaled shrink
  weighting is right, which most homegrown flex clones get wrong.
- **CJK line breaking works for free** via UAX #14 through cosmic-text, including
  default-strictness kinsoku. RTL carets work.
- **The support matrix is unusually honest.** The `Metadata` tier and the
  legend's *"`Runtime` is the only status that means the property currently
  changes rendered or interactive behavior"* (`:18-20`) are accurate. Two real
  over-claims found (`position` at `:128,641`; `overflow` at `:120-122,604-612`)
  and three under-claims (`aspect-ratio`, `order`, `align-self` marked
  `Computed` but actually Runtime).
- **`UiRoot` holds no window handle or viewport** — multi-window is blocked only
  at the backend, not in the runtime model.
- **The renderer/core boundary holds**, as the implementation audit also found.
  Every gap above is additive; none require unwinding a wrong abstraction.

## 9. Recommended order

The dependency structure matters more than the ranking. Three observations
drive it:

1. **One seam serves three gaps.** A clip/transform stack in hit testing is
   required by scroll (G3), transforms (G10), and popups (G11). Build it once.
2. **One clock serves four.** Animation/transitions (G8), tooltips/hover-delay
   (§5), async resources (G13), and kinetic scrolling all wait on a frame clock
   — which [D2](../design-decisions.md)'s frame scheduler is the natural
   owner of.
3. **One export serves three.** Role/name on `Node` plus general focusability
   yields accessibility (G4), keyboard operation (G5), and focus containment
   (§5) from a single change.

**Phase A — stop the silent lies (small diffs, restores trust)**
1. G1 parity gate: every registered property has a consumer, is removed, or
   errors loudly. `pct()`/`content()` must not compile while unsupported.
2. G6 `position: relative` — implement it or error; correct the support matrix.
3. G12 font family chain across the ABI + honor `useSystemFonts`.
4. Document that the default text engine does not wrap and mismeasures CJK (§3).

**Phase B — the basics (unblocks a GUI library at all)**
5. G2 percentage / `auto` / intrinsic sizing, landed with
   [D7](../design-decisions.md)'s measure/arrange split.
6. The clip/transform stack in hit testing, then G3 scroll containers on it.
7. G5 general focus traversal, then G4's semantic export on the same pass.

**Phase C — the subsystems**
8. G8 frame clock + interpolation + `@keyframes`; `animationDirty` gets a
   producer; G13 async resources follow.
9. G9 variables + conditional rules (pending [D19](../design-decisions.md)).
10. G10 layer primitive; transforms reach paint and hit.
11. G11 window abstraction + event demux; OS popup surface.

**Phase D — depth**
12. G7 inline layout and rich text; document selection, ruby, and baseline
    alignment follow it.
13. G14 value-set completion (mechanical once Phase A's gate exists).
14. Vertical writing (縦書き), RTL base direction, `line-break` — all gated on an
    axis abstraction and a widened FFI.
