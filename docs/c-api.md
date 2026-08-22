# CBSS C ABI

The C ABI is CBSS's language-neutral engine protocol. It is not the intended
application-authoring API. Nim remains the canonical authoring reference;
Version 0.6 Craft Drivers give C++, Rust, and later host languages a high-level
surface over the same engine without depending on Nim object layouts or making
ordinary users manage opaque handles, callback userdata, and status codes.

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

ABI version `0x00010018` supports:

- machine-readable Craft Driver contract metadata and runtime capability
  negotiation through stable numeric identifiers before tree construction;
- public Craft Style Slot exposure, bounded atomic Craft Style replacement,
  active Style queries, and structured parse/replacement diagnostics;
- bounded atomic Craft Pack manifest loading, compatibility negotiation,
  active Pack queries, and structured Pack diagnostics;
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
- Atomic retained-subtree removal with synchronous cleanup of interaction,
  event, Style, motion, scroll, Craft Slot, and Render Surface state.
- Groups, attributes, pseudo-state flags, validation invalid-state exposure,
  and accessibility semantics, including an append-only protected-password
  text role.
- Typed length, number, keyword, color, color-pair, border, shadow, gradient,
  and transform declarations.
- Append-only `lh`, `rlh`, `ex`, `ch`, `rex`, and `rch` unit tags. The C ABI
  uses deterministic CSS fallback font metrics because concrete text engines
  remain an application-side adapter concern.
- Opaque authored-color handles for typed color spaces, `currentColor`,
  serialized CSS colors, and `color-mix()`, without changing the stable
  16-byte resolved `CbssColor` value.
- Replaceable per-node and per-state style application.
- Context-scoped named-keyframe definitions built from copied `CbssStyle`
  steps, declaration-driven transition/keyframe reconciliation, monotonic
  paint-only motion advancement, active-track counts, dirty-domain bits, next
  deadlines, reduced-motion policy, and lifecycle payloads.
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
  payloads. Existing `CbssEventCallback` signatures remain unchanged. The
  library-owned `CbssEvent` callback record is 152 bytes and appends borrowed
  motion name, elapsed-time, and iteration fields after its original 128-byte
  prefix. Submit views expose an owning retained
  FormData snapshot, while a synthetic submit without a snapshot reports
  `CBSS_NOT_AVAILABLE`.
- Optional pointer-device metadata with stable-in-process device IDs, contact,
  button, eraser, and proximity state. A capability bitmask distinguishes an
  unavailable pen axis from a supported axis whose value is zero; timestamps,
  pressure,
  tangential pressure, x/y tilt, rotation, distance, and slider values cross
  both ordinary event callbacks and RenderSurface input callbacks.
- Hover, active, focus, focus-visible, pointer-capture, and focus-scope state.
- Inherited inert-state mutation/query and subtree-scoped first-focusable
  lookup for retained screen hosts.
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

## Craft Driver Negotiation

`schema/craft_driver_contract.json` is the source of truth for the engine ABI,
Driver contract version, stable capability identifiers, and capability
versions. `tools/generate_driver_contract.nim` generates the corresponding Nim
table and C declarations; `nimble checkDriverContract` rejects stale generated
surfaces.

A Driver must perform negotiation before it creates a `CbssContext` or mounts
any Craft:

1. Compare `cbss_abi_version()` with the ABI range supported by the Driver.
2. Compare `cbss_driver_contract_version()` with the Driver contract range.
3. Check every required numeric capability id and minimum version with
   `cbss_has_capability()`.
4. Use `cbss_capability_at()` and `cbss_capability_name()` for diagnostics and
   tooling, not as substitutes for stable numeric identity.

Failure aborts construction before application callbacks, resources, or a
partial tree are installed. Capability identifiers are append-only. A
capability version increases only when optional behavior is added under the
same semantic family; incompatible semantics require a new capability id.

The maintained C++14 reference Driver is in `drivers/cpp`. Its header-only
surface performs this negotiation automatically, owns contexts and Styles with
RAII, translates status codes into typed exceptions, and provides scoped nested
Box/Text/Image construction without explicit parent node identifiers. Raw handles
remain available only as an advanced interoperability escape hatch. Run
`nimble testCppDriver` to exercise the same reference tree against both shared
and static C ABI builds.

The maintained Rust reference Driver is in `drivers/rust`. It keeps the raw FFI
module private, owns `Ui` and `Style` through `Drop`, and uses borrowed child
Scopes instead of a mutable parent stack. Generated ABI and capability
constants come from the same contract JSON as Nim and C. Run
`nimble testRustDriver` for ARC shared/static integration and
`nimble testRustDriverOrc` for the equivalent ORC boundary.

## Craft Style And Pack Loading

`cbss_node_expose_craft_style_slot` publishes an explicit component/Slot pair
for a mounted node. `cbss_context_replace_craft_style_json` accepts copied
bytes with an explicit length, compiles the candidate, validates all targets,
and replaces the active Style with the same name only on success. Component-
owned Style remains higher precedence than externally loaded Craft Style.

`cbss_context_replace_craft_pack_json` validates and registers a Version 1
manifest under the same atomic rule. It does not open declared asset paths or
verify asset bytes. File access and digest verification belong to a separate
host-authorized resolver described in
[Craft Pack Manifest Format](craft-pack-format.md).

