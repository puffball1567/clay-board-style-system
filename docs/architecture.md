# CBSS Architecture Notes

This document records the intended internal shape of Clay Board Style System
(CBSS). It is not a final specification. It exists to keep the implementation
direction clear while the project is still early.

## Design Goal

CBSS should be organized around three independent extension units:

- Elements
- Selectors
- Style properties

These units should stay loosely coupled.

```text
Element implementations should not know selector implementations.
Selector implementations should not know style property implementations.
Style property implementations should avoid element-specific behavior.
The resolver and engine connect them.
```

The goal is to make CBSS extensible in the same way CSS feels extensible: new
element kinds, new selector conditions, and new style properties can be added
without rewriting the whole engine.

## OSS Contribution Shape

CBSS should be structured for low-conflict open source contribution.

The implementation should prefer many small, explicit modules over large central
files. A contributor adding one style property, one selector condition, one
element behavior, or one backend feature should usually touch a small number of
localized files.

This matters for human contributors, but it also matters for AI-assisted
contribution. A project goal is that local LLMs running on ordinary developer
PCs should be able to make accurate, useful changes without needing the whole
codebase in context.

Design implications:

- Keep element implementations in `elements/<name>/`.
- Keep selector implementations in `selectors/`.
- Keep style property implementations in `properties/`.
- Keep renderer-specific code in `backends/<name>/`.
- Keep external integrations such as text engines behind narrow adapters.
- Avoid large catch-all files that every feature has to edit.
- Avoid central switch statements that must be updated for every property.
- Prefer registration tables or generated indexes over hand-edited monoliths.
- Keep tests near the feature they validate when practical.
- Document the expected files to touch for common contribution types.

The ideal contribution path is:

```text
Add one property:
  create or edit properties/<property>.nim
  add focused tests for that property
  update the support matrix status

Add one selector:
  create or edit selectors/<selector>.nim
  add focused selector matching tests

Add one element behavior:
  edit elements/<element>/<phase>.nim
  add focused layout, paint, or hit-test tests
```

The architecture should make merge conflicts uncommon. When conflicts do happen,
they should usually be limited to small registry or documentation updates.

Developer tooling, gallery examples, and planned MCP integration are tracked in
[tooling-roadmap.md](tooling-roadmap.md).

## External Design Workflow Compatibility

CBSS should be designed with external design tools in mind, including Figma-like
services and future design-source MCP integrations. This should influence the
shape of the public model, but it should not make CBSS a clone of any single
external service.

The import boundary starts with a service-neutral intermediate model under
`src/clay_board_style_system/design_source/`. Source services should map into
that model first, then CBSS can turn it into `Tree` and `StyleSheet` data. This
keeps source-specific behavior outside core style, layout, paint, and event
code.

External styles should remain first-class. Design-source imports may generate
local style rules, or they may emit only ids, groups, and attributes while
project-owned styles are injected later. Injection layers can be ordered before
or after generated styles and may be gated by viewport conditions.

The design rule is:

```text
Optimize for clean translation.
Do not optimize for exact source-tool imitation.
```

CBSS should keep or add concepts when they make design data easier to translate
into native UI code:

- Stable node identity through `NodeId`
- Explicit ids and groups
- Box/Text/Image primitives
- Flex-like layout vocabulary
- CSS-familiar property names where they map well
- Explicit style merge operations
- Inspectable computed style and layout results
- Clear diagnostics for unsupported source features
- Source metadata hooks that can be kept out of runtime behavior

CBSS should resist changing core behavior just to mirror one design tool:

- Do not add a browser DOM identity model only because a source tool has layers.
- Do not make Figma, Canva, or any service name part of the core style model.
- Do not hide generated style rules in opaque blobs.
- Do not weaken type checking to accept every external value silently.
- Do not make runtime applications depend on MCP availability.

External tool integration should pass through a CBSS-owned intermediate model.
That lets each service adapter handle service-specific details without forcing
those details into style resolution, layout, painting, or event handling.

This principle also informs the question "what should change and what should
not change?" A change is more likely to belong in CBSS core if it improves the
native UI model and also makes design-source translation clearer. A change is
more likely to belong in tooling if it is mainly about importing, naming,
metadata, asset lookup, or preserving source-tool structure.

## Implementation Language And Memory Model

The first implementation will be written in Nim.

The Nimble package and public import path should use snake case:

```text
clay_board_style_system
```

The public project name can remain human-readable, but Nim modules should use
the package spelling above.

Applications may compile CBSS with either `--mm:arc` or `--mm:orc`. CBSS uses
ARC-compatible ownership as the stricter design and release-verification
baseline; the ORC test lane verifies application compatibility rather than
hiding cycles in CBSS-owned state.

CBSS should therefore prefer Nim ARC-compatible ownership patterns:

- Value objects where practical
- `seq`-backed arenas for trees and computed results
- Stable ids such as `NodeId` instead of parent/child `ref object` cycles
- Command buffers for paint commands and hit regions
- Explicit close/free APIs for external native resources

The core tree should not be modeled as cyclic object references.

Public Nim component handles are non-owning views into a `UiRoot`. Their root
back-reference uses `{.cursor.}` because the root owns event handlers that may
capture those handles. A handle must not outlive its root, and code must not
dereference it after the referenced node generation has been retired. The C ABI
does not expose these Nim references; it uses opaque handles with explicit
create and destroy contracts.

Avoid this shape:

```nim
type
  Node = ref object
    parent: Node
    children: seq[Node]
```

Prefer this shape:

```nim
type
  NodeId* = distinct int

  Node* = object
    parent*: NodeId
    children*: seq[NodeId]

  Tree* = object
    root*: NodeId
    nodes*: seq[Node]
```

Manual memory management is acceptable where ARC is not the right ownership
boundary. Expected cases include:

- Renderer backend handles
- Windows, surfaces, textures, and GPU resources
- Text engine bridge contexts
- Font systems and glyph caches
- Image resources
- Large caches that need explicit lifetime control

Foreign or backend resources should be wrapped in Nim objects with explicit
`close`, `destroy`, or `free` procedures. The public core should still expose
simple value-oriented data structures wherever possible.

## Runtime Update And Performance Policy

CBSS should aim to be a lightweight native UI foundation. Full UI tree
reconstruction is acceptable for early demos, tests, and simple examples, but
it must not be the assumed production update path.

Production-oriented runtime updates should be dirty-driven:

- The runtime should not render every frame by default. A frame should be
  requested only when input, state mutation, animation, resize, async resource
  completion, caret blink, or another explicit invalidation source changes
  visible output or hit behavior.
- Text changes should update the existing text node and text layout cache.
- Style changes should invalidate computed style only for affected nodes and
  descendants when inheritance requires it.
- Layout changes should invalidate the smallest layout subtree that can affect
  geometry.
- Paint-only changes should rebuild paint commands without rerunning style and
  layout.
- Text-only changes such as caret movement, selection highlight, composition
  preview, and bounded input editing should avoid full style/layout rebuilds.
- Focus, blur, pointer focus normalization, Tab order, and focus-visible state
  are coordinated by the runtime/root interaction layer for every interactive
  element. Individual components may own their values and local geometry, but
  they do not independently decide global focus ownership. Text controls remain
  responsible only for caret and selection geometry. This prevents stale
  carets, delayed focus visibility, and input events leaking between controls.
- A retained but inactive subtree is marked `inert` by runtime ownership code.
  Inertness is inherited and excludes descendants from focus, tree-aware event
  dispatch, and accessibility exposure without pretending to be a CSS state.
  Visual and geometric exclusion remains the style system's responsibility;
  the navigation screen host pairs inertness with `display: none`.
- Hit regions should be rebuilt only when geometry, visibility, z order, or
  event participation changes.
- Renderer backends should cache expensive rasterized resources such as text,
  rounded masks, shadows, and image variants when their inputs are unchanged.
- Renderer backends should prefer partial invalidation or dirty-rect rendering
  where the backend makes that practical. Full-frame presentation is acceptable
  as a backend fallback, but the core should still expose enough dirty metadata
  for narrower updates.

CBSS also owns UI semantics, while application behavior remains outside it.
Nodes expose typed accessible roles, names, descriptions, values, state,
relations, and logical set position/size through a platform-neutral semantic
tree. Standard controls own
intrinsic behavior such as keyboard activation, selection, disabled handling,
and disclosure expansion. A user callback owns what happens after activation,
such as saving, printing, or calling a backend. AT-SPI, UIA, and
NSAccessibility adapters consume the same semantic tree without changing
component implementations. The Linux adapter is split again into an AT-SPI
snapshot/action model and a D-Bus transport so platform communication cannot
leak into controls. See [accessibility.md](accessibility.md).

