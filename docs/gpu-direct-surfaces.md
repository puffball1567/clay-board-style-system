# GPU Display Surfaces

Status: `Same-host direct draw path and asynchronous readback fallback implemented;
visible real-GPU qualification pending`

The normal, failure, edge-case, and pending hardware coverage is tracked in
[GPU Surface Quality Matrix](gpu-surface-test-matrix.md).

`GpuDisplaySurface` is the negotiated UI boundary for displaying a GPU Texture
or RenderTarget. It selects one of three paths without changing the surrounding
Box, Canvas, layout, clipping, opacity, transform, stacking, hit-test, focus,
or accessibility contracts:

- `gdspDirect`: the paint adapter samples a resource from the same GPU host and
  ordered queue without a CPU readback;
- `gdspReadback`: CBSS performs a bounded asynchronous copy into a
  `RasterSurface` and uses the ordinary CPU/SDL renderer.
- `gdspHybrid`: CBSS retains a direct frame and an asynchronous raster copy.
  SDL uses the copy when its active offscreen target cannot accept direct GPU
  composition.

The normal configuration allows the fallback:

```nim
var config = defaultGpuDisplaySurfaceConfig(1280, 720)
config.bufferCount = 3

let display = host.newGpuDisplaySurface(resources, config)
let view = ui.gpuDisplaySurface(display, viewportStyle)
```

Set `config.fallback = gdsfRequireDirect` only when the application has selected
a paint adapter that consumes `pcDrawGpuDirectSurface` from the same
`GpuHost`. The standard bgfx same-host compositor supports its qualified
final-window target. SDL texture-backed offscreen layers have a separate SDL
texture and cannot pass it as a typed bgfx `RenderTarget`.

When a Canvas may be painted inside an SDL texture-backed transform, opacity,
filter, or cached layer, set `config.fallback = gdsfRequireReadback` before
creating the display surface. This selects the asynchronous `RasterSurface`
path even if the host advertises direct presentation, so the ordinary SDL
renderer can include the pixels in its layer. Construction fails if readback is
unavailable for the requested format or byte budget. This is an explicit CPU
transfer, not zero-copy SDL/bgfx texture sharing. Set
`config.fallback = gdsfRequireHybrid` to keep direct presentation for compatible
window passes while also preparing that SDL layer fallback. Both direct and
readback capabilities and their resource budgets are required. The copied frame
may appear later than its direct counterpart while readback completes.

## GPU RGB matrix postprocess

Import `runtime/gpu_color_matrix` and `paint/layer_color_filter` to apply a
Canvas `LayerColorFilter` to a
sampled RGBA8 or BGRA8 Texture or RenderTarget. The source and destination must
be distinct resources in one namespace, with equal dimensions; the destination
is an RGBA8 RenderTarget. Compile `gpuColorMatrixVertexSource()` and
`gpuColorMatrixFragmentSource()` for the selected backend, then create a
`GpuColorMatrixMaterial` from those artifacts outside a frame.

```nim
let filter = colorMatrixFilter([
  0'f32, 0, 1, 0,
  0'f32, 1, 0, 0,
  1'f32, 0, 0, 0
])
let frame = host.beginGpuFrame()
discard material.submit(source, filteredTarget, filter, gcamStraight)
discard display.queueGpuDisplayFrame(filteredTarget, frame)
host.endGpuFrame(frame)
```

The pass evaluates the matrix in encoded sRGB, preserves source alpha, and
stores premultiplied output. Configure the receiving display surface with
`gcamPremultiplied`. An identity filter is represented by `nil`. This pass
filters a GPU-owned surface; Style filters that include ordinary UI descendants
still use their existing CPU layer path.
The shared `brightnessColorFilter`, `contrastColorFilter`,
`saturationColorFilter`, `grayscaleColorFilter`, `invertColorFilter`,
`sepiaColorFilter`, and `hueRotateColorFilter` constructors can be passed
directly to this material or to
`colorMatrixStage()` in an ordered GPU filter chain.

Pass `opacity = 0..1` to `GpuColorMatrixMaterial.submit()` to fade the filtered
result. The opacity multiplies both alpha and premultiplied RGB. It defaults to
one, so existing matrix output is unchanged.

