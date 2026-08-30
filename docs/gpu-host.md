# GPU Host

Status: `Version 0.7 foundation implemented; GPU Canvas execution remains in progress`

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
`createGpuShader`, `createGpuGraphicsPipeline`, and `createGpuComputePipeline`
map backend-neutral descriptors to real backend objects,
record them under generation-checked handles, and destroy them on explicit
release, namespace teardown, or host teardown. Device loss drops the stale
generation without issuing unsafe destruction calls to the lost device.
Pipeline dependencies are retained explicitly. Later Version 0.7 work adds
ordered submission without exposing a second Present path.

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
Shader, and Graphics/Compute Pipeline creation, and deterministic teardown
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

GPU Canvas composition, a public native-window helper, compute-output
verification, and device restoration are still required before the GPU profile
is release-complete.

The NOOP fixture validates that those native calls coexist with host ownership
and budget accounting. Texture, Buffer, the first owned RenderTarget, Shader,
and Pipeline are now mapped through `GpuResourceHandle`; the fixture's remaining
direct uniform, view, and submission calls are not the final public APIs.
