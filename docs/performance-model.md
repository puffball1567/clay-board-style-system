# CBSS Performance Model

CBSS must be lightweight and fast. A clean but sluggish UI engine will not be
adopted, no matter how pleasant its API is. This document makes that
requirement a design constraint with budgets, rules, and verification — not an
aspiration.

This document has the same authority as `architecture.md`: a change that
violates a rule here needs an explicit justification in review, exactly like a
change that violates an architecture boundary.

## Performance targets

Reference workload: an application UI of **1,000–10,000 nodes**, pointer
movement every frame, at **60–120 fps** on an ordinary desktop.

Per-frame budgets on the reference workload (10k nodes, release build,
x86_64):

| Stage | Budget | Notes |
| --- | --- | --- |
| Input dispatch (per pointer move) | ≤ 0.2 ms | including hover synthesis |
| Style resolution (dirty subtree) | ≤ 1 ms | full-tree resolve is not a per-frame operation |
| Layout (dirty subtree) | ≤ 2 ms | full-tree layout only on resize |
| Paint command build (dirty subtree) | ≤ 1 ms | |
| Hit region refresh | ≤ 0.5 ms | |
| Render submit (SDL3 backend) | ≤ 4 ms | excluding vsync wait |
| Idle CPU (no dirty domain, no animation) | ~0 | the loop must block on events |

Full-tree cold passes (first frame, window resize) should stay under one
frame at 10k nodes: style ≤ 20 ms, layout ≤ 10 ms, paint ≤ 5 ms.

Memory: retained per-node cost (node + computed style + layout box + hit
region share) should stay under ~1 KB on average. 10k nodes ≈ ≤ 10 MB of
engine-owned state, excluding renderer texture caches, which are bounded by
their own budgets.

## Measured baseline (2026-07-16)

Recorded so regressions and progress are visible. See
`docs/audits/2026-07-16-implementation-audit.md` for root causes.

| nodes | style | layout | paint build | hit build |
|------:|------:|-------:|------------:|----------:|
| 1000 | 19.6 ms | 1,205 ms | 974 ms | 0.23 ms |
| 4000 | 289 ms | 23,801 ms | 23,755 ms | 3.4 ms |

Layout/paint are currently O(n²) (sort-comparator closures deep-copying
`ResolvedTree` per node); style resolution is O(nodes × rules) with per-node
sheets. These are implementation bugs, not design limits; the budgets above
assume the Phase 0/1 fixes from the audit.

### P1 verification (2026-07-16)

The P1 comparator-capture fix is measured by `nimble bench` using a compiled
ARC release build and a nested-row tree with visible paint output:

| nodes | style | layout | paint build | commands |
|------:|------:|-------:|------------:|---------:|
| 500 | 3.61 ms | 0.91 ms | 1.30 ms | 500 |
| 1,000 | 6.99 ms | 2.09 ms | 1.73 ms | 1,000 |
| 4,000 | 28.21 ms | 7.70 ms | 22.58 ms | 4,000 |

These figures replace neither the original baseline nor the target budgets:
they isolate the P1 fix. P3/P4 and paint caching remain required before the
full-tree targets are met.

### Layout length verification (2026-07-17)

The `%`/`auto`/intrinsic sizing change conditionally adds a bottom-up measure
pass. A tree without intrinsic sizing skips that pass. Percentage gap,
flex-basis, and inset resolution stays in the existing arrangement pass. The
release ARC probe warms each workload once and reports the median of five
measured runs. After these changes it measured:

| nodes | style | layout | paint build | commands |
|------:|------:|-------:|------------:|---------:|
| 500 | 3.10 ms | 1.09 ms | 0.68 ms | 500 |
| 1,000 | 6.30 ms | 2.30 ms | 1.81 ms | 1,000 |
| 4,000 | 26.32 ms | 9.48 ms | 17.47 ms | 4,000 |

The 4,000-node layout result remains linear and is about 7% above the preceding
8.86 ms measurement, below the 20% regression gate. The sizing unit test also
counts text-engine measurement calls and bounds them linearly by text-node
count. Intrinsic-heavy wall-clock workloads still need a dedicated benchmark
before intrinsic sizing is considered optimized.

