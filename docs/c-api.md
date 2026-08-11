# CBSS C ABI

The C ABI is CBSS's language-neutral runtime boundary. Nim remains the primary
authoring API, while C++, Rust, Zig, Swift, and other native languages can
build wrappers over the same engine without depending on Nim object layouts.

## Build

```sh
nimble buildCAbiShared
nimble buildCAbiStatic
nimble testCAbi
nimble testCAbiOrc
```

The C ABI includes a worker-to-UI stream transport and is therefore compiled
with Nim thread support. Use `--threads:on` when invoking `nim c` directly;
the Nimble tasks already supply it.

The development tasks write artifacts outside the repository:

```text
/tmp/libcbss.so
/tmp/libcbss.a
```

The installed header is `include/cbss.h`.

## Current Pipeline

ABI version `0x00010010` supports:

- Opaque context and style handles.
- Atomically reference-counted immutable Blob handles with advisory MIME
  metadata, bounded reads into host buffers, and a 64 MiB eager-construction
  limit. Blob storage does not expose Nim-managed pointers.
- Host-authorized fixed-size Blob providers for files, mappings, decoders, and
  foreign buffers. Provider data is read lazily into caller-owned buffers,
  reads on one Blob are serialized, and the host context is released exactly
  once after the final Blob reference.
- Ordered immutable FormData handles built through an explicit builder. Text
  entries preserve repeated names, Blob entries retain shared Blob handles,
  and every returned Blob owns one reference that the caller releases. Finished
  snapshots use shared raw storage and expose no Nim-managed pointer.
- Bounded Blob streams with atomically retained producer handles, declared-byte
  backpressure, coalesced host-loop wake callbacks, ordered UI-thread pumping,
  progress, terminal states, cancellation, and deterministic late-offer
  rejection. Stream payloads cross the ABI only as retained Blob handles.
- Generation-checked node handles plus box, text, and image node creation.
- Groups, attributes, pseudo-state flags, and accessibility semantics.
- Typed length, number, keyword, color, color-pair, border, shadow, gradient,
  and transform declarations.
- Append-only `lh`, `rlh`, `ex`, `ch`, `rex`, and `rch` unit tags. The C ABI
  uses deterministic CSS fallback font metrics because concrete text engines
  remain an application-side adapter concern.
- Opaque authored-color handles for typed color spaces, `currentColor`,
  serialized CSS colors, and `color-mix()`, without changing the stable
  16-byte resolved `CbssColor` value.
- Replaceable per-node and per-state style application.
- Style resolution, intrinsic sizing, and flex layout.
- Layout-box and node-rectangle queries.
- Renderer-neutral paint-command iteration.
- Text/image payload, basic computed text style, and gradient-stop queries.
- Append-only paint kinds for retained paths and 2D transform scopes, including
  path-segment/stroke metadata and affine-matrix queries. Existing paint-kind
  values remain unchanged.
- Append-only bounded layer paint scopes. `CBSS_PAINT_PUSH_LAYER` stores bounds
  in `rect`, opacity in `value0`, and `CbssLayerCompositeMode` in `value1`;
  `CBSS_PAINT_POP_LAYER` closes the scope.
- A retained Canvas drawing adapter on every registered RenderSurface. Foreign
  libraries append local drawing commands and publish the complete display-list
  update with one `cbss_render_surface_canvas_commit`.
- Hit testing.
- Replaceable C callbacks and removable additive subscriptions for all CBSS
  event kinds, including bubbling through ancestors.
- Pointer, touch, pen, keyboard, text, wheel, and component-event dispatch.
- Stable event `target`/`current_target`, target and bubble phase flags,
  bubbling/cancelability metadata, and independent handled,
  stop-propagation, and prevent-default callback result bits. Dispatch summaries
  retain the legacy `handled` byte and expose the complete bitset as `outcome`.
- An additive opaque `CbssEventView` callback contract for managed event
  payloads. Existing `CbssEventCallback` signatures and the 128-byte
  `CbssEvent` layout remain unchanged. Submit views expose an owning retained
  FormData snapshot, while a synthetic submit without a snapshot reports
  `CBSS_NOT_AVAILABLE`.
- Optional pointer-device metadata with stable-in-process device IDs, contact,
  button, eraser, and proximity state. A capability bitmask distinguishes an
  unavailable pen axis from a supported axis whose value is zero; timestamps,
  pressure,
  tangential pressure, x/y tilt, rotation, distance, and slider values cross
  both ordinary event callbacks and RenderSurface input callbacks.
