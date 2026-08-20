# Native Canvas, Visualization, And Game UI Roadmap

Status: `In progress`

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
- The canonical CPU rasterizer is a CBSS implementation. It defines the
  deterministic vector and headless baseline while remaining behind the
  public CBSS color, paint, cache, surface, and C ABI contracts.

## Phase 1: Standard Canvas Element

Status: `In progress`

The first implementation slice now provides the versioned Nim RenderSurface
lifecycle, retained Canvas construction in `UiRoot`, content-area placement,
local pointer/input conversion including typed touch and pen metadata,
deterministic disposal, explicit frame
requests, and conversion of retained Canvas commands into the canonical paint
stream. Scroll translation, ancestor clipping, inherited opacity, paint, hit
testing, and surface placement share one presentation-coordinate helper. The
same lifecycle is now exposed through the C ABI and exercised by both shared
and static C consumers.

Phase 1 is not complete. Retained open and closed paths, adaptive quadratic
and cubic curves, configurable line caps/joins, save/restore transforms,
bounded composition layers, and the C ABI Canvas drawing adapter now use the
shared SDL3 and headless paint stream. Final release performance, memory, and
platform gates remain required. The interactive SDL3 Canvas/color demo is
available through
`nimble v03CanvasDemo`. See
[render-surfaces.md](render-surfaces.md) for the implemented contract.

SDL3 pen proximity, contact, motion, axis, and barrel-button events now feed
the common pointer contract. Axis capability masks preserve meaningful zero
values, synthesized duplicate mouse/touch events are filtered, RenderSurface
callbacks receive local coordinates without losing device data, and the C ABI
uses the same fixed-layout representation. High-rate sample coalescing and
hardware-specific platform validation remain later performance and release
gates.

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

### Canonical CPU Raster And Effects Path

CBSS owns the CPU vector rasterization and baked-effects path used by Canvas
and normal Style painting. SDL3 presents its retained texture output, but SDL
line primitives do not define the vector quality model.

For game-oriented applications, this path can provide a reusable authored and
procedural visual layer rather than acting as the real-time scene renderer.
Candidate workloads include:

- vector and SVG-derived HUD skins, icons, markers, badges, and inventory art;
- baked gradients, masks, glows, shadows, outlines, and state variants;
- procedural textures, minimaps, card faces, gauges, diagrams, and generated
  interface assets;
- image cropping, recoloring, compositing, and atlas preparation when source
  assets or themes change; and
- cached path-based Canvas content that does not need a GPU pipeline of its
  own.

Sprites, tile maps, particles, cameras, and continuously changing game scenes
remain on the SDL3 real-time path or the optional bgfx GPU Canvas. CPU output
becomes a texture or cached layer consumed by that path. This combination lets
a game use CSS-inspired CBSS layout and interaction, high-quality generated 2D
art, and conventional real-time rendering in one window without forcing all
three workloads through one implementation.

The rasterizer consumes resolved CBSS paint commands and produces cacheable
SDL3 resources. It preserves the color compatibility and color-management
contracts established in `roadmap.md` and `native-rendering-stack.md`.

CPU effect work follows retained invalidation:

- static results are generated once and cached;
- source, style, size, scale, or output-color changes invalidate only the
  affected result;
- continuous regeneration is explicit and active only while requested; and
- application policy may restrict quality, cache memory, or dynamic effects
  for embedded Linux deployments.

No rasterizer-internal type or owning object crosses the C ABI. Foreign callers
select CBSS capabilities and policies through CBSS-owned versioned API, while
the implementation remains private.

## Phase 2: Independent Visualization And Surface Libraries

Status: `Planned`

CBSS should enable independent visualization and application-surface libraries
built on Canvas rather than absorbing charts and domain-specific application
formats into its core. SDL-native visual-asset surfaces are the deliberate
exception: sprite animation, tile-map rendering, and Tiled-output integration
may be opt-in CBSS modules because they must share the existing SDL renderer,
texture cache, input routing, frame loop, and resource lifecycle. This avoids
duplicating or coordinating two SDL rendering stacks in every consuming
library while keeping gameplay policy outside CBSS.

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

