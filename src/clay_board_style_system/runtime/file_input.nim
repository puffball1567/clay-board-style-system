import std/[options, strutils]

import ../core/[declaration, node, style_value]
import ../data/blob
import ../input/events
import ./form
import ./ui_root
import ./validation

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
    validation: ValidationBinding[seq[ValidationFile]]

  FileInputHandle* = object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    actionNode*: NodeHandle
    valueNode*: NodeHandle
    state*: FileInputState

proc evaluateValidation(
    input: FileInputHandle;
    trigger: ValidationTrigger;
    forceReport = false
): ValidationResult

proc validationAdapterFor(input: FileInputHandle): ValidationAdapter

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
  form.registerFileField(
    input.container,
    name,
    input.state.fileState,
    validation = input.validationAdapterFor()
  )

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
  discard input.evaluateValidation(ValidationTrigger.input)
  if not input.state.validation.isNil:
    input.root.notifyValidationDependencies(input.state.validation.valueReference.identity)
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
  else:
    discard input.evaluateValidation(ValidationTrigger.explicit)
    if not input.state.validation.isNil:
      input.root.notifyValidationDependencies(input.state.validation.valueReference.identity)

proc validationFiles(input: FileInputHandle): seq[ValidationFile] =
  let files = input.state.fileState.values()
  result = newSeqOfCap[ValidationFile](files.len)
  for file in files:
    result.add validationFile(
      file.fileName,
      file.blob.size,
      if file.blob.mimeType.isSome: file.blob.mimeType.get else: ""
    )

proc syncValidationState(input: FileInputHandle) =
  if not input.container.valid():
    return
  let validation =
    if input.state.validation.isNil:
      validValidationResult()
    else:
      input.state.validation.result
  input.container.setState(esInvalid, not input.state.disabled and not validation.isValid)
  input.root.tree.setAttribute(
    input.container.id,
    "validation-message",
    if input.state.disabled or input.state.validation.isNil:
      ""
    else:
      input.state.validation.validationMessage()
  )

proc evaluateValidation(
    input: FileInputHandle;
    trigger: ValidationTrigger;
    forceReport = false
): ValidationResult =
  if input.state.validation.isNil:
    return validValidationResult()
  result = input.state.validation.evaluate(
    input.validationFiles(),
    trigger,
    forceReport = forceReport
  )
  input.syncValidationState()

proc validationAdapterFor(input: FileInputHandle): ValidationAdapter =
  validationAdapter(
    proc(report: bool): ValidationResult =
      input.evaluateValidation(
        if report: ValidationTrigger.submit else: ValidationTrigger.explicit,
        forceReport = report
      ),
    proc(): ValidationResult =
      if input.state.validation.isNil:
        validValidationResult()
      else:
        input.state.validation.result
  )

proc setValidation*(
    input: FileInputHandle;
    rules: ValidationRules[seq[ValidationFile]];
    reportOn = ValidationReport.onBlur
) =
  input.root.clearValidationDependencies(input.container.id)
  input.state.validation = initValidationBinding(rules, input.validationFiles(), reportOn)
  for peer in input.state.validation.dependencyReferences:
    let dependent = input
    input.root.registerValidationDependency(
      peer.identity,
      input.container.id,
      proc() =
        discard dependent.evaluateValidation(ValidationTrigger.explicit)
    )
  input.syncValidationState()

proc validationValue*(input: FileInputHandle): ValidationValueRef[seq[ValidationFile]] =
  if input.state.validation.isNil:
    input.setValidation(validationRules[seq[ValidationFile]]())
  input.state.validation.valueReference

proc validationResult*(input: FileInputHandle): ValidationResult =
  if input.state.validation.isNil:
    validValidationResult()
  else:
    input.state.validation.result

proc validationMessage*(input: FileInputHandle): string =
  if input.state.disabled or input.state.validation.isNil:
    ""
  else:
    input.state.validation.validationMessage()

proc checkValidity*(input: FileInputHandle): bool =
  if input.state.disabled:
    return true
  input.evaluateValidation(ValidationTrigger.explicit).isValid

proc reportValidity*(input: FileInputHandle): bool =
  if input.state.disabled:
    return true
  result = input.evaluateValidation(
    ValidationTrigger.explicit,
    forceReport = true
  ).isValid
  if not result:
    discard input.container.emit(iekInvalid)
    input.root.requestFocus(some(input.container.id))

proc clear*(input: FileInputHandle; emitEvents = false) =
  input.setFiles([], emitEvents = emitEvents)

proc setDisabled*(input: FileInputHandle; disabled: bool) =
  if not input.container.valid():
    return
  input.state.disabled = disabled
  input.syncVisibleState()
  input.syncValidationState()

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
  root.events.addInternalEventHandler(
    input.container.id,
    iekBlur,
    proc(event: DispatchResult): EventOutcome =
      discard input.evaluateValidation(ValidationTrigger.blur)
      ignoredEvent()
  )

proc fileInput*(
    root: UiRoot;
    params: FileInputParams;
    validation: ValidationRules[seq[ValidationFile]];
    reportOn = ValidationReport.onBlur;
    style = UiStyle();
    actionStyle = UiStyle();
    valueStyle = UiStyle();
    id = "";
    groups: openArray[string] = ["file-input"]
): FileInputHandle {.discardable.} =
  result = root.fileInput(
    params,
    style = style,
    actionStyle = actionStyle,
    valueStyle = valueStyle,
    id = id,
    groups = groups
  )
  result.setValidation(validation, reportOn)
