# Native Canvas, Visualization, And Game UI Roadmap

Status: `Planned`

## Purpose

CBSS should make the native equivalent of the browser's CSS plus Canvas model
available in one application. CBSS style, layout, text, focus, and events
should handle application UI, HUDs, menus, overlays, and panels. A standard
Canvas element should host continuously updated 2D content such as games,
charts, graphs, maps, timelines, and media visualizations.

The goal is not to turn CBSS into a game engine, a chart product, or a 3D
engine. The goal is to make those workloads possible without every application
having to invent a native drawing host, an input bridge, and a layout bridge.

```text
CBSS UI tree
  |- Canvas: game scene, graph, chart, map, or custom 2D drawing
  |- Box/Text/Button: HUD, menus, forms, tooltips, and overlays
  `- Future external surface: UE, Unity, video, or another renderer
```

Canvas is a CBSS standard element, not a plugin requirement. Libraries may
later build higher-level components on it, but an application must be able to
draw a game or visualization without first adopting a third-party widget
library.

The same host contract must allow an `ExternalSurface` for a renderer or layout
library reached through FFI. This allows a Clay-based view, C++ chart engine,
Rust renderer, video surface, or host-engine viewport to live inside a normal
CBSS Box. CBSS owns the outer layout and composition; the adapter owns only the
external surface's interior.

## Product Principles

- A Canvas is a normal CBSS layout participant. Its box accepts the applicable
  CSS-inspired sizing, positioning, clipping, opacity, transform, stacking,
  background, border, and radius properties.
- The Canvas content owns only its interior pixels. CBSS owns the box model,
  clipping, hit region, focus boundary, pointer coordinate conversion, and
  layering with other UI.
- Standard CBSS controls must not acquire a separate GPU-only visual
  implementation. Buttons, forms, text, and style properties retain one
  canonical paint contract.
- Continuous work is opt-in. A Canvas requests frames while it animates;
  otherwise CBSS returns to event-driven idle behavior.
- The base API must be useful for applications and games without requiring a
  rendering plugin or a separate game engine.
- GPU-specific extensions must be capability-gated and explicit. They must not
  silently change the appearance or behavior of ordinary CBSS UI.

## Phase 1: Standard Canvas Element

Status: `Planned`

Introduce a first-class `Canvas` element and a backend-neutral `CanvasContext`.
The initial surface is 2D and uses the existing SDL3 renderer path.

Required behavior:

- Declarative Canvas construction inside `UiRoot` and normal component
  constructors.
- A public, versioned render-surface host contract so independent Nim packages
  and C ABI adapters can mount, update, and unmount their drawing inside a
  Canvas without accessing renderer internals. The application owns box
  placement; the mounted library owns only its interior drawing and resources.
- A stable local coordinate system derived from the resolved Canvas box.
- Pointer, wheel, keyboard, focus, and resize events translated into Canvas
  local coordinates.
- Pen and touch events translated into Canvas-local coordinates, preserving
  pressure, tilt, rotation, eraser, and proximity data when available.
- A frame request API for animation, with no continuous redraw while idle.
- Clipping, overflow, opacity, transform, z-order, and pointer blocking that
  agree with the surrounding CBSS box.
- Retained static Canvas content where possible, with dynamic content redrawn
  only while it changes.
- Deterministic headless and SDL3 integration tests for coordinates, clipping,
  input routing, and frame scheduling.

The first `CanvasContext` should cover the common 2D substrate:

- Clear, rectangles, rounded rectangles, lines, paths, and fills/strokes.
- Images, sprites, texture regions, and text.
- Transforms, save/restore state, clipping, alpha, and blend modes.
- Texture-backed offscreen surfaces for cached layers and composition.

Sprites and tile maps are first-class Canvas drawing targets. They are not a
second layout system: a `SpriteAnimation` or `TileMap` lives inside a resolved
CBSS box and inherits its clipping, opacity, transform, stacking, hit routing,
and frame scheduling rules.

The API should be designed around explicit commands and data, not a hidden
per-frame component rebuild.

## Phase 2: Independent Visualization And Surface Libraries

Status: `Planned`

CBSS should enable independent visualization and application-surface libraries
built on Canvas rather than absorbing charts and domain-specific application
formats into its core. SDL-native game surfaces are the deliberate exception:
sprite animation, tile-map rendering, and Tiled integration may be opt-in CBSS
game modules because they must share the existing SDL renderer, texture cache,
input routing, frame loop, and resource lifecycle. This avoids duplicating or
coordinating two SDL rendering stacks in every game-oriented library.

Initial targets:

- Numeric, time, ordinal, and band scales.
- Tick generation, axis layout, grid lines, legends, and labels.
- Line, area, bar, scatter, pie/donut, heatmap, and sparkline marks.
- Path generation and interpolation helpers.
- Pan, zoom, hover, tooltip, selection, brush, and viewport transforms.
- Incremental series updates that do not rebuild unrelated UI.
- Accessible textual summaries and keyboard-operable equivalents where the
  visualization is used in an application UI.

An independent library should be free to provide both levels of expression:

- A high-level chart constructor for common application charts.
- Lower-level scales, marks, paths, and events for D3.js-like custom
  visualization work.

Neither CBSS nor the extension contract owns network loading, databases,
dashboard business rules, or a proprietary chart document format.

The SDL-native game module set consumes application-provided sprites or texture
atlases. Its initial Tiled-output importer/renderer should read the required
subset of Tiled JSON and render that exported map through Canvas, following
Tiled's public format and established SDL-game patterns. It owns map-data
traversal, global tile IDs and flip flags, camera culling, and Tiled tile
animation, but it does not bundle the Tiled editor or implementation. TMX/XML
and less common orientations can be added after the JSON/orthogonal path is
stable. These modules remain opt-in imports so ordinary CBSS GUI applications
do not pull game-oriented code or assets into their build.

## Phase 3: SDL3 GPU Canvas Capability

Status: `Planned`

The SDL3 GPU API provides portable graphics and compute primitives for custom
GPU workloads. CBSS should expose this as an optional capability of the
standard Canvas surface, not as a second implementation of all CBSS UI
properties.

Targets:

- GPU textures, buffers, render targets, graphics pipelines, and compute
  pipelines for Canvas content.
- Explicit lifecycle, resize, device-loss, synchronization, and resource
  ownership rules.
- A portable baseline suitable for 2D games, high-density charts, particle
  effects, image processing, and conventional real-time 3D scenes.
- Offscreen GPU rendering and composition into a Canvas-owned surface.
- Capability and fallback diagnostics for unsupported drivers or devices.

Constraints:

- This is not a promise of ray tracing, mesh shaders, or vendor-specific GPU
  features.
- Shader packaging and cross-compilation must be part of the build story;
  applications must not rely on implicit platform-specific shader behavior.
- The current high-level SDL Renderer and SDL3 GPU API cannot independently
  own the same window swapchain. A GPU Canvas integration must establish one
  explicit composition owner before it is exposed as supported.
- CBSS style rendering remains canonical. GPU Canvas content is isolated to
  the Canvas interior, avoiding a second renderer-specific interpretation of
  normal CBSS properties.

`wgpu-native` is a planned optional CBSS GPU Canvas backend for projects that
specifically need a WebGPU/WGSL-oriented GPU contract. It can support custom
visualization, camera-frame effects, tile-map rendering, and game scenes while
remaining behind the same Canvas composition, input, and lifecycle contract.
It is not a prerequisite for the standard Canvas roadmap, and it must not
change the canonical renderer for ordinary CBSS UI.

## Phase 4: Game UI Workflow

Status: `Planned`

With Canvas in place, CBSS should support the native-game equivalent of an
HTML/CSS HUD over a Canvas/WebGL game scene.

```text
Canvas game scene
  + CBSS HUD
  + CBSS menus and dialogs
  + CBSS inventory, settings, chat, and accessibility UI