### Borrowed-style hot path verification (2026-07-23)

Parent styles are now borrowed during resolution, and layout, paint, and hit
passes borrow `ComputedStyle` entries with ARC cursors instead of copying the
5.7 KB value into loop locals. On the same release ARC pipeline probe, the
4,000-node result changed as follows:

| state | style | layout | paint build | hit build |
| --- | ---: | ---: | ---: | ---: |
| before borrowed hot paths | 35.170 ms | 24.787 ms | 5.849 ms | 4.148 ms |
| after borrowing and first cold-field split | 13.014 ms | 6.883 ms | 2.728 ms | 1.581 ms |
| after retained layout index and animation/transform split | 9.993 ms | 5.317 ms | 2.457 ms | 1.247 ms |

This removes avoidable transport cost. The first physical cold-field split
moves columns, mask, and vector metadata behind lazy refs, reducing
`sizeof(ComputedStyle)` from 5,672 to 3,448 bytes for ordinary nodes.
Animation and transform metadata now use value-preserving lazy accessors, so
nodes that do not declare either group retain only two references; this lowers
the inline size again to 2,944 bytes. The remaining text, box, and visual split
is still required to reach the retained-memory budget.

### Version 0.2 release baseline (2026-08-01)

The release ARC pipeline probe passed with the following median results after
one warmup:

| nodes | style | layout | scroll | paint | hit | commands |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 500 | 1.197 ms | 0.642 ms | 0.003 ms | 0.198 ms | 0.128 ms | 502 |
| 1,000 | 2.403 ms | 1.297 ms | 0.007 ms | 0.393 ms | 0.239 ms | 1,004 |
| 4,000 | 10.648 ms | 6.616 ms | 0.021 ms | 2.585 ms | 1.358 ms | 4,004 |

These are full-tree cold-pass measurements, not dirty-subtree frame costs.
The fixed seven-node dirty benchmark and retained navigation benchmark below
verify that interactive updates remain independent of unrelated tree size.

### Version 0.3 RenderSurface baseline (2026-08-02)

`RenderSurfaceRegistry` retains an explicit set of requested, visible, mounted
surfaces. The idle event-loop predicate is therefore `O(1)` and frame delivery
is `O(requested)` rather than scanning every registered surface. Hidden and
device-lost surfaces retain their request without entering the runnable set.

The release ARC benchmark on the development machine measured:

| workload | result | gate |
| --- | ---: | ---: |
| 1,000,000 idle predicates with 10,000 registered surfaces | 5.690 ms total | <= 50 ms |
| flatten 10,000 retained Canvas commands | 2.198 ms average | <= 4 ms |
| flatten 1,000 transformed Canvas scopes | 0.566 ms average | <= 4 ms |
| flatten 1,000 bounded Canvas layers | 0.382 ms average | <= 4 ms |
| flatten a retained path with 1,000 cubic curves | 0.436 ms average | <= 12 ms |

`tests/perf/render_surface_benchmark.nim` enforces all five gates. The Canvas
measurements cover display-list translation, transform-scope balancing, and
transform visual-bounds resolution into canonical paint commands. The layer
measurement covers bounded scope conversion and balancing; it does not include
backend texture allocation or composition. The path
measurement covers adaptive curve subdivision into backend-ready contours.
None of these measurements includes backend rasterization or text shaping.
Memory instrumentation may compile the same workload with
`-d:cbssMemoryCheck`; this keeps structural assertions and workload sizes but
disables wall-clock gates that are not meaningful under Valgrind.
The release ARC memory-check build completed this workload under Valgrind with
zero bytes retained at exit and zero reported memory errors.

### Version 0.5 validation gate

`tests/perf/validation_benchmark.nim` measures prepared typed rule descriptors
and a precompiled regular expression independently. It compares 10,000 and
100,000 successful evaluations per operation and fails if mean cost scales
superlinearly. It also compares one-dependant dispatch in trees with 100 and
10,000 unrelated nodes, enforcing that notification remains indexed by source
rather than scanning the tree. Rule construction and regular-expression
compilation stay outside the input path. A control value change evaluates that
control and its explicit cross-field dependants only; unrelated form controls
are not scanned.
Full registered-field traversal is reserved for `checkValidity`,
`reportValidity`, and `submit`.

