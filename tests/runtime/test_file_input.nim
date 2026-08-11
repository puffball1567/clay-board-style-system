import std/[options, strutils, unittest]

import clay_board_style_system

proc sampleFile(name: string; value: byte): FileInputValue =
  fileInputValue(newBlob([value], "application/octet-stream"), name)

suite "file input component":
  test "default input exposes a host-facing selection request":
    let ui = initUiRoot()
    let input = ui.fileInput(FileInputParams(
      accept: @["image/png", ".jpg"],
      multiple: true
    ))

    let request = input.selectionRequest()
    check request.accept == @["image/png", ".jpg"]
    check request.multiple
    check input.fileCount == 0
    check ui.tree.nodes[input.valueNode.nodeId.nodeIndex].text == "No file selected"
    check ui.tree.semanticInfo(input.container.nodeId).role == arButton

    var changed = request.accept
    changed[0] = "mutated"
    check input.selectionRequest().accept[0] == "image/png"

  test "host-authorized files update visible state and value events":
    let ui = initUiRoot()
    let input = ui.fileInput()
    var events: seq[string]

    input.onInput = proc(event: DispatchResult): EventOutcome =
      events.add "input:" & event.event.text.get("")
      ignoredEvent()
    input.onChange = proc(event: DispatchResult): EventOutcome =
      events.add "change:" & event.event.text.get("")
      ignoredEvent()

    input.setFiles([sampleFile("report.bin", 7)], emitEvents = true)

    check input.fileCount == 1
    check ui.tree.nodes[input.valueNode.nodeId.nodeIndex].text == "report.bin"
    check ui.tree.semanticInfo(input.container.nodeId).value == "report.bin"
    check events == @["input:report.bin", "change:report.bin"]

    var returned = input.files()
    returned[0].fileName = "outside.bin"
    check input.files()[0].fileName == "report.bin"

  test "multiple files preserve order and repeated form names":
    let ui = initUiRoot()
    let upload = ui.form()
    ui.pushParent(upload.container)
    let input = ui.fileInput(FileInputParams(multiple: true))
    ui.popParent()
    upload.register("attachment", input)

    input.setFiles([
      sampleFile("first.bin", 1),
      sampleFile("second.bin", 2)
    ])
    let snapshot = upload.collectData()

    check snapshot.diagnostics.len == 0
    check snapshot.data.len == 2
    check snapshot.data[0].name == "attachment"
    check snapshot.data[0].kind == fdvBlob
    check snapshot.data[0].fileName == some("first.bin")
    check snapshot.data[0].blob.readAll(1) == @[byte 1]
    check snapshot.data[1].fileName == some("second.bin")
    check snapshot.data[1].blob.readAll(1) == @[byte 2]
    check ui.tree.nodes[input.valueNode.nodeId.nodeIndex].text == "2 files selected"

    input.clear()
    check upload.collectData().data.isEmpty
    check snapshot.data.len == 2

  test "single selection rejects invalid or excessive values atomically":
    let ui = initUiRoot()
    let input = ui.fileInput()
    input.setFiles([sampleFile("retained.bin", 3)])

    expect ValueError:
      input.setFiles([
        sampleFile("one.bin", 1),
        sampleFile("two.bin", 2)
      ])
    expect ValueError:
      input.setFiles([fileInputValue(Blob(), "invalid.bin")])
    expect ValueError:
      input.setFiles([sampleFile(repeat("x", maxFileInputNameBytes + 1), 4)])

    check input.fileCount == 1
    check input.files()[0].fileName == "retained.bin"

  test "selection count limit is enforced without replacing existing values":
    let ui = initUiRoot()
    let input = ui.fileInput(FileInputParams(multiple: true))
    input.setFiles([sampleFile("retained.bin", 3)])
    var excessive = newSeq[FileInputValue](maxFileInputValues + 1)
    for index in 0 ..< excessive.len:
      excessive[index] = sampleFile("item-" & $index & ".bin", byte(index mod 256))

    expect ValueError:
      input.setFiles(excessive)

    check input.fileCount == 1
    check input.files()[0].fileName == "retained.bin"

  test "accept replacement is copied and failed updates are atomic":
    let ui = initUiRoot()
    let input = ui.fileInput(FileInputParams(accept: @["image/png"]))
    var replacement = @["image/jpeg", ".webp"]

    input.setAccept(replacement)
    replacement[0] = "mutated"
    check input.selectionRequest().accept == @["image/jpeg", ".webp"]

    expect ValueError:
      input.setAccept(["application/pdf", " "])
    check input.selectionRequest().accept == @["image/jpeg", ".webp"]

  test "empty file input contributes no form entry or diagnostic":
    let ui = initUiRoot()
    let form = ui.form()
    ui.pushParent(form.container)
    let input = ui.fileInput()
    ui.popParent()
    form.register("attachment", input)

    let collection = form.collectData()
    check collection.data.isEmpty
    check collection.diagnostics.len == 0

  test "form file state rejects invalid blobs without losing prior values":
    let state = initFormFileFieldState()
    state.replaceValues([FormFileValue(
      blob: newBlob([byte 8]),
      fileName: "retained.bin"
    )])

    expect ValueError:
      state.replaceValues([FormFileValue(blob: Blob(), fileName: "invalid.bin")])

    check state.len == 1
    check state.values()[0].fileName == "retained.bin"

  test "multiple mode cannot be disabled while several files remain":
    let ui = initUiRoot()
    let input = ui.fileInput(FileInputParams(multiple: true))
    input.setFiles([sampleFile("one.bin", 1), sampleFile("two.bin", 2)])

    expect ValueError:
      input.setMultiple(false)
    check input.multiple

    input.clear()
    input.setMultiple(false)
    check not input.multiple

  test "disabled input suppresses pointer and keyboard activation":
    let ui = initUiRoot()
    let input = ui.fileInput(FileInputParams(disabled: true))
    var clicks = 0
    input.onClick = proc(event: DispatchResult): EventOutcome =
      inc clicks
      ignoredEvent()

    check not input.container.emit(iekClick)
    check not input.container.emit(InputEvent(kind: iekKeyDown, key: some("Enter")))
    check clicks == 0

    input.setDisabled(false)
    check input.container.emit(InputEvent(kind: iekKeyDown, key: some("Enter")))
    check clicks == 1

  test "empty accept entries and direct file-kind registration are rejected":
    let ui = initUiRoot()
    expect ValueError:
      discard ui.fileInput(FileInputParams(accept: @["image/png", " "]))

    let form = ui.form()
    ui.pushParent(form.container)
    let node = ui.box()
    ui.popParent()
    expect ValueError:
      form.registerField(node, "file", ffFile)

  test "disposed file fields produce collection diagnostics":
    let ui = initUiRoot()
    let form = ui.form()
    ui.pushParent(form.container)
    let input = ui.fileInput()
    ui.popParent()
    form.register("attachment", input)
    input.setFiles([sampleFile("temporary.bin", 9)])

    var interaction = initInteractionState()
    check ui.disposeSubtree(input.container, interaction)
    let collection = form.collectData()

    check collection.data.isEmpty
    check collection.diagnostics.len == 1
    check collection.diagnostics[0].kind == fddDisposedField
