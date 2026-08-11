import std/[options, strutils]

import ../core/[declaration, node, style_value]
import ../data/blob
import ../input/events
import ./form
import ./ui_root

const
  maxFileInputValues* = 1024
  maxFileInputNameBytes* = 4096

type
  FileInputValue* = FormFileValue

  FileSelectionRequest* = object
    accept*: seq[string]
    multiple*: bool

  FileInputParams* = object
    label*: string
    emptyLabel*: string
    accept*: seq[string]
    multiple*: bool
    disabled*: bool

  FileInputState* = ref object
    label: string
    emptyLabel: string
    accept: seq[string]
    multiple: bool
    disabled: bool
    fileState: FormFileFieldState

  FileInputHandle* = object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    actionNode*: NodeHandle
    valueNode*: NodeHandle
    state*: FileInputState

proc fileInputValue*(blob: Blob; fileName = ""): FileInputValue =
  FileInputValue(blob: blob, fileName: fileName)

proc normalizedLabel(label, fallback: string): string =
  if label.len > 0: label else: fallback

proc selectedSummary(input: FileInputHandle): string =
  let values = input.state.fileState.values()
  case values.len
  of 0:
    input.state.emptyLabel
  of 1:
    if values[0].fileName.len > 0: values[0].fileName else: "Unnamed file"
  else:
    $values.len & " files selected"

proc syncVisibleState(input: FileInputHandle) =
  if not input.container.valid():
    return
  let summary = input.selectedSummary()
  input.root.tree.nodes[input.actionNode.id.nodeIndex].text = input.state.label
  input.root.tree.nodes[input.valueNode.id.nodeIndex].text = summary
  input.root.tree.setAttribute(input.container.id, "value", summary)
  input.root.tree.setAttribute(
    input.container.id,
    "multiple",
    if input.state.multiple: "true" else: "false"
  )
  input.container.setAccessibleName(input.state.label)
  input.container.setAccessibleValue(summary)
  input.container.setState(esDisabled, input.state.disabled)

proc register*(form: FormHandle; name: string; input: FileInputHandle) =
  form.registerFileField(input.container, name, input.state.fileState)

proc selectionRequest*(input: FileInputHandle): FileSelectionRequest =
  result.multiple = input.state.multiple
  result.accept = newSeqOfCap[string](input.state.accept.len)
  for accepted in input.state.accept:
    result.accept.add accepted

proc files*(input: FileInputHandle): seq[FileInputValue] =
  input.state.fileState.values()

proc fileCount*(input: FileInputHandle): int =
  input.state.fileState.len

proc multiple*(input: FileInputHandle): bool =
  input.state.multiple

proc disabled*(input: FileInputHandle): bool =
  input.state.disabled

proc emitValueEvents(input: FileInputHandle) =
  let summary = input.selectedSummary()
  discard input.container.emit(inputEvent(summary))
  discard input.container.emit(changeEvent(summary))

proc setFiles*(
    input: FileInputHandle;
    values: openArray[FileInputValue];
    emitEvents = false
) =
  if not input.container.valid():
    return
  if values.len > maxFileInputValues:
    raise newException(ValueError, "file selection exceeds the supported item limit")
  if not input.state.multiple and values.len > 1:
    raise newException(ValueError, "single-file input cannot accept multiple values")
  for value in values:
    if not value.blob.isValid:
      raise newException(ValueError, "file input Blob value is not initialized")
    if value.fileName.len > maxFileInputNameBytes:
      raise newException(ValueError, "file input name exceeds the supported byte limit")
  input.state.fileState.replaceValues(values)
  input.syncVisibleState()
  if emitEvents:
    input.emitValueEvents()

proc clear*(input: FileInputHandle; emitEvents = false) =
  input.setFiles([], emitEvents = emitEvents)

proc setDisabled*(input: FileInputHandle; disabled: bool) =
  if not input.container.valid():
    return
  input.state.disabled = disabled
  input.syncVisibleState()

proc setMultiple*(input: FileInputHandle; multiple: bool) =
  if not input.container.valid() or input.state.multiple == multiple:
    return
  if not multiple and input.fileCount > 1:
    raise newException(ValueError, "clear multiple file values before disabling multiple selection")
  input.state.multiple = multiple
  input.syncVisibleState()

proc setAccept*(input: FileInputHandle; accept: openArray[string]) =
  if not input.container.valid():
    return
  var acceptedValues = newSeqOfCap[string](accept.len)
  for accepted in accept:
    if accepted.strip().len == 0:
      raise newException(ValueError, "file input accept entries cannot be empty")
    acceptedValues.add accepted
  input.state.accept = acceptedValues

proc `onClick=`*(input: FileInputHandle; handler: EventHandler) =
  input.container.onClick = handler

proc `onInput=`*(input: FileInputHandle; handler: EventHandler) =
  input.container.onInput = handler

proc `onChange=`*(input: FileInputHandle; handler: EventHandler) =
  input.container.onChange = handler

proc fileInput*(
    root: UiRoot;
    params = FileInputParams();
    style = UiStyle();
    actionStyle = UiStyle();
    valueStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["file-input"]
): FileInputHandle {.discardable.} =
  let label = params.label.normalizedLabel(
    if params.multiple: "Choose files" else: "Choose file"
  )
  let emptyLabel = params.emptyLabel.normalizedLabel("No file selected")
  var accepted = newSeqOfCap[string](params.accept.len)
  for entry in params.accept:
    if entry.strip().len == 0:
      raise newException(ValueError, "file input accept entries cannot be empty")
    accepted.add entry

  result.root = root
  result.state = FileInputState(
    label: label,
    emptyLabel: emptyLabel,
    accept: accepted,
    multiple: params.multiple,
    disabled: params.disabled,
    fileState: initFormFileFieldState()
  )
  result.container = root.box(style, id = id, groups = groups)
  result.container.setFocusable()
  result.container.setAccessibleRole(arButton)
  result.actionNode = root.text(
    result.container,
    label,
    actionStyle,
    groups = ["file-input-action"]
  )
  result.valueNode = root.text(
    result.container,
    emptyLabel,
    valueStyle,
    groups = ["file-input-value"]
  )
  result.actionNode.applyStyle(uiStyle([decl("pointer-events", keyword("none"))]))
  result.valueNode.applyStyle(uiStyle([decl("pointer-events", keyword("none"))]))
  result.syncVisibleState()

  let input = result
  let ownDisabled = params.disabled
  root.registerFieldsetTarget(proc(disabled: bool) =
    input.setDisabled(ownDisabled or disabled)
  )

  root.events.addInternalEventHandler(
    input.container.id,
    iekClick,
    proc(event: DispatchResult): EventOutcome =
      if input.state.disabled: stoppedEvent() else: ignoredEvent()
  )
  root.events.addInternalEventHandler(
    input.container.id,
    iekKeyDown,
    proc(event: DispatchResult): EventOutcome =
      if input.state.disabled:
        return stoppedEvent()
      if event.event.key.isSome and event.event.key.get in ["Enter", " "]:
        discard input.container.emit(InputEvent(kind: iekClick))
        return stoppedEvent()
      ignoredEvent()
  )