## Hot-path data rules

The hot path is: input event → dispatch → dirty marking → subtree style →
subtree layout → paint command patch → hit refresh → render. Code on this
path follows these rules.

1. **No closure captures of large values.** A comparator or callback used in a
   per-node loop must be `{.nimcall.}` or capture only pointers/indices.
   Capturing a `seq` or large object into a closure copies it under ARC.
   (This single pattern cost ~99% of frame time in the 2026-07 baseline.)
2. **Large structs travel by `lent`/`ptr`/index, never by value, in loops.**
   `ComputedStyle`-sized objects are stored once in an arena and referenced by
   `NodeId`/index. `Option[BigStruct]` parameters are forbidden on hot paths.
3. **Hot/cold split for wide structs.** `ComputedStyle` keeps frequently-read
   numeric fields (layout, box, visual) in a compact struct; rarely-used
   long-tail properties live behind a lazily-allocated `ref` extension that is
   nil for the vast majority of nodes. Adding a property to the cold extension
   is cheap; adding one to the hot struct requires justification.
4. **No string identity in per-frame code.** Property names, event keys, group
   names, and cache keys are matched via enums, interned ids, bitsets, or
   64-bit content hashes — not string comparison or string building. Strings
   are for authoring-time and boundary APIs; they get interned once when the
   tree/styles are built.
5. **Index, don't scan.** Required lookup structures:
   - `nodeIndex → boxIndex` in `LayoutResult` (paint, relayout, caret
     placement must not scan boxes),
   - rules bucketed by target (`nodeIndex`, group, element kind) at sheet
     registration,
   - event bindings keyed by (node, kind), not a linear `seq` scan,
   - caches keyed by hash in a `Table` with LRU, not linear scans of string
     keys.
6. **Reuse scratch buffers.** Per-node/per-frame `seq` allocations in resolver,
   layout, paint, and dispatch loops are hoisted into reusable scratch storage
   passed as `var` parameters or kept on the engine object.
7. **Amortize, don't recompute.** Anything derived from unchanged inputs is
   cached and keyed by those inputs: text measurement (per node + revision),
   text rasterization (content hash — no length cutoff), rounded/gradient/
   shadow rasters. Crossing the FFI to re-shape unchanged text is a defect.
   The cosmic-text bridge enforces this on its side of the FFI with a small
   LRU of shaped buffers keyed by the full shaping input (text, families,
   features, size, wrap width, …), so the measure/caret/caret-layout/hit/
   raster queries that follow one edit shape the text once. The bridge must
   be built with `cargo build --release` (the nimble tasks do); debug-build
   shaping is ~25x slower and alone turns large-paste editing into
   multi-second stalls.
8. **Parse once.** Style values are parsed at declaration/apply time into
   typed fields. `parseInt`/`parseFloat`/`split` in layout or paint passes is
   a defect (specified value → computed value → used value, never
   string → value per frame).

## Update model (dirty-driven, library-owned)

The dirty-domain model in `architecture.md` (styleDirty, layoutDirty,
paintDirty, hitDirty, textDirty, resourceDirty, animationDirty) is the
production update path. The consequences:

- **The frame scheduler is a library component** (`runtime/frame_scheduler`,
  planned), not example code. It consumes `InvalidationState`, decides which
  passes run, and exposes the loop skeleton apps and the demo use. Examples
  must not contain scheduling machinery that applications would need to copy.
- **Runtime components mark dirty domains** when they mutate state; they never
  trigger full-tree rebuilds. Style updates from components use keyed
  replacement (`setNodeStyle`-style APIs), never sheet appends — a component
  interaction must not change the size of the stylesheet set.
- **State changes patch the retained tree.** Rebuilding the whole `UiRoot` per
  action is acceptable only in throwaway examples and must be labeled as such.
- **The event loop blocks when idle.** No dirty domain + no animation deadline
  ⇒ wait on backend events (with a timeout equal to the next animation/caret
  deadline). Idle polling at N Hz is a defect.
- **Pointer movement that only changes hover** re-resolves style only for
  nodes whose rules actually depend on hover state, repaints only their
  command spans, and never invalidates the static layer for the whole scene.