```

Required integration behavior:

- Explicit input ownership and propagation between the Canvas and surrounding
  CBSS controls.
- SDL3 gamepad integration with hotplug handling, stable-in-session device
  identity, player assignment, normalized buttons, axes, triggers, and d-pad
  input. CBSS uses SDL3's mapped gamepad API rather than exposing arbitrary
  joystick button numbers as the default contract.
- Two deliberate gamepad layers: semantic UI actions such as navigate,
  activate, cancel, tab, and focus movement for normal controls; and raw
  gamepad button/axis events routed into Canvas or game modules for gameplay.
  A focused control or active modal owns semantic UI actions before an
  underlying game surface can consume them.
- Runtime capability queries and optional support for rumble, trigger rumble,
  LEDs, touchpads, gyro, accelerometer, and controller-specific inputs. These
  features vary by controller, driver, and OS, so unavailable capability is not
  represented as a meaningful zero value.
- Application-configurable mappings loaded through SDL3's mapping support, plus
  a test input adapter or SDL virtual joystick for deterministic headless
  gamepad tests. CBSS must not require a physical controller in CI.
- Pause, focus, modal, pointer capture, and gamepad navigation behavior.
- Frame scheduling that keeps the game scene active without forcing unrelated
  UI to relayout or repaint every frame.
- Canvas resizing, high-DPI handling, fullscreen transitions, and viewport
  scaling.
- Opt-in CBSS sprite-animation and tile-map surfaces for gameplay scenes as
  well as ordinary application visuals, with cached static layers and
  dirty-region updates. They share the CBSS SDL renderer and resource lifecycle
  instead of creating a second SDL integration layer.
- Gallery examples for a HUD, pause menu, inventory panel, and a simple
  Canvas-driven 2D scene.

CBSS does not own gameplay loops, physics, maps, AI, sprites, or game asset
formats. It provides the UI and surface integration that lets those systems
live naturally in the same native application.

## Phase 5: External Engine And Renderer Integration

Status: `Planned`

CBSS should eventually be usable as a UI layer around rendering performed by
another native engine, including Unreal Engine and Unity. The target is not to
replace those engines. The target is to let their applications use CBSS for
high-expression, design-tool-friendly UI.

The core contract must support:

- Rendering into an application-owned target rather than requiring CBSS to
  create and own a window.
- Viewport, DPI, frame-clock, and input injection from a host engine.
- External texture or render-target exchange through engine-specific adapters.
- C ABI access to tree construction, style updates, state, events, and
  diagnostics.
- Clear ownership and synchronization rules for device resources.

Unreal and Unity will require separate, project-owned integration packages.
Those packages should be written once per engine, not once per game. They may
use engine-native texture and render-pass APIs while relying on the same CBSS
UI model and C ABI.

### Generic External Surface Boundary

CBSS will define one library-neutral `ExternalSurface` boundary instead of
embedding a specific engine or renderer in the core. This is an in-process
composition contract, not a child-window API: CBSS remains the composition
owner and an external surface contributes only the contents of its resolved
Canvas rectangle.

The boundary must provide:

- Resolved bounds, clip, transform, DPI, visibility, focus, Canvas-local input,
  frame-clock updates, resize, device-loss/recovery, and deterministic teardown.
- One declared render path at mount time: CBSS Canvas commands, a compatible
  shared GPU target, or a bounded CPU pixel buffer for non-realtime previews.
- Explicit texture/image/device ownership, synchronization, color-space,
  alpha, resize, and destruction rules for shared GPU targets.
- Explicit event-consumption and frame-request results, so an external scene
  cannot bypass modal policy, focused controls, or the idle rendering policy.
- Capability diagnostics when the host and external renderer cannot compose
  safely. CBSS must never silently open a second application window or accept
  an unsafe implicit readback path.

This contract is the prerequisite for future host-engine integrations and for
rendering libraries that wish to expose their output in a CBSS Canvas. It does
not promise that an arbitrary, unmodified renderer can be embedded zero-copy:
that depends on whether it can participate in one of the declared render paths.
The CBSS core remains independent of any particular engine or renderer.

### Host-Driven CBSS UI

The same public renderer boundary must also support the reverse direction: an
application or engine may own its window, frame loop, graphics target, and raw
input source while using CBSS for its HUD, menus, inventory, settings, dialogs,
and other UI. CBSS continues to own the UI tree, style resolution, layout,
focus, accessibility semantics, event dispatch, and paint-command generation.

A host-driven integration must:

- inject viewport, DPI, frame-clock, focus, resize, and input into CBSS;
- receive explicit input-consumption results so gameplay and focused UI controls
  do not react to the same action accidentally;
- execute CBSS paint commands through a documented renderer boundary without
  allowing CBSS to create or present a second native window;
- define texture, image, font, clipping, blend, render-target, and device
  ownership; and
- run renderer-conformance tests against the canonical SDL3 output for the
  declared CBSS feature subset.

This direction is also generic. A host may use a native renderer, a game
renderer, a GPU API, or another compatible drawing system, but it must satisfy
the same lifecycle and capability contract before CBSS can claim supported
composition.

## Phase 6: Design-Source And NIF/BIF Workflow

Status: `Planned`

The design-source roadmap should feed Canvas and game UI just as it feeds
ordinary application screens.

```text
Figma or another design-source MCP
  -> DesignSourceDocument
  -> CBSS UI, styles, and Canvas placement
  -> native preview or host-engine integration