The intended model is:

```text
state or input event
  -> update stable nodes, styles, or component-local state
  -> mark dirty domains
  -> recompute only required style/layout/paint/hit data
  -> render changed frame data
```

The frame scheduler should distinguish at least these invalidation domains:

- `styleDirty`: selector, state, variable, or injected style changes require
  computed style refresh.
- `layoutDirty`: size, display, flex, position, text measurement, or child
  contribution changes require layout refresh.
- `paintDirty`: visual-only changes require paint command refresh.
- `hitDirty`: geometry, visibility, z order, pointer-events, cursor, or event
  participation changes require hit-region refresh.
- `textDirty`: text content, caret, composition, selection, or text-scroll
  changes require text/cache updates.
- `resourceDirty`: async image/font/resource completion requires affected
  nodes to update.
- `animationDirty`: active transitions, keyframes, timers, or caret blink
  require another frame until the animation is idle.

The event loop should sleep or wait for backend events when no dirty domain is
active. It should request continuous frames only while animation-like work is
active. This includes CSS-style animations, transitions, kinetic scrolling,
timers, and caret blink if the backend cannot update the caret layer without a
frame.

Input processing should also be invalidation-aware. Pointer movement that only
changes hover state should not force full style/layout work unless hover styles
actually affect those domains. Text input should be tied to the focused text
control at the time the input was generated; delayed key, text, or composition
events from a previous focus context must be discarded instead of being applied
to the newly focused control.

CBSS should not depend on virtual-DOM-style full component replay as its core
performance strategy. Stable `NodeId` values, explicit node mutation APIs, and
domain-specific dirty flags are preferred because they fit ARC-friendly Nim data
structures and native renderer caches.

Three separate mechanisms must not be grouped under the word "virtualization":

- **Virtual DOM replay** compares reconstructed component output. CBSS does not
  use this as its production update model.
- **Viewport/data virtualization** materializes only the visible window of a
  very large logical collection. Lists and data grids still need this capability
  independently of renderer caching.
- **Event-driven frame scheduling** keeps retained nodes and baked renderer
  layers, blocks on backend events while idle, and wakes only for dirty work or
  the next timer deadline. This avoids unnecessary frames but does not by itself
  reduce the number of retained rows in a 100,000-row grid.

The viewport/data path starts with `VirtualExtentIndex` and
`planVirtualRange`. The reusable index prepares sparse measured corrections
when measurements change; scroll-time planning accepts a viewport, overscan,
and a hard materialization limit without sorting those measurements again. The
result contains geometry only for the bounded materialized range plus leading
and trailing spacer extents. It does not allocate or scan one record per
logical item.

`VirtualNodePool[Key]` consumes that plan for one dedicated item host. The pool
retains generation-checked Node IDs and mounted component lifecycle for keys
that stay materialized, mounts and disposes only entering or leaving keys, and
reorders the complete direct-child set when reverse scrolling or application
data order changes. Duplicate keys, shared hosts, foreign nodes, inconsistent
plans, and factories that create more than one direct root are explicit errors.
Partial factory failure removes every node added during the failed reconcile.
The pool remains bounded by the plan's materialization limit; at most another
bounded range can exist transiently while a disjoint replacement is prepared
before stale roots are torn down.

Leading and trailing spacers live outside the dedicated item host. Retained
refresh callbacks use normal node/component mutation and invalidation rather
than replaying component render procedures.

`VirtualFocusMemory[Key]` optionally attaches focus retention to that pool. When
a focused item leaves the materialized range, it records only one stable item
key, the focus-visible state, and a locator relative to the item root. An
explicit node `code` is the preferred locator and survives internal child
reordering; a child-index path is the fallback when no code is authored. A
missing or duplicate explicit code fails closed instead of redirecting focus to
another control. The interaction focus serial arms the record after disposal.
Any later focus operation changes that serial and cancels restoration, so an
item returning to the viewport cannot steal focus chosen by the user or the
application.

Logical collection semantics attach to the same stable item roots rather than
materialization slots. `VirtualNodePool` writes one-based `positionInSet` and
the plan's logical `setSize` after successful mount/refresh. Retained keys
therefore update their positions when application data is reordered, while a
100,000-item collection still exposes only the bounded accessible nodes that
are currently materialized. The pool does not guess List, Grid, Tree, or item
roles; component authors retain ownership of that meaning. The neutral tree,
AT-SPI snapshot/diff, and append-only C ABI carry the same range contract.

The runtime may still offer declarative construction helpers. Those helpers
should compile down to stable tree and style objects, and later updates should
be able to target those existing objects directly.

## Platform And Backend Policy

CBSS is Linux-first during the initial development phase. The primary runtime
backend is SDL3 on Linux x86_64.

Windows and macOS support are planned, but they should be treated as
contributor-validated platforms until active maintainers can run regular real
machine checks for them. They are not initial release blockers.

SDL3 is a project assumption for the first real backend, but SDL3 types and
handles should stay inside the SDL3 backend. The core should emit style,
layout, paint command, hit region, and input-state data that the SDL3 backend
consumes.

SDL3 path and link differences belong in:

```text
src/clay_board_style_system/backends/sdl3/config.nim
```

This is intentional. CBSS may be embedded into projects that already vendor
SDL3, so changing one configuration file should be enough to retarget the SDL3
headers and libraries.

## Frontend, Backend Logic, And Server Side Boundary

CBSS should be positioned as the frontend layer of a native application, not as
the place where every application concern must live.

Application projects may be organized into three layers:

```text
Frontend:
  CBSS UI, styling, layout, rendering, state, and event handling

Backend Logic:
  application use cases, domain logic, validation, data transformation,
  filesystem access, database access, external API calls, and integration code

Server Side / Transport:
  the mechanism that exposes backend logic to the frontend, such as process
  IPC, HTTP, WebSocket, local sockets, named pipes, or in-process calls
```

In this model, CBSS focuses on frontend design and interaction. When the UI
needs data or a side effect, it asks backend logic through a narrow client
boundary. If that backend logic needs external data, it performs the external
request itself or delegates to another service. CBSS does not need to directly
own database access, secret-bearing service calls, or business rules.

The backend logic may be written in any suitable language:

```text
CBSS frontend -> backend client -> Rust backend
CBSS frontend -> backend client -> Go backend
CBSS frontend -> backend client -> Python backend
CBSS frontend -> backend client -> Node backend
CBSS frontend -> backend client -> C# backend
CBSS frontend -> backend client -> Nim backend
```

The goal is to abstract language differences at the frontend/backend boundary.
Rust, Go, Python, Node, C#, Java, Kotlin, Nim, or other language communities
should be able to keep their backend logic in their preferred ecosystem while
using CBSS for the native frontend.

The CBSS-facing API should therefore be transport-neutral:

```text
BackendClient
  request(action, payload) -> response

Transport implementations
  process stdio JSON messages
  HTTP JSON
  WebSocket JSON
  Unix domain socket or Windows named pipe
  in-process Nim call
```

The first practical demo target should be process IPC over standard input and
standard output. It is simple to implement in many languages, does not require
port allocation, works well for local desktop applications, and keeps the
backend process easy to supervise from the frontend runtime or a dev launcher.

The protocol should start small and explicit. A JSON-RPC-like shape is enough
for early demos:

```json
{"id":1,"action":"todos.list","payload":{}}
{"id":1,"ok":true,"payload":[{"id":1,"title":"Write UI"}]}
```

HTTP and WebSocket transports remain planned alternatives. HTTP is familiar to
web engineers and useful when a backend already exists as a service. WebSocket
is useful for subscriptions and server-pushed events. In-process transport is
useful when the backend is Nim and the application wants no child process.

CBSS core should not depend on any one transport. The transport layer belongs in
a narrow integration module or examples first. Core style, layout, paint, input,
and runtime components should continue to work without a backend process.

This boundary should also guide examples:

```text
examples/multilang/
  rust_backend/
    ...
  nim_frontend/
    ...
  README.md
```

The demo should show that a backend can be implemented in another language
while CBSS remains focused on frontend code. The demo should avoid implying
that CBSS is only for Nim-only applications.

## Style Value Model

Numeric style values should be stored as floating point values internally.
This matches the practical shape of modern layout engines: the engine performs
layout in continuous coordinates and only snaps or rounds at renderer/backend
boundaries when necessary.

