import std/[options, unittest]

import clay_board_style_system

type ProviderProbe = object
  bytes: seq[byte]
  reads: int
  releases: int
  status: int32
  exceedCapacity: bool

proc readProvider(
    raw: pointer;
    offset: uint64;
    output: pointer;
    capacity: uint32;
    outputRead: ptr uint32
): int32 {.cdecl, gcsafe, raises: [].} =
  let probe = cast[ptr ProviderProbe](raw)
  inc probe.reads
  if probe.status != BlobProviderOk:
    return probe.status
  if probe.exceedCapacity:
    outputRead[] = capacity + 1
    return BlobProviderOk
  let available = probe.bytes.len - int(offset)
  let count = min(available, int(capacity))
  if count > 0:
    copyMem(output, unsafeAddr probe.bytes[int(offset)], count)
  outputRead[] = uint32(count)
  BlobProviderOk

proc releaseProvider(raw: pointer) {.cdecl, gcsafe, raises: [].} =
  inc cast[ptr ProviderProbe](raw).releases

suite "Blob data contract":
  test "construction snapshots caller-owned bytes":
    var source = @[byte 1, 2, 3, 4]
    let blob = newBlob(source, "application/octet-stream")
    source[0] = 99

    check blob.isValid
    check blob.size == 4
    check blob.mimeType == some("application/octet-stream")
    check blob.readAll(4) == @[byte 1, 2, 3, 4]

  test "bounded reads never expose mutable internal storage":
    let blob = newBlob([byte 10, 20, 30, 40])
    var first = blob.read(1, 2)
    first[0] = 99

    check blob.read(1, 2) == @[byte 20, 30]
    check blob.read(4, 10).len == 0
    check blob.read(0, 0).len == 0

  test "materialization enforces explicit size limits":
    let blob = newBlob([byte 1, 2, 3])

    expect ValueError:
      discard blob.readAll(2)
    expect ValueError:
      discard blob.read(0, -1)
    check blob.readAll(3) == @[byte 1, 2, 3]

  test "slices preserve advisory MIME metadata and own their bytes":
    let source = newBlob([byte 1, 2, 3, 4], "image/example")
    let selected = source.slice(1, 2)

    check selected.size == 2
    check selected.mimeType == some("image/example")
    check selected.readAll(2) == @[byte 2, 3]

  test "default Blob is invalid and safely empty":
    let blob = Blob()

    check not blob.isValid
    check blob.size == 0
    check blob.mimeType.isNone
    check blob.read(0, 4).len == 0

  test "provider reads stay bounded and preserve metadata":
    var probe = ProviderProbe(bytes: @[byte 4, 5, 6, 7])
    var blob = newProviderBlob(
      4,
      readProvider,
      releaseProvider,
      addr probe,
      "application/provider"
    )

    check blob.isValid
    check blob.size == 4
    check blob.mimeType == some("application/provider")
    check blob.read(1, 2) == @[byte 5, 6]
    check probe.reads == 1
    check blob.read(4, 2).len == 0
    check probe.reads == 1
    reset(blob)
    check probe.releases == 1

  test "provider ownership is shared and released exactly once":
    var probe = ProviderProbe(bytes: @[byte 1, 2, 3])
    var blob = newProviderBlob(
      3, readProvider, releaseProvider, addr probe
    )
    var retained = blob

    check retained.readAll(3) == probe.bytes
    reset(blob)
    check probe.releases == 0
    reset(retained)
    check probe.releases == 1

  test "provider failures cannot escape their declared read boundary":
    var probe = ProviderProbe(
      bytes: @[byte 1, 2, 3],
      status: BlobProviderIoError
    )
    var blob = newProviderBlob(
      3, readProvider, releaseProvider, addr probe
    )
    expect IOError:
      discard blob.read(0, 3)

    probe.status = BlobProviderOk
    probe.exceedCapacity = true
    expect IOError:
      discard blob.read(0, 3)
    reset(blob)
    check probe.releases == 1

  test "provider construction rejects a missing reader":
    expect ValueError:
      discard newProviderBlob(1, nil)