- Hover, active, focus, focus-visible, pointer-capture, and focus-scope state.
- Tab and Shift+Tab focus traversal.
- Retained scrolling and scrollbar interaction without layout recomputation.
- Versioned RenderSurface registration, Box attachment, placement, local input,
  explicit frame requests, pixel-scale resize, visibility, device recovery,
  and deterministic unmount callbacks.
- Accessibility roles, including semantic links and switches, plus name,
  description, value, range, relation, and hidden-state queries for platform
  adapters.
- Structured diagnostics and a context error message.

Platform accessibility transports, native resource loading, operating-system
window ownership, and final execution of paint commands remain host adapters.
The ABI exposes the semantics and renderer-neutral data those adapters need.

`cbss_style_set_linear_gradient` retains its sRGB interpolation behavior.
`cbss_style_set_linear_gradient_in` accepts a
`CbssColorInterpolationSpace`. For `CBSS_PAINT_FILL_LINEAR_GRADIENT`, paint
command `value0` is the angle, `value1` is the stop count, and `value2` is that
interpolation-space enum, so a foreign renderer can reproduce CBSS sampling.
`cbss_style_set_linear_gradient_color_values` accepts wide-gamut,
`currentColor`, and color-mix handles as gradient stops. It resolves them only
when the style context is computed and copies every handle value during the
setter call.

## Host Event Loop

After the initial `cbss_context_compute`, feed backend events through
`cbss_context_dispatch_input`. The returned `CbssDispatchSummary` distinguishes
two update paths:

- `paint_changed != 0`: paint commands and hit regions were patched by CBSS.
  This is used for retained scrolling and does not require layout.
- `needs_compute != 0`: style, content, focus, hover, or active state changed.
  Call `cbss_context_recompute` before consuming the next paint snapshot.

`cbss_context_recompute` reuses the last successful viewport size. A resize
uses `cbss_context_compute` with the new dimensions.

## Worker-To-UI Blob Streams

`CbssBlobStream` is owned by the UI thread. Create a producer with
`cbss_blob_stream_producer`, retain it when another native owner needs a copy,
and move that retained handle to a worker thread. A thread created outside Nim
must call `cbss_thread_attach` before its first CBSS call and
`cbss_thread_detach` before exiting; first-party language wrappers should hide
that pair in their worker adapter. Producer calls are
non-blocking and return a `CbssStreamOfferResult`; backpressure is an ordinary
result, not an allocation request or an instruction to grow the queue.

The host may install one `CbssStreamWakeCallback`. It must only post a wake to
the host event loop. Offers are coalesced until the UI pumps all pending work,
so an idle application does not poll. Replacing or clearing the callback waits
for an already-running callback before returning, after which the host may
release the old `user_data`.

On the owning UI thread:

1. call `cbss_blob_stream_pump` after a wake;
2. consume events with `cbss_blob_stream_next` until it returns
   `CBSS_NOT_AVAILABLE`;
3. release the Blob returned by every `CBSS_STREAM_EVENT_DATA` event; and
4. pump again before blocking when `CbssStreamPumpResult.pending` is nonzero.

`CBSS_STREAM_EVENT_ERROR` reports the complete message length in
`message_bytes`; copy the retained terminal message with
`cbss_blob_stream_error_message`. Destroying the stream disposes queued work,
waits for an in-flight wake callback, and makes escaped producer handles return
`CBSS_STREAM_OFFER_DISPOSED`. The producer handle itself remains valid until
its final `cbss_stream_producer_release`.

Event handlers are installed with `cbss_node_set_event_handler`. Reinstalling
the same node/event pair replaces the callback; passing a null callback removes
it. Independent observers use `cbss_node_subscribe_event`, retain the returned
`CbssEventSubscription`, and remove it with
`cbss_context_unsubscribe_event`. The callback returns a bitwise combination of
`CBSS_EVENT_OUTCOME_*`:
`HANDLED` records handling, `STOP_PROPAGATION` stops traversal after the current
target, and `PREVENT_DEFAULT` suppresses a cancelable intrinsic action when the
hosted component defines one. Returning `1` remains the handled-only form.
Callbacks may update nodes and styles, but must not destroy or reset the
context currently dispatching. The callback and `user_data` remain owned by the
host.

Use `cbss_node_set_event_view_handler` or
`cbss_node_subscribe_event_view` when a callback needs a managed payload. The
view and the pointer returned by `cbss_event_view_event` are borrowed only for
that callback. `cbss_event_view_form_data` returns a retained owning handle;
the caller releases it even when it keeps the snapshot after the callback.
An intentionally empty submitted form returns `CBSS_OK` and a zero-length
handle. An event with no FormData returns `CBSS_NOT_AVAILABLE` and a null
output. `cbss_context_emit_submit` converts an immutable C FormData handle to
the same Nim submit-event contract used by first-party forms. The older
`cbss_context_emit_event` can still emit a payload-free synthetic submit.

