# Native Web-Platform Capability Roadmap

CBSS aims to provide a native application foundation that covers the useful
roles commonly split between HTML, CSS, and JavaScript on the web. It is not a
browser, a DOM implementation, or a CSS compatibility layer. The purpose of
this document is to make the intended boundary explicit: which capabilities
belong in CBSS, which remain normal Nim or independent libraries, and which
browser-specific behaviors are intentional non-goals.

The CSS-property-level inventory remains in
[css-property-support.md](css-property-support.md). This document tracks the
broader platform capabilities that make independently developed native GUI
libraries practical.

## Status Terms

- `Runtime`: available through the CBSS runtime today.
- `In progress`: represented in the runtime or design, but not yet reliable
  enough to present as complete.
- `Planned`: belongs to the CBSS implementation target.
- `External`: belongs to Nim, an application, or a focused independent package
  that integrates with CBSS rather than becoming core behavior.
- `No plan`: intentionally outside the native CBSS model.

## Platform Mapping

| Web role | Native CBSS equivalent | Status | Boundary |
| --- | --- | --- | --- |
| HTML element tree | `UiRoot`, Boxes, text, controls, and component constructors | Runtime | CBSS uses Nim construction syntax rather than parsing HTML. |
| Semantic document structure | roles, accessible names, state, labels, and relationships | In progress | The runtime model belongs in CBSS; operating-system accessibility export must be completed per platform. |
| HTML custom elements | Nim modules exporting components, styles, and behavior | Runtime | Packages define their own components without a global tag registry. |
| HTML forms | text input, textarea, select, checkbox, switch, radio, range, buttons, focus, and events | Runtime | Form behavior is native and typed, not HTML form submission. |
| Constraint validation | typed validation state, validity messages, and native form policy | Planned | Core provides reusable control semantics; applications own business validation rules. |
| Links and document navigation | native `Link` and navigation stack | Planned | In-process destinations replace browser document navigation. |
| Canvas | first-class CBSS Canvas and 2D drawing context | Planned | Must behave as a normal CBSS box with clipping, focus, and retained rendering. |
| SVG/vector drawing | paths, fills, strokes, images, and text through Canvas | Planned | SVG text parsing is not required; vector capabilities are exposed as typed APIs. |
| Image, video, and camera elements | native media/image surfaces | Planned | Decoding and device access use dedicated adapters or packages. |
| Drag and drop | pointer capture, drag lifecycle, data payloads, and native drop integration | Planned | Browser `DataTransfer` compatibility is not a goal. |
| Clipboard | typed clipboard actions and platform adapters | In progress | Clipboard policy remains explicit and local to the application. |
| Browser document parser | HTML parser and document mutation API | No plan | Nim source constructs the UI directly. |
| Browser tabs, SEO, page reload, browser history | browser navigation model | No plan | Native navigation has different requirements. |

## CSS-Like Presentation And Layout

| Capability | Status | Direction |
| --- | --- | --- |
| Typed style declarations and computed values | Runtime | CSS-inspired property names map to typed Nim values. |
| Flex layout, box model, min/max sizing, percentage and intrinsic sizing | Runtime / In progress | Preserve the executable behavior and tests; close remaining edge cases before adding new layout models. |
| Overflow, scrolling, scrollbars, clipping, and hit-test coordinate conversion | Runtime | Scroll offsets are paint/hit transforms, not style mutations or full relayouts. |
| Relative and absolute positioning | Runtime / In progress | Complete containing-block and positioned-ancestor edge cases. |
| Inline flow, baselines, mixed inline content, and rich text | Planned | Required for advanced labels, editors, tables, and design-system typography. |
| CSS Grid | No plan | Flex, Boxes, and future native layout primitives are the intended model; CBSS does not inherit every browser layout system. |
| Style merge, injection, and component-local overrides | Runtime | Nim values and Style DI replace browser stylesheet loading and class-driven global cascade. |
| Selector state such as hover, active, focus, disabled, checked, and open | Runtime / In progress | State is driven by native events and component semantics. |
| Descendant, structural, and document-tree selectors | No plan | Components, arrays, methods, and explicit style composition replace DOM traversal matching. |
| CSS custom properties | No plan | Typed Nim `let`, `var`, `const`, parameters, themes, and Style DI are the indirection model. |
| Complete color authoring surface | Planned | Hex, named colors, RGB/HSL/HWB, Lab/LCH, Oklab/Oklch, alpha, interpolation, and gamut behavior. |
| Complete unit resolution | Planned | Explicit units remain canonical; property-specific shorthand is allowed only where unambiguous. |
| Layering, transforms, clipping, opacity, filters, and blend behavior | In progress / Planned | One paint and hit-test coordinate contract must serve ordinary UI, overlays, Canvas, and animation. |
| Transitions, keyframes, and animation clock | Runtime / In progress | Paint-only transitions and named keyframes cover opacity, foreground/background colors, and typed 2D transform/translate/scale/rotate, including multiple animation names, CSS-like longhand list cycling, and start/iteration/end/cancel lifecycle dispatch. Additive composition, the complete discrete policy, additional values, and platform reduced-motion adapters remain. Continuous frames are requested only while motion is active. |
| Media/container queries | Planned | Native viewport, window, device, and application-state conditions replace browser CSS text parsing. |
| Browser/vendor/legacy CSS compatibility | No plan | CBSS prioritizes modern native behavior over web compatibility debt. |