The SDL-native visual-asset module set consumes application-provided sprites or
texture atlases. Its initial Tiled-output importer/renderer should read the required
subset of Tiled JSON and render that exported map through Canvas, following
Tiled's public format and established SDL-game patterns. It owns map-data
traversal, global tile IDs and flip flags, camera culling, and Tiled tile
animation, but it does not bundle the Tiled editor or implementation. TMX/XML
and less common orientations can be added after the JSON/orthogonal path is
stable. These modules remain opt-in imports so ordinary CBSS GUI applications
do not pull unused visual-asset code or assets into their build.

## Motion Scene Dependency Track

Status: `Planned after declarative transition binding`

GPU Canvas is not limited to displaying frames completed elsewhere. CBSS will
also provide a retained Motion Scene whose visual objects are evaluated and
drawn by the CBSS Canvas pipeline. This is the primary path for simultaneously
animated shapes, text, images, particles, sprites, chart marks, and procedural
visuals. External Nim code may calculate object data, but the resulting scene
participates in CBSS composition, clipping, frame scheduling, coordinate
conversion, hit testing, and presentation.

A Motion Scene is internal content of one Canvas layout node. It must not
inflate the UI tree by creating one Box for every particle, chart point, or
motion-graphics layer. Scene objects instead use stable typed IDs and
data-oriented retained storage suitable for CPU chunking, GPU instancing, and
storage-buffer upload. Optional per-object interaction metadata maps scene
hits back to CBSS input events without making those objects independent layout
participants.

The user-facing goal is a Web-like authoring boundary:

```nim
let scene = motionScene()
scene.add(titleLayer)
scene.add(particleField)

ui.gpuCanvas(scene, style = previewStyle())
```

Application authors do not manage GPU queues, worker channels, swapchain
ownership, generation counters, or frame fences. Independent Nim libraries
can expose reusable motion, chart, game, and generative-design objects that
mount through this contract.

Motion Scene actions are valid targets of the first-party Cue graph. UI
events, timeline or media markers, audio-analysis signals, game events, and
independent Nim libraries may start a Cue session that coordinates scene
actions in serial or parallel. Continuous amplitude, spectrum, simulation, or
sensor values remain bounded Streams or frame parameters; meaningful markers
become typed Signals. This keeps media analysis and simulation outside the Cue
scheduler while giving animation, video editing, music-synchronized visuals,
games, and generative design one deterministic orchestration contract.

Implementation order:

1. The ordinary-UI declarative transition engine defines the shared clock,
   interpolation, reversal, cancellation, reduced-motion, and invalidation
   semantics.
2. A deterministic CPU reference renderer validates scene snapshots, stable
   identities, hit testing, frame replacement, and headless output.
3. The bgfx GPU adapter batches scene data into graphics and compute passes and
   composites its offscreen result into the Canvas-owned region.
4. Additional GPU adapters may implement the same CBSS-owned contract without
   creating a second public scene model or becoming standard dependencies.

The architectural contract is fixed before transition work completes: Canvas
owns layout and presentation; Motion Scene owns its interior visual objects;
backend handles remain private; worker results are bounded immutable snapshots;
and static scenes do not request idle frames.

Deployment remains capability-based. The CPU Canvas and SDL 2D profile does
not import, link, or package bgfx, Little CMS, Motion GPU, media codecs, or
shader bundles unless selected by the application. This profile remains the
baseline for 64-bit Raspberry Pi-class Linux targets. GPU-enabled profiles add
only the target's chosen bgfx renderers and report unsupported devices
explicitly instead of silently falling back to an unbounded software workload.

Capability selection occurs at compile/configure time. It controls source
imports, native bridge builds, linker inputs, staged libraries, and assets;
runtime feature flags alone are insufficient. The project may expose one
generated `cbss_app` import for ergonomics, but that module re-exports only the
selected profile. Release CI measures both artifact size and native dependency
closure for the standard CPU/SDL 2D profile and the target's full profile.

## Phase 3: bgfx GPU Canvas Capability

Status: `Planned`

bgfx provides portable graphics and compute primitives across the GPU APIs
selected for each target. CBSS exposes it as an optional capability of the
standard Canvas surface, not as a second implementation of all CBSS UI
properties. SDL3 remains responsible for the window, native handle, input,
event, and CPU presentation lifecycle.

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

The bgfx binding is an independent low-level Nim package and is linked only by
the selected GPU profile. A later wgpu-native or other provider may implement
the same Canvas composition, input, resource, and lifecycle contract, but it
is not a prerequisite for this roadmap and must not change the canonical
renderer for ordinary CBSS UI.

