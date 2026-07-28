# Clay Board Style System (CBSS)

Clay Board Style System (CBSS) is a CSS-inspired primitive style and layout
foundation for native GUI libraries.

The first implementation target is Nim. The Nim package/import name should be
`clay_box_style_system`.

The initial runtime target is Linux x86_64 with SDL3. Windows and macOS support
are planned, but they are contributor-validated and not release-blocking during
the early phase.

CBSS is not a component library. Its product boundary is the primitive layer
that GUI libraries build on: boxes, text, images, style, layout, state, drawing
commands, hit testing, focus, input, and accessibility semantics. The repository
contains replaceable reference controls so these mechanisms can be exercised
and tested, but their visual design is not the public product.

The name is intentional. The project is not the clay itself, meaning the GUI
components. It is the board where the clay is placed, shaped, arranged, and
prepared.

## Release Status

Version 0.1 is a Linux x86_64 developer preview. It is suitable for evaluating
the API, building GUI libraries, and contributing runtime capabilities. Public
APIs may still change before 1.0.

Current boundaries:

- Linux x86_64 with SDL3 is the only Tier 1 runtime target.
- Windows and macOS adapters require contributor validation.
- The semantic accessibility model exists, but the Linux AT-SPI D-Bus
  transport, UIA, and NSAccessibility transports are not complete.
- Animation timelines, full inline rich-text layout, and native multi-window
  popup escape are not complete.
- Property status is defined by the
  [support matrix](docs/css-property-support.md); accepted metadata does not
  imply active runtime behavior.

## Quick Start

Requirements:

- Nim 2.2 or newer
- Rust and Cargo for the cosmic-text and image bridges
- Linux x86_64 SDL3 development files and native bridges

Install CBSS once:

```sh
nimble install clay_box_style_system
```

Prepare a runtime directory using the layout in
[docs/runtime-linking.md](docs/runtime-linking.md), then select bundled setup
to link its SDL3 archive statically:

```sh
cbss_configure bundled /path/to/cbss-runtime
nimble test
nimble sdl3Demo
```

CBSS does not include native runtime binaries in its Nimble package. Bundled
setup statically links SDL3 from the supplied runtime directory and dynamically
links the CBSS image and cosmic-text C ABI bridges. Both bridges are built from
source included with CBSS. To use libraries supplied by the operating system
instead:

```sh
cbss_configure system
nimble sdl3Demo
```

The selected mode is stored in the application's ignored `.cbss/` directory;
application source code and imports stay the same. Custom runtime prefixes and
release packaging are documented in
[docs/runtime-linking.md](docs/runtime-linking.md).

When developing CBSS itself, `nimble setupBundled` and `nimble setupSystem`
provide equivalent repository-local shortcuts.

## Language-Neutral C ABI

CBSS exposes its tree, full typed-style values, layout, paint commands, input
dispatch, event callbacks, focus, retained scrolling, accessibility semantics,
diagnostics, and hit testing through a versioned C ABI. The public boundary
uses opaque handles and fixed-layout value structs; Nim strings, sequences,
references, exceptions, and object layouts are not exposed.

```sh
nimble buildCAbiShared
nimble buildCAbiStatic
nimble testCAbi
```

These tasks produce `/tmp/libcbss.so` or `/tmp/libcbss.a` during development.
Applications include `cbss.h` and may wrap the same ABI from C++, Rust, Zig,
Swift, or another language with C interop. See
[docs/c-api.md](docs/c-api.md) for ownership and compatibility rules.

## Motivation

Modern web frontend development is productive partly because many frameworks
share the same underlying platform: the browser style and layout engine. React,
Vue, Svelte, Solid, and other frameworks can focus on component models because
CSS already provides a common foundation for color, spacing, sizing, layout,
state styling, and responsive behavior.

Native GUI ecosystems usually do not have an equivalent shared layer. Each GUI
toolkit tends to reinvent:

- Layout
- Styling
- Theming
- Responsive sizing
- State styling
- Text measurement
- Clipping and scrolling
- Hit testing
- Paint ordering
- Focus and input routing

As a result, building a modern native GUI library remains expensive. CBSS is an
attempt to provide the missing CSS-position layer for native GUI work, without
copying browser-specific CSS behavior.

## Design Philosophy

CBSS should borrow the mental model of CSS, not the full browser specification.

The goal is not CSS compatibility. The goal is to make primitive native GUI
construction understandable to people who already know how to build interfaces
with CSS-like concepts.

The same rule applies to event and component vocabulary. CBSS may use familiar
Web/DOM/TSX names such as `onClick`, `onInput`, or `onPointerMove`, but the
implementation is independent. CBSS should not copy browser or framework
internals such as React SyntheticEvent, Fiber/reconciler behavior, hooks, or
framework source code.

CBSS should make common UI intentions direct:

- Make a rectangle
- Set a color
- Add padding
- Add a border
- Round corners
- Put text inside a box
- Arrange children horizontally or vertically
- Add a gap between children
- Fill remaining space
- Size to content
- Center children
- Hide overflow
- Wrap text
- Change style on hover, active, focus, or disabled state
- Create hit regions for pointer events