Units still matter. CBSS should parse and preserve enough unit information to
resolve values according to the relevant CSS definition or CBSS equivalent.

Examples:

```text
px:
  resolved directly into engine units

%:
  resolved against the relevant containing size

em:
  resolved against the current font size

rem:
  resolved against the root font size

fill:
  resolved by the layout algorithm

content:
  resolved through intrinsic measurement
```

Font-relative units require a font context. If a property uses a font-relative
unit and the required font setting is unavailable, CBSS should report a style
resolution error instead of silently guessing.

The public value model should distinguish the unit and the resolved float. A
typical shape is:

```nim
type
  UnitKind* = enum
    ukPx, ukPercent, ukEm, ukRem, ukFill, ukContent,
    ukMinContent, ukMaxContent, ukFitContent, ukAuto, ukNone

  LengthValue* = object
    kind*: UnitKind
    value*: float32

  ResolvedLength* = distinct float32
```

The exact names can change, but the split between specified value and resolved
float should remain.

Sizing properties preserve non-pixel values until layout. `width`, `height`,
their min/max forms, and logical aliases accept `%`, `auto`, `content`,
`min-content`, `max-content`, and `fit-content`. Percentages resolve against
the containing content box. Intrinsic values use a bottom-up measurement pass;
trees containing only fixed, percentage, and auto sizing skip that pass. The
uncommon non-pixel specifications live in a lazily allocated cold sizing
extension so fixed-pixel nodes retain the compact hot path.

The same used-value boundary applies to layout-dependent lengths outside box
sizing. Percentage gaps resolve on the container content axis; percentage and
intrinsic flex bases resolve on the parent's main axis; and signed percentage
insets resolve against the containing content width or height. These values use
the same cold extension and do not allocate it for fixed-pixel declarations.

## Pipeline

The core pipeline is:

```text
Element tree
  -> selector matching
  -> declaration collection
  -> style resolution
  -> layout calculation
  -> paint command generation
  -> hit region generation
  -> backend rendering
```

For a rule like:

```css
[id=button]:hover {
  background-color: #4b5563;
  padding: 8px 12px;
}
```

CBSS should treat the parts separately:

```text
selector:
  id = button
  requiredStates = { hover }

declarations:
  background-color = #4b5563
  padding = 8px 12px

properties:
  background-color
  padding
```

The selector decides whether the rule applies to an element. The properties
parse and apply values into computed style. The element implementation consumes
computed style during layout, paint, and hit testing.

## Extension Units

### Elements

Elements define what a node is and how it participates in layout, painting, and
hit testing.

Initial element kinds:

- `Box`
- `Text`
- `Image`

CBSS is not a GUI component library. It is a style system and UI substrate for
building native interfaces with CSS-like styling, event handling, state
integration, layout, and rendering backends.

Runtime elements cover the small set of primitive or near-primitive controls
needed to validate interaction semantics: Button, Checkbox, Dialog, Fieldset,
Form, Label, Progress, Radio, Select, Slider, TextArea, and TextInput. These
are intentionally thin and style-neutral.

Bundled widgets live under `runtime/widgets/`. They are lightweight reference
implementations, not the product surface of CBSS. Widgets such as CommandMenu,
ListBox, and Tabs exist to validate the style/event/runtime model and to provide
practical starting points. Applications and third-party libraries are expected
to define their own component design on top of CBSS.

Element implementations should consume computed style, not raw style rules.

```text
Box
  reads display, width, height, padding, margin, background-color, border,
  border-radius, overflow, gap, align, justify

Text
  reads color, font-size, font-family, line-height, text-wrap, text-align

Image
  reads width, height, object-fit, object-position, opacity
```

### Selectors

Selectors match style rules against elements.

CBSS should not assume a browser DOM selector model. In particular, `id`,
`class`, descendant selectors, and child selectors are not required as core
concepts just because CSS has them.

Initial selector support should focus on conditions that make sense for a native
GUI tree rendered through SDL or another backend:

- Element name
- Attribute
- State conditions
- Direct `NodeId` target for low-level rules
- Optional id
- Optional CBSS code
- Group

The primary user-facing path for hand-written components should be direct
`UiStyle` injection into `UiRoot` builders. `target(NodeId)` remains useful as a
low-level escape hatch and for internally mapping a style to a node. Optional
string ids, CBSS codes, and groups exist for external stylesheets,
design-source imports, generated code, testing, and debugging. A CBSS code is a
project-owned identifier string; it does not carry browser DOM `id` semantics
and does not need to be globally unique unless the application chooses that
discipline.

The ergonomic user-facing layer can wrap a UI tree in `UiRoot` and each `NodeId`
in a lightweight handle. A handle keeps direct identity while allowing familiar
assignments such as:

```nim
saveButton.onClick = proc(event: DispatchResult): EventOutcome =
  dispatch(Action(kind: SaveClicked))
  handledEvent()

rule(target(saveButton), [
  decl("background-color", colorValue(rgb(0.1, 0.35, 0.6)))
])
```

For nested UI, `UiRoot` provides block-style builders so the source
indentation mirrors the UI tree. This keeps parent management out of ordinary
application code while still producing explicit `NodeId` values internally.
Complex UIs are split into typed `CBSSComponent` subtypes with ordinary Nim
`render(self)` procedures. The checked `ui` render context supplies the current
root, `ui.mount()` composes child components, and `ui.box(self, ...)` registers
the component root. This keeps a declarative component shape without requiring
a TSX parser, a browser DOM, an untyped macro, or a virtual DOM. The complete
authoring contract is documented in [component-authoring.md](component-authoring.md).

Component files should normally own their own styles and events. Parent
components should place child components, not wire their internal events. When a
style must be customized, the parent imports or builds a `UiStyle` and passes it
as an argument. When style rules conflict, component-owned styles are resolved
after external parent styles so the component wins by default.

The component input policy is:

```text
style  : injectable and overridable when a caller wants to alter appearance
events : owned by the component file by default
params : optional values required to render or configure that component
```

Event names should stay generic and standard. Components should assign handlers
to JavaScript/TypeScript-style event slots such as `onClick`, `onInput`,
`onChange`, `onTextInput`, `onFocus`, or `onBlur`. `onTextInput` is the
lower-level text input signal; `onInput` and `onChange` are the component-level
value signals. Application-specific meaning belongs to the handler proc name or
the component name, not to a custom event field.

Event assignment on handles is replacement-oriented. Writing
`button.onClick = handler` should replace the previous user-owned click handler
for that node and event slot, while preserving internal component handlers such
as disabled-state guards. This keeps the component authoring model simple:
component libraries can export a styled part with a default handler, and
application code can inject a replacement behavior later without accumulating
stale handlers.

The lower-level registry API may still expose additive registration for cases
where a component deliberately wants listener-like behavior. That additive path
should be explicit. Public handle assignment should read like setting a method
or property, not appending an invisible event listener.

The public event-slot vocabulary should track familiar DOM/TSX names where they
make sense for native UI code. A supported slot must have a firing path through
backend input, CBSS synthesis, or explicit component dispatch. Deprecated names
or names without a plausible native firing path should stay unsupported until a
real implementation exists.

The event surface should borrow only broadly familiar Web/DOM/TSX naming
conventions. CBSS must not copy browser, React, or framework internals such as
SyntheticEvent, plugin dispatch, Fiber/reconciler behavior, hooks, or framework
source code. Implementation must stay independent and be expressed in CBSS
terms: SDL3/backend input, `Tree` hit testing, direct `NodeId` dispatch,
component-owned handlers, and explicit `emit`.

Each event kind must also declare how it is expected to fire:

```text
edmBackendInput       : emitted by a backend such as SDL3
edmCoreSynthetic     : synthesized by CBSS from backend input
edmComponentDispatch : emitted by a higher-level component implementation
```

This keeps JS/TS-familiar names available without silently promising that every
slot is fired by the SDL3 backend. Tooling and debug builds can inspect
`dispatchMode` and `bindingsNeedingComponentDispatch` to warn when a component
registers a slot that needs the component layer to emit it.

Pointer events are the primary backend input path. Mouse events are compatibility
slots over that path: for example, a `pointerDownEvent` can invoke `onMouseDown`
with the effective event kind changed to `iekMouseDown`. Component-semantic
events such as `onSubmit`, `onChange`, and media load events must be dispatched
by the component that owns that behavior until a dedicated backend or widget
layer implements them. Basic pointer-driven drag and drop is synthesized by
CBSS as `onDragStart`, `onDrag`, `onDragEnter`, `onDragOver`, `onDragLeave`,
`onDrop`, and `onDragEnd`; file drops or application-specific payloads still
belong to a backend or component layer.

