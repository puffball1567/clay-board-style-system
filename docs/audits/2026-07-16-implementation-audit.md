# CBSS Implementation Audit — 2026-07-16

Full-codebase audit of CBSS at commit `d7ceb4a` (branch `main`, clean tree).
Seven parallel reviews covered: core style system, layout, runtime,
paint/hit/input, SDL3 backend + text stack + FFI, build/test/repo structure,
and a dedicated performance/memory pass with compiled benchmarks.

Every finding below was verified against the actual code (file:line), and the
layout/performance findings were verified empirically with compiled probe
programs against the real pipeline (`--mm:arc -d:release`).

Severity scale: **CRITICAL** (breaks the product promise now) / **HIGH**
(wrong behavior or unsustainable cost on the main path) / **MEDIUM**
(correctness or policy drift with real consequences) / LOW (worth fixing,
bounded impact).

---

## 0. Measured performance baseline

CBSS is required to be lightweight and fast. Measured today (release build,
per-node stylesheets as `ui_root.applyStyle` produces them):

| nodes | resolveTreeStyles | computeLayout | buildPaintCommands | hit build | hit test/move |
|------:|------------------:|--------------:|-------------------:|----------:|--------------:|
| 500   | 8.9 ms  | 257 ms    | 235 ms    | 0.06 ms | 0.001 ms |
| 1000  | 19.6 ms | 1,205 ms  | 974 ms    | 0.23 ms | 0.003 ms |
| 2000  | 70 ms   | 5,445 ms  | 4,839 ms  | 0.92 ms | 0.006 ms |
| 4000  | 289 ms  | 23,801 ms | 23,755 ms | 3.4 ms  | 0.012 ms |

Layout and paint are **O(n²) with a ~6 KB constant factor**. The engine falls
below 60 fps at roughly 150 nodes and below 1 fps at ~2,000 nodes. Style
resolution is also O(n²) in the per-node-stylesheet pattern the runtime itself
generates. Hit testing is healthy.

Measured struct sizes: `ComputedStyle` = **5,664 B** (~350 fields),
`PaintCommand` = **1,560 B**, `Node` = 168 B, `InputEvent` = 128 B.

The three fixes P1–P3 below take the 1,000-node frame from ~2.2 s to
low-single-digit milliseconds. They are small, surgical changes.

---

## 1. Top-priority findings (ranked)

### P1 — CRITICAL: sort comparator closures deep-copy the entire `ResolvedTree` per node
`layout/layout.nim:200-207` and `paint/paint.nim:348-349` (also `paint.nim:377`).

```nim
orderedChildren.sort(proc(a, b: NodeId): int =
  let leftOrder = styles.styles[a.nodeIndex].layout.order  # captures `styles`
  ...)
```

Under ARC, capturing the `styles` parameter copies the whole
`seq[ComputedStyle]` (n × 5,664 B) into the closure environment — **once per
node, per pass**. Micro-benchmark: capturing an 8 MB value in a sort closure
costs 2,320 ms / 2,000 calls vs 0.2 ms when passing a pointer (~10,000×).
This one pattern accounts for ~99% of measured layout+paint time.

**Fix**: never capture large values in hot-loop closures. Precompute sort keys
into a scratch `seq[(int32, NodeId)]` and sort with a `{.nimcall.}` comparator,
or skip the sort when all `order`/`zIndex` are 0 (the common case).

### P2 — CRITICAL: `em`/`rem` unusable through tree resolution — font context never populated
`core/style_resolver.nim:67`: `let env = ResolveEnv(parent: parent)` leaves
`rootFontSize`/`currentFontSize` always `none`, so `properties/font_size.nim:24-35`,
`margin.nim:18-29`, `padding.nim:18-29` emit "em requires current font-size"
errors even when font-size is fully known. All public tree-resolution entry
points are affected.