## JavaScript-Like Behavior And Application Services

| Web role | Native CBSS/Nim equivalent | Status | Boundary |
| --- | --- | --- | --- |
| JavaScript language runtime | Nim | External | CBSS does not embed a scripting runtime. |
| DOM event listeners | typed `onClick`, `onChange`, keyboard, pointer, focus, form, and gamepad handlers | Runtime / In progress | Event names and semantics are familiar where useful, while payloads remain native and typed. |
| Component state and updates | Retained Nim fields, `StateRuntime`, and explicit invalidation | Runtime / Planned | The current primitives remain; concise `State[T]` and component-owned `watch` are planned without virtual-DOM-style reconstruction. |
| Effects, derived state, and subscriptions | First-party opt-in frontend-runtime module | Partial | Typed State, Store transactions, selectors, owned watch/effects, bounded Commands, the Cue graph core, typed Signal/State/Store Cue sources, ticket-scoped Command actions, and transition/keyframe Cue actions are implemented. Canvas integration, traces, and the orchestration demo remain planned. The module does not enter builds that omit it, and external state systems remain usable through ordinary Nim and Provider boundaries. |
| Timers and animation frames | scheduler deadlines and frame requests | In progress / Planned | Idle applications block on events; animation explicitly requests frames. |
| `fetch`, HTTP, retries, promises, and serialization | dedicated Nim networking packages | External | UI handlers may call those packages; transport policy is not CBSS core. |
| Browser storage APIs | application persistence packages and native storage adapters | External | CBSS owns no database, cookie, or browser-origin model. |
| ES module registry | Nim imports and Nimble packages | External | GUI libraries remain ordinary Nim packages. |
| Web Worker model | Nim threads/processes/async services with explicit UI-thread handoff | External | CBSS tree mutation and graphics submission remain on the host UI/render thread. |
| Browser sandbox and same-origin model | native application security policy | No plan | Native applications have different trust and permission boundaries. |

## Native Capabilities Beyond The Web Baseline

These are deliberate CBSS opportunities rather than attempts to imitate a
browser.

| Capability | Status | Direction |
| --- | --- | --- |
| SDL3 gamepad input and navigation | Planned | Semantic UI actions coexist with raw Canvas/game input. |
| Pen, touch, pressure, tilt, rotation, eraser, and proximity | Planned | Values remain capability-gated because hardware and OS support vary. |
| Sprite animation, tile maps, and Tiled-exported map rendering | Planned | Optional SDL-native modules share CBSS renderer, resource, input, and frame lifecycles. |
| SDL3 GPU Canvas | Planned | GPU workloads remain inside Canvas and do not create a second interpretation of ordinary styles. |
| Camera, video, and audio surfaces | Planned | Media adapters have explicit resource and permission lifecycles. |
| External renderer surfaces | Planned | A versioned `ExternalSurface` contract supports Canvas composition without coupling CBSS to a particular renderer. |
| C ABI | Runtime | Other languages can construct and control CBSS through stable opaque handles. Tree, style, events, focus, Canvas, frame requests, named-keyframe registration, monotonic motion advancement, dirty domains, deadlines, reduced motion, and lifecycle payloads are available. Foreign-language convenience wrappers and paint-command span patching remain later work. |
| Native accessibility bridges | Planned | Export the semantic/focus model through the relevant OS accessibility system. |
| Platform-native dialogs, file pickers, notifications, and system integration | Planned | Capability-gated adapters keep platform policy out of components. |

## Cross-Cutting Foundations

The following are prerequisites for a dependable ecosystem, even though they do
not map neatly to one web technology.

1. **Layout correctness:** percentage, automatic, intrinsic, min/max, flex
   shrink, containing-block, and text-metric behavior must be specified and
   regression-tested.
2. **Layer and overlay model:** menus, dialogs, popovers, tooltips, command
   surfaces, scroll clipping, transforms, and modal focus containment must use
   one coordinate and stacking model.
3. **Accessibility and keyboard operation:** every standard control must have
   focus, keyboard semantics, accessible role/name/state, and an OS export path.
4. **Asynchronous resources:** fonts, images, media, and future external data
   need loading, cancellation, failure, placeholder, cleanup, and targeted
   invalidation without synchronous paint-time I/O.
5. **Virtualization extension points:** CBSS need not auto-virtualize every
   list, but scrolling must expose viewport/content metrics and visible-range
   hooks so independent virtual-list and data-grid libraries can avoid creating
   an entire 100,000-row tree.
6. **Performance contracts:** dirty updates are proportional to affected work,
   idle applications do not poll continuously, and benchmarks are CI-enforced
   alongside correctness tests.
7. **Compatibility contracts:** public Canvas, C ABI, renderer, accessibility,
   and test-driver boundaries need versioning, capability reporting, and
   deterministic conformance tests.

## Deliberate Shape

The target is not “a browser in Nim.” The target is a native platform where:

- CBSS supplies composition, style, layout, semantics, events, rendering, and
  native input behavior.
- Nim supplies language features, modules, types, ordinary control flow, and
  application business logic.
- Independent packages supply domain capabilities such as HTTP clients,
  persistence, charts, data grids, editors, media codecs, and design systems.
- Contributors can add properties, elements, renderer adapters, and GUI
  libraries without changing unrelated subsystems.

This separation is what should let a native GUI ecosystem gain the composable
development experience associated with HTML, CSS, and JavaScript without
copying their browser-specific constraints.