Touch input is normalized through the same pointer path. A touch start can
invoke `onPointerDown` and `onTouchStart`; touch move/end/cancel similarly map
to pointer move/up/cancel plus their touch-specific slots. This lets components
prefer pointer handlers for most input while still allowing touch-specific
handlers when needed.

Text input has two layers. Backend text events feed `onTextInput`, and the
registry expands that event to `onBeforeInput`, `onInput`, and `onChange` in a
stable order for simple components. More complex text controls may bypass that
shortcut and explicitly emit value-level `onInput`/`onChange` only when their
internal value actually changes.

Per-component behavior notes for the runtime controls (TextInput, TextArea,
Label, Fieldset, Button, Checkbox, Radio, Select, Slider, Progress, Form,
Dialog, and the reference widgets Tabs, ListBox, CommandMenu) live in
[runtime-components.md](runtime-components.md). The shared component
conventions are defined in [design-decisions.md](design-decisions.md).

IME composition is modeled explicitly as `onCompositionStart`,
`onCompositionUpdate`, and `onCompositionEnd`. SDL3 text editing events can feed
the first two, and the committed text input can close composition before normal
text input is emitted. This keeps Japanese and other composed text entry on the
same event surface as Web-familiar UI code without copying browser internals.

Clipboard events are component/focused-target events. The backend may expose
clipboard text for an explicit paste command, but CBSS should not silently read
clipboard data during ordinary input processing. Copy, cut, and paste actions
should be dispatched by a focused text component or by an application shortcut
handler.

Keyboard events should expose Web-familiar modifier names on the event value:
`ctrlKey`, `altKey`, `shiftKey`, and `metaKey`. Backends can map native modifier
state into those fields while keeping shortcut policy in the application or
component layer.

`onScroll` is synthesized from wheel input. `onScrollEnd` is emitted when the
application or backend decides that scrolling has become idle:

```nim
discard ui.events.handle(inputState.finishScroll())
```

This keeps idle timing under the event loop or backend instead of baking a
platform-specific timer into core event dispatch.

Scroll containers retain their offset separately from computed style and
layout. `LayoutResult` publishes sparse immutable viewport/content metrics only
for scroll-capable boxes; `ScrollState` retains the current clamped offset by stable
`NodeId`. Wheel input updates only that state. Paint and hit testing then apply
the same ancestor clip and translation stack:

```text
layout child rect
  -> subtract each scrollable ancestor offset
  -> intersect each ancestor overflow clip
  -> emit paint command or hit region
```

Therefore ordinary scrolling is paint/hit work, not style/layout work. A
resize, content-size change, or overflow-mode change re-synchronizes metrics
and clamps the retained offset. Nested containers consume wheel movement at the
nearest container that can move in that direction and chain to an ancestor
once the inner container is at its boundary. `overscroll-behavior: contain` and
`none` stop that chaining on the resolved axis. Scrollbars are overlay paint
derived from the same retained metrics: `scrollbar-width` chooses normal,
thin, or hidden paint and `scrollbar-color` supplies thumb and track colors.
`scrollbar-gutter: stable` reserves content space during layout; the
`both-edges` form reserves the same thickness on the opposite edge so content
alignment does not jump when a classic scrollbar is present.
They do not reserve layout space or own a second coordinate model. Reserved
gutter layout, smooth motion, and kinetic motion remain separate consumers of
this mechanism. Paint and hit testing consume one shared scrollbar geometry;
thumb dragging and track page movement therefore cannot drift from the visible
shape or pass pointer input through to scrolled children. These interactions
emit `onScroll` and retain `onScrollEnd` under event-loop idle control.

Pointer capture is represented on `InteractionState`, not by copying a browser
element API. A component or event loop can capture and release pointer routing
explicitly:

```nim
discard ui.events.handle(inputState.capturePointer(handle.nodeId))
discard ui.events.handle(inputState.releasePointer().get)
```

While capture is active, pointer move/down/up dispatches route to the captured
node even when hit testing would target another node. Capture emits
`onGotPointerCapture` and `onLostPointerCapture`.

The component dispatch path is still a real firing path:

```nim
submitButton.onClick = proc(event: DispatchResult): EventOutcome =
  discard form.emit(iekSubmit)
  handledEvent()
```

If an event name is public, CBSS should provide one of these paths. Deprecated
or browser-only names should stay unsupported instead of being exposed as inert
slots.

Initial standard slots:

```text
onAbort
onAnimationCancel
onAnimationEnd
onAnimationIteration
onAnimationStart
onAuxClick
onBeforeInput
onBlur
onCancel
onCanPlay
onCanPlayThrough
onChange
onClick
onClose
onContextMenu
onCopy
onCueChange
onCut
onDblClick
onDoubleClick
onCompositionEnd
onCompositionStart
onCompositionUpdate
onDrag
onDragEnd
onDragEnter
onDragExit
onDragLeave
onDragOver
onDragStart
onDrop
onDurationChange
onEmptied
onEncrypted
onEnded
onError
onFocus
onFullscreenChange
onFullscreenError
onGotPointerCapture
onInput
onInvalid
onKeyDown
onKeyUp
onLoad
onLoadEnd
onLoadedData
onLoadedMetadata
onLoadStart
onLostPointerCapture
onMouseDown
onMouseEnter
onMouseLeave
onMouseMove
onMouseOut
onMouseOver
onMouseUp
onPaste
onPause
onPlay
onPlaying
onPointerCancel
onPointerDown
onPointerEnter
onPointerLeave
onPointerMove
onPointerOut
onPointerOver
onPointerUp
onProgress
onRateChange
onReset
onResize
onScroll
onScrollEnd
onSeeked
onSeeking
onSelect
onShow
onStalled
onSubmit
onSuspend
onTextInput
onTimeUpdate
onToggle
onTouchCancel
onTouchEnd
onTouchMove
onTouchStart
onTransitionCancel
onTransitionEnd
onTransitionRun
onTransitionStart
onVolumeChange
onWaiting
onWheel
```

`onDoubleClick` is the preferred TSX-style spelling. `onDblClick` exists as a
DOM-name compatibility alias. "Deprecated" in this event policy means deprecated
or effectively obsolete in modern Web/DOM/React/TSX usage, not deprecated by
CBSS or SDL3. Web-deprecated names such as `onKeyPress` and `onMouseWheel` are
not part of the supported CBSS event surface; use `onKeyDown`/`onKeyUp` and
`onWheel`.

String ids, CBSS codes, groups, and attributes are matching symbols only. They
must not represent runtime identity or object sameness. Runtime identity belongs
to `NodeId`.

In CBSS, two nodes with the same id, code, group, or attributes are still
separate instances. Matching symbols can say "apply the same styling intent
here" or "find this application-owned label"; they cannot say "this is the same
object."

Parent/child relationships exist in the element tree for layout and coordinate
systems, but parent-child selectors should not be part of the initial selector
model. Contextual styling should prefer explicit variables, inherited style
values, state, attributes, or higher-layer rule generation. That keeps style
matching cheaper, less DOM-like, and easier to reason about in native GUI code.

Selectors should not apply style values directly. They should only answer
whether a rule matches a node and how specific that match is.

## Instances, Copies, And Shared Styling

CBSS should treat every node in the element tree as a distinct instance.

Even when two UI parts come from the same higher-level component definition,
they are not the same thing once they exist in the rendered tree. They have
different positions, layout constraints, states, hit regions, and potentially
different inherited variables.

The useful operation is therefore not "style the same component in multiple
places." The useful operation is:

```text
Apply the same styling intent to multiple distinct instances.
```

This can be represented through direct `NodeId` targets, shared group rules,
attributes, or higher-layer component expansion.

```text
Component definition:
  describes how to create nodes

Node instance:
  has its own NodeId, layout, state, hit region, and computed style

Shared style:
  can be referenced or matched by many node instances
```

This distinction matters because CBSS is not a DOM. In a native GUI tree there
are object instances, copies, references, and generated nodes. If two buttons
appear in different coordinates, they are separate nodes even if they came from
the same source definition.

For production use, style sharing should avoid unnecessary duplication while
preserving instance identity. Good implementation strategies include:

- Immutable style rules shared across many nodes
- Groups matched by multiple node instances
- Higher-layer component templates that generate separate CBSS nodes
- Copy-on-write or cached computed style where it is safe

Style sharing must not collapse distinct nodes into one runtime object. Layout,
state, hit testing, focus, hover, active state, and event routing all depend on
per-instance identity.

### Style Properties

Style properties are the unit for adding CSS-like behavior.

Examples:

- `display`
- `width`
- `height`
- `min-width`
- `max-width`
- `padding`
- `margin`
- `gap`
- `background-color`
- `border`
- `border-radius`
- `color`
- `font-size`
- `font-family`
- `line-height`
- `overflow`
- `opacity`

Each property should own:

- Name
- Accepted value syntax
- Parsing
- Validation
- Computed-style application
- Invalidation metadata

Properties should not decide which elements they apply to unless the restriction
is fundamental. In most cases, a property should write to computed style and let
each element decide whether that field matters.

For example, `background-color` should write a color into computed style. `Box`
may use it during paint. `Text` may ignore it. A future element may use it
differently.

## State Pseudo-Classes

State pseudo-classes should initially be represented as selector condition
flags, not as independent property behavior.

Good candidates:

- `:hover`
- `:active`
- `:focus`
- `:disabled`
- `:checked`
- `:selected`

Internal representation can be simple:

```text
selector:
  id = button
  requiredStates = { hover }
```

Then `[id=button]:hover` matches when:

```text
node.id == "button"
and node.states contains hover
```

The property does not need to know that the rule came from `:hover`.

```text
Selector/rule:
  decides when declarations apply

Property:
  parses and applies accepted declarations
```

More structural pseudo-classes can be added later:

- `:first-child`
- `:last-child`
- `:nth-child`
- `:empty`

However, structural pseudo-classes should not be core selector features by
default. In CBSS, UI nodes are usually generated from arrays or explicit data
structures. The generating code already knows which item is first, last, odd,
even, empty, selected, or grouped.

Therefore structural selector behavior should usually be expressed through
array operations, generation-time metadata, groups, attributes, or helper
methods.

```nim
for i, item in items:
  nodes.add(listItem(
    item,
    group =
      if i == 0: "first"
      elif i == items.high: "last"
      elif i mod 2 == 0: "even"
      else: "odd"
  ))
```

CBSS or a higher layer may provide convenience methods that read like structural
selectors, but they should compile down to explicit metadata instead of making
the style resolver infer tree structure.

```nim
items
  .markFirstLast()
  .markOddEven()
  .mapIt(listItem(it))
```

Logical selectors can also be deferred:

- `:not(...)`
- `:is(...)`
- `:where(...)`

Pseudo-elements should be treated as a separate later topic:

- `::before`
- `::after`
- `::selection`

## Suggested Directory Structure

The implementation should make extension boundaries visible in the file tree.

```text
src/
  cbss.nim

  core/
    node.nim
    rule.nim
    declaration.nim
    computed_style.nim
    registry.nim
    resolver.nim
    layout_tree.nim
    paint_command.nim
    hit_region.nim

  elements/
    box/
      mod.nim
      layout.nim
      paint.nim
      hit.nim

    text/
      mod.nim
      measure.nim
      layout.nim
      paint.nim

    image/
      mod.nim
      layout.nim
      paint.nim

  selectors/
    element_name.nim
    attribute.nim
    id.nim
    group.nim
    state.nim
    style_tag.nim

  properties/
    display.nim
    width.nim
    height.nim
    min_width.nim
    max_width.nim
    margin.nim
    padding.nim
    gap.nim
    background_color.nim
    border.nim
    border_radius.nim
    color.nim
    font_size.nim
    font_family.nim
    line_height.nim
    overflow.nim
    opacity.nim

  text/
    cosmic_text_bridge/

  backends/
    sdl3/
    blend2d/
    skia/
```

This structure is intentionally more important than the exact filenames. The
main point is that new behavior has an obvious home:

```text
New element kind:
  elements/<name>/

New selector behavior:
  selectors/<name>.nim

New style property:
  properties/<name>.nim

New renderer backend:
  backends/<name>/
```

## Registry

The first implementation can use an internal registry instead of a public plugin
system.

```nim
registerElement(boxElement)
registerElement(textElement)
registerElement(imageElement)

registerSelector(elementNameSelector)
registerSelector(attributeSelector)
registerSelector(roleSelector)
registerSelector(stateSelector)
registerSelector(groupSelector)

registerProperty(displayProperty)
registerProperty(paddingProperty)
registerProperty(backgroundColorProperty)
```

This keeps the design modular without committing too early to dynamic plugins,
ABI stability, or third-party loading.

The implementation should be as declarative as practical. Elements, selectors,
style properties, and style rules should be described as data or small
capability records that can be passed into the engine.

```nim
type
  EngineConfig* = object
    elements*: seq[ElementImpl]
    selectors*: seq[SelectorImpl]
    properties*: seq[PropertyImpl]
    styleSheets*: seq[StyleSheet]

let engine = newEngine(EngineConfig(
  elements: defaultElements(),
  selectors: defaultSelectors(),
  properties: defaultProperties(),
  styleSheets: @[appStyles]
))
```

This gives CBSS a dependency-injection-friendly shape. A host application,
backend, test, or higher-level GUI library can choose which properties,
selectors, and elements to provide.

From the author's point of view, this still feels like applying CSS to matching
UI parts:

```text
Declare style rules.
Declare or generate node instances.
Resolve matching rules against those instances.
Apply property declarations into computed style.
```

The implementation flow differs from browser CSS, but the design intent is the
same: describe visual behavior separately, then apply it to the UI instances
that match.

For production use, the registry should stay small, predictable, and easy to
audit. It should not become a place where property-specific behavior accumulates.
Property-specific parsing, validation, and computed-style application should
remain in the property module.

As the number of modules grows, generated indexes are preferred over large
hand-edited central files. This reduces merge conflicts and makes property
addition/removal safer.

## Computed Style Shape

`ComputedStyle` should be typed and grouped by concern instead of becoming an
unstructured string-keyed map.

Recommended shape:

```nim
type
  ComputedStyle* = object
    layout*: ComputedLayoutStyle
    box*: ComputedBoxStyle
    text*: ComputedTextStyle
    image*: ComputedImageStyle
    effects*: ComputedEffectsStyle
```

This structure is more suitable for production use:

- Layout can read layout fields without parsing dynamic values.
- Paint can read paint fields without selector knowledge.
- Text measurement can receive the text subset directly.
- Backends can consume normalized values.
- Invalidations can be tracked by category.

The grouped structure should still preserve loose coupling. Adding or removing a
property should usually affect one property module and one computed-style group,
not the entire engine.

## Style Composition And Merge

CBSS should support explicit style composition.

This is the native-GUI alternative to relying on DOM parent-child selectors for
contextual styling. Instead of asking the style matcher to walk ancestors and
infer context, a higher layer can merge style inputs and inject the resulting
style context into a subtree or node group.

```text
base style
  + theme style
  + component style
  + variant style
  + state style
  + local override
  -> merged style context
  -> resolve against node instances
```

This keeps the data flow explicit:

```text
Parent or host layer:
  creates style context
  merges contextual styles
  passes the merged context into child node generation or resolution

CBSS:
  applies declarations from the injected context
  resolves properties into computed style
  performs layout, paint, and hit testing
```

From the author's point of view, this can still express "children inside this
panel should look this way." The difference is that the context is passed
explicitly instead of discovered through a descendant selector.

Example shape:

```nim
let base = styleBlock(@[
  decl("font-size", px(14)),
  decl("color", rgb(32, 36, 42))
])

let panel = styleBlock(@[
  decl("background-color", rgb(245, 247, 250)),
  decl("padding", px(12))
])

let danger = styleBlock(@[
  decl("color", rgb(180, 32, 32))
])

let panelContext = mergeStyles(base, panel)
let dangerContext = mergeStyles(panelContext, danger)
```

Then the merged context can be injected:

```nim
resolveStyles(tree, styleContext = panelContext)
resolveStyles(dangerSubtree, styleContext = dangerContext)
```

Merge behavior should be deterministic and property-aware.

Recommended merge model:

```text
Declaration order:
  default behavior is that later declarations override earlier declarations for
  the same property

Shorthands:
  expanded through the owning property module before or during merge when the
  shorthand has sub-property slots

Unset values:
  no declaration means no override

Explicit reset:
  use a distinct value such as initial, inherit, unset, or CBSS reset semantics

Inherited properties:
  flow through the injected style context

Non-inherited properties:
  only apply when explicitly present in the merged declarations
```