### Scheduling implementation status (2026-07-17)

`runtime/frame_scheduler.nim` now consumes `InvalidationState`, combines
multiple deadlines, and computes an indefinite, immediate, or bounded backend
wait. The SDL3 renderer exposes `waitEvent` and `waitEventTimeout` without
reordering the SDL event queue. The SDL3 demo has removed its fixed
`delay(16)` idle poll: it blocks indefinitely when idle and uses deadlines for
caret blink, scroll-end dispatch, and the short focus-transition input drain.

This is the first production connection of the dirty-domain model, not the end
of D2. Several components still report changes through demo-local booleans
before those changes are classified into domains. Moving frame construction,
component-level dirty production, and the animation clock out of the demo
remains required.

Wayland verification on 2026-07-17 used a release SDL3 demo, ignored the first
three seconds of startup, and sampled the process once per second for five
seconds with `pidstat`. All five idle samples reported `0.00%` user and system
CPU. This measurement verifies the blocking path, but it is not a substitute
for an automated wakeup/render-count regression test.

Event-driven frame scheduling is not viewport virtualization. The scheduler
eliminates idle frames and preserves baked renderer layers; a large list or data
grid still needs a separate visible-range/materialization contract so offscreen
rows do not become retained nodes or intrinsic-measurement work.

### Scroll pipeline status (2026-07-17)

Generic scroll offsets are retained outside style and layout. A wheel update
changes `ScrollState` and regenerates paint/hit data without recomputing layout.
Paint and hit testing each build one compact `NodeId -> LayoutBox` index and
then traverse linearly. Scroll-state synchronization walks only the sparse
overflow metrics. Per-node linear scans of the full layout result are
prohibited. Regression tests also assert that the `LayoutResult` remains
byte-for-byte equal across an offset update.

The release ARC probe now includes one `overflow-y: auto` root and reports the
scroll and hit stages independently (median of five runs after warmup):

| nodes | scroll sync | paint build | hit build |
|------:|------------:|------------:|----------:|
| 500 | 0.005 ms | 0.805 ms | 0.503 ms |
| 1,000 | 0.009 ms | 1.533 ms | 1.219 ms |
| 4,000 | 0.020 ms | 5.996 ms | 4.797 ms |

Scroll synchronization is comfortably linear and negligible. Full-tree paint
and hit construction still exceed dirty-subtree frame budgets at larger node
counts, so command-span patching and hit-region patching remain required; the
numbers above must not be represented as completion of those later stages.

The SDL3 demo now moves the active scroll subtree to the dynamic layer. Wheel
frames rebuild that subtree's paint commands without rebaking the static
texture. Hit presentation uses the same dirty subtree and replaces its
contiguous retained span instead of recomputing geometry for the full tree.
Scroll end builds the full final presentation once and returns the subtree to
the static layer. `LayoutResult` retains its `NodeId -> LayoutBox` index, so
paint and hit updates do not recreate an O(tree) lookup table.

`tests/perf/dirty_subtree_benchmark.nim` holds the dirty subtree at seven nodes
while growing unrelated retained content. The 2026-08-01 Version 0.2 release
ARC run measured:

| total nodes | subtree paint | subtree hit | paint commands | hit regions |
| ---: | ---: | ---: | ---: | ---: |
| 500 | 4.964 us | 3.482 us | 10 | 5 |
| 4,000 | 6.817 us | 5.502 us | 10 | 5 |
| 10,000 | 10.331 us | 8.883 us | 10 | 5 |

The benchmark fails if the 10k fixed-dirty cost exceeds four times the
500-node cost. The remaining region-span move is proportional to the retained
suffix when a replacement changes command count; a segmented arena or stable
per-node spans is still required for a strict zero-copy `O(dirty)` guarantee.

This is independent from viewport virtualization. Retaining 100,000 row nodes
still incurs retained-tree and intrinsic-measurement cost even though scrolling
those already-laid-out nodes no longer invokes layout.

### Virtual range planning status (2026-08-24)

