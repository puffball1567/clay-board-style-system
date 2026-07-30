# Changelog

All notable user-facing changes will be documented in this file.

The project follows Semantic Versioning after the initial developer-preview
release. Before 1.0, minor releases may contain public API changes.

## [Unreleased]

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