### WGSL-Backed Custom Style Painting

Status: `Deferred adapter-specific design; not a bgfx release gate`

The primary intended use of WGSL in ordinary CBSS UI is not to reimplement the
layout engine, text stack, or every control on the GPU. CBSS first resolves
Style, layout, text, and ordinary paint through its CPU-owned pipeline. A
selected Box or retained layer can then use WGSL to paint beneath that result,
paint over it, or process the CPU-rendered pixels as an input texture before
CBSS performs final composition.

```text
CBSS Style / component tree
          |
          v
CPU style, layout, text shaping, paint generation
          |
          v
bounded retained element/layer texture
          |
          +--> WGSL underlay
          +--> CPU-rendered content
          +--> WGSL overlay
          `--> WGSL post-process/filter
                         |
                         v
              CBSS clip, opacity, transform,
              stacking, and final presentation
```

This makes effects such as a moving liquid surface on a Button, animated light
over static text, refraction of a baked panel, procedural borders, generated
backgrounds, masks, and local color processing possible without making those
elements separate GPU-only widgets. A later GPU profile may therefore let a
normal CBSS Style reference a typed, registered WGSL material. The Style stores
a stable material identifier and typed parameters, not a backend device,
pipeline, raw native handle, or unvalidated shader string. Style resolution and
layout remain backend-neutral; the material executes only after CBSS has
produced the element's layout and paint placement.

The public authoring unit remains `UiStyle`. A "custom Style" is an ordinary,
mergeable `UiStyle` exported by a Nim library, with one or more typed custom
paint declarations that reference packaged WGSL resources. It is not a second
style system and does not require application code to manage a GPU pipeline.

```nim
proc liquidButtonStyle*(): UiStyle =
  let liquid = wgslPaint(
    shader = wgslResource("liquid-button"),
    fallback = linearGradient(...),
    effectOutset = px(8)
  )

  uiStyle([
    customPaint(liquid, stage = cpsOverlay),
    borderRadius(10),
    overflow("visible")
  ])

