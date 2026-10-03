# Custom Paint

Custom Paint lets an ordinary `UiStyle` reference a named paint material. The
Style stores only a stable material identifier and stage. Backend objects,
callbacks, textures, and pipelines remain in the `UiRoot`-owned registry and
never enter style resolution or layout.

```nim
let ui = initUiRoot()
let panel = ui.box(uiStyle([
  decl("width", px(240)),
  decl("height", px(96)),
  decl("border-radius", px(12)),
  decl("overflow", keyword("hidden")),
  customPaint(
    "panel-accent",
    cpsUnderlay,
    parameters = [
      customPaintFloat("phase", 0.25),
      customPaintColor("accent", rgb(0.12, 0.48, 0.82))
    ]
  )
]))

discard ui.registerCustomPaintMaterial(
  "panel-accent",
  proc(request: CustomPaintRequest): seq[PaintCommand] =
    let accent = request.parameters.findCustomPaintParameter("accent")
    let color =
      if accent.isSome: accent.get.colorValue
      else: rgb(0.12, 0.48, 0.82)
    @[
      fillRect(
        request.bounds,
        rgba(color.r, color.g, color.b, request.opacity),
        owner = some(request.owner)
      )
    ],
  {cpsUnderlay}
)
```

`cpsUnderlay` paints after the owner's background and border but before its
children. `cpsOverlay` paints after the children. `cpsMask` renders an alpha
mask over the owner's complete isolated visual subtree, including its ordinary
paint, RenderSurface content, children, overlay, and scrollbars. CBSS clips
each returned command stream to the owner's resolved bounds and border radius.
The material does not add layout, hit-test, focus, or accessibility nodes.

Mask RGB values do not affect the result; only the rendered alpha is used.
An empty successfully resolved mask makes the owner transparent. A missing or
invalid mask provider leaves the owner unmasked and emits a bounded diagnostic,
so a bad optional visual capability does not erase otherwise usable UI.

The host should build commands through the `UiRoot` overload so Canvas and
Custom Paint providers cannot be omitted accidentally:

```nim
let commands = ui.buildPaintCommands(styles, layout)
```

## Typed Material Parameters

Custom Paint declarations can carry an immutable, ordered parameter snapshot.
The supported kinds are `float32`, `int64`, `bool`, `vec2`, `vec4`, and
`Color`. Providers receive these values directly in `CustomPaintRequest`; they
do not parse strings during paint.

Parameter names use the portable shader-identifier subset
`[A-Za-z_][A-Za-z0-9_]*`, are limited to 64 bytes, and must be unique within a
declaration. A declaration accepts at most 64 parameters. Floating-point,
vector, and color components must be finite. Unsigned integers that do not fit
in `int64` are rejected rather than wrapped.

An empty declaration retains no parameter allocation. Non-empty snapshots live
in the computed style's cold Custom Paint storage and are shared read-only with
the paint callback. They do not enlarge the hot layout or hit-test records and
are not copied once per frame.

The parameter contract is backend-neutral. A CPU provider may consume it
directly, while a GPU provider can map the same typed values to validated
uniform or storage bindings. This change does not expose a bgfx handle through
Style. C ABI `0x0001001D` exposes the equivalent values through a fixed-layout
parameter view and a separate bounded name accessor rather than Nim object or
closure layout.

## Style Color Filters

Nim applications can register a typed RGB matrix provider for `cpsFilter`:

```nim
let invert = colorMatrixFilter([
  -1.0'f32, 0, 0, 1,
  0.0'f32, -1, 0, 1,
  0.0'f32, 0, -1, 1
])
discard ui.registerCustomPaintFilter(
  "invert-panel",
  proc(request: CustomPaintRequest): LayerColorFilter = invert
)
let filtered = ui.box(uiStyle([
  width(240), height(160), customPaint("invert-panel", cpsFilter)
]))
```

