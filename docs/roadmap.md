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

## Later Milestones

Later milestones remain intentionally unversioned until Version 0.2 APIs and
runtime behavior are stable. Tooling plans for galleries, plugins, MCP
integration, and design-source adapters are tracked separately in
[tooling-roadmap.md](tooling-roadmap.md).
