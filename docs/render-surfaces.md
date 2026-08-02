# Render Surfaces And Canvas

Status: `Version 0.3 development API`

CBSS render surfaces let a retained drawing module occupy the content area of
an ordinary styled Box. CBSS owns layout, padding, borders, clipping, opacity,
stacking, input routing, and lifecycle. The mounted surface owns only its
local drawing commands and resources.

The API is independent of SDL3. `Canvas2D` converts its retained local display
list into the canonical CBSS paint-command stream; the normal backend then
renders those commands. This avoids a second interpretation of CBSS styles.

## Basic Canvas

```nim
import clay_board_style_system

let ui = initUiRoot()
let app = ui.box(uiStyle([
  decl("width", px(640)),
  decl("height", px(360))
]))

let chart = newCanvas2D()
chart.fillLinearGradient(
  rect(0, 0, 280, 140),
  LinearGradient(
    angle: 90,
    interpolationSpace: cisOklab,
    stops: @[
      colorStop(oklch(0.72, 0.16, 250).resolveColor(), 0),
      colorStop(oklch(0.62, 0.20, 310).resolveColor(), 100)
    ]
  ),
  radius = 8
)

let chartHost = ui.canvas(
  chart,
  uiStyle([
    decl("width", px(300)),
    decl("height", px(160)),
    decl("padding", px(10)),
    decl("border-width", px(1)),
    decl("border-color", rgb(0.25, 0.28, 0.34))
  ]),
  parent = some(app),
  code = "sales-chart"
)
```

Canvas coordinates begin at `(0, 0)` inside the host's padding and border.
Changing window placement, ancestor scroll offsets, or DPI does not require
rebuilding the retained Canvas display list.

## Lifecycle

`RenderSurfaceDescriptor` provides optional callbacks for:

- mount and revision update;
- resize and pixel-scale changes;
- input in surface-local coordinates;
- requested frames;
- effective visibility;
- device loss and restoration; and
- unmount.

`RenderSurfaceRegistry` assigns stable IDs and owns lifecycle state. Mounting
the same surface twice is an error. Unmount and unregister are deterministic;
`UiRoot.disposeSubtree` unregisters every surface owned by the removed
subtree. Callback order is registration order where ordering is observable.

Placement bounds and clips use host presentation coordinates. Pointer input
contains both the original `InputEvent` and an optional local position.
Uncaptured input outside the effective clip is rejected. Pointer capture is an
explicit host decision and is not inferred from the mere presence of a pointer
position.

The same lifecycle is available to foreign-language hosts through
`include/cbss.h`. A `CbssRenderSurfaceCallback` receives the versioned event
union, while the host retains ownership of its renderer and resources. See
[c-api.md](c-api.md#render-surfaces) for the C event-loop contract.

## Frame Scheduling

A surface does not receive continuous frames by default. It calls
`requestFrame()` or returns `rsfRequestNext` from `onFrame` while work remains.
Returning `rsfIdle` stops the sequence. Hidden or device-lost surfaces retain
a pending request but do not execute it until they become renderable again.

The application loop connects pending work to `FrameScheduler`:

```nim
ui.scheduleRenderSurfaceFrames(scheduler, nowSeconds)
discard ui.runRenderSurfaceFrames(scheduler, nowSeconds, 60.0)
```

The target rate must be positive and finite. An idle UI has no Canvas deadline
and can return to the SDL event wait path.

## Canvas Commands

The initial retained command set includes nested clips, filled and stroked
rectangles, rounded rectangles, open and closed paths, adaptive quadratic and
cubic curves, configurable line caps and joins, linear gradients, text, and
images. Use `strokeLine` for one segment, the point overload of `strokePath`
for a polyline, or build a retained `Path2D` with `moveTo`, `lineTo`,
`quadraticCurveTo`, `bezierCurveTo`, and `closePath`. Every mutation increments
the Canvas revision. A frame callback may replace only the Canvas commands
without rebuilding or resolving the surrounding UI tree.

Unbalanced authored clip pushes are closed at the paint boundary. Extra pops
are ignored so a surface cannot corrupt the surrounding CBSS clip stack.

## Current Limits

The Version 0.3 contract is still in development. The following are not yet
runtime-complete:

- Canvas save/restore transforms, blend modes, and offscreen surfaces;
- C ABI drawing commands beyond the implemented RenderSurface lifecycle; and
- GPU/shared-texture surface paths.

Resolved box transforms already use one affine contract across SDL3 and
headless paint, hit tests, clips, and RenderSurface-local input. Canvas-authored
save/restore transforms are a separate command API and remain release work
rather than a silent backend difference.