The default rule is simple: the same property is overwritten by the later
declaration. There is no numeric addition for repeated properties unless the
property explicitly defines a relative merge operation.

```text
color: red
color: blue
-> color: blue
```

However, the merge policy should be defined by each property. Some properties
only support overwrite. Some support inheritance. Some may support relative
operations.

```text
overwrite:
  replace the previous value

inherit:
  read from parent or injected style context

initial:
  use the property's initial value

unset:
  inherit for inherited properties, otherwise initial

relative:
  compute from the parent or injected context, such as parent + 4px
```

Relative operations are useful for native GUI styling, but they must be explicit
and property-owned.

```text
parent padding = 8px
child padding = parent + 4px
-> child padding = 12px
```

The exact syntax can be decided later. Internally, it should be represented as a
style operation rather than as an already-resolved float.

```nim
type
  MergeMode* = enum
    mmOverwrite
    mmInherit
    mmInitial
    mmUnset
    mmRelative

  StyleOperation* = object
    mode*: MergeMode
    value*: StyleValue
```

Property modules decide which modes they accept and how those modes are
resolved. For example, `color` may support overwrite and inherit. `padding` may
support overwrite, inherit, and relative operations. Unsupported operations
should be rejected by the static style checker when possible, or reported as
diagnostics for dynamic style input.

Shorthand properties are the main exception in shape, not in principle. They may
expand into sub-property slots, and later declarations override the slots they
target.

```text
padding: 8px
padding-left: 12px
-> top/right/bottom = 8px
-> left = 12px
```

That logic belongs to the owning property module, not a central string map.

Function-valued style values are supported as a trusted-code escape hatch for
Nim UI libraries and application code.

```nim
decl("padding-left", computedValue(proc(): StyleValue = px(theme.spacing.large)))
```

Regular `resolveStyles` rejects function values. Code that intentionally accepts
Nim closures must call `resolveTrustedStyles`, making the trust boundary explicit.
External themes, user-authored style data, and unverified plugins should be
loaded through data-only declarations and must not be converted into
`computedValue` or `functionValue` closures.

```text
properties/padding.nim:
  parses padding shorthand
  expands slots
  merges side-specific declarations
  writes ComputedBoxStyle.padding
```

The merge system should be usable through dependency injection:

```nim
type
  StyleContext* = object
    variables*: Variables
    declarations*: ResolvedDeclarationSet
    inherited*: InheritedStyle

  ResolveOptions* = object
    styleContext*: StyleContext
```

This makes contextual style explicit, testable, and cacheable. It also keeps
parent-child styling from becoming a selector feature that couples style
matching to tree traversal.

## Property Phases

Properties affect different engine phases. This should be explicit so the engine
can invalidate the right work later.

```text
display:
  tree participation, layout

width / height:
  layout

padding / margin / gap:
  layout, paint

background-color:
  paint

color / font-size / font-family:
  text measurement, text paint, inheritance

overflow:
  layout, clipping, paint, hit testing

opacity:
  paint
```

Early implementations can recompute broadly. The metadata still matters because
it keeps the architecture ready for caching, dirty flags, and partial
invalidation.

## Layout Direction

CBSS layout should feel familiar to developers who use modern CSS Flexbox.

### Box Sizing Contract

`LayoutBox.rect` always represents the outer border box. The authored
quantitative `width`, `height`, min/max constraints, and `flex-basis` values
are interpreted according to `box-sizing` before layout stores that rectangle:

- `content-box` is the default and adds resolved padding plus visible border
  widths around the authored sizing box.
- `border-box` treats the authored value as the outer size and clamps it to at
  least the combined padding and visible border widths.
- child percentages, alignment, absolute positioning, overflow, and clipping
  use the content box derived from the same outer rectangle.
- automatic and intrinsic dimensions produce the same natural outer size in
  either mode because `box-sizing` does not change non-quantitative sizing
  keywords such as `auto`, `min-content`, and `max-content`.

CBSS does not silently apply a universal `border-box` reset. Applications and
component libraries that prefer fixed outer dimensions can inject one explicit
`element(nkBox)` rule, as the bundled demos do. This keeps the engine default
familiar to CSS while making the application policy visible and replaceable.

### Multi-Line Flex Contract

Flex containers collect in-flow children into explicit lines before flexible
length resolution. A definite main size, including an effective maximum size,
sets the wrapping boundary. Each line independently freezes and redistributes
grow or shrink space against item min/max constraints, then applies
`justify-content`. Cross-axis placement applies `row-gap` or `column-gap` once
between lines and distributes remaining space through `align-content`.

`wrap-reverse` mirrors completed line positions across the cross axis; it does
not reorder nodes, paint commands, hit regions, focus traversal, or
accessibility semantics. Absolute and `display:none` children do not create
lines. A single line uses the full available cross size and ignores
`align-content`, matching the useful Flexbox behavior without importing DOM
layout quirks. Overflow metrics use the same resolved line geometry as paint
and hit testing, so wrapped scroll content does not need a second estimate.

`row-reverse` and `column-reverse` independently swap main-start and main-end.
Line membership is still collected in order-modified logical order, while each
line is placed from the opposite physical edge. This is a coordinate transform,
not a mutation of the retained tree or a second reversal of paint and hit
order. It therefore composes with `wrap-reverse` without changing keyboard or
assistive-technology reading order.

The goal is not DOM or browser compatibility. CBSS should reproduce what Flexbox
is trying to achieve for application UI: predictable distribution, alignment,
sizing, and wrapping behavior. It can simplify browser-specific details when a
native GUI model has a cleaner answer.

Common Flexbox mental models should transfer:

- Main axis and cross axis
- Row, row-reverse, column, and column-reverse direction
- Gap
- Flex grow, shrink, and basis
- Min/max constraints
- Content sizing
- Alignment and justification
- Overflow behavior

Layout quality is a product feature. Frontend-minded users are sensitive to
whether flex-like layout feels right, so this area should be designed carefully
rather than treated as a minimal placeholder.

CBSS does not need to reproduce DOM mutation behavior, anonymous flex items,
browser inline layout interactions, or compatibility quirks. The important part
is that a developer can express the same UI intent and get an unsurprising
native layout result.

The root layout constraint usually comes from the backend window size. With SDL,
window creation and resize events provide the size that CBSS uses to recompute
the root layout:

```text
SDL window size
  -> root layout constraints
  -> CBSS flex-like layout
  -> paint commands
  -> SDL rendering
```

This keeps the layout engine deterministic and independent of the event loop.

## Renderer Backend Boundary

The first backend may be SDL, but CBSS core should remain renderer-independent.

Renderer-independent means:

```text
CBSS core:
  computes style
  computes layout
  emits paint commands
  emits hit regions

SDL backend:
  opens windows
  receives input events
  converts paint commands to SDL drawing calls or GPU work
  owns SDL handles and renderer resources
```

The core should not call SDL directly. Keeping this boundary makes it possible
to add Skia, Blend2D, Metal, Vulkan, or test backends later without rewriting
style resolution or layout.

This boundary also helps production use: layout and style behavior can be tested
without opening a window, and backend-specific bugs stay localized.

## Hit Testing Boundary

SDL can provide pointer coordinates and input events, but it does not know which
CBSS element those coordinates correspond to.

CBSS should therefore generate hit regions from layout results. The backend can
feed pointer coordinates into CBSS hit testing and receive the matched node or
region data.

Expected split:

```text
SDL:
  event loop
  pointer coordinates
  keyboard events
  window focus

CBSS:
  node geometry
  clipping-aware hit regions
  z-order-aware hit ordering
  mapping from point to NodeId or hit region id

Higher GUI layer:
  click behavior
  drag behavior
  widget semantics
  application event handling
```

This keeps SDL usage conventional while still giving a higher GUI layer enough
information to implement widgets and interaction.

## Event Handler Boundary

CBSS has the lower-level pieces for interaction: node state, hit regions, hit
testing, `pointer-events`, and hover updates. It should not own application
callbacks as part of the style/layout core. Event handlers belong to the GUI
library or application layer that composes CBSS nodes into widgets.

The intended split is:

```text
Backend:
  reads SDL or platform events
  normalizes them into CBSS input events

CBSS input layer:
  updates hover/active/focus states where requested
  hit-tests pointer coordinates against current hit regions
  returns a dispatch result with target NodeId and local coordinates

Higher GUI layer:
  stores handlers keyed by NodeId or widget instance
  invokes callbacks
  decides whether to rebuild style/layout/paint after state changes
```

