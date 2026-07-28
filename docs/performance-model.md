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
while growing unrelated retained content. A 2026-07-28 release ARC run measured:

| total nodes | subtree paint | subtree hit | paint commands | hit regions |
| ---: | ---: | ---: | ---: | ---: |
| 500 | 5.076 us | 3.410 us | 10 | 5 |
| 4,000 | 6.157 us | 4.795 us | 10 | 5 |
| 10,000 | 8.632 us | 7.135 us | 10 | 5 |

The benchmark fails if the 10k fixed-dirty cost exceeds four times the
500-node cost. The remaining region-span move is proportional to the retained
suffix when a replacement changes command count; a segmented arena or stable
per-node spans is still required for a strict zero-copy `O(dirty)` guarantee.

This is independent from viewport virtualization. Retaining 100,000 row nodes
still incurs retained-tree and intrinsic-measurement cost even though scrolling
those already-laid-out nodes no longer invokes layout.

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