## GPU alpha mask postprocess

Import `runtime/gpu_alpha_mask` to multiply a sampled GPU surface by another
surface's alpha. Compile `gpuAlphaMaskVertexSource()` and
`gpuAlphaMaskFragmentSource()` for the selected backend, then create a
`GpuAlphaMaskMaterial` outside a frame. The source and mask are sampled RGBA8
or BGRA8 Textures or RenderTargets. The destination is a distinct RGBA8
RenderTarget matching the source size. The mask has that size unless it has
explicit placement. Mask RGB is ignored by the default alpha mode.

```nim
let frame = host.beginGpuFrame()
discard maskMaterial.submit(source, coverage, maskedTarget,
  sourceAlphaMode = gcamStraight, invertMask = true,
  maskStrength = 0.5'f32)
discard display.queueGpuDisplayFrame(maskedTarget, frame)
host.endGpuFrame(frame)
```

The pass converts straight source color to premultiplied alpha, then multiplies
color and alpha by the mask coverage. It also accepts premultiplied or opaque
source alpha modes. Set `invertMask = true` to use the complement of mask
coverage. `maskStrength` blends from the unmasked source at `0` to full mask
coverage at `1` and must be finite and normalized. Both options default to
the original alpha-mask behavior. The output uses `gcamPremultiplied` for
presentation.
Set `maskMode = gmmLuminance` to derive coverage from the mask RGB channels
using the [luminance-to-alpha coefficients](https://www.w3.org/TR/filter-effects-1/#attr-valuedef-type-luminancetoalpha)
`0.2126 R + 0.7152 G + 0.0722 B`. For a straight-alpha mask, the result is
multiplied by its alpha. Pass `maskAlphaMode = gcamPremultiplied` for a GPU
render target whose RGB has already been multiplied by alpha, or `gcamOpaque`
to ignore sampled alpha. This pass evaluates the sampled RGB values in their
existing color space; applications needing linear-RGB mask luminance must
convert the mask before this pass. The default `gmmAlpha` continues to use
only the sampled alpha channel. Inversion and strength apply after either
coverage calculation. `alphaMaskStage` accepts both options in a filter chain.
Pass `maskPlacement = gpuAlphaMaskPlacement(x, y, width, height)` to position
and scale a mask of any size in destination pixels. `x` and `y` may be
negative; `width` and `height` must be positive. Outside the placed mask,
coverage is zero before inversion and strength are applied. Omitting the
placement retains the same-size, full-target behavior.
Use `alphaMaskStage(coverage, invertMask, maskStrength, maskPlacement)` in an
ordered filter chain, supplying the `alphaMask` material when constructing it.
The mask must remain distinct from the chain's writable render targets. It may
share the source resource.
Pass `maskFilter = gsfLinear` when constructing `GpuAlphaMaskMaterial` to
interpolate coverage while scaling a placed mask. The default `gsfNearest`
preserves hard pixel edges. The selected filter applies to direct passes and
filter chains that use that material.
Pass `maskCrop = gpuAlphaMaskCrop(x, y, width, height)` to sample a rectangle
from the mask in source pixels. The rectangle must fit inside the mask and have
positive dimensions. A crop may fill the whole destination without a separate
placement, or combine with `maskPlacement` to choose its destination bounds.
Linear sampling clamps to texel centers within the crop, avoiding neighboring
atlas tiles. `alphaMaskStage` accepts the same `maskCrop` argument.

## GPU source-over composition

Import `runtime/gpu_composite` to place one sampled GPU surface over another.
Compile `gpuCompositeVertexSource()` and `gpuCompositeFragmentSource()` for the
selected backend, then create a `GpuCompositeMaterial` outside a frame. Both
inputs may be sampled RGBA8 or BGRA8 Textures or RenderTargets. The distinct
RGBA8 destination matches the backdrop size. The foreground has that size
unless it has explicit placement. The two inputs may share a resource, but
neither may alias the destination.

```nim
let frame = host.beginGpuFrame()
discard composite.submit(backdrop, foreground, combinedTarget,
  backdropAlphaMode = gcamStraight,
  foregroundAlphaMode = gcamPremultiplied,
  blendMode = gcbmMultiply,
  foregroundOpacity = 0.5'f32)
discard display.queueGpuDisplayFrame(combinedTarget, frame)
host.endGpuFrame(frame)
```

The pass converts each input according to its alpha mode, then places the
foreground over the backdrop. The default `gcbmNormal` uses source-over color;
`gcbmMultiply`, `gcbmScreen`, `gcbmOverlay`, `gcbmDarken`, `gcbmLighten`,
`gcbmColorDodge`, `gcbmColorBurn`, `gcbmHardLight`, `gcbmSoftLight`,
`gcbmDifference`, `gcbmExclusion`, `gcbmHue`, `gcbmSaturation`,
`gcbmColor`, and `gcbmLuminosity` apply the corresponding
[W3C blend functions](https://www.w3.org/TR/compositing-1/#blending) with
source-over alpha. Color blending runs on the sampled encoded RGB channels.
Color dodge and burn handle zero and unit color channels explicitly; soft light
uses the specified cubic and square-root curves. Hue, saturation, color, and
luminosity use the specified RGB luminosity weights, saturation transfer, and
bounded color clipping. All sixteen modes accept straight, premultiplied, or
opaque inputs, including transparent pixels.
`gcbmPlusLighter` adds premultiplied foreground and backdrop RGB and alpha,
clamping each channel to one as specified for
[plus-lighter compositing](https://drafts.csswg.org/compositing-2/#plus-lighter).
It works in a direct pass or filter-chain composite stage and supports the
same input alpha modes, foreground opacity, and placement.
`foregroundOpacity` defaults to `1` and accepts finite values from `0` to
`1`. It scales the foreground's premultiplied color and alpha after its alpha
mode is applied, so the same setting works with every blend mode.
Pass `foregroundPlacement = gpuCompositePlacement(x, y, width, height)` to
position a foreground of any size in destination pixels. `x` and `y` may be
negative; `width` and `height` must be positive. The foreground is scaled to
those bounds and clipped by the destination. Outside them, only the backdrop
is visible, including with `gcamOpaque`. Omitting placement retains the
same-size, full-target behavior.
The output is premultiplied RGBA8; present with `gcamPremultiplied`. Use
`compositeStage(foreground, foregroundAlphaMode, blendMode,
foregroundOpacity, foregroundPlacement)` in a filter chain to place an
external foreground over the current stage result.
The foreground must remain distinct from all writable chain targets.
Pass `foregroundFilter = gsfLinear` when constructing
`GpuCompositeMaterial` to interpolate a scaled foreground; the default is
`gsfNearest`. Use a premultiplied foreground with `gcamPremultiplied` for
smooth transparent edges, since hardware filtering interpolates texels before
the composite pass applies its alpha mode. The selected filter also applies
to filter-chain composite stages using that material.
Pass `foregroundCrop = gpuCompositeCrop(x, y, width, height)` to select a
source-pixel rectangle from the foreground. It may fill the destination or
combine with `foregroundPlacement`. The rectangle must fit inside the source
and have positive dimensions. Linear sampling stays within the selected
rectangle, so adjacent atlas tiles do not bleed into the result.
`compositeStage` accepts the same `foregroundCrop` argument.

## GPU Gaussian blur postprocess

Import `runtime/gpu_gaussian_blur` for a separable binomial Gaussian blur with
an integer radius from 0 to 16 pixels. Radius 2 keeps the original five-tap
kernel; radius 0 preserves the source while normalizing alpha. Compile
`gpuGaussianBlurVertexSource()` and
`gpuGaussianBlurFragmentSource()` for the selected backend, then create a
`GpuGaussianBlurMaterial` outside a frame. Provide three distinct same-namespace
resources of equal dimensions: a sampled RGBA8 or BGRA8 Texture or RenderTarget,
a sampled RGBA8 scratch RenderTarget, and an RGBA8 destination RenderTarget.

```nim
let frame = host.beginGpuFrame()
discard blur.submit(source, scratch, blurredTarget,
  sourceAlphaMode = gcamStraight, radius = 16)
discard display.queueGpuDisplayFrame(blurredTarget, frame)
host.endGpuFrame(frame)
```

The first pass blurs horizontally and converts straight input to premultiplied
alpha. The second pass blurs vertically; both passes clamp samples at the image
edge. The output is premultiplied RGBA8, so configure the receiving display
surface with `gcamPremultiplied`. Keep the scratch target available until the
frame's queued work is complete. This is a GPU-owned surface effect; filtering
an ordinary Style subtree still requires a shared GPU offscreen target.

## GPU drop shadow postprocess

Import `runtime/gpu_drop_shadow` for a bounded shadow of a sampled RGBA8 or
BGRA8 Texture or RenderTarget. Compile the Gaussian blur and drop-shadow shader
pairs, then construct `GpuDropShadowMaterial` outside a frame. Supply distinct
same-size RGBA8 RenderTargets for the blur scratch, blurred alpha, and final
output. The material owns its blur material and submits three ordered passes.

```nim
let frame = host.beginGpuFrame()
discard shadow.submit(source, scratch, blurred, shadowTarget,
  8'f32, 6'f32, rgba(0, 0, 0, 0.6),
  sourceAlphaMode = gcamStraight, blurRadius = 16)
discard display.queueGpuDisplayFrame(shadowTarget, frame)
host.endGpuFrame(frame)
```

Offsets are in destination pixels, positive right and down. The tinted blurred
alpha is composited behind the original source in premultiplied RGBA8. Shadow
blur radius accepts the same 0 to 16 pixel range and defaults to 2. Shadow
pixels outside the destination are clipped; provide transparent source padding
if the entire shadow should remain visible. The receiving display surface uses
`gcamPremultiplied`. Ordinary Style subtree shadowing still requires a shared
GPU offscreen composition target.

## Ordered GPU filter chains

Import `runtime/gpu_filter_chain` to combine the RGB matrix, opacity, Gaussian
blur, drop-shadow, alpha-mask, and source-over passes on GPU-owned surfaces. Create only
the materials used by the chain, then supply their references when constructing
it. A chain accepts
one to eight immutable stages. It does not own the materials or render targets.

```nim
let effects = host.newGpuFilterChain(resources,
  [colorMatrixStage(tint), gaussianBlurStage(radius = 4)],
  colorMatrix = matrixMaterial, gaussianBlur = blurMaterial)
let scratch = [scratchA, scratchB, scratchC]
let frame = host.beginGpuFrame()
discard effects.submit(source, filteredTarget, scratch, gcamStraight)
discard display.queueGpuDisplayFrame(filteredTarget, frame)
host.endGpuFrame(frame)
```

The source may be a sampled RGBA8 or BGRA8 Texture or RenderTarget. The
`opacityStage(0..1)` constructor uses the color matrix material without a
separate pipeline. The `dropShadowStage` constructor also accepts
`blurRadius = 0..16`. The
destination and all three scratch resources are distinct, sampled RGBA8
RenderTargets of the same size and namespace. The chain reuses them between
stages, passes premultiplied alpha to each later stage, and returns a
premultiplied RGBA8 destination for a display surface configured with
`gcamPremultiplied`. A non-final shadow may use the destination temporarily;
submit all stages before publishing it. The chain rejects invalid resources,
released materials, presentation-retained write targets, and insufficient
frame work or view capacity before the first pass. `requiredWorkUnits()` reports
the chain's draw count: one for matrix, opacity, mask, or composite, two for
blur, and three for shadow. Direct blur and shadow passes also check their full
draw count before writing. Ordinary Style subtrees still need the shared GPU
offscreen target.

## Raster input for filtered UI display

Import `runtime/gpu_raster_filter_display` to connect an application-owned
`RasterSurface` to a GPU filter chain and a normal `GpuDisplaySurface` UI
attachment. `GpuRasterFilterDisplay` owns the dynamic upload texture, three
scratch RenderTargets, a bounded ring of output RenderTargets, and the display
surface. The chain and its materials remain caller-owned.

```nim
var config = defaultGpuRasterFilterDisplayConfig(
  uint32(raster.width), uint32(raster.height))
config.fallback = gdsfAllowReadback
let filtered = host.newGpuRasterFilterDisplay(resources, raster, effects, config)
let view = ui.gpuDisplaySurface(filtered.displaySurface())

discard raster.publish()
let frame = host.beginGpuFrame()
discard filtered.queueUpdatedGpuRasterFrame(frame)
host.endGpuFrame(frame)
discard view.collectGpuFrame()
```

The adapter uploads only published raster revisions, using dirty rectangles
when possible. An unchanged revision or full presentation ring returns `false`
without filtering or uploading; retry after collecting the display frame.
Before uploading a changed revision, it checks the combined upload, filter,
and readback work against the current frame budget, including readback bytes
and view capacity. A full display or readback ring returns `false` before
uploading. If a budget limit is insufficient, the call raises `GpuHostError`
without uploading or drawing; the published revision remains pending for a
later frame.
Call `filtered.replaceSource(nextRaster)` to switch to another `RasterSurface`
of the same dimensions while keeping the display and Style registrations.
The next queued frame uploads the complete replacement once; subsequent
published dirty regions return to partial uploads. A different size requires
recreating the adapter and its display resources.
Call `filtered.replaceFilterChain(nextEffects)` to change the effect while
keeping the same source, upload texture, display, and Style registrations.
The next queued frame reprocesses the current raster even if its revision is
unchanged, without another texture upload. The replacement chain must belong
to the same host namespace. Keep materials used by already queued frames alive
until those frames complete.
When a chain reads an external GPU resource such as an alpha mask, call
`filtered.requestReprocess()` after changing that resource. The next queued
frame applies the current chain to the unchanged raster without uploading it
again. If the display ring is full, the request remains pending until a frame
can be queued. Collect that frame through the usual display or Style handle to
publish its pixels and invalidate its UI consumers.
The output remains premultiplied on the GPU, and the existing readback path
normalizes it for CPU Canvas presentation. Close the adapter after queued
frames drain, before releasing its chain materials. This provides GPU effects
for retained raster content; automatic capture and filtering of an ordinary
Style subtree still needs the shared GPU offscreen target.

To use the filtered raster as a Style-owned visual rather than a Canvas node,
register it with `ui.registerGpuRasterFilterMaterial()` from
`runtime/gpu_raster_filter_display_ui`. Underlay and overlay stages select the
same direct, readback, or hybrid path. Style masks use the completed readback
pixels in a readback or hybrid display path. Collection invalidates only
components that consumed the material. See
[Custom Paint](custom-paint.md#filtered-raster-material).

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

An unpublished frame can be withdrawn with
`surface.cancelGpuDirectSurfaceFrame(resource)`. Cancellation prevents that
frame from becoming visible. Before the backend accepts its frame boundary,
the resource remains retained and occupies its queue slot. After acceptance,
`collectGpuDirectSurfaceFrame()` releases a previously cancelled frame, or a
new cancellation releases it immediately. Cancellation of a presented
frame returns `false`; closing a surface still waits for the cancelled frame
boundary. Acceptance preserves same-device ordering; it is not a CPU-visible
GPU completion fence.

The queue is bounded to two through eight slots. When full, queueing returns
`false` rather than blocking or allocating. Collection coalesces multiple ready
frames to the latest revision, retires older resources after active leases end,
and invalidates only `ddPaint` for the attached UI node. This supports standard
double and triple buffering without rebuilding layout or hit regions.

## Capability Contract

`GpuBackendInfo` reports direct Texture, RenderTarget, and compute-output
support separately, along with accepted formats, alpha modes, maximum buffer
count, and optional direct-display width and height limits. CBSS validates the
matrix when the host opens. Inconsistent declarations close or detach the
backend and fail the open operation. Surface negotiation checks every axis
before retaining a GPU resource, allowing `GpuDisplaySurface` to select its
readback fallback instead of discovering an incompatible compositor at paint
time.

The bgfx backend defaults all direct capabilities to disabled. A presentation
owner that has passed the real-renderer release gate may opt in with an explicit
profile:

```nim
var options = defaultBgfxHostOptions()
options.directPresentation = newQualifiedBgfxDirectPresentationProfile(
  {gtfRgba8, gtfBgra8},
  maxBuffers = 3,
  textureSupported = true,
  renderTargetSupported = true,
  computeOutputSupported = true,
  alphaModes = {gcamStraight, gcamPremultiplied},
  maxWidth = 4096,
  maxHeight = 4096
)
let backend = newBgfxBackend(options)
```

The constructor rejects an empty format or alpha-mode set, a buffer count
outside two through eight, a profile with no presentation path, and compute
output without Texture presentation. Zero maximum dimensions mean that the
profile adds no limit beyond the backend's general texture limit. The profile
is an assertion by the presentation owner, not a runtime hardware probe. It
must be paired with a compositor created for the same `backend` and must not be
enabled solely because resource creation works.

`gpuDisplaySurfaceCapabilities()` reports both the direct and readback paths.
Readback capability also accounts for the requested format, bounded raster
memory, and internal label limits. Direct resources must match the configured
dimensions and format and must include sampled usage. Storage output additionally
requires explicit compute-output presentation support.

`gpuDirectSurfaceLimitations()` returns a bounded set of typed reasons instead
of requiring callers to infer why direct presentation is unavailable. It
distinguishes host state, presentation path, format, alpha mode, buffer count,
width, height, backend texture limit, and compute-output support. The same set
is included in `GpuDisplaySurfaceCapabilities.directLimitations`, so an
application can choose fallback or diagnostics without parsing backend strings.

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
alpha mode, revision, and the active composition context. That context identifies
whether the current target is the final window or an offscreen layer and carries
the target bounds, effective rectangular clip, a bounded copy of the active
rounded-mask stack, and pixel scale. The fixed-capacity stack avoids renderer
hot-path allocation and fails closed when more than eight rounded clips are
active.

The compositor must preserve those constraints or return `gdcsUnsupported`.
In particular, a callback must not redirect an offscreen-layer submission to the
window or ignore `requiresClipMask`. The surrounding CBSS paint stream remains
responsible for ordering the command among ordinary UI content.
The standard same-host compositor also checks that the context's logical target
size and pixel scale match the current physical window or offscreen target.
After a window resize or DPI change, a stale context returns `gdcsUnsupported`
instead of drawing with the old coordinate mapping.

New integrations should wrap their callback with `newGpuDirectCompositor()` and
declare `GpuDirectCompositeCapabilities`. Target kinds, rectangular clipping,
and rounded clip masks are checked before CBSS acquires a presentation lease.
After acquiring the current frame, CBSS also checks the declared source
provider, Texture/RenderTarget kind, format, alpha mode, and optional maximum
dimensions before invoking the backend callback. Rejection releases the lease
in the same call. The SDL renderer retains a proc-only setter for source
compatibility, but that overload necessarily assumes the callback can process
every target and source context.

The bgfx helper requires exact source-kind, format, alpha-mode, and dimension
coverage between its qualified host profile and typed compositor. A profile
therefore cannot advertise a direct Surface that its installed compositor
would later reject.

The SDL3 renderer exposes `setGpuDirectCompositor()` and routes direct-surface
commands through that callback in its normal, Cosmic Text, and layered render
paths. `gpuDirectCompositionStats()` reports the last frame's `noFrame`,
`presented`, `retry`, `unsupported`, and `failed` counts without retaining an
unbounded diagnostic queue. With no compositor installed, direct commands are
reported as unsupported instead of being silently ignored. Closing the renderer
releases the callback holder.

For the normal one-host path, `newGpuHostDirectCompositor()` creates a typed
compositor over the same `GpuHost` that owns the published source. The caller
opens one host frame around the surrounding paint stream. The compositor adds
one draw to that frame and never calls Present independently. Its pipeline,
vertex buffer, uniforms, and sampler remain in a compositor namespace. Only a
sampled Texture or RenderTarget already retained by a presentation surface may
cross from the producer namespace, so this path does not weaken ordinary
namespace isolation.

CBSS publishes the matching portable shader sources through
`gpuHostDirectCompositeVertexSource()` and
`gpuHostDirectCompositeFragmentSource()`. Rounded composition uses the separate
`gpuHostDirectCompositeMaskedFragmentSource()` variant, so an unmasked draw does
not pay the rounded-mask branch cost. They use this interface:

- a full-viewport `POSITION` and `TEXCOORD0` vertex stream;
- sampler `s_cbssSurface` at the material's configured texture stage;
- `u_cbssComposite = (opacity, alphaMode, 0, 0)`; and
- `u_cbssUvRect = (u0, v0, u1, v1)`.

The masked variant additionally consumes the fixed `u_cbssClipMasks[17]`
array. Its header is `(maskCount, visibleWidth, visibleHeight, pixelScale)`;
each of the eight bounded entries uses one local-bounds `vec4` and one radius
`vec4`. Every active nested rounded clip participates in fragment coverage with
a one-physical-pixel antialiased edge. Materials opt in by providing the typed
array uniform and one masked pipeline per advertised alpha mode.

The sources use the build-only shader pipeline described in
[GPU Shader Authoring And Packaging](gpu-shaders.md). Straight,
premultiplied, and opaque sources use distinct material pipelines;
`alphaGpuBlendState()` and `premultipliedAlphaGpuBlendState()` provide the
standard blend contracts. Rectangular clips become one physical viewport and
a cropped UV rectangle, so clipping does not stretch the source image. Empty
intersections produce no draw. Bounded rounded masks are implemented for both
final-window and typed same-host offscreen targets; overflow fails closed.

GPU-native renderers may set `offscreenTarget` to a live CBSS `RenderTarget`
owned by the compositor namespace. The standard compositor checks its kind,
namespace, generation, dimensions, usage, and source/target feedback before
placing it in the graphics pass. This is a CBSS handle, not a backend handle,
and remains valid only for the synchronous composition call. The standard
same-host compositor requires this typed target for offscreen drawing and
rejects an SDL texture-backed target before acquiring a frame lease. The
explicit readback path above can paint those SDL layers; zero-copy mixed
SDL/GPU layer integration remains a separate real-renderer release gate.

The optional bgfx backend exposes `newBgfxDirectCompositeAdapter(backend,
submit)` for presentation-backend authors. It binds the callback to one bgfx
backend context and resolves a CBSS Texture or a RenderTarget's color attachment
to a typed bgfx texture only for the duration of the synchronous `submit`
callback. The callback receives destination, opacity, alpha, revision, size,
format, and composition-context metadata, but it does not receive the `GpuDirectSurface` or the
opaque backend resource ID. It must not retain the temporary bgfx handle.
`newBgfxDirectCompositor()` combines this scoped adapter with the capability
preflight and is the preferred entry point for new presentation backends. It
narrows the provider capability to bgfx and requires source kinds and formats
to exactly match the backend's qualified direct-presentation profile. This
prevents the host from selecting a direct path that the installed compositor
cannot draw.

The adapter fails closed before touching bgfx when the host is detached, the
provider is different, the packed resource kind is inconsistent, or the
RenderTarget attachment is invalid. Construction also rejects a mismatched GPU
host API version, non-bgfx context, or nil submit callback. These checks prevent
an ordinary UI node from becoming a general raw-handle escape hatch.

These hooks are an adapter boundary, not a claim that SDL's high-level renderer can
import an arbitrary bgfx texture. A direct adapter must still share the actual
GPU device and presentation ordering. SDL textures used for transform, opacity,
and cached layers are not bgfx render targets; the context exposes these cases
so a compositor can fail closed rather than draw into the wrong target. Until
visible pixel tests satisfy that contract, the default profile continues to
make display surfaces select the readback path. Constructing the same-host
compositor does not implicitly enable or broaden a backend profile.

For an SDL-created native window, use
`bgfxPlatformDataFromSdl3Window()` before opening the bgfx host. This removes
application-side native-property probing while preserving the rule that only
one renderer owns presentation.

A production direct adapter must test all of the following together:

- one Device/Queue and one presentation owner;
- GPU output plus ordinary CBSS paint in one ordered frame;
- resize, device loss, cancellation, and shutdown ordering;
- double/triple-buffer backpressure and GPU memory limits; and
- fallback selection when direct composition or a texture format is unsupported.

The deterministic mock suite covers the host, cross-namespace presentation
binding, clip/UV calculation, RenderTarget attachment resolution, and UI state
machine under ARC and ORC. The standard shader pair is compiled with the
official bgfx `shaderc`. Visible bgfx direct composition must still pass the
real-renderer tests before it is advertised as a production-qualified path.
