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

Status: `Planned`

The primary Version 0.2 feature is a state-driven navigation layer for native
applications. CBSS already lets applications change state and render a
different component tree. Version 0.2 should turn that capability into a small,
consistent navigation surface without importing browser-only routing behavior.

Planned capabilities:

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

### Non-Goals

- SEO, server-side routing, or browser URL compatibility.
- A DOM, browser history clone, or dependency on a WebView.
- Application-specific authorization or data-fetching policy.
- Rebuilding the complete UI tree for every navigation action.
- Forcing one router convention on GUI libraries built above CBSS.

## Version 0.3 - Visual Foundation And Color

Status: `Planned`

Version 0.3 establishes the public visual-surface foundation that independent
libraries can build on. CBSS owns the host contract, placement, composition,
input routing, frame scheduling, and core color model. Charting and other
application-domain libraries remain separate OSS packages. SDL-native game
surfaces that must share CBSS texture, renderer, input, and frame lifecycles
are optional modules shipped within CBSS.

Planned capabilities:

- Complete the practical CSS Color authoring surface described below, including
  hexadecimal, named, RGB, HSL, HWB, Lab/LCH, Oklab/Oklch, alpha, interpolation,
  gamut handling, `currentColor`, and typed color-mix behavior where relevant.
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

Independent modules may use the resulting contract to provide capabilities
such as `cbss_charts`. CBSS itself may provide opt-in game modules for sprites,
tile maps, and Tiled integration because they share its SDL renderer, texture
cache, input routing, coordinate conversion, and frame scheduler. CBSS does
not bundle image assets or make a chart/widget catalogue part of its core
release.

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

The target is to support the complete practical authoring surface of CSS Color
expressions, while retaining a typed Nim API rather than requiring a CSS text
parser. A syntax is not considered supported merely because CBSS can store its
source text: it must have a specified conversion, interpolation, paint result,
and diagnostic behavior.

Planned work:

- Keep explicit `rgb(...)` and `rgba(...)` constructors for numeric color
  values and alpha.
- Add hexadecimal color constructors, including short, long, and alpha forms,
  with strict validation and clear diagnostics.
- Add named colors, `transparent`, and `currentColor` semantics where the
  consuming property has a foreground-color context.
- Add modern and legacy-compatible RGB forms, HSL/HSLA, HWB, Lab/LCH, and
  Oklab/Oklch constructors, with defined gamut mapping into the renderer's
  output space.
- Add CSS Color 4/5-style functional forms where meaningful in typed Nim,
  including `color(...)` spaces and `color-mix(...)`.
- Provide ergonomic declaration overloads where a plain `Color` unambiguously
  means a solid style color, so authors need not write `colorValue(...)` in
  ordinary declarations.
- Define interpolation-space behavior for gradients, transitions, and animated
  colors instead of relying on backend-specific blending.
- Treat device-dependent, wide-gamut, and system-color behavior as explicit
  capability work. Unsupported output profiles must diagnose or use a
  documented conversion; they must not silently render unpredictably.

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
