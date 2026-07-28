# Platform Support

CBSS is Linux-first during the initial development phase.

## Support Tiers

| Tier | Platform | Status | Release Blocking | Validation Owner |
| --- | --- | --- | --- | --- |
| Tier 1 | Linux x86_64 | Active | Yes | Maintainer |
| Tier 2 | Windows x86_64 | Planned | No | Contributors |
| Tier 2 | macOS Apple Silicon | Planned | No | Contributors |
| Tier 2 | macOS x86_64 | Planned | No | Contributors |

The primary runtime target is Linux x86_64 with SDL3. Windows and macOS support
are welcome, but they require contributor validation before they can be treated
as supported release targets.

## SDL3 Policy

SDL3 is the primary runtime backend. The core style, layout, paint command, hit
test, and input-state code should remain independent from SDL3 types. SDL3
integration belongs under `src/clay_board_style_system/backends/sdl3/`.

The development checkout keeps Linux x86_64 SDL3 binaries and headers under:

```text
vendor/sdl3/
  include/SDL3/
  linux-x86_64/
```

These files support CBSS development and validation. They are not installed
with the published Nimble package; applications provide a runtime directory or
use system libraries.

The SDL3 backend reads its paths from:

```text
src/clay_board_style_system/backends/sdl3/config.nim
```

When embedding CBSS into another project that already vendors SDL3, adjust that
project's link setup instead of editing renderer logic. Bundled, system, and
custom-prefix configurations are documented in
[runtime-linking.md](runtime-linking.md). They keep user imports identical and
store the selection under the application's `.cbss/` directory.

## Contributor Validation

Windows and macOS support should be added by contributors who can run real
machine validation. A useful validation report should include:

- OS version
- CPU architecture
- SDL3 version or source
- Dynamic or static linking choice
- Window creation
- Resize behavior
- Pointer movement and hover
- Basic text rendering
- DPI or display scale
- IME status if text input is involved

Platform PRs should keep OS-specific path, link, and packaging changes isolated
from the renderer implementation whenever possible.

Accessibility platform support follows the same boundary. CBSS currently has a
platform-neutral semantic tree and an AT-SPI model adapter, but the Linux
accessibility D-Bus transport is not yet implemented. UIA and NSAccessibility
must be added as independent adapters rather than conditionals inside controls.
No platform may be marked accessibility-supported from compilation alone; it
requires real assistive-technology validation.

Use [platform-validation-checklist.md](platform-validation-checklist.md) when
reporting a new platform validation result.
