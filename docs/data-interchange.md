# UI Data Interchange

CBSS owns immutable values and snapshots at the UI boundary. It does not own
HTTP, multipart encoding, retry policy, filesystem permission policy, or media
decoding.

## Blob

`Blob` takes an immutable copy of caller-owned bytes and may carry advisory
MIME metadata. Reads are bounded and return a new buffer:

```nim
let payload = newBlob(bytes, "application/octet-stream")
let header = payload.read(offset = 0, maxBytes = 16)
let complete = payload.readAll(maxBytes = 1024 * 1024)
```

`readAll` rejects a value larger than the caller's explicit allocation limit.
MIME metadata is not a security decision; consumers still validate content and
the operation they permit.

The C ABI exposes `CbssBlob` with atomic retain/release, immutable shared-heap
storage, bounded reads into caller-owned buffers, and a 64 MiB eager-
construction limit. It does not expose Nim-managed pointers. Larger or
progressive resources belong on the future stream/provider path instead of
forcing one allocation.

## FormData

`FormData` is an immutable, ordered snapshot. Repeated names are preserved.
Build snapshots directly for adapters or register controls with a `FormHandle`:

```nim
let form = ui.form()
ui.pushParent(form.container)
let email = ui.textInput(TextInputParams(value: "user@example.com"))
let updates = ui.checkbox("Receive updates", checked = true)
ui.popParent()

form.register("email", email)
form.register("updates", updates)

form.onSubmit = proc(event: DispatchResult): EventOutcome =
  let data = event.formData.get
  sendWithApplicationAdapter(data)
  handledEvent()

discard form.submit()
```

TextInput, TextArea, Select, Checkbox, and Radio use the same registration
surface. Disabled fields and unchecked checkable controls are omitted. A
disposed registered field or a control without a value produces a diagnostic
instead of disappearing silently. Editing a control after collection does not
change an existing snapshot.

`form.submit()` validates first, collects successful controls once, and carries
that immutable snapshot on its `onSubmit` event. An empty valid form still
carries an explicitly present empty snapshot. A synthetic `iekSubmit` emitted
without `submitEvent(data)` has no snapshot, so generic event producers do not
silently claim that they collected a form. Call `form.collectData()` directly
when collection diagnostics are needed before submission.

`FileInput` uses the same form contract without granting filesystem authority
to CBSS. The host opens its platform picker, validates the result under its own
sandbox and size policy, and supplies immutable Blob values:

```nim
let attachments = ui.fileInput(FileInputParams(
  accept: @["image/*", ".pdf"],
  multiple: true
))
form.register("attachments", attachments)

attachments.onClick = proc(event: DispatchResult): EventOutcome =
  let request = attachments.selectionRequest()
  openHostFilePicker(request) # asynchronous, application-owned integration
  handledEvent()

# Called later on the UI thread with host-authorized immutable values.
attachments.setFiles([
  fileInputValue(selectedBlob, "design.pdf")
], emitEvents = true)
```

The `accept` list is an advisory picker hint, not content validation. CBSS never
turns an untrusted path into a Blob, and FormData snapshots contain no platform
file handles. A single-file input rejects multiple values; a multiple input
preserves selection order and emits one Blob entry per selected value.

Request serialization remains outside CBSS. An optional `joubako` adapter may
translate a snapshot to JSON, NIF, multipart, or another request format.

The C ABI exposes a separate `CbssFormDataBuilder` and immutable,
atomically-reference-counted `CbssFormData` snapshot. Builders preserve entry
order and repeated names, retain Blob values without copying their bytes, and
cannot be reused after finishing. Entry string queries use caller-owned bounded
buffers. A Blob returned by `cbss_form_data_entry_blob` owns one retained
reference and must be released by the caller. Finished snapshots store their
entry table and copied strings in shared raw storage, so no Nim-managed pointer
crosses this ABI boundary.

ABI `0x0001000E` carries those snapshots through the additive opaque
`CbssEventView` contract without changing the existing `CbssEvent` layout or
callback signature. `cbss_context_emit_submit` accepts an immutable C snapshot;
EventView callbacks retrieve their own retained snapshot reference. Empty forms
remain distinct from payload-free synthetic submit events.

## Streams

The first stream slice provides a bounded, transport-neutral UI-side state
machine through `StreamBridge[T]`. It preserves ordered data, coalesces progress
to the latest pending value, applies both item-count and declared-weight limits,
and emits open, terminal, cancellation, and close events deterministically:

```nim
let stream = initStreamBridge[Blob](
  maxQueuedItems = 8,
  maxQueuedWeight = 16 * 1024 * 1024
)

doAssert stream.open()
case stream.pushData(chunk, chunk.size)
of sorAccepted:
  discard
of sorBackpressure:
  pauseProducer()
of sorNotOpen:
  discard

discard stream.reportProgress(receivedBytes, some(totalBytes))
discard stream.finish()

for event in stream.drain():
  applyOnUiThread(event)
```

Cancellation drops queued data and progress before emitting one cancellation
event. Closing an active stream cancels it first; closing a completed or failed
stream preserves its terminal event before close. Late producer offers are
rejected instead of reaching a disposed consumer.

`StreamBridge` remains a UI-thread state machine, not a lock-based shared UI
object. A producer running on another thread uses `StreamMailbox[T]`:

```nim
let mailbox = initStreamMailbox[Blob](
  maxQueuedItems = 8,
  maxQueuedWeight = 16 * 1024 * 1024
)
let source = mailbox.producer()

# `source` may be moved to a worker thread.
doAssert source.open() == smorAccepted
case source.pushData(chunk, chunk.size)
of smorAccepted:
  discard
of smorBackpressure:
  pauseProducer()
of smorInvalidState, smorDisposed:
  stopProducer()

# The owning UI thread drains bounded work into its StreamBridge.
let pumped = mailbox.pumpInto(stream, maxMessages = 32)
if pumped.changed:
  invalidateConsumer()
```

Producer handles use an atomic shared-state lifetime and may cross a thread
boundary. Managed payloads move into bounded shared channel storage and back to
the UI thread; they are not copied through a global queue. The mailbox retains
one UI-side deferred value when `StreamBridge` applies backpressure, and that
value remains part of the configured item and weight limits. Explicit disposal
or destruction rejects escaped producer handles and drops queued payloads.

An optional wake callback may post one host-loop wake signal when an empty or
already-signalled mailbox first needs UI pumping. Repeated offers are coalesced
until the UI fully drains the mailbox, so streams do not require a polling
frame loop. The callback is a non-closure C-style function plus raw context; it
must only post the host wake and must not re-enter or dispose the mailbox.

Remaining stream work is component-disposal attachment, the SDL3 host-loop wake
adapter and invalidation path, C ABI transport, broader cancellation race
verification, and host-authorized file/provider Blob sources. None of these
paths may expose Nim-managed pointers across an ABI or mutate the UI tree from
a worker thread.
