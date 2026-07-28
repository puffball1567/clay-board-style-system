# Tooling Roadmap

This document records planned developer tooling around CBSS. These items are
not required for the first style/layout core, but they are part of the intended
project direction.

## Status Terms

- `Planned`: intended project direction, not implemented yet.
- `Prototype`: partially implemented or experimental.
- `Supported`: implemented, tested, and expected to be maintained.

## Gallery Examples

Status: `Planned`

CBSS should include a project-local gallery under `examples/gallery/`. This is
not a marketing website and not dependent on MCP tooling. It is a set of
runnable files in the repository, similar to the local example galleries often
provided by CSS libraries and UI component libraries.

The gallery should be simple, inspectable, and easy to copy from. Its main job
is to show developers "this is how you build it with CBSS" while staying close
to real implementation code.

Initial gallery targets:

- Buttons
- Toolbar
- Cards
- Dialog
- Tabs
- Form controls
- Hover, active, and focus states
- `onClick` and pointer events
- Flex layout examples
- Absolute overlays
- Text rendering and font fallback
- Japanese text rendering
- Theme and style merge examples
- Game HUD style UI

The preferred contribution shape is one focused example per file:

```text
examples/gallery/
  buttons.nim
  toolbar.nim
  cards.nim
  dialog.nim
  tabs.nim
  form.nim
  text_rendering.nim
  japanese_text.nim
  hover_active_focus.nim
  theme_switch.nim
  game_hud.nim
```

Shared gallery shell code may live under:

```text
examples/gallery/common/
```

The gallery should be useful on its own before any design-tool integration
exists.

## CBSS MCP

Status: `Planned`

CBSS should eventually provide an MCP server that understands the project
model, implementation constraints, and supported style surface.

This is a planned tooling layer, separate from the local gallery. The MCP is
not required to view or run gallery examples.

The CBSS MCP should expose project-specific knowledge and actions such as:

- Runtime, computed, metadata, planned, and no-plan CSS property status
- CBSS property value helpers and Nim authoring patterns
- Style merge rules
- Selector, target, id, group, and state rules
- Layout constraints and backend boundaries
- Event handler patterns such as `onClick`
- Diagnostics for unsupported or partially supported properties
- Suggested substitutions for unsupported CSS or design-source features

The MCP should act as a CBSS-aware implementation assistant, not as a separate
runtime dependency for applications built with CBSS.

## Design-Source MCP Integration

Status: `Planned`

The shared in-process design-source model has a prototype implementation in
`src/clay_board_style_system/design_source/model.nim`. Service-specific MCP
adapters are still planned.

CBSS tooling should be designed so a design-source MCP can feed CBSS-oriented
source generation. Figma is the first obvious target, but the integration should
not be hard-coded to a single service if other design or creative tools expose
compatible MCP servers.

The goal is to let modern design workflows feed native application development
without requiring a browser WebView runtime. In this model, design services can
remain the place where teams design UI, while CBSS-backed applications become
one possible native desktop target for that work.

A source MCP reads design data; the CBSS MCP maps that data into
CBSS-oriented source code that a developer can run, inspect, and edit.

Service support should be implemented as isolated adapters. Adding support for a
new design service must not require changes to existing service adapters.

Planned shape:

```text
tools/cbss_mcp/
  core/
    design_source_model.*
    cbss_codegen.*
    diagnostics.*
  services/
    figma/
      adapter.*
      mapping.*
      tests.*
    canva/
      adapter.*
      mapping.*
      tests.*
    penpot/
      adapter.*
      mapping.*
      tests.*
```

Each service adapter should translate service-specific data into a shared
CBSS-owned intermediate model:

```text
Figma MCP data  -> Figma adapter  -> DesignSourceDocument
Canva MCP data  -> Canva adapter  -> DesignSourceDocument
Penpot data     -> Penpot adapter -> DesignSourceDocument

DesignSourceDocument -> CBSS codegen or higher UI layer codegen
```

The current prototype can map a `DesignSourceDocument` or `DesignSourcePage`
into a CBSS `Tree` and generated `StyleSheet`. It also supports external
stylesheet usage: adapters may emit only structure plus semantic ids/groups,
while project-owned `StyleSheet` values provide or override the actual
styling.

Style should be injectable as named stylesheet layers. A design-source adapter,
theme file, or responsive override can provide a `StyleInjection` that is placed
before or after generated design-source styles. Viewport conditions allow
layout.css-style responsive behavior without parsing media-query strings.

