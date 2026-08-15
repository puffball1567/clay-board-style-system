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

The current registration model uses the retained form validity state before it
collects successful controls once and carries that immutable snapshot on its
`onSubmit` event. Version 0.5 replaces manual aggregate validity with attached
control rules, `checkValidity()`, `reportValidity()`, and validation-first
`submit()` behavior as specified in
[Form Validation Design](form-validation.md). An empty valid form still carries
an explicitly present empty snapshot. A synthetic `iekSubmit` emitted without
`submitEvent(data)` has no snapshot, so generic event producers do not silently
claim that they collected a form. Call `form.collectData()` directly when
collection diagnostics are needed before submission.

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

Components can own the UI side without writing a manual unmount hook:

```nim
type ResultsPanel = ref object of CBSSComponent
  results: ComponentStreamBinding[Blob]

method onMount(self: ResultsPanel) =
  self.results = self.attachStream(
    Blob,
    maxQueuedItems = 8,
    maxQueuedWeight = 16 * 1024 * 1024,
    dirtyDomains = {ddResource, ddPaint}
  )

# SDL3 hosts attach once on the UI thread before starting the producer.
import clay_board_style_system/backends/sdl3/stream_wake
let resultsWake = panel.results.attachSdl3Wake()

# The normal SDL event loop remains blocked until a coalesced wake arrives.
if resultsWake.matches(event):
  let pumped = panel.results.pumpSdl3Wake(
    resultsWake,
    event,
    scheduler,
    maxMessages = 32
  )
  for streamEvent in panel.results.drain():
    applyResult(streamEvent)
  # A bounded pump must run again before waiting when work remains.
  if pumped.pending:
    discard panel.results.pump(scheduler, maxMessages = 32)
```

`ComponentStreamBinding` uses the ordinary component-owned resource lifecycle,
not a stream-specific unmount exception. The component retains the binding;
subtree disposal closes it exactly once, releases pending payloads, and makes
escaped worker handles reject later offers. Pumping marks only the configured
dirty domains and only when the UI-side stream revision actually changes.

The SDL3 adapter reserves one process-wide SDL user-event kind. Each attached
binding receives an integer token, and worker callbacks put only that token in
the copied SDL event. No Nim reference, component pointer, mailbox pointer, or
payload crosses the SDL queue. `SDL_WaitEvent`/`SDL_WaitEventTimeout` therefore
remain the idle mechanism; receiving `sekStreamWake` only authorizes the UI
thread to pump the matching binding. Multiple producer offers are coalesced
until the mailbox has been pumped empty.

Replacing or clearing a wake callback is a context-ownership boundary. The
operation waits for any callback already executing on a producer thread before
returning, so the caller may release the previous raw context immediately after
detachment. Disposing a mailbox provides the same guarantee while additionally
rejecting all escaped producer handles.

C ABI `0x0001000F` exposes the same bounded transport as a Blob-specialized
opaque stream. Atomically retained producer handles may cross worker-thread
boundaries; UI-owned pump/drain calls return ordered events and transfer each
data Blob as one explicit owning reference. Backpressure, coalesced wakes,
progress, terminal states, callback replacement, disposal, and late-producer
rejection are exercised by shared and static C consumers using a real pthread.
The pthread uses the public attach/detach boundary, including under ORC. No
Nim-managed pointer crosses the ABI.

C ABI `0x00010010` and the Nim API add host-authorized fixed-size Blob
providers. A provider exposes a synchronous bounded read callback rather than
a path or mutable buffer. CBSS serializes reads on each Blob, writes only to
caller-owned output buffers, and invokes the release callback once after the
final Blob reference. Context ownership transfers only when construction
succeeds. Different providers may execute concurrently, and a provider
callback must not re-enter its own Blob or mutate the UI tree.
