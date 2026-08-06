import std/options

type
  BlobStorage = ref object
    bytes: seq[byte]

  Blob* = object
    storage: BlobStorage
    contentType: Option[string]

proc newBlob*(bytes: openArray[byte]; mimeType = ""): Blob =
  ## Takes an immutable snapshot. Later mutations of the input buffer cannot
  ## affect the Blob.
  result.storage = BlobStorage(bytes: newSeq[byte](bytes.len))
  for index, value in bytes:
    result.storage.bytes[index] = value
  if mimeType.len > 0:
    result.contentType = some(mimeType)

proc isValid*(blob: Blob): bool {.inline.} =
  not blob.storage.isNil

proc size*(blob: Blob): uint64 {.inline.} =
  if blob.storage.isNil:
    0'u64
  else:
    uint64(blob.storage.bytes.len)

proc mimeType*(blob: Blob): Option[string] {.inline.} =
  blob.contentType

proc read*(blob: Blob; offset: uint64; maxBytes: int): seq[byte] =
  ## Returns at most `maxBytes` in a new buffer. The caller never receives the
  ## Blob's internal immutable storage.
  if maxBytes < 0:
    raise newException(ValueError, "Blob read size cannot be negative")
  if blob.storage.isNil or maxBytes == 0 or offset >= blob.size:
    return @[]

  let start = int(offset)
  let available = blob.storage.bytes.len - start
  let count = min(available, maxBytes)
  result = newSeq[byte](count)
  for index in 0 ..< count:
    result[index] = blob.storage.bytes[start + index]

proc readAll*(blob: Blob; maxBytes: int): seq[byte] =
  ## Materializes the complete Blob only when it fits the caller's explicit
  ## allocation bound.
  if maxBytes < 0:
    raise newException(ValueError, "Blob materialization limit cannot be negative")
  if blob.size > uint64(maxBytes):
    raise newException(ValueError, "Blob exceeds the materialization limit")
  blob.read(0, maxBytes)

proc slice*(blob: Blob; offset: uint64; maxBytes: int): Blob =
  result = newBlob(blob.read(offset, maxBytes))
  result.contentType = blob.contentType