Both inputs have public byte limits. A failure can be inspected through
`cbss_context_craft_diagnostic_count`, `cbss_context_craft_diagnostic_at`, and
the path/message copy functions. `CbssCraftDiagnosticDomain` and the three
domain-specific diagnostic-code enums are the stable programmatic contract;
text is explanatory. Active Style and Pack names are returned through
caller-owned buffers. No Nim string or sequence crosses the ABI.

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

## Declarative Motion

`CbssKeyframes` is a mutable definition builder. Create it with
`cbss_keyframes_create`, add offset-sorted steps with
`cbss_keyframes_add_step`, and register a copied context-scoped definition with
`cbss_context_register_keyframes`. Every step copies its source `CbssStyle`
during the call. Registration copies the completed definition again, so both
the step style and builder may be cleared, reused, or destroyed immediately
after their successful calls.

Use one monotonic clock for all calls on a context:

1. call `cbss_context_compute_at` for the first frame;
2. after declaration or pseudo-state changes, call
   `cbss_context_recompute_at` at the current time;
3. while `CbssMotionState.has_deadline` is nonzero, wake at
   `next_deadline` and call `cbss_context_advance_motion`; and
4. block for input when no deadline and no other frame source remains.

Recompute performs style reconciliation and layout because authored target
styles may have changed. Advance samples only already-active transition and
keyframe tracks; it does not resolve styles or run layout. It refreshes the
renderer-neutral paint/hit snapshot only when a sample changed presentation.
`dirty_domains` uses `CBSS_DIRTY_*` bits and tells a foreign host whether the
sample affected paint, hit testing, or timed animation work. Sample and active
counts are separate: a paused animation may remain active without requesting a
deadline.

Times must be finite and must not move backwards. A rejected time leaves the
previous presentation intact. `cbss_context_set_reduced_motion` accepts only
zero or one and immediately settles nonessential active motion at the current
context time. Removing a registered definition synchronously cancels its
active tracks before returning. Replacing a definition becomes observable on
the next recompute, where definition revision changes cancel and restart the
affected declaration-bound tracks.

Motion lifecycle callbacks use the ordinary event subscription API.
`CBSS_EVENT_HAS_MOTION` indicates that `motion_name`,
`motion_elapsed_seconds`, and `motion_iteration` are populated. The name is
borrowed only for the callback. Animation events include start, iteration,
end, and cancel; transition events include run, start, end, and cancel.

```c
CbssKeyframes *pulse = NULL;
CbssStyle *step = cbss_style_create();
cbss_keyframes_create("pulse", &pulse);

cbss_style_set_number(step, "opacity", 0.2f);
cbss_keyframes_add_step(pulse, 0.0, step);
cbss_style_clear(step);
cbss_style_set_number(step, "opacity", 1.0f);
cbss_keyframes_add_step(pulse, 1.0, step);

cbss_context_register_keyframes(ui, pulse);
cbss_style_destroy(step);
cbss_keyframes_destroy(pulse);

CbssMotionState motion;
cbss_context_compute_at(ui, 800.0f, 600.0f, now_seconds);
cbss_context_motion_state(ui, &motion);
```

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
it. Intrinsic widget behavior uses `cbss_node_set_default_action`; it runs after
public bubbling and is skipped when a cancelable event is marked
prevent-default. Reinstalling the same node/event pair replaces the default
action, and a null callback removes it. Its callback receives
`CBSS_EVENT_PHASE_DEFAULT_ACTION` in `CbssEvent.flags`. Independent observers use
`cbss_node_subscribe_event`, retain the returned
`CbssEventSubscription`, and remove it with
`cbss_context_unsubscribe_event`. The callback returns a bitwise combination of
`CBSS_EVENT_OUTCOME_*`:
`HANDLED` records handling, `STOP_PROPAGATION` stops traversal after the current
target, and `PREVENT_DEFAULT` suppresses a cancelable intrinsic action when the
hosted component defines one. Returning `1` remains the handled-only form.
Callbacks may update nodes and styles, but must not destroy or reset the
context currently dispatching or remove a subtree containing the current
dispatch path. The callback and `user_data` remain owned by the host.

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
- `cbss_keyframes_add_step` copies all declarations from its source style.
  `cbss_context_register_keyframes` copies the complete builder into the
  context. Destroying either source handle does not affect registered motion.
  Registered definitions live until replacement, explicit removal, context
  reset, or context destruction. Reset and destruction cancel active tracks
  and dispatch their cancellation events before event handlers are detached.
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
- Node IDs are generation-checked values owned by their context.
  `CBSS_NODE_NONE` is never valid. `cbss_context_remove_subtree` synchronously
  releases all CBSS-owned state for the node and its descendants; every removed
  ID becomes invalid before the call returns and cannot alias a later node that
  reuses the same arena slot.
- Strings passed into CBSS are copied before the call returns.
- Strings returned by CBSS are copied into caller-owned buffers. Query with a
  null buffer or zero capacity to obtain the required byte count.
- Output pointers must remain valid only for the duration of their call.
- `CbssEvent.key`, `CbssEvent.text`, and `CbssEvent.motion_name` are borrowed
  and valid only during the callback.
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

Compatible additions include new functions, new constants, and append-only
fields on library-owned callback records whose original prefix remains stable.
Removing or reordering fields, changing an enum value, shrinking a callback
record, or changing ownership requires a new major ABI. Bindings should compare
the major version before constructing a context and use the complete header
matching the linked minor version when reading appended fields.

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