**Fix**: two-phase resolve — resolve `font-size` declarations first, then build
`env` (root font size from root/`ResolveOptions` default, current from the
node's own resolved font-size) before applying remaining declarations.

### P3 — HIGH: O(nodes × rules) selector matching; the runtime's own style pattern makes it O(n²)
`core/style_resolver.nim:33-53` rescans every rule of every sheet per node,
allocates and sorts a fresh `seq[MatchedDeclaration]` per node.
`runtime/ui_root.nim:143-147` (`applyStyle`) creates one single-rule sheet per
styled node, so sheets ≈ nodes and full resolve is O(n²) — and re-runs on every
state change.

**Fix**: bucket rules by target at registration (`nodeIndex → seq[RuleRef]`
plus a short list for group/kind selectors); pre-sort per bucket (priority /
specificity / order are resolve-invariant); reuse a scratch seq.

### P4 — HIGH: stylesheets grow without bound during slider/progress/textarea interaction
`runtime/ui_root.nim:143-147` `applyStyle` **appends** a new sheet every call.
`slider.nim:62-64` calls it on every pointer-move of a drag;
`progress.nim:62-64` per `setValue`; `textarea.nim:405-412` per resize-drag
move. Every appended sheet permanently slows all future style resolution —
a session-lifetime memory leak and a progressive frame-time regression.

**Fix**: keyed replacement (`setNodeStyle(nodeId, sheet)`), the same
replace-by-index pattern the text controls already use
(`text_input.nim:461-465`, `text_focus.nim:140-144`).

### P5 — HIGH: reference cycles under `--mm:arc` leak the whole UI graph on every rebuild
All builds use `--mm:arc` (no cycle collector). `UiRoot` (ref) owns
`EventRegistry`; controls register closures capturing handles whose `root`
field points back at the same `UiRoot` (e.g. `text_input.nim:1064-1067`,
`select_box.nim:226-233`). UiRoot → registry → closure env → handle.root →
UiRoot is a true cycle. The demo replaces `ui = makeUi(...)` per state
dispatch (`sdl3_demo.nim:3630-3631`), leaking the previous tree, registry,
styles, and closures each time.

**Fix**: `{.cursor.}` (non-owning) `root` references in handles / closure
contexts, or key internal handlers off `NodeId` + context passed at dispatch;
alternatively build with `--mm:orc` as a safety net.

### P6 — HIGH: single-pass layout finalizes children before their container size is known
`layout/layout.nim` (verified empirically):
- **No min/max re-clamp after grow/shrink** (no CSS freeze/redistribute loop):
  `flex-grow:1; max-width:30px` in a 200 px row ends at w=100 (should be 30);
  `min-width:55px` under shrink ends at 40 (should be 55). (`layout.nim:299-341`)
- **A grown/stretched child's interior is never re-laid-out**: a `flex-grow:1`
  panel (50→200 px) with `justify-content:center` leaves its inner child
  centered for the old 50 px width. (`layout.nim:57-76,237-247`)
- **Text is measured against the parent's incoming constraint, not the node's
  resolved width** (`layout.nim:150-155`), while paint wraps at the final box
  width (`paint.nim:323-325`) — layout and paint disagree about wrapping;
  boxes get sized for unwrapped text that then wraps at paint time.

**Fix (keystone)**: introduce a measure/arrange two-pass. After final sizes are
known, re-run layout for flexed/stretched children with definite constraints.
This also unlocks F-L4/F-L5/F-L8 below and provides the seam `flex-wrap` needs.

### P7 — HIGH: hit testing disagrees with painting
`hit/hit_test.nim`:
- Not clipping-aware (`:54-65`): children overflowing an `overflow: hidden`
  parent are clickable in the invisible area (architecture.md promises
  "clipping-aware hit regions").
- Stacking layer not propagated to descendants (`:63` + `layout.nim:438`):
  a button inside a `z-index: 10` overlay sits in layer 0 — content behind a
  modal can steal its clicks.
- Negative z-index encoding broken: `zIndex * 100000 + index` then
  `div 100000` truncates toward zero, so `z-index: -1` lands in layer 0
  (verified numerically).
- Same-layer ties resolved by **smaller area**, not paint order (`:70-78`) —
  "topmost wins" is violated for overlapping siblings.

**Fix**: record the paint traversal order index during region build, store
`(layer, order)` as two fields, propagate effective layer down the tree,
intersect region rects with the accumulated ancestor clip.

### P8 — HIGH: any 1 px pointer movement between down and up kills the click and fires a drag cycle
`input/events.nim:818-831,895`: `dragTarget` is set on the first
`iekPointerMove` with a pressed target — no distance threshold — and click is
synthesized only if **zero** motion events occurred. Real mice jitter; clicks
become unreliable and spurious `dragStart/drag/drop/dragEnd` fire. Tests pass
only because the test driver sends down+up with no motion.

**Fix**: record the pointer-down position; promote to drag only past a
threshold (e.g. 4 px Manhattan); synthesize click below it. Related:
`iekPointerCancel` never resets pressed/drag state or honors capture
(`events.nim:784-790,931-932`), and double-click has **no time source at all**
(`events.nim:914-926` — two clicks minutes apart fire `onDoubleClick`; the SDL
backend already captures `raw.button.timestamp` and drops it).

### P9 — HIGH: Rust text bridge has no panic isolation — a panic aborts the whole process
`native/cosmic_text_bridge/src/lib.rs` has no `catch_unwind` (verified) and no
`panic = "abort"` profile; entry points index slices and allocate unbounded
(`lib.rs:509,691,700`). On Rust ≥ 1.81 a panic crossing `extern "C"` aborts
the host app, despite every call having an `ok`/status channel designed for
graceful fallback.

**Fix**: wrap every entry point in `std::panic::catch_unwind(AssertUnwindSafe(...))`
returning the error status; or set `panic = "abort"` deliberately and document it.

### P10 — HIGH: the documented dirty-domain scheduler is dead code; the real incremental pipeline lives inside the demo
`runtime/invalidation.nim` defines exactly the seven documented dirty domains —
its only consumers are its own test and the public re-export. Meanwhile the
working incremental machinery (`repaintDirtySubtrees`, static/dynamic layers,
event coalescing, text-control repaint) lives in `examples/sdl3_demo.nim`
(3,740 lines). Every real app would have to reinvent the production update
path the architecture doc mandates. The demo loop also never blocks on events
(`delay(16)` idle poll — permanent 60 Hz wakeup), and any state action rebuilds
the *entire* UI tree (`makeUi` + full `buildFrame`, `sdl3_demo.nim:3630-3643`).

**Fix**: lift the demo's frame machinery into `runtime/frame_scheduler.nim`
consuming `InvalidationState`; controls mark dirty domains; expose
`waitEvent(timeoutMs)` from the backend and sleep when no domain is active.

**Remediation status (2026-07-17):** the scheduler primitive and SDL3 ordered
wait APIs exist, and the demo blocks when idle with deadlines for caret blink,
scroll end, and transient input draining. Dirty-domain classification is now a
real consumer in the demo. Full frame construction and some invalidation
producers still live in example-local code, so P10 is only partially closed.

### P11 — HIGH: ~850 duplicated lines between text_input.nim (1,277) and textarea.nim (1,821)
~72% of text_input's non-blank lines appear verbatim in textarea (rune
helpers, undo stack, edit commands, clipboard, the 60-line printable-key
table, ~250 lines of handler registration). They have **already diverged**:
change-event semantics differ between the two controls and between input
paths of the same control (`text_input.nim:1272-1273` emits input only;
`textarea.nim:1772-1773` emits input+change per keystroke).