The shared model should describe concepts CBSS can reason about without naming
the source service:

- Document
- Page or canvas
- Frame
- Component
- Instance
- Auto-layout or layout hints
- Fill
- Stroke
- Radius
- Text layer
- Text style
- Token
- Prototype or interaction hint
- Asset reference

Service-specific details should stay inside the adapter unless they are promoted
intentionally into the shared model. This keeps Figma-specific behavior from
leaking into Canva support, and vice versa.

Expected split:

```text
Design-source MCP:
  read frames/pages/components, layout data, fills, strokes, text styles, and tokens

CBSS MCP:
  translate design data into CBSS style/layout/event code
  explain unsupported features
  create or update application or prototype source files
  keep generated code close to existing CBSS patterns
```

Initial mapping targets:

| Design-source concept | CBSS target |
| --- | --- |
| Frame | `Box` |
| Component | reusable constructor plus optional id/group metadata |
| Auto layout direction | `flex-direction` |
| Auto layout gap | `gap`, `row-gap`, `column-gap` |
| Padding | `padding` and side-specific padding |
| Alignment | `align-items`, `justify-content` |
| Fill | `background-color` |
| Stroke | `border-width`, `border-color`, `border-style` |
| Corner radius | `border-radius` and corner-specific radius |
| Text layer | `Text` node |
| Text style | `font-family`, `font-size`, `font-weight`, `line-height`, `color` |
| Prototype click | `onClick` stub |

The first goal should be useful generated starting points, not perfect
round-trip design fidelity. Generated code should be easy for a developer to
read, edit, and commit.

The integration should be treated as a planned workflow target. It may also be
valuable to design-tool vendors because it gives their users another practical
application target, but CBSS should keep this as an interoperability goal rather
than depending on any specific vendor relationship.

## CBSS CLI And Plugin Templates

Status: `Planned`

CBSS should provide a small CLI that creates project and plugin templates. The
goal is to make CBSS feel like a shared native UI runtime rather than a library
that every source file has to import directly.

The CLI should support at least:

```text
cbss create app my_app
cbss create plugin super_admin_ui
cbss add plugin super_admin_ui
cbss dev
cbss build
```

The generated application template should hide the direct CBSS import behind a
project-local facade:

```text
my_app/
  nim.cfg
  cbss.nim
  main.nim
  plugins/
  styles/
  examples/
```

`cbss.nim` is generated by the CLI and re-exports the public CBSS surface:

```nim
import clay_board_style_system
export clay_board_style_system
```

`nim.cfg` should make that facade available to project and plugin source files
without requiring each file to write an explicit import:

```text
--mm:arc
--path:"plugins"
--import:cbss
```

This makes plugin authoring closer to browser-based development: the shared UI
runtime is already present in the project environment, and plugin authors focus
on the component, style, chart, widget, or theme they are publishing.

Plugin source can then be written without direct CBSS imports:

```nim
proc adminButtonStyle*(): UiStyle =
  uiStyle([
    decl("border-radius", px(6)),
    decl("background-color", colorValue(rgb(0.12, 0.32, 0.58)))
  ])

proc AdminButton*(ui: UiRoot; label: string): ButtonHandle =
  ui.button(label, style = adminButtonStyle())
```

A user of that plugin should only need to import the plugin:

```nim
import super_admin_ui

let ui = initUiRoot()
AdminButton(ui, "Save")
```

The plugin should not vendor, copy, or statically embed a separate CBSS source
tree. It is authored against the CBSS facade supplied by the generated
application environment. This keeps the app on one CBSS runtime surface and
avoids every plugin carrying its own style, layout, paint, text, and event
engine.

Initial plugin template:

```text
plugins/super_admin_ui/
  super_admin_ui.nim
  styles.nim
  components/
    buttons.nim
    panels.nim
  examples/
  tests/
  README.md
  cbss-plugin.toml
```

The manifest should be light metadata, not a dynamic loader contract:

```toml
name = "super_admin_ui"
version = "0.1.0"
cbss = ">=0.1.0"
kind = "ui-plugin"

[capabilities]
styles = ["layout", "background", "border", "shadow", "font"]
events = ["pointer", "keyboard"]
paint = ["rect", "text", "gradient", "shadow"]
```

The first implementation can treat plugins as normal Nim modules and packages.
Dynamic plugin loading is not an initial goal. The important development
experience is:

- app templates create the shared CBSS environment;
- plugin templates assume that environment exists;
- plugin users import the plugin, not CBSS internals;
- plugins can expose styles that users import, merge, and override;
- the CLI keeps `nim.cfg`, plugin paths, and generated facade files consistent.

This approach keeps CBSS close to the role browsers play for Web UI libraries:
the shared runtime provides style, layout, paint, text, and events, while
independent libraries provide charts, widgets, themes, and application-specific
UI systems on top of that runtime.

## CBSS Test Driver

Status: `Prototype`

CBSS should eventually provide a Playwright-like testing layer for applications
built on CBSS. The goal is not to clone a browser automation tool. The goal is
to make native CBSS applications testable through CBSS's own stable runtime
model: `Tree`, resolved styles, layout, hit regions, event dispatch, focus
state, and paint commands.

This should be split into two layers.

### Headless Driver

Prototype module: `src/clay_board_style_system/testing/test_driver.nim`

The first implementation should be a headless test driver that does not open an
SDL3 window. It should build or receive a `UiRoot`, resolve styles, compute
layout, build hit regions, dispatch pointer and keyboard events, and expose
assertion helpers around visible text, values, focus, state, paint commands, and
hit targets.

This layer is the highest priority because it is deterministic, fast, and can
run in CI without platform-specific windowing or IME behavior.

The testing module must stay outside the normal application facade. Production
code that imports `clay_board_style_system` should not receive test-driver APIs.
Tests should import it explicitly:

```nim
import clay_board_style_system
import clay_board_style_system/testing/test_driver
```

Expected capabilities:

- Create a driver from a `UiRoot` or `UiRoot` builder and viewport size.
- Query nodes by direct handle/`NodeId`, CBSS code, id, group, text,
  placeholder, value, or attribute.
- Scope queries with `within(...)` so repeated components can be tested without
  requiring ids or globally unique visible text.
- Chain nested `within(...)` scopes and query direct children of a scoped
  component.
- Click, click outside, hover, drag, wheel, set focus directly, type text,
  paste, press keys, and move focus with Tab.
- Open and close popups through named helpers and choose popup options without
  hand-writing the click sequence in every test.
- Assert text, value, attributes, focus, open/closed state, checked/selected/
  disabled state, selection text/range, caret position, textarea scroll offset,
  arbitrary element state, diagnostics, and paint command presence.
- Validate that popups sit above overlapping content in hit testing and paint
  order.
- Capture layout and paint command snapshots for structural visual regression
  tests.
- Read synchronized component state from standard runtime controls such as
  text input, textarea, select, checkbox, radio, and slider.
- Exercise clipboard-like copy, cut, and paste workflows in headless tests.
- Read id-addressable and code-addressable component values as form-style value
  lists.
- Provide concise workflow helpers for common form operations such as fill,
  clear, toggle, and select-option flows.
- Emit query reports, tree snapshots, and line-based snapshot diffs so failed
  CI logs are readable without opening an SDL3 window.
- Emit compact debug reports containing viewport, focus, values, dispatches,
  and diagnostics.
- Emit a debug bundle that combines the compact report, optional query report,
  layout snapshot, paint snapshot, and dispatch snapshot for CI failure triage.
- Emit structured JSON snapshots containing viewport, tree nodes, layout boxes,
  paint commands, focused target, form-style values, and recent driver actions.
- Record recent driver actions such as click, focus, type, paste, drag, wheel,
  popup, and viewport operations so failed UI tests can show a useful
  Playwright-style trace without opening a window.
- Save debug bundles and large-suite summaries to files for CI artifacts.
- Run scenario-style headless E2E flows with named steps. A scenario should
  aggregate checks, keep the recent action trace, and write a debug bundle only
  for failed steps.
- Save and compare approved snapshot baseline files, either as structured JSON
  snapshots or as the older text layout/paint snapshots.
- Resolve named approved snapshot paths from a baseline directory, update
  baselines with `CBSS_UPDATE_SNAPSHOTS`, and write `.actual` files for failed
  comparisons.
- Detect ambiguous queries with uniqueness assertions before a test silently
  drives the first matching node.
- Wait for common semantic conditions such as existence, value changes, and
  dispatched events while returning the same query/debug reports used elsewhere.
- Aggregate large test-suite checks into a compact pass/fail summary and write
  that summary to an artifact file so CI logs can report multiple UI or
  baseline failures at once.
