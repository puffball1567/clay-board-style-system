import std/options

import ./blob

type
  FormDataValueKind* = enum
    fdvText,
    fdvBlob

  FormDataEntry* = object
    name*: string
    case kind*: FormDataValueKind
    of fdvText:
      text*: string
    of fdvBlob:
      blob*: Blob
      fileName*: Option[string]

  FormDataStorage = ref object
    entries: seq[FormDataEntry]

  FormData* = object
    storage: FormDataStorage

  FormDataBuilder* = object
    entries: seq[FormDataEntry]
    finished: bool

proc initFormDataBuilder*(): FormDataBuilder =
  FormDataBuilder(entries: @[])

proc requireWritable(builder: FormDataBuilder) =
  if builder.finished:
    raise newException(ValueError, "FormDataBuilder has already been finished")

proc requireName(name: string) =
  if name.len == 0:
    raise newException(ValueError, "FormData field name cannot be empty")

proc addText*(builder: var FormDataBuilder; name, value: string) =
  builder.requireWritable()
  name.requireName()
  builder.entries.add FormDataEntry(
    name: name,
    kind: fdvText,
    text: value
  )

proc addBlob*(
    builder: var FormDataBuilder;
    name: string;
    value: Blob;
    fileName = ""
) =
  builder.requireWritable()
  name.requireName()
  if not value.isValid:
    raise newException(ValueError, "FormData Blob value is not initialized")
  builder.entries.add FormDataEntry(
    name: name,
    kind: fdvBlob,
    blob: value,
    fileName: if fileName.len > 0: some(fileName) else: none(string)
  )

proc finish*(builder: var FormDataBuilder): FormData =
  builder.requireWritable()
  result.storage = FormDataStorage(entries: move(builder.entries))
  builder.entries = @[]
  builder.finished = true

proc len*(data: FormData): int {.inline.} =
  if data.storage.isNil: 0 else: data.storage.entries.len

proc isEmpty*(data: FormData): bool {.inline.} =
  data.len == 0

proc `[]`*(data: FormData; index: int): FormDataEntry =
  if data.storage.isNil:
    raise newException(IndexDefect, "FormData is empty")
  data.storage.entries[index]

iterator items*(data: FormData): FormDataEntry =
  if not data.storage.isNil:
    for entry in data.storage.entries:
      yield entry

proc entries*(data: FormData): seq[FormDataEntry] =
  ## Returns a snapshot so callers cannot reorder or replace internal entries.
  result = newSeqOfCap[FormDataEntry](data.len)
  for entry in data.items:
    result.add entry

proc values*(data: FormData; name: string): seq[FormDataEntry] =
  for entry in data.items:
    if entry.name == name:
      result.add entry