The project should avoid legacy browser concerns that do not help native GUI
libraries.

Do not implement:

- HTML output
- DOM compatibility
- JavaScript
- Full CSS compatibility
- Float layout
- Table layout
- Browser quirks
- Full cascade specificity
- Full inline formatting context
- Full CSS Grid as an initial goal
- Browser default stylesheets

## Core Idea

The primitive element should be similar in spirit to a `div`: a generic box that
can be styled, laid out, nested, drawn, and used as an event region.

CBSS core primitives:

- `Box`
- `Text`
- `Image`

Everything else belongs to GUI libraries built on top of CBSS.

Examples:

- `Button = Box + Text + clickable behavior`
- `Card = Box + padding + border/radius/shadow + children`
- `Toolbar = Box + row layout + gap`
- `Window = Box + titlebar + draggable/resizable behavior + z-order`
- `ScrollView = Box + clipping + scroll behavior`

The CBSS core should not need to know what a button is.

Reference controls under `runtime/` are compositions used to verify this
primitive machinery. GUI libraries may use, replace, or ignore them without
changing the core pipeline.

## Conceptual Pipeline

CBSS should work as a native UI computation engine:

```text
Node tree
  -> style resolution
  -> layout calculation
  -> paint command generation
  -> hit region generation
  -> native renderer backend
```

The output should be native-renderer-friendly command data, not HTML.

Possible backend targets:

- SDL3
- OpenGL
- Vulkan
- Metal
- Direct2D
- Skia
- Blend2D
- Sokol

The core should stay renderer-independent.

## Architecture Notes

The intended internal architecture is organized around loosely coupled
extension units:

- Elements
- Selectors
- Style properties

See [docs/architecture.md](docs/architecture.md) for the current design notes.
See [docs/performance-model.md](docs/performance-model.md) for performance
budgets and hot-path rules — being lightweight and fast is a product
requirement, and that document has the same authority as the architecture
notes.
See [docs/design-decisions.md](docs/design-decisions.md) for settled design
decisions and component conventions.
See [docs/runtime-components.md](docs/runtime-components.md) for per-component
behavior notes on the reference runtime controls.
See [docs/accessibility.md](docs/accessibility.md) for the semantic-tree,
focus, platform-adapter, and assistive-technology transport boundaries.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the files-to-touch map and ground
rules for contributions.
See [docs/platform-support.md](docs/platform-support.md) for the current
platform support policy.
See [docs/runtime-linking.md](docs/runtime-linking.md) for bundled, system, and
custom dynamic-link setup and packaging.
Use
[docs/platform-validation-checklist.md](docs/platform-validation-checklist.md)
when validating Windows, macOS, or another non-primary platform.
See [docs/css-property-support.md](docs/css-property-support.md) for the CSS
property support matrix.
See
[docs/css-property-implementation-order.md](docs/css-property-implementation-order.md)
for the planned CSS property implementation order.

## Initial Scope

The first useful version should focus on primitive layout and style, not rich
widgets.

Minimum useful features:

- Node tree
- Generic `Box`
- `Text`
- `Image`
- Width and height
- Min and max size
- `px`, `percent`, `fill`, and `content` sizing
- Padding
- Margin
- Border
- Border radius
- Background color
- Text color
- Row and column layout
- Gap
- Align and justify
- Basic absolute or overlay positioning
- Overflow hidden
- Text wrapping
- Hover, active, focus, and disabled state styling
- Draw command output
- Hit testing
- General keyboard focus traversal
- Text input, selection, clipboard, and IME handling
- Platform-neutral accessibility semantics
- AT-SPI semantic adapter core and action routing

Possible later features:

- Typed theme and token APIs
- Broader partial-render invalidation
- Linux AT-SPI D-Bus transport, UIA, and NSAccessibility adapters
- Animation and transitions
- Debug inspector for computed style and layout boxes

## CSS-Like, Not CSS-Compatible

CBSS should use familiar names where they help:

- `padding`
- `margin`
- `gap`
- `border`
- `radius`
- `background`
- `color`
- `fontSize`
- `align`
- `justify`
- `overflow`

But it should prefer direct native-GUI intentions where CSS is more complicated
than necessary:

- `width = fill`
- `height = content`
- `textWrapping = word`
- `clip = true`
- `scroll = vertical`
- `clickable = true`
- `draggable = true`

The guiding rule:

```text
Use CSS vocabulary when it improves intuition.
Avoid CSS behavior when it only exists for browser compatibility.
```

## Example Shape

The exact API is not decided, but usage should feel understandable to people
who know CSS concepts.

```nim
box(id = "toolbar"):
  box(groups = ["button", "primary"]):
    text("Save")
  box(groups = ["button"]):
    text("Cancel")
```

Style could be represented with a Nim DSL:

```nim
style "[id=toolbar]":
  layout row
  gap 8.px
  padding 8.px
  background "#20242a"

style ".button":
  padding 6.px, 12.px
  radius 4.px
  background "#3a3f48"
  color "#f5f5f5"

style ".button:hover":
  background "#4b5563"
```

Or the API could be more explicitly typed. The important part is that written
style and visual result are easy to connect mentally.

For hand-written code, component-owned styles and events should be the main
path:

```nim
proc saveButtonStyle(): UiStyle =
  uiStyle([
    decl("padding", px(8)),
    decl("background-color", colorValue(rgb(0.1, 0.35, 0.6))),
    decl("color", colorValue(rgb(1, 1, 1)))
  ])

proc onSave(event: DispatchResult): bool =
  echo "save"
  true

proc SaveButton(ui: UiRoot; style = saveButtonStyle()): NodeHandle {.discardable.} =
  ui.box(result, style):
    ui.text("Save")
  result.onClick = onSave
```

For deeper trees, block-style builders keep parent-child relationships visible:

```nim
let ui = initUiRoot()
var app: NodeHandle

ui.box(app, "app"):
  ui.box("header"):
    ui.box("toolbar"):
      SaveButton(ui)
```

Large UIs should be split into component-like procedures instead of one large
nested block. Style can be injected, events stay inside the component by
default, and params are only for extra values the component needs:

```nim
type ToolbarParams = object
  title: string

proc toolbarStyle(): UiStyle =
  uiStyle([
    decl("height", px(48)),
    decl("gap", px(8))
  ])

proc onSave(event: DispatchResult): bool =
  echo "save"
  true

proc SaveButton(ui: UiRoot; style = saveButtonStyle()): NodeHandle {.discardable.} =
  ui.box(result, style):
    ui.text("Save")
  result.onClick = onSave

proc Toolbar(
    ui: UiRoot;
    style = toolbarStyle();
    params = ToolbarParams(title: "Editor")
): NodeHandle {.discardable.} =
  ui.box(result, style):
    ui.text(params.title, groups = ["title"])
    SaveButton(ui)

proc App(ui: UiRoot): NodeHandle {.discardable.} =
  ui.box(result, uiStyle([decl("padding", px(16))])):
    Toolbar(ui, params = ToolbarParams(title: "Editor"))
    ui.box(uiStyle([decl("padding", px(12))])):
      ui.text("Document body")
```

If a parent wants to change a child component's style, it imports or builds a
`UiStyle` and passes it directly:

```nim
SaveButton(ui, style = saveButtonStyle() + uiStyle([
  decl("background-color", colorValue(rgb(0.45, 0.12, 0.12)))
]))
```

## Why This Matters

If CBSS exists, native GUI libraries do not need to repeatedly solve the same
primitive layout and styling problems. They can focus on higher-level component
behavior and application architecture.

The intended ecosystem shape is:

```text
CBSS core:
  primitive boxes, text, style, layout, paint commands, hit testing

GUI libraries:
  Button, Card, Dialog, TextInput, Menu, Window, Inspector, Editor UI

Applications:
  actual product interfaces
```

This makes GUI components a matter of composition rather than reinvention.

## Project Positioning

Clay Board Style System (CBSS) is:

- A native GUI foundation
- CSS-inspired
- Primitive-first
- Renderer-independent
- Widget-toolkit-agnostic
- Useful for building GUI libraries

Clay Board Style System (CBSS) is not:

- A browser
- A webview
- A CSS implementation
- A complete GUI toolkit
- A component library
- A replacement for application architecture

## Development

Run `nimble test` for the automatically discovered ARC test suite,
`nimble checkExamples` for all example and link-mode checks, and `nimble bench`
for release-mode performance probes. Real-window Wayland tests remain explicit
opt-in tasks.

See [CONTRIBUTING.md](CONTRIBUTING.md) before changing public boundaries or hot
paths.

## Memory Verification

The shared and static C ABI consumers are checked with Valgrind during release
verification. The exercised path covers context and style handle lifetimes,
tree and style mutation, C event callbacks, focus traversal, retained
scrolling, recomputation, diagnostics, and repeated context creation and
destruction.

The current shared and static builds both complete with:

```text
ERROR SUMMARY: 0 errors from 0 contexts
in use at exit: 0 bytes in 0 blocks
```

After `nimble testCAbi`, the checks can be reproduced with:

```sh
valgrind --vgdb=no --leak-check=full --show-leak-kinds=definite \
  --errors-for-leak-kinds=definite --error-exitcode=99 \
  /tmp/clay_box_style_system_c_consumer_shared

valgrind --vgdb=no --leak-check=full --show-leak-kinds=definite \
  --errors-for-leak-kinds=definite --error-exitcode=99 \
  /tmp/clay_box_style_system_c_consumer_static
```

Valgrind is one release check, not a substitute for the ARC test suite,
platform-specific integration tests, sanitizers, or API ownership review.

## License

CBSS is licensed under the [MIT License](LICENSE). Vendored and dynamically
linked dependency notices are recorded in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