**Fix**: extract `runtime/text_edit_core.nim` (buffer + caret/selection/undo +
key command mapping + composition state) parameterized single/multi-line;
define one change-event contract (per-edit `input`, commit/blur `change`).

### P12 — HIGH: `ComputedStyle` is a 5.7 KB struct copied ≥3× per node during resolve
`core/computed_style.nim:697-707`: ~350 fields, of which ~150 are
`Option[string]` passthroughs nothing consumes (`mask-*`, `timeline-trigger-*`,
`corner-*-shape`, SVG vector fields with no vector element, 2009-era
`legacyBox*`). `style_resolver.nim:145` copies the full struct per child edge,
`:67` again into env, `:142` into the result. 10k nodes ≈ 57 MB of styles.

**Fix**: split into a compact hot struct (layout/box/visual numerics, ~300 B)
plus a lazily-allocated `ref` extension for long-tail fields (nil for ~99% of
nodes); pass parent as `lent`; trim the speculative property surface to what
elements actually read, with one documented passthrough table for the rest.

**Remediation status (2026-07-23):** parent styles are borrowed rather than
stored in `Option[ComputedStyle]`, and hot layout/paint/hit locals use ARC
cursor borrows. Columns, mask, and vector metadata are now lazy cold refs,
reducing the ordinary inline value from 5,672 to 3,448 bytes. Animation and
transform metadata now use value-preserving lazy accessors as well, reducing
the inline value to 2,944 bytes. This materially improves the pipeline, but
the remaining wide text/box/visual groups still exceed the retained-memory
target. P12 remains partially open.