button.applyStyle(liquidButtonStyle())
```

Custom paint declarations participate in the existing Style merge, component
DI, replacement, state-style, invalidation, and ownership rules. A component
library can therefore package a WGSL-backed visual language and consumers use
it in the same way as any other imported Style. Shader identity, typed uniform
schema, fallback, paint stage, effect bounds, frame policy, and required GPU
capabilities are part of the declaration; backend objects are not.

Provisional paint stages are:

- `underlay`: run WGSL before ordinary CPU content, within the element's
  background/effect bounds;
- `overlay`: preserve the CPU-rendered content and paint WGSL output over it;
- `filter`: provide the CPU-rendered element/layer as a sampled input texture
  and replace it with the shader result; and
- `mask`: use bounded WGSL output to control the final alpha of the retained
  layer.

The execution and caching contract is:

- One presentation owner performs the final frame. When WGSL participates, CPU
  raster output is uploaded or updated as a bounded texture; a second renderer
  does not independently present the same window.
- CPU content is rerasterized and reuploaded only when its paint revision,
  logical size, pixel scale, clip source, or required color context changes.
  Time-only WGSL animation reuses the retained CPU texture and must not rerun
  style resolution, layout, text shaping, or ordinary CPU paint each frame.
- A static shader result is cacheable after its source texture, uniforms, size,
  and output context stop changing. An animated shader requests frames only
  while its time/state inputs require them and returns to event-driven idle
  afterward.
- Composition is region-bounded. The allocation and redraw area is the element
  or retained layer plus its declared `effectOutset`, not the complete window
  unless a root-level effect explicitly requests that scope.
- The CPU texture and shader pipeline agree on device-pixel scale, premultiplied
  alpha, linear-versus-encoded color operations, clip and rounded-mask order,
  and texture orientation. Text remains shaped by the configured CBSS text
  engine and is not reconstructed by the shader.
- Typed uniforms may expose size, local coordinates, time, pointer position,
  element state, resolved colors, and explicitly registered images or textures.
  They do not expose mutable `UiRoot`, backend ownership, arbitrary filesystem
  access, or application memory.
- If the selected profile cannot execute WGSL, the material uses its declared
  standard Style/CPU fallback or reports a capability error according to its
  policy. It must not leave the element blank without a diagnostic.

The initial implementation should prove a bounded overlay first: bake one
ordinary CPU-rendered Button or panel, upload it when dirty, animate a WGSL
surface effect above it, preserve the existing Box hit region and accessibility
semantics, and return to idle when the effect stops. Filter, mask, visual-shape
hit testing, and arbitrary scene picking remain later layers on the same
contract.

This bounded Custom Style path is the scope of the design above. It ends at
declaratively attaching packaged WGSL paint to an ordinary CPU-defined CBSS
element and composing the result correctly. It does not require shader-derived
layout, GPU-derived accessibility geometry, or visual-shape event targeting.

### Deferred Visual-Shape Hit Testing

Status: `Exploratory design; outside the Custom Style milestone`

The default interaction shape remains the logical CBSS box. A ripple, color
wave, refraction, or other surface-only effect therefore adds no hit-test cost
and does not make a stable Button target move under the pointer. An effect that
intentionally changes the visible interactive silhouette may opt into a visual
hit-test contract.

Provisional modes are:

- `logical-box`: use the unmodified CBSS hit region; this is the default;
- `effect-bounds`: use a conservative, declared maximum visual outset;
- `transformed-box`: inverse-map the pointer through a CBSS-owned affine
  transform;
- `analytic-shape`: evaluate a bounded CPU path, signed-distance function, or
  typed deformation expression using the same parameters supplied to WGSL;
- `cached-mask`: sample a retained CPU-visible occupancy or alpha mask that is
  regenerated only when its declared source changes; and
- `gpu-pick`: resolve an object or alpha identifier from an asynchronous GPU
  picking pass for specialized Canvas, scene, or editor workloads.

Visual hit testing obeys the following invariants:

- A normal broad-phase Box/effect-bounds test runs first. Detailed deformation,
  path, or mask work runs only for topmost candidates that contain the pointer,
  and only while processing relevant input rather than for every node each
  frame.
- WGSL is not introspected to infer geometry. Arbitrary shader output has no
  automatic inverse. An effect that wants shape-aware input declares a matching
  CPU-evaluable shape, mask, or specialized GPU-picking policy explicitly.
- A future typed deformation IR may generate both a CPU evaluator and WGSL from
  one expression. Until that contract exists, duplicated handwritten CPU/WGSL
  formulas are an advanced adapter responsibility and must have conformance
  tests over time, state, scale, and edge coordinates.
- The shader cannot fabricate a `NodeId`, bypass clipping or stacking, dispatch
  an event, or mutate focus. CBSS validates a visual hit against the retained
  node generation, effective clip, visibility, pointer-events state, stacking
  order, and the open event contract before dispatch.
- A visual hit produces the same original `target`, traversal `currentTarget`,
  propagation, default-action, disabled/inert, pointer-capture, and disposal
  behavior as a logical hit. The rendering backend does not own a second event
  system.
- Layout, sibling flow, focus order, and accessibility geometry do not depend on
  GPU readback. If visual expansion must affect layout or semantic bounds, the
  corresponding width, transform, effect outset, or semantic geometry is
  declared to CBSS independently of the shader.
- Synchronous GPU readback is prohibited on ordinary pointer-event paths. GPU
  picking is asynchronous, carries a frame and surface generation, discards
  stale results after resize/unmount/device loss, and is not the default for
  buttons, forms, links, or menus.
- Unsupported GPU capability uses the declared CPU/standard Style fallback or
  reports a capability diagnostic. It must not silently turn an irregular
  visible target into an unrelated interactive shape.

This capability is intentionally separate and optional. Builds without visual
hit testing do not import a picking implementation or extra hit-test data.
Ordinary nodes and WGSL-backed Custom Styles retain the current logical
Box/transform hot path. If this later work is implemented, performance tests
must separately cover broad-phase rejection, topmost-candidate analytic tests,
mask cache invalidation, animated effects, large listener/node sets, and
asynchronous picking under delayed completion.

### Application GPU Compute Coexistence

An application backend may use the same physical GPU for inference, image or
signal processing, simulation, encoding preparation, or other general-purpose
compute. CBSS must not assume that its Canvas renderer is the process-wide or
machine-wide exclusive GPU owner.

The integration model depends on the process and API boundary:

- A separate backend process owns its own GPU device and queues. It transfers
  only bounded results, Blob data, or immutable stream snapshots to the CBSS
  process. API contexts cannot conflict across the process boundary, although
  applications remain responsible for GPU memory, bandwidth, thermal, and
  scheduling budgets shared by the physical device.
- An in-process backend using a different GPU API owns an isolated device by
  default. Its portable exchange path is a bounded CPU staging buffer. Raw
  texture, external-memory, and semaphore exchange is an optional
  platform-specific adapter and is never assumed merely because both APIs use
  the same physical GPU.
- An in-process backend using the selected CBSS GPU API may receive a
  host-owned compute submission capability. It registers work with the shared
  frame scheduler instead of creating a second swapchain owner or submitting
  unsynchronized work behind CBSS.

#### Conditional wgpu Runtime And Binding Contract

This subsection is retained for a possible future wgpu adapter. D29 selects
bgfx as the planned standard GPU capability, so none of the wgpu-specific
runtime, binding, or release-gate requirements below apply to a standard or
`gpu-bgfx` build.

A process using an optional wgpu or WGSL Custom Style profile has exactly one
selected low-level Nim binding package and one linked or dynamically loaded
`wgpu-native` runtime. CBSS and every in-process Nim compute, visualization, or
rendering package depend on that same package and resolved version. An adapter
must not vendor another generated binding, link a second static wgpu runtime,
or load an independently selected shared-library version into the process.

The canonical binding package is deliberately low-level. It owns generated C
declarations, platform calling conventions, native-library discovery, the
pinned header/runtime compatibility manifest, and minimal ABI probes. It does
not own CBSS Style, application kernels, scene objects, or product logic. The
application's generated capability configuration records the exact binding and
native artifact version/checksum, and startup rejects a provider that does not
match that manifest before creating a device.

This single-provider rule prevents two Nim packages from compiling compatible-
looking but ABI-incompatible handle types or from disagreeing about who may
initialize, unload, or destroy the native runtime. Backend-specific handles
remain outside the ordinary CBSS module and C ABI.

#### Explicit GpuHost Ownership

Device ownership is not inferred from who imports a module first. A versioned
`GpuHost` contract supports two explicit creation modes:

- `owned`: CBSS creates and owns the wgpu Instance, Adapter, Device, and Queue,
  destroys them after all namespaces and surfaces have detached, and exposes
  only scoped capabilities to registered in-process packages; or
- `borrowed`: the application creates the compatible Instance, Adapter, Device,
  and Queue through the canonical provider and attaches them to CBSS. The
  application guarantees that they outlive every attached CBSS surface and
  namespace; CBSS never destroys borrowed objects.

In either mode CBSS is the only swapchain/surface acquisition and presentation
owner for each CBSS window. A borrowed Device does not grant the application a
second Present path. The host contract records thread affinity, supported
features and limits, texture formats, queue identity, surface compatibility,
device generation, and shutdown state before attachment. It rejects a second
Device/Queue pair for the same presentation domain rather than attempting to
merge unrelated command streams implicitly.

Device loss increments the host generation and invalidates every device-bound
resource handle. CBSS stops acquiring frames, notifies registered owners in a
deterministic order, releases surface resources, and either asks the owning host
to replace borrowed objects or recreates owned objects. No callback may retain
a frame encoder, swapchain texture, or borrowed device pointer beyond its
documented scope.

#### Persistent GPU Resource Namespaces

Frame-scoped submission is not sufficient for real compute or rendering
packages. A `GpuResourceNamespace` is therefore a required part of the shared
host contract. It is registered to a stable owner and may retain pipelines,
buffers, textures, samplers, bind-group data, and immutable shader modules
across frames without receiving ownership of the Device, Queue, or swapchain.

Each namespace provides:

- an owner ID and device generation, with stale handles rejected after device
  loss or host replacement;
- opaque typed resource handles and labels rather than process-global integer
  names;
- explicit create, replace, retain where sharing is permitted, release, cancel,
  and close operations;
- separate persistent GPU-memory, transient upload, readback, and per-frame
  submission budgets;
- declared resource usage and dependencies so CBSS can order compute, copy, and
  render work without an implicit queue wait;
- optional recreation descriptors or an owner callback for resources that may
  be rebuilt after device restoration;
- deterministic namespace teardown that waits for or safely retires in-flight
  work before releasing resources; and
- accounting and diagnostics that identify the owning namespace when a budget,
  validation, lifetime, or device-generation rule is violated.

Persistent resources survive frame callbacks, but command encoders, passes,
swapchain textures, temporary mappings, and frame-local views do not. A
namespace may submit compute or produce a texture for CBSS composition through
a frame-scoped scheduler capability; it cannot present, bypass dependency
tracking, or mutate another namespace's resources.

The shared submission contract must provide:

- exactly one window swapchain and present owner;
- explicit device, queue, command-buffer, resource, and fence ownership;
- scoped compute and copy submission that cannot retain a frame encoder after
  its callback returns;
- resource namespaces, memory budgets, upload limits, and per-frame work
  budgets so backend compute cannot starve UI presentation;
- declared dependencies between compute output and Canvas consumption without
  blocking the UI thread for an unbounded fence wait;
- device-loss and shutdown notification delivered to every registered owner;
  and
- deterministic mock scheduling tests that do not require GPU hardware.

#### Shared-Device Integration Release Gate

The wgpu profile is not considered integrated after isolated unit tests alone.
A maintained independent compute fixture must run in the same process as CBSS
and exercise all of the following together:

```text
CBSS Motion Scene and WGSL Custom Style rendering
  + independent Nim compute package
  + one canonical wgpu runtime and binding package
  + one Instance / Adapter / Device / Queue
  + one CBSS-owned window Surface and Present path
