# CBSS C ABI

The C ABI is CBSS's language-neutral runtime boundary. Nim remains the primary
authoring API, while C++, Rust, Zig, Swift, and other native languages can
build wrappers over the same engine without depending on Nim object layouts.

## Build

```sh
nimble buildCAbiShared
nimble buildCAbiStatic
nimble testCAbi
```

The development tasks write artifacts outside the repository:

```text
/tmp/libcbss.so
/tmp/libcbss.a
```

The installed header is `include/cbss.h`.

## Current Pipeline

ABI version `0x00010000` supports:

- Opaque context and style handles.
- Generation-checked node handles plus box, text, and image node creation.
- Groups, attributes, pseudo-state flags, and accessibility semantics.
- Typed length, number, keyword, color, color-pair, border, shadow, gradient,
  and transform declarations.
- Replaceable per-node and per-state style application.
- Style resolution, intrinsic sizing, and flex layout.
- Layout-box and node-rectangle queries.
- Renderer-neutral paint-command iteration.
- Text/image payload, basic computed text style, and gradient-stop queries.
- Hit testing.
- C callbacks for all CBSS event kinds, including bubbling through ancestors.
- Pointer, touch, keyboard, text, wheel, and component-event dispatch.
- Hover, active, focus, focus-visible, pointer-capture, and focus-scope state.
- Tab and Shift+Tab focus traversal.
- Retained scrolling and scrollbar interaction without layout recomputation.
- Accessibility role, including semantic links, name, description, value,
  range, relation, and hidden state queries for platform adapters.
- Structured diagnostics and a context error message.

Platform accessibility transports, native resource loading, operating-system
window ownership, and final execution of paint commands remain host adapters.
The ABI exposes the semantics and renderer-neutral data those adapters need.

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

Event handlers are installed with `cbss_node_set_event_handler`. Reinstalling
the same node/event pair replaces the callback; passing a null callback removes
it. Returning nonzero stops propagation to ancestors for that dispatch.
Callbacks may update nodes and styles, but must not destroy or reset the
context currently dispatching. The callback and `user_data` remain owned by the
host.

## Ownership

- `cbss_context_create` owns one independent tree and all computed snapshots.
- `cbss_context_destroy` invalidates that context and every node ID from it.
- `cbss_style_create` owns a reusable declaration set.
- `cbss_style_destroy` does not affect styles already applied to a context;
  declarations are copied on application.
- Node IDs are values owned by their context. `CBSS_NODE_NONE` is never valid.
- Strings passed into CBSS are copied before the call returns.
- Strings returned by CBSS are copied into caller-owned buffers. Query with a
  null buffer or zero capacity to obtain the required byte count.
- Output pointers must remain valid only for the duration of their call.
- `CbssEvent.key` and `CbssEvent.text` are borrowed and valid only during the
  callback.
- Callback function pointers and `user_data` are borrowed. They must remain
  valid until replaced, removed, or the context is destroyed.

Context and style handles are not internally synchronized. A host may use
independent contexts on separate threads, but it must serialize access to each
individual handle. Static-library hosts should create their first handle on the
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

Shared libraries initialize the Nim runtime when loaded. Static libraries
initialize it lazily on the first context or style creation, so consumers do
not call `NimMain` or another Nim-specific entry point.