## Render Surfaces

`cbss_context_register_render_surface` registers a host-owned drawing surface.
Attach the returned 64-bit ID with `cbss_context_add_render_surface`; the node
then participates in ordinary layout, clipping, scrolling, hit testing, and
input routing. The surface receives one multiplexed
`CbssRenderSurfaceCallback` with mount, update, resize, input, frame,
visibility, device-loss, restoration, and unmount event kinds.

Input coordinates remain in the original presentation space in
`event.input`. When `CBSS_SURFACE_HAS_LOCAL_POSITION` is set, `local_x` and
`local_y` identify the same point relative to the surface content area.
Returning `CBSS_SURFACE_HANDLED` consumes input. Returning
`CBSS_SURFACE_REQUEST_NEXT_FRAME` from a frame callback schedules exactly one
additional frame; otherwise the surface becomes idle.

Hosts call `cbss_render_surface_request_frame` when new work arrives and
`cbss_context_run_render_surface_frames` at the selected frame deadline.
`cbss_context_needs_render_surface_frame` lets an event loop remain blocked
while no visible surface needs work. Set the output scale with
`cbss_context_set_pixel_scale`; a size change is delivered before subsequent
drawing. The callback does not expose SDL renderer internals.

## RenderSurface Canvas Adapter

Every registered surface owns a private retained Canvas display list. The
`cbss_render_surface_canvas_*` functions modify that list in surface-local
coordinates without exposing Nim, SDL3, renderer, texture, or allocation types
across the ABI.

A normal update is transactional at the presentation boundary:

1. call `cbss_render_surface_canvas_clear` when replacing the previous list;
2. append drawing and scope commands;
3. call `cbss_render_surface_canvas_commit` once.

Command appends do not recompute style or layout and do not alter the visible
paint snapshot before commit. Commit publishes a new surface
revision, issues the ordinary RenderSurface update callback when mounted, and
refreshes only presentation data when the context has already been computed.
Calling commit again without a Canvas mutation is a no-op and returns the same
revision.

The adapter accepts save/restore, affine transforms, rectangular clips,
bounded composition layers, rectangles, gradients, retained path strokes,
text, and images. All pointer arrays are copied during the call. Caller-owned
arrays and strings need remain valid only until the function returns. Invalid
handles, unknown enums, non-finite coordinates, negative dimensions, and
unusable widths are rejected before they enter the retained list. Scope
balancing follows the Nim Canvas contract: unmatched closes are safe no-ops
and dangling scopes are closed at the paint boundary.

This is the language-neutral path for chart, visualization, game, and other
drawing libraries that can emit canonical CBSS Canvas commands. Shared GPU
targets and CPU pixel buffers are separate future capabilities with explicit
ownership and synchronization contracts.

## Ownership

- `cbss_context_create` owns one independent tree and all computed snapshots.
- `cbss_context_destroy` invalidates that context and every node ID from it.
- `cbss_style_create` owns a reusable declaration set.
- `cbss_style_destroy` does not affect styles already applied to a context;
  declarations are copied on application.
- `cbss_color_value_create`, `cbss_color_value_current`, the two parse
  constructors, and `cbss_color_mix_create` return owning color-value handles.
  `cbss_color_value_destroy` releases them. Style setters copy the authored
  value, so the caller may destroy a handle immediately after a successful
  setter call.
- `cbss_color_mix_create` accepts component-value handles, not another mix;
  nested serialized mixes remain unsupported in this ABI version.
- `CbssColorValueGradientStop.color` is borrowed only for the duration of
  `cbss_style_set_linear_gradient_color_values`; the setter copies every
  authored value before returning.
- `cbss_blob_create` copies eager input bytes. `cbss_blob_create_provider`
  instead takes ownership of its `user_data` only on success. Its release
  callback runs exactly once after the final atomically retained Blob reference
  and may run on that releasing thread. Reads on one provider Blob are
  serialized; a provider callback must not release or re-enter its own Blob.
- `cbss_form_data_builder_create` returns one mutable builder. Finishing moves
  its entries into a new immutable snapshot; the builder must still be
  destroyed and cannot be reused. Destroying an unfinished builder releases
  every Blob it retained.
- `cbss_form_data_builder_add_blob` retains the Blob on success. FormData
  snapshots use atomic retain/release. `cbss_form_data_entry_blob` returns an
  additional owning Blob reference, which the caller must release.