The callback receives the same owner, resolved bounds, and immutable typed
parameters as drawing materials. It returns a `LayerColorFilter`, rather than
paint commands, and must not raise or block. Build immutable matrices outside
the callback when possible. A nil result is an identity filter; missing and
stage-mismatched providers leave ordinary content visible and emit the usual
bounded diagnostics.

A resolved non-identity filter isolates the owner's background, border,
underlay, RenderSurface content, descendants, overlay, scrollbars, and mask
within its bounds and border radius. The completed group is color-transformed
before applying the owner's inherited opacity once. The filter callback receives
opacity 1 and the owner's content starts at opacity 1 inside the isolated group;
descendants still apply their own opacity. Alpha and transparent coverage are
preserved by the RGB matrix.
The PPM reference and SDL3 use the same retained layer filter contract described
in [Render Surfaces](render-surfaces.md#layer-color-filters).

A Box with a filter declaration establishes a local paint-order boundary.
Positive-z descendants are sorted and drawn inside that boundary, including
when the material is missing or resolves to identity. They cannot escape the
filter to overlay unrelated higher-level content. Nested filter groups apply
inside out. `buildPaintCommandsForSubtree` expands a descendant repaint to the
outermost enclosing filter Box, since filtering only one child's pixels cannot
reproduce the combined group. Consumers of subtree command streams must treat
that returned group as one repaint unit. `paintGroupRoot(tree, styles, node)`
returns its root, allowing dynamic/static partitions to include all of that
group's descendants. Unfiltered nodes keep their original subtree root.

`registerCustomPaintFilterTracked` returns the same generation-safe registration
token as drawing materials. Names, replacement, unregister, and consumer-only
paint invalidation share the existing registry. Call
`invalidateCustomPaintMaterial(name)` after changing state used by a callback;
this does not trigger style resolution or layout. A name supports either a
drawing provider or a filter provider, and explicit replacement can switch
between them. `registerCustomPaintMaterial` still rejects `cpsFilter`, preventing
a drawing command callback from being mistaken for a filter.

C ABI `0x00010028` also supports Style RGB filter registration, as described
below. Foreign command-sink providers can author filtered layers with
`cbss_custom_paint_sink_begin_layer_color_matrix` from ABI `0x00010027`.
`GpuCanvasSurface` materials continue to support drawing and masks; spatial
filters and shader post-processing remain follow-ups.

## Foreign Provider Boundary

Foreign-language Craft Drivers can install a material with
`cbss_context_register_custom_paint_provider`. The callback receives a
versioned `CbssCustomPaintRequest` and an opaque `CbssCustomPaintSink` that is
valid only until the callback returns. Sink coordinates are local to
`request.local_bounds`; CBSS translates them into the owner's resolved bounds
and applies the owner's opacity and clip during composition.

The sink exposes the same bounded 2D primitives as the retained C Canvas:
transform and save/restore scopes, clips, layers, rectangles, gradients,
stroked and filled paths with nonzero/evenodd rules, text, images, and
`RasterSurface` composition. It is a command boundary,
not a second tree, event loop, hit-test system, or presentation owner.
The dashed-stroke entry point copies and validates its dash array during the
callback. Odd-length arrays repeat once, offsets are retained, and bounded
outline expansion prevents caller-controlled dash density from creating
unbounded work.

`cbss_style_set_custom_paint` copies the material name and up to 64 typed
parameters. Provider registration takes ownership of callback user data only
on success. Replacement, unregister, context reset, and context destruction
invoke the optional release callback exactly once. Registration tokens are
context-local, monotonically allocated, and generation-safe; stale tokens
cannot remove a replacement. Release callbacks must not re-enter the same
context; CBSS rejects provider lifecycle changes while a release callback is
running.

### Foreign Style Filters

Register `CBSS_CUSTOM_PAINT_STAGE_FILTER` alone through the existing provider
registration function. Combining FILTER with any drawing stage returns
`CBSS_INVALID_ARGUMENT` without taking ownership of the user data.

```c
static CbssStatus invert_filter(const CbssCustomPaintRequest *request,
                               CbssCustomPaintSink *sink, void *user_data) {
  (void)request;
  (void)user_data;
  const CbssRgbColorMatrix invert = {{
    -1, 0, 0, 1, 0, -1, 0, 1, 0, 0, -1, 1
  }};
  return cbss_custom_paint_sink_set_color_matrix(sink, invert);
}

CbssCustomPaintRegistration registration = 0;
CbssStatus status = cbss_context_register_custom_paint_provider(
    context, "invert-panel", CBSS_CUSTOM_PAINT_STAGE_FILTER,
    invert_filter, NULL, NULL, 0, &registration);
```

The callback receives the same owner, bounds, and copied typed parameters as a
drawing provider, with request opacity 1. It may query parameters and call
`cbss_custom_paint_sink_set_color_matrix`; drawing and scope commands return
`CBSS_NOT_AVAILABLE` in this stage. The setter copies all 12 finite coefficients,
and the last successful call wins. Invalid coefficients leave the preceding
matrix intact. No setter call or an identity matrix leaves the colors unchanged.
The sink and its parameter views expire when the callback returns.

A non-OK callback result discards its matrix, records a context error, and
leaves ordinary content visible. CBSS resets the result before every callback,
so a preceding frame's filter cannot leak into an identity or failed result.
Successful matrices use the same complete visual group, mask, local overlay,
and owner-opacity semantics as Nim filter providers. Registration tokens,
replacement, unregister, reset/destruction release callbacks, and paint-only
invalidation use the existing provider lifecycle; lifecycle changes during a
provider callback are rejected.

## GPU Canvas Material

A `GpuCanvasSurface` can be registered behind the same Style contract. One GPU
frame is queued per material, even when several components reference it.
Completed pixels invalidate only the components that consumed that material.

```nim
var accent = ui.registerGpuPaintMaterial(
  "panel-accent",
  gpuCanvas,
  {cpsUnderlay, cpsMask}
)

let queued = accent.queueGpuFrame()
# Submit/end the owning GpuHost frame here.
let published = accent.collectGpuFrame()

discard accent.unregister()
```

The current bridge uses the bounded GPU-to-`RasterSurface` readback path, which
also makes GPU-produced alpha masks available without exposing a GPU handle to
Style. It is backend-neutral above `GpuCanvasSurface`; the optional bgfx
implementation and its `bgfxim` dependency stay behind the adapter boundary.

## Failure And Ownership Rules

- Material names are non-empty, bounded to 256 bytes, and cannot contain
  control characters or surrounding whitespace.
- Material parameters are immutable after authoring, bounded in name length and
  count, unique by name, finite where applicable, and retained outside hot
  layout data.
- Duplicate names are rejected unless generic registry replacement is
  explicitly requested.
- Tracked registrations carry a generation. Removing an old registration can
  never remove a newer replacement with the same name.
- Material callbacks execute during paint-command construction on the UI
  thread. They may return at most 4,096 commands and must not perform blocking
  work.
- Transform, clip, and layer pushes must be balanced. An invalid command stream
  is rejected before composition.
- Missing materials fail closed and emit deduplicated diagnostics. Diagnostics
  are bounded so malformed content cannot grow memory without limit.
- `cpsMask` uses retained destination-in layer composition in the deterministic
  PPM and SDL3 backends. SDL3 renderers with custom blend support stay on the
  accelerated one-pass path; software renderers use a bounded 64 MiB temporary
  working set only for the affected mask region.
- `cpsFilter` accepts typed RGB filter providers registered through
  `registerCustomPaintFilter`. Registering or resolving a provider at a stage
  it does not support fails explicitly.
- GPU work and readback remain application-scheduled. Custom Paint does not
  create a second frame loop or take presentation ownership.

The optional bgfx adapter is tested against an explicit `bgfxim` revision.
Changing that revision requires the optional adapter contract on Linux,
Windows, and macOS plus the available real-runtime GPU checks; a dependency
update does not change this public material contract.

The declaration, registry, and callback-scoped command boundary are available
to Nim and through the current C ABI. Foreign callers never depend on Nim
closure layout or backend handles.
