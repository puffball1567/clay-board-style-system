# Contributing to CBSS

CBSS is structured for low-conflict contribution: many small modules, an
enforced public boundary, and tests that mirror the source tree. A change
should usually touch a small number of localized files — this document tells
you which ones.

Before writing code, skim:

- [README.md](README.md) — what CBSS is and is not.
- [docs/architecture.md](docs/architecture.md) — design intent and boundaries.
- [docs/performance-model.md](docs/performance-model.md) — hot-path rules and
  budgets. Performance is a product requirement; hot-path code is reviewed
  against these rules.
- [docs/design-decisions.md](docs/design-decisions.md) — settled decisions and
  component conventions.

## Branch and Release Workflow

- Create feature and fix branches from `devel`.
- Open pull requests against `devel`. Feature pull requests do not target
  `main`.
- Keep `devel` green with the required tests and compatibility checks.
- For a release, merge `devel` into `main` after the release checks pass.
- Create the version tag from `main` only after that merge. Direct development
  commits and feature merges do not land on `main`.

## Contribution License

Unless you explicitly state otherwise, a contribution intentionally submitted
for inclusion in CBSS is provided under the
[Apache License 2.0](LICENSE), including its contributor patent grant. Submit
only work that you have the right to license under those terms.

## Quickstart

```sh
nimble setupBundled       # select the vendored Linux runtime
nimble test              # unit/behavior test suite
nimble checkExamples     # examples plus bundled/system/custom link checks
nimble testCAbi          # shared/static C ABI build and C consumer
nimble demo              # paint-command demo (no window)
nimble renderDemo        # render demo to a PPM image
nimble sdl3Demo          # SDL3 demo (Linux; builds the Rust text bridge)
nimble testCosmicTextBridge   # text bridge integration test (needs cargo)
CBSS_RUN_WAYLAND_E2E=1 nimble testSdl3Wayland  # opt-in real-window smoke test
```

Requirements: Nim ≥ 2.2.0; for the SDL3 demo and text tests, a Rust toolchain
(cargo) and Linux x86_64. The checkout's SDL3 development runtime under
`vendor/sdl3/` is not installed as part of the published Nimble package.

C ABI changes touch `src/clay_box_style_system/c_api.nim`, `include/cbss.h`,
and `tests/c_api/c_consumer.c` together. Never expose a Nim-managed type or
change an existing C struct/function signature without an ABI-version decision.
Use `nimble setupSystem` when the application supplies SDL3, the image bridge,
and the cosmic-text bridge through its own dynamic-library installation.

## Files to touch, by contribution type

| Contribution | Implementation | Tests | Docs |
| --- | --- | --- | --- |
| Style property | `src/clay_box_style_system/properties/<group>.nim` (grouped modules — e.g. sizing, margin, padding, border, text, visual, transform); register in `src/clay_box_style_system/generated/default_properties.nim` | `tests/properties/` | update status in `docs/css-property-support.md` |
| Selector capability | `src/clay_box_style_system/core/selector.nim` | `tests/properties/test_style_resolver.nim` or new focused test | `docs/architecture.md` selector section if policy changes |
| Layout behavior | `src/clay_box_style_system/layout/layout.nim` | `tests/layout/` | support matrix row if a property's status changes |
| Paint behavior | `src/clay_box_style_system/paint/` | `tests/paint/` | — |
| Hit testing | `src/clay_box_style_system/hit/hit_test.nim` | `tests/hit/` | — |
| Input/events | `src/clay_box_style_system/input/events.nim` | `tests/input/` | event policy lives in `docs/architecture.md` |
| Runtime control / widget | `src/clay_box_style_system/runtime/<name>.nim` (widgets under `runtime/widgets/`) | `tests/runtime/test_<name>.nim` | behavior notes in `docs/runtime-components.md`; follow conventions in design-decisions D15 |
| SDL3 backend | `src/clay_box_style_system/backends/sdl3/` (paths/link flags only in `config.nim`) | `tests/backends/`, opt-in Wayland smoke test | `docs/platform-support.md` |
| Text engine / bridge | `src/clay_box_style_system/text/`, `native/cosmic_text_bridge/src/lib.rs` | `tests/text/` | `docs/architecture.md` text section |
| Design-source import | `src/clay_box_style_system/design_source/` | `tests/design_source/` | — |
| Public API surface | `src/clay_box_style_system.nim` (umbrella) | `tests/testing/test_public_import_boundary.nim` | — |

If your change needs to edit more than one registry/central file, that is a
signal to discuss first — the architecture prefers registration tables and
generated indexes over central switches.

## Ground rules

- **Boundaries**: no SDL3 or cosmic-text types outside `backends/` and
  `text/`; the core emits renderer-neutral data. The public umbrella must not
  export testing or backend internals (enforced by the boundary test).
- **Memory model**: ARC-friendly value objects, `NodeId` arenas, no `ref`
  cycles, no closures stored in the core tree. Foreign resources get explicit
  `close`/`destroy`.
- **Hot paths**: follow `docs/performance-model.md` — no large-value closure
  captures, no string identity per frame, index instead of scan, reuse
  scratch buffers.
- **Diagnostics over guessing**: invalid style input produces a named
  diagnostic, never a silent fallback.
- **Tests near features**: add the focused test next to the subsystem you
  changed. `nimble test` discovers new `tests/**/*.nim` files automatically,
  except explicit Wayland E2E, bridge, and benchmark targets. Keep every example
  compiling with `nimble checkExamples`.
- **Docs**: architecture.md records stable intent. Component behavior notes go
  to `docs/runtime-components.md`; audits under `docs/audits/`.
- **Native dependencies**: do not add an unexplained binary. Record its
  upstream, version, license, update process, and link mode in
  `THIRD_PARTY_NOTICES.md` and `docs/runtime-linking.md`.
