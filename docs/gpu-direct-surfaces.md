# GPU Display Surfaces

Status: `Backend-neutral direct presentation and asynchronous readback fallback implemented`

The normal, failure, edge-case, and pending hardware coverage is tracked in
[GPU Surface Quality Matrix](gpu-surface-test-matrix.md).

`GpuDisplaySurface` is the negotiated UI boundary for displaying a GPU Texture
or RenderTarget. It selects one of two paths without changing the surrounding
Box, Canvas, layout, clipping, opacity, transform, stacking, hit-test, focus,
or accessibility contracts:

- `gdspDirect`: the paint adapter samples a resource from the same GPU host and
  ordered queue without a CPU readback;
- `gdspReadback`: CBSS performs a bounded asynchronous copy into a
  `RasterSurface` and uses the ordinary CPU/SDL renderer.

The normal configuration allows the fallback:

```nim
var config = defaultGpuDisplaySurfaceConfig(1280, 720)
config.bufferCount = 3

let display = host.newGpuDisplaySurface(resources, config)
let view = ui.gpuDisplaySurface(display, viewportStyle)
```

Set `config.fallback = gdsfRequireDirect` only when the application has selected
a paint adapter that consumes `pcDrawGpuDirectSurface` from the same
`GpuHost`. The SDL high-level renderer does not import arbitrary external GPU
textures. The current bgfx adapter therefore leaves direct-presentation
capabilities disabled until its same-device compositor is qualified. With the
default policy, these adapters select `gdspReadback` instead of silently
displaying nothing.

## Publishing Frames

Producers rotate two or more sampled Texture or RenderTarget resources. A frame
is queued with the `GpuFrameToken` that orders its writes:

```nim
let frame = host.beginGpuFrame()
host.dispatchGpuCompute(resources, computeCommand)
discard view.queueGpuFrame(outputTexture, frame)
host.endGpuFrame(frame)

# Called by the UI loop. This never waits for GPU work.
discard view.collectGpuFrame()
```

Direct publication becomes eligible only after the backend accepts the frame
boundary. This is an ordered same-device dependency, not a CPU-visible fence
and not permission to share a resource across unrelated GPU devices. A backend
must not advertise direct presentation unless its compositor can preserve that
ordering.

Each queued resource is retained for presentation. CBSS rejects writes,
copies into it, explicit destruction, and namespace teardown until the frame is
retired. A compositor receives only the generic `GpuBackendResourceId` at its
adapter boundary; ordinary UI code never receives a bgfx or platform-native
handle. The compositor lease is released in a `finally` path even when drawing
returns retry, unsupported, or failed.

The queue is bounded to two through eight slots. When full, queueing returns
`false` rather than blocking or allocating. Collection coalesces multiple ready
frames to the latest revision, retires older resources after active leases end,
and invalidates only `ddPaint` for the attached UI node. This supports standard
double and triple buffering without rebuilding layout or hit regions.

## Capability Contract

`GpuBackendInfo` reports direct Texture, RenderTarget, and compute-output
support separately, along with accepted formats and the maximum buffer count.
CBSS validates the matrix when the host opens. Inconsistent declarations close
or detach the backend and fail the open operation.

`gpuDisplaySurfaceCapabilities()` reports both the direct and readback paths.
Readback capability also accounts for the requested format, bounded raster
memory, and internal label limits. Direct resources must match the configured
dimensions and format and must include sampled usage. Storage output additionally
requires explicit compute-output presentation support.

Device loss invalidates the host generation and all queued or presented frames.
Stale resources are never revived. A restored producer creates new resources
and a new display surface. Resizing follows the same replacement rule: create
new correctly sized buffers, publish them, then close and release the old
surface after outstanding leases drain.

Normal shutdown closes display surfaces before their namespaces and `GpuHost`.
CBSS rejects host or namespace closure while presentation-retained resources
remain. Device-loss teardown is exempt because the old backend generation is
already invalid and must not receive destruction calls.

## Adapter Boundary

`compositeGpuDirectSurface()` is the renderer-facing bridge. It acquires the
current frame for the duration of one callback and supplies its provider,
opaque backend resource ID, dimensions, format, destination rectangle, opacity,
alpha mode, and revision. The renderer applies the active paint transform, clip, layer, and
stacking scopes.

The SDL3 renderer exposes `setGpuDirectCompositor()` and routes direct-surface
commands through that callback in its normal, Cosmic Text, and layered render
paths. `gpuDirectCompositionStats()` reports the last frame's `noFrame`,
`presented`, `retry`, `unsupported`, and `failed` counts without retaining an
unbounded diagnostic queue. With no compositor installed, direct commands are
reported as unsupported instead of being silently ignored. Closing the renderer
releases the callback holder.

The optional bgfx backend exposes `newBgfxDirectCompositeAdapter(backend,
submit)` for presentation-backend authors. It binds the callback to one bgfx
backend context and resolves a CBSS Texture or a RenderTarget's color attachment
to a typed bgfx texture only for the duration of the synchronous `submit`
callback. The callback receives destination, opacity, alpha, revision, size,
and format metadata, but it does not receive the `GpuDirectSurface` or the
opaque backend resource ID. It must not retain the temporary bgfx handle.

The adapter fails closed before touching bgfx when the host is detached, the
provider is different, the packed resource kind is inconsistent, or the
RenderTarget attachment is invalid. Construction also rejects a mismatched GPU
host API version, non-bgfx context, or nil submit callback. These checks prevent
an ordinary UI node from becoming a general raw-handle escape hatch.

This hook is an adapter boundary, not a claim that SDL's high-level renderer can
import an arbitrary bgfx texture. A direct adapter must still share the actual
GPU device and presentation ordering, and must draw while the callback's active
SDL clip/layer scope is valid. Until the bgfx implementation and visible pixel
tests satisfy that contract, the default display surface continues to select the
readback path.

A production direct adapter must test all of the following together:

- one Device/Queue and one presentation owner;
- GPU output plus ordinary CBSS paint in one ordered frame;
- resize, device loss, cancellation, and shutdown ordering;
- double/triple-buffer backpressure and GPU memory limits; and
- fallback selection when direct composition or a texture format is unsupported.

The deterministic mock suite covers the host and UI state machine under ARC and
ORC. Visible bgfx direct composition remains dependent on the qualified bgfxim
adapter update; it must not be advertised before those real-renderer tests pass.
