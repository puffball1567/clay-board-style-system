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

let collection = form.collectData()
for diagnostic in collection.diagnostics:
  echo diagnostic.kind, ": ", diagnostic.name

sendWithApplicationAdapter(collection.data)
```

TextInput, TextArea, Select, Checkbox, and Radio use the same registration
surface. Disabled fields and unchecked checkable controls are omitted. A
disposed registered field or a control without a value produces a diagnostic
instead of disappearing silently. Editing a control after collection does not
change an existing snapshot.

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

## Streams

Host-authorized file/provider Blob sources and the bounded asynchronous stream
bridge are still planned. The bridge will marshal
immutable chunks and coalesced progress onto the UI thread, cancel delivery on
component disposal, and return to event-driven idle when no data or animation
work remains.
