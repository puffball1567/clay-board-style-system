# Changelog

All notable user-facing changes will be documented in this file.

The project follows Semantic Versioning after the initial developer-preview
release. Before 1.0, minor releases may contain public API changes.

## [Unreleased]

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
