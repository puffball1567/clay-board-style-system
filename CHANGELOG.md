# Changelog

All notable user-facing changes will be documented in this file.

The project follows Semantic Versioning after the initial developer-preview
release. Before 1.0, minor releases may contain public API changes.

## [Unreleased]

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