`planVirtualRange` does not retain one geometry or measurement record per
logical item. `VirtualExtentIndex` prepares `m` sparse measurements in
`O(m log m)` time and `O(m)` storage when measurements change. Scroll-time
planning for `n` logical items and `k` materialized items is
`O((log n + k) log m)` with `O(k)` result storage. The configured hard cap
bounds `k`; a visible range larger than that cap fails explicitly instead of
silently omitting visible UI.

`tests/perf/virtualization_benchmark.nim` plans the same viewport shape over
100,000 and 10,000,000 logical items with three sparse measurements. The
2026-08-24 release ARC run measured:

| logical items | mean planning time | materialized items |
| ---: | ---: | ---: |
| 100,000 | 2.428 us | 31 |
| 10,000,000 | 2.599 us | 31 |

The gate rejects logical-count scaling beyond a deliberately broad noise
margin and asserts the same bounded materialized count. This covers range
planning itself.

`VirtualNodePool` now performs stable-key node/component reconciliation over
that bounded result. Lookup, validation, ordering, mount/disposal, and retained
refresh work are proportional to materialized entries, not logical item count.
The pool never stores one entry per logical row. A fully disjoint range may
transiently hold the old and new bounded ranges so factory failure can roll back
without losing the previous pool; stale roots are then retired through the
normal `UiRoot.disposeSubtree` lifecycle.

`tests/perf/virtual_node_pool_benchmark.nim` alternates adjacent ranges for
20,000 reconciliations. The 2026-08-24 release ARC run measured:

| logical items | mean reconcile time | materialized items | node arena slots |
| ---: | ---: | ---: | ---: |
| 100,000 | 8.513 us | 30 | 36 |
| 10,000,000 | 8.057 us | 30 | 36 |

The gate rejects logical-count scaling and requires identical bounded node
capacity. Focus retention and accessibility range integration still need
separate behavior and performance gates before viewport virtualization is
production-complete.

### Retained navigation status (2026-08-01)

`NavigationScreenHost` registers prebuilt, disjoint screen roots. A navigation
listener only queues the latest history entry; one `sync` after the event batch
changes the previous and next roots. Repeated back/forward operations reuse the
same keyed display declarations and never append nodes or style sheets.

Inactive screens combine `display: none` with inherited runtime inertness, so
they do not enter layout, paint, hit testing, direct tree-aware dispatch, focus
traversal, or visible accessibility output. Focus fallback discovery traverses
only the activated screen subtree. Common focus transfer updates the previous
and next focus nodes directly instead of clearing focus flags across the full
tree. Focus records for history entries removed by replace or forward-branch
truncation are pruned from retained memory.

`tests/perf/navigation_screen_host_benchmark.nim` alternates two fixed screen
subtrees with `replace` while growing unrelated retained content. The Version
0.2 release ARC run measured:

| total nodes | replace + host sync |
| ---: | ---: |
| 500 | 2.377 us |
| 10,000 | 1.994 us |

The benchmark also asserts stable node/style counts and fails if the 10k result
exceeds twice the 500-node result plus a one-microsecond noise allowance.
Dynamic screen creation and physical subtree disposal remain separate work;
this benchmark covers switching among already registered screens.

### Frontend runtime Command and Cue gates (2026-08-13)

Command completion must depend on the number of results drained in the current
UI turn, not require a scan of the retained UI tree or a linear search through
all concurrent runs. Active runs use their typed ticket ID as a hash index, and
the ordered policy advances through an amortized O(1) queue head rather than
shifting every remaining input after each completion.

`tests/perf/frontend_runtime_benchmark.nim` creates concurrent Commands,
delivers every result in reverse run order, and measures release ARC UI-pump
cost. The initial same-machine baseline is:

| active runs | mean pump cost per completion |
| ---: | ---: |
| 1,000 | 0.151 us |
| 10,000 | 0.134 us |

The gate fails if the 10,000-run per-completion cost exceeds four times the
1,000-run cost plus a 0.5 microsecond noise allowance. Absolute time varies by
host; the enforced property is that completion lookup is not O(active runs).
The completion mailbox remains bounded, and `pump(maxCompletions)` leaves
excess results queued rather than dropping or processing them invisibly.

Parallel Cue completion likewise updates one indexed session branch and
constant-size stage counters. It does not rescan every sibling branch after
each completion. The same benchmark completes 1,000- and 10,000-branch `all`
stages and applies the same ratio gate. The initial same-machine ARC baseline
is:

