import std/options

import ../core/node
import ../data/[blob, form_data]
import ../input/events
import ./ui_root

type
  FormFieldKind* = enum
    ffText,
    ffCheckable,
    ffFile

  FormFileValue* = object
    blob*: Blob
    fileName*: string

  FormFileFieldState* = ref object
    values: seq[FormFileValue]

  FormFieldRegistration* = object
    node*: NodeId
    name*: string
    kind*: FormFieldKind
    fileState: FormFileFieldState

  FormDataDiagnosticKind* = enum
    fddDisposedField,
    fddMissingValue

  FormDataDiagnostic* = object
    kind*: FormDataDiagnosticKind
    node*: NodeId
    name*: string

  FormDataCollection* = object
    data*: FormData
    diagnostics*: seq[FormDataDiagnostic]

  FormParams* = object
    disabled*: bool
    valid*: bool

  FormState* = ref object
    disabled*: bool
    valid*: bool
    submitted*: int
    resetCount*: int
    invalidCount*: int
    fields*: seq[FormFieldRegistration]

  FormHandle* = object
    root* {.cursor.}: UiRoot
    container*: NodeHandle
    state*: FormState

proc submitted*(form: FormHandle): int =
  form.state.submitted

proc resetCount*(form: FormHandle): int =
  form.state.resetCount

proc invalidCount*(form: FormHandle): int =
  form.state.invalidCount

proc disabled*(form: FormHandle): bool =
  form.state.disabled

proc valid*(form: FormHandle): bool =
  form.state.valid

proc initFormFileFieldState*(): FormFileFieldState =
  FormFileFieldState(values: @[])

proc replaceValues*(state: FormFileFieldState; values: openArray[FormFileValue]) =
  if state.isNil:
    raise newException(ValueError, "form file field state is not initialized")
  var replacement = newSeqOfCap[FormFileValue](values.len)
  for value in values:
    if not value.blob.isValid:
      raise newException(ValueError, "form file field Blob value is not initialized")
    replacement.add value
  state.values = move(replacement)

proc values*(state: FormFileFieldState): seq[FormFileValue] =
  if state.isNil:
    return @[]
  result = newSeqOfCap[FormFileValue](state.values.len)
  for value in state.values:
    result.add value

proc len*(state: FormFileFieldState): int {.inline.} =
  if state.isNil: 0 else: state.values.len

proc validateFieldRegistration(
    form: FormHandle;
    node: NodeHandle;
    name: string
) =
  if name.len == 0:
    raise newException(ValueError, "form field name cannot be empty")
  if node.root != form.root:
    raise newException(ValueError, "form field belongs to another UiRoot")
  if not form.container.valid() or not node.valid():
    raise newException(ValueError, "form and field must be active")
  if not form.root.tree.isDescendantOrSelf(node.id, form.container.id):
    raise newException(ValueError, "form field must be a descendant of the form")
  for field in form.state.fields:
    if field.node == node.id:
      raise newException(ValueError, "form field is already registered")

proc registerField*(
    form: FormHandle;
    node: NodeHandle;
    name: string;
    kind = ffText
) =
  if kind == ffFile:
    raise newException(ValueError, "file fields require registerFileField")
  form.validateFieldRegistration(node, name)
  form.state.fields.add FormFieldRegistration(
    node: node.id,
    name: name,
    kind: kind
  )

proc registerFileField*(
    form: FormHandle;
    node: NodeHandle;
    name: string;
    state: FormFileFieldState
) =
  if state.isNil:
    raise newException(ValueError, "form file field state is not initialized")
  form.validateFieldRegistration(node, name)
  form.state.fields.add FormFieldRegistration(
    node: node.id,
    name: name,
    kind: ffFile,
    fileState: state
  )

proc unregisterField*(form: FormHandle; node: NodeHandle): bool {.discardable.} =
  for index in 0 ..< form.state.fields.len:
    if form.state.fields[index].node == node.id:
      form.state.fields.delete(index)
      return true

proc collectData*(form: FormHandle): FormDataCollection =
  var builder = initFormDataBuilder()
  for field in form.state.fields:
    if not form.root.tree.isValid(field.node):
      result.diagnostics.add FormDataDiagnostic(
        kind: fddDisposedField,
        node: field.node,
        name: field.name
      )
      continue

    let node = form.root.tree.nodes[field.node.nodeIndex]
    if esDisabled in node.states:
      continue
    if field.kind == ffFile:
      for value in field.fileState.values:
        builder.addBlob(field.name, value.blob, value.fileName)
      continue
    if field.kind == ffCheckable:
      let checked = node.attrValue("checked")
      if checked.isNone or checked.get != "true":
        continue

    let value = node.attrValue("value")
    if value.isNone:
      result.diagnostics.add FormDataDiagnostic(
        kind: fddMissingValue,
        node: field.node,
        name: field.name
      )
      continue
    builder.addText(field.name, value.get)
  result.data = builder.finish()

proc setDisabled*(form: FormHandle; disabled: bool) =
  form.state.disabled = disabled
  form.container.setState(esDisabled, disabled)

proc setValid*(form: FormHandle; valid: bool) =
  form.state.valid = valid

proc submit*(form: FormHandle): bool =
  if form.state.disabled:
    return false
  if not form.state.valid:
    inc form.state.invalidCount
    discard form.container.emit(iekInvalid)
    return false
  inc form.state.submitted
  discard form.container.emit(iekSubmit)
  true

proc reset*(form: FormHandle): bool =
  if form.state.disabled:
    return false
  inc form.state.resetCount
  discard form.container.emit(iekReset)
  true

proc `onSubmit=`*(form: FormHandle; handler: EventHandler) =
  form.container.onSubmit = handler

proc `onReset=`*(form: FormHandle; handler: EventHandler) =
  form.container.onReset = handler

proc `onInvalid=`*(form: FormHandle; handler: EventHandler) =
  form.container.onInvalid = handler

proc form*(
    root: UiRoot;
    params = FormParams(valid: true);
    style = UiStyle();
    id = "";
    groups: openArray[string] = ["form"]
): FormHandle {.discardable.} =
  result.root = root
  result.state = FormState(
    disabled: params.disabled,
    valid: params.valid,
    fields: @[]
  )
  result.container = root.box(style, id = id, groups = groups)
  result.container.setState(esDisabled, params.disabled)

proc form*(
    root: UiRoot;
    valid = true;
    disabled = false;
    style = UiStyle();
    id = "";
    groups: openArray[string] = ["form"]
): FormHandle {.discardable.} =
  root.form(FormParams(disabled: disabled, valid: valid), style = style, id = id, groups = groups)