```

The fixture creates persistent pipelines and buffers in its own namespace,
submits compute that produces data or a texture consumed by a CBSS frame, and
proves that ordinary UI, scene rendering, compute, and presentation complete in
the declared dependency order without a second queue owner or synchronous
unbounded wait. It runs in both CBSS-owned and application-borrowed `GpuHost`
modes.

Release tests cover:

- binding/runtime manifest mismatch and duplicate-provider rejection;
- initialization failure at every ownership stage and rollback without leaked
  native or Nim resources;
- namespace creation, persistent reuse across many frames, explicit release,
  cancellation with work in flight, and teardown in every supported owner order;
- injected device loss before submission, during retained resource use, and
  during shutdown, followed by generation rejection and supported restoration;
- window resize, surface reconfiguration, hidden/minimized windows, and closing
  while compute work is pending;
- enforced persistent memory, transient upload, readback, and per-frame work
  limits, including a package that deliberately exceeds each limit;
- no callback or namespace retaining a frame encoder or swapchain texture after
  scope exit;
- idle behavior after all scene, Style effect, and compute work completes; and
- bounded frame latency when compute and UI rendering contend for the same
  Device and Queue.

Deterministic mock tests run on every portable CI target. The release profile
also requires a real Linux GPU integration run for the supported wgpu backend;
additional native GPU/OS lanes may be contributed independently. GPU allocation
accounting, validation errors, uncaptured errors, and CBSS ARC/resource
lifecycle checks are recorded together because host-memory leak tools alone do
not prove correct GPU teardown.

CBSS does not become a general-purpose compute framework. Application logic
owns kernels, data, retry policy, and result meaning. CBSS owns only the GPU
composition and scheduling boundary needed to coexist safely in one process.
Backend-specific device handles remain opaque across the C ABI and are absent
from the standard CPU/SDL 2D capability profile.

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
  gamepad button/axis events routed into Canvas or visual surfaces for
  application-defined behavior.
  A focused control or active modal owns semantic UI actions before an
  underlying game surface can consume them.
- Runtime capability queries and optional support for rumble, trigger rumble,
  LEDs, touchpads, gyro, accelerometer, and controller-specific inputs. These
  features vary by controller, driver, and OS, so unavailable capability is not
  represented as a meaningful zero value.
- Application-configurable mappings loaded through SDL3's mapping support, plus
  a test input adapter or SDL virtual joystick for deterministic headless
  gamepad tests. CBSS must not require a physical controller in CI.
- Focus, modal, pointer capture, and gamepad navigation behavior. Application
  pause policy is not part of this integration contract.
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

CBSS does not own gameplay loops, physics, map meaning, AI, sprite artwork, or
application rules. It provides image-sequence and map-layer presentation plus
the UI and surface integration that lets those systems live naturally in the
same native application.

### Complex Game Frontend Architecture

Status: `Design recorded; dependent on Motion Scene and GPU profiles`

The combination of Visual Scene storage, WGSL-backed visual styles, Canvas,
and ordinary CBSS components is intended to support complex 2D games without
turning every game object into a Box or moving gameplay policy into Style.
CBSS is the frontend and presentation owner; application or imported Nim
systems remain responsible for simulation and domain logic.

```text
Nim game systems
  fixed-step simulation, ECS, physics, AI, rules, save, networking
                              |
                              v
                 bounded immutable SceneSnapshot
                              |
                              v
