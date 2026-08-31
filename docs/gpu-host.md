# GPU Host

Status: `Version 0.7 foundation and portable GPU Canvas composition implemented`

`GpuHost` is the renderer-neutral lifecycle and ownership boundary for optional
GPU work. It does not make bgfx part of ordinary CBSS builds and does not expose
backend handles through Box, Style, Canvas, or the current C ABI.

## Ownership

Every host chooses one mode explicitly:

- `ghoOwned`: the selected adapter creates and destroys its GPU runtime;
- `ghoBorrowed`: the application creates a compatible runtime, CBSS attaches
  to it, and CBSS detaches without destroying it.

The backend API version must match `gpuHostApiVersion`. A presentation host
requires a non-zero viewport, permits only one active frame token, and cannot
resize during an active frame. Device loss advances the host generation and
invalidates every retained resource handle from the previous generation.
Successful restoration refreshes backend capability information before the
host becomes ready again.

The host is UI-thread-owned. Lifecycle, frame, namespace, and resource-accounting
operations run on the presentation thread. Worker threads should return
immutable command or data buffers to that thread instead of mutating a host.

## Resource Namespaces

Independent Nim rendering and compute libraries register a unique, bounded
namespace. Each namespace declares limits for:

- persistent GPU bytes;
- transient upload bytes per frame;
- readback bytes per frame;
- abstract work units per frame; and
- persistent resource count.

Persistent handles carry the namespace, resource kind, and device generation.
Stale or released handles are rejected. Transient, readback, and work usage is
reset only when the next valid frame starts; persistent accounting survives
frames and is cleared on device loss or namespace teardown.

The current implementation establishes safe identity, lifecycle, and
accounting. `createGpuTexture`, `createGpuBuffer`, `createGpuRenderTarget`,
`createGpuShader`, `createGpuUniform`, `createGpuSampler`,
`createGpuGraphicsPipeline`, and `createGpuComputePipeline` map backend-neutral
descriptors to real backend objects,
record them under generation-checked handles, and destroy them on explicit
release, namespace teardown, or host teardown. Device loss drops the stale
generation without issuing unsafe destruction calls to the lost device.
Pipeline dependencies are retained explicitly. `submitGpuDraw`,
`submitGpuDraws`, and `dispatchGpuCompute` provide ordered frame submission
without exposing backend handles or a second Present path.

```nim
let resources = host.createGpuNamespace(
  "chart",
  GpuResourceBudget(
    persistentBytes: 16 * 1024 * 1024,
    maxResources: 64
  )
)

let pixels = newSeq[byte](256 * 256 * 4)
let texture = host.createGpuTexture(
  resources,
  GpuTextureDescriptor(
    width: 256,
    height: 256,
    format: gtfRgba8,
    usage: {gtuSampled, gtuBlitDestination},
    label: "chart-surface"
  ),
  pixels
)

defer:
  discard host.releaseGpuResource(texture)
```

Initial bytes are copied by the backend during `createGpuTexture`; callers do
not have to retain that sequence. Retained resource creation, release, and
namespace teardown are rejected while a frame is active so destruction cannot
race submitted work.

Buffers use explicit roles and layouts instead of backend types:

```nim
let vertices = host.createGpuBuffer(
  resources,
  GpuBufferDescriptor(
    byteSize: 3 * 12,
    role: gbrVertex,
    access: gbaDynamic,
    vertexLayout: @[
      GpuVertexAttribute(
        semantic: gvsPosition,
        components: 2,
        componentType: gvctFloat
      ),
      GpuVertexAttribute(
        semantic: gvsColor0,
        components: 4,
        componentType: gvctUint8,
        normalized: true
      )
    ],
    label: "chart-vertices"
  )
)

host.updateGpuBuffer(vertices, offsetBytes = 12, data = nextTwoVertices)
```

Static buffers require complete initial bytes and cannot be updated. Dynamic
buffers may be created empty or with complete initial bytes. Updates must fit
the declared capacity and align to a whole vertex stride or index element.
Creation, update, release, and namespace teardown currently occur between
frames; frame submission never observes a partially changed retained buffer.