The first event model should be direct-target dispatch, not DOM-compatible
bubbling/capture. CBSS nodes are copied or referenced values with explicit
`NodeId`; a DOM identity model is not required for native GUI use. If a higher
layer wants bubbling, it can walk the CBSS parent chain or its own widget tree
after receiving the direct target.

Initial event data should be value-oriented:

```nim
type
  InputEventKind* = enum
    iekAbort,
    iekBeforeInput,
    iekChange,
    iekClick,
    iekInput,
    iekPointerMove,
    iekPointerDown,
    iekPointerUp,
    iekKeyDown,
    iekKeyUp,
    iekTextInput,
    iekFocus,
    iekBlur,
    # See input/events.nim for the complete JS/TS-style slot set.

  InputEvent* = object
    kind*: InputEventKind
    position*: Option[Vec2]
    button*: Option[int]
    key*: Option[string]
    text*: Option[string]

  DispatchResult* = object
    target*: Option[NodeId]
    local*: Option[Vec2]
    event*: InputEvent
```

CBSS should avoid storing Nim closures inside the core tree. That keeps tree
data serializable, easier to diff, easier to test, and less likely to create
ARC lifetime surprises. A GUI layer can maintain a separate handler table:

```nim
type
  EventHandler* = proc(event: DispatchResult): EventOutcome {.closure.}

handlerTable[NodeId] = EventHandler
```

The result independently records handled state, propagation control, and
default-action prevention. A higher layer may also enqueue application
commands without conflating those effects.

Pseudo-selectors such as `:hover`, `:active`, and `:focus` should be represented
as node state flags. Event dispatch updates those flags; selectors only read
them. This keeps properties, selectors, hit testing, and event handling loosely
coupled.

CBSS may keep a small interaction state for input bookkeeping, such as the node
pressed during pointer down and the currently focused node. That is not the same
as application state. Application state should stay outside CBSS so different
UI runtimes can choose their own model:

```nim
# React-like local state:
var count = 0
handlers.onClick(button, proc(event: DispatchResult): EventOutcome =
  inc count
  handledEvent()
)

# Redux-like external store:
handlers.onClick(button, proc(event: DispatchResult): EventOutcome =
  appStore.dispatch(Action(kind: SaveClicked, node: event.target.get))
  handledEvent()
)
```

This leaves room for a higher UI layer to provide hooks, signals,
reducers, atoms, or a retained widget runtime without forcing those concepts
into the CBSS style/layout core.

## State Management Policy

CBSS should distinguish four kinds of state:

```text
Style state:
  hover, active, focus, disabled, checked, selected
  stored as ElementState flags on nodes
  read by selectors

Interaction state:
  pressed target, focused target, pointer bookkeeping
  stored in a small runtime object such as InteractionState
  used to synthesize events like click from pointer down/up

Application state:
  counters, form models, selected records, async data, domain data
  owned by the application or UI runtime
  never required by the CBSS core tree

Derived render state:
  resolved styles, layout results, paint commands, hit regions
  recomputed from tree + style + application-provided inputs
```

CBSS should own the first two only. Application state should be external. That
keeps CBSS usable with several state styles:

```nim
# Local closure state
var open = false
handlers.onClick(toggleButton, proc(event: DispatchResult): EventOutcome =
  open = not open
  handledEvent()
)

# Reducer/store state
handlers.onClick(saveButton, proc(event: DispatchResult): EventOutcome =
  appStore.dispatch(SaveClicked())
  handledEvent()
)

# Signal/atom style
handlers.onClick(toggleButton, proc(event: DispatchResult): EventOutcome =
  expandedSignal.set(not expandedSignal.get())
  handledEvent()
)
```

The recommended runtime loop is:

```text
platform event
  -> normalize to InputEvent
  -> CBSS processInput updates interaction/style state
  -> EventRegistry invokes handlers
  -> application state may change
  -> UI layer rebuilds or patches Tree/StyleSheet inputs
  -> resolve styles
  -> compute layout
  -> build paint commands and hit regions
  -> backend renders
```

The CBSS style/layout core does not require React-like Hooks, Redux-like Stores,
or a particular signal library. It remains the lower-level engine that accepts
the resulting tree, Styles, event handlers, and state flags.

The CBSS package also includes a first-party frontend runtime as an opt-in Nim
module above that lower-level boundary. It extracts the useful frontend
capabilities -- retained local state, typed Stores and Actions, selected
subscriptions, owned effects, asynchronous Commands, and Cue orchestration --
without adopting Hook ordering, dependency arrays, virtual-DOM replay, or
Redux-specific APIs. Applications may still use external state systems through
ordinary Nim and Provider boundaries. The complete contract and delivery order
are documented in
[Frontend Runtime Design](frontend-runtime.md).

The low-level pieces should not be the primary authoring surface. Most
developers should not have to manually call `processInput`, bind an
`EventRegistry`, track a `needsRebuild` flag, and rebuild layout in application
code. Those steps are runtime responsibilities.

The current low-level pieces live in:

```text
src/clay_board_style_system/input/events.nim
src/clay_board_style_system/runtime/state_runtime.nim
src/clay_board_style_system/runtime/providers.nim
```

A higher-level CBSS runtime or UI layer should hide that loop and expose a
smaller app shape. A single state object is useful as the smallest example:

```nim
type
  AppState = object
    runClicks: int

  AppActionKind = enum
    akRunClicked

  AppAction = object
    kind: AppActionKind

proc update(state: var AppState; action: AppAction) =
  case action.kind
  of akRunClicked:
    inc state.runClicks

proc view(state: AppState; dispatch: DispatchProc[AppAction]): UiNode =
  box(id = "surface"):
    button(
      text = "Run",
      onClick = proc() = dispatch(AppAction(kind: akRunClicked))
    )
    text("Run clicked " & $state.runClicks & " time(s)")

runApp(
  initialState = AppState(),
  update = update,
  view = view
)
```

Real applications should not be forced into one state object. The runtime should
also support multiple state providers or context values:

```nim
type
  ThemeState = object
    density: float32
    primaryColor: Color

  RouteState = object
    currentScreen: string

  UiState = object
    selectedTab: string
    dialogOpen: bool

  AppStore = object
    # application-owned domain state

proc view(ctx: ViewContext): UiNode =
  let theme = ctx.use(ThemeState)
  let route = ctx.use(RouteState)
  let ui = ctx.use(UiState)
  let store = ctx.use(AppStore)

  box(id = "surface"):
    button(
      text = "Run",
      onClick = proc() =
        store.dispatch(RunClicked(screen: route.currentScreen))
    )
    text("Selected tab: " & ui.selectedTab)

runApp(
  providers = providers([
    provide(ThemeState(density: 1.0, primaryColor: rgb(0.2, 0.5, 0.9))),
    provide(RouteState(currentScreen: "home")),
    provide(UiState(selectedTab: "overview")),
    provide(appStore)
  ]),
  view = view
)
```

In this shape, `ViewContext` is a dependency injection boundary for UI state and
services. It can carry immutable values, mutable stores, signals, atoms,
reducers, commands, or service clients. CBSS still does not need to understand
those models; it only needs the UI layer to produce tree, style, and handler
data for the current frame.

Internally, `runApp` can own the event registry, interaction state, dirty flag,
style resolution, layout recomputation, paint command generation, hit region
generation, and backend rendering. The public API should make state changes and
UI declaration obvious; the runtime should handle the mechanical loop.

This also makes external service integration cleaner. A Figma-like importer or
MCP workflow can generate UI structure and handler stubs without needing to
choose the application's state management library.

## Text Handling

CBSS should treat text as a first-class primitive, but it does not need to own a
complete text engine at the beginning.

An external library such as `cosmic-text` can carry most of the text workload.
CBSS should wrap it behind a narrow text service instead of recreating shaping,
font fallback, and glyph layout early.

```text
CBSS core:
  asks TextEngine for text measurement
  emits text paint commands

Text service:
  shapes text
  performs font fallback
  produces glyph positions
  optionally rasterizes glyphs
```

The initial implementation exposes a small `TextEngine` interface for layout
measurement, caret and hit-test geometry, and versioned font-unit metrics:

```text
src/clay_board_style_system/text/text_engine.nim
```

Font registration and fallback policy are represented separately:

```text
src/clay_board_style_system/text/font_registry.nim
```

