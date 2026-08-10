import std/[locks, options]

const
  BlobProviderOk* = 0'i32
  BlobProviderUnavailable* = 1'i32
  BlobProviderIoError* = 2'i32

type
  BlobProviderReadProc* = proc(
    context: pointer;
    offset: uint64;
    output: pointer;
    capacity: uint32;
    outputRead: ptr uint32
  ): int32 {.cdecl, gcsafe, raises: [].}

  BlobProviderReleaseProc* = proc(
    context: pointer
  ) {.cdecl, gcsafe, raises: [].}

  BlobProviderStorage = ref object
    gate: Lock
    context: pointer
    readProc: BlobProviderReadProc
    releaseProc: BlobProviderReleaseProc

  BlobStorage = ref object
    bytes: seq[byte]
    provider: BlobProviderStorage
    length: uint64

  Blob* = object
    storage: BlobStorage
    contentType: Option[string]

proc `=destroy`(provider: var typeof(BlobProviderStorage()[])) =
  if provider.releaseProc != nil:
    provider.releaseProc(provider.context)
    provider.releaseProc = nil
  provider.context = nil
  deinitLock(provider.gate)

proc newBlob*(bytes: openArray[byte]; mimeType = ""): Blob =
  ## Takes an immutable snapshot. Later mutations of the input buffer cannot
  ## affect the Blob.
  result.storage = BlobStorage(
    bytes: newSeq[byte](bytes.len),
    length: uint64(bytes.len)
  )
  for index, value in bytes:
    result.storage.bytes[index] = value
  if mimeType.len > 0:
    result.contentType = some(mimeType)

proc newProviderBlob*(
    size: uint64;
    readProc: BlobProviderReadProc;
    releaseProc: BlobProviderReleaseProc = nil;
    context: pointer = nil;
    mimeType = ""
): Blob =
  ## Takes ownership of `context`. The provider is released exactly once when
  ## the last Blob snapshot is destroyed. Reads are serialized by CBSS. The
  ## callback must not re-enter this provider through one of its Blob values.
  if readProc == nil:
    raise newException(ValueError, "Blob provider read callback is required")
  let provider = BlobProviderStorage(
    context: context,
    readProc: readProc,
    releaseProc: releaseProc
  )
  initLock(provider.gate)
  result.storage = BlobStorage(provider: provider, length: size)
  if mimeType.len > 0:
    result.contentType = some(mimeType)

proc isValid*(blob: Blob): bool {.inline.} =
  not blob.storage.isNil

proc size*(blob: Blob): uint64 {.inline.} =
  if blob.storage.isNil:
    0'u64
  else:
    blob.storage.length

proc mimeType*(blob: Blob): Option[string] {.inline.} =
  blob.contentType

proc read*(blob: Blob; offset: uint64; maxBytes: int): seq[byte] =
  ## Returns at most `maxBytes` in a new buffer. The caller never receives the
  ## Blob's internal immutable storage.
  if maxBytes < 0:
    raise newException(ValueError, "Blob read size cannot be negative")
  if blob.storage.isNil or maxBytes == 0 or offset >= blob.size:
    return @[]

  let available = blob.size - offset
  let count = int(min(available, uint64(maxBytes)))
  result = newSeq[byte](count)
  if blob.storage.provider.isNil:
    let start = int(offset)
    for index in 0 ..< count:
      result[index] = blob.storage.bytes[start + index]
    return

  if uint64(count) > uint64(high(uint32)):
    raise newException(ValueError, "Blob provider read exceeds one callback")
  let provider = blob.storage.provider
  var outputRead = 0'u32
  acquire(provider.gate)
  try:
    let status = provider.readProc(
      provider.context,
      offset,
      addr result[0],
      uint32(count),
      addr outputRead
    )
    if status != BlobProviderOk:
      raise newException(
        IOError,
        "Blob provider read failed with status " & $status
      )
  finally:
    release(provider.gate)
  if outputRead > uint32(count):
    raise newException(IOError, "Blob provider exceeded the read capacity")
  result.setLen(int(outputRead))

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