An offscreen render target owns one color attachment and its framebuffer:

```nim
let panelLayer = host.createGpuRenderTarget(
  resources,
  GpuRenderTargetDescriptor(
    width: 640,
    height: 360,
    format: gtfRgba8,
    usage: {gtuRenderTarget, gtuSampled, gtuBlitSource},
    label: "panel-layer"
  )
)
```

The attachment is private to the target and is destroyed with it. Applications
must not create a second retained Texture handle for the same attachment. This
first contract intentionally omits depth, multiple render targets, external
attachments, direct readback, and resizing in place. Those capabilities need
explicit dependency and synchronization rules; resizing currently means
creating a replacement target between frames and releasing the old target.

Shaders are retained precompiled resources:

```nim
let fragmentShader = host.createGpuShader(
  resources,
  GpuShaderDescriptor(
    stage: gssFragment,
    label: "chart-fragment"
  ),
  selectedBgfxShaderBytecode
)
```

The bytecode must already target the renderer selected by the active adapter.
CBSS copies it during creation, accounts its retained binary size, and does not
compile or execute source-language strings at runtime. Compute shaders are
rejected when the active backend does not advertise compute support. Shader
creation and destruction occur between frames. Pipeline resources retain typed
shader dependencies so a live program cannot outlast its stages.

Graphics and compute programs use backend-neutral descriptors:

```nim
let graphics = host.createGpuGraphicsPipeline(
  resources,
  GpuGraphicsPipelineDescriptor(
    vertexShader: vertexShader,
    fragmentShader: fragmentShader,
    vertexLayout: positionColorLayout(),
    colorFormat: gtfRgba8,
    topology: gptTriangleList,
    cullMode: gcmBack,
    frontFace: gffCounterClockwise,
    blend: alphaGpuBlendState(),
    label: "chart-pipeline"
  )
)
```

Both shaders must be live, correctly staged resources from the pipeline's
namespace and device generation. A shader cannot be explicitly released while
a live pipeline depends on it. Releasing the pipeline removes those dependency
references; namespace and host teardown destroy newer pipelines before their
older shader stages. The initial graphics contract records topology, culling,
front-face, vertex layout, output color format, blending, and color-write state.
bgfx applies state that is dynamic in its API during the later submission step;
adapters with immutable pipeline state may consume it during creation.

## Bounded Submission

Submission requires an active GPU frame. A graphics pass declares its render
target, viewport, optional scissor, and optional normalized clear color. Draw
commands refer only to retained CBSS handles:

```nim
let frame = host.beginGpuFrame()
host.submitGpuDraw(
  resources,
  GpuGraphicsPassDescriptor(
    viewport: GpuViewport(width: 640, height: 360),
    renderTarget: panelLayer
  ),
  GpuDrawCommand(
    pipeline: graphics,
    vertexBuffer: vertices,
    vertexCount: 3
  )
)
host.endGpuFrame(frame)
```

The host validates generation, namespace, resource kind, graphics-versus-
compute pipeline kind, vertex layout, vertex and index ranges, target format,
viewport and scissor bounds, compute group dimensions, and per-frame work
budget before calling the adapter. Multiple draw commands submitted through
`submitGpuDraws` share one ordered pass identifier. The adapter configures the
target, viewport, scissor, and clear state once for that pass, then receives
only the validated draw commands; adding draws does not repeat pass setup.

`GpuHostConfig.viewIdBase` and `viewIdCount` reserve the backend view range used
by CBSS. A zero count means the complete 256-view range. Borrowed runtimes can
assign a smaller non-overlapping range so application-owned bgfx work and CBSS
cannot silently reuse one another's view identifiers. The range resets each
frame and exhaustion fails before submission.

Uniform, sampled-texture, and storage-image bindings are part of each command:

```nim
let tint = host.createGpuUniform(
  resources,
  GpuUniformDescriptor(
    name: "u_tint",
    uniformType: gutVec4,
    arrayLength: 1
  )
)
let imageSampler = host.createGpuSampler(
  resources,
  GpuSamplerDescriptor(
    name: "s_image",
    addressU: gsamClamp,
    addressV: gsamClamp,
    minFilter: gsfLinear,
    magFilter: gsfLinear,
    mipFilter: gsfLinear
  )
)

host.submitGpuDraw(
  resources,
  pass,
  GpuDrawCommand(
    pipeline: graphics,
    vertexBuffer: vertices,
    vertexCount: 3,
    bindings: GpuBindingSet(
      uniforms: @[
        GpuUniformBinding(
          uniform: tint,
          values: @[0.9'f32, 0.4'f32, 0.7'f32, 1'f32]
        )
      ],
      textures: @[
        GpuTextureBinding(stage: 0, sampler: imageSampler, texture: image)
      ]
    )
  )
)
```

Uniform names are portable ASCII identifiers and values must exactly match the
declared Vec4, Mat3, or Mat4 array shape. Samplers retain backend-neutral wrap,
filter, and border-color state. Sampled textures require `gtuSampled`; compute
storage images require `gtuStorage`. Binding stage collisions, duplicate
uniforms, stale or foreign handles, non-finite values, unsupported mip levels,
and fixed per-command binding limits fail before pass setup or dispatch.

The current contract deliberately omits storage-buffer bindings. They require
the same typed namespace, dependency, and budget checks before GPU Canvas is
declared complete.

## Texture Transfer And Readback

GPU output can cross the portable CPU composition boundary without exposing a
backend handle. A render target or texture with `gtuBlitSource` is copied into
a distinct readback texture, then read asynchronously:

```nim
let readbackTexture = host.createGpuTexture(
  resources,
  GpuTextureDescriptor(
    width: 640,
    height: 360,
    format: gtfRgba8,
    usage: {gtuBlitDestination, gtuReadback},
    label: "panel-readback"
  )
)

let frame = host.beginGpuFrame()
host.copyGpuTexture(resources, panelLayer, readbackTexture)
let pending = host.requestGpuReadback(resources, readbackTexture)
host.endGpuFrame(frame)

var pixels: GpuReadbackData
if host.tryTakeGpuReadback(pending, pixels):
  discard pixels # Publish through RasterSurface on the UI thread.
```

`copyGpuTexture` also accepts a checked source/destination region. Source and
destination formats must match, coordinates use the portable 16-bit baseline,
and copies consume one reserved view and one work unit only after the adapter
accepts the command.

Readback is never a synchronous pointer-event operation. The backend writes
into host-owned storage retained until `tryTakeGpuReadback` succeeds. Polling
returns `pending`, `ready`, or `invalid`; taking a ready result transfers its
pixel sequence to the caller exactly once. A readback texture cannot be
released, its namespace cannot close, and a borrowed host cannot detach while
a request still owns that texture. Device loss invalidates all requests.

Readback textures intentionally accept exactly
`{gtuBlitDestination, gtuReadback}` and no initial data. They are CPU transfer
destinations, not sampled or storage textures. Per-frame readback-byte and work
budgets, plus a fixed per-namespace pending-request limit, bound retained CPU
memory and queued work. `GpuReadbackData.format` remains explicit. The
high-level GPU Canvas bridge normalizes R8, RGBA8, and BGRA8 output into the
straight-alpha RGBA8 contract owned by `RasterSurface`.

## GPU Canvas Composition

`GpuCanvasSurface` packages a render target and a bounded ring of asynchronous
readback textures behind one ordinary `RasterSurface`. It is the portable,
deterministic composition path for adapters that advertise both texture copy
and readback:

```nim
var gpuCanvasConfig = defaultGpuCanvasConfig(640, 360)
gpuCanvasConfig.alphaMode = gcamPremultiplied
let gpuCanvas = newGpuCanvasSurface(host, resources, gpuCanvasConfig)
let canvasView = ui.rasterSurface(gpuCanvas.rasterSurface(), panelStyle)

# Submit graphics or compute work to gpuCanvas.renderTarget() first.
let frame = host.beginGpuFrame()
host.submitGpuDraw(resources, pass, commands)
discard gpuCanvas.queueGpuCanvasFrame()
host.endGpuFrame(frame)

# Poll from the ordinary UI frame loop; this never waits for the GPU.
if gpuCanvas.collectGpuCanvasFrame():
  discard canvasView.publish()
```