CBSS Visual Scene / Canvas
  sprites, tiles, particles, chart marks, effects, cameras, render layers
                              |
                  CPU renderer or WGSL backend
                              |
                              v
CBSS components
  HUD, menus, inventory, dialogs, chat, settings, accessibility UI
                              |
                              v
                 one compositor and presentation owner
```

The simulation clock and presentation clock are separate. Gameplay may update
at a deterministic fixed rate, while CBSS presents at the available display
rate and may interpolate visual state. A slow or paused renderer must not change
simulation results, and a busy simulation worker must not mutate the live UI or
GPU resource graph. Worker-produced results cross to the presentation thread as
bounded immutable snapshots, ownership-transferred buffers, or latest-result
state according to the subsystem's ordering requirements.

Dense visuals use a general data-oriented item contract rather than one CBSS
Node per tile, sprite, particle, graph point, or world object:

```text
VisualItem
  stable item ID
  geometry or atlas reference
  transform and layer
  VisualStyle/material index
  compact state flags
  typed per-instance parameters
```

`VisualStyle` reuses the paint-relevant CBSS vocabulary, including fill,
stroke, opacity, transform, clip, mask, blend, animation, and registered Custom
Paint, but it does not pretend that every dense item is a Flex or Box layout
participant. Full `UiStyle` remains on the containing Canvas/component. Logical
per-item styling is compiled into shared material/style tables and instance or
storage buffers; implementations batch by pipeline and material instead of
creating one shader, pipeline, allocation, or event binding per item.

The same contract covers tiles, sprites, particles, vector marks, graph bars and
points, map regions, waveform samples, timeline clips, node-editor edges, and
other repeated visuals. A tile map is one adapter over this substrate, not the
definition of the substrate. Independent Nim libraries may expose higher-level
game, chart, map, editor, and generative-design objects while sharing CBSS
composition and scheduling.

Interaction remains layered:

- CBSS first applies window/Canvas placement, effective clipping, modal policy,
  focus ownership, pointer capture, and input propagation.
- The active scene maps local input to a stable `VisualItemId` using a grid,
  spatial index, analytic shape, or another bounded scene-owned accelerator.
- Scene selection or activation is reported through the open CBSS event/signal
  contract. A visual item does not bypass disabled ancestors, overlays, or a
  focused control merely because it is GPU-rendered.
- Ordinary gameplay picking must not synchronously read pixels back from the
  GPU. Tiles use coordinate/grid lookup; sprites and shapes use retained spatial
  data. Asynchronous GPU picking remains an explicit specialized path.

The intended practical range includes 2D RPGs, strategy and simulation games,
card games, tower defense, dense particle/bullet scenes, adventure games,
editor-heavy games, and other UI-rich native applications. Performance depends
on culling, atlas use, material batching, stable buffers, bounded uploads, and
not rebuilding unrelated CBSS UI when a scene frame changes.

Three-dimensional rendering uses the same Canvas/RenderSurface placement and UI
composition boundary, but CBSS does not claim to provide a complete 3D engine.
A 3D package or application owns meshes, materials, scene graphs, lighting,
shadows, skeletal animation, physics, visibility, and asset preparation. CBSS
may host its texture or compatible GPU pass, route bounded input, and compose
the HUD and application UI above it. Advanced 3D support therefore extends the
frontend integration surface without making those engine systems mandatory
CBSS core dependencies.

Release work for this track must include deterministic simulation/snapshot
fixtures, CPU reference output, GPU/CPU visual conformance for the supported
subset, large-item batching benchmarks, bounded-memory and upload tests,
snapshot replacement races, resize and device-loss recovery, input ownership,
and proof that static or paused scenes return to event-driven idle behavior.

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
