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
model and the reference-control implementation. ARC remains CBSS's release
memory model. ORC compatibility may be tested as a safety net, but cycle
collection must not be used to hide an ownership cycle in the runtime.

This work is a Version 0.2 release gate:

- Remove owning `UiRoot` back-references from public and internal component
  handles. Handles use `NodeId`, component state, or explicitly non-owning
  `{.cursor.}` access whose lifetime is bounded by the owning `UiRoot`.
- Ensure event-registry closures cannot form
  `UiRoot -> EventRegistry -> closure -> component handle -> UiRoot` cycles.
  Internal handlers capture only the state and stable identifiers they need,
  and receive root-scoped services from dispatch-time context.
- Audit every reference control and widget, including buttons, checkboxes,
  dialogs, details, forms, labels, list boxes, command menus, radio sets,
  select boxes, sliders, tabs, text inputs, and textareas.
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

Status: `In progress`

Version 0.3 establishes the public visual-surface foundation that independent
libraries can build on. CBSS owns the host contract, placement, composition,
input routing, frame scheduling, and core color model. Charting and other
application-domain libraries remain separate OSS packages. SDL-native game
surfaces that must share CBSS texture, renderer, input, and frame lifecycles
are optional modules shipped within CBSS.

Planned capabilities:

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
  independent Nim modules and C ABI adapters: mount, update, resize, input,
  frame request, visibility, device-loss, unmount, and deterministic cleanup.
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
- Pixie evaluation result: do not make Pixie a core dependency or expose its
  types. A future optional adapter remains appropriate for cached paths,
  masks, SVG, blur, and image effects after the canonical path/mask paint
  vocabulary and cache ownership are stable. SDL3 remains sufficient for the
  mandatory Version 0.3 Canvas path.
- Remaining Version 0.3 visual work: add Canvas-authored transform
  save/restore, blend state, and explicit offscreen surfaces; expose drawing
  adapters beyond the existing C ABI lifecycle; and complete the final SDL3,
  headless, performance, memory, and platform release gates. Three-dimensional
  transforms, filters, and blend/isolation semantics remain later work.

## Version 0.4 - Complete Unit Resolution

Status: `Planned`

Version 0.4 completes the typed unit model across supported properties. The
goal is not merely to parse more values: every supported unit/property pair
must have a defined resolution context, a computed-value result, diagnostics,
and tests.

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

## Authoring Value Model And Ergonomics

Status: `Planned`

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

## GPU Canvas Capability

Status: `Planned`

CBSS will support optional GPU-backed drawing inside the standard Canvas
element. This is a capability for game scenes, charts, visualizations, image
processing, and other custom drawing workloads; it is not a second renderer
for normal CBSS buttons, text, or style properties. Normal UI retains one
canonical visual contract.

The initial implementation target is the SDL3 GPU API, with explicit resource,
swapchain, shader, synchronization, resize, and device-loss ownership rules.
`wgpu-native` is also a planned optional CBSS GPU Canvas backend for workloads
that benefit from a WebGPU/WGSL contract, such as custom visualizations,
camera-frame effects, tile maps, and game scenes. It remains behind the same
Canvas contract and must not create a second renderer-specific interpretation
of ordinary CBSS UI properties.

The complete staged plan, including GPU Canvas composition, visualization APIs,
game UI, and external engine integration, is maintained in
[render-surface-roadmap.md](render-surface-roadmap.md).

## Motion, Transform, And Native Visual Surfaces

Status: `Planned`

CBSS should support the CSS-inspired motion and geometric vocabulary needed by
modern application UI without adopting a browser or a virtual-DOM redraw
model. A change that animates paint-only state must not force unrelated nodes
to resolve style or relayout on every frame.

### Transforms And Transitions

Planned work:

- Complete `translate`, `scale`, `rotate`, transform origin, and composition
  order with a single layout, paint, and hit-test coordinate contract.
- Add declarative transition property, duration, delay, timing-function, and
  interpolation behavior for supported style values.
- Add keyframe-style animation definitions for values that CBSS can resolve,
  interpolate, and paint deterministically.
- Schedule frames only while an animation, transition, caret blink, scrolling
  motion, or Canvas explicitly needs one; idle UI remains event-driven.
- Respect reduced-motion preferences through an application or platform
  capability interface.

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

Status: `Planned`

CBSS should support pen input as more than mouse emulation. A stylus can still
participate in ordinary pointer interaction, while Canvas, drawing controls,
and applications that need it can receive the richer pen data without losing
the common event model.

Planned work:

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

## Later Milestones

Later milestones remain intentionally unversioned until Version 0.2 APIs and
runtime behavior are stable. Tooling plans for galleries, plugins, MCP
integration, and design-source adapters are tracked separately in
[tooling-roadmap.md](tooling-roadmap.md). Native Canvas, visualization, game
UI, and external-renderer integration are tracked in
[render-surface-roadmap.md](render-surface-roadmap.md). The broader capability
mapping against the roles commonly supplied by HTML, CSS, and JavaScript is in
[web-platform-capability-roadmap.md](web-platform-capability-roadmap.md).
