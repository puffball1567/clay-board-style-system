import std/[options, sequtils, unittest]

import clay_board_style_system

suite "FormData snapshot":
  test "preserves field order and repeated names":
    var builder = initFormDataBuilder()
    builder.addText("tag", "first")
    builder.addText("title", "Document")
    builder.addText("tag", "second")
    let data = builder.finish()

    check data.len == 3
    check data[0].name == "tag"
    check data[0].text == "first"
    check data[1].name == "title"
    check data[2].text == "second"
    check data.values("tag").mapIt(it.text) == @["first", "second"]

  test "stores immutable Blob-backed file values":
    var bytes = @[byte 4, 5, 6]
    let blob = newBlob(bytes, "application/example")
    var builder = initFormDataBuilder()
    builder.addBlob("attachment", blob, "sample.bin")
    let data = builder.finish()
    bytes[0] = 99

    check data[0].kind == fdvBlob
    check data[0].fileName == some("sample.bin")
    check data[0].blob.readAll(3) == @[byte 4, 5, 6]

  test "returned entry arrays cannot reorder the snapshot":
    var builder = initFormDataBuilder()
    builder.addText("first", "1")
    builder.addText("second", "2")
    let data = builder.finish()
    var copied = data.entries()
    swap(copied[0], copied[1])
    copied[0].text = "changed outside"

    check data[0].name == "first"
    check data[1].name == "second"
    check data[1].text == "2"

  test "builder rejects invalid values and reuse after finish":
    var emptyName = initFormDataBuilder()
    expect ValueError:
      emptyName.addText("", "value")

    var invalidBlob = initFormDataBuilder()
    expect ValueError:
      invalidBlob.addBlob("file", Blob())

    var finished = initFormDataBuilder()
    finished.addText("field", "value")
    discard finished.finish()
    expect ValueError:
      finished.addText("later", "rejected")
    expect ValueError:
      discard finished.finish()

  test "default FormData is an empty snapshot":
    let data = FormData()

    check data.isEmpty
    check data.entries().len == 0
