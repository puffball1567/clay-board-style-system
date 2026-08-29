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
accounting. Later Version 0.7 work maps those handles to backend textures,
buffers, render targets, shaders, and pipelines and adds dependency-ordered
submission without exposing a second Present path.

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
reporting, frame completion, resize, and deterministic teardown under both ARC
and ORC. Its maintained NOOP integration also executes real bgfx buffer,
texture, partial-update, blit, readback, framebuffer, uniform, encoder, view,
frame, and destruction calls inside a CBSS-owned host. The portable adapter
contract separately executes shader/program creation, graphics submission,
compute dispatch, and ordered destruction through deterministic C fixtures.
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
and budget accounting. It does not yet map a `GpuResourceHandle` directly to a
backend object; applications must not treat the fixture's direct bgfx calls as
the final public resource API.