- Use `CbssScenario` for longer user-flow tests where each step should be named
  and failed steps should produce CI artifacts.

Still planned for the headless driver:

- richer async/wait diagnostics once CBSS has a production runtime queue.
- configurable trace filtering and redaction for very large suites.

Example shape:

```nim
let driver = initCbssTestDriver(buildDemoUi, size(1280, 720))

driver.click(byText("Run"))
check driver.textContent(byId("status")) == "Running"

driver.click(byPlaceholder("Type here"))
driver.typeText("hello")
check driver.value(byPlaceholder("Type here")) == "hello"

driver.click(byText("Theme"))
check driver.isOpen(byGroup("select"))
```

Longer flows can use a scenario wrapper:

```nim
let driver = initCbssTestDriver(buildSettingsUi, size(1280, 720))
var scenario = initCbssScenario("settings workflow", driver, "build/cbss-artifacts")

discard scenario.step("fill account name", proc(): bool =
  driver.fill(byCode("account-name"), "Ada")
)

discard scenario.expect(
  "account name persisted",
  driver.expectValue(byCode("account-name"), "Ada"),
  some(byCode("account-name"))
)

check scenario.ok
```

The query API should be CBSS-native. It can feel familiar to Web engineers, but
it should not require a DOM, CSS selector engine, or browser-compatible
semantics. Direct handles should also remain supported so Nim tests can stay
precise and refactor-friendly.

### SDL3 Integration Driver

A second layer may drive a real SDL3 backend. This should be reserved for cases
where the headless driver cannot validate enough behavior:

- native clipboard integration;
- IME composition and candidate-window placement;
- cursor shape;
- real event timing and key repeat;
- platform-specific text input behavior;
- screenshot or pixel-diff checks.

This layer is useful but less deterministic. It should be optional and should
not be required for ordinary unit or CI tests. Linux should be the first
supported target, with Windows and macOS validation handled as contributors and
CI coverage become available.

The first real-window driver is the SDL3 Wayland driver:

```text
src/clay_board_style_system/testing/integration/
  sdl3_wayland_driver.nim
```

This driver is intentionally separate from the headless test driver and from
the production facade. It opens a real SDL3 window on a Wayland session,
renders the same CBSS paint command output into that window, can poll SDL3
events, can save debug bundles, and can write a PPM screenshot artifact. It
also embeds the headless driver so tests can reuse the same query and semantic
assertion helpers while checking the real rendered window.

The prototype can also compare ASCII PPM screenshots against a baseline. A
failed comparison reports changed pixel count, changed ratio, maximum channel
delta, and can write a red-highlighted diff PPM artifact. This is deliberately
kept as a backend-level opt-in check. Most tests should continue to prefer
semantic assertions and paint/layout snapshots before relying on pixels.

Real-window flows can use `Sdl3WaylandScenario`, which mirrors the headless
scenario style with named steps, pass/fail aggregation, action traces, and
failure artifacts. This gives Wayland E2E tests a consistent report shape
without making SDL3 or Wayland part of the production API.

The Wayland smoke test currently covers a narrow but important real-device
slice: rendered output, cursor resolution from hit regions, SDL text input area
synchronization for focused text controls, SDL clipboard round-tripping,
screenshot creation, screenshot baseline comparison, and debug bundle output.
IME composition itself still needs deeper real-input coverage, but the text
input area synchronization is in place and follows the focused text control's
caret node where possible. This lets candidate-window placement be tested
against real compositor behavior without hard-coding a full IME implementation
into the test driver.

The driver also has a small `Sdl3Event` dispatch bridge. It converts SDL3
events into CBSS input events for pointer, key, text input, composition, wheel,
touch, and resize flows. This bridge lets unit tests replay important native
event sequences without opening a real window, while the Wayland smoke test can
still validate the SDL3/window-system path.

Composition candidate events are retained as diagnostic state. Tests can assert
the current candidate list and selected candidate, and debug bundles include
the most recent candidate snapshot. This does not attempt to implement or own
the OS IME UI; it records the SDL3-visible state needed to diagnose candidate
placement and composition behavior.

Clipboard helpers should keep the SDL clipboard and the headless semantic
clipboard in sync for focused copy, cut, and paste workflows. In headless-only
tests the same helpers fall back to the semantic clipboard, so test code can
exercise the workflow without requiring a window server.

