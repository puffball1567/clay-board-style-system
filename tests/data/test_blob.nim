import std/[options, unittest]

import clay_board_style_system

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
