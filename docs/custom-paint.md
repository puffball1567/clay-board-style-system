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
  customPaint("panel-accent", cpsUnderlay)
]))

discard ui.registerCustomPaintMaterial(
  "panel-accent",
  proc(request: CustomPaintRequest): seq[PaintCommand] =
    @[
      fillRect(
        request.bounds,
        rgba(0.12, 0.48, 0.82, request.opacity),
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

The declaration and registry contract in this first slice is a Nim API. A
versioned C ABI for registering foreign material providers remains Version 0.7
work; foreign callers must not depend on Nim closure layout or backend handles.