```

NIF/BIF is a candidate interchange and cache format for a CBSS-owned design or
UI document schema. It must not be treated as executable application code.
Event handlers remain application-owned named bindings; arbitrary code is not
serialized into design documents.

The first goal is one-way, inspectable generation from a design source into
editable CBSS code and assets. Perfect round-trip synchronization is not a
precondition.

## Validation Gates

Each phase requires more than a demo:

- Unit tests for coordinate conversion, clipping, hit testing, input routing,
  frame requests, and resource lifecycle.
- Headless screenshot and command-stream tests for static and dynamic Canvas
  scenes.
- SDL3 Wayland integration coverage for resize, focus, high-DPI, and input.
- Performance budgets separating idle UI, active Canvas animation, and chart
  interaction.
- Demonstrations covering a game HUD, a dynamic line/bar chart, a custom
  path-based visualization, and Canvas/CBSS overlay composition.
- Before external-engine support is marked supported: a maintained host
  integration example and documented device/texture ownership rules.

## Non-Goals

- Reimplementing Unreal Engine, Unity, Three.js, Babylon.js, Chart.js, or D3
  in their entirety.
- Making gameplay logic, physics, 3D scene graphs, data loading, or dashboard
  business rules part of the CBSS core.
- Silently substituting renderer-specific visuals for normal CBSS controls.
- Depending on a browser, WebView, MCP server, or a specific design service at
  runtime.
