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
children. `cpsOverlay` paints after the children. CBSS clips each returned
command stream to the owner's resolved bounds and border radius. The material
does not add layout, hit-test, focus, or accessibility nodes.

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

`cbss_style_set_custom_paint` copies the material name and up to 64 typed
parameters. Provider registration takes ownership of callback user data only
on success. Replacement, unregister, context reset, and context destruction
invoke the optional release callback exactly once. Registration tokens are
context-local, monotonically allocated, and generation-safe; stale tokens
cannot remove a replacement. Release callbacks must not re-enter the same
context; CBSS rejects provider lifecycle changes while a release callback is
running.

## GPU Canvas Material

A `GpuCanvasSurface` can be registered behind the same Style contract. One GPU
frame is queued per material, even when several components reference it.
Completed pixels invalidate only the components that consumed that material.

```nim
var accent = ui.registerGpuPaintMaterial(
  "panel-accent",
  gpuCanvas,
  {cpsUnderlay}
)

let queued = accent.queueGpuFrame()
# Submit/end the owning GpuHost frame here.
let published = accent.collectGpuFrame()

discard accent.unregister()
```

The current bridge uses the bounded GPU-to-`RasterSurface` readback path. It is
backend-neutral above `GpuCanvasSurface`; the optional bgfx implementation and
its `bgfxim` dependency stay behind the adapter boundary.

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
- `cpsMask` and `cpsFilter` declarations are accepted and retained, but their
  retained-layer composition is not implemented yet. They fail closed with an
  explicit unsupported-stage diagnostic.
- GPU work and readback remain application-scheduled. Custom Paint does not
  create a second frame loop or take presentation ownership.

The optional bgfx adapter is tested against an explicit `bgfxim` revision.
Changing that revision requires the optional adapter contract on Linux,
Windows, and macOS plus the available real-runtime GPU checks; a dependency
update does not change this public material contract.

The declaration, registry, and callback-scoped command boundary are available
to Nim and through the current C ABI. Foreign callers never depend on Nim
closure layout or backend handles.
