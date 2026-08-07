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

Host-authorized file/provider Blob sources and the bounded asynchronous stream
bridge are still planned. The bridge will marshal
immutable chunks and coalesced progress onto the UI thread, cancel delivery on
component disposal, and return to event-driven idle when no data or animation
work remains.