| parallel branches | mean completion cost per branch |
| ---: | ---: |
| 1,000 | 0.040 us |
| 10,000 | 0.038 us |

Session finalization may visit the stage once to release unfinished branches;
the total completion path remains O(branches), not O(branches squared).

Canvas Cue fan-out uses an indexed additive frame-subscription table. A frame
may settle many parallel branches, marks each subscription inactive in O(1),
and compacts the observer storage once after dispatch. It must not linearly
search the observer sequence for every completed branch. The benchmark applies
the same ratio gate to one RenderSurface frame:

| parallel Canvas branches | mean dispatch + completion cost per branch |
| ---: | ---: |
| 1,000 | 0.086 us |
| 10,000 | 0.089 us |

The baseline is a release ARC run on the same development host. Canvas display
list construction and rasterization are deliberately excluded; this gate
isolates adapter dispatch, Cue settlement, observer removal, and compaction.

### Indexed event dispatch gate

Event lookup must depend on the original target's ancestor route and matching
listeners, not on the total number of unrelated listeners retained by the
application. Public handlers, additive observers, and intrinsic default actions
share the same `(NodeId, InputEventKind)` index; event aliases are iterated
without allocating a temporary sequence.

`tests/perf/event_dispatch_benchmark.nim` dispatches 100,000 target-local click
events with 500 and 50,000 unrelated listener bindings. The 50,000-listener
case must remain within four times the 500-listener cost plus a 250 ns noise
allowance. This is a structural scaling gate rather than a universal wall-clock
promise: ancestor depth and the number of listeners actually attached to the
route remain legitimate costs.

### Color conversion and parsing baseline (2026-08-02)

Version 0.3 color authoring keeps declared color spaces outside the compact
paint `Color`. Conversion is allocation-free and occurs when a computed color
or active color animation needs an output value; unchanged paint colors remain
resolved and cached with their computed style.

`tests/perf/color_conversion_benchmark.nim` performs 100,000 operations per
path in a release ARC build. The initial development baseline is:

| path | mean cost |
| --- | ---: |
| in-gamut sRGB resolution | 137.1 ns/color |
| out-of-gamut Display P3 resolution | 1,865.1 ns/color |
| premultiplied Oklab interpolation | 482.4 ns/color |
| serialized color parsing | 1,151.3 ns/color |

The wide-gamut path includes iterative Oklch chroma reduction. It must not run
for unchanged static colors on every frame. Future browser-parity and Pixie
work must keep backend conversion and raster caching outside ordinary layout
and hit-test passes. Serialized parsing is likewise an authoring and resource
ingestion operation: computed styles retain parsed values, so paint, layout,
and hit-test passes do not reparse unchanged strings.

Solid authored-color integration keeps `ColorValue` behind an ARC-managed cold
reference in declaration values and resolves it before compact computed styles
reach paint. A same-machine release ARC A/B run against development commit
`37d31b9` measured the 4,000-node ordinary pipeline at 11.610 ms for style
resolution before the integration and 11.552 ms after the cold-reference
change. Style-context construction places foreground declarations first while
preserving their cascade order, so runtime style resolution remains a single
pass for every context.

## Renderer budgets

- Texture/measure caches are bounded (entry count and total bytes) with LRU
  eviction; keys are content hashes computed once per style/text revision,
  not rebuilt per frame.
- Static/dynamic layer split: static content renders at output (pixel)
  resolution, not logical resolution; hover/caret/text-edit deltas belong on
  the dynamic layer.
- CPU rasterization of rounded rects, borders, gradients, and shadows happens
  once per (geometry, style) key into cached textures — never per frame.
- FFI round trips (cosmic-text) per frame should be zero when text content and
  style are unchanged.

## Verification

- `tests/perf/` holds compiled benchmark probes for the pipeline
  stages at 500/1k/4k/10k nodes, runnable via a `nimble bench` task. Numbers
  are recorded in this file's baseline table when they change materially.
- A benchmark that regresses a budget by >20% blocks merge, same as a failing
  test.
- New hot-path code is reviewed against the rules above; the audit doc's
  findings serve as the canonical examples of each anti-pattern.