Each real-window driver should expose a small capability report and artifact
manifest. The report describes what the driver can validate, such as semantic
queries, SDL event dispatch, cursor state, text input area tracking, IME
candidate diagnostics, clipboard synchronization, PPM screenshots, screenshot
diffs, debug bundles, and scenario artifacts. The manifest records the same
capabilities together with generated artifact paths, action traces, and recent
events. This gives CI and contributors a consistent way to compare Wayland,
X11, Windows, and macOS drivers without making those drivers part of the
production API.

The current Wayland driver is a prototype and reference implementation. Its
purpose is twofold:

- make real-window verification useful during CBSS development on Linux;
- show contributors how to add OS-specific real-device drivers without changing
  application code or the headless driver API.

Wayland should be treated as the reference real-window driver for the first
phase. It is not a portability requirement for every contributor, and it is not
a signal that every OS-specific driver must be implemented before CBSS can
move forward. The expected development order is:

1. Keep most behavior covered by headless unit, integration, scenario, and
   snapshot tests.
2. Use the Wayland driver to prove that the same behavior also survives a real
   SDL3 window, compositor events, clipboard, cursor changes, screenshots, and
   text-input area synchronization.
3. Let X11, Windows, and macOS drivers adopt the same capability report,
   artifact manifest, and scenario style when contributors or CI environments
   are available.

This keeps OS-specific work useful but non-blocking. A new platform driver is
expected to report exactly which capabilities it supports rather than claiming
full parity immediately. Missing capabilities should be visible in the driver
report and CI artifacts, not hidden behind broad pass/fail labels.

Optional smoke test:

```text
CBSS_RUN_WAYLAND_E2E=1 nimble testSdl3Wayland
```

Without `CBSS_RUN_WAYLAND_E2E=1`, the smoke test compiles and reports skipped
instead of opening a window. This keeps ordinary CI fast and deterministic.

For local visual inspection, keep the window open for a short period:

```text
CBSS_RUN_WAYLAND_E2E=1 CBSS_WAYLAND_HOLD_MS=3000 nimble testSdl3Wayland
```

`CBSS_WAYLAND_HOLD_MS` is intentionally opt-in. It should not be set in normal
CI because it slows tests down. While holding the window, the driver continues
to poll SDL events so compositor/window events do not accumulate unchecked.

Expected future split:

```text
testing/integration/
  sdl3_wayland_driver.nim   # prototype/reference
  sdl3_x11_driver.nim       # future/contributor
  sdl3_windows_driver.nim   # future/contributor
  sdl3_macos_driver.nim     # future/contributor
```

The Wayland implementation should not become a portability bottleneck. OS and
compositor differences belong in integration drivers; normal CBSS tests should
continue to prefer headless unit, integration, scenario, and snapshot tests
unless real SDL3/window-system behavior is the thing being tested.

### Design Constraints

- The test driver must use public or intentionally exposed CBSS runtime
  boundaries, not backend-private SDL3 details.
- Headless tests should not depend on SDL3.
- Assertions should prefer semantic runtime state and paint command structure
  before pixel comparison.
- Pixel or screenshot testing should be an optional backend-level feature.
- The driver should make performance-sensitive behavior testable, including
  partial invalidation, focus-owned text events, popup hit ordering, and
  text-control caret movement.
- The tool should remain separate from application runtime code. Applications
  should not need to ship the test driver.
- The top-level `clay_board_style_system` module should not export the test
  driver. Test code must opt in through `clay_board_style_system/testing/...`.
- Production import-boundary tests should verify that neither the headless test
  driver nor real-window integration drivers leak through the top-level module.
- Test artifacts are files only. Testing drivers should not execute artifact
  paths, shell out through artifact values, or read arbitrary project state
  beyond the explicit UI/test inputs they were given.

This tooling would make CBSS more suitable for production use because native UI
behavior could be tested with the same kind of confidence Web teams expect from
modern browser automation, while still staying inside CBSS's native rendering
model.

## Non-Goals

- The MCP should not require applications to run through an MCP at runtime.
- Design-source integration should not force CBSS to imitate the browser DOM.
- Generated code should not hide CBSS style rules behind opaque blobs.
- Unsupported design-source features should be reported clearly instead of silently
  producing misleading UI.
- Plugins should not vendor a private copy of CBSS.
- Dynamic plugin loading is not required for the first plugin model; Nim modules
  and project templates are enough for the initial workflow.
- The test driver should not try to become a general-purpose browser automation
  compatibility layer.