The `RasterSurfaceHandle.publish()` call performs the existing Canvas revision
and paint invalidation. Layout, clipping, transforms, opacity, stacking, hit
testing, focus, keyboard behavior, accessibility semantics, and events remain
owned by the surrounding CBSS component. GPU content does not introduce a
second UI tree or a coordinate-placement API.

The readback ring defaults to three slots. `queueGpuCanvasFrame()` returns
`false` when every slot is in flight instead of blocking the UI thread. Ready
requests are collected in submission order; if several complete together,
only the newest pixels are staged, avoiding redundant UI invalidation while
preserving ordered resource release. R8 expands to opaque grayscale, BGRA8 is
swizzled, and straight, premultiplied, or opaque source alpha is normalized to
the canonical straight-alpha surface.

Closing a canvas with current pending work returns `false`; callers collect the
work and retry. Device loss invalidates the GPU generation, permits stale
canvas teardown without touching invalid resources, and requires recreation
after host restoration. The bridge owns no implicit finalizer and therefore
keeps GPU lifetime explicit under both ARC and ORC.

This path copies completed GPU pixels through CPU memory. It is the portability
and testing baseline, not the final high-throughput path for full-window video
or motion graphics. A later shared-texture composition path may remove that
copy while preserving the same upper Canvas, layout, and component contract.

## Optional bgfx Adapter

The bgfx adapter is compiled only with `-d:cbssGpuBgfx` and imports the separate
[`bgfxim`](https://github.com/puffball1567/bgfxim) package. The application must
also provide a compatible bgfx/bx/bimg native runtime and target-specific
renderer libraries.

```nim
import clay_board_style_system

let backend = newBgfxBackend()
let host = openGpuHost(
  backend,
  ghoOwned,
  GpuHostConfig(
    width: 1280,
    height: 720,
    presentation: true
  )
)

defer:
  host.close()
```

For a native window, fill `BgfxHostOptions.platformData` with handles obtained
from SDL3 before opening the host. Exactly one component owns presentation for
that window. The SDL high-level renderer and bgfx must not independently
present to the same window.

The current adapter covers initialization or borrowed attachment, capability
reporting, frame completion, resize, mapped Texture, Buffer, RenderTarget,
Shader, Uniform, Sampler, Graphics/Compute Pipeline creation, bounded
graphics/compute submission with sampled textures and storage images, and
typed texture copies and asynchronous readback, and deterministic teardown
under both ARC and ORC. Its
maintained NOOP integration also executes real bgfx static and dynamic buffers,
aligned partial updates, textures, blit, readback, framebuffer, uniform,
encoder, view, frame, and destruction calls inside a CBSS-owned host. The
portable adapter contract verifies mapped formats, vertex layouts, index width,
initial data, labels, updates, offscreen target flags, shader bytecode copies,
program creation, dependency-safe destruction, graphics submission, compute
dispatch, and ordered teardown through deterministic C fixtures.
The Linux `bgfx_host_demo` additionally opens an SDL3 native window, initializes
the OpenGL renderer, uploads a changing dynamic vertex buffer, submits indexed
graphics, presents through `GpuHost`, and follows window resize. Run it with
compatible source checkouts:

```sh
CBSS_BGFXIM_PATH=../nim-bindings/bgfxim \
CBSS_BGFX_PATH=/path/to/bgfx \
CBSS_BX_PATH=/path/to/bx \
CBSS_BIMG_PATH=/path/to/bimg \
nimble runBgfxHostDemo
```

GPU Canvas composition, storage-buffer bindings, a public native-window helper,
real-renderer output verification, and device restoration are still required
before the GPU profile is release-complete.

The NOOP fixture validates that native resource calls coexist with host
ownership and budget accounting. Because the NOOP renderer does not advertise
portable blit or readback capabilities, public transfer calls fail closed
there. Deterministic C fixtures advertise those capabilities and cover the
complete typed copy/readback path under ARC and ORC; visible real-renderer
qualification remains a GPU Canvas release gate.