- `CbssEventView` is callback-scoped and cannot be retained. Its FormData
  accessor returns a separate retained owning reference. CBSS releases its
  dispatch reference after the callback, so a successfully returned handle
  remains valid until the caller releases it.
- `CbssBlobStream` and its pump/drain operations are UI-thread-owned.
  `CbssStreamProducer` uses atomic retain/release and may cross worker-thread
  boundaries. A successful data offer retains its Blob; rejection and stream
  disposal release that reference automatically. A DATA event transfers one
  owning Blob reference to the caller.
- A worker not created by Nim brackets CBSS calls with `cbss_thread_attach` and
  `cbss_thread_detach`. ARC treats the pair as a no-op; ORC uses it to establish
  and release the foreign thread's runtime state.
- Node IDs are values owned by their context. `CBSS_NODE_NONE` is never valid.
- Strings passed into CBSS are copied before the call returns.
- Strings returned by CBSS are copied into caller-owned buffers. Query with a
  null buffer or zero capacity to obtain the required byte count.
- Output pointers must remain valid only for the duration of their call.
- `CbssEvent.key` and `CbssEvent.text` are borrowed and valid only during the
  callback.
- Unless a constructor explicitly transfers ownership, callback function
  pointers and `user_data` are borrowed. They must remain valid until replaced,
  removed, or the context is destroyed.
- RenderSurface event pointers, input strings, and placement data are borrowed
  only for the callback duration. Registration owns no host resource.
- Unregistering a RenderSurface detaches it from its node and synchronously
  delivers visibility/unmount callbacks before returning.

Context, style, and Blob-stream consumer handles are not internally
synchronized. Blob retain/release is atomic, and reads on one provider Blob are
serialized as the explicit exceptions. A host may use
independent contexts on separate threads, but it must serialize access to each
individual handle. Producer handles are the explicit exception described
above. Static-library hosts should create their first handle on the
main thread before starting worker threads; subsequent first-party wrappers can
hide this process-level initialization in their normal startup path.

## Error Boundary

C-facing functions return `CbssStatus`, a count, a handle, or a node ID.
Recoverable style and layout failures do not cross the ABI as Nim exceptions.
Use `cbss_context_last_error` and the diagnostic iteration functions after a
failed compute.

Passing an arbitrary pointer, using a handle after destruction, or concurrently
mutating one handle is outside the ABI contract.

## Compatibility

`cbss_abi_version()` returns:

```text
0xMMMMmmmm
```

The high 16 bits are the ABI major version and the low 16 bits are the minor
version. Existing function signatures, enum values, struct field order, and
ownership rules are frozen within one major version.

Compatible additions include new functions and new constants. Removing or
reordering fields, changing an enum value, or changing ownership requires a new
major ABI. Bindings should compare the major version before constructing a
context.

Functions with a complete replacement may be annotated with
`CBSS_DEPRECATED("replacement guidance")`. The annotation produces a compiler
warning on supported C/C++ compilers but does not remove the symbol or relax
the major-ABI rule. Product Version 0.x and the C ABI version are separate
contracts. See [API Stability And Deprecation](api-stability.md) for the staged
migration policy.

## Minimal C Example

```c
#include <cbss.h>

CbssContext *ui = cbss_context_create();
CbssStyle *style = cbss_style_create();

uint32_t root = cbss_context_add_box(ui, CBSS_NODE_NONE, "root");
cbss_style_set_length(style, "width", CBSS_UNIT_PX, 320.0f);
cbss_style_set_length(style, "height", CBSS_UNIT_PX, 200.0f);
cbss_node_apply_style(ui, root, style, 0, 0);

if (cbss_context_compute(ui, 320.0f, 200.0f) == CBSS_OK) {
  CbssRect rect;
  cbss_node_layout_rect(ui, root, &rect);
}

cbss_style_destroy(style);
cbss_context_destroy(ui);
```

Viewport-relative units use the viewport passed to `cbss_context_compute` and
are recomputed on every later compute with a different size:

```c
cbss_style_set_length(style, "width", CBSS_UNIT_VW, 50.0f);
cbss_style_set_length(style, "height", CBSS_UNIT_VH, 25.0f);
cbss_context_compute(ui, 1280.0f, 720.0f);
```

`CBSS_UNIT_VMIN` uses the smaller viewport dimension and `CBSS_UNIT_VMAX` uses
the larger one. The original unit enum values `0` through `10` remain stable;
the viewport units are appended as values `11` through `14`.

Shared libraries initialize the Nim runtime when loaded. Static libraries
initialize it lazily on the first context or style creation, so consumers do
not call `NimMain` or another Nim-specific entry point.