---

## 2. Core style system (`core/`, `properties/`, `generated/`)

- **HIGH — Inheritance hardcoded in the resolver** (`style_resolver.nim:69-141`):
  a ~70-line per-property copy block duplicates the `mmInherit` logic property
  modules already own — the exact central switch the architecture forbids.
  It also breaks semantics: explicit `initial()` gets silently converted back
  to inherit (e.g. `font-family: initial` → parent's family), and
  non-inherited properties (`object-fit`, `object-position`) are force-
  inherited. **Fix**: `inherited` flag/proc on `PropertyImpl`; registry-driven
  generic inheritance pass; tri-state (unset / explicitly-reset / set).
- **HIGH — Cascade order breaks when `rule.sourceOrder` is set**
  (`style_resolver.nim:34-48`): explicit sourceOrder values are compared
  against a per-node running declaration counter — two incompatible scales in
  one `cmp`. `Declaration.sourceOrder` is meanwhile a public field that is
  **silently ignored** everywhere. **Fix**: compare
  (priority, specificity, sheetIndex, ruleIndex, declIndex); make explicit
  sourceOrder a distinct documented tier or remove it.
- **MEDIUM — Property-name string re-dispatch inside property modules**:
  `properties/text.nim:1005-1204` has three parallel ~65-branch string
  switches (set/clear/get) that must stay in sync; same pattern in border,
  visual, margin, padding, sizing, mask, vector, columns, animation. Silent
  `else: discard` branches already produced live bugs: `margin-inline` with
  relative merge computes from 0 instead of the base value
  (`margin.nim:60-71,154-166`); an unmatched font keyword silently writes
  `fontSynthesisWeight` (`text.nim:329-342`). **Fix**: generate one
  `PropertyImpl` per property with a field accessor captured at registration
  (macro), eliminating name re-dispatch; make fallthroughs assert.
- **MEDIUM — ~130 copies of the same 5-arm merge-mode skeleton** across 19
  property modules; `resolveLength`/`resolvePx` redefined 8+ times with
  inconsistent unit acceptance and error text. A declarative one-line-per-
  property macro (`lengthProperty("padding-top", box.padding.top, units = {...},
  inherit = ...)`) would collapse ~4,000 lines and make merge policy auditable.
- **MEDIUM — `generated/default_properties.nim` is not generated**: 429
  hand-maintained `registerProperty` calls, no generator in the repo. **Fix**:
  real generator or registration macro + a test asserting every exported
  `PropertyImpl` is registered. `registerProperty` silently overwrites
  duplicates (`registry.nim:11-12`) — add a duplicate diagnostic.
- **MEDIUM — Shorthand/value-model gaps**: `padding: 8px 12px` (the doc's own
  flagship example) is unrepresentable — no multi-length value kind
  (`padding.nim:84-97`); `overflow-x/y` silently collapse into one flag
  (`layout_basic.nim:611-613`); `transform-origin: left` wrongly sets both
  axes to 0% (`transform.nim:242-246`); `text-wrap-mode`/`text-wrap-style`
  clobber each other (`text.nim:1402-1403`); px and % silently conflated for
  `background-position`/`text-size-adjust` (`background_color.nim:159-161`,
  `text.nim:1264-1266`); `position: relative` silently treated as static
  (`positioning.nim:30-32`); multi-token values smuggled through `svKeyword`
  strings with per-property micro-grammars (`style_value.nim:117-121`,
  `layout_basic.nim:107`). **Fix**: add `svLengthList`/string-list value
  kinds; per-axis overflow; keyword-axis-aware origins; diagnostics instead of
  silent aliasing.
- **MEDIUM — Node arena never frees**: no `removeNode`, free-list, or
  generation counter (`node.nim:41-60`); dynamic UIs leak slots and every
  `ResolvedTree.styles` grows with them. Add tombstone + free-list and make
  `NodeId` (index, generation) before external code bakes in raw indices.

## 3. Layout engine (all verified with compiled probes)

Beyond P6:
- **MEDIUM — `display:none` children still consume gap slots and
  justify-content counts** (`layout.nim:144-146,208-263`): row `gap:10` with
  [20, none, 20] yields width 60 and third child at x=40 (should be 50 / 30).
- **MEDIUM — Shrink floors at 0 without redistributing the remaining deficit**
  (`layout.nim:324-341`) — content overflows although siblings had capacity.
- **LOW — min/max conflict resolves the wrong way** (`clampSize`,
  `layout.nim:78-87`): max currently beats min; CSS says min wins.
- **MEDIUM — `justify-content` supports only 4 values** — no
  `space-around`/`space-evenly` (`computed_style.nim:24-28`), yet the support
  matrix marks it Runtime without caveat.
- **MEDIUM — `white-space` marked Runtime but never consulted by layout**, and
  the default debug text engine ignores `maxWidth` entirely
  (`text_engine.nim:79-95`).
- **MEDIUM — structure**: `layoutNode` is one 314-line proc with ~14 duplicated
  `direction == fdRow` branches; `flexWrap`/`alignContent` have no seam to
  land in. **Fix**: main/cross `AxisView` abstraction; split into
  measureLeaf / collectFlexLines / resolveFlexibleLengths / justifyAndAlign /
  placeAbsolute.
- **LOW — absolute positioning**: `left+right` together never stretches
  (`layout.nim:422-435`); absolute children measured against stale constraints.
- Also: `boxFor` in paint and `relayoutSubtree` do linear box scans — add a
  `nodeIndex → boxIndex` array to `LayoutResult` (fixes three call sites,
  including `focusedTextInputPlacement`).

## 4. Runtime layer

Beyond P4/P5/P10/P11:
- **MEDIUM — Focus has two competing staleness mechanisms**: the tested
  library mechanism (`focusSerial`/`markFocusOwned`, `events.nim:372-394`) is
  used only by the test driver, while the shipped demo uses a separate
  timestamp scheme (`isStaleTextControlEvent`, discard modes,
  `sdl3_demo.nim:2885-2935`). Three actors mutate `esFocus`. **Fix**: make the
  focus-serial path the single mechanism, applied at the root interaction
  layer; move the focus/blink/discard logic from the demo into
  `runtime/interaction.nim`.
- **MEDIUM — Component semantics drift across the ~15 controls**:
  dialog/command_menu encode *closed* as `esDisabled` (a `:disabled` selector
  matches every closed dialog; `disabledTarget()` treats their descendants as
  disabled) while select/details use `esOpen`; radio activates on pointerDown
  + click while others use click; select_box suppresses positioned clicks via
  `position.isSome` sniffing; disabled keydown is consumed by most controls
  but bubbles from text controls; fieldset auto-disable only registered by 4
  of ~10 interactive controls; attribute mirroring inconsistent. **Fix**: a
  written control-authoring convention (state flags, activation gesture,
  guard placement, emitted attributes) applied mechanically; use `esOpen` for
  open/closed.
- **MEDIUM — Visual policy baked into "style-neutral" controls**: hardcoded
  selection/caret colors (`text_input.nim:1037-1053`), checkbox glyph/color
  (`checkbox.nim:109-124`), radio dot, details `"v"/">"` markers, slider/
  progress injecting percentage text, select popup fixed at `top: 30px` with a
  fixed z-index scheme, and a fully-styled context menu inside `ui_root.nim`
  (:181-208, :427-504). **Fix**: theme layer with replaceable defaults;
  indicator glyphs/text as parameters; context menu out of the core builder.
- **LOW — caret/selection**: rune-safe (verified) but not grapheme-cluster-
  aware; `maxLength` counts bytes (document or count runes); Ctrl+Backspace
  treats a whole CJK run as one word.

## 5. Paint / hit / input

Beyond P7/P8:
- **MEDIUM — Overlay paint pass drops ancestor opacity/visibility/clips**
  (`paint.nim:372-379`): a `z-index:1` child of an `opacity:0.3` or hidden
  parent paints fully opaque/visible.
- **MEDIUM — `pointer-events:none` / `visibility:hidden` on a container does
  not affect children in hit testing** (`hit_test.nim:56-57`) — invisible
  subtrees remain hittable; paint prunes them.
- **MEDIUM — `events.nim` (932 lines) is the forbidden central catch-all**:
  adding one event touches the enum, `dispatchMode` case, slot list,
  `expandedEventKinds`, `processInput`, plus a duplicated slot list in
  `ui_root.nim:634-724`. ~30 public slots (media/fullscreen/cue/encrypted)
  have **zero** firing paths; `onScrollEnd`'s only producer is called from
  tests only. **Fix**: single declarative event table (macro-generates both
  registries); split synthesis into `input/synthesis.nim`; remove dead slots
  until a real firing path exists (the architecture doc explicitly endorses
  this).
- **MEDIUM — Handler registry**: append-only (no removal API; stale bindings
  accumulate for replaced subtrees), O(bindings) linear scans per dispatch ×
  expanded kinds × ancestors, internal handlers run first and a `true` return
  blocks user handlers entirely (a user `onClick` on a details summary can
  never fire — `details.nim:135-140`); a consumed `beforeinput` silently
  swallows `input`/`change` (`events.nim:614-627`). **Fix**: per-node binding
  table, explicit cancel vs handled, user-before-internal-defaults order,
  `removeEventHandlers(node)`.
- **MEDIUM — Button numbering mixes SDL (left=1) and DOM (left=0)**
  conventions (`renderer.nim:626` vs `events.nim:209-213`); `click` +
  `auxclick` + `contextmenu` all fire for right-clicks (`events.nim:895-913`).
  Normalize to DOM numbering at the backend boundary; click = primary only.
- **MEDIUM — enter/leave synthesized identically to over/out** (no LCA walk,
  `events.nim:792-816`) and every kind bubbles, including non-bubbling ones.
- LOW: overflow clip uses content box instead of padding box
  (`paint.nim:223-232`); negative z-index children paint above the parent
  background; `input/pointer.nim` is a vestigial second hover path — delete.

## 6. SDL3 backend / text stack / FFI

Beyond P9:
- **HIGH — 27,782-line SDL3 binding duplicated** (`src/.../vendor/sdl3.nim` vs
  `bindings/c/sdl3/sdl3.nim`), already drifted at line 245 where the stale
  copy types IME `candidates` as `cstring` instead of
  `ptr UncheckedArray[cstring]` — importing the wrong copy is memory-unsafe.
  Nothing imports the `bindings/` copy. **Fix**: delete or reduce to the
  documented generator input; keep one copy.
- **MEDIUM — long text (>256 B) re-shaped over FFI + texture created/destroyed
  every frame** (`renderer.nim:1866,1916`); the same cutoff disables the
  measure cache, so layout re-measures paragraphs per pass. **Fix**: hash-based
  cache keys (uint64 content hash instead of building `|`-joined key strings
  per frame — `cosmic_text_engine.nim:364-394`), bound caches by bytes, LRU
  via `Table` instead of linear scans.
- **MEDIUM — static layer rasterized at logical resolution** — blurry on
  HiDPI (`renderer.nim:2025-2031`); size at `renderOutputSize()` like
  `createRoundedImageTexture` already does.
- **MEDIUM — `useSystemFonts` silently ignored by the bridge**
  (`lib.rs:216-217`); only the first font family reaches cosmic-text and
  registered family/weight/style metadata is dropped (`lib.rs:105-121`,
  `cosmic_text_engine.nim:121-129`) — fallback chains (`Noto Sans CJK JP`)
  are dead letters.
- LOW: `render_bitmap` span compositing is last-writer-wins (overlapping
  glyphs punch alpha holes, `lib.rs:693-706` — use alpha max); bridge is not
  thread-safe and nothing documents single-thread ownership; rounded-rect
  fill issues ~1 renderFillRect per scanline (cache as texture);
  `PaintCommand` embeds a full 1,480 B `ComputedTextStyle` per text command
  (store an index instead); `cosmicTextBridgeLib` path hardcoded outside
  `config.nim` (`cosmic_text_engine.nim:5`) and config constants aren't
  `{.strdefine.}`-overridable.
- **Boundary check: PASS** — zero SDL/cosmic imports in core/layout/paint/
  runtime/input/hit; paint commands are renderer-neutral; resource lifetimes
  and cache eviction verified sound (LRU-capped, freed on close).

## 7. Build, tests, repo, docs

> **Remediation update (2026-07-28):** The findings below describe the
> 2026-07-16 audit baseline. D12 has since landed: the repository now has an
> MIT `LICENSE`, third-party notices, a discovery-based ARC test runner, CI,
> example checks, release hygiene checks, setup-time bundled/system/custom
> linking, documented reference controls, and contributor instructions.
> Portable discovery currently runs 47 test files. The duplicate SDL3 files
> are now symlinks to one versioned binary, and the unused font bridge binary
> was removed. The image bridge now has CBSS-owned Rust source and a locked
> dependency graph. Native-display, performance, and native-bridge tests remain
> explicit tasks rather than being silently omitted. D13 now records the
> deliberate product/package naming split.

- **HIGH — no LICENSE file** despite `license = "MIT"` in the nimble file
  (`licenses/` holds only a third-party notice). Add MIT text + SDL3/
  cosmic-text notices (binaries are redistributed).
- **HIGH — no CI configuration** — the contribution-optimized project has no
  automated check that `nimble test` passes.
- **HIGH — two passing test files are silently never run**:
  `tests/properties/test_style_resolver.nim` and
  `tests/backends/test_sdl3_text_event_guard.nim` are missing from the
  hand-maintained 38-line `test` task (both verified passing when run
  manually). The hand-edited exec list is the exact monolith the architecture
  doc forbids, plus `/tmp` hardcoding (multi-user collision) and serial
  execution (~1.5–2 min warm). **Fix**: glob-based runner or testament;
  repo-local `build/` outputs; parallel execution.
- **HIGH — ~28 MB of binaries/duplicates tracked**: three full copies of
  `libSDL3.so*` (regular files, not symlinks), unexplained native bridge
  binaries, a 2.4 MB TypeScript declaration file, and the
  duplicated 1.27 MB binding. Document or remove; consider a fetch script.
- **MEDIUM — README scope contradicts shipped code**: "does not try to provide
  Button …" / "not a component library" while the public umbrella exports 15
  controls + 3 widgets. Position them explicitly as replaceable reference
  implementations (architecture.md already does) or split the package.
- **MEDIUM — architecture.md (2,239 lines) has accreted**: the `### Selectors`
  section spans 433 lines of which ~230 are per-component runtime
  implementation notes (text_input, textarea, label, fieldset, button, …).
  The suggested directory structure section describes `elements/`,
  `selectors/`, per-property files, `cbss.nim` — none of which exist in that
  form. **Fix**: extract component notes to `docs/runtime-components.md`;
  correct the directory map to the real tree.
- **MEDIUM — "Board" vs "Box" naming split**: repo/README say Clay **Board**
  Style System; package, imports, and all code say `clay_box_style_system`.
  Pick one; state the other as historical alias. (Owner decision — see
  design-decisions doc.)
- LOW: no CONTRIBUTING.md (the "files to touch" map architecture.md promises
  doesn't exist); README lacks any build/test instructions ("nimble" appears
  nowhere in it); no `nim.cfg`/`config.nims` (flags duplicated into every
  nimble exec line); `build/` only ignored accidentally; boundary test guards
  only two symbols.

## 8. What is notably good (calibration)

- **The renderer/core boundary genuinely holds** — no SDL/cosmic types outside
  backends; opaque-pointer text ABI with paired free functions; a compile-time
  public-import-boundary test.
- **Event-handler policy implemented exactly as documented** — no closures in
  the core tree; NodeId-keyed registry; replacement assignment preserving
  internal guards; focus-serial staleness guard is well designed (just not
  wired into the shipped path).
- **Paint clip discipline is correct and well tested**; scaled flex-shrink
  weighting is correct (most homegrown flex clones get it wrong); absolute
  children properly excluded from flow sizing; `relayoutSubtree` is a genuinely
  useful editor optimization.
- **Honest status documentation** — the property-support matrix explicitly
  refuses to oversell, and its counts reconcile exactly with the
  implementation-order doc.
- **Text controls take hard problems seriously** — rune-safe editing
  everywhere, bounded undo, visible-window clamping, IME composition modeled
  explicitly, clipboard write coalescing.
- **Test hygiene** — tests mirror src directory-for-directory; examples
  `nim check` cleanly; input-layer behavioral coverage is unusually broad.

## 9. Recommended fix order

**Phase 0 — stop the bleeding (small diffs, huge wins)**
1. P1 sort-closure fix (layout + paint) — ~1000× on layout/paint.
2. P4 `applyStyle` replace-not-append + P3 rule bucketing.
3. P8 drag threshold + pointer-cancel reset + double-click timestamps.
4. P9 `catch_unwind` in the bridge; delete the stale `bindings/` copy (P-F2).
5. Add LICENSE, CI (test + example check + bridge build), glob test runner
   (recovers the two skipped tests).

**Phase 1 — structural correctness**
6. P6 two-pass layout (measure/arrange) + freeze/redistribute + text
   measurement against resolved width; axis abstraction while in there.
7. P7 hit-testing rewrite on paint order + clip awareness.
8. P2 font context two-phase resolve; inheritance made property-owned;
   cascade tiebreaker fix.
9. P5 break UiRoot cycles.

**Phase 2 — architecture consolidation**
10. P10 frame scheduler into the library; event-loop wait; demo slimmed to a
    consumer of it.
11. P11 text_edit_core extraction; one change-event contract; single focus
    staleness mechanism in `runtime/interaction.nim`.
12. P12 ComputedStyle hot/cold split; property surface trim; PaintCommand
    de-fattening; hash-keyed render caches.
13. Property-module macro/codegen; real generated registry; event table
    codegen; dead event slots removed.
14. Docs restructure + naming decision + CONTRIBUTING (see
    `docs/design-decisions.md`).