Applications can enable system font discovery, register bundled font files, add
memory-backed fonts, and define fallback families. `font-family` resolves to an
ordered family list, not just a single string, so a text engine can perform
CSS-like fallback without exposing browser concepts in the core API.

`ex` and `ch` resolution does not make the style resolver depend on a concrete
font library. A `FontUnitMetricsResolver` receives the resolved text style and
returns the selected font's x-height and `0` glyph advance. `TextEngine` can
produce this resolver for a fixed `FontRegistry`:

```nim
let metrics = textEngine.fontMetricsResolver(fonts)
let resolved = resolveTreeStyles(
  tree,
  sheets,
  defaultProperties(),
  diagnostics,
  fontMetricsResolver = metrics
)
```

The contract is versioned and rejects non-positive, non-finite, or incompatible
results. Missing metrics use the CSS-defined `0.5em` fallback. The cosmic-text
adapter caches results by font configuration so repeated nodes do not reshape
the `0` glyph or reopen font data. Root variants `rex` and `rch` are established
from the root text style and remain stable during descendant and subtree
resolution.

The default engine matches SDL3 debug text behavior so the current demo remains
stable. Higher quality text engines should be added as adapters, not wired into
the layout algorithm directly.

Renderer-specific text drawing stays in the renderer backend. For SDL3 debug
text, that adapter lives in:

```text
src/clay_board_style_system/backends/sdl3/text_debug.nim
```

If `cosmic-text` is used, it should be hidden behind a CBSS-owned C ABI or
native adapter. The public CBSS model should not expose `cosmic-text` types.
That keeps the text implementation replaceable.

The expected `cosmic-text` adapter responsibilities are:

```text
read FontRegistry
  -> load system, file-backed, and memory-backed fonts
  -> map ComputedTextStyle to cosmic text attributes
  -> resolve effective font fallback
  -> shape and measure text
  -> produce rasterized text bitmaps for backend rendering
```

The current Rust bridge maps these CBSS fields into `cosmic-text` measurement
and bitmap rasterization:

```text
font-size / line-height -> Metrics
font-family             -> Family and font fallback input
font-weight             -> Attrs weight
font-style              -> Attrs style
font-stretch            -> Attrs stretch
letter-spacing          -> Attrs letter spacing
font-feature-settings   -> FontFeatures
font-variation-settings -> common axes: wght, wdth, ital, slnt
font-kerning            -> kern feature
font-variant-ligatures  -> liga/clig/dlig/hlig/calt features
font-variant-caps       -> smcp/c2sc/pcap/c2pc/unic/titl features
font-variant-numeric    -> lnum/onum/pnum/tnum/frac/afrc/ordn/zero features
font-variant-east-asian -> jp78/jp83/jp90/jp04/smpl/trad/fwid/pwid/ruby features
font-variant-position   -> subs/sups features
font-size-adjust        -> adjusted font size before measurement/rasterization
```

Arbitrary variation axes are preserved in CBSS style data and carried through the
C ABI request, but only the common axes above are mapped into `cosmic-text`
attributes today. Full arbitrary-axis application belongs with later glyph
run/rasterization work if the chosen text stack exposes that control cleanly.

The SDL3 renderer owns renderer-local text texture caching. The cache key is
derived from the text content, effective font families, computed font features,
variation settings, metric inputs, wrap mode, and paint color. This keeps
`cosmic-text` shaping/rasterization reusable across frames without making the
core layout or paint command model depend on SDL texture handles. A later atlas
or glyph-run cache can replace this renderer-local cache without changing the
public CBSS style model.

CBSS core should own the stable style model. The adapter should own font-system
handles, caches, shaping buffers, and any Rust/C ABI resource lifetime.

## Higher UI Layers

CBSS should remain useful to GUI libraries built above it. The core should
provide primitive element trees, style resolution, layout, text measurement,
paint commands, hit regions, input dispatch, and renderer adapters without
requiring one specific component model or application runtime.

CBSS should therefore be a public foundation for native GUI work, not merely a
private implementation detail for one higher-level API.

## Embedded Native Components

CBSS should consider a first-class way to embed Nim-authored native components
inside the UI tree. The goal is not to make CBSS itself a game engine, media
engine, chart engine, or 3D engine. The goal is to let those things be written
as normal Nim components and placed inside CBSS layouts.

This is closer to component composition than document embedding. A game view,
video player, chart, map, or 3D viewer should be usable like any other CBSS
component from the application author's perspective.

Possible primitive names for the low-level host element:

```text
surface
viewport
renderSlot
nativeLayer
```

`iframe` should not be used as the CBSS API name because it implies separate web
document embedding and isolation. `surface` or `viewport` is clearer for a
native component that participates in the same Nim application.

Conceptual API shape:

```nim
type
  GameView = ref object
    world: GameWorld

proc render(view: GameView; ctx: NativeComponentContext) =
  view.world.update(ctx.dt)
  view.world.render(ctx.renderer, ctx.rect)

proc gamePanel(ui: UiRoot; view: GameView) =
  ui.nativeComponent(
    view,
    style = uiStyle([
      decl("width", percent(100)),
      decl("height", px(480)),
      decl("overflow", keyword("hidden")),
      decl("border-radius", px(8))
    ])
  )
```

Application code can then compose it normally:

```nim
appShell:
  headerBar()
  gamePanel(gameView)
  inspectorPanel()
```

This would allow CBSS applications to use:

```text
Nim game components
Nim video player components
camera preview components
3D model viewers
custom chart or graph components
map widgets
terminal or editor components
audio visualizers
```

The responsibility split should be explicit:

```text
CBSS:
  component placement in the UI tree
  layout box and constraints for the component
  border, radius, clip, opacity, transform, z-index
  pointer and keyboard routing
  focus and cursor state
  overlay UI above the native component
  invalidation domain for the component

Embedded Nim component:
  internal component state
  pixel rendering inside the supplied rect
  media/game/chart timing
  resource ownership specific to that component
  optional event handling for events routed to its box
```

For games, this means CBSS should not require the gameplay loop, physics,
sprite management, map system, AI, or game-specific rendering to be expressed as
CSS-like declarations. Those belong in ordinary Nim and the chosen backend
library. CBSS can still place the game component and provide a strong HUD,
menu, inventory, dialog, and settings layer around or above it.

For video players, the component can own media decoding and frame timing while
CBSS reserves the playback rectangle and draws controls, captions, overlays,
menus, progress bars, and focus states using the same style system.

Native component invalidation should integrate with the dirty-domain model:

```text
component content changed -> resourceDirty or paintDirty
component animation/timeline active -> animationDirty
component size changed -> layoutDirty + resourceDirty
component input capture changed -> hitDirty or paintDirty
```

The implementation should avoid forcing a full CBSS tree rebuild on every
component frame. A continuously updating video player or game component may need
repeated present calls, but style resolution, layout, and hit-region generation
should remain stable unless the component element or surrounding UI changes.

Open design questions:

```text
Does the native component render before normal child overlays, after them, or in
a dedicated background pass?

Should the component receive raw backend handles, an abstract render context, or
backend-specific adapters?

How should clipping and border-radius be applied when the component renderer is
not the same renderer used by CBSS?

Can a component opt into pointer capture while still allowing CBSS overlays
above it to receive input?

Should native components be allowed to request continuous frames independently
from the rest of the UI?
```

The near-term design goal is to keep the concept planned and compatible with
the runtime architecture. The first implementation can be SDL3-specific and
small, as long as the public model does not prevent later non-SDL adapters.

SDL3 is a deliberate fit for this direction. CBSS should not be framed as using
SDL only to imitate a desktop GUI toolkit. SDL's value is its broad native
runtime surface: applications, games, media tools, creative tools, editors, and
visualization software can all share the same windowing, input, rendering, and
platform foundation.

That means CBSS can present itself as a CSS-like UI and styling foundation for
wide native software, not only business GUI applications:

```text
application UI:
  forms, settings, dashboards, admin tools

game UI:
  HUDs, menus, inventory, pause screens, debug overlays

media UI:
  video controls, timelines, subtitles, overlays

creative/tool UI:
  canvases, inspectors, timelines, property panels

visualization UI:
  charts, maps, telemetry panels, interactive data views
```

The core message should be that SDL3 gives CBSS a wide native target surface,
while CBSS adds style, layout, text, events, hit testing, and component
composition on top of that surface. This keeps the project broader than a
traditional GUI toolkit without forcing the core package to become a full game
engine, media engine, or visualization framework.
