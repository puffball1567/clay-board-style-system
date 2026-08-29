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
accounting. `createGpuTexture` and `createGpuBuffer` map backend-neutral
descriptors to real backend objects, record them under generation-checked
handles, and destroy them on explicit release, namespace teardown, or host
teardown. Device loss drops the stale generation without issuing unsafe
destruction calls to the lost device. Later Version 0.7 work applies the same
contract to render targets, shaders, and pipelines and adds dependency-ordered
submission without exposing a second Present path.

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
reporting, frame completion, resize, mapped Texture and Buffer creation, and
deterministic teardown under both ARC and ORC. Its maintained NOOP integration
also executes real bgfx static and dynamic buffers, aligned partial updates,
textures, blit, readback, framebuffer, uniform, encoder, view, frame, and
destruction calls inside a CBSS-owned host. The portable adapter contract
verifies mapped formats, vertex layouts, index width, initial data, labels,
updates, and destruction, then separately executes shader/program creation,
graphics submission, compute dispatch, and ordered destruction through
deterministic C fixtures.
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
and budget accounting. Texture and Buffer are now mapped through
`GpuResourceHandle`; the fixture's remaining direct framebuffer, uniform,
shader, and pipeline calls are not the final public resource APIs.
