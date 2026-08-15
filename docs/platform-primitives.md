# Official Platform Primitive Candidates

Status: `Proposed after the Version 0.5 and 0.6 foundation work`

CBSS is not limited to layout and paint internals. A native UI foundation is
more useful when it also standardizes difficult, broadly reusable capabilities
that otherwise prevent applications and component libraries from being built.
Browsers demonstrate this value with forms, Canvas, media, clipboard, and
drag-and-drop facilities that sit above the smallest rendering primitives.

This document records candidates, not an unconditional promise to place every
feature in the default binary.

## Inclusion Test

A capability is a strong CBSS candidate when most of these statements are
true:

- it is reusable across unrelated applications and design systems;
- implementing it correctly requires coordination between layout, paint, hit
  testing, focus, events, accessibility, scheduling, or platform adapters;
- leaving it to every component author would create incompatible contracts or
  repeated correctness, performance, and accessibility failures;
- a shared typed API makes independently developed Nim packages more portable;
- the mechanism can remain independent of application business logic; and
- applications that do not use it can exclude its implementation, assets, and
  native dependencies from their build.

Features are rejected from CBSS when they encode one product's workflow,
content model, business policy, or visual identity rather than reusable UI
mechanics.

## Delivery Layers

Candidates are divided into three layers:

1. **Core mechanism:** the smallest retained contracts needed by layout,
   events, paint, accessibility, ownership, and invalidation.
2. **Official optional module:** a first-party implementation that is imported
   and linked only when used. Optional modules remain subject to CBSS API,
   performance, ownership, and cross-platform release gates.
3. **Reference control:** a usable style-neutral component built on the same
   mechanism. GUI libraries may replace its appearance or compose a different
   control without replacing the underlying contract.

An official feature therefore does not have to increase every CBSS binary.
Exact module names and package boundaries are finalized only when their public
contracts are implemented.

## Brush And Stroke Engine

Status: `Candidate for the Version 0.7 visual-expression scope`

The existing Canvas path and stroke foundation should grow into one reusable
Brush and Stroke Engine shared by Canvas drawing and Style painting. The shared
contract may include:

- retained paths, stroke samples, brush descriptors, pressure, tilt, rotation,
  variable width, deterministic seeds, texture stamps, spacing, joins, and
  bounded caches;
- CPU, optional Pixie, SDL GPU, and optional wgpu execution behind one authored
  brush model;
- Canvas use for illustration, diagrams, signatures, and drawing tools; and
- Style use for borders, outlines, masks, decorations, and authored visual
  effects.

Connected hand-drawn borders require more than painting each Box separately.
For adjacent zero-gap children, layout may produce a parent-owned `EdgeGraph`
that identifies shared edges and junctions. Paint then draws each shared edge
once with a deterministic brush, preventing gaps and doubled strokes. Separate
boxes and non-zero gaps retain independent borders.

CBSS owns path topology, brush evaluation, paint integration, caching, input
sample metadata, and backend contracts. It does not own an illustration
application, a branded brush library, layer-panel workflows, or content-
specific drawing automation. Those belong to optional packages and
applications built on the engine.

## Color Picker

Status: `Candidate after the authored color and accessibility contracts are stable`

CBSS already owns the authored color model and its resolution boundary. A
style-neutral Color Picker is a suitable reference control because correct
interaction spans color spaces, focus, keyboard input, pointer input,
accessibility, platform behavior, and visual state.

The reusable contract may provide:

- typed color value editing across supported CBSS color spaces;
- alpha and gamut-aware preview behavior;
- keyboard operation, focus, accessible value/state, and validation;
- a standard style-neutral picker that works without adopting a GUI library;
- Style injection and replaceable subcomponents for independent design
  systems; and
- an optional native-picker adapter where a platform provides one.

CBSS does not own brand palettes, cloud palette storage, automatic color-theme
generation, or an application's color-history policy. Those can compose the
same control and authored color values.

## Drag And Drop

Status: `Planned expansion of the existing pointer drag lifecycle`

CBSS already synthesizes the basic pointer-driven `onDragStart`, `onDrag`,
`onDragEnter`, `onDragOver`, `onDragLeave`, `onDrop`, and `onDragEnd` lifecycle.
The candidate is a complete platform primitive above those events, not a second
drag implementation.

The internal CBSS contract should cover:

- drag thresholds, long-press policy where applicable, pointer capture,
  cancellation, and deterministic cleanup;
- a typed payload whose ownership does not depend on public ids, classes, or
  string selectors;
- accepted payload kinds and `copy`, `move`, or `link` operation negotiation;
- paint-only drag previews, drop indicators, cursor feedback, and Style state;
- clipping, transforms, stacking, modal boundaries, and event blocking that
  agree with normal hit testing;
- edge-triggered automatic scrolling without full layout per pointer sample;
- keyboard-accessible drag/reorder operations and accessibility announcements;
  and
- bounded high-rate pointer coalescing and deterministic injected-event tests.

Native file, text, and cross-window drops belong behind platform adapters. The
adapter converts host-authorized data into immutable CBSS Blob or typed payload
values; an untrusted path is never opened merely because it was dropped. Exact
browser `DataTransfer` compatibility and a browser-origin security model are
not goals.

CBSS owns gesture and UI mechanics through `drop`. Applications own what the
drop means: mutating a document, moving a card, importing a file, persisting an
order, checking business permissions, or invoking backend work. A reference
sortable-list component may use this primitive, but sortable-list policy is not
the drag core.

## Candidate Gates

Before a candidate becomes a supported module or control, it needs:

- an ownership and disposal model under ARC and ORC;
- deterministic headless tests plus the applicable Wayland/platform fixtures;
- accessibility and complete keyboard behavior for reference controls;
- dirty-work and idle-frame performance budgets;
- C ABI exposure only after the Nim contract is stable;
- explicit native dependency and compile-time profile behavior; and
- documentation that separates CBSS mechanics from application policy.

These gates prevent a broad platform surface from becoming a monolithic binary
or an accumulation of partially connected demo features.
